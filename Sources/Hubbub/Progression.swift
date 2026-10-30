import Foundation
import SwiftUI

// MARK: Data model (all local, JSON in Application Support)

/// Per-session high-water marks so every update only has to look at deltas.
struct ProgressMark: Codable, Equatable {
    var provider: String
    var calls = 0, failures = 0, tokens = 0
    var credits = 0.0
    var callsAtTask = 0
    var working = false
    var counted = false          // completion already credited
    var lastSeen = 0.0
}

/// One session's contribution to one day (feeds the scoreboard).
struct ProgressRow: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var provider: String
    var model: String
    var calls = 0, failures = 0, tasks = 0
    var firstSeen = 0.0, lastSeen = 0.0

    var activeSeconds: Double { max(0, lastSeen - firstSeen) }
    /// Seconds per tool call; nil when there is too little data to be meaningful.
    var secondsPerCall: Double? { calls >= 5 && activeSeconds > 0 ? activeSeconds / Double(calls) : nil }
}

struct ProgressDay: Codable, Equatable {
    var tasks = 0, calls = 0, failures = 0
    var credits = 0.0
    var rows: [String: ProgressRow] = [:]
    var providers: [String: Int] = [:]
    var models: [String: Int] = [:]
    var budgetLimit = 0.0
    var underBudget = false
}

struct ProgressData: Codable, Equatable {
    var xp = 0
    var tasks = 0, sessionsCompleted = 0, toolCalls = 0, tokens = 0
    var providers: [String] = []
    var maxSubs = 0, maxSessionCalls = 0
    var longestSessionSec = 0.0
    var nightOwl = false
    var unlocked: [String: Double] = [:]
    var marks: [String: ProgressMark] = [:]
    var days: [String: ProgressDay] = [:]
}

enum ProgressEvent: Equatable {
    case achievement(String)
    case levelUp(Int)
}

// MARK: Levels

enum Levels {
    /// Cumulative XP needed to *reach* `level`: 50·L·(L−1) → L2 = 100, L3 = 300, L5 = 1000, L10 = 4500.
    static func threshold(_ level: Int) -> Int { 50 * level * (level - 1) }

    static func level(forXP xp: Int) -> Int {
        var l = 1
        while threshold(l + 1) <= xp { l += 1 }
        return l
    }

    /// Progress inside the current level: (xp into level, xp the level spans).
    static func progress(xp: Int) -> (into: Int, span: Int) {
        let l = level(forXP: xp)
        return (xp - threshold(l), threshold(l + 1) - threshold(l))
    }

    private static let tiers: [String: [String]] = [
        "space": ["Rookie Cadet", "Navigator", "Pilot", "Flight Officer", "Commander", "Admiral", "Star Legend"],
        "kitchen": ["Rookie Cook", "Line Cook", "Sous Chef", "Station Chef", "Head Chef", "Executive Chef", "Culinary Legend"],
        "prison": ["Newcomer", "Trusty", "Block Rep", "Warden's Aide", "Deputy Warden", "Warden", "Yard Legend"],
        "football": ["Rookie", "Reserve", "Starter", "Playmaker", "Team Captain", "Head Coach", "Hall of Famer"],
        "farm": ["Farmhand", "Shepherd", "Barn Boss", "Harvester", "Farm Manager", "Master Farmer", "Legendary Farmer"],
        "impostor": ["Fresh Recruit", "Shipmate", "Engineer", "Sharp Eye", "Task Master", "Ship Captain", "Ship Legend"],
        "wizard": ["Novice", "Apprentice", "Adept", "Conjurer", "Sorcerer", "Archmage", "Grand Legend"],
        "galactic": ["Recruit", "Scout", "Pathfinder", "Captain", "Commodore", "Grand Marshal", "Galactic Legend"],
        "fellowship": ["Wanderer", "Traveler", "Ranger", "Guardian", "Lorekeeper", "Elder", "Legend of the Road"],
    ]
    private static let generic = ["Rookie", "Apprentice", "Regular", "Specialist", "Veteran", "Expert", "Legend"]

