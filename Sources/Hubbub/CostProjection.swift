import Foundation
import SwiftUI

// MARK: - Pure projection math (self-tested)

enum ProjectionConfidence: Int, Comparable, Equatable {
    case low, medium, high
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var title: String { ["low", "medium", "high"][rawValue] }
    var lowered: Self { Self(rawValue: max(0, rawValue - 1)) ?? .low }
}

enum ProjectionLevel: Equatable { case ok, warn, over }

struct CostProjection: Equatable {
    var used: Double
    var limit: Double
    var projected: Double
    var projectedLow: Double
    var projectedHigh: Double
    var daysLeft: Double
    var confidence: ProjectionConfidence
    var level: ProjectionLevel
    /// Only set when the limit is predicted to run out before the reset.
    var exhaustDate: Date?
    var resetDate: Date
}

enum CostProjector {
    /// Linear projection to the end of a quota cycle. `recentDaily` = credits per full day for the latest days of the cycle.
    /// The rate blends the cycle average with the recent average, so a changed pace is picked up without being jumpy.
    static func project(used: Double, limit: Double, cycleStart: Date, reset: Date, now: Date,
                        recentDaily: [Double] = []) -> CostProjection? {
        guard limit > 0, used >= 0, reset > cycleStart else { return nil }
        let elapsed = now.timeIntervalSince(cycleStart) / 86400
        let daysLeft = max(0, reset.timeIntervalSince(now) / 86400)
        guard elapsed >= 0.5 else { return nil }
        let avg = used / elapsed
        let recent: Double? = recentDaily.count >= 3 ? recentDaily.reduce(0, +) / Double(recentDaily.count) : nil
        let rate = recent.map { ($0 + avg) / 2 } ?? avg
        let lo = min(avg, recent ?? avg * 0.75), hi = max(avg, recent ?? avg * 1.25)
        let projected = used + rate * daysLeft

        var conf: ProjectionConfidence = elapsed < 2 ? .low : (elapsed < 7 || recent == nil ? .medium : .high)
        if let r = recent, r > 0 {
            let mean = r
            let variance = recentDaily.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recentDaily.count)
            if variance.squareRoot() / mean > 1.2 { conf = conf.lowered }
        }

        var exhaust: Date?
        if rate > 0, used < limit {
            let d = (limit - used) / rate
            if d < daysLeft { exhaust = now.addingTimeInterval(d * 86400) }
        }
        let level: ProjectionLevel = (projected >= limit || used >= limit) ? .over : (projected >= limit * 0.9 ? .warn : .ok)
        return CostProjection(used: used, limit: limit, projected: projected,
                              projectedLow: used + lo * daysLeft, projectedHigh: used + hi * daysLeft,
                              daysLeft: daysLeft, confidence: conf, level: level, exhaustDate: exhaust, resetDate: reset)
    }

    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    /// Percent-based windows of non-Copilot providers: scales the used percentage by the elapsed share of the window.
    static func projectWindow(percentUsed: Double, resetsAt: Date, windowSeconds: Double, now: Date) -> (percent: Double, confidence: ProjectionConfidence)? {
        guard windowSeconds > 0, resetsAt > now else { return nil }
        let left = resetsAt.timeIntervalSince(now)
        let frac = 1 - min(1, left / windowSeconds)
        guard frac >= 0.05 else { return nil }
        let conf: ProjectionConfidence = frac < 0.2 ? .low : (frac < 0.5 ? .medium : .high)
        return (percentUsed / frac, conf)
    }

    static func windowSeconds(label: String) -> Double? {
        let l = label.lowercased()
        if l.hasPrefix("weekly") { return 7 * 86400 }
        if l.hasPrefix("monthly") { return 30 * 86400 }
        let parts = l.split(separator: " ")
        guard parts.count == 2, let n = Double(parts[0]) else { return nil }
        if parts[1].hasPrefix("hour") { return n * 3600 }
        if parts[1].hasPrefix("day") { return n * 86400 }
        return nil
    }

    /// Daily budget pace: spend so far scaled to the whole day. Needs a few hours of data to be meaningful.
    static func dailyPace(spent: Double, limit: Double, now: Date, calendar: Calendar = .current) -> Double? {
        guard limit > 0, spent > 0 else { return nil }
        let start = calendar.startOfDay(for: now)
        let frac = now.timeIntervalSince(start) / 86400
        guard frac >= 0.125 else { return nil }
        return spent / frac
    }

    static func summary(_ p: CostProjection, unit: String = "credits", now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "MMM d"
        let days = max(0, Int(p.daysLeft.rounded(.up)))
        let tail = "resets in \(days) day\(days == 1 ? "" : "s")"
        return "At this pace you'll use \(Int(p.projected.rounded())) of \(Int(p.limit.rounded())) \(unit) by \(f.string(from: p.resetDate)) · \(tail)"
    }
}

