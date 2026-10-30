import SwiftUI
import AppKit

/// One-line empty state below the stage when no agent session has been detected.
struct NoSessionsCard: View {
    let onCheckAgain: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "terminal").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("No agents running — start one and it appears here.").font(HubFont.body).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: Space.xs)
            Button("Check again", action: onCheckAgain).buttonStyle(.borderless).font(HubFont.body)
                .help("Rescan for sessions now")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, Space.sm)
        .cardSurface(radius: Space.radius)
    }
}

/// One-line pill shown instead of the quota bar when the Copilot token is missing.
struct ConnectQuotaPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Connect Copilot quota", systemImage: "key").font(HubFont.caption).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Open Settings → Providers to show your Copilot quota (needs `gh auth login`)")
        .accessibilityHint("Opens Providers settings")
    }
}

/// Dismissible message row (e.g. hotkey registration failure).
struct ToastRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard").foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(HubFont.caption).lineLimit(2)
            Spacer(minLength: 4)
            Button { onDismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss").help("Dismiss")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15)))
        .accessibilityElement(children: .combine)
    }
}

/// Card background that stays visible in light mode (white card + hairline) and subtle in dark mode.
struct CardSurface: ViewModifier {
    var radius: CGFloat = 10
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius)
                .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.13), lineWidth: 0.5))
    }
}

extension View {
    func cardSurface(radius: CGFloat = 10) -> some View { modifier(CardSurface(radius: radius)) }
}

/// First-use hints. Each is shown once, at most one per launch, and never before onboarding is done.
enum Tip: String, CaseIterable {
    case stage, camera, zoom, achievements, expand

    var icon: String {
        switch self {
        case .stage: "hand.tap"
        case .camera: "video"
        case .zoom: "plus.magnifyingglass"
        case .achievements: "trophy"
        case .expand: "arrow.up.left.and.arrow.down.right"
        }
    }
    var text: String {
        switch self {
        case .stage: "Click a character or prop · drag to move"
        case .camera: "Press C to switch camera: Free, Follow, Cinematic"
        case .zoom: "Scroll or pinch to zoom the stage"
        case .achievements: "Open the Awards tab (⌘4) to see your level and achievements"
        case .expand: "Need more room? Expand opens a resizable window"
        }
    }

    private var key: String { "tip.\(rawValue).seen" }
    /// Picked once per launch so the same hint stays up until dismissed.
    static let launchTip: Tip? = remaining.first

    var seen: Bool { UserDefaults.standard.bool(forKey: key) }
    func markSeen() { UserDefaults.standard.set(true, forKey: key) }
    static var remaining: [Tip] { allCases.filter { !$0.seen } }
}

/// Short, dismissible stage hint. Walks through `Tip`s across launches; reports done to the host once all were seen.
struct CoachMark: View {
    let onDismiss: () -> Void
    @State private var hidden = false

    var body: some View {
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if !hidden, let tip = Tip.launchTip, !tip.seen {
                HStack(spacing: 6) {
                    Image(systemName: tip.icon).accessibilityHidden(true)
                    Text(tip.text).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    Button { dismiss(tip) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss hint").help("Dismiss hint")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .padding(.bottom, 8)
            }
        }
        .onAppear { if Tip.remaining.isEmpty { onDismiss() } }
    }

    private func dismiss(_ t: Tip) {
        t.markSeen()
        hidden = true
        if Tip.remaining.isEmpty { onDismiss() }
    }
}

/// Changes new-user defaults without touching what existing users already see.
enum DefaultsMigration {
    /// Surprise guests used to default to on. People who finished onboarding under that default keep it.
    static let run: Void = {
        let d = UserDefaults.standard
        guard d.object(forKey: "defaultsV2") == nil else { return }
        d.set(true, forKey: "defaultsV2")
        if d.bool(forKey: "hasOnboarded"), d.object(forKey: GuestLayer.enabledKey) == nil {
            d.set(true, forKey: GuestLayer.enabledKey)
        }
    }()
}
