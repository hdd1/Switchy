import Testing
@testable import SwitchyCore

@Suite("Память раскладки по окнам")
struct WindowLayoutMemoryTests {
    let a = WindowKey(pid: 100, windowID: 1)
    let b = WindowKey(pid: 100, windowID: 2)
    let c = WindowKey(pid: 200, windowID: 7)

    @Test func restoresSavedLayout() {
        var m = WindowLayoutMemory()
        m.record("ru", for: a)
        #expect(m.layoutToRestore(for: a, current: "en", policy: .keepCurrent, fixedLayout: nil) == "ru")
        #expect(m.layoutToRestore(for: a, current: "ru", policy: .keepCurrent, fixedLayout: nil) == nil)
    }

    @Test func newWindowKeepsCurrent() {
        var m = WindowLayoutMemory()
        #expect(m.layoutToRestore(for: b, current: "ua", policy: .keepCurrent, fixedLayout: nil) == nil)
        #expect(m.layout(for: b) == "ua")
    }

    @Test func newWindowFixed() {
        var m = WindowLayoutMemory()
        #expect(m.layoutToRestore(for: b, current: "ru", policy: .fixed, fixedLayout: "en") == "en")
        #expect(m.layout(for: b) == "en")
    }

    @Test func forgetProcess() {
        var m = WindowLayoutMemory()
        m.record("ru", for: a)
        m.record("ua", for: b)
        m.record("en", for: c)
        m.forget(pid: 100)
        #expect(m.layout(for: a) == nil)
        #expect(m.layout(for: b) == nil)
        #expect(m.layout(for: c) == "en")
    }

    @Test func capacity() {
        var m = WindowLayoutMemory()
        m.capacity = 2
        m.record("ru", for: a)
        m.record("ua", for: b)
        m.record("en", for: a) // a — свежее, вытеснится b
        m.record("en", for: c)
        #expect(m.layout(for: b) == nil)
        #expect(m.count == 2)
    }
}
