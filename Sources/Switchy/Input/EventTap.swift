import CoreGraphics
import Foundation

/// Глобальный перехватчик клавиатуры и мыши (CGEventTap) на главном run loop.
@MainActor
final class EventTap {
    /// Метка синтетических событий Switchy — перехватчик их пропускает, не анализируя.
    static let syntheticMarker: Int64 = 0x5357_4954 // "SWIT"

    /// Обработчик: вернуть `true`, чтобы поглотить событие.
    var handler: ((CGEventType, CGEvent) -> Bool)?

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { machPort != nil }

    @discardableResult
    func start() -> Bool {
        guard machPort == nil else { return true }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Switchy: не удалось создать перехватчик событий (нет прав?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        runLoopSource = source
        NSLog("Switchy: перехватчик событий запущен")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        machPort = nil
        runLoopSource = nil
    }

    /// Возвращает `true`, если событие нужно поглотить.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Система отключает медленный перехватчик — включаем обратно.
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            NSLog("Switchy: перехватчик был отключён системой (\(type.rawValue)), включён снова")
            return false
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return false
        }
        return handler?(type, event) ?? false
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    // Источник добавлен в главный run loop — колбэк приходит на главном потоке,
    // событие живёт только в пределах этого вызова.
    nonisolated(unsafe) let event = event
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
