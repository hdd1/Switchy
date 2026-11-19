import Testing
@testable import SwitchyCore

@Suite("Движок хоткеев")
struct HotkeyEngineTests {
    static let f13: UInt16 = 105
    static let keyA: UInt16 = 0

    func makeEngine() -> HotkeyEngine {
        HotkeyEngine(bindings: [
            .modifierTap(.rightOption): .convert,
            .modifierDoubleTap(.leftOption): .clipboardHistory,
            .key(keyCode: Self.f13, modifiers: []): .selectLayout(id: "en"),
            .key(keyCode: 9, modifiers: [.command, .shift]): .clipboardHistory, // ⇧⌘V
        ])
    }

    func down(_ key: ModifierKey) -> KeyEvent { .modifierChanged(key: key, isDown: true, modifiers: key.modifier) }
    func up(_ key: ModifierKey, still: Modifiers = []) -> KeyEvent { .modifierChanged(key: key, isDown: false, modifiers: still) }

    @Test func rightOptionTapFires() {
        var e = makeEngine()
        #expect(e.process(down(.rightOption), at: 0) == .pass)
        let r = e.process(up(.rightOption), at: 0.1)
        #expect(r.action == .convert)
        #expect(r.swallow == false)
    }

    @Test func leftOptionTapDoesNotFireRightBinding() {
        var e = makeEngine()
        _ = e.process(down(.leftOption), at: 0)
        #expect(e.process(up(.leftOption), at: 0.1).action == nil)
    }

    @Test func longHoldIsNotTap() {
        var e = makeEngine()
        _ = e.process(down(.rightOption), at: 0)
        #expect(e.process(up(.rightOption), at: 0.8).action == nil)
    }

    @Test func optionWithLetterIsNotTap() {
        var e = makeEngine()
        _ = e.process(down(.rightOption), at: 0)
        _ = e.process(.keyDown(keyCode: Self.keyA, modifiers: .option, isRepeat: false), at: 0.05)
        _ = e.process(.keyUp(keyCode: Self.keyA), at: 0.08)
        #expect(e.process(up(.rightOption), at: 0.1).action == nil)
    }

    @Test func optionWithOtherModifierIsNotTap() {
        var e = makeEngine()
        _ = e.process(.modifierChanged(key: .leftCommand, isDown: true, modifiers: .command), at: 0)
        _ = e.process(.modifierChanged(key: .rightOption, isDown: true, modifiers: [.command, .option]), at: 0.02)
        _ = e.process(.modifierChanged(key: .rightOption, isDown: false, modifiers: .command), at: 0.05)
        #expect(e.process(.modifierChanged(key: .leftCommand, isDown: false, modifiers: []), at: 0.07).action == nil)
    }

    @Test func doubleTap() {
        var e = makeEngine()
        _ = e.process(down(.leftOption), at: 0)
        #expect(e.process(up(.leftOption), at: 0.08).action == nil)
        _ = e.process(down(.leftOption), at: 0.2)
        #expect(e.process(up(.leftOption), at: 0.28).action == .clipboardHistory)
        // Третий тап сразу после — не двойной (серия сброшена).
        _ = e.process(down(.leftOption), at: 0.35)
        #expect(e.process(up(.leftOption), at: 0.4).action == nil)
    }

    @Test func slowDoubleTapIsNotDouble() {
        var e = makeEngine()
        _ = e.process(down(.leftOption), at: 0)
        _ = e.process(up(.leftOption), at: 0.08)
        _ = e.process(down(.leftOption), at: 0.6)
        #expect(e.process(up(.leftOption), at: 0.68).action == nil)
    }

    @Test func singleKeyFiresAndSwallowsWholePress() {
        var e = makeEngine()
        let d = e.process(.keyDown(keyCode: Self.f13, modifiers: [], isRepeat: false), at: 0)
        #expect(d == HotkeyResult(action: .selectLayout(id: "en"), swallow: true))
        let rep = e.process(.keyDown(keyCode: Self.f13, modifiers: [], isRepeat: true), at: 0.5)
        #expect(rep == HotkeyResult(action: nil, swallow: true))
        #expect(e.process(.keyUp(keyCode: Self.f13), at: 0.6).swallow == true)
        // Обычная клавиша — не трогаем.
        #expect(e.process(.keyDown(keyCode: Self.keyA, modifiers: [], isRepeat: false), at: 1) == .pass)
        #expect(e.process(.keyUp(keyCode: Self.keyA), at: 1.1) == .pass)
    }

    @Test func comboRequiresExactModifiers() {
        var e = makeEngine()
        #expect(e.process(.keyDown(keyCode: 9, modifiers: .command, isRepeat: false), at: 0) == .pass)
        #expect(e.process(.keyDown(keyCode: 9, modifiers: [.command, .shift], isRepeat: false), at: 1).action == .clipboardHistory)
    }

    @Test func mouseCancelsTap() {
        var e = makeEngine()
        _ = e.process(down(.rightOption), at: 0)
        _ = e.process(.mouseDown, at: 0.05)
        #expect(e.process(up(.rightOption), at: 0.1).action == nil)
    }
}
