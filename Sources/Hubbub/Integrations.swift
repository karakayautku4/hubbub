import Foundation

/// A parsed `hubbub://` deep link.
enum HubbubRoute: Equatable {
    case open
    case session(String)
    case settings(String?)
    case theme(String)
    case refresh
    case insights
    case history
    case achievements
}

enum HubbubURL {
    /// Accepts `hubbub://open`, `session/<id>`, `settings[/<tab>]`, `theme/<name>`, `refresh`, `insights`, `history`, `achievements`.
    static func parse(_ url: URL) -> HubbubRoute? {
        guard url.scheme?.lowercased() == "hubbub" else { return nil }
        var parts: [String] = []
        if let h = url.host, !h.isEmpty { parts.append(h) }
        parts += url.path.split(separator: "/").map(String.init)
        parts = parts.map { $0.removingPercentEncoding ?? $0 }
        guard let head = parts.first?.lowercased() else { return .open }
        let arg = parts.count > 1 ? parts[1] : nil
        switch head {
        case "open": return .open
        case "refresh": return .refresh
        case "insights": return .insights
        case "history": return .history
        case "achievements", "awards": return .achievements
        case "session":
            guard let arg, !arg.isEmpty else { return nil }
            return .session(arg)
        case "theme":
            guard let arg, !arg.isEmpty else { return nil }
            return .theme(arg)
        case "settings":
            guard let arg else { return .settings(nil) }
            let tab = arg.lowercased()
            if ["sound", "sync", "about"].contains(tab) { return .settings(SettingsTab.advanced.rawValue) }
            guard SettingsTab(rawValue: tab) != nil else { return nil }
            return .settings(tab)
        default: return nil
        }
    }
}

extension Theme {
    /// Matches a `hubbub://theme/<x>` argument against raw values and titles, ignoring case, spaces and punctuation ("sneaky-ship", "Spell Academy").
    static func named(_ name: String) -> Theme? {
        func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }
        let n = norm(name)
        guard !n.isEmpty else { return nil }
        return allCases.first { norm($0.rawValue) == n || norm($0.title) == n }
    }
}

/// Plain-text and JSON rendering of the current state, used by `--status`.
enum StatusFormat {
    struct QuotaInfo { var percentUsed: Double; var used: Double; var entitlement: Double; var resetDate: String; var plan: String; var unlimited: Bool }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(n / 1000)K" }
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }

    static func text(sessions: [SessionInfo], quota: QuotaInfo?, providerName: (String) -> String) -> String {
        var lines: [String] = []
        let working = sessions.filter { $0.state == .working }.count
        lines.append("Sessions: \(sessions.count) (\(working) working)")
        for s in sessions.sorted(by: { $0.lastEvent > $1.lastEvent }) {
            var l = "  [\(s.state.rawValue)] \(s.name) · \(providerName(s.provider)) · \(compact(s.inputTokens + s.outputTokens)) tokens"
            if s.failures > 0 { l += " · \(s.failures) failed" }
            if s.waitingApproval { l += " · needs approval" }
            lines.append(l)
        }
        if let q = quota {
            if q.unlimited { lines.append("Quota: unlimited") }
            else {
                var l = "Quota: \(Int(q.percentUsed.rounded()))% used (\(Int(q.used)) of \(Int(q.entitlement)))"
                if !q.resetDate.isEmpty { l += " · resets \(q.resetDate)" }
                lines.append(l + " [cached]")
            }
        } else { lines.append("Quota: unavailable") }
        return lines.joined(separator: "\n")
    }

    static func json(sessions: [SessionInfo], quota: QuotaInfo?) -> String {
        let iso = ISO8601DateFormatter()
        let list: [[String: Any]] = sessions.sorted { $0.lastEvent > $1.lastEvent }.map { s in
            ["id": s.id, "name": s.name, "provider": s.provider, "state": s.state.rawValue, "model": s.model, "cwd": s.cwd,
             "inputTokens": s.inputTokens, "outputTokens": s.outputTokens, "toolCalls": s.toolCalls, "failures": s.failures,
             "waitingApproval": s.waitingApproval, "lastEvent": iso.string(from: s.lastEvent)]
        }
        var root: [String: Any] = ["sessions": list, "working": sessions.filter { $0.state == .working }.count, "total": sessions.count]
        if let q = quota {
            root["quota"] = ["percentUsed": q.percentUsed, "used": q.used, "entitlement": q.entitlement,
                             "resetDate": q.resetDate, "plan": q.plan, "unlimited": q.unlimited, "cached": true] as [String: Any]
        }
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Last quota the app cached in UserDefaults (the CLI never hits the network).
    static func cachedQuota() -> QuotaInfo? {
        guard let d = UserDefaults.standard.dictionary(forKey: "cachedQuota") else { return nil }
        func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        return QuotaInfo(percentUsed: 100 - num("percentRemaining"), used: num("used"), entitlement: num("entitlement"),
                         resetDate: d["resetDate"] as? String ?? "", plan: d["plan"] as? String ?? "", unlimited: d["unlimited"] as? Bool ?? false)
    }

    /// `Hubbub --status [--json]`: prints and exits without starting the UI.
    static func runCLI(json wantsJSON: Bool) -> Never {
        let sessions = SessionMonitor.scan()
        let quota = cachedQuota()
        print(wantsJSON ? json(sessions: sessions, quota: quota)
                        : text(sessions: sessions, quota: quota, providerName: { ProviderRegistry.shared.name(for: $0) }))
        exit(0)
    }
}

