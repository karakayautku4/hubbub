import AppKit
import SceneKit

// Software Office: an open-plan dev floor. The office manager walks the aisle while each agent works in a three-sided cubicle.
// Everything theme-specific lives here; shared files only call these entry points.

enum Off {
    static func shade(_ hex: UInt32, _ k: CGFloat) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, CGFloat((hex >> s) & 255) * k))) }
        return ch(16) << 16 | ch(8) << 8 | ch(0)
    }

    static let tops: [UInt32] = [0x4b5563, 0x2563eb, 0x16a34a, 0x9333ea, 0xea580c, 0x0d9488, 0xdb2777, 0x0891b2]

    static func text(_ lines: [String], w: CGFloat, h: CGFloat, bg: NSColor, fg: NSColor, size: CGFloat, border: NSColor? = nil) -> NSImage {
        NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            bg.setFill(); r.fill()
            if let border { border.setStroke(); let p = NSBezierPath(rect: r.insetBy(dx: 4, dy: 4)); p.lineWidth = 5; p.stroke() }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: fg]
            let lh = size * 1.2
            var y = r.midY + lh * CGFloat(lines.count) / 2 - lh
            for l in lines {
                let s = (l as NSString).size(withAttributes: attrs)
                (l as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: y), withAttributes: attrs)
                y -= lh
            }
            return true
        }
    }

    /// City skyline for the office windows.
    static func skyline(seed: UInt64) -> NSImage {
        Gfx.image(256, 128) { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [Gfx.color(0xbfe3ff).cgColor, Gfx.color(0x6fb4ee).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
            var rng = Gfx.RNG(s: seed)
            for layer in 0..<2 {
                var x: CGFloat = 0
                while x < 256 {
                    let w = 18 + rng.next() * 22, h = 30 + rng.next() * (layer == 0 ? 60 : 40)
                    c.setFillColor(Gfx.color(layer == 0 ? 0x8fb3d6 : 0x5f87b0).cgColor)
                    c.fill(CGRect(x: x, y: 0, width: w, height: h))
                    c.setFillColor(Gfx.color(0xffffff, 0.55).cgColor)
                    var wy: CGFloat = 6
                    while wy < h - 6 { c.fill(CGRect(x: x + 4, y: wy, width: max(3, w - 8), height: 2)); wy += 9 }
                    x += w + 2
                }
            }
        }
    }

    static func kanban() -> NSImage {
        Gfx.image(256, 160) { c in
            c.setFillColor(Gfx.color(0xf8fafc).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 160))
            c.setFillColor(Gfx.color(0xcbd5e1).cgColor)
            for x in [0, 85, 170, 255] { c.fill(CGRect(x: CGFloat(x), y: 0, width: 2, height: 160)) }
            c.fill(CGRect(x: 0, y: 130, width: 256, height: 2))
            let cols: [UInt32] = [0xfde047, 0xfb923c, 0x86efac, 0x7dd3fc, 0xf9a8d4]
            var rng = Gfx.RNG(s: 11)
            for col in 0..<3 {
                let n = [4, 3, 2][col]
                for i in 0..<n {
                    c.setFillColor(Gfx.color(cols[Int(rng.next() * 4.99)]).cgColor)
                    c.fill(CGRect(x: CGFloat(col) * 85 + 10, y: 100 - CGFloat(i) * 30, width: 62, height: 24))
                }
            }
        }
    }

    static func carpet() -> NSImage {
        Gfx.tiles(0x93a3b8, 0x8e9fb4, grout: 0x8798ae, cells: 12, noise: 0.04)
    }

    static func blink(_ n: SCNNode, every: Double) {
        n.runAction(.repeatForever(.sequence([.wait(duration: every), .fadeOpacity(to: 0.2, duration: 0.08), .fadeOpacity(to: 1, duration: 0.08)])))
    }

    static func plant(_ root: SCNNode, _ x: CGFloat, _ z: CGFloat, big: Bool = true) {
        let p = root.group("prop:plant", x, 0, z)
        p.cyl(0.4, 0.7, Gfx.mat(0xe5e7eb, r: 0.5), 0, 0.35, 0)
        p.cyl(0.36, 0.06, Gfx.mat(0x3b2a1a, r: 0.9), 0, 0.7, 0)
        let leaf = Gfx.mat(0x3f9a4a, r: 0.6)
        for i in 0..<(big ? 7 : 4) {
            let a = CGFloat(i) * 0.9
            let l = p.ball(0.3, leaf, cos(a) * 0.3, (big ? 1.1 : 0.95) + CGFloat(i % 3) * 0.28, sin(a) * 0.3)
            l.scale = SCNVector3(0.7, 1.5, 0.7)
        }
    }

    /// Three-sided cubicle around a job spot: the back wall sits away from the camera, the open side faces it.
    static func booth(_ n: SCNNode, color: UInt32 = 0x6f8fb3, number: Int = 0) {
        let back: CGFloat = n.eulerAngles.y > 0 ? 1 : -1
        let fabric = Gfx.mat(color, r: 0.95)
        let trim = Gfx.mat(shade(color, 0.55), r: 0.6)
        let h: CGFloat = 1.5
        n.box(0.1, h, 2.8, fabric, back * 0.95, h / 2, 0.55)
        n.box(0.14, 0.08, 2.9, trim, back * 0.95, h + 0.02, 0.55)
        for z in [-0.85, 1.95] as [CGFloat] {
            n.box(1.9, h, 0.1, fabric, 0, h / 2, z)
            n.box(1.95, 0.08, 0.14, trim, 0, h + 0.02, z)
        }
        // pinboard on the back wall with a few sticky notes and a number plate
        let board = n.box(0.03, 0.55, 0.9, Gfx.mat(0xd9b98a, r: 0.9), back * 0.88, 1.0, 1.25)
        _ = board
        let notes: [UInt32] = [0xfde047, 0xf9a8d4, 0x86efac, 0x7dd3fc]
        for i in 0..<4 {
            n.box(0.02, 0.17, 0.17, Gfx.mat(notes[(i + number) % 4], r: 0.9), back * 0.86, 1.1 - CGFloat(i / 2) * 0.22, 0.95 + CGFloat(i % 2) * 0.5)
        }
        n.box(0.02, 0.18, 0.4, Gfx.texMat(text(["#\(10 + number)"], w: 80, h: 36, bg: NSColor(white: 0.95, alpha: 1), fg: NSColor(white: 0.2, alpha: 1), size: 24), r: 0.6), back * 0.88, 1.32, -0.1)
        // bare desk; each job adds its own gear on top
        JP.table(n, 0xe4dccb, w: 1.5, d: 0.8, z: 1.15)
        // chair
        let chair = n.group("chair", 0, 0, -0.45)
        chair.cyl(0.28, 0.08, Gfx.mat(0x2d3748, r: 0.7), 0, 0.5, 0)
        chair.box(0.5, 0.55, 0.08, Gfx.mat(0x2d3748, r: 0.7), 0, 0.85, -0.25, round: 0.03)
        chair.cyl(0.04, 0.5, Gfx.mat(0x9ca3af, m: 0.8), 0, 0.25, 0)
    }
}

