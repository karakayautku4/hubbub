import SceneKit

extension Jobs {
    static var spaceCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Dish repair", "📡", spot: b[0], .wrench, lines: ["Have you tried turning the dish off and on?", "This bolt is older than the station.", "Signal's back! Oh, it's just static.", "Tightening. Always tightening."]) { n in
                let d = n.group("dish", 0, 0, 1.3)
                d.cyl(0.05, 1.2, JP.m(0x8a93a3, 0.4, 0.6), 0, 0.6, 0)
                let bowl = d.ball(0.6, JP.m(0xdfe6f0, 0.4, 0.4), 0, 1.35, 0)
                bowl.scale = SCNVector3(1, 0.35, 1); bowl.eulerAngles.x = -0.6
                JP.sway(bowl, 0.08, 1.4)
                JP.blink(d.ball(0.06, JP.glow(0xff4444), 0.3, 1.7, 0.2))
            },
            Job("Hydroponics", "🌱", spot: b[1], .water, lines: ["Grow, little lettuce, grow!", "Day 40: the basil has opinions.", "Zero-g watering is mostly chasing droplets.", "Salad bar opens soon."]) { n in
                let t = JP.table(n, 0x6b7a8c, w: 1.6, d: 0.7)
                for i in 0..<4 { let x = CGFloat(i) * 0.38 - 0.57; t.ball(0.15, JP.m(0x4fb86a), x, 1.05, 0); t.cyl(0.08, 0.1, JP.m(0xdfe6f0), x, 0.95, 0) }
                JP.pulse(t.ball(0.07, JP.glow(0x66ff99), 0.7, 1.4, 0), 0.4, 0.8)
            },
            Job("Zero-g yoga", "🧘", spot: b[2], .yoga, lines: ["Breathe in... and drift.", "My chakras are floating away.", "Downward dog, upward dog, sideways dog.", "Namaste, nebula."]) { n in
                let mat = n.box(1.2, 0.05, 1.0, JP.m(0x7a5cff), 0, 0.03, 0.2, round: 0.02)
                JP.bob(mat, 0.08, 1.3)
                JP.spin(n.ball(0.08, JP.glow(0xffd966), 0.7, 1.9, 0.6), 3)
            },
            Job("Asteroid scan", "☄️", spot: b[3], .scan, lines: ["Rock. Rock. Slightly bigger rock.", "Scanning... it's a potato.", "No life forms. Just vibes.", "That one looks like a cat."]) { n in
                let s = JP.screen(n, 0x33ccff, w: 0.9, h: 0.55, y: 1.4, z: 1.3)
                JP.blink(s, 0.9)
                let rock = n.ball(0.28, JP.m(0x6b665e, 0.95), 0.9, 1.9, 1.0)
                rock.scale = SCNVector3(1.2, 0.9, 1)
                JP.spin(rock, 6)
            },
            Job("Solar panel polish", "☀️", spot: b[4], .polish, lines: ["Shine bright like a star.", "Spotless. Again.", "Space dust is rude.", "I can see my helmet in it."]) { n in
                let p = n.group("panel", 0, 0, 1.2)
                p.cyl(0.04, 1.0, JP.m(0x8a93a3, 0.4, 0.6), 0, 0.5, 0)
                let pan = p.box(1.5, 0.9, 0.05, JP.m(0x1d3f8a, 0.3, 0.3), 0, 1.3, 0)
                pan.eulerAngles.x = -0.25
                JP.sway(pan, 0.06, 1.5)
            },
            Job("Oxygen tank check", "🫧", spot: b[5], .tinker, lines: ["Air: still there. Excellent.", "Psst... it smells like pizza.", "Sixteen tanks, one sneeze.", "Counting breaths for science."]) { n in
                for i in 0..<3 { JP.barrel(n, 0x4aa3d9, x: CGFloat(i) * 0.5 - 0.5, z: 1.2, r: 0.2, h: 0.9) }
                JP.blink(n.ball(0.06, JP.glow(0x66ff99), 0, 1.15, 1.2), 0.8)
            },
            Job("Cargo juggling", "📦", spot: b[6], .juggle, lines: ["Fragile. Very fragile. Whoops.", "Zero-g makes this so easy!", "Three crates, two hands, one plan.", "Do not drop. Do not drop."]) { n in
                JP.crate(n, 0xb98b52, x: -0.9, z: 1.1)
                JP.crate(n, 0xa5784a, x: 0.9, z: 1.1, s: 0.6)
                let c = n.box(0.3, 0.3, 0.3, JP.m(0xd9a35f), 0, 2.2, 1.0)
                JP.bob(c, 0.3, 0.6)
            },
            Job("Rover wash", "🚙", spot: b[7], .wash, lines: ["Moon dust everywhere!", "Scrub, scrub, vacuum.", "This rover has seen things.", "Wax on, wax off, helmet on."]) { n in
                let r = n.group("rover", 0, 0, 1.4)
                r.box(1.3, 0.35, 0.7, JP.m(0xd9dde4, 0.5, 0.3), 0, 0.5, 0, round: 0.05)
                for sx: CGFloat in [-1, 1] { for sz: CGFloat in [-1, 1] { r.cyl(0.2, 0.15, JP.m(0x2a2f38), sx * 0.5, 0.2, sz * 0.38).eulerAngles.z = .pi / 2 } }
                JP.bucket(n, 0x4aa3d9, x: 0.9, z: 0.4)
            }
        ]
    }
}
