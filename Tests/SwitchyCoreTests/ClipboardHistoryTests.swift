import Foundation
import Testing
@testable import SwitchyCore

@Suite("История буфера обмена")
struct ClipboardHistoryTests {
    @Test func newestFirst() {
        var h = ClipboardHistory()
        h.add("один", capacity: 10)
        h.add("два", capacity: 10)
        h.add("три", capacity: 10)
        #expect(h.items.map(\.text) == ["три", "два", "один"])
    }

    @Test func duplicateMovesToTop() {
        var h = ClipboardHistory()
        h.add("один", capacity: 10)
        h.add("два", capacity: 10)
        h.add("один", capacity: 10)
        #expect(h.items.map(\.text) == ["один", "два"])
    }

    @Test func emptyIgnored() {
        var h = ClipboardHistory()
        #expect(h.add("  \n ", capacity: 10) == false)
        #expect(h.items.isEmpty)
    }

    @Test func capacity() {
        var h = ClipboardHistory()
        for i in 1...5 { h.add("\(i)", capacity: 3) }
        #expect(h.items.map(\.text) == ["5", "4", "3"])
        h.trim(to: 1)
        #expect(h.items.map(\.text) == ["5"])
    }

    @Test func removeAndClear() {
        var h = ClipboardHistory()
        h.add("а", capacity: 10)
        h.add("б", capacity: 10)
        h.remove(id: h.items[0].id)
        #expect(h.items.map(\.text) == ["а"])
        h.clear()
        #expect(h.items.isEmpty)
    }

    @Test func filter() {
        var h = ClipboardHistory()
        h.add("SELECT * FROM orders", capacity: 10)
        h.add("Привет, мир", capacity: 10)
        h.add("hello", capacity: 10)
        #expect(h.filtered("").count == 3)
        #expect(h.filtered("select").map(\.text) == ["SELECT * FROM orders"])
        #expect(h.filtered("МИР").map(\.text) == ["Привет, мир"])
    }

    @Test func preview() {
        let item = ClipboardItem(text: "\n\n   первая    строка  \nвторая")
        #expect(item.preview() == "первая строка")
        #expect(item.lineCount == 4)
        let long = ClipboardItem(text: String(repeating: "x", count: 200))
        #expect(long.preview(maxLength: 10) == "xxxxxxxxx…")
    }

    @Test func codableRoundTrip() throws {
        var h = ClipboardHistory()
        h.add("тест", source: "com.apple.Notes", capacity: 10)
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(h))
        #expect(decoded.items == h.items)
    }
}
