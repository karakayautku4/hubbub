import Foundation

/// Claude Code: ~/.claude/projects/<encoded-cwd>/<session>.jsonl
/// (also honours CLAUDE_CONFIG_DIR). Sub-agents are `Task` tool calls; sidechain messages are attributed to them.
struct ClaudeCodeProvider: AgentProvider {
    let id = "claude"
    let displayName = "Claude Code"
    let symbol = "sparkles"
    let dataHint = "~/.claude/projects"

    private static let cache = ProviderKit.OfflineCache()

    private var root: URL {
        if let d = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d).appendingPathComponent("projects")
        }
        return ProviderKit.home.appendingPathComponent(".claude/projects")
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: root.path) }

    func scan() -> [SessionInfo] {
        // <projects>/<project>/<session>.jsonl — depth 1 only so sub-agent transcripts are not listed as sessions
        ProviderKit.recentFiles(under: root, ext: "jsonl", maxDepth: 1).compactMap { url, mod in
            let sid = url.deletingPathExtension().lastPathComponent
            if let hit = Self.cache.get(url.path, mod) { return hit }
            let info = Self.parse(lines: ProviderKit.readTail(url), id: sid, modified: mod)
            Self.cache.put(url.path, mod, info)
            return info
        }
    }

    static func parse(lines: [Substring], id: String, modified: Date) -> SessionInfo {
        var b = SessionBuilder(provider: "claude", rawID: id, modified: modified)
        var usageByMessage: [String: (Int, Int)] = [:]
        var taskIDs = Set<String>()

        for line in lines {
            guard let obj = ProviderKit.json(line) else { continue }
            let ts = ProviderKit.date(obj["timestamp"])
            b.touch(ts)
            if b.created == nil { b.created = ts }
            if let c = obj["cwd"] as? String, !c.isEmpty { b.cwd = c }
            if let g = obj["gitBranch"] as? String, !g.isEmpty { b.branch = g }
            let sidechain = obj["isSidechain"] as? Bool ?? false
            guard let msg = obj["message"] as? [String: Any] else { continue }
            let at = ts ?? modified

            if sidechain == false, let m = msg["model"] as? String, !m.hasPrefix("<") { b.model = m }

            if let u = msg["usage"] as? [String: Any], let mid = msg["id"] as? String {
                let cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
                let cacheNew = u["cache_creation_input_tokens"] as? Int ?? 0
                let fresh = (u["input_tokens"] as? Int ?? 0) + cacheNew
                usageByMessage[mid] = (fresh, u["output_tokens"] as? Int ?? 0)
                if !sidechain { b.contextTokens = fresh + cacheRead }
            }

            let parts: [[String: Any]]
            if let arr = msg["content"] as? [[String: Any]] { parts = arr } else { 
                // plain-string user content: only look for the interrupt marker
                if let s = msg["content"] as? String, s.hasPrefix("[Request interrupted") { b.interrupt() }
                continue
            }
            for p in parts {
                switch p["type"] as? String {
                case "tool_use":
                    guard let tid = p["id"] as? String, let name = p["name"] as? String else { continue }
                    let input = p["input"] as? [String: Any] ?? [:]
                    if name == "Task" || name == "Agent" {
                        taskIDs.insert(tid)
                        let kind = input["subagent_type"] as? String ?? "agent"
                        let desc = (input["description"] as? String).map { String($0.prefix(40)) } ?? kind
                        b.subStart(id: tid, name: kind, display: desc, at: at)
                        b.toolStart(id: tid, tool: "task", detail: ProviderKit.detail(input), at: at)
                    } else {
                        b.toolStart(id: tid, tool: name, detail: ProviderKit.detail(input), at: at,
                                    sub: sidechain ? b.newestSubID : nil)
                        if name == "AskUserQuestion", !sidechain, let q = QuestionParser.claudeAskUserQuestion(id: tid, input: input, at: at) {
                            b.questionAsked(q)
                        }
                    }
                case "tool_result":
                    guard let tid = p["tool_use_id"] as? String else { continue }
                    let ok = !(p["is_error"] as? Bool ?? false)
                    b.toolEnd(id: tid, ok: ok, at: at, error: ok ? nil : "Tool failed")
                    if taskIDs.contains(tid) { b.subEnd(id: tid) }
                case "text":
                    if msg["role"] as? String == "user", let t = p["text"] as? String, t.hasPrefix("[Request interrupted") { b.interrupt() }
                default: break
                }
            }
        }
        b.inputTokens = usageByMessage.values.reduce(0) { $0 + $1.0 }
        b.outputTokens = usageByMessage.values.reduce(0) { $0 + $1.1 }
        return b.build()
    }
}
