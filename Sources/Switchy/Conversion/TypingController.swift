import AppKit
import Carbon
import SwitchyCore

/// Перевод текста: набранного (буфер набора) и выделенного, серия нажатий, прямые хоткеи раскладок.
///
/// Серия нажатий хоткея перевода:
/// - 1-е нажатие в умном режиме — перевод по словам (только слова, набранные не в той раскладке);
///   если таких слов нет — умный выбор раскладки для всего фрагмента;
/// - 2-е и дальше — весь фрагмент по кругу, исходная раскладка последней.
@MainActor
final class TypingController {
    private var settings: AppSettings { SettingsStore.shared.settings }

    private var buffer = TypingBuffer()
    private var session: Session?
    private var layouts: [String: KeyboardLayout] = [:]
    private let detector = SmartDetector()
    /// Раскладка, которую последней включили мы сами. Уведомления о ней (они приходят с задержкой,
    /// иногда по нескольку) не считаются ручной сменой раскладки. Забывается, когда раскладка
    /// сменилась на другую не нами.
    private var ownLayout: String?
    /// Цепочка отложенных действий: следующее начинается только после предыдущего.
    private var pendingWork: Task<Void, Never>?
    /// Идёт чтение выделения — повторные нажатия игнорируем.
    private var readingSelection = false

    /// Серия нажатий над одним и тем же фрагментом.
    private struct Session {
        /// Фрагмент: нажатия (набранное) или символы выделенного текста в исходной раскладке.
        let tokens: [TextToken]
        /// Раскладка, в которой фрагмент был набран.
        let original: String
        /// Порядок раскладок для перевода целиком (исходная — последней).
        let sequence: [String]
        /// Шаг в `sequence`, который сейчас в поле; -1 — умный перевод по словам.
        var step: Int
        /// Текст, который сейчас стоит в поле (его стираем на следующем шаге).
        var currentText: String
    }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    // MARK: - События ввода

    /// Нажатие клавиши, прошедшее мимо хоткеев (дошедшее до приложения).
    func keyDown(keyCode: UInt16, modifiers: Modifiers, capsLock: Bool) {
        if SettingsStore.shared.frontmostAppExcludedFromConversion {
            reset()
            return
        }
        if session != nil {
            // Пользователь продолжил печатать после перевода — переведённое считаем принятым
            // и начинаем фрагмент заново.
            session = nil
            buffer.reset()
        }
        buffer.handleKeyDown(
            keyCode: keyCode, modifiers: modifiers, capsLock: capsLock,
            at: ProcessInfo.processInfo.systemUptime, idleReset: settings.idleResetSeconds
        )
    }

    func reset() {
        buffer.reset()
        session = nil
    }

    private func inputSourceChanged() {
        let current = InputSources.current()?.id
        if let current, current == ownLayout { return }
        // Раскладку сменили не мы — набранное дальше будет в другой раскладке.
        ownLayout = nil
        reset()
    }

    // MARK: - Хоткей перевода

    /// Есть набранное — переводим его; нет — выделение. Повторные нажатия — следующий шаг серии.
    func convert() {
        guard !SettingsStore.shared.frontmostAppExcludedFromConversion else { return }
        if session != nil {
            nextStep()
            return
        }

        guard let original = InputSources.current()?.id else { return }
        let strokes = buffer.fragment(settings.fragmentMode)
        guard !strokes.isEmpty else {
            convertSelection()
            return
        }

        let tokens = strokes.map(TextToken.key)
        guard let start = firstStep(tokens: tokens, original: original),
              let oldText = render(tokens, in: original) else { return }
        session = start.session
        replace(oldText: oldText, with: start.session.currentText, switchTo: start.layout)
    }

    /// Следующий шаг серии: весь фрагмент в следующую раскладку по кругу
    /// (шаги, которые не меняют текст в поле, пропускаем).
    private func nextStep() {
        guard var current = session, !current.sequence.isEmpty else { return }
        let oldText = current.currentText
        for _ in current.sequence.indices {
            current.step = (current.step + 1) % current.sequence.count
            let target = current.sequence[current.step]
            guard let newText = render(current.tokens, in: target) else { continue }
            if newText == oldText { continue }
            current.currentText = newText
            session = current
            replace(oldText: oldText, with: newText, switchTo: target)
            return
        }
    }

    /// Первый шаг серии: умный перевод по словам, иначе умный выбор / следующая по кругу для всего фрагмента.
    private func firstStep(tokens: [TextToken], original: String) -> (session: Session, layout: String)? {
        let cycle = cycleIDs()

        if settings.smartMode, let fix = wordFix(tokens, original: original, cycle: cycle) {
            if let uniform = fix.uniformTarget {
                let sequence = ConversionOrder.sequence(cycle: cycle, original: original, first: uniform)
                return (Session(tokens: tokens, original: original, sequence: sequence, step: 0, currentText: fix.text),
                        uniform)
            }
            let sequence = ConversionOrder.sequence(cycle: cycle, original: original, first: fix.dominantTarget)
            return (Session(tokens: tokens, original: original, sequence: sequence, step: -1, currentText: fix.text),
                    fix.finalLayout)
        }

        let smartPick = settings.smartMode ? smartChoice(tokens, original: original, cycle: cycle) : nil
        let sequence = ConversionOrder.sequence(cycle: cycle, original: original, first: smartPick)
        guard let newText = render(tokens, in: sequence[0]) else { return nil }
        return (Session(tokens: tokens, original: original, sequence: sequence, step: 0, currentText: newText),
                sequence[0])
    }

