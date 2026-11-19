import SwiftUI
import SwitchyCore

/// Окно настроек Switchy.
struct SettingsView: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        TabView {
            ConversionTab(store: store)
                .tabItem { Label("Conversion", systemImage: "character.cursor.ibeam") }
            LayoutsTab(store: store)
                .tabItem { Label("Layouts", systemImage: "keyboard") }
            WindowsTab(store: store)
                .tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }
            ClipboardTab(store: store)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            ExclusionsTab(store: store)
                .tabItem { Label("Exclusions", systemImage: "nosign") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
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
        return String(localized: "This hotkey is already assigned to another Switchy action.")
    }
    return KeyNames.systemConflict(hotkey)
}

// MARK: - Перевод

private struct ConversionTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Conversion hotkey") {
                    HotkeyField(hotkey: $store.settings.convertHotkey,
                                warning: warning(for: store.settings.convertHotkey, in: store.settings))
                }
                Text("Converts the text you've just typed, or the selected text if nothing was typed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Mode", selection: $store.settings.smartMode) {
                    Text("Smart").tag(true)
                    Text("Simple cycle").tag(false)
                }
                .pickerStyle(.segmented)
                Text(LocalizedStringKey(store.settings.smartMode
                     ? "The first press picks the most likely layout (macOS spell checking and language recognition, offline). Further presses cycle through the layouts, the original one last."
                     : "Each press switches to the next layout in the cycle, the original one last."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("What to convert", selection: $store.settings.fragmentMode) {
                    Text("Everything since the last click, Enter, ⌫, arrow key or layout switch").tag(FragmentMode.all)
                    Text("Last word").tag(FragmentMode.lastWord)
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
                                Text(source.menuLabel)
                            }
                        }
                    }
                    .onMove(perform: move)
                }
                .frame(minHeight: CGFloat(max(orderedSources.count, 2)) * 28 + 8)
            } header: {
                Text("Cycle order")
            } footer: {
                Text("Drag to reorder. Unchecked layouts are skipped when cycling (their direct hotkey still works).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(enabled, id: \.id) { source in
                    LabeledContent(source.menuLabel) {
                        VStack(alignment: .trailing, spacing: 6) {
                            HotkeyField(hotkey: bindingHotkey(source.id, \.primary),
                                        warning: warning(for: binding(source.id).primary, in: store.settings))
                            HotkeyField(hotkey: bindingHotkey(source.id, \.secondary),
                                        warning: warning(for: binding(source.id).secondary, in: store.settings))
                        }
                    }
                }
                Toggle("Also convert just-typed text into this layout", isOn: $store.settings.directHotkeysConvert)
            } header: {
                Text("Direct layout hotkeys")
            } footer: {
                Text("Each layout has a primary and a secondary hotkey (e.g. ⌃⌥2 and F14).")
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
                Toggle("Remember the layout for each window", isOn: $store.settings.windowMemoryEnabled)
                Text("When you switch to a window, the layout last used in it is restored — including switches made by Switchy.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("New window") {
                Picker("Layout in a new window", selection: $store.settings.newWindowPolicy) {
                    Text("Keep current").tag(NewWindowPolicy.keepCurrent)
                    Text("Always switch to…").tag(NewWindowPolicy.fixed)
                }
                if store.settings.newWindowPolicy == .fixed {
                    Picker("Layout", selection: newWindowLayout) {
                        ForEach(enabled, id: \.id) { source in
                            Text(source.menuLabel).tag(source.id)
                        }
                    }
                }
            }
            .disabled(!store.settings.windowMemoryEnabled)

            if WindowLayoutController.systemPerDocumentSwitchingEnabled {
                Section {
                    Label("The system option “Automatically switch to a document’s input source” is on. It conflicts with Switchy — the layout may flicker when switching windows.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("System Settings → Keyboard → Input Sources → Edit… → turn it off.")
                        .font(.caption)
                    Button("Open Keyboard Settings") {
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

// MARK: - Буфер обмена

private struct ClipboardTab: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var clipboard = ClipboardStore.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep clipboard history", isOn: $store.settings.clipboardEnabled)
                Text("Text only. Passwords and other content marked as sensitive (1Password, Bitwarden, Keychain…) are never saved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("History panel") {
                    HotkeyField(hotkey: $store.settings.clipboardHotkey,
                                warning: warning(for: store.settings.clipboardHotkey, in: store.settings))
                }
                Picker("Items to keep", selection: $store.settings.clipboardCapacity) {
                    ForEach([20, 50, 100, 200, 500], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Remember after restart", isOn: $store.settings.clipboardPersist)
                Text(LocalizedStringKey(store.settings.clipboardPersist
                     ? "History is stored on disk in ~/Library/Application Support/Switchy (accessible only to you)."
                     : "History is kept in memory only and is lost when Switchy quits."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.settings.clipboardEnabled)

            Section {
                LabeledContent("In history: \(clipboard.history.items.count)") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(clipboard.history.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the entire clipboard history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { clipboard.clear() }
        }
    }
}

// MARK: - Исключения

private struct ExclusionsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                AppListEditor(bundleIDs: $store.settings.excludedConversionApps)
            } header: {
                Text("Don't convert text")
            } footer: {
                Text("The conversion hotkey is disabled and typing isn't tracked there. Direct layout hotkeys only switch the layout. Useful for terminals, games, remote desktop.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                AppListEditor(bundleIDs: $store.settings.excludedClipboardApps)
            } header: {
                Text("Don't save clipboard")
            } footer: {
                Text("Text copied in these apps is not added to history (e.g. a banking app or a password manager that doesn't mark its data as sensitive).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Основные

private struct GeneralTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibility = Permissions.accessibility
    @State private var inputMonitoring = Permissions.inputMonitoring
    @State private var language = AppLanguage.selected
    @State private var askRestart = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag("")
                    ForEach(AppLanguage.options, id: \.code) { option in
                        Text(verbatim: option.name).tag(option.code)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.select(newValue)
                    askRestart = true
                }
                Toggle("Launch Switchy at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }

            Section("Permissions") {
                permissionRow("Accessibility", granted: accessibility, open: Permissions.openAccessibilitySettings)
                permissionRow("Input Monitoring", granted: inputMonitoring, open: Permissions.openInputMonitoringSettings)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                Link("github.com/hdd1/Switchy", destination: URL(string: "https://github.com/hdd1/Switchy")!)
            }
        }
        .formStyle(.grouped)
        .alert("Restart Switchy to apply the new language.", isPresented: $askRestart) {
            Button("Restart Now") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        }
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            accessibility = Permissions.accessibility
            inputMonitoring = Permissions.inputMonitoring
        }
    }

    private func permissionRow(_ title: LocalizedStringKey, granted: Bool, open: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Settings…", action: open)
            }
        }
    }
}
