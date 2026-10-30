import SceneKit
import SwiftUI
import AppKit

/// Pure arena/zoom maths (no SceneKit), shared by the stage, the camera and `--selftest-jobs`.
enum ArenaMath {
    /// Base camera: 23.97 world units from the look-at point, 41 degree vertical FOV.
    static let baseDistance: CGFloat = 23.97
    static let fovHalfTan: CGFloat = tan(20.5 * .pi / 180)

    /// Camera distance multiplier that frames an arena of the given half-width / far edge (1 = the classic framing).
    static func fit(xHalf: CGFloat, zFar: CGFloat, aspect: CGFloat) -> CGFloat { frame(xHalf: xHalf, zFar: zFar, aspect: aspect).fit }

    /// How far the camera target slides toward the viewer so the arena sits vertically centred in the view.
    static func lookShift(xHalf: CGFloat, zFar: CGFloat, aspect: CGFloat) -> CGFloat { frame(xHalf: xHalf, zFar: zFar, aspect: aspect).shift }

    /// Normalised screen height (-1 bottom … 1 top) of a point at (height, z) for the free camera at distance multiplier `m`
    /// and camera height factor `tilt`, looking at `baseZ`.
    private static func ndcY(_ y: CGFloat, _ z: CGFloat, baseZ: CGFloat, m: CGFloat, tilt: CGFloat) -> CGFloat {
        let cy = 14.2 * m * tilt, dz = 19.3 * m
        let n = hypot(cy, dz)
        let fy = -cy / n, fz = -dz / n
        let vy = y - cy, vz = z - (baseZ + dz)
        return (vy * -fz + vz * fy) / ((vy * fy + vz * fz) * fovHalfTan)
    }

    static let maxTilt: CGFloat = 1.5

    /// Fits the arena horizontally, then raises the camera (a steeper view uses the spare screen height) and centres wall top to front edge vertically.
    static func frame(xHalf: CGFloat, zFar: CGFloat, aspect: CGFloat) -> (fit: CGFloat, shift: CGFloat, tilt: CGFloat) {
        let halfW = baseDistance * fovHalfTan * max(aspect, 0.5)
        var m = max(1, (xHalf + 1.0) / halfW)
        let topY: CGFloat = 6.4, topZ: CGFloat = -0.4, bottomZ = zFar - 0.4, want: CGFloat = 1.76
        func solve(_ m: CGFloat, _ tilt: CGFloat) -> (bz: CGFloat, extent: CGFloat) {
            var lo: CGFloat = -8, hi: CGFloat = 18
            for _ in 0..<22 {
                let mid = (lo + hi) / 2
                let c = (ndcY(topY, topZ, baseZ: mid, m: m, tilt: tilt) + ndcY(0, bottomZ, baseZ: mid, m: m, tilt: tilt)) / 2
                if c > 0 { hi = mid } else { lo = mid }
            }
            let bz = (lo + hi) / 2
            return (bz, ndcY(topY, topZ, baseZ: bz, m: m, tilt: tilt) - ndcY(0, bottomZ, baseZ: bz, m: m, tilt: tilt))
        }
        for _ in 0..<30 {
            if solve(m, 1).extent <= want { break }
            m *= 1.04
        }
        var lo: CGFloat = 1, hi = maxTilt
        if solve(m, hi).extent <= want { lo = hi } else {
            for _ in 0..<14 {
                let mid = (lo + hi) / 2
                if solve(m, mid).extent <= want { lo = mid } else { hi = mid }
            }
        }
        return (m, solve(m, lo).bz - 3.5, lo)
    }

    static let zoomRange: ClosedRange<CGFloat> = 0.5...3.0
    static let zoomStep: CGFloat = 1.25