    // MARK: - Прямые хоткеи

    /// Прямой хоткей раскладки: включить её и (по настройке) перевести в неё набранное целиком.
    /// Выделение прямые хоткеи не трогают (кроме продолжения уже начатой серии).
    func selectLayout(id target: String) {
        guard let currentID = InputSources.current()?.id, currentID != target else { return }
        // Перевод выключен (или приложение в исключениях) — только переключаем раскладку.
        // Набранное сбрасываем, как при ручной смене раскладки: дальше текст пойдёт в другой раскладке.
        guard settings.directHotkeysConvert, !SettingsStore.shared.frontmostAppExcludedFromConversion else {
            reset()
            switchLayout(to: target)
            return
        }

        let tokens: [TextToken]
        let original: String
        let oldText: String
        if let session {
            tokens = session.tokens
            original = session.original
            oldText = session.currentText
        } else {
            let strokes = buffer.fragment(settings.fragmentMode)
            guard !strokes.isEmpty, let rendered = render(strokes.map(TextToken.key), in: currentID) else {
                switchLayout(to: target)
                return
            }
            tokens = strokes.map(TextToken.key)
            original = currentID
            oldText = rendered
        }
        guard let newText = render(tokens, in: target) else { return }
        let sequence = ConversionOrder.sequence(cycle: cycleIDs(), original: original, first: target)
        session = Session(tokens: tokens, original: original, sequence: sequence, step: 0, currentText: newText)
        replace(oldText: oldText, with: newText, switchTo: target)
    }

    // MARK: - Выделение

    private func convertSelection() {
        guard !readingSelection else { return }
        readingSelection = true

        enqueueAfterModifiersReleased { [weak self] in
            guard let self else { return }
            defer { self.readingSelection = false }

            let text: String
            switch SelectionReader.read() {
            case let .text(selected):
                text = selected
            case .empty:
                return
            case .unavailable:
                guard let copied = await ClipboardIO.copySelection(), !copied.isEmpty else { return }
                text = copied
            }

            let candidates = self.cycleIDs().compactMap(self.layout)
            guard let source = LayoutDetector.sourceLayout(
                of: text, among: candidates, preferred: InputSources.current()?.id
            ) else { return }

            let tokens = source.tokens(for: text)
            guard let start = self.firstStep(tokens: tokens, original: source.source.id),
                  start.session.currentText != text else { return }

            // Ввод поверх выделения заменяет его.
            await Self.insert(start.session.currentText)
            self.session = start.session
            self.switchLayout(to: start.layout)
        }
    }

    // MARK: - Внутреннее

    private func render(_ tokens: [TextToken], in layoutID: String) -> String? {
        layout(layoutID)?.render(tokens)
    }

    /// Стирает `oldText`, вводит `newText` и включает раскладку.
    private func replace(oldText: String, with newText: String, switchTo layoutID: String) {
        enqueueAfterModifiersReleased { [weak self] in
            if oldText != newText {
                EventPoster.backspace(count: oldText.count)
                await Self.insert(newText)
            }
            self?.switchLayout(to: layoutID)
        }
    }

    /// Короткий однострочный текст — печатаем; многострочный или длинный — вставляем через буфер обмена.
    private static func insert(_ text: String) async {
        if text.count <= 300, !text.contains(where: \.isNewline) {
            EventPoster.type(text)
        } else {
            await ClipboardIO.paste(text)
        }
    }

    private func switchLayout(to id: String) {
        guard InputSources.current()?.id != id else { return }
        ownLayout = id
        if !InputSources.select(id: id) {
            ownLayout = nil
            NSLog("Switchy: раскладка \(id) не найдена среди включённых")
            NSSound.beep()
        }
    }

    /// Выполняет действие, когда пользователь отпустит модификаторы (⌥ тапа, ⌃⌥ прямого хоткея),
    /// иначе приложение может принять наш Backspace за ⌥⌫ «удалить слово».
    private func enqueueAfterModifiersReleased(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingWork
        pendingWork = Task { @MainActor in
            await previous?.value
            try? await Task.sleep(for: .milliseconds(15))
            for _ in 0..<50 {
                if Modifiers(cgFlags: CGEventSource.flagsState(.hidSystemState)).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            await work()
        }
    }

    /// Умный перевод по словам (`nil` — ни одно слово не выглядит набранным не в той раскладке).
    private func wordFix(_ tokens: [TextToken], original: String, cycle: [String]) -> WordFixer.Result? {
        guard let originalLayout = layout(original) else { return nil }
        let alternatives = cycle.filter { $0 != original }.compactMap(layout)
        return WordFixer().fix(tokens, original: originalLayout, alternatives: alternatives)
    }

    /// Умный выбор раскладки для всего фрагмента.
    private func smartChoice(_ tokens: [TextToken], original: String, cycle: [String]) -> String? {
        let candidates = cycle.filter { $0 != original }.compactMap { id -> SmartDetector.Candidate? in
            guard let layout = layout(id) else { return nil }
            return SmartDetector.Candidate(layoutID: id, language: layout.source.language ?? "", text: layout.render(tokens))
        }
        return detector.pick(candidates)
    }

    /// Порядок круга из настроек (только включённые в системе раскладки).
    private func cycleIDs() -> [String] {
        SettingsStore.shared.cycle
    }

    private func layout(_ id: String) -> KeyboardLayout? {
        if let cached = layouts[id] { return cached }
        let loaded = KeyboardLayout(id: id)
        layouts[id] = loaded
        return loaded
    }
}
