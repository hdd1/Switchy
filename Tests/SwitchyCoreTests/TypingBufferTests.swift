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

    @Test func pauseStartsNewFragment() {
        var b = TypingBuffer()
        // «я » набрано подряд, затем пауза 6 с и «sql».
        for (i, code) in [UInt16(5), 49].enumerated() {
            b.handleKeyDown(keyCode: code, modifiers: [], capsLock: false, at: Double(i) * 0.2, idleReset: 5)
        }
        b.handleKeyDown(keyCode: 1, modifiers: [], capsLock: false, at: 6.5, idleReset: 5)
        b.handleKeyDown(keyCode: 12, modifiers: [], capsLock: false, at: 6.7, idleReset: 5)
        #expect(b.strokes.map(\.keyCode) == [1, 12])
    }

    @Test func noPauseKeepsFragment() {
        var b = TypingBuffer()
        for (i, code) in [UInt16(5), 4, 11].enumerated() {
            b.handleKeyDown(keyCode: code, modifiers: [], capsLock: false, at: Double(i) * 4, idleReset: 5)
        }
        #expect(b.strokes.count == 3)
        // Таймаут выключен (0) — даже большая пауза ничего не забывает.
        b.handleKeyDown(keyCode: 2, modifiers: [], capsLock: false, at: 1000, idleReset: 0)
        #expect(b.strokes.count == 4)
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
