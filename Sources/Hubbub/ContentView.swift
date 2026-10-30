import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var quotaService: QuotaService
    var layout: HubbubLayout = .popover
    @AppStorage("theme") private var themeRaw = Theme.defaultTheme.rawValue
    @AppStorage("sounds") private var sounds = true
    @AppStorage("team") private var teamRaw = Team.fallback.rawValue
    @AppStorage("notifications") private var notifications = true
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("showWelcome") private var showWelcome = false
    @AppStorage("stageHintDismissed") private var stageHintDismissed = false
    @AppStorage(PopoverSize.key) private var sizeRaw = PopoverSize.compact.rawValue
    @State private var hotkeyToastDismissed: String?
    @ObservedObject private var app = AppModel.shared
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var hotkey = HotkeyManager.shared
    @ObservedObject private var library = CustomThemes.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var progression = ProgressionCenter.shared
    @State private var detailSheet: DetailTarget?

    private struct DetailTarget: Identifiable { let id: String }

    private var stage: Stage { app.stage }
    private var screen: Screen { app.screen }
    private var selectedID: String? { app.selectedID }
    private var isWindow: Bool { layout == .window }
    private var compact: Bool { !isWindow && sizeRaw != PopoverSize.comfortable.rawValue }
    private var theme: Theme { library.resolve(themeRaw).0 }
    private var custom: CustomTheme? { library.resolve(themeRaw).1 }
    private var onboardingVisible: Bool { !hasOnboarded || showWelcome }
    private var selected: SessionInfo? {
        monitor.sessions.first { $0.id == selectedID } ?? sortedSessions.first
    }
    private var inSettings: Bool { screen == .settings }
    private var updateOffer: UpdateChecker.Release? {
        guard let r = updates.available, hasOnboarded, !showWelcome, !updates.snoozed else { return nil }
        return r
    }

    /// Stable order: by start time, then id. State is shown via glyphs, so chips never jump.
    private var sortedSessions: [SessionInfo] {
        monitor.sessions.sorted {
            switch ($0.startedAt, $1.startedAt) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }

    private func syncStage() {
        stage.sessions = monitor.sessions
        stage.theme = theme
        stage.custom = custom
        stage.team = Team.from(teamRaw)
        stage.selectedSessionID = selected?.id
    }

    // MARK: Navigation

    private func go(_ s: Screen) {
        withAnimation(.easeInOut(duration: 0.15)) { app.screen = s }
    }

    private func back() {
        if detailSheet != nil { detailSheet = nil; return }
        switch screen {
        case .live: if !isWindow { SurfaceController.shared.closePopover() }
        case .history, .insights, .achievements, .settings, .detail: go(.live)
        }
    }

    private func openDetail() { if let s = selected { showDetail(s.id) } }

    /// The expanded window shows Details as a sheet over the stage; the popover navigates to it.
    private func showDetail(_ id: String) {
        if isWindow { detailSheet = DetailTarget(id: id) } else { go(.detail(id)) }
    }

    private func openSettings(_ tab: String?) {
        if let tab { UserDefaults.standard.set(tab, forKey: "settingsTab") }
        go(.settings)
    }

    /// Popover and window both observe the router; only the surface that is actually showing handles a request.
    private var isActiveSurface: Bool { isWindow == SurfaceController.shared.windowVisible }

    private func consumePendingScreen() {
        guard isActiveSurface, let s = router.pendingScreen else { return }
        router.pendingScreen = nil
        switch s {
        case "insights": go(.insights)
        case "history": go(.history)
        case "achievements": go(.achievements)
        case "settings": go(.settings)
        default: go(.live)
        }
    }

    private func consumePending() {
        guard isActiveSurface, let id = router.pendingSessionID else { return }
        router.pendingSessionID = nil
        if monitor.sessions.contains(where: { $0.id == id }) {
            app.selectedID = id
            stage.select(nil)
            showDetail(id)
        } else {
            go(.live)
        }
    }

    private func moveSelection(_ delta: Int) {
        let list = sortedSessions
        guard list.count > 1, let cur = list.firstIndex(where: { $0.id == selected?.id }) else { return }
        let next = list[(cur + delta + list.count) % list.count].id
        select(next)
    }

    private func stepSession(_ delta: Int) {
        let list = sortedSessions
        guard !list.isEmpty else { return }
        let cur = list.firstIndex { $0.id == selected?.id } ?? 0
        select(list[(cur + delta + list.count) % list.count].id)
    }

    private func select(_ id: String) {
        app.selectedID = id
        stage.select(nil)
        switch screen {
        case .detail: app.screen = .detail(id)
        default: break
        }
    }

    /// The arrow shortcuts must not steal the caret while a text field (search, reply, tags) is being edited.
    private func moveCaret(left: Bool) -> Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        if left { tv.moveLeft(nil) } else { tv.moveRight(nil) }
        return true
    }

    private func cycleTheme(_ delta: Int) {
        let ids = Theme.allCases.map(\.rawValue) + library.themes.map(\.raw)
        guard !ids.isEmpty else { return }
        let cur = ids.firstIndex(of: themeRaw) ?? 0
        themeRaw = ids[(cur + delta + ids.count) % ids.count]
    }

    private var tabBinding: Binding<Screen> {
        Binding(get: {
            switch screen { case .history: .history; case .insights: .insights; case .achievements: .achievements; default: .live }
        }, set: { go($0) })
    }

    private var nav: HubbubNav {
        HubbubNav(openDetail: { openDetail() },
                  back: { back() },
                  refreshQuota: { quotaService.refresh() },
                  openSettings: { openSettings($0) })
    }

    // MARK: Body

    var body: some View {
        let _ = syncStage()
        Group {
            if isWindow { windowBody } else { popoverBody }
        }
        .environment(\.hubbubNav, nav)
        .halloweenChrome()
        .overlay(alignment: .top) { ProgressToastHost() }
        .background(shortcuts)
        .animation(.easeInOut(duration: 0.15), value: hotkey.error)
        .onAppear { consumePending(); consumePendingScreen() }
        .task { updates.checkIfDue() }
        .onChange(of: router.pendingSessionID) { _ in consumePending() }
        .onChange(of: router.pendingScreen) { _ in consumePendingScreen() }
        .onChange(of: statusTokens) { old, new in announceStatusChanges(old, new) }
    }

    private var stageSummary: String {
        A11yNarration.summary(themeTitle: theme.title, sessions: sortedSessions, attention: monitor.attentionByID)
    }

    private var statusTokens: [String: String] {
        Dictionary(uniqueKeysWithValues: monitor.sessions.map { ($0.id, A11yNarration.status($0, attention: monitor.attentionByID[$0.id] ?? .none)) })
    }

    private func announceStatusChanges(_ old: [String: String], _ new: [String: String]) {
        let names = Dictionary(uniqueKeysWithValues: monitor.sessions.map { ($0.id, $0.name) })
        for line in A11yNarration.announcements(old: old, new: new, names: names) { A11yNarration.announce(line) }
    }

    // MARK: Layouts

    private var onStage: Bool { screen == .live || isWindow }

    /// One stage slot per layout, always in the hierarchy so the shared SCNView keeps its size; parked while another screen is showing.
    private var stageBlock: some View {
        StageSlot(kind: isWindow ? .window : .popover, parked: !onStage)
            .modifier(StageFrame(isWindow: isWindow, parked: !onStage))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageSummary)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityAction(named: "Next session") { stepSession(1) }
            .accessibilityAction(named: "Previous session") { stepSession(-1) }
            .overlay(alignment: .bottom) {
                if onStage, !onboardingVisible, !stageHintDismissed, !monitor.sessions.isEmpty {
                    CoachMark { stageHintDismissed = true }
                }
            }
            .overlay(alignment: .topTrailing) {
                if onStage { HStack(spacing: 0) { StageZoomControl(stage: stage); RaceModeButton(); CameraModeButton() } }
            }
    }

    private var toast: some View {
        Group {
            if let msg = hotkey.error, msg != hotkeyToastDismissed {
                ToastRow(message: msg) { hotkeyToastDismissed = msg }
            }
        }
    }

    private func scrollPage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 2)
        }
        .frame(maxHeight: .infinity)
    }

    /// Everything below the header/stage for the current screen.
    @ViewBuilder private var pageArea: some View {
        switch screen {
        case .live:
            scrollPage {
                if onboardingVisible { OnboardingCard() }
                liveContent
            }
        case .settings:
            SettingsView(monitor: monitor, stage: stage).frame(maxHeight: .infinity, alignment: .top)
        default:
            scrollPage { pageContent }
        }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            stageBlock
            if screen == .live, !sortedSessions.isEmpty { switcher }
            toast
            pageArea
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var windowBody: some View {
        HStack(spacing: 0) {
            stageBlock.padding(12)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                header
                if screen == .live, !sortedSessions.isEmpty {
                    if sortedSessions.count > 1 { sessionList } else { switcher }
                }
                toast
                pageArea
            }
            .padding(12)
            .frame(width: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $detailSheet) { t in detailSheetContent(t.id) }
    }

    private var sessionList: some View {
        let list = sortedSessions
        return ScrollView {
            LazyVStack(spacing: 4) { ForEach(list) { s in sessionRow(s) } }
                .padding(.vertical, 1)
        }
        .frame(height: min(CGFloat(list.count) * (Space.row + 4) + 2, 6 * (Space.row + 4)))
        .accessibilityLabel("\(list.count) sessions")
    }

    // MARK: Header

    private var expandButton: some View {
        Button { SurfaceController.shared.toggleExpanded() } label: {
            Image(systemName: isWindow ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isWindow ? "Dock to menu bar" : "Expand to window")
        .help(isWindow ? "Dock back to the menu bar (⌘E)" : "Expand to a resizable window (⌘E)")
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch screen {
            case .live, .history, .insights, .achievements:
                if compact || isWindow { compactTitle } else { titleCluster }
                tabs
            case .settings:
                backButton("Back")
                Text("Settings").font(.headline)
            case .detail(let id):
                backButton("Sessions")
                crumb(sessionName(id))
            }
            Spacer(minLength: 4)
            expandButton
            if !inSettings {
                gearMenu
            } else {
                Button { go(.live) } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close settings")
                    .help("Close settings (Esc)")
            }
        }
        .frame(height: 24)
    }

    /// Icon + theme menu; room-saving stand-in for the ‹ theme › cluster.
    private var compactTitle: some View {
        Menu {
            Button("Next theme") { cycleTheme(1) }
            Button("Previous theme") { cycleTheme(-1) }
            Divider()
            ForEach(Theme.allCases) { t in Button("\(t.icon) \(t.title)") { themeRaw = t.rawValue } }
            ForEach(library.themes) { c in Button("\(c.emoji) \(c.title)") { themeRaw = c.raw } }
        } label: {
            HStack(spacing: 4) {
                if let c = custom { Text(c.emoji).font(.system(size: 16)) } else { ThemeIcon(theme: theme, size: 16) }
                Text(themeName).font(.caption).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
        .accessibilityLabel("Theme: \(themeName)")
        .help("Change theme")
    }

    private func sessionName(_ id: String) -> String {
        monitor.sessions.first { $0.id == id }?.name ?? "Session"
    }

    private var themeName: String { custom?.title ?? theme.title }

    private var titleCluster: some View {
        HStack(spacing: 5) {
            Group {
                if let c = custom { Text(c.emoji).font(.system(size: 16)) } else { ThemeIcon(theme: theme, size: 16) }
            }
            .contextMenu {
                Button("Next theme") { cycleTheme(1) }
                Button("Previous theme") { cycleTheme(-1) }
                Divider()
                ForEach(Theme.allCases) { t in Button("\(t.icon) \(t.title)") { themeRaw = t.rawValue } }
                ForEach(library.themes) { c in Button("\(c.emoji) \(c.title)") { themeRaw = c.raw } }
            }
            .accessibilityHidden(true)
            Text("Hubbub").font(.headline)
            Button { cycleTheme(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Previous theme").help("Previous theme")
            Text(themeName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityLabel("Theme: \(themeName)")
            Button { cycleTheme(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Next theme").help("Next theme")
        }
    }

    private func backButton(_ title: String) -> some View {
        Button { back() } label: { Label(title, systemImage: "chevron.left").lineLimit(1) }
            .buttonStyle(.borderless)
            .accessibilityLabel("Back to \(title)")
            .help("Back (Esc or ⌘[)")
    }

    private func crumb(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text("/").foregroundStyle(.secondary)
            Text(text).font(.headline).lineLimit(1)
        }
    }

    private var tabs: some View {
        Picker("View", selection: tabBinding) {
            Text("Live").tag(Screen.live)
            Text("Insights").tag(Screen.insights)
            Text("History").tag(Screen.history)
            Text("Awards").accessibilityLabel("Achievements").tag(Screen.achievements)
        }
        .pickerStyle(.segmented).labelsHidden()
        .controlSize(.small)
        .frame(width: 236)
        .accessibilityLabel("View")
        .help("Live (⌘1) · Insights (⌘2) · History (⌘3) · Awards (⌘4)")
    }

    // MARK: Page content

    @ViewBuilder private var pageContent: some View {
        switch screen {
        case .live: liveContent
        case .history: HistoryView()
        case .insights: InsightsView(monitor: monitor)
        case .detail(let id):
            if let s = monitor.sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: s, attention: monitor.attentionByID[s.id] ?? .none) { go(.live) }
                    .id(s.id)
            } else {
                Text("This session is no longer available.").font(.caption).foregroundStyle(.secondary)
            }
        case .settings: SettingsView(monitor: monitor, stage: stage)
        case .achievements: AchievementsView()
        }
    }

    @ViewBuilder private var liveContent: some View {
        if let s = selected {
            LiveSessionPanel(session: s, attention: monitor.attentionByID[s.id] ?? .none, theme: theme, stacked: isWindow,
                             onConnectQuota: { openSettings("providers") }, onDetails: { openDetail() }, quotaService: quotaService)
        } else {
            NoSessionsCard(onCheckAgain: { monitor.refresh() })
            QuotaBar(provider: "copilot", theme: theme, quotaService: quotaService, onConnect: { openSettings("providers") })
        }
    }

    private func detailSheetContent(_ id: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if let s = monitor.sessions.first(where: { $0.id == id }) {
                        SessionDetailView(session: s, attention: monitor.attentionByID[s.id] ?? .none) { detailSheet = nil }
                    } else {
                        Text("This session is no longer available.").font(HubFont.body).foregroundStyle(.secondary)
                    }
                }
                .padding(Space.md)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { detailSheet = nil }.keyboardShortcut(.cancelAction)
            }
            .padding(Space.sm)
        }
        .frame(width: 440, height: 560)
        .environment(\.hubbubNav, nav)
    }

    // MARK: Session switcher

    private func glyph(_ s: SessionInfo) -> (name: String, color: Color, label: String) {
        let level = monitor.attentionByID[s.id] ?? .none
        if level == .stuck { return ("exclamationmark.triangle.fill", .red, "stuck") }
        if level == .failed { return ("xmark.octagon.fill", .red, "failed") }
        if s.waitingApproval { return ("hand.raised.fill", .orange, "waiting for approval") }
        switch s.state {
        case .working: return ("play.fill", .green, "working")
        case .idle: return ("moon.fill", .secondary, "idle")
        case .offline: return ("poweroff", .secondary, "offline")
        }
    }

    /// One-line pill: pick a session from a menu, or step with ‹ ›. The window uses `sessionList` instead.
    private var switcher: some View {
        let list = sortedSessions
        let idx = list.firstIndex { $0.id == selected?.id } ?? 0
        return HStack(spacing: Space.xs) {
            Menu {
                ForEach(list) { s in
                    Button { select(s.id) } label: {
                        Label(s.name, systemImage: s.id == selected?.id ? "checkmark" : glyph(s).name)
                    }
                }
            } label: {
                if let s = selected {
                    let g = glyph(s)
                    HStack(spacing: 6) {
                        Image(systemName: g.name).font(.system(size: 11, weight: .bold)).foregroundStyle(g.color)
                        ProviderBadge(provider: s.provider)
                        Text(list.count > 1 ? "\(s.name) · \(idx + 1)/\(list.count)" : s.name)
                            .font(HubFont.body).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Session: \(s.name), \(g.label)\(list.count > 1 ? ", \(idx + 1) of \(list.count)" : "")")
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.visible)
            .padding(.horizontal, 10)
            .frame(height: Space.row)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .a11yContrastBorder(Capsule())
            .help("Switch session (← →)")
            if list.count > 1 {
                Button { stepSession(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Previous session").help("Previous session (←)")
                Button { stepSession(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Next session").help("Next session (→)")
            }
        }
    }

    private func sessionRow(_ s: SessionInfo) -> some View {
        let g = glyph(s)
        let isSel = s.id == selected?.id
        return Button { select(s.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: g.name).font(.system(size: 11, weight: .bold)).foregroundStyle(g.color)
                ProviderBadge(provider: s.provider)
                Text(s.name).font(HubFont.body).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Space.row, alignment: .leading)
            .background(Capsule().fill(Color.primary.opacity(isSel ? 0.18 : 0.06)))
            .a11yContrastBorder(Capsule())
        }
        .buttonStyle(.plain)
        .id(s.id)
        .help("\(s.name) — \(g.label)")
        .accessibilityLabel("\(s.name), \(g.label)")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    // MARK: Gear menu

    private var gearMenu: some View {
        Menu {
            Button("Settings…") { go(.settings) }
            Button(isWindow ? "Dock to menu bar" : "Expand to window") { SurfaceController.shared.toggleExpanded() }
            if let r = updateOffer {
                Menu("Update to \(r.version)") {
                    Button("Download") { updates.download() }
                    Button("Release notes") { NSWorkspace.shared.open(r.url) }
                    Button("Remind me later") { updates.remindLater() }
                    Button("Skip this version") { updates.skip() }
                }
            }
            Button(updates.checking ? "Checking for Updates…" : "Check for Updates…") { go(.settings); updates.check(manual: true) }
                .disabled(updates.checking)
            Divider()
            Button("Quit Hubbub") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .overlay(alignment: .topTrailing) {
                    if updateOffer != nil { Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 3, y: -3) }
                }
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel(updateOffer == nil ? "Menu" : "Menu, update available")
        .help("Settings, expand, quit")
    }

    // MARK: Shortcuts (hidden buttons)

    private var shortcuts: some View {
        ZStack {
            Button("Back") { back() }.keyboardShortcut(.cancelAction)
            Button("Back") { back() }.keyboardShortcut("[", modifiers: .command)
            Button("Settings") { go(inSettings ? .live : .settings) }.keyboardShortcut(",", modifiers: .command)
            Button("Refresh") { quotaService.refresh(); monitor.refresh() }.keyboardShortcut("r", modifiers: .command)
            Button("Expand") { SurfaceController.shared.toggleExpanded() }.keyboardShortcut("e", modifiers: .command)
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
            if isWindow { Button("Close window") { SurfaceController.shared.closeWindow() }.keyboardShortcut("w", modifiers: .command) }
            else { Button("Close popover") { SurfaceController.shared.closePopover() }.keyboardShortcut("w", modifiers: .command) }
            Button("Zoom in") { stage.zoomBy(direction: 1) }.keyboardShortcut("+", modifiers: .command)
            Button("Live") { go(.live) }.keyboardShortcut("1", modifiers: .command)
            Button("Insights") { go(.insights) }.keyboardShortcut("2", modifiers: .command)
            Button("History") { go(.history) }.keyboardShortcut("3", modifiers: .command)
            Button("Awards") { go(.achievements) }.keyboardShortcut("4", modifiers: .command)
            if !inSettings, sortedSessions.count > 1 {
                Button("Previous session") { if !moveCaret(left: true) { moveSelection(-1) } }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Next session") { if !moveCaret(left: false) { moveSelection(1) } }.keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
    }
}


/// Emoji for the theme.
struct ThemeIcon: View {
    let theme: Theme
    let size: CGFloat
    var body: some View {
        Text(theme.icon).font(.system(size: size))
    }
}
