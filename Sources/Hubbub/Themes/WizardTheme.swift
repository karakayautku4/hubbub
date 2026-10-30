import AppKit
import SceneKit

// Spell Academy: a candle-lit castle great hall where apprentices learn spells. Original parody art.

private enum WZ {
    static let stone = 0x5b5666 as UInt32
    static let wood = 0x6b4426 as UInt32
    static let darkWood = 0x3f2815 as UInt32
    static let gold = 0xf2c94c as UInt32
    static let houses: [UInt32] = [0x9c2336, 0x1f7a52, 0x2a4f9c, 0xd9a21f]

    static func bobbing(_ n: SCNNode, _ amp: CGFloat = 0.15, _ dur: Double = 1.6, phase: Double = 0) {
        let up = SCNAction.moveBy(x: 0, y: amp, z: 0, duration: dur)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        n.runAction(.sequence([.wait(duration: phase), .repeatForever(.sequence([up, down]))]))
    }

    static func flicker(_ n: SCNNode) {
        n.runAction(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.17), .scale(to: 0.85, duration: 0.23), .scale(to: 1.1, duration: 0.15)])))
    }

    static func candle(_ parent: SCNNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, phase: Double, light: Bool) -> SCNNode {
        let c = parent.group("candle", x, y, z)
        c.cyl(0.07, 0.34, Gfx.mat(0xf6ecd0, r: 0.8, e: 0x3a3020, eIntensity: 0.4), 0, 0, 0)
        let flame = c.add(SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.17), Gfx.mat(0xffd36a, e: 0xffa020, eIntensity: 2), at: SCNVector3(0, 0.25, 0), shadow: false)
        c.ball(0.1, Gfx.mat(0xffc060, e: 0xff9a30, eIntensity: 1, alpha: 0.25), 0, 0.25, 0).castsShadow = false
        flicker(flame)
        if light {
            let l = SCNLight()
            l.type = .omni; l.color = Gfx.color(0xffb255); l.intensity = 180; l.attenuationEndDistance = 7
            let ln = SCNNode(); ln.light = l; ln.position = SCNVector3(0, 0.4, 0.5)
            c.addChildNode(ln)
        }
        bobbing(c, 0.18, 1.7 + phase * 0.13, phase: phase * 0.3)
        return c
    }

    static func banner(_ root: SCNNode, _ x: CGFloat, _ color: UInt32, emblem: Int) {
        let b = root.group("banner", x, 6.3, -0.12)
        let cloth = Gfx.mat(color, r: 0.85)
        b.cyl(0.07, 1.5, Gfx.mat(darkWood), 0, 0.1, 0).eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        let sway = b.group("sway", 0, 0, 0)
        sway.box(1.1, 3.2, 0.06, cloth, 0, -1.6, 0)
        let tip = sway.box(0.78, 0.78, 0.06, cloth, 0, -3.3, 0)
        tip.eulerAngles = SCNVector3(0, 0, Float.pi / 4)
        let trim = Gfx.mat(gold, r: 0.4, m: 0.4)
        sway.box(1.1, 0.1, 0.08, trim, 0, -0.1, 0.01)
        sway.box(0.08, 3.1, 0.08, trim, -0.5, -1.6, 0.01)
        sway.box(0.08, 3.1, 0.08, trim, 0.5, -1.6, 0.01)
        switch emblem {
        case 0: sway.ball(0.3, trim, 0, -1.6, 0.06)                                   // lion-ish sun
        case 1: for k in 0..<3 { sway.box(0.12, 0.7, 0.05, trim, -0.25 + CGFloat(k) * 0.25, -1.6, 0.05) }
        case 2: sway.add(SCNTorus(ringRadius: 0.28, pipeRadius: 0.06), trim, at: SCNVector3(0, -1.6, 0.05))
        default: sway.box(0.5, 0.5, 0.05, trim, 0, -1.6, 0.05).eulerAngles = SCNVector3(0, 0, Float.pi / 4)
        }
        sway.pivot = SCNMatrix4Identity
        sway.runAction(.repeatForever(.sequence([.rotateBy(x: 0, y: 0, z: 0.03, duration: 2.2 + Double(emblem) * 0.3), .rotateBy(x: 0, y: 0, z: -0.03, duration: 2.2 + Double(emblem) * 0.3)])))
    }

    static func window(_ root: SCNNode, _ x: CGFloat, sky: SCNMaterial) {
        let y: CGFloat = 4.0, w: CGFloat = 2.4, h: CGFloat = 3.2
        let g = root.group("window", x, y, -0.18)
        g.box(w, h, 0.05, sky, 0, 0, 0).castsShadow = false
        let arch = g.cyl(w / 2, 0.05, sky, 0, h / 2, 0)
        arch.eulerAngles = SCNVector3(Float.pi / 2, 0, 0); arch.castsShadow = false
        let frame = Gfx.mat(0x3d3946, r: 0.9)
        g.box(0.14, h, 0.2, frame, -w / 2, 0, 0.04)
        g.box(0.14, h, 0.2, frame, w / 2, 0, 0.04)
        g.box(w, 0.14, 0.2, frame, 0, -h / 2, 0.04)
        g.box(0.08, h + w / 2, 0.14, frame, 0, w / 4, 0.04)
        g.box(w, 0.08, 0.14, frame, 0, 0.2, 0.04)
        g.box(w, 0.08, 0.14, frame, 0, 1.2, 0.04)
        let arc = g.add(SCNTorus(ringRadius: w / 2, pipeRadius: 0.07), frame, at: SCNVector3(0, h / 2, 0.04), shadow: false)
        arc.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        arc.scale = SCNVector3(1, 1, 1)
        g.box(w + 0.3, 0.12, 0.4, Gfx.mat(0x4a4656, r: 0.9), 0, -h / 2 - 0.1, 0.1)
    }

    static func book(_ n: SCNNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ hex: UInt32, w: CGFloat = 0.16, h: CGFloat = 0.5, tilt: Float = 0) {
        let b = n.box(w, h, 0.34, Gfx.mat(hex, r: 0.7), x, y + h / 2, z, round: 0.01)
        b.eulerAngles = SCNVector3(0, 0, tilt)
        n.box(w + 0.01, 0.04, 0.35, Gfx.mat(gold, r: 0.3, m: 0.5), x, y + h * 0.75, z).eulerAngles = SCNVector3(0, 0, tilt)
    }

    static func owl(_ body: UInt32 = 0x8a6a4a, scale: CGFloat = 1) -> (SCNNode, [SCNNode]) {
        let o = SCNNode()
        let fur = Gfx.mat(body, r: 0.95), pale = Gfx.mat(0xe8dcc4, r: 0.95)
        let b = o.ball(0.32, fur, 0, 0, 0); b.scale = SCNVector3(0.9, 1.05, 1.1)
        o.ball(0.2, pale, 0, -0.05, 0.2)
        let head = o.ball(0.24, fur, 0, 0.32, 0.12)
        for x in [-0.1, 0.1] {
            head.parent!.ball(0.09, Gfx.mat(0xffffff), CGFloat(x), 0.36, 0.3)
            head.parent!.ball(0.05, Gfx.mat(0xffb800, e: 0x603800, eIntensity: 0.5), CGFloat(x), 0.36, 0.37)
            head.parent!.ball(0.025, Gfx.mat(0x000000), CGFloat(x), 0.36, 0.415)
            let tuft = head.parent!.add(SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.16), fur, at: SCNVector3(CGFloat(x) * 1.5, 0.58, 0.1))
            tuft.eulerAngles = SCNVector3(0, 0, Float(-x) * 1.2)
        }
        let beak = o.add(SCNCone(topRadius: 0, bottomRadius: 0.045, height: 0.12), Gfx.mat(0xe8a13a), at: SCNVector3(0, 0.3, 0.38))
        beak.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        var wings: [SCNNode] = []
        for s in [-1.0, 1.0] {
            let w = o.group("wing", CGFloat(s) * 0.28, 0.1, 0)
            let panel = w.box(0.7, 0.05, 0.4, fur, CGFloat(s) * 0.33, 0, 0, round: 0.02)
            w.box(0.3, 0.052, 0.3, pale, CGFloat(s) * 0.55, 0, 0.02)
            _ = panel
            wings.append(w)
        }
        o.scale = SCNVector3(scale, scale, scale)
        return (o, wings)
    }

    static func flap(_ wings: [SCNNode], speed: Double = 0.18, amp: CGFloat = 0.7) {
        for (i, w) in wings.enumerated() {
            let s: CGFloat = i == 0 ? 1 : -1
            w.runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0, z: s * amp, duration: speed), .rotateTo(x: 0, y: 0, z: -s * amp, duration: speed)])))
        }
    }

    static func bubbles(_ parent: SCNNode, _ hex: UInt32, radius: CGFloat, y: CGFloat, count: Int) {
        for i in 0..<count {
            let b = parent.ball(0.06 + CGFloat(i % 3) * 0.025, Gfx.mat(hex, r: 0.2, e: hex, eIntensity: 1.2, alpha: 0.85), 0, y, 0)
            b.castsShadow = false
            let a = Double(i) / Double(count) * .pi * 2
            b.position = SCNVector3(cos(a) * Double(radius) * 0.6, Double(y), sin(a) * Double(radius) * 0.6)
            let rise = SCNAction.group([.moveBy(x: 0, y: 0.9, z: 0, duration: 1.6 + Double(i) * 0.2), .sequence([.wait(duration: 1.2 + Double(i) * 0.2), .fadeOut(duration: 0.4)])])
            b.runAction(.sequence([.wait(duration: Double(i) * 0.35), .repeatForever(.sequence([.group([.fadeIn(duration: 0.01)]), rise, .move(to: b.position, duration: 0)]))]))
        }
    }
}

