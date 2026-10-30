import SceneKit
import SwiftUI

/// Looping work animation a character plays at its job spot (see `JobAnimations.swift`).
enum JobAnim: CaseIterable {
    case type, hammer, stir, sweep, polish, juggle, stack, wrench, water, yoga, scan, dig, pushups, cards, dance
    case pump, paint, spell, read, tinker, aim, plot, smoke, flip, peel, taste, wash, chase, milk
}

/// One themed job: a persistent spot on the map with a prop, a looping animation and a pool of funny speech lines.
struct Job {
    let name: String
    let emoji: String
    /// Preferred position in logical map coordinates (320x180 space) when the job lives in the base arena.
    let spot: CGPoint
    let animation: JobAnim
    let lines: [String]
    /// Builds the prop at the character's feet. The character faces local +Z, so props usually sit around z = 1.
    let prop: (SCNNode) -> Void

    init(_ name: String, _ emoji: String, spot: CGPoint, _ animation: JobAnim, lines: [String], prop: @escaping (SCNNode) -> Void) {
        self.name = name; self.emoji = emoji; self.spot = spot; self.animation = animation; self.lines = lines; self.prop = prop
    }
}

/// One fixed place on the map where a job can happen. Positions never depend on how many agents there are,
/// so spots never shuffle when agents come and go; the arena just grows to cover the occupied ones.
struct JobSlot {
    let index: Int
    let pos: CGPoint
    let jobIndex: Int
}

enum Jobs {
    /// Eight hand-placed spots in the base arena that avoid the tool stations, the coffee corner and the captain post.
    static let base: [CGPoint] = [
        CGPoint(x: 28, y: 150), CGPoint(x: 84, y: 170), CGPoint(x: 176, y: 172), CGPoint(x: 236, y: 170),
        CGPoint(x: 180, y: 138), CGPoint(x: 24, y: 118), CGPoint(x: 296, y: 122), CGPoint(x: 300, y: 172)
    ]
    static let minJobs = 8
    static let maxAgents = 30
    static let slotCount = 40

    private static var catalogCache: [Theme: [Job]] = [:]
    private static var slotCache: [Theme: [JobSlot]] = [:]

    /// The themed jobs of a theme (never empty: unknown themes fall back to the space station).
    static func catalog(for theme: Theme) -> [Job] {
        if let c = catalogCache[theme] { return c }
        let list: [Job]
        switch theme {
        case .space: list = spaceCatalog
        case .kitchen: list = kitchenCatalog
        case .prison: list = prisonCatalog
        case .football: list = footballCatalog
        case .farm: list = farmCatalog
        case .impostor: list = impostorCatalog
        case .wizard: list = wizardCatalog
        case .galactic: list = galacticCatalog
        case .fellowship: list = fellowshipCatalog
        }
        let result = list.isEmpty ? spaceCatalog : list
        catalogCache[theme] = result
        return result
    }

