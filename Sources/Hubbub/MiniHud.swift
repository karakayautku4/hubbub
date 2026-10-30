import SwiftUI
import AppKit
import Combine

/// Small snapshot the HUD renders; only republished when something visible changes.
@MainActor
final class HudModel: ObservableObject {
    static let shared = HudModel()
    @Published var percent: String = "–"
    @Published var active = 0
    @Published var dot: Color = .gray

    func update(sessions: [SessionInfo], quota: Quota?, attention: Bool) {
        let working = sessions.filter { $0.state == .working }.count
        let approval = sessions.contains { $0.waitingApproval }
        let pct: String = {
            if let q = quota { return q.unlimited ? "∞" : "\(Int((100 - q.percentRemaining).rounded()))%" }
            let fb = sessions.sorted { $0.lastEvent > $1.lastEvent }.lazy.compactMap { ProviderQuotaService.shared.headline($0.provider) }.first
            return fb.map { "\(Int($0.rounded()))%" } ?? "–"
        }()
        let color: Color = attention ? .red : approval ? .orange : working > 0 ? .green : .gray
        if pct != percent { percent = pct }
        if working != active { active = working }
        if color != dot { dot = color }
    }
}

struct MiniHudView: View {
    @ObservedObject var model: HudModel
    @AppStorage("theme") private var themeRaw = Theme.defaultTheme.rawValue

    var body: some View {
        let (theme, custom) = CustomThemes.shared.resolve(themeRaw)
        HStack(spacing: 8) {
            Text(custom?.emoji ?? theme.icon).font(.system(size: 18))
            Text(model.percent).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Label("\(model.active)", systemImage: "person.2.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Circle().fill(model.dot).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(A11y.panelFill(.ultraThinMaterial), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hubbub: quota \(model.percent), \(model.active) active agent\(model.active == 1 ? "" : "s")")
    }
}

/// Floating always-on-top mini HUD. Static SwiftUI content that re-renders only when `HudModel` changes.
@MainActor
final class HudController {
    static let shared = HudController()
    static let enabledKey = "hudEnabled", clickThroughKey = "hudClickThrough"
    private let xKey = "hudX", yKey = "hudY"
    private(set) var panel: NSPanel?
    private var hudBag: AnyCancellable?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var clickThrough: Bool { UserDefaults.standard.bool(forKey: Self.clickThroughKey) }

    func setEnabled(_ on: Bool) { UserDefaults.standard.set(on, forKey: Self.enabledKey); apply() }
    func setClickThrough(_ on: Bool) { UserDefaults.standard.set(on, forKey: Self.clickThroughKey); apply() }

    func apply() {
        guard isEnabled else { panel?.orderOut(nil); return }
        let p = panel ?? makePanel()
        p.ignoresMouseEvents = clickThrough
        p.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: MiniHudView(model: HudModel.shared))
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.setFrameOrigin(savedOrigin(for: size))
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.save(w.frame.origin) }
        }
        // The capsule grows with the text (e.g. "9%" → "100%"); keep the panel as wide as its content.
        hudBag = HudModel.shared.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak p, weak host] in
            guard let p, let host else { return }
            let size = host.fittingSize
            if abs(p.contentView!.frame.width - size.width) > 0.5 || abs(p.contentView!.frame.height - size.height) > 0.5 { p.setContentSize(size) }
        }
        panel = p
        return p
    }

    private func save(_ o: NSPoint) {
        UserDefaults.standard.set(Double(o.x), forKey: xKey)
        UserDefaults.standard.set(Double(o.y), forKey: yKey)
    }

    private func savedOrigin(for size: NSSize) -> NSPoint {
        let d = UserDefaults.standard
        if d.object(forKey: xKey) != nil {
            let o = NSPoint(x: d.double(forKey: xKey), y: d.double(forKey: yKey))
            if NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: o, size: size)) }) { return o }
        }
        let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(x: f.maxX - size.width - 16, y: f.maxY - size.height - 16)
    }
}