    static func clampZoom(_ z: CGFloat) -> CGFloat { min(max(z.isFinite ? z : 1, zoomRange.lowerBound), zoomRange.upperBound) }
    static func steppedZoom(_ z: CGFloat, direction: Int) -> CGFloat {
        let v = clampZoom(direction > 0 ? z * zoomStep : z / zoomStep)
        return abs(v - 1) < 0.04 ? 1 : v
    }
    /// Scroll-wheel / pinch delta to a zoom factor (positive delta zooms in).
    static func zoom(_ z: CGFloat, scrollDelta d: CGFloat) -> CGFloat { clampZoom(z * exp(min(max(d, -40), 40) * 0.012)) }
    static func zoom(_ z: CGFloat, magnification m: CGFloat) -> CGFloat { clampZoom(z * max(0.2, 1 + m)) }
}

/// Smoothly animated playable area: grows with the occupied job spots and shrinks again when agents leave.
struct ArenaState {
    var xHalf: CGFloat = 14.6
    var zFar: CGFloat = 7.8

    mutating func ease(toward target: (xHalf: CGFloat, zFar: CGFloat), dt: Double, snap: Bool) {
        let k = snap ? 1 : CGFloat(1 - exp(-dt * 2.2))
        xHalf += (target.xHalf - xHalf) * k
        zFar += (target.zFar - zFar) * k
    }
}

/// Oversized ground, side walls and on-demand decor so a zoomed-out camera never sees the edge of the set.
@MainActor
final class ArenaExtension {
    let root = SCNNode()
    private var decor: [(node: SCNNode, threshold: CGFloat)] = []