    /// Fixed spot list: the catalog's own spots first, then a staggered lattice ordered by distance from the middle.
    static func slots(for theme: Theme) -> [JobSlot] {
        if let s = slotCache[theme] { return s }
        let jobs = catalog(for: theme)
        var reserved = theme.stations.map(\.pos)
        reserved += [theme.coffee, theme.post]
        // Big set pieces at the arena edge that props would otherwise poke into (logical coordinates).
        switch theme {
        case .space, .impostor: reserved.append(CGPoint(x: 2, y: 128))
        case .prison: reserved.append(CGPoint(x: 2, y: 114))
        case .farm: reserved.append(CGPoint(x: 306, y: 108))
        default: break
        }
        var pts: [CGPoint] = []
        // Catalog spots are shared between themes, so nudge any that land on this theme's stations.
        let nudges = [-72, -60, -48, -36, -24, 0, 24, 36, 48, 60, 72].flatMap { dx in [-48, -36, -24, -18, 0, 18, 24, 36, 48].map { CGPoint(x: CGFloat(dx), y: CGFloat($0)) } }
            .sorted { hypot($0.x, $0.y) < hypot($1.x, $1.y) }
        func free(_ p: CGPoint) -> Bool {
            !reserved.contains { hypot($0.x - p.x, $0.y - p.y) < 28 } && !pts.contains { hypot($0.x - p.x, $0.y - p.y) < 30 }
        }
        for j in jobs {
            let alt = nudges.lazy.map { CGPoint(x: j.spot.x + $0.x, y: j.spot.y + $0.y) }
                .first { free($0) && $0.x > 12 && $0.x < 308 && $0.y > 104 && $0.y < 194 }
            pts.append(free(j.spot) ? j.spot : alt ?? j.spot)
        }
        var extras: [CGPoint] = []
        let rows: [CGFloat] = [114, 136, 158, 180]
        for (r, y) in rows.enumerated() {
            for k in -10...10 {
                let x = 160 + 42 * CGFloat(k) + (r % 2 == 1 ? 21 : 0)
                if y < 118, x > 10, x < 310 { continue }
                let p = CGPoint(x: x, y: y)
                if !free(p) || pts.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 30 }) { continue }
                extras.append(p)
            }
        }
        extras.sort { hypot(($0.x - 160) * 0.85, $0.y - 152) < hypot(($1.x - 160) * 0.85, $1.y - 152) }
        pts += extras.prefix(max(0, slotCount - pts.count))
        let out = pts.enumerated().map { JobSlot(index: $0.offset, pos: $0.element, jobIndex: $0.offset % jobs.count) }
        slotCache[theme] = out
        return out
    }

    /// Stable, mostly collision-free slot for an agent: its id hash picks among the first few free slots,
    /// which keeps the occupied area compact while still varying the jobs between agents.
    static func pickSlot(id: String, taken: Set<Int>, theme: Theme) -> Int {
        let total = slots(for: theme).count
        let free = (0..<total).filter { !taken.contains($0) }
        guard !free.isEmpty else { return Sprite3D.stableHash(id) % total }
        let window = Array(free.prefix(4))
        return window[Sprite3D.stableHash(id) % window.count]
    }

    /// Yaw that makes a character at `pos` face the middle of the map (and its prop sit on that side).
    static func facing(atLogicalX x: CGFloat) -> CGFloat { Environments.wx(x) > 0 ? -.pi / 2 : .pi / 2 }

    /// Accent colours used for generic extension decor.
    static func accent(_ theme: Theme) -> (primary: UInt32, secondary: UInt32) {
        switch theme {
        case .space: (0x3fa9f5, 0x8a96a8)
        case .kitchen: (0xd9a066, 0xb9bec6)
        case .prison: (0xe0a43a, 0x8a8f96)
        case .football: (0xf2f2f2, 0x2f7d32)
        case .farm: (0xa7743c, 0xd8c08a)
        case .impostor: (0xe23a3a, 0x7b8498)
        case .wizard: (0x8d5cf6, 0x6b5a4a)
        case .galactic: (0x4fd1ff, 0x6a7286)
        case .fellowship: (0x5a9a3c, 0x7a5a38)
        }
    }

    /// World-space radius of the playable area covering the given slots (never smaller than the base arena).
    static func extent(of slotIndices: [Int], theme: Theme) -> (xHalf: CGFloat, zFar: CGFloat) {
        let all = slots(for: theme)
        var x: CGFloat = 14.6, z: CGFloat = 7.8
        for i in slotIndices where all.indices.contains(i) {
            x = max(x, abs(Environments.wx(all[i].pos.x)) + 1.8)
            z = max(z, Environments.wz(all[i].pos.y) + 1.2)
        }
        return (x, z)
    }
}

/// Small prop-building helpers shared by the per-theme job catalogs.
enum JP {
    static func m(_ hex: UInt32, _ r: CGFloat = 0.7, _ metal: CGFloat = 0) -> SCNMaterial { Gfx.mat(hex, r: r, m: metal) }
    static func glow(_ hex: UInt32) -> SCNMaterial { Gfx.mat(hex, r: 0.4, e: hex, eIntensity: 0.9) }

