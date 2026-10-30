import SwiftUI

extension Theme {
    /// Accent used by the info panel; derived from the theme's preview palette.
    var accent: Color {
        if let c = ov, let h = c.color(c.palette?.accent) { return Color(red: Double(h >> 16 & 255) / 255, green: Double(h >> 8 & 255) / 255, blue: Double(h & 255) / 255) }
        return previewColors.last ?? .accentColor
    }
}

struct MiniBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(max(0, min(1, fraction)) * 100)) percent")
    }
}

struct Chip: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(.primary)
            .help(text)
    }
}

// MARK: - Live strip

/// One metric: label, big value, optional bar and sub-line. Reads as a single VoiceOver element.
struct LiveTile: View {
    let title: String
    let value: String
    var sub: String? = nil
    var fraction: Double? = nil
    var level: Level = .ok
    var spoken: String
    var tooltip: String? = nil
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                HStack(spacing: Space.sm) {
                    Text(title).font(HubFont.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Text(value).font(HubFont.title.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                    if let fraction { MiniBar(fraction: fraction, color: Semantic.color(level), height: Space.bar).frame(maxWidth: 80) }
                    Spacer(minLength: 0)
                    if let sub { Text(sub).font(HubFont.captionDigits).foregroundStyle(.secondary).lineLimit(1) }
                }
                .padding(.horizontal, Space.sm)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(value).font(HubFont.metric).lineLimit(1).minimumScaleFactor(0.7)
                    if let fraction { MiniBar(fraction: fraction, color: Semantic.color(level), height: Space.bar + 2) }
                    if let sub { Text(sub).font(HubFont.captionDigits).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .cardSurface(radius: Space.radius)
        .help(tooltip ?? "\(title) \(value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }
}

/// Tokens · Context · Cost of the selected session (cost tile is hidden when it cannot be known).
struct LiveMetricsStrip: View {
    let session: SessionInfo
    var stacked = false

    var body: some View {
        let s = session
        let total = s.inputTokens + s.outputTokens
        let ctxLevel = Semantic.context(s.contextFraction)
        let cost = s.costDisplay
        let hasContext = s.contextLimit > 0
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.xs)) : AnyLayout(HStackLayout(alignment: .top, spacing: Space.sm))
        layout {
            LiveTile(title: "Tokens", value: Fmt.tokens(total),
                     sub: total > 0 ? "↓\(Fmt.tokens(s.inputTokens)) ↑\(Fmt.tokens(s.outputTokens))" : nil,
                     spoken: "\(Fmt.spoken(total)) total, \(Fmt.spoken(s.inputTokens)) in, \(Fmt.spoken(s.outputTokens)) out",
                     tooltip: "Tokens · \(total) total, \(s.inputTokens) in, \(s.outputTokens) out", stacked: stacked)
            LiveTile(title: "Context", value: hasContext ? Fmt.percent(s.contextFraction) : Fmt.none,
                     sub: hasContext && ctxLevel == .alert ? "⚠︎ compacts soon" : nil,
                     fraction: hasContext ? s.contextFraction : nil, level: ctxLevel,
                     spoken: hasContext ? "\(Int(s.contextFraction * 100)) percent\(Semantic.spoken(ctxLevel).isEmpty ? "" : ", " + Semantic.spoken(ctxLevel))" : "unknown",
                     tooltip: hasContext ? "Context window · \(Fmt.pair(s.contextTokens, s.contextLimit))" : "Context window size unknown",
                     stacked: stacked)
            if !cost.hidden {
                LiveTile(title: "Cost", value: cost.value, sub: cost.sub, spoken: [cost.value, cost.sub].compactMap { $0 }.joined(separator: ", "),
                         tooltip: cost.tooltip ?? "Cost · \(cost.value)", stacked: stacked)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The one status line under the switcher. Replaced by the reply banner when the agent actually asks.
struct LiveStatusRow: View {
    let session: SessionInfo
    let attention: AttentionLevel
    var showStatus = true
    let onDetails: () -> Void

    private var status: (text: String, symbol: String, color: Color) {
        if attention == .stuck { return ("Stuck · see Details", "xmark.octagon.fill", .red) }
        if attention == .failed { return ("Failed · see Details", "xmark.octagon.fill", .red) }
        switch session.state {
        case .working: return ("Working · \(Fmt.duration(session.age))", "play.fill", .green)
        case .idle: return ("Idle · \(Fmt.duration(session.age))", "moon.fill", .secondary)
        case .offline: return ("Offline", "poweroff", .secondary)
        }
    }

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            if showStatus {
                let st = status
                Image(systemName: st.symbol).font(HubFont.caption).foregroundStyle(st.color).accessibilityHidden(true)
                Text(st.text).font(HubFont.body).foregroundStyle(st.color == .red ? Color.red : Color.primary).lineLimit(1)
                    .accessibilityLabel("Status: \(st.text)")
            }
            Spacer(minLength: Space.xs)
            Button("Details", action: onDetails)
                .buttonStyle(.borderless).font(HubFont.body)
                .help("Open session details")
        }
        .frame(minHeight: 20)
    }
}

/// Everything under the stage for the selected session.
struct LiveSessionPanel: View {
    let session: SessionInfo
    let attention: AttentionLevel
    let theme: Theme
    var stacked = false
    var onConnectQuota: () -> Void = {}
    let onDetails: () -> Void
    @ObservedObject var quotaService: QuotaService
    @ObservedObject private var center = ReplyCenter.shared

    private var pending: Bool {
        center.question(for: session) != nil || center.status[session.id] != nil || session.waitingApproval
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if pending { ReplySection(session: session) }
            LiveStatusRow(session: session, attention: attention, showStatus: !pending, onDetails: onDetails)
            LiveMetricsStrip(session: session, stacked: stacked)
            QuotaBar(provider: session.provider, theme: theme, quotaService: quotaService, onConnect: onConnectQuota)
        }
    }
}

// MARK: - Quota bar

/// One slim bar that follows the selected session's provider. Providers without a real quota source get none.
struct QuotaBar: View {
    let provider: String
    let theme: Theme
    @ObservedObject var quotaService: QuotaService
    var onConnect: () -> Void = {}
    @ObservedObject private var other = ProviderQuotaService.shared
    @ObservedObject private var budget = BudgetCenter.shared

    private struct Model {
        var label: String
        var fraction: Double?
        var level: Level
        var tooltip: String
        var refresh: (() -> Void)?
    }

    private static func resetText(_ iso: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso.isEmpty ? nil : iso }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    private func budgetModel() -> Model? {
        guard budget.dailyLimit > 0, budget.dailySpent >= budget.dailyLimit else { return nil }
        let f = budget.dailySpent / budget.dailyLimit
        return Model(label: "Daily budget \(Int((f * 100).rounded()))%", fraction: min(1, f), level: .alert,
                     tooltip: "Daily budget \(budget.fmt(budget.dailySpent)) / \(budget.fmt(budget.dailyLimit))", refresh: nil)
    }

    private func copilotModel() -> Model? {
        guard ProviderRegistry.shared.isEnabled("copilot") else { return nil }
        let refresh = { quotaService.refresh() }
        guard let q = quotaService.quota else {
            if quotaService.noToken { return nil }
            return Model(label: quotaService.error == nil ? "Quota…" : "Quota —", fraction: nil, level: .ok,
                         tooltip: quotaService.error ?? "Loading Copilot quota", refresh: quotaService.error == nil ? nil : refresh)
        }
        let tip = "\(theme.quotaLabel) · Copilot premium requests (credits) · \(Fmt.credits(q.used)) of \(Fmt.credits(q.entitlement))"
            + (quotaService.error.map { "\n\($0)" } ?? "")
        if q.unlimited { return Model(label: "Copilot · unlimited", fraction: nil, level: .ok, tooltip: tip, refresh: nil) }
        let used = min(max((100 - q.percentRemaining) / 100, 0), 1)
        var label = "Copilot · \(Fmt.percent(used)) used"
        if let r = Self.resetText(q.resetDate) { label += " · resets \(r)" }
        return Model(label: label, fraction: used, level: Semantic.quota(used), tooltip: tip, refresh: quotaService.error == nil ? nil : refresh)
    }

    private func otherModel() -> Model? {
        guard ProviderQuotaService.optedIn(provider), QuotaEndpoints.hasAPI(provider) else { return nil }
        let name = ProviderRegistry.shared.name(for: provider)
        let st = other.states[provider]
        let refresh = { other.refresh(provider, force: true) }
        guard let w = st?.quota?.windows.first(where: { $0.percentUsed != nil }), let p = w.percentUsed else {
            if st?.notAvailable == true { return nil }
            return Model(label: st?.error == nil ? "\(name) · Quota…" : "\(name) · Quota —", fraction: nil, level: .ok,
                         tooltip: st?.error ?? "Loading usage limits", refresh: st?.error == nil ? nil : refresh)
        }
        let f = min(1, max(0, p / 100))
        return Model(label: "\(name) · \(w.label) \(Fmt.percent(f)) used", fraction: f, level: Semantic.quota(f),
                     tooltip: (st?.quota?.windows ?? []).map { "\($0.label) \(Fmt.percentValue($0.percentUsed))" }.joined(separator: " · "), refresh: nil)
    }

    var body: some View {
        let isCopilot = provider == "copilot"
        if isCopilot, quotaService.noToken, quotaService.quota == nil, ProviderRegistry.shared.isEnabled("copilot") {
            ConnectQuotaPill(action: onConnect)
        } else if let m = budgetModel() ?? (isCopilot ? copilotModel() : otherModel()) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.xs) {
                    Text(m.label).font(HubFont.captionDigits).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let r = m.refresh {
                        Button(action: r) { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).font(HubFont.caption)
                            .help("Retry").accessibilityLabel("Retry quota")
                    }
                }
                MiniBar(fraction: m.fraction ?? 0, color: m.fraction == nil ? .secondary : Semantic.color(m.level), height: Space.bar)
                    .opacity(m.fraction == nil ? 0.4 : 1)
            }
            .help(m.tooltip)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(m.label)
            .onAppear { if !isCopilot { other.refreshAll() } }
        }
    }
}

