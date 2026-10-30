import SceneKit

extension Jobs {
    static var farmCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Chicken chasing", "🐔", spot: b[0], .chase, lines: ["Come back, Henrietta!", "Bawk! (rude)", "Fastest chicken in the west.", "I almost had her."]) { n in
                for i in 0..<3 {
                    let c = n.group("hen", CGFloat(i) * 0.6 - 0.6, 0, 1.1)
                    c.ball(0.17, JP.m(0xffffff), 0, 0.25, 0); c.ball(0.1, JP.m(0xffffff), 0, 0.45, 0.12); c.box(0.06, 0.06, 0.1, JP.m(0xf2a23a), 0, 0.45, 0.2)
                    JP.bob(c, 0.06, 0.25 + Double(i) * 0.08)
                }
            },
            Job("Cow milking", "🥛", spot: b[1], .milk, lines: ["Moo-ve over a little.", "Squeeze, pull, repeat.", "She is not amused.", "Fresh and cold in the bucket."]) { n in
                let c = n.group("cow", 0, 0, 1.3)
                c.box(1.0, 0.6, 0.5, JP.m(0xffffff), 0, 0.7, 0, round: 0.05)
                c.box(0.3, 0.3, 0.3, JP.m(0xffffff), 0.6, 0.9, 0)
                for i in 0..<3 { c.box(0.25, 0.25, 0.52, JP.m(0x2a2a2a), CGFloat(i) * 0.3 - 0.3, 0.8, 0) }
                for sx: CGFloat in [-1, 1] { c.box(0.12, 0.4, 0.12, JP.m(0xe8e8e8), sx * 0.35, 0.2, 0.15) }
                JP.sway(c.ball(0.05, JP.m(0x2a2a2a), -0.55, 0.7, 0), 0.5, 0.5)
                JP.bucket(n, 0xd9dde4, x: 0.5, z: 0.5)
            },
            Job("Scarecrow duty", "🎃", spot: b[2], .stack, lines: ["Standing very still. Very. Still.", "The crows know. They know.", "Is this hat on straight?", "Shoo! ...please."]) { n in
                JP.pole(n, 0x8a6a45, x: 0, z: 1.1, h: 1.7)
                n.box(1.0, 0.08, 0.08, JP.m(0x8a6a45), 0, 1.35, 1.1)
                let s = n.box(0.5, 0.6, 0.2, JP.m(0xd9a35f, 0.9), 0, 1.15, 1.1)
                JP.sway(s, 0.04, 1.3)
                n.ball(0.2, JP.m(0xe0c08a), 0, 1.8, 1.1)
                n.cyl(0.25, 0.04, JP.m(0x5a4a3a), 0, 1.95, 1.1)
            },
            Job("Tractor polishing", "🚜", spot: b[3], .polish, lines: ["Red, shiny, vroom.", "Wax on, mud on.", "Don't tell it, but it's my favorite.", "Beep beep, polished."]) { n in
                let t = n.group("tractor", 0, 0, 1.4)
                t.box(1.2, 0.5, 0.6, JP.m(0xc43a2a, 0.4), 0, 0.6, 0, round: 0.05)
                t.box(0.5, 0.5, 0.55, JP.m(0xd94a3a, 0.4), -0.3, 1.05, 0)
                t.cyl(0.35, 0.15, JP.m(0x2a2a2a), -0.45, 0.35, 0.38).eulerAngles.x = .pi / 2
                t.cyl(0.22, 0.15, JP.m(0x2a2a2a), 0.5, 0.22, 0.38).eulerAngles.x = .pi / 2
                JP.blink(t.ball(0.05, JP.glow(0xffffcc), 0.62, 0.7, 0.2), 1.2)
            },
            Job("Hay stacking", "🌾", spot: b[4], .stack, lines: ["Hay there!", "Stack it high, sleep tight.", "Pitchfork is heavier than it looks.", "That bale has a mind of its own."]) { n in
                for i in 0..<3 { n.box(0.7, 0.4, 0.5, JP.m(0xd9b84a, 0.95), CGFloat(i) * 0.7 - 0.7, 0.2, 1.2, round: 0.03) }
                n.box(0.7, 0.4, 0.5, JP.m(0xd9b84a, 0.95), 0, 0.6, 1.2, round: 0.03)
            },
            Job("Egg collecting", "🥚", spot: b[5], .stack, lines: ["Gently now.", "Twelve eggs, one omelette.", "One hen is staring at me.", "Warm eggs, warm hearts."]) { n in
                JP.bucket(n, 0xb98b52, x: 0.4, z: 1.0, r: 0.35, h: 0.3)
                for i in 0..<4 { n.ball(0.09, JP.m(0xfff4e0), 0.3 + CGFloat(i % 2) * 0.2, 0.34, 0.9 + CGFloat(i / 2) * 0.2) }
                n.box(0.9, 0.3, 0.6, JP.m(0x8a6a45, 0.9), -0.7, 0.15, 1.2)
            },
            Job("Pumpkin watering", "💧", spot: b[6], .water, lines: ["Grow big!", "Drink up, little orange ones.", "This one's bigger than my head.", "Pumpkin pie dreams."]) { n in
                for i in 0..<3 { let p = n.ball(0.28, JP.m(0xe8872a), CGFloat(i) * 0.6 - 0.6, 0.28, 1.1); p.scale = SCNVector3(1, 0.8, 1) }
                JP.bucket(n, 0x4aa3d9, x: 1.0, z: 0.6)
            },
            Job("Fence painting", "🖌️", spot: b[7], .paint, lines: ["Another fence, another coat.", "Whitewash everything!", "Paint dries; patience doesn't.", "I think I painted a sheep."]) { n in
                for i in 0..<5 { n.box(0.12, 0.8, 0.06, JP.m(0xffffff), CGFloat(i) * 0.34 - 0.68, 0.4, 1.3) }
                n.box(1.6, 0.1, 0.05, JP.m(0xf4f4f4), 0, 0.55, 1.3)
                JP.bucket(n, 0xffffff, x: 1.0, z: 0.7)
            }
        ]
    }
}
