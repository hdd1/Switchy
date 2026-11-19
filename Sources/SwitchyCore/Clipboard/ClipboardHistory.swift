import Foundation

/// Элемент истории буфера обмена (только текст).
public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let date: Date
    /// Приложение, из которого скопировано (bundle id) — для иконки в панели.
    public let sourceBundleID: String?

    public init(id: UUID = UUID(), text: String, date: Date = Date(), sourceBundleID: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.sourceBundleID = sourceBundleID
    }

    /// Первая непустая строка без лишних пробелов, обрезанная до `maxLength`.
    public func preview(maxLength: Int = 90) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? text
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    /// Сколько строк в тексте (для подсказки «+ ещё N строк»).
    public var lineCount: Int {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}

/// История буфера обмена: новые сверху, без дубликатов, ограниченного размера.
public struct ClipboardHistory: Codable, Sendable {
    public private(set) var items: [ClipboardItem] = []

    public init(items: [ClipboardItem] = []) {
        self.items = items
    }

    /// Добавляет текст наверх. Повторно скопированное поднимается наверх, а не дублируется.
    /// Возвращает `false`, если текст пустой (из одних пробелов).
    @discardableResult
    public mutating func add(_ text: String, source: String? = nil, date: Date = Date(), capacity: Int) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(text: text, date: date, sourceBundleID: source), at: 0)
        trim(to: capacity)
        return true
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func clear() {
        items.removeAll()
    }

    public mutating func trim(to capacity: Int) {
        if items.count > max(capacity, 1) {
            items.removeLast(items.count - max(capacity, 1))
        }
    }

    /// Поиск без учёта регистра; пустой запрос — все элементы.
    public func filtered(_ query: String) -> [ClipboardItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
