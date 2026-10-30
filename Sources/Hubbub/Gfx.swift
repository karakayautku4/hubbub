import SceneKit
import AppKit

enum Gfx {
    static func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    static func mat(_ hex: UInt32, r: CGFloat = 0.65, m: CGFloat = 0, e: UInt32? = nil, eIntensity: CGFloat = 1, alpha: CGFloat = 1) -> SCNMaterial {
        let s = SCNMaterial()
        s.lightingModel = .physicallyBased
        s.diffuse.contents = color(hex, alpha)
        s.roughness.contents = r
        s.metalness.contents = m
        if let e { s.emission.contents = color(e); s.emission.intensity = eIntensity }
        if alpha < 1 { s.transparency = alpha; s.writesToDepthBuffer = false }
        return s
    }

    static func texMat(_ img: NSImage, r: CGFloat = 0.8, m: CGFloat = 0, repeatX: CGFloat = 1, repeatY: CGFloat = 1, emissive: Bool = false) -> SCNMaterial {
        let s = SCNMaterial()
        s.lightingModel = emissive ? .constant : .physicallyBased
        s.diffuse.contents = img
        s.roughness.contents = r
        s.metalness.contents = m
        s.diffuse.wrapS = .repeat
        s.diffuse.wrapT = .repeat
        s.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        return s
    }

