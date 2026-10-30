import SwiftUI
import AppKit

/// Config snippets users paste into their own CLI settings. Hubbub never writes these files.
enum ReplyHookConfig {
    static let hookTimeout = 60
    static let cliTimeout = 75

    static func claude(executable: String) -> String {
        json(["hooks": ["PermissionRequest": [["hooks": [[
            "type": "command", "command": executable, "args": ["--reply-hook", "claude", "--timeout", String(hookTimeout)],
            "timeout": cliTimeout,
        ] as [String: Any]]]]]])
    }

    static func copilot(executable: String) -> String {
        json(["version": 1, "hooks": ["permissionRequest": [[
            "type": "command", "exec": executable, "args": ["--reply-hook", "copilot", "--timeout", String(hookTimeout)],
            "timeoutSec": cliTimeout,
        ] as [String: Any]]]])
    }

    private static func json(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static var executable: String { Bundle.main.executablePath ?? "/Applications/Hubbub.app/Contents/MacOS/Hubbub" }
}

/// Settings → Alerts: opt-in switches for replying from Hubbub, with an explanation of what each does.
struct ReplySettingsView: View {
    @AppStorage(ReplyKey.hook) private var hook = false
    @AppStorage(ReplyKey.terminal) private var terminal = false
    @ObservedObject private var center = ReplyCenter.shared
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hubbub always shows an agent's question. These opt-in switches let you answer from here too; they only act when you press a button.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $terminal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Type replies into the session's terminal").font(.callout)
                    Text("Types your answer into the agent's tmux pane, iTerm2 or Terminal.app tab. macOS asks once for Automation permission.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)

            Toggle(isOn: $hook) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approve or deny through a permission hook").font(.callout)
                    Text("A hook you install yourself in Claude Code or Copilot CLI asks Hubbub over a private socket; after \(ReplyHookConfig.hookTimeout)s the CLI's own prompt appears. Hubbub never edits CLI settings.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch).controlSize(.small)

            if hook {
                HStack(spacing: 6) {
                    Circle().fill(center.socketActive ? Color.green : Color.red).frame(width: 7, height: 7)
                    Text(center.socketActive ? "Listening on a private local socket" : (center.serverError ?? "Not listening"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Button("Copy Claude Code hook") { copy(ReplyHookConfig.claude(executable: ReplyHookConfig.executable), "Claude Code") }
                    Button("Copy Copilot CLI hook") { copy(ReplyHookConfig.copilot(executable: ReplyHookConfig.executable), "Copilot CLI") }
                }.controlSize(.small)
                Text(copied.map { "\($0) hook copied. Paste it into your CLI's hooks settings (see docs/REPLY.md)." } ?? "Claude Code: add to ~/.claude/settings.json. Copilot CLI: save as ~/.copilot/hooks/hubbub.json. Details in docs/REPLY.md.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: hook) { _ in center.applySettings() }
    }

    private func copy(_ s: String, _ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        copied = name
    }
}
