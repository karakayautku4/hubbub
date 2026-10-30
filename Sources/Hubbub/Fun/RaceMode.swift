import SceneKit
import AppKit

/// Little themed races in the foreground, driven by real agent activity. Everything here is a few dozen primitive nodes
/// that are built per round and removed afterwards; ticking is only ever called from the render path.
@MainActor
final class RaceOverlay {
    static let enabledKey = "raceMode"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    let root = SCNNode()
    private enum Phase { case off, waiting(Double), countdown(Double), running, podium(Double) }
    private var phase: Phase = .off
    private var theme: Theme?
    private var state: RaceState?
    private var rates: [String: RaceRate] = [:]
    private var runners: [String: Runner] = [:]
    private var pacerSpeed = 0.05
    private var lastT: Double?
    private var endAt: Double?
    private var announcer: SCNNode?
    private var announceUntil = 0.0
    private var obstacleXs: [Double] = []
    private var counted = 0
    private var track: SCNNode?
    private let debug = ProcessInfo.processInfo.environment["HUBBUB_FUN"] ?? ""
    private var speedScale: Double { debug.contains("racefast") ? 6 : 1 }

    // Geometry (world units): a shallow lane strip in the foreground.
    private let length = 10.4, laneW = 0.4, cx = -0.8, z0 = 11.15
    private var startX: Double { cx - length / 2 }
    private var finishX: Double { cx + length / 2 }

    init() { root.name = "race" }

    private struct Runner {
        let root: SCNNode, inner: SCNNode
        let legs: [(node: SCNNode, sign: Double)]
        let name: String
    }

    var isActive: Bool { if case .off = phase { false } else { true } }

    func clear() {
        root.childNodes.forEach { $0.removeFromParentNode() }
        runners = [:]; state = nil; rates = [:]; endAt = nil; announcer = nil; track = nil
        phase = .off
        lastT = nil
    }

    // MARK: Frame

    func tick(t: Double, theme: Theme, session: SessionInfo?, sim: RoomSim, stage: Stage) {
        guard Self.enabled || debug.contains("race"), session != nil else { if isActive { clear() }; return }
        if self.theme != theme { clear(); self.theme = theme }
        let dt = min(max(t - (lastT ?? t), 0), 0.1)
        lastT = t
        if announcer != nil, t > announceUntil { announcer?.removeFromParentNode(); announcer = nil }
        switch phase {
        case .off:
            phase = .waiting(t + (debug.contains("race") ? 0.4 : 4))
        case .waiting(let until):
            if t >= until, let session { begin(t: t, theme: theme, session: session, sim: sim) }
        case .countdown(let until):
            positionRunners(t: t, theme: theme)
            if t >= until { phase = .running; announce(RaceText.start(theme), t: t, hold: 3.5) }
        case .running:
            run(t: t, dt: dt, theme: theme, session: session, stage: stage)
        case .podium(let until):
            podiumBob(t: t)
            if t >= until {
                clear()
                phase = .waiting(t + 14)
            }
        }
    }

    // MARK: Round lifecycle

    private func begin(t: Double, theme: Theme, session: SessionInfo, sim: RoomSim) {
        var list: [RaceRacer] = [RaceRacer(id: "captain", name: Self.short(sim.captain.name.isEmpty ? theme.captainRole : sim.captain.name))]
        for s in session.subagents.prefix(RaceMath.maxRacers - 1) { list.append(RaceRacer(id: s.id, name: Self.short(s.displayName.isEmpty ? s.name : s.displayName))) }
        if list.count < 2 { list.append(RaceRacer(id: "pacer", name: "Pacer")) }
        state = RaceState(list)
        rates = [:]
        endAt = nil
        counted = list.count
        buildTrack(theme: theme, racers: list)
        phase = .countdown(t + (debug.contains("race") ? 0.8 : 3))
        announce(RaceText.title(theme) + "!", t: t, hold: 3)
    }

