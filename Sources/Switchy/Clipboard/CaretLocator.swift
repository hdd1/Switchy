import AppKit
import ApplicationServices

/// Где показать панель: у текстового курсора (через AX), иначе у указателя мыши.
@MainActor
enum CaretLocator {
    /// Точка в координатах Cocoa (начало — левый нижний угол основного экрана):
    /// нижний левый угол курсора / позиция мыши.
    static func anchorPoint() -> NSPoint {
        caretRect().map { NSPoint(x: $0.minX, y: $0.minY) } ?? NSEvent.mouseLocation
    }

    /// Прямоугольник текстового курсора в координатах Cocoa.
    static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef
        ) == .success, let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect != .zero else { return nil }

        // AX: начало в левом верхнем углу основного экрана, ось Y вниз → переводим в Cocoa.
        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.maxY - rect.maxY
        return NSRect(x: rect.minX, y: flippedY, width: max(rect.width, 1), height: max(rect.height, 1))
    }
}
