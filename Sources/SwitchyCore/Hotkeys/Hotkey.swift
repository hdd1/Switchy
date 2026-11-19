import Foundation

/// Модификаторы без учёта стороны — для сочетаний вроде Ctrl+Option+Space.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    /// Символы в порядке, принятом в macOS: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// Конкретная клавиша-модификатор с учётом стороны — для тапов (тап правого Option и т. п.).
public enum ModifierKey: String, Codable, Hashable, Sendable, CaseIterable {
    case leftOption, rightOption, leftCommand, rightCommand
    case leftShift, rightShift, leftControl, rightControl

    public var keyCode: UInt16 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    /// Бит конкретной клавиши в «аппаратных» флагах события (NX_DEVICE*KEYMASK).
    public var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0000_0001
        case .leftShift: 0x0000_0002
        case .rightShift: 0x0000_0004
        case .leftCommand: 0x0000_0008
        case .rightCommand: 0x0000_0010
        case .leftOption: 0x0000_0020
        case .rightOption: 0x0000_0040
        case .rightControl: 0x0000_2000
        }
    }

    public var modifier: Modifiers {
        switch self {
        case .leftOption, .rightOption: .option
        case .leftCommand, .rightCommand: .command
        case .leftShift, .rightShift: .shift
        case .leftControl, .rightControl: .control
        }
    }

    public var displayName: String {
        switch self {
        case .leftOption: "левый ⌥"
        case .rightOption: "правый ⌥"
        case .leftCommand: "левый ⌘"
        case .rightCommand: "правый ⌘"
        case .leftShift: "левый ⇧"
        case .rightShift: "правый ⇧"
        case .leftControl: "левый ⌃"
        case .rightControl: "правый ⌃"
        }
    }
}

/// Хоткей Switchy.
public enum Hotkey: Codable, Hashable, Sendable {
    /// Нажать и отпустить модификатор, ничего не нажимая между этим.
    case modifierTap(ModifierKey)
    /// Два быстрых тапа одного модификатора.
    case modifierDoubleTap(ModifierKey)
    /// Обычная клавиша с модификаторами (или без них — например, F13).
    case key(keyCode: UInt16, modifiers: Modifiers)
}

/// Что делает хоткей.
public enum HotkeyAction: Codable, Hashable, Sendable {
    /// Перевести набранный / выделенный текст (умно или по кругу).
    case convert
    /// Включить конкретную раскладку (и, по настройке, перевести в неё набранное).
    case selectLayout(id: String)
    /// Показать панель истории буфера обмена.
    case clipboardHistory
}