    func build(theme: Theme, env: SCNNode) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        decor = []
        buildGround(env: env, theme: theme)
        buildWalls(env: env)
        buildDecor(theme)
    }

    private static func average(of m: SCNMaterial) -> UInt32 {
        guard let img = m.diffuse.contents as? NSImage, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0x555555 }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let d = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return 0x555555 }
        return UInt32(d[0]) << 16 | UInt32(d[1]) << 8 | UInt32(d[2])
    }

    private func buildGround(env: SCNNode, theme: Theme) {
        guard let floor = env.childNode(withName: "floor", recursively: false), let box = floor.geometry as? SCNBox,
              let mat = box.firstMaterial else { return }
        let fw = box.width, fd = box.length, fz = CGFloat(floor.position.z)
        let ground: SCNMaterial
        if theme == .football {
            ground = Gfx.mat(ArenaExtension.average(of: mat), r: 0.95)
        } else {
            ground = mat.copy() as! SCNMaterial
        }
        let keepsTexture = theme != .football
        let base = mat.diffuse.contentsTransform
        func slab(_ w: CGFloat, _ d: CGFloat, _ x: CGFloat, _ z: CGFloat) {
            let g = SCNBox(width: w, height: 0.3, length: d, chamferRadius: 0)
            let m = ground.copy() as! SCNMaterial
            if keepsTexture {
                m.diffuse.contentsTransform = SCNMatrix4MakeScale(base.m11 * w / fw, base.m22 * d / fd, 1)
                m.diffuse.wrapS = .repeat
                m.diffuse.wrapT = .repeat
            }
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(x, -0.15, z)
            n.name = "floor"
            n.castsShadow = false
            root.addChildNode(n)
        }
        let side: CGFloat = 120
        let farZ = fz + fd / 2 + 60
        let depth = farZ - (fz - fd / 2)
        slab(side, depth, -(fw / 2 + side / 2), fz - fd / 2 + depth / 2)
        slab(side, depth, fw / 2 + side / 2, fz - fd / 2 + depth / 2)
        slab(fw, farZ - (fz + fd / 2), 0, fz + fd / 2 + (farZ - (fz + fd / 2)) / 2)
    }

    private func buildWalls(env: SCNNode) {
        for n in env.childNodes {
            guard let b = n.geometry as? SCNBox, b.width >= 30, b.height >= 4, abs(n.position.z) < 1.5, n.name != "floor",
                  let mat = b.firstMaterial else { continue }
            for sign: CGFloat in [-1, 1] {
                let g = SCNBox(width: 120, height: b.height, length: b.length, chamferRadius: 0)
                let m = mat.copy() as! SCNMaterial
                let t = m.diffuse.contentsTransform
                m.diffuse.contentsTransform = SCNMatrix4MakeScale(t.m11 * 120 / b.width, t.m22, 1)
                m.diffuse.wrapS = .repeat
                g.materials = [m]
                let w = SCNNode(geometry: g)
                w.position = SCNVector3(sign * (b.width / 2 + 60), CGFloat(n.position.y), CGFloat(n.position.z))
                w.castsShadow = false
                root.addChildNode(w)
            }
            // Tall zoomed-out framings would otherwise show void above the wall.
            let capH: CGFloat = 14
            let cg = SCNBox(width: 240, height: capH, length: b.length, chamferRadius: 0)
            let cm = mat.copy() as! SCNMaterial
            let ct = cm.diffuse.contentsTransform
            cm.diffuse.contentsTransform = SCNMatrix4MakeScale(ct.m11 * 240 / b.width, ct.m22 * capH / b.height, 1)
            cm.diffuse.wrapS = .repeat
            cm.diffuse.wrapT = .repeat
            cg.materials = [cm]
            let cap = SCNNode(geometry: cg)
            cap.position = SCNVector3(0, CGFloat(n.position.y) + b.height / 2 + capH / 2, CGFloat(n.position.z))
            cap.castsShadow = false
            root.addChildNode(cap)
        }
    }

    /// Lamp posts and crate stacks along the back edge; each one fades in when the arena grows past it.
    private func buildDecor(_ theme: Theme) {
        let (primary, secondary) = Jobs.accent(theme)
        let metal = Gfx.mat(secondary, r: 0.5, m: 0.4), wood = Gfx.mat(0x7a5a38, r: 0.85), lit = Gfx.mat(primary, r: 0.4, e: primary, eIntensity: 0.9)
        for i in 0..<7 {
            for sign: CGFloat in [-1, 1] {
                let x = sign * (21.5 + CGFloat(i) * 7)
                let g = SCNNode()
                g.position = SCNVector3(x, 0, 0.5)
                if i % 2 == 0 {
                    g.cyl(0.08, 2.6, metal, 0, 1.3, 0)
                    g.box(0.5, 0.25, 0.5, lit, 0, 2.7, 0, round: 0.05)
                } else {
                    g.box(0.8, 0.8, 0.8, wood, 0, 0.4, 0, round: 0.03)
                    g.box(0.6, 0.6, 0.6, wood, 0.1, 1.1, 0.05, round: 0.03)
                }
                g.opacity = 0
                g.isHidden = true
                root.addChildNode(g)
                decor.append((g, abs(x) - 5))
            }
        }
    }

    /// Fades decor in/out as the (smoothed) arena half-width passes it. Cheap: only touches nodes that are changing.
    func update(xHalf: CGFloat, dt: Double, snap: Bool) {
        let step = snap ? 1 : CGFloat(dt / 0.6)
        for d in decor {
            let want: CGFloat = xHalf >= d.threshold ? 1 : 0
            let cur = d.node.opacity
            guard cur != want else { continue }
            let next = snap ? want : cur + min(max(want - cur, -step), step)
            d.node.opacity = next
            d.node.isHidden = next <= 0.001
        }
    }
}

/// Small unobtrusive zoom control (+ / − / fit) shown next to the camera control in the stage corner.
struct StageZoomControl: View {
    @ObservedObject var stage: Stage

    var body: some View {
        HStack(spacing: 0) {
            button("minus", help: "Zoom out (⌘−)", key: "-") { stage.zoomBy(direction: -1) }
            button(stage.isFitted ? "arrow.up.left.and.down.right.magnifyingglass" : "scope", help: "Fit: auto-framing (⌘0)", key: "0") { stage.resetZoom() }
                .opacity(stage.isFitted ? 0.55 : 1)
            button("plus", help: "Zoom in (⌘+)", key: "=") { stage.zoomBy(direction: 1) }
        }
        .padding(.vertical, 8)
        .opacity(0.85)
    }

    private func button(_ icon: String, help: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 24)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(help)
        .accessibilityLabel(help)
    }
}
