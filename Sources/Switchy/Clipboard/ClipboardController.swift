import AppKit
import SwitchyCore

/// История буфера обмена: монитор, хранилище, панель. Включается/выключается настройками.
@MainActor
final class ClipboardController {
    private let monitor = ClipboardMonitor()
    private let store = ClipboardStore.shared
    let panel = ClipboardPanelController()

    func start() {
        monitor.onText = { [weak self] text, source in
            let settings = SettingsStore.shared
            if settings.isPaused { return }
            if let source, settings.settings.excludedClipboardApps.contains(source) { return }
            self?.store.add(text, source: source)
        }
        SettingsStore.shared.observe { [weak self] settings in
            guard let self else { return }
            if settings.clipboardEnabled {
                self.monitor.start()
            } else {
                self.monitor.stop()
                self.panel.close()
            }
            self.store.apply(settings)
        }
    }

    func togglePanel() {
        guard SettingsStore.shared.settings.clipboardEnabled, !SettingsStore.shared.isPaused else { return }
        panel.toggle()
    }
}
