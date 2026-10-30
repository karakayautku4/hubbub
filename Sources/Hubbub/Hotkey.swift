import SwiftUI
import Carbon.HIToolbox

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case optCmdC, ctrlOptC, shiftCmdC, optSpace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .optCmdC: "⌥⌘C"
        case .ctrlOptC: "⌃⌥C"
        case .shiftCmdC: "⇧⌘C"
        case .optSpace: "⌥Space"
        }
    }
    var keyCode: UInt32 { self == .optSpace ? UInt32(kVK_Space) : UInt32(kVK_ANSI_C) }
    var modifiers: UInt32 {
        switch self {
        case .optCmdC: UInt32(optionKey | cmdKey)
        case .ctrlOptC: UInt32(controlKey | optionKey)
        case .shiftCmdC: UInt32(shiftKey | cmdKey)
        case .optSpace: UInt32(optionKey)
        }
    }
}

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "hotkeyEnabled"); apply() } }
    @Published var presetRaw: String { didSet { UserDefaults.standard.set(presetRaw, forKey: "hotkeyPreset"); apply() } }
    /// Registration failure text (nil when OK). Observed by ContentView for a toast; keep the name `error` stable.
    @Published var error: String?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "hotkeyEnabled") as? Bool ?? true
        presetRaw = d.string(forKey: "hotkeyPreset") ?? HotkeyPreset.optCmdC.rawValue
    }

    func start() {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotkeyManager.togglePopover() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        apply()
    }

    private func apply() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        error = nil
        guard enabled, handler != nil else { return }
        let p = HotkeyPreset(rawValue: presetRaw) ?? .optCmdC
        let id = EventHotKeyID(signature: OSType(0x4343_5257), id: 1)
        let st = RegisterEventHotKey(p.keyCode, p.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if st != noErr {
            error = st == OSStatus(eventHotKeyExistsErr)
                ? "\(p.title) is already used by another app or a second Hubbub instance."
                : "Could not register \(p.title) (error \(st))."
        }
    }

    /// Runs an open/save panel modally. The popover floats below modal panels, but the focus change must not dismiss it.
    static func runPanel(_ p: NSSavePanel) -> NSApplication.ModalResponse {
        SurfaceController.shared.withoutDismissal {
            NSApp.activate(ignoringOtherApps: true)
            return p.runModal()
        }
    }

    /// Hotkey: toggle the popover (or focus/hide the expanded window).
    static func togglePopover() { SurfaceController.shared.toggle() }

    /// Open (never close) the popover, e.g. from a notification click.
    static func openPopover() { SurfaceController.shared.open() }
}
