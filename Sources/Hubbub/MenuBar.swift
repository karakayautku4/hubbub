import SwiftUI
import AppKit
import Combine

enum MenuBarDisplay: String { case iconOnly, iconAndPercent }

/// Settings picker for the menu bar display (UserDefaults key `menuBarDisplay`).
struct MenuBarDisplaySetting: View {
    @AppStorage("menuBarDisplay") private var raw = MenuBarDisplay.iconAndPercent.rawValue
    var body: some View {
        Picker("Menu bar shows", selection: $raw) {
            Text("Icon + quota %").tag(MenuBarDisplay.iconAndPercent.rawValue)
            Text("Icon only").tag(MenuBarDisplay.iconOnly.rawValue)
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Menu bar display")
    }
}

/// What the status item shows; computed from the shared models and only applied when it changes.
@MainActor
struct MenuBarStatus: Equatable {
    enum Badge: Equatable { case none, working, approval, failed
        var color: NSColor? {
            switch self {
            case .none: nil
            case .working: .systemGreen
            case .approval: .systemOrange
            case .failed: .systemRed
            }
        }
    }
    var emoji: String
    var badge: Badge
    var text: String?
    var summary: String

    static func make(monitor: SessionMonitor, quota: QuotaService, budget: BudgetCenter) -> MenuBarStatus {
        let pq = ProviderQuotaService.shared
        let d = UserDefaults.standard
        let themeRaw = d.string(forKey: "theme") ?? Theme.defaultTheme.rawValue
        let displayRaw = d.string(forKey: "menuBarDisplay") ?? MenuBarDisplay.iconAndPercent.rawValue
        let (theme, custom) = CustomThemes.shared.resolve(themeRaw)
        let working = monitor.sessions.filter { $0.state == .working }.count
        let approvals = monitor.sessions.filter { $0.waitingApproval }.count
        let attn = monitor.attention
        let badge: Badge = attn != .none ? .failed : approvals > 0 ? .approval : working > 0 ? .working : .none
        // Without a Copilot quota, show the most-used window of the provider with the most recent session (opt-in only).
        let fallback: (id: String, pct: Double)? = quota.quota != nil ? nil : monitor.sessions.sorted { $0.lastEvent > $1.lastEvent }
            .lazy.compactMap { s in pq.headline(s.provider).map { (s.provider, $0) } }.first
        let text: String? = {
            guard MenuBarDisplay(rawValue: displayRaw) != .iconOnly else { return nil }
            if let q = quota.quota { return q.unlimited ? "∞" : "\(Int((100 - q.percentRemaining).rounded()))%" }
            if let f = fallback { return "\(Int(f.pct.rounded()))%" }
            return quota.error != nil && !quota.noToken ? "–" : nil
        }()

        var parts = ["Hubbub"]
        if let q = quota.quota { parts.append(q.unlimited ? "Copilot quota unlimited" : "Copilot quota \(Int((100 - q.percentRemaining).rounded()))% used") }
        else if let f = fallback { parts.append("\(ProviderRegistry.shared.name(for: f.id)) usage \(Int(f.pct.rounded()))% used") }
        else if quota.error != nil && !quota.noToken { parts.append("Copilot quota unavailable") }
        if working > 0 { parts.append("\(working) session\(working == 1 ? "" : "s") working") }
        if approvals > 0 { parts.append("\(approvals) needs approval") }
        if attn != .none { parts.append(attn == .stuck ? "a session looks stuck" : "a session failed") }
        if budget.showWarning { parts.append("! budget limit exceeded") }
        let summary = parts.joined(separator: " · ")

        let shown = budget.showWarning ? [text, "!"].compactMap { $0 }.joined(separator: " ") : text
        return MenuBarStatus(emoji: custom?.emoji ?? theme.icon, badge: badge, text: shown, summary: summary)
    }

    func image() -> NSImage {
        Self.render(emoji: emoji, badge: badge.color)
    }

    private static func render(emoji: String, badge: NSColor?) -> NSImage {
        let h: CGFloat = 18
        let img = NSImage(size: NSSize(width: h, height: h), flipped: false) { rect in
            let s = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 14)])
            let sz = s.size()
            s.draw(at: NSPoint(x: (rect.width - sz.width) / 2, y: (rect.height - sz.height) / 2))
            if let badge {
                let d: CGFloat = 7
                let r = NSRect(x: rect.maxX - d, y: 0, width: d, height: d)
                NSColor.black.withAlphaComponent(0.35).setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: -1, dy: -1)).fill()
                badge.setFill()
                NSBezierPath(ovalIn: r).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}

/// Owns the NSStatusItem: icon + status dot + quota percent. A click toggles the popover; right-click is handled by IntegrationHub's menu.
@MainActor
final class MenuBarController {
    static let shared = MenuBarController()
    private var item: NSStatusItem?
    private var bag = Set<AnyCancellable>()
    private var last: MenuBarStatus?

    func install() {
        guard item == nil else { return }
        let app = AppModel.shared
        app.start()
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.autosaveName = "HubbubStatusItem"
        // A force-quit can leave macOS' per-item "visible" flag at 0, which silently hides the icon on the next launch.
        let d = UserDefaults.standard
        for k in d.dictionaryRepresentation().keys where k.hasPrefix("NSStatusItem Visible") { d.removeObject(forKey: k) }
        it.isVisible = true
        if let b = it.button {
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp])
            b.imagePosition = .imageLeft
        }
        item = it
        SurfaceController.shared.anchor = { [weak self] in self?.item?.button }

        let triggers: [AnyPublisher<Void, Never>] = [
            app.monitor.objectWillChange.eraseToAnyPublisher(),
            app.quota.objectWillChange.eraseToAnyPublisher(),
            app.budget.objectWillChange.eraseToAnyPublisher(),
            ProviderQuotaService.shared.objectWillChange.eraseToAnyPublisher(),
            CustomThemes.shared.objectWillChange.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &bag)
        refresh()
    }

    private func refresh() {
        let app = AppModel.shared
        let s = MenuBarStatus.make(monitor: app.monitor, quota: app.quota, budget: app.budget)
        guard s != last, let b = item?.button else { return }
        last = s
        b.image = s.image()
        b.title = s.text.map { " " + $0 } ?? ""
        b.toolTip = s.summary
        b.setAccessibilityLabel(s.summary)
    }

    @objc private func clicked() { SurfaceController.shared.statusItemClicked() }
}
