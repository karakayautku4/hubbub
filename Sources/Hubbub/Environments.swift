import SceneKit
import AppKit

/// Builds the 3D set for each theme. Clickable props are named "prop:<id>".
enum Environments {
    static func wx(_ lx: CGFloat) -> CGFloat { (lx - 160) / 10 }
    static func wz(_ ly: CGFloat) -> CGFloat { (ly - 96) / 10 }

    static func build(_ theme: Theme) -> SCNNode {
        let root = SCNNode()
        root.name = "env"
        switch theme {
        case .space: space(root)
        case .kitchen: kitchen(root)
        case .prison: prison(root)
        case .football: football(root)
        case .farm: farm(root)
        case .impostor: impostor(root)
        case .wizard: wizard(root)
        case .galactic: galactic(root)
        case .fellowship: fellowship(root)
        }
        for (i, st) in theme.stations.enumerated() {
            let n = root.group("station\(i)", wx(st.pos.x), 0, wz(st.pos.y) - 0.95)
            stationProp(theme, i, n)
        }
        pruneShadows(root)
        return root
    }

    /// The shadow pass re-draws every caster each frame; tiny pieces and anything above head height cast no visible shadow on the stage.
    static func pruneShadows(_ root: SCNNode) {
        root.enumerateHierarchy { n, _ in
            guard n.castsShadow, let g = n.geometry else { return }
            let (lo, hi) = g.boundingBox
            let m = n.simdWorldTransform
            let sx = simd_length(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)), sy = simd_length(SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z)),
                sz = simd_length(SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
            let extent = max(CGFloat(sx) * (hi.x - lo.x), CGFloat(sy) * (hi.y - lo.y), CGFloat(sz) * (hi.z - lo.z))
            let lowest = CGFloat(m.columns.3.y) + CGFloat(sy) * lo.y
            if extent < 0.4 || lowest > 3.4 { n.castsShadow = false }
        }
    }

    static func floor(_ root: SCNNode, _ m: SCNMaterial, w: CGFloat = 38, d: CGFloat = 16, z: CGFloat = 7.6) {
        let f = root.box(w, 0.3, d, m, 0, -0.15, z, name: "floor")
        f.castsShadow = false
    }

    static func pulse(_ n: SCNNode, _ amount: CGFloat = 0.06, _ dur: Double = 1.2) {
        n.runAction(.repeatForever(.sequence([.scale(to: 1 + amount, duration: dur), .scale(to: 1, duration: dur)])))
    }

    static func coffee(_ root: SCNNode, _ theme: Theme) {
        let g = root.group("prop:coffee", wx(theme.coffee.x), 0, wz(theme.coffee.y) - 0.9)
        g.box(0.8, 1.3, 0.7, Gfx.mat(0x2e3238, r: 0.4, m: 0.4), 0, 0.65, 0, round: 0.05)
        g.box(0.5, 0.18, 0.05, Gfx.mat(0x6fe3b0, e: 0x6fe3b0, eIntensity: 0.8), 0, 1.0, 0.36)
        g.cyl(0.08, 0.14, Gfx.mat(0xffffff), 0, 0.5, 0.2)
        g.box(0.55, 0.06, 0.4, Gfx.mat(0x888d94, m: 0.8), 0, 0.42, 0.22)
    }

    // MARK: Space station

    static func space(_ root: SCNNode) {
        floor(root, Gfx.texMat(Gfx.tiles(0x3a4250, 0x333a47, grout: 0x1a1f28, cells: 6), r: 0.35, m: 0.6, repeatX: 5, repeatY: 2))
        root.box(38, 7, 0.4, Gfx.mat(0x20283a, r: 0.5, m: 0.5), 0, 3.5, -0.4)
        for (i, x) in [-9.0, 0.0, 9.0].enumerated() {
            root.box(5.6, 3.2, 0.1, Gfx.texMat(Gfx.stars(), emissive: true), x, 4.0, -0.18)
            root.box(5.9, 0.15, 0.2, Gfx.mat(0x8a96a8, m: 0.8), x, 2.35, -0.1)
            root.box(5.9, 0.15, 0.2, Gfx.mat(0x8a96a8, m: 0.8), x, 5.65, -0.1)
            root.box(0.15, 3.4, 0.2, Gfx.mat(0x8a96a8, m: 0.8), x - 2.9, 4, -0.1)
            root.box(0.15, 3.4, 0.2, Gfx.mat(0x8a96a8, m: 0.8), x + 2.9, 4, -0.1)
            _ = i
        }
        let planet = root.add(SCNSphere(radius: 1.5), Gfx.mat(0x3b82c4, r: 0.7, e: 0x0a2244, eIntensity: 0.6), at: SCNVector3(9.6, 4.3, -1.5), name: "prop:planet", shadow: false)
        planet.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 60)))
        let ring = root.add(SCNTorus(ringRadius: 2.3, pipeRadius: 0.06), Gfx.mat(0xd9c28a, r: 0.6, e: 0x4a3c18), at: SCNVector3(9.6, 4.3, -1.5), name: "prop:planet", shadow: false)
        ring.eulerAngles = SCNVector3(1.2, 0, 0.3)
        root.box(38, 0.1, 0.4, Gfx.mat(0x3fa9f5, e: 0x3fa9f5, eIntensity: 0.9), 0, 0.3, -0.1)
        // airlock door (left, where the crew arrives)
        let air = root.group("prop:airlock", -15.8, 0, 3.5)
        air.box(0.4, 3.4, 3.6, Gfx.mat(0x7e8896, m: 0.8, e: nil), 0, 1.7, 0)
        air.box(0.1, 2.8, 1.4, Gfx.mat(0x1b2230, m: 0.5), 0.22, 1.5, 0)
        air.box(0.06, 0.25, 0.9, Gfx.mat(0xffd24a, e: 0xffd24a), 0.25, 3.1, 0)
        // reactor, central and glowing
        let r = root.group("prop:reactor", 6.6, 0, 0.7)
        r.cyl(1.0, 0.4, Gfx.mat(0x5b6678, m: 0.8), 0, 0.2, 0)
        let core = r.cyl(0.55, 2.2, Gfx.mat(0x7be9ff, r: 0.1, e: 0x2bb6e6, eIntensity: 1.2, alpha: 0.85), 0, 1.5, 0)
        pulse(core, 0.08, 0.9)
        r.add(SCNTorus(ringRadius: 0.8, pipeRadius: 0.07), Gfx.mat(0x9aa7b5, m: 0.9), at: SCNVector3(0, 1.0, 0))
        r.add(SCNTorus(ringRadius: 0.8, pipeRadius: 0.07), Gfx.mat(0x9aa7b5, m: 0.9), at: SCNVector3(0, 2.0, 0))
        // commander console
        let c = root.group("prop:console", 0, 0, 0.55)
        c.box(3.2, 0.9, 1.0, Gfx.mat(0x2a3142, m: 0.6), 0, 0.45, 0, round: 0.05)
        c.box(2.4, 0.9, 0.06, Gfx.texMat(Gfx.screen(0x061425, 0x3fd0ff, seed: 3, style: 0), emissive: true), 0, 1.5, -0.2)
        coffee(root, .space)
    }

    // MARK: Restaurant kitchen

    static func kitchen(_ root: SCNNode) {
        floor(root, Gfx.texMat(Gfx.tiles(0xd9d4c8, 0x8a8f96, grout: 0x5a5e66, cells: 10), r: 0.4, m: 0.1, repeatX: 6, repeatY: 2.4))
        root.box(38, 7, 0.4, Gfx.texMat(Gfx.tiles(0xf3efe4, 0xece7da, grout: 0xbab5a8, cells: 16), r: 0.35, repeatX: 8, repeatY: 2), 0, 3.5, -0.4)
        // hood and shelves
        root.box(7, 0.9, 1.6, Gfx.mat(0x9aa0a8, r: 0.3, m: 0.9), 9.2, 5.6, 0.4)
        for x in [-6.0, -1.0, 3.5] {
            root.box(3, 0.12, 0.6, Gfx.mat(0x8a5a35), x, 4.2, 0.0)
            for k in 0..<4 {
                root.cyl(0.22, 0.4, Gfx.mat([0xc8372d, 0x4a90d9, 0xe0b040, 0x6aa84f][k], r: 0.4), x - 1.0 + CGFloat(k) * 0.65, 4.5, 0.05)
            }
        }
        // back counter + stove
        root.box(36, 1.0, 1.2, Gfx.mat(0xb5bbc4, r: 0.3, m: 0.8), 0, 0.5, 0.3)
        let stove = root.group("prop:stove", 9.2, 0, 0.35)
        stove.box(5, 1.15, 1.3, Gfx.mat(0x3a3e45, r: 0.3, m: 0.7), 0, 0.58, 0, round: 0.03)
        for x in [-1.4, 0, 1.4] {
            stove.cyl(0.55, 0.06, Gfx.mat(0x14161a), x, 1.17, 0)
            let flame = stove.add(SCNCone(topRadius: 0.0, bottomRadius: 0.3, height: 0.5), Gfx.mat(0xff7a1a, e: 0xff5a00, eIntensity: 1.4), at: SCNVector3(x, 1.45, 0), shadow: false)
            flame.runAction(.repeatForever(.sequence([.scale(to: 1.3, duration: 0.18), .scale(to: 0.8, duration: 0.22)])))
        }
        // serving hatch with bell (right side where finished plates leave)
        let hatch = root.group("prop:bell", 13.9, 0, 2.8)
        hatch.box(0.5, 1.1, 3.0, Gfx.mat(0x8a5a35), 0, 0.55, 0)
        hatch.box(0.6, 0.1, 3.2, Gfx.mat(0xb5bbc4, m: 0.8), 0, 1.15, 0)
        hatch.add(SCNSphere(radius: 0.28), Gfx.mat(0xe8c15a, r: 0.2, m: 1.0), at: SCNVector3(0, 1.4, 0))
        hatch.box(0.5, 0.06, 0.5, Gfx.mat(0xe8c15a, m: 1.0), 0, 1.22, 0)
        // coat rack/head chef pass
        let pass = root.group("prop:pass", 0, 0, 1.0)
        pass.box(4, 0.95, 0.9, Gfx.mat(0xb5bbc4, r: 0.3, m: 0.8), 0, 0.48, 0)
        for k in 0..<3 { pass.cyl(0.35, 0.06, Gfx.mat(0xffffff, r: 0.2), -1.0 + CGFloat(k), 0.98, 0.1) }
        coffee(root, .kitchen)
    }

    // MARK: Prison

    static func prison(_ root: SCNNode) {
        root.add(SCNPlane(width: 120, height: 40), Gfx.texMat(Gfx.skyGradient(), emissive: true), at: SCNVector3(0, 9, -12), shadow: false)
        floor(root, Gfx.texMat(Gfx.speckle(0x8b8f94, 0x6f7378), r: 0.95, repeatX: 6, repeatY: 2))
        // grass yard (back right)
        root.box(13, 0.06, 4.8, Gfx.texMat(Gfx.speckle(0x5f9b46, 0x4a8036, count: 1400, size: 3), r: 0.95, repeatX: 3, repeatY: 1.2), 11.0, 0.02, 2.3)
        // asphalt road
        root.box(38, 0.05, 2.4, Gfx.mat(0x3b3d42, r: 0.9), 0, 0.02, 6.2)
        for i in 0..<9 { root.box(1.1, 0.02, 0.18, Gfx.mat(0xe8d34a, r: 0.7), -16 + CGFloat(i) * 3.8, 0.06, 6.2) }
        // outer wall & watch posts
        let brick = Gfx.texMat(Gfx.tiles(0xa9a39a, 0x9a948b, grout: 0x6b665f, cells: 12), r: 0.9, repeatX: 10, repeatY: 1)
        root.box(38, 3.2, 0.5, brick, 0, 1.6, -0.5)
        root.box(38, 0.25, 0.7, Gfx.mat(0x6b665f), 0, 3.3, -0.5)
        for x in stride(from: -17.0, through: 17.0, by: 2.0) { root.cyl(0.04, 0.8, Gfx.mat(0x555a60, m: 0.9), x, 3.7, -0.5) }
        root.box(38, 0.05, 0.05, Gfx.mat(0x555a60, m: 0.9), 0, 4.0, -0.5)
        // cell block (3 cells, left)
        let cellBrick = Gfx.texMat(Gfx.tiles(0x7d8189, 0x73777f, grout: 0x4d5057, cells: 8), r: 0.9, repeatX: 3, repeatY: 1)
        root.box(12.4, 3.6, 0.3, cellBrick, -9.8, 1.8, 0.1)
        root.box(12.4, 0.3, 3.8, Gfx.mat(0x555a60), -9.8, 3.75, 1.9)
        for i in 0..<3 {
            let cx = -13.8 + CGFloat(i) * 4.0
            let cell = root.group("prop:cell\(i)", cx, 0, 0)
            cell.box(0.2, 3.6, 3.6, Gfx.mat(0x6b6f76, r: 0.9), -2.0, 1.8, 1.8)
            cell.box(3.2, 0.9, 1.3, Gfx.mat(0x8a5a35, r: 0.8), -0.2, 0.45, 0.8)
            cell.box(3.0, 0.2, 1.1, Gfx.mat(0xd9d5c8, r: 0.9), -0.2, 1.0, 0.8)
            cell.box(0.6, 0.12, 0.4, Gfx.mat(0xe7e2d3, r: 0.9), 1.0, 1.15, 0.8)
            for k in 0..<10 {
                let gap = k >= 4 && k <= 5
                if !gap { cell.cyl(0.05, 3.5, Gfx.mat(0x2c2f34, r: 0.3, m: 0.9), -1.7 + CGFloat(k) * 0.38, 1.75, 3.5) }
            }
            cell.box(3.8, 0.12, 0.12, Gfx.mat(0x2c2f34, m: 0.9), 0, 3.5, 3.5)
            cell.box(3.8, 0.12, 0.12, Gfx.mat(0x2c2f34, m: 0.9), 0, 0.12, 3.5)
        }
        // warden post
        let post = root.group("prop:desk", 0, 0, 0.45)
        post.box(2.6, 0.9, 1.0, Gfx.mat(0x3b4560, r: 0.5), 0, 0.45, 0, round: 0.04)
        post.box(0.7, 0.04, 0.5, Gfx.mat(0xf4f4ea), 0.5, 0.95, 0)
        post.box(0.1, 0.35, 0.1, Gfx.mat(0x2c2f34), -0.8, 1.1, -0.1)
        // alarm
        let alarm = root.group("prop:alarm", 1.9, 3.0, -0.2)
        alarm.box(0.4, 0.4, 0.2, Gfx.mat(0x444a52, m: 0.6), 0, 0, 0)
        let lamp = alarm.ball(0.26, Gfx.mat(0xe23b2e, r: 0.2, e: 0xe23b2e, eIntensity: 0.6), 0, 0.4, 0.05)
        lamp.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.8), .fadeOpacity(to: 1, duration: 0.8)])))
        // exit gate (right, where freed inmates leave)
        let gate = root.group("prop:gate", 15.6, 0, 5.6)
        gate.box(0.3, 3.4, 0.3, Gfx.mat(0x555a60, m: 0.8), 0, 1.7, -1.4)
        gate.box(0.3, 3.4, 0.3, Gfx.mat(0x555a60, m: 0.8), 0, 1.7, 1.4)
        gate.box(0.3, 0.3, 3.1, Gfx.mat(0x555a60, m: 0.8), 0, 3.4, 0)
        for k in 0..<7 { gate.box(0.1, 3.0, 0.1, Gfx.mat(0x2c2f34, m: 0.9), 0, 1.5, -1.2 + CGFloat(k) * 0.4) }
        let sign = gate.box(0.1, 0.5, 1.2, Gfx.mat(0x2f9e57, e: 0x1c7a40), 0.1, 3.8, 0)
        sign.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.6, duration: 1), .fadeOpacity(to: 1, duration: 1)])))
        coffee(root, .prison)
    }


    // MARK: Football

    static func pitchTexture() -> NSImage {
        Gfx.image(1024, 512) { c in
            for i in 0..<10 {
                c.setFillColor(Gfx.color(i % 2 == 0 ? 0x2f8a3a : 0x3a9a45).cgColor)
                c.fill(CGRect(x: CGFloat(i) * 102.4, y: 0, width: 103, height: 512))
            }
            var g = Gfx.RNG(s: 9)
            for _ in 0..<2500 {
                c.setFillColor(Gfx.color(0x1f6a2a, 0.25).cgColor)
                c.fill(CGRect(x: g.next() * 1024, y: g.next() * 512, width: 3, height: 3))
            }
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            c.setLineWidth(5)
            c.stroke(CGRect(x: 18, y: 18, width: 988, height: 476))
            c.move(to: CGPoint(x: 512, y: 18)); c.addLine(to: CGPoint(x: 512, y: 494))
            c.strokePath()
            c.strokeEllipse(in: CGRect(x: 512 - 70, y: 256 - 70, width: 140, height: 140))
            c.stroke(CGRect(x: 18, y: 130, width: 130, height: 252))
            c.stroke(CGRect(x: 876, y: 130, width: 130, height: 252))
        }
    }

    static func goal(_ g: SCNNode, scale s: CGFloat = 1) {
        let post = Gfx.mat(0xf2f2f2, r: 0.3, m: 0.3)
        g.box(0.12, 2.2 * s, 0.12, post, -1.6 * s, 1.1 * s, 0)
        g.box(0.12, 2.2 * s, 0.12, post, 1.6 * s, 1.1 * s, 0)
        g.box(3.3 * s, 0.12, 0.12, post, 0, 2.2 * s, 0)
        let net = Gfx.mat(0xffffff, r: 1, alpha: 0.22)
        g.box(3.2 * s, 2.1 * s, 0.03, net, 0, 1.1 * s, -0.8 * s)
        g.box(0.03, 2.1 * s, 0.8 * s, net, -1.6 * s, 1.1 * s, -0.4 * s)
        g.box(0.03, 2.1 * s, 0.8 * s, net, 1.6 * s, 1.1 * s, -0.4 * s)
    }

    static func football(_ root: SCNNode) {
        let team = Team.current
        floor(root, Gfx.texMat(pitchTexture(), r: 0.95))
        // advertising boards + tiered stands filled with fans in the team colours
        let crowd = Gfx.texMat(Gfx.speckle(0x262a38, team.kit.0, count: 1600, size: 5), r: 0.9, repeatX: 8, repeatY: 1)
        let crowd2 = Gfx.texMat(Gfx.speckle(0x2d3142, team.kit.2, count: 1400, size: 5), r: 0.9, repeatX: 8, repeatY: 1)
        for i in 0..<4 {
            let h = 1.3 + CGFloat(i) * 1.2
            root.box(38, h, 1.6, i % 2 == 0 ? crowd : crowd2, 0, h / 2, -0.6 - CGFloat(i) * 1.5)
        }
        root.box(38, 0.7, 0.2, Gfx.mat(team.kit.0, r: 0.5, e: team.kit.0, eIntensity: 0.4), 0, 0.35, 0.3)
        for i in 0..<8 {
            root.box(3.6, 0.5, 0.05, Gfx.mat([team.kit.1, 0xffffff, team.kit.2, 0x1c1c1c][i % 4], r: 0.4), -16.5 + CGFloat(i) * 4.7, 0.36, 0.42)
        }
        for x in [-15.0, 15.0] {
            root.cyl(0.12, 9, Gfx.mat(0x888d94, m: 0.8), x, 4.5, -2.5)
            root.box(2.4, 1.0, 0.3, Gfx.mat(0xfff6d8, r: 0.2, e: 0xfff1b0, eIntensity: 1.6), x, 9.2, -2.3)
        }
        // goal at the right end, corner flags, centre circle
        let g = root.group("prop:goal", 14.6, 0, 6.0)
        g.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        goal(g)
        let g2 = root.group("prop:goal", -14.6, 0, 6.0)
        g2.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        goal(g2)
        for x in [-17.5, 17.5] {
            root.cyl(0.03, 1.2, Gfx.mat(0xffffff), x, 0.6, 0.5)
            root.box(0.4, 0.25, 0.02, Gfx.mat(0xf2c200), x + 0.2, 1.05, 0.5)
        }
        // referee's VAR screen
        let var_ = root.group("prop:var", 2.4, 0, 0.8)
        var_.box(1.6, 1.0, 0.7, Gfx.mat(0x23262e, m: 0.4), 0, 0.5, 0)
        var_.box(1.4, 0.85, 0.05, Gfx.texMat(Gfx.screen(0x0a1a10, 0x6fe36f, seed: 5, style: 2), emissive: true), 0, 1.5, 0)
        // substitutes' bench (also the "break" spot)
        let b = root.group("prop:coffee", Environments.wx(Theme.football.coffee.x), 0, Environments.wz(Theme.football.coffee.y) - 0.6)
        b.box(3.2, 0.12, 0.7, Gfx.mat(0xd9d9d9, m: 0.4), 0, 0.6, 0)
        b.box(3.2, 0.9, 0.08, Gfx.mat(0x2b4a8a, r: 0.5, alpha: 0.55), 0, 0.9, -0.3)
        b.box(3.4, 0.08, 1.0, Gfx.mat(0x2b4a8a, r: 0.6), 0, 1.5, -0.1)
        for x in [-1.1, -0.5, 0.1, 0.7, 1.3] { b.box(0.08, 0.6, 0.08, Gfx.mat(0x888d94, m: 0.8), x, 0.3, 0) }
        b.cyl(0.1, 0.3, Gfx.mat(0x4aa3e8, r: 0.3), 1.0, 0.8, 0.1)
        // ball by the centre spot
        let ball = root.add(SCNSphere(radius: 0.22), Gfx.mat(0xfafafa, r: 0.45), at: SCNVector3(-3.5, 0.22, 3.6), name: "prop:ball")
        ball.runAction(.repeatForever(.sequence([.wait(duration: 1.6), .move(by: SCNVector3(0, 0.3, 0), duration: 0.18), .move(by: SCNVector3(0, -0.3, 0), duration: 0.18)])))
    }

    // MARK: Farm

    static func tree(_ root: SCNNode, _ x: CGFloat, _ z: CGFloat, _ s: CGFloat = 1) {
        root.cyl(0.22 * s, 1.6 * s, Gfx.mat(0x6b4a2f, r: 0.9), x, 0.8 * s, z)
        root.ball(1.1 * s, Gfx.mat(0x3f8f3a, r: 0.9), x, 2.2 * s, z)
        root.ball(0.8 * s, Gfx.mat(0x4aa043, r: 0.9), x + 0.5 * s, 2.7 * s, z + 0.1)
    }

    static func hay(_ root: SCNNode, _ x: CGFloat, _ z: CGFloat) {
        let m = Gfx.mat(0xe2c25a, r: 0.95)
        let n = root.cyl(0.55, 0.8, m, x, 0.4, z)
        n.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        n.position.y = 0.55
    }

    static func farm(_ root: SCNNode) {
        root.add(SCNPlane(width: 120, height: 40), Gfx.texMat(Gfx.skyGradient(), emissive: true), at: SCNVector3(0, 9, -12), shadow: false)
        floor(root, Gfx.texMat(Gfx.speckle(0x6fae4c, 0x5a9a3c, count: 2200, size: 4), r: 0.98, repeatX: 6, repeatY: 3))
        // dirt path
        root.box(38, 0.05, 1.6, Gfx.mat(0xb08a5a, r: 0.95), 0, 0.02, 7.6)
        // fence
        for i in 0..<20 {
            root.box(0.15, 1.1, 0.15, Gfx.mat(0x9a6b3c, r: 0.9), -17.4 + CGFloat(i) * 1.85, 0.55, -0.4)
        }
        root.box(38, 0.12, 0.08, Gfx.mat(0xb07d46, r: 0.9), 0, 0.85, -0.4)
        root.box(38, 0.12, 0.08, Gfx.mat(0xb07d46, r: 0.9), 0, 0.4, -0.4)
        // hills and trees
        root.add(SCNSphere(radius: 7), Gfx.mat(0x7fba5a, r: 1), at: SCNVector3(-8, -2.5, -4.5), shadow: false)
        root.add(SCNSphere(radius: 8), Gfx.mat(0x6aa94a, r: 1), at: SCNVector3(4, -3.8, -6), shadow: false)
        tree(root, -16, -1.5, 1.2); tree(root, -13.5, -2.4, 0.9); tree(root, 3.5, -2.2, 1.1)
        // barn (right) – where the flock arrives and heads home
        let barn = root.group("prop:barn", 13.3, 0, 0.6)
        let red = Gfx.mat(0xb8322a, r: 0.8)
        barn.box(5.4, 3.0, 3.2, red, 0, 1.5, 0)
        let roof = barn.box(5.9, 0.25, 3.8, Gfx.mat(0x5a2c20, r: 0.8), 0, 3.5, 0)
        roof.eulerAngles = SCNVector3(0, 0, 0)
        barn.box(5.6, 0.7, 3.5, Gfx.mat(0x5a2c20, r: 0.8), 0, 3.35, 0)
        barn.box(2.0, 2.2, 0.1, Gfx.mat(0x7a1e18, r: 0.8), 0, 1.1, 1.62)
        for s in [-1.0, 1.0] {
            let d = barn.box(0.08, 2.4, 0.06, Gfx.mat(0xf1e7d0), 0, 1.1, 1.7)
            d.eulerAngles = SCNVector3(0, 0, Float(s) * 0.7)
        }
        barn.box(2.1, 0.12, 0.1, Gfx.mat(0xf1e7d0), 0, 2.3, 1.7)
        barn.box(0.9, 0.6, 0.1, Gfx.mat(0x2b2018), 0, 3.4, 1.8)
        hay(root, 10.6, 0.2); hay(root, 16.4, 2.6)
        // windmill (left back)
        let mill = root.group("prop:windmill", -11.5, 0, -0.9)
        let cone = mill.add(SCNCone(topRadius: 0.55, bottomRadius: 1.0, height: 4.2), Gfx.mat(0xf3eee2, r: 0.8), at: SCNVector3(0, 2.1, 0))
        cone.name = "prop:windmill"
        mill.add(SCNCone(topRadius: 0, bottomRadius: 0.75, height: 1.0), Gfx.mat(0x8a3b2c, r: 0.8), at: SCNVector3(0, 4.7, 0))
        let hub = mill.group("hub", 0, 4.1, 0.75)
        for i in 0..<4 {
            let blade = hub.group("blade", 0, 0, 0)
            blade.eulerAngles = SCNVector3(0, 0, Float(i) * Float.pi / 2)
            blade.box(0.5, 2.8, 0.05, Gfx.mat(0xf1e7d0, r: 0.8), 0, 1.5, 0)
        }
        hub.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: -.pi * 2, duration: 7)), forKey: "spin")
        // scarecrow
        let sc = root.group("prop:scarecrow", -4.2, 0, 0.6)
        sc.cyl(0.05, 2.2, Gfx.mat(0x6b4a2f), 0, 1.1, 0)
        sc.box(1.6, 0.08, 0.08, Gfx.mat(0x6b4a2f), 0, 1.6, 0)
        sc.box(0.7, 0.8, 0.3, Gfx.mat(0xb5532a, r: 0.9), 0, 1.5, 0)
        sc.ball(0.28, Gfx.mat(0xe2c25a, r: 0.9), 0, 2.2, 0)
        sc.cyl(0.35, 0.05, Gfx.mat(0x6b4a2f), 0, 2.45, 0)
        sc.cyl(0.2, 0.25, Gfx.mat(0x6b4a2f), 0, 2.58, 0)
        // well (idle spot)
        let w = root.group("prop:coffee", Environments.wx(Theme.farm.coffee.x), 0, Environments.wz(Theme.farm.coffee.y) - 0.7)
        w.cyl(0.8, 0.9, Gfx.mat(0x9a9a9a, r: 0.9), 0, 0.45, 0)
        w.cyl(0.62, 0.05, Gfx.mat(0x3a86c8, r: 0.1, e: 0x0b2a55, eIntensity: 0.5), 0, 0.88, 0)
        w.box(0.1, 1.6, 0.1, Gfx.mat(0x6b4a2f), -0.7, 1.6, 0)
        w.box(0.1, 1.6, 0.1, Gfx.mat(0x6b4a2f), 0.7, 1.6, 0)
        let wr = w.box(1.8, 0.12, 0.7, Gfx.mat(0x8a3b2c), 0, 2.4, 0)
        wr.eulerAngles = SCNVector3(0, 0, 0)
        // flowers
        for i in 0..<14 {
            let x = -15 + CGFloat(i) * 2.3, z = 8.4 + CGFloat(i % 3) * 0.5
            root.cyl(0.02, 0.35, Gfx.mat(0x3d7a2c), x, 0.18, z)
            root.ball(0.09, Gfx.mat([0xe2506a, 0xf0c040, 0xffffff, 0xb06ad8][i % 4], r: 0.5), x, 0.4, z)
        }
    }

    // MARK: Station props

    static func stationProp(_ theme: Theme, _ kind: Int, _ n: SCNNode) {
        let scr = { (bg: UInt32, fg: UInt32, s: Int) in Gfx.texMat(Gfx.screen(bg, fg, seed: UInt64(kind * 5 + s), style: s), emissive: true) }
        switch theme {
        case .impostor: impostorStation(kind, n)
        case .wizard: wizardStation(kind, n)
        case .galactic: galacticStation(kind, n)
        case .fellowship: fellowshipStation(kind, n)
        case .space:
            let tint: UInt32 = 0x3fd0ff
            let bodyM = Gfx.mat(0x3a4558, r: 0.4, m: 0.5)
            switch kind {
            case 0:
                n.box(2.6, 0.9, 0.9, bodyM, 0, 0.45, 0, round: 0.04)
                n.box(0.9, 0.55, 0.05, scr(0x08141f, tint, 0), -0.7, 1.4, 0)
                n.box(0.9, 0.55, 0.05, scr(0x08141f, tint, 1), 0.7, 1.4, 0)
            case 1:
                n.box(2.4, 0.8, 0.9, Gfx.mat(0x4a5568, m: 0.3), 0, 0.4, 0, round: 0.04)
                n.box(0.8, 0.04, 0.6, Gfx.mat(0xb0b8c4, m: 0.8), 0, 0.82, 0.05)
                n.box(0.8, 0.5, 0.05, scr(0x1a0d08, 0xf2661f, 1), 0.2, 1.3, -0.1)
                n.cyl(0.07, 0.5, Gfx.mat(0xe8a13a, m: 0.7), -0.8, 1.05, 0.1)
            case 2:
                n.box(2.2, 1.0, 0.8, bodyM, 0, 0.5, 0, round: 0.04)
                let s = n.box(1.4, 0.8, 0.05, scr(0x0a1a12, tint, 2), 0, 1.6, 0)
                s.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.8, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])))
                n.ball(0.1, Gfx.mat(0x35e0a1, e: 0x35e0a1), -0.9, 1.05, 0.3)
            default:
                n.box(2.0, 0.9, 0.8, bodyM, 0, 0.45, 0, round: 0.04)
                n.ball(0.5, Gfx.mat(0x2d78c8, r: 0.5, e: 0x0b2a55, eIntensity: 0.8), 0, 1.5, 0)
                n.add(SCNTorus(ringRadius: 0.62, pipeRadius: 0.02), Gfx.mat(tint, e: tint), at: SCNVector3(0, 1.5, 0))
            }
        case .kitchen:
            let steel = Gfx.mat(0xb5bbc4, r: 0.3, m: 0.85)
            switch kind {
            case 0:
                n.box(2.4, 0.95, 0.9, Gfx.mat(0x8a5a35), 0, 0.48, 0)
                for k in 0..<3 { n.box(0.55, 0.45, 0.55, Gfx.mat(0xb07a45), -0.8 + CGFloat(k) * 0.8, 1.15, 0, round: 0.03) }
                n.ball(0.2, Gfx.mat(0xc8372d, r: 0.4), -0.8, 1.55, 0)
            case 1:
                n.box(2.4, 0.95, 0.9, steel, 0, 0.48, 0)
                n.box(1.1, 0.06, 0.6, Gfx.mat(0xd7b27a, r: 0.7), -0.2, 1.0, 0.05)
                n.ball(0.14, Gfx.mat(0x6aa84f, r: 0.5), -0.4, 1.12, 0.05)
                n.box(0.4, 0.04, 0.08, steel, 0.4, 1.06, 0.05)
            case 2:
                n.box(2.4, 0.95, 0.9, steel, 0, 0.48, 0)
                n.cyl(0.4, 0.4, Gfx.mat(0x6b7280, r: 0.3, m: 0.9), -0.4, 1.15, 0)
                n.cyl(0.33, 0.04, Gfx.mat(0x8a3b12, r: 0.6), -0.4, 1.33, 0)
                n.cyl(0.28, 0.28, Gfx.mat(0xc8372d, r: 0.3, m: 0.5), 0.6, 1.1, 0)
            default:
                n.box(2.6, 0.95, 0.9, steel, 0, 0.48, 0)
                n.box(0.9, 0.25, 0.6, Gfx.mat(0x6b7280, m: 0.9), -0.7, 1.0, 0)
                for k in 0..<3 { n.cyl(0.3, 0.05, Gfx.mat(0xffffff, r: 0.2), 0.5, 1.0 + CGFloat(k) * 0.06, 0) }
            }
        case .football:
            let ballM = Gfx.mat(0xfafafa, r: 0.45)
            switch kind {
            case 0:
                for k in 0..<4 {
                    let c = n.add(SCNCone(topRadius: 0.05, bottomRadius: 0.22, height: 0.4), Gfx.mat(0xff7a1a, r: 0.6), at: SCNVector3(-1.2 + CGFloat(k) * 0.8, 0.2, 0.2))
                    c.castsShadow = true
                }
                n.ball(0.2, ballM, 0.4, 0.2, 0.6)
            case 1:
                goal(n, scale: 0.7)
                for k in 0..<3 { n.ball(0.18, ballM, -0.6 + CGFloat(k) * 0.6, 0.18, 0.9) }
            case 2:
                for k in 0..<3 {
                    n.cyl(0.25, 1.3, Gfx.mat(0x2b4a8a, r: 0.7), -1.0 + CGFloat(k) * 1.0, 0.65, 0)
                    n.ball(0.22, Gfx.mat(0xe0b890, r: 0.8), -1.0 + CGFloat(k) * 1.0, 1.5, 0)
                }
            default:
                n.box(2.2, 1.3, 0.1, Gfx.mat(0xf2f2f2, r: 0.5), 0, 1.5, 0)
                n.box(2.4, 1.5, 0.05, Gfx.mat(0x555a60, m: 0.7), 0, 1.5, -0.08)
                n.box(2.0, 1.1, 0.02, Gfx.texMat(Gfx.image(256, 160) { c in
                    c.setFillColor(Gfx.color(0x2f8a3a).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 160))
                    c.setStrokeColor(NSColor.white.cgColor); c.setLineWidth(3)
                    c.stroke(CGRect(x: 8, y: 8, width: 240, height: 144))
                    for (x, y) in [(60, 50), (110, 100), (160, 40), (200, 110), (130, 70)] {
                        c.setFillColor(Gfx.color(0xffd400).cgColor); c.fillEllipse(in: CGRect(x: x, y: y, width: 14, height: 14))
                    }
                }), 0, 1.5, 0.07)
                n.cyl(0.04, 1.3, Gfx.mat(0x555a60, m: 0.7), -0.9, 0.65, 0)
                n.cyl(0.04, 1.3, Gfx.mat(0x555a60, m: 0.7), 0.9, 0.65, 0)
            }
        case .farm:
            switch kind {
            case 0:
                for k in 0..<6 {
                    n.add(SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.5), Gfx.mat(0x4aa043, r: 0.9), at: SCNVector3(-1.3 + CGFloat(k) * 0.52, 0.25, 0.1 * CGFloat(k % 2)))
                }
                n.box(2.6, 0.06, 0.9, Gfx.mat(0x5a9a3c, r: 1), 0, 0.03, 0.2)
            case 1:
                n.box(2.0, 0.3, 1.0, Gfx.mat(0xe9d5f0, r: 0.9), 0, 0.15, 0.2)
                n.box(2.0, 0.3, 0.3, Gfx.mat(0xe9d5f0, r: 0.9), 0, 0.45, -0.3)
                n.cyl(0.2, 0.3, Gfx.mat(0x4aa3e8, r: 0.4), 1.4, 0.15, 0.3)
                n.box(0.5, 0.12, 0.3, Gfx.mat(0xf2f2f2, r: 0.7), -1.4, 0.18, 0.4)
                n.add(SCNCone(topRadius: 0, bottomRadius: 0.3, height: 0.6), Gfx.mat(0x7fd1c8, r: 0.6), at: SCNVector3(1.4, 0.8, 0.3))
            case 2:
                n.box(2.4, 0.5, 0.8, Gfx.mat(0x8a5a35, r: 0.9), 0, 0.25, 0.1)
                n.box(2.1, 0.08, 0.55, Gfx.mat(0x3a86c8, r: 0.1, e: 0x0b2a55, eIntensity: 0.5), 0, 0.5, 0.1)
                n.cyl(0.35, 0.7, Gfx.mat(0x9a6b3c, r: 0.9), -1.6, 0.35, 0.3)
            default:
                for k in 0..<5 {
                    n.cyl(0.04, 1.1, Gfx.mat(0x3d7a2c), -1.2 + CGFloat(k) * 0.6, 0.55, 0.1 * CGFloat(k % 2))
                    n.cyl(0.24, 0.06, Gfx.mat(0xf2b81c, r: 0.5, e: 0x6a4a00), -1.2 + CGFloat(k) * 0.6, 1.12, 0.1 * CGFloat(k % 2))
                    n.cyl(0.1, 0.07, Gfx.mat(0x5a3b1c), -1.2 + CGFloat(k) * 0.6, 1.14, 0.1 * CGFloat(k % 2))
                }
            }
        case .prison:
            switch kind {
            case 0:
                n.box(3.2, 0.25, 1.1, Gfx.mat(0x6b4a2f, r: 0.9), 0, 0.12, 0)
                for k in 0..<5 {
                    n.cyl(0.03, 0.4, Gfx.mat(0x3d7a2c), -1.2 + CGFloat(k) * 0.6, 0.45, 0)
                    n.ball(0.14, Gfx.mat([0xe2506a, 0xf0c040, 0xd34fd0, 0xff8f3a, 0xe2506a][k], r: 0.5), -1.2 + CGFloat(k) * 0.6, 0.7, 0)
                }
            case 1:
                n.box(3.6, 2.2, 0.2, Gfx.mat(0xbdb7ab, r: 0.9), 0, 1.1, 0.7)
                n.box(1.0, 0.7, 0.01, Gfx.mat(0x3f7fd6, r: 0.7), -0.5, 1.4, 0.82)
                n.box(0.8, 0.5, 0.01, Gfx.mat(0xf08a1e, r: 0.7), 0.7, 1.0, 0.82)
                n.box(0.5, 0.45, 0.4, Gfx.mat(0xd9d5c8), 1.5, 0.22, 0.2)
            case 2:
                n.box(0.2, 1.4, 0.2, Gfx.mat(0x555a60, m: 0.8), -1.2, 0.7, 0.4)
                n.box(0.5, 0.18, 0.5, Gfx.mat(0xe2a63a), -1.2, 1.5, 0.4)
                n.cyl(0.35, 0.6, Gfx.mat(0x6b7280, m: 0.8), 1.2, 0.3, 0.3)
            default:
                n.cyl(0.35, 0.85, Gfx.mat(0x3d6b4f, r: 0.6, m: 0.2), 1.0, 0.43, 0.3)
                n.box(0.4, 0.04, 0.4, Gfx.mat(0x2c3a30), 1.0, 0.87, 0.3)
                for k in 0..<4 { n.box(0.2, 0.06, 0.15, Gfx.mat([0xdad3c0, 0x87b0d8, 0xe8c15a, 0xcdd7dd][k]), -0.8 + CGFloat(k) * 0.35, 0.05, 0.9) }
            }
        }
    }
}
