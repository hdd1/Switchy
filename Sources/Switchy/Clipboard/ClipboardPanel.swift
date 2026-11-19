import AppKit
import Combine
import SwiftUI
import SwitchyCore

/// Плавающая панель, которая принимает ввод, не активируя Switchy (как Spotlight):
/// приложение, куда вставляем, остаётся активным.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Состояние панели: поиск и выбранная строка.
@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published var query = "" {
        didSet { selection = 0 }
    }
    @Published var selection = 0

    let store = ClipboardStore.shared

    var items: [ClipboardItem] { store.history.filtered(query) }

    func moveSelection(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }
}

/// Показ/скрытие панели и обработка клавиш.
@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private let model = ClipboardPanelModel()
    private var keyMonitor: Any?

    private static let size = NSSize(width: 460, height: 380)

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.query = ""
        model.selection = 0

        panel.setFrameOrigin(origin(for: Self.size))
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    // MARK: - Выбор

    func choose(_ item: ClipboardItem) {
        close()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        // Даём панели уйти и фокусу вернуться в исходное поле, затем вставляем.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            EventPoster.postKey(9, flags: .maskCommand) // ⌘V
        }
    }

    private func chooseSelected() {
        let items = model.items
        guard items.indices.contains(model.selection) else { return }
        choose(items[model.selection])
    }

    // MARK: - Клавиши

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    /// `true` — событие обработано; иначе оно уходит дальше (в поле поиска).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: // Esc
            close()
            return true
        case 125: // ↓
            model.moveSelection(1)
            return true
        case 126: // ↑
            model.moveSelection(-1)
            return true
        case 36, 76: // Return, Enter
            chooseSelected()
            return true
        case 51 where modifiers.contains(.command): // ⌘⌫ — удалить из истории
            let items = model.items
            if items.indices.contains(model.selection) {
                model.store.remove(id: items[model.selection].id)
                model.selection = min(model.selection, max(model.items.count - 1, 0))
            }
            return true
        default:
            break
        }

        // Цифры 1–9 при пустом поиске — быстрый выбор.
        if model.query.isEmpty, modifiers.subtracting(.numericPad).isEmpty,
           let chars = event.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit) {
            let items = model.items
            if items.indices.contains(digit - 1) { choose(items[digit - 1]) }
            return true
        }
        return false
    }

    // MARK: - Окно

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(model: model) { [weak self] item in
            self?.choose(item)
        })
        return panel
    }

    /// Под курсором (или указателем мыши), в пределах видимой области экрана.
    private func origin(for size: NSSize) -> NSPoint {
        let anchor = CaretLocator.anchorPoint()
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height - 6)
        if origin.y < visible.minY { origin.y = anchor.y + 24 } // не помещается снизу — над курсором
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return origin
    }

    // Клик мимо панели — закрываем.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

// MARK: - Вид

struct ClipboardPanelView: View {
    @ObservedObject var model: ClipboardPanelModel
    @ObservedObject private var store = ClipboardStore.shared
    let onChoose: (ClipboardItem) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = store.history.filtered(model.query)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").foregroundStyle(.secondary)
                TextField("Поиск в истории буфера", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            if items.isEmpty {
                Spacer()
                Text(store.history.items.isEmpty ? "История пуста — скопируйте что-нибудь" : "Ничего не найдено")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(item: item, index: index, selected: index == model.selection)
                                    .id(item.id)
                                    .onTapGesture { onChoose(item) }
                                    .onHover { if $0 { model.selection = index } }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) { _, newValue in
                        if items.indices.contains(newValue) { proxy.scrollTo(items[newValue].id) }
                    }
                }
            }

            Divider()
            Text("↩ вставить · 1–9 быстрый выбор · ⌘⌫ удалить · esc закрыть")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
        }
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            appIcon
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview())
                    .lineLimit(1)
                    .truncationMode(.tail)
                if item.lineCount > 1 {
                    Text("+ ещё \(item.lineCount - 1) стр.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var appIcon: some View {
        if let id = item.sourceBundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
        }
    }
}
