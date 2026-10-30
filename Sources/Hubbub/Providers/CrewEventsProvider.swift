import Foundation

/// Generic provider: any tool can append JSON lines to ~/.hubbub/events/<session>.jsonl.
/// Schema documented in docs/PROVIDERS.md.
struct CrewEventsProvider: AgentProvider {
    let id = "crew"
    let displayName = "Crew Events (generic)"
    let symbol = "antenna.radiowaves.left.and.right"
    let dataHint = "~/.hubbub/events"

    private static let cache = ProviderKit.OfflineCache()

    private var root: URL {
        if let d = ProcessInfo.processInfo.environment["HUBBUB_EVENTS_DIR"], !d.isEmpty { return URL(fileURLWithPath: d) }
        return ProviderKit.home.appendingPathComponent(".hubbub/events")
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: root.path) }

    func scan() -> [SessionInfo] {
        ProviderKit.recentFiles(under: root, ext: "jsonl", maxDepth: 0).compactMap { url, mod in
            let sid = url.deletingPathExtension().lastPathComponent
            if let hit = Self.cache.get(url.path, mod) { return hit }
            let lines = ProviderKit.readTail(url)
            // Files claimed by an alias provider (e.g. grok-*.jsonl) are not shown twice.
            if Self.aliasProvider(file: sid, lines: lines) != nil { return nil }
            let info = Self.parse(lines: lines, id: sid, modified: mod)
            Self.cache.put(url.path, mod, info)
            return info
        }
    }

    static let aliases: Set<String> = ["grok"]

    /// "grok" when the file is named grok-*.jsonl or any of its first events carries `"provider":"grok"`.
    static func aliasProvider(file: String, lines: [Substring]) -> String? {
        for a in aliases where file.lowercased().hasPrefix(a + "-") { return a }
        for l in lines.prefix(20) where l.contains("\"provider\"") {
            if let p = (ProviderKit.json(l)?["provider"] as? String)?.lowercased(), aliases.contains(p) { return p }
        }
        return nil
    }

    static func parse(lines: [Substring], id: String, modified: Date, provider: String = "crew") -> SessionInfo {
        var b = SessionBuilder(provider: provider, rawID: id, modified: modified)
        var source = ""
        var anon = 0
        for line in lines {
            guard let o = ProviderKit.json(line), let ev = (o["event"] as? String) ?? (o["type"] as? String) else { continue }
            let ts = ProviderKit.date(o["ts"]) ?? ProviderKit.date(o["timestamp"])
            b.touch(ts)
            let at = ts ?? modified
            if b.created == nil { b.created = ts }
            if let v = o["name"] as? String, !v.isEmpty { b.name = v }
            if let v = o["cwd"] as? String, !v.isEmpty { b.cwd = v }
            if let v = o["model"] as? String, !v.isEmpty { b.model = v }
            if let v = o["branch"] as? String, !v.isEmpty { b.branch = v }
            if let v = o["source"] as? String, !v.isEmpty { source = v }
            if let v = o["input_tokens"] as? Int { b.inputTokens += v }
            if let v = o["output_tokens"] as? Int { b.outputTokens += v }
            if let v = o["context_tokens"] as? Int { b.contextTokens = v }
            if let v = o["context_limit"] as? Int { b.contextLimit = v }
            func str(_ k: String) -> String? { (o[k] as? String) ?? (o[k] as? NSNumber).map { "\($0)" } }
            let cid = str("id") ?? str("tool_call_id")
            let agent = str("agent")
            switch ev {
            case "session_start": b.ended = false
            case "session_end": b.finish()
            case "tool_start":
                anon += 1
                b.toolStart(id: cid ?? "t\(anon)", tool: o["tool"] as? String ?? "tool",
                            detail: String((o["detail"] as? String ?? "").prefix(80)), at: at, sub: agent)
            case "tool_end":
                if let cid { b.toolEnd(id: cid, ok: o["ok"] as? Bool ?? true, at: at, error: o["error"] as? String) }
                else if o["ok"] as? Bool == false { b.failure(at: at, message: o["error"] as? String) }
            case "subagent_start":
                if let aid = agent ?? cid {
                    b.subStart(id: aid, name: o["tool"] as? String ?? "agent", display: o["display_name"] as? String,
                               model: o["model"] as? String ?? "", at: at)
                }
            case "subagent_end":
                if let aid = agent ?? cid { b.subEnd(id: aid) }
            case "failure":
                b.failure(at: at, message: o["error"] as? String ?? o["message"] as? String)
            case "approval_request":
                b.approvalRequested(id: cid ?? "approval", sub: agent)
            case "approval_granted", "approval_denied":
                b.approvalResolved(id: cid ?? "approval")
            default: break   // "message" and unknown types only refresh the activity timestamp
            }
        }
        var info = b.build()
        if info.model.isEmpty, !source.isEmpty { info.model = source }
        return info
    }
}
