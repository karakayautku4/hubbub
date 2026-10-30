import Foundation

/// Context-window sizes by model family (first matching key wins); unknown models fall back to 128k.
enum ModelInfo {
    static let contextLimits: [(String, Int)] = [
        ("claude-opus-4.8", 200_000), ("claude", 200_000), ("gemini", 1_000_000),
        ("gpt-5", 272_000), ("gpt-6", 272_000), ("gpt-4.1", 128_000), ("gpt-4o", 128_000), ("o3", 200_000), ("o4", 200_000),
    ]
    static let defaultLimit = 128_000

    static func contextLimit(_ model: String) -> Int {
        let m = model.lowercased()
        return contextLimits.first { m.contains($0.0) }?.1 ?? defaultLimit
    }
}

struct ActorAgg: Codable { var ok = 0, failed = 0, cost = 0.0 }

struct FileMetrics: Codable {
    var offset: UInt64 = 0
    var fp: UInt64?
    var name = ""
    var calls = 0, failures = 0
    var cost = 0.0
    var compactions = 0
    var streak = 0, bestStreak = 0
    var intervals: [(Date, Date)] = []
    var days: [Double: [String: ActorAgg]] = [:]   // start-of-day epoch -> actor key -> totals
    var actorNames: [String: String] = [:]
    var cidActor: [String: String] = [:]

    init() {}

    private enum K: String, CodingKey { case offset, fp, name, calls, failures, cost, compactions, streak, bestStreak, intervals, days, actorNames, cidActor }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        offset = try c.decode(UInt64.self, forKey: .offset); fp = try c.decodeIfPresent(UInt64.self, forKey: .fp)
        name = try c.decode(String.self, forKey: .name)
        calls = try c.decode(Int.self, forKey: .calls); failures = try c.decode(Int.self, forKey: .failures)
        cost = try c.decode(Double.self, forKey: .cost); compactions = try c.decode(Int.self, forKey: .compactions)
        streak = try c.decode(Int.self, forKey: .streak); bestStreak = try c.decode(Int.self, forKey: .bestStreak)
        intervals = try c.decode([[Double]].self, forKey: .intervals).map { (Date(timeIntervalSinceReferenceDate: $0[0]), Date(timeIntervalSinceReferenceDate: $0[1])) }
        days = try c.decode([Double: [String: ActorAgg]].self, forKey: .days)
        actorNames = try c.decode([String: String].self, forKey: .actorNames); cidActor = try c.decode([String: String].self, forKey: .cidActor)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(offset, forKey: .offset); try c.encodeIfPresent(fp, forKey: .fp); try c.encode(name, forKey: .name)
        try c.encode(calls, forKey: .calls); try c.encode(failures, forKey: .failures); try c.encode(cost, forKey: .cost)
        try c.encode(compactions, forKey: .compactions); try c.encode(streak, forKey: .streak); try c.encode(bestStreak, forKey: .bestStreak)
        try c.encode(intervals.map { [$0.0.timeIntervalSinceReferenceDate, $0.1.timeIntervalSinceReferenceDate] }, forKey: .intervals)
        try c.encode(days, forKey: .days); try c.encode(actorNames, forKey: .actorNames); try c.encode(cidActor, forKey: .cidActor)
    }
}

struct AgentRow: Identifiable {
    let id: String
    let agent: String
    let session: String
    var ok: Int
    var failed: Int
    var cost: Double
    var successRate: Double { ok + failed > 0 ? Double(ok) / Double(ok + failed) : 1 }
}

struct TimelineRow: Identifiable {
    let id: String
    let name: String
    let intervals: [(Date, Date)]
}

struct DayReport {
    var sessions = 0, toolCalls = 0, failures = 0
    var credits = 0.0
    var leaderboard: [AgentRow] = []
    var timeline: [TimelineRow] = []
    var mvp: AgentRow? { leaderboard.max { $0.ok < $1.ok } }
    var bestStreak = 0
    var maxSessionCalls = 0
    var compactions = 0
    var nightOwl = false
}

/// Incrementally scans events.jsonl files (only appended bytes, only relevant lines) for day/lifetime metrics.
/// State is persisted (when `cacheURL` is set) so a relaunch only parses what was appended since.
final class MetricsScanner: @unchecked Sendable {
    static let shared = MetricsScanner(root: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/session-state"),
                                       cacheURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                        .appendingPathComponent("Hubbub/metrics-cache.json"))
    /// Posted (any thread) when a background catch-up finished and new numbers are available.
    static let didUpdate = Notification.Name("HubbubMetricsDidUpdate")

