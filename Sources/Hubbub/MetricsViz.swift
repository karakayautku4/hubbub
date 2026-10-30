import SceneKit
import AppKit

/// Per-rig state for the themed metric visuals (context gauge, nameplate, beacon, cost pops).
struct MetricsState {
    var built = false
    var theme: Theme = .defaultTheme
    var plateModel = "", plateName = "", plateEmoji = ""
    var plateAge = -1, plateBucket = -1, plateMedal = false
    var bucket = -1
    var fill: SCNNode?
    var ball: SCNNode?
    var beacon: SCNNode?
    var lastCost = 0, lastCompact = 0
    var approvalOn = false
    var plateFull: NSImage?, plateCompact: NSImage?
    var plateChipOn = true
    var lift: CGFloat = 0
}

enum MetricsFmt {
    static func age(_ s: Double) -> String {
        let m = Int(s / 60)
        if m < 1 { return "<1m" }
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h \(m % 60)m" }
        return "\(h / 24)d \(h % 24)h"
    }

    static func shortModel(_ m: String) -> String {
        var s = m.lowercased()
        for p in ["claude-", "github-copilot/"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        s = s.replacingOccurrences(of: "-preview", with: "").replacingOccurrences(of: "-latest", with: "")
        return s.count > 14 ? String(s.prefix(14)) : s
    }

    static func medal(_ t: Theme) -> String {
        switch t {
        case .kitchen: "⭐"
        case .space: "🚀"
        case .prison: "🏅"
        case .football: "🥇"
        case .farm: "🌾"
        case .impostor: impostorMedal
        case .wizard: wizardMedal
        case .galactic: galacticMedal
        case .fellowship: fellowshipMedal
        }
    }

    static func rank(_ age: Double) -> (Int, String) {
        switch age {
        case ..<3600: (1, "Apprentice")
        case ..<21600: (2, "Line cook")
        case ..<86400: (3, "Sous chef")
        case ..<259200: (4, "Chef")
        default: (5, "Master chef")
        }
    }

    static func color(_ f: Double) -> UInt32 {
        f < 0.6 ? 0x3ddc84 : (f < 0.85 ? 0xffb020 : 0xff4d3d)
    }
}

extension Gfx {
    /// Name pill with model chip, age text and a thin context bar (green → amber → red).
    static func nameplate(_ text: String, chip: String?, tail: String?, frac: Double) -> NSImage {
        let font = NSFont.systemFont(ofSize: 23, weight: .semibold)
        let cfont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let tfont = NSFont.systemFont(ofSize: 17, weight: .medium)
        let a1: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let a2: [NSAttributedString.Key: Any] = [.font: cfont, .foregroundColor: NSColor.white]
        let a3: [NSAttributedString.Key: Any] = [.font: tfont, .foregroundColor: Gfx.color(0xffd98a)]
        let ts = (text as NSString).size(withAttributes: a1)
        let cs = chip.map { ($0 as NSString).size(withAttributes: a2) } ?? .zero
        let ds = tail.map { ($0 as NSString).size(withAttributes: a3) } ?? .zero
        let chipW = chip == nil ? 0 : cs.width + 14 + 6
        let tailW = tail == nil ? 0 : ds.width + 8
        let w = ceil(ts.width + chipW + tailW) + 22
        let h = ceil(ts.height) + 18
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
            NSColor.black.withAlphaComponent(Gfx.scrimAlpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
            var x: CGFloat = 11
            (text as NSString).draw(at: NSPoint(x: x, y: 11), withAttributes: a1)
            x += ts.width
            if let chip {
                x += 6
                let cr = NSRect(x: x, y: 12, width: cs.width + 14, height: cs.height + 2)
                NSColor.white.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: cr, xRadius: cr.height / 2, yRadius: cr.height / 2).fill()
                (chip as NSString).draw(at: NSPoint(x: x + 7, y: 13), withAttributes: a2)
                x += cs.width + 14
            }
            if let tail { (tail as NSString).draw(at: NSPoint(x: x + 8, y: 12), withAttributes: a3) }
            let bar = NSRect(x: 12, y: 4, width: r.width - 24, height: 4)
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            Gfx.color(MetricsFmt.color(frac)).setFill()
            NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: max(4, bar.width * CGFloat(frac)), height: 4), xRadius: 2, yRadius: 2).fill()
            return true
        }
    }

    static func sign(_ title: String, _ sub: String, accent: UInt32, tally: Int = 0) -> NSImage {
        let a1: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white]
        let a2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: Gfx.color(0xe6e6e6)]
        let t1 = (title as NSString).size(withAttributes: a1), t2 = (sub as NSString).size(withAttributes: a2)
        let groups = (tally + 4) / 5
        let tallyW = CGFloat(min(groups, 6)) * 46
        let w = max(t1.width, t2.width, tallyW) + 36
        let h = t1.height + t2.height + 24 + (tally > 0 ? 34 : 0)
        return NSImage(size: NSSize(width: ceil(w), height: ceil(h)), flipped: false) { r in
            NSColor.black.withAlphaComponent(max(0.7, Gfx.scrimAlpha)).setFill()
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
            p.fill()
            Gfx.color(accent).setStroke()
            p.lineWidth = 3
            p.stroke()
            (title as NSString).draw(at: NSPoint(x: 18, y: r.height - t1.height - 8), withAttributes: a1)
            (sub as NSString).draw(at: NSPoint(x: 18, y: r.height - t1.height - t2.height - 10), withAttributes: a2)
            if tally > 0 {
                NSColor.white.setStroke()
                let ln = NSBezierPath()
                ln.lineWidth = 3
                ln.lineCapStyle = .round
                var left = min(tally, 30)
                var gx: CGFloat = 20
                while left > 0 {
                    let n = min(left, 5)
                    for i in 0..<min(n, 4) {
                        ln.move(to: NSPoint(x: gx + CGFloat(i) * 8, y: 8)); ln.line(to: NSPoint(x: gx + CGFloat(i) * 8, y: 28))
                    }
                    if n == 5 { ln.move(to: NSPoint(x: gx - 4, y: 10)); ln.line(to: NSPoint(x: gx + 30, y: 26)) }
                    left -= n
                    gx += 46
                }
                ln.stroke()
            }
            return true
        }
    }
}

