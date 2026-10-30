import SceneKit
import AppKit

/// A small themed pet that wanders near the captain, jumps on success and hides on failure.
@MainActor
final class Mascot {
    enum Kind { case sheepdog, hound, cat, pony, owl, droid, drone, bean, ball, robot }
    enum Reaction { case success, failure }

    let node = SCNNode()
    private let body = SCNNode()
    private var legs: [SCNNode] = []
    private var wings: [SCNNode] = []
    private var spinner: SCNNode?
    private let kind: Kind
    private let flies: Bool
    private var x: CGFloat, z: CGFloat
    private var yaw: CGFloat = 0
    private var target: CGPoint
    private var nextWander = 0.0
    private var phase = 0.0
    private var jumpUntil = 0.0
    private var hideUntil = 0.0
    private var moving = false

    static func kind(for theme: Theme) -> Kind {
        if let k = ThemeExtensions.active?.mascotKind(theme) { return k }
        return switch theme {
        case .space: .drone
        case .kitchen: .cat
        case .prison: .hound
        case .football: .ball
        case .farm: .sheepdog
        case .impostor: .bean
        case .wizard: .owl
        case .galactic: .droid
        case .fellowship: .pony
        default: .robot
        }
    }

    private var voice: (happy: String, scared: String) {
        switch kind {
        case .sheepdog, .hound: ("Woof!", "…whimper")
        case .cat: ("Mrow!", "…hiss")
        case .pony: ("Neigh!", "…snort")
        case .owl: ("Hoo!", "…hoo?")
        case .droid, .drone, .robot: ("Beep!", "…bzzt")
        case .bean: ("Blorp!", "…blip")
        case .ball: ("Boing!", "…eep")
        }
    }

    init(kind: Kind, start: CGPoint) {
        self.kind = kind
        flies = [.owl, .drone].contains(kind)
        x = Environments.wx(start.x) + 1.8
        z = Environments.wz(start.y) + 0.6
        target = CGPoint(x: x, y: z)
        node.name = "mascot"
        node.scale = SCNVector3(1.5, 1.5, 1.5)
        node.addChildNode(body)
        build()
        node.position = SCNVector3(x, 0, z)
    }

    // MARK: Behaviour

    func react(_ r: Reaction, t: Double) {
        switch r {
        case .success:
            jumpUntil = t + 1.3
            hideUntil = 0
            say(voice.happy)
        case .failure:
            hideUntil = t + 4.5
            jumpUntil = 0
            say(voice.scared)
        }
    }

    private func say(_ text: String) {
        let b = Gfx.billboard(Gfx.bubble(text, size: 20), unitsPerPoint: 0.02)
        b.position = SCNVector3(0, 1.4, 0)
        node.addChildNode(b)
        b.runAction(.sequence([.group([.moveBy(x: 0, y: 0.4, z: 0, duration: 1.8), .sequence([.wait(duration: 1.3), .fadeOut(duration: 0.5)])]), .removeFromParentNode()]))
    }

    func update(captain: CGPoint, sleeping: Bool, t: Double, dt: Double) {
        let cx = Environments.wx(captain.x), cz = Environments.wz(captain.y)
        let scared = t < hideUntil
        if scared {
            // tuck in beside the captain (not behind: its speech bubble would sit on the captain's name pill)
            target = CGPoint(x: cx + (x < cx ? -1.7 : 1.7), y: cz + 0.1)
        } else if hypot(cx - x, cz - z) > 4 {
            target = CGPoint(x: cx + (x - cx) * 0.3, y: cz + (z - cz) * 0.3)
            nextWander = t + 1.5
        } else if t > nextWander {
            let a = Double.random(in: 0..<(.pi * 2)), r = Double.random(in: 1.6...3.4)
            target = CGPoint(x: cx + CGFloat(cos(a) * r), y: cz + CGFloat(sin(a) * r * 0.6))
            nextWander = t + Double.random(in: 3...7)
        }
        target.x = min(max(target.x, -13.5), 13.5)
        target.y = min(max(target.y, 0.6), 7.6)

        let dx = target.x - x, dz = target.y - z
        let d = hypot(dx, dz)
        moving = d > 0.12 && !sleeping
        if moving {
            let speed: CGFloat = (scared ? 6 : (d > 3 ? 6 : 3)) * CGFloat(dt)
            let s = min(speed, d)
            x += dx / d * s
            z += dz / d * s
            var diff = atan2(dx, dz) - yaw
            while diff > .pi { diff -= .pi * 2 }
            while diff < -.pi { diff += .pi * 2 }
            yaw += diff * min(1, CGFloat(dt) * 10)
            phase += dt * (d > 3 ? 14 : 9)
        } else {
            phase += dt * 2
        }
        node.position = SCNVector3(x, 0, z)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        pose(t: t, scared: scared, sleeping: sleeping)
    }

