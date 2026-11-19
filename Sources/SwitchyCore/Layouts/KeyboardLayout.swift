import Carbon
import Foundation

/// Физическое нажатие клавиши: код клавиши + состояние Shift / CapsLock.
public struct KeyStroke: Hashable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool
    public let capsLock: Bool

    public init(keyCode: UInt16, shift: Bool = false, capsLock: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
        self.capsLock = capsLock
    }
}

/// Таблица раскладки: какая клавиша какой символ даёт, и обратно.
/// Строится из системных данных раскладки (`UCKeyTranslate`), поэтому работает с любой раскладкой.
public final class KeyboardLayout: Sendable {
    public let source: InputSource
    private let layoutData: Data
    private let reverseMap: [Character: KeyStroke]

    /// Коды «печатающих» клавиш основного блока (ANSI/ISO): буквы, цифры, знаки, пробел.
    /// Без Return (36) и Tab (48). Цифровой блок не берём — он одинаков во всех раскладках.
    static let printableKeyCodes: [UInt16] = (0...50).map(UInt16.init).filter { $0 != 36 && $0 != 48 }

    @MainActor
    public convenience init?(source: InputSource) {
        self.init(id: source.id, fallbackSource: source)
    }

    /// Загружает раскладку по идентификатору (в том числе не включённую пользователем).
    @MainActor
    public convenience init?(id: String) {
        self.init(id: id, fallbackSource: nil)
    }

    @MainActor
    private init?(id: String, fallbackSource: InputSource?) {
        guard let tis = InputSources.tisSource(id: id, includeAllInstalled: true),
              let source = fallbackSource ?? InputSources.makeSource(tis),
              let cfData: CFData = InputSources.property(tis, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        self.source = source
        self.layoutData = cfData as Data

        // Обратная таблица: символ → клавиша. Сначала без Shift, потом с Shift;
        // при совпадениях побеждает первый вариант (меньший код клавиши, без Shift).
        var reverse: [Character: KeyStroke] = [:]
        for shift in [false, true] {
            for code in Self.printableKeyCodes {
                let stroke = KeyStroke(keyCode: code, shift: shift)
                if let ch = Self.translate(stroke, data: layoutData), reverse[ch] == nil {
                    reverse[ch] = stroke
                }
            }
        }
        self.reverseMap = reverse
    }

    /// Символ, который даёт нажатие в этой раскладке (или `nil` для непечатающих/пустых).
    public func character(for stroke: KeyStroke) -> Character? {
        Self.translate(stroke, data: layoutData)
    }

    /// Клавиша, которой в этой раскладке набирается символ.
    public func keyStroke(for character: Character) -> KeyStroke? {
        reverseMap[character]
    }

    /// Текст, который дала бы последовательность нажатий в этой раскладке.
    /// Нажатия, не дающие символа, пропускаются.
    public func render(_ strokes: [KeyStroke]) -> String {
        String(strokes.compactMap(character(for:)))
    }

    /// Нажатия, которыми набирается текст в этой раскладке. `nil` для символов, которых в раскладке нет.
    public func keyStrokes(for text: String) -> [KeyStroke?] {
        text.map { reverseMap[$0] }
    }

    // MARK: - UCKeyTranslate

    private static func translate(_ stroke: KeyStroke, data: Data) -> Character? {
        var modifiers: UInt32 = 0
        if stroke.shift { modifiers |= UInt32(shiftKey >> 8) }
        if stroke.capsLock { modifiers |= UInt32(alphaLock >> 8) }

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(paramErr) }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                layout,
                stroke.keyCode,
                UInt16(kUCKeyActionDown),
                modifiers & 0xFF,
                UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }

        let string = String(utf16CodeUnits: chars, count: length)
        guard string.count == 1, let ch = string.first else { return nil }
        // Отбрасываем управляющие символы.
        if ch.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7F }) { return nil }
        return ch
    }
}
