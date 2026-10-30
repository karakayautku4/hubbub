import SceneKit
import AppKit

enum Motion { case type, hammer, stir, bend, paint, sweep, scan, kick }

final class Rig {
    let root = SCNNode()
    let body = SCNNode()
    let head = SCNNode()
    let armL = SCNNode(), armR = SCNNode()
    let legL = SCNNode(), legR = SCNNode()
    let handR = SCNNode()
    let carryNode = SCNNode()
    let ring: SCNNode
    var nameNode: SCNNode?
    var bubbleNode: SCNNode?
    var bubbleText: String?
    var nameText = ""
    var badge: String?
    var lastPos = SCNVector3Zero
    var yaw: CGFloat = 0
    var carryKind: Carry?
    var isSheep = false
    var isCaptain = false
    var labelY: CGFloat = 2.85
    var woolMats: [SCNMaterial] = []
    var woolBase: UInt32 = 0xf4f1e8
    var sick = false
    var mv = MetricsState()
    var plateWidth: CGFloat = 0

    init(actor: Actor, theme: Theme) {
        root.name = "actor:\(actor.id)"
        let v = actor.variant
        let skins: [UInt32] = [0xf2c9a0, 0xe0a878, 0xc68642, 0x8d5524, 0xffdbb4, 0xd9a066]
        let hairs: [UInt32] = [0x2b1b12, 0x6b3f1d, 0xc9a227, 0x1c1c1c, 0x8a3b12, 0x777777]
        let cap = actor.isCaptain
        isCaptain = cap
        var skinHex = skins[v % skins.count], hairHex = hairs[(v / 7) % hairs.count]
        if let o = theme.ov {
            let s = o.colors(o.characters?.skins)
            if !s.isEmpty { skinHex = s[v % s.count] }
        }
        let skin = Gfx.mat(skinHex, r: 0.8)
        let hair = Gfx.mat(hairHex, r: 0.9)
        var (top, bottom, accent) = Rig.outfit(theme, captain: cap, v: v)
        if let o = theme.ov {
            if cap { top = o.color(o.characters?.captainShirt) ?? top }
            else { let s = o.colors(o.characters?.shirts); if !s.isEmpty { top = s[v % s.count] } }
            accent = o.color(o.palette?.accent) ?? accent
        }
        if theme == .farm && !cap { isSheep = true; labelY = 1.95 }
        let topM = Gfx.mat(top, r: 0.85), botM = Gfx.mat(bottom, r: 0.85), accM = Gfx.mat(accent, r: 0.5)
        let shoe = Gfx.mat(0x222222, r: 0.6)

        ring = SCNNode(geometry: SCNTorus(ringRadius: 0.62, pipeRadius: 0.05))
        ring.geometry?.materials = [Gfx.mat(0xffd54a, r: 0.3, e: 0xffd54a)]
        ring.position = SCNVector3(0, 0.05, 0)
        ring.isHidden = true
        root.addChildNode(ring)

        // The inner node scales the captain up without touching the logical position.
        let figure = root.group("figure", 0, 0, 0)
        figure.scale = cap ? SCNVector3(1.12, 1.12, 1.12) : SCNVector3(1, 1, 1)
        if isSheep { buildSheep(figure, v); return }
        for (leg, x) in [(legL, -0.16), (legR, 0.16)] {
            leg.position = SCNVector3(x, 0.8, 0)
            leg.box(0.24, 0.8, 0.26, botM, 0, -0.4, 0, round: 0.04)
            leg.box(0.27, 0.14, 0.38, shoe, 0, -0.76, 0.05, round: 0.05)
            figure.addChildNode(leg)
        }
        body.position = SCNVector3(0, 0.8, 0)
        figure.addChildNode(body)
        body.box(0.66, 0.74, 0.38, topM, 0, 0.37, 0, round: 0.1)
        body.box(0.68, 0.1, 0.4, accM, 0, 0.05, 0, round: 0.03)
        for (arm, x) in [(armL, -0.42), (armR, 0.42)] {
            arm.position = SCNVector3(x, 0.66, 0)
            arm.box(0.19, 0.6, 0.21, topM, 0, -0.27, 0, round: 0.07)
            arm.ball(0.11, skin, 0, -0.62, 0)
            body.addChildNode(arm)
        }
        handR.position = SCNVector3(0, -0.66, 0.05)
        armR.addChildNode(handR)
        handR.addChildNode(carryNode)

        head.position = SCNVector3(0, 0.78, 0)
        body.addChildNode(head)
        head.ball(0.3, skin, 0, 0.3, 0)
        for x in [-0.11, 0.11] {
            head.ball(0.045, Gfx.mat(0x151515, r: 0.2), x, 0.34, 0.27)
        }
        head.box(0.12, 0.03, 0.04, Gfx.mat(0x8a3b3b, r: 0.5), 0, 0.2, 0.28)
        Rig.accessories(theme, captain: cap, number: v % 90 + 10, rig: self, hair: hair, accM: accM, topM: topM)
        if cap { applyProgressionCosmetics() }
    }