    private func run(t: Double, dt: Double, theme: Theme, session: SessionInfo?, stage: Stage) {
        guard var st = state else { return }
        for i in st.racers.indices {
            let id = st.racers[i].id
            if id == "pacer" { st.racers[i].speed = pacerSpeed * speedScale; continue }
            var calls = 0, tokens = 0, failures = 0, busy = false
            if id == "captain", let s = session {
                (calls, tokens, failures, busy) = (s.toolCalls, s.outputTokens, s.failures, s.state == .working)
            } else if let sa = session?.subagents.first(where: { $0.id == id }) {
                (calls, tokens, failures, busy) = (sa.toolCalls, sa.contextTokens, sa.failures, sa.busy)
            }
            var r = rates[id] ?? RaceRate()
            let failed = r.feed(calls: calls, tokens: tokens, failures: failures, t: t)
            rates[id] = r
            st.racers[i].speed = RaceMath.speed(callsPerMin: r.callsPerMin, tokensPerSec: r.tokensPerSec, busy: busy) * speedScale * RaceMath.jitter(id)
            if failed, !st.isStumbling(i) {
                st.stumble(id)
                announce(RaceText.stumble(theme, name: st.racers[i].name, roll: Double(st.racers[i].stumbles * 7 % 10) / 10), t: t, hold: 3)
                if let n = runners[id]?.root { stage.floatEmoji("💫", at: SCNVector3(n.worldPosition.x, 1.0, n.worldPosition.z), size: 30, rise: 0.8) }
            }
        }
        let wasOver = st.isOver
        st.advance(dt)
        state = st
        if st.isOver, !wasOver, let w = st.winner, let name = st.racers.first(where: { $0.id == w })?.name {
            endAt = st.clock + 1.6
            announce(RaceText.win(theme, name: name, roll: Double(name.count % 2)), t: t, hold: 6)
            SoundCenter.shared.play(.success)
        }
        positionRunners(t: t, theme: theme)
        if let e = endAt, st.clock >= e { startPodium(t: t) }
    }

    private func startPodium(t: Double) {
        guard let st = state else { return }
        let podiumX = finishX + 1.0, zc = z0 + Double(counted) * laneW / 2
        let top = Array(st.ranking.prefix(3))
        let heights = [0.55, 0.38, 0.26], zs = [0.0, -0.62, 0.62]
        let ped = root.group("podium", podiumX, 0, zc)
        let m = Gfx.mat(0xe9e2cf, r: 0.7), gold = Gfx.mat(0xf2c14e, r: 0.35, m: 0.6)
        for (i, r) in top.enumerated() {
            ped.box(0.55, heights[i], 0.55, i == 0 ? gold : m, 0, heights[i] / 2, zs[i], round: 0.03)
            if let rn = runners[r.id] {
                rn.root.position = SCNVector3(podiumX, heights[i] + 0.02, zc + zs[i])
                rn.root.eulerAngles = SCNVector3(0, -CGFloat.pi / 2, 0)
                rn.inner.eulerAngles = SCNVector3Zero
                rn.inner.position = SCNVector3Zero
                rn.legs.forEach { $0.node.eulerAngles = SCNVector3Zero }
            }
        }
        // One label: separate "1st" and trophy pills were stacked closer than their height and covered each other.
        let star = Gfx.billboard(Gfx.label("🏆 1st", size: 20), unitsPerPoint: 0.014)
        star.position = SCNVector3(0, heights[0] + 1.85, 0)
        ped.addChildNode(star)
        phase = .podium(t + 7)
    }

    private func podiumBob(t: Double) {
        guard let st = state, let w = st.winner, let rn = runners[w] else { return }
        rn.inner.position = SCNVector3(0, abs(sin(t * 6)) * 0.18, 0)
    }

    // MARK: Positioning

