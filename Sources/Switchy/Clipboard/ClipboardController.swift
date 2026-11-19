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
        guard SettingsStore.shared.settings.clipboardEnabled else { return }
        panel.toggle()
    }
}
