import SwiftUI

import Charts

/// Pure aggregation for the Insights page (self-tested).
enum InsightsRange: String, CaseIterable, Identifiable {
    case today, week
    var id: String { rawValue }
    var title: String { self == .today ? "Today" : "Week" }
    var chartDays: Int { 7 }
    func cutoff(now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: self == .today ? 0 : -6, to: calendar.startOfDay(for: now)) ?? now
    }
}

/// Pure bar geometry: every day gets a bar; empty days are a faint stub so the chart is never a void.
enum InsightsBars {
    static let stub = 0.07
    static func fractions(_ values: [Double]) -> [Double] {
        let peak = values.max() ?? 0
        return values.map { peak > 0 && $0 > 0 ? max(stub * 1.5, $0 / peak) : stub }
    }
    static func peakIndex(_ values: [Double]) -> Int? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.lastIndex(of: peak)
    }
}

/// Debug: INSIGHTS_FAKE=none|one|sparse|rich replaces the records so each state can be snapshotted.
enum InsightsFake {
    static func records(now: Date = Date(), calendar: Calendar = .current) -> [SessionRecord]? {
        guard let mode = ProcessInfo.processInfo.environment["INSIGHTS_FAKE"] else { return nil }
        func rec(_ id: String, _ prov: String, _ model: String, _ perDay: [Int: Int]) -> SessionRecord {
            var r = SessionRecord(id: id, provider: prov, name: id, model: model, tokens: 0, credits: 0, lastEvent: now)
            var days: [String: DayUsage] = [:]
            for (back, t) in perDay {
                let d = calendar.date(byAdding: .day, value: -back, to: now) ?? now
                days[DayKey.string(d, calendar: calendar)] = DayUsage(input: t * 3 / 4, output: t / 4, credits: 0)
            }
            r.days = days
            r.inputTokens = days.values.reduce(0) { $0 + $1.input }
            r.outputTokens = days.values.reduce(0) { $0 + $1.output }
            return r
        }
        switch mode {
        case "none": return []
        case "one": return [rec("alpha", "claude", "sonnet", [0: 48_000])]
        case "sparse": return [rec("alpha", "claude", "sonnet", [0: 21_000, 3: 380_000]), rec("beta", "copilot", "gpt", [6: 12_000])]
        default: return [rec("alpha", "claude", "sonnet", [0: 640_000, 1: 910_000, 2: 120_000, 4: 1_400_000, 5: 300_000, 6: 760_000]),
                         rec("beta", "copilot", "gpt", [0: 220_000, 2: 90_000, 3: 510_000, 6: 40_000])]
        }
    }
}

struct InsightsSummary {
    var tokens = 0
    var sessions = 0
    var costs = CostTotals()
    var topModel: String?
    var topProvider: String?
    var perDay: [DayValue] = []

    static func make(_ records: [SessionRecord], range: InsightsRange, now: Date = Date(), calendar: Calendar = .current,
                     prices: PriceTable = .shared) -> InsightsSummary {
        var s = InsightsSummary()
        let local = records.filter { $0.machine == nil }
        let cut = range.cutoff(now: now, calendar: calendar)
        let inRange = local.filter { $0.lastEvent >= cut }
        s.sessions = inRange.count
        // Only each session's share that falls inside the range counts, not its lifetime total.
        let shares = local.map { ($0, $0.usage(since: cut, calendar: calendar)) }.filter { $0.1.tokens > 0 || $0.1.credits > 0 }
        s.tokens = shares.reduce(0) { $0 + $1.1.tokens }
        s.costs = prices.totals(shares.map { ($0.provider, $0.model, $1.input, $1.output, $1.credits) })
        func top(_ key: (SessionRecord) -> String) -> String? {
            var t: [String: Int] = [:]
            for (r, u) in shares where !key(r).isEmpty { t[key(r), default: 0] += u.tokens }
            return t.filter { $0.value > 0 }.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        }
        s.topModel = top { $0.model }
        s.topProvider = top { $0.provider }
        let today = calendar.startOfDay(for: now)
        var byDay: [String: Double] = [:]
        for r in local { for (k, u) in r.usageByDay(calendar: calendar) { byDay[k, default: 0] += Double(u.tokens) } }
        s.perDay = (0..<range.chartDays).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { DayValue(day: $0, value: byDay[DayKey.string($0, calendar: calendar)] ?? 0) }
        }
        return s
    }
}

