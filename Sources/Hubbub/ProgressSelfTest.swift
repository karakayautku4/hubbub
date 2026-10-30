import Foundation

/// `Hubbub --selftest-progress`: fixture-based checks of XP, levels, achievements, scoreboard and cosmetics (no real data).
enum ProgressSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) { if !cond { print("FAIL \(name)"); ok = false } else { print("ok   \(name)") } }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func at(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: 30))! }
        func session(_ id: String, provider: String = "copilot", state: SessionState = .working, calls: Int = 0, fails: Int = 0,
                     tokens: Int = 0, subs: Int = 0, inUse: Bool = true, last: Date, start: Date? = nil, credits: Double = 0) -> SessionInfo {
            var s = SessionInfo(id: id, name: "S-\(id)", cwd: "/x/\(id)", model: "model-a", lastEvent: last, state: state, currentTool: nil,
                                subagents: (0..<subs).map { SubAgent(id: "a\($0)", name: "a", displayName: "a", model: "m", startedAt: last) },
                                inputTokens: tokens, outputTokens: 0, toolCalls: calls)
            s.failures = fails; s.inUse = inUse; s.provider = provider; s.startedAt = start; s.costCredits = credits
            return s
        }

        // Levels
        check("level 1 at 0 xp", Levels.level(forXP: 0) == 1)
        check("level 2 at 100", Levels.level(forXP: 100) == 2 && Levels.level(forXP: 99) == 1)
        check("level 5 at 1000", Levels.level(forXP: 1000) == 5)
        check("titles per theme", Levels.title(level: 5, themeRaw: "kitchen") == "Sous Chef" && Levels.title(level: 1, themeRaw: "custom") == "Rookie")

        // Baseline: old idle sessions grant nothing
        var d = ProgressData()
        let now = at(10, 14)
        var r = d.ingest([session("old", state: .idle, calls: 50, inUse: false, last: at(8, 10), start: at(8, 9))], now: now, cal: cal)
        check("old session baselined", d.xp == 0 && d.sessionsCompleted == 0 && d.tasks == 0 && r.events.isEmpty)
        r = d.ingest([session("old", state: .idle, calls: 50, inUse: false, last: at(8, 10), start: at(8, 9))], now: now, cal: cal)
        check("idempotent ingest", !r.changed)

        // A live session: calls, a finished task, completion
        d = ProgressData()
        _ = d.ingest([session("a", calls: 10, fails: 2, tokens: 25_000, last: now, start: now)], now: now, cal: cal)
        check("xp from calls + tokens", d.xp == 8 * 1 + 2 && d.toolCalls == 10)
        _ = d.ingest([session("a", state: .idle, calls: 10, fails: 2, tokens: 25_000, last: now, start: now)], now: now, cal: cal)
        check("task on working→idle", d.tasks == 1 && d.xp == 10 + 10)
        r = d.ingest([session("a", state: .idle, calls: 10, fails: 2, tokens: 25_000, inUse: false, last: now, start: now)], now: now, cal: cal)
        check("session completion + First Blood", d.sessionsCompleted == 1 && r.events.contains(.achievement("first_blood")))
        check("achievement bonus xp", d.xp == 20 + 50 + 100)
        r = d.ingest([session("a", state: .idle, calls: 10, fails: 2, tokens: 25_000, inUse: false, last: now, start: now)], now: now, cal: cal)
        check("completion counted once", d.sessionsCompleted == 1 && r.events.isEmpty)

        // Achievements
        d = ProgressData()
        _ = d.ingest([session("p1", provider: "copilot", subs: 10, last: now, start: now.addingTimeInterval(-7300)),
                      session("p2", provider: "claude", last: now), session("p3", provider: "codex", last: now)], now: now, cal: cal)
        check("Polyglot", d.unlocked["polyglot"] != nil)
        check("Sub-agent Army", d.unlocked["sub_army"] != nil)
        check("Marathon 2h", d.unlocked["marathon"] != nil)
        var night = ProgressData()
        _ = night.ingest([session("n", last: at(10, 2))], now: at(10, 2), cal: cal)
        check("Night Owl", night.unlocked["night_owl"] != nil)
        check("no Night Owl by day", d.unlocked["night_owl"] == nil)

        var clean = ProgressData()
        _ = clean.ingest([session("c", calls: 30, last: now)], now: now, cal: cal)
        check("Zero Failures Day", clean.unlocked["zero_failures"] != nil)

        var boss = ProgressData()
        for day in 1...7 {
            _ = boss.ingest([session("b\(day)", calls: 3, last: at(day, 12), credits: 2)], now: at(day, 12), dailyLimit: 10, cal: cal)
        }
        check("Budget Boss after 7 days", boss.unlocked["budget_boss"] != nil && boss.budgetStreak(now: at(7, 12), cal: cal) == 7)
        _ = boss.ingest([session("b8", calls: 3, last: at(8, 12), credits: 50)], now: at(8, 12), dailyLimit: 10, cal: cal)
        check("budget streak resets when exceeded", boss.budgetStreak(now: at(8, 12), cal: cal) == 0)

        // Scoreboard
        var sb = ProgressData()
        _ = sb.ingest([session("fast", provider: "claude", calls: 0, last: now, start: now)], now: now.addingTimeInterval(-600), cal: cal)
        _ = sb.ingest([session("fast", provider: "claude", calls: 20, fails: 0, last: now, start: now),
                       session("slow", provider: "copilot", calls: 6, fails: 3, last: now)], now: now, cal: cal)
        let board = Scoreboard.board(sb, days: 1, now: now, cal: cal)
        check("scoreboard totals", board.calls == 26 && board.failures == 3)
        check("scoreboard top provider", board.topProvider?.name == "claude" && board.topModel?.name == "model-a")
        check("scoreboard cleanest", board.cleanest?.id == "fast")

        // Persistence + cosmetics
        if let blob = try? JSONEncoder().encode(boss), let back = try? JSONDecoder().decode(ProgressData.self, from: blob) {
            check("json round trip", back == boss)
        } else { check("json round trip", false) }
        check("cosmetics gated by level", Progression.unlockedCosmetics(level: 2, enabled: true).isEmpty
              && Progression.unlockedCosmetics(level: 3, enabled: true) == ["hat.star"]
              && Progression.unlockedCosmetics(level: 20, enabled: false).isEmpty)

        print(ok ? "PROGRESS SELFTEST PASSED" : "PROGRESS SELFTEST FAILED")
        return ok
    }
}
