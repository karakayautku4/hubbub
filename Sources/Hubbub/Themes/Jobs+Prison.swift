import SceneKit

extension Jobs {
    static var prisonCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Spoon tunnel", "🥄", spot: b[0], .dig, lines: ["Only 900 years to go.", "Day 412 with the spoon.", "Where did all this dirt go? Pockets.", "The spoon is mightier than the wall."]) { n in
                n.box(1.3, 0.05, 1.0, JP.m(0x6b5a45, 0.95), 0, 0.03, 1.1)
                for i in 0..<4 { n.ball(0.12, JP.m(0x7a6850, 0.95), CGFloat(i) * 0.3 - 0.45, 0.1, 1.6) }
                n.box(0.9, 0.7, 0.05, JP.m(0x2a2a2a), 0, 0.4, 1.9)
            },
            Job("Laundry duty", "🧺", spot: b[1], .wash, lines: ["Orange. Everything is orange.", "One sock found. Two missing.", "Soap is the real currency.", "Spin cycle: me."]) { n in
                JP.bucket(n, 0x6b7a8c, x: 0.5, z: 1.0, r: 0.35, h: 0.5)
                JP.pole(n, 0x8a8f99, x: -0.9, z: 1.2, h: 1.6); JP.pole(n, 0x8a8f99, x: 0.9, z: 1.2, h: 1.6)
                let c = n.box(1.7, 0.4, 0.04, JP.m(0xe87a1e), 0, 1.35, 1.2); JP.sway(c, 0.05, 1.1)
            },
            Job("Yard push-ups", "💪", spot: b[2], .pushups, lines: ["One... two... forty-seven!", "Gains behind bars.", "Who needs a gym?", "Count with me!"]) { n in
                n.box(1.4, 0.04, 0.8, JP.m(0x5a6a5a, 0.95), 0, 0.02, 0.3)
                JP.barrel(n, 0x8a8f99, x: 0.9, z: 0.8, r: 0.2, h: 0.4)
            },
            Job("Guard card game", "🃏", spot: b[3], .cards, lines: ["Full house! ...Not really.", "I fold. No, wait.", "Ace of spades in my sleeve.", "Winner takes the keys."]) { n in
                let t = JP.table(n, 0x5a4a3a, w: 1.0, d: 0.8, h: 0.8)
                for i in 0..<3 { t.box(0.2, 0.01, 0.3, JP.m(0xffffff), CGFloat(i) * 0.25 - 0.25, 0.86, 0).eulerAngles.y = CGFloat(i) * 0.3 }
                JP.pole(n, 0x444444, x: 0.9, z: 0.8, h: 0.6)
            },
            Job("Cafeteria stew", "🍲", spot: b[4], .stir, lines: ["Today's mystery: stew.", "Seconds? Nobody's asked.", "Stir clockwise. Or else.", "Chef's special: gray."]) { n in
                let t = JP.table(n, 0x8a8f99, w: 1.0, d: 0.8)
                t.cyl(0.38, 0.3, JP.m(0x2a2f38, 0.4, 0.7), 0, 1.0, 0)
                JP.bob(t.ball(0.09, JP.m(0xb6c28a), 0.1, 1.2, 0), 0.05, 0.9)
            },
            Job("Bar polishing", "🔔", spot: b[5], .polish, lines: ["Shiny bars. Very shiny.", "I can see my freedom in them.", "Rub, rub, rub.", "Spotless cell, spotless record."]) { n in
                for i in 0..<5 { JP.pole(n, 0x9aa0aa, x: CGFloat(i) * 0.32 - 0.64, z: 1.3, h: 1.8, r: 0.04) }
                n.box(1.5, 0.06, 0.1, JP.m(0x6b7a8c), 0, 1.8, 1.3)
            },
            Job("Warden's mop", "🧹", spot: b[6], .sweep, lines: ["Mop, bucket, repeat.", "Floor's wet, watch out.", "Clean floor, clean conscience.", "The mop is my best friend."]) { n in
                JP.bucket(n, 0x4a7ad9, x: 0.7, z: 0.9, r: 0.28, h: 0.4)
                JP.pole(n, 0xa5784a, x: -0.6, z: 1.0, h: 1.5)
                JP.blink(n.box(0.4, 0.02, 0.4, JP.m(0xf2d24a, 0.5), 0, 0.02, 1.4), 1)
            },
            Job("License plate stamping", "🔨", spot: b[7], .hammer, lines: ["Stamp, stamp, stamp!", "My number is 4-2-... what was it?", "Plates by the pound.", "Clang! Clang!"]) { n in
                let t = JP.table(n, 0x6b7a8c, w: 1.3, d: 0.7)
                for i in 0..<3 { t.box(0.3, 0.02, 0.15, JP.m(0xffd24a, 0.4, 0.4), CGFloat(i) * 0.35 - 0.35, 0.92, 0) }
            }
        ]
    }
}
