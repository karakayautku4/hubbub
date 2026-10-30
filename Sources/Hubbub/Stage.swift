import SceneKit
import SwiftUI
import AppKit

final class Feedback {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true }
    static func play(_ name: String) {
        guard enabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

@MainActor
final class Stage: ObservableObject {
    let scene = SCNScene()
    let world = World()
    let sign = RoomSign()
    let fun = FunLayer()
    let fx = SceneFX()
    private var _sessions: [SessionInfo] = []
    /// Equality-guarded: SwiftUI re-renders assign this constantly, only real changes touch the scene.
    var sessions: [SessionInfo] {
        get { _sessions }
        set {
            guard newValue != _sessions else { return }
            _sessions = newValue
            updateAccessibility()
        }
    }
    static weak var current: Stage?
    var theme: Theme = .defaultTheme
    var custom: CustomTheme? { didSet { CustomThemes.active = custom } }
    private var envCustom: String?
    var team: Team = .fallback
    private var envTeam: Team?
    var selectedSessionID: String?
    @Published var selected: Actor?
    @Published var hint: String = ""
    private(set) var selectedActorID: String?

    private let cameraNode = SCNNode()
    private let actorsRoot = SCNNode()
    let jobsRoot = SCNNode()
    let arenaExt = ArenaExtension()
    var arena = ArenaState()
    var lastArenaT: Double?
    var jobProps: [Int: SCNNode] = [:]
    var jobFades: [Int: (node: SCNNode, since: Double)] = [:]
    var jobBirth: [Int: Double] = [:]
    var zoomBySession: [String: CGFloat] = [:]
    /// Multiplier applied to name pills and bubbles so they stay readable when the camera is far away.
    var labelScale: CGFloat = 1
    /// User zoom (1 = auto-framing). Remembered per session until reset.
    @Published var zoomLevel: CGFloat = 1
    var isFitted: Bool { zoomLevel == 1 }
    private var envNode: SCNNode?
    private var envTheme: Theme?
    private var lights: [SCNNode] = []
    private let ambience = Ambience()
    var rigs: [String: Rig] = [:]
    private var simKey = ""
    private var timer: Timer?
    private var ticks = 0
    private var lastPublish = 0.0
    private var lastBubblePass = -1000.0
    private var dragging = false
    private var pressedActor: String?
    private var pressPoint = CGPoint.zero
    weak var view: SCNView?
    private var baseCamX: CGFloat = 0
    let cameraRig = CameraRig()
    private var hoveredActorID: String?
    private var petTimer: Timer?
    private var openWork: DispatchWorkItem?
    private var pressedWasSelected = false
    private var petted = false

    init() {
        scene.rootNode.addChildNode(arenaExt.root)
        scene.rootNode.addChildNode(jobsRoot)
        scene.rootNode.addChildNode(actorsRoot)
        scene.rootNode.addChildNode(fx.root)
        sign.node.position = SCNVector3(-8.6, 1.0, 11.2)
        sign.node.scale = SCNVector3(0.85, 0.85, 0.85)
        scene.rootNode.addChildNode(sign.node)
        scene.rootNode.addChildNode(fun.root)
        let cam = SCNCamera()
        cam.fieldOfView = 41
        cam.zNear = 1
        cam.zFar = 200
        cam.wantsHDR = true
        cam.bloomIntensity = 0.35
        cam.bloomThreshold = 1.0
        cam.bloomBlurRadius = 8
        // Auto-exposure re-brightens dark scenes (night looks like day) and drifts under the bloom; use a fixed per-theme exposure.
        cam.wantsExposureAdaptation = false
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 14.2, 22.8)
        cameraNode.look(at: SCNVector3(0, 0, 3.5))
        scene.rootNode.addChildNode(cameraNode)
    }

    var camera: SCNNode { cameraNode }

    /// True while the popover is on screen; background services throttle themselves when false.
    nonisolated(unsafe) static var popoverVisible = false
    static let visibilityChanged = Notification.Name("HubbubStageVisibilityChanged")
    private var fastMode: Bool?
    private var fps = 0
    private var observers: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?

    func start() {
        Stage.current = self
        guard timer == nil else { return }
        schedule(fast: false)
        updateAccessibility()
    }

    /// Re-arms the timers from window notifications instead of polling while hidden.
    func attach(window: NSWindow?) {
        guard window !== observedWindow else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        observedWindow = window
        guard let window else { return }
        let nc = NotificationCenter.default
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observers.append(nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateVisibility() }
            })
        }
        evaluateVisibility()
    }

    private var anyWorking: Bool { sessions.contains { $0.state == .working } }

    /// Interaction (zoom, drag, hover) raises the frame rate to 60 for a second, then eases back.
    private var interactiveUntil = 0.0
    func noteInteraction() { interactiveUntil = now + 1.0 }
    private static let noBoost = ProcessInfo.processInfo.environment["PERF_NOBOOST"] != nil
    private var targetFPS: Int { now < interactiveUntil && !Stage.noBoost ? 60 : (anyWorking ? 30 : 20) }

    private func schedule(fast: Bool) {
        timer?.invalidate()
        fastMode = fast
        fps = fast ? targetFPS : 0
        view?.preferredFramesPerSecond = fast ? fps : 30
        // Hidden: a 5 s heartbeat keeps the simulation and alert sounds alive without waking the CPU.
        let interval = fast ? 1.0 / Double(fps) : 5.0
        let tm = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFired() }
        }
        tm.tolerance = fast ? 0.005 : 2.5
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }

    /// Self-test hook: treat the window as visible even when no window server session reports occlusion.
    nonisolated(unsafe) static var forceVisible = false

    private var windowVisible: Bool {
        Stage.forceVisible || (view?.window?.isVisible ?? false) && (view?.window?.occlusionState.contains(.visible) ?? false)
    }

    private func evaluateVisibility() {
        let visible = windowVisible
        if visible != (fastMode ?? false) || (visible && fps != targetFPS) {
            let flipped = visible != Stage.popoverVisible
            Stage.popoverVisible = visible
            view?.isPlaying = visible
            view?.rendersContinuously = visible
            // Detaching the scene is the only reliable way to stop SceneKit's display link from drawing while hidden.
            view?.scene = visible ? scene : nil
            if visible { view?.pointOfView = cameraNode }
            schedule(fast: visible)
            if flipped { NotificationCenter.default.post(name: Stage.visibilityChanged, object: nil) }
        }
    }

    // MARK: Accessibility

    private var a11ySummary = ""

    /// One-line VoiceOver summary of the stage, e.g. "3 sessions: 1 working, 1 waiting for approval, 1 idle".
    static func summary(of list: [SessionInfo]) -> String {
        guard !list.isEmpty else { return "No agent sessions" }
        let working = list.filter { $0.state == .working }.count
        let approval = list.filter { $0.waitingApproval }.count
        let offline = list.filter { $0.state == .offline }.count
        let idle = list.count - working - offline
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if approval > 0 { parts.append("\(approval) waiting for approval") }
        if idle > 0 { parts.append("\(idle) idle") }
        if offline > 0 { parts.append("\(offline) offline") }
        return "\(list.count) session\(list.count == 1 ? "" : "s"): " + parts.joined(separator: ", ")
    }

    private func updateAccessibility() {
        guard view != nil else { return }
        let text = Stage.summary(of: _sessions)
        guard text != a11ySummary else { return }
        a11ySummary = text
        view?.setAccessibilityElement(true)
        view?.setAccessibilityRole(.image)
        view?.setAccessibilityLabel("Agent stage")
        view?.setAccessibilityValue(text)
    }

    func simulateFailure() {
        let key = selectedSessionID.flatMap { id in sessions.contains { $0.id == id } ? id : nil } ?? sessions.first?.id ?? "__empty"
        let sim = key == "__empty" ? (world.emptySim() ?? world.sim(for: key)) : world.sim(for: key)
        sim?.simulateFailure(t: Date().timeIntervalSinceReferenceDate)
    }

    private func timerFired() {
        ticks += 1
        evaluateVisibility()
        let now = Date().timeIntervalSinceReferenceDate
        if fastMode == true { tick(t: now, render: true) } else { tick(t: now, render: false) }
    }

    // MARK: Scene setup

    private func configure(for theme: Theme) {
        envNode?.removeFromParentNode()
        let env = Environments.build(theme)
        scene.rootNode.insertChildNode(env, at: 0)
        envNode = env
        arenaExt.build(theme: theme, env: env)
        jobsRoot.childNodes.forEach { $0.removeFromParentNode() }
        jobProps = [:]
        jobFades = [:]; jobBirth = [:]
        envTheme = theme
        envCustom = custom?.fingerprint
        envTeam = team

        var (bg, ambient, ambI, key, keyI, fill): (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) = switch theme {
        case .space: (0x04050f, 0x6f8fd8, 450, 0xdbe8ff, 1450, 0x3fa9f5)
        case .kitchen: (0x2a2420, 0xfff1dd, 340, 0xfff0d8, 700, 0xffb26b)
        case .prison: (0x9bc7ee, 0xcfe0f5, 320, 0xfff1d0, 780, 0xffffff)
        case .football: (0x0b1022, 0xb5c8ff, 380, 0xfff4e0, 1100, 0xffffff)
        case .farm: (0x9bc7ee, 0xd8e8ff, 340, 0xfff0c8, 820, 0xffffff)
        case .impostor: Stage.impostorLighting()
        case .wizard: Stage.wizardLighting()
        case .galactic: Stage.galacticLighting()
        case .fellowship: Stage.fellowshipLighting()
        }
        if let p = custom?.palette {
            bg = custom?.color(p.background) ?? bg
            ambient = custom?.color(p.ambient) ?? ambient
            key = custom?.color(p.keyLight) ?? key
            fill = custom?.color(p.fillLight) ?? fill
        }
        scene.background.contents = Gfx.color(bg)
        // Light nodes (and their shadow maps) persist across theme switches; only their parameters change.
        if lights.isEmpty {
            let amb = SCNNode(), sun = SCNNode(), accent = SCNNode()
            amb.light = SCNLight()
            amb.light?.type = .ambient
            let l = SCNLight()
            l.type = .directional
            l.castsShadow = true
            l.shadowMode = .deferred
            l.shadowColor = NSColor.black.withAlphaComponent(0.55)
            l.shadowRadius = 5
            l.shadowSampleCount = 6
            l.shadowMapSize = CGSize(width: 1024, height: 1024)
            l.automaticallyAdjustsShadowProjection = true
            sun.light = l
            sun.eulerAngles = SCNVector3(-0.95, 0.35, 0)
            accent.light = SCNLight()
            accent.light?.type = .omni
            accent.light?.attenuationEndDistance = 22
            accent.position = SCNVector3(0, 8, 6.5)
            for n in [amb, sun, accent] { scene.rootNode.addChildNode(n); lights.append(n) }
        }
        let (amb, sun, accent) = (lights[0], lights[1], lights[2])
        amb.light?.color = Gfx.color(ambient)
        amb.light?.intensity = ambI
        sun.light?.color = Gfx.color(key)
        sun.light?.intensity = keyI
        accent.light?.color = Gfx.color(fill)
        accent.light?.intensity = theme == .kitchen || theme == .prison ? 110 : 320
        if let cam = cameraNode.camera {
            let look = Stage.look(for: theme)
            cam.exposureOffset = look.exposure
            cam.bloomIntensity = look.bloom
            cam.bloomThreshold = look.threshold
        }
        scene.lightingEnvironment.contents = Gfx.image(64, 64) { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [Gfx.color(0xffffff).cgColor, Gfx.color(0x8a93a6).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 64), end: .zero, options: [])
        }
        scene.lightingEnvironment.intensity = 0.9
        ambience.attach(scene: scene, env: env, theme: theme, lights: lights, custom: custom != nil)
        clearActors()
    }

    /// Fixed exposure (EV offset) and bloom per theme; bright daylight sets sit lower so they do not blow out.
    static func look(for theme: Theme) -> (exposure: CGFloat, bloom: CGFloat, threshold: CGFloat) {
        switch theme {
        case .kitchen: (-0.6, 0.2, 1.1)
        case .prison: (-0.5, 0.25, 1.1)
        case .farm: (-0.5, 0.25, 1.1)
        default: (0, 0.35, 1.0)
        }
    }

    private func clearActors() {
        rigs.values.forEach { $0.root.removeFromParentNode() }
        rigs = [:]
        selectedActorID = nil
        selected = nil
    }

    // MARK: Simulation tick

    func tick(t: Double, render: Bool) {
        var needsReconfigure = envTheme != theme || envCustom != custom?.fingerprint || (theme == .football && envTeam != team)
        if needsReconfigure { configure(for: theme) }
        world.step(sessions: sessions, theme: theme, t: t)
        for sim in world.allSims {
            for e in sim.drainEvents() {
                handle(e)
                if render, sim === currentSim { cameraCut(for: e, sim: sim, t: t) }
            }
        }
        guard render else { fx.discard(world.allSims); return }
        ambience.update(t: t)

        let key = selectedSessionID.flatMap { id in sessions.contains { $0.id == id } ? id : nil } ?? sessions.first?.id ?? "__empty"
        if key != simKey {
            simKey = key
            clearActors()
            zoomLevel = zoomBySession[key] ?? 1
        }
        guard let sim = key == "__empty" ? world.emptySim() : world.sim(for: key) else { return }
        fx.tick(sim: sim, all: world.allSims, theme: theme, t: t)
        sign.update(theme: theme, custom: custom, age: key == "__empty" ? nil : sim.captain.ageSec, jersey: sim.captain.variant % 90 + 10)
        fun.tick(t: t, theme: theme, session: sessions.first { $0.id == key }, sim: sim, stage: self)

        updateArena(sim: sim, t: t)
        var alive = Set<String>()
        for a in sim.all {
            alive.insert(a.id)
            let rig = rigs[a.id] ?? makeRig(a)
            sync(rig, a, job: sim.job(of: a), t: t)
        }
        let followID = cameraRig.followID.flatMap { alive.contains($0) ? $0 : nil } ?? selectedActorID ?? "captain"
        cameraRig.update(cameraNode, t: t, follow: rigs[followID]?.root.position)
        layoutLabels(rigs: rigs.filter { alive.contains($0.key) }, t: t)
        if t - lastBubblePass >= 0.1 { lastBubblePass = t; hideOverlappingBubbles() }
        for (id, rig) in rigs where !alive.contains(id) {
            rig.root.removeFromParentNode()
            rigs[id] = nil
            if selectedActorID == id { selectedActorID = nil; selected = nil }
        }
        if let id = selectedActorID, t - lastPublish > 0.5 {
            lastPublish = t
            selected = sim.all.first { $0.id == id }
        }
    }

    private var hoverPoint: CGPoint?
    private var projSize: CGSize { view?.bounds.size ?? CGSize(width: 636, height: 358) }

    /// Pinhole projection matching the stage camera (vertical FOV); returns screen point (y up) and pixels per world unit.
    private func project(_ p: SCNVector3) -> (pt: CGPoint, scale: CGFloat)? {
        let size = projSize
        let inv = simd_inverse(cameraNode.simdWorldTransform)
        let c = inv * simd_float4(Float(p.x), Float(p.y), Float(p.z), 1)
        guard c.z < -0.1 else { return nil }
        let fy = CGFloat(1 / tan((cameraNode.camera?.fieldOfView ?? 41) * .pi / 360))
        let k = fy * size.height / 2 / CGFloat(-c.z)
        return (CGPoint(x: size.width / 2 + CGFloat(c.x) * k, y: size.height / 2 + CGFloat(c.y) * k), k)
    }

    /// Name pills: full (with model tag) for selected/hovered/captain, compact for the rest; overlapping pills are nudged upward in screen space.
    private func layoutLabels(rigs map: [String: Rig], t: Double) {
        let list = Array(map.values)
        let ids = Dictionary(uniqueKeysWithValues: map.map { (ObjectIdentifier($0.value), $0.key) })
        struct Item { var rig: Rig; var rect: CGRect; var scale: CGFloat; var priority: Bool; var key: String; var shift: CGFloat }
        // Screen pixels per world unit of upward label travel (less than the depth scale because the camera looks down).
        var upScale: CGFloat = 0
        var hovered: Rig?
        if let hp = hoverPoint {
            var best: CGFloat = 50
            for r in list where !r.root.isHidden {
                guard let q = project(SCNVector3(r.root.position.x, r.root.position.y + 1.8, r.root.position.z)) else { continue }
                let d = hypot(q.pt.x - hp.x, q.pt.y - hp.y)
                if d < best { best = d; hovered = r }
            }
        }
        hoveredActorID = hovered.flatMap { h in map.first { $0.value === h }?.key }
        var items: [Item] = []
        for r in list where !r.root.isHidden {
            guard let n = r.nameNode, let plane = n.geometry as? SCNPlane else { continue }
            let pri = r.isCaptain || map[selectedActorID ?? ""] === r || r === hovered
            r.setPlateChip(pri)
            let base = SCNVector3(r.root.position.x, r.root.position.y + r.labelY * 1.3, r.root.position.z)
            guard let q = project(base) else { continue }
            let w = plane.width * 1.3 * q.scale * labelScale, h = plane.height * 1.3 * q.scale * labelScale
            if let up = project(SCNVector3(base.x, base.y + 1, base.z)) { upScale = max(up.pt.y - q.pt.y, 1) }
            // Keep the pill and its bubble inside the visible width (screen space, so it holds at any zoom).
            let half = max(w, ((r.bubbleNode?.geometry as? SCNPlane)?.width ?? 0) * 1.3 * q.scale * labelScale) / 2
            var dx: CGFloat = 0
            if q.pt.x - half < 4 { dx = 4 - (q.pt.x - half) } else if q.pt.x + half > projSize.width - 4 { dx = projSize.width - 4 - (q.pt.x + half) }
            items.append(Item(rig: r, rect: CGRect(x: q.pt.x + dx - w / 2, y: q.pt.y - h / 2, width: w, height: h), scale: upScale, priority: pri, key: String(format: "%06.2f|%07.2f|", 100 - r.root.position.z, r.root.position.x + 200) + (ids[ObjectIdentifier(r)] ?? ""), shift: dx / q.scale))
        }
        // Front (lowest on screen) first so back-row pills are the ones that stack upward.
        items.sort { a, b in a.priority != b.priority ? a.priority : a.key < b.key }
        var kept: [CGRect] = []
        for it in items {
            var rect = it.rect
            for _ in 0..<40 {
                guard let hit = kept.filter({ $0.insetBy(dx: -2, dy: -1).intersects(rect) }).max(by: { $0.maxY < $1.maxY }) else { break }
                rect.origin.y = hit.maxY + 2
            }
            kept.append(rect)
            let target = rect.minY - it.rect.minY
            let r = it.rig
            r.mv.lift += (target - r.mv.lift) * (abs(target - r.mv.lift) < 0.5 ? 1 : 0.35)
            let local = r.mv.lift / it.scale / 1.3
            let ph = (r.nameNode?.geometry as? SCNPlane)?.height ?? 0.6
            r.nameNode?.position.y = r.labelY + local + (labelScale - 1) * ph / 2
            r.applyLabelScale(labelScale)
            r.shiftLabels(world: it.shift / 1.3, yaw: r.yaw)
            if let b = r.bubbleNode {
                let bh = ((b.geometry as? SCNPlane)?.height ?? 1) * labelScale
                b.position.y = r.labelY + 0.2 + bh / 2 + local + (labelScale - 1) * ph
            }
        }
    }

    /// Number of visible name-pill pairs whose on-screen rectangles still intersect (diagnostics for `--snapshot` with SNAP_DEBUG).
    func overlappingPillCount() -> Int {
        var rects: [CGRect] = []
        for rig in rigs.values where !rig.root.isHidden {
            guard let n = rig.nameNode, let pl = n.geometry as? SCNPlane, let q = project(n.worldPosition) else { continue }
            let w = pl.width * 1.3 * q.scale * labelScale, h = pl.height * 1.3 * q.scale * labelScale
            rects.append(CGRect(x: q.pt.x - w / 2, y: q.pt.y - h / 2, width: w, height: h))
        }
        var c = 0
        for i in rects.indices { for j in rects.indices where j > i && rects[i].insetBy(dx: 1, dy: 1).intersects(rects[j]) { c += 1 } }
        return c
    }

    /// Keeps speech bubbles readable: when two overlap on screen, only the higher-priority one stays visible.
    private func hideOverlappingBubbles() {
        // Name pills of every rig act as obstacles so a bubble never covers another character's name.
        var plates: [(Rig, CGRect)] = []
        for rig in rigs.values where !rig.root.isHidden {
            guard let n = rig.nameNode, let pl = n.geometry as? SCNPlane, let q = project(n.worldPosition) else { continue }
            let w = pl.width * 1.3 * q.scale * labelScale, h = pl.height * 1.3 * q.scale * labelScale
            plates.append((rig, CGRect(x: q.pt.x - w / 2, y: q.pt.y - h / 2, width: w, height: h)))
        }
        var kept: [CGRect] = []
        let ordered = rigs.values.filter { $0.bubbleNode != nil && !$0.root.isHidden }
            .sorted { ($0.isCaptain ? 0 : 1, $0.bubbleText ?? "") < ($1.isCaptain ? 0 : 1, $1.bubbleText ?? "") }
        for rig in ordered {
            guard let n = rig.bubbleNode, let pl = n.geometry as? SCNPlane, let q = project(n.worldPosition) else { continue }
            n.isHidden = false
            let w = pl.width * 1.3 * q.scale * labelScale, h = pl.height * 1.3 * q.scale * labelScale
            let r = CGRect(x: q.pt.x - w / 2, y: q.pt.y - h / 2, width: w, height: h)
            let blocked = plates.contains { $0.0 !== rig && $0.1.intersects(r.insetBy(dx: 3, dy: 3)) }
            if blocked || kept.contains(where: { $0.intersects(r) }) { n.isHidden = true } else { kept.append(r) }
        }
    }

    private func makeRig(_ a: Actor) -> Rig {
        let r = Rig(actor: a, theme: theme)
        actorsRoot.addChildNode(r.root)
        rigs[a.id] = r
        return r
    }

    private func sync(_ rig: Rig, _ a: Actor, job: Job?, t: Double) {
        let wx = Environments.wx(a.pos.x), wz = Environments.wz(a.pos.y)
        rig.root.position = SCNVector3(wx, 0, wz)
        rig.root.isHidden = t < a.spawnAt
        let lift: CGFloat = a.id == hoveredActorID && !a.dragged ? 1.07 : 1
        rig.root.scale = SCNVector3(1.3 * lift, 1.3 * lift, 1.3 * lift)
        let standing = a.phase == .working && !a.moving && a.mood == .none && (!a.isCaptain || a.atJob)
        let jobAnim = standing && a.atJob ? job?.animation : nil
        let target: CGFloat = standing ? .pi * 0.5 * (wx > 0 ? -1 : 1) : a.heading
        var diff = (target - rig.yaw).truncatingRemainder(dividingBy: .pi * 2)
        if diff > .pi { diff -= .pi * 2 } else if diff < -.pi { diff += .pi * 2 }
        rig.yaw += diff * 0.2
        rig.root.eulerAngles = SCNVector3(0, rig.yaw, 0)
        rig.setCarry(a.carry)
        rig.setSick(a.mood == .sick)
        let motion = Stage.motion(theme, a.kind)
        rig.pose(actor: a, theme: theme, t: t, moving: a.moving && !a.dragged, motion: a.isCaptain ? .scan : motion, stationary: standing, job: jobAnim)
        let stationEmoji = theme.stations[a.kind % theme.stations.count].emoji
        let emoji = a.isCaptain ? "⭐" : (a.phase == .working ? (a.onJob ? job?.emoji ?? stationEmoji : stationEmoji) : "")
        rig.setMetrics(a, theme: theme, emoji: emoji, t: t)
        let sleepy = a.mood == .sleep || (rig.isSheep && a.ctx > 0.9)
        rig.setBubble(a.say ?? (a.approval ? "✋ needs approval" : (sleepy ? "Zzz…" : nil)))
        rig.ring.isHidden = a.id != selectedActorID
        if !rig.ring.isHidden { rig.ring.eulerAngles = SCNVector3(0, CGFloat(t) * 1.5, 0) }
    }

    static func motion(_ theme: Theme, _ kind: Int) -> Motion {
        switch theme {
        case .space: [.scan, .hammer, .type, .type][kind % 4]
        case .kitchen: [.bend, .hammer, .stir, .stir][kind % 4]
        case .prison: [.bend, .paint, .sweep, .bend][kind % 4]
        case .football: [.kick, .kick, .bend, .scan][kind % 4]
        case .farm: [.bend, .bend, .bend, .bend][kind % 4]
        case .impostor: impostorMotion(kind)
        case .wizard: wizardMotion(kind)
        case .galactic: galacticMotion(kind)
        case .fellowship: fellowshipMotion(kind)
        }
    }

    private func handle(_ e: SimEvent) {
        switch e {
        case .failure:
            SoundCenter.shared.play(.failure)
        case .finished: SoundCenter.shared.play(.success); fun.guests.noteFinished()
        case .spawned: SoundCenter.shared.play(.spawn)
        case .tired: break
        }
    }

    // MARK: Pointer interaction

    private enum Hit { case actor(String), prop(String, SCNNode), floor(CGPoint), none }

    private func hit(_ p: CGPoint, in v: SCNView) -> Hit {
        let results = v.hitTest(p, options: [.searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for r in results {
            var n: SCNNode? = r.node
            while let c = n {
                if let name = c.name {
                    if name.hasPrefix("actor:") { return .actor(String(name.dropFirst(6))) }
                    if name.hasPrefix("prop:") { return .prop(String(name.dropFirst(5)), c) }
                    if name == "floor" {
                        let w = r.worldCoordinates
                        return .floor(CGPoint(x: w.x * 10 + 160, y: w.z * 10 + 96))
                    }
                }
                n = c.parent
            }
        }
        return .none
    }

    var currentSim: RoomSim? { simKey == "__empty" ? world.emptySim() : world.sim(for: simKey) }
    var now: Double { Date().timeIntervalSinceReferenceDate }

    func pointerDown(_ p: CGPoint, in v: SCNView, clicks: Int = 1) {
        openWork?.cancel()
        petTimer?.invalidate()
        noteInteraction()
        cameraRig.poke(t: now)
        pressPoint = p
        dragging = false
        petted = false
        pressedActor = nil
        pressedWasSelected = false
        switch hit(p, in: v) {
        case .actor(let id):
            pressedActor = id
            pressedWasSelected = selectedActorID == id && clicks == 1
            select(id)
            if clicks >= 2 {
                toggleFollow(id)
            } else {
                if CameraMode.current == .follow { cameraRig.followID = id; cameraRig.focus(true) }
                petTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let id = self.pressedActor, !self.dragging else { return }
                        self.petted = true
                        self.petActor(id)
                    }
                }
            }
        case .prop("guest", _): fun.guests.poke(t: now, stage: self)
        case .prop(let name, let node): react(prop: name, node)
        case .floor(let pt):
            select(nil)
            cameraRig.followID = nil
            cameraRig.focus(false)
            currentSim?.send(captainTo: pt, t: now)
            Feedback.play("Pop")
        case .none: select(nil)
        }
    }

    private func toggleFollow(_ id: String) {
        if CameraMode.current == .follow, cameraRig.followID == id {
            CameraMode.current = .free
            cameraRig.followID = nil
            cameraRig.focus(false)
        } else {
            CameraMode.current = .follow
            cameraRig.followID = id
            cameraRig.focus(true)
        }
    }

    func pointerDragged(_ p: CGPoint, in v: SCNView) {
        noteInteraction()
        guard let id = pressedActor, let sim = currentSim else { return }
        if !dragging {
            guard hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 5 else { return }
            dragging = true
            petTimer?.invalidate()
            sim.beginDrag(id, t: now)
            Feedback.play("Pop")
        }
        if case .floor(let pt) = hit(p, in: v) { sim.drag(id, to: pt) }
    }

    func pointerUp() {
        petTimer?.invalidate()
        if dragging, let id = pressedActor, let sim = currentSim {
            sim.drop(id, t: now)
            if sim.goToNearestStation(id, t: now) { Feedback.play("Pop") } else { Feedback.play("Tink") }
        } else if pressedActor != nil, !petted, pressedWasSelected, simKey != "__empty" {
            let sid = simKey
            let w = DispatchWorkItem { Task { @MainActor in AppRouter.shared.open(sessionID: sid) } }
            openWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
        }
        dragging = false
        pressedActor = nil
    }

    func hover(_ p: CGPoint, in v: SCNView) {
        hoverPoint = p
        noteInteraction()
        cameraRig.hoverNX = (p.x / max(v.bounds.width, 1) - 0.5) * 2
        cameraRig.poke(t: now)
    }

    func hoverEnded() { hoverPoint = nil; cameraRig.hoverNX = 0 }

    private func cameraCut(for e: SimEvent, sim: RoomSim, t: Double) {
        let target: Actor?
        switch e {
        case .failure: target = sim.victim() ?? sim.captain
        case .spawned: target = sim.subs.last
        case .finished: target = sim.captain
        case .tired: target = nil
        }
        guard let a = target else { return }
        cameraRig.cut(to: SCNVector3(Environments.wx(a.pos.x), 0, Environments.wz(a.pos.y)), t: t)
    }

    func select(_ id: String?) {
        selectedActorID = id
        selected = id.flatMap { id in currentSim?.all.first { $0.id == id } }
    }


    private func react(prop: String, _ node: SCNNode) {
        guard let sim = currentSim else { return }
        node.removeAllActions()
        puff(prop: prop, at: node)
        node.runAction(.sequence([.scale(to: 1.1, duration: 0.1), .scale(to: 0.96, duration: 0.1), .scale(to: 1, duration: 0.12)]))
        let t = now
        func line(_ text: String, _ sound: String) { sim.say("captain", text, t: t); Feedback.play(sound) }
        switch prop {
        case "radar": line("Sweeping the network…", "Ping")
        case "rack": line("All servers green.", "Tink")
        case "wallmap": line("Live threat map.", "Ping")
        case "console": line("Systems nominal.", "Ping")
        case "planet": line("Beautiful view!", "Pop")
        case "reactor": line("Reactor at 100%!", "Funk"); sim.cheerAll(t: t, line: "Power up! ⚡️")
        case "airlock": line("Airlock cycling…", "Submarine")
        case "bell": sim.cheerAll(t: t, line: theme.celebrateLine); Feedback.play("Glass")
        case "stove": sim.panicAll(t: t, line: "Hot hot hot! 🔥"); Feedback.play("Basso")
        case "pass": line("Service, please!", "Tink")
        case "alarm":
            sim.panicAll(t: t, line: "Lockdown! 🚨")
            Feedback.play("Funk")
        case "gate": line("Gate's open for good behavior.", "Pop")
        case "desk": line(theme.deskLine, "Tink")
        case "coffee": sim.send(captainTo: theme.coffee, t: t); line(theme == .football ? "Water break 💧" : (theme == .farm ? "Fresh water 💧" : theme.coffeeLine), "Pop")
        case "goal": sim.cheerAll(t: t, line: "GOAL! ⚽️🎉"); Feedback.play("Hero")
        case "ball": line("Keepy-uppy! ⚽️", "Pop")
        case "var": line("Checking VAR… 📺", "Ping")
        case "barn": sim.cheerAll(t: t, line: "Baa! 🐑"); Feedback.play("Pop")
        case "windmill":
            node.childNode(withName: "hub", recursively: false)?.runAction(.rotateBy(x: 0, y: 0, z: -.pi * 8, duration: 2))
            line("Nice breeze!", "Pop")
        case "scarecrow": line("Shoo, crows! 🐦", "Tink")
        default:
            if prop.hasPrefix("cell") { line("Back to work, inmate!", "Tink") }
        }
    }

    // MARK: Offscreen snapshot

    private var snapshotRenderer: SCNRenderer?

    func snapshot(width: Int, height: Int) -> NSImage? {
        // One renderer per stage: a fresh renderer re-uploads every texture and pipeline state on each call.
        if snapshotRenderer == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            let made = SCNRenderer(device: device, options: nil)
            made.scene = scene
            made.pointOfView = cameraNode
            snapshotRenderer = made
        }
        guard let r = snapshotRenderer else { return nil }
        return r.snapshot(atTime: 0, with: CGSize(width: width, height: height), antialiasingMode: .multisampling4X)
    }
}

