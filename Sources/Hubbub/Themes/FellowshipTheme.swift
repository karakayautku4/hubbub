import AppKit
import SceneKit

// Hillside Quest: a golden-hour hillside village, a tavern, a distant fiery mountain and a wise guide
// leading sturdy adventurers who are all a bit too fond of one lucky golden charm. Original parody art.

extension Environments {
    /// Room, floor, walls, ambient props and animated set pieces.
    static func fellowship(_ root: SCNNode) {
        fellowshipSky(root)
        floor(root, Gfx.texMat(Gfx.speckle(0x78a53a, 0x628f30, count: 2600, size: 4), r: 0.98, repeatX: 6, repeatY: 3))
        root.box(38, 0.05, 1.6, Gfx.mat(0xa67c48, r: 0.95), 0, 0.02, 7.6)
        for i in 0..<26 {
            let x = -17.5 + CGFloat(i) * 1.4 + CGFloat(i % 3) * 0.1
            let st = root.cyl(0.22 + CGFloat(i % 2) * 0.08, 0.03, Gfx.mat(0x9a8a70, r: 1), x, 0.04, 8.7 + CGFloat(i % 3) * 0.3)
            st.castsShadow = false
        }
        fellowshipMountain(root)
        fellowshipHills(root)
        fellowshipTavern(root)
        fellowshipCharmStump(root)
        fellowshipEagle(root)
        fellowshipGarden(root)
    }