    static func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSImage {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage() }
        draw(ctx)
        guard let cg = ctx.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// Deterministic noise so textures are stable between runs.
    struct RNG { var s: UInt64
        mutating func next() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((s >> 33) & 0xFFFF) / 65535
        }
    }

    static func tiles(_ a: UInt32, _ b: UInt32, grout: UInt32, cells: Int = 8, noise: CGFloat = 0.05) -> NSImage {
        image(512, 512) { c in
            var g = RNG(s: UInt64(a) &+ UInt64(b))
            let n = CGFloat(512 / cells)
            for i in 0..<cells { for j in 0..<cells {
                let base = (i + j) % 2 == 0 ? a : b
                let v = (g.next() - 0.5) * noise
                c.setFillColor(color(base).blended(withFraction: v > 0 ? v : -v, of: v > 0 ? .white : .black)?.cgColor ?? color(base).cgColor)
                c.fill(CGRect(x: CGFloat(i) * n, y: CGFloat(j) * n, width: n, height: n))
            } }
            c.setStrokeColor(color(grout).cgColor)
            c.setLineWidth(3)
            for i in 0...cells {
                c.move(to: CGPoint(x: CGFloat(i) * n, y: 0)); c.addLine(to: CGPoint(x: CGFloat(i) * n, y: 512))
                c.move(to: CGPoint(x: 0, y: CGFloat(i) * n)); c.addLine(to: CGPoint(x: 512, y: CGFloat(i) * n))
            }
            c.strokePath()
        }
    }

    static func speckle(_ base: UInt32, _ spot: UInt32, count: Int = 900, size: CGFloat = 4) -> NSImage {
        image(256, 256) { c in
            c.setFillColor(color(base).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            var g = RNG(s: UInt64(base))
            for _ in 0..<count {
                c.setFillColor(color(spot, 0.35 + g.next() * 0.4).cgColor)
                c.fill(CGRect(x: g.next() * 256, y: g.next() * 256, width: size * (0.4 + g.next()), height: size * (0.4 + g.next())))
            }
        }
    }

    /// Glowing monitor content: coloured bars, graphs and dots.
    static func screen(_ bg: UInt32, _ fg: UInt32, seed: UInt64 = 1, style: Int = 0) -> NSImage {
        image(256, 160) { c in
            c.setFillColor(color(bg).cgColor); c.fill(CGRect(x: 0, y: 0, width: 256, height: 160))
            var g = RNG(s: seed)
            c.setStrokeColor(color(fg, 0.25).cgColor); c.setLineWidth(1)
            for i in stride(from: 0, to: 256, by: 16) { c.move(to: CGPoint(x: i, y: 0)); c.addLine(to: CGPoint(x: i, y: 160)) }
            for j in stride(from: 0, to: 160, by: 16) { c.move(to: CGPoint(x: 0, y: j)); c.addLine(to: CGPoint(x: 256, y: j)) }
            c.strokePath()
            c.setFillColor(color(fg, 0.9).cgColor)
            if style == 0 {
                for i in 0..<14 { c.fill(CGRect(x: 10 + CGFloat(i) * 17, y: 8, width: 11, height: 10 + g.next() * 110)) }
            } else if style == 1 {
                for i in 0..<9 { c.fill(CGRect(x: 10, y: 140 - CGFloat(i) * 15, width: 20 + g.next() * 200, height: 6)) }
            } else {
                c.setStrokeColor(color(fg).cgColor); c.setLineWidth(3)
                c.move(to: CGPoint(x: 0, y: 80))
                for i in 1...16 { c.addLine(to: CGPoint(x: CGFloat(i) * 16, y: 30 + g.next() * 100)) }
                c.strokePath()
                for _ in 0..<30 { c.fillEllipse(in: CGRect(x: g.next() * 250, y: g.next() * 150, width: 5, height: 5)) }
            }
        }
    }

    static func stars() -> NSImage {
        image(1024, 512) { c in
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x05061a).cgColor, color(0x1a0f3a).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 1024, y: 512), options: [])
            var g = RNG(s: 42)
            for _ in 0..<420 {
                let s = 1 + g.next() * 2.4
                c.setFillColor(NSColor.white.withAlphaComponent(0.4 + g.next() * 0.6).cgColor)
                c.fillEllipse(in: CGRect(x: g.next() * 1024, y: g.next() * 512, width: s, height: s))
            }
        }
    }

    static func skyGradient() -> NSImage {
        image(8, 256) { c in
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0xf6d8a8).cgColor, color(0x8fc4ee).cgColor] as CFArray, locations: [0, 1])!
            c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
        }
    }

    /// Shared dark scrim behind every 3D label; keeps white text ≥ 4.5:1 even over a white backdrop.
    static let scrimAlpha: CGFloat = 0.78

    static func luminance(_ rgb: UInt32) -> Double {
        func lin(_ v: UInt32) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin((rgb >> 16) & 255) + 0.7152 * lin((rgb >> 8) & 255) + 0.0722 * lin(rgb & 255)
    }

    /// WCAG contrast of `fg` text (optionally translucent) on a black scrim of `alpha` over `backdrop`.
    static func scrimContrast(fg: UInt32, fgAlpha: Double = 1, backdrop: UInt32, alpha: CGFloat = scrimAlpha) -> Double {
        func ch(_ v: UInt32, _ s: Int) -> Double { Double((v >> UInt32(s)) & 255) }
        func mix(_ a: Double, _ b: Double, _ k: Double) -> Double { a * k + b * (1 - k) }
        let k = Double(alpha)
        var bg: UInt32 = 0, text: UInt32 = 0
        for s in [16, 8, 0] {
            let b = mix(0, ch(backdrop, s), k)
            bg |= UInt32(b.rounded()) << UInt32(s)
            text |= UInt32(mix(ch(fg, s), b, fgAlpha).rounded()) << UInt32(s)
        }
        let l1 = luminance(text), l2 = luminance(bg)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static var labelCache: [String: NSImage] = [:]
    private static let cacheLimit = 96

    /// Name pills and bubbles repeat constantly (same agent names, same status lines), so default-styled ones are shared.
    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let hit = labelCache[key] { return hit }
        if labelCache.count >= cacheLimit { labelCache.removeAll(keepingCapacity: true) }
        let img = make()
        labelCache[key] = img
        return img
    }

    static func label(_ text: String, size: CGFloat = 22, fg: NSColor = .white, bg: NSColor = NSColor.black.withAlphaComponent(scrimAlpha)) -> NSImage {
        if fg == .white, bg == NSColor.black.withAlphaComponent(scrimAlpha) {
            return cached("l\(size)|\(text)") { renderLabel(text, size: size, fg: fg, bg: bg) }
        }
        return renderLabel(text, size: size, fg: fg, bg: bg)
    }

    private static func renderLabel(_ text: String, size: CGFloat, fg: NSColor, bg: NSColor) -> NSImage {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let ts = (text as NSString).size(withAttributes: attrs)
        let img = NSImage(size: NSSize(width: ceil(ts.width) + 22, height: ceil(ts.height) + 10), flipped: false) { r in
            bg.setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
            (text as NSString).draw(at: NSPoint(x: 11, y: 5), withAttributes: attrs)
            return true
        }
        return img
    }

    static func bubble(_ text: String, size: CGFloat = 22) -> NSImage {
        cached("b\(size)|\(text)") { renderBubble(text, size: size) }
    }

    private static func renderBubble(_ text: String, size: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.1, alpha: 1)]
        let ts = (text as NSString).size(withAttributes: attrs)
        let tail: CGFloat = 12
        return NSImage(size: NSSize(width: ceil(ts.width) + 28, height: ceil(ts.height) + 16 + tail), flipped: false) { r in
            let body = NSRect(x: 0, y: tail, width: r.width, height: r.height - tail)
            NSColor.white.setFill()
            NSColor(white: 0.2, alpha: 1).setStroke()
            let p = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 14, yRadius: 14)
            p.lineWidth = 2
            p.fill(); p.stroke()
            let t = NSBezierPath()
            t.move(to: NSPoint(x: r.midX - 8, y: tail + 1)); t.line(to: NSPoint(x: r.midX, y: 1)); t.line(to: NSPoint(x: r.midX + 8, y: tail + 1))
            NSColor.white.setFill(); t.fill()
            (text as NSString).draw(at: NSPoint(x: 14, y: tail + 8), withAttributes: attrs)
            return true
        }
    }

    static func billboard(_ img: NSImage, unitsPerPoint: CGFloat = 0.022) -> SCNNode {
        let plane = SCNPlane(width: img.size.width * unitsPerPoint, height: img.size.height * unitsPerPoint)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.isDoubleSided = true
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 200
        return n
    }
}