final class StageSCNView: SCNView {
    weak var stage: Stage?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stage?.attach(window: window)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        stage?.pointerDown(convert(event.locationInWindow, from: nil), in: self, clicks: event.clickCount)
    }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers?.lowercased() == "c", event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            stage?.cycleCameraMode()
        } else { super.keyDown(with: event) }
    }
    // Scroll and pinch zoom the stage; the event is consumed so the enclosing popover never scrolls with it.
    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.5 : event.scrollingDeltaY * 3
        if dy != 0 { stage?.scrollZoom(delta: dy) }
    }
    override func magnify(with event: NSEvent) { stage?.pinchZoom(magnification: event.magnification) }
    override func mouseDragged(with event: NSEvent) { stage?.pointerDragged(convert(event.locationInWindow, from: nil), in: self) }
    override func mouseUp(with event: NSEvent) { stage?.pointerUp() }
    override func mouseExited(with event: NSEvent) { stage?.hoverEnded() }
    override func mouseMoved(with event: NSEvent) { stage?.hover(convert(event.locationInWindow, from: nil), in: self) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
}

struct StageView: NSViewRepresentable {
    let stage: Stage
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> StageSCNView {
        let v = StageSCNView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        v.stage = stage
        v.scene = stage.scene
        v.pointOfView = stage.camera
        // The 2x backing store already halves edge aliasing; 4x MSAA on top is pure GPU/bandwidth cost.
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = false
        v.backgroundColor = .black
        v.wantsLayer = true
        v.layer?.cornerRadius = 8
        v.layer?.masksToBounds = true
        stage.view = v
        stage.start()
        return v
    }

    func updateNSView(_ nsView: StageSCNView, context: Context) {}
}

