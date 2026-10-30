import Foundation

/// Reads Copilot CLI session logs from ~/.copilot/session-state/<id>/events.jsonl
@MainActor
final class SessionMonitor: ObservableObject {
    @Published var sessions: [SessionInfo] = []
    @Published var attention: AttentionLevel = .none
    @Published var attentionByID: [String: AttentionLevel] = [:]
    private var timer: Timer?

    private nonisolated static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".copilot/session-state")

    private var observer: NSObjectProtocol?
    private var metricsObserver: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        refresh()
        arm(Stage.popoverVisible ? 2 : 10)
        // Warm the history index shortly after launch so opening History is instant (throttled, newest sessions first)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            UsageHistory.shared.scanSessions()
        }
        // A background metrics catch-up finished: pick up the totals it produced
        metricsObserver = NotificationCenter.default.addObserver(forName: MetricsScanner.didUpdate, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Poll fast only while the popover is visible; Stage posts this when visibility flips.
        observer = NotificationCenter.default.addObserver(forName: Stage.visibilityChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.arm()
                if Stage.popoverVisible { self.refresh() }
            }
        }
    }

    private var unchanged = 0
    private var currentInterval: TimeInterval = 0
    private var lastRefreshAt = Date.distantPast
    private var kickPending = false
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    /// Polls fast while the popover is visible and slower when hidden; backs off further while nothing is working or changing.
    /// File watchers (see `syncWatchers`) wake it promptly when a Copilot log is written.
    private func desiredInterval(anyWorking: Bool) -> TimeInterval {
        let base: TimeInterval = Stage.popoverVisible ? 2 : 10
        guard !anyWorking, unchanged >= 3 else { return base }
        return Stage.popoverVisible ? base * 2 : base * (unchanged >= 10 ? 3 : 2)
    }

    private func arm(_ interval: TimeInterval? = nil) {
        timer?.invalidate()
        let interval = interval ?? desiredInterval(anyWorking: sessions.contains { $0.state == .working })
        currentInterval = interval
        let tm = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        tm.tolerance = interval * 0.25
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    /// Coalesced refresh request from a file watcher: at most one per 0.5 s while visible, one per 5 s while hidden.
    private func kick() {
        guard !kickPending else { return }
        kickPending = true
        let gap: TimeInterval = Stage.popoverVisible ? 0.5 : 5
        let wait = max(0.3, gap - Date().timeIntervalSince(lastRefreshAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.kickPending = false
                self.unchanged = 0
                self.refresh()
            }
        }
    }

    private func watch(_ path: String) {
        guard watchers[path] == nil else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let src, !src.data.isDisjoint(with: [.delete, .rename]) { src.cancel(); self.watchers[path] = nil }
                self.kick()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchers[path] = src
    }

    private func syncWatchers(_ result: [SessionInfo]) {
        let root = Self.root.path
        watch(root)   // new session folders
        var wanted: Set<String> = [root]
        for s in result where s.provider == "copilot" || s.provider.isEmpty {
            let p = root + "/" + s.id + "/events.jsonl"
            wanted.insert(p); watch(p)
        }
        for (p, src) in watchers where !wanted.contains(p) { src.cancel(); watchers[p] = nil }
    }

    private var scanning = false

    func refresh() {
        guard !scanning else { return }
        scanning = true
        lastRefreshAt = Date()
        Task.detached(priority: .utility) {
            let result = SessionMonitor.scan()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                let changed = self.sessions != result
                if changed { self.sessions = result; self.unchanged = 0 } else { self.unchanged += 1 }
                ProdFeatures.ingest(result)
                ProgressionCenter.shared.ingest(result)
                let levels = StuckDetector.shared.evaluate(result)
                if levels != self.attentionByID { self.attentionByID = levels }
                let top = levels.values.max() ?? .none
                if top != self.attention { self.attention = top }
                if changed { self.syncWatchers(result) }
                let want = self.desiredInterval(anyWorking: result.contains { $0.state == .working })
                if want != self.currentInterval, self.timer != nil { self.arm(want) }
            }
        }
    }

    /// Sessions of every enabled provider (see Providers/).
    nonisolated static func scan() -> [SessionInfo] { ProviderRegistry.shared.scanEnabled() }

    nonisolated static func scanCopilot() -> [SessionInfo] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var candidates: [(URL, Date)] = []
        for dir in dirs {
            let events = dir.appendingPathComponent("events.jsonl")
            if let attrs = try? fm.attributesOfItem(atPath: events.path),
               let mod = attrs[.modificationDate] as? Date, mod > cutoff {
                candidates.append((dir, mod))
            }
        }
        candidates.sort { $0.1 > $1.1 }
        MetricsScanner.shared.update(ids: candidates.map { $0.0.lastPathComponent })
        return candidates.prefix(12).compactMap { dir, mod in
            guard var info = scanOne(dir, mod) else { return nil }
            if let m = MetricsScanner.shared.metrics(for: info.id), m.calls > 0 {
                info.toolCalls = m.calls; info.failures = m.failures; info.costCredits = m.cost
            }
            return info
        }
    }

    private nonisolated static func scanOne(_ dir: URL, _ mod: Date) -> SessionInfo? {
        let id = dir.lastPathComponent
        var st = stat()
        let size = stat(dir.appendingPathComponent("events.jsonl").path, &st) == 0 ? Int(st.st_size) : -1
        cacheLock.lock()
        let hit = cache[id]
        cacheLock.unlock()
        if let h = hit, h.mod == mod, h.size == size {
            var info = h.info
            // Unchanged logs of non-working sessions can't change state, and a working one keeps its state until its earliest time-based deadline
            if info.state != .working || Date() < h.reuseUntil {
                info.inUse = isInUse(dir)
                return info
            }
        }
        let parsedAt = Date()
        guard let info = parse(dir: dir, modified: mod) else { return nil }
        var until = Date.distantPast
        if info.state == .working {
            var deadline = info.lastEvent.addingTimeInterval(15)
            for c in info.recentCalls where c.status == .running { deadline = min(deadline, c.time.addingTimeInterval(600)) }
            for s in info.subagents { deadline = min(deadline, s.startedAt.addingTimeInterval(2 * 3600)) }
            // Running tools/subagents beyond the recentCalls window are covered by re-parsing at the 15 s mark
            until = max(parsedAt, deadline)
        }
        cacheLock.lock(); cache[id] = CacheEntry(mod: mod, size: size, info: info, reuseUntil: until); cacheLock.unlock()
        return info
    }

    private struct CacheEntry { let mod: Date; let size: Int; let info: SessionInfo; let reuseUntil: Date }
    private nonisolated(unsafe) static var cache: [String: CacheEntry] = [:]
    private nonisolated static let cacheLock = NSLock()

    private nonisolated static func isInUse(_ dir: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where f.hasPrefix("inuse.") && f.hasSuffix(".lock") {
            let parts = f.split(separator: ".")
            if parts.count >= 3, let pid = Int32(parts[1]), kill(pid, 0) == 0 { return true }
        }
        return false
    }

    private nonisolated static func readTail(_ url: URL, bytes: Int = 2_000_000) -> [Substring] {
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

    /// Last model named in the first 256 KB of an events file (`session.start.selectedModel` / `session.model_change.newModel`).
    nonisolated static func headModel(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 256 << 10), !data.isEmpty else { return nil }
        var found: String?
        for line in data.split(separator: 0x0A) {
            guard line.starts(with: typePrefix) else { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let t = obj["type"] as? String, t == "session.start" || t == "session.model_change" || t == "session.resume",
                  let d = obj["data"] as? [String: Any] else { continue }
            if let m = (d["newModel"] ?? d["selectedModel"]) as? String, !m.isEmpty { found = m }
        }
        return found
    }

    private nonisolated static func detail(_ args: [String: Any], title: String?) -> String {
        for key in ["description", "intent", "command", "path", "pattern", "query", "url", "question", "prompt"] {
            if let v = args[key] as? String, !v.isEmpty {
                let one = v.replacingOccurrences(of: "\n", with: " ")
                return String(one.prefix(80))
            }
        }
        return title ?? ""
    }

    private nonisolated static func parseDate(_ s: String?) -> Date? {
        FastDate.parse(s)
    }

    private nonisolated static let typePrefix = Array("{\"type\":\"".utf8)
    private nonisolated static let handledTypes: Set<String> = [
        "session.start", "session.resume", "session.model_change", "tool.execution_start", "tool.execution_complete",
        "permission.requested", "permission.completed", "session.compaction_start", "session.truncation",
        "subagent.started", "subagent.completed", "subagent.failed", "session.usage_record", "abort", "session.shutdown"]
    private nonisolated static let tsKey = Array("\"timestamp\":\"".utf8)

    /// Event type read straight from the line head (`{"type":"..."`).
    private nonisolated static func typeOf(_ p: UnsafeRawBufferPointer) -> String? {
        guard JSONL.hasPrefix(p, typePrefix) else { return nil }
        let head = UnsafeRawBufferPointer(rebasing: p[typePrefix.count..<min(p.count, typePrefix.count + 48)])
        guard let q = memchr(head.baseAddress!, 0x22, head.count) else { return nil }
        let n = head.baseAddress!.distance(to: UnsafeRawPointer(q))
        return String(decoding: UnsafeRawBufferPointer(rebasing: head[0..<n]), as: UTF8.self)
    }

    /// Top-level timestamp (the last unescaped `"timestamp":"` in the line).
    private nonisolated static func rawTimestamp(_ p: UnsafeRawBufferPointer) -> Date? {
        guard let base = p.baseAddress else { return nil }
        var i = p.count - tsKey.count
        let floor = max(0, p.count - 400)
        while i >= floor {
            if memcmp(base + i, tsKey, tsKey.count) == 0 {
                let from = i + tsKey.count
                guard let q = memchr(base + from, 0x22, min(40, p.count - from)) else { return nil }
                let n = base.distance(to: UnsafeRawPointer(q)) - from
                return FastDate.parse(String(decoding: UnsafeRawBufferPointer(rebasing: p[from..<(from + n)]), as: UTF8.self))
            }
            i -= 1
        }
        return nil
    }

    nonisolated static func parse(dir: URL, modified: Date, naive: Bool = false) -> SessionInfo? {
        let id = dir.lastPathComponent
        var name = "Session " + id.prefix(6)
        var cwd = ""
        var branch = ""
        var created: Date?
        if let yaml = try? String(contentsOf: dir.appendingPathComponent("workspace.yaml"), encoding: .utf8) {
            for line in yaml.split(separator: "\n") {
                if line.hasPrefix("name: ") { name = String(line.dropFirst(6)) }
                if line.hasPrefix("branch: ") { branch = String(line.dropFirst(8)) }
                if line.hasPrefix("created_at: ") { created = parseDate(String(line.dropFirst(12))) }
                if line.hasPrefix("cwd: ") { cwd = String(line.dropFirst(5)) }
            }
        }

        var runningTools: [String: (String, Date)] = [:]
        var subs: [String: SubAgent] = [:]
        var model = ""
        var tin = 0, tout = 0, toolCalls = 0
        var last = modified
        var ended = false
        var captainActions: [ActionRecord] = []
        var subActions: [String: [ActionRecord]] = [:]
        var subTool: [String: String] = [:]
        var subRunning: [String: Set<String>] = [:]
        var cidOwner: [String: String] = [:]
        var lastFail: Date?
        var lastError: String?
        var calls: [ToolCallRecord] = []
        var callIndex: [String: Int] = [:]
        var ctxTokens = 0, ctxLimit = 0, failCount = 0, cost = 0.0
        var agentCid: [String: String] = [:]
        var subStats: [String: (ctx: Int, limit: Int, calls: Int, fails: Int, cost: Double)] = [:]
        var pendingApprovals: [String: String] = [:]   // requestId / toolCallId -> owner sub cid ("" = main)
        var pendingQuestions: [String: PendingQuestion] = [:]
        var clock = ActiveClock()
        var dayUsage: [String: DayUsage] = [:]
        let cal = Calendar.current

        func handle(_ obj: [String: Any], _ type: String) {
            let data = obj["data"] as? [String: Any] ?? [:]
            let ts = parseDate(obj["timestamp"] as? String)
            if let ts { last = ts; clock.tick(ts) }
            switch type {
            case "session.start", "session.resume":
                ended = false
                if let m = data["selectedModel"] as? String { model = m }
            case "session.model_change":
                if let m = data["newModel"] as? String { model = m }
            case "tool.execution_start":
                toolCalls += 1
                if let aid = obj["agentId"] as? String, let owner = agentCid[aid] {
                    subStats[owner, default: (0, 0, 0, 0, 0)].calls += 1
                }
                if data["toolName"] as? String == "ask_user", let cid = data["toolCallId"] as? String {
                    pendingApprovals["ask:" + cid] = agentCid[obj["agentId"] as? String ?? ""] ?? ""
                    pendingQuestions["ask:" + cid] = QuestionParser.copilotAskUser(id: cid, args: data["arguments"] as? [String: Any] ?? [:], at: ts)
                }
                if let cid = data["toolCallId"] as? String, let tn = data["toolName"] as? String {
                    runningTools[cid] = (tn, ts ?? Date())
                    let args = data["arguments"] as? [String: Any] ?? [:]
                    callIndex[cid] = calls.count
                    calls.append(ToolCallRecord(id: cid, time: ts ?? Date(), tool: tn,
                                                detail: detail(args, title: data["toolTitle"] as? String), status: .running))
                    if calls.count > 40 { calls.removeFirst(); callIndex = Dictionary(uniqueKeysWithValues: calls.enumerated().map { ($1.id, $0) }) }
                    let rec = ActionRecord(id: cid, time: ts ?? Date(), tool: tn,
                                           detail: detail(args, title: data["toolTitle"] as? String))
                    if let parent = data["parentToolCallId"] as? String {
                        subActions[parent, default: []].append(rec)
                        if subActions[parent]!.count > 8 { subActions[parent]!.removeFirst() }
                        subTool[parent] = tn
                        subRunning[parent, default: []].insert(cid)
                        cidOwner[cid] = parent
                    } else {
                        captainActions.append(rec)
                        if captainActions.count > 8 { captainActions.removeFirst() }
                    }
                }
            case "tool.execution_complete":
                if let cid = data["toolCallId"] as? String {
                    runningTools[cid] = nil
                    if let owner = cidOwner[cid] { subRunning[owner]?.remove(cid) }
                }
                let ok = data["success"] as? Bool != false
                if let cid = data["toolCallId"] as? String { pendingApprovals["ask:" + cid] = nil; pendingQuestions["ask:" + cid] = nil }
                if !ok {
                    failCount += 1
                    if let owner = agentCid[obj["agentId"] as? String ?? ""] { subStats[owner, default: (0, 0, 0, 0, 0)].fails += 1 }
                }
                if let cid = data["toolCallId"] as? String, let i = callIndex[cid], i < calls.count {
                    calls[i].status = ok ? .ok : .failed
                }
                if !ok {
                    lastFail = ts
                    let err = data["error"] as? [String: Any]
                    lastError = (err?["message"] as? String) ?? (err?["code"] as? String) ?? "Tool failed"
                }
            case "permission.requested":
                if let rid = data["requestId"] as? String {
                    pendingApprovals[rid] = agentCid[obj["agentId"] as? String ?? ""] ?? ""
                    pendingQuestions[rid] = QuestionParser.copilotPermission(data: data, at: ts)
                }
            case "permission.completed":
                if let rid = data["requestId"] as? String { pendingApprovals[rid] = nil; pendingQuestions[rid] = nil }
            case "session.compaction_start":
                if let t = data["currentTokens"] as? Int { ctxTokens = t }
                if let l = data["tokenLimit"] as? Int { ctxLimit = l }
            case "session.truncation":
                if let t = data["postTruncationTokensInMessages"] as? Int { ctxTokens = t }
                if let l = data["tokenLimit"] as? Int { ctxLimit = l }
            case "subagent.started":
                if let aid = obj["agentId"] as? String, let cid = data["toolCallId"] as? String { agentCid[aid] = cid }
                if let cid = data["toolCallId"] as? String {
                    subs[cid] = SubAgent(
                        id: cid,
                        name: data["agentName"] as? String ?? "agent",
                        displayName: data["agentDisplayName"] as? String ?? "Agent",
                        model: data["model"] as? String ?? "",
                        startedAt: ts ?? Date())
                }
            case "subagent.completed", "subagent.failed":
                if let cid = data["toolCallId"] as? String { subs[cid] = nil }
            case "session.usage_record":
                if let u = data["usage"] as? [String: Any] {
                    tin += u["inputTokens"] as? Int ?? 0
                    tout += u["outputTokens"] as? Int ?? 0
                    let inTok = u["inputTokens"] as? Int ?? 0
                    let lim = u["maxPromptTokens"] as? Int ?? 0
                    let c = (u["cost"] as? Double) ?? Double(u["cost"] as? Int ?? 0)
                    let dayKey = DayKey.string(ts ?? last, calendar: cal)
                    var du = dayUsage[dayKey] ?? DayUsage()
                    du.input += inTok; du.output += u["outputTokens"] as? Int ?? 0
                    if obj["agentId"] == nil { du.credits += c }
                    dayUsage[dayKey] = du
                    if let owner = agentCid[obj["agentId"] as? String ?? ""] {
                        subStats[owner, default: (0, 0, 0, 0, 0)].ctx = inTok
                        if lim > 0 { subStats[owner]!.limit = lim }
                        subStats[owner]!.cost += c
                    } else if obj["agentId"] == nil {
                        ctxTokens = inTok
                        if lim > 0 { ctxLimit = lim }
                        cost += c
                        if let m = u["model"] as? String { model = m }
                    }
                }
            case "abort":
                runningTools.removeAll(); subs.removeAll(); pendingApprovals.removeAll(); pendingQuestions.removeAll()
            case "session.shutdown":
                ended = true; runningTools.removeAll(); subs.removeAll(); pendingApprovals.removeAll(); pendingQuestions.removeAll()
                if let t = data["currentTokens"] as? Int, t > 0 { ctxTokens = t }
            default: break
            }
        }

        let eventsPath = dir.appendingPathComponent("events.jsonl").path
        if naive {
            for line in readTail(dir.appendingPathComponent("events.jsonl")) {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let type = obj["type"] as? String else { continue }
                handle(obj, type)
            }
        } else {
            // Same window as `readTail`, but streamed: only state-bearing events are JSON-parsed; the rest only contribute their timestamp.
            var size: UInt64 = 0
            var st = stat(); if stat(eventsPath, &st) == 0 { size = UInt64(st.st_size) }
            let start = size > 2_000_000 ? size - 2_000_000 : 0
            var first = start > 0
            func feed(_ p: UnsafeRawBufferPointer) {
                if first { first = false; return }
                if let type = typeOf(p), !handledTypes.contains(type), let ts = rawTimestamp(p) { last = ts; clock.tick(ts); return }
                autoreleasepool { if let obj = JSONL.object(p), let t = obj["type"] as? String { handle(obj, t) } }
            }
            let r = JSONL.scan(path: eventsPath, from: start, chunk: 256 << 10, wants: { _ in true }, line: feed)
            // An unterminated final line is still a line (matches the whole-tail reader)
            if let r, r.endOffset < r.size, r.size - r.endOffset < 8 << 20, let h = FileHandle(forReadingAtPath: eventsPath) {
                try? h.seek(toOffset: r.endOffset)
                if let d = try? h.readToEnd(), !d.isEmpty {
                    if first { first = false } else if let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let t = obj["type"] as? String { handle(obj, t) }
                }
                try? h.close()
            }
        }

        // The tail window can miss both `session.start`/`model_change` (head) and any main-agent usage record
        // (long tool output, sub-agent-only stretches): recover the model from the file head instead of reading blank.
        if model.isEmpty, let m = headModel(URL(fileURLWithPath: eventsPath)) { model = m }

        let now = Date()
        let waiting = !runningTools.isEmpty && !ended
        // Drop stale unfinished work (aborted/crashed runs never log a completion)
        runningTools = runningTools.filter { now.timeIntervalSince($0.value.1) < 600 }
        let activeSubs = subs.values.filter { now.timeIntervalSince($0.startedAt) < 2 * 3600 }
            .map { sub -> SubAgent in
                var s = sub
                s.tool = subTool[sub.id]
                s.busy = !(subRunning[sub.id]?.isEmpty ?? true)
                s.actions = subActions[sub.id] ?? []
                let st = subStats[sub.id]
                s.contextTokens = st?.ctx ?? 0
                s.contextLimit = (st?.limit ?? 0) > 0 ? st!.limit : ModelInfo.contextLimit(sub.model)
                s.toolCalls = st?.calls ?? 0
                s.failures = st?.fails ?? 0
                s.costCredits = st?.cost ?? 0
                s.waitingApproval = pendingApprovals.values.contains(sub.id)
                return s
            }
            .sorted { $0.startedAt < $1.startedAt }
        let inUse = isInUse(dir)

        let state: SessionState
        if ended && !inUse { state = .offline }
        else if !runningTools.isEmpty || !activeSubs.isEmpty || now.timeIntervalSince(last) < 15 { state = .working }
        else if inUse { state = .idle }
        else { state = .offline }

        let tool = runningTools.values.max { $0.1 < $1.1 }?.0
        var info = SessionInfo(
            id: id, name: name, cwd: cwd, model: model, lastEvent: last, state: state,
            currentTool: state == .working ? tool : nil, subagents: state == .offline ? [] : activeSubs,
            inputTokens: tin, outputTokens: tout, toolCalls: toolCalls,
            actions: captainActions, lastFailureAt: lastFail,
            branch: branch, startedAt: created, lastError: lastError, recentCalls: calls,
            inUse: inUse, waitingOnTool: waiting,
            contextTokens: ctxTokens, contextLimit: ctxLimit > 0 ? ctxLimit : ModelInfo.contextLimit(model),
            failures: failCount, costCredits: cost, waitingApproval: !ended && pendingApprovals.values.contains(""))
        info.dayUsage = dayUsage
        info.activeSeconds = clock.total
        if !ended { info.pendingQuestion = pendingQuestions.values.max { ($0.askedAt ?? .distantPast) < ($1.askedAt ?? .distantPast) } }
        return info
    }
}
