import Foundation

/// Хоткеи одной раскладки: основной и дополнительный (например, ⌃⌥2 и F14).
public struct LayoutBinding: Codable, Hashable, Sendable {
    public var layoutID: String
    public var primary: Hotkey?
    public var secondary: Hotkey?

    public init(layoutID: String, primary: Hotkey? = nil, secondary: Hotkey? = nil) {
        self.layoutID = layoutID
        self.primary = primary
        self.secondary = secondary
    }
}

/// Все настройки Switchy. Хранятся в UserDefaults как JSON.
/// Декодирование терпимо к отсутствующим полям — новые настройки получают значения по умолчанию.
public struct AppSettings: Codable, Equatable, Sendable {
    // Перевод
    public var convertHotkey: Hotkey? = .modifierTap(.leftOption)
    public var smartMode = true
    public var fragmentMode: FragmentMode = .all
    /// Пауза в наборе (секунды), после которой набранное забывается; 0 — никогда.
    public var idleResetSeconds: Double = 5

    // Раскладки
    /// Порядок круга (идентификаторы раскладок). Новые включённые раскладки добавляются в конец.
    public var cycleOrder: [String] = []
    /// Раскладки, не участвующие в переводе по кругу.
    public var cycleExcluded: Set<String> = []
    public var layoutBindings: [LayoutBinding] = []
    /// Прямые хоткеи заодно переводят только что набранное (по умолчанию выключено:
    /// от «переключить раскладку» обычно не ждут, что изменится уже набранный текст).
    public var directHotkeysConvert = false

    // Окна
    public var windowMemoryEnabled = true
    public var newWindowPolicy: NewWindowPolicy = .keepCurrent
    /// Раскладка для новых окон при политике `.fixed` (`nil` — первая в круге).
    public var newWindowLayout: String?

    // Буфер обмена
    public var clipboardEnabled = true
    public var clipboardHotkey: Hotkey? = .key(keyCode: 9, modifiers: [.command, .shift]) // ⇧⌘V
    /// Сколько элементов хранить.
    public var clipboardCapacity = 50
    /// Хранить историю на диске (переживает перезапуск).
    public var clipboardPersist = true

    // Исключения (bundle id приложений)
    /// Где не переводить текст (прямые хоткеи там только переключают раскладку).
    public var excludedConversionApps: [String] = []
    /// Откуда не сохранять скопированное в историю.
    public var excludedClipboardApps: [String] = []

    public init() {}

    /// Настройки по умолчанию для данного набора раскладок: ⌃⌥1, ⌃⌥2, … по порядку.
    public static func defaults(enabledLayouts: [String]) -> AppSettings {
        var settings = AppSettings()
        settings.cycleOrder = enabledLayouts
        // Коды клавиш цифр 1…9 основного ряда.
        let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        settings.layoutBindings = zip(enabledLayouts, digitKeyCodes).map { id, code in
            LayoutBinding(layoutID: id, primary: .key(keyCode: code, modifiers: [.control, .option]))
        }
        return settings
    }

    /// Итоговый круг: сохранённый порядок ∩ включённые в системе, плюс новые включённые в конце,
    /// без исключённых. Если исключено всё — все включённые.
    public func cycle(enabled: [String]) -> [String] {
        let enabledSet = Set(enabled)
        var order = cycleOrder.filter { enabledSet.contains($0) }
        order += enabled.filter { !order.contains($0) }
        let included = order.filter { !cycleExcluded.contains($0) }
        return included.isEmpty ? order : included
    }

    /// Раскладки в порядке для отображения (включая исключённые).
    public func orderedLayouts(enabled: [String]) -> [String] {
        let enabledSet = Set(enabled)
        var order = cycleOrder.filter { enabledSet.contains($0) }
        order += enabled.filter { !order.contains($0) }
        return order
    }

    /// Привязки для движка хоткеев.
    public func hotkeyBindings(includeClipboard: Bool) -> [Hotkey: HotkeyAction] {
        var result: [Hotkey: HotkeyAction] = [:]
        for binding in layoutBindings {
            for hotkey in [binding.primary, binding.secondary].compactMap({ $0 }) {
                result[hotkey] = .selectLayout(id: binding.layoutID)
            }
        }
        if includeClipboard, clipboardEnabled, let hotkey = clipboardHotkey {
            result[hotkey] = .clipboardHistory
        }
        if let hotkey = convertHotkey {
            result[hotkey] = .convert
        }
        return result
    }

