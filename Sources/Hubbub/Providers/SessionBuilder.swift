import Foundation

/// Shared helpers for file based providers.
enum ProviderKit {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func dirExists(_ relative: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path, isDirectory: &isDir) && isDir.boolValue
    }

    static let recentWindow: TimeInterval = 24 * 3600
    static let perProviderLimit = 12

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso = ISO8601DateFormatter()

    /// Accepts ISO-8601 strings and epoch seconds/milliseconds.
    static func date(_ v: Any?) -> Date? {
        if let s = v as? String { return isoFrac.date(from: s) ?? iso.date(from: s) }
        if let n = v as? NSNumber {
            let d = n.doubleValue
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        }
        return nil
    }

    static func modDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Last `bytes` of a JSONL file as lines (first partial line dropped).
    static func readTail(_ url: URL, bytes: Int = 2_000_000) -> [Substring] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    static func json(_ line: Substring) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    /// Recursively lists files with the given extension modified inside the recency window, newest first.
    static func recentFiles(under root: URL, ext: String, prefix: String? = nil, maxDepth: Int = 6) -> [(URL, Date)] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-recentWindow)
        var out: [(URL, Date)] = []
        func walk(_ dir: URL, _ depth: Int) {
            guard depth <= maxDepth,
                  let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]) else { return }
            for u in items {
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                if v?.isDirectory == true { walk(u, depth + 1); continue }
                guard u.pathExtension == ext, prefix.map({ u.lastPathComponent.hasPrefix($0) }) ?? true,
                      let m = v?.contentModificationDate, m > cutoff else { continue }
                out.append((u, m))
            }
        }
        walk(root, 0)
        out.sort { $0.1 > $1.1 }
        return Array(out.prefix(perProviderLimit))
    }

    static func detail(_ args: [String: Any]) -> String {
        for key in ["description", "intent", "command", "cmd", "file_path", "path", "pattern", "query", "url", "prompt"] {
            let v = args[key]
            let s = (v as? String) ?? (v as? [String])?.joined(separator: " ")
            if let s, !s.isEmpty { return String(s.replacingOccurrences(of: "\n", with: " ").prefix(80)) }
        }
        return ""
    }

    static func folder(_ cwd: String) -> String { (cwd as NSString).lastPathComponent }

    /// Maps provider-specific tool names onto names the themes' station logic (`Theme.toolKind`) understands.
    static func canonicalTool(_ name: String) -> String {
        switch name.lowercased() {
        case "read", "read_file", "read_many_files", "readfile", "view_image": return "view"
        case "grep", "search_file_content", "grep_search": return "grep"
        case "glob", "list_directory", "ls", "list_dir": return "glob"
        case "edit", "multiedit", "write", "notebookedit", "write_file", "replace", "apply_patch", "str_replace_editor": return "edit"
        case "bash", "shell", "exec_command", "local_shell", "run_shell_command", "bashoutput", "killshell", "shell_command": return "bash"
        case "websearch", "google_web_search": return "web_search"
        case "todowrite", "update_plan", "save_memory": return "plan"
        default: return name
        }
    }

    /// Lock-protected cache for sessions that can no longer change (offline + unchanged mtime).
    final class OfflineCache: @unchecked Sendable {
        private var store: [String: (Date, SessionInfo)] = [:]
        private let lock = NSLock()
        func get(_ key: String, _ mod: Date) -> SessionInfo? {
            lock.lock(); defer { lock.unlock() }
            if let h = store[key], h.0 == mod { return h.1 }
            return nil
        }
        func put(_ key: String, _ mod: Date, _ info: SessionInfo) {
            lock.lock(); defer { lock.unlock() }
            if info.state == .offline { store[key] = (mod, info) } else { store[key] = nil }
        }
    }
}

/// Accumulates normalized events of one session and produces a `SessionInfo`.
/// Providers translate their native log format into these calls.
struct SessionBuilder {
    let provider: String
    let rawID: String
    var name = ""
    var cwd = ""
    var model = ""
    var branch = ""
    var created: Date?
    var last: Date
    var ended = false
    var inputTokens = 0
    var outputTokens = 0
    var toolCalls = 0
    var failures = 0
    var contextTokens = 0
    var contextLimit = 0
    var lastFail: Date?
    var lastError: String?
    private var clock = ActiveClock()

    private var running: [String: (tool: String, at: Date)] = [:]
    private var calls: [ToolCallRecord] = []
    private var callIndex: [String: Int] = [:]
    private var captainActions: [ActionRecord] = []
    private var owner: [String: String] = [:]
    private var subs: [String: SubAgent] = [:]
    private var subActions: [String: [ActionRecord]] = [:]
    private var subTool: [String: String] = [:]
    private var subRunning: [String: Set<String>] = [:]
    private var subStats: [String: (calls: Int, fails: Int, ctx: Int)] = [:]
    private var approvals: [String: String] = [:]   // request id -> owner sub id ("" = main agent)
    private var questions: [String: PendingQuestion] = [:]

    init(provider: String, rawID: String, modified: Date) {
        self.provider = provider
        self.rawID = rawID
        self.last = modified
    }

    var prefixedID: String { provider == "copilot" ? rawID : "\(provider):\(rawID)" }

    mutating func touch(_ ts: Date?) {
        guard let ts else { return }
        clock.tick(ts)
        if ts > last { last = ts }
    }

