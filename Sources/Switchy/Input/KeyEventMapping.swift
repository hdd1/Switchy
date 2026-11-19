import CoreGraphics
import SwitchyCore

extension Modifiers {
    /// Модификаторы из флагов события (CapsLock и Fn не учитываются: у F-клавиш и стрелок
    /// система всегда выставляет Fn-флаг).
    init(cgFlags flags: CGEventFlags) {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        self = m
    }
}

extension KeyEvent {
    /// Перевод события CoreGraphics в событие движка хоткеев.
    init?(cgType type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Modifiers(cgFlags: event.flags)

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            self = .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
        case .keyUp:
            self = .keyUp(keyCode: keyCode)
        case .flagsChanged:
            if let key = ModifierKey(keyCode: keyCode) {
                let isDown = (event.flags.rawValue & key.deviceMask) != 0
                self = .modifierChanged(key: key, isDown: isDown, modifiers: modifiers)
            } else {
                self = .otherFlagsChanged
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self = .mouseDown
        default:
            return nil
        }
    }
}