    static func tier(forLevel l: Int) -> Int {
        switch l { case ..<3: 0; case 3...4: 1; case 5...7: 2; case 8...11: 3; case 12...16: 4; case 17...22: 5; default: 6 }
    }

    static func title(level: Int, themeRaw: String) -> String {
        (tiers[themeRaw] ?? ThemeExtensions.active?.levelTitles(themeRaw) ?? generic)[tier(forLevel: level)]
    }
}

// MARK: Cosmetics

struct Cosmetic: Identifiable, Equatable {
    enum Kind: String { case hat, color, trail }
    let id: String
    let kind: Kind
    let name: String
    let level: Int
}

enum Progression {
    static let enabledKey = "progressionEnabled"
    static let levelKey = "progressionLevel"

    static let cosmetics: [Cosmetic] = [
        Cosmetic(id: "hat.star", kind: .hat, name: "Spinning star hat", level: 3),
        Cosmetic(id: "color.cyan", kind: .color, name: "Cyan glow", level: 5),
        Cosmetic(id: "trail.sparkle", kind: .trail, name: "Sparkle orbit", level: 8),
        Cosmetic(id: "color.gold", kind: .color, name: "Gold glow", level: 12),
        Cosmetic(id: "color.violet", kind: .color, name: "Violet glow", level: 16),
    ]

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    /// Mirrored into UserDefaults so scene code can read it from any context.
    static var level: Int { max(1, UserDefaults.standard.integer(forKey: levelKey)) }

    /// Identifiers of every cosmetic unlocked at the current level (empty when progression is off).
    static var unlockedCosmetics: [String] { unlockedCosmetics(level: level, enabled: enabled) }

    static func unlockedCosmetics(level: Int, enabled: Bool) -> [String] {
        enabled ? cosmetics.filter { $0.level <= level }.map(\.id) : []
    }
}

// MARK: Engine (pure; fixture-testable)

extension ProgressData {
    static let xpPerSuccessfulCall = 1
    static let xpPerTask = 10
    static let xpPerSession = 50
    static let xpPer10kTokens = 1
    static let xpPerAchievement = 100

    var level: Int { Levels.level(forXP: xp) }

