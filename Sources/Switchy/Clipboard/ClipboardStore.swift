import AppKit
import Combine
import SwitchyCore

/// История буфера обмена + хранение на диске
/// (`~/Library/Application Support/Switchy/history.json`, доступ только владельцу).
@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var history = ClipboardHistory()

    private let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Switchy", isDirectory: true).appendingPathComponent("history.json")
    }()

    private var settings: AppSettings { SettingsStore.shared.settings }

    private init() {
        if settings.clipboardPersist { load() }
    }

    func add(_ text: String, source: String?) {
        guard history.add(text, source: source, capacity: settings.clipboardCapacity) else { return }
        save()
    }

    func remove(id: UUID) {
        history.remove(id: id)
        save()
    }

    func clear() {
        history.clear()
        save()
    }

    /// Применить изменившиеся настройки (размер, хранение на диске).
    func apply(_ settings: AppSettings) {
        history.trim(to: settings.clipboardCapacity)
        save()
    }

    // MARK: - Диск

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else { return }
        history = decoded
        history.trim(to: settings.clipboardCapacity)
    }

    private func save() {
        let fm = FileManager.default
        guard settings.clipboardPersist else {
            try? fm.removeItem(at: fileURL)
            return
        }
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("Switchy: не удалось сохранить историю буфера: \(error.localizedDescription)")
        }
    }
}