extension Rig {
    func tinted(_ hex: UInt32, e: Bool = false) -> SCNMaterial { Gfx.mat(hex, r: 0.4, e: e ? hex : nil) }

    func bottomAnchored(_ n: SCNNode, height: CGFloat) {
        n.pivot = SCNMatrix4MakeTranslation(0, -height / 2, 0)
    }

    private func buildMetrics(_ theme: Theme) {
        mv.built = true
        mv.theme = theme
        guard let figure = root.childNode(withName: "figure", recursively: false) else { return }
        let metal = Gfx.mat(0x9aa7b5, r: 0.35, m: 0.7)
        switch theme {
        case .kitchen:
            let g = figure.group("gauge", 0.85, 1.0, 0.25)
            g.cyl(0.26, 0.04, Gfx.mat(0xffffff, r: 0.2), 0, 0, 0)
            let pile = SCNCylinder(radius: 0.17, height: 0.5)
            let f = g.add(pile, tinted(0x3ddc84), at: SCNVector3(0, 0.02, 0))
            bottomAnchored(f, height: 0.5)
            mv.fill = f
        case .space:
            let g = body.group("gauge", 0.3, 0.42, -0.32)
            g.cyl(0.16, 0.76, metal, 0, 0, 0)
            g.ball(0.16, metal, 0, 0.38, 0)
            let f = g.add(SCNCylinder(radius: 0.17, height: 0.64), tinted(0x3ddc84, e: true), at: SCNVector3(0, -0.32, 0), shadow: false)
            bottomAnchored(f, height: 0.64)
            mv.fill = f
        case .prison:
            let ballNode = figure.group("ball", 0.6, 0.2, 0.45)
            ballNode.ball(1, Gfx.mat(0x2a2d33, r: 0.35, m: 0.8), 0, 0, 0)
            mv.ball = ballNode
            let chain = Gfx.mat(0x555a63, r: 0.4, m: 0.8)
            for i in 1...3 { figure.ball(0.05, chain, 0.16 + CGFloat(i) * 0.09, 0.08, 0.08 + CGFloat(i) * 0.11) }
        case .football:
            let g = figure.group("gauge", 0.78, 1.05, 0)
            let h: CGFloat = 1.0, w: CGFloat = 0.12
            g.box(w + 0.05, h + 0.05, 0.1, Gfx.mat(0x1b2030, r: 0.5), 0, 0, -0.03)
            let f = g.add(SCNBox(width: w, height: h, length: 0.06, chamferRadius: 0), tinted(0x3ddc84, e: true), at: SCNVector3(0, -h / 2, 0), shadow: false)
            f.position.z = 0.03
            bottomAnchored(f, height: h)
            mv.fill = f
        case .impostor: impostorGauge(figure, metal: metal)
        case .wizard: wizardGauge(figure, metal: metal)
        case .galactic: galacticGauge(figure, metal: metal)
        case .fellowship: fellowshipGauge(figure, metal: metal)
        default: break
        }
        let beacon = figure.group("beacon", 0.55, labelY - 0.7, 0)
        let gold = Gfx.mat(0xffd54a, r: 0.25, m: 0.6, e: 0xffa000)
        switch theme {
        case .kitchen, .farm:
            beacon.ball(0.14, gold, 0, 0.08, 0)
            beacon.cyl(0.2, 0.03, gold, 0, -0.03, 0)
        case .space:
            beacon.cyl(0.04, 0.2, metal, 0, -0.1, 0)
            beacon.ball(0.13, tinted(0xff8a2a, e: true), 0, 0.05, 0)
        case .prison:
            beacon.cyl(0.1, 0.18, tinted(0xff3b30, e: true), 0, 0, 0)
            beacon.cyl(0.13, 0.04, Gfx.mat(0x333333), 0, -0.1, 0)
        case .football:
            beacon.cyl(0.02, 0.5, Gfx.mat(0xf0f0f0), 0, 0, 0)
            beacon.box(0.3, 0.2, 0.02, tinted(0xffd400, e: true), 0.16, 0.18, 0)
        case .impostor: impostorBeacon(beacon, metal: metal)
        case .wizard: wizardBeacon(beacon, metal: metal)
        case .galactic: galacticBeacon(beacon, metal: metal)
        case .fellowship: fellowshipBeacon(beacon, metal: metal)
        }
        beacon.isHidden = true
        mv.beacon = beacon
    }