    private func positionRunners(t: Double, theme: Theme) {
        guard let st = state else { return }
        let running: Bool = { if case .running = phase { true } else { false } }()
        for (i, r) in st.racers.enumerated() {
            guard let rn = runners[r.id] else { continue }
            let x = startX + 0.2 + r.progress * (length - 0.5)
            let z = z0 + (Double(i) + 0.5) * laneW
            var hop = 0.0
            let stumbling = st.isStumbling(i)
            for ox in obstacleXs where abs(x - ox) < 0.42 && !stumbling && running {
                hop = max(hop, 0.3 * cos((x - ox) / 0.42 * .pi / 2))
            }
            rn.root.position = SCNVector3(x, 0.03, z)
            var tilt = 0.0
            if stumbling {
                let u = 1 - (r.stumbleUntil - st.clock) / RaceMath.stumbleSeconds
                tilt = -0.95 * sin(.pi * max(0, min(1, u)))
            }
            rn.inner.eulerAngles = SCNVector3(0, 0, tilt)
            rn.inner.position = SCNVector3(0, hop, 0)
            let moving = running && !stumbling && r.finishedAt == nil
            let rate = 9 + 40 * r.speed
            for (leg, sign) in rn.legs { leg.eulerAngles = SCNVector3(0, 0, moving ? sin(t * rate) * sign * 0.8 : 0) }
        }
    }

    // MARK: Scene building

    private func announce(_ text: String, t: Double, hold: Double) {
        announcer?.removeFromParentNode()
        let n = Gfx.billboard(FunGfx.bubble(text, size: 19, maxWidth: 330), unitsPerPoint: 0.021)
        let zc = z0 + Double(counted) * laneW / 2
        n.position = SCNVector3(cx, 2.3, zc)
        root.addChildNode(n)
        announcer = n
        announceUntil = t + hold
    }

    private func buildTrack(theme: Theme, racers: [RaceRacer]) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        runners = [:]
        let motif = Self.motif(theme)
        let lanes = racers.count
        let depth = Double(lanes) * laneW
        let g = root.group("track", 0, 0, 0)
        track = g
        let zc = z0 + depth / 2
        g.box(length + 1.8, 0.06, depth + 0.3, Gfx.mat(motif.track, r: 0.9), cx, 0.0, zc, round: 0.02)
        let lineM = Gfx.mat(motif.line, r: 0.8, e: motif.glow ? motif.line : nil, eIntensity: 0.6)
        for i in 0...lanes { g.box(length + 0.6, 0.012, 0.02, lineM, cx, 0.034, z0 + Double(i) * laneW) }
        g.box(0.05, 0.012, depth, lineM, startX, 0.034, zc)
        let checker = Gfx.image(32, 64) { c in
            for y in 0..<8 { for x in 0..<4 {
                c.setFillColor((x + y) % 2 == 0 ? Gfx.color(0xffffff).cgColor : Gfx.color(0x20232b).cgColor)
                c.fill(CGRect(x: x * 8, y: y * 8, width: 8, height: 8))
            } }
        }
        let fin = SCNBox(width: 0.22, height: 0.012, length: depth, chamferRadius: 0)
        g.add(fin, Gfx.texMat(checker), at: SCNVector3(finishX, 0.036, zc), shadow: false)
        for dz in [-1.0, 1.0] { g.cyl(0.04, 0.9, Gfx.mat(motif.line, r: 0.6), finishX, 0.45, zc + dz * (depth / 2 + 0.1)) }
        let banner = Gfx.billboard(Gfx.label(RaceText.title(theme), size: 18), unitsPerPoint: 0.013)
        banner.position = SCNVector3(finishX, 1.05, zc)
        g.addChildNode(banner)
        obstacleXs = RaceMath.obstacleSpots.map { startX + 0.2 + $0 * (length - 0.5) }
        for i in 0..<lanes {
            for ox in obstacleXs { g.addChildNode(Self.obstacle(motif.obstacle, at: SCNVector3(ox + 0.3, 0.03, z0 + (Double(i) + 0.5) * laneW))) }
            let tag = Gfx.billboard(Gfx.label(racers[i].name, size: 15), unitsPerPoint: 0.011)
            tag.position = SCNVector3(startX - 0.95, 0.15, z0 + (Double(i) + 0.5) * laneW)
            g.addChildNode(tag)
            let rn = Self.makeRunner(motif.runner, color: Self.palette[(i + racers[i].id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.palette.count], name: racers[i].name)
            root.addChildNode(rn.root)
            runners[racers[i].id] = rn
        }
    }