    /// A table with its top at 0.85 centred in front of the character.
    @discardableResult
    static func table(_ n: SCNNode, _ color: UInt32 = 0x8a6a45, w: CGFloat = 1.3, d: CGFloat = 0.8, z: CGFloat = 1.1, h: CGFloat = 0.85) -> SCNNode {
        let g = n.group("table", 0, 0, z)
        g.box(w, 0.1, d, m(color), 0, h, 0, round: 0.02)
        for sx: CGFloat in [-1, 1] { for sz: CGFloat in [-1, 1] { g.box(0.1, h, 0.1, m(color, 0.8), sx * (w / 2 - 0.1), h / 2, sz * (d / 2 - 0.1)) } }
        return g
    }

    static func spin(_ n: SCNNode, _ dur: Double = 2, axis: SCNVector3 = SCNVector3(0, 1, 0)) {
        n.runAction(.repeatForever(.rotate(by: .pi * 2, around: axis, duration: dur)))
    }

    static func bob(_ n: SCNNode, _ amp: CGFloat = 0.15, _ dur: Double = 0.8) {
        n.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: amp, z: 0, duration: dur), .moveBy(x: 0, y: -amp, z: 0, duration: dur)])))
    }

    static func sway(_ n: SCNNode, _ ang: CGFloat = 0.2, _ dur: Double = 0.7) {
        n.runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0, z: ang, duration: dur, usesShortestUnitArc: true),
                                              .rotateTo(x: 0, y: 0, z: -ang, duration: dur, usesShortestUnitArc: true)])))
    }

    static func pulse(_ n: SCNNode, _ amount: CGFloat = 0.12, _ dur: Double = 0.6) {
        n.runAction(.repeatForever(.sequence([.scale(to: 1 + amount, duration: dur), .scale(to: 1, duration: dur)])))
    }

    static func blink(_ n: SCNNode, _ dur: Double = 0.5) {
        n.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.25, duration: dur), .fadeOpacity(to: 1, duration: dur)])))
    }

    static func barrel(_ n: SCNNode, _ color: UInt32, x: CGFloat, z: CGFloat, r: CGFloat = 0.32, h: CGFloat = 0.7) {
        n.cyl(r, h, m(color, 0.6), x, h / 2, z)
        n.cyl(r + 0.02, 0.05, m(0x555a62, 0.4, 0.7), x, h * 0.3, z)
        n.cyl(r + 0.02, 0.05, m(0x555a62, 0.4, 0.7), x, h * 0.75, z)
    }

    static func crate(_ n: SCNNode, _ color: UInt32, x: CGFloat, z: CGFloat, s: CGFloat = 0.5, y: CGFloat = 0) {
        n.box(s, s, s, m(color, 0.8), x, y + s / 2, z, round: 0.02)
    }

    static func pole(_ n: SCNNode, _ color: UInt32, x: CGFloat, z: CGFloat, h: CGFloat, r: CGFloat = 0.05) {
        n.cyl(r, h, m(color, 0.5, 0.3), x, h / 2, z)
    }

    static func screen(_ n: SCNNode, _ hex: UInt32, w: CGFloat = 0.8, h: CGFloat = 0.5, x: CGFloat = 0, y: CGFloat = 1.3, z: CGFloat = 1.2) -> SCNNode {
        n.box(w + 0.1, h + 0.1, 0.08, m(0x20242c, 0.4, 0.4), x, y, z)
        return n.box(w, h, 0.03, glow(hex), x, y, z + 0.05)
    }

    static func bucket(_ n: SCNNode, _ color: UInt32, x: CGFloat, z: CGFloat, r: CGFloat = 0.22, h: CGFloat = 0.34) {
        n.cyl(r, h, m(color, 0.5, 0.2), x, h / 2, z)
        n.cyl(r * 0.85, 0.02, m(0x2a2f38), x, h, z)
    }
}
