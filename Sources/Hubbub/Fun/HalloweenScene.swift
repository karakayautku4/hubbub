import SceneKit
import AppKit
import SwiftUI

/// Seasonal overlay that sits on top of every theme: a purple vignette riding on the camera, carved pumpkins,
/// tombstones, skulls and candy at the arena edges, drifting ghosts, the odd bat flight and a rare "BOO!". Built lazily on first use,
/// about 45 nodes, shared geometry and materials, no extra lights, and fully idle (hidden, no work) while the mode is off.
@MainActor
final class HalloweenLayer {
    let root = SCNNode()
    private var built = false
    private var active = false
    private var nextCheck = 0.0
    private var lastT: Double?
    private var layoutKey = ""
    private var aspect: CGFloat = 0

    private let cameraRig = SCNNode()
    private let left = SCNNode(), right = SCNNode()
    private let leftBack = SCNNode(), leftFront = SCNNode(), rightBack = SCNNode(), rightFront = SCNNode()
    private var ghosts: [(node: SCNNode, x: CGFloat, y: CGFloat, z: CGFloat, phase: Double)] = []
    private var bats: [(node: SCNNode, wings: [SCNNode], dy: CGFloat, dx: CGFloat)] = []
    private var batFlight: (start: Double, dir: CGFloat, dur: Double)?
    private var nextBat = 0.0
    private var boo = SCNNode()
    private var booStart: Double?
    private var nextBoo = 0.0
    private var vignette = SCNNode()
    private var bodyMat = SCNMaterial(), faceMat = SCNMaterial(), poolMat = SCNMaterial()

    private let debug = ProcessInfo.processInfo.environment["HUBBUB_HALLOWEEN_DEBUG"] ?? ""

    init() { root.name = "halloween"; root.isHidden = true }

    /// Number of nodes the overlay adds (diagnostics and `--selftest-halloween`).
    var nodeCount: Int { root.childNodes { _, _ in true }.count + cameraRig.childNodes { _, _ in true }.count }

    // MARK: Frame

    func tick(t: Double, theme: Theme, stage: Stage) {
        if t >= nextCheck {
            nextCheck = t + 1
            let now = Halloween.isActiveNow
            if now != active {
                active = now
                root.isHidden = !now
                if now { buildIfNeeded() ; nextBat = t + (debug.contains("bat") ? 1 : 10); nextBoo = t + (debug.contains("boo") ? 2 : 70) }
            }
        }
        guard active, built else { return }
        let dt = min(max(t - (lastT ?? t), 0), 0.1)
        lastT = t
        let still = A11y.reduceMotion

        syncLayout(stage)
        flicker(t: t, still: still)
        if !still {
            drift(t: t)
            updateBats(t: t, dt: dt, stage: stage)
            updateBoo(t: t, stage: stage)
        } else {
            for g in ghosts { g.node.position = SCNVector3(g.x, g.y, g.z); g.node.eulerAngles.x = -0.7 }
            for b in bats { b.node.isHidden = true }
            boo.isHidden = true
        }
    }

    // MARK: Layout

    private func syncLayout(_ stage: Stage) {
        let size = stage.view?.bounds.size ?? CGSize(width: 636, height: 358)
        let a = size.width / max(size.height, 1)
        if abs(a - aspect) > 0.005 { aspect = a; fitCameraOverlay() }
        let key = String(format: "%.2f|%.2f", stage.arena.xHalf, stage.arena.zFar)
        guard key != layoutKey else { return }
        layoutKey = key
        let x = stage.arena.xHalf - 0.5, zf = stage.arena.zFar
        left.position = SCNVector3(-x, 0, 0)
        right.position = SCNVector3(x, 0, 0)
        leftBack.position = SCNVector3(0, 0, 1.3)
        rightBack.position = SCNVector3(0.7, 0, 1.6)
        leftFront.position = SCNVector3(0, 0, zf - 2.0)
        rightFront.position = SCNVector3(0, 0, zf - 1.9)
    }

    /// The vignette rides on the camera, so they hug the frame corners at any zoom or window size.
    private func fitCameraOverlay() {
        let d: CGFloat = 2
        let hh = d * ArenaMath.fovHalfTan, hw = hh * aspect
        (vignette.geometry as? SCNPlane)?.width = hw * 2.04
        (vignette.geometry as? SCNPlane)?.height = hh * 2.04
    }

