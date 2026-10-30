import SwiftUI
import AppKit
import Combine

/// Runtime glue for integrations: `hubbub://` links, right-click menu, mini HUD, Focus guard and the end-of-day summary.
@MainActor
final class IntegrationHub: NSObject {
    static let shared = IntegrationHub()

    enum Key {
        static let summaryEnabled = "dailySummaryEnabled"
        static let summaryMinute = "dailySummaryMinute"
        static let summaryLastDay = "dailySummaryLastDay"
    }

    private weak var monitor: SessionMonitor?
    private weak var quota: QuotaService?
    private var bag = Set<AnyCancellable>()
    private var attached = false
    private var summaryTimer: Timer?
    private let launchedAt = Date()

    // MARK: URL scheme

    /// Registers the Apple Event handler for `hubbub://` links; call as early as possible at launch.
    func installURLHandler() {
        register()
        // AppKit installs its own kAEGetURL handler during finishLaunching, which would replace ours.
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
    }

    private func register() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s),
              let route = HubbubURL.parse(url) else { return }
        // A link that launches the app arrives before the menu bar item exists.
        let delay = Date().timeIntervalSince(launchedAt) < 5 ? 0.8 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.perform(route) }
    }

    func perform(_ route: HubbubRoute) {
        let router = AppRouter.shared
        let d = UserDefaults.standard
        switch route {
        case .open: router.open(sessionID: nil)
        case .session(let id): router.open(sessionID: id)
        case .insights: router.open(screen: "insights")
        case .history: router.open(screen: "history")
        case .achievements: router.open(screen: "achievements")
        case .settings(let tab):
            if let tab { d.set(tab, forKey: "settingsTab") }
            router.open(screen: "settings")
        case .theme(let name):
            let n = name.lowercased()
            if let t = Theme.named(name) { d.set(t.rawValue, forKey: "theme") }
            else if let c = CustomThemes.shared.themes.first(where: { $0.id.lowercased() == n || $0.raw.lowercased() == n || $0.title.lowercased() == n }) { d.set(c.raw, forKey: "theme") }
        case .refresh:
            monitor?.refresh()
            quota?.refresh()
        }
    }

    // MARK: Lifecycle

    func attach(monitor: SessionMonitor, quota: QuotaService) {
        self.monitor = monitor
        self.quota = quota
        guard !attached else { return }
        attached = true
        let push = { [weak self] in
            guard let self, let m = self.monitor else { return }
            HudModel.shared.update(sessions: m.sessions, quota: self.quota?.quota, attention: m.attention != .none)
        }
        monitor.$sessions.dropFirst().sink { _ in DispatchQueue.main.async(execute: push) }.store(in: &bag)
        quota.$quota.dropFirst().sink { _ in DispatchQueue.main.async(execute: push) }.store(in: &bag)
        push()
        HudController.shared.apply()
        FocusGuard.shared.start()
        installContextMenu()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkDailySummary() } }
        t.tolerance = 20
        RunLoop.main.add(t, forMode: .common)
        summaryTimer = t
    }

    // MARK: End-of-day summary

    func checkDailySummary(now: Date = Date()) {
        let d = UserDefaults.standard
        guard d.bool(forKey: Key.summaryEnabled), let m = monitor else { return }
        let target = d.object(forKey: Key.summaryMinute) as? Int ?? 18 * 60
        let minute = QuietHours.minuteOfDay(now)
        let day = Self.dayString(now)
        // Only within three hours after the chosen time, so a late launch doesn't deliver a stale summary.
        guard minute >= target, minute < target + 180, d.string(forKey: Key.summaryLastDay) != day else { return }
        d.set(day, forKey: Key.summaryLastDay)
        postSummary(m.sessions, now: now)
    }

    func sendSummaryNow() { postSummary(monitor?.sessions ?? []) }

    func postSummary(_ sessions: [SessionInfo], now: Date = Date()) {
        let r = DailySummary.compute(sessions, now: now)
        Notifier.shared.post("Your day with Hubbub", DailySummary.text(r, providerName: { ProviderRegistry.shared.name(for: $0) }),
                             id: "daily-summary", info: ["screen": "insights"])
    }

    private static func dayString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: Right-click menu (menu bar item and HUD)

    private func installContextMenu() {
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let w = event.window, let view = w.contentView else { return event }
            let isStatus = String(describing: type(of: w)).contains("StatusBar")
            guard isStatus || w === HudController.shared.panel else { return event }
            MainActor.assumeIsolated { NSMenu.popUpContextMenu(self.buildMenu(), with: event, for: view) }
            return nil
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, on: Bool = false, key: String = "") {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            if !key.isEmpty { i.keyEquivalentModifierMask = .command }
            i.target = self
            i.state = on ? .on : .off
            m.addItem(i)
        }
        add("Open Hubbub", #selector(menuOpen))
        add(SurfaceController.shared.windowVisible ? "Dock to Menu Bar" : "Expand to Window", #selector(menuExpand), key: "e")
        add("Refresh", #selector(menuRefresh))
        add("Settings…", #selector(menuSettings))
        add("Check for Updates…", #selector(menuCheckUpdates))
        m.addItem(.separator())
        add("Show mini HUD", #selector(menuToggleHud), on: HudController.shared.isEnabled)
        if HudController.shared.isEnabled { add("HUD click-through", #selector(menuToggleClickThrough), on: HudController.shared.clickThrough) }
        m.addItem(.separator())
        add("Quit Hubbub", #selector(menuQuit))
        return m
    }

    @objc private func menuOpen() { perform(.open) }
    @objc private func menuExpand() { SurfaceController.shared.toggleExpanded() }
    @objc private func menuRefresh() { perform(.refresh) }
    @objc private func menuCheckUpdates() { UpdateChecker.shared.checkWithAlert() }
    @objc private func menuSettings() { perform(.settings(nil)) }
    @objc private func menuToggleHud() { HudController.shared.setEnabled(!HudController.shared.isEnabled) }
    @objc private func menuToggleClickThrough() { HudController.shared.setClickThrough(!HudController.shared.clickThrough) }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
