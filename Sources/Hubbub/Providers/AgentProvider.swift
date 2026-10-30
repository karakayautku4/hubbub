import Foundation

/// A source of agent sessions (Copilot CLI, Claude Code, Codex, ...).
/// Implementations must be cheap, never crash on missing/malformed data and be safe to call off the main thread.
protocol AgentProvider: Sendable {
    /// Stable lowercase id, stored in `SessionInfo.provider` and in UserDefaults keys.
    var id: String { get }
    var displayName: String { get }
    /// SF Symbol used for badges.
    var symbol: String { get }
    /// Short human readable location of the data, shown in settings.
    var dataHint: String { get }
    /// True when the provider's local data directory exists.
    var isAvailable: Bool { get }
    func scan() -> [SessionInfo]
    /// Optional remote quota. Providers without a real quota API return nil (the UI shows token totals instead).
    func quota() async -> Quota?
}

extension AgentProvider {
    func quota() async -> Quota? { nil }
}

final class ProviderRegistry: ObservableObject, @unchecked Sendable {
    static let shared = ProviderRegistry()

    let all: [AgentProvider] = [CopilotProvider(), ClaudeCodeProvider(), CodexProvider(), GeminiProvider(), CursorProvider(), GrokProvider(), CrewEventsProvider()]

    private func key(_ id: String) -> String { "provider.enabled.\(id)" }

    func provider(_ id: String) -> AgentProvider? { all.first { $0.id == id } }

    /// Unset means "auto": enabled as soon as the provider's data exists.
    func isEnabled(_ id: String) -> Bool {
        if let v = UserDefaults.standard.object(forKey: key(id)) as? Bool { return v }
        return provider(id)?.isAvailable ?? false
    }

    func setEnabled(_ id: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: key(id))
        DispatchQueue.main.async {
            self.objectWillChange.send()
            // Sessions of the toggled provider appear/disappear now instead of at the next poll.
            MainActor.assumeIsolated {
                AppModel.shared.monitor.refresh()
                if on { ProviderQuotaService.shared.refresh(id) }
            }
        }
    }

    var enabled: [AgentProvider] { all.filter { isEnabled($0.id) } }

    func symbol(for id: String) -> String { provider(id)?.symbol ?? "questionmark.circle" }
    func name(for id: String) -> String { provider(id)?.displayName ?? id }

    /// Merges the sessions of all enabled providers, newest first.
    func scanEnabled() -> [SessionInfo] {
        var out: [SessionInfo] = []
        for p in enabled { out += p.scan() }
        out.sort { $0.lastEvent > $1.lastEvent }
        return Array(out.prefix(24))
    }
}

struct CopilotProvider: AgentProvider {
    let id = "copilot"
    let displayName = "GitHub Copilot CLI"
    let symbol = "airplane"
    let dataHint = "~/.copilot/session-state"
    var isAvailable: Bool { ProviderKit.dirExists(".copilot/session-state") }
    // Quota is owned by QuotaService (token handling, caching, back-off), so nothing to do here.
    func scan() -> [SessionInfo] { SessionMonitor.scanCopilot() }
}
