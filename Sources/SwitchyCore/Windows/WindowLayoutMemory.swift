import Foundation

/// Ключ окна: процесс + идентификатор окна (или «всё приложение», если окно не определить).
public struct WindowKey: Hashable, Sendable, CustomStringConvertible {
    public let pid: Int32
    public let windowID: UInt32?

    public init(pid: Int32, windowID: UInt32?) {
        self.pid = pid
        self.windowID = windowID
    }

    public var description: String { "\(pid):\(windowID.map(String.init) ?? "app")" }
}

/// Что делать с окном, для которого раскладка ещё не запоминалась.
public enum NewWindowPolicy: String, Codable, Sendable, CaseIterable {
    /// Оставить текущую раскладку (и запомнить её для окна).
    case keepCurrent
    /// Включить конкретную раскладку.
    case fixed
}

/// Память «окно → раскладка». Чистая логика, без системных вызовов.
public struct WindowLayoutMemory: Sendable {
    private var entries: [WindowKey: String] = [:]
    /// Порядок использования — для ограничения размера.
    private var order: [WindowKey] = []
    public var capacity = 500

    public init() {}

    public var count: Int { entries.count }

    public func layout(for key: WindowKey) -> String? { entries[key] }

    public mutating func record(_ layoutID: String, for key: WindowKey) {
        entries[key] = layoutID
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > capacity {
            let dropped = order.removeFirst()
            entries[dropped] = nil
        }
    }

    /// Забыть все окна процесса (приложение завершилось).
    public mutating func forget(pid: Int32) {
        entries = entries.filter { $0.key.pid != pid }
        order.removeAll { $0.pid == pid }
    }

    /// Какую раскладку включить при фокусе окна (`nil` — ничего не менять).
    /// Для нового окна при `keepCurrent` запоминает текущую.
    public mutating func layoutToRestore(
        for key: WindowKey,
        current: String,
        policy: NewWindowPolicy,
        fixedLayout: String?
    ) -> String? {
        if let saved = entries[key] {
            return saved == current ? nil : saved
        }
        switch policy {
        case .keepCurrent:
            record(current, for: key)
            return nil
        case .fixed:
            guard let fixedLayout else { return nil }
            record(fixedLayout, for: key)
            return fixedLayout == current ? nil : fixedLayout
        }
    }
}
