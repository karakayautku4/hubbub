import AppKit
import SceneKit

// Galactic Fleet: everything theme-specific lives here. Shared files only call these entry points.
// Scaffold: currently mirrors the Space Station theme; replace the bodies, keep the signatures.

extension Environments {
    private static func glowTube(_ n: SCNNode, _ hex: UInt32, len: CGFloat, r: CGFloat = 0.04, at p: SCNVector3, roll: CGFloat = 0) -> SCNNode {
        let t = n.add(SCNCylinder(radius: r, height: len), Gfx.mat(hex, r: 0.2, e: hex, eIntensity: 1.6), at: p, shadow: false)
        t.eulerAngles = SCNVector3(0, 0, roll)
        return t
    }

    /// Parked fighter: wedge fuselage, split wings, cockpit and engine glow.
    private static func fighter(_ root: SCNNode, x: CGFloat, z: CGFloat, yaw: CGFloat, stripe: UInt32) {
        let g = root.group("prop:fighter", x, 0, z)
        g.eulerAngles = SCNVector3(0, yaw, 0)
        let hull = Gfx.mat(0xb9bfc7, r: 0.45, m: 0.5)
        let dark = Gfx.mat(0x3b4350, r: 0.5, m: 0.6)
        for sx in [-0.4, 0.4] as [CGFloat] { g.box(0.14, 0.7, 0.5, dark, sx * 1.05, 0.42, 0) }
        g.box(0.9, 0.5, 2.2, hull, 0, 0.9, 0, round: 0.1)
        let nose = g.add(SCNCone(topRadius: 0.02, bottomRadius: 0.38, height: 1.4), hull, at: SCNVector3(0, 0.9, 1.7))
        nose.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        g.ball(0.3, Gfx.mat(0x7be9ff, r: 0.05, m: 0.3, e: 0x155a77, eIntensity: 0.7, alpha: 0.8), 0, 1.22, 0.2)
        for sx in [-1.0, 1.0] as [CGFloat] {
            let w = g.box(2.4, 0.07, 1.1, hull, sx * 1.55, 0.9, -0.3, round: 0.02)
            w.eulerAngles = SCNVector3(0, 0, sx * 0.28)
            g.box(0.5, 0.075, 1.12, Gfx.mat(stripe, r: 0.5), sx * 2.3, 0.9 + 0.57 * 0.0 + 0.3, -0.3).eulerAngles = SCNVector3(0, 0, sx * 0.28)
            g.cyl(0.05, 1.3, dark, sx * 2.45, 1.05, 0.5).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            let e = g.cyl(0.2, 0.15, Gfx.mat(0x5ec8ff, e: 0x5ec8ff, eIntensity: 1.8), sx * 0.3, 0.9, -1.15)
            e.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            pulse(e, 0.15, 0.7)
        }
    }

