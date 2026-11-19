import AppKit
import Combine
import SwitchyCore

/// Хранилище настроек: UserDefaults (JSON) + уведомление подписчиков об изменениях.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private static let defaultsKey = "settings.v1"

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            observers.forEach { $0(settings) }
        }
    }

    /// Идёт запись хоткея в окне настроек — движок хоткеев на это время молчит.
    @Published var isRecordingHotkey = false

    /// Пауза: Switchy временно ничего не делает (не сохраняется между запусками).
    @Published var isPaused = false

    /// Активное приложение в списке исключений перевода.
    var frontmostAppExcludedFromConversion: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settings.excludedConversionApps.contains(id)
    }

    private var observers: [(AppSettings) -> Void] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings.defaults(enabledLayouts: InputSources.enabled().map(\.id))
        }
    }

    /// Подписка на изменения; обработчик сразу вызывается с текущими настройками.
    func observe(_ handler: @escaping (AppSettings) -> Void) {
        observers.append(handler)
        handler(settings)
    }

    /// Включённые раскладки в порядке круга.
    var cycle: [String] {
        settings.cycle(enabled: InputSources.enabled().map(\.id))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
