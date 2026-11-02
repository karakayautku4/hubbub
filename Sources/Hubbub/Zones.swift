import SceneKit
import AppKit

/// Themed rooms: the map is split into three zones (left / middle / right). Each zone tints the floor, gets short partition walls at
/// its borders and a hanging sign that shows how many agents are working there right now.
struct ZoneDef {
    let name: String
    let emoji: String
    let accent: UInt32
}

enum Zones {
    /// World-space x of the two borders between the three zones.
    static let cuts: [CGFloat] = [-4.4, 9.0]

    static func index(atLogicalX x: CGFloat) -> Int {
        let w = Environments.wx(x)
        return w < cuts[0] ? 0 : (w < cuts[1] ? 1 : 2)
    }

    static func defs(for theme: Theme) -> [ZoneDef] {
        switch theme {
        case .office: [ZoneDef(name: "Dev pod", emoji: "💻", accent: 0x4a8cff), ZoneDef(name: "War room", emoji: "🚀", accent: 0xff7a59), ZoneDef(name: "Support & planning", emoji: "🎧", accent: 0x5ad19a)]
        case .kitchen: [ZoneDef(name: "Stove line", emoji: "🔥", accent: 0xff7a3c), ZoneDef(name: "Prep & pantry", emoji: "🥔", accent: 0xe0b34a), ZoneDef(name: "Dish pit & pastry", emoji: "🧽", accent: 0x4fb8e0)]
        case .space: [ZoneDef(name: "Life support", emoji: "🌱", accent: 0x4fd18a), ZoneDef(name: "Observation deck", emoji: "🔭", accent: 0x5a8cff), ZoneDef(name: "Cargo bay", emoji: "📦", accent: 0xffb347)]
        case .prison: [ZoneDef(name: "Cell block", emoji: "🔒", accent: 0x8a96a8), ZoneDef(name: "Yard & mess hall", emoji: "🏋️", accent: 0xe0a43a), ZoneDef(name: "Workshop", emoji: "🔨", accent: 0xe0603a)]
        case .football: [ZoneDef(name: "Training pitch", emoji: "⚽", accent: 0x4fd15a), ZoneDef(name: "Stadium floor", emoji: "🏟️", accent: 0xf2f2f2), ZoneDef(name: "Locker room", emoji: "👕", accent: 0x5a8cff)]
        case .farm: [ZoneDef(name: "Barnyard", emoji: "🐔", accent: 0xe0603a), ZoneDef(name: "Hayfield", emoji: "🌾", accent: 0xe0c04a), ZoneDef(name: "Pumpkin patch", emoji: "🎃", accent: 0xff8a2a)]
        case .impostor: [ZoneDef(name: "Electrical", emoji: "⚡", accent: 0xffd23a), ZoneDef(name: "Admin", emoji: "🗂️", accent: 0x5a8cff), ZoneDef(name: "Navigation", emoji: "🧭", accent: 0x4fd1d9)]
        case .wizard: [ZoneDef(name: "Alchemy lab", emoji: "🧪", accent: 0x4fd18a), ZoneDef(name: "Divination hall", emoji: "🔮", accent: 0xa070ff), ZoneDef(name: "Library", emoji: "📚", accent: 0xe0a43a)]
        case .galactic: [ZoneDef(name: "Droid bay", emoji: "🤖", accent: 0x4fd1ff), ZoneDef(name: "Hangar", emoji: "🚀", accent: 0xff7a59), ZoneDef(name: "Power deck", emoji: "🔋", accent: 0xffd23a)]
        case .fellowship: [ZoneDef(name: "Forge", emoji: "⚒️", accent: 0xe0603a), ZoneDef(name: "Hall of maps", emoji: "🗺️", accent: 0xd9b36a), ZoneDef(name: "Garden", emoji: "🌿", accent: 0x5aba4a)]
        }
    }
}

@MainActor
final class ZoneLayer {
    let root = SCNNode()
    private var signs: [SCNNode] = []
    private var lastText: [String] = []
    private var defs: [ZoneDef] = []

    func build(theme: Theme) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        signs = []
        lastText = []
        defs = Zones.defs(for: theme)
        let edges: [CGFloat] = [-60, Zones.cuts[0], Zones.cuts[1], 60]
        for (i, d) in defs.enumerated() {
            let x0 = edges[i], x1 = edges[i + 1]
            let tint = SCNNode(geometry: SCNPlane(width: x1 - x0, height: 11))
            let m = Gfx.mat(d.accent, r: 1)
            m.transparency = 0.1
            m.writesToDepthBuffer = false
            tint.geometry?.firstMaterial = m
            tint.eulerAngles.x = -.pi / 2
            tint.position = SCNVector3((x0 + x1) / 2, 0.008, 6.5)
            tint.renderingOrder = -1
            root.addChildNode(tint)

            let center = i == 0 ? min(x1 - 4.5, -8.5) : (i == 2 ? max(x0 + 4.5, 12) : (x0 + x1) / 2)
            let sign = SCNNode(geometry: SCNPlane(width: 3, height: 0.85))
            let sm = SCNMaterial()
            sm.lightingModel = .constant
            sm.isDoubleSided = true
            sign.geometry?.firstMaterial = sm
            sign.position = SCNVector3(center, 5.2, -1.0)
            sign.constraints = [{ let c = SCNBillboardConstraint(); c.freeAxes = .Y; return c }()]
            sign.opacity = 0.92
            sign.renderingOrder = -1
            root.addChildNode(sign)
            signs.append(sign)
            lastText.append("")
        }
        // Short partition walls where two zones meet, with a glowing rail on top.
        for (k, x) in Zones.cuts.enumerated() {
            let c = defs[k].accent
            let wall = root.group("partition", x, 0, 2.2)
            wall.box(0.14, 1.4, 2.4, Gfx.mat(0xdfe5ee, r: 0.5), 0, 0.7, 0, round: 0.03)
            wall.box(0.2, 0.1, 2.5, Gfx.mat(c, r: 0.4, e: c, eIntensity: 0.6), 0, 1.42, 0)
        }
        update(busy: [0, 0, 0], total: [0, 0, 0])
    }

    /// Refreshes the sign text only when it changed (the label texture is cached by Gfx).
    func update(busy: [Int], total: [Int]) {
        for (i, d) in defs.enumerated() where i < signs.count {
            let status = total[i] == 0 ? "" : " · \(busy[i])/\(total[i]) working"
            let text = "\(d.emoji) \(d.name)\(status)"
            guard text != lastText[i] else { continue }
            lastText[i] = text
            let img = Gfx.label(text, size: 40, fg: .white, bg: NSColor(white: 0.08, alpha: 0.72))
            signs[i].geometry?.firstMaterial?.diffuse.contents = img
            let aspect = img.size.width / max(img.size.height, 1)
            (signs[i].geometry as? SCNPlane)?.width = min(0.85 * aspect, 3.8)
        }
    }
}
