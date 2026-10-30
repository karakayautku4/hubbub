import Foundation

/// Tokens and credits attributed to one calendar day.
struct DayUsage: Codable, Equatable {
    var input = 0
    var output = 0
    var credits = 0.0
    var tokens: Int { input + output }

    static func + (a: DayUsage, b: DayUsage) -> DayUsage { DayUsage(input: a.input + b.input, output: a.output + b.output, credits: a.credits + b.credits) }
    func maxed(with o: DayUsage) -> DayUsage { DayUsage(input: max(input, o.input), output: max(output, o.output), credits: max(credits, o.credits)) }
}

enum DayKey {
    /// Local calendar day as "yyyy-MM-dd" (sorts chronologically).
    static func string(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Sums the gaps between consecutive event timestamps; a gap longer than `idleCap` counts as `idleCap` (the user was away).
struct ActiveClock {
    static let idleCap: TimeInterval = 30 * 60
    private var prev: Date?
    private(set) var total: TimeInterval = 0

    mutating func tick(_ t: Date) {
        guard let p = prev else { prev = t; return }
        if t > p { total += min(t.timeIntervalSince(p), Self.idleCap); prev = t }
    }
}

extension SessionRecord {
    /// Without any event timeline a session's duration is shown as at most this.
    static let unknownActiveCap: TimeInterval = 8 * 3600
    private static let maxSpreadDays = 366

    /// Active time, never longer than the wall-clock span. Records from before active time was tracked get a capped estimate.
    var activeDuration: TimeInterval? {
        guard let start = startedAt else { return active }
        let span = max(0, lastEvent.timeIntervalSince(start))
        return min(active ?? Self.unknownActiveCap, span)
    }

    /// Tokens/credits per local day. Exact when `days` was recorded from the event timeline (or from observed deltas);
    /// otherwise the lifetime total is spread evenly over the days between start and last event so one long session cannot inflate a single day.
    func usageByDay(calendar: Calendar = .current) -> [String: DayUsage] {
        if let days, !days.isEmpty { return days }
        let total = DayUsage(input: inputTokens, output: outputTokens, credits: credits)
        let last = calendar.startOfDay(for: lastEvent)
        let first = min(last, startedAt.map { calendar.startOfDay(for: $0) } ?? last)
        let n = min(Self.maxSpreadDays, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
        guard n > 1 else { return total.tokens == 0 && total.credits == 0 ? [:] : [DayKey.string(lastEvent, calendar: calendar): total] }
        var out: [String: DayUsage] = [:]
        for i in 0..<n {
            guard let d = calendar.date(byAdding: .day, value: -i, to: last) else { continue }
            var share = DayUsage(input: total.input / n, output: total.output / n, credits: total.credits / Double(n))
            if i == 0 { share.input += total.input % n; share.output += total.output % n }
            out[DayKey.string(d, calendar: calendar)] = share
        }
        return out
    }

    /// Share of this session that falls on or after `cutoff`'s day.
    func usage(since cutoff: Date, calendar: Calendar = .current) -> DayUsage {
        let key = DayKey.string(cutoff, calendar: calendar)
        return usageByDay(calendar: calendar).reduce(DayUsage()) { $1.key >= key ? $0 + $1.value : $0 }
    }

    /// Record for `s`, carrying forward what is known from `prev`.
    /// Sessions that report a per-day timeline (`dayUsage`) are merged day by day (monotonic: a sliding read window never lowers a day).
    /// Others get the growth since the previous snapshot attributed to the day it was observed.
    static func merged(prev: SessionRecord?, with s: SessionInfo, calendar: Calendar = .current) -> SessionRecord {
        var r = SessionRecord(s)
        if !s.dayUsage.isEmpty {
            var days = prev?.days ?? [:]
            for (k, v) in s.dayUsage { days[k] = days[k].map { $0.maxed(with: v) } ?? v }
            r.days = days
        } else if let prev {
            var days = prev.usageByDay(calendar: calendar)
            let delta = DayUsage(input: max(0, s.inputTokens - prev.inputTokens), output: max(0, s.outputTokens - prev.outputTokens),
                                 credits: max(0, s.costCredits - prev.credits))
            if delta.tokens > 0 || delta.credits > 0 {
                let k = DayKey.string(s.lastEvent, calendar: calendar)
                days[k] = (days[k] ?? DayUsage()) + delta
            }
            r.days = days.isEmpty ? nil : days
        }
        if let prev {
            let inc = min(max(0, s.lastEvent.timeIntervalSince(prev.lastEvent)), ActiveClock.idleCap)
            let carried = (prev.active ?? 0) + inc
            r.active = (prev.active != nil || s.activeSeconds != nil) ? max(s.activeSeconds ?? 0, carried) : nil
        }
        return r
    }
}
