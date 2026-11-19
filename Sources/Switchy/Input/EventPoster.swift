import CoreGraphics

/// Синтетические нажатия: Backspace и ввод произвольного текста.
/// Все события помечены `EventTap.syntheticMarker`, поэтому собственный перехватчик их пропускает.
@MainActor
enum EventPoster {
    /// Отдельное состояние источника — на наши события не влияют зажатые пользователем модификаторы.
    private static let source = CGEventSource(stateID: .privateState)
    private static let backspaceKeyCode: CGKeyCode = 51

    static func backspace(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(backspaceKeyCode)
        }
    }

    /// Вводит текст Unicode-событиями — результат не зависит от текущей раскладки.
    static func type(_ text: String) {
        for character in text {
            let utf16 = Array(String(character).utf16)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                post(event)
            }
        }
    }

    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            post(event)
        }
    }

    private static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: EventTap.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }
}