    static let palette: [UInt32] = [0xe4572e, 0x29b6f6, 0xffc857, 0x7bd389, 0xc77dff, 0xff8fa3]

    static func short(_ s: String) -> String { s.count > 11 ? String(s.prefix(10)) + "…" : s }

    // MARK: Motifs

    enum RunnerStyle { case human, sheep, bean, robot, wizard, chef, hooded }
    enum ObstacleStyle { case crater, pin, hurdle, cone, fence, vent, books, gate, cairn }
    struct Motif { let runner: RunnerStyle; let obstacle: ObstacleStyle; let track: UInt32; let line: UInt32; var glow = false }

    static func motif(_ theme: Theme) -> Motif {
        if let m = ThemeExtensions.active?.raceMotif(theme) { return m }
        return switch theme {
        case .kitchen: Motif(runner: .chef, obstacle: .pin, track: 0x9aa3ad, line: 0xffffff)
        case .prison: Motif(runner: .human, obstacle: .hurdle, track: 0x8a7f6a, line: 0xf5f0e0)
        case .football: Motif(runner: .human, obstacle: .cone, track: 0x2f8f46, line: 0xffffff)
        case .farm: Motif(runner: .sheep, obstacle: .fence, track: 0x7a9b4a, line: 0xf3e9c8)
        case .impostor: Motif(runner: .bean, obstacle: .vent, track: 0x4a5160, line: 0xffd23f)
        case .wizard: Motif(runner: .wizard, obstacle: .books, track: 0x4b3a6b, line: 0xd9b8ff, glow: true)
        case .galactic: Motif(runner: .robot, obstacle: .gate, track: 0x1a2438, line: 0x4cc9ff, glow: true)
        case .fellowship: Motif(runner: .hooded, obstacle: .cairn, track: 0x8a7650, line: 0xe9dfc0)
        default: Motif(runner: .robot, obstacle: .crater, track: 0x3a4466, line: 0x5ad1ff, glow: true)
        }
    }

    static func obstacle(_ s: ObstacleStyle, at p: SCNVector3) -> SCNNode {
        let n = SCNNode()
        n.position = p
        let wood = Gfx.mat(0xb07a3a, r: 0.8), white = Gfx.mat(0xf5f5f0, r: 0.7), dark = Gfx.mat(0x23262e, r: 0.9)
        switch s {
        case .crater:
            n.cyl(0.14, 0.03, dark, 0, 0.02, 0)
            n.cyl(0.18, 0.02, Gfx.mat(0x6f7896, r: 0.9), 0, 0.01, 0)
        case .pin:
            let c = n.cyl(0.05, 0.3, Gfx.mat(0xd9b27c, r: 0.6), 0, 0.06, 0)
            c.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        case .hurdle:
            n.box(0.04, 0.2, 0.04, white, 0, 0.1, -0.13); n.box(0.04, 0.2, 0.04, white, 0, 0.1, 0.13)
            n.box(0.04, 0.04, 0.3, Gfx.mat(0xe4572e, r: 0.6), 0, 0.2, 0)
        case .cone:
            n.add(SCNCone(topRadius: 0.02, bottomRadius: 0.1, height: 0.22), Gfx.mat(0xff7a1a, r: 0.6), at: SCNVector3(0, 0.11, 0))
        case .fence:
            n.box(0.04, 0.22, 0.04, wood, 0, 0.11, -0.13); n.box(0.04, 0.22, 0.04, wood, 0, 0.11, 0.13)
            n.box(0.03, 0.04, 0.32, wood, 0, 0.17, 0); n.box(0.03, 0.04, 0.32, wood, 0, 0.09, 0)
        case .vent:
            n.box(0.26, 0.04, 0.26, Gfx.mat(0x2b2f3a, r: 0.5, m: 0.5), 0, 0.02, 0)
            for i in -1...1 { n.box(0.2, 0.02, 0.03, dark, 0, 0.045, Double(i) * 0.07) }
        case .books:
            n.box(0.22, 0.06, 0.28, Gfx.mat(0x7a2f4f, r: 0.7), 0, 0.03, 0)
            n.box(0.2, 0.05, 0.24, Gfx.mat(0x2f5f7a, r: 0.7), 0.01, 0.085, 0)
            n.box(0.18, 0.05, 0.2, Gfx.mat(0xc9a24a, r: 0.7), -0.01, 0.135, 0)
        case .gate:
            let glowM = Gfx.mat(0x4cc9ff, r: 0.3, e: 0x4cc9ff, eIntensity: 1.4)
            n.box(0.04, 0.24, 0.04, glowM, 0, 0.12, -0.13); n.box(0.04, 0.24, 0.04, glowM, 0, 0.12, 0.13)
            n.box(0.01, 0.02, 0.26, glowM, 0, 0.24, 0)
        case .cairn:
            n.add(SCNSphere(radius: 0.12), Gfx.mat(0x8c8a84, r: 0.95), at: SCNVector3(0, 0.07, 0))
            n.add(SCNSphere(radius: 0.08), Gfx.mat(0x9d9b94, r: 0.95), at: SCNVector3(0, 0.2, 0))
        }
        return n
    }

