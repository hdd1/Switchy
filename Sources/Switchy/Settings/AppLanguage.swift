import AppKit

/// Язык интерфейса Switchy. macOS берёт переводы при запуске, поэтому смена применяется после перезапуска.
@MainActor
enum AppLanguage {
    /// Доступные языки: код → самоназвание (не переводится).
    static let options: [(code: String, name: String)] = [
        ("en", "English"),
        ("ru", "Русский"), // l10n-ignore
        ("uk", "Українська"), // l10n-ignore
    ]

    /// Выбранный в Switchy язык; пустая строка — как в системе.
    static var selected: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        return (domain?["AppleLanguages"] as? [String])?.first ?? ""
    }

    static func select(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    /// Перезапуск: новый экземпляр стартует, когда этот уже завершится.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
