import SwiftUI
import AppKit

// Cost estimation. Rules (see docs/COST.md):
//  • credits (Copilot premium requests) and USD are different units and are never added together;
//  • a dollar figure only exists when prices.json holds a row with both `source` and `asOf`;
//  • estimates are always prefixed "~" and labelled "est."; the shipped defaults contain no prices.

struct ModelPrice: Codable, Equatable {
    var match: String
    var inPerM: Double?
    var outPerM: Double?
    var cachedInPerM: Double?
    var source: String?
    var asOf: String?
    var note: String?

    /// A price is only usable when it names its source and date.
    var documented: Bool { !(source ?? "").isEmpty && PriceTable.parseDay(asOf) != nil }
}

struct CreditPrice: Codable, Equatable {
    var provider: String
    var usdPerCredit: Double?
    var source: String?
    var asOf: String?

    var documented: Bool { !(source ?? "").isEmpty && PriceTable.parseDay(asOf) != nil }
}

struct PriceFile: Codable, Equatable {
    var version = 1
    var currency = "USD"
    var models: [ModelPrice] = []
    var credits: [CreditPrice] = [CreditPrice(provider: "copilot", usdPerCredit: nil, source: nil, asOf: nil)]
}

enum CostEstimate: Equatable {
    case credits(Double)
    case usd(Double, estimated: Bool)
    case unknown
}

struct CostDisplay: Equatable {
    let value: String
    let sub: String?
    let hidden: Bool
    /// Compact cell for lists: "4.4 cr", "~$0.42", "—".
    var short: String = Fmt.none
    var tooltip: String? = nil
}

/// Credits and USD kept apart when several sessions are combined.
struct CostTotals: Equatable {
    var credits = 0.0
    var usd = 0.0
    var hasUSD = false
    var hasCredits: Bool { credits > 0 }
    var isEmpty: Bool { !hasCredits && !hasUSD }

    mutating func add(_ e: CostEstimate) {
        switch e {
        case .credits(let c): credits += c
        case .usd(let v, _): usd += v; hasUSD = true
        case .unknown: break
        }
    }
}