    // MARK: Animation

    private func flicker(t: Double, still: Bool) {
        let n = still ? 0.8 : 0.78 + 0.14 * sin(t * 9.1) * sin(t * 3.7 + 1) + 0.08 * sin(t * 23)
        bodyMat.emission.intensity = 0.18 + 0.2 * n
        faceMat.transparency = CGFloat(0.75 + 0.25 * n)
        poolMat.transparency = CGFloat(0.35 + 0.35 * n)
    }

    private func drift(t: Double) {
        for g in ghosts {
            g.node.position = SCNVector3(g.x + CGFloat(sin(t * 0.22 + g.phase)) * 2.4, g.y + CGFloat(sin(t * 0.7 + g.phase * 2)) * 0.3, g.z)
            g.node.eulerAngles = SCNVector3(-0.7, 0, CGFloat(sin(t * 0.5 + g.phase)) * 0.12)
        }
    }

    private func updateBats(t: Double, dt: Double, stage: Stage) {
        if batFlight == nil, t >= nextBat {
            batFlight = (t, Bool.random() ? 1 : -1, 9)
            for b in bats { b.node.isHidden = false }
        }
        guard let f = batFlight else { return }
        let k = (t - f.start) / f.dur
        if k >= 1 {
            batFlight = nil
            nextBat = t + Double.random(in: 25...50)
            for b in bats { b.node.isHidden = true }
            return
        }
        let reach = stage.arena.xHalf + 3
        let flap = sin(t * 16) * 0.75
        for (i, b) in bats.enumerated() {
            let kk = CGFloat(k) - CGFloat(i) * 0.05
            let x = f.dir * (-reach + 2 * reach * kk) + b.dx
            b.node.position = SCNVector3(x, 4.4 + b.dy + CGFloat(sin(t * 2.2 + Double(i) * 1.7)) * 0.5, 0.6 + CGFloat(i) * 0.9)
            b.node.eulerAngles = SCNVector3(0.25, f.dir > 0 ? -.pi / 2 : .pi / 2, 0)
            b.wings[0].eulerAngles.z = CGFloat(flap)
            b.wings[1].eulerAngles.z = CGFloat(-flap)
        }
    }

    private func updateBoo(t: Double, stage: Stage) {
        if booStart == nil, t >= nextBoo { booStart = t }
        guard let s = booStart else { return }
        let e = t - s
        if e > 2.4 { booStart = nil; boo.isHidden = true; nextBoo = t + Double.random(in: 70...140); return }
        boo.isHidden = false
        let pop = e < 0.3 ? 1.6 * sin(e / 0.3 * .pi / 2) : 1.6 - 0.3 * min(1, (e - 0.3) / 0.2)
        boo.scale = SCNVector3(pop, pop, pop)
        boo.position = SCNVector3(0, 4.3, 1.2)
        boo.opacity = CGFloat(e > 1.8 ? max(0, 1 - (e - 1.8) / 0.6) : 1)
    }

    // MARK: Build