    static func galactic(_ root: SCNNode) {
        let steel = Gfx.mat(0x6d7684, r: 0.5, m: 0.7)
        let panel = Gfx.mat(0x3d4552, r: 0.55, m: 0.55)
        floor(root, Gfx.texMat(Gfx.tiles(0x4a4f58, 0x42474f, grout: 0x1c2027, cells: 5), r: 0.4, m: 0.5, repeatX: 5, repeatY: 2))
        // hazard stripe lane along the hangar mouth
        let hazard = Gfx.texMat(Gfx.image(256, 32) { c in
            c.setFillColor(Gfx.color(0x20232a).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 32))
            c.setFillColor(Gfx.color(0xffb020).cgColor)
            for i in stride(from: -32, to: 288, by: 32) {
                c.move(to: CGPoint(x: i, y: 0)); c.addLine(to: CGPoint(x: i + 16, y: 0)); c.addLine(to: CGPoint(x: i + 48, y: 32)); c.addLine(to: CGPoint(x: i + 32, y: 32)); c.fillPath()
            }
        }, r: 0.7, repeatX: 8, repeatY: 1)
        root.box(38, 0.04, 0.5, hazard, 0, 0.01, 8.4)
        // back wall with ribs
        root.box(38, 7, 0.4, Gfx.mat(0x2b313c, r: 0.6, m: 0.5), 0, 3.5, -0.4)
        for x in stride(from: -17.0, through: 17.0, by: 3.4) {
            root.box(0.3, 7, 0.3, panel, x, 3.5, -0.15)
            root.box(0.5, 0.35, 0.34, Gfx.mat(0xe0742a, r: 0.5), x, 0.9, -0.12)
        }
        root.box(38, 0.12, 0.2, Gfx.mat(0xe0742a, e: 0xe0742a, eIntensity: 0.5), 0, 0.45, -0.1)
        // hyperspace window: streaking stars scroll past
        let streakTex = Gfx.image(512, 256) { c in
            c.setFillColor(Gfx.color(0x050824).cgColor); c.fill(CGRect(x: 0, y: 0, width: 512, height: 256))
            var g = Gfx.RNG(s: 77)
            for _ in 0..<90 {
                let len = 30 + g.next() * 150, y = g.next() * 256, x = g.next() * 512
                c.setFillColor(Gfx.color(g.next() > 0.5 ? 0xbfe6ff : 0xffffff, 0.35 + g.next() * 0.6).cgColor)
                c.fill(CGRect(x: x, y: y, width: len, height: 1 + g.next() * 2.2))
            }
        }
        let wm = Gfx.texMat(streakTex, repeatX: 1.5, repeatY: 1, emissive: true)
        wm.diffuse.wrapS = .repeat
        for x in [-9.5, 9.5] as [CGFloat] {
            root.box(7.4, 3.4, 0.1, wm, x, 4.2, -0.16)
            root.box(7.8, 0.2, 0.25, steel, x, 2.45, -0.1)
            root.box(7.8, 0.2, 0.25, steel, x, 5.95, -0.1)
            for k in -1...1 { root.box(0.14, 3.6, 0.25, steel, x + CGFloat(k) * 3.8, 4.2, -0.1) }
        }
        let scroll = SCNAction.repeatForever(.customAction(duration: 6) { n, t in
            guard let m = n.geometry?.firstMaterial else { return }
            m.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(1.5, 1, 1), SCNMatrix4MakeTranslation(t / 6, 0, 0))
        })
        root.enumerateChildNodes { n, _ in if n.geometry?.firstMaterial === wm { n.runAction(scroll) } }
        // command bridge banner + glowing emblem (original: a ringed star)
        root.box(5, 1.1, 0.12, Gfx.mat(0x7a1f24, r: 0.7), 0, 5.4, -0.15)
        root.add(SCNTorus(ringRadius: 0.38, pipeRadius: 0.05), Gfx.mat(0xffd24a, e: 0xffd24a, eIntensity: 0.8), at: SCNVector3(0, 5.4, -0.05), shadow: false).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        root.ball(0.12, Gfx.mat(0xffd24a, e: 0xffd24a), 0, 5.4, -0.05)
        // alarm beacons (idle: slow amber pulse)
        for x in [-4.5, 4.5] as [CGFloat] {
            let b = root.ball(0.2, Gfx.mat(0xff9a2a, e: 0xff7a00, eIntensity: 1.2), x, 6.3, 0)
            b.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 1.2), .fadeOpacity(to: 1, duration: 1.2)])))
        }
        // blast door (left, where the crew arrives)
        let door = root.group("prop:hangardoor", -15.8, 0, 3.5)
        door.box(0.4, 3.6, 3.8, steel, 0, 1.8, 0)
        door.box(0.1, 3.0, 1.5, Gfx.mat(0x14181f, m: 0.5), 0.22, 1.6, 0)
        for k in 0..<4 { door.box(0.06, 0.18, 3.6, Gfx.mat(0xffb020, r: 0.5), 0.23, 0.25 + CGFloat(k) * 0.9, 0) }
        // parked fighters in the back corners
        fighter(root, x: -11.6, z: 0.0, yaw: CGFloat.pi / 2 * 0.15, stripe: 0xd8402e)
        fighter(root, x: 11.8, z: 0.0, yaw: -CGFloat.pi / 2 * 0.15, stripe: 0x3d7de0)
        // holo-table with spinning wireframe globe
        let t = root.group("prop:holotable", 0, 0, 0.7)
        t.cyl(0.9, 0.22, steel, 0, 0.11, 0)
        t.cyl(0.35, 0.7, panel, 0, 0.55, 0)
        t.cyl(1.25, 0.14, Gfx.mat(0x2d3542, r: 0.4, m: 0.7), 0, 0.95, 0)
        t.cyl(1.1, 0.04, Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 1.1, alpha: 0.7), 0, 1.04, 0)
        let wire = Gfx.mat(0x7be9ff, r: 0.1, e: 0x2bb6e6, eIntensity: 1.4, alpha: 0.35)
        wire.fillMode = .lines
        let globe = t.add(SCNSphere(radius: 0.65), wire, at: SCNVector3(0, 1.8, 0), shadow: false)
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 14)))
        let cone = t.add(SCNCone(topRadius: 0.65, bottomRadius: 0.2, height: 0.75), Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 0.6, alpha: 0.14), at: SCNVector3(0, 1.4, 0), shadow: false)
        cone.opacity = 0.7
        // rolling droid patrolling the foreground
        let droid = root.group("prop:droid", -6, 0, 9.4)
        droid.cyl(0.04, 0.4, steel, 0, 0.5, 0)
        droid.ball(0.38, Gfx.mat(0xeef0f3, r: 0.35, m: 0.2), 0, 0.42, 0)
        droid.add(SCNSphere(radius: 0.3), Gfx.mat(0xf2793a, r: 0.35, m: 0.2), at: SCNVector3(0, 0.82, 0))
        droid.ball(0.1, Gfx.mat(0x111111, r: 0.1, e: 0x7be9ff, eIntensity: 1), 0, 0.88, 0.26)
        droid.cyl(0.02, 0.28, steel, 0.12, 1.2, 0)
        droid.ball(0.04, Gfx.mat(0xff4a3a, e: 0xff4a3a), 0.12, 1.36, 0)
        let wheel = droid.group("wheel", 0, 0, 0)
        wheel.add(SCNTorus(ringRadius: 0.38, pipeRadius: 0.05), Gfx.mat(0x2a2e36, r: 0.8), at: SCNVector3(0, 0.12, 0)).eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        droid.runAction(.repeatForever(.sequence([
            .move(to: SCNVector3(6, 0, 9.4), duration: 14),
            .rotateTo(x: 0, y: CGFloat.pi, z: 0, duration: 0.6, usesShortestUnitArc: true),
            .move(to: SCNVector3(-6, 0, 9.4), duration: 14),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.6, usesShortestUnitArc: true)])))
        droid.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.06, z: 0, duration: 0.25), .moveBy(x: 0, y: -0.06, z: 0, duration: 0.25)])), forKey: "bob")
        // laser-sword rack on the wall: glowing blue/red tubes in hilts
        let rack = root.group("prop:swordrack", -4.2, 0, 0.05)
        rack.box(2.2, 1.5, 0.12, panel, 0, 2.5, -0.1, round: 0.03)
        for (i, c) in [0x3da8ff, 0xff3a3a, 0x3dff8a].enumerated() {
            let x = -0.7 + CGFloat(i) * 0.7
            rack.cyl(0.07, 0.4, Gfx.mat(0x9aa0aa, r: 0.3, m: 0.9), x, 2.05, 0.0)
            _ = glowTube(rack, UInt32(c), len: 1.0, r: 0.045, at: SCNVector3(x, 2.75, 0))
        }
        coffee(root, .galactic)
    }

    /// Prop for one work station; `kind` 0 sensors, 1 droid workshop, 2 hyperdrive, 3 holo-comms (see `Theme.stations`).
    static func galacticStation(_ kind: Int, _ n: SCNNode) {
        let tint: UInt32 = 0xffa63a
        let bodyM = Gfx.mat(0x4a525e, r: 0.45, m: 0.6)
        let scr = { (bg: UInt32, fg: UInt32, s: Int) in Gfx.texMat(Gfx.screen(bg, fg, seed: UInt64(40 + kind * 5 + s), style: s), emissive: true) }
        switch kind {
        case 0:
            // holo-map table
            n.cyl(0.9, 0.9, bodyM, 0, 0.45, 0)
            n.cyl(0.8, 0.05, Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 1.1, alpha: 0.8), 0, 0.93, 0)
            let w = Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 1.4, alpha: 0.4); w.fillMode = .lines
            let m = n.add(SCNSphere(radius: 0.45), w, at: SCNVector3(0, 1.6, 0), shadow: false)
            m.runAction(.repeatForever(.rotateBy(x: 0.3, y: CGFloat.pi * 2, z: 0, duration: 9)))
            for (x, z) in [(-0.4, 0.2), (0.3, -0.3), (0.5, 0.3)] as [(CGFloat, CGFloat)] { n.ball(0.05, Gfx.mat(0xff4a3a, e: 0xff4a3a), x, 1.0, z) }
        case 1:
            // droid repair bench with a half-assembled droid and a wrench
            n.box(2.4, 0.8, 0.9, bodyM, 0, 0.4, 0, round: 0.04)
            n.box(2.4, 0.06, 1.0, Gfx.mat(0xb0b8c4, m: 0.8), 0, 0.83, 0)
            n.ball(0.3, Gfx.mat(0xeef0f3, r: 0.35, m: 0.2), -0.4, 1.15, 0)
            n.add(SCNSphere(radius: 0.2), Gfx.mat(0xf2793a, r: 0.35), at: SCNVector3(-0.4, 1.5, 0))
            n.ball(0.07, Gfx.mat(0x111111, e: 0x7be9ff, eIntensity: 1), -0.4, 1.52, 0.17)
            n.box(0.7, 0.5, 0.05, scr(0x1a0d08, 0xf2661f, 1), 0.7, 1.3, -0.3)
            let sp = n.ball(0.06, Gfx.mat(0xffe08a, e: 0xffd24a, eIntensity: 2), -0.1, 1.2, 0.25)
            sp.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0, duration: 0.15), .wait(duration: 0.9), .fadeOpacity(to: 1, duration: 0.05)])))
            n.box(0.5, 0.05, 0.08, Gfx.mat(0xc8372d, m: 0.6), 0.2, 0.9, 0.25)
        case 2:
            // blaster range: target + blaster
            n.box(2.2, 0.9, 0.8, bodyM, 0, 0.45, 0.2, round: 0.04)
            n.box(0.5, 0.18, 0.12, Gfx.mat(0x2a2f38, r: 0.4, m: 0.7), -0.6, 0.99, 0.3)
            n.box(0.12, 0.3, 0.1, Gfx.mat(0x2a2f38, r: 0.4, m: 0.7), -0.8, 0.82 + 0.15, 0.3)
            n.cyl(0.04, 1.4, bodyM, 0.5, 1.6, -0.3)
            let tgt = n.cyl(0.5, 0.06, Gfx.mat(0xf2f2f2), 0.5, 2.1, -0.3); tgt.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            let ring = n.cyl(0.3, 0.07, Gfx.mat(0xd8402e, e: 0x8a1a10), 0.5, 2.1, -0.28); ring.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
            let bolt = glowTube(n, 0xff3a3a, len: 0.4, r: 0.03, at: SCNVector3(-0.1, 1.0, 0.3), roll: CGFloat.pi / 2)
            bolt.runAction(.repeatForever(.sequence([.move(to: SCNVector3(0.5, 1.0, 0.3), duration: 0.8), .fadeOut(duration: 0.1), .move(to: SCNVector3(-0.1, 1.0, 0.3), duration: 0.01), .fadeIn(duration: 0.1), .wait(duration: 1)])))
        default:
            // comms: dish and hologram bust
            n.box(2.0, 0.9, 0.8, bodyM, 0, 0.45, 0, round: 0.04)
            n.cyl(0.4, 0.04, Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 1, alpha: 0.7), -0.3, 0.92, 0.1)
            let h = n.ball(0.26, { let m = Gfx.mat(0x7be9ff, e: 0x2bb6e6, eIntensity: 1.4, alpha: 0.4); m.fillMode = .lines; return m }(), -0.3, 1.35, 0.1)
            h.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 4)))
            let dish = n.add(SCNCone(topRadius: 0.55, bottomRadius: 0.05, height: 0.3), Gfx.mat(0xc9d0d8, r: 0.3, m: 0.7), at: SCNVector3(0.6, 1.5, 0))
            dish.eulerAngles = SCNVector3(-0.6, 0.4, 0)
            n.cyl(0.05, 0.7, bodyM, 0.6, 1.0, 0)
            n.ball(0.07, Gfx.mat(tint, e: tint, eIntensity: 1.5), 0.6, 1.8, 0)
        }
    }
}

