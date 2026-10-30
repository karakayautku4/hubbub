import SceneKit

extension Jobs {
    static var footballCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Ball juggling", "⚽", spot: b[0], .juggle, lines: ["Eighty-nine... ninety!", "Keepie-uppie champion.", "Don't look down.", "Header, knee, foot, oops."]) { n in
                let ball = n.ball(0.22, JP.m(0xffffff, 0.5), 0, 1.5, 1.0)
                JP.bob(ball, 0.6, 0.55)
                n.cyl(0.35, 0.02, JP.m(0xf2d24a, 0.9), 0, 0.02, 1.0)
            },
            Job("Goalpost painting", "🥅", spot: b[1], .paint, lines: ["One more coat of white.", "Straight lines? Optional.", "Fresh paint, don't touch!", "Painted myself into a corner."]) { n in
                JP.pole(n, 0xffffff, x: -0.9, z: 1.2, h: 1.8, r: 0.06); JP.pole(n, 0xffffff, x: 0.9, z: 1.2, h: 1.8, r: 0.06)
                n.box(1.9, 0.1, 0.1, JP.m(0xffffff), 0, 1.8, 1.2)
                JP.bucket(n, 0xffffff, x: 1.1, z: 0.5)
            },
            Job("Mascot dance", "🕺", spot: b[2], .dance, lines: ["Wave to the crowd!", "I'm sweating inside this suit.", "Shake what the club gave me.", "Goal! ...for dancing."]) { n in
                let p = n.box(1.3, 0.06, 1.3, JP.m(0x7a5cff, 0.6), 0, 0.03, 0.4, round: 0.02)
                JP.pulse(n.ball(0.12, JP.glow(0xffd24a), 0.6, 0.2, 0.8), 0.4, 0.4)
                JP.blink(p, 1.2)
            },
            Job("Ball pump", "🎈", spot: b[3], .pump, lines: ["Pssshh... not enough!", "Pump, pump, pump.", "Overinflated. Too late.", "This one is shaped like an egg."]) { n in
                let pile = n.group("balls", 0.9, 0, 0.9)
                for i in 0..<4 { pile.ball(0.2, JP.m(i % 2 == 0 ? 0xffffff : 0xf2d24a, 0.5), CGFloat(i % 2) * 0.3, 0.2 + CGFloat(i / 2) * 0.3, 0) }
                n.cyl(0.07, 0.5, JP.m(0xd94a3a), -0.6, 0.25, 1.0)
            },
            Job("Line marking", "📏", spot: b[4], .sweep, lines: ["Straight as a ruler.", "Whose line is this anyway?", "Chalk dust in my nose.", "Offside, if I say so."]) { n in
                n.box(1.8, 0.01, 0.06, JP.m(0xffffff), 0, 0.02, 1.2)
                JP.bucket(n, 0xffffff, x: 1.0, z: 0.6, h: 0.3)
            },
            Job("Penalty practice", "🎯", spot: b[5], .aim, lines: ["Top corner. Top corner. Top... cloud.", "Keeper's asleep!", "Left, right, panic.", "I meant that."]) { n in
                n.box(1.1, 0.8, 0.04, JP.m(0xe8e8e8, 0.9), 0, 0.9, 1.9)
                for i in 0..<3 { n.ball(0.17, JP.m(0xffffff, 0.5), CGFloat(i) * 0.4 - 0.4, 0.17, 0.9) }
                JP.bob(n.ball(0.14, JP.m(0xffffff, 0.5), 0, 0.9, 1.8), 0.1, 0.6)
            },
            Job("Kit washing", "👕", spot: b[6], .wash, lines: ["Mud, grass, more mud.", "Whites are now beige.", "Lucky socks, don't shrink!", "Number nine, clean at last."]) { n in
                JP.bucket(n, 0x4a7ad9, x: 0.5, z: 0.9, r: 0.3, h: 0.45)
                JP.pole(n, 0x8a8f99, x: -0.9, z: 1.2, h: 1.5); JP.pole(n, 0x8a8f99, x: 0.9, z: 1.2, h: 1.5)
                JP.sway(n.box(0.4, 0.5, 0.03, JP.m(0xd94a3a), -0.3, 1.3, 1.2), 0.1, 0.9)
                JP.sway(n.box(0.4, 0.5, 0.03, JP.m(0xffffff), 0.3, 1.3, 1.2), 0.1, 1.1)
            },
            Job("Trophy shine", "🏆", spot: b[7], .polish, lines: ["Gleaming. And heavy.", "Dust never wins.", "I see my reflection winning.", "It's the old cup. Treat it kindly."]) { n in
                let t = JP.table(n, 0x7a5a3a, w: 0.9, d: 0.6)
                t.cyl(0.18, 0.08, JP.m(0xffd24a, 0.2, 0.9), 0, 0.95, 0)
                t.cyl(0.08, 0.3, JP.m(0xffd24a, 0.2, 0.9), 0, 1.15, 0)
                JP.blink(t.ball(0.18, JP.m(0xffd24a, 0.2, 0.9), 0, 1.4, 0), 0.9)
            }
        ]
    }
}