    static func dayKey(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Consecutive active days (most recent first) that stayed within the daily budget. Days without activity are neutral.
    func budgetStreak(now: Date, cal: Calendar = .current) -> Int {
        var streak = 0
        for back in 0..<90 {
            guard let d = cal.date(byAdding: .day, value: -back, to: now), let day = days[Self.dayKey(d, cal)] else { continue }
            if day.budgetLimit > 0, day.underBudget { streak += 1 } else if day.budgetLimit > 0 || day.calls > 0 { break }
        }
        return streak
    }

    /// Folds the current session list into the totals. Only deltas since the previous call are credited.
    ///
    /// XP formula: 1 per successful tool call · 10 per finished task (agent goes working → idle after new calls)
    /// · 50 per completed session · 1 per 10k tokens · 100 per achievement.
    /// Sessions already idle before today when first seen are baselined (no XP) so history is not farmed retroactively.
    mutating func ingest(_ sessions: [SessionInfo], now: Date, dailyLimit: Double = 0, cal: Calendar = .current) -> (events: [ProgressEvent], changed: Bool) {
        let original = self
        let levelBefore = level
        let dayStart = cal.startOfDay(for: now)
        let key = Self.dayKey(now, cal)
        var day = days[key] ?? ProgressDay()
        var gained = 0
        let nowTS = now.timeIntervalSince1970

        for s in sessions {
            let end = s.inUse ? now : s.lastEvent
            if let st = s.startedAt { longestSessionSec = max(longestSessionSec, end.timeIntervalSince(st)) }
            if !s.provider.isEmpty, !providers.contains(s.provider) { providers.append(s.provider) }
            let tokens = s.inputTokens + s.outputTokens
            let done = (!s.inUse || s.state == .offline) && s.toolCalls > 0
            let working = s.state == .working

            guard var m = marks[s.id] else {
                var m = ProgressMark(provider: s.provider)
                m.lastSeen = nowTS
                m.working = working
                if s.lastEvent < dayStart {
                    m.calls = s.toolCalls; m.failures = s.failures; m.tokens = tokens; m.credits = s.costCredits
                    m.callsAtTask = s.toolCalls; m.counted = done
                    maxSessionCalls = max(maxSessionCalls, s.toolCalls); maxSubs = max(maxSubs, s.subagents.count)
                    marks[s.id] = m
                    continue
                }
                marks[s.id] = m
                apply(s, &m, &day, working: working, done: done, tokens: tokens, now: now, cal: cal, gained: &gained)
                marks[s.id] = m
                continue
            }
            m.lastSeen = nowTS
            apply(s, &m, &day, working: working, done: done, tokens: tokens, now: now, cal: cal, gained: &gained)
            marks[s.id] = m
        }

        if dailyLimit > 0 {
            day.budgetLimit = dailyLimit
            day.underBudget = day.credits <= dailyLimit
        }
        if day != (days[key] ?? ProgressDay()) { days[key] = day }
        xp = max(0, xp + gained)

        var events: [ProgressEvent] = []
        for _ in 0..<2 {
            for def in BadgeCatalog.all where unlocked[def.id] == nil {
                if def.progress(self, now, cal).current >= def.target {
                    unlocked[def.id] = nowTS
                    xp += Self.xpPerAchievement
                    events.append(.achievement(def.id))
                }
            }
        }
        let levelAfter = level
        if levelAfter > levelBefore { events.append(.levelUp(levelAfter)) }

        prune(now: now)
        return (events, self != original)
    }

    private mutating func apply(_ s: SessionInfo, _ m: inout ProgressMark, _ day: inout ProgressDay,
                                working: Bool, done: Bool, tokens: Int, now: Date, cal: Calendar, gained: inout Int) {
        let dCalls = max(0, s.toolCalls - m.calls)
        let dFail = min(dCalls, max(0, s.failures - m.failures))
        let dTok = max(0, tokens - m.tokens)
        let dCred = max(0, s.costCredits - m.credits)
        let hour = cal.component(.hour, from: now)
        if (working || dCalls > 0), hour < 5 { nightOwl = true }

        var dTasks = 0
        if m.working, !working, s.toolCalls > m.callsAtTask { dTasks = 1; m.callsAtTask = s.toolCalls }
        m.working = working

        gained += (dCalls - dFail) * Self.xpPerSuccessfulCall + dTasks * Self.xpPerTask
        gained += max(0, tokens / 10_000 - m.tokens / 10_000) * Self.xpPer10kTokens
        if done, !m.counted {
            m.counted = true
            sessionsCompleted += 1
            gained += Self.xpPerSession
        }

        toolCalls += dCalls; tasks += dTasks; self.tokens += dTok
        m.calls = max(m.calls, s.toolCalls); m.failures = max(m.failures, s.failures)
        m.tokens = max(m.tokens, tokens); m.credits = max(m.credits, s.costCredits)
        maxSessionCalls = max(maxSessionCalls, s.toolCalls)
        maxSubs = max(maxSubs, s.subagents.count)

        guard dCalls > 0 || dTasks > 0 || dCred > 0 || day.rows[s.id] != nil else { return }
        day.tasks += dTasks; day.calls += dCalls; day.failures += dFail; day.credits += dCred
        day.providers[s.provider, default: 0] += dCalls
        if !s.model.isEmpty { day.models[s.model, default: 0] += dCalls }
        var row = day.rows[s.id] ?? ProgressRow(id: s.id, name: s.name, provider: s.provider, model: s.model,
                                                firstSeen: now.timeIntervalSince1970)
        row.calls += dCalls; row.failures += dFail; row.tasks += dTasks
        row.lastSeen = max(row.lastSeen, now.timeIntervalSince1970)
        if !s.model.isEmpty { row.model = s.model }
        day.rows[s.id] = row
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-45 * 86400).timeIntervalSince1970
        if marks.contains(where: { $0.value.lastSeen < cutoff }) { marks = marks.filter { $0.value.lastSeen >= cutoff } }
        if days.count > 90 { for k in days.keys.sorted().dropLast(90) { days[k] = nil } }
    }
}

