import SwiftUI
import SwitchyCore

/// Окно настроек Switchy.
struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        TabView {
            ConversionTab(store: store)
                .tabItem { Label("Перевод", systemImage: "character.cursor.ibeam") }
            LayoutsTab(store: store)
                .tabItem { Label("Раскладки", systemImage: "keyboard") }
            WindowsTab(store: store)
                .tabItem { Label("Окна", systemImage: "macwindow.on.rectangle") }
            GeneralTab()
                .tabItem { Label("Основные", systemImage: "gearshape") }
        }
        // Формы прокручиваются и не имеют собственной высоты — размер задаём явно.
        .frame(width: 600, height: 600)
        .padding(.vertical, 8)
    }
}

/// Предупреждение для хоткея: дубликат внутри Switchy или известное системное сочетание.
@MainActor
private func warning(for hotkey: Hotkey?, in settings: AppSettings) -> String? {
    guard let hotkey else { return nil }
    if settings.duplicateHotkeys().contains(hotkey) {
        return "Этот хоткей уже назначен на другое действие Switchy."
    }
    return KeyNames.systemConflict(hotkey)
}

// MARK: - Перевод

private struct ConversionTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Хоткей перевода") {
                    HotkeyField(hotkey: $store.settings.convertHotkey,
                                warning: warning(for: store.settings.convertHotkey, in: store.settings))
                }
                Text("Переводит только что набранный текст, а если ничего не набрано — выделенный.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Режим", selection: $store.settings.smartMode) {
                    Text("Умный").tag(true)
                    Text("Просто по кругу").tag(false)
                }
                .pickerStyle(.segmented)
                Text(store.settings.smartMode
                     ? "Первое нажатие само выбирает самую вероятную раскладку (проверка орфографии и распознавание языка macOS, без сети). Следующие нажатия — по кругу, исходная раскладка последней."
                     : "Каждое нажатие — следующая раскладка по кругу, исходная последней.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Что переводить из набранного", selection: $store.settings.fragmentMode) {
                    Text("Всё с последнего клика, Enter, ⌫, стрелок, смены раскладки").tag(FragmentMode.all)
                    Text("Последнее слово").tag(FragmentMode.lastWord)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Раскладки

private struct LayoutsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var enabled: [InputSource] = InputSources.enabled()

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(orderedSources, id: \.id) { source in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Toggle(isOn: includedBinding(source.id)) {
                                Text("\(source.shortCode)  \(source.name)")
                            }
                        }
                    }
                    .onMove(perform: move)
                }
                .frame(minHeight: CGFloat(max(orderedSources.count, 2)) * 28 + 8)
            } header: {
                Text("Порядок перевода по кругу")
            } footer: {
                Text("Перетащите, чтобы изменить порядок. Снятая галочка — раскладка не участвует в переводе по кругу (прямой хоткей для неё работает).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(enabled, id: \.id) { source in
                    LabeledContent("\(source.shortCode)  \(source.name)") {
                        VStack(alignment: .trailing, spacing: 6) {
                            HotkeyField(hotkey: bindingHotkey(source.id, \.primary),
                                        warning: warning(for: binding(source.id).primary, in: store.settings))
                            HotkeyField(hotkey: bindingHotkey(source.id, \.secondary),
                                        warning: warning(for: binding(source.id).secondary, in: store.settings))
                        }
                    }
                }
                Toggle("Заодно переводить только что набранное в эту раскладку", isOn: $store.settings.directHotkeysConvert)
            } header: {
                Text("Прямые хоткеи раскладок")
            } footer: {
                Text("У каждой раскладки — основной и дополнительный хоткей (например, ⌃⌥2 и F14).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { enabled = InputSources.enabled() }
    }

    private var orderedSources: [InputSource] {
        let byID = Dictionary(uniqueKeysWithValues: enabled.map { ($0.id, $0) })
        return store.settings.orderedLayouts(enabled: enabled.map(\.id)).compactMap { byID[$0] }
    }

    private func move(from: IndexSet, to: Int) {
        var order = orderedSources.map(\.id)
        order.move(fromOffsets: from, toOffset: to)
        store.settings.cycleOrder = order
    }

    private func includedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !store.settings.cycleExcluded.contains(id) },
            set: { included in
                if included { store.settings.cycleExcluded.remove(id) } else { store.settings.cycleExcluded.insert(id) }
            }
        )
    }

    private func binding(_ id: String) -> LayoutBinding {
        store.settings.layoutBindings.first { $0.layoutID == id } ?? LayoutBinding(layoutID: id)
    }

    private func bindingHotkey(_ id: String, _ keyPath: WritableKeyPath<LayoutBinding, Hotkey?>) -> Binding<Hotkey?> {
        Binding(
            get: { binding(id)[keyPath: keyPath] },
            set: { newValue in
                if let index = store.settings.layoutBindings.firstIndex(where: { $0.layoutID == id }) {
                    store.settings.layoutBindings[index][keyPath: keyPath] = newValue
                } else {
                    var entry = LayoutBinding(layoutID: id)
                    entry[keyPath: keyPath] = newValue
                    store.settings.layoutBindings.append(entry)
                }
            }
        )
    }
}

