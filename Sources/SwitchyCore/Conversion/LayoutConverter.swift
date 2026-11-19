import Foundation

/// Перевод текста между раскладками «как будто те же клавиши нажали в другой раскладке».
public enum LayoutConverter {
    /// Переводит текст, набранный в раскладке `from`, в раскладку `to`.
    /// Символы, которых нет в `from` (эмодзи, спецсимволы), остаются как есть.
    public static func convert(_ text: String, from: KeyboardLayout, to: KeyboardLayout) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            if let stroke = from.keyStroke(for: ch), let mapped = to.character(for: stroke) {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