struct InsightsView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject private var library = SessionLibrary.shared
    @State private var range: InsightsRange = .today
    @State private var report = DayReport()
    @State private var toast: String?
    @State private var visible = false
    @State private var lastSignature: [String]?
    @State private var moreOpen = false
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let records = InsightsFake.records() ?? library.records
        let sum = InsightsSummary.make(records, range: range)
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                if let toast {
                    Text(toast).font(HubFont.caption).padding(.horizontal, Space.sm).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                        .transition(.opacity)
                }
                Spacer()
                Picker("Range", selection: $range) { ForEach(InsightsRange.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            if records.isEmpty {
                VStack(spacing: Space.sm) {
                    Text("🐣").font(.system(size: 34)).accessibilityHidden(true)
                    chartBars(sum, placeholder: true)
                    Text("Quiet so far — start an agent and it shows up here.").font(HubFont.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                .accessibilityElement(children: .combine)
            } else {
                numbers(sum)
                chart(sum)
                top(sum)
            }
            ProjectionLine()
            DisclosureGroup(isExpanded: $moreOpen) {
                if moreOpen { more }
            } label: { Text("More").font(HubFont.body) }
        }
        .padding(Space.sm)
        .onAppear { visible = true; reload() }
        .onDisappear { visible = false }
        .onReceive(tick) { _ in if visible { reload() } }
    }

    private func numbers(_ s: InsightsSummary) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            big(s.tokens > 0 ? Fmt.tokens(s.tokens) : Fmt.none, "tokens", "Tokens \(Fmt.spoken(s.tokens))", muted: s.tokens == 0)
            costBig(s.costs)
            big(s.sessions > 0 ? "\(s.sessions)" : Fmt.none, s.sessions == 1 ? "session" : "sessions", "\(s.sessions) sessions", muted: s.sessions == 0)
        }
    }

    @ViewBuilder private func costBig(_ c: CostTotals) -> some View {
        if c.hasCredits && c.hasUSD {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.credits(c.credits)).font(HubFont.metric)
                Text("credits · \(Fmt.usd(c.usd, estimated: true)) est.").font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .help("Credits and dollar estimates are different units and are never added together.")
        } else if c.hasUSD {
            big(Fmt.usd(c.usd, estimated: true), "est. cost", "Estimated cost \(Fmt.usd(c.usd, estimated: true))", help: "Tokens × list price from prices.json; ignores cache and your plan.")
        } else if c.hasCredits {
            big(Fmt.credits(c.credits), "credits", "\(Fmt.credits(c.credits)) credits", help: "Copilot premium requests, not dollars.")
        } else {
            big(Fmt.none, "no cost data", "No cost data", help: "Add a price in prices.json to see estimates for token-based providers.", muted: true)
        }
    }

    private func big(_ value: String, _ label: String, _ a11y: String, help: String? = nil, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(HubFont.metric).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(muted ? Color.secondary.opacity(0.6) : Color.primary)
            Text(label).font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
        .help(help ?? a11y)
    }

    private func chart(_ s: InsightsSummary) -> some View { chartBars(s, placeholder: false) }

    private func chartBars(_ s: InsightsSummary, placeholder: Bool) -> some View {
        let values = s.perDay.map(\.value)
        let fr = InsightsBars.fractions(values)
        let peak = InsightsBars.peakIndex(values)
        let cal = Calendar.current
        let h: CGFloat = placeholder ? 36 : 72
        return HStack(alignment: .bottom, spacing: Space.sm) {
            ForEach(Array(s.perDay.enumerated()), id: \.offset) { i, d in
                let today = cal.isDateInToday(d.day)
                let empty = d.value <= 0
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: h)
                        RoundedRectangle(cornerRadius: 3)
                        .fill(empty ? Color.primary.opacity(0.10)
                              : today ? Color.accentColor
                              : Color.accentColor.opacity(i == peak ? 0.9 : 0.4))
                        .frame(maxWidth: 34).frame(height: max(3, h * fr[i]))
                    }
                    Text(d.day.formatted(.dateTime.weekday(.narrow))).font(HubFont.caption)
                        .fontWeight(today ? .bold : .regular).foregroundStyle(today ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.bottom, 17) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tokens per day, last \(s.perDay.count) days")
        .accessibilityValue(placeholder ? "No data" : chartSummary(s.perDay))
    }

    private func chartSummary(_ series: [DayValue]) -> String {
        guard let peak = series.max(by: { $0.value < $1.value }), peak.value > 0 else { return "No data" }
        return "Peak \(peak.day.formatted(.dateTime.weekday(.abbreviated))) \(Fmt.tokens(Int(peak.value))), total \(Fmt.tokens(Int(series.reduce(0) { $0 + $1.value }))) tokens"
    }

    @ViewBuilder private func top(_ s: InsightsSummary) -> some View {
        let parts = [s.topModel, s.topProvider.map { ProviderRegistry.shared.name(for: $0) }].compactMap { $0 }
        if !parts.isEmpty {
            Text("Top · " + parts.joined(separator: " · ")).font(HubFont.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .help("Most-used model and provider by tokens")
        }
    }

    @ViewBuilder private var more: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            leaderboard.frame(maxWidth: .infinity, alignment: .leading)
            timeline.frame(maxWidth: .infinity, alignment: .leading)
            ScoreboardCard()
            CostProjectionCard()
        }
        .padding(.top, Space.sm)
    }

    // Only rescan when the monitor snapshot actually changed.
    private func reload() {
        let sessions = monitor.sessions
        let sig = sessions.map { "\($0.id)|\($0.lastEvent.timeIntervalSince1970)|\($0.toolCalls)|\($0.failures)" }
        if lastSignature != nil, sig == lastSignature { return }
        lastSignature = sig
        Task.detached(priority: .utility) {
            let r = MetricsScanner.shared.todayReport()
            let fresh = await MainActor.run { Achievements.evaluate(report: r, sessions: sessions) }
            await MainActor.run {
                report = r
                if let a = fresh.first {
                    withAnimation { toast = "Unlocked: \(a.title)" }
                    Task { try? await Task.sleep(nanoseconds: 4_000_000_000); withAnimation { toast = nil } }
                }
            }
        }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Leaderboard today").font(HubFont.caption.bold()).foregroundStyle(.secondary)
            if report.leaderboard.isEmpty { Text("No activity today").font(HubFont.caption).foregroundStyle(.secondary) }
            ForEach(Array(report.leaderboard.prefix(5).enumerated()), id: \.element.id) { i, r in
                HStack(spacing: 4) {
                    Group {
                        if i == 0 { Image(systemName: "trophy.fill").foregroundStyle(.orange) } else { Text("\(i + 1).") }
                    }.font(HubFont.caption).frame(width: 18, alignment: .leading)
                    Text("\(r.agent) · \(r.session)").font(HubFont.caption).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Text("\(r.ok) ok · \(Fmt.percent(r.successRate)) · \(Fmt.creditsShort(r.cost))").font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                .help("\(r.agent) · \(r.session)")
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var timeline: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let span = max(1, Date().timeIntervalSince(start))
        return VStack(alignment: .leading, spacing: 2) {
            Text("Timeline · 00:00 → now").font(HubFont.caption.bold()).foregroundStyle(.secondary)
            if report.timeline.isEmpty { Text("No sessions today").font(HubFont.caption).foregroundStyle(.secondary) }
            ForEach(report.timeline.prefix(6)) { row in
                HStack(spacing: 4) {
                    Text(row.name).font(HubFont.caption).lineLimit(1).frame(width: 70, alignment: .leading).help(row.name)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                            ForEach(Array(row.intervals.enumerated()), id: \.offset) { _, iv in
                                let x = iv.0.timeIntervalSince(start) / span * g.size.width
                                let w = max(2, iv.1.timeIntervalSince(iv.0) / span * g.size.width)
                                RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: w).offset(x: x)
                            }
                        }
                    }.frame(height: 8)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.name), \(row.intervals.count) active periods today")
            }
        }
    }
}