    /// Applies context, age, model, cost, approval and success visuals; only touches the scene when a value changed.
    func setMetrics(_ a: Actor, theme: Theme, emoji: String, t: Double) {
        if !mv.built { buildMetrics(theme) }
        let bucket = Int((a.ctx * 20).rounded())
        let showAge = a.isCaptain || theme == .farm
        let ageMin = showAge ? Int(a.ageSec / 60) : -1
        let medal = a.calls >= 5 && a.success > 0.95
        if bucket != mv.plateBucket || ageMin != mv.plateAge || medal != mv.plateMedal || a.name != mv.plateName || a.model != mv.plateModel || emoji != mv.plateEmoji {
            mv.plateBucket = bucket; mv.plateAge = ageMin; mv.plateMedal = medal
            mv.plateName = a.name; mv.plateModel = a.model; mv.plateEmoji = emoji
            var text = emoji.isEmpty ? a.name : "\(emoji) \(a.name)"
            if medal { text += " " + MetricsFmt.medal(theme) }
            var tail: String?
            if showAge, a.ageSec >= 60 {
                tail = MetricsFmt.age(a.ageSec)
                if theme == .kitchen, a.isCaptain { tail = String(repeating: "★", count: MetricsFmt.rank(a.ageSec).0) + " " + tail! }
            }
            let chip = a.model.isEmpty ? nil : MetricsFmt.shortModel(a.model)
            let frac = Double(bucket) / 20
            mv.plateFull = Gfx.nameplate(text, chip: chip, tail: tail, frac: frac)
            mv.plateCompact = chip == nil ? mv.plateFull : Gfx.nameplate(text, chip: nil, tail: tail, frac: frac)
            if nameNode == nil {
                let n = Gfx.billboard(mv.plateFull!)
                n.position = SCNVector3(0, labelY, 0)
                root.addChildNode(n)
                nameNode = n
            }
            applyPlate()
        }
        if bucket != mv.bucket {
            mv.bucket = bucket
            applyGauge(Double(bucket) / 20, theme)
        }
        if a.costEvents != mv.lastCost {
            mv.lastCost = a.costEvents
            popCost(a.costDelta)
        }
        if a.compactEvents != mv.lastCompact {
            mv.lastCompact = a.compactEvents
            if let fig = root.childNode(withName: "figure", recursively: false) {
                let base = fig.scale.x
                fig.runAction(.sequence([.scale(to: base * 0.8, duration: 0.15), .scale(to: base, duration: 0.3)]), forKey: "compact")
            }
        }
        if a.approval != mv.approvalOn {
            mv.approvalOn = a.approval
            mv.beacon?.isHidden = !a.approval
            mv.beacon?.removeAllActions()
            if a.approval {
                mv.beacon?.runAction(.repeatForever(.sequence([.scale(to: 1.35, duration: 0.35), .scale(to: 1, duration: 0.35)])))
            }
        }
    }

    /// Swaps the nameplate between the full pill (with model tag) and the compact one without re-creating the node.
    func setPlateChip(_ on: Bool) {
        guard on != mv.plateChipOn else { return }
        mv.plateChipOn = on
        applyPlate()
    }

    private func applyPlate() {
        guard let img = mv.plateChipOn ? mv.plateFull : mv.plateCompact, let plane = nameNode?.geometry as? SCNPlane else { return }
        plane.width = img.size.width * 0.022
        plane.height = img.size.height * 0.022
        plane.firstMaterial?.diffuse.contents = img
        plateWidth = plane.width
    }

