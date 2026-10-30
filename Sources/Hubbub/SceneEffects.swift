import SceneKit
import AppKit

/// Scene-level effects requested by a RoomSim (positions are logical 320x180 room coordinates).
enum SceneEffect {
    case failure(CGPoint)
    case success(CGPoint)
    case spawn(CGPoint)
    case celebration
}

/// Plays themed one-shot effects and hosts the mascot. Everything is a few nodes or one particle system and removes itself.
@MainActor
final class SceneFX {
    let root = SCNNode()
    private let glow = SCNNode()
    private var mascot: Mascot?
    private var mascotTheme: Theme?
    private var lastT: Double?
    private var debugNext = 0.0
    private var debugStart: Double?
    private var activeEffects = 0

    static var mascotEnabled: Bool { UserDefaults.standard.object(forKey: "showMascot") as? Bool ?? true }
    /// Debug: HUBBUB_FX=failure|success|celebration|spawn replays that effect every 2.5 s.
    private static let debugFX = ProcessInfo.processInfo.environment["HUBBUB_FX"]

    init() {
        root.name = "fx"
        // One permanent dormant light avoids shader recompiles when an effect needs coloured light.
        let l = SCNLight()
        l.type = .omni
        l.intensity = 0
        l.attenuationEndDistance = 16
        glow.light = l
        glow.position = SCNVector3(0, 3, 4)
        root.addChildNode(glow)
    }

    // MARK: Frame hook

    func discard(_ sims: [RoomSim]) { for s in sims { _ = s.drainEffects() } }

    func tick(sim: RoomSim, all: [RoomSim], theme: Theme, t: Double) {
        let dt = min(max(t - (lastT ?? t), 0), 0.1)
        lastT = t
        for s in all {
            let list = s.drainEffects()
            guard s === sim else { continue }
            for e in list.suffix(6) { play(e, theme: theme, t: t) }
        }
        if let d = SceneFX.debugFX {
            if debugStart == nil { debugStart = t; debugNext = t + 2 }
            if t >= debugNext {
                debugNext = t + 2.5
                let p = sim.subs.first?.pos ?? sim.captain.pos
                switch d {
                case "failure": play(.failure(p), theme: theme, t: t); mascot?.react(.failure, t: t)
                case "spawn": play(.spawn(p), theme: theme, t: t)
                case "celebration": play(.celebration, theme: theme, t: t)
                default: play(.success(p), theme: theme, t: t)
                }
            }
        }
        updateMascot(sim: sim, theme: theme, t: t, dt: dt)
    }

    private func updateMascot(sim: RoomSim, theme: Theme, t: Double, dt: Double) {
        guard SceneFX.mascotEnabled else {
            mascot?.node.removeFromParentNode()
            mascot = nil
            return
        }
        if mascot == nil || mascotTheme != theme {
            mascot?.node.removeFromParentNode()
            let m = Mascot(kind: Mascot.kind(for: theme), start: sim.captain.pos)
            root.addChildNode(m.node)
            mascot = m
            mascotTheme = theme
        }
        mascot?.update(captain: sim.captain.pos, sleeping: sim.captain.mood == .sleep, t: t, dt: dt)
    }

    // MARK: Playing

    private func world(_ p: CGPoint, y: CGFloat = 0) -> SCNVector3 { SCNVector3(Environments.wx(p.x), y, Environments.wz(p.y)) }

    func play(_ e: SceneEffect, theme: Theme, t: Double) {
        guard activeEffects < 14 else { return }
        switch e {
        case .failure(let p):
            mascot?.react(.failure, t: t)
            failure(at: world(p), theme: theme)
        case .success(let p):
            mascot?.react(.success, t: t)
            success(at: world(p), theme: theme)
        case .spawn(let p):
            let c = SceneFX.palette(theme)[0]
            burst(at: world(p, y: 0.2), color: c, count: 14, speed: 1.6, life: 0.7, size: 0.22, gravity: 0.5, dir: SCNVector3(0, 1, 0), spread: 1.2)
        case .celebration:
            mascot?.react(.success, t: t)
            celebration(theme: theme)
        }
    }