// MARK: - Per-provider / per-model comparison (local data only)

struct UsageRow: Identifiable, Equatable {
    var key: String
    var sessions = 0
    var credits = 0.0
    var tokens = 0
    var id: String { key }
}

enum UsageComparison {
    static func byProvider(_ records: [SessionRecord], since: Date) -> [UsageRow] { aggregate(records, since: since) { $0.provider } }
    static func byModel(_ records: [SessionRecord], since: Date) -> [UsageRow] {
        aggregate(records, since: since) { $0.model.isEmpty ? "unknown" : $0.model }
    }

    private static func aggregate(_ records: [SessionRecord], since: Date, key: (SessionRecord) -> String) -> [UsageRow] {
        var rows: [String: UsageRow] = [:]
        for r in records where r.lastEvent >= since && r.machine == nil {
            let u = r.usage(since: since)
            var row = rows[key(r)] ?? UsageRow(key: key(r))
            row.sessions += 1; row.credits += u.credits; row.tokens += u.tokens
            rows[row.key] = row
        }
        return rows.values.sorted { ($0.tokens, $0.credits) > ($1.tokens, $1.credits) }
    }
}

// MARK: - Live state + alerts

@MainActor
final class CostProjectionCenter: ObservableObject {
    static let shared = CostProjectionCenter()
    @Published private(set) var copilot: CostProjection?
    /// Over-pace daily spend (same unit as the daily budget), when a daily budget is set and the pace exceeds it.
    @Published private(set) var dailyPace: Double?
    private var lastRun = Date.distantPast
    private static let alertKey = "projectionAlerted"

    /// Reads the cached quota (kept fresh by QuotaService) and the local daily history. Cheap; throttled.
    func refresh(force: Bool = false, now: Date = Date()) {
        guard force || now.timeIntervalSince(lastRun) > 30 else { return }
        lastRun = now
        let d = UserDefaults.standard.dictionary(forKey: "cachedQuota")
        func num(_ k: String) -> Double { (d?[k] as? NSNumber)?.doubleValue ?? 0 }
        var next: CostProjection?
        if let d, d["unlimited"] as? Bool != true, let reset = CostProjector.parseDay(d["resetDate"] as? String ?? "") {
            let cal = Calendar.current
            let start = cal.date(byAdding: .month, value: -1, to: reset) ?? reset.addingTimeInterval(-30 * 86400)
            let recent = UsageHistory.shared.dailyCredits(days: 8).dropLast().filter { $0.day >= cal.startOfDay(for: start) }.map(\.value)
            next = CostProjector.project(used: num("used"), limit: num("entitlement"), cycleStart: start, reset: reset, now: now, recentDaily: Array(recent))
        }
        if next != copilot { copilot = next }

        let b = BudgetCenter.shared
        let pace = CostProjector.dailyPace(spent: b.dailySpent, limit: b.dailyLimit, now: now)
        let over = pace.flatMap { $0 >= b.dailyLimit && b.dailySpent < b.dailyLimit ? $0 : nil }
        if over != dailyPace { dailyPace = over }
        alert(resetKey: d?["resetDate"] as? String ?? "", now: now)
    }

    /// One notification per cycle / day, only while the budget or quota is not exceeded yet.
    private func alert(resetKey: String, now: Date) {
        let defaults = UserDefaults.standard
        var done = Set(defaults.stringArray(forKey: Self.alertKey) ?? [])
        let day = BudgetLogic.dayKey(now)
        done = done.filter { $0.hasSuffix(resetKey) || $0.hasSuffix(day) }
        func fire(_ key: String, _ title: String, _ body: String) {
            guard !done.contains(key) else { return }
            done.insert(key)
            Notifier.shared.post(title, body)
        }
        if let p = copilot, p.level == .over, p.used < p.limit, p.confidence >= .medium {
            fire("copilot|" + resetKey, "Copilot quota projected to run out", CostProjector.summary(p))
        }
        if let pace = dailyPace {
            let b = BudgetCenter.shared
            fire("daily|" + day, "Daily budget on pace to be exceeded", "Today: \(b.fmt(b.dailySpent)) so far, on pace for \(b.fmt(pace)) of \(b.fmt(b.dailyLimit))")
        }
        defaults.set(Array(done), forKey: Self.alertKey)
    }
}

