import AppKit

/// Временное использование буфера обмена (копировать выделение / вставить результат)
/// с последующим восстановлением исходного содержимого.
@MainActor
enum ClipboardIO {
    /// Служебная метка записей Switchy — история буфера (этап 7) их пропускает.
    static let internalType = NSPasteboard.PasteboardType("app.switchy.internal")
    /// Общепринятая метка «временное содержимое, не сохранять в историю» (nspasteboard.org).
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    static func snapshot() -> Snapshot {
        let items = NSPasteboard.general.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        return Snapshot(items: items)
    }

    static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let items = snapshot.items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            item.setData(Data(), forType: internalType)
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// Копирует выделение через ⌘C и возвращает буфер обмена как было.
    static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot()
        let before = pasteboard.changeCount

        EventPoster.postKey(keyC, flags: .maskCommand)
        for _ in 0..<20 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else { return nil }

        let text = pasteboard.string(forType: .string)
        restore(saved)
        return text
    }

    /// Вставляет текст через ⌘V и возвращает буфер обмена как было.
    static func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = snapshot()

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: internalType)
        item.setData(Data(), forType: transientType)
        pasteboard.writeObjects([item])

        EventPoster.postKey(keyV, flags: .maskCommand)
        // Приложению нужно время забрать содержимое, прежде чем мы его подменим обратно.
        try? await Task.sleep(for: .milliseconds(300))
        restore(saved)
    }
}