    static func palette(_ theme: Theme) -> [NSColor] {
        if let h = ThemeExtensions.active?.effectPalette(theme) { return h.map { Gfx.color($0) } }
        let hex: [UInt32] = switch theme {
        case .space: [0x5fd4ff, 0xffffff, 0x8f7bff]
        case .kitchen: [0xffb23e, 0xffe27a, 0xff6f3c]
        case .prison: [0xffd24a, 0x58a6ff, 0xffffff]
        case .football: [0xffffff, 0x35d66b, 0xffd24a]
        case .farm: [0xffe066, 0x8ee05a, 0xff9f6b]
        case .impostor: [0x3bf0ff, 0xff4a4a, 0x7dff6b]
        case .wizard: [0xb48cff, 0xffd86b, 0x7fe3ff]
        case .galactic: [0x59a8ff, 0x7dffa0, 0xffd24a]
        case .fellowship: [0xffd56a, 0x9bd36a, 0xffffff]
        default: [0xff7a3d, 0x5fd4ff, 0xffd24a]
        }
        return hex.map { Gfx.color($0) }
    }

    private func failure(at p: SCNVector3, theme: Theme) {
        switch theme {
        case .kitchen:
            flare(at: p)
        case .prison:
            pulse(at: p, colors: [0xff2a2a, 0x2a5aff], duration: 2.6, rate: 9)
            sparks(at: SCNVector3(p.x, 1.2, p.z), count: 20)
        case .football:
            redCard(at: p)
        case .farm:
            smoke(at: SCNVector3(p.x, 0.4, p.z), color: NSColor(red: 0.5, green: 0.9, blue: 0.35, alpha: 1), count: 18, size: 0.9)
            pulse(at: p, colors: [0x7dff4a], duration: 1.4, rate: 6)
        case .impostor:
            ventPop(at: p)
        case .wizard:
            frog(at: p)
        case .galactic:
            pulse(at: p, colors: [0xff2020], duration: 2.8, rate: 8)
            sparks(at: SCNVector3(p.x, 1.1, p.z), count: 46)
            smoke(at: SCNVector3(p.x, 1.2, p.z), color: NSColor(white: 0.25, alpha: 1), count: 10, size: 0.7)
        case .fellowship:
            eagle(at: p)
        default:
            pulse(at: p, colors: [0xff2020], duration: 2.4, rate: 8)
            sparks(at: SCNVector3(p.x, 1.1, p.z), count: 30)
            smoke(at: SCNVector3(p.x, 1.3, p.z), color: NSColor(white: 0.3, alpha: 1), count: 10, size: 0.7)
        }
    }

    private func success(at p: SCNVector3, theme: Theme) {
        let pal = SceneFX.palette(theme)
        confetti(at: SCNVector3(p.x, 2.4, p.z), colors: pal, count: 36, radius: 0.5)
        burst(at: SCNVector3(p.x, 1.9, p.z), color: pal[0], count: 18, speed: 2.2, life: 0.8, size: 0.2, gravity: -1.5, dir: SCNVector3(0, 1, 0), spread: 3)
    }

    private func celebration(theme: Theme) {
        let pal = SceneFX.palette(theme)
        confetti(at: SCNVector3(0, 6, 3.5), colors: pal, count: 140, radius: 9)
        for i in 0..<4 {
            let at = SCNVector3(CGFloat([-6, 5, -1.5, 8][i]), CGFloat([5.5, 6.2, 7, 5.2][i]), CGFloat([2, 1, 4.5, 4][i]))
            let c = pal[i % pal.count]
            track(1.8) {
                self.root.runAction(.sequence([.wait(duration: Double(i) * 0.45), .run { _ in
                    Task { @MainActor in
                        self.burst(at: at, color: c, count: 45, speed: 4, life: 1.2, size: 0.22, gravity: -2.4, dir: SCNVector3(0, 1, 0), spread: .pi)
                    }
                }]))
            }
        }
        pulse(at: SCNVector3(0, 3, 4), colors: pal.map { UInt32(hexOf: $0) }, duration: 2.4, rate: 3, intensity: 700)
    }

