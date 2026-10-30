import SceneKit

extension Jobs {
    static var fellowshipCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Forging", "⚒️", spot: b[0], .hammer, lines: ["Clang! Clang! Clang!", "Hot metal, cool head.", "Another horseshoe. Another day.", "Sparks make everything better."]) { n in
                n.box(0.7, 0.4, 0.4, JP.m(0x3a3f48, 0.5, 0.7), 0, 0.5, 1.2)
                n.box(0.9, 0.1, 0.5, JP.m(0x2a2f38, 0.5, 0.7), 0, 0.75, 1.2)
                JP.blink(n.ball(0.15, JP.glow(0xff8a30), -0.6, 0.35, 1.0), 0.3)
            },
            Job("Campfire stew", "🍲", spot: b[1], .stir, lines: ["Stew is the best meal of the day.", "Needs more... everything.", "Don't tell the cook it's soup.", "Smells like a good day."]) { n in
                for i in 0..<5 { n.cyl(0.05, 0.4, JP.m(0x5a3a1a), CGFloat(i) * 0.15 - 0.3, 0.1, 1.1).eulerAngles.z = 1.2 }
                let f = n.ball(0.2, JP.glow(0xff8a30), 0, 0.35, 1.1); f.scale = SCNVector3(1, 1.5, 1); JP.pulse(f, 0.25, 0.25)
                n.cyl(0.3, 0.3, JP.m(0x2a2f38, 0.4, 0.7), 0, 0.7, 1.1)
            },
            Job("Map reading", "🗺️", spot: b[2], .read, lines: ["Is that a mountain or a stain?", "We are exactly here. Probably.", "The road goes on... where?", "Upside down helps."]) { n in
                let t = JP.table(n, 0x7a5a3a, w: 1.1, d: 0.8)
                let m = t.box(0.8, 0.02, 0.6, JP.m(0xf0e0b0, 0.95), 0, 0.92, 0); m.eulerAngles.y = 0.1
            },
            Job("Hilltop pipe", "🪈", spot: b[3], .smoke, lines: ["A fine view, a fine pipe.", "Puff... puff... pondering.", "The leaf is strong today.", "Nothing like a quiet hill."]) { n in
                n.box(1.2, 0.3, 0.9, JP.m(0x5a7a3a, 0.95), 0, 0.15, 1.1, round: 0.08)
                JP.bob(n.ball(0.08, JP.m(0xe8e8e8, 0.9), 0.4, 0.8, 1.0), 0.3, 1.2)
                JP.bob(n.ball(0.06, JP.m(0xe8e8e8, 0.9), 0.3, 0.7, 1.0), 0.3, 0.9)
            },
            Job("Charm polishing", "🪙", spot: b[4], .polish, lines: ["Shiny. Too shiny?", "Mine now... I mean, shine.", "It looks gold from this side.", "I keep dropping it. By choice."]) { n in
                let t = JP.table(n, 0x5a4a3a, w: 0.8, d: 0.6)
                let r = t.cyl(0.14, 0.04, JP.m(0xffd24a, 0.2, 0.9), 0, 1.0, 0); r.eulerAngles.x = .pi / 2
                JP.blink(t.ball(0.18, JP.glow(0xffd24a), 0, 1.0, 0), 0.9)
            },
            Job("Sword sharpening", "🗡️", spot: b[5], .polish, lines: ["Shing! Shing!", "Sharp enough to slice bread.", "Mind the toes.", "Sparks! Nice."]) { n in
                n.cyl(0.35, 0.15, JP.m(0x8a8f99, 0.7, 0.4), 0, 0.5, 1.1).eulerAngles.z = .pi / 2
                JP.spin(n.cyl(0.35, 0.12, JP.m(0x6b7a8c, 0.7, 0.4), 0, 0.7, 1.1), 1.2, axis: SCNVector3(0, 0, 1))
                JP.pole(n, 0x5a3a1a, x: -0.5, z: 1.1, h: 0.6)
            },
            Job("Herb gardening", "🌿", spot: b[6], .water, lines: ["Sage advice from sage.", "These are weeds. Or herbs. Ah well.", "Water, wait, repeat.", "Mint, fresh."]) { n in
                for i in 0..<4 { n.ball(0.15, JP.m(0x4fa04f), CGFloat(i) * 0.35 - 0.5, 0.2, 1.2) }
                n.box(1.5, 0.15, 0.6, JP.m(0x5a3a1a, 0.95), 0, 0.08, 1.2)
                JP.bucket(n, 0x4aa3d9, x: 1.0, z: 0.7)
            },
            Job("Harp tuning", "🎶", spot: b[7], .stack, lines: ["Plink. Plonk. Plink.", "That string is a rebel.", "Do-re-mi... fa?", "Tune, tune, tune."]) { n in
                n.box(0.08, 1.3, 0.08, JP.m(0xa5784a), 0, 0.7, 1.2)
                n.box(0.6, 0.06, 0.06, JP.m(0xa5784a), 0.3, 1.3, 1.2)
                for i in 0..<4 { JP.sway(n.box(0.01, 1.0 - CGFloat(i) * 0.15, 0.01, JP.m(0xf0e0b0), 0.1 + CGFloat(i) * 0.12, 0.75, 1.2), 0.02, 0.2 + Double(i) * 0.05) }
            }
        ]
    }
}