// MARK: - Views

/// Subtle one-liner for the quota header.
struct ProjectionLine: View {
    @ObservedObject private var center = CostProjectionCenter.shared

    var body: some View {
        Group {
            if let p = center.copilot {
                Text(p.level == .ok ? "On pace for \(Fmt.credits(p.projected.rounded())) of \(Fmt.credits(p.limit.rounded())) credits by reset"
                                    : "⚠︎ Pace → \(Fmt.credits(p.projected.rounded())) of \(Fmt.credits(p.limit.rounded())) credits by reset")
                    .font(HubFont.caption).foregroundStyle(p.level == .ok ? Color.secondary : Color.orange).lineLimit(1)
                    .help(CostProjector.summary(p) + " · \(p.confidence.title) confidence")
            }
        }
        .onAppear { center.refresh() }
    }
}

struct CostProjectionCard: View {
    @ObservedObject private var center = CostProjectionCenter.shared
    @ObservedObject private var library = SessionLibrary.shared
    @ObservedObject private var providers = ProviderQuotaService.shared
    @State private var byModel = false

    private var monthAgo: Date { Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date() }
    private func color(_ l: ProjectionLevel) -> Color { l == .over ? .red : (l == .warn ? .orange : .green) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cost projection").font(HubFont.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if let p = center.copilot { Chip(text: "\(p.confidence.title) confidence", color: .secondary) }
            }
            if let p = center.copilot {
                MiniBar(fraction: p.projected / p.limit, color: color(p.level), height: 6)
                Text(CostProjector.summary(p)).font(HubFont.caption).foregroundStyle(color(p.level) == .green ? Color.primary : color(p.level))
                    .fixedSize(horizontal: false, vertical: true)
                if let e = p.exhaustDate {
                    Text("Credits would run out around \(e.formatted(.dateTime.month(.abbreviated).day())).").font(HubFont.caption).foregroundStyle(.orange)
                }
            } else {
                Text("Needs a Copilot quota reading and about a day of usage in the cycle.").font(HubFont.caption).foregroundStyle(.secondary)
            }
            if let pace = center.dailyPace {
                let b = BudgetCenter.shared
                Text("Daily budget: on pace for \(b.fmt(pace)) of \(b.fmt(b.dailyLimit)) today.").font(HubFont.caption).foregroundStyle(.orange)
            }
            windows
            comparison
        }
        .onAppear { center.refresh(force: true) }
    }

    @ViewBuilder private var windows: some View {
        let now = Date()
        ForEach(providers.active, id: \.self) { id in
            if let q = providers.states[id]?.quota {
                ForEach(q.windows.indices, id: \.self) { i in
                    let w = q.windows[i]
                    if let pct = w.percentUsed, let r = w.resetsAt, let secs = CostProjector.windowSeconds(label: w.label),
                       let pr = CostProjector.projectWindow(percentUsed: pct, resetsAt: r, windowSeconds: secs, now: now) {
                        HStack(spacing: 4) {
                            ProviderBadge(provider: id)
                            Text("\(ProviderRegistry.shared.name(for: id)) · \(w.label): ~\(Fmt.percentValue(min(pr.percent, 999))) by reset (\(pr.confidence.title) confidence)")
                                .font(HubFont.caption).foregroundStyle(pr.percent >= 100 ? Color.orange : Color.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var comparison: some View {
        let rows = byModel ? UsageComparison.byModel(library.records, since: monthAgo) : UsageComparison.byProvider(library.records, since: monthAgo)
        if !rows.isEmpty {
            HStack {
                Text("Last 30 days · local data").font(HubFont.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $byModel) { Text("Provider").tag(false); Text("Model").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 130).controlSize(.mini)
            }
            let maxTok = Double(max(1, rows.map(\.tokens).max() ?? 1))
            ForEach(rows.prefix(5)) { r in
                HStack(spacing: 6) {
                    Text(byModel ? r.key : ProviderRegistry.shared.name(for: r.key)).font(HubFont.caption).lineLimit(1).frame(width: 110, alignment: .leading)
                    MiniBar(fraction: Double(r.tokens) / maxTok, color: .blue, height: 4)
                    Text("\(Fmt.creditsShort(r.credits)) · \(Fmt.tokens(r.tokens)) tok").font(HubFont.captionDigits).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
