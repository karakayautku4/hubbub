import AppKit
import SceneKit

// Sneaky Ship: a bean-crew spaceship parody. Everything theme-specific lives here; shared files only call these entry points.

private enum Imp {
    static func shade(_ hex: UInt32, _ k: CGFloat) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, CGFloat((hex >> s) & 255) * k))) }
        return ch(16) << 16 | ch(8) << 8 | ch(0)
    }

    static let crew: [UInt32] = [0x3b5bdb, 0x2f9e44, 0xf783ac, 0xf59f00, 0xffd43b, 0x495057, 0x1098ad, 0x7048e8, 0x74b816, 0x8b5a2b, 0xe9ecef]

    static func text(_ lines: [String], w: CGFloat, h: CGFloat, bg: NSColor, fg: NSColor, size: CGFloat, border: NSColor? = nil) -> NSImage {
        NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            bg.setFill(); r.fill()
            if let border { border.setStroke(); let p = NSBezierPath(rect: r.insetBy(dx: 4, dy: 4)); p.lineWidth = 6; p.stroke() }
            let font = NSFont.systemFont(ofSize: size, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
            let lh = size * 1.15
            var y = r.midY + lh * CGFloat(lines.count) / 2 - lh
            for l in lines {
                let s = (l as NSString).size(withAttributes: attrs)
                (l as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: y), withAttributes: attrs)
                y -= lh
            }
            return true
        }
    }

    static func hazard() -> NSImage {
        Gfx.image(128, 32) { c in
            c.setFillColor(Gfx.color(0x23252b).cgColor); c.fill(CGRect(x: 0, y: 0, width: 128, height: 32))
            c.setFillColor(Gfx.color(0xf2c230).cgColor)
            for i in stride(from: -32, to: 160, by: 32) {
                c.move(to: CGPoint(x: i, y: 0)); c.addLine(to: CGPoint(x: i + 16, y: 0))
                c.addLine(to: CGPoint(x: i + 48, y: 32)); c.addLine(to: CGPoint(x: i + 32, y: 32)); c.fillPath()
            }
        }
    }

    static func blink(_ n: SCNNode, every: Double) {
        n.runAction(.repeatForever(.sequence([.wait(duration: every), .scale(to: 0.05, duration: 0.07), .scale(to: 1, duration: 0.09)])))
    }

    @discardableResult
    static func bean(_ n: SCNNode, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, r: CGFloat = 0.45, h: CGFloat = 1.6) -> SCNNode {
        n.add(SCNCapsule(capRadius: r, height: h), m, at: SCNVector3(x, y, z))
    }
}