    mutating func toolStart(id: String, tool rawTool: String, detail: String, at: Date, sub: String? = nil) {
        let tool = ProviderKit.canonicalTool(rawTool)
        toolCalls += 1
        running[id] = (tool, at)
        callIndex[id] = calls.count
        calls.append(ToolCallRecord(id: id, time: at, tool: tool, detail: detail, status: .running))
        if calls.count > 40 {
            calls.removeFirst()
            callIndex = Dictionary(uniqueKeysWithValues: calls.enumerated().map { ($1.id, $0) })
        }
        let rec = ActionRecord(id: id, time: at, tool: tool, detail: detail)
        if let s = sub, subs[s] != nil {
            subActions[s, default: []].append(rec)
            if subActions[s]!.count > 8 { subActions[s]!.removeFirst() }
            subTool[s] = tool
            subRunning[s, default: []].insert(id)
            owner[id] = s
            subStats[s, default: (0, 0, 0)].calls += 1
        } else {
            captainActions.append(rec)
            if captainActions.count > 8 { captainActions.removeFirst() }
        }
    }

    mutating func toolEnd(id: String, ok: Bool, at: Date?, error: String? = nil) {
        running[id] = nil
        approvals[id] = nil
        questions[id] = nil
        if let o = owner[id] { subRunning[o]?.remove(id) }
        if let i = callIndex[id], i < calls.count { calls[i].status = ok ? .ok : .failed }
        guard !ok else { return }
        failures += 1
        if let o = owner[id] { subStats[o, default: (0, 0, 0)].fails += 1 }
        lastFail = at ?? Date()
        lastError = error ?? "Tool failed"
    }

    /// A failure that is not tied to a tool call (API error, crash, ...).
    mutating func failure(at: Date?, message: String?) {
        failures += 1
        lastFail = at ?? Date()
        lastError = message ?? "Failure"
    }

    mutating func subStart(id: String, name: String, display: String? = nil, model: String = "", at: Date) {
        subs[id] = SubAgent(id: id, name: name, displayName: display ?? name, model: model.isEmpty ? self.model : model, startedAt: at)
    }

    mutating func subEnd(id: String) {
        subs[id] = nil
        for cid in subRunning[id] ?? [] { running[cid] = nil }
        subRunning[id] = nil
    }

    /// The sub-agent a sidechain message most plausibly belongs to (newest running one).
    var newestSubID: String? { subs.values.max { $0.startedAt < $1.startedAt }?.id }
    var hasSub: Bool { !subs.isEmpty }

    mutating func approvalRequested(id: String, sub: String? = nil) { approvals[id] = sub ?? "" }
    mutating func approvalResolved(id: String) { approvals[id] = nil; questions[id] = nil }
    mutating func clearApprovals() { approvals.removeAll(); questions.removeAll() }
    /// An approval with its question text/options attached (same lifecycle as `approvalRequested`).
    mutating func questionAsked(_ q: PendingQuestion, sub: String? = nil) {
        approvals[q.id] = sub ?? ""
        questions[q.id] = q
    }

    mutating func interrupt() { running.removeAll(); subs.removeAll(); approvals.removeAll(); questions.removeAll() }

    mutating func finish() { ended = true; interrupt() }

    func build(now: Date = Date(), idleAfter: TimeInterval = 15, offlineAfter: TimeInterval = 600) -> SessionInfo {
        let age = now.timeIntervalSince(last)
        let fresh = age < offlineAfter
        let live = running.filter { now.timeIntervalSince($0.value.at) < 600 }
        let activeSubs: [SubAgent] = fresh ? subs.values.filter { now.timeIntervalSince($0.startedAt) < 2 * 3600 }.map { sub in
            var s = sub
            s.tool = subTool[sub.id]
            s.busy = !(subRunning[sub.id]?.isEmpty ?? true)
            s.actions = subActions[sub.id] ?? []
            s.toolCalls = subStats[sub.id]?.calls ?? 0
            s.failures = subStats[sub.id]?.fails ?? 0
            s.contextLimit = ModelInfo.contextLimit(sub.model)
            s.waitingApproval = approvals.values.contains(sub.id)
            return s
        }.sorted { $0.startedAt < $1.startedAt } : []

        let state: SessionState
        if ended || !fresh { state = .offline }
        else if !live.isEmpty || !activeSubs.isEmpty || age < idleAfter { state = .working }
        else { state = .idle }

        let tool = live.values.max { $0.at < $1.at }?.tool
        var info = SessionInfo(
            id: prefixedID,
            name: name.isEmpty ? "\(ProviderKit.folder(cwd).isEmpty ? provider : ProviderKit.folder(cwd)) #\(rawID.prefix(4))" : name,
            cwd: cwd, model: model, lastEvent: last, state: state,
            currentTool: state == .working ? tool : nil,
            subagents: state == .offline ? [] : activeSubs,
            inputTokens: inputTokens, outputTokens: outputTokens, toolCalls: toolCalls)
        info.provider = provider
        info.activeSeconds = clock.total
        info.actions = captainActions
        info.lastFailureAt = lastFail
        info.branch = branch
        info.startedAt = created
        info.lastError = lastError
        info.recentCalls = calls
        info.inUse = state != .offline
        info.waitingOnTool = !live.isEmpty && !ended
        info.contextTokens = contextTokens
        info.contextLimit = contextLimit > 0 ? contextLimit : ModelInfo.contextLimit(model)
        info.failures = failures
        info.waitingApproval = state != .offline && approvals.values.contains("")
        if state != .offline { info.pendingQuestion = questions.values.max { ($0.askedAt ?? .distantPast) < ($1.askedAt ?? .distantPast) } }
        return info
    }
}
