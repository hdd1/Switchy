import AppKit
import ApplicationServices
import CoreGraphics

/// Права, без которых Switchy не может работать:
/// - Accessibility (Универсальный доступ) — активный перехват клавиатуры, синтетические нажатия, AX;
/// - Input Monitoring (Мониторинг ввода) — чтение нажатий клавиш.
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var allGranted: Bool { accessibility && inputMonitoring }

    /// Показывает системный запрос Accessibility (если права ещё не выданы).
    static func requestAccessibility() {
        // Ключ kAXTrustedCheckOptionPrompt строкой — глобальная константа не concurrency-safe в Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Показывает системный запрос Input Monitoring (если права ещё не выданы).
    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