    static func outfit(_ t: Theme, captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) {
        switch t {
        case .space:
            let suits: [UInt32] = [0xe8eef5, 0xdfe6f0, 0xcfe3f5, 0xf0e6d8]
            return captain ? (0xc8372d, 0x2a2f55, 0xffd24a) : (suits[v % suits.count], 0x3a4a78, 0x3fa9f5)
        case .kitchen:
            return captain ? (0xffffff, 0x333a44, 0xc8372d) : (0xf6f6f2, 0x4a5568, 0x4a90d9)
        case .prison:
            return captain ? (0x25324d, 0x1b2438, 0xd4af37) : (0xf08a1e, 0xe27a10, 0x2a2a2a)
        case .football:
            let k = Team.current.kit
            return captain ? (0x161616, 0x161616, 0xffd400) : (k.0, k.1, k.2)
        case .farm:
            return (0xc8372d, 0x3a6ab0, 0xe8c15a)
        case .impostor: return impostorOutfit(captain: captain, v: v)
        case .wizard: return wizardOutfit(captain: captain, v: v)
        case .galactic: return galacticOutfit(captain: captain, v: v)
        case .fellowship: return fellowshipOutfit(captain: captain, v: v)
        }
    }

    static func accessories(_ t: Theme, captain: Bool, number: Int, rig: Rig, hair: SCNMaterial, accM: SCNMaterial, topM: SCNMaterial) {
        let head = rig.head
        func hairCap() { head.add(SCNSphere(radius: 0.32), hair, at: SCNVector3(0, 0.36, -0.04)) }
        switch t {
        case .impostor: impostorAccessories(captain: captain, number: number, rig: rig, hair: hair, accM: accM, topM: topM)
        case .wizard: wizardAccessories(captain: captain, number: number, rig: rig, hair: hair, accM: accM, topM: topM)
        case .galactic: galacticAccessories(captain: captain, number: number, rig: rig, hair: hair, accM: accM, topM: topM)
        case .fellowship: fellowshipAccessories(captain: captain, number: number, rig: rig, hair: hair, accM: accM, topM: topM)
        case .football:
            hairCap()
            for leg in [rig.legL, rig.legR] {
                leg.box(0.28, 0.42, 0.3, captain ? Gfx.mat(0x161616, r: 0.8) : accM, 0, -0.55, 0, round: 0.04)
            }
            if captain {
                rig.body.box(0.12, 0.08, 0.05, Gfx.mat(0xffd400, r: 0.3), 0.15, 0.55, 0.2)
                rig.body.box(0.68, 0.06, 0.4, accM, 0, 0.6, 0)
            } else {
                rig.body.box(0.36, 0.06, 0.03, accM, 0, 0.62, 0.2)
                rig.body.box(0.24, 0.3, 0.03, accM, 0, 0.35, -0.2)
            }
        case .farm:
            hairCap()
            let straw = Gfx.mat(0xe0c26a, r: 0.9)
            head.cyl(0.46, 0.05, straw, 0, 0.55, 0)
            head.cyl(0.25, 0.22, straw, 0, 0.66, 0)
            head.cyl(0.26, 0.06, Gfx.mat(0xc8372d), 0, 0.58, 0)
            rig.body.box(0.5, 0.5, 0.05, Gfx.mat(0x3a6ab0, r: 0.8), 0, 0.3, 0.2)
            rig.body.box(0.06, 0.4, 0.04, Gfx.mat(0x3a6ab0), -0.18, 0.62, 0.2)
            rig.body.box(0.06, 0.4, 0.04, Gfx.mat(0x3a6ab0), 0.18, 0.62, 0.2)
        case .space:
            let glass = Gfx.mat(0x9fd8ff, r: 0.05, m: 0.2, alpha: 0.3)
            head.add(SCNSphere(radius: 0.4), glass, at: SCNVector3(0, 0.3, 0), shadow: false)
            head.cyl(0.43, 0.08, Gfx.mat(0xc9d2dc, r: 0.4, m: 0.6), 0, -0.04, 0)
            rig.body.box(0.4, 0.3, 0.1, Gfx.mat(0x9aa7b5, r: 0.4, m: 0.5), 0, 0.42, 0.22)
            rig.body.box(0.12, 0.06, 0.04, Gfx.mat(0x3cf0a0, e: 0x3cf0a0), -0.1, 0.5, 0.28)
            rig.body.box(0.12, 0.06, 0.04, Gfx.mat(0xff5a4d, e: 0xff5a4d), 0.1, 0.5, 0.28)
            if captain { head.add(SCNSphere(radius: 0.05), Gfx.mat(0xffd24a, e: 0xffd24a), at: SCNVector3(0, 0.74, 0)) }
        case .kitchen:
            hairCap()
            let white = Gfx.mat(0xffffff, r: 0.9)
            head.cyl(0.27, captain ? 0.46 : 0.3, white, 0, captain ? 0.78 : 0.7, 0)
            head.ball(captain ? 0.33 : 0.29, white, 0, captain ? 1.08 : 0.9, 0)
            rig.body.box(0.56, 0.5, 0.05, Gfx.mat(captain ? 0xe8e8e8 : 0x4a90d9, r: 0.8), 0, 0.3, 0.2)
            if captain { rig.body.box(0.5, 0.1, 0.4, Gfx.mat(0xc8372d), 0, 0.72, 0.03, round: 0.04) }
        case .prison:
            if captain {
                head.cyl(0.33, 0.1, Gfx.mat(0x1c2540), 0, 0.58, 0)
                head.box(0.4, 0.04, 0.22, Gfx.mat(0x0e1320, r: 0.3), 0, 0.55, 0.3)
                head.cyl(0.26, 0.2, Gfx.mat(0x25324d), 0, 0.66, 0)
                head.ball(0.05, Gfx.mat(0xd4af37, r: 0.2, m: 0.9), 0, 0.68, 0.27)
                rig.body.box(0.12, 0.14, 0.03, Gfx.mat(0xd4af37, r: 0.2, m: 0.9), -0.2, 0.52, 0.2)
            } else {
                let stubble = Gfx.mat(0x3a2a20, r: 0.9)
                head.add(SCNSphere(radius: 0.305), stubble, at: SCNVector3(0, 0.38, -0.02))
                rig.body.box(0.3, 0.2, 0.03, Gfx.mat(0xffffff, r: 0.9), 0, 0.42, 0.2)
                rig.body.add(SCNBox(width: 0.02, height: 0.02, length: 0.02, chamferRadius: 0), accM, at: SCNVector3(0, 0.42, 0.22))
            }
        }
    }

