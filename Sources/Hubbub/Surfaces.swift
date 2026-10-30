import SwiftUI
import SceneKit
import AppKit
import Combine

// MARK: Sizes

enum HubbubLayout { case popover, window }

/// Popover size preset (UserDefaults key `popoverSize`, Settings > Appearance).
enum PopoverSize: String, CaseIterable, Identifiable {
    case compact, comfortable
    static let key = "popoverSize"
    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Comfortable" }
    var width: CGFloat { self == .compact ? 440 : 560 }
    /// Same height on every screen so switching tabs never makes the popover jump.
    var height: CGFloat { self == .compact ? 600 : 740 }
    static var current: PopoverSize { PopoverSize(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .compact }

    /// Content size for a screen: the preset, capped so it never exceeds the visible area (below the menu bar, above the Dock).
    func contentSize(on screen: NSScreen?) -> NSSize {
        let vis = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        return NSSize(width: min(width, vis.width - 16), height: min(height, vis.height - 12))
    }
}

// MARK: Shared stage view

enum StageSurface { case popover, window }

/// Owns the one SCNView and moves it between the popover and the expanded window, so the scene is rendered in a single view at a time.
@MainActor
final class StageHost {
    static let shared = StageHost()
    private(set) var desired: StageSurface = .popover
    private var slots: [StageSurface: WeakSlot] = [:]
    private struct WeakSlot { weak var slot: StageSlotView? }

    private(set) lazy var scnView: StageSCNView = {
        let stage = AppModel.shared.stage
        let v = StageSCNView(frame: NSRect(x: 0, y: 0, width: 400, height: 250))
        v.stage = stage
        v.scene = stage.scene
        v.pointOfView = stage.camera
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = false
        v.backgroundColor = .black
        v.wantsLayer = true
        v.layer?.cornerRadius = 8
        v.layer?.masksToBounds = true
        stage.view = v
        stage.start()
        return v
    }()

    func register(_ slot: StageSlotView) {
        slots[slot.kind] = WeakSlot(slot: slot)
        if slot.kind == desired { slot.adopt() }
    }

    func unregister(_ slot: StageSlotView) {
        if slots[slot.kind]?.slot === slot { slots[slot.kind] = nil }
    }

    /// Moves the SCNView into the slot of `surface` (now, or as soon as that slot exists).
    func claim(_ surface: StageSurface) {
        desired = surface
        slots[surface]?.slot?.adopt()
    }
}

final class StageSlotView: NSView {
    let kind: StageSurface
    var parked = false { didSet { if parked != oldValue { MainActor.assumeIsolated { applyParked() } } } }

    init(kind: StageSurface) {
        self.kind = kind
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    @MainActor func adopt() {
        let v = StageHost.shared.scnView
        guard v.superview !== self else { applyParked(); return }
        v.removeFromSuperview()
        v.autoresizingMask = []
        v.frame = bounds
        addSubview(v)
        applyParked()
    }

    override func layout() {
        super.layout()
        // While parked the view keeps its last real size, so the camera framing doesn't change.
        guard !parked, bounds.height > 8, let v = subviews.first(where: { $0 is StageSCNView }) else { return }
        if v.frame != bounds { v.frame = bounds }
    }

    @MainActor private func applyParked() {
        guard let v = subviews.first(where: { $0 is StageSCNView }) as? StageSCNView else { return }
        v.isHidden = parked
        if parked {
            v.isPlaying = false
            v.rendersContinuously = false
            v.scene = nil
        } else if Stage.popoverVisible, let stage = v.stage {
            v.scene = stage.scene
            v.pointOfView = stage.camera
            v.isPlaying = true
            v.rendersContinuously = true
            needsLayout = true
        }
    }
}

struct StageSlot: NSViewRepresentable {
    let kind: StageSurface
    let parked: Bool

    func makeNSView(context: Context) -> StageSlotView {
        let v = StageSlotView(kind: kind)
        v.parked = parked
        MainActor.assumeIsolated { StageHost.shared.register(v) }
        return v
    }

    func updateNSView(_ v: StageSlotView, context: Context) { v.parked = parked }

    static func dismantleNSView(_ v: StageSlotView, coordinator: ()) {
        MainActor.assumeIsolated { StageHost.shared.unregister(v) }
    }
}

/// 16:10 stage in the popover, filling stage in the window, collapsed while another screen is showing.
struct StageFrame: ViewModifier {
    let isWindow: Bool
    let parked: Bool
    func body(content: Content) -> some View {
        content
            .aspectRatio(isWindow || parked ? nil : 1.6, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: isWindow ? .infinity : (parked ? 0 : nil))
            .padding(.vertical, parked ? -4 : 0)
    }
}

// MARK: Popover panel + expanded window

private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the popover panel and the expanded window; only one of them is on screen at a time.
@MainActor
final class SurfaceController: NSObject, NSWindowDelegate {
    static let shared = SurfaceController()

    /// Supplied by the menu bar controller: the status item button the popover hangs from.
    var anchor: () -> NSStatusBarButton? = { nil }

