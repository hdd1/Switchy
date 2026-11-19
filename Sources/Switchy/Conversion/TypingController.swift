import AppKit
import Carbon
import SwitchyCore

/// Перевод текста: набранного (буфер набора) и выделенного, серия нажатий, прямые хоткеи раскладок.
@MainActor
final class TypingController {
    private var settings: AppSettings { SettingsStore.shared.settings }

    private var buffer = TypingBuffer()
    private var session: Session?
    private var layouts: [String: KeyboardLayout] = [:]
    private let detector = SmartDetector()
    /// Раскладка, которую включили мы сами, — её уведомление о смене не сбрасывает буфер.
    private var ownSwitchTarget: String?
    /// Цепочка отложенных действий: следующее начинается только после предыдущего.
    private var pendingWork: Task<Void, Never>?
    /// Идёт чтение выделения — повторные нажатия игнорируем.
    private var readingSelection = false

    /// Серия нажатий хоткея перевода над одним и тем же фрагментом.
    private struct Session {
        enum Content {
            /// Набранное: физические нажатия.
            case typed([KeyStroke])
            /// Выделенное: готовый текст и раскладка, в которой он набран.
            case selection(text: String, source: String)
        }
        let content: Content
        /// Раскладка, в которой фрагмент был набран.
        let original: String
        /// Порядок раскладок серии (исходная — последней).
        let sequence: [String]
        /// Индекс текущей раскладки в `sequence`.
        var index: Int
        var current: String { sequence[index] }
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
        if session != nil {
            // Пользователь продолжил печатать после перевода — переведённое считаем принятым
            // и начинаем фрагмент заново.
            session = nil
            buffer.reset()
        }
        buffer.handleKeyDown(keyCode: keyCode, modifiers: modifiers, capsLock: capsLock)
    }

    func reset() {
        buffer.reset()
        session = nil
    }

    private func inputSourceChanged() {
        let current = InputSources.current()?.id
        if let target = ownSwitchTarget, current == target {
            ownSwitchTarget = nil
            return
        }
        // Раскладку сменили не мы — набранное дальше будет в другой раскладке.
        reset()
    }

    // MARK: - Действия

    /// Хоткей перевода: первое нажатие — умный выбор (или следующая по кругу), дальше — по кругу.
    /// Есть набранное — переводим его; нет — переводим выделение.
    func convert() {
        if var current = session {
            let from = current.current
            current.index = (current.index + 1) % current.sequence.count
            session = current
            apply(current.content, from: from, to: current.current)
            return
        }

        guard let original = InputSources.current()?.id else { return }
        let strokes = buffer.fragment(settings.fragmentMode)
        guard !strokes.isEmpty else {
            convertSelection()
            return
        }

        let cycle = cycleIDs()
        let content = Session.Content.typed(strokes)
        let smartPick = settings.smartMode ? smartChoice(content, original: original, cycle: cycle) : nil
        let sequence = ConversionOrder.sequence(cycle: cycle, original: original, first: smartPick)
        session = Session(content: content, original: original, sequence: sequence, index: 0)
        apply(content, from: original, to: sequence[0])
    }

    /// Прямой хоткей раскладки: включить её и (по настройке) перевести в неё набранное.
    /// Выделение прямые хоткеи не трогают (кроме продолжения уже начатой серии).
    func selectLayout(id target: String) {
        guard let currentID = InputSources.current()?.id, currentID != target else { return }

        let content: Session.Content
        if let session {
            content = session.content
        } else {
            let strokes = buffer.fragment(settings.fragmentMode)
            guard settings.directHotkeysConvert, !strokes.isEmpty else {
                switchLayout(to: target)
                return
            }
            content = .typed(strokes)
        }
        let original = session?.original ?? currentID
        let from = session?.current ?? currentID
        let sequence = ConversionOrder.sequence(cycle: cycleIDs(), original: original, first: target)
        session = Session(content: content, original: original, sequence: sequence, index: 0)
        apply(content, from: from, to: target)
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

            let cycle = self.cycleIDs()
            let candidates = cycle.compactMap(self.layout)
            guard let source = LayoutDetector.sourceLayout(
                of: text, among: candidates, preferred: InputSources.current()?.id
            ) else { return }

            let content = Session.Content.selection(text: text, source: source.source.id)
            let smartPick = self.settings.smartMode
                ? self.smartChoice(content, original: source.source.id, cycle: cycle) : nil
            let sequence = ConversionOrder.sequence(cycle: cycle, original: source.source.id, first: smartPick)
            guard let newText = self.render(content, in: sequence[0]), newText != text else { return }

            // Ввод поверх выделения заменяет его.
            await Self.insert(newText)
            self.session = Session(content: content, original: source.source.id, sequence: sequence, index: 0)
            self.switchLayout(to: sequence[0])
        }
    }

    // MARK: - Внутреннее

    private func render(_ content: Session.Content, in layoutID: String) -> String? {
        guard let target = layout(layoutID) else { return nil }
        switch content {
        case let .typed(strokes):
            return target.render(strokes)
        case let .selection(text, sourceID):
            guard let source = layout(sourceID) else { return nil }
            return LayoutConverter.convert(text, from: source, to: target)
        }
    }

    /// Стирает фрагмент, как он выглядит в `from`, вводит его в виде `to` и включает `to`.
    private func apply(_ content: Session.Content, from: String, to: String) {
        guard from != to, let oldText = render(content, in: from), let newText = render(content, in: to) else {
            if from != to { switchLayout(to: to) }
            return
        }
        enqueueAfterModifiersReleased { [weak self] in
            EventPoster.backspace(count: oldText.count)
            await Self.insert(newText)
            self?.switchLayout(to: to)
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
        ownSwitchTarget = id
        if !InputSources.select(id: id) {
            ownSwitchTarget = nil
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

    private func smartChoice(_ content: Session.Content, original: String, cycle: [String]) -> String? {
        let candidates = cycle.filter { $0 != original }.compactMap { id -> SmartDetector.Candidate? in
            guard let layout = layout(id), let text = render(content, in: id) else { return nil }
            return SmartDetector.Candidate(layoutID: id, language: layout.source.language ?? "", text: text)
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