    func setCarry(_ c: Carry?) {
        guard c != carryKind else { return }
        carryKind = c
        carryNode.childNodes.forEach { $0.removeFromParentNode() }
        switch c {
        case .cup:
            carryNode.cyl(0.07, 0.14, Gfx.mat(0xffffff, r: 0.4), 0, 0.05, 0.1)
            carryNode.cyl(0.055, 0.02, Gfx.mat(0x4a2c17, r: 0.3), 0, 0.12, 0.1)
        case .plate:
            carryNode.cyl(0.2, 0.03, Gfx.mat(0xffffff, r: 0.2), 0, 0.02, 0.18)
            carryNode.ball(0.09, Gfx.mat(0xe07b39, r: 0.6), 0, 0.09, 0.18)
        case .papers:
            carryNode.box(0.2, 0.03, 0.26, Gfx.mat(0xf4f4ea, r: 0.9), 0, 0.02, 0.15)
        case .ball:
            carryNode.ball(0.17, Gfx.mat(0xfafafa, r: 0.5), 0, 0.12, 0.2)
        case .card:
            carryNode.box(0.34, 0.48, 0.02, Gfx.mat(0xe0201a, r: 0.4, e: 0xb01010), 0, 0.3, 0.06)
        case nil: break
        }
    }

    func buildSheep(_ figure: SCNNode, _ v: Int) {
        let tints: [UInt32] = [0xf4f1e8, 0xfaf7ef, 0xe9e4d6, 0xefe9dc]
        woolBase = tints[v % tints.count]
        let wool = Gfx.mat(woolBase, r: 0.98)
        let faceBase: UInt32 = v % 5 == 0 ? 0x6a5a50 : 0x3a302b
        let face = Gfx.mat(faceBase, r: 0.8)
        woolMats = [wool, face]
        let dark = Gfx.mat(0x2b2622, r: 0.8)
        body.position = SCNVector3(0, 0.88, 0)
        figure.addChildNode(body)
        body.ball(0.44, wool, 0, 0, 0)
        body.ball(0.36, wool, 0, 0.05, 0.3)
        body.ball(0.38, wool, 0, 0.04, -0.3)
        for (x, y, z) in [(0.3, -0.05, 0.05), (-0.3, -0.05, 0.05), (0.15, 0.36, 0.1), (-0.15, 0.34, -0.15), (0, 0.3, 0.32)] {
            body.ball(0.26, wool, CGFloat(x), CGFloat(y), CGFloat(z))
        }
        body.ball(0.12, wool, 0, 0.1, -0.68)
        head.position = SCNVector3(0, 0.12, 0.5)
        body.addChildNode(head)
        let h = head.ball(0.2, face, 0, 0, 0.18)
        h.scale = SCNVector3(0.9, 0.95, 1.2)
        head.ball(0.15, wool, 0, 0.17, 0.08)
        for x in [-1.0, 1.0] {
            let ear = head.box(0.24, 0.06, 0.12, face, CGFloat(x) * 0.25, 0.04, 0.1)
            ear.eulerAngles = SCNVector3(0, 0, CGFloat(x) * -0.4)
            head.ball(0.055, Gfx.mat(0xffffff, r: 0.3), CGFloat(x) * 0.1, 0.07, 0.3)
            head.ball(0.03, Gfx.mat(0x111111, r: 0.2), CGFloat(x) * 0.1, 0.07, 0.34)
        }
        head.ball(0.04, Gfx.mat(0xd98a8a, r: 0.6), 0, -0.04, 0.4)
        for (leg, x) in [(legL, -0.2), (legR, 0.2)] {
            leg.position = SCNVector3(x, 0.5, -0.3)
            leg.box(0.13, 0.5, 0.13, dark, 0, -0.25, 0, round: 0.03)
            figure.addChildNode(leg)
        }
        for (arm, x) in [(armL, -0.2), (armR, 0.2)] {
            arm.position = SCNVector3(x, -0.35, 0.3)
            arm.box(0.13, 0.5, 0.13, dark, 0, -0.25, 0, round: 0.03)
            body.addChildNode(arm)
        }
    }

