import SwiftUI

/// Small provider icon used on session chips.
struct ProviderBadge: View {
    let provider: String
    var body: some View {
        ProviderLogo(id: provider, symbol: ProviderRegistry.shared.symbol(for: provider), size: 10)
            .foregroundStyle(.secondary)
            .help(ProviderRegistry.shared.name(for: provider))
    }
}

/// Settings section: one toggle per provider with detection status and live session count.
struct ProviderSettingsView: View {
    @ObservedObject var registry = ProviderRegistry.shared
    let sessions: [SessionInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(registry.all, id: \.id) { p in
                let detected = p.isAvailable
                let count = sessions.filter { $0.provider == p.id }.count
                let on = registry.isEnabled(p.id)
                HStack(spacing: 10) {
                    ProviderLogo(id: p.id, symbol: p.symbol, size: 16).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(.caption)
                        Text(p.dataHint).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(detected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                        Text(!detected ? "Not found" : (on ? "\(count) session\(count == 1 ? "" : "s")" : "Found"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Toggle(p.displayName, isOn: Binding(get: { on }, set: { registry.setEnabled(p.id, $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if on && p.id != "copilot" && p.id != "crew" { ProviderQuotaRow(id: p.id) }
            }
        }
    }
}

/// Shared token formatting kept for callers that still use the old name; forwards to `Fmt`.
enum ProviderUsageStrip {
    static func fmt(_ n: Int) -> String { Fmt.tokens(n) }
}

extension SessionInfo {
    /// Shell command that resumes this session in its CLI; nil for providers without one.
    var resumeCommand: String? {
        switch provider {
        case "copilot": "copilot --resume \(id)"
        case "claude": "claude --resume \(id)"
        case "codex": "codex resume \(id)"
        default: nil
        }
    }
}
