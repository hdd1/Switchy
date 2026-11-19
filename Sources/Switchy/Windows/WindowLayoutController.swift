import AppKit
import Carbon
import SwitchyCore

/// Память раскладки по окнам: запоминаем при любой смене раскладки, восстанавливаем при фокусе окна.
@MainActor
final class WindowLayoutController {
    private var settings: AppSettings { SettingsStore.shared.settings }

    private let tracker = FocusTracker()
    private var memory = WindowLayoutMemory()
    /// Сразу после смены фокуса уведомления о смене раскладки не записываем: это либо наше
    /// восстановление, либо системное переключение, а не выбор пользователя.
    private var ignoreChangesUntil: TimeInterval = 0
    private static let settleInterval: TimeInterval = 0.3

    func start() {
        tracker.onFocusChange = { [weak self] key in self?.focusChanged(to: key) }
        tracker.onAppTerminated = { [weak self] pid in self?.memory.forget(pid: pid) }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        }
        tracker.start()
    }

    /// Системная опция «Автоматически переключаться на источник ввода документа» — конфликтует с нами.
    static var systemPerDocumentSwitchingEnabled: Bool {
        let props = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .dictionary(forKey: "AppleGlobalTextInputProperties")
        return (props?["TextInputGlobalPropertyPerContextInput"] as? Bool) ?? false
    }

    private func focusChanged(to key: WindowKey) {
        guard settings.windowMemoryEnabled, let current = InputSources.current()?.id else { return }
        ignoreChangesUntil = ProcessInfo.processInfo.systemUptime + Self.settleInterval

        if let target = memory.layoutToRestore(
            for: key, current: current,
            policy: settings.newWindowPolicy,
            fixedLayout: settings.newWindowLayout ?? SettingsStore.shared.cycle.first
        ) {
            InputSources.select(id: target)
        }

        // Система (опция «источник ввода документа») может переключить раскладку чуть позже нас —
        // после паузы проверяем и возвращаем запомненную.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleInterval + 0.05))
            guard let self, self.tracker.currentKey == key,
                  let saved = self.memory.layout(for: key),
                  InputSources.current()?.id != saved
            else { return }
            self.ignoreChangesUntil = ProcessInfo.processInfo.systemUptime + 0.2
            InputSources.select(id: saved)
        }
    }

    private func inputSourceChanged() {
        guard settings.windowMemoryEnabled,
              ProcessInfo.processInfo.systemUptime >= ignoreChangesUntil,
              let key = tracker.currentKey,
              let current = InputSources.current()?.id
        else { return }
        memory.record(current, for: key)
    }
}
