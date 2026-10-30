import Foundation

struct QuotaSample: Codable { var t: Date; var used: Double; var reset: String }
struct DayValue: Identifiable { let day: Date; let value: Double; var id: Date { day } }
struct ModelUsage: Identifiable { let model: String; var requests: Double; var inputTokens: Int; var outputTokens: Int; var id: String { model } }
struct SessionUsage: Identifiable { let id: String; var name: String; var requests: Double; var lastUsed: Date }

struct SessionScan: Codable {
    var fp: UInt64?
    var size: Int = 0
    var offset: Int = 0
    var name: String = ""
    var last: Date = .distantPast
    var models: [String: [Double]] = [:]   // model -> [requests, input, output]
    var days: [String: Double] = [:]       // yyyy-MM-dd -> requests
}

@MainActor
final class UsageHistory: ObservableObject {
    static let shared = UsageHistory()
    @Published private(set) var samples: [QuotaSample] = []
    @Published private(set) var models: [ModelUsage] = []
    @Published private(set) var sessions: [SessionUsage] = []
    @Published private(set) var sessionDays: [String: Double] = [:]
    @Published private(set) var scanning = false

    nonisolated private static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Hubbub")
    nonisolated private static let samplesURL = dir.appendingPathComponent("quota-samples.json")
    nonisolated private static let scanURL = dir.appendingPathComponent("session-usage-cache.json")

