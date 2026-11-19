import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Редактор списка приложений (bundle id): добавить из запущенных или выбрать .app, удалить.
struct AppListEditor: View {
    @Binding var bundleIDs: [String]
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(bundleIDs, id: \.self) { id in
                    HStack(spacing: 8) {
                        Image(nsImage: Self.icon(for: id))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(Self.name(for: id))
                        Spacer()
                        Text(id).font(.caption).foregroundStyle(.tertiary)
                    }
                    .tag(id)
                }
            }
            .frame(minHeight: 90)
            .overlay {
                if bundleIDs.isEmpty {
                    Text("No apps").foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            add(app.bundleIdentifier)
                        }
                    }
                    Divider()
                    Button("Choose in Applications folder…") { chooseApp() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    if let selection { bundleIDs.removeAll { $0 == selection } }
                    selection = nil
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
            }
            .padding(.top, 6)
        }
    }

    /// Запущенные обычные приложения, которых ещё нет в списке.
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !bundleIDs.contains($0.bundleIdentifier!) && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ id: String?) {
        guard let id, !bundleIDs.contains(id) else { return }
        bundleIDs.append(id)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            add(Bundle(url: url)?.bundleIdentifier)
        }
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}