// MARK: Live center

struct ProgressToast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

@MainActor
final class ProgressionCenter: ObservableObject {
    static let shared = ProgressionCenter()

    @Published private(set) var data: ProgressData
    @Published var toasts: [ProgressToast] = []
    @Published private(set) var enabled: Bool

    private var lastSave = Date.distantPast
    private var dirty = false

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hubbub/progression.json")
    }

    private init() {
        enabled = Progression.enabled
        if let raw = try? Data(contentsOf: Self.fileURL) {
            if let d = try? JSONDecoder().decode(ProgressData.self, from: raw) { data = d } else {
                // Keep the unreadable file instead of overwriting it with a fresh start.
                try? FileManager.default.removeItem(at: Self.fileURL.appendingPathExtension("corrupt"))
                try? FileManager.default.moveItem(at: Self.fileURL, to: Self.fileURL.appendingPathExtension("corrupt"))
                data = ProgressData()
            }
        } else { data = ProgressData() }
        UserDefaults.standard.set(data.level, forKey: Progression.levelKey)
    }

    var level: Int { data.level }
    var themeRaw: String { Theme.resolve(UserDefaults.standard.string(forKey: "theme") ?? "").rawValue }
    var title: String { Levels.title(level: level, themeRaw: themeRaw) }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Progression.enabledKey)
    }

    func ingest(_ sessions: [SessionInfo]) {
        guard enabled else { return }
        let budget = BudgetCenter.shared
        let limit = budget.tokenMode ? 0 : budget.dailyLimit
        var d = data
        let r = d.ingest(sessions, now: Date(), dailyLimit: limit)
        guard r.changed else { return }
        data = d
        dirty = true
        UserDefaults.standard.set(d.level, forKey: Progression.levelKey)
        if !r.events.isEmpty { announce(r.events) }
        if !r.events.isEmpty || Date().timeIntervalSince(lastSave) > 20 { save() }
    }

    private func announce(_ events: [ProgressEvent]) {
        for e in events {
            switch e {
            case .achievement(let id):
                guard let def = BadgeCatalog.all.first(where: { $0.id == id }) else { continue }
                toasts.append(ProgressToast(icon: def.icon, title: "Achievement unlocked: \(def.title)", detail: def.detail))
            case .levelUp(let l):
                toasts.append(ProgressToast(icon: "⭐️", title: "Level \(l) — \(Levels.title(level: l, themeRaw: themeRaw))",
                                            detail: Progression.cosmetics.first { $0.level == l }.map { "New cosmetic: \($0.name)" } ?? "Keep it up!"))
            }
        }
        if toasts.count > 5 { toasts.removeFirst(toasts.count - 5) }
        SoundCenter.shared.play(.success)
    }

    func dismissToast(_ id: UUID) { toasts.removeAll { $0.id == id } }

    func save() {
        guard dirty else { return }
        dirty = false
        lastSave = Date()
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let blob = try? JSONEncoder().encode(data) { try? blob.write(to: url, options: .atomic) }
    }

    func reset() {
        data = ProgressData()
        toasts = []
        UserDefaults.standard.set(1, forKey: Progression.levelKey)
        dirty = true
        save()
    }
}