    func setSick(_ s: Bool) {
        guard isSheep, s != sick else { return }
        sick = s
        let wool = woolMats.first, face = woolMats.last
        wool?.diffuse.contents = s ? Gfx.color(0x7fd35a) : Gfx.color(woolBase)
        wool?.emission.contents = s ? Gfx.color(0x2c6a18) : NSColor.black
        face?.diffuse.contents = s ? Gfx.color(0x3e6b2a) : Gfx.color(0x3a302b)
    }

    func poseSheep(actor a: Actor, t: Double, moving: Bool, stationary: Bool, job: JobAnim? = nil) {
        let tt = CGFloat(t), v = CGFloat(a.variant)
        var lift: CGFloat = 0, bodyX: CGFloat = 0, bodyZ: CGFloat = 0, headX: CGFloat = 0, headY: CGFloat = 0
        var sw: CGFloat = 0, sheepDX: CGFloat = 0, sheepDZ: CGFloat = 0
        let phase = a.walked * 0.55 + v
        if a.dragged {
            sw = sin(tt * 14) * 0.9; lift = 0.9; headX = -0.4
        } else if moving {
            let f: CGFloat = a.mood == .panic ? 1.6 : (a.mood == .sick ? 0.6 : 1)
            sw = sin(phase * f) * 0.7
            lift = abs(sin(phase * f)) * (a.mood == .panic ? 0.25 : 0.05)
            bodyZ = a.mood == .sick ? sin(tt * 5) * 0.12 : 0
            headX = a.mood == .sick ? 0.5 : sin(phase * f * 2) * 0.05
        } else {
            switch a.mood {
            case .panic: lift = abs(sin(tt * 10)) * 0.3; bodyZ = sin(tt * 20) * 0.1; headX = -0.3
            case .celebrate: lift = abs(sin(tt * 7)) * 0.65; headX = -0.35; bodyX = -0.1
            case .sick: bodyZ = sin(tt * 4) * 0.14; headX = 0.7 + sin(tt * 3) * 0.1; lift = -0.04
            case .sad, .tired, .sleep: headX = 0.8; lift = -0.12
            case .dizzy: bodyZ = sin(tt * 6) * 0.2; headY = sin(tt * 8) * 0.5
            case .chat: headY = sin(tt * 2.5) * 0.3; headX = -0.1
            case .sip: headX = 0.7 + sin(tt * 5) * 0.15
            default:
                if a.phase == .working && stationary, let job {
                    let p = job.pose(t: tt, v: v)
                    lift = max(0, p.lift) * 0.8 + abs(p.dx) * 0.05; headX = p.headX * 0.9 + 0.1; headY = p.headY; bodyZ = p.bodyZ + sin(tt * 3 + v) * 0.04
                    bodyX = p.bodyX * 0.2; sw = p.lL * 0.6 + (job == .chase ? p.lL : 0)
                    sheepDX = p.dx; sheepDZ = p.dz
                } else if a.phase == .working && stationary {
                    switch a.kind {
                    case 1: bodyZ = sin(tt * 6) * 0.05; headX = 0.15; headY = sin(tt * 3) * 0.2
                    case 2: headX = 0.75 + sin(tt * 6) * 0.1
                    case 3: headY = sin(tt * 1.4 + v) * 0.5; headX = -0.1 + sin(tt * 2) * 0.1
                    default: headX = 0.65 + sin(tt * 3 + v) * 0.3; lift = 0
                    }
                } else if a.phase == .finishing { lift = abs(sin(tt * 7)) * 0.55 }
                else { headY = sin(tt * 0.8 + v) * 0.4; headX = sin(tt * 0.5 + v) * 0.1 }
            }
        }
        if a.ctx > 0.9, !a.dragged { headX = max(headX, 0.6 + sin(tt * 1.2) * 0.1); lift = min(lift, -0.05) }
        if a.approval, !moving, !a.dragged, a.mood == .none { lift = max(lift, abs(sin(tt * 5)) * 0.15); headX = -0.3 }
        body.eulerAngles = SCNVector3(bodyX, 0, bodyZ)
        head.eulerAngles = SCNVector3(headX, headY, 0)
        legL.eulerAngles = SCNVector3(sw, 0, 0)
        legR.eulerAngles = SCNVector3(-sw, 0, 0)
        armL.eulerAngles = SCNVector3(-sw, 0, 0)
        armR.eulerAngles = SCNVector3(sw, 0, 0)
        root.childNode(withName: "figure", recursively: false)?.position = SCNVector3(sheepDX, lift, sheepDZ)
    }

