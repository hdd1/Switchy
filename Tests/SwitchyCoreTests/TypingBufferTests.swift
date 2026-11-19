import Testing
@testable import SwitchyCore

@Suite("Буфер набора и порядок серии")
struct TypingBufferTests {
    // Коды клавиш ANSI: g=5, h=4, b=11, d=2, t=17, n=45, пробел=49, Enter=36, ←=123.
    func type(_ buffer: inout TypingBuffer, _ codes: [UInt16], shift: Bool = false) {
        for c in codes { buffer.handleKeyDown(keyCode: c, modifiers: shift ? .shift : [], capsLock: false) }
    }

    @Test func backspaceIsBoundary() {
        var b = TypingBuffer()
        type(&b, [5, 4, 11])
        #expect(b.strokes.count == 3)
        #expect(b.handleKeyDown(keyCode: TypingBuffer.backspaceKeyCode, modifiers: [], capsLock: false) == .reset)
        #expect(b.isEmpty)
        type(&b, [2, 17])
        #expect(b.strokes.map(\.keyCode) == [2, 17])
    }

    @Test func navigationAndCommandsReset() {
        var b = TypingBuffer()
        type(&b, [5, 4])
        #expect(b.handleKeyDown(keyCode: 123, modifiers: [], capsLock: false) == .reset)
        #expect(b.isEmpty)
        type(&b, [5, 4])
        #expect(b.handleKeyDown(keyCode: 36, modifiers: [], capsLock: false) == .reset)
        type(&b, [5, 4])
        #expect(b.handleKeyDown(keyCode: 9, modifiers: .command, capsLock: false) == .reset)
        type(&b, [5, 4])
        #expect(b.handleKeyDown(keyCode: 5, modifiers: .option, capsLock: false) == .reset)
    }

    @Test func shiftRecorded() {
        var b = TypingBuffer()
        type(&b, [5], shift: true)
        #expect(b.strokes.first == KeyStroke(keyCode: 5, shift: true))
    }

    @Test func lastWordFragment() {
        var b = TypingBuffer()
        type(&b, [5, 4, 49, 11, 2, 49, 49])
        #expect(b.fragment(.lastWord).map(\.keyCode) == [11, 2, 49, 49])
        #expect(b.fragment(.all).count == 7)
    }

    @Test func sequenceOrder() {
        let cycle = ["en", "ru", "ua"]
        #expect(ConversionOrder.sequence(cycle: cycle, original: "en") == ["ru", "ua", "en"])
        #expect(ConversionOrder.sequence(cycle: cycle, original: "ru") == ["ua", "en", "ru"])
        #expect(ConversionOrder.sequence(cycle: cycle, original: "en", first: "ua") == ["ua", "ru", "en"])
        #expect(ConversionOrder.sequence(cycle: cycle, original: "ua", first: "ru") == ["ru", "en", "ua"])
    }
}