extension Environments {
    static func office(_ root: SCNNode) {
        let steel = Gfx.mat(0x9ca3af, r: 0.35, m: 0.7)
        floor(root, Gfx.texMat(Off.carpet(), r: 0.9, repeatX: 5, repeatY: 2.4))
        root.box(38, 7, 0.4, Gfx.mat(0xe8ecf1, r: 0.85), 0, 3.5, -0.4)
        root.box(38, 0.9, 0.25, Gfx.mat(0x4b5563, r: 0.6), 0, 0.45, -0.15)
        root.box(38, 0.35, 0.5, Gfx.mat(0xd1d5db, r: 0.7), 0, 6.8, -0.3)
        for x in stride(from: -17.0, through: 17.0, by: 5.0) {
            root.box(2.6, 0.12, 0.5, Gfx.mat(0xffffff, e: 0xffffff, eIntensity: 0.9), x, 6.55, 0.0)
        }

        // big windows over the city
        for (i, x) in [-11.0, 6.4].enumerated() {
            root.box(8.4, 3.6, 0.1, Gfx.texMat(Off.skyline(seed: UInt64(5 + i * 3)), r: 0.9, emissive: true), x, 3.9, -0.18)
            for (dx, dy, w, h) in [(0.0, 1.85, 8.7, 0.16), (0.0, -1.85, 8.7, 0.16), (-4.3, 0.0, 0.16, 3.9), (4.3, 0.0, 0.16, 3.9), (-1.4, 0.0, 0.08, 3.6), (1.4, 0.0, 0.08, 3.6)] {
                root.box(CGFloat(w), CGFloat(h), 0.2, steel, x + dx, 3.9 + dy, -0.08)
            }
        }

        // entrance door on the left where everyone arrives
        let door = root.group("prop:airlock", -15.8, 0, 3.5)
        door.box(0.3, 3.4, 3.2, Gfx.mat(0xcbd5e1, r: 0.5, m: 0.3), 0, 1.7, 0)
        door.box(0.1, 2.9, 1.3, Gfx.mat(0x7dc4ea, r: 0.1, alpha: 0.6), 0.18, 1.6, -0.7)
        door.box(0.1, 2.9, 1.3, Gfx.mat(0x7dc4ea, r: 0.1, alpha: 0.6), 0.18, 1.6, 0.7)
        door.box(0.08, 0.3, 1.8, Gfx.texMat(Off.text(["BYTE & CO"], w: 180, h: 30, bg: NSColor(red: 0.12, green: 0.25, blue: 0.5, alpha: 1), fg: .white, size: 22), emissive: true), 0.2, 3.2, 0)

        // kanban board on the wall
        let kb = root.group("kanban", -4.0, 0, -0.15)
        kb.box(4.0, 2.6, 0.08, Gfx.mat(0xe5e7eb, r: 0.4, m: 0.4), 0, 3.6, 0)
        kb.box(3.8, 2.4, 0.05, Gfx.texMat(Off.kanban(), r: 0.5), 0, 3.6, 0.05)

        // wall clock and "ship it" gong
        let clock = root.group("clock", -4.0, 6.0, -0.12)
        clock.cyl(0.55, 0.1, Gfx.mat(0xf8fafc, r: 0.4), 0, 0, 0).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        let hand = clock.box(0.05, 0.4, 0.04, Gfx.mat(0x111827), 0, 0.18, 0.08)
        hand.pivot = SCNMatrix4MakeTranslation(0, -0.18, 0)
        hand.runAction(.repeatForever(.rotateBy(x: 0, y: 0, z: -.pi * 2, duration: 60)))
        let bell = root.group("prop:bell", 12.0, 0, 0.9)
        bell.cyl(0.05, 1.5, steel, -0.7, 0.75, 0)
        bell.cyl(0.05, 1.5, steel, 0.7, 0.75, 0)
        bell.box(1.5, 0.06, 0.08, steel, 0, 1.5, 0)
        bell.cyl(0.5, 0.08, Gfx.mat(0xe3b341, r: 0.25, m: 0.9), 0, 0.95, 0).eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)

