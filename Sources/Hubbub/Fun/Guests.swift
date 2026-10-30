import SceneKit
import AppKit

/// Rare surprise visitors. At most one guest at a time, built from a handful of primitives, removed when it leaves.
@MainActor
final class GuestLayer {
    nonisolated static let enabledKey = "surpriseGuests"
    static var enabled: Bool { DefaultsMigration.run; return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
    private static let countKey = "funFinishedCount", specialKey = "funLastSpecial"

    let root = SCNNode()
    private var guest: Guest?
    private var theme: Theme?
    private var nextCheck: Double?
    private var lastGuestAt: Date?
    private var pendingMilestone: Int?
    private var lastT: Double?
    private let debug = ProcessInfo.processInfo.environment["HUBBUB_FUN"] ?? ""
    private var debugDone = false

    init() { root.name = "guests" }

    var isActive: Bool { guest != nil }

    func noteFinished() {
        guard Self.enabled else { return }
        let n = UserDefaults.standard.integer(forKey: Self.countKey) + 1
        UserDefaults.standard.set(n, forKey: Self.countKey)
        if n % GuestPlan.milestoneEvery == 0 { pendingMilestone = n }
    }

    func clear() {
        guest?.root.removeFromParentNode()
        guest = nil
    }

    // MARK: Frame

    func tick(t: Double, theme: Theme, stage: Stage) {
        if self.theme != theme { clear(); self.theme = theme }
        let dt = min(max(t - (lastT ?? t), 0), 0.1)
        lastT = t
        if let g = guest {
            update(g, t: t, dt: dt, stage: stage)
            if g.done { g.root.removeFromParentNode(); guest = nil; lastGuestAt = Date() }
            return
        }
        if debug.contains("guest:"), !debugDone {
            debugDone = true
            let raw = debug.components(separatedBy: "guest:").last?.components(separatedBy: ",").first ?? ""
            summon(GuestKind(rawValue: raw) ?? .ghost, occasion: .random, t: t, theme: theme, stage: stage)
            return
        }
        guard Self.enabled else { return }
        guard let next = nextCheck else { nextCheck = t + 6; return }
        guard t >= next else { return }
        nextCheck = t + GuestPlan.checkInterval
        let d = UserDefaults.standard
        if let occ = GuestPlan.decide(now: Date(), calendar: .current, lastGuestAt: lastGuestAt, lastSpecialKey: d.string(forKey: Self.specialKey),
                                      pendingMilestone: pendingMilestone, roll: Double.random(in: 0..<1)) {
            if case .special(let s) = occ { d.set(GuestPlan.dayKey(s, Date(), calendar: .current), forKey: Self.specialKey) }
            if case .milestone = occ { pendingMilestone = nil }
            summon(GuestPlan.kind(for: occ, theme: theme, roll: Double.random(in: 0..<1)), occasion: occ, t: t, theme: theme, stage: stage)
        }
    }

    /// Settings button: sends a guest right away (ignores the enabled flag and the schedule).
    func visitNow(t: Double, theme: Theme, stage: Stage) {
        guard guest == nil else { return }
        summon(GuestPlan.kind(for: .random, theme: theme, roll: Double.random(in: 0..<1)), occasion: .random, t: t, theme: theme, stage: stage)
    }

    private func summon(_ kind: GuestKind, occasion: GuestOccasion, t: Double, theme: Theme, stage: Stage) {
        let g = Guest(kind: kind, occasion: occasion, startT: t, hold: debug.contains("guest:"))
        root.addChildNode(g.root)
        guest = g
        lastGuestAt = Date()
        say(g, GuestPlan.occasionLine(occasion, kind: kind), t: t, hold: 4)
        SoundCenter.shared.play(.spawn)
    }

    // MARK: Interaction

    /// Click on a guest: a funny line, a hop and a little emoji.
    func poke(t: Double, stage: Stage) {
        guard let g = guest, let theme else { return }
        g.clicks += 1
        var lines = g.kind.clickLines
        if g.clicks % 4 == 0 { lines = [GuestPlan.quip(theme)] }
        say(g, lines[(g.clicks - 1) % lines.count], t: t, hold: 3)
        g.root.removeAction(forKey: "hop")
        g.root.runAction(.sequence([.moveBy(x: 0, y: 0.35, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.35, z: 0, duration: 0.12)]), forKey: "hop")
        let p = g.root.worldPosition
        stage.floatEmoji(["✨", "💬", "😄"][g.clicks % 3], at: SCNVector3(p.x, p.y + 2.8, p.z), size: 32, rise: 1.1)
        if g.clicks >= 5, !g.leaving {
            g.leaving = true
            say(g, g.kind.leaveLine, t: t, hold: 3)
        }
    }

    private func say(_ g: Guest, _ text: String, t: Double, hold: Double) {
        g.bubble?.removeFromParentNode()
        let n = Gfx.billboard(FunGfx.bubble(text, size: 19, maxWidth: 260), unitsPerPoint: 0.02)
        n.position = SCNVector3(0, g.kind == .ufo ? 1.7 : 2.9, 0)
        g.root.addChildNode(n)
        g.bubble = n
        g.bubbleUntil = t + hold
    }

    // MARK: Animation

    private func update(_ g: Guest, t: Double, dt: Double, stage: Stage) {
        if let b = g.bubble, t > g.bubbleUntil { b.removeFromParentNode(); g.bubble = nil }
        if g.kind == .ufo { updateUFO(g, t: t, stage: stage); return }
        let dist = abs(g.x1 - g.x0)
        let paused = (g.pausedUntil ?? 0) > t
        if !paused {
            let speed = (g.kind == .ghost ? 1.6 : 2.2) * (g.leaving ? 2.2 : 1)
            g.u = min(1, g.u + dt * speed / dist * (g.hold && g.u < 0.5 ? 4 : 1))
            if g.u >= 0.5, !g.pauseDone, !g.leaving {
                g.pauseDone = true
                g.pausedUntil = t + (g.hold ? 999 : (g.kind == .ghost ? 1.4 : 4.5))
                g.nextEmoji = t
                startPause(g, t: t)
            }
        }
        let dir = g.x1 > g.x0 ? 1.0 : -1.0
        let x = g.x0 + (g.x1 - g.x0) * g.u
        var y = 0.0
        var zOff = 0.0
        if g.kind == .ghost {
            y = 0.9 + 0.25 * sin(t * 2.4)
            zOff = 0.5 * sin(t * 1.3)
        } else if !paused {
            y = abs(sin(t * 7)) * 0.07
        }
        g.root.position = SCNVector3(x, y, g.z + zOff)
        let yaw = paused ? 0.0 : (dir > 0 ? 0.0 : Double.pi)
        g.root.eulerAngles = SCNVector3(0, g.kind == .ghost ? 0 : yaw + (paused ? -0.0 : 0), 0)
        for (leg, s) in g.legs { leg.eulerAngles = SCNVector3(0, 0, paused ? 0 : sin(t * 9) * s * 0.7) }
        if paused, t >= g.nextEmoji { pauseEmoji(g, t: t, stage: stage) }
        if g.u >= 1 { g.done = true }
    }

    private func startPause(_ g: Guest, t: Double) {
        switch g.kind {
        case .ghost: g.root.runAction(.sequence([.scale(to: 1.5, duration: 0.15), .scale(to: 1, duration: 0.3)]))
        case .alien: g.flash(t: t)
        default: break
        }
    }

    private func pauseEmoji(_ g: Guest, t: Double, stage: Stage) {
        let p = g.root.worldPosition
        let at = SCNVector3(p.x + CGFloat.random(in: -0.6...0.6), p.y + 2.5, p.z)
        switch g.kind {
        case .bard: stage.floatEmoji(["🎵", "🎶"].randomElement()!, at: at, size: 34, rise: 1.4); g.nextEmoji = t + 0.9
        case .merchant: stage.floatEmoji("🔔", at: at, size: 32, rise: 1.0); g.nextEmoji = t + 1.6
        case .partyPal: stage.floatEmoji(["🎉", "🎊", "✨"].randomElement()!, at: at, size: 36, rise: 1.5); g.nextEmoji = t + 0.5
        case .alien: stage.floatEmoji("📸", at: at, size: 32, rise: 1.0); g.flash(t: t); g.nextEmoji = t + 1.8
        default: g.nextEmoji = t + 5
        }
    }

    private func updateUFO(_ g: Guest, t: Double, stage: Stage) {
        var s = t - g.startT
        if g.hold { s = min(s, 5.2) }
        if g.leaving { s = max(s, 8) }
        let hoverX = g.chairX, hoverY = 4.3
        let ease = { (v: Double) in v * v * (3 - 2 * v) }
        var x = hoverX, y = hoverY
        if s < 3 {
            x = g.x0 + (hoverX - g.x0) * ease(s / 3)
        } else if s > 8 {
            let k = min(1, (s - 8) / 2.5)
            x = hoverX + (g.x1 - hoverX) * k * k
            y = hoverY + 1.2 * k
        }
        y += 0.12 * sin(t * 3)
        g.root.position = SCNVector3(x, y, g.z)
        g.spin.eulerAngles = SCNVector3(0, CGFloat(t) * 2.5, 0)
        // Tractor beam and chair, positioned in world space under the saucer.
        let beamOn = s > 3 && s < 7.6
        g.beam.opacity = beamOn ? min(0.38, CGFloat(min(s - 3, 7.6 - s)) * 0.6) : 0
        g.beam.position = SCNVector3(0, -y / 2, 0)
        (g.beam.geometry as? SCNCone)?.height = y
        if s > 3.2, s < 7.4 {
            let k = ease(max(0, min(1, (s - 3.6) / 3.6)))
            g.chair.isHidden = false
            g.chair.position = SCNVector3(0, -y + 0.05 + CGFloat(k) * (y - 0.9), 0)
            g.chair.eulerAngles = SCNVector3(0.3 * sin(t * 2) * CGFloat(k), CGFloat(k) * 12, 0)
            g.chair.scale = SCNVector3(1 - 0.6 * k, 1 - 0.6 * k, 1 - 0.6 * k)
        } else {
            g.chair.isHidden = true
        }
        if s > 7.4, !g.pauseDone {
            g.pauseDone = true
            say(g, "Chair acquired. Thank you!", t: t, hold: 3)
            stage.floatEmoji("🪑", at: SCNVector3(x, y + 1.2, g.z), size: 36, rise: 1.0)
        }
        if s > 10.6 { g.done = true }
    }

    // MARK: Guest model

    private final class Guest {
        let kind: GuestKind
        let occasion: GuestOccasion
        let root = SCNNode()
        let startT: Double
        let hold: Bool
        let x0: Double, x1: Double, z: Double
        var chairX = Double.random(in: -3...3)
        var u = 0.0
        var pausedUntil: Double?
        var pauseDone = false
        var clicks = 0
        var leaving = false
        var bubble: SCNNode?
        var bubbleUntil = 0.0
        var nextEmoji = 0.0
        var done = false
        var legs: [(SCNNode, Double)] = []
        var spin = SCNNode()
        var beam = SCNNode()
        var chair = SCNNode()
        var flashNode: SCNNode?

        init(kind: GuestKind, occasion: GuestOccasion, startT: Double, hold: Bool) {
            self.kind = kind; self.occasion = occasion; self.startT = startT; self.hold = hold
            let ltr = Bool.random()
            x0 = ltr ? -13.5 : 13.5
            x1 = -x0
            z = kind == .ufo ? 8.2 : 9.7
            root.name = "prop:guest"
            let s: CGFloat = kind == .ufo ? 1 : 1.15
            root.scale = SCNVector3(s, s, s)
            build()
            root.tag(prefix: "prop:guest")
            root.position = SCNVector3(x0, 0, z)
        }

        func flash(t: Double) {
            guard let f = flashNode else { return }
            f.removeAllActions()
            f.opacity = 1
            f.runAction(.sequence([.fadeOut(duration: 0.35)]))
        }

        private func build() {
            let skin = Gfx.mat(0xf2c9a0, r: 0.7), dark = Gfx.mat(0x23262e, r: 0.8)
            func legPair(_ m: SCNMaterial, y: CGFloat = 0.45, h: CGFloat = 0.45, w: CGFloat = 0.18) {
                for (i, z) in [CGFloat(0.12), -0.12].enumerated() {
                    let p = root.group("leg", 0, y, z)
                    p.box(w, h, w, m, 0, -h / 2, 0)
                    legs.append((p, i == 0 ? 1 : -1))
                }
            }
            func eyes(_ y: CGFloat, _ x: CGFloat, r: CGFloat = 0.04, spread: CGFloat = 0.09) {
                root.ball(r, dark, x, y, spread); root.ball(r, dark, x, y, -spread)
            }
            switch kind {
            case .merchant:
                legPair(Gfx.mat(0x4b3a2a, r: 0.9))
                root.cyl(0.32, 0.85, Gfx.mat(0x8a4b2a, r: 0.85), 0, 0.88, 0)
                root.ball(0.25, skin, 0.02, 1.52, 0)
                eyes(1.55, 0.22)
                root.cyl(0.46, 0.05, Gfx.mat(0x5a3b22, r: 0.9), 0, 1.72, 0)
                root.cyl(0.26, 0.28, Gfx.mat(0x5a3b22, r: 0.9), 0, 1.86, 0)
                let pack = root.group("pack", -0.42, 1.0, 0)
                pack.box(0.4, 0.8, 0.62, Gfx.mat(0xb8893c, r: 0.9), 0, 0, 0, round: 0.05)
                pack.box(0.46, 0.12, 0.66, Gfx.mat(0x6e4b24, r: 0.9), 0, 0.46, 0)
                pack.cyl(0.14, 0.2, Gfx.mat(0x8c96a8, r: 0.4, m: 0.7), -0.28, 0.3, 0.18)
                pack.ball(0.16, Gfx.mat(0xc95f3b, r: 0.6), -0.26, -0.05, -0.2)
                pack.cyl(0.07, 0.5, Gfx.mat(0xd9b27c, r: 0.6), -0.1, 0.62, 0)
                pack.ball(0.1, Gfx.mat(0xffd23f, r: 0.3, e: 0xffd23f, eIntensity: 1.2), 0.0, 0.95, 0.0)
            case .ghost:
                let m = Gfx.mat(0xf4f7ff, r: 0.6, e: 0xdfe8ff, eIntensity: 0.45, alpha: 0.78)
                let b = root.add(SCNCapsule(capRadius: 0.38, height: 1.25), m, at: SCNVector3(0, 0.85, 0), shadow: false)
                b.scale = SCNVector3(1, 1, 0.9)
                root.ball(0.07, dark, 0.3, 1.15, 0.12); root.ball(0.07, dark, 0.3, 1.15, -0.12)
                root.ball(0.06, dark, 0.34, 0.95, 0)
                for z in [CGFloat(-0.5), 0.5] { root.add(SCNSphere(radius: 0.16), m, at: SCNVector3(0.1, 0.75, z), shadow: false) }
            case .bard:
                legPair(Gfx.mat(0x7a2f4f, r: 0.8))
                root.add(SCNCone(topRadius: 0.2, bottomRadius: 0.38, height: 0.9), Gfx.mat(0x3f8f5a, r: 0.8), at: SCNVector3(0, 0.95, 0))
                root.ball(0.24, skin, 0, 1.55, 0)
                eyes(1.58, 0.21)
                root.add(SCNCone(topRadius: 0.04, bottomRadius: 0.34, height: 0.4), Gfx.mat(0xc9a24a, r: 0.7), at: SCNVector3(0, 1.88, 0))
                root.box(0.04, 0.5, 0.06, Gfx.mat(0xe4572e, r: 0.6), -0.12, 2.1, 0).eulerAngles = SCNVector3(0, 0, 0.5)
                let lute = root.group("lute", 0.38, 1.0, 0)
                let body = lute.ball(0.22, Gfx.mat(0xb06a2e, r: 0.6), 0, 0, 0)
                body.scale = SCNVector3(0.5, 1, 0.8)
                lute.ball(0.06, dark, 0.06, 0, 0)
                lute.box(0.05, 0.6, 0.06, Gfx.mat(0x5a3b22, r: 0.8), 0, 0.42, 0)
            case .alien:
                legPair(Gfx.mat(0x3fb36a, r: 0.7), y: 0.4, h: 0.4, w: 0.14)
                root.add(SCNCapsule(capRadius: 0.26, height: 0.8), Gfx.mat(0xff8a3d, r: 0.7), at: SCNVector3(0, 0.78, 0))
                let head = root.ball(0.34, Gfx.mat(0x4fd183, r: 0.5), 0, 1.45, 0)
                head.scale = SCNVector3(1, 1.1, 1)
                for z in [CGFloat(0.16), -0.16] {
                    let e = root.ball(0.1, dark, 0.28, 1.5, z)
                    e.scale = SCNVector3(0.5, 1.3, 1)
                    root.cyl(0.015, 0.3, Gfx.mat(0x3fb36a, r: 0.6), -0.02, 1.95, z * 1.4)
                    root.ball(0.05, Gfx.mat(0xff5fa8, r: 0.3, e: 0xff5fa8, eIntensity: 1), -0.02, 2.12, z * 1.4)
                }
                let cam = root.box(0.18, 0.14, 0.26, Gfx.mat(0x2b2f3a, r: 0.4, m: 0.5), 0.34, 1.0, 0.0, round: 0.02)
                cam.addChildNode(SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.08)))
                let f = SCNNode(geometry: SCNSphere(radius: 0.35))
                let fm = SCNMaterial()
                fm.lightingModel = .constant
                fm.diffuse.contents = NSColor.white
                f.geometry?.materials = [fm]
                f.position = SCNVector3(0.55, 1.05, 0)
                f.opacity = 0
                root.addChildNode(f)
                flashNode = f
            case .partyPal:
                legPair(Gfx.mat(0x2b3550, r: 0.8), y: 0.3, h: 0.3)
                root.ball(0.42, Gfx.mat(0xff6fa8, r: 0.6), 0, 0.85, 0)
                eyes(1.0, 0.36, r: 0.05, spread: 0.12)
                root.add(SCNCone(topRadius: 0.0, bottomRadius: 0.26, height: 0.6), Gfx.mat(0xffd23f, r: 0.6), at: SCNVector3(0, 1.5, 0))
                root.ball(0.07, Gfx.mat(0x29b6f6, r: 0.5), 0, 1.84, 0)
                root.box(0.3, 0.05, 0.3, Gfx.mat(0x29b6f6, r: 0.6), 0, 1.4, 0)
            case .ufo:
                spin = root.group("spin", 0, 0, 0)
                let hull = spin.ball(0.9, Gfx.mat(0xb8c2d6, r: 0.3, m: 0.8), 0, 0, 0)
                hull.scale = SCNVector3(1, 0.28, 1)
                for i in 0..<8 {
                    let a = Double(i) / 8 * 2 * .pi
                    spin.ball(0.07, Gfx.mat(0xffd23f, r: 0.3, e: i % 2 == 0 ? 0xffd23f : 0x5ad1ff, eIntensity: 1.6), cos(a) * 0.85, 0.02, sin(a) * 0.85)
                }
                let dome = root.add(SCNSphere(radius: 0.45), Gfx.mat(0xa8e6ff, r: 0.1, m: 0.1, alpha: 0.5), at: SCNVector3(0, 0.2, 0), shadow: false)
                dome.scale = SCNVector3(1, 0.8, 1)
                root.ball(0.16, Gfx.mat(0x4fd183, r: 0.5), 0, 0.28, 0)
                let bm = SCNMaterial()
                bm.lightingModel = .constant
                bm.diffuse.contents = Gfx.color(0xfff2a8)
                bm.transparency = 0.5
                bm.writesToDepthBuffer = false
                bm.isDoubleSided = true
                let cone = SCNCone(topRadius: 0.2, bottomRadius: 1.0, height: 4)
                cone.materials = [bm]
                beam = SCNNode(geometry: cone)
                beam.opacity = 0
                root.addChildNode(beam)
                chair = Guest.makeChair()
                chair.isHidden = true
                root.addChildNode(chair)
            }
        }

        static func makeChair() -> SCNNode {
            let n = SCNNode()
            let wood = Gfx.mat(0xb07a3a, r: 0.8)
            n.box(0.6, 0.08, 0.6, wood, 0, 0.45, 0)
            n.box(0.6, 0.6, 0.07, wood, 0, 0.78, -0.27)
            for (x, z) in [(-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25)] { n.box(0.07, 0.45, 0.07, wood, x, 0.22, z) }
            return n
        }
    }
}