// MARK: - Окна

private struct WindowsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var enabled: [InputSource] = InputSources.enabled()

    var body: some View {
        Form {
            Section {
                Toggle("Помнить раскладку для каждого окна", isOn: $store.settings.windowMemoryEnabled)
                Text("При переходе в окно включается раскладка, которая была в нём последней — в том числе после переключений Switchy.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Новое окно") {
                Picker("Раскладка в новом окне", selection: $store.settings.newWindowPolicy) {
                    Text("Оставлять текущую").tag(NewWindowPolicy.keepCurrent)
                    Text("Всегда включать…").tag(NewWindowPolicy.fixed)
                }
                if store.settings.newWindowPolicy == .fixed {
                    Picker("Раскладка", selection: newWindowLayout) {
                        ForEach(enabled, id: \.id) { source in
                            Text("\(source.shortCode)  \(source.name)").tag(source.id)
                        }
                    }
                }
            }
            .disabled(!store.settings.windowMemoryEnabled)

            if WindowLayoutController.systemPerDocumentSwitchingEnabled {
                Section {
                    Label("Включена системная опция «Автоматически переключаться на источник ввода документа». Она спорит со Switchy — раскладка может мигать при переходе между окнами.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Системные настройки → Клавиатура → Источники ввода → Изменить… → снимите галочку.")
                        .font(.caption)
                    Button("Открыть настройки клавиатуры") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { enabled = InputSources.enabled() }
    }

    private var newWindowLayout: Binding<String> {
        Binding(
            get: { store.settings.newWindowLayout ?? store.cycle.first ?? enabled.first?.id ?? "" },
            set: { store.settings.newWindowLayout = $0 }
        )
    }
}

// MARK: - Основные

private struct GeneralTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibility = Permissions.accessibility
    @State private var inputMonitoring = Permissions.inputMonitoring

    var body: some View {
        Form {
            Section {
                Toggle("Запускать Switchy при входе в систему", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }

            Section("Права доступа") {
                permissionRow("Универсальный доступ", granted: accessibility, open: Permissions.openAccessibilitySettings)
                permissionRow("Мониторинг ввода", granted: inputMonitoring, open: Permissions.openInputMonitoringSettings)
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                Link("github.com/hdd1/Switchy", destination: URL(string: "https://github.com/hdd1/Switchy")!)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            accessibility = Permissions.accessibility
            inputMonitoring = Permissions.inputMonitoring
        }
    }

    private func permissionRow(_ title: String, granted: Bool, open: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Выдано", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Открыть настройки…", action: open)
            }
        }
    }
}
