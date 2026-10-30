import SwiftUI

/// First-launch card (2 steps), meant to be overlaid at the bottom of / below the stage so the scene stays visible.
/// Re-openable from Settings via `showWelcome`. Skip and Done both dismiss it permanently; only Done applies step 2's choices.
struct OnboardingCard: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("showWelcome") private var showWelcome = false
    @AppStorage("theme") private var themeRaw = Theme.defaultTheme.rawValue
    @AppStorage("notifications") private var notifications = true
    @ObservedObject var registry = ProviderRegistry.shared
    @StateObject private var login = LaunchAtLogin()
    @State private var step = 0
    @State private var showAll = false

    /// True while the card is visible; the update pill stays hidden meanwhile.
    static var isShowing: Bool {
        let d = UserDefaults.standard
        return !d.bool(forKey: "hasOnboarded") || d.bool(forKey: "showWelcome")
    }

    private static let hints: [String: String] = [
        "crew": "Append one JSON line per event to ~/.hubbub/events/<name>.jsonl (see docs/PROVIDERS.md).",
        "grok": "No local logs: emit events to ~/.hubbub/events/grok-*.jsonl (Crew Events format).",
    ]

    private func hint(_ p: AgentProvider) -> String {
        Self.hints[p.id] ?? "Looked in \(p.dataHint). Use the agent once and it appears automatically."
    }

    private var foundCount: Int { registry.all.filter(\.isAvailable).count }

    var body: some View {
        if !hasOnboarded || showWelcome {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(step == 0 ? "Hubbub watches your agent sessions — \(foundCount) found" : "Make it yours")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(step + 1) of 2").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Skip") { finish(apply: false) }
                        .buttonStyle(.borderless).font(.system(size: 11))
                        .accessibilityLabel("Skip welcome")
                        .accessibilityHint("Dismisses this card permanently without changing settings")
                }
                if step == 0 { providers } else { setup }
                HStack {
                    if step > 0 { Button("Back") { step -= 1 } }
                    Spacer()
                    if step == 0 { Button("Next") { step = 1 }.keyboardShortcut(.defaultAction) }
                    else { Button("Done") { finish(apply: true) }.keyboardShortcut(.defaultAction) }
                }
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: 636)
            .background(RoundedRectangle(cornerRadius: 10).fill(A11y.panelFill()))
            .cardSurface(radius: 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Welcome to Hubbub, step \(step + 1) of 2")
        }
    }

    private func finish(apply: Bool) {
        if apply, notifications { Notifier.shared.requestAuthorization() }
        hasOnboarded = true
        showWelcome = false
        step = 0
        showAll = false
    }

    private var providers: some View {
        let found = registry.all.filter(\.isAvailable)
        let missing = registry.all.filter { !$0.isAvailable }
        return VStack(alignment: .leading, spacing: 4) {
            if found.isEmpty {
                Text("No agents found yet. Use one and it appears automatically.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(found, id: \.id) { p in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 14)
                    Text(p.displayName).font(.system(size: 11, weight: .semibold))
                    Text(p.dataHint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(p.displayName), found")
            }
            if showAll {
                ForEach(missing, id: \.id) { p in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.dashed").foregroundStyle(.secondary).frame(width: 14)
                        Text(p.displayName).font(.system(size: 11, weight: .semibold))
                        Text(hint(p)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(p.displayName), not found")
                }
            }
            if !missing.isEmpty {
                Button(showAll ? "Hide others" : "Show all (\(registry.all.count))") { showAll.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityLabel(showAll ? "Hide providers that were not found" : "Show all providers")
            }
            Text("Found providers are on automatically. Change them in Settings › Providers.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Theme.allCases) { th in
                        Button { themeRaw = th.rawValue } label: {
                            HStack(spacing: 4) { ThemeIcon(theme: th, size: 14); Text(th.title).font(.system(size: 11)) }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                                .overlay(Capsule().stroke(th.rawValue == themeRaw ? Color.accentColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Theme \(th.title)")
                        .accessibilityAddTraits(th.rawValue == themeRaw ? .isSelected : [])
                    }
                }
            }
            Toggle("Notify me about approvals, stuck and finished sessions", isOn: $notifications)
            Toggle("Launch at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                .disabled(!LaunchAtLogin.isBundled)
            if notifications {
                Text("macOS will ask for permission when you press Done.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .onAppear { login.refresh() }
    }
}

struct WelcomeSettingsButton: View {
    @AppStorage("showWelcome") private var showWelcome = false
    var body: some View {
        Button("Show welcome again") {
            showWelcome = true
            AppRouter.shared.pendingScreen = "live"   // the card lives on the Live page
        }.controlSize(.small)
    }
}