/// End-of-day summary numbers and wording.
enum DailySummary {
    struct Result: Equatable { var sessions: Int; var failures: Int; var tokens: Int; var topProvider: String? }

    static func compute(_ sessions: [SessionInfo], now: Date, calendar: Calendar = .current) -> Result {
        let today = sessions.filter { calendar.isDate($0.lastEvent, inSameDayAs: now) }
        var byProvider: [String: Int] = [:]
        for s in today { byProvider[s.provider, default: 0] += 1 }
        let top = byProvider.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
        return Result(sessions: today.count, failures: today.reduce(0) { $0 + $1.failures },
                      tokens: today.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }, topProvider: top)
    }

    static func text(_ r: Result, providerName: (String) -> String) -> String {
        var s = "\(r.sessions) session\(r.sessions == 1 ? "" : "s"), \(r.failures) failure\(r.failures == 1 ? "" : "s"), \(StatusFormat.compact(r.tokens)) tokens"
        if let p = r.topProvider { s += ", top provider \(providerName(p))" }
        return s
    }
}

/// Quiet-hours window arithmetic (minutes since midnight; wraps past midnight when start > end).
enum QuietHours {
    static func contains(minute: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static func minuteOfDay(_ d: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

enum IntegrationSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL \(m)"); ok = false } }
        func p(_ s: String) -> HubbubRoute? { URL(string: s).flatMap(HubbubURL.parse) }
        check(p("hubbub://open") == .open, "open")
        check(p("hubbub://") == .open, "bare scheme opens")
        check(p("hubbub://session/abc-123") == .session("abc-123"), "session")
        check(p("hubbub:///session/abc") == .session("abc"), "triple slash")
        check(p("hubbub://session") == nil, "session needs id")
        check(p("hubbub://settings") == .settings(nil), "settings")
        check(p("hubbub://settings/Alerts") == .settings("alerts"), "settings tab case-insensitive")
        check(p("hubbub://settings/bogus") == nil, "unknown tab rejected")
        for legacy in ["sound", "sync", "about"] { check(p("hubbub://settings/\(legacy)") == .settings("advanced"), "legacy \(legacy) tab maps to advanced") }
        check(SettingsTab.migrated("about") == .advanced && SettingsTab.migrated("sync") == .advanced, "stored legacy tab migrates")
        check(p("hubbub://theme/wizard") == .theme("wizard"), "theme")
        check(p("hubbub://theme/my%20theme") == .theme("my theme"), "theme percent-decoded")
        check(p("hubbub://refresh") == .refresh, "refresh")
        check(p("hubbub://INSIGHTS") == .insights, "insights")
        check(p("hubbub://achievements") == .achievements && p("hubbub://Awards") == .achievements, "achievements")
        check(p("hubbub://nope") == nil, "unknown route")
        check(p("https://example.com") == nil, "foreign scheme")

        func s(_ id: String, provider: String, tokens: Int, fails: Int, ageHours: Double = 0, now: Date) -> SessionInfo {
            SessionInfo(id: id, name: id, cwd: "/x", model: "m", lastEvent: now.addingTimeInterval(-ageHours * 3600), state: .idle,
                        currentTool: nil, subagents: [], inputTokens: tokens, outputTokens: 0, toolCalls: 5, failures: fails, provider: provider)
        }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 18))!
        let list = [s("a", provider: "copilot", tokens: 900_000, fails: 2, now: now), s("b", provider: "copilot", tokens: 300_000, fails: 1, now: now),
                    s("c", provider: "claude", tokens: 5, fails: 0, now: now), s("old", provider: "claude", tokens: 99, fails: 9, ageHours: 48, now: now)]
        let r = DailySummary.compute(list, now: now, calendar: cal)
        check(r == DailySummary.Result(sessions: 3, failures: 3, tokens: 1_200_005, topProvider: "copilot"), "summary numbers \(r)")
        check(DailySummary.text(r, providerName: { $0.capitalized }) == "3 sessions, 3 failures, 1.2M tokens, top provider Copilot", "summary text")
        check(DailySummary.text(.init(sessions: 1, failures: 0, tokens: 950, topProvider: nil), providerName: { $0 }) == "1 session, 0 failures, 950 tokens", "summary singular")
        check(StatusFormat.compact(12_345) == "12K" && StatusFormat.compact(1500) == "1.5K", "compact")

