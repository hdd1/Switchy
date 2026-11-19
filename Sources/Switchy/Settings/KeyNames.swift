import AppKit
import Carbon
import SwitchyCore

/// Человекочитаемые названия клавиш и хоткеев.
@MainActor
enum KeyNames {
    static let functionKeys: [(name: String, keyCode: UInt16)] = [
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97),
        ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
        ("F13", 105), ("F14", 107), ("F15", 113), ("F16", 106), ("F17", 64), ("F18", 79),
        ("F19", 80), ("F20", 90),
    ]

    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 76: "⌤",
    ]

    /// Латинская раскладка для подписей клавиш (чтобы ⌃⌥1 не показывался как ⌃⌥«1» в другой раскладке).
    private static let labelLayout: KeyboardLayout? = {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        if let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            if let layout = KeyboardLayout(id: id) { return layout }
        }
        return KeyboardLayout(id: "com.apple.keylayout.ABC")
    }()

    static func name(keyCode: UInt16) -> String {
        if let special = special[keyCode] { return special }
        if let f = functionKeys.first(where: { $0.keyCode == keyCode }) { return f.name }
        if let ch = labelLayout?.character(for: KeyStroke(keyCode: keyCode)) {
            return String(ch).uppercased()
        }
        return "#\(keyCode)"
    }

    static func describe(_ hotkey: Hotkey) -> String {
        switch hotkey {
        case let .modifierTap(key):
            return String(localized: "Tap: \(key.displayName)")
        case let .modifierDoubleTap(key):
            return String(localized: "Double tap: \(key.displayName)")
        case let .key(keyCode, modifiers):
            return modifiers.symbols + name(keyCode: keyCode)
        }
    }

    /// Предупреждение о совпадении с известными системными сочетаниями.
    static func systemConflict(_ hotkey: Hotkey) -> String? {
        switch hotkey {
        case .key(keyCode: 49, modifiers: [.control]):
            return String(localized: "⌃Space is the system input source shortcut")
        case .key(keyCode: 49, modifiers: [.control, .option]):
            return String(localized: "⌃⌥Space is the system “next input source” shortcut")
        case .key(keyCode: 49, modifiers: [.command]):
            return String(localized: "⌘Space is Spotlight")
        case .key(keyCode: 9, modifiers: [.command, .shift]):
            return String(localized: "⇧⌘V is used by some apps: “Paste and Match Style”, JetBrains “Paste from History”. Switchy will take it over.")
        default:
            return nil
        }
    }
}

extension Modifiers {
    init(nsFlags flags: NSEvent.ModifierFlags) {
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        self = m
    }
}

extension InputSource {
    /// Подпись раскладки в списках: «RU  Russian – PC» (не переводится).
    var menuLabel: String { "\(shortCode)  \(name)" }
}
