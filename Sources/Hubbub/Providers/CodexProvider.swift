import Foundation

/// OpenAI Codex CLI: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (CODEX_HOME honoured).
/// Handles both the wrapped ({"type","payload"}) and the older flat record layouts.
struct CodexProvider: AgentProvider {
    let id = "codex"
    let displayName = "OpenAI Codex CLI"
    let symbol = "terminal"
    let dataHint = "~/.codex/sessions"

    private static let cache = ProviderKit.OfflineCache()

    private var root: URL {
        if let d = ProcessInfo.processInfo.environment["CODEX_HOME"], !d.isEmpty {
            return URL(fileURLWithPath: d).appendingPathComponent("sessions")
        }
        return ProviderKit.home.appendingPathComponent(".codex/sessions")
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: root.path) }

    func scan() -> [SessionInfo] {
        ProviderKit.recentFiles(under: root, ext: "jsonl", prefix: "rollout-", maxDepth: 5).compactMap { url, mod in
            let sid = Self.sessionID(from: url.deletingPathExtension().lastPathComponent)
            if let hit = Self.cache.get(url.path, mod) { return hit }
            let info = Self.parse(lines: ProviderKit.readTail(url), id: sid, modified: mod)
            Self.cache.put(url.path, mod, info)
            return info
        }
    }

    /// rollout-2025-01-01T10-00-00-<uuid>  ->  <uuid>
    static func sessionID(from file: String) -> String {
        let parts = file.split(separator: "-")
        return parts.count >= 5 ? parts.suffix(5).joined(separator: "-") : file
    }

    static func parse(lines: [Substring], id: String, modified: Date) -> SessionInfo {
        var b = SessionBuilder(provider: "codex", rawID: id, modified: modified)
        var pendingExec: Set<String> = []

        for line in lines {
            guard let obj = ProviderKit.json(line) else { continue }
            let ts = ProviderKit.date(obj["timestamp"])
            b.touch(ts)
            let at = ts ?? modified
            let kind = obj["type"] as? String ?? ""
            let p = obj["payload"] as? [String: Any] ?? obj
            let ptype = p["type"] as? String ?? kind

            switch kind {
            case "session_meta":
                if let c = p["cwd"] as? String { b.cwd = c }
                if b.created == nil { b.created = ProviderKit.date(p["timestamp"]) ?? ts }
                if let g = (p["git"] as? [String: Any])?["branch"] as? String { b.branch = g }
            case "turn_context":
                if let c = p["cwd"] as? String { b.cwd = c }
                if let m = p["model"] as? String { b.model = m }
            case "event_msg":
                switch ptype {
                case "token_count":
                    guard let info = p["info"] as? [String: Any] else { break }
                    if let t = info["total_token_usage"] as? [String: Any] {
                        b.inputTokens = (t["input_tokens"] as? Int ?? 0) - (t["cached_input_tokens"] as? Int ?? 0)
                        b.outputTokens = t["output_tokens"] as? Int ?? 0
                    }
                    if let l = info["last_token_usage"] as? [String: Any] { b.contextTokens = l["input_tokens"] as? Int ?? b.contextTokens }
                    if let w = info["model_context_window"] as? Int { b.contextLimit = w }
                case "exec_approval_request", "apply_patch_approval_request", "elicitation_request":
                    let cid = p["call_id"] as? String ?? "approval"
                    let cmd = (p["command"] as? [String])?.joined(separator: " ")
                    let title = ptype == "apply_patch_approval_request" ? "Apply this patch?" : ptype == "elicitation_request" ? (p["message"] as? String ?? "Codex needs input") : "Run this command?"
                    var q = QuestionParser.genericApproval(id: cid, title: title, detail: cmd ?? p["reason"] as? String, tool: ptype, at: at)
                    if ptype == "elicitation_request" { q.kind = .freeText; q.options = []; q.detail = nil; q.allowsFreeText = true }
                    b.questionAsked(q)
                case "turn_aborted":
                    b.interrupt()
                case "error", "stream_error":
                    b.failure(at: at, message: "Agent error")
                default: break
                }
            case "response_item", "function_call", "local_shell_call", "custom_tool_call",
                 "function_call_output", "custom_tool_call_output":
                switch ptype {
                case "function_call", "local_shell_call", "custom_tool_call":
                    guard let cid = (p["call_id"] as? String) ?? (p["id"] as? String) else { break }
                    let name = (p["name"] as? String) ?? (ptype == "local_shell_call" ? "shell" : "tool")
                    var args: [String: Any] = [:]
                    if let s = p["arguments"] as? String, let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] { args = d }
                    else if let a = p["action"] as? [String: Any] { args = a }
                    b.approvalResolved(id: cid)
                    pendingExec.insert(cid)
                    b.toolStart(id: cid, tool: name, detail: ProviderKit.detail(args), at: at)
                case "function_call_output", "custom_tool_call_output":
                    guard let cid = p["call_id"] as? String else { break }
                    pendingExec.remove(cid)
                    b.toolEnd(id: cid, ok: exitOK(p["output"]), at: at, error: "Command failed")
                default: break
                }
            default: break
            }
        }
        return b.build()
    }

    /// Output is either a JSON string with metadata.exit_code, or plain text; only the exit code is inspected.
    private static func exitOK(_ output: Any?) -> Bool {
        let obj: [String: Any]?
        if let s = output as? String { obj = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] }
        else { obj = output as? [String: Any] }
        if let code = (obj?["metadata"] as? [String: Any])?["exit_code"] as? Int { return code == 0 }
        if let s = output as? String, let r = s.range(of: "Process exited with code ") {
            return Int(s[r.upperBound...].prefix { $0.isNumber || $0 == "-" }) == 0
        }
        return true
    }
}