    /// Хоткеи, назначенные больше чем на одно действие.
    public func duplicateHotkeys() -> Set<Hotkey> {
        var all: [Hotkey] = [convertHotkey, clipboardHotkey].compactMap { $0 }
        for binding in layoutBindings {
            all += [binding.primary, binding.secondary].compactMap { $0 }
        }
        var seen: Set<Hotkey> = []
        var duplicates: Set<Hotkey> = []
        for hotkey in all where !seen.insert(hotkey).inserted {
            duplicates.insert(hotkey)
        }
        return duplicates
    }

    // MARK: - Codable (терпимое к отсутствующим полям)

    private enum CodingKeys: String, CodingKey {
        case convertHotkey, smartMode, fragmentMode, idleResetSeconds
        case cycleOrder, cycleExcluded, layoutBindings, directHotkeysConvert
        case windowMemoryEnabled, newWindowPolicy, newWindowLayout
        case clipboardEnabled, clipboardHotkey, clipboardCapacity, clipboardPersist
        case excludedConversionApps, excludedClipboardApps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        // `decodeIfPresent` для Optional-полей не отличает «нет ключа» от null — оба значат «не задан»,
        // кроме случая, когда ключа нет вовсе: тогда берём значение по умолчанию.
        convertHotkey = c.contains(.convertHotkey) ? try c.decodeIfPresent(Hotkey.self, forKey: .convertHotkey) : d.convertHotkey
        smartMode = try c.decodeIfPresent(Bool.self, forKey: .smartMode) ?? d.smartMode
        fragmentMode = try c.decodeIfPresent(FragmentMode.self, forKey: .fragmentMode) ?? d.fragmentMode
        idleResetSeconds = try c.decodeIfPresent(Double.self, forKey: .idleResetSeconds) ?? d.idleResetSeconds
        cycleOrder = try c.decodeIfPresent([String].self, forKey: .cycleOrder) ?? d.cycleOrder
        cycleExcluded = try c.decodeIfPresent(Set<String>.self, forKey: .cycleExcluded) ?? d.cycleExcluded
        layoutBindings = try c.decodeIfPresent([LayoutBinding].self, forKey: .layoutBindings) ?? d.layoutBindings
        directHotkeysConvert = try c.decodeIfPresent(Bool.self, forKey: .directHotkeysConvert) ?? d.directHotkeysConvert
        windowMemoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowMemoryEnabled) ?? d.windowMemoryEnabled
        newWindowPolicy = try c.decodeIfPresent(NewWindowPolicy.self, forKey: .newWindowPolicy) ?? d.newWindowPolicy
        newWindowLayout = try c.decodeIfPresent(String.self, forKey: .newWindowLayout)
        clipboardEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardEnabled) ?? d.clipboardEnabled
        clipboardHotkey = c.contains(.clipboardHotkey) ? try c.decodeIfPresent(Hotkey.self, forKey: .clipboardHotkey) : d.clipboardHotkey
        clipboardCapacity = try c.decodeIfPresent(Int.self, forKey: .clipboardCapacity) ?? d.clipboardCapacity
        clipboardPersist = try c.decodeIfPresent(Bool.self, forKey: .clipboardPersist) ?? d.clipboardPersist
        excludedConversionApps = try c.decodeIfPresent([String].self, forKey: .excludedConversionApps) ?? d.excludedConversionApps
        excludedClipboardApps = try c.decodeIfPresent([String].self, forKey: .excludedClipboardApps) ?? d.excludedClipboardApps
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Optional-хоткеи пишем явно (null = «не задан»), чтобы отличать от «ключа нет».
        try c.encode(convertHotkey, forKey: .convertHotkey)
        try c.encode(smartMode, forKey: .smartMode)
        try c.encode(fragmentMode, forKey: .fragmentMode)
        try c.encode(idleResetSeconds, forKey: .idleResetSeconds)
        try c.encode(cycleOrder, forKey: .cycleOrder)
        try c.encode(cycleExcluded, forKey: .cycleExcluded)
        try c.encode(layoutBindings, forKey: .layoutBindings)
        try c.encode(directHotkeysConvert, forKey: .directHotkeysConvert)
        try c.encode(windowMemoryEnabled, forKey: .windowMemoryEnabled)
        try c.encode(newWindowPolicy, forKey: .newWindowPolicy)
        try c.encodeIfPresent(newWindowLayout, forKey: .newWindowLayout)
        try c.encode(clipboardEnabled, forKey: .clipboardEnabled)
        try c.encode(clipboardHotkey, forKey: .clipboardHotkey)
        try c.encode(clipboardCapacity, forKey: .clipboardCapacity)
        try c.encode(clipboardPersist, forKey: .clipboardPersist)
        try c.encode(excludedConversionApps, forKey: .excludedConversionApps)
        try c.encode(excludedClipboardApps, forKey: .excludedClipboardApps)
    }
}