    private var panel: PopoverPanel?
    private var window: NSWindow?
    private var suppressDismiss = 0
    private var lastDismiss = Date.distantPast

    var popoverVisible: Bool { panel?.isVisible == true }
    var windowVisible: Bool { window?.isVisible == true }

    // MARK: Entry points

    /// Status item click.
    func statusItemClicked() {
        // The click that dismisses the popover (focus loss) must not immediately reopen it.
        if Date().timeIntervalSince(lastDismiss) < 0.3 { return }
        toggle()
    }

    /// Hotkey: show, or hide the surface that is already frontmost.
    func toggle() {
        if windowVisible {
            if window?.isKeyWindow == true { closeWindow() } else { focusWindow() }
        } else if popoverVisible {
            closePopover()
        } else {
            openPopover()
        }
    }

    /// Open (never close): notification click, deep link, menu item.
    func open() {
        if windowVisible { focusWindow() } else if popoverVisible { focusPopover() } else { openPopover() }
    }

    func toggleExpanded() { windowVisible ? dock() : expand() }

    // MARK: Popover

    func openPopover() {
        let p = panel ?? makePanel()
        StageHost.shared.claim(.popover)
        p.setFrame(popoverFrame(), display: true)
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func closePopover() {
        guard popoverVisible else { return }
        lastDismiss = Date()
        panel?.orderOut(nil)
    }

    private func focusPopover() {
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> PopoverPanel {
        let app = AppModel.shared
        let host = NSHostingView(rootView: ContentView(monitor: app.monitor, quotaService: app.quota, layout: .popover))
        host.sizingOptions = []
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor), host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor), host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let p = PopoverPanel(contentRect: NSRect(origin: .zero, size: PopoverSize.current.contentSize(on: nil)),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        p.contentView = effect
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.title = "Hubbub"
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelResignedKey() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resizeIfNeeded() }
        }
        panel = p
        return p
    }

    private func popoverFrame() -> NSRect {
        let button = anchor()
        let screen = button?.window?.screen ?? NSScreen.main
        let vis = (screen ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = PopoverSize.current.contentSize(on: screen)
        var x = vis.maxX - size.width - 8
        var top = vis.maxY - 4
        if let bw = button?.window {
            let r = bw.frame
            x = r.midX - size.width / 2
            top = min(r.minY, vis.maxY) - 4
        }
        x = max(vis.minX + 8, min(x, vis.maxX - size.width - 8))
        let y = max(vis.minY + 8, top - size.height)
        return NSRect(x: x, y: y, width: size.width, height: min(size.height, top - y))
    }

    /// Applies a changed popover-size setting to a visible popover, keeping its top edge.
    private func resizeIfNeeded() {
        guard let p = panel, p.isVisible else { return }
        let size = PopoverSize.current.contentSize(on: p.screen)
        guard abs(p.frame.width - size.width) > 0.5 || abs(p.frame.height - size.height) > 0.5 else { return }
        var f = p.frame
        f.origin.y += f.height - size.height
        f.origin.x += (f.width - size.width) / 2
        f.size = size
        p.setFrame(f, display: true, animate: false)
    }

    private func panelResignedKey() {
        guard suppressDismiss == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel, p.isVisible, self.suppressDismiss == 0, NSApp.modalWindow == nil, p.attachedSheet == nil else { return }
            if let kw = NSApp.keyWindow {
                if kw === p || kw.parent === p || p.childWindows?.contains(kw) == true { return }
                // SwiftUI popovers owned by the panel take key briefly.
                if String(describing: type(of: kw)).contains("Popover") { return }
            }
            self.closePopover()
        }
    }

    /// Runs `body` (an open/save panel) without the popover treating the focus change as a click outside.
    func withoutDismissal<T>(_ body: () -> T) -> T {
        suppressDismiss += 1
        defer {
            suppressDismiss -= 1
            if suppressDismiss == 0, popoverVisible { panel?.makeKeyAndOrderFront(nil) }
        }
        return body()
    }

    // MARK: Expanded window

    func expand() {
        closePopover()
        let w = window ?? makeWindow()
        StageHost.shared.claim(.window)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func dock() {
        closeWindow()
        openPopover()
    }

    func closeWindow() { window?.close() }

    private func focusWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let app = AppModel.shared
        let host = NSHostingView(rootView: ContentView(monitor: app.monitor, quotaService: app.quota, layout: .window))
        host.sizingOptions = []
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Hubbub"
        w.contentView = host
        w.contentMinSize = NSSize(width: 640, height: 480)
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.fullScreenPrimary]
        w.tabbingMode = .disallowed
        let name = "HubbubExpandedWindow"
        let hasSaved = UserDefaults.standard.object(forKey: "NSWindow Frame \(name)") != nil
        w.setFrameAutosaveName(name)
        // A saved frame from a disconnected display would leave the window off-screen.
        if !hasSaved || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame) }) { w.center() }
        window = w
        return w
    }
}
