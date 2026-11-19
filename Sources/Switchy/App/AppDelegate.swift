import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var hotkeys: HotkeyController?
    private var windowLayouts: WindowLayoutController?
    private let clipboard = ClipboardController()
    private var permissionTimer: Timer?
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        statusBar?.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        if Permissions.allGranted {
            permissionsGranted()
        } else {
            if !Permissions.accessibility { Permissions.requestAccessibility() }
            if !Permissions.inputMonitoring { Permissions.requestInputMonitoring() }
            startPermissionPolling()
        }
        statusBar?.refresh()
    }

    /// Повторный запуск уже работающего Switchy (двойной клик в Finder) — открываем настройки.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    /// Пока прав нет — раз в 2 секунды проверяем, не выдал ли их пользователь.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusBar?.refresh()
                if Permissions.allGranted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.permissionsGranted()
                }
            }
        }
    }

    private func permissionsGranted() {
        clipboard.start()

        let controller = HotkeyController()
        controller.onClipboardHistory = { [weak self] in self?.clipboard.togglePanel() }
        if controller.start() {
            hotkeys = controller
        }
        let windows = WindowLayoutController()
        windows.start()
        windowLayouts = windows
    }
}