    private static func makeRunner(_ style: RunnerStyle, color: UInt32, name: String) -> Runner {
        let root = SCNNode()
        root.scale = SCNVector3(0.62, 0.62, 0.62)
        let inner = root.group("inner", 0, 0, 0)
        var legs: [(SCNNode, Double)] = []
        let skin = Gfx.mat(0xf2c9a0, r: 0.7), dark = Gfx.mat(0x23262e, r: 0.8), body = Gfx.mat(color, r: 0.6)
        func eyes(_ y: CGFloat, _ x: CGFloat) {
            inner.ball(0.04, dark, x, y, 0.09); inner.ball(0.04, dark, x, y, -0.09)
        }
        func legPair(_ mat: SCNMaterial, y: CGFloat = 0.4, h: CGFloat = 0.4, w: CGFloat = 0.16) {
            for (i, z) in [CGFloat(0.11), -0.11].enumerated() {
                let pivot = inner.group("leg", 0, y, z)
                pivot.box(w, h, w, mat, 0, -h / 2, 0)
                legs.append((pivot, i == 0 ? 1 : -1))
            }
        }
        switch style {
        case .human, .chef, .hooded:
            legPair(Gfx.mat(0x2b3550, r: 0.8))
            inner.box(0.5, 0.55, 0.36, body, 0, 0.68, 0, round: 0.05)
            inner.ball(0.24, skin, 0, 1.2, 0)
            eyes(1.24, 0.21)
            if style == .chef {
                inner.cyl(0.2, 0.28, Gfx.mat(0xffffff, r: 0.9), 0, 1.5, 0)
                inner.ball(0.22, Gfx.mat(0xffffff, r: 0.9), 0, 1.66, 0)
            } else if style == .hooded {
                let hood = inner.add(SCNCone(topRadius: 0.02, bottomRadius: 0.3, height: 0.5), Gfx.mat(0x4d6b3a, r: 0.9), at: SCNVector3(-0.04, 1.5, 0))
                hood.eulerAngles = SCNVector3(0, 0, 0.2)
            } else {
                inner.box(0.1, 0.06, 0.36, Gfx.mat(0xe4572e, r: 0.6), 0.26, 1.34, 0)
            }
        case .sheep:
            for (i, p) in [(0.2, 0.14), (-0.2, -0.14), (0.2, -0.14), (-0.2, 0.14)].enumerated() {
                let pivot = inner.group("leg", p.0, 0.34, p.1)
                pivot.cyl(0.05, 0.34, dark, 0, -0.17, 0)
                legs.append((pivot, i < 2 ? 1 : -1))
            }
            let wool = inner.ball(0.4, Gfx.mat(0xf7f3ea, r: 0.95), 0, 0.68, 0)
            wool.scale = SCNVector3(1.2, 0.95, 0.95)
            inner.ball(0.2, dark, 0.5, 0.78, 0)
            inner.ball(0.04, Gfx.mat(0xffffff, r: 0.4), 0.66, 0.84, 0.08); inner.ball(0.04, Gfx.mat(0xffffff, r: 0.4), 0.66, 0.84, -0.08)
            inner.ball(0.09, body, 0.3, 0.42, 0)
        case .bean:
            legPair(body, y: 0.3, h: 0.3, w: 0.2)
            inner.add(SCNCapsule(capRadius: 0.3, height: 0.95), body, at: SCNVector3(0, 0.78, 0))
            inner.box(0.16, 0.22, 0.34, Gfx.mat(0xa8e6ff, r: 0.2, m: 0.2, e: 0x7fd0f0, eIntensity: 0.4), 0.26, 0.98, 0, round: 0.05)
            inner.box(0.16, 0.5, 0.34, body, -0.3, 0.7, 0, round: 0.05)
        case .robot:
            legPair(Gfx.mat(0x8c96a8, r: 0.4, m: 0.7), y: 0.38, h: 0.38)
            inner.box(0.5, 0.5, 0.42, Gfx.mat(0xc5ccd8, r: 0.35, m: 0.7), 0, 0.65, 0, round: 0.05)
            inner.box(0.12, 0.12, 0.2, Gfx.mat(color, r: 0.3, e: color, eIntensity: 0.8), 0.26, 0.7, 0)
            inner.box(0.36, 0.3, 0.36, Gfx.mat(0xdde2ec, r: 0.35, m: 0.6), 0, 1.07, 0, round: 0.05)
            inner.box(0.06, 0.1, 0.24, Gfx.mat(0xffd23f, r: 0.3, e: 0xffd23f, eIntensity: 0.9), 0.19, 1.1, 0)
            inner.cyl(0.02, 0.3, Gfx.mat(0x8c96a8, r: 0.4, m: 0.7), 0, 1.4, 0)
            inner.ball(0.05, Gfx.mat(color, r: 0.3, e: color), 0, 1.57, 0)
        case .wizard:
            legPair(dark, y: 0.16, h: 0.16, w: 0.14)
            inner.add(SCNCone(topRadius: 0.08, bottomRadius: 0.38, height: 0.9), body, at: SCNVector3(0, 0.62, 0))
            inner.ball(0.2, skin, 0, 1.2, 0)
            eyes(1.22, 0.17)
            inner.add(SCNCone(topRadius: 0.0, bottomRadius: 0.3, height: 0.6), Gfx.mat(0x2d2a6b, r: 0.7), at: SCNVector3(0, 1.62, 0))
            inner.cyl(0.32, 0.04, Gfx.mat(0x2d2a6b, r: 0.7), 0, 1.34, 0)
        }
        return Runner(root: root, inner: inner, legs: legs, name: name)
    }
}

