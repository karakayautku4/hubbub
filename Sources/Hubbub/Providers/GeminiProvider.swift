import Foundation

/// Gemini CLI: ~/.gemini/tmp/<project>/chats/session-*.json (or .jsonl in newer builds).
/// Tool calls are stored together with their result, so a call without a final status counts as running.
struct GeminiProvider: AgentProvider {
    let id = "gemini"
    let displayName = "Gemini CLI"
    let symbol = "diamond"
    let dataHint = "~/.gemini/tmp"

    private static let cache = ProviderKit.OfflineCache()
    private static let maxFileBytes = 20_000_000

    private var root: URL { ProviderKit.home.appendingPathComponent(".gemini/tmp") }
    var isAvailable: Bool { FileManager.default.fileExists(atPath: root.path) }

    func scan() -> [SessionInfo] {
        let projects = Self.projectNames()
        let files = ProviderKit.recentFiles(under: root, ext: "json", prefix: "session-", maxDepth: 3)
            + ProviderKit.recentFiles(under: root, ext: "jsonl", prefix: "session-", maxDepth: 3)
        return files.sorted { $0.1 > $1.1 }.prefix(ProviderKit.perProviderLimit).compactMap { url, mod in
            if let hit = Self.cache.get(url.path, mod) { return hit }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
            guard size > 0, size < Self.maxFileBytes, let data = try? Data(contentsOf: url) else { return nil }
            let projectDir = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            var messages: [[String: Any]] = []
            var meta: [String: Any] = [:]
            if url.pathExtension == "jsonl" {
                for l in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    guard let o = ProviderKit.json(l) else { continue }
                    if o["messages"] != nil || o["sessionId"] != nil && o["type"] == nil { meta = o } else { messages.append(o) }
                }
            } else if let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                meta = o
                messages = o["messages"] as? [[String: Any]] ?? []
            }
            let sid = (meta["sessionId"] as? String) ?? url.deletingPathExtension().lastPathComponent
            var info = Self.parse(meta: meta, messages: messages, id: sid, modified: mod)
            if info.cwd.isEmpty, let path = projects[projectDir] { info.cwd = path; info.name = ProviderKit.folder(path) + " #" + sid.prefix(4) }
            Self.cache.put(url.path, mod, info)
            return info
        }
    }

    /// ~/.gemini/projects.json maps project paths to the short names used as directories under tmp/.
    private static func projectNames() -> [String: String] {
        let url = ProviderKit.home.appendingPathComponent(".gemini/projects.json")
        guard let d = try? Data(contentsOf: url),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let map = o["projects"] as? [String: String] else { return [:] }
        return Dictionary(map.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func parse(meta: [String: Any], messages: [[String: Any]], id: String, modified: Date) -> SessionInfo {
        var b = SessionBuilder(provider: "gemini", rawID: id, modified: modified)
        b.created = ProviderKit.date(meta["startTime"])
        b.touch(ProviderKit.date(meta["lastUpdated"]))
        var tin = 0, tout = 0
        for m in messages {
            let ts = ProviderKit.date(m["timestamp"])
            b.touch(ts)
            if let mod = m["model"] as? String { b.model = mod }
            if let t = m["tokens"] as? [String: Any] {
                tin += t["input"] as? Int ?? 0
                tout += (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0)
                if let total = t["input"] as? Int { b.contextTokens = total }
            }
            for c in m["toolCalls"] as? [[String: Any]] ?? [] {
                guard let name = c["name"] as? String else { continue }
                let cid = (c["id"] as? String) ?? "\(name)-\(b.toolCalls)"
                let at = ProviderKit.date(c["timestamp"]) ?? ts ?? modified
                b.toolStart(id: cid, tool: name, detail: ProviderKit.detail(c["args"] as? [String: Any] ?? [:]), at: at)
                switch c["status"] as? String {
                case "success": b.toolEnd(id: cid, ok: true, at: at)
                case "error": b.toolEnd(id: cid, ok: false, at: at, error: "Tool failed")
                case "cancelled": b.toolEnd(id: cid, ok: true, at: at)
                case "awaiting_approval":
                    b.questionAsked(QuestionParser.genericApproval(id: cid, title: "Allow \(name)?", detail: ProviderKit.detail(c["args"] as? [String: Any] ?? [:]), tool: name, at: at))
                default: break
                }
            }
        }
        b.inputTokens = tin
        b.outputTokens = tout
        return b.build()
    }
}
