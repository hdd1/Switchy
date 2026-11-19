import Testing
@testable import SwitchyCore

/// Набор фраз «набрал не в той раскладке» — проверка и подбор порогов умного режима.
@Suite("Умный перевод", .serialized)
@MainActor
struct SmartDetectorTests {
    static let enID = "com.apple.keylayout.ABC"
    static let ruID = "com.apple.keylayout.RussianWin"
    static let uaID = "com.apple.keylayout.Ukrainian-PC"

    let layouts: [String: KeyboardLayout] = [
        enID: KeyboardLayout(id: enID)!,
        ruID: KeyboardLayout(id: ruID)!,
        uaID: KeyboardLayout(id: uaID)!,
    ]
    let detector = SmartDetector()

    /// Пользователь хотел написать `intended` в `intendedID`, но набрал в `typedID`.
    /// Возвращает выбор умного режима.
    func pick(intended: String, in intendedID: String, typedIn typedID: String) -> String? {
        let strokes = layouts[intendedID]!.keyStrokes(for: intended).compactMap { $0 }
        let candidates = layouts.filter { $0.key != typedID }.map { id, layout in
            SmartDetector.Candidate(layoutID: id, language: layout.source.language ?? "", text: layout.render(strokes))
        }
        let scored = detector.score(candidates)
        let report = scored.map {
            "\($0.candidate.text) [\($0.candidate.language)] \(String(format: "%.2f", $0.score))"
            + " (spell \(String(format: "%.2f", $0.spellRatio)), lang \(String(format: "%.2f", $0.languageProbability)))"
        }
        print("«\(intended)»:", report.joined(separator: " | "))
        return detector.pick(candidates)
    }

    @Test(arguments: [
        "привет как дела",
        "Съешь же ещё этих мягких французских булок",
        "сегодня хорошая погода",
        "привет",
        "спасибо",
    ])
    func russianTypedInEnglish(_ phrase: String) {
        #expect(pick(intended: phrase, in: Self.ruID, typedIn: Self.enID) == Self.ruID)
    }

    @Test(arguments: [
        "привіт як справи",
        "дякую за допомогу",
        "привіт",
        "Добрий день",
    ])
    func ukrainianTypedInEnglish(_ phrase: String) {
        #expect(pick(intended: phrase, in: Self.uaID, typedIn: Self.enID) == Self.uaID)
    }

    @Test(arguments: ["hello world", "the quick brown fox", "hello", "commit"])
    func englishTypedInRussian(_ phrase: String) {
        #expect(pick(intended: phrase, in: Self.enID, typedIn: Self.ruID) == Self.enID)
    }

    @Test func ukrainianTypedInRussian() {
        #expect(pick(intended: "привіт як справи", in: Self.uaID, typedIn: Self.ruID) == Self.uaID)
    }

    @Test func russianTypedInUkrainian() {
        #expect(pick(intended: "как дела", in: Self.ruID, typedIn: Self.uaID) == Self.ruID)
    }

    /// Мусор и код — уверенности быть не должно (тогда работает «по кругу»).
    @Test(arguments: ["xq", "a1b2"])
    func noConfidenceOnGarbage(_ text: String) {
        #expect(pick(intended: text, in: Self.enID, typedIn: Self.ruID) == nil)
    }
}