extension Rig {
    /// (top, bottom, accent) colours; `v` is a per-actor variant index.
    static func galacticOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        let suits: [UInt32] = [0xe9e4d8, 0xdad6c8, 0xe6dfd0, 0xd5dbe0]
        return captain ? (0x4a5568, 0x252b36, 0xffd24a) : (suits[v % suits.count], 0xd9672a, 0xff9a2a)
    }
    /// Helmets, capes, armour etc. added to the head/body.
    static func galacticAccessories(captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let head = rig.head
        if captain {
            // peaked admiral cap, epaulettes, medals and a belt-clipped laser sword
            let cap = Gfx.mat(0x2a3140, r: 0.5)
            head.cyl(0.34, 0.1, cap, 0, 0.58, 0)
            head.box(0.42, 0.04, 0.24, Gfx.mat(0x12151c, r: 0.3), 0, 0.54, 0.3)
            head.cyl(0.27, 0.2, cap, 0, 0.67, 0)
            head.ball(0.05, Gfx.mat(0xffd24a, r: 0.2, m: 0.9, e: 0x6a4a00), 0, 0.68, 0.27)
            for sx in [-0.38, 0.38] as [CGFloat] { rig.body.box(0.2, 0.06, 0.26, Gfx.mat(0xffd24a, r: 0.3, m: 0.8), sx, 0.78, 0) }
            for k in 0..<3 { rig.body.box(0.07, 0.07, 0.03, Gfx.mat([0xff3a3a, 0x3da8ff, 0xffd24a][k], e: [0x701010, 0x103a70, 0x6a4a00][k]), -0.2 + CGFloat(k) * 0.09, 0.55, 0.22) }
            rig.body.cyl(0.04, 0.2, Gfx.mat(0x9aa0aa, r: 0.3, m: 0.9), 0.3, 0.1, 0.18)
            rig.body.cyl(0.03, 0.5, Gfx.mat(0x3da8ff, e: 0x3da8ff, eIntensity: 1.6), 0.3, 0.45, 0.18)
        } else {
            // cadet helmet with a tinted visor and a stripe
            let shell = Gfx.mat(0xf2f2ee, r: 0.3, m: 0.2)
            head.add(SCNSphere(radius: 0.34), shell, at: SCNVector3(0, 0.34, -0.03))
            head.box(0.46, 0.14, 0.12, Gfx.mat(0x16202e, r: 0.05, m: 0.6, e: 0x0b2a44, eIntensity: 0.6), 0, 0.32, 0.27, round: 0.05)
            head.box(0.08, 0.04, 0.5, accM, 0, 0.67, 0)
            rig.body.box(0.3, 0.2, 0.04, Gfx.mat(0x3a4250, r: 0.4, m: 0.5), 0, 0.4, 0.21)
            rig.body.box(0.08, 0.05, 0.03, Gfx.mat(0x3cf0a0, e: 0x3cf0a0), -0.06, 0.42, 0.24)
            if number % 3 == 0 { rig.body.cyl(0.03, 0.4, Gfx.mat(0xff3a3a, e: 0xff3a3a, eIntensity: 1.5), 0.3, 0.12, 0.18) }
        }
    }
    /// Context-usage gauge shown on a worker (set `mv.fill`).
    func galacticGauge(_ figure: SCNNode, metal: SCNMaterial) {
        let g = body.group("gauge", 0.3, 0.42, -0.32)
        g.cyl(0.16, 0.76, metal, 0, 0, 0)
        g.ball(0.16, metal, 0, 0.38, 0)
        let f = g.add(SCNCylinder(radius: 0.17, height: 0.64), tinted(0x3ddc84, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
        bottomAnchored(f, height: 0.64)
        mv.fill = f
    }
    /// Small beacon shown for approval requests.
    func galacticBeacon(_ beacon: SCNNode, metal: SCNMaterial) {
        beacon.cyl(0.04, 0.2, metal, 0, -0.1, 0)
        beacon.ball(0.13, tinted(0xff8a2a, e: true), 0, 0.05, 0)
    }
}

extension Stage {
    /// (background, ambient, ambient intensity, key, key intensity, fill).
    static func galacticLighting() -> (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) { (0x05070d, 0x9aa4c4, 480, 0xfff0dc, 1500, 0xff8a3a) }
    /// Work animation per tool kind (0 read, 1 write, 2 run, 3 other).
    static func galacticMotion(_ kind: Int) -> Motion { [.scan, .hammer, .type, .type][kind % 4] }
}

extension RoomSim {
    /// Failure effect (red alert). Helpers `mutate`, `victim`, `panicAll` are available.
    func galacticFailure(t: Double) {
        let lines = ["Why is the engine humming like that?! 😬", "Red alert! 🚨", "Is that button supposed to blink?!"]
        for s in subs where s.phase != .leaving {
            mutate(s.id) { $0.mood = .panic; $0.moodUntil = t + 2.2; $0.say = lines.randomElement(); $0.sayUntil = t + 2.4 }
        }
        guard let v = victim() else {
            captain.say = "Bzzt! My helper bot exploded 💥"; captain.sayUntil = t + 3
            return
        }
        // the malfunctioning droid-handler spins and sparks
        mutate(v.id) { $0.mood = .dizzy; $0.moodUntil = t + 8; $0.say = "Bzzzt! ⚡🤖 *spins*"; $0.sayUntil = t + 4 }
        captain.say = "Who fixed the bot?! 😤"
        captain.sayUntil = t + 3
    }
}



extension MetricsFmt {
    static var galacticMedal: String { "🎖️" }
}

extension RoomSign {
    /// Captain age sign; `minutes` is whole minutes, `txt` the formatted age.
    static func galacticAgeSign(age: Double, days: Int, minutes: Int, jersey: Int, txt: String) -> NSImage {
        Gfx.sign("🌌 Stardate \(days)", "T+ \(txt)", accent: 0xff9a2a)
    }
}

extension SoundCenter {
    /// WAV data for this theme, or nil to use the system sound.
    nonisolated static func galacticSynth(_ kind: Kind) -> Data? {
        switch kind {
        case .spawn: return wav(tone(freq: { 300 + 1400 * $0 / 0.25 }, dur: 0.25, decay: 4, attack: 0.03))
        case .success: return wav(tone(freq: { $0 < 0.15 ? 660 : 990 }, dur: 0.4, decay: 3, trem: 12))
        case .failure: return wav(tone(freq: { 880 - 700 * min(1, $0 / 0.7) + 25 * sin($0 * 90) }, dur: 0.7, decay: 1.2, trem: 9, saw: true))
        case .alert: return wav(tone(freq: { fmod($0, 0.3) < 0.15 ? 740 : 520 }, dur: 0.6, decay: 1, saw: true))
        }
    }
}
