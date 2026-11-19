import Testing
@testable import SwitchyCore

/// Тесты маппинга на реальных системных раскладках пользователя: ABC, Russian – PC, Ukrainian (PC).
@Suite("Перевод между раскладками", .serialized)
@MainActor
struct LayoutConverterTests {
    let en = KeyboardLayout(id: "com.apple.keylayout.ABC")!
    let ru = KeyboardLayout(id: "com.apple.keylayout.RussianWin")!
    let ua = KeyboardLayout(id: "com.apple.keylayout.Ukrainian-PC")!

    @Test func shortCodes() {
        #expect(en.source.shortCode == "EN")
        #expect(ru.source.shortCode == "RU")
        #expect(ua.source.shortCode == "UA")
    }

    @Test func enToRu() {
        #expect(LayoutConverter.convert("ghbdtn", from: en, to: ru) == "привет")
        #expect(LayoutConverter.convert("Ghbdtn", from: en, to: ru) == "Привет")
        #expect(LayoutConverter.convert("ntcn 123", from: en, to: ru) == "тест 123")
    }

    @Test func ruToEn() {
        #expect(LayoutConverter.convert("руддщ", from: ru, to: en) == "hello")
        #expect(LayoutConverter.convert("Руддщ цщкдв", from: ru, to: en) == "Hello world")
    }

    @Test func enToUa() {
        // В украинской раскладке на месте «ы» — «і», «ъ» — «ї», «э» — «є».
        #expect(LayoutConverter.convert("ghbdsn", from: en, to: ua) == "привіт")
        #expect(LayoutConverter.convert("]", from: en, to: ua) == "ї")
        #expect(LayoutConverter.convert("'", from: en, to: ua) == "є")
    }

    @Test func ruToUa() {
        #expect(LayoutConverter.convert("ы", from: ru, to: ua) == "і")
        #expect(LayoutConverter.convert("ъ", from: ru, to: ua) == "ї")
        #expect(LayoutConverter.convert("э", from: ru, to: ua) == "є")
        #expect(LayoutConverter.convert("ghbdtn", from: en, to: ru) == LayoutConverter.convert("ghbdtn", from: en, to: ua))
    }

    @Test func roundTrip() {
        let text = "Съешь же ещё этих мягких французских булок"
        let typedInEn = LayoutConverter.convert(text, from: ru, to: en)
        #expect(LayoutConverter.convert(typedInEn, from: en, to: ru) == text)
    }

    @Test func keyStrokesRender() {
        let strokes = en.keyStrokes(for: "Ghbdtn").compactMap { $0 }
        #expect(strokes.count == 6)
        #expect(ru.render(strokes) == "Привет")
        #expect(ua.render(strokes) == "Привет")
    }

    @Test func unknownCharactersPassThrough() {
        #expect(LayoutConverter.convert("ghbdtn 👋", from: en, to: ru) == "привет 👋")
    }
}
