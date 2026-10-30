import SceneKit

extension Jobs {
    static var wizardCatalog: [Job] {
        let b = Jobs.base
        return [
            Job("Potion brewing", "🧪", spot: b[0], .stir, lines: ["Eye of newt, check.", "Bubble, bubble, ...oops.", "Smells like blueberries.", "This one turns you into a frog. Maybe."]) { n in
                let c = n.cyl(0.4, 0.5, JP.m(0x2a2f38, 0.4, 0.7), 0, 0.3, 1.1)
                _ = c
                JP.bob(n.ball(0.1, JP.glow(0x66ff99), 0.1, 0.65, 1.1), 0.2, 0.5)
                JP.bob(n.ball(0.07, JP.glow(0x66ff99), -0.15, 0.6, 1.15), 0.25, 0.7)
            },
            Job("Spell practice", "✨", spot: b[1], .spell, lines: ["Abracadabra! ...Hocus-pocus?", "That was a spark. A big one.", "I meant to light a candle.", "Next: levitating socks."]) { n in
                let t = n.ball(0.15, JP.glow(0xb06aff), 0, 1.9, 1.2)
                JP.pulse(t, 0.5, 0.5); JP.bob(t, 0.2, 0.7)
                n.cyl(0.5, 0.02, JP.glow(0x7a5cff), 0, 0.02, 1.0)
            },
            Job("Self-sweeping broom", "🧹", spot: b[2], .sweep, lines: ["Look, no hands! Also no help.", "The broom sweeps itself. I supervise.", "It missed a spot on purpose.", "Dust bunnies, flee!"]) { n in
                let g = n.group("broom", 0.6, 0, 1.2)
                g.cyl(0.03, 1.4, JP.m(0xa5784a), 0, 0.7, 0).eulerAngles.z = 0.3
                g.box(0.3, 0.2, 0.1, JP.m(0xd9b84a), 0.2, 0.1, 0)
                g.runAction(.repeatForever(.sequence([.moveBy(x: -1.2, y: 0, z: 0, duration: 1.2), .moveBy(x: 1.2, y: 0, z: 0, duration: 1.2)])))
            },
            Job("Owl post", "🦉", spot: b[3], .read, lines: ["Hoot! Letter for you.", "He keeps eating the mail.", "Sorting scrolls by smell.", "Dear Moon: wow."]) { n in
                JP.pole(n, 0x6b4a2a, x: 0, z: 1.2, h: 1.6)
                n.box(0.7, 0.05, 0.05, JP.m(0x6b4a2a), 0, 1.5, 1.2)
                let o = n.ball(0.17, JP.m(0xa58a68), 0.2, 1.7, 1.2); JP.bob(o, 0.04, 0.6)
                n.box(0.25, 0.3, 0.02, JP.m(0xf4e8c0), -0.4, 1.0, 1.0)
            },
            Job("Crystal gazing", "🔮", spot: b[4], .scan, lines: ["I see... Tuesday.", "Fog. Lots of fog.", "Oh! That's a sandwich.", "The ball says: later."]) { n in
                let t = JP.table(n, 0x4a3a6a, w: 0.9, d: 0.7)
                let s = t.ball(0.28, JP.glow(0x8a7aff), 0, 1.2, 0)
                JP.pulse(s, 0.12, 0.8)
            },
            Job("Rune carving", "ᚱ", spot: b[5], .hammer, lines: ["Tap, tap, glow.", "That rune means 'oops'.", "Carve here. Not there!", "Careful, it bites."]) { n in
                let s = n.box(0.7, 0.9, 0.3, JP.m(0x7a8090, 0.9), 0, 0.45, 1.2, round: 0.03)
                JP.blink(n.box(0.2, 0.3, 0.03, JP.glow(0x66ccff), 0, 0.6, 1.36), 0.8)
                _ = s
            },
            Job("Cauldron stoking", "🔥", spot: b[6], .tinker, lines: ["Hotter! Hotter!", "That log looks tasty.", "Fireproof beard, again.", "Phoenix on standby."]) { n in
                n.box(0.9, 0.2, 0.5, JP.m(0x5a5a5a, 0.9), 0, 0.1, 1.2)
                let f = n.ball(0.25, JP.glow(0xff8a30), 0, 0.4, 1.2); f.scale = SCNVector3(1, 1.4, 1)
                JP.pulse(f, 0.25, 0.25)
            },
            Job("Book levitation", "📚", spot: b[7], .read, lines: ["Fly, little books.", "Chapter twelve escaped.", "Page 47 is in a mood.", "Quiet in the library!"]) { n in
                for i in 0..<3 { JP.bob(n.box(0.4, 0.06, 0.3, JP.m([0xa03a3a, 0x3a5aa0, 0x3a8a4a][i], 0.8), CGFloat(i) * 0.45 - 0.45, 1.3 + CGFloat(i) * 0.15, 1.1), 0.2, 0.8 + Double(i) * 0.2) }
            }
        ]
    }
}
