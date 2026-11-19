import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var hotkeys: HotkeyController?
    private var windowLayouts: WindowLayoutController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()

        if Permissions.allGranted {
            permissionsGranted()
        } else {
            if !Permissions.accessibility { Permissions.requestAccessibility() }
            if !Permissions.inputMonitoring { Permissions.requestInputMonitoring() }
            startPermissionPolling()
        }
        statusBar?.refresh()
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
        let controller = HotkeyController()
        if controller.start() {
            hotkeys = controller
        }
        let windows = WindowLayoutController()
        windows.start()
        windowLayouts = windows
    }
}
