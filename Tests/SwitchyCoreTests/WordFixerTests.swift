import Testing
@testable import SwitchyCore

/// Умный перевод по словам на настоящих раскладках и системном словаре.
@Suite("Перевод по словам", .serialized)
@MainActor
struct WordFixerTests {
    static let enID = "com.apple.keylayout.ABC"
    static let ruID = "com.apple.keylayout.RussianWin"
    static let uaID = "com.apple.keylayout.Ukrainian-PC"

    let en = KeyboardLayout(id: enID)!
    let ru = KeyboardLayout(id: ruID)!
    let ua = KeyboardLayout(id: uaID)!
    let fixer = WordFixer()

    func layout(_ id: String) -> KeyboardLayout { [en, ru, ua].first { $0.source.id == id }! }

    /// Пользователь хотел написать `parts` (слово → раскладка, в которой оно задумано),
    /// но всё набрал в раскладке `typedIn` (слова, задуманные в `typedIn`, набраны правильно).
    /// Возвращает то, что получится после умного перевода, или `nil`.
    func fix(_ parts: [(String, String)], typedIn: String) -> WordFixer.Result? {
        var tokens: [TextToken] = []
        for (n, (word, id)) in parts.enumerated() {
            if n > 0 { tokens.append(.key(KeyStroke(keyCode: TypingBuffer.spaceKeyCode))) }
            tokens += layout(id).keyStrokes(for: word).map { .key($0!) }
        }
        let original = layout(typedIn)
        let typed = original.render(tokens)
        let result = fixer.fix(tokens, original: original, alternatives: [en, ru, ua].filter { $0 !== original })
        print("«\(typed)» →", result.map { "«\($0.text)» [\(layout($0.finalLayout).source.shortCode)]" } ?? "nil")
        return result
    }

    func inRU(_ s: String) -> [(String, String)] { s.split(separator: " ").map { (String($0), Self.ruID) } }
    func inUA(_ s: String) -> [(String, String)] { s.split(separator: " ").map { (String($0), Self.uaID) } }
    func inEN(_ s: String) -> [(String, String)] { s.split(separator: " ").map { (String($0), Self.enID) } }

    @Test func englishTermInsideRussianTypedInEnglish() {
        // Пример пользователя: всё набрано в EN, «dev» — правильно.
        let r = fix(inRU("потому что") + inEN("dev") + inRU("сервер может обратиться к тебе"), typedIn: Self.enID)
        #expect(r?.text == "потому что dev сервер может обратиться к тебе")
        #expect(r?.finalLayout == Self.ruID)
        #expect(r?.uniformTarget == nil)
    }

    @Test func wholeRussianTypedInEnglish() {
        let r = fix(inRU("Если я пошел гулять"), typedIn: Self.enID)
        #expect(r?.text == "Если я пошел гулять")
        #expect(r?.uniformTarget == Self.ruID)
    }

    @Test func englishWordAtEndTypedInRussian() {
        let r = fix(inRU("Да, я выполнил") + inEN("sql"), typedIn: Self.ruID)
        #expect(r?.text == "Да, я выполнил sql")
        #expect(r?.finalLayout == Self.enID)
    }

    @Test func englishWordInMiddleTypedInRussian() {
        let r = fix(inRU("я сделал") + inEN("sql") + inRU("запрос"), typedIn: Self.ruID)
        #expect(r?.text == "я сделал sql запрос")
        #expect(r?.finalLayout == Self.ruID)
    }

    @Test func severalEnglishTerms() {
        let r = fix(inRU("запушил в") + inEN("git") + inRU("и сделал") + inEN("commit"), typedIn: Self.ruID)
        #expect(r?.text == "запушил в git и сделал commit")
    }

    @Test func typoIsLeftAlone() {
        let r = fix(inRU("я выполнл") + inEN("sql"), typedIn: Self.ruID)
        #expect(r?.text == "я выполнл sql")
    }

    @Test func correctEnglishUntouched() {
        #expect(fix(inEN("kubectl get pods"), typedIn: Self.enID) == nil)
    }

    @Test func ukrainianTypedInEnglish() {
        let r = fix(inUA("привіт як справи"), typedIn: Self.enID)
        #expect(r?.text == "привіт як справи")
        #expect(r?.finalLayout == Self.uaID)
    }

    @Test func ukrainianAmbiguousWordFollowsNeighbors() {
        // «день» есть и в русском, и в украинском — решают соседи.
        let r = fix(inUA("Добрий день"), typedIn: Self.enID)
        #expect(r?.text == "Добрий день")
        #expect(r?.finalLayout == Self.uaID)
    }

    @Test func ukrainianApostrophe() {
        // В раскладке Ukrainian-PC апостроф — «ʼ» (U+02BC) на клавише «\\».
        let r = fix(inUA("памʼять та подвірʼя"), typedIn: Self.enID)
        #expect(r?.text == "памʼять та подвірʼя")
    }

    @Test func russianShortWordStaysBeforeEnglishTerm() {
        let r = fix(inRU("положил в") + inEN("buffer"), typedIn: Self.ruID)
        #expect(r?.text == "положил в buffer")
    }

    @Test func singleWords() {
        #expect(fix(inRU("привет"), typedIn: Self.enID)?.text == "привет")
        #expect(fix(inEN("hello world"), typedIn: Self.ruID)?.text == "hello world")
    }

    @Test func shortWordsWithEnglishPhrase() {
        let r = fix(inEN("it is a test"), typedIn: Self.ruID)
        #expect(r?.text == "it is a test")
    }
}