        // server rack by the right wall
        let rack = root.group("prop:rack", 15.0, 0, 1.0)
        rack.box(1.3, 3.0, 1.0, Gfx.mat(0x1f2937, r: 0.4, m: 0.5), 0, 1.5, 0, round: 0.04)
        for i in 0..<6 {
            let y = 0.45 + CGFloat(i) * 0.42
            rack.box(1.1, 0.3, 0.04, Gfx.mat(0x374151, r: 0.4, m: 0.6), 0, y, 0.51)
            Off.blink(rack.ball(0.04, Gfx.mat(i % 2 == 0 ? 0x4ade80 : 0xfbbf24, e: i % 2 == 0 ? 0x4ade80 : 0xfbbf24, eIntensity: 1.2), 0.4, y, 0.55), every: 0.8 + Double(i) * 0.3)
        }

        // plants, a printer and the vending machine
        Off.plant(root, -13.6, 0.3)
        Off.plant(root, 8.8, 0.3, big: false)
        Off.plant(root, 16.4, 4.4)
        let printer = root.group("printer", -8.4, 0, 0.5)
        printer.box(1.1, 0.8, 0.9, Gfx.mat(0xf3f4f6, r: 0.5), 0, 0.4, 0, round: 0.05)
        printer.box(0.8, 0.5, 0.6, Gfx.mat(0xd1d5db, r: 0.5), 0, 1.0, 0, round: 0.04)
        printer.box(0.6, 0.02, 0.3, Gfx.mat(0xffffff), 0, 1.27, 0.35)

