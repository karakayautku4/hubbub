import Foundation

/// xAI Grok. There is no known official local session log, so this is an alias of the Crew Events pipeline:
/// ~/.hubbub/events/grok-*.jsonl, or any events file whose events carry `"provider":"grok"`.
/// Emit events from an xAI API script with tools/crew-emit (see docs/PROVIDERS.md).
struct GrokProvider: AgentProvider {
    let id = "grok"
    let displayName = "xAI Grok (via events)"
    let symbol = "bolt"
    let dataHint = "~/.hubbub/events/grok-*.jsonl"

    private static let cache = ProviderKit.OfflineCache()

    private var root: URL {
        if let d = ProcessInfo.processInfo.environment["HUBBUB_EVENTS_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return ProviderKit.home.appendingPathComponent(".hubbub/events")
    }

    var isAvailable: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.contains { $0.lowercased().hasPrefix("grok-") && $0.hasSuffix(".jsonl") }
    }

    func scan() -> [SessionInfo] {
        ProviderKit.recentFiles(under: root, ext: "jsonl", maxDepth: 0).compactMap { url, mod in
            let sid = url.deletingPathExtension().lastPathComponent
            let key = "grok:" + url.path
            if let hit = Self.cache.get(key, mod) { return hit }
            let lines = ProviderKit.readTail(url)
            guard CrewEventsProvider.aliasProvider(file: sid, lines: lines) == "grok" else { return nil }
            let info = Self.parse(lines: lines, id: sid, modified: mod)
            Self.cache.put(key, mod, info)
            return info
        }
    }

    static func parse(lines: [Substring], id: String, modified: Date) -> SessionInfo {
        var info = CrewEventsProvider.parse(lines: lines, id: id, modified: modified, provider: "grok")
        if info.model.isEmpty { info.model = "grok" }
        return info
    }
}