    private static func fellowshipSky(_ root: SCNNode) {
        let sky = Gfx.image(8, 256) { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [Gfx.color(0xffd48a).cgColor, Gfx.color(0xf9a56a).cgColor, Gfx.color(0xc97a9a).cgColor, Gfx.color(0x6f6fb5).cgColor] as CFArray,
                               locations: [0, 0.28, 0.6, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
        root.add(SCNPlane(width: 140, height: 44), Gfx.texMat(sky, emissive: true), at: SCNVector3(0, 10, -22), shadow: false)
        let sun = root.ball(2.2, Gfx.mat(0xfff0b0, e: 0xffe08a, eIntensity: 1.5), -9, 3.2, -20.5)
        sun.castsShadow = false
        let halo = root.ball(4.2, Gfx.mat(0xffc870, e: 0xffb050, eIntensity: 1, alpha: 0.28), -9, 3.2, -20.4)
        halo.castsShadow = false
        for (i, c) in [(-16.0, 7.5, 1.0), (-2.0, 9.5, 0.8), (13.0, 8.2, 1.2), (22.0, 6.2, 0.7)].enumerated() {
            let cloud = root.group("cloud", c.0, c.1, -19)
            for k in 0..<4 {
                let b = cloud.ball(1.0 * c.2, Gfx.mat(0xffd9c0, r: 1, e: 0xe88a7a, eIntensity: 0.55), CGFloat(k) * 1.3 * c.2 - 2, CGFloat(k % 2) * 0.3, 0)
                b.scale = SCNVector3(1.5, 0.55, 0.7)
                b.castsShadow = false
            }
            let d = 4.0 + Double(i) * 1.2
            cloud.runAction(.repeatForever(.sequence([.moveBy(x: 3, y: 0, z: 0, duration: 40 + Double(i) * 6), .moveBy(x: -3, y: 0, z: 0, duration: 40 + Double(i) * 6)])))
            _ = d
        }
    }

    private static func fellowshipMountain(_ root: SCNNode) {
        let rock = Gfx.mat(0x5a3d4e, r: 1)
        let far = root.add(SCNCone(topRadius: 0.7, bottomRadius: 8.5, height: 9), rock, at: SCNVector3(5, 3.4, -15), shadow: false)
        far.name = "prop:volcano"
        root.add(SCNCone(topRadius: 0, bottomRadius: 6, height: 6), Gfx.mat(0x7a5566, r: 1), at: SCNVector3(-3, 2.4, -14), shadow: false)
        root.add(SCNCone(topRadius: 0, bottomRadius: 5, height: 5), Gfx.mat(0x6b4a5e, r: 1), at: SCNVector3(14, 1.8, -13), shadow: false)
        let lava = root.add(SCNCone(topRadius: 0.78, bottomRadius: 1.4, height: 1.1), Gfx.mat(0xff6a1a, e: 0xff5a00, eIntensity: 1.6), at: SCNVector3(5, 7.6, -15), name: "prop:volcano", shadow: false)
        pulse(lava, 0.07, 0.8)
        let glow = root.ball(2.1, Gfx.mat(0xff7a2a, e: 0xff6a1a, eIntensity: 1, alpha: 0.3), 5, 8.3, -14.6)
        glow.castsShadow = false
        pulse(glow, 0.15, 1.4)
        for k in 0..<3 {
            let puff = root.ball(0.7, Gfx.mat(0x6a5a66, r: 1, alpha: 0.55), 5, 8.6, -15)
            puff.castsShadow = false
            let dur = 6.0
            puff.runAction(.sequence([.wait(duration: Double(k) * 2), .repeatForever(.sequence([
                .group([.moveBy(x: 1.6, y: 3.2, z: 0, duration: dur), .fadeOut(duration: dur), .scale(to: 2.2, duration: dur)]),
                .group([.moveBy(x: -1.6, y: -3.2, z: 0, duration: 0), .fadeIn(duration: 0), .scale(to: 1, duration: 0)])]))]))
        }
        for k in 0..<4 {
            let e = root.ball(0.07, Gfx.mat(0xffc060, e: 0xffa030, eIntensity: 1.5), 5, 8.5, -14.4)
            e.castsShadow = false
            let dx = CGFloat(k - 2) * 0.5
            e.runAction(.sequence([.wait(duration: Double(k) * 0.7), .repeatForever(.sequence([
                .group([.moveBy(x: dx, y: 1.8, z: 0.3, duration: 2.2), .fadeOut(duration: 2.2)]),
                .group([.moveBy(x: -dx, y: -1.8, z: -0.3, duration: 0), .fadeIn(duration: 0)])]))]))
        }
    }

    private static func roundDoor(_ root: SCNNode, hill c: SCNVector3, radius r: CGFloat, dx: CGFloat, y: CGFloat, size: CGFloat, color: UInt32) {
        let dy = y - CGFloat(c.y)
        let z = CGFloat(c.z) + sqrt(r * r - dx * dx - dy * dy) + 0.12
        let g = root.group("door", CGFloat(c.x) + dx, y, z)
        let d = g.cyl(size, 0.12, Gfx.mat(color, r: 0.7), 0, 0, 0)
        d.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        let frame = g.add(SCNTorus(ringRadius: size, pipeRadius: 0.07), Gfx.mat(0x6b4a2f, r: 0.9), at: SCNVector3(0, 0, 0.04))
        frame.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        g.ball(0.07, Gfx.mat(0xffd54a, r: 0.2, m: 1, e: 0x8a6a10), size * 0.45, -size * 0.1, 0.1)
        for k in -1...1 { g.box(0.05, size * 1.5, 0.03, Gfx.mat(0x3a2a1a, r: 0.8), CGFloat(k) * size * 0.5, 0, 0.07) }
        let lamp = g.group("lamp", -size - 0.35, size * 0.5, 0.15)
        lamp.box(0.04, 0.4, 0.04, Gfx.mat(0x3a2a1a), 0, -0.2, 0)
        lamp.ball(0.13, Gfx.mat(0xffd070, e: 0xffb040, eIntensity: 1.4), 0, 0.05, 0)
        let patch = g.box(size * 2.6, 0.05, 0.7, Gfx.mat(0x7a5a38, r: 1), 0, -size - 0.1, 0.35)
        patch.castsShadow = false
    }

    private static func fellowshipHills(_ root: SCNNode) {
        let turf = Gfx.mat(0x7da342, r: 1)
        let turf2 = Gfx.mat(0x6a9240, r: 1)
        let h1 = SCNVector3(-12, -2.5, -6.5), h2 = SCNVector3(-1.5, -3.2, -9)
        root.add(SCNSphere(radius: 6), turf, at: h1, shadow: false)
        root.add(SCNSphere(radius: 5.6), turf2, at: h2, shadow: false)
        root.add(SCNSphere(radius: 7), Gfx.mat(0x5f8a3e, r: 1), at: SCNVector3(-21, -3.5, -5), shadow: false)
        root.add(SCNSphere(radius: 6), Gfx.mat(0x6f9a46, r: 1), at: SCNVector3(10, -4, -9.5), shadow: false)
        roundDoor(root, hill: h1, radius: 6, dx: -2.3, y: 0.9, size: 0.85, color: 0x3f8f5a)
        roundDoor(root, hill: h1, radius: 6, dx: 1.8, y: 0.8, size: 0.7, color: 0xc8452d)
        roundDoor(root, hill: h2, radius: 5.6, dx: 0.4, y: 0.9, size: 0.8, color: 0x2f6fb0)
        // chimneys with a little smoke
        for p in [(-9.5, 3.1, -7.2), (-1.0, 2.0, -9.8)] {
            root.cyl(0.25, 0.7, Gfx.mat(0x8a6a58, r: 0.9), CGFloat(p.0), CGFloat(p.1), CGFloat(p.2))
            let sm = root.ball(0.25, Gfx.mat(0xe8e0d8, r: 1, alpha: 0.6), CGFloat(p.0), CGFloat(p.1) + 0.5, CGFloat(p.2))
            sm.castsShadow = false
            sm.runAction(.repeatForever(.sequence([.group([.moveBy(x: 0.6, y: 1.4, z: 0, duration: 4), .fadeOut(duration: 4), .scale(to: 2.2, duration: 4)]),
                                                   .group([.moveBy(x: -0.6, y: -1.4, z: 0, duration: 0), .fadeIn(duration: 0), .scale(to: 1, duration: 0)])])))
        }
        // trees in golden light
        tree(root, -17.5, -1.8, 1.3); tree(root, -15.4, -2.8, 1.0); tree(root, 4.2, -3.2, 1.2); tree(root, 8.4, -4.5, 1.5)
        for (x, z) in [(-6.0, -1.2), (2.4, -1.4), (9.0, -1.0)] {
            let b = root.ball(0.7, Gfx.mat(0x4f8a3a, r: 1), CGFloat(x), 0.4, CGFloat(z))
            b.scale = SCNVector3(1.3, 0.8, 1)
        }
        // picket fence with a gate
        let wood = Gfx.mat(0xb08650, r: 0.9)
        for i in 0..<22 {
            let x = -6.5 + CGFloat(i) * 0.65
            if x > 3.2 && x < 4.6 { continue }
            let p = root.box(0.14, 0.9, 0.1, wood, x, 0.45, -0.4)
            _ = p
        }
        root.box(14, 0.08, 0.06, wood, 0.6, 0.7, -0.4)
        root.box(14, 0.08, 0.06, wood, 0.6, 0.3, -0.4)
        // signpost shadowed lanterns
        for x in [-15.4, 8.2] {
            root.cyl(0.07, 2.2, Gfx.mat(0x4a3322), CGFloat(x), 1.1, 3.2)
            root.box(0.34, 0.4, 0.34, Gfx.mat(0xffd070, e: 0xffa840, eIntensity: 1.3), CGFloat(x), 2.35, 3.2)
            root.box(0.46, 0.08, 0.46, Gfx.mat(0x3a2a1a), CGFloat(x), 2.62, 3.2)
        }
    }

    private static func fellowshipTavern(_ root: SCNNode) {
        let t = root.group("prop:tavern", 12.4, 0, 0.2)
        t.scale = SCNVector3(0.9, 0.9, 0.9)
        let plaster = Gfx.mat(0xf0dcb0, r: 0.9), beam = Gfx.mat(0x5a3b22, r: 0.9), stone = Gfx.mat(0x8f8a82, r: 1)
        let roofM = Gfx.mat(0x9a4a32, r: 0.8)
        t.box(5.8, 0.9, 3.4, stone, 0, 0.45, 0)
        t.box(5.4, 2.4, 3.2, plaster, 0, 2.1, 0)
        for x in [-2.7, -0.9, 0.9, 2.7] { t.box(0.16, 2.4, 0.1, beam, CGFloat(x), 2.1, 1.62) }
        t.box(5.5, 0.16, 0.12, beam, 0, 1.35, 1.62)
        t.box(5.5, 0.16, 0.12, beam, 0, 3.2, 1.62)
        for s in [-1.0, 1.0] {
            let r = t.box(6.2, 0.2, 2.5, roofM, 0, 4.0, CGFloat(s) * 0.95)
            r.eulerAngles = SCNVector3(Float(s) * -0.62, 0, 0)
        }
        t.box(6.2, 0.16, 0.2, Gfx.mat(0x6a2e22), 0, 4.65, 0)
        // gable end triangles
        for x in [-2.75, 2.75] {
            let g = t.add(SCNPyramid(width: 3.3, height: 1.25, length: 0.2), plaster, at: SCNVector3(x, 3.3, 0))
            g.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            g.scale = SCNVector3(1, 1, 1)
        }
        t.box(0.55, 1.4, 0.5, Gfx.mat(0x8a6a58, r: 0.9), -1.8, 4.9, -0.4)
        let sm = t.ball(0.3, Gfx.mat(0xf0e8e0, r: 1, alpha: 0.6), -1.8, 5.8, -0.4)
        sm.castsShadow = false
        sm.runAction(.repeatForever(.sequence([.group([.moveBy(x: 0.8, y: 1.6, z: 0, duration: 4.5), .fadeOut(duration: 4.5), .scale(to: 2.4, duration: 4.5)]),
                                               .group([.moveBy(x: -0.8, y: -1.6, z: 0, duration: 0), .fadeIn(duration: 0), .scale(to: 1, duration: 0)])])))
        // door and windows
        let door = t.cyl(0.62, 0.14, Gfx.mat(0x6b3f22, r: 0.8), 0, 1.35, 1.68)
        door.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        t.box(1.24, 0.9, 0.14, Gfx.mat(0x6b3f22, r: 0.8), 0, 0.85, 1.68)
        t.ball(0.07, Gfx.mat(0xffd54a, m: 1), 0.35, 1.2, 1.78)
        for x in [-2.0, 2.0] {
            let w = t.box(0.9, 0.8, 0.1, Gfx.mat(0xffcf70, r: 0.3, e: 0xffa840, eIntensity: 1.1), CGFloat(x), 2.3, 1.64)
            w.name = "window"
            t.box(0.96, 0.06, 0.14, beam, CGFloat(x), 2.3, 1.66)
            t.box(0.06, 0.86, 0.14, beam, CGFloat(x), 2.3, 1.66)
        }
        // hanging sign
        t.box(0.08, 0.08, 0.9, beam, -3.1, 3.0, 2.0)
        let board = Gfx.image(256, 128) { c in
            c.setFillColor(Gfx.color(0x8a5a30).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .heavy), .foregroundColor: Gfx.color(0xffe9a8)]
            ("THE FULL MUG" as NSString).draw(at: NSPoint(x: 26, y: 68), withAttributes: a)
            ("🍺" as NSString).draw(at: NSPoint(x: 100, y: 14), withAttributes: [.font: NSFont.systemFont(ofSize: 40)])
            NSGraphicsContext.restoreGraphicsState()
        }
        let sign = t.box(0.08, 0.7, 1.4, Gfx.texMat(board, r: 0.8), -3.1, 2.55, 2.4)
        sign.eulerAngles = SCNVector3(0, 0, 0)
        sign.runAction(.repeatForever(.sequence([.rotateTo(x: 0.06, y: 0, z: 0, duration: 2, usesShortestUnitArc: true), .rotateTo(x: -0.06, y: 0, z: 0, duration: 2, usesShortestUnitArc: true)])))
        // barrels and benches
        for (x, z) in [(3.4, 2.4), (3.9, 1.9), (-3.5, 2.2)] {
            let b = t.cyl(0.38, 0.8, Gfx.mat(0x8a5a30, r: 0.8), CGFloat(x), 0.4, CGFloat(z))
            _ = b
            t.cyl(0.4, 0.05, Gfx.mat(0x3a2a1a, m: 0.6), CGFloat(x), 0.25, CGFloat(z))
            t.cyl(0.4, 0.05, Gfx.mat(0x3a2a1a, m: 0.6), CGFloat(x), 0.55, CGFloat(z))
        }
        t.box(1.6, 0.12, 0.5, beam, -4.0, 0.45, 1.2)
    }

    private static func fellowshipCharmStump(_ root: SCNNode) {
        let g = root.group("prop:coffee", wx(Theme.fellowship.coffee.x), 0, wz(Theme.fellowship.coffee.y) - 0.7)
        let bark = Gfx.mat(0x6b4a2f, r: 0.95)
        g.cyl(0.7, 0.8, bark, 0, 0.4, 0)
        g.cyl(0.62, 0.05, Gfx.mat(0xc79a62, r: 0.9), 0, 0.82, 0)
        for k in 0..<5 {
            let a = CGFloat(k) * 1.26
            g.ball(0.18, Gfx.mat(0x7a7a72, r: 1), cos(a) * 0.9, 0.12, sin(a) * 0.9 + 0.1)
        }
        g.cyl(0.14, 0.2, Gfx.mat(0xb07a45, r: 0.7), 0.35, 0.95, 0.15)
        g.cyl(0.11, 0.02, Gfx.mat(0xf3e2b5), 0.35, 1.06, 0.15)
        // the lucky charm: hovers, spins, and now and then rolls away with everyone chasing it
        let roller = g.group("roller", 0, 0, 0)
        let bob = roller.group("bob", 0, 1.35, 0)
        bob.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: 0.15, z: 0, duration: 1.2), .moveBy(x: 0, y: -0.15, z: 0, duration: 1.2)])))
        let ring = bob.add(SCNTorus(ringRadius: 0.3, pipeRadius: 0.075), Gfx.mat(0xffc830, r: 0.15, m: 1, e: 0xc08a10, eIntensity: 0.9), name: "prop:coffee")
        ring.runAction(.repeatForever(.rotateBy(x: 0.3, y: .pi * 2, z: 0, duration: 4)))
        let halo = bob.ball(0.6, Gfx.mat(0xffd060, e: 0xffc040, eIntensity: 1, alpha: 0.22), 0, 0, 0)
        halo.castsShadow = false
        pulse(halo, 0.12, 0.9)
        let spark = bob.add(SCNBox(width: 0.05, height: 0.5, length: 0.02, chamferRadius: 0), Gfx.mat(0xfff4c0, e: 0xfff0a0, eIntensity: 1.5), at: SCNVector3(0.3, 0.2, 0.2), shadow: false)
        spark.runAction(.repeatForever(.sequence([.scale(to: 0.2, duration: 0.6), .scale(to: 1.1, duration: 0.6)])))
        roller.runAction(.repeatForever(.sequence([
            .wait(duration: 14),
            .group([.moveBy(x: 4.5, y: -0.2, z: 1.2, duration: 2.2), .rotateBy(x: 0, y: -.pi, z: 0, duration: 2.2)]),
            .wait(duration: 2),
            .group([.moveBy(x: -4.5, y: 0.2, z: -1.2, duration: 2.6), .rotateBy(x: 0, y: .pi, z: 0, duration: 2.6)])
        ])))
    }

    private static func fellowshipEagle(_ root: SCNNode) {
        let e = root.group("eagle", 30, 9, -6)
        let brown = Gfx.mat(0x6b4a2f, r: 0.9), white = Gfx.mat(0xf6f0e0, r: 0.9)
        let b = e.ball(0.5, brown, 0, 0, 0)
        b.scale = SCNVector3(1.9, 0.7, 0.8)
        e.ball(0.26, white, -0.95, 0.12, 0)
        let beak = e.add(SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.3), Gfx.mat(0xffc02a, r: 0.5), at: SCNVector3(-1.25, 0.08, 0))
        beak.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        e.box(0.7, 0.05, 0.5, brown, 1.1, 0, 0)
        for s in [1.0, -1.0] {
            let w = e.group("wing", 0, 0.1, 0)
            let panel = w.box(0.9, 0.06, 2.2, brown, 0.1, 0, CGFloat(s) * 1.2)
            panel.castsShadow = false
            w.box(0.5, 0.07, 0.8, Gfx.mat(0x3a2a1a, r: 0.9), 0.55, 0, CGFloat(s) * 2.2).castsShadow = false
            w.runAction(.repeatForever(.sequence([.rotateTo(x: CGFloat(s) * 0.45, y: 0, z: 0, duration: 0.35), .rotateTo(x: CGFloat(s) * -0.45, y: 0, z: 0, duration: 0.35)])))
        }
        e.eulerAngles = SCNVector3(0, 0, 0)
        e.scale = SCNVector3(0.9, 0.9, 0.9)
        e.runAction(.repeatForever(.sequence([
            .wait(duration: 18),
            .move(to: SCNVector3(30, 9, -6), duration: 0),
            .move(to: SCNVector3(2, 3.2, 7), duration: 4.5),
            .move(to: SCNVector3(-32, 10, -6), duration: 4.5)
        ])))
    }

    private static func fellowshipGarden(_ root: SCNNode) {
        for i in 0..<18 {
            let x = -16 + CGFloat(i) * 1.9, z = 9.2 + CGFloat(i % 3) * 0.45
            root.cyl(0.02, 0.3, Gfx.mat(0x3d7a2c), x, 0.15, z)
            root.ball(0.09, Gfx.mat([0xf0c040, 0xffffff, 0xe2506a, 0xb06ad8][i % 4], r: 0.5), x, 0.34, z)
        }
        for (x, z) in [(-11.0, 3.4), (-1.5, 9.5), (6.0, 3.5)] {
            root.cyl(0.07, 0.35, Gfx.mat(0xf3e2b5), CGFloat(x), 0.17, CGFloat(z))
            let cap = root.ball(0.26, Gfx.mat(0xd2432d, r: 0.6), CGFloat(x), 0.4, CGFloat(z))
            cap.scale = SCNVector3(1, 0.6, 1)
        }
        for (x, z) in [(-8.0, 5.2), (0.5, 5.4), (9.0, 5.0), (-14.0, 6.0)] {
            let r = root.ball(0.32, Gfx.mat(0x8a877f, r: 1), CGFloat(x), 0.12, CGFloat(z))
            r.scale = SCNVector3(1.4, 0.6, 1)
        }
    }

    /// Prop for one work station; `kind` 0 map table, 1 forge, 2 campfire, 3 signpost + beacon (see `Theme.stations`).
    static func fellowshipStation(_ kind: Int, _ n: SCNNode) {
        let wood = Gfx.mat(0x8a5a30, r: 0.9), dark = Gfx.mat(0x3a2a1a, r: 0.8)
        let flicker = { (node: SCNNode, lo: CGFloat, hi: CGFloat, d: Double) in
            node.runAction(.repeatForever(.sequence([.scale(to: hi, duration: d), .scale(to: lo, duration: d * 1.2)])))
        }
        switch kind {
        case 0:
            n.box(2.5, 0.12, 1.1, wood, 0, 0.95, 0.1, round: 0.03)
            for (x, z) in [(-1.1, -0.35), (1.1, -0.35), (-1.1, 0.5), (1.1, 0.5)] { n.box(0.14, 0.95, 0.14, dark, CGFloat(x), 0.47, CGFloat(z)) }
            let map = Gfx.image(256, 128) { c in
                c.setFillColor(Gfx.color(0xecd9a2).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
                c.setFillColor(Gfx.color(0xb9c98a).cgColor); c.fillEllipse(in: CGRect(x: 20, y: 20, width: 120, height: 80))
                c.setFillColor(Gfx.color(0x8fb4c8).cgColor); c.fillEllipse(in: CGRect(x: 150, y: 14, width: 80, height: 50))
                c.setFillColor(Gfx.color(0x7a5a4a).cgColor)
                c.move(to: CGPoint(x: 170, y: 70)); c.addLine(to: CGPoint(x: 200, y: 118)); c.addLine(to: CGPoint(x: 230, y: 70)); c.fillPath()
                c.setFillColor(Gfx.color(0xff6a1a).cgColor); c.fillEllipse(in: CGRect(x: 194, y: 108, width: 12, height: 10))
                c.setStrokeColor(Gfx.color(0x8a2a1a).cgColor); c.setLineWidth(3); c.setLineDash(phase: 0, lengths: [8, 6])
                c.move(to: CGPoint(x: 40, y: 40)); c.addCurve(to: CGPoint(x: 190, y: 90), control1: CGPoint(x: 90, y: 110), control2: CGPoint(x: 120, y: 20)); c.strokePath()
                c.setLineDash(phase: 0, lengths: [])
                c.setStrokeColor(Gfx.color(0xc8201a).cgColor); c.setLineWidth(5)
                c.move(to: CGPoint(x: 34, y: 34)); c.addLine(to: CGPoint(x: 46, y: 46)); c.move(to: CGPoint(x: 34, y: 46)); c.addLine(to: CGPoint(x: 46, y: 34)); c.strokePath()
            }
            let pm = n.box(1.7, 0.02, 0.85, Gfx.texMat(map, r: 0.9), -0.15, 1.02, 0.1)
            pm.castsShadow = false
            let roll = n.cyl(0.09, 0.9, Gfx.mat(0xe8d5a0, r: 0.9), 0.95, 1.1, 0.35)
            roll.eulerAngles = SCNVector3(0, 0, Float.pi / 2 + 0.25)
            n.cyl(0.05, 0.3, Gfx.mat(0xf6efd8, r: 0.8), 0.9, 1.19, -0.15)
            let fl = n.add(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.14), Gfx.mat(0xffc040, e: 0xff9a20, eIntensity: 1.5), at: SCNVector3(0.9, 1.4, -0.15), shadow: false)
            flicker(fl, 0.8, 1.25, 0.15)
            n.cyl(0.07, 0.1, dark, -1.0, 1.06, -0.2)
            let q = n.box(0.03, 0.4, 0.03, Gfx.mat(0xf3f0e6), -0.96, 1.3, -0.2)
            q.eulerAngles = SCNVector3(0, 0, -0.4)
            n.add(SCNTorus(ringRadius: 0.11, pipeRadius: 0.02), Gfx.mat(0xd0a040, m: 1, e: 0x6a4a10), at: SCNVector3(-0.5, 1.04, 0.45), shadow: false)
        case 1:
            let stone = Gfx.mat(0x7a7570, r: 1)
            n.box(1.3, 1.1, 1.0, stone, -0.55, 0.55, 0, round: 0.05)
            n.box(0.9, 0.9, 0.5, Gfx.mat(0x6a6560, r: 1), -0.55, 1.5, -0.25)
            n.box(0.5, 1.2, 0.5, Gfx.mat(0x6a6560, r: 1), -0.55, 2.4, -0.25)
            let coals = n.box(0.9, 0.12, 0.55, Gfx.mat(0xff5a10, e: 0xff4a00, eIntensity: 1.5), -0.55, 1.14, 0.12)
            coals.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.7, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])))
            let fl = n.add(SCNCone(topRadius: 0, bottomRadius: 0.22, height: 0.5), Gfx.mat(0xffa020, e: 0xff7a10, eIntensity: 1.4), at: SCNVector3(-0.55, 1.45, 0.12), shadow: false)
            flicker(fl, 0.8, 1.3, 0.16)
            let bel = n.box(0.5, 0.3, 0.4, Gfx.mat(0x6b3f22, r: 0.8), -1.55, 0.6, 0.2, round: 0.06)
            bel.eulerAngles = SCNVector3(0, 0, 0.2)
            n.cyl(0.32, 0.5, Gfx.mat(0x6a4a30), 0.9, 0.25, 0.2)
            n.box(0.75, 0.22, 0.4, Gfx.mat(0x4a4f58, r: 0.35, m: 0.8), 0.9, 0.61, 0.2, round: 0.03)
            let horn = n.add(SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.45), Gfx.mat(0x4a4f58, r: 0.35, m: 0.8), at: SCNVector3(1.4, 0.62, 0.2))
            horn.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
            let hot = n.box(0.4, 0.05, 0.12, Gfx.mat(0xff7a2a, e: 0xff5a10, eIntensity: 1.2), 0.85, 0.75, 0.2)
            hot.castsShadow = false
            let hm = n.cyl(0.04, 0.6, Gfx.mat(0x6b4a2f), 1.1, 0.4, 0.55)
            hm.eulerAngles = SCNVector3(0.3, 0, 0.3)
            n.box(0.28, 0.14, 0.14, Gfx.mat(0x4a4f58, m: 0.8), 1.2, 0.72, 0.62)
            for k in 0..<4 {
                let sp = n.ball(0.04, Gfx.mat(0xffd060, e: 0xffb030, eIntensity: 1.6), 0.9, 0.8, 0.2)
                sp.castsShadow = false
                let dx = CGFloat(k - 2) * 0.25 + 0.1
                sp.runAction(.sequence([.wait(duration: Double(k) * 0.35), .repeatForever(.sequence([
                    .group([.moveBy(x: dx, y: 0.7, z: 0.2, duration: 0.7), .fadeOut(duration: 0.7)]),
                    .group([.moveBy(x: -dx, y: -0.7, z: -0.2, duration: 0), .fadeIn(duration: 0)]),
                    .wait(duration: 0.5)]))]))
            }
        case 2:
            for k in 0..<9 {
                let a = CGFloat(k) / 9 * 2 * .pi
                let s = n.ball(0.17, Gfx.mat(0x8a877f, r: 1), cos(a) * 0.62, 0.1, sin(a) * 0.62 + 0.1)
                s.scale = SCNVector3(1.1, 0.8, 1)
            }
            for k in 0..<3 {
                let l = n.cyl(0.07, 0.9, Gfx.mat(0x5a3b22, r: 1), 0, 0.14, 0.1)
                l.eulerAngles = SCNVector3(0, Float(k) * 1.05, Float.pi / 2)
            }
            for (i, c) in [(0xff6a1a, 0.38), (0xffa828, 0.28), (0xffe070, 0.16)].enumerated() {
                let fl = n.add(SCNCone(topRadius: 0, bottomRadius: CGFloat(c.1), height: 0.55 + CGFloat(i) * 0.05), Gfx.mat(UInt32(c.0), e: UInt32(c.0), eIntensity: 1.5), at: SCNVector3(0, 0.45 + CGFloat(i) * 0.03, 0.1), shadow: false)
                flicker(fl, 0.75, 1.3, 0.12 + Double(i) * 0.04)
            }
            for k in 0..<3 {
                let a = Float(k) * 2.09 + 0.4
                let leg = n.cyl(0.035, 1.5, Gfx.mat(0x5a3b22), CGFloat(cos(a)) * 0.35, 0.78, CGFloat(sin(a)) * 0.35 + 0.1)
                leg.eulerAngles = SCNVector3(Float(sin(a)) * 0.28, 0, -Float(cos(a)) * 0.28)
            }
            n.ball(0.42, Gfx.mat(0x2c2f36, r: 0.4, m: 0.7), 0, 1.15, 0.1)
            n.cyl(0.36, 0.04, Gfx.mat(0x8a5a22, r: 0.5), 0, 1.5, 0.1)
            n.cyl(0.4, 0.03, Gfx.mat(0x2c2f36, m: 0.7), 0, 1.48, 0.1)
            let steam = n.ball(0.15, Gfx.mat(0xffffff, r: 1, alpha: 0.5), 0, 1.6, 0.1)
            steam.castsShadow = false
            steam.runAction(.repeatForever(.sequence([.group([.moveBy(x: 0.2, y: 0.9, z: 0, duration: 2.4), .fadeOut(duration: 2.4), .scale(to: 2.4, duration: 2.4)]),
                                                      .group([.moveBy(x: -0.2, y: -0.9, z: 0, duration: 0), .fadeIn(duration: 0), .scale(to: 1, duration: 0)])])))
            let log = n.cyl(0.18, 0.7, Gfx.mat(0x7a5232, r: 0.9), -1.2, 0.18, 0.5)
            log.eulerAngles = SCNVector3(Float.pi / 2, 0, 0.2)
            n.cyl(0.14, 0.08, Gfx.mat(0xc79a62), -1.2, 0.2, 0.86).eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            n.cyl(0.1, 0.18, Gfx.mat(0xe8dcc0, r: 0.8), 1.1, 0.09, 0.6)
        default:
            n.cyl(0.09, 2.4, Gfx.mat(0x6b4a2f, r: 0.95), -0.7, 1.2, 0.1)
            func plank(_ text: String, _ y: CGFloat, _ yaw: Float, _ left: Bool) {
                let img = Gfx.image(256, 64) { c in
                    c.setFillColor(Gfx.color(0xc9a064).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 64))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
                    ((left ? "◀ " + text : text + " ▶") as NSString).draw(at: NSPoint(x: 14, y: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .heavy), .foregroundColor: Gfx.color(0x3a2210)])
                    NSGraphicsContext.restoreGraphicsState()
                }
                let b = n.box(1.15, 0.28, 0.06, Gfx.texMat(img, r: 0.9), -0.7 + (left ? -0.45 : 0.45), y, 0.17)
                b.eulerAngles = SCNVector3(0, yaw, 0)
            }
            plank("MOUNTAIN", 2.1, 0.06, false)
            plank("NOT HERE", 1.7, -0.08, true)
            plank("SNACKS", 1.3, 0.05, false)
            let tower = Gfx.mat(0x8a877f, r: 1)
            n.cyl(0.55, 0.7, tower, 0.7, 0.35, 0.1)
            n.cyl(0.42, 0.7, Gfx.mat(0x7a7770, r: 1), 0.7, 1.05, 0.1)
            n.cyl(0.5, 0.12, Gfx.mat(0x2c2f36, m: 0.7), 0.7, 1.46, 0.1)
            let fl = n.add(SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.8), Gfx.mat(0xff8a20, e: 0xff6a10, eIntensity: 1.6), at: SCNVector3(0.7, 1.9, 0.1), shadow: false)
            flicker(fl, 0.8, 1.35, 0.14)
            let core = n.add(SCNCone(topRadius: 0, bottomRadius: 0.16, height: 0.5), Gfx.mat(0xffe070, e: 0xffd040, eIntensity: 1.8), at: SCNVector3(0.7, 1.78, 0.1), shadow: false)
            flicker(core, 0.7, 1.3, 0.1)
            let halo = n.ball(0.9, Gfx.mat(0xffa040, e: 0xff8a20, eIntensity: 1, alpha: 0.16), 0.7, 1.9, 0.1)
            halo.castsShadow = false
            pulse(halo, 0.12, 0.7)
        }
    }
}