    private let root: URL
    private let cacheURL: URL?
    private let lock = NSLock()
    private var files: [String: FileMetrics] = [:]
    private var running = false
    private var queued: [String] = []
    private let queue = DispatchQueue(label: "hubbub.metrics", qos: .utility)
    private static let prefixes = ["{\"type\":\"tool.execution_", "{\"type\":\"session.usage_record\"", "{\"type\":\"session.compaction_complete\"",
                                   "{\"type\":\"subagent.started\"", "{\"type\":\"user.message\""].map { Array($0.utf8) }
    /// Appended bytes below this are parsed inline (keeps live sessions fresh); larger catch-ups go to the background queue.
    static let inlineBudget: UInt64 = 8 << 20

    init(root: URL, cacheURL: URL? = nil) {
        self.root = root; self.cacheURL = cacheURL
        if let cacheURL, let d = try? Data(contentsOf: cacheURL),
           let m = try? JSONDecoder().decode([String: FileMetrics].self, from: d) { files = m }
    }

    func metrics(for id: String) -> FileMetrics? { lock.lock(); defer { lock.unlock() }; return files[id] }

    private func pendingBytes(_ id: String) -> UInt64 {
        var st = stat()
        guard stat(root.appendingPathComponent(id).appendingPathComponent("events.jsonl").path, &st) == 0 else { return 0 }
        lock.lock(); let off = files[id]?.offset ?? 0; lock.unlock()
        let size = UInt64(st.st_size)
        return size >= off ? size - off : size
    }

    /// Small deltas are parsed before returning; big ones continue in the background and post `didUpdate`.
    func update(ids: [String], sync: Bool = false) {
        let pending = ids.reduce(UInt64(0)) { $0 + pendingBytes($1) }
        if pending == 0 { return }
        if sync || pending <= Self.inlineBudget {
            var changed = false
            for id in ids { changed = scan(id, pacer: nil) || changed }
            if changed { persist() }
            return
        }
        lock.lock()
        queued = ids
        if running { lock.unlock(); return }
        running = true; lock.unlock()
        queue.async { [self] in
            while true {
                lock.lock(); let batch = queued; queued = []; lock.unlock()
                if batch.isEmpty { break }
                let pacer = Pacer.background()
                for id in batch { _ = scan(id, pacer: pacer) }
                persist()
            }
            lock.lock(); running = false; lock.unlock()
            NotificationCenter.default.post(name: Self.didUpdate, object: nil)
        }
    }

    /// Blocks until a background catch-up (if any) finished.
    func waitIdle() {
        while true { lock.lock(); let r = running; lock.unlock(); if !r { return }; Thread.sleep(forTimeInterval: 0.02) }
    }

    private func persist() {
        guard let cacheURL else { return }
        lock.lock(); let snap = files; lock.unlock()
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(snap) { try? d.write(to: cacheURL, options: .atomic) }
    }

    @discardableResult
    private func scan(_ id: String, pacer: Pacer?) -> Bool {
        let dir = root.appendingPathComponent(id)
        let path = dir.appendingPathComponent("events.jsonl").path
        lock.lock(); var fm = files[id] ?? FileMetrics(); lock.unlock()
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        let size = UInt64(st.st_size)
        let fp = JSONL.fingerprint(path: path)
        // Replaced (shorter, or different head) rather than appended: start over
        if size < fm.offset || (fm.fp != nil && fm.fp != fp) { fm = FileMetrics() }
        fm.fp = fp
        if fm.name.isEmpty {
            fm.name = "Session " + id.prefix(6)
            if let yaml = try? String(contentsOf: dir.appendingPathComponent("workspace.yaml"), encoding: .utf8),
               let l = yaml.split(separator: "\n").first(where: { $0.hasPrefix("name: ") }) { fm.name = String(l.dropFirst(6)) }
        }
        guard size > fm.offset else { lock.lock(); files[id] = fm; lock.unlock(); return false }
        var day = DayCache()
        let r = JSONL.scan(path: path, from: fm.offset, uncached: size - fm.offset > 64 << 20, pacer: pacer,
                           wants: { p in Self.prefixes.contains { JSONL.hasPrefix(p, $0) } },
                           line: { p in autoreleasepool { if let o = JSONL.object(p) { Self.handle(o, &fm, &day) } } })
        if let r { fm.offset = r.endOffset }
        lock.lock(); files[id] = fm; lock.unlock()
        return true
    }

    /// Whole-file, in-memory reference implementation used by `--selftest-perf-data` to prove the streaming path equal.
    static func reference(path: String) -> FileMetrics {
        var fm = FileMetrics(), day = DayCache()
        guard let data = FileManager.default.contents(atPath: path) else { return fm }
        let complete = data.lastIndex(of: 10).map { data[data.startIndex...$0] } ?? data[data.startIndex..<data.startIndex]
        fm.offset = UInt64(complete.count)
        for line in complete.split(separator: 10, omittingEmptySubsequences: true) where prefixes.contains(where: { line.starts(with: $0) }) {
            if let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { handle(o, &fm, &day) }
        }
        return fm
    }

