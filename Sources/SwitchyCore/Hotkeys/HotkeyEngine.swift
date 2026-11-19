import Foundation

/// Событие клавиатуры/мыши в независимом от CoreGraphics виде (удобно для тестов).
public enum KeyEvent: Sendable, Equatable {
    case keyDown(keyCode: UInt16, modifiers: Modifiers, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    /// Нажата/отпущена клавиша-модификатор. `modifiers` — состояние ПОСЛЕ изменения.
    case modifierChanged(key: ModifierKey, isDown: Bool, modifiers: Modifiers)
    /// Прочие изменения флагов (CapsLock, Fn).
    case otherFlagsChanged
    case mouseDown
}

public struct HotkeyResult: Equatable, Sendable {
    /// Сработавшее действие.
    public var action: HotkeyAction?
    /// Не пропускать событие дальше в приложение.
    public var swallow: Bool

    public static let pass = HotkeyResult(action: nil, swallow: false)
}

/// Распознаёт хоткеи в потоке событий. Чистая логика, время передаётся снаружи.
public struct HotkeyEngine: Sendable {
    public var bindings: [Hotkey: HotkeyAction]
    /// Максимальная длительность удержания модификатора, чтобы считать это тапом.
    public var tapMaxDuration: TimeInterval = 0.3
    /// Максимальный интервал между тапами для двойного тапа.
    public var doubleTapInterval: TimeInterval = 0.35

    private var pendingTap: (key: ModifierKey, start: TimeInterval)?
    private var lastTap: (key: ModifierKey, time: TimeInterval)?
    /// Клавиши, чьё нажатие мы поглотили, — поглощаем и их повторы, и отпускание.
    private var swallowedKeyCodes: Set<UInt16> = []

    public init(bindings: [Hotkey: HotkeyAction] = [:]) {
        self.bindings = bindings
    }

    public mutating func process(_ event: KeyEvent, at time: TimeInterval) -> HotkeyResult {
        switch event {
        case let .keyDown(keyCode, modifiers, isRepeat):
            resetTaps()
            if swallowedKeyCodes.contains(keyCode) {
                return HotkeyResult(action: nil, swallow: true)
            }
            if let action = bindings[.key(keyCode: keyCode, modifiers: modifiers)] {
                swallowedKeyCodes.insert(keyCode)
                return HotkeyResult(action: isRepeat ? nil : action, swallow: true)
            }
            return .pass

        case let .keyUp(keyCode):
            if swallowedKeyCodes.remove(keyCode) != nil {
                return HotkeyResult(action: nil, swallow: true)
            }
            return .pass

        case let .modifierChanged(key, isDown, modifiers):
            if isDown {
                // Кандидат в тап — только если кроме этого модификатора ничего не зажато.
                if modifiers == key.modifier {
                    pendingTap = (key, time)
                } else {
                    resetTaps()
                }
                return .pass
            }
            return modifierReleased(key, modifiers: modifiers, at: time)

        case .otherFlagsChanged, .mouseDown:
            resetTaps()
            return .pass
        }
    }

    private mutating func modifierReleased(_ key: ModifierKey, modifiers: Modifiers, at time: TimeInterval) -> HotkeyResult {
        guard let pending = pendingTap, pending.key == key,
              time - pending.start <= tapMaxDuration,
              modifiers.isEmpty
        else {
            resetTaps()
            return .pass
        }
        pendingTap = nil

        if let last = lastTap, last.key == key, time - last.time <= doubleTapInterval,
           let action = bindings[.modifierDoubleTap(key)] {
            lastTap = nil
            return HotkeyResult(action: action, swallow: false)
        }
        lastTap = (key, time)
        if let action = bindings[.modifierTap(key)] {
            return HotkeyResult(action: action, swallow: false)
        }
        return .pass
    }

    private mutating func resetTaps() {
        pendingTap = nil
        lastTap = nil
    }
}