extension Rig {
    /// (top, bottom, accent) colours; `v` is a per-actor variant index.
    static func fellowshipOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        if captain { return (0x9aa3b4, 0x6a7384, 0xe2b64a) }
        let vests: [UInt32] = [0xa8442d, 0x4d7f3a, 0x3f6f9a, 0x8a4f7a, 0xc89a3a]
        let pants: [UInt32] = [0x7a5a3a, 0x5a4630, 0x6b5a3a]
        return (vests[v % vests.count], pants[(v / 3) % pants.count], 0xe2b64a)
    }

    /// Cloaks, hoods, beards, pointy ears etc. added to the head/body.
    static func fellowshipAccessories(captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let head = rig.head, body = rig.body
        let gold = Gfx.mat(0xffc830, r: 0.15, m: 1, e: 0xa07010, eIntensity: 0.8)
        if captain {
            let grey = Gfx.mat(0xd9dce2, r: 0.9), robe = Gfx.mat(0x8b94a6, r: 0.9), hat = Gfx.mat(0x6f7890, r: 0.85)
            head.ball(0.31, grey, 0, 0.34, -0.06)
            let beard = head.add(SCNCone(topRadius: 0.26, bottomRadius: 0.03, height: 1.0), grey, at: SCNVector3(0, -0.28, 0.14))
            beard.scale = SCNVector3(1, 1, 0.8)
            head.box(0.3, 0.07, 0.1, grey, 0, 0.2, 0.3, round: 0.03)
            for x in [-0.11, 0.11] { head.box(0.14, 0.06, 0.08, grey, CGFloat(x), 0.42, 0.28, round: 0.02) }
            head.cyl(0.55, 0.05, hat, 0, 0.56, 0)
            let cone = head.add(SCNCone(topRadius: 0.03, bottomRadius: 0.34, height: 1.0), hat, at: SCNVector3(0, 1.05, 0))
            cone.eulerAngles = SCNVector3(0, 0, 0.16)
            head.cyl(0.35, 0.09, accM, 0, 0.64, 0)
            head.add(SCNSphere(radius: 0.05), Gfx.mat(0xffd54a, e: 0xffd54a), at: SCNVector3(0.0, 0.68, 0.35))
            body.box(0.84, 1.5, 0.1, robe, 0, -0.05, -0.24, round: 0.04)
            body.box(0.9, 0.16, 0.5, robe, 0, 0.72, 0, round: 0.06)
            body.box(0.7, 0.07, 0.4, Gfx.mat(0xd8c9a0, r: 0.9), 0, 0.2, 0.01)
            body.ball(0.14, Gfx.mat(0x7a5a3a, r: 0.9), 0.32, 0.12, 0.2)
            let staff = rig.armL.cyl(0.05, 2.35, Gfx.mat(0x6b4a2f, r: 0.9), 0, -0.3, 0.12)
            staff.name = "staff"
            rig.armL.ball(0.2, Gfx.mat(0xb8f0ff, r: 0.1, e: 0x6ad0f0, eIntensity: 1.2, alpha: 0.9), 0, 0.98, 0.12)
            rig.armL.add(SCNTorus(ringRadius: 0.17, pipeRadius: 0.035), Gfx.mat(0x6b4a2f), at: SCNVector3(0, 0.98, 0.12))
            for leg in [rig.legL, rig.legR] {
                let f = leg.ball(0.17, grey, 0, -0.76, 0.1)
                f.scale = SCNVector3(1.1, 0.6, 1.7)
            }
        } else {
            let cloaks: [UInt32] = [0x4d6b3a, 0x7a4a2f, 0x3d5a78, 0x6a4a6a, 0x8a6a2a]
            let cloak = Gfx.mat(cloaks[number % cloaks.count], r: 0.9)
            head.ball(0.33, hair, 0, 0.38, -0.05)
            for (i, p) in [(-0.2, 0.55), (0.0, 0.62), (0.2, 0.55), (-0.3, 0.42), (0.3, 0.42)].enumerated() {
                head.ball(0.1, hair, CGFloat(p.0), CGFloat(p.1), 0.12 - CGFloat(i % 2) * 0.05)
            }
            for (s, a) in [(-1.0, Float.pi / 2), (1.0, -Float.pi / 2)] {
                let ear = head.add(SCNCone(topRadius: 0, bottomRadius: 0.06, height: 0.24), Gfx.mat(0xe8b890, r: 0.8), at: SCNVector3(CGFloat(s) * 0.3, 0.34, 0))
                ear.eulerAngles = SCNVector3(0, 0, a)
            }
            body.box(0.78, 0.95, 0.09, cloak, 0, 0.28, -0.24, round: 0.04)
            body.box(0.84, 0.13, 0.46, cloak, 0, 0.72, 0, round: 0.05)
            body.cyl(0.04, 0.03, Gfx.mat(0x6ad060, e: 0x3a9a30), 0, 0.72, 0.24)
            let chain = body.box(0.03, 0.26, 0.02, gold, -0.06, 0.62, 0.21)
            chain.eulerAngles = SCNVector3(0, 0, -0.35)
            let chain2 = body.box(0.03, 0.26, 0.02, gold, 0.06, 0.62, 0.21)
            chain2.eulerAngles = SCNVector3(0, 0, 0.35)
            let ring = body.add(SCNTorus(ringRadius: 0.07, pipeRadius: 0.022), gold, at: SCNVector3(0, 0.46, 0.22), shadow: false)
            ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            ring.runAction(.repeatForever(.sequence([.scale(to: 1.35, duration: 0.7), .scale(to: 1, duration: 0.7)])))
            for leg in [rig.legL, rig.legR] {
                let f = leg.ball(0.17, hair, 0, -0.74, 0.1)
                f.scale = SCNVector3(1.25, 0.65, 1.9)
            }
        }
    }

    /// Context-usage gauge shown on a worker (set `mv.fill`): a glowing flask on the pack.
    func fellowshipGauge(_ figure: SCNNode, metal: SCNMaterial) {
        let g = body.group("gauge", 0.3, 0.42, -0.32)
        g.cyl(0.16, 0.76, Gfx.mat(0xcfe8f0, r: 0.1, alpha: 0.35), 0, 0, 0)
        g.cyl(0.1, 0.1, Gfx.mat(0x8a5a30, r: 0.8), 0, 0.42, 0)
        let f = g.add(SCNCylinder(radius: 0.17, height: 0.64), tinted(0xffb02a, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
        bottomAnchored(f, height: 0.64)
        mv.fill = f
    }

    /// Small beacon shown for approval requests: a brazier with a lit flame.
    func fellowshipBeacon(_ beacon: SCNNode, metal: SCNMaterial) {
        beacon.cyl(0.04, 0.2, metal, 0, -0.1, 0)
        beacon.cyl(0.1, 0.06, tinted(0x2c2f36), 0, 0.02, 0)
        let fl = beacon.add(SCNCone(topRadius: 0, bottomRadius: 0.11, height: 0.26), tinted(0xff8a2a, e: true), at: SCNVector3(0, 0.17, 0), shadow: false)
        fl.runAction(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.15), .scale(to: 0.85, duration: 0.18)])))
    }
}