    private init() {
        if let d = try? Data(contentsOf: Self.samplesURL) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode([QuotaSample].self, from: d) { samples = s } else {
                try? FileManager.default.removeItem(at: Self.samplesURL.appendingPathExtension("corrupt"))
                try? FileManager.default.moveItem(at: Self.samplesURL, to: Self.samplesURL.appendingPathExtension("corrupt"))
                samples = []
            }
        }
    }

    // MARK: samples & forecast

    func record(_ q: Quota) {
        guard !q.unlimited else { return }
        let now = Date()
        if let last = samples.last, last.used == q.used, last.reset == q.resetDate, now.timeIntervalSince(last.t) < 3600 { return }
        samples.append(QuotaSample(t: now, used: q.used, reset: q.resetDate))
        if samples.count > 5000 { samples.removeFirst(samples.count - 5000) }
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(samples) { try? d.write(to: Self.samplesURL, options: .atomic) }
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    func forecast(_ q: Quota, now: Date = Date()) -> String? {
        guard !q.unlimited, q.entitlement > 0, let reset = Self.parseDate(q.resetDate) else { return nil }
        let cal = Calendar.current
        let cycleStart = cal.date(byAdding: .month, value: -1, to: reset) ?? reset.addingTimeInterval(-30 * 86400)
        let elapsed = now.timeIntervalSince(cycleStart) / 86400
        guard elapsed >= 0.5, q.used > 0 else { return elapsed >= 0.5 ? "On track" : nil }
        let daily = q.used / elapsed
        let daysLeft = q.remaining / daily
        let runOut = now.addingTimeInterval(daysLeft * 86400)
        guard runOut < reset else { return "On track" }
        let before = max(1, Int((reset.timeIntervalSince(runOut) / 86400).rounded()))
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"
        return "At this pace: runs out ~\(f.string(from: runOut)) (\(before) day\(before == 1 ? "" : "s") before reset)"
    }

    /// Daily credits derived from deltas between consecutive samples of the same cycle.
    func dailyCredits(days: Int) -> [DayValue] {
        let cal = Calendar.current
        var perDay: [Date: Double] = [:]
        for (a, b) in zip(samples, samples.dropFirst()) where a.reset == b.reset && b.used >= a.used {
            perDay[cal.startOfDay(for: b.t), default: 0] += b.used - a.used
        }
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).map { DayValue(day: $0, value: perDay[$0] ?? 0) }
        }
    }

    /// Daily premium requests derived from session-state usage records.
    func dailySessionRequests(days: Int) -> [DayValue] {
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).map { DayValue(day: $0, value: sessionDays[f.string(from: $0)] ?? 0) }
        }
    }

    // MARK: session-state scan

    private var lastScan: Date?

    /// Reloads only when never scanned or the last scan is older than `minInterval` (unless `force`).
    /// The first run is a throttled background backfill (newest sessions first); partial results are published as they arrive.
    func scanSessions(force: Bool = false, minInterval: TimeInterval = 60) {
        guard !scanning else { return }
        if !force, let last = lastScan, Date().timeIntervalSince(last) < minInterval { return }
        scanning = true
        Task {
            let result = await Task.detached(priority: .utility) {
                Self.runScan(pacer: Pacer.background()) { partial in
                    Task { @MainActor in
                        UsageHistory.shared.sessions = partial.sessions; UsageHistory.shared.models = partial.models
                        UsageHistory.shared.sessionDays = partial.days
                    }
                }
            }.value
            sessions = result.sessions; models = result.models; sessionDays = result.days
            lastScan = Date()
            scanning = false
        }
    }

    typealias Aggregate = (sessions: [SessionUsage], models: [ModelUsage], days: [String: Double])
    nonisolated private static let usageMarker = Array("\"type\":\"session.usage_record\"".utf8)

    /// Incremental, indexed scan: only bytes appended since the persisted offset are read, newest files first.
    nonisolated static func runScan(root: URL? = nil, cacheURL: URL? = nil, pacer: Pacer? = nil, workers: Int = 1,
                                    progress: ((Aggregate) -> Void)? = nil) -> Aggregate {
        let fm = FileManager.default
        let root = root ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/session-state")
        let scanURL = cacheURL ?? Self.scanURL
        var cache: [String: SessionScan] = [:]
        if let d = try? Data(contentsOf: scanURL) { cache = (try? JSONDecoder().decode([String: SessionScan].self, from: d)) ?? [:] }

        struct Entry { let id: String; let size: Int; let mod: Double }
        var entries: [Entry] = []
        for id in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            var st = stat()
            guard stat(root.appendingPathComponent(id).appendingPathComponent("events.jsonl").path, &st) == 0 else { continue }
            entries.append(Entry(id: id, size: Int(st.st_size), mod: Double(st.st_mtimespec.tv_sec)))
        }
        entries.sort { $0.mod > $1.mod }
        let live = Set(entries.map(\.id))
        cache = cache.filter { live.contains($0.key) }

        let lock = NSLock()
        var lastPublish = Date(), lastSave = Date(), done = 0
        func save() {
            try? fm.createDirectory(at: scanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: scanURL, options: .atomic) }
        }
        let todo = entries.filter { e in
            guard let sc = cache[e.id] else { return true }
            return sc.name.isEmpty || e.size != sc.offset || sc.size != e.size
        }
        var taken = 0
        func next() -> Entry? { lock.lock(); defer { lock.unlock() }; guard taken < todo.count else { return nil }; taken += 1; return todo[taken - 1] }
        func work() {
            while let e = next() {
                lock.lock(); var sc = cache[e.id] ?? SessionScan(); lock.unlock()
                autoreleasepool { scanFile(root: root, id: e.id, size: e.size, sc: &sc, pacer: pacer) }
                lock.lock()
                cache[e.id] = sc; done += 1
                let now = Date()
                var snap: Aggregate?
                if let progress, now.timeIntervalSince(lastPublish) > 0.5 || done == todo.count { lastPublish = now; snap = aggregate(cache) }
                if now.timeIntervalSince(lastSave) > 3 { lastSave = now; save() }
                lock.unlock()
                if let snap { progress?(snap) }
            }
        }
        if workers > 1 { DispatchQueue.concurrentPerform(iterations: workers) { _ in work() } } else { work() }
        if !todo.isEmpty { save() }
        return aggregate(cache)
    }

    nonisolated private static func scanFile(root: URL, id: String, size: Int, sc: inout SessionScan, pacer: Pacer?) {
        let dir = root.appendingPathComponent(id)
        let path = dir.appendingPathComponent("events.jsonl").path
        if sc.name.isEmpty {
            let yaml = (try? String(contentsOf: dir.appendingPathComponent("workspace.yaml"), encoding: .utf8)) ?? ""
            var name = "", cwd = ""
            for line in yaml.split(separator: "\n") {
                if line.hasPrefix("name: ") { name = String(line.dropFirst(6)) }
                if line.hasPrefix("cwd: ") { cwd = String(line.dropFirst(5)) }
            }
            sc.name = !name.isEmpty ? name : ((cwd as NSString).lastPathComponent.isEmpty ? String(id.prefix(8)) : (cwd as NSString).lastPathComponent)
        }
        let fp = JSONL.fingerprint(path: path)
        if size < sc.offset || (sc.fp != nil && sc.fp != fp) { sc = SessionScan(name: sc.name) }
        sc.fp = fp
        if size > sc.offset {
            let marker = usageMarker
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
            let r = JSONL.scan(path: path, from: UInt64(sc.offset), uncached: size - sc.offset > 64 << 20, pacer: pacer,
                               wants: { JSONL.contains($0, marker, within: marker.count + 8) },
                               line: { p in
                guard p.count > marker.count else { return }
                autoreleasepool {
                    guard let obj = JSONL.object(p), let u = (obj["data"] as? [String: Any])?["usage"] as? [String: Any] else { return }
                    let model = u["model"] as? String ?? "unknown"
                    let cost = (u["cost"] as? NSNumber)?.doubleValue ?? 0
                    var m = sc.models[model] ?? [0, 0, 0]
                    m[0] += cost
                    m[1] += (u["inputTokens"] as? NSNumber)?.doubleValue ?? 0
                    m[2] += (u["outputTokens"] as? NSNumber)?.doubleValue ?? 0
                    sc.models[model] = m
                    if let ts = obj["timestamp"] as? String, let date = FastDate.parseFractional(ts) {
                        sc.days[f.string(from: date), default: 0] += cost
                        sc.last = max(sc.last, date)
                    }
                }
            })
            if let r { sc.offset = Int(r.endOffset) }
        }
        sc.size = size
    }

    nonisolated static func aggregate(_ cache: [String: SessionScan]) -> Aggregate {
        var models: [String: ModelUsage] = [:]
        var days: [String: Double] = [:]
        var sessions: [SessionUsage] = []
        for id in cache.keys.sorted() {
            let sc = cache[id]!
            var total = 0.0
            for m in sc.models.keys.sorted() {
                let v = sc.models[m]!
                total += v[0]
                var mu = models[m] ?? ModelUsage(model: m, requests: 0, inputTokens: 0, outputTokens: 0)
                mu.requests += v[0]; mu.inputTokens += Int(v[1]); mu.outputTokens += Int(v[2])
                models[m] = mu
            }
            for d in sc.days.keys.sorted() { days[d, default: 0] += sc.days[d]! }
            if total > 0 { sessions.append(SessionUsage(id: id, name: sc.name, requests: total, lastUsed: sc.last)) }
        }
        return (sessions.sorted { $0.requests != $1.requests ? $0.requests > $1.requests : $0.id < $1.id },
                models.values.sorted { $0.requests != $1.requests ? $0.requests > $1.requests : $0.model < $1.model }, days)
    }

    nonisolated private static func localDay(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