extension Environments {
    /// Room, floor, walls, ambient props and animated set pieces.
    static func impostor(_ root: SCNNode) {
        let metal = Gfx.mat(0x8b95a5, r: 0.35, m: 0.8)
        let hullM = Gfx.mat(0x4a5364, r: 0.55, m: 0.4)
        floor(root, Gfx.texMat(Gfx.tiles(0x6b7587, 0x626c7e, grout: 0x2a2f3a, cells: 6), r: 0.4, m: 0.5, repeatX: 5, repeatY: 2))
        root.box(38, 7, 0.4, hullM, 0, 3.5, -0.4)
        // lower wall band, hazard strip and ceiling trim
        root.box(38, 1.1, 0.25, Gfx.mat(0x343b49, r: 0.6, m: 0.5), 0, 0.55, -0.15)
        root.box(38, 0.3, 0.1, Gfx.texMat(Imp.hazard(), r: 0.6, repeatX: 24, repeatY: 1), 0, 1.25, -0.02)
        root.box(38, 0.5, 0.5, Gfx.mat(0x2b303b, m: 0.6), 0, 6.8, -0.3)
        for x in stride(from: -17.0, through: 17.0, by: 6.0) {
            root.box(2.4, 0.12, 0.3, Gfx.mat(0xfff4d0, e: 0xfff1c0, eIntensity: 0.9), x, 6.5, -0.05)
        }
        // wall panels with rivets
        for x in stride(from: -16.0, through: 16.0, by: 4.0) {
            root.box(0.08, 3.6, 0.12, Gfx.mat(0x2f3644, m: 0.7), x, 3.5, -0.12)
        }
        // observation windows
        for x in [-9.5, 2.5] {
            root.box(5.6, 3.0, 0.1, Gfx.texMat(Gfx.stars(), emissive: true), x, 4.0, -0.18)
            for (dx, dy, w, h) in [(0.0, 1.55, 5.9, 0.16), (0.0, -1.55, 5.9, 0.16), (-2.95, 0.0, 0.16, 3.2), (2.95, 0.0, 0.16, 3.2), (0.0, 0.0, 0.1, 3.0)] {
                root.box(CGFloat(w), CGFloat(h), 0.22, metal, x + dx, 4.0 + dy, -0.08)
            }
        }
        let planet = root.add(SCNSphere(radius: 0.95), Gfx.mat(0xd9602e, r: 0.7, e: 0x4a1a08, eIntensity: 0.6), at: SCNVector3(3.6, 4.0, -0.1), name: "prop:planet", shadow: false)
        planet.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 80)))
        root.add(SCNTorus(ringRadius: 1.4, pipeRadius: 0.04), Gfx.mat(0xf0d6a0, e: 0x5a4a28), at: SCNVector3(3.6, 4.0, -0.1), name: "prop:planet", shadow: false).eulerAngles = SCNVector3(1.3, 0, 0.25)
        let moon = root.add(SCNSphere(radius: 0.45), Gfx.mat(0x9aa4b8, r: 0.9, e: 0x20242c), at: SCNVector3(-8.3, 4.3, -0.1), shadow: false)
        moon.name = "moon"

        // posters
        let poster = root.group("poster1", -14.0, 3.9, -0.15)
        poster.box(1.9, 2.4, 0.06, Gfx.texMat(Imp.text(["WHO", "LEFT THE", "HATCH", "OPEN?"], w: 190, h: 240, bg: NSColor(red: 0.95, green: 0.9, blue: 0.7, alpha: 1), fg: NSColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1), size: 30, border: NSColor(white: 0.15, alpha: 1)), r: 0.9), 0, 0, 0)
        let poster2 = root.group("poster2", 9.2, 3.9, -0.15)
        poster2.box(2.6, 1.8, 0.06, Gfx.texMat(Imp.text(["TRUST NO BEAN", "👀 stay in groups"], w: 260, h: 180, bg: NSColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 1), fg: NSColor(red: 0.6, green: 0.95, blue: 1, alpha: 1), size: 26, border: NSColor(red: 0.84, green: 0.14, blue: 0.16, alpha: 1)), emissive: true), 0, 0, 0)

        // sliding door on the left, where the crew boards
        let door = root.group("prop:airlock", -15.8, 0, 3.5)
        door.box(0.4, 3.6, 3.6, Gfx.mat(0x7e8896, m: 0.8), 0, 1.8, 0)
        door.box(0.1, 3.0, 1.5, Gfx.mat(0x1b2230, m: 0.5), 0.22, 1.6, -0.76)
        door.box(0.1, 3.0, 1.5, Gfx.mat(0x1b2230, m: 0.5), 0.22, 1.6, 0.76)
        door.box(0.06, 0.25, 1.2, Gfx.mat(0xf2c230, e: 0xf2c230), 0.26, 3.3, 0)

        // vent with two sneaky eyes peeking out
        let vent = root.group("prop:vent", -5.4, 0, 0.0)
        vent.box(2.0, 1.2, 0.2, Gfx.mat(0x2a2e38, r: 0.5, m: 0.6), 0, 2.4, -0.1, round: 0.04)
        vent.box(1.7, 0.9, 0.05, Gfx.mat(0x050608), 0, 2.4, 0.0)
        let eyes = vent.group("eyes", 0, 2.45, 0.02)
        for x in [-0.28, 0.28] { eyes.box(0.22, 0.2, 0.03, Gfx.mat(0xff3b3b, e: 0xff2020, eIntensity: 1.2), x, 0, 0) }
        Imp.blink(eyes, every: 3.4)
        for i in 0..<5 { vent.box(1.8, 0.07, 0.08, Gfx.mat(0x8e97a6, m: 0.8), 0, 2.0 + CGFloat(i) * 0.19, 0.08) }

        // reactor on the right, glowing
        let r = root.group("prop:reactor", 14.2, 0, 1.0)
        r.cyl(1.1, 0.4, Gfx.mat(0x5b6678, m: 0.8), 0, 0.2, 0)
        let core = r.cyl(0.6, 2.4, Gfx.mat(0x7be9ff, r: 0.1, e: 0x2bb6e6, eIntensity: 1.2, alpha: 0.85), 0, 1.6, 0)
        pulse(core, 0.08, 0.9)
        for y in [0.9, 1.6, 2.3] { r.add(SCNTorus(ringRadius: 0.85, pipeRadius: 0.07), Gfx.mat(0x9aa7b5, m: 0.9), at: SCNVector3(0, CGFloat(y), 0)) }
        r.cyl(0.9, 0.2, Gfx.mat(0x5b6678, m: 0.8), 0, 3.0, 0)

        // trash chute: leaves, a banana peel and a lonely sock
        let chute = root.group("prop:chute", -12.0, 0, 0.5)
        chute.box(1.8, 2.0, 1.0, Gfx.mat(0x3d4452, m: 0.6), 0, 1.0, 0, round: 0.05)
        chute.box(1.2, 0.9, 0.06, Gfx.mat(0x101319), 0, 1.3, 0.52)
        chute.box(1.3, 0.12, 0.2, Gfx.mat(0xf2c230), 0, 1.9, 0.52)
        chute.ball(0.16, Gfx.mat(0x6aa84f, r: 0.6), -0.4, 0.14, 0.9)
        chute.ball(0.13, Gfx.mat(0xe8d34a, r: 0.6), 0.3, 0.1, 1.0)
        chute.cyl(0.07, 0.3, Gfx.mat(0xd8d8d8, r: 0.9), 0.6, 0.1, 0.85).eulerAngles = SCNVector3(0, 0, 1.4)

        // emergency siren on the wall
        let siren = root.group("siren", 12.2, 5.6, 0.0)
        siren.cyl(0.35, 0.1, Gfx.mat(0x3a404c, m: 0.7), 0, 0, 0).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        let lamp = siren.ball(0.3, Gfx.mat(0xff2a2a, r: 0.2, e: 0xff1a1a, eIntensity: 0.5, alpha: 0.9), 0, 0, 0.12)
        lamp.scale = SCNVector3(1, 1, 0.6)
        lamp.runAction(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.7), .scale(to: 0.85, duration: 0.7)])))

        // potted sprout and a cheerful banana for crew morale
        let plant = root.group("prop:plant", 16.4, 0, 3.4)
        plant.cyl(0.4, 0.6, Gfx.mat(0xb5653a, r: 0.7), 0, 0.3, 0)
        plant.cyl(0.05, 0.9, Gfx.mat(0x4f9a3a), 0, 1.0, 0)
        for s in [-1.0, 1.0] { plant.ball(0.26, Gfx.mat(0x6fc24a, r: 0.6), CGFloat(s) * 0.25, 1.5, 0).scale = SCNVector3(1.3, 0.45, 0.8) }

        // main console: captain's blinking desk
        let c = root.group("prop:console", 0.5, 0, 0.55)
        c.box(3.0, 0.9, 1.0, Gfx.mat(0x2a3142, m: 0.6), 0, 0.45, 0, round: 0.05)
        c.box(2.2, 0.8, 0.06, Gfx.texMat(Gfx.screen(0x061425, 0x7be9ff, seed: 7, style: 2), emissive: true), 0, 1.4, -0.2)
        c.box(0.3, 0.12, 0.3, Gfx.mat(0xff3b3b, e: 0xff2020, eIntensity: 0.8), 1.0, 0.96, 0.1)
        coffee(root, .impostor)
    }

    /// Prop for one work station; `kind` 0 data, 1 wires, 2 engines, 3 meeting table (see `Theme.stations`).
    static func impostorStation(_ kind: Int, _ n: SCNNode) {
        let body = Gfx.mat(0x3a4558, r: 0.4, m: 0.5)
        switch kind {
        case 0:
            // download terminal with a creeping progress bar
            n.box(2.4, 0.9, 0.9, body, 0, 0.45, 0, round: 0.04)
            n.box(1.9, 1.0, 0.08, Gfx.mat(0x0b1220, r: 0.3), 0, 1.5, -0.2)
            n.box(1.6, 0.18, 0.04, Gfx.mat(0x1c2b44), 0, 1.3, -0.15)
            let bar = n.box(1.6, 0.18, 0.05, Gfx.mat(0x3ddc84, e: 0x3ddc84, eIntensity: 0.9), 0, 1.3, -0.14)
            bar.pivot = SCNMatrix4MakeTranslation(-0.8, 0, 0)
            bar.position.x = -0.8
            bar.scale = SCNVector3(0.1, 1, 1)
            bar.runAction(.repeatForever(.sequence([.scale(to: 1, duration: 4), .wait(duration: 0.6), .scale(to: 0.1, duration: 0.01)])))
            n.box(1.7, 0.3, 0.04, Gfx.texMat(Gfx.screen(0x08141f, 0x7be9ff, seed: 11, style: 1), emissive: true), 0, 1.75, -0.14)
            n.box(0.5, 0.4, 0.4, Gfx.mat(0xd9dde4, r: 0.4), 0.8, 1.1, 0.1, round: 0.04)
        case 1:
            // open wire panel: match the colours!
            n.box(2.2, 0.8, 0.9, body, 0, 0.4, 0, round: 0.04)
            n.box(1.7, 1.3, 0.12, Gfx.mat(0x6b7587, m: 0.7), 0, 1.45, -0.2, round: 0.03)
            n.box(1.4, 1.0, 0.04, Gfx.mat(0x12151c), 0, 1.45, -0.12)
            let cols: [UInt32] = [0xe03131, 0x3b5bdb, 0xf2c230, 0xf783ac]
            for (i, col) in cols.enumerated() {
                let y = 1.75 - CGFloat(i) * 0.22
                n.box(1.15, 0.05, 0.04, Gfx.mat(col, r: 0.4), 0, y + CGFloat(i % 2) * 0.03, -0.09)
                n.ball(0.07, Gfx.mat(col, e: col), -0.62, y, -0.08)
                n.ball(0.07, Gfx.mat(col, e: col), 0.62, y, -0.08)
            }
            let spark = n.ball(0.07, Gfx.mat(0xfff2a0, e: 0xffee70, eIntensity: 1.4), 0.5, 1.45, -0.05)
            spark.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.1, duration: 0.2), .wait(duration: 1.1), .fadeOpacity(to: 1, duration: 0.1)])))
        case 2:
            // engine block with a fuel canister
            n.box(2.0, 1.0, 0.9, body, 0, 0.5, 0, round: 0.04)
            let core = n.cyl(0.4, 1.0, Gfx.mat(0x7be9ff, r: 0.1, e: 0x2bb6e6, eIntensity: 1.0, alpha: 0.85), -0.3, 1.5, 0)
            pulse(core, 0.07, 0.8)
            n.add(SCNTorus(ringRadius: 0.5, pipeRadius: 0.05), Gfx.mat(0x9aa7b5, m: 0.9), at: SCNVector3(-0.3, 1.3, 0))
            n.add(SCNTorus(ringRadius: 0.5, pipeRadius: 0.05), Gfx.mat(0x9aa7b5, m: 0.9), at: SCNVector3(-0.3, 1.7, 0))
            n.cyl(0.28, 0.7, Gfx.mat(0xd6232a, r: 0.35, m: 0.3), 0.7, 1.35, 0.05)
            n.cyl(0.1, 0.1, Gfx.mat(0xf2c230, m: 0.6), 0.7, 1.75, 0.05)
            n.cyl(0.04, 0.5, Gfx.mat(0x22252c), 0.4, 1.2, 0.2).eulerAngles = SCNVector3(0, 0, 1.2)
        default:
            // cafeteria table, benches and the big red button
            n.cyl(1.0, 0.12, Gfx.mat(0xd9dde4, r: 0.4), 0, 0.85, 0)
            n.cyl(0.18, 0.8, Gfx.mat(0x7e8896, m: 0.8), 0, 0.4, 0)
            n.cyl(0.5, 0.08, Gfx.mat(0x7e8896, m: 0.8), 0, 0.04, 0)
            for (i, x) in [-1.3, 1.3].enumerated() {
                n.box(0.4, 0.3, 1.5, Gfx.mat(i == 0 ? 0xd6232a : 0x3b5bdb, r: 0.6), CGFloat(x), 0.3, 0.1, round: 0.06)
            }
            n.cyl(0.28, 0.1, Gfx.mat(0x2b303b, m: 0.6), 0, 0.96, 0)
            let btn = n.add(SCNSphere(radius: 0.2), Gfx.mat(0xff2a2a, r: 0.2, e: 0xff1a1a, eIntensity: 0.6), at: SCNVector3(0, 1.0, 0), name: "prop:alarm")
            btn.scale = SCNVector3(1, 0.6, 1)
            pulse(btn, 0.08, 0.7)
        }
    }
}