final class PriceTable: @unchecked Sendable {
    static let shared = PriceTable()
    static let staleAfterDays = 180

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hubbub").appendingPathComponent("prices.json")
    }

    private let lock = NSLock()
    private var _file = PriceFile()
    private var _error: String?
    private var loadedStamp: Date?
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? PriceTable.fileURL
        reload()
    }

    var file: PriceFile { lock.lock(); defer { lock.unlock() }; return _file }
    /// Set when prices.json exists but could not be read; defaults are in effect.
    var loadError: String? { lock.lock(); defer { lock.unlock() }; return _error }

    func reload() {
        var f = PriceFile(), err: String? = nil
        if let d = try? Data(contentsOf: url) {
            do { f = try JSONDecoder().decode(PriceFile.self, from: d) } catch { err = "prices.json ignored: \(Self.describe(error))" }
        }
        lock.lock(); _file = f; _error = err
        loadedStamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.unlock()
    }

    /// Cheap check used before each lookup batch so edits show up without restarting.
    func reloadIfChanged() {
        let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        lock.lock(); let same = m == loadedStamp; lock.unlock()
        if !same { reload() }
    }

    private static func describe(_ e: Error) -> String {
        if case DecodingError.dataCorrupted(let c) = e { return c.debugDescription }
        return "invalid format"
    }

    /// Creates an empty, editable prices.json (never overwrites an existing one).
    @discardableResult
    func ensureFileForEditing() -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(PriceFile()) { try? d.write(to: url, options: .atomic) }
            reload()
        }
        return url
    }

    func reset() { try? FileManager.default.removeItem(at: url); reload() }

    // MARK: lookup

    /// First documented row whose `match` is contained (case-insensitively) in the model name and has both prices.
    func price(forModel model: String) -> ModelPrice? {
        let m = model.lowercased()
        guard !m.isEmpty else { return nil }
        return file.models.first { !$0.match.isEmpty && m.contains($0.match.lowercased()) && $0.documented && $0.inPerM != nil && $0.outPerM != nil }
    }

    func usdPerCredit(provider: String) -> CreditPrice? {
        file.credits.first { $0.provider == provider && $0.documented && ($0.usdPerCredit ?? 0) > 0 }
    }

    func estimate(provider: String, model: String, inTok: Int, outTok: Int, credits: Double) -> CostEstimate {
        if provider == "copilot" { return credits > 0 ? .credits(credits) : .unknown }
        guard inTok + outTok > 0, let p = price(forModel: model), let i = p.inPerM, let o = p.outPerM else { return .unknown }
        return .usd((Double(inTok) * i + Double(outTok) * o) / 1_000_000, estimated: true)
    }

    func isStale(_ asOf: String?, now: Date = Date()) -> Bool {
        guard let d = Self.parseDay(asOf) else { return false }
        return now.timeIntervalSince(d) > Double(Self.staleAfterDays) * 86400
    }

    static func parseDay(_ s: String?) -> Date? {
        guard let s, s.count == 10 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    // MARK: display

    func display(provider: String, model: String, inTok: Int, outTok: Int, credits: Double, now: Date = Date(), locale: Locale = .current) -> CostDisplay {
        switch estimate(provider: provider, model: model, inTok: inTok, outTok: outTok, credits: credits) {
        case .credits(let c):
            var sub: String? = nil, tip: String? = "Copilot premium requests (credits), not dollars."
            if let cp = usdPerCredit(provider: provider), let r = cp.usdPerCredit {
                sub = "≈ " + Fmt.usd(c * r, estimated: false, locale: locale) + " est."
                tip = (tip ?? "") + " Dollar figure = credits × your price from \(cp.asOf ?? "?")."
            }
            return CostDisplay(value: Fmt.credits(c, locale: locale) + " credits", sub: sub, hidden: false, short: Fmt.creditsShort(c, locale: locale), tooltip: tip)
        case .usd(let v, let est):
            let p = price(forModel: model)
            var tip = "est.: tokens × list price; ignores cache and your plan."
            if let a = p?.asOf { tip += " Price from \(a)\(isStale(a, now: now) ? " (older than \(Self.staleAfterDays) days, check it)" : "")." }
            let s = Fmt.usd(v, estimated: est, locale: locale)
            return CostDisplay(value: s, sub: "est. · API rates", hidden: false, short: s, tooltip: tip)
        case .unknown:
            if provider == "copilot" { return CostDisplay(value: Fmt.credits(0, locale: locale) + " credits", sub: nil, hidden: false, short: Fmt.none, tooltip: nil) }
            return CostDisplay(value: Fmt.none, sub: "no price set", hidden: true, short: Fmt.none, tooltip: "No price for this model. Add one in prices.json to see an estimate.")
        }
    }

    /// Totals for many sessions without mixing units.
    func totals(_ items: [(provider: String, model: String, inTok: Int, outTok: Int, credits: Double)]) -> CostTotals {
        var t = CostTotals()
        for i in items { t.add(estimate(provider: i.provider, model: i.model, inTok: i.inTok, outTok: i.outTok, credits: i.credits)) }
        return t
    }
}

extension SessionInfo {
    var costDisplay: CostDisplay {
        PriceTable.shared.display(provider: provider, model: model, inTok: inputTokens, outTok: outputTokens, credits: costCredits)
    }
}

extension SessionRecord {
    var costDisplay: CostDisplay {
        PriceTable.shared.display(provider: provider, model: model, inTok: inputTokens, outTok: outputTokens, credits: credits)
    }
}

/// Settings ▸ Providers: where the editable price table lives.
struct PricesRow: View {
    @State private var rows = PriceTable.shared.file.models.count
    @State private var error = PriceTable.shared.loadError
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Prices").font(HubFont.body)
                Text(rows == 0 ? "none set — no dollar estimates" : "\(rows) model price\(rows == 1 ? "" : "s")")
                    .font(HubFont.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reveal prices.json") {
                    NSWorkspace.shared.activateFileViewerSelecting([PriceTable.shared.ensureFileForEditing()])
                }.controlSize(.small)
                Button("Reset…") { confirmReset = true }.controlSize(.small)
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload prices.json").accessibilityLabel("Reload prices")
            }
            if let error { Text(error).font(HubFont.caption).foregroundStyle(.orange) }
            Text("Estimates are labelled “est.” and need a source URL and date per row. Copilot credits are never converted unless you add a sourced rate.")
                .font(HubFont.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Delete your prices.json?", isPresented: $confirmReset) {
            Button("Reset to defaults", role: .destructive) { PriceTable.shared.reset(); refresh() }
        }
    }

    private func refresh() { PriceTable.shared.reload(); rows = PriceTable.shared.file.models.count; error = PriceTable.shared.loadError }
}

