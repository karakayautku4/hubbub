import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, providers, alerts, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .providers: "Providers"
        case .alerts: "Notifications"
        case .advanced: "Advanced"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .providers: "square.stack.3d.up"
        case .alerts: "bell"
        case .advanced: "slider.horizontal.3"
        }
    }
    /// Maps tab names stored by earlier versions (sound, sync, about) to the Advanced tab.
    static func migrated(_ raw: String) -> SettingsTab {
        switch raw {
        case "sound", "sync", "about": return .advanced
        default: return SettingsTab(rawValue: raw) ?? .general
        }
    }
}

/// Titled card used by every settings tab.
struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .cardSurface(radius: 10)
            if let footer {
                Text(footer).font(.caption2).foregroundStyle(.secondary).padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Settings screen: fixed tab bar plus a scrollable page per tab.
struct SettingsView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var stage: Stage
    @ObservedObject private var library = CustomThemes.shared
    @AppStorage("settingsTab") private var tabRaw = SettingsTab.general.rawValue
    @AppStorage("theme") private var themeRaw = Theme.defaultTheme.rawValue
    @AppStorage("team") private var teamRaw = Team.fallback.rawValue
    @AppStorage("sounds") private var sounds = true
    @AppStorage("showMascot") private var showMascot = true
    @AppStorage(PopoverSize.key) private var popoverSize = PopoverSize.compact.rawValue
    @AppStorage("ambienceLevel") private var ambienceLevel = AmbienceLevel.subtle.rawValue
    @AppStorage("ambienceTime") private var ambienceTime = AmbienceTime.auto.rawValue
    @AppStorage("notifications") private var notifications = true

    private var tab: SettingsTab { SettingsTab.migrated(tabRaw) }
    private var theme: Theme { library.resolve(themeRaw).0 }
    private var custom: CustomTheme? { library.resolve(themeRaw).1 }

    var body: some View {
        VStack(spacing: 10) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .general: general
                    case .appearance: appearance
                    case .providers: providers
                    case .alerts: alerts
                    case .advanced: advanced
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { library.reload() }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { t in
                Button { tabRaw = t.rawValue } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol).font(.system(size: 13)).frame(height: 16)
                        Text(t.title).font(.system(size: 10.5, weight: t == tab ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(t == tab ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(t == tab ? Color.accentColor.opacity(0.16) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(t == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .cardSurface(radius: 9)
    }

    // MARK: Tabs

    private var general: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Startup & shortcuts") { StartupSettingsView() }
            SettingsCard(title: "Menu bar") { MenuBarDisplaySetting() }
            SettingsCard(title: "Progression") { ProgressionSettingsView() }
            SettingsCard(title: "About") {
                UpdateSettingsView()
                Divider()
                HStack(spacing: 8) {
                    if let url = URL(string: "https://github.com/\(UpdateChecker.repo)") {
                        Link(destination: url) { Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right") }
                        Link(destination: url.appendingPathComponent("graphs/contributors")) { Label("Credits", systemImage: "heart") }
                    }
                    Spacer()
                    WelcomeSettingsButton()
                }
                .controlSize(.small)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Theme", footer: custom?.blurb ?? theme.blurb) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Theme.allCases) { th in
                        card(selected: th == theme && custom == nil,
                             fill: LinearGradient(colors: th.previewColors.map { $0.opacity(0.45) }, startPoint: .top, endPoint: .bottom)) {
                            themeRaw = th.rawValue
                        } label: {
                            VStack(spacing: 4) { ThemeIcon(theme: th, size: 26); Text(th.title).font(.caption2).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85) }
                        }
                    }
                }
            }
            SettingsCard(title: "Scene") {
                Toggle("Show mascot", isOn: $showMascot).toggleStyle(.switch).controlSize(.small)
                HalloweenSettingsRow()
                row("Popover size", "Compact is quick to glance at; Comfortable is larger.") {
                    Picker("Popover size", selection: $popoverSize) {
                        ForEach(PopoverSize.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
            }
            if theme == .football && custom == nil { teamPicker }
            CameraModePicker()
            AccessibilitySettingsCard()
            SettingsCard(title: "Ambience", footer: "Light follows your clock; weather changes daily.") {
                Picker("Ambience", selection: $ambienceLevel) {
                    ForEach(AmbienceLevel.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Picker("Time of day", selection: $ambienceTime) {
                    ForEach(AmbienceTime.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(ambienceLevel == AmbienceLevel.off.rawValue)
            }
            SettingsCard(title: "Community themes",
                         footer: library.themes.isEmpty ? "Drop theme .json files into the folder." : nil) {
                if !library.themes.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(library.themes) { c in
                            card(selected: custom?.id == c.id, fill: Color.primary.opacity(0.07)) {
                                themeRaw = c.raw
                            } label: {
                                VStack(spacing: 4) { Text(c.emoji).font(.system(size: 26)); Text(c.title).font(.caption2).lineLimit(1) }
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button { library.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Button { library.openFolder() } label: { Label("Open folder", systemImage: "folder") }
                }
                .controlSize(.small)
                if !library.errors.isEmpty {
                    DisclosureGroup("\(library.errors.count) theme file\(library.errors.count == 1 ? "" : "s") with problems") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(library.errors, id: \.self) { e in
                                Text(e).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.top, 4)
                    }
                    .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var teamPicker: some View {
        SettingsCard(title: "Your team") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(Team.allCases) { tm in
                    card(selected: tm.rawValue == teamRaw, fill: Color.primary.opacity(0.07), padding: 6) {
                        teamRaw = tm.rawValue
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(tm.shirt).overlay(Circle().stroke(tm.trim, lineWidth: 2)).frame(width: 14, height: 14)
                            Text(tm.name).font(.caption2).lineLimit(1)
                        }
                    }
                }
            }
        }
    }


    private var providers: some View {
        SettingsCard(title: "Providers",
                     footer: "Sessions are read locally. Usage limits are opt-in per provider; tokens only go to that provider's own host.") {
            ProviderSettingsView(sessions: monitor.sessions)
            PricesRow()
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Notifications") { NotificationSettingsView() }
            SettingsCard(title: "Quiet hours") { FocusSettingsView() }
            SettingsCard(title: "Daily summary") { DailySummarySettingsView() }
            SettingsCard(title: "Budgets", footer: "0 = no limit. Alerts fire at 80% and 100%.") {
                BudgetSettingsView()
            }
        }
    }

    /// Power and novelty features live here so the main tabs stay short.
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: "Sync") { SyncSettingsView() }
            SettingsCard(title: "Reply from Hubbub", footer: "Off by default. Hubbub never answers for you. See docs/REPLY.md.") {
                ReplySettingsView()
            }
            SettingsCard(title: "Mini HUD") { HudSettingsView() }
            SettingsCard(title: "Sound") {
                row("Click sounds", "Small sounds when you click characters and props.") {
                    Toggle("Click sounds", isOn: $sounds).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                SoundSettingsView()
            }
            SettingsCard(title: "Theme music") { MusicSettingsView() }
            SettingsCard(title: "Just for fun", footer: "Off by default.") { FunSettingsView() }
            SettingsCard(title: "Developer") {
                row("Test failure effect", "Plays the failure animation.") {
                    Button("Run") { stage.simulateFailure() }.controlSize(.small)
                }
            }
        }
    }

    // MARK: Helpers

    private func row<C: View>(_ title: String, _ help: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption)
                Text(help).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }

    private func card<L: View, F: ShapeStyle>(selected: Bool, fill: F, padding: CGFloat = 8,
                                              action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity).padding(padding)
                .background(RoundedRectangle(cornerRadius: 9).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
