import Foundation

/// Achievement definition; `progress` is evaluated from the incrementally maintained `ProgressData`, never from raw logs.
struct BadgeDef: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let target: Int
    let progress: (ProgressData, _ now: Date, _ cal: Calendar) -> (current: Int, label: String)

    init(_ id: String, _ icon: String, _ title: String, _ detail: String, target: Int,
         unit: String = "", value: @escaping (ProgressData, Date, Calendar) -> Int) {
        self.id = id; self.icon = icon; self.title = title; self.detail = detail; self.target = target
        self.progress = { d, now, cal in
            let v = value(d, now, cal)
            return (v, "\(min(v, target)) / \(target)\(unit)")
        }
    }
}

enum BadgeCatalog {
    static let all: [BadgeDef] = [
        BadgeDef("first_blood", "🩸", "First Blood", "Complete your first session", target: 1) { d, _, _ in d.sessionsCompleted },
        BadgeDef("tasks_100", "💯", "100 Tasks", "Finish 100 agent tasks", target: 100) { d, _, _ in d.tasks },
        BadgeDef("night_owl", "🦉", "Night Owl", "Work with an agent between midnight and 5 AM", target: 1) { d, _, _ in d.nightOwl ? 1 : 0 },
        BadgeDef("zero_failures", "🧼", "Zero Failures Day", "25 tool calls in a day without a single failure", target: 25) { d, _, _ in
            d.days.values.filter { $0.failures == 0 }.map(\.calls).max() ?? 0
        },
        BadgeDef("marathon", "🏃", "Marathon", "Keep one session going for 2 hours", target: 120, unit: " min") { d, _, _ in
            Int(d.longestSessionSec / 60)
        },
        BadgeDef("polyglot", "🌍", "Polyglot", "Use 3 different providers", target: 3) { d, _, _ in d.providers.count },
        BadgeDef("budget_boss", "💰", "Budget Boss", "Stay under your daily budget on 7 active days in a row (set a budget in Settings › Alerts)", target: 7, unit: " days") { d, now, cal in
            d.budgetStreak(now: now, cal: cal)
        },
        BadgeDef("sub_army", "🪖", "Sub-agent Army", "Run 10 sub-agents in one session", target: 10) { d, _, _ in d.maxSubs },
        BadgeDef("centurion", "🎯", "Centurion", "100 tool calls in a single session", target: 100) { d, _, _ in d.maxSessionCalls },
        BadgeDef("token_hoard", "🪙", "Token Hoarder", "Burn through 1 million tokens", target: 1_000_000) { d, _, _ in d.tokens },
        BadgeDef("level_10", "🏆", "Double Digits", "Reach level 10", target: 10) { d, _, _ in d.level },
    ]

    static func def(_ id: String) -> BadgeDef? { all.first { $0.id == id } }
}