        check(QuietHours.contains(minute: 23 * 60, start: 22 * 60, end: 7 * 60), "quiet late evening")
        check(QuietHours.contains(minute: 3 * 60, start: 22 * 60, end: 7 * 60), "quiet after midnight")
        check(!QuietHours.contains(minute: 12 * 60, start: 22 * 60, end: 7 * 60), "not quiet midday")
        check(QuietHours.contains(minute: 13 * 60, start: 12 * 60, end: 14 * 60), "non-wrapping window")
        check(!QuietHours.contains(minute: 5, start: 100, end: 100), "empty window")

        let one = FocusGuard.catchUp([.init(title: "Done", body: "Finished", sessionID: "x", id: "i")])
        check(one == nil, "single held item is replayed as-is")
        let many = FocusGuard.catchUp([.init(title: "A", body: "", sessionID: nil, id: "1"), .init(title: "B", body: "", sessionID: nil, id: "2"), .init(title: "A", body: "", sessionID: nil, id: "3")])
        check(many?.title == "3 notifications while you were away" && many?.body == "A (2), B", "catch-up text \(String(describing: many))")

        let js = StatusFormat.json(sessions: list, quota: .init(percentUsed: 42, used: 42, entitlement: 100, resetDate: "x", plan: "p", unlimited: false))
        let obj = (try? JSONSerialization.jsonObject(with: Data(js.utf8))) as? [String: Any]
        check((obj?["total"] as? Int) == 4 && (obj?["quota"] as? [String: Any]) != nil, "status json")
        check(StatusFormat.text(sessions: list, quota: nil, providerName: { $0 }).contains("Quota: unavailable"), "status text")
        print(ok ? "integration selftest OK" : "integration selftest FAILED")
        return ok
    }
}
