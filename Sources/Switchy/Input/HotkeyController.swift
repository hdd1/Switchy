import AppKit
import SwitchyCore

/// Связывает перехватчик событий, движок хоткеев, буфер набора и действия.
@MainActor
final class HotkeyController {
    private let tap = EventTap()
    private var engine: HotkeyEngine
    let typing = TypingController()

    /// Пока нет окна настроек (этап 6) — привязки по умолчанию.
    static let defaultBindings: [Hotkey: HotkeyAction] = [
        .modifierTap(.leftOption): .convert,
        .key(keyCode: 105, modifiers: []): .selectLayout(id: "com.apple.keylayout.ABC"),          // F13
        .key(keyCode: 107, modifiers: []): .selectLayout(id: "com.apple.keylayout.RussianWin"),   // F14
        .key(keyCode: 113, modifiers: []): .selectLayout(id: "com.apple.keylayout.Ukrainian-PC"), // F15
        // Временно, пока нет дополнительной клавиатуры с F13–F15: ⌃⌥1 / ⌃⌥2 / ⌃⌥3.
        .key(keyCode: 18, modifiers: [.control, .option]): .selectLayout(id: "com.apple.keylayout.ABC"),
        .key(keyCode: 19, modifiers: [.control, .option]): .selectLayout(id: "com.apple.keylayout.RussianWin"),
        .key(keyCode: 20, modifiers: [.control, .option]): .selectLayout(id: "com.apple.keylayout.Ukrainian-PC"),
    ]

    init(bindings: [Hotkey: HotkeyAction] = HotkeyController.defaultBindings) {
        engine = HotkeyEngine(bindings: bindings)
        tap.handler = { [weak self] type, event in
            self?.handle(type: type, event: event) ?? false
        }
    }

    @discardableResult
    func start() -> Bool { tap.start() }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard let keyEvent = KeyEvent(cgType: type, event: event) else { return false }
        let result = engine.process(keyEvent, at: ProcessInfo.processInfo.systemUptime)

        if !result.swallow {
            switch keyEvent {
            case let .keyDown(keyCode, modifiers, _):
                typing.keyDown(keyCode: keyCode, modifiers: modifiers,
                               capsLock: event.flags.contains(.maskAlphaShift))
            case .mouseDown:
                typing.reset()
            default:
                break
            }
        }

        if let action = result.action {
            perform(action)
        }
        return result.swallow
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case let .selectLayout(id):
            typing.selectLayout(id: id)
        case .convert:
            typing.convert()
        case .clipboardHistory:
            // Этап 7: панель истории буфера обмена.
            NSLog("Switchy: хоткей истории буфера")
        }
    }
}