    /// Scales name pill and bubble together (used to keep labels legible when the camera is far away).
    func applyLabelScale(_ s: CGFloat) {
        for n in [nameNode, bubbleNode] {
            if let n, n.scale.x != s { n.scale = SCNVector3(s, s, s) }
        }
    }

    func setLabel(_ text: String) {
        guard text != nameText else { return }
        nameText = text
        nameNode?.removeFromParentNode()
        let n = Gfx.billboard(Gfx.label(text, size: 20))
        n.position = SCNVector3(0, labelY, 0)
        root.addChildNode(n)
        nameNode = n
    }

    func setBubble(_ text: String?) {
        guard text != bubbleText else { return }
        bubbleText = text
        bubbleNode?.removeFromParentNode()
        bubbleNode = nil
        guard let text else { return }
        let short = text.count > 26 ? String(text.prefix(25)) + "…" : text
        let n = Gfx.billboard(Gfx.bubble(short, size: 19), unitsPerPoint: 0.02)
        let h = (n.geometry as? SCNPlane)?.height ?? 1
        n.position = SCNVector3(0, labelY + 0.2 + h / 2, 0)
        root.addChildNode(n)
        bubbleNode = n
    }

    // MARK: Animation

    func pose(actor a: Actor, theme: Theme, t: Double, moving: Bool, motion: Motion, stationary: Bool, job: JobAnim? = nil) {
        if isSheep { poseSheep(actor: a, t: t, moving: moving, stationary: stationary, job: job); return }
        var figDX: CGFloat = 0, figDZ: CGFloat = 0
        let tt = CGFloat(t)
        var bodyX: CGFloat = 0, bodyZ: CGFloat = 0, lift: CGFloat = 0
        var headX: CGFloat = 0, headY: CGFloat = 0
        var aL = SCNVector3Zero, aR = SCNVector3Zero
        var lL: CGFloat = 0, lR: CGFloat = 0
        let phase = a.walked * 0.5 + CGFloat(a.variant)

        if a.dragged {
            lL = sin(tt * 9) * 0.5; lR = -sin(tt * 9) * 0.5
            aL.z = 2.4 + sin(tt * 12) * 0.3; aR.z = -2.4 - sin(tt * 12) * 0.3
            lift = 0.9
        } else if moving {
            let fast: CGFloat = a.mood == .panic ? 1.5 : 1
            let s = sin(phase * fast)
            lL = s * 0.75; lR = -s * 0.75
            aL.x = -s * 0.6; aR.x = s * 0.6
            lift = abs(sin(phase * fast)) * 0.07
            bodyX = a.mood == .panic ? 0.2 : 0.05
            if a.mood == .panic { aL.z = 2.0; aR.z = -2.0 }
            if a.carry != nil { aR.x = -1.1; aR.z = 0.1 }
        } else {
            switch a.mood {
            case .panic:
                aL.z = 2.5 + sin(tt * 18) * 0.4; aR.z = -2.5 - sin(tt * 18) * 0.4
                bodyZ = sin(tt * 22) * 0.07; lift = abs(sin(tt * 9)) * 0.12
            case .celebrate:
                lift = abs(sin(tt * 7)) * 0.6
                aL.z = 2.7; aR.z = -2.7; aL.x = sin(tt * 14) * 0.3; aR.x = -sin(tt * 14) * 0.3
                headX = -0.2
            case .tired:
                bodyX = 0.28; headX = 0.5; aL.x = 0.1; aR.x = 0.1
                bodyZ = sin(tt * 1.4) * 0.03
            case .sip:
                aR.x = -2.2 + sin(tt * 2) * 0.12; headX = -0.15
            case .dizzy:
                bodyZ = sin(tt * 6) * 0.22; headY = sin(tt * 8) * 0.5; aL.z = 0.8; aR.z = -0.8
            case .sleep:
                bodyX = 0.35; headX = 0.7; aL.x = 0.1; aR.x = 0.1
                lift = -0.02 + sin(tt * 1.2) * 0.02
            case .chat:
                headY = sin(tt * 2.5) * 0.2
                aR.x = -1.0 + sin(tt * 5) * 0.5; aL.x = -0.4 + sin(tt * 4 + 1) * 0.3
            case .dragged: break
            case .sad:
                bodyX = 0.3; headX = 0.65; aL.x = 0.15; aR.x = 0.15; bodyZ = sin(tt * 2) * 0.03
            case .sick: bodyX = 0.3
            case .card:
                aR.x = -3.1; aR.z = 0.1; aL.x = 0.1; headY = sin(tt * 1.5) * 0.2
            case .none:
                if a.phase == .working && stationary, let job {
                    let p = job.pose(t: tt, v: CGFloat(a.variant % 7))
                    bodyX = p.bodyX; bodyZ = p.bodyZ; lift = p.lift; headX = p.headX; headY = p.headY
                    aL = p.aL; aR = p.aR; lL = p.lL; lR = p.lR; figDX = p.dx; figDZ = p.dz
                } else if a.phase == .working && stationary { work(motion, tt, &bodyX, &aL, &aR, &headX, &headY, &lift); if motion == .kick { lR = sin(tt * 6) * 0.8; lL = -0.1 } }
                else if a.phase == .finishing { aL.z = 2.5; aR.z = -2.5 }
                else {
                    bodyZ = sin(tt * 1.6 + CGFloat(a.variant)) * 0.015
                    headY = sin(tt * 0.8 + CGFloat(a.variant)) * 0.35
                    aL.x = sin(tt * 1.6) * 0.05; aR.x = -sin(tt * 1.6) * 0.05
                    if a.isCaptain && a.busy { aR.x = -1.2 + sin(tt * 3) * 0.1 }
                }
            }
        }

        if a.approval, !moving, !a.dragged, a.mood == .none { aR.x = -3.0; aR.z = -0.15 + sin(tt * 6) * 0.2 }
        if theme == .prison { bodyX += CGFloat(a.ctx) * 0.28 }
        body.eulerAngles = SCNVector3(bodyX, 0, bodyZ)
        head.eulerAngles = SCNVector3(headX, headY, 0)
        armL.eulerAngles = aL
        armR.eulerAngles = aR
        legL.eulerAngles = SCNVector3(lL, 0, 0)
        legR.eulerAngles = SCNVector3(lR, 0, 0)
        root.childNode(withName: "figure", recursively: false)?.position = SCNVector3(figDX, lift, figDZ)
    }