extension Environments {
    /// Room, floor, walls, ambient props and animated set pieces.
    static func wizard(_ root: SCNNode) {
        floor(root, Gfx.texMat(Gfx.tiles(0x4a4452, 0x3b3646, grout: 0x1f1c26, cells: 6), r: 0.55, m: 0.1, repeatX: 5, repeatY: 2))
        // long red runner carpet
        root.box(38, 0.03, 2.2, Gfx.mat(0x6b1f2e, r: 0.95), 0, 0.01, 7.9)
        root.box(38, 0.035, 0.12, Gfx.mat(WZ.gold, r: 0.5, m: 0.3), 0, 0.012, 6.8)
        root.box(38, 0.035, 0.12, Gfx.mat(WZ.gold, r: 0.5, m: 0.3), 0, 0.012, 9.0)

        let brick = Gfx.texMat(Gfx.tiles(0x5e596b, 0x544f61, grout: 0x2c2933, cells: 14, noise: 0.07), r: 0.9, repeatX: 9, repeatY: 2)
        root.box(38, 7.4, 0.4, brick, 0, 3.7, -0.4)
        root.box(38, 0.5, 0.6, Gfx.mat(0x3a3644, r: 0.9), 0, 0.25, -0.2)
        // timber ceiling beams and chains
        for x in stride(from: -15.0, through: 15.0, by: 7.5) {
            root.box(0.5, 0.5, 1.2, Gfx.mat(WZ.darkWood, r: 0.9), x, 7.2, 0.2)
        }
        root.box(38, 0.5, 0.5, Gfx.mat(WZ.darkWood, r: 0.9), 0, 7.2, -0.1)

        // tall arched windows with a moonlit night sky
        let sky = Gfx.texMat(Gfx.stars(), emissive: true)
        for x in [-12.0, -4.0, 4.0, 12.0] where x != 12.0 { WZ.window(root, CGFloat(x), sky: sky) }
        let moon = root.add(SCNSphere(radius: 0.7), Gfx.mat(0xfff6d8, e: 0xfff1c0, eIntensity: 1.2), at: SCNVector3(4.4, 5.2, -0.3), shadow: false)
        moon.name = "moon"

        // guild banners (generic colours) between the windows
        for (i, x) in [-16.0, -8.0, 0.0, 8.0].enumerated() {
            WZ.banner(root, CGFloat(x), WZ.houses[i], emblem: i)
        }
        WZ.banner(root, 16.5, WZ.houses[3], emblem: 3)

        // fireplace (right) with crackling fire
        let fp = root.group("prop:fireplace", 10.8, 0, -0.1)
        let st = Gfx.mat(0x6a6574, r: 0.9)
        fp.box(0.6, 3.4, 0.8, st, -1.4, 1.7, 0)
        fp.box(0.6, 3.4, 0.8, st, 1.4, 1.7, 0)
        fp.box(3.6, 0.6, 0.9, st, 0, 3.4, 0)
        fp.box(2.2, 2.7, 0.1, Gfx.mat(0x14100e), 0, 1.35, -0.3)
        for k in 0..<3 {
            let f = fp.add(SCNCone(topRadius: 0, bottomRadius: 0.34 - CGFloat(k) * 0.05, height: 0.8 + CGFloat(k) * 0.1), Gfx.mat(k == 1 ? 0xffc040 : 0xff6a1a, e: k == 1 ? 0xffa020 : 0xff4a00, eIntensity: 1.6), at: SCNVector3(-0.5 + CGFloat(k) * 0.5, 0.55, -0.05), shadow: false)
            WZ.flicker(f)
        }
        fp.box(1.8, 0.2, 0.3, Gfx.mat(WZ.darkWood), 0, 0.12, 0.05).eulerAngles = SCNVector3(0, 0, 0.05)
        let fl = SCNLight(); fl.type = .omni; fl.color = Gfx.color(0xff8a30); fl.intensity = 350; fl.attenuationEndDistance = 12
        let fln = SCNNode(); fln.light = fl; fln.position = SCNVector3(0, 1.2, 1.5); fp.addChildNode(fln)
        fln.runAction(.repeatForever(.sequence([.customAction(duration: 0.4) { n, _ in n.light?.intensity = 300 + CGFloat.random(in: 0...120) }])))
        // mantel clock, goblets
        fp.cyl(0.18, 0.4, Gfx.mat(WZ.gold, r: 0.3, m: 0.8), -1.0, 3.9, 0)
        fp.cyl(0.18, 0.4, Gfx.mat(WZ.gold, r: 0.3, m: 0.8), 1.0, 3.9, 0)

        // floating candles drifting over the hall
        let candlePos: [(CGFloat, CGFloat, CGFloat)] = [(-14, 4.4, 1.2), (-11, 4.8, 3.4), (-8.5, 5.6, 0.8), (-5, 4.6, 4.2), (-2, 4.2, 1.0), (1.5, 6.2, 3.6), (4.5, 5.8, 0.6), (7.5, 6.3, 3.9), (10, 4.2, 1.4), (13.5, 6.1, 3.0), (16, 4.2, 0.9), (-16, 4.7, 3.5)]
        for (i, p) in candlePos.enumerated() {
            let c = WZ.candle(root, p.0, p.1, p.2, phase: Double(i), light: i % 4 == 0)
            c.name = "prop:candles"
        }

        // owls: two circling the hall, one sleeping on a beam
        for (i, spec) in [(0xa88a64 as UInt32, 5.0, 0.0, 14.0), (0x5d5448, 6.6, 6.0, 19.0)].enumerated() {
            let (owl, wings) = WZ.owl(spec.0, scale: i == 0 ? 0.9 : 0.7)
            let holder = root.group("prop:owl", -19, spec.1, 3.0 + CGFloat(i) * 2.0)
            holder.addChildNode(owl)
            owl.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            WZ.flap(wings)
            let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.35, z: 0, duration: 1.1), .moveBy(x: 0, y: -0.35, z: 0, duration: 1.1)])
            owl.runAction(.repeatForever(bob))
            holder.runAction(.sequence([.wait(duration: spec.2), .repeatForever(.sequence([
                .move(to: SCNVector3(-19, spec.1, 3.0 + Double(i) * 2.0), duration: 0),
                .move(to: SCNVector3(19, spec.1 + 0.4, 3.0 + Double(i) * 2.0), duration: 16),
                .wait(duration: 9 + Double(i) * 6)]))]))
            _ = spec.3
        }
        let (sleeper, _) = WZ.owl(0xcdbd9a, scale: 0.8)
        let perch = root.group("prop:owl", -17.2, 6.7, -0.2)
        perch.addChildNode(sleeper)
        sleeper.position = SCNVector3(0, 0.3, 0)
        root.box(1.4, 0.15, 0.3, Gfx.mat(WZ.darkWood), -17.2, 6.9 - 0.5, -0.2)
        WZ.bobbing(sleeper, 0.03, 2.4)

        // armour display (comedy: wearing a party hat), left of the clock
        let ar = root.group("prop:armor", -18.0, 0, 0.3)
        let steel = Gfx.mat(0x9aa7b5, r: 0.3, m: 0.85)
        ar.box(0.5, 0.9, 0.3, steel, 0, 0.45, 0)
        ar.box(0.7, 0.8, 0.4, steel, 0, 1.3, 0, round: 0.1)
        ar.ball(0.3, steel, 0, 2.0, 0)
        ar.box(0.35, 0.08, 0.05, Gfx.mat(0x111111), 0, 2.0, 0.28)
        ar.add(SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.5), Gfx.mat(0xe23b8a, e: 0x601030), at: SCNVector3(0, 2.5, 0)).eulerAngles = SCNVector3(0, 0, 0.25)
        ar.ball(0.07, Gfx.mat(0xffd24a, e: 0xffd24a), 0.07, 2.78, 0)

        // great hall double doors where the apprentices arrive (left)
        let door = root.group("prop:door", -15.4, 0, 0.0)
        door.box(3.2, 3.8, 0.35, Gfx.mat(0x4a3220, r: 0.8), 0, 1.9, -0.05)
        door.cyl(1.6, 0.35, Gfx.mat(0x4a3220, r: 0.8), 0, 3.8, -0.05).eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        door.box(0.06, 3.8, 0.1, Gfx.mat(0x241508), 0, 1.9, 0.14)
        for y in [0.8, 1.9, 3.0] { door.box(3.0, 0.12, 0.08, Gfx.mat(0x2a2a30, m: 0.8), 0, y, 0.15) }
        door.ball(0.12, Gfx.mat(WZ.gold, r: 0.2, m: 0.9), -0.3, 1.8, 0.2)
        door.ball(0.12, Gfx.mat(WZ.gold, r: 0.2, m: 0.9), 0.3, 1.8, 0.2)

        // headwizard's lectern (centre)
        let l = root.group("prop:lectern", 0, 0, 0.5)
        l.box(2.4, 0.4, 1.2, Gfx.mat(WZ.stone, r: 0.9), 0, 0.2, 0)
        l.box(1.8, 0.9, 0.9, Gfx.mat(WZ.wood, r: 0.7), 0, 0.85, 0, round: 0.03)
        let slope = l.box(1.8, 0.08, 0.85, Gfx.mat(WZ.darkWood, r: 0.7), 0, 1.35, 0)
        slope.eulerAngles = SCNVector3(-0.4, 0, 0)
        l.box(0.75, 0.06, 0.5, Gfx.mat(0xf3e8c8, r: 0.9), -0.2, 1.42, 0.05).eulerAngles = SCNVector3(-0.4, 0, 0)
        let gem = l.ball(0.2, Gfx.mat(0x7be9ff, r: 0.1, e: 0x2bb6e6, eIntensity: 1.5, alpha: 0.9), 0.6, 1.65, 0)
        WZ.bobbing(gem, 0.1, 1.2)
        gem.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 6)))

        // cocoa cauldron – the idle/break spot
        let w = root.group("prop:coffee", wx(Theme.wizard.coffee.x), 0, wz(Theme.wizard.coffee.y) - 0.7)
        w.cyl(0.65, 0.12, Gfx.mat(0x2a2a30, m: 0.8), 0, 0.06, 0)
        w.ball(0.65, Gfx.mat(0x2a2a30, r: 0.4, m: 0.8), 0, 0.7, 0)
        w.cyl(0.5, 0.06, Gfx.mat(0x5a3320, r: 0.2, e: 0x2a1408, eIntensity: 0.5), 0, 1.0, 0)
        w.add(SCNTorus(ringRadius: 0.55, pipeRadius: 0.05), Gfx.mat(0x2a2a30, m: 0.8), at: SCNVector3(0, 1.02, 0))
        for s in [-1.0, 1.0] { w.cyl(0.06, 0.45, Gfx.mat(0x2a2a30, m: 0.8), CGFloat(s) * 0.4, 0.2, 0.25) }
        WZ.bubbles(w, 0xd9a066, radius: 0.5, y: 1.05, count: 4)
        w.box(0.9, 0.05, 0.5, Gfx.mat(0xf3e8c8), 1.1, 0.7, 0.3).eulerAngles = SCNVector3(0, 0.4, 0)
        w.cyl(0.14, 0.2, Gfx.mat(WZ.gold, r: 0.3, m: 0.8), 1.1, 0.8, 0.3)

        // tall hourglass tracking the "guild points": rows of glowing gems on the wall (left of the board)
        let hg = root.group("prop:points", 17.2, 0, 0.4)
        for (i, c) in WZ.houses.enumerated() {
            let h = 1.0 + CGFloat((i * 5) % 4) * 0.5
            hg.cyl(0.25, 3.0, Gfx.mat(0xcfe3f5, r: 0.05, alpha: 0.25), 0, 1.5, CGFloat(i) * 0.0).position.x = CGFloat(i) * 0.7 - 1.0
            let f = hg.cyl(0.21, h, Gfx.mat(c, r: 0.3, e: c, eIntensity: 0.9), CGFloat(i) * 0.7 - 1.0, h / 2, 0)
            f.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.75, duration: 1.1 + Double(i) * 0.2), .fadeOpacity(to: 1, duration: 1.1)])))
        }
        hg.position.x = 15.7
    }

    /// Prop for one work station; `kind` 0 library, 1 wand workshop, 2 potions, 3 owl post (see `Theme.stations`).
    static func wizardStation(_ kind: Int, _ n: SCNNode) {
        let wood = Gfx.mat(WZ.wood, r: 0.75), dark = Gfx.mat(WZ.darkWood, r: 0.8)
        let iron = Gfx.mat(0x2a2a30, r: 0.4, m: 0.8)
        switch kind {
        case 0:
            // bookshelf with spellbooks, a floating open tome and a ladder
            n.box(2.7, 2.6, 0.7, dark, 0, 1.3, 0.0)
            let cols: [UInt32] = [0x9c2336, 0x2a4f9c, 0x1f7a52, 0xd9a21f, 0x6a3a8a, 0x8a5a35]
            for row in 0..<3 {
                n.box(2.5, 0.08, 0.72, wood, 0, 0.4 + CGFloat(row) * 0.8, 0.02)
                for k in 0..<9 {
                    let tilt: Float = (row == 1 && k == 5) ? 0.35 : 0
                    WZ.book(n, -1.0 + CGFloat(k) * 0.24, 0.44 + CGFloat(row) * 0.8, 0.05, cols[(k + row * 2) % cols.count], w: 0.15 + CGFloat(k % 3) * 0.02, h: 0.5 + CGFloat((k * 3 + row) % 3) * 0.08, tilt: tilt)
                }
            }
            let tome = n.group("tome", 1.0, 1.9, 0.9)
            tome.box(0.5, 0.04, 0.38, Gfx.mat(0x6a3a8a), -0.25, 0, 0, round: 0.01).eulerAngles = SCNVector3(0, 0, 0.35)
            tome.box(0.5, 0.04, 0.38, Gfx.mat(0xf3e8c8), 0.25, 0.0, 0, round: 0.01).eulerAngles = SCNVector3(0, 0, -0.35)
            tome.ball(0.05, Gfx.mat(0xffe08a, e: 0xffd24a, eIntensity: 1.5), 0, 0.3, 0)
            WZ.bobbing(tome, 0.2, 1.3)
            let lad = n.box(0.1, 2.6, 0.06, wood, -1.55, 1.3, 0.55); lad.eulerAngles = SCNVector3(0.15, 0, 0)
            let lad2 = n.box(0.1, 2.6, 0.06, wood, -1.25, 1.3, 0.55); lad2.eulerAngles = SCNVector3(0.15, 0, 0)
            for y in stride(from: 0.4, through: 2.2, by: 0.45) { n.box(0.4, 0.05, 0.05, wood, -1.4, CGFloat(y), 0.5 + CGFloat(y) * -0.0) }
        case 1:
            // spell-practice dummy with scorched target, wand rack and sparks
            n.box(2.4, 0.2, 1.1, wood, 0, 0.1, 0.2, round: 0.03)
            n.cyl(0.08, 1.6, dark, 0, 1.0, 0.2)
            let sack = n.ball(0.38, Gfx.mat(0xd9c28a, r: 0.95), 0, 1.45, 0.2); sack.scale = SCNVector3(0.9, 1.2, 0.9)
            n.ball(0.24, Gfx.mat(0xe2cf9a, r: 0.95), 0, 2.15, 0.2)
            n.box(1.3, 0.1, 0.1, dark, 0, 1.7, 0.2)
            n.add(SCNCone(topRadius: 0, bottomRadius: 0.26, height: 0.55), Gfx.mat(0x6a3a8a, r: 0.9), at: SCNVector3(0.03, 2.55, 0.2)).eulerAngles = SCNVector3(0, 0, 0.2)
            n.cyl(0.4, 0.04, Gfx.mat(0x6a3a8a, r: 0.9), 0, 2.3, 0.2)
            let target = n.cyl(0.32, 0.04, Gfx.mat(0xffffff, r: 0.7), 0, 1.5, 0.6)
            target.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            n.cyl(0.2, 0.05, Gfx.mat(0xc8372d, r: 0.7), 0, 1.5, 0.62).eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            n.cyl(0.08, 0.05, Gfx.mat(0xffffff, r: 0.7), 0, 1.5, 0.64).eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            n.ball(0.14, Gfx.mat(0x241a14, r: 1), 0.28, 1.45, 0.6).scale = SCNVector3(1, 1, 0.2)
            for k in 0..<5 {
                let sp = n.ball(0.05, Gfx.mat([0xffd24a, 0x7be9ff, 0xe07bd8][k % 3], e: [0xffd24a, 0x7be9ff, 0xe07bd8][k % 3], eIntensity: 2), 0, 0, 0, name: nil)
                sp.castsShadow = false
                let ox = CGFloat(k) * 0.3 - 0.6
                sp.position = SCNVector3(ox, 1.0, 0.8)
                let up = SCNAction.group([.moveBy(x: 0, y: 1.0, z: 0.0, duration: 0.9), .sequence([.wait(duration: 0.6), .fadeOut(duration: 0.3)])])
                sp.runAction(.sequence([.wait(duration: Double(k) * 0.25), .repeatForever(.sequence([.fadeIn(duration: 0.01), up, .move(to: SCNVector3(ox, 1.0, 0.8), duration: 0)]))]))
            }
            // wand rack
            n.box(1.0, 0.7, 0.1, dark, 1.4, 1.2, -0.2)
            for k in 0..<5 {
                n.cyl(0.025, 0.55, Gfx.mat([0x6b4426, 0x2b1b12, 0xc9a96a, 0x8a3b12, 0x4a3220][k], r: 0.5), 1.15 + CGFloat(k) * 0.12, 1.2, -0.12)
                n.ball(0.03, Gfx.mat(WZ.gold, m: 0.8), 1.15 + CGFloat(k) * 0.12, 1.5, -0.12)
            }
        case 2:
            // big bubbling cauldron on logs plus a shelf of flasks
            n.box(1.8, 0.2, 0.2, Gfx.mat(0x3a2410), 0, 0.1, 0.2).eulerAngles = SCNVector3(0, 0.5, 0)
            n.box(1.8, 0.2, 0.2, Gfx.mat(0x3a2410), 0, 0.12, 0.2).eulerAngles = SCNVector3(0, -0.5, 0)
            let fire = n.add(SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.5), Gfx.mat(0xff7a1a, e: 0xff5a00, eIntensity: 1.5), at: SCNVector3(0, 0.3, 0.2), shadow: false)
            WZ.flicker(fire)
            n.ball(0.85, iron, 0, 1.15, 0.2).scale = SCNVector3(1, 0.85, 1)
            n.add(SCNTorus(ringRadius: 0.72, pipeRadius: 0.09), iron, at: SCNVector3(0, 1.62, 0.2))
            let brew = n.cyl(0.7, 0.05, Gfx.mat(0x6fe34a, r: 0.1, e: 0x2faa20, eIntensity: 1.3), 0, 1.6, 0.2)
            WZ.flicker(brew)
            let bn = n.group("bubbles", 0, 0, 0.2)
            WZ.bubbles(bn, 0x9bff6a, radius: 0.8, y: 1.65, count: 6)
            let glow = SCNLight(); glow.type = .omni; glow.color = Gfx.color(0x6fe34a); glow.intensity = 120; glow.attenuationEndDistance = 5
            let gn = SCNNode(); gn.light = glow; gn.position = SCNVector3(0, 2.2, 0.8); n.addChildNode(gn)
            for s in [-1.0, 1.0] { n.cyl(0.07, 0.5, iron, CGFloat(s) * 0.6, 0.25, 0.5) }
            // shelf of flasks
            n.box(1.4, 0.08, 0.4, dark, 1.6, 1.6, -0.2)
            for (k, c) in ([0xe23b8a, 0x7be9ff, 0xffd24a] as [UInt32]).enumerated() {
                n.ball(0.16, Gfx.mat(c, r: 0.1, e: c, eIntensity: 0.7, alpha: 0.9), 1.15 + CGFloat(k) * 0.42, 1.8, -0.2)
                n.cyl(0.05, 0.2, Gfx.mat(0xcfe3f5, r: 0.1, alpha: 0.5), 1.15 + CGFloat(k) * 0.42, 2.0, -0.2)
            }
            n.cyl(0.05, 0.4, Gfx.mat(0xcfe3f5, r: 0.1, alpha: 0.5), -1.3, 0.2, 0.5)
            n.box(0.5, 0.35, 0.02, Gfx.mat(0xf3e8c8), -1.3, 0.7, -0.4).eulerAngles = SCNVector3(0, 0, 0.1)
        default:
            // owl post: pigeonholes, perched owl, floating letter, parcel
            n.box(2.6, 1.9, 0.5, dark, 0, 0.95, 0)
            for r in 0..<3 { for c in 0..<4 {
                n.box(0.5, 0.5, 0.45, Gfx.mat(0x1c1208), -0.95 + CGFloat(c) * 0.63, 0.35 + CGFloat(r) * 0.6, 0.05)
                if (r + c) % 2 == 0 { n.box(0.3, 0.04, 0.2, Gfx.mat(0xf3e8c8), -0.95 + CGFloat(c) * 0.63, 0.55 + CGFloat(r) * 0.6, 0.2).eulerAngles = SCNVector3(0, 0, 0.15) }
            } }
            n.cyl(0.04, 1.6, dark, 1.65, 0.8, 0.5)
            n.box(0.7, 0.06, 0.06, dark, 1.65, 1.6, 0.5)
            let (owl, wings) = WZ.owl(0xe8dcc4, scale: 0.9)
            owl.position = SCNVector3(1.65, 1.95, 0.5)
            owl.eulerAngles = SCNVector3(0, -0.5, 0)
            n.addChildNode(owl)
            WZ.bobbing(owl, 0.04, 1.4)
            _ = wings
            let env = n.group("letter", -0.5, 2.4, 0.6)
            env.box(0.5, 0.34, 0.03, Gfx.mat(0xf3e8c8), 0, 0, 0)
            env.ball(0.07, Gfx.mat(0xc8372d, r: 0.3, e: 0x601010), 0, 0, 0.03)
            env.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 7)))
            WZ.bobbing(env, 0.25, 1.5)
            n.box(0.6, 0.45, 0.5, Gfx.mat(0xb08a5a, r: 0.9), -1.7, 0.23, 0.9)
            n.box(0.62, 0.06, 0.1, Gfx.mat(0xe8dcc4), -1.7, 0.4, 0.9)
        }
    }
}

