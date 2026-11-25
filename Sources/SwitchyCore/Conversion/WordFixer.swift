import AppKit

/// Элемент переводимого фрагмента: физическое нажатие (набранное) или готовый символ,
/// которого нет в исходной раскладке (эмодзи, перевод строки в выделенном тексте…).
public enum TextToken: Hashable, Sendable {
    case key(KeyStroke)
    case literal(Character)

    var isWhitespace: Bool {
        switch self {
        case let .key(stroke): stroke.keyCode == TypingBuffer.spaceKeyCode
        case let .literal(ch): ch.isWhitespace
        }
    }
}

public extension KeyboardLayout {
    /// Текст, который дают токены в этой раскладке.
    func render(_ tokens: [TextToken]) -> String {
        var result = ""
        for token in tokens {
            switch token {
            case let .key(stroke): if let ch = character(for: stroke) { result.append(ch) }
            case let .literal(ch): result.append(ch)
            }
        }
        return result
    }

    /// Токены готового текста, набранного в этой раскладке.
    func tokens(for text: String) -> [TextToken] {
        text.map { ch in keyStroke(for: ch).map(TextToken.key) ?? .literal(ch) }
    }
}

/// Проверка слов по системному словарю.
@MainActor
public enum SpellCheck {
    public static func isKnown(_ word: String, language: String) -> Bool {
        let checker = NSSpellChecker.shared
        guard checker.availableLanguages.contains(language) else { return false }
        return checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                     inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}

/// Умный перевод по словам: переводит только слова, набранные не в той раскладке.
///
/// - Длинное слово (3+ буквы) переводится, если в текущей раскладке это не слово,
///   а в другой — настоящее слово (двусторонняя проверка бережёт термины и опечатки).
/// - Короткие слова (1–2 буквы) словарём не проверить — для них встроенные списки коротких слов,
///   а при неоднозначности короткое слово следует за соседним длинным (сначала справа, потом слева).
@MainActor
public struct WordFixer {
    public struct Result: Equatable, Sendable {
        /// Итоговый текст.
        public let text: String
        /// Раскладка, которую включить после перевода (раскладка последнего слова).
        public let finalLayout: String
        /// Если все переведённые слова ушли в одну раскладку и итог совпадает с переводом
        /// фрагмента целиком в неё — эта раскладка.
        public let uniformTarget: String?
        /// Раскладка, в которую ушло больше всего слов.
        public let dominantTarget: String
    }

    /// Проверка «это слово языка»: (слово, код языка) → Bool.
    let isWord: @MainActor (String, String) -> Bool

    public init(isWord: @escaping @MainActor (String, String) -> Bool = SpellCheck.isKnown) {
        self.isWord = isWord
    }