    private func work(_ m: Motion, _ t: CGFloat, _ bodyX: inout CGFloat, _ aL: inout SCNVector3, _ aR: inout SCNVector3,
                      _ headX: inout CGFloat, _ headY: inout CGFloat, _ lift: inout CGFloat) {
        switch m {
        case .type:
            aL.x = -1.3 + sin(t * 17) * 0.12; aR.x = -1.3 + sin(t * 15 + 1) * 0.12
            headX = 0.12; headY = sin(t * 0.9) * 0.15
        case .hammer:
            aR.x = -1.6 + sin(t * 8) * 1.0; aL.x = -0.9; bodyX = 0.1 + sin(t * 8) * 0.06
        case .stir:
            aR.x = -1.35; aR.z = sin(t * 7) * 0.5; aL.x = -0.8; headX = 0.3
        case .bend:
            bodyX = 0.55 + sin(t * 3) * 0.15; aL.x = -0.8 + sin(t * 6) * 0.3; aR.x = -0.8 - sin(t * 6) * 0.3; headX = -0.2
        case .paint:
            aR.x = -2.6 + sin(t * 3.5) * 0.5; aR.z = sin(t * 3.5) * 0.3; aL.x = 0.2; headX = -0.15
        case .sweep:
            aL.x = -1.0; aR.x = -1.0; bodyX = 0.18
            bodyX += sin(t * 4) * 0.08; aL.z = sin(t * 4) * 0.35; aR.z = sin(t * 4) * 0.35
        case .kick:
            aL.x = 0.4 + sin(t * 6) * 0.3; aR.x = -0.4 - sin(t * 6) * 0.3; bodyX = 0.12
        case .scan:
            aR.x = -0.6; aL.x = -1.3 + sin(t * 12) * 0.1; headY = sin(t * 1.6) * 0.5; headX = 0.1
        }
    }
}