    // MARK: Particle helpers

    private static let dot: NSImage = Gfx.image(32, 32) { c in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }
    private static let square: NSImage = Gfx.image(8, 8) { c in
        c.setFillColor(NSColor.white.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    /// Runs `work` and reserves an effect slot for `life` seconds.
    private func track(_ life: Double, _ work: () -> Void) {
        activeEffects += 1
        work()
        root.runAction(.sequence([.wait(duration: life), .run { _ in Task { @MainActor in self.activeEffects = max(0, self.activeEffects - 1) } }]))
    }

    private func attach(_ ps: SCNParticleSystem, at p: SCNVector3, life: Double) {
        let n = SCNNode()
        n.position = p
        n.addParticleSystem(ps)
        root.addChildNode(n)
        n.runAction(.sequence([.wait(duration: life), .removeFromParentNode()]))
    }

    private func fade(_ ps: SCNParticleSystem, grow: CGFloat? = nil) {
        let a = CAKeyframeAnimation()
        a.values = [1.0, 1.0, 0.0]
        a.keyTimes = [0, 0.55, 1]
        a.duration = 1
        var ctl: [SCNParticleSystem.ParticleProperty: SCNParticlePropertyController] = [.opacity: SCNParticlePropertyController(animation: a)]
        if let grow {
            let s = CABasicAnimation()
            s.fromValue = 0.5
            s.toValue = grow
            s.duration = 1
            ctl[.size] = SCNParticlePropertyController(animation: s)
        }
        ps.propertyControllers = ctl
    }

    private func burst(at p: SCNVector3, color: NSColor, count: Int, speed: CGFloat, life: Double, size: CGFloat, gravity: CGFloat, dir: SCNVector3, spread: CGFloat) {
        let ps = SCNParticleSystem()
        ps.particleImage = SceneFX.dot
        ps.emissionDuration = 0.12
        ps.birthRate = CGFloat(count) / 0.12
        ps.loops = false
        ps.particleLifeSpan = life
        ps.particleLifeSpanVariation = life * 0.3
        ps.particleVelocity = speed
        ps.particleVelocityVariation = speed * 0.4
        ps.particleSize = size
        ps.particleColor = color
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0, gravity, 0)
        ps.emittingDirection = dir
        ps.spreadingAngle = spread * 57.3
        ps.emitterShape = SCNSphere(radius: 0.1)
        fade(ps)
        attach(ps, at: p, life: life * 1.4 + 0.3)
    }

    private func sparks(at p: SCNVector3, count: Int) {
        let ps = SCNParticleSystem()
        ps.particleImage = SceneFX.dot
        ps.emissionDuration = 0.9
        ps.birthRate = CGFloat(count) / 0.9
        ps.loops = false
        ps.particleLifeSpan = 0.6
        ps.particleLifeSpanVariation = 0.3
        ps.particleVelocity = 4
        ps.particleVelocityVariation = 2
        ps.particleSize = 0.12
        ps.particleColor = NSColor(red: 1, green: 0.7, blue: 0.2, alpha: 1)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0, -9, 0)
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 70
        fade(ps)
        track(2) { attach(ps, at: p, life: 2) }
    }