enum FormatSelfTest {
    static func run() -> Bool {
        var fails = 0
        func check(_ name: String, _ got: String, _ want: String) {
            if got != want { fails += 1; print("FAIL \(name): got '\(got)' want '\(want)'") }
        }
        func yes(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL \(name)") } }
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")

        for (n, w) in [(0, "0"), (842, "842"), (999, "999"), (1000, "1k"), (1234, "1.2k"), (9800, "9.8k"), (9960, "10k"), (10_000, "10k"),
                       (123_456, "123k"), (999_499, "999k"), (999_500, "1M"), (1_000_000, "1M"), (1_234_567, "1.2M"),
                       (99_960_000, "100M"), (123_400_000, "123M"), (-5, "0")] { check("tokens \(n)", Fmt.tokens(n, locale: us), w) }
        check("tokens de", Fmt.tokens(1234, locale: de), "1,2k")

        check("pct", Fmt.percent(0.634, locale: us), "63%")
        check("pct cap", Fmt.percent(1.7, locale: us), "100%")
        check("pct nil", Fmt.percent(nil), "—")
        check("pct nan", Fmt.percent(.nan), "—")
        check("pctValue", Fmt.percentValue(35, locale: us), "35%")

        check("cr", Fmt.credits(4.4, locale: us), "4.4")
        check("cr int", Fmt.credits(566, locale: us), "566")
        check("cr round", Fmt.credits(4.04, locale: us), "4")
        check("cr short", Fmt.creditsShort(4.4, locale: us), "4.4 cr")

        check("usd small", Fmt.usd(0.42, estimated: true, locale: us), "~$0.42")
        check("usd tiny", Fmt.usd(0.004, estimated: true, locale: us), "~<$0.01")
        check("usd zero", Fmt.usd(0, estimated: false, locale: us), "$0.00")
        check("usd 10", Fmt.usd(12.34, estimated: false, locale: us), "$12.3")
        check("usd 100", Fmt.usd(1234.6, estimated: true, locale: us), "~$1,235")
        check("usd neg", Fmt.usd(-1, estimated: false, locale: us), "—")

        for (s, w) in [(0.0, "0s"), (45, "45s"), (60, "1m"), (720, "12m"), (7500, "2h 05m"), (3600, "1h 00m"), (3 * 86400 + 4 * 3600 + 200, "3d 4h"), (-3, "0s")] {
            check("dur \(s)", Fmt.duration(s), w)
        }

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_761_825_600) // 2025-10-30 12:00 UTC
        check("rel now", Fmt.relative(now.addingTimeInterval(-20), now: now, calendar: cal, locale: us), "now")
        check("rel m", Fmt.relative(now.addingTimeInterval(-300), now: now, calendar: cal, locale: us), "5m ago")
        check("rel h", Fmt.relative(now.addingTimeInterval(-7200), now: now, calendar: cal, locale: us), "2h ago")
        check("rel y", Fmt.relative(now.addingTimeInterval(-86400), now: now, calendar: cal, locale: us), "Yesterday")
        check("rel date", Fmt.relative(now.addingTimeInterval(-4 * 86400), now: now, calendar: cal, locale: us), "Oct 26")
        check("pair", Fmt.pair(126_000, 200_000, locale: us), "126k / 200k")
        check("spoken", Fmt.spoken(3_200_000), "3.2 million")

        yes("ctx", Semantic.context(0.59) == .ok && Semantic.context(0.6) == .warn && Semantic.context(0.85) == .alert)
        yes("quota", Semantic.quota(0.69) == .ok && Semantic.quota(0.7) == .warn && Semantic.quota(0.9) == .alert)
        yes("budget", Semantic.budget(0.79) == .ok && Semantic.budget(0.8) == .warn && Semantic.budget(1) == .alert)

        // price table: scratch file in the working directory, never the user's
        let dir = FileManager.default.currentDirectoryPath + "/.selftest-prices"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let url = URL(fileURLWithPath: dir + "/prices.json")

        let empty = PriceTable(url: url)
        yes("defaults no models", empty.file.models.isEmpty && empty.loadError == nil)
        let d0 = empty.display(provider: "claude", model: "claude-sonnet-5", inTok: 1_000_000, outTok: 1000, credits: 0, locale: us)
        yes("no price → hidden", d0.hidden && d0.value == "—" && d0.sub == "no price set" && !d0.value.contains("$"))
        let c0 = empty.display(provider: "copilot", model: "x", inTok: 10, outTok: 10, credits: 4.4, locale: us)
        check("copilot credits", c0.value, "4.4 credits")
        yes("copilot no $ by default", c0.sub == nil && !c0.hidden)

        let json = """
        {"version":1,"currency":"USD","models":[
          {"match":"Sonnet","inPerM":2,"outPerM":10,"source":"https://example.invalid/p","asOf":"2020-01-01"},
          {"match":"opus","inPerM":9,"outPerM":9,"source":null,"asOf":null},
          {"match":"half","inPerM":1,"outPerM":null,"source":"https://example.invalid/p","asOf":"2026-01-01"}],
         "credits":[{"provider":"copilot","usdPerCredit":0.5,"source":"https://example.invalid/c","asOf":"2026-01-01"}]}
        """
        try? json.data(using: .utf8)!.write(to: url)
        let t = PriceTable(url: url)
        let d1 = t.display(provider: "claude", model: "Claude-SONNET-5", inTok: 1_000_000, outTok: 100_000, credits: 0, locale: us)
        check("est value", d1.value, "~$3.00")
        yes("est label", d1.sub == "est. · API rates" && !d1.hidden && (d1.tooltip ?? "").contains("older than"))
        yes("undocumented row ignored", t.display(provider: "claude", model: "opus-4", inTok: 5000, outTok: 5000, credits: 0).hidden)
        yes("incomplete row ignored", t.display(provider: "claude", model: "half", inTok: 5000, outTok: 5000, credits: 0).hidden)
        yes("zero tokens unknown", t.estimate(provider: "claude", model: "sonnet", inTok: 0, outTok: 0, credits: 0) == .unknown)
        let c1 = t.display(provider: "copilot", model: "x", inTok: 0, outTok: 0, credits: 4, locale: us)
        yes("credits $ only with sourced rate", c1.value == "4 credits" && c1.sub == "≈ $2.00 est.")

        let tot = t.totals([("copilot", "x", 0, 0, 4.4), ("claude", "sonnet", 1_000_000, 0, 0), ("claude", "sonnet", 1_000_000, 0, 0), ("gemini", "g", 5, 5, 0)])
        yes("units kept apart", tot.credits == 4.4 && tot.usd == 4 && tot.hasUSD)

        try? "{ not json".data(using: .utf8)!.write(to: url)
        let bad = PriceTable(url: url)
        yes("invalid → defaults + message", bad.file.models.isEmpty && (bad.loadError ?? "").hasPrefix("prices.json ignored"))

        // insights aggregation + history day groups
        let nowD = Date()
        let recs = [
            SessionRecord(id: "a", provider: "copilot", name: "A", model: "m", tokens: 1000, credits: 4, lastEvent: nowD),
            SessionRecord(id: "b", provider: "claude", name: "B", model: "m2", tokens: 5000, credits: 0, lastEvent: nowD.addingTimeInterval(-3 * 86400)),
            SessionRecord(id: "r", provider: "claude", name: "R", model: "m2", tokens: 9000, credits: 0, lastEvent: nowD, machine: "other"),
        ]
        let td = InsightsSummary.make(recs, range: .today, now: nowD, prices: empty)
        yes("insights today", td.sessions == 1 && td.tokens == 1000 && td.costs.credits == 4 && !td.costs.hasUSD && td.perDay.count == 7)
        let wk = InsightsSummary.make(recs, range: .week, now: nowD, prices: empty)
        yes("insights week", wk.sessions == 2 && wk.tokens == 6000 && wk.topModel == "m2" && wk.topProvider == "claude" && wk.perDay.count == 7)
        yes("insights bars", InsightsBars.fractions([0, 0, 0]) == [0.07, 0.07, 0.07] && InsightsBars.fractions([0, 50, 100]) == [0.07, 0.5, 1] && InsightsBars.fractions([1, 100]) [0] >= 0.1 && InsightsBars.peakIndex([0, 0]) == nil && InsightsBars.peakIndex([5, 9, 9, 1]) == 2)
        yes("day groups", SessionBrowser.dayGroups(recs.sorted { $0.lastEvent > $1.lastEvent }).count == 2)

        // multi-day session: only the share that falls in the range counts
        var ucal = Calendar(identifier: .gregorian); ucal.timeZone = TimeZone(identifier: "UTC")!
        let day = 86400.0
        func key(_ back: Int) -> String { DayKey.string(now.addingTimeInterval(-Double(back) * day), calendar: ucal) }
        var multi = SessionRecord(id: "m", provider: "copilot", name: "M", model: "m", tokens: 0, credits: 0, lastEvent: now)
        multi.inputTokens = 1700; multi.outputTokens = 300; multi.credits = 11; multi.startedAt = now.addingTimeInterval(-199 * day)
        multi.days = [key(2): DayUsage(input: 1000, output: 100, credits: 6), key(1): DayUsage(input: 500, output: 100, credits: 3),
                      key(0): DayUsage(input: 200, output: 100, credits: 2)]
        let mt = InsightsSummary.make([multi], range: .today, now: now, calendar: ucal, prices: empty)
        yes("multi-day today share", mt.tokens == 300 && mt.costs.credits == 2 && mt.sessions == 1)
        yes("multi-day chart", mt.perDay.map { Int($0.value) }.suffix(3) == [1100, 600, 300])
        let mw = InsightsSummary.make([multi], range: .week, now: now, calendar: ucal, prices: empty)
        yes("multi-day week share", mw.tokens == 2000 && mw.costs.credits == 11)
        yes("comparison share", UsageComparison.byProvider([multi], since: ucal.startOfDay(for: now)).first?.tokens == 300)
        var legacy = multi; legacy.days = nil; legacy.startedAt = now.addingTimeInterval(-3 * day); legacy.inputTokens = 4000; legacy.outputTokens = 0
        let lt = InsightsSummary.make([legacy], range: .today, now: now, calendar: ucal, prices: empty)
        yes("legacy record not inflated", lt.tokens > 0 && lt.tokens <= 1000)
        yes("legacy split keeps total", legacy.usageByDay(calendar: ucal).values.reduce(0) { $0 + $1.tokens } == 4000)

        // sessions without a timeline: growth is attributed to the day it was observed
        var s1 = SessionInfo(id: "p", name: "P", cwd: "/x", model: "m", lastEvent: now.addingTimeInterval(-day), state: .idle, currentTool: nil,
                             subagents: [], inputTokens: 1000, outputTokens: 0, toolCalls: 0)
        s1.startedAt = now.addingTimeInterval(-day - 600)
        let r1 = SessionRecord.merged(prev: nil, with: s1, calendar: ucal)
        var s2 = s1; s2.lastEvent = now; s2.inputTokens = 1500
        let r2 = SessionRecord.merged(prev: r1, with: s2, calendar: ucal)
        let d2 = InsightsSummary.make([r2], range: .today, now: now, calendar: ucal, prices: empty)
        yes("observed delta lands on today", d2.tokens == 500)

        // active time + display
        var clock = ActiveClock()
        for off in [0.0, 60, 120, 18_120, 18_150] as [TimeInterval] { clock.tick(now.addingTimeInterval(off)) }
        yes("active clock caps idle gaps", clock.total == 120 + ActiveClock.idleCap + 30)
        var longRec = multi; longRec.active = 40 * 3600
        yes("duration never above wall span", legacy.activeDuration == SessionRecord.unknownActiveCap && longRec.activeDuration == 40 * 3600)
        longRec.active = 5 * 3600
        check("long-lived session shows active time", Fmt.duration(longRec.activeDuration ?? -1), "5h 00m")
        longRec.active = nil
        check("unknown active time is capped", Fmt.duration(longRec.activeDuration ?? -1), "8h 00m")

        print(fails == 0 ? "format/cost selftest OK" : "format/cost selftest FAILED (\(fails))")
        return fails == 0
    }
}
