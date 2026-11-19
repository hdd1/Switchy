import AppKit
import ApplicationServices
import SwitchyCore

/// Приватная, но стабильная функция Accessibility: идентификатор окна CoreGraphics для AX-элемента окна.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Следит за фокусным окном: смена приложения (NSWorkspace) и смена окна внутри приложения (AXObserver).
@MainActor
final class FocusTracker {
    /// Вызывается при смене фокусного окна.
    var onFocusChange: ((WindowKey) -> Void)?
    /// Вызывается при завершении приложения.
    var onAppTerminated: ((Int32) -> Void)?

    private(set) var currentKey: WindowKey?
    private var observer: AXObserver?
    private var observedPID: pid_t?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.observe(pid: pid)
                self.updateFocus(pid: pid)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.onAppTerminated?(pid)
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            observe(pid: app.processIdentifier)
            updateFocus(pid: app.processIdentifier)
        }
    }

    /// Ключ фокусного окна приложения.
    static func focusedWindowKey(pid: pid_t) -> WindowKey {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return WindowKey(pid: pid, windowID: nil) }

        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(windowRef as! AXUIElement, &windowID) == .success, windowID != 0 else {
            return WindowKey(pid: pid, windowID: nil)
        }
        return WindowKey(pid: pid, windowID: windowID)
    }

    fileprivate func updateFocus(pid: pid_t) {
        let key = Self.focusedWindowKey(pid: pid)
        guard key != currentKey else { return }
        currentKey = key
        onFocusChange?(key)
    }

    /// Подписка на смену фокусного окна внутри приложения.
    private func observe(pid: pid_t) {
        guard pid != observedPID else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = pid

        var newObserver: AXObserver?
        guard AXObserverCreate(pid, axCallback, &newObserver) == .success, let newObserver else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(newObserver, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, appElement, kAXMainWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    // Источник в главном run loop — колбэк на главном потоке.
    MainActor.assumeIsolated { tracker.updateFocus(pid: pid) }
}