extension Rig {
    /// (top, bottom, accent) colours; `v` is a per-actor variant index.
    static func wizardOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        if captain { return (0x4b2a8a, 0x2a1f50, 0xf2c94c) }
        let tops = WZ.houses
        let accents: [UInt32] = [0xf2c94c, 0xe8e8e8, 0xf2c94c, 0x3a2a14]
        return (tops[v % 4], 0x2a2433, accents[v % 4])
    }

    /// Pointy hats, robes, beards etc. added to the head/body.
    static func wizardAccessories(captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let head = rig.head
        let hat = captain ? Gfx.mat(0x4b2a8a, r: 0.85) : Gfx.mat(0x2a2433, r: 0.85)
        let white = Gfx.mat(0xf2f2f2, r: 0.95)
        head.add(SCNSphere(radius: 0.32), captain ? white : hair, at: SCNVector3(0, 0.36, -0.04))
        // robe skirt, scarf and wand
        rig.body.add(SCNCone(topRadius: 0.36, bottomRadius: captain ? 0.55 : 0.5, height: 0.65), topM, at: SCNVector3(0, -0.12, 0))
        rig.body.add(SCNTorus(ringRadius: 0.3, pipeRadius: 0.07), accM, at: SCNVector3(0, 0.76, 0))
        rig.body.box(0.12, 0.34, 0.06, accM, 0.18, 0.62, 0.22)
        let wand = rig.handR.cyl(0.018, captain ? 0.6 : 0.46, Gfx.mat(0x4a2c17, r: 0.5), 0, 0, 0.26)
        wand.eulerAngles = SCNVector3(Float.pi / 2.4, 0, 0)
        let tip = rig.handR.ball(0.045, Gfx.mat(0xffe08a, e: 0xffd24a, eIntensity: 2.2), 0, 0.17, 0.5)
        tip.castsShadow = false
        WZ.bobbing(tip, 0.02, 0.4)
        // pointy hat with a wide brim and a floppy tip
        head.cyl(0.5, 0.05, hat, 0, 0.56, 0)
        let h = captain ? 1.0 : 0.75
        head.add(SCNCone(topRadius: 0.05, bottomRadius: 0.3, height: h), hat, at: SCNVector3(0, 0.56 + h / 2, 0))
        let tipN = head.add(SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.3), hat, at: SCNVector3(0.1, 0.56 + h + 0.08, 0))
        tipN.eulerAngles = SCNVector3(0, 0, -0.9)
        head.cyl(0.31, 0.08, accM, 0, 0.62, 0)
        if captain {
            for (i, p) in [(0.0, 0.2), (0.2, -0.5), (-0.2, 0.2)].enumerated() {
                _ = i
                head.ball(0.045, Gfx.mat(WZ.gold, e: WZ.gold, eIntensity: 1.4), CGFloat(p.0) * 0.6, 0.95 + CGFloat(p.1) * 0.3, 0.27)
            }
            // long, long beard and moustache
            head.add(SCNCone(topRadius: 0.24, bottomRadius: 0.03, height: 1.1), white, at: SCNVector3(0, -0.2, 0.2))
            head.box(0.4, 0.14, 0.14, white, 0, 0.12, 0.26, round: 0.05)
            head.box(0.2, 0.06, 0.1, white, -0.12, 0.17, 0.3, round: 0.03).eulerAngles = SCNVector3(0, 0, 0.3)
            head.box(0.2, 0.06, 0.1, white, 0.12, 0.17, 0.3, round: 0.03).eulerAngles = SCNVector3(0, 0, -0.3)
            head.box(0.14, 0.05, 0.05, white, -0.11, 0.42, 0.3)
            head.box(0.14, 0.05, 0.05, white, 0.11, 0.42, 0.3)
            for x in [-0.11, 0.11] { head.add(SCNTorus(ringRadius: 0.06, pipeRadius: 0.012), Gfx.mat(WZ.gold, m: 0.8), at: SCNVector3(CGFloat(x), 0.34, 0.285)) }
        } else {
            head.box(0.12, 0.03, 0.04, Gfx.mat(0x8a3b3b, r: 0.5), 0, 0.2, 0.28)
            // a lightning-ish forehead scar? no, original: a tiny star mark
            head.box(0.05, 0.05, 0.02, Gfx.mat(WZ.gold, e: WZ.gold), 0.1, 0.5, 0.28)
            if number % 3 == 0 { head.add(SCNTorus(ringRadius: 0.06, pipeRadius: 0.012), Gfx.mat(0x2a2a30, m: 0.8), at: SCNVector3(-0.11, 0.34, 0.285)) }
        }
    }

    /// Context-usage gauge shown on a worker: a potion vial on the back (set `mv.fill`).
    func wizardGauge(_ figure: SCNNode, metal: SCNMaterial) {
        let g = body.group("gauge", 0.3, 0.42, -0.32)
        g.cyl(0.16, 0.76, Gfx.mat(0xcfe3f5, r: 0.05, alpha: 0.35), 0, 0, 0)
        g.cyl(0.1, 0.1, metal, 0, 0.42, 0)
        g.ball(0.07, Gfx.mat(0x8a5a35), 0, 0.5, 0)
        let f = g.add(SCNCylinder(radius: 0.14, height: 0.64), tinted(0xb48cf2, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
        bottomAnchored(f, height: 0.64)
        mv.fill = f
    }

    /// Small floating letter shown for approval requests: "an owl has brought mail!".
    func wizardBeacon(_ beacon: SCNNode, metal: SCNMaterial) {
        beacon.box(0.3, 0.2, 0.03, Gfx.mat(0xf3e8c8, e: 0x403018, eIntensity: 0.6), 0, 0, 0)
        beacon.ball(0.05, tinted(0xff4a3a, e: true), 0, 0, 0.03)
        beacon.add(SCNTorus(ringRadius: 0.2, pipeRadius: 0.012), metal, at: SCNVector3(0, 0, 0))
        beacon.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
    }
}

extension Stage {
    /// (background, ambient, ambient intensity, key, key intensity, fill): warm candlelight over a night castle.
    static func wizardLighting() -> (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) { (0x0b0814, 0xa88a8c, 520, 0xffd9a0, 1250, 0x7f6ad8) }
    /// Work animation per tool kind (0 read, 1 write, 2 run, 3 other).
    static func wizardMotion(_ kind: Int) -> Motion { [.scan, .hammer, .stir, .type][kind % 4] }
}

extension RoomSim {
    /// A spell backfires: one apprentice is turned into a frog, everyone panics, the headwizard hurries over.
    func wizardFailure(t: Double) {
        let lines = ["Wrong spell! 💨", "Not the frog one!", "Who sneezed?!", "My cauldron! 🫧"]
        for s in subs where s.phase != .leaving {
            mutate(s.id) { $0.mood = .panic; $0.moodUntil = t + 2.2; $0.say = lines.randomElement(); $0.sayUntil = t + 2.4 }
        }
        guard let v = victim() else {
            say("captain", "Oops, that was supposed to be a rabbit!", t: t)
            return
        }
        mutate(v.id) { $0.mood = .sick; $0.moodUntil = t + 12; $0.say = "Ribbit! 🐸"; $0.sayUntil = t + 4 }
        captain.pending = v.id
        captain.chatPartner = nil
        captain.route = [CGPoint(x: v.pos.x + (v.pos.x > 160 ? 14 : -14), y: v.pos.y + 4)]
        captain.pauseUntil = t + 1
        captain.say = "Hold still, I know the counter-spell!"
        captain.sayUntil = t + 2.8
    }
}



extension MetricsFmt {
    static var wizardMedal: String { "🏆" }
}

extension RoomSign {
    /// Captain age sign; `minutes` is whole minutes, `txt` the formatted age.
    static func wizardAgeSign(age: Double, days: Int, minutes: Int, jersey: Int, txt: String) -> NSImage {
        Gfx.sign("🪄 Term day \(days)", "Class in session \(txt)", accent: 0xb48cf2)
    }
}

extension SoundCenter {
    /// Original synthesized chimes: glassy bell arpeggios; the failure is a comic descending "pop-wobble".
    nonisolated static func wizardSynth(_ kind: Kind) -> Data? {
        func seq(_ notes: [(Double, Double)], gap: Double = 0.09, decay: Double = 5) -> [Float] {
            var out: [Float] = []
            for (f, d) in notes {
                var s = tone(freq: { _ in f }, dur: d, decay: decay)
                let h = tone(freq: { _ in f * 2.76 }, dur: d, decay: decay * 1.8)
                for i in s.indices where i < h.count { s[i] = s[i] * 0.8 + h[i] * 0.2 }
                out += s
                out += [Float](repeating: 0, count: Int(gap * 22050))
            }
            return out
        }
        switch kind {
        case .spawn: return wav(seq([(880, 0.12), (1319, 0.22)], gap: 0.02))
        case .success: return wav(seq([(659, 0.14), (784, 0.14), (988, 0.14), (1319, 0.4)], gap: 0.0))
        case .failure: return wav(tone(freq: { 520 - 380 * $0 + 40 * sin($0 * 55) }, dur: 0.55, decay: 2.5, saw: true) + tone(freq: { _ in 1400 }, dur: 0.08, decay: 12))
        case .alert: return wav(seq([(1175, 0.18), (1568, 0.3)], gap: 0.04, decay: 4))
        }
    }
}
