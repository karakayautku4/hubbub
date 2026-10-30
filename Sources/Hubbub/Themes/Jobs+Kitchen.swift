import SceneKit

extension Jobs {
    static var kitchenCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Pancake flipping", "🥞", spot: b[0], .flip, lines: ["Higher! Stick it to the ceiling!", "Pancake #212 is now a ceiling lamp.", "Flip, flop, splat.", "Gravity is just a suggestion."]) { n in
                let t = JP.table(n, 0x8a8f99, w: 1.0, d: 0.7)
                t.cyl(0.3, 0.05, JP.m(0x2a2f38, 0.4, 0.6), 0, 0.95, 0)
                let p = n.cyl(0.2, 0.05, JP.m(0xd9a35f), 0, 2.1, 1.1)
                JP.bob(p, 0.5, 0.7); JP.spin(p, 1.2, axis: SCNVector3(1, 0, 0))
            },
            Job("Potato peeling", "🥔", spot: b[1], .peel, lines: ["Peel, peel, peel... 4,000 to go.", "This potato is mostly eyes.", "Never cry over a peeler.", "Spud-tacular."]) { n in
                JP.bucket(n, 0xb98b52, x: 0.5, z: 1.0, r: 0.3, h: 0.5)
                for i in 0..<5 { n.ball(0.12, JP.m(0xc9a36a), CGFloat(i % 3) * 0.2 + 0.4, 0.55, 0.9 + CGFloat(i / 3) * 0.2) }
                JP.bucket(n, 0x6b7a8c, x: -0.7, z: 1.0, r: 0.28, h: 0.45)
            },
            Job("Soup tasting", "🥣", spot: b[2], .taste, lines: ["Needs... more soup.", "Mmm. Needs salt. Or a hug.", "Is it supposed to blink?", "Quality control. Very serious."]) { n in
                let t = JP.table(n, 0x8a8f99, w: 0.9, d: 0.7)
                t.cyl(0.35, 0.3, JP.m(0xb0b6c0, 0.3, 0.8), 0, 1.05, 0)
                JP.bob(t.ball(0.08, JP.m(0xffffff), 0.1, 1.3, 0), 0.2, 0.9)
            },
            Job("Mountain of dishes", "🍽️", spot: b[3], .wash, lines: ["The pile is winning.", "Who uses 80 spoons?!", "Bubbles! So many bubbles.", "Clean one, two more appear."]) { n in
                let t = JP.table(n, 0x8a8f99, w: 1.4, d: 0.8)
                for i in 0..<6 { t.cyl(0.3 - CGFloat(i) * 0.02, 0.06, JP.m(i % 2 == 0 ? 0xf2f2f2 : 0xd9e6f2), 0.3, 0.95 + CGFloat(i) * 0.08, 0) }
                JP.bob(t.ball(0.1, JP.m(0xe6f6ff, 0.2), -0.35, 1.0, 0), 0.15, 1.1)
                JP.bob(t.ball(0.07, JP.m(0xe6f6ff, 0.2), -0.5, 1.05, 0.1), 0.2, 0.8)
            },
            Job("Dough kneading", "🍞", spot: b[4], .stir, lines: ["Knead it, love it, bake it.", "The dough is rising. Unionizing, perhaps.", "Flour everywhere. Worth it.", "Punch, fold, repeat."]) { n in
                let t = JP.table(n, 0xc9a36a, w: 1.3, d: 0.8)
                let d = t.ball(0.28, JP.m(0xf2e2c4), 0, 1.05, 0); d.scale = SCNVector3(1.2, 0.6, 1)
                JP.pulse(d, 0.1, 0.8)
            },
            Job("Onion chopping", "🧅", spot: b[5], .hammer, lines: ["I'm not crying, you're crying.", "Chop chop chop!", "Tears. So many tears.", "Fastest knife in the kitchen."]) { n in
                let t = JP.table(n, 0xc9a36a, w: 1.2, d: 0.7)
                t.box(0.7, 0.05, 0.4, JP.m(0xe0c08a), 0, 0.95, 0)
                for i in 0..<3 { t.ball(0.1, JP.m(0xd9b3e0), CGFloat(i) * 0.2 - 0.2, 1.05, 0) }
            },
            Job("Spice sorting", "🌶️", spot: b[6], .stack, lines: ["Cumin, cumin, ...not cinnamon.", "Alphabetical? By color? By mood.", "Achoo!", "One pinch is never one pinch."]) { n in
                let t = JP.table(n, 0x7a5a3a, w: 1.5, d: 0.6)
                for i in 0..<6 { t.cyl(0.07, 0.22, JP.m([0xd94a3a, 0xe0b030, 0x4aa04a, 0x8a5a3a, 0xf0e0c0, 0xb03a8a][i], 0.5), CGFloat(i) * 0.22 - 0.55, 1.0, 0) }
            },
            Job("Cake decorating", "🎂", spot: b[7], .paint, lines: ["More sprinkles. Always more.", "A cake with a cherry on top and a hat.", "It's art. Edible art.", "Frosting stays on the cake. Mostly."]) { n in
                let t = JP.table(n, 0xc9a36a, w: 1.1, d: 0.8)
                t.cyl(0.32, 0.2, JP.m(0xf4c6d9), 0, 1.0, 0)
                t.cyl(0.22, 0.15, JP.m(0xfff0f6), 0, 1.18, 0)
                JP.bob(t.ball(0.06, JP.m(0xd02a3a), 0, 1.33, 0), 0.03, 0.5)
            }
        ]
    }
}
