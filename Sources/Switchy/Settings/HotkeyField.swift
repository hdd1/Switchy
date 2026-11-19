import AppKit
import SwiftUI
import SwitchyCore

/// Запись хоткея: сочетание клавиш, тап или двойной тап модификатора.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var hint = "Нажмите сочетание или тапните модификатор…"

    private var monitor: Any?
    private var completion: ((Hotkey) -> Void)?
    private var pendingTap: (key: ModifierKey, start: TimeInterval)?
    private var lastTap: (key: ModifierKey, time: TimeInterval)?
    private var singleTapTask: Task<Void, Never>?

    private static let tapMaxDuration: TimeInterval = 0.4
    private static let doubleTapInterval: TimeInterval = 0.4

    func start(completion: @escaping (Hotkey) -> Void) {
        stop()
        self.completion = completion
        isRecording = true
        hint = "Нажмите сочетание или тапните модификатор…"
        SettingsStore.shared.isRecordingHotkey = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated { self?.handle(event) }
            return nil // событие поглощаем — это запись, а не ввод
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        singleTapTask?.cancel()
        singleTapTask = nil
        pendingTap = nil
        lastTap = nil
        isRecording = false
        SettingsStore.shared.isRecordingHotkey = false
    }

    private func handle(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .keyDown:
            singleTapTask?.cancel()
            let modifiers = Modifiers(nsFlags: event.modifierFlags)
            if event.keyCode == 53, modifiers.isEmpty { // Esc — отмена
                stop()
                return
            }
            finish(.key(keyCode: event.keyCode, modifiers: modifiers))

        case .flagsChanged:
            guard let key = ModifierKey(keyCode: event.keyCode) else { return }
            let isDown = (UInt64(event.modifierFlags.rawValue) & key.deviceMask) != 0
            let modifiers = Modifiers(nsFlags: event.modifierFlags)
            if isDown {
                pendingTap = modifiers == key.modifier ? (key, now) : nil
                return
            }
            guard let pending = pendingTap, pending.key == key,
                  now - pending.start <= Self.tapMaxDuration, modifiers.isEmpty else {
                pendingTap = nil
                return
            }
            pendingTap = nil
            if let last = lastTap, last.key == key, now - last.time <= Self.doubleTapInterval {
                singleTapTask?.cancel()
                finish(.modifierDoubleTap(key))
                return
            }
            lastTap = (key, now)
            hint = "Тап: \(key.displayName)… (ещё раз — двойной тап)"
            singleTapTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.doubleTapInterval + 0.05))
                guard !Task.isCancelled else { return }
                self?.finish(.modifierTap(key))
            }

        default:
            break
        }
    }

    private func finish(_ hotkey: Hotkey) {
        let completion = self.completion
        stop()
        completion?(hotkey)
    }
}

/// Поле хоткея: кнопка записи, меню с F13–F20 (если нет такой клавиатуры под рукой), сброс.
struct HotkeyField: View {
    @Binding var hotkey: Hotkey?
    var warning: String?

    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        recorder.start { hotkey = $0 }
                    }
                } label: {
                    Text(label)
                        .foregroundStyle(recorder.isRecording ? Color.accentColor : (hotkey == nil ? .secondary : .primary))
                        .frame(minWidth: 190)
                }

                Menu {
                    ForEach(KeyNames.functionKeys.suffix(8), id: \.keyCode) { key in // F13–F20
                        Button(key.name) { hotkey = .key(keyCode: key.keyCode, modifiers: []) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Выбрать F13–F20 без нажатия")

                if hotkey != nil {
                    Button {
                        hotkey = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Убрать хоткей")
                }
            }
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var label: String {
        if recorder.isRecording { return recorder.hint }
        return hotkey.map(KeyNames.describe) ?? "Не задан"
    }
}