    private func buildIfNeeded() {
        guard !built else { return }
        built = true
        let orange = 0xf28a1c as UInt32

        bodyMat = Gfx.mat(orange, r: 0.6, e: 0xff6a00, eIntensity: 0.3)
        let stemMat = Gfx.mat(0x4a5a2a, r: 0.8)
        faceMat = Self.constant(Self.faceImage())
        poolMat = Self.constant(Self.poolImage())
        poolMat.blendMode = .add

        // Camera-attached overlay
        cameraRig.name = "halloweenCam"
        let vg = SCNPlane(width: 2, height: 1)
        vg.materials = [Self.constant(Self.vignetteImage())]
        vignette = Self.overlayNode(vg, order: 4000)
        vignette.position = SCNVector3(0, 0, -2)
        cameraRig.addChildNode(vignette)

        // Shared pumpkin parts
        let pumpkin = SCNSphere(radius: 0.45); pumpkin.segmentCount = 14; pumpkin.materials = [bodyMat]
        let stem = SCNBox(width: 0.1, height: 0.2, length: 0.1, chamferRadius: 0.02); stem.materials = [stemMat]
        let face = SCNPlane(width: 0.62, height: 0.62); face.materials = [faceMat]
        let pool = SCNPlane(width: 2.6, height: 2.6); pool.materials = [poolMat]

        func pumpkinNode(_ x: CGFloat, _ z: CGFloat, scale: CGFloat, carved: Bool, yaw: CGFloat, on parent: SCNNode) {
            let g = SCNNode()
            g.position = SCNVector3(x, 0.4 * scale, z)
            g.scale = SCNVector3(scale, scale, scale)
            g.eulerAngles.y = yaw
            let b = SCNNode(geometry: pumpkin); b.scale = SCNVector3(1, 0.82, 1)
            let s = SCNNode(geometry: stem); s.position = SCNVector3(0, 0.38, 0)
            g.addChildNode(b); g.addChildNode(s)
            if carved {
                let f = SCNNode(geometry: face); f.position = SCNVector3(0, 0, 0.43)
                g.addChildNode(f)
            }
            parent.addChildNode(g)
        }
        func glowPool(on parent: SCNNode, x: CGFloat, z: CGFloat, size: CGFloat) {
            let p = SCNNode(geometry: pool)
            p.eulerAngles.x = -.pi / 2
            p.position = SCNVector3(x, 0.03, z)
            p.scale = SCNVector3(size, size, size)
            p.castsShadow = false
            p.renderingOrder = 10
            parent.addChildNode(p)
        }

        // Left edge: tombstones in the back, a pumpkin pile in front
        let stone = Gfx.mat(0x7b7f8c, r: 0.9)
        left.addChildNode(leftBack); left.addChildNode(leftFront)
        leftBack.box(0.8, 1.1, 0.22, stone, 0, 0.55, 0, round: 0.12)
        let t2 = leftBack.box(0.65, 0.8, 0.2, stone, 0.2, 0.4, 1.0, round: 0.1)
        t2.eulerAngles.z = 0.14
        pumpkinNode(-0.3, 0, scale: 1.3, carved: true, yaw: 0.3, on: leftFront)
        pumpkinNode(0.8, -0.3, scale: 1.0, carved: false, yaw: 0, on: leftFront)
        pumpkinNode(0.4, 0.75, scale: 0.85, carved: true, yaw: -0.25, on: leftFront)
        glowPool(on: leftFront, x: 0.2, z: 0.3, size: 1.5)

        // Right edge: a big jack-o'-lantern in the back, a skull with candy in front
        right.addChildNode(rightBack); right.addChildNode(rightFront)
        pumpkinNode(0, 0, scale: 1.5, carved: true, yaw: -0.3, on: rightBack)
        glowPool(on: rightBack, x: 0, z: 0.5, size: 1.8)
        let bone = Gfx.mat(0xe8e2cf, r: 0.6), dark = Gfx.mat(0x151515, r: 0.4)
        let skull = rightFront.group("skull", 0, 0, 0)
        skull.eulerAngles.y = -0.35
        skull.scale = SCNVector3(1.5, 1.5, 1.5)
        skull.ball(0.24, bone, 0, 0.26, 0)
        skull.box(0.2, 0.1, 0.18, bone, 0, 0.1, 0.06, round: 0.03)
        for sx: CGFloat in [-1, 1] { skull.ball(0.06, dark, sx * 0.09, 0.3, 0.2) }
        let candy = Gfx.mat(0xffb21e, r: 0.5), candy2 = Gfx.mat(0xb36bff, r: 0.5)
        for (i, c) in [(-0.55, 0.3), (0.5, 0.5), (0.75, -0.1)].enumerated() {
            let cone = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.22)
            cone.materials = [i == 1 ? candy2 : candy]
            let n = SCNNode(geometry: cone)
            n.position = SCNVector3(CGFloat(c.0), 0.11, CGFloat(c.1))
            n.eulerAngles.z = CGFloat(i) * 0.9 - 0.8
            rightFront.addChildNode(n)
        }
        root.addChildNode(left)
        root.addChildNode(right)