    private static func handle(_ o: [String: Any], _ fm: inout FileMetrics, _ dayCache: inout DayCache) {
        guard let type = o["type"] as? String, let ts = FastDate.parse(o["timestamp"] as? String) else { return }
        let d = o["data"] as? [String: Any] ?? [:]
        let actor = o["agentId"] as? String ?? "main"
        let day = dayCache.startOfDay(ts)
        switch type {
        case "subagent.started":
            if let aid = o["agentId"] as? String { fm.actorNames[aid] = d["agentDisplayName"] as? String ?? "Agent" }
            return
        case "session.compaction_complete":
            if d["success"] as? Bool != false { fm.compactions += 1 }
            return
        case "tool.execution_start":
            if let cid = d["toolCallId"] as? String { fm.cidActor[cid] = actor }
        case "tool.execution_complete":
            let cid = d["toolCallId"] as? String
            let who = cid.flatMap { fm.cidActor.removeValue(forKey: $0) } ?? actor
            if d["success"] as? Bool == false {
                fm.failures += 1; fm.streak = 0
                fm.days[day, default: [:]][who, default: ActorAgg()].failed += 1
            } else {
                fm.streak += 1; fm.bestStreak = max(fm.bestStreak, fm.streak)
                fm.days[day, default: [:]][who, default: ActorAgg()].ok += 1
            }
            fm.calls += 1
        case "session.usage_record":
            let c = (d["usage"] as? [String: Any])?["cost"] as? Double ?? 0
            fm.cost += c
            fm.days[day, default: [:]][actor, default: ActorAgg()].cost += c
        default: break
        }
        if let last = fm.intervals.last, ts.timeIntervalSince(last.1) <= 120, ts >= last.0 {
            fm.intervals[fm.intervals.count - 1].1 = max(last.1, ts)
        } else {
            fm.intervals.append((ts, ts))
            if fm.intervals.count > 400 { fm.intervals.removeFirst(100) }
        }
    }

    func todayReport() -> DayReport {
        let start = Calendar.current.startOfDay(for: Date())
        let key = start.timeIntervalSince1970
        lock.lock(); let snapshot = files; lock.unlock()
        var r = DayReport()
        for (id, fm) in snapshot {
            r.bestStreak = max(r.bestStreak, fm.bestStreak)
            r.maxSessionCalls = max(r.maxSessionCalls, fm.calls)
            r.compactions += fm.compactions
            let ivs = fm.intervals.filter { $0.1 >= start }.map { (max($0.0, start), $0.1) }
            if fm.intervals.contains(where: { $0.0 >= start && Calendar.current.component(.hour, from: $0.0) < 5 }) { r.nightOwl = true }
            guard let actors = fm.days[key] else { continue }
            r.sessions += 1
            r.timeline.append(TimelineRow(id: id, name: fm.name, intervals: ivs))
            for (a, agg) in actors {
                r.toolCalls += agg.ok + agg.failed; r.failures += agg.failed; r.credits += agg.cost
                r.leaderboard.append(AgentRow(id: id + a, agent: a == "main" ? "Captain" : (fm.actorNames[a] ?? "Agent"),
                                              session: fm.name, ok: agg.ok, failed: agg.failed, cost: agg.cost))
            }
        }
        r.leaderboard.sort { $0.ok > $1.ok }
        r.timeline.sort { ($0.intervals.first?.0 ?? .distantFuture) < ($1.intervals.first?.0 ?? .distantFuture) }
        return r
    }
}

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "streak10", icon: "🎯", title: "Flawless 10", detail: "10 tool calls in a row without failure"),
        Achievement(id: "marathon", icon: "🏃", title: "Marathon", detail: "A session open for more than 24 hours"),
        Achievement(id: "nightowl", icon: "🦉", title: "Night owl", detail: "Worked between midnight and 5 AM"),
        Achievement(id: "juggler", icon: "🤹", title: "Context juggler", detail: "Survived a context compaction"),
        Achievement(id: "centurion", icon: "💯", title: "Centurion", detail: "100 tool calls in one session"),
    ]
    private static let key = "achievementsUnlocked"

    static func unlocked() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    /// Persists newly earned achievements and returns them.
    static func evaluate(report: DayReport, sessions: [SessionInfo]) -> [Achievement] {
        var earned = Set<String>()
        if report.bestStreak >= 10 { earned.insert("streak10") }
        if sessions.contains(where: { $0.inUse && $0.age > 86400 }) { earned.insert("marathon") }
        if report.nightOwl { earned.insert("nightowl") }
        if report.compactions > 0 { earned.insert("juggler") }
        if report.maxSessionCalls >= 100 { earned.insert("centurion") }
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let fresh = all.filter { earned.contains($0.id) && raw[$0.id] == nil }
        for a in fresh { raw[a.id] = Date().timeIntervalSince1970 }
        if !fresh.isEmpty { UserDefaults.standard.set(raw, forKey: key) }
        return fresh
    }
}