/// Small drawing helpers shared by the fun features.
enum FunGfx {
    /// Speech bubble that wraps at `maxWidth` points.
    static func bubble(_ text: String, size: CGFloat = 19, maxWidth: CGFloat = 300) -> NSImage {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium),
                                                    .foregroundColor: NSColor(white: 0.1, alpha: 1), .paragraphStyle: style]
        let box = (text as NSString).boundingRect(with: NSSize(width: maxWidth, height: 400), options: [.usesLineFragmentOrigin], attributes: attrs)
        let tail: CGFloat = 12
        let w = ceil(box.width) + 28, h = ceil(box.height) + 16
        return NSImage(size: NSSize(width: w, height: h + tail), flipped: false) { r in
            let body = NSRect(x: 0, y: tail, width: r.width, height: r.height - tail)
            NSColor.white.setFill()
            NSColor(white: 0.2, alpha: 1).setStroke()
            let p = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 14, yRadius: 14)
            p.lineWidth = 2
            p.fill(); p.stroke()
            let t = NSBezierPath()
            t.move(to: NSPoint(x: r.midX - 8, y: tail + 1)); t.line(to: NSPoint(x: r.midX, y: 1)); t.line(to: NSPoint(x: r.midX + 8, y: tail + 1))
            NSColor.white.setFill(); t.fill()
            (text as NSString).draw(with: NSRect(x: 14, y: tail + 8, width: ceil(box.width), height: ceil(box.height)), options: [.usesLineFragmentOrigin], attributes: attrs)
            return true
        }
    }
}
