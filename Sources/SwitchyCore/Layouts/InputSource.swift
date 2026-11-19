import Carbon
import Foundation

/// Источник ввода (раскладка клавиатуры) macOS.
public struct InputSource: Hashable, Sendable, Identifiable {
    /// Системный идентификатор, например `com.apple.keylayout.RussianWin`.
    public let id: String
    /// Локализованное имя, например «Russian – PC».
    public let name: String
    /// Языки раскладки; первый — основной (`en`, `ru`, `uk`).
    public let languages: [String]

    public init(id: String, name: String, languages: [String]) {
        self.id = id
        self.name = name
        self.languages = languages
    }

    public var language: String? { languages.first }

    /// Короткий код для строки меню: EN / RU / UA.
    public var shortCode: String {
        switch language {
        case "uk": return "UA"
        case let lang?: return String(lang.prefix(2)).uppercased()
        case nil: return "??"
        }
    }
}

/// Работа с источниками ввода через Text Input Sources (TIS).
/// TIS требует главного потока (иначе процесс падает), поэтому всё — `@MainActor`.
@MainActor
public enum InputSources {
    /// Раскладки, включённые в системе (то, что видно в меню ввода), в системном порядке.
    public static func enabled() -> [InputSource] {
        list(includeAllInstalled: false).compactMap(makeSource)
    }

    /// Текущая раскладка.
    public static func current() -> InputSource? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return makeSource(source)
    }

    /// Переключает раскладку. Возвращает `false`, если такой нет или переключение не удалось.
    @discardableResult
    public static func select(id: String) -> Bool {
        guard let source = tisSource(id: id, includeAllInstalled: false) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    /// Системный объект раскладки по идентификатору.
    /// `includeAllInstalled: true` находит и не включённые пользователем раскладки (нужно тестам).
    static func tisSource(id: String, includeAllInstalled: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue()
                as? [TISInputSource] else { return nil }
        return list.first
    }

    private static func list(includeAllInstalled: Bool) -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        return TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    static func makeSource(_ source: TISInputSource) -> InputSource? {
        guard let id: String = property(source, kTISPropertyInputSourceID) else { return nil }
        let name: String = property(source, kTISPropertyLocalizedName) ?? id
        let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
        return InputSource(id: id, name: name, languages: languages)
    }

    static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
}
