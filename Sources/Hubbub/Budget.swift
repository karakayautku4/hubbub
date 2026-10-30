import Foundation
import SwiftUI

/// Pure threshold/dedupe logic, kept separate so it can be self-tested.
enum BudgetLogic {
    static let thresholds = [80, 100]

    /// Returns thresholds newly crossed (not in `fired`) for the given spend.
    static func newlyCrossed(spent: Double, limit: Double, fired: Set<Int>) -> [Int] {
        guard limit > 0 else { return [] }
        let pct = spent / limit * 100
        return thresholds.filter { pct >= Double($0) && !fired.contains($0) }
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

@MainActor
final class BudgetCenter: ObservableObject {
    static let shared = BudgetCenter()
    static let dailyKey = "budgetDaily", sessionKey = "budgetSession", unitKey = "budgetUnit", pauseKey = "budgetPause"
    private static let firedKey = "budgetFired"

    @Published private(set) var dailySpent = 0.0
    @Published private(set) var sessionSpent: [String: Double] = [:]
    /// True while any enabled budget is exceeded (drives the optional menu bar "!").
    @Published private(set) var exceeded = false

    private let d = UserDefaults.standard
    var dailyLimit: Double { d.double(forKey: Self.dailyKey) }
    var sessionLimit: Double { d.double(forKey: Self.sessionKey) }
    var tokenMode: Bool { d.string(forKey: Self.unitKey) == "tokens" }
    var showWarning: Bool { exceeded && d.bool(forKey: Self.pauseKey) }
    var unit: String { tokenMode ? "k tok" : "cr" }

    private func spend(_ s: SessionInfo) -> Double {
        tokenMode ? Double(s.inputTokens + s.outputTokens) / 1000 : s.costCredits
    }

    /// Called whenever the session list changes.
    func update(_ sessions: [SessionInfo]) {
        guard dailyLimit > 0 || sessionLimit > 0 else {
            if exceeded { exceeded = false }
            return
        }
        let cal = Calendar.current
        let today = sessions.filter { cal.isDateInToday($0.lastEvent) }
        var daily = today.reduce(0) { $0 + spend($1) }
        if !tokenMode, let q = UsageHistory.shared.dailyCredits(days: 1).last?.value { daily = max(daily, q) }
        var per: [String: Double] = [:]
        for s in sessions { per[s.id] = spend(s) }
        dailySpent = daily
        sessionSpent = per

        var over = dailyLimit > 0 && daily >= dailyLimit
        var fired = d.dictionary(forKey: Self.firedKey) as? [String: [Int]] ?? [:]
        let todayKey = "d|" + BudgetLogic.dayKey(Date())
        fired = fired.filter { !$0.key.hasPrefix("d|") || $0.key == todayKey }
        func check(_ key: String, _ spent: Double, _ limit: Double, _ title: String, _ what: String) {
            let done = Set(fired[key] ?? [])
            let hit = BudgetLogic.newlyCrossed(spent: spent, limit: limit, fired: done)
            guard !hit.isEmpty else { return }
            fired[key] = Array(done.union(hit)).sorted()
            let t = hit.max()!
            Notifier.shared.post(t >= 100 ? "\(title) budget reached" : "\(title) budget at \(t)%",
                                 "\(what): \(fmt(spent)) of \(fmt(limit))")
        }
        check(todayKey, daily, dailyLimit, "Daily", "Today")
        if sessionLimit > 0 {
            for s in today { // only sessions active today can cross
                let v = per[s.id] ?? 0
                if v >= sessionLimit { over = true }
                check("s|" + s.id, v, sessionLimit, "Session", s.name)
            }
        }
        d.set(fired, forKey: Self.firedKey)
        if over != exceeded { exceeded = over }
    }

    func fmt(_ v: Double) -> String { tokenMode ? String(format: "%.0fk tok", v) : String(format: "%.1f cr", v) }
}

/// Small progress chip(s) for the info panel; empty when no budget is configured.
struct BudgetChip: View {
    var sessionID: String? = nil
    @ObservedObject private var budget = BudgetCenter.shared

    private func color(_ f: Double) -> Color { f >= 1 ? .red : (f >= 0.8 ? .orange : .green) }

    private func row(_ label: String, _ spent: Double, _ limit: Double) -> some View {
        let f = spent / limit
        return HStack(spacing: 6) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            MiniBar(fraction: f, color: color(f), height: 4).frame(width: 60)
            Text("\(budget.fmt(spent)) / \(budget.fmt(limit))").font(.caption2.monospacedDigit()).foregroundStyle(color(f))
        }
    }

    var body: some View {
        let showDaily = budget.dailyLimit > 0
        let sv = sessionID.flatMap { budget.sessionSpent[$0] }
        if showDaily || (budget.sessionLimit > 0 && sv != nil) {
            HStack(spacing: 10) {
                Text("BUDGET").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                if showDaily { row("DAY", budget.dailySpent, budget.dailyLimit) }
                if budget.sessionLimit > 0, let sv { row("SESSION", sv, budget.sessionLimit) }
                Spacer(minLength: 0)
            }
        }
    }
}

struct BudgetSettingsView: View {
    @AppStorage(BudgetCenter.dailyKey) private var daily = 0.0
    @AppStorage(BudgetCenter.sessionKey) private var session = 0.0
    @AppStorage(BudgetCenter.unitKey) private var unit = "credits"
    @AppStorage(BudgetCenter.pauseKey) private var pause = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Unit", selection: $unit) {
                Text("Credits (Copilot)").tag("credits")
                Text("Thousand tokens (any provider)").tag("tokens")
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Daily").font(.caption).frame(width: 50, alignment: .leading)
                TextField("off", value: limit($daily), format: .number).frame(width: 70).textFieldStyle(.roundedBorder)
                Text("Per session").font(.caption).frame(width: 70, alignment: .leading)
                TextField("off", value: limit($session), format: .number).frame(width: 70).textFieldStyle(.roundedBorder)
            }
            Toggle("Show “!” in the menu bar when a budget is exceeded", isOn: $pause)
        }
        .onChange(of: unit) { _ in UserDefaults.standard.removeObject(forKey: "budgetFired"); recheck() }
        .onChange(of: daily) { _ in recheck() }
        .onChange(of: session) { _ in recheck() }
    }

    /// An empty or invalid field means "no limit" (0) instead of keeping the previous value.
    private func limit(_ b: Binding<Double>) -> Binding<Double?> {
        Binding(get: { b.wrappedValue > 0 ? b.wrappedValue : nil },
                set: { v in b.wrappedValue = v.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0 })
    }

    /// Limits changed: re-evaluate now so the menu bar "!" and alerts don't wait for the next session update.
    private func recheck() { BudgetCenter.shared.update(AppModel.shared.monitor.sessions) }
}

enum BudgetSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) { if !cond { print("FAIL \(name)"); ok = false } else { print("ok   \(name)") } }
        check("below", BudgetLogic.newlyCrossed(spent: 50, limit: 100, fired: []).isEmpty)
        check("80", BudgetLogic.newlyCrossed(spent: 80, limit: 100, fired: []) == [80])
        check("both", BudgetLogic.newlyCrossed(spent: 120, limit: 100, fired: []) == [80, 100])
        check("dedupe", BudgetLogic.newlyCrossed(spent: 120, limit: 100, fired: [80]) == [100])
        check("all fired", BudgetLogic.newlyCrossed(spent: 500, limit: 100, fired: [80, 100]).isEmpty)
        check("no limit", BudgetLogic.newlyCrossed(spent: 500, limit: 0, fired: []).isEmpty)
        print(ok ? "BUDGET SELFTEST PASSED" : "BUDGET SELFTEST FAILED")
        return ok
    }
}
