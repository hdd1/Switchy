import Testing
@testable import SwitchyCore

@Suite("Определение раскладки текста", .serialized)
@MainActor
struct LayoutDetectorTests {
    let en = KeyboardLayout(id: "com.apple.keylayout.ABC")!
    let ru = KeyboardLayout(id: "com.apple.keylayout.RussianWin")!
    let ua = KeyboardLayout(id: "com.apple.keylayout.Ukrainian-PC")!
    var all: [KeyboardLayout] { [en, ru, ua] }

    func detect(_ text: String, preferred: String? = nil) -> String? {
        LayoutDetector.sourceLayout(of: text, among: all, preferred: preferred)?.source.shortCode
    }

    @Test func latin() { #expect(detect("ghbdtn rfr ltkf") == "EN") }
    @Test func russianOnlyLetters() { #expect(detect("привыт") == "RU") }
    @Test func ukrainianOnlyLetters() { #expect(detect("привіт") == "UA") }

    @Test func ambiguousCyrillicUsesPreferred() {
        #expect(detect("привет", preferred: ru.source.id) == "RU")
        #expect(detect("привет", preferred: ua.source.id) == "UA")
        #expect(detect("привет", preferred: en.source.id) == "RU") // первая по порядку из равных
    }

    @Test func noLetters() { #expect(detect("123 !?") == nil) }
}
