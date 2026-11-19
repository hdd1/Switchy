import Foundation
import Testing
@testable import SwitchyCore

@Suite("Настройки")
struct AppSettingsTests {
    @Test func defaultsBindDigits() {
        let s = AppSettings.defaults(enabledLayouts: ["en", "ru", "ua"])
        #expect(s.layoutBindings.map(\.primary) == [
            .key(keyCode: 18, modifiers: [.control, .option]),
            .key(keyCode: 19, modifiers: [.control, .option]),
            .key(keyCode: 20, modifiers: [.control, .option]),
        ])
        #expect(s.cycleOrder == ["en", "ru", "ua"])
    }

    @Test func cycleMergesAndExcludes() {
        var s = AppSettings()
        s.cycleOrder = ["ru", "gone", "en"]
        #expect(s.cycle(enabled: ["en", "ru", "ua"]) == ["ru", "en", "ua"])
        s.cycleExcluded = ["en"]
        #expect(s.cycle(enabled: ["en", "ru", "ua"]) == ["ru", "ua"])
        s.cycleExcluded = ["en", "ru", "ua"]
        #expect(s.cycle(enabled: ["en", "ru", "ua"]) == ["ru", "en", "ua"]) // всё исключено — берём все
    }

    @Test func bindings() {
        var s = AppSettings.defaults(enabledLayouts: ["en", "ru"])
        s.layoutBindings[1].secondary = .key(keyCode: 107, modifiers: [])
        let b = s.hotkeyBindings(includeClipboard: false)
        #expect(b[.modifierTap(.leftOption)] == .convert)
        #expect(b[.key(keyCode: 107, modifiers: [])] == .selectLayout(id: "ru"))
        #expect(b[.key(keyCode: 9, modifiers: [.command, .shift])] == nil)
        #expect(s.hotkeyBindings(includeClipboard: true)[.key(keyCode: 9, modifiers: [.command, .shift])] == .clipboardHistory)
    }

    @Test func duplicates() {
        var s = AppSettings.defaults(enabledLayouts: ["en", "ru"])
        #expect(s.duplicateHotkeys().isEmpty)
        s.layoutBindings[1].secondary = .modifierTap(.leftOption)
        #expect(s.duplicateHotkeys() == [.modifierTap(.leftOption)])
    }

    @Test func roundTripAndClearedHotkey() throws {
        var s = AppSettings.defaults(enabledLayouts: ["en"])
        s.convertHotkey = nil
        s.smartMode = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == s)
        #expect(decoded.convertHotkey == nil) // явно снятый хоткей не возвращается к умолчанию
    }

    @Test func missingKeysGetDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"smartMode": false}"#.utf8))
        #expect(decoded.smartMode == false)
        #expect(decoded.convertHotkey == .modifierTap(.leftOption))
        #expect(decoded.windowMemoryEnabled == true)
    }
}
