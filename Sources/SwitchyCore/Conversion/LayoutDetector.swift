import Foundation

/// Определяет, в какой раскладке набран готовый текст (для перевода выделения).
public enum LayoutDetector {
    /// Раскладка, которой можно набрать больше всего букв текста.
    /// При равенстве — `preferred` (обычно текущая системная), иначе первая по порядку `layouts`.
    /// `nil`, если в тексте нет букв ни одной раскладки.
    @MainActor
    public static func sourceLayout(of text: String, among layouts: [KeyboardLayout], preferred: String?) -> KeyboardLayout? {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }

        let scored = layouts.map { layout in
            (layout, letters.filter { layout.keyStroke(for: $0) != nil }.count)
        }
        guard let best = scored.map(\.1).max(), best > 0 else { return nil }
        let top = scored.filter { $0.1 == best }.map(\.0)
        return top.first { $0.source.id == preferred } ?? top.first
    }
}