    private func applyGauge(_ f: Double, _ theme: Theme) {
        let col = Gfx.color(MetricsFmt.color(f))
        if let fill = mv.fill {
            let remaining = theme == .kitchen ? f : 1 - f
            fill.scale = SCNVector3(1, max(0.03, CGFloat(remaining)), 1)
            if let m = fill.geometry?.firstMaterial {
                m.diffuse.contents = col
                if m.emission.contents != nil { m.emission.contents = col }
            }
        }
        if let ball = mv.ball {
            let r = 0.1 + 0.2 * CGFloat(f)
            ball.scale = SCNVector3(r, r, r)
            ball.position.y = r
        }
        if isSheep {
            let k = CGFloat(f)
            body.scale = SCNVector3(1 + 0.22 * k, 1 + 0.08 * k, 1 + 0.22 * k)
        }
    }

    private func popCost(_ delta: Double) {
        let s = delta < 0.05 ? "+<0.1 credits" : String(format: delta >= 10 ? "+%.0f credits" : "+%.1f credits", delta)
        let img = Gfx.label(s, size: 16, fg: Gfx.color(0xffe08a))
        let n = Gfx.billboard(img, unitsPerPoint: 0.018)
        n.position = SCNVector3(0, labelY + 0.55, 0)
        root.addChildNode(n)
        n.runAction(.sequence([.group([.moveBy(x: 0, y: 0.9, z: 0, duration: 1.8), .sequence([.wait(duration: 1.0), .fadeOut(duration: 0.8)])]), .removeFromParentNode()]))
    }

    /// Slides the label and bubble sideways by `world` units (in the unscaled rig space) along the world x axis; the rig root is yawed.
    func shiftLabels(world s: CGFloat, yaw: CGFloat) {
        let lx = s * cos(yaw), lz = s * sin(yaw)
        nameNode?.position.x = lx; nameNode?.position.z = lz
        bubbleNode?.position.x = lx; bubbleNode?.position.z = lz
    }
}

/// Themed session-age sign shown in the room (tally marks, mission day, match clock, rank, wool, uptime).
@MainActor
final class RoomSign {
    let node = SCNNode()
    private var key = ""

    func update(theme: Theme, custom: CustomTheme? = nil, age: Double?, jersey: Int) {
        guard let age else { node.isHidden = true; key = ""; return }
        let min = Int(age / 60)
        let k = "\(theme)-\(custom?.fingerprint ?? "")-\(min)"
        guard k != key else { return }
        key = k
        let days = Int(age / 86400) + 1
        let txt = MetricsFmt.age(age)
        let img: NSImage
        if let c = custom, c.baseTheme == theme, c.ageSign != nil {
            let a = c.ageSign
            img = Gfx.sign(c.expand(a?.title ?? "Day {days}", age: age, days: days), c.expand(a?.subtitle ?? "{age}", age: age, days: days),
                           accent: c.color(c.palette?.accent) ?? 0xffffff, tally: 0)
        } else {
        switch theme {
        case .kitchen:
            let (n, name) = MetricsFmt.rank(age)
            img = Gfx.sign("👨‍🍳 \(name)", String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n) + "  \(txt)", accent: 0xffd54a)
        case .prison: img = Gfx.sign("Day \(days)", "served \(txt)", accent: 0xd4af37, tally: days)
        case .space: img = Gfx.sign("🚀 Mission day \(days)", "T+ \(txt)", accent: 0x3fa9f5)
        case .football:
            let m = min < 90 ? "\(min)'" : "90+'"
            img = Gfx.sign("#\(jersey)  ⏱ \(m)", "match clock · \(txt)", accent: 0xffd400)
        case .farm:
            let (lv, name): (Int, String) = age < 3600 ? (1, "stubble") : (age < 21600 ? (2, "short") : (age < 86400 ? (3, "fluffy") : (age < 259200 ? (4, "woolly") : (5, "very woolly"))))
            img = Gfx.sign("🐑 Wool: \(name)", String(repeating: "●", count: lv) + String(repeating: "○", count: 5 - lv) + "  \(txt)", accent: 0xf4f1e8)
        case .impostor: img = Self.impostorAgeSign(age: age, days: days, minutes: min, jersey: jersey, txt: txt)
        case .wizard: img = Self.wizardAgeSign(age: age, days: days, minutes: min, jersey: jersey, txt: txt)
        case .galactic: img = Self.galacticAgeSign(age: age, days: days, minutes: min, jersey: jersey, txt: txt)
        case .fellowship: img = Self.fellowshipAgeSign(age: age, days: days, minutes: min, jersey: jersey, txt: txt)
        }
        }
        if let plane = node.geometry as? SCNPlane, let m = plane.firstMaterial {
            plane.width = img.size.width * 0.02
            plane.height = img.size.height * 0.02
            m.diffuse.contents = img
        } else {
            let b = Gfx.billboard(img, unitsPerPoint: 0.02)
            node.geometry = b.geometry
            node.constraints = b.constraints
            node.renderingOrder = b.renderingOrder
        }
        node.isHidden = false
    }
}