    private func pose(t: Double, scared: Bool, sleeping: Bool) {
        var lift: CGFloat = flies ? 0.7 + 0.08 * CGFloat(sin(phase * 0.8)) : (kind == .droid ? 0.05 : 0)
        var squash: CGFloat = 1
        var shake: CGFloat = 0
        if t < jumpUntil {
            let k = (jumpUntil - t) / 1.3
            lift += CGFloat(abs(sin(k * .pi * 3))) * 0.9
        } else if scared {
            squash = 0.65
            shake = CGFloat(sin(t * 40)) * 0.03
        } else if sleeping {
            squash = 0.8
        } else if moving, kind == .ball {
            lift += CGFloat(abs(sin(phase))) * 0.35
        } else if moving, !flies {
            lift += CGFloat(abs(sin(phase))) * 0.05
        }
        body.position = SCNVector3(shake, lift, 0)
        body.scale = SCNVector3(1, squash, 1)
        let swing = moving ? CGFloat(sin(phase)) * 0.7 : 0
        for (i, l) in legs.enumerated() { l.eulerAngles.x = (i % 2 == 0 ? swing : -swing) * (scared ? 0.2 : 1) }
        let flap = flies ? CGFloat(sin(phase * (moving ? 3 : 1.2))) * (moving ? 0.7 : 0.25) : 0
        for (i, w) in wings.enumerated() { w.eulerAngles.z = (i == 0 ? 1 : -1) * flap }
        spinner?.eulerAngles.y = CGFloat(phase * 0.8)
        if kind == .ball { body.eulerAngles.x = moving ? CGFloat(phase * 0.5) : 0 }
    }

    // MARK: Models

    @discardableResult
    private func part(_ g: SCNGeometry, _ hex: UInt32, _ p: SCNVector3, parent: SCNNode? = nil, scale: SCNVector3? = nil, e: UInt32? = nil) -> SCNNode {
        let n = (parent ?? body).add(g, Gfx.mat(hex, r: 0.8, e: e), at: p)
        if let scale { n.scale = scale }
        return n
    }

    private func eyes(y: CGFloat, z: CGFloat, spread: CGFloat, r: CGFloat = 0.035, parent: SCNNode? = nil, hex: UInt32 = 0x101010) {
        for s: CGFloat in [-1, 1] { _ = part(SCNSphere(radius: r), hex, SCNVector3(spread * s, y, z), parent: parent) }
    }

    private func build() {
        switch kind {
        case .sheepdog: quadruped(coat: 0xf2f2ee, patch: 0x1e1e22, ears: 0x1e1e22, earStyle: .floppy, height: 0.3, size: 1)
        case .hound: quadruped(coat: 0xb98a58, patch: 0x7a5530, ears: 0x5a3b1f, earStyle: .floppy, height: 0.28, size: 1.05)
        case .cat: quadruped(coat: 0xe8892e, patch: 0xf7e2c2, ears: 0xe8892e, earStyle: .pointy, height: 0.2, size: 0.8)
        case .pony: quadruped(coat: 0x8a4f2a, patch: 0x2a1a10, ears: 0x8a4f2a, earStyle: .pointy, height: 0.5, size: 1.25, mane: true)
        case .owl: owl()
        case .droid: droid()
        case .drone: drone()
        case .bean: bean()
        case .ball: ball()
        case .robot: robot()
        }
    }

    private enum EarStyle { case floppy, pointy }