extension Stage {
    /// (background, ambient, ambient intensity, key, key intensity, fill): low golden-hour sun with a violet sky fill.
    static func fellowshipLighting() -> (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) { (0xf6b878, 0xffd9b0, 430, 0xffb866, 1350, 0xb07ad0) }
    /// Work animation per tool kind (0 read, 1 write, 2 run, 3 other).
    static func fellowshipMotion(_ kind: Int) -> Motion { [.scan, .hammer, .stir, .type][kind % 4] }
}

extension RoomSim {
    /// Failure effect: a giant eagle snatches a snack, the stew burns, or the charm rolls away.
    func fellowshipFailure(t: Double) {
        let scenes: [(panic: String, victim: String, guide: String, mood: Mood)] = [
            ("Giant eagle! 🦅", "Put me down! 🦅", "Not the lunch basket!", .dizzy),
            ("The stew is burnt! 🔥", "My eyebrows… 🍲", "Add more salt?", .sick),
            ("Where's the charm?! 🪙", "It rolled away… 😭", "Everybody calm down!", .sad)
        ]
        let s = scenes.randomElement()!
        panicAll(t: t, line: s.panic)
        guard let v = victim() else { return }
        mutate(v.id) { $0.mood = s.mood; $0.moodUntil = t + 8; $0.say = s.victim; $0.sayUntil = t + 4 }
        captain.pending = v.id
        captain.chatPartner = nil
        captain.route = [CGPoint(x: v.pos.x + (v.pos.x > 160 ? 14 : -14), y: v.pos.y + 4)]
        captain.pauseUntil = t + 1
        captain.say = s.guide
        captain.sayUntil = t + 3
    }
}