        // manager's desk
        let c = root.group("prop:console", 0.5, 0, 0.55)
        c.box(3.2, 0.12, 1.1, Gfx.mat(0x8b5e34, r: 0.5), 0, 0.85, 0, round: 0.04)
        c.box(3.0, 0.8, 0.9, Gfx.mat(0x6b4426, r: 0.6), 0, 0.4, 0.05)
        c.box(1.0, 0.7, 0.05, Gfx.texMat(Gfx.screen(0x0d1117, 0x58a6ff, seed: 9, style: 2), emissive: true), -0.6, 1.4, -0.2)
        c.box(0.2, 0.3, 0.05, Gfx.mat(0x111827), -0.6, 1.0, -0.2)
        c.box(0.9, 0.12, 0.3, Gfx.texMat(Off.text(["OFFICE MANAGER"], w: 220, h: 36, bg: NSColor(red: 0.12, green: 0.25, blue: 0.5, alpha: 1), fg: .white, size: 20), r: 0.4), 0.8, 0.95, 0.45)
        c.cyl(0.12, 0.2, Gfx.mat(0xffffff, r: 0.4), 1.2, 1.0, 0)
        coffee(root, .office)
    }

    /// Prop for one work station; `kind` 0 docs, 1 pair programming, 2 CI rack, 3 stand-up board (see `Theme.stations`).
    static func officeStation(_ kind: Int, _ n: SCNNode) {
        let desk = Gfx.mat(0xe4dccb, r: 0.6)
        let dark = Gfx.mat(0x1f2937, r: 0.4, m: 0.4)
        switch kind {
        case 0:
            // bookshelf with docs
            n.box(2.2, 2.4, 0.6, Gfx.mat(0x8b5e34, r: 0.7), 0, 1.2, -0.2, round: 0.03)
            let cols: [UInt32] = [0x2563eb, 0xdc2626, 0x16a34a, 0xfacc15, 0x9333ea, 0xf97316, 0x0d9488]
            for row in 0..<3 {
                n.box(2.0, 0.05, 0.62, Gfx.mat(0x6b4426, r: 0.7), 0, 0.5 + CGFloat(row) * 0.75, -0.2)
                for i in 0..<7 {
                    n.box(0.2, 0.55, 0.4, Gfx.mat(cols[(i + row * 2) % cols.count], r: 0.8), -0.85 + CGFloat(i) * 0.28, 0.82 + CGFloat(row) * 0.75, -0.15)
                }
            }
        case 1:
            // pair-programming desk: two monitors, two keyboards
            n.box(2.4, 0.1, 0.9, desk, 0, 0.85, 0, round: 0.03)
            for x in [-1.0, 1.0] as [CGFloat] { n.box(0.1, 0.85, 0.8, desk, x, 0.42, 0) }
            for (i, x) in [-0.6, 0.6].enumerated() {
                n.box(0.9, 0.55, 0.05, dark, CGFloat(x), 1.4, -0.2)
                n.box(0.82, 0.47, 0.03, Gfx.texMat(Gfx.screen(0x0d1117, i == 0 ? 0x58a6ff : 0x7ee787, seed: UInt64(30 + i), style: 0), emissive: true), CGFloat(x), 1.4, -0.17)
                n.box(0.7, 0.04, 0.22, dark, CGFloat(x), 0.92, 0.15)
            }
        case 2:
            // CI server rack with a build light
            n.box(1.4, 2.4, 0.9, Gfx.mat(0x111827, r: 0.4, m: 0.5), 0, 1.2, -0.1, round: 0.04)
            for i in 0..<5 {
                let y = 0.4 + CGFloat(i) * 0.42
                n.box(1.2, 0.3, 0.04, Gfx.mat(0x374151, r: 0.4, m: 0.6), 0, y, 0.36)
                Off.blink(n.ball(0.04, Gfx.mat(0x4ade80, e: 0x4ade80, eIntensity: 1.2), 0.45, y, 0.4), every: 0.6 + Double(i) * 0.25)
            }
            let beacon = n.cyl(0.12, 0.2, Gfx.mat(0x4ade80, r: 0.2, e: 0x22c55e, eIntensity: 1.0, alpha: 0.9), 0, 2.55, -0.1)
            pulse(beacon, 0.15, 0.7)
        default:
            // stand-up board on wheels
            n.box(2.0, 1.4, 0.08, Gfx.mat(0xe5e7eb, r: 0.4, m: 0.4), 0, 1.65, -0.1)
            n.box(1.85, 1.25, 0.05, Gfx.texMat(Off.kanban(), r: 0.5), 0, 1.65, -0.05)
            n.cyl(0.04, 1.0, Gfx.mat(0x9ca3af, m: 0.8), -0.8, 0.5, -0.1)
            n.cyl(0.04, 1.0, Gfx.mat(0x9ca3af, m: 0.8), 0.8, 0.5, -0.1)
            n.box(2.0, 0.06, 0.4, Gfx.mat(0x9ca3af, m: 0.8), 0, 0.05, -0.1)
        }
    }
}