    private func quadruped(coat: UInt32, patch: UInt32, ears: UInt32, earStyle: EarStyle, height: CGFloat, size: CGFloat, mane: Bool = false) {
        body.scale = SCNVector3(1, 1, 1)
        let rig = SCNNode()
        rig.scale = SCNVector3(size, size, size)
        body.addChildNode(rig)
        let h = height
        _ = part(SCNBox(width: 0.34, height: 0.3, length: 0.7, chamferRadius: 0.08), coat, SCNVector3(0, h + 0.15, 0), parent: rig)
        _ = part(SCNBox(width: 0.36, height: 0.12, length: 0.4, chamferRadius: 0.05), patch, SCNVector3(0, h + 0.3, -0.02), parent: rig)
        let neck: CGFloat = mane ? 0.22 : 0.05
        let head = SCNNode()
        head.position = SCNVector3(0, h + 0.3 + neck, 0.4)
        rig.addChildNode(head)
        _ = part(SCNBox(width: 0.26, height: 0.24, length: 0.26, chamferRadius: 0.06), mane ? coat : (kind == .sheepdog ? patch : coat), SCNVector3(0, 0, 0), parent: head)
        _ = part(SCNBox(width: 0.14, height: 0.12, length: 0.18, chamferRadius: 0.04), kind == .sheepdog ? 0xf2f2ee : patch, SCNVector3(0, -0.04, 0.2), parent: head)
        _ = part(SCNSphere(radius: 0.03), 0x101010, SCNVector3(0, -0.01, 0.3), parent: head)
        eyes(y: 0.05, z: 0.13, spread: 0.08, parent: head)
        for s: CGFloat in [-1, 1] {
            switch earStyle {
            case .floppy:
                let e = part(SCNBox(width: 0.06, height: 0.22, length: 0.12, chamferRadius: 0.02), ears, SCNVector3(0.15 * s, -0.02, -0.02), parent: head)
                e.eulerAngles.z = 0.25 * s
            case .pointy:
                _ = part(SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.16), ears, SCNVector3(0.09 * s, 0.19, -0.02), parent: head)
            }
        }
        if mane { _ = part(SCNBox(width: 0.06, height: 0.34, length: 0.14, chamferRadius: 0.02), patch, SCNVector3(0, h + 0.38, 0.3), parent: rig) }
        let tail = part(SCNBox(width: 0.07, height: 0.07, length: kind == .cat ? 0.5 : 0.26, chamferRadius: 0.03), kind == .sheepdog ? 0xf2f2ee : (mane ? patch : coat), SCNVector3(0, h + 0.3, -0.5), parent: rig)
        tail.eulerAngles.x = kind == .cat ? 0.9 : -0.6
        for (i, p) in [(-1, 1), (1, 1), (-1, -1), (1, -1)].enumerated() {
            let hip = SCNNode()
            hip.position = SCNVector3(0.12 * CGFloat(p.0), h + 0.05, 0.24 * CGFloat(p.1))
            let leg = SCNNode()
            leg.add(SCNBox(width: 0.09, height: h + 0.05, length: 0.09, chamferRadius: 0.02), Gfx.mat(kind == .sheepdog ? 0xf2f2ee : coat, r: 0.8), at: SCNVector3(0, -(h + 0.05) / 2, 0))
            hip.addChildNode(leg)
            rig.addChildNode(hip)
            legs.append(hip)
            _ = i
        }
    }

    private func owl() {
        _ = part(SCNSphere(radius: 0.26), 0x8a6a4a, SCNVector3(0, 0.3, 0), scale: SCNVector3(0.9, 1.1, 0.9))
        _ = part(SCNSphere(radius: 0.17), 0xe9dcc0, SCNVector3(0, 0.25, 0.14), scale: SCNVector3(1, 1.1, 0.5))
        for s: CGFloat in [-1, 1] {
            part(SCNCylinder(radius: 0.09, height: 0.03), 0xffe9a0, SCNVector3(0.1 * s, 0.46, 0.2), e: 0xaa8a30).eulerAngles.x = .pi / 2
            _ = part(SCNSphere(radius: 0.035), 0x101010, SCNVector3(0.1 * s, 0.46, 0.225))
            _ = part(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.12), 0x6a4a2a, SCNVector3(0.13 * s, 0.6, 0.02))
            let pivot = SCNNode()
            pivot.position = SCNVector3(0.2 * s, 0.36, 0)
            body.addChildNode(pivot)
            _ = part(SCNBox(width: 0.38, height: 0.05, length: 0.24, chamferRadius: 0.02), 0x6e5033, SCNVector3(0.19 * s, 0, 0), parent: pivot)
            wings.append(pivot)
        }
        part(SCNCone(topRadius: 0, bottomRadius: 0.04, height: 0.1), 0xe0a020, SCNVector3(0, 0.4, 0.24)).eulerAngles.x = .pi / 2
    }

    private func droid() {
        _ = part(SCNCylinder(radius: 0.2, height: 0.32), 0xe8eaee, SCNVector3(0, 0.3, 0))
        let dome = part(SCNSphere(radius: 0.2), 0xe8eaee, SCNVector3(0, 0.46, 0), scale: SCNVector3(1, 0.9, 1))
        _ = part(SCNSphere(radius: 0.06), 0xff3a2a, SCNVector3(0, 0.02, 0.18), parent: dome, e: 0xff2010)
        _ = part(SCNBox(width: 0.3, height: 0.06, length: 0.06, chamferRadius: 0), 0x3a7ac8, SCNVector3(0, 0.3, 0.19))
        _ = part(SCNCylinder(radius: 0.012, height: 0.3), 0x888c94, SCNVector3(0.08, 0.76, 0))
        _ = part(SCNSphere(radius: 0.03), 0xffb030, SCNVector3(0.08, 0.92, 0), e: 0xffa010)
        for s: CGFloat in [-1, 1] {
            let w = part(SCNCylinder(radius: 0.09, height: 0.08), 0x555a66, SCNVector3(0.2 * s, 0.09, 0))
            w.eulerAngles.z = .pi / 2
        }
        spinner = dome
    }

    private func drone() {
        _ = part(SCNSphere(radius: 0.22), 0xd8dde6, SCNVector3(0, 0.3, 0), scale: SCNVector3(1, 0.8, 1))
        _ = part(SCNSphere(radius: 0.09), 0x5fd4ff, SCNVector3(0, 0.3, 0.17), e: 0x2aa8ff)
        let ring = SCNNode()
        ring.position = SCNVector3(0, 0.3, 0)
        body.addChildNode(ring)
        _ = part(SCNTorus(ringRadius: 0.32, pipeRadius: 0.025), 0x8f7bff, SCNVector3(0, 0, 0), parent: ring, e: 0x4a3acc)
        for s: CGFloat in [-1, 1] {
            let w = part(SCNBox(width: 0.18, height: 0.02, length: 0.1, chamferRadius: 0), 0x9ec8ff, SCNVector3(0.26 * s, 0.4, -0.05), e: 0x4a7acc)
            _ = w
        }
        spinner = ring
        _ = part(SCNCylinder(radius: 0.01, height: 0.2), 0x888c94, SCNVector3(0, 0.6, 0))
    }

    private func bean() {
        let c: UInt32 = [0x2fbf5a, 0xe86a2f, 0x3a8ae8][Int.random(in: 0..<3)]
        _ = part(SCNCapsule(capRadius: 0.2, height: 0.62), c, SCNVector3(0, 0.34, 0))
        _ = part(SCNBox(width: 0.28, height: 0.13, length: 0.1, chamferRadius: 0.05), 0xaee8f4, SCNVector3(0, 0.46, 0.18), e: 0x3a6a80)
        _ = part(SCNCone(topRadius: 0, bottomRadius: 0.05, height: 0.16), 0x5ad06a, SCNVector3(0, 0.74, 0))
        for s: CGFloat in [-1, 1] {
            let l = SCNNode()
            l.position = SCNVector3(0.1 * s, 0.1, 0)
            _ = part(SCNBox(width: 0.12, height: 0.12, length: 0.14, chamferRadius: 0.04), c, SCNVector3(0, -0.04, 0), parent: l)
            body.addChildNode(l)
            legs.append(l)
        }
    }

    private func ball() {
        let b = part(SCNSphere(radius: 0.26), 0xf4f4f0, SCNVector3(0, 0.3, 0))
        for p in [SCNVector3(0, 0.26, 0.05), SCNVector3(0.22, 0.05, 0.08), SCNVector3(-0.2, 0.0, -0.1), SCNVector3(0.05, -0.2, 0.15)] {
            _ = part(SCNSphere(radius: 0.09), 0x1a1a1e, p, parent: b, scale: SCNVector3(1, 0.5, 1))
        }
        eyes(y: 0.34, z: 0.23, spread: 0.09, r: 0.045, hex: 0x101010)
        for s: CGFloat in [-1, 1] {
            let l = SCNNode()
            l.position = SCNVector3(0.1 * s, 0.07, 0)
            _ = part(SCNBox(width: 0.1, height: 0.07, length: 0.16, chamferRadius: 0.03), 0xff6a2a, SCNVector3(0, -0.02, 0.03), parent: l)
            body.addChildNode(l)
            legs.append(l)
        }
    }

    private func robot() {
        _ = part(SCNBox(width: 0.34, height: 0.3, length: 0.28, chamferRadius: 0.05), 0xc9ced8, SCNVector3(0, 0.28, 0))
        _ = part(SCNBox(width: 0.28, height: 0.2, length: 0.24, chamferRadius: 0.05), 0xe8ecf2, SCNVector3(0, 0.55, 0))
        _ = part(SCNBox(width: 0.2, height: 0.07, length: 0.04, chamferRadius: 0.02), 0xf2661f, SCNVector3(0, 0.56, 0.125), e: 0xf2661f)
        _ = part(SCNCylinder(radius: 0.012, height: 0.2), 0x888c94, SCNVector3(0, 0.76, 0))
        _ = part(SCNSphere(radius: 0.03), 0xff4a3a, SCNVector3(0, 0.88, 0), e: 0xff2010)
        for s: CGFloat in [-1, 1] {
            let w = part(SCNCylinder(radius: 0.08, height: 0.07), 0x333842, SCNVector3(0.17 * s, 0.08, 0))
            w.eulerAngles.z = .pi / 2
        }
    }
}
