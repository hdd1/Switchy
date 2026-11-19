import AppKit
import SwitchyCore

/// Связывает перехватчик событий, движок хоткеев, буфер набора и действия.
@MainActor
final class HotkeyController {
    private let tap = EventTap()
    private var engine = HotkeyEngine()
    private let store = SettingsStore.shared
    let typing = TypingController()
    /// Хоткей истории буфера обмена.
    var onClipboardHistory: (() -> Void)?

    init() {
        tap.handler = { [weak self] type, event in
            self?.handle(type: type, event: event) ?? false
        }
        store.observe { [weak self] settings in
            self?.engine.bindings = settings.hotkeyBindings(includeClipboard: true)
        }
    }

    @discardableResult
    func start() -> Bool { tap.start() }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // Во время записи хоткея в настройках ничего не перехватываем.
        if store.isRecordingHotkey { return false }

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
            onClipboardHistory?()
        }
    }
}
