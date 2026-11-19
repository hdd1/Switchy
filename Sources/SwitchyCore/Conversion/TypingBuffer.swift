import Foundation

/// Что переводить из набранного.
public enum FragmentMode: String, Codable, Sendable, CaseIterable {
    /// Последнее слово (вместе с пробелами после него).
    case lastWord
    /// Всё, что набрано с последнего сброса.
    case all
}

/// Буфер набора: физические нажатия, которые пользователь сделал в текущем поле с последнего сброса.
/// Отражает текст «справа от курсора назад»: всё, что в нём есть, сейчас стоит в поле перед курсором.
public struct TypingBuffer: Sendable {
    public static let backspaceKeyCode: UInt16 = 51
    public static let spaceKeyCode: UInt16 = 49
    /// Ограничение длины — набор длиннее нескольких строк переводить уже бессмысленно.
    public static let maxLength = 500

    public enum Outcome: Equatable, Sendable {
        case appended, removed, reset
    }

    public private(set) var strokes: [KeyStroke] = []

    public init() {}

    public var isEmpty: Bool { strokes.isEmpty }

    /// Обрабатывает нажатие клавиши (уже прошедшее мимо хоткеев).
    @discardableResult
    public mutating func handleKeyDown(keyCode: UInt16, modifiers: Modifiers, capsLock: Bool) -> Outcome {
        // Сочетания с ⌘/⌃/⌥ — это команды или спецсимволы, а не набор текста.
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            reset()
            return .reset
        }
        if keyCode == Self.backspaceKeyCode {
            if !strokes.isEmpty { strokes.removeLast() }
            return .removed
        }
        guard KeyboardLayout.printableKeyCodes.contains(keyCode) else {
            // Enter, Tab, Esc, стрелки, F-клавиши, Home/End… — курсор ушёл или ввод завершён.
            reset()
            return .reset
        }
        strokes.append(KeyStroke(keyCode: keyCode, shift: modifiers.contains(.shift), capsLock: capsLock))
        if strokes.count > Self.maxLength {
            strokes.removeFirst(strokes.count - Self.maxLength)
        }
        return .appended
    }

    public mutating func reset() {
        strokes.removeAll(keepingCapacity: true)
    }

    /// Фрагмент для перевода: всё или последнее слово с хвостовыми пробелами.
    public func fragment(_ mode: FragmentMode) -> [KeyStroke] {
        switch mode {
        case .all:
            return strokes
        case .lastWord:
            var end = strokes.count
            while end > 0, strokes[end - 1].keyCode == Self.spaceKeyCode { end -= 1 }
            var start = end
            while start > 0, strokes[start - 1].keyCode != Self.spaceKeyCode { start -= 1 }
            return Array(strokes[start...])
        }
    }
}

/// Порядок раскладок в серии нажатий хоткея перевода.
public enum ConversionOrder {
    /// По кругу начиная со следующей после исходной; исходная — последней.
    /// Если задан `first` (выбор умного режима или прямой хоткей) — он идёт первым.
    ///
    /// Круг EN → RU → UA, исходная EN: `[RU, UA, EN]`; с first = UA: `[UA, RU, EN]`.
    public static func sequence(cycle: [String], original: String, first: String? = nil) -> [String] {
        var others: [String]
        if let index = cycle.firstIndex(of: original) {
            others = Array(cycle[(index + 1)...]) + Array(cycle[..<index])
        } else {
            others = cycle
        }
        if let first, first != original {
            others.removeAll { $0 == first }
            others.insert(first, at: 0)
        }
        return others + [original]
    }
}
