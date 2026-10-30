import Foundation

/// The single place user-facing numbers are formatted. Decimal separators follow `locale`.
enum Fmt {
    static let none = "—"

    private static func dec(_ v: Double, _ digits: Int, _ locale: Locale) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)).locale(locale).grouping(.never))
    }

    /// 842 · 9.8k · 123k · 1.2M · 123M
    static func tokens(_ n: Int, locale: Locale = .current) -> String {
        let n = max(0, n)
        if n < 1000 { return "\(n)" }
        let d = Double(n)
        if n < 10_000 {
            let k = (d / 100).rounded() / 10
            return k >= 10 ? "10k" : dec(k, 1, locale) + "k"
        }
        if n < 1_000_000 {
            let k = (d / 1000).rounded()
            return k >= 1000 ? "1M" : dec(k, 0, locale) + "k"
        }
        let m = d / 1e6
        if m >= 100 { return dec(m.rounded(), 0, locale) + "M" }
        let r = (m * 10).rounded() / 10
        return r >= 100 ? "100M" : dec(r, 1, locale) + "M"
    }

    /// Integer percent of a 0…1 fraction, capped at 100%. nil / NaN → "—".
    static func percent(_ fraction: Double?, locale: Locale = .current) -> String {
        guard let f = fraction, f.isFinite else { return none }
        return dec(min(100, max(0, (f * 100).rounded())), 0, locale) + "%"
    }

    /// Percent already expressed as 0…100.
    static func percentValue(_ p: Double?, locale: Locale = .current) -> String {
        guard let p, p.isFinite else { return none }
        return percent(p / 100, locale: locale)
    }

    /// Up to one decimal, ".0" dropped: 4.4 · 566
    static func credits(_ c: Double, locale: Locale = .current) -> String {
        c.isFinite ? dec(max(0, c), 1, locale) : none
    }

    /// "4.4 cr" for list cells.
    static func creditsShort(_ c: Double, locale: Locale = .current) -> String { credits(c, locale: locale) + " cr" }

    /// $0.42 · $12.3 · $123. Estimates carry a "~" prefix. Below one cent: "<$0.01".
    static func usd(_ v: Double, estimated: Bool, locale: Locale = .current) -> String {
        guard v.isFinite, v >= 0 else { return none }
        let p = estimated ? "~" : ""
        if v > 0 && v < 0.01 { return p + "<$0.01" }
        if v < 10 { return p + "$" + v.formatted(.number.precision(.fractionLength(2)).locale(locale).grouping(.never)) }
        if v < 100 { return p + "$" + v.formatted(.number.precision(.fractionLength(1)).locale(locale).grouping(.never)) }
        return p + "$" + v.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    /// 45s · 12m · 2h 05m · 3d 4h (two units at most)
    static func duration(_ t: TimeInterval) -> String {
        guard t.isFinite else { return none }
        let s = max(0, Int(t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h " + String(format: "%02d", s % 3600 / 60) + "m" }
        return "\(s / 86400)d \(s % 86400 / 3600)h"
    }

    /// now · 5m ago · 2h ago · Yesterday · Oct 26
    static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s) / 60)m ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(s) / 3600)h ago" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }

    /// Day-section header: Today / Yesterday / Oct 26
    static func day(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
    }

    /// "126k / 200k" – tooltips and Details only.
    static func pair(_ used: Int, _ limit: Int, locale: Locale = .current) -> String {
        limit > 0 ? "\(tokens(used, locale: locale)) / \(tokens(limit, locale: locale))" : tokens(used, locale: locale)
    }

    /// VoiceOver wording: "3.2 million", "310 thousand".
    static func spoken(_ n: Int) -> String {
        n >= 1_000_000 ? "\(dec(Double(n) / 1e6, 1, Locale(identifier: "en_US"))) million"
            : n >= 1000 ? "\(Int((Double(n) / 1000).rounded())) thousand" : "\(n)"
    }
}
