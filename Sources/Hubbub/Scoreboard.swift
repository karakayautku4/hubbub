import SwiftUI

struct Board: Equatable {
    var tasks = 0, calls = 0, failures = 0
    var fastest: ProgressRow?
    var mostTasks: ProgressRow?
    var cleanest: ProgressRow?
    var topProvider: (name: String, calls: Int)?
    var topModel: (name: String, calls: Int)?

    static func == (a: Board, b: Board) -> Bool {
        a.tasks == b.tasks && a.calls == b.calls && a.failures == b.failures && a.fastest == b.fastest
            && a.mostTasks == b.mostTasks && a.cleanest == b.cleanest
            && a.topProvider?.name == b.topProvider?.name && a.topModel?.name == b.topModel?.name
    }
    var isEmpty: Bool { calls == 0 && tasks == 0 }
}

enum Scoreboard {
    /// Aggregates the stored per-day rows for the last `days` days (1 = today).
    static func board(_ data: ProgressData, days: Int, now: Date = Date(), cal: Calendar = .current) -> Board {
        var b = Board()
        var rows: [ProgressRow] = []
        var prov: [String: Int] = [:], models: [String: Int] = [:]
        for back in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -back, to: now), let day = data.days[ProgressData.dayKey(d, cal)] else { continue }
            b.tasks += day.tasks; b.calls += day.calls; b.failures += day.failures
            rows += day.rows.values
            for (k, v) in day.providers { prov[k, default: 0] += v }
            for (k, v) in day.models { models[k, default: 0] += v }
        }
        b.fastest = rows.filter { $0.secondsPerCall != nil }.min { $0.secondsPerCall! < $1.secondsPerCall! }
        b.mostTasks = rows.filter { $0.tasks > 0 }.max { ($0.tasks, $0.calls) < ($1.tasks, $1.calls) }
        b.cleanest = rows.filter { $0.calls >= 5 }.min {
            (Double($0.failures) / Double($0.calls), -$0.calls) < (Double($1.failures) / Double($1.calls), -$1.calls)
        }
        b.topProvider = prov.filter { $0.value > 0 }.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
        b.topModel = models.filter { $0.value > 0 }.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
        return b
    }
}

/// Compact "Today's Scoreboard" card for Insights.
struct ScoreboardCard: View {
    @ObservedObject private var center = ProgressionCenter.shared
    @State private var week = false

    var body: some View {
        if center.enabled {
            let b = Scoreboard.board(center.data, days: week ? 7 : 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(week ? "Scoreboard · this week" : "Today's Scoreboard").font(HubFont.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $week) {
                        Text("Today").tag(false); Text("Week").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 120).controlSize(.small)
                }
                if b.isEmpty {
                    Text("Finish a task and the scoreboard fills up.").font(HubFont.caption).foregroundStyle(.secondary)
                } else {
                    let cols = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 3) {
                        entry("bolt.fill", .yellow, "Fastest", b.fastest.map { "\(label($0)) · \(Fmt.duration($0.secondsPerCall!))/call" })
                        entry("checkmark.circle.fill", .green, "Most tasks", b.mostTasks.map { "\(label($0)) · \($0.tasks)" })
                        entry("shield.fill", .blue, "Fewest failures", b.cleanest.map { "\(label($0)) · \($0.failures) of \($0.calls)" })
                        entry("cpu", .purple, "Top provider", b.topProvider.map { "\(ProviderRegistry.shared.name(for: $0.name)) · \($0.calls) calls" })
                        entry("sparkles", .orange, "Top model", b.topModel.map { "\($0.name) · \($0.calls) calls" })
                        entry("flag.checkered", .secondary, "Total", "\(b.tasks) tasks · \(b.failures) failures")
                    }
                }
            }
                    }
    }

    private func label(_ r: ProgressRow) -> String { r.name }

    private func entry(_ icon: String, _ tint: Color, _ title: String, _ value: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint).font(HubFont.caption).frame(width: 14).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(HubFont.caption).foregroundStyle(.secondary)
                Text(value ?? "–").font(HubFont.caption).lineLimit(1).truncationMode(.tail).help(value ?? "")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