        // Ghosts
        let ghostMat = Self.constant(nil, color: NSColor(white: 1, alpha: 1))
        ghostMat.transparency = 0.55
        let ghostGeo = SCNCapsule(capRadius: 0.32, height: 1.1); ghostGeo.materials = [ghostMat]
        let eyeGeo = SCNSphere(radius: 0.09); eyeGeo.materials = [dark]
        for (i, p) in [(-9.0, 3.6), (1.0, 4.6), (9.0, 3.9)].enumerated() {
            let g = SCNNode(geometry: ghostGeo)
            g.scale = SCNVector3(1.5, 1.5, 1.5)
            g.castsShadow = false
            for sx: CGFloat in [-1, 1] {
                let e = SCNNode(geometry: eyeGeo); e.position = SCNVector3(sx * 0.14, 0.25, 0.27); g.addChildNode(e)
            }
            let item = (node: g, x: CGFloat(p.0), y: CGFloat(p.1), z: CGFloat(0.5 + Double(i) * 0.4), phase: Double(i) * 2.1)
            g.position = SCNVector3(item.x, item.y, item.z)
            ghosts.append(item)
            root.addChildNode(g)
        }

        // Bats
        let batMat = Gfx.mat(0x2a1a3a, r: 0.7, e: 0x3a1f5a, eIntensity: 0.5)
        let bodyGeo = SCNSphere(radius: 0.1); bodyGeo.materials = [batMat]
        let wingGeo = SCNBox(width: 0.7, height: 0.02, length: 0.4, chamferRadius: 0); wingGeo.materials = [batMat]
        for i in 0..<2 {
            let b = SCNNode(geometry: bodyGeo)
            b.scale = SCNVector3(1.5, 1.2, 2.2)
            b.isHidden = true
            var wings: [SCNNode] = []
            for sx: CGFloat in [-1, 1] {
                let w = SCNNode(geometry: wingGeo)
                w.pivot = SCNMatrix4MakeTranslation(-sx * 0.35, 0, 0)
                w.position = SCNVector3(sx * 0.08, 0, 0)
                b.addChildNode(w)
                wings.append(w)
            }
            bats.append((b, wings, CGFloat(i) * 0.4, CGFloat(i) * -1.2))
            root.addChildNode(b)
        }