    private func smoke(at p: SCNVector3, color: NSColor, count: Int, size: CGFloat) {
        let ps = SCNParticleSystem()
        ps.particleImage = SceneFX.dot
        ps.emissionDuration = 0.5
        ps.birthRate = CGFloat(count) / 0.5
        ps.loops = false
        ps.particleLifeSpan = 1.5
        ps.particleLifeSpanVariation = 0.4
        ps.particleVelocity = 0.9
        ps.particleVelocityVariation = 0.5
        ps.particleSize = size
        ps.particleColor = color.withAlphaComponent(0.55)
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0, 0.6, 0)
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 35
        fade(ps, grow: 1.8)
        track(2.4) { attach(ps, at: p, life: 2.4) }
    }

    private func confetti(at p: SCNVector3, colors: [NSColor], count: Int, radius: CGFloat) {
        guard !A11y.reduceMotion else { return }
        for (i, c) in colors.enumerated() {
            let ps = SCNParticleSystem()
            ps.particleImage = SceneFX.square
            ps.emissionDuration = 0.35
            ps.birthRate = CGFloat(count / colors.count) / 0.35
            ps.loops = false
            ps.particleLifeSpan = 2.2
            ps.particleLifeSpanVariation = 0.6
            ps.particleVelocity = 1.6 + CGFloat(i)
            ps.particleVelocityVariation = 1.5
            ps.particleSize = 0.15
            ps.particleSizeVariation = 0.05
            ps.particleColor = c
            ps.particleColorVariation = SCNVector4(0.08, 0.15, 0.1, 0)
            ps.particleAngularVelocity = 6
            ps.particleAngularVelocityVariation = 8
            ps.blendMode = .alpha
            ps.isLightingEnabled = false
            ps.acceleration = SCNVector3(0, -3, 0)
            ps.emittingDirection = SCNVector3(0, 1, 0)
            ps.spreadingAngle = 80
            ps.emitterShape = SCNSphere(radius: radius)
            fade(ps)
            track(3.2) { attach(ps, at: p, life: 3.2) }
        }
    }

    /// Flickers the shared coloured light around `p` (red alarm, siren, flare ...).
    private func pulse(at p: SCNVector3, colors: [UInt32], duration: Double, rate: Double, intensity: CGFloat = 1500) {
        guard !A11y.reduceMotion else { return }   // pulsing light is a flashing effect
        glow.removeAllActions()
        glow.position = SCNVector3(p.x, 3, p.z)
        let cols = colors.map { Gfx.color($0) }
        glow.runAction(.sequence([
            .customAction(duration: duration) { n, el in
                let k = CGFloat(el / CGFloat(duration))
                let on = sin(Double(el) * rate) > -0.2
                n.light?.color = cols[Int(Double(el) * rate / .pi) % cols.count]
                n.light?.intensity = on ? intensity * (1 - k * k) : 60
            },
            .run { n in n.light?.intensity = 0 }
        ]))
    }

    // MARK: Themed failure effects

    private func flare(at p: SCNVector3) {
        let ps = SCNParticleSystem()
        ps.particleImage = SceneFX.dot
        ps.emissionDuration = 1.6
        ps.birthRate = 40
        ps.loops = false
        ps.particleLifeSpan = 0.8
        ps.particleLifeSpanVariation = 0.3
        ps.particleVelocity = 1.4
        ps.particleVelocityVariation = 0.6
        ps.particleSize = 0.5
        ps.particleColor = NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
        ps.particleColorVariation = SCNVector4(0.06, 0.2, 0.2, 0)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0, 1.8, 0)
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 18
        ps.emitterShape = SCNSphere(radius: 0.35)
        fade(ps, grow: 0.3)
        track(3) { attach(ps, at: SCNVector3(p.x, 0.5, p.z), life: 3) }
        smoke(at: SCNVector3(p.x, 1.6, p.z), color: NSColor(white: 0.18, alpha: 1), count: 14, size: 0.9)
        pulse(at: p, colors: [0xff7a1a, 0xffb23e], duration: 2.2, rate: 14)
    }

    private func redCard(at p: SCNVector3) {
        let card = SCNNode()
        card.add(SCNBox(width: 0.55, height: 0.8, length: 0.03, chamferRadius: 0.02), Gfx.mat(0xe01818, r: 0.4, e: 0xc01010, eIntensity: 0.7), shadow: false)
        card.position = SCNVector3(p.x, 2.6, p.z)
        card.scale = SCNVector3(0.1, 0.1, 0.1)
        root.addChildNode(card)
        card.runAction(.sequence([
            .group([.scale(to: 1.5, duration: 0.25), .moveBy(x: 0, y: 0.9, z: 0, duration: 2.4), .rotateBy(x: 0, y: 6.28, z: 0, duration: 2.4)]),
            .scale(to: 0.01, duration: 0.2), .removeFromParentNode()
        ]))
        pulse(at: p, colors: [0xff2020, 0xffffff], duration: 1.2, rate: 10, intensity: 1800)
        burst(at: SCNVector3(p.x, 2.2, p.z), color: .white, count: 16, speed: 2, life: 0.6, size: 0.2, gravity: 0, dir: SCNVector3(0, 1, 0), spread: .pi)
    }

    private func ventPop(at p: SCNVector3) {
        let grate = SCNNode()
        grate.add(SCNBox(width: 1.3, height: 0.1, length: 0.9, chamferRadius: 0.03), Gfx.mat(0x3b4452, r: 0.5, m: 0.6), shadow: false)
        for i in -2...2 { grate.add(SCNBox(width: 0.07, height: 0.12, length: 0.8, chamferRadius: 0), Gfx.mat(0x0b0d12), at: SCNVector3(CGFloat(i) * 0.24, 0.01, 0), shadow: false) }
        grate.position = SCNVector3(p.x, 0.06, p.z + 0.5)
        root.addChildNode(grate)
        grate.runAction(.sequence([
            .group([.moveBy(x: 0, y: 2.6, z: 0, duration: 0.35), .rotateBy(x: 1.4, y: 2.5, z: 0.6, duration: 0.35)]),
            .group([.move(to: SCNVector3(p.x + 0.7, 0.07, p.z + 1.4), duration: 0.4), .rotateTo(x: 0, y: 0.5, z: 0, duration: 0.4)]),
            .wait(duration: 1.6), .fadeOut(duration: 0.3), .removeFromParentNode()
        ]))
        pulse(at: p, colors: [0xff1c1c], duration: 2.8, rate: 7, intensity: 3000)
        smoke(at: SCNVector3(p.x, 0.2, p.z + 0.5), color: NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1), count: 16, size: 0.8)
        sparks(at: SCNVector3(p.x, 0.3, p.z + 0.5), count: 24)
    }

    private func frog(at p: SCNVector3) {
        let f = SCNNode()
        let green = Gfx.mat(0x56c23a, r: 0.5)
        f.add(SCNSphere(radius: 0.3), green, at: SCNVector3(0, 0.25, 0)).scale = SCNVector3(1, 0.7, 1.2)
        for s: CGFloat in [-1, 1] {
            f.add(SCNSphere(radius: 0.11), Gfx.mat(0xf4f4d8), at: SCNVector3(0.14 * s, 0.5, 0.16), shadow: false)
            f.add(SCNSphere(radius: 0.05), Gfx.mat(0x101010), at: SCNVector3(0.14 * s, 0.52, 0.25), shadow: false)
            f.add(SCNSphere(radius: 0.13), green, at: SCNVector3(0.3 * s, 0.1, -0.15)).scale = SCNVector3(0.6, 0.5, 1.1)
        }
        f.position = SCNVector3(p.x, 0, p.z)
        f.scale = SCNVector3(0.1, 0.1, 0.1)
        root.addChildNode(f)
        let hop = SCNAction.sequence([.moveBy(x: 0, y: 0.7, z: 0.3, duration: 0.22), .moveBy(x: 0, y: -0.7, z: 0.3, duration: 0.22), .wait(duration: 0.25)])
        f.runAction(.sequence([.scale(to: 1.2, duration: 0.15), .repeat(hop, count: 4), .fadeOut(duration: 0.3), .removeFromParentNode()]))
        smoke(at: SCNVector3(p.x, 0.5, p.z), color: NSColor(red: 0.6, green: 0.4, blue: 0.95, alpha: 1), count: 20, size: 1.0)
        burst(at: SCNVector3(p.x, 0.8, p.z), color: NSColor(red: 0.8, green: 0.6, blue: 1, alpha: 1), count: 24, speed: 2.5, life: 0.9, size: 0.18, gravity: -0.5, dir: SCNVector3(0, 1, 0), spread: 2.5)
        pulse(at: p, colors: [0x9a6bff], duration: 1.6, rate: 8, intensity: 1800)
    }

    private func eagle(at p: SCNVector3) {
        let e = SCNNode()
        let brown = Gfx.mat(0x5b4129, r: 0.8)
        e.add(SCNSphere(radius: 0.45), brown, at: SCNVector3(0, 0, 0)).scale = SCNVector3(0.8, 0.7, 1.5)
        e.add(SCNSphere(radius: 0.22), Gfx.mat(0xf2ead8), at: SCNVector3(0, 0.12, 0.6))
        e.add(SCNCone(topRadius: 0, bottomRadius: 0.09, height: 0.3), Gfx.mat(0xe0a020), at: SCNVector3(0, 0.08, 0.86)).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        e.add(SCNBox(width: 0.35, height: 0.04, length: 0.5, chamferRadius: 0), brown, at: SCNVector3(0, 0, -0.75), shadow: false)
        var wings: [SCNNode] = []
        for s: CGFloat in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0.25 * s, 0.1, 0)
            pivot.add(SCNBox(width: 1.5, height: 0.05, length: 0.7, chamferRadius: 0.02), brown, at: SCNVector3(0.75 * s, 0, 0), shadow: false)
            e.addChildNode(pivot)
            wings.append(pivot)
        }
        wings[0].runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0, z: -0.7, duration: 0.14), .rotateTo(x: 0, y: 0, z: 0.5, duration: 0.14)])))
        wings[1].runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0, z: 0.7, duration: 0.14), .rotateTo(x: 0, y: 0, z: -0.5, duration: 0.14)])))
        let from = SCNVector3(p.x + 15, 8, p.z - 6), hit = SCNVector3(p.x, 1.7, p.z), away = SCNVector3(p.x - 16, 10, p.z - 9)
        e.position = from
        e.scale = SCNVector3(1.6, 1.6, 1.6)
        e.eulerAngles = SCNVector3(0.5, atan2(hit.x - from.x, hit.z - from.z), 0)
        root.addChildNode(e)
        let dive = SCNAction.move(to: hit, duration: 1.1)
        dive.timingMode = .easeIn
        e.runAction(.sequence([
            dive,
            .run { _ in e.eulerAngles = SCNVector3(-0.4, atan2(away.x - hit.x, away.z - hit.z), 0) },
            .move(to: away, duration: 1.5), .removeFromParentNode()
        ]))
        track(3) {
            root.runAction(.sequence([.wait(duration: 1.1), .run { _ in
                Task { @MainActor in
                    self.burst(at: hit, color: NSColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 1), count: 22, speed: 2.4, life: 0.8, size: 0.25, gravity: -1, dir: SCNVector3(0, 1, 0), spread: 2.5)
                }
            }]))
        }
    }
}