extension SCNNode {
    @discardableResult
    func add(_ g: SCNGeometry, _ m: SCNMaterial, at p: SCNVector3 = SCNVector3Zero, name: String? = nil, shadow: Bool = true) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        n.name = name
        n.castsShadow = shadow
        addChildNode(n)
        return n
    }
    @discardableResult
    func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, round: CGFloat = 0, name: String? = nil) -> SCNNode {
        add(SCNBox(width: w, height: h, length: d, chamferRadius: round), m, at: SCNVector3(x, y, z), name: name)
    }
    @discardableResult
    func cyl(_ r: CGFloat, _ h: CGFloat, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, name: String? = nil) -> SCNNode {
        add(SCNCylinder(radius: r, height: h), m, at: SCNVector3(x, y, z), name: name)
    }
    @discardableResult
    func ball(_ r: CGFloat, _ m: SCNMaterial, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, name: String? = nil) -> SCNNode {
        add(SCNSphere(radius: r), m, at: SCNVector3(x, y, z), name: name)
    }
    func group(_ name: String, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.name = name
        n.position = SCNVector3(x, y, z)
        addChildNode(n)
        return n
    }
    func tag(prefix: String) {
        // Make a whole prop clickable by naming the root and every descendant geometry node.
        enumerateChildNodes { c, _ in if c.name == nil { c.name = self.name } }
    }
}

/// Contrast guard for the 3D label scrim: every label foreground must reach 4.5:1 even over the brightest scene backdrops.
enum LabelContrastTest {
    static func run() -> Bool {
        let backdrops: [UInt32] = [0xffffff, 0x9bc7ee, 0xf6d8a8, 0xfff1dd, 0x2a2420, 0x04050f]
        let fgs: [(String, UInt32, Double)] = [("name", 0xffffff, 1), ("chip", 0xffffff, 1), ("age", 0xffd98a, 1), ("cost", 0xffe08a, 1)]
        var ok = true
        for (n, fg, a) in fgs {
            let worst = backdrops.map { Gfx.scrimContrast(fg: fg, fgAlpha: a, backdrop: $0) }.min() ?? 0
            let pass = worst >= 4.5
            print(pass ? "PASS" : "FAIL", "label contrast \(n) \(String(format: "%.1f", worst)):1")
            ok = ok && pass
        }
        return ok
    }
}
