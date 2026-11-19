import AppKit
import Carbon
import SwitchyCore

/// Иконка Switchy в строке меню (код текущей раскладки) и её меню.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    /// Открыть окно настроек.
    var onOpenSettings: (() -> Void)?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        item.menu = menu
        observeInputSourceChanges()
        refresh()
    }

    /// Обновляет заголовок: код текущей раскладки, ⚠︎ — если не хватает прав.
    func refresh() {
        guard let button = item.button else { return }
        let code = InputSources.current()?.shortCode ?? "??"
        button.title = Permissions.allGranted ? code : "\(code)⚠︎"
        button.toolTip = Permissions.allGranted ? "Switchy" : "Switchy: нужны права доступа"
    }

    /// Система рассылает уведомление при любой смене раскладки (вручную, хоткеем, программно).
    private func observeInputSourceChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let header = NSMenuItem(title: "Switchy \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Раскладки: текущая отмечена галочкой, клик — переключить.
        let currentID = InputSources.current()?.id
        for source in InputSources.enabled() {
            let entry = NSMenuItem(
                title: "\(source.shortCode)  \(source.name)",
                action: #selector(selectSource(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = source.id
            entry.state = source.id == currentID ? .on : .off
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        addPermissionItem(
            title: "Универсальный доступ",
            granted: Permissions.accessibility,
            action: #selector(openAccessibility)
        )
        addPermissionItem(
            title: "Мониторинг ввода",
            granted: Permissions.inputMonitoring,
            action: #selector(openInputMonitoring)
        )

        if WindowLayoutController.systemPerDocumentSwitchingEnabled {
            let warn = NSMenuItem(
                title: "⚠️ Выключите системную «память раскладки документа»…",
                action: #selector(openKeyboardSettings), keyEquivalent: ""
            )
            warn.target = self
            warn.toolTip = "Клавиатура → Источники ввода → Изменить… → «Автоматически переключаться на источник ввода документа». Switchy запоминает раскладку окон сам."
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addPermissionItem(title: String, granted: Bool, action: Selector) {
        let mark = granted ? "✅" : "⚠️"
        let suffix = granted ? "" : " — открыть настройки…"
        let item = NSMenuItem(title: "\(mark) \(title)\(suffix)", action: granted ? nil : action, keyEquivalent: "")
        item.target = self
        item.isEnabled = !granted
        menu.addItem(item)
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        InputSources.select(id: id)
    }

    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openInputMonitoring() { Permissions.openInputMonitoringSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
