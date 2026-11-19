import ServiceManagement

/// Запуск при входе в систему через SMAppService.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Switchy: не удалось изменить автозапуск: \(error.localizedDescription)")
        }
    }
}