extension MetricsFmt {
    static var fellowshipMedal: String { "🪙" }
}

extension RoomSign {
    /// Captain age sign; `minutes` is whole minutes, `txt` the formatted age.
    static func fellowshipAgeSign(age: Double, days: Int, minutes: Int, jersey: Int, txt: String) -> NSImage {
        Gfx.sign("🪙 Quest day \(days)", "on the road \(txt)", accent: 0xe0b060)
    }
}

extension SoundCenter {
    /// Short lute plucks and horn calls.
    nonisolated static func fellowshipSynth(_ kind: Kind) -> Data? {
        func pluck(_ f: Double, _ d: Double = 0.22) -> [Float] {
            let a = tone(freq: { _ in f }, dur: d, decay: 6), b = tone(freq: { _ in f * 2 }, dur: d, decay: 10)
            return zip(a, b).map { $0 * 0.7 + $1 * 0.3 }
        }
        func horn(_ f: Double, _ d: Double) -> [Float] {
            tone(freq: { f * (1 + 0.006 * sin(2 * .pi * 5.5 * $0)) }, dur: d, decay: 1.2, attack: 0.05, saw: true).map { $0 * 0.7 }
        }
        switch kind {
        case .spawn: return wav(pluck(659, 0.12) + pluck(880, 0.18))
        case .success: return wav(horn(392, 0.16) + horn(523, 0.16) + horn(659, 0.45))
        case .failure: return wav(horn(311, 0.3) + horn(277, 0.3) + horn(233, 0.3) + horn(196, 0.6))
        case .alert: return wav(horn(440, 0.18) + horn(440, 0.4))
        }
    }
}