    /// Короткие (1–2 буквы) слова, которые точно существуют в языке.
    static let shortWords: [String: Set<String>] = [
        "en": ["a", "i", "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it",
               "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "we"],
        "ru": ["а", "б", "в", "ж", "и", "к", "о", "с", "у", "я", "ах", "во", "вы", "да", "до", "её", "ее", "же", // l10n-ignore: словарные данные, не интерфейс
               "за", "из", "им", "их", "ко", "ли", "мы", "на", "не", "ни", "но", "ну", "об", "ой", "ок", "он", // l10n-ignore: словарные данные, не интерфейс
               "от", "ох", "по", "со", "та", "те", "то", "ту", "ты", "уж", "эх"], // l10n-ignore: словарные данные, не интерфейс
        "uk": ["а", "б", "в", "ж", "з", "і", "й", "о", "у", "я", "ах", "ви", "де", "до", "же", "за", "із", "їй", // l10n-ignore: словарные данные, не интерфейс
               "ми", "на", "не", "ні", "ну", "об", "ой", "ок", "он", "от", "ох", "по", "та", "те", "ти", "то", // l10n-ignore: словарные данные, не интерфейс
               "ту", "це", "ще", "як"], // l10n-ignore: словарные данные, не интерфейс
    ]

    /// `nil` — ни одно слово не выглядит набранным не в той раскладке.
    public func fix(_ tokens: [TextToken], original: KeyboardLayout, alternatives: [KeyboardLayout]) -> Result? {
        let segments = Self.split(tokens)
        let wordIndices = segments.indices.filter { segments[$0].isWord }
        guard !wordIndices.isEmpty else { return nil }

        let all = [original] + alternatives
        func lang(_ layout: KeyboardLayout) -> String { layout.source.language ?? "" }

        // 1. Длинные слова: однозначные решения и кандидаты для неоднозначных.
        var targets: [Int: String] = [:]           // индекс сегмента → раскладка
        var ambiguous: [Int: [KeyboardLayout]] = [:]
        var short: [Int] = []

        for i in wordIndices {
            let word = segments[i].tokens
            let letters = all.map { $0.render(word).filter(\.isLetter).count }.max() ?? 0
            guard letters >= 3 else { short.append(i); continue }

            if isValidLong(original.render(word), language: lang(original)) {
                targets[i] = original.source.id
                continue
            }
            let valid = alternatives.filter { isValidLong($0.render(word), language: lang($0)) }
            switch valid.count {
            case 0: targets[i] = original.source.id
            case 1: targets[i] = valid[0].source.id
            default: ambiguous[i] = valid
            }
        }

        // 2. Неоднозначные длинные: в пользу раскладки, куда ушло больше однозначных слов.
        let decidedCounts = Dictionary(grouping: targets.values.filter { $0 != original.source.id }, by: { $0 })
            .mapValues(\.count)
        for (i, valid) in ambiguous {
            let best = valid.max { (decidedCounts[$0.source.id] ?? 0) < (decidedCounts[$1.source.id] ?? 0) }!
            let tie = valid.filter { (decidedCounts[$0.source.id] ?? 0) == (decidedCounts[best.source.id] ?? 0) }
            if tie.count == 1 {
                targets[i] = best.source.id
            } else {
                // Нет подсказки от соседей — оценка умного детектора по самому слову.
                let candidates = tie.map {
                    SmartDetector.Candidate(layoutID: $0.source.id, language: lang($0), text: $0.render(segments[i].tokens))
                }
                targets[i] = SmartDetector().score(candidates).first?.candidate.layoutID ?? tie[0].source.id
            }
        }

        // 3. Короткие слова и слова без букв.
        func neighbor(of i: Int) -> String? {
            let longs = targets.keys.sorted()
            if let right = longs.first(where: { $0 > i }) { return targets[right] }
            if let left = longs.last(where: { $0 < i }) { return targets[left] }
            return nil
        }
        func inList(_ layout: KeyboardLayout, _ word: [TextToken]) -> Bool {
            let core = Self.core(layout.render(word)).lowercased()
            return !core.isEmpty && (Self.shortWords[lang(layout)]?.contains(core) ?? false)
        }
        var shortTargets: [Int: String] = [:]
        for i in short {
            let word = segments[i].tokens
            let hasLetters = all.contains { $0.render(word).contains(where: \.isLetter) }
            let near = neighbor(of: i)
            guard hasLetters else {
                shortTargets[i] = near ?? original.source.id
                continue
            }
            let originalOK = inList(original, word)
            let altOK = alternatives.filter { inList($0, word) }.map(\.source.id)
            if originalOK {
                // Правильное здесь короткое слово («в», «я», «to») остаётся, если только соседнее слово
                // не уходит в раскладку, где оно тоже правильное (RU «в» → UA «в» среди украинских слов).
                shortTargets[i] = (near.flatMap { altOK.contains($0) ? $0 : nil }) ?? original.source.id
            } else if !altOK.isEmpty {
                shortTargets[i] = (near.flatMap { altOK.contains($0) ? $0 : nil }) ?? altOK[0]
            } else {
                // Ни там, ни там не слово (или без букв) — как сосед.
                shortTargets[i] = near ?? original.source.id
            }
        }
        targets.merge(shortTargets) { a, _ in a }

        // 4. Итог.
        let converted = wordIndices.filter { targets[$0] != original.source.id }
        guard !converted.isEmpty else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.source.id, $0) })
        var text = ""
        for (i, segment) in segments.enumerated() {
            let layout = segment.isWord ? (byID[targets[i] ?? ""] ?? original) : original
            text += layout.render(segment.tokens)
        }

        let lastWithLetters = wordIndices.last { i in all.contains { $0.render(segments[i].tokens).contains(where: \.isLetter) } }
        let finalLayout = lastWithLetters.flatMap { targets[$0] } ?? original.source.id

        let counts = Dictionary(grouping: converted.compactMap { targets[$0] }, by: { $0 }).mapValues(\.count)
        let dominant = counts.max { $0.value < $1.value }?.key ?? finalLayout

        var uniform: String?
        if Set(converted.compactMap { targets[$0] }).count == 1, let only = converted.first.flatMap({ targets[$0] }),
           let layout = byID[only], layout.render(tokens) == text {
            uniform = only
        }

        return Result(text: text, finalLayout: finalLayout, uniformTarget: uniform, dominantTarget: dominant)
    }

    // MARK: - Слова

    struct Segment {
        var tokens: [TextToken]
        var isWord: Bool
    }

    /// Разбивка на слова и пробельные промежутки (с сохранением всех токенов).
    static func split(_ tokens: [TextToken]) -> [Segment] {
        var segments: [Segment] = []
        for token in tokens {
            let isWord = !token.isWhitespace
            if var last = segments.last, last.isWord == isWord {
                last.tokens.append(token)
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(tokens: [token], isWord: isWord))
            }
        }
        return segments
    }

    /// Слово без знаков по краям («Да,» → «Да», «(привет)» → «привет»).
    static func core(_ word: String) -> String {
        let chars = Array(word)
        guard let start = chars.firstIndex(where: \.isLetter),
              let end = chars.lastIndex(where: \.isLetter) else { return "" }
        return String(chars[start...end])
    }

    /// Длинное слово — настоящее слово языка: без знаков внутри (кроме апострофа и дефиса),
    /// все части через дефис — в словаре.
    func isValidLong(_ rendered: String, language: String) -> Bool {
        let core = Self.core(rendered)
        guard core.count >= 2 else { return false }
        let parts = core.split(separator: "-", omittingEmptySubsequences: false)
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return false }
            let word = String(part)
            // Украинский апостроф раскладки — «ʼ» (U+02BC); словарь может знать слово с «'».
            let variants = [word, word.replacingOccurrences(of: "ʼ", with: "'"), word.replacingOccurrences(of: "ʼ", with: "’")]
            guard variants.contains(where: { isWord($0, language) }) else { return false }
        }
        return true
    }
}
