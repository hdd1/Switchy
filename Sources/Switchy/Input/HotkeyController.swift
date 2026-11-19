import AppKit
import SwitchyCore

/// Связывает перехватчик событий, движок хоткеев, буфер набора и действия.
@MainActor
final class HotkeyController {
    private let tap = EventTap()
    private var engine = HotkeyEngine()
    private let store = SettingsStore.shared
    let typing = TypingController()

    init() {
        tap.handler = { [weak self] type, event in
            self?.handle(type: type, event: event) ?? false
        }
        store.observe { [weak self] settings in
            // История буфера обмена (этап 7) пока не подключена.
            self?.engine.bindings = settings.hotkeyBindings(includeClipboard: false)
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
            // Этап 7: панель истории буфера обмена.
            break
        }
    }
}