extension Rig {
    /// (top, bottom, accent) colours; `v` is a per-actor variant index.
    static func impostorOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        let top = captain ? 0xd6232a : Imp.crew[v % Imp.crew.count]
        return (top, Imp.shade(top, 0.72), captain ? 0xf2c230 : 0x9be8ff)
    }
    /// Visor, backpack, hats etc. added to the head/body. Replaces the stock human body with a bean.
    static func impostorAccessories(captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let body = rig.body, head = rig.head
        func mat(_ n: SCNNode?) -> SCNMaterial? { n?.geometry?.materials.first }
        let botM = mat(rig.legL.childNodes.first) ?? topM
        head.childNodes.forEach { $0.isHidden = true }
        body.childNodes.filter { $0 !== rig.armL && $0 !== rig.armR && $0 !== head }.forEach { $0.isHidden = true }
        for leg in [rig.legL, rig.legR] {
            leg.childNodes.forEach { $0.isHidden = true }
            Imp.bean(leg, botM, 0, -0.5, 0, r: 0.15, h: 0.56)
        }
        for arm in [rig.armL, rig.armR] {
            arm.childNodes.filter { $0 !== rig.handR }.forEach { $0.isHidden = true }
            Imp.bean(arm, topM, 0, -0.27, 0, r: 0.1, h: 0.6)
        }
        Imp.bean(body, topM, 0, 0.35, 0, r: 0.38, h: 1.3)
        head.ball(0.37, topM, 0, 0.25, 0)
        let visor = Gfx.mat(0x9fe8ff, r: 0.08, m: 0.2, e: 0x1f6d88, eIntensity: 0.5)
        let v = head.add(SCNCapsule(capRadius: 0.14, height: 0.5), visor, at: SCNVector3(0, 0.34, 0.27))
        v.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        head.box(0.14, 0.05, 0.04, Gfx.mat(0xffffff, e: 0xffffff, eIntensity: 0.6), -0.08, 0.4, 0.4, round: 0.02)
        Imp.bean(body, botM, 0, 0.4, -0.45, r: 0.12, h: 0.7).scale = SCNVector3(1.7, 1, 1.1)

        if captain {
            head.cyl(0.33, 0.14, Gfx.mat(0xf4f4f8, r: 0.6), 0, 0.64, 0)
            head.box(0.5, 0.03, 0.2, Gfx.mat(0x14161c, r: 0.3), 0, 0.58, 0.3)
            head.ball(0.06, Gfx.mat(0xf2c230, m: 0.8, e: 0xf2c230, eIntensity: 0.4), 0, 0.66, 0.34)
            return
        }
        switch number % 6 {
        case 1:
            head.cyl(0.03, 0.22, Gfx.mat(0x4f9a3a), 0, 0.68, 0)
            for s in [-1.0, 1.0] { head.ball(0.12, Gfx.mat(0x6fc24a, r: 0.6), CGFloat(s) * 0.1, 0.8, 0).scale = SCNVector3(1.4, 0.4, 0.8) }
        case 2:
            head.add(SCNSphere(radius: 0.34), accM, at: SCNVector3(0, 0.36, 0)).scale = SCNVector3(1, 0.55, 1)
            head.cyl(0.02, 0.1, Gfx.mat(0x22252c), 0, 0.66, 0)
            let prop = head.group("prop", 0, 0.72, 0)
            prop.box(0.5, 0.02, 0.08, Gfx.mat(0xf2c230), 0, 0, 0)
            prop.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.6)))
        case 3:
            head.add(SCNCone(topRadius: 0, bottomRadius: 0.2, height: 0.42), Gfx.mat(0xf783ac, r: 0.5), at: SCNVector3(0, 0.78, 0))
            head.ball(0.06, Gfx.mat(0xffe066, e: 0xffe066), 0, 1.0, 0)
        case 4:
            head.cyl(0.02, 0.35, Gfx.mat(0x22252c), 0.12, 0.78, 0)
            head.ball(0.07, Gfx.mat(0xff5a4d, e: 0xff3b3b), 0.12, 0.98, 0)
        default: break
        }
    }
    /// Context-usage gauge shown on a worker (set `mv.fill`): a fuel tube on the backpack side.
    func impostorGauge(_ figure: SCNNode, metal: SCNMaterial) {
        let g = body.group("gauge", 0.44, 0.42, -0.3)
        g.cyl(0.13, 0.76, metal, 0, 0, 0)
        g.ball(0.13, metal, 0, 0.38, 0)
        let f = g.add(SCNCylinder(radius: 0.14, height: 0.64), tinted(0x3ddc84, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
        bottomAnchored(f, height: 0.64)
        mv.fill = f
    }
    /// Small beacon shown for approval requests: a tiny emergency siren.
    func impostorBeacon(_ beacon: SCNNode, metal: SCNMaterial) {
        beacon.cyl(0.07, 0.1, metal, 0, -0.14, 0)
        beacon.ball(0.13, tinted(0xff2a2a, e: true), 0, 0.0, 0).scale = SCNVector3(1, 0.85, 1)
    }
}

extension Stage {
    /// (background, ambient, ambient intensity, key, key intensity, fill).
    static func impostorLighting() -> (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) { (0x080a16, 0x9aa6d8, 520, 0xfff1de, 1400, 0x4f7ff0) }
    /// Work animation per tool kind (0 read, 1 write, 2 run, 3 other).
    static func impostorMotion(_ kind: Int) -> Motion { [.scan, .hammer, .type, .type][kind % 4] }
}

extension RoomSim {
    /// Failure effect: everyone suspects everyone, one shipmate gets dizzy and the captain calls a huddle.
    func impostorFailure(t: Double) {
        panicAll(t: t, line: "Sus!! 🚨")
        if let v = victim() {
            mutate(v.id) {
                $0.mood = .dizzy
                $0.moodUntil = t + 5
                $0.say = ["I was in the engine room!", "It wasn't me! 😳", "Why am I floating…"].randomElement()
                $0.sayUntil = t + 4
            }
        }
        mutate("captain") { $0.say = "Crew huddle! 📣"; $0.sayUntil = t + 3 }
    }
}



extension MetricsFmt {
    static var impostorMedal: String { "✅" }
}

extension RoomSign {
    /// Captain age sign; `minutes` is whole minutes, `txt` the formatted age.
    static func impostorAgeSign(age: Double, days: Int, minutes: Int, jersey: Int, txt: String) -> NSImage {
        Gfx.sign("🚀 Shift \(days)", "Alive for \(txt)", accent: 0xd6232a)
    }
}

extension SoundCenter {
    /// WAV data for this theme: short blips, a chime for finished tasks, and a siren for trouble.
    nonisolated static func impostorSynth(_ kind: Kind) -> Data? {
        switch kind {
        case .spawn: return wav(tone(freq: { $0 < 0.07 ? 523 : 784 }, dur: 0.16, decay: 6))
        case .success: return wav(tone(freq: { $0 < 0.1 ? 659 : ($0 < 0.2 ? 880 : 1175) }, dur: 0.4, decay: 3))
        case .failure: return wav(tone(freq: { 180 + 40 * sin($0 * 40) }, dur: 0.7, decay: 1.5, trem: 9, saw: true))
        case .alert: return wav(tone(freq: { 700 + 350 * sin($0 * 14) }, dur: 0.6, decay: 1, saw: true))
        }
    }
}