private extension UInt32 {
    init(hexOf c: NSColor) {
        let r = c.usingColorSpace(.deviceRGB) ?? c
        self = (UInt32(r.redComponent * 255) << 16) | (UInt32(r.greenComponent * 255) << 8) | UInt32(r.blueComponent * 255)
    }
}

extension RoomSim {
    func emit(_ e: SceneEffect) {
        if pendingEffects.count < 12 { pendingEffects.append(e) }
    }

    func drainEffects() -> [SceneEffect] {
        defer { pendingEffects = [] }
        return pendingEffects
    }

    /// Per-frame hook: delayed spawn puffs and the end-of-turn celebration after a long working stretch.
    func emitSceneEffects(state: SessionState, t: Double) {
        if !spawnQueue.isEmpty {
            spawnQueue.removeAll { id in
                guard let a = subs.first(where: { $0.id == id }) else { return true }
                guard t >= a.spawnAt else { return false }
                emit(.spawn(a.pos))
                return true
            }
        }
        if state == .working {
            if workingSince == nil { workingSince = t }
        } else if let w = workingSince {
            workingSince = nil
            if state == .idle, t - w > 8 { emit(.celebration) }
        }
    }

    /// Where a failure should show: on the afflicted sub-agent if the theme marked one, otherwise the captain.
    func failureSpot() -> CGPoint {
        if let id = captain.pending, let v = subs.first(where: { $0.id == id }) { return v.pos }
        let bad: [Mood] = [.sick, .dizzy, .sad, .card]
        return (subs.first { bad.contains($0.mood) } ?? captain).pos
    }
}