        // BOO!
        let bp = SCNPlane(width: 3.2, height: 1.6)
        let bm = Self.constant(Self.booImage())
        bp.materials = [bm]
        boo = Self.overlayNode(bp, order: 3000)
        boo.constraints = [SCNBillboardConstraint()]
        boo.isHidden = true
        root.addChildNode(boo)
    }

    /// Attaches the camera-riding overlay (called once by the stage hook).
    func attach(to camera: SCNNode) {
        guard cameraRig.parent == nil else { return }
        camera.addChildNode(cameraRig)
    }

    // MARK: Textures

    private static func constant(_ image: NSImage?, color: NSColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image ?? color
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        return m
    }

    private static func overlayNode(_ g: SCNGeometry, order: Int) -> SCNNode {
        let n = SCNNode(geometry: g)
        n.renderingOrder = order
        n.castsShadow = false
        return n
    }

    private static func faceImage() -> NSImage {
        Gfx.image(128, 128) { c in
            c.setShadow(offset: .zero, blur: 10, color: Gfx.color(0xff7a00).cgColor)
            c.setFillColor(Gfx.color(0xffd24a).cgColor)
            for sx: CGFloat in [0, 1] {
                let x = 28 + sx * 44
                c.move(to: CGPoint(x: x, y: 74)); c.addLine(to: CGPoint(x: x + 26, y: 74)); c.addLine(to: CGPoint(x: x + 13, y: 100)); c.fillPath()
            }
            c.move(to: CGPoint(x: 64, y: 62)); c.addLine(to: CGPoint(x: 56, y: 52)); c.addLine(to: CGPoint(x: 72, y: 52)); c.fillPath()
            c.move(to: CGPoint(x: 26, y: 46))
            for i in 0..<7 { c.addLine(to: CGPoint(x: 26 + CGFloat(i + 1) * 12, y: i % 2 == 0 ? 28 : 46)) }
            c.addLine(to: CGPoint(x: 102, y: 34)); c.addLine(to: CGPoint(x: 26, y: 34)); c.closePath(); c.fillPath()
        }
    }

    private static func poolImage() -> NSImage {
        Gfx.image(128, 128) { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [Gfx.color(0xff8a1c, 0.8).cgColor, Gfx.color(0xff8a1c, 0).cgColor] as CFArray, locations: [0, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }

    private static func vignetteImage() -> NSImage {
        Gfx.image(128, 128) { c in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [Gfx.color(0x5a1f8a, 0).cgColor, Gfx.color(0x5a1f8a, 0).cgColor, Gfx.color(0x2a0a4a, 0.5).cgColor] as CFArray,
                               locations: [0, 0.5, 1])!
            c.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 92, options: .drawsAfterEndLocation)
        }
    }

    private static func booImage() -> NSImage {
        let w = 400, h = 200
        return Gfx.image(w, h) { c in
            let ns = NSGraphicsContext(cgContext: c, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            let font = NSFont.systemFont(ofSize: 104, weight: .black)
            let str = NSAttributedString(string: "BOO!", attributes: [
                .font: font, .foregroundColor: Gfx.color(0xff8a1c),
                .strokeColor: Gfx.color(0x2a0a4a), .strokeWidth: -10])
            let s = str.size()
            str.draw(at: CGPoint(x: (CGFloat(w) - s.width) / 2, y: (CGFloat(h) - s.height) / 2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

/// `--selftest-halloween` helper bits that need SceneKit (node budget).
@MainActor
enum HalloweenSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func day(_ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))! }
        let none: [String: String] = [:]

        for (m, d, want) in [(10, 23, false), (10, 24, true), (10, 30, true), (10, 31, true), (11, 1, true), (11, 2, false), (6, 15, false), (12, 31, false)] {
            check(Halloween.isActive(mode: .auto, date: day(m, d), calendar: cal, env: none) == want, "auto \(m)/\(d)")
        }
        check(Halloween.isActive(mode: .on, date: day(6, 15), calendar: cal, env: none), "on beats the date")
        check(!Halloween.isActive(mode: .off, date: day(10, 31), calendar: cal, env: none), "off beats the date")
        check(Halloween.isActive(mode: .off, date: day(6, 1), calendar: cal, env: [Halloween.envKey: "1"]), "env=1 forces on")
        check(!Halloween.isActive(mode: .on, date: day(10, 31), calendar: cal, env: [Halloween.envKey: "0"]), "env=0 forces off")
        check(Halloween.isActive(mode: .auto, date: day(10, 31), calendar: cal, env: [Halloween.envKey: "maybe"]), "junk env is ignored")
        check(Halloween.mode(from: nil) == .auto && Halloween.mode(from: "bogus") == .auto && Halloween.mode(from: "on") == .on, "mode parsing defaults to auto")

        setenv(Halloween.envKey, "1", 1)
        let layer = HalloweenLayer()
        check(layer.nodeCount == 0, "layer builds lazily")
        let stage = Stage()
        Stage.forceVisible = true
        layer.attach(to: stage.camera)
        layer.tick(t: 1, theme: .space, stage: stage)
        let n = layer.nodeCount
        check(n > 20 && n < 60, "node budget (\(n))")
        check(!layer.root.isHidden, "visible when active")
        setenv(Halloween.envKey, "0", 1)
        layer.tick(t: 3, theme: .space, stage: stage)
        check(layer.root.isHidden, "hidden when off")
        unsetenv(Halloween.envKey)

        if failures.isEmpty { print("halloween self-test: OK") } else { print("halloween self-test FAILED: \(failures.joined(separator: "; "))") }
        return failures.isEmpty
    }
}

/// `Hubbub --snapshot-halloween out.png [WxH] [dark] [settings]`: renders the app frame offscreen at a fixed size (the stage itself stays blank).
@MainActor
enum HalloweenSnapshot {
    static func run(_ args: [String]) {
        guard let out = args.first else { print("usage: --snapshot-halloween out.png [WxH] [dark] [settings]"); return }
        let dims = (args.first { $0.contains("x") && $0.first?.isNumber == true } ?? "440x600").split(separator: "x").compactMap { Double($0) }
        let dark = args.contains("dark")
        if args.contains("settings") { AppModel.shared.screen = .settings; UserDefaults.standard.set("appearance", forKey: "settingsTab") }
        let monitor = SessionMonitor(); monitor.start()
        let quota = QuotaService(); quota.start()
        let host = NSHostingView(rootView: ContentView(monitor: monitor, quotaService: quota).frame(width: dims[0], height: dims[1]))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: dims[0], height: dims[1]), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        host.frame = NSRect(x: 0, y: 0, width: dims[0], height: dims[1])
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
    }
}
