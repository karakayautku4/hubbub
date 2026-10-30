import Foundation

/// `Hubbub --selftest-prodfeatures`: cost projection math, search/filter, snapshot round-trip and privacy redaction (fixtures only).
@MainActor
enum ProdFeaturesSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) { if !cond { print("FAIL \(name)"); ok = false } else { print("ok   \(name)") } }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let reset = cal.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let now = start.addingTimeInterval(10 * 86400)

        // Projection: 100 used in 10 days of a 31-day cycle -> 10/day -> 310
        let p = CostProjector.project(used: 100, limit: 300, cycleStart: start, reset: reset, now: now, recentDaily: Array(repeating: 10, count: 7))!
        check("projection linear", abs(p.projected - 310) < 0.01)
        check("projection over", p.level == .over && p.exhaustDate != nil)
        check("projection confidence high", p.confidence == .high)
        let fast = CostProjector.project(used: 100, limit: 300, cycleStart: start, reset: reset, now: now, recentDaily: [30, 30, 30, 30, 30, 30, 30])!
        check("recent pace blends in", fast.projected > p.projected && abs(fast.projected - (100 + 20 * 21)) < 0.01)
        let spiky = CostProjector.project(used: 100, limit: 1000, cycleStart: start, reset: reset, now: now, recentDaily: [0, 0, 0, 0, 0, 0, 70])!
        check("spiky usage lowers confidence", spiky.confidence == .medium)
        check("ok level", CostProjector.project(used: 50, limit: 1000, cycleStart: start, reset: reset, now: now)!.level == .ok)
        check("too early", CostProjector.project(used: 5, limit: 300, cycleStart: start, reset: reset, now: start.addingTimeInterval(3600)) == nil)
        check("early = low confidence", CostProjector.project(used: 5, limit: 300, cycleStart: start, reset: reset, now: start.addingTimeInterval(86400))!.confidence == .low)
        check("summary text", CostProjector.summary(p).contains("310 of 300") && CostProjector.summary(p).contains("resets in 21 days"))
        let w = CostProjector.projectWindow(percentUsed: 30, resetsAt: now.addingTimeInterval(3.5 * 86400), windowSeconds: 7 * 86400, now: now)!
        check("window projection", abs(w.percent - 60) < 0.01 && w.confidence == .high)
        check("window label", CostProjector.windowSeconds(label: "5 hours") == 18000 && CostProjector.windowSeconds(label: "Weekly Opus") == 604800)
        let noon = cal.date(byAdding: .hour, value: 12, to: start)!
        check("daily pace", abs((CostProjector.dailyPace(spent: 5, limit: 8, now: noon, calendar: cal) ?? 0) - 10) < 0.01)
        check("daily pace needs data", CostProjector.dailyPace(spent: 5, limit: 8, now: start.addingTimeInterval(1800), calendar: cal) == nil)

        // Search / filter
        let t0 = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var a = SessionRecord(id: "a", provider: "copilot", name: "Fix login bug", cwd: "/Users/x/webapp", model: "gpt-x", state: "working", tokens: 5000, credits: 3, lastEvent: t0)
        a.failed = false
        let b = SessionRecord(id: "b", provider: "claude", name: "Refactor parser", cwd: "/Users/x/compiler", model: "sonnet-x", state: "idle", tokens: 9000, credits: 0, lastEvent: t0.addingTimeInterval(-3 * 86400))
        var c = SessionRecord(id: "c", provider: "codex", name: "Résumé export", cwd: "/Users/x/webapp", model: "o-x", state: "offline", tokens: 100, credits: 0, lastEvent: t0.addingTimeInterval(-40 * 86400))
        c.failed = true
        var meta = SessionMeta()
        meta.favorites = ["b"]; meta.tags = ["c": ["urgent"]]; meta.notes = ["a": "blocked on API keys"]
        let all = [a, b, c]
        func q(_ f: SessionFilter) -> [String] { SessionSearch.apply(all, meta: meta, filter: f, now: t0).map(\.id) }
        check("favorites pinned first", q(SessionFilter()) == ["b", "a", "c"])
        check("title search", q(SessionFilter(query: "login")) == ["a"])
        check("folder search", q(SessionFilter(query: "webapp")) == ["a", "c"])
        check("multi-token AND", q(SessionFilter(query: "webapp copilot")) == ["a"])
        check("diacritics folded", q(SessionFilter(query: "resume")) == ["c"])
        check("note search", q(SessionFilter(query: "api keys")) == ["a"])
        check("tag search", q(SessionFilter(query: "#urg")) == ["c"])
        check("provider filter", q(SessionFilter(providers: ["claude"])) == ["b"])
        check("date filter", q(SessionFilter(range: .week)) == ["b", "a"])
        check("status filter", q(SessionFilter(status: .failed)) == ["c"] && q(SessionFilter(status: .working)) == ["a"])
        check("favorites only", q(SessionFilter(favoritesOnly: true)) == ["b"])
        check("no match", q(SessionFilter(query: "zzz")).isEmpty)
        let groups = SessionSearch.grouped(SessionSearch.apply(all, meta: meta, filter: SessionFilter(), now: t0), meta: meta)
        check("group by project", groups.map(\.project) == ["compiler", "webapp"] && groups[1].items.count == 2)
        check("tag parsing", SessionSearch.parseTags(" #Bug, bug ,, review ") == ["Bug", "review"])
        let rows = UsageComparison.byProvider(all, since: t0.addingTimeInterval(-7 * 86400))
        check("comparison", rows.map(\.key) == ["claude", "copilot"] && rows[1].credits == 3)

        // Library persistence round-trip (no shared state)
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-prod/prod-selftest-\(getpid())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = SessionLibrary(dir: dir)
        lib.toggleFavorite("a"); lib.setTags("a", ["x", "y"]); lib.setNote("a", "hello")
        lib.flush()
        let lib2 = SessionLibrary(dir: dir)
        check("meta persisted", lib2.isFavorite("a") && lib2.tags("a") == ["x", "y"] && lib2.note("a") == "hello")

        // Snapshot: redaction, round-trip, hostile input
        var s1 = SessionInfo(id: "secret-session-id", name: "Customer-X payroll migration", cwd: "/Users/x/private", model: "m",
                             lastEvent: t0, state: .working, currentTool: nil, subagents: [], inputTokens: 1200, outputTokens: 300, toolCalls: 4)
        s1.provider = "claude"
        let anon = SyncCodec.makeSnapshot([s1], options: SyncOptions(), machineId: "m-1", machineName: "MacBook-Work", now: t0)
        let text = String(data: SyncCodec.encode(anon)!, encoding: .utf8)!
        check("titles hidden by default", anon.sessions[0].title == nil && !text.contains("payroll"))
        check("no paths or raw ids", !text.contains("/Users") && !text.contains("secret-session-id") && !text.contains("private"))
        let open = SyncCodec.makeSnapshot([s1], options: SyncOptions(shareTitles: true, shareTokens: false), machineId: "m-1", machineName: "MacBook-Work", now: t0)
        check("opt-in title, tokens off", open.sessions[0].title == "Customer-X payroll migration" && open.sessions[0].inputTokens == nil)
        var idle = s1; idle.state = .idle
        check("only active", SyncCodec.makeSnapshot([s1, idle], options: SyncOptions(onlyActive: true), machineId: "m-1", machineName: "n", now: t0).sessions.count == 1)

        let folder = dir.appendingPathComponent("shared")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        check("write", SyncCodec.write(anon, to: folder))
        check("write to missing folder fails", !SyncCodec.write(anon, to: dir.appendingPathComponent("nope")))
        var other = anon; other.machineId = "m-2"; other.machineName = "Studio"; other.sessions[0].id = "abc123"
        check("write other", SyncCodec.write(other, to: folder))
        let read = SyncCodec.readOthers(in: folder, excluding: "m-1", now: t0)
        check("reads only other machines", read.count == 1 && read[0].machineName == "Studio")
        let recs = SyncCodec.records(from: read[0])
        check("remote flagged with machine", recs.count == 1 && recs[0].machine == "Studio" && recs[0].inputTokens == 1200 && recs[0].name.contains("abc1"))
        check("round-trip equal", SyncCodec.decode(SyncCodec.encode(anon)!, now: t0) == anon)

        let bad = "{\"version\":1,\"machineId\":\"x\",\"machineName\":\"Evil\\u0007Name\",\"generatedAt\":\"2026-01-01T00:00:00Z\",\"sessions\":[{\"id\":\"../../z\",\"provider\":\"Co pilot\",\"title\":\"t\\u0000t\",\"state\":\"bogus\",\"inputTokens\":-5,\"lastEvent\":\"2026-01-01T00:00:00Z\"}]}"
        let nowBad = ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z")!
        let sd = SyncCodec.decode(Data(bad.utf8), now: nowBad)
        check("sanitizes hostile file", sd != nil && sd!.machineName == "EvilName" && sd!.sessions[0].id == "z" && sd!.sessions[0].provider == "copilot"
              && sd!.sessions[0].title == "tt" && sd!.sessions[0].state == "idle" && sd!.sessions[0].inputTokens == 0)
        check("stale snapshot ignored", SyncCodec.decode(Data(bad.utf8), now: nowBad.addingTimeInterval(30 * 86400)) == nil)
        check("garbage ignored", SyncCodec.decode(Data("nope".utf8)) == nil && SyncCodec.decode(Data(count: SyncCodec.maxFileBytes + 1)) == nil)

        print(ok ? "PRODFEATURES SELFTEST PASSED" : "PRODFEATURES SELFTEST FAILED")
        return ok
    }
}
