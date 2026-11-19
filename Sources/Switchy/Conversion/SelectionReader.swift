import AppKit
import ApplicationServices

/// Чтение выделенного текста в активном приложении через Accessibility.
@MainActor
enum SelectionReader {
    enum Result: Equatable {
        case text(String)
        /// Поле поддерживает AX, но ничего не выделено.
        case empty
        /// Приложение не отдаёт выделение через AX — нужен запасной путь через ⌘C.
        case unavailable
    }

    private static var manualAccessibilityPIDs: Set<pid_t> = []

    static func read() -> Result {
        enableManualAccessibilityForFrontmostApp()

        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return .unavailable }
        let focused = focusedRef as! AXUIElement

        var valueRef: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &valueRef)
        guard error == .success, let text = valueRef as? String else { return .unavailable }
        return text.isEmpty ? .empty : .text(text)
    }

    /// Electron-приложения (Slack, VS Code, …) включают AX-дерево только по этому флагу.
    private static func enableManualAccessibilityForFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              !manualAccessibilityPIDs.contains(app.processIdentifier) else { return }
        manualAccessibilityPIDs.insert(app.processIdentifier)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
