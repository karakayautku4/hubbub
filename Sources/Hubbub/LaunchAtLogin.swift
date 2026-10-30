import SwiftUI
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published var error: String?

    static var isBundled: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        error = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}

struct StartupSettingsView: View {
    @StateObject private var login = LaunchAtLogin()
    @StateObject private var hotkey = HotkeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                .disabled(!LaunchAtLogin.isBundled)
            if !LaunchAtLogin.isBundled {
                Text("Available only when running from Hubbub.app.").font(.caption2).foregroundStyle(.secondary)
            } else if login.status == .requiresApproval {
                Text("Approve Hubbub in System Settings › General › Login Items.").font(.caption2).foregroundStyle(.secondary)
            }
            if let e = login.error { Text(e).font(.caption2).foregroundStyle(.red) }

            HStack {
                Toggle("Global hotkey", isOn: $hotkey.enabled)
                Picker("", selection: $hotkey.presetRaw) {
                    ForEach(HotkeyPreset.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 100).disabled(!hotkey.enabled)
                .accessibilityLabel("Global hotkey shortcut")
            }
            if let e = hotkey.error { Text(e).font(.caption2).foregroundStyle(.red) }
        }
        .onAppear { login.refresh() }
    }
}
