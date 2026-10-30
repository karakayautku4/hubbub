import SceneKit

extension Jobs {
    static var galacticCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Bot tuning", "🤖", spot: b[0], .tinker, lines: ["Beep boop. Bad beep.", "Your oil is fine. Stop whining.", "Tuning chirps to 11.", "Which wire is the sarcasm one?"]) { n in
                let d = n.group("droid", 0, 0, 1.3)
                d.cyl(0.25, 0.5, JP.m(0xd9dde4, 0.4, 0.4), 0, 0.5, 0)
                d.ball(0.25, JP.m(0xd9dde4, 0.4, 0.4), 0, 0.85, 0)
                JP.blink(d.ball(0.07, JP.glow(0x33ccff), 0, 0.88, 0.2), 0.7)
                JP.sway(d, 0.06, 1.0)
            },
            Job("Laser target practice", "🎯", spot: b[1], .aim, lines: ["Pew pew! Missed.", "It moved!", "I'm calibrating. Not missing.", "Bullseye... for the wall."]) { n in
                let t = n.cyl(0.4, 0.05, JP.m(0xe8e8e8), 0, 1.2, 1.9); t.eulerAngles.x = .pi / 2
                n.cyl(0.2, 0.06, JP.glow(0xff4040), 0, 1.2, 1.9).eulerAngles.x = .pi / 2
                let beam = n.cyl(0.02, 1.0, JP.glow(0xff4040), 0, 1.3, 1.4)
                beam.eulerAngles.x = .pi / 2
                JP.blink(beam, 0.15)
            },
            Job("Holo-map plotting", "🗺️", spot: b[2], .plot, lines: ["Plotting a shortcut. Probably.", "That planet isn't on the map.", "Left at the nebula.", "Zoom in, zoom out, still lost."]) { n in
                let t = JP.table(n, 0x4a5568, w: 1.0, d: 0.8)
                let h = t.ball(0.3, JP.glow(0x33ccff), 0, 1.3, 0); h.opacity = 0.7
                JP.spin(h, 5, axis: SCNVector3(0, 1, 0))
            },
            Job("Hyperdrive tinkering", "🚀", spot: b[3], .wrench, lines: ["It's making that noise again.", "Probably fine. Probably.", "One spare bolt. Whoops.", "Eleven light-minutes to go."]) { n in
                let e = n.cyl(0.4, 0.8, JP.m(0x6b7a8c, 0.4, 0.6), 0, 0.5, 1.3)
                _ = e
                JP.pulse(n.ball(0.25, JP.glow(0x3388ff), 0, 1.0, 1.3), 0.15, 0.4)
                n.box(0.7, 0.04, 0.5, JP.m(0x20242c), 0.8, 0.02, 0.9)
            },
            Job("Cantina mopping", "🧽", spot: b[4], .sweep, lines: ["What spilled? Don't ask.", "Squeak, squeak.", "This stain is sentient.", "Slippery when blue."]) { n in
                JP.bucket(n, 0x4a7ad9, x: 0.7, z: 0.9)
                JP.blink(n.cyl(0.5, 0.01, JP.glow(0x3388ff), 0, 0.02, 1.3), 1.4)
            },
            Job("Crate scanning", "📦", spot: b[5], .scan, lines: ["Scanning: boxes. Boxes. Boxes.", "Contents: surprise.", "Declare your cargo!", "Beep. Customs approved."]) { n in
                JP.crate(n, 0x6a7a8a, x: -0.5, z: 1.3, s: 0.6)
                JP.crate(n, 0x8a7a6a, x: 0.3, z: 1.3, s: 0.5)
                JP.blink(n.box(0.7, 0.02, 0.02, JP.glow(0xff4040), 0, 0.9, 1.0), 0.4)
            },
            Job("Ship polish", "✨", spot: b[6], .polish, lines: ["Ship shape, literally.", "Not a scratch. A tiny scratch.", "Shine on, little ship.", "Please no blaster marks."]) { n in
                let s = n.group("ship", 0, 0, 1.4)
                s.box(1.4, 0.3, 0.7, JP.m(0xd9dde4, 0.3, 0.6), 0, 0.5, 0, round: 0.1)
                s.box(0.6, 0.05, 1.2, JP.m(0xaab0ba, 0.4, 0.6), 0, 0.5, 0)
                JP.bob(s, 0.04, 1.3)
            },
            Job("Power cell charging", "🔋", spot: b[7], .stack, lines: ["Fully charged. Mostly.", "Zap zap zap!", "Don't lick that.", "Spare cells for a rainy day."]) { n in
                for i in 0..<4 { let c = n.cyl(0.12, 0.4, JP.m(0x20242c, 0.5, 0.5), CGFloat(i) * 0.3 - 0.45, 0.2, 1.2); _ = c; JP.blink(n.box(0.1, 0.05, 0.1, JP.glow(0x66ff99), CGFloat(i) * 0.3 - 0.45, 0.42, 1.2), 0.5 + Double(i) * 0.2) }
            }
        ]
    }
}
