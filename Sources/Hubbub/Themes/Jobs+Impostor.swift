import SceneKit

extension Jobs {
    static var impostorCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Card swipe", "💳", spot: b[0], .tinker, lines: ["Too fast. Too slow. Too fast.", "Swipe again. Again. Again.", "Why is the light still red?", "Totally normal swiping."]) { n in
                n.box(0.4, 1.0, 0.2, JP.m(0x4a5568, 0.5, 0.3), 0, 0.9, 1.2)
                JP.blink(n.box(0.1, 0.1, 0.03, JP.glow(0xff4444), 0, 1.2, 1.32), 0.6)
            },
            Job("Wiring fix", "🔌", spot: b[1], .wrench, lines: ["Red to red. Blue to blue.", "Sparks? That's normal.", "Fixing, definitely fixing.", "Nobody saw that zap."]) { n in
                n.box(1.0, 1.0, 0.1, JP.m(0x4a5568, 0.5, 0.3), 0, 1.0, 1.3)
                for (i, c) in [0xff3030, 0x3070ff, 0xffe030, 0xf030f0].enumerated() { JP.blink(n.box(0.7, 0.04, 0.03, JP.glow(UInt32(c)), 0, 0.7 + CGFloat(i) * 0.2, 1.37), 0.4 + Double(i) * 0.15) }
            },
            Job("Fake tasks", "🕵️", spot: b[2], .tinker, lines: ["I'm doing tasks. Many tasks.", "Look at me being busy.", "Not suspicious at all.", "This is my real task, I swear."]) { n in
                let t = JP.table(n, 0x6b7a8c, w: 1.1, d: 0.7)
                JP.blink(t.box(0.4, 0.3, 0.03, JP.glow(0x66ff99), 0, 1.15, -0.2), 0.7)
            },
            Job("Button polishing", "🔴", spot: b[3], .polish, lines: ["Don't press it. Don't press it.", "Shiny red button of doom.", "One more rub. Just one.", "Is it humming?"]) { n in
                let t = JP.table(n, 0x6b7a8c, w: 0.7, d: 0.6)
                t.cyl(0.22, 0.1, JP.m(0x555a62, 0.4, 0.6), 0, 0.95, 0)
                JP.pulse(t.cyl(0.15, 0.1, JP.glow(0xff3030), 0, 1.05, 0), 0.1, 0.5)
            },
            Job("Vent cleaning", "🌀", spot: b[4], .sweep, lines: ["Nothing suspicious in here.", "Why are there footprints?", "Vents are just for... air.", "I crawled out of it. Normal."]) { n in
                n.box(1.0, 0.5, 0.06, JP.m(0x4a5568, 0.5, 0.5), 0, 0.3, 1.5)
                for i in 0..<4 { n.box(0.8, 0.03, 0.02, JP.m(0x20242c), 0, 0.16 + CGFloat(i) * 0.1, 1.54) }
            },
            Job("Download wait", "💾", spot: b[5], .type, lines: ["Downloading... 12%.", "Upload next. Pray.", "The bar is moving. Sideways.", "Have you seen my progress bar?"]) { n in
                let s = JP.screen(n, 0x33ccff, w: 0.9, h: 0.5)
                s.runAction(.repeatForever(.sequence([.scale(to: 1.05, duration: 0.6), .scale(to: 1, duration: 0.6)])))
            },
            Job("Trash chute", "🗑️", spot: b[6], .stack, lines: ["Pull the lever. Thump.", "Leaves... fall.", "Whoosh. Gone.", "Recycling suspicious items."]) { n in
                JP.barrel(n, 0x5a6a7a, x: 0, z: 1.2, r: 0.35, h: 0.9)
                JP.bob(n.ball(0.12, JP.m(0x3a8a3a), 0.5, 0.4, 1.0), 0.1, 0.7)
            },
            Job("Navigation align", "🧭", spot: b[7], .scan, lines: ["Course corrected. I think.", "North is... that way.", "Align engine output.", "Steering with confidence."]) { n in
                let s = JP.screen(n, 0x6a5cff, w: 1.0, h: 0.55, y: 1.3, z: 1.3)
                JP.spin(n.cyl(0.25, 0.03, JP.glow(0xffd24a), 0, 0.9, 1.1), 4)
                _ = s
            }
        ]
    }
}
