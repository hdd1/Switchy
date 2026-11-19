import AppKit
import NaturalLanguage

/// Умный выбор раскладки: какой из вариантов текста больше похож на осмысленный текст на своём языке.
/// Только встроенные средства macOS, без сети:
/// - `NSSpellChecker` — доля слов, известных словарю языка (главный сигнал, особенно между алфавитами);
/// - `NLLanguageRecognizer` — вероятность языка (различает русский и украинский на одном алфавите).
@MainActor
public struct SmartDetector {
    public struct Candidate: Sendable {
        public let layoutID: String
        /// Код языка раскладки: `en`, `ru`, `uk`.
        public let language: String
        public let text: String

        public init(layoutID: String, language: String, text: String) {
            self.layoutID = layoutID
            self.language = language
            self.text = text
        }
    }

    public struct Scored: Sendable {
        public let candidate: Candidate
        public let score: Double
        public let spellRatio: Double
        public let languageProbability: Double
        public let letterRatio: Double
    }

    /// Минимальная оценка лучшего варианта.
    public var minScore = 0.45
    /// Минимальный отрыв лучшего варианта от второго.
    public var minMargin = 0.1

    public init() {}

    /// Раскладка, в которую стоит перевести, или `nil`, если уверенности нет.
    public func pick(_ candidates: [Candidate]) -> String? {
        let scored = score(candidates)
        guard let best = scored.first, best.score >= minScore else { return nil }
        if scored.count > 1, best.score - scored[1].score < minMargin { return nil }
        return best.candidate.layoutID
    }

    /// Оценки по убыванию.
    public func score(_ candidates: [Candidate]) -> [Scored] {
        candidates.map(score).sorted { $0.score > $1.score }
    }

    func score(_ candidate: Candidate) -> Scored {
        let spell = spellRatio(candidate.text, language: candidate.language)
        let probability = languageProbability(candidate.text, language: candidate.language)
        let letters = letterRatio(candidate.text)
        let total = 0.7 * spell + 0.2 * probability + 0.1 * letters
        return Scored(candidate: candidate, score: total, spellRatio: spell,
                      languageProbability: probability, letterRatio: letters)
    }

    // MARK: - Сигналы

    /// Доля слов (2+ буквы), которые словарь языка считает правильными.
    func spellRatio(_ text: String, language: String) -> Double {
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(language) else { return 0 }
        let words = Self.words(in: text).filter { $0.count >= 2 }
        guard !words.isEmpty else { return 0 }
        let known = words.filter { word in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        return Double(known.count) / Double(words.count)
    }

    /// Вероятность языка по распознавателю (без ограничения списка языков: при ограничении
    /// любой латинский мусор получает «английский» с вероятностью ~1).
    func languageProbability(_ text: String, language: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 30)
        return hypotheses[NLLanguage(rawValue: language)] ?? 0
    }

    /// Доля букв среди непробельных символов: варианты вроде «ghb;tn» с знаками внутри слов — хуже.
    func letterRatio(_ text: String) -> Double {
        let visible = text.filter { !$0.isWhitespace }
        guard !visible.isEmpty else { return 0 }
        return Double(visible.filter(\.isLetter).count) / Double(visible.count)
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { !$0.isEmpty }
    }
}