extension Rig {
    /// (top, bottom, accent) colours; `v` is a per-actor variant index.
    static func officeOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        if captain { return (0xf3f4f6, 0x1f2937, 0xb91c1c) }
        let top = Off.tops[v % Off.tops.count]
        return (top, 0x374151, 0xfacc15)
    }

    /// Hair, glasses, headphones, hats and a tie for the manager.
    static func officeAccessories(captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let head = rig.head, body = rig.body
        head.add(SCNSphere(radius: 0.32), hair, at: SCNVector3(0, 0.36, -0.04))
        let frame = Gfx.mat(0x111827, r: 0.4)
        func glasses() {
            for x in [-0.12, 0.12] as [CGFloat] {
                head.box(0.17, 0.12, 0.03, frame, x, 0.36, 0.31)
                head.box(0.13, 0.08, 0.035, Gfx.mat(0xbfe6ff, r: 0.05, alpha: 0.5), x, 0.36, 0.315)
            }
            head.box(0.08, 0.03, 0.03, frame, 0, 0.37, 0.31)
        }
        if captain {
            glasses()
            body.box(0.12, 0.42, 0.04, Gfx.mat(0xb91c1c, r: 0.5), 0, 0.36, 0.21)
            body.box(0.16, 0.14, 0.05, Gfx.mat(0xb91c1c, r: 0.5), 0, 0.6, 0.21)
            body.box(0.22, 0.14, 0.03, Gfx.mat(0xffffff, r: 0.4), -0.17, 0.35, 0.21)
            return
        }
        switch number % 6 {
        case 0:
            for x in [-0.34, 0.34] as [CGFloat] { head.cyl(0.1, 0.1, Gfx.mat(0x111827, r: 0.4), x, 0.36, 0).eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2) }
            head.box(0.7, 0.05, 0.06, Gfx.mat(0x111827, r: 0.4), 0, 0.7, 0)
        case 1:
            glasses()
        case 2:
            head.add(SCNSphere(radius: 0.34), accM, at: SCNVector3(0, 0.4, -0.02)).scale = SCNVector3(1, 0.6, 1)
            head.ball(0.05, Gfx.mat(0xffffff), 0, 0.68, 0)
        case 3:
            head.cyl(0.3, 0.12, accM, 0, 0.62, -0.02)
            head.box(0.4, 0.03, 0.26, accM, 0, 0.58, 0.28)
        case 4:
            body.box(0.04, 0.4, 0.02, Gfx.mat(0x2563eb, r: 0.6), -0.1, 0.5, 0.21)
            body.box(0.04, 0.4, 0.02, Gfx.mat(0x2563eb, r: 0.6), 0.1, 0.5, 0.21)
            body.box(0.2, 0.14, 0.03, Gfx.mat(0xffffff, r: 0.4), 0, 0.24, 0.22)
            glasses()
        default:
            head.box(0.7, 0.04, 0.05, Gfx.mat(0x111827), 0, 0.68, 0)
            head.cyl(0.08, 0.1, Gfx.mat(0x111827), -0.34, 0.36, 0).eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            head.box(0.03, 0.03, 0.22, Gfx.mat(0x111827), -0.3, 0.3, 0.16)
        }
    }

    /// Context-usage gauge shown on a worker (set `mv.fill`): a coffee mug on the back.
    func officeGauge(_ figure: SCNNode, metal: SCNMaterial) {
        let g = body.group("gauge", 0.3, 0.42, -0.3)
        g.cyl(0.16, 0.76, Gfx.mat(0xf9fafb, r: 0.3, alpha: 0.5), 0, 0, 0)
        let f = g.add(SCNCylinder(radius: 0.17, height: 0.64), tinted(0x7c4a21, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
        bottomAnchored(f, height: 0.64)
        mv.fill = f
    }

    /// Small beacon shown for approval requests: a raised sticky note with an exclamation dot.
    func officeBeacon(_ beacon: SCNNode, metal: SCNMaterial) {
        beacon.cyl(0.03, 0.2, metal, 0, -0.1, 0)
        beacon.box(0.3, 0.3, 0.03, tinted(0xfde047, e: true), 0, 0.12, 0)
        beacon.ball(0.05, tinted(0xdc2626, e: true), 0, 0.08, 0.03)
    }
}

extension Stage {
    /// (background, ambient, ambient intensity, key, key intensity, fill): bright, neutral office daylight.
    static func officeLighting() -> (UInt32, UInt32, CGFloat, UInt32, CGFloat, UInt32) { (0xcfd8e3, 0xf3f6ff, 480, 0xfff8ee, 1000, 0xdbe7ff) }
    /// Work animation per tool kind (0 read, 1 write, 2 run, 3 other).
    static func officeMotion(_ kind: Int) -> Motion { [.scan, .type, .type, .scan][kind % 4] }
}

extension RoomSim {
    /// Failure effect: production is down; everybody panics and one developer blames the last deploy.
    func officeFailure(t: Double) {
        panicAll(t: t, line: "Prod is down! 🚨")
        if let v = victim() {
            mutate(v.id) {
                $0.mood = .dizzy
                $0.moodUntil = t + 5
                $0.say = ["Who deployed on Friday?!", "It worked on my machine!", "Have you tried a rollback?"].randomElement()
                $0.sayUntil = t + 4
            }
        }
        mutate("captain") { $0.say = "All hands: incident call! 📞"; $0.sayUntil = t + 3 }
    }
}

extension MetricsFmt {
    static var officeMedal: String { "✅" }
}

extension RoomSign {
    static func officeAgeSign(age: Double, days: Int, minutes: Int, jersey: Int, txt: String) -> NSImage {
        Gfx.sign("🏢 Sprint day \(days)", "In the office \(txt)", accent: 0x3a7bd5)
    }
}

extension SoundCenter {
    /// WAV data for this theme: keyboard-ish blips, a notification ping for finished tasks, and a pager buzz for trouble.
    nonisolated static func officeSynth(_ kind: Kind) -> Data? {
        switch kind {
        case .spawn: return wav(tone(freq: { $0 < 0.05 ? 660 : 880 }, dur: 0.12, decay: 8))
        case .success: return wav(tone(freq: { $0 < 0.12 ? 988 : 1319 }, dur: 0.35, decay: 4))
        case .failure: return wav(tone(freq: { 220 - 40 * $0 }, dur: 0.6, decay: 1.5, trem: 14, saw: true))
        case .alert: return wav(tone(freq: { $0 < 0.2 ? 880 : 660 }, dur: 0.5, decay: 2, trem: 10))
        }
    }
}
