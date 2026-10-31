import AppKit
import SceneKit

extension Jobs {
    /// Eight cubicle jobs. Every prop starts with a three-sided booth and a desk (`Off.booth`), then adds its own gear.
    static var officeCatalog: [Job] {
        let b = Jobs.base
        func monitor(_ n: SCNNode, _ fg: UInt32, seed: UInt64, x: CGFloat = 0, style: Int = 0) {
            n.box(0.9, 0.58, 0.05, Gfx.mat(0x111827, r: 0.4, m: 0.4), x, 1.4, 1.35)
            n.box(0.82, 0.5, 0.03, Gfx.texMat(Gfx.screen(0x0d1117, fg, seed: seed, style: style), emissive: true), x, 1.4, 1.38)
            n.box(0.12, 0.2, 0.1, Gfx.mat(0x111827), x, 1.0, 1.35)
        }
        func keyboard(_ n: SCNNode, x: CGFloat = 0) { n.box(0.6, 0.04, 0.2, Gfx.mat(0x1f2937, r: 0.5), x, 0.92, 1.0) }
        func mug(_ n: SCNNode, x: CGFloat, color: UInt32 = 0xffffff) {
            n.cyl(0.07, 0.14, Gfx.mat(color, r: 0.4), x, 0.97, 0.95)
        }
        return [
            Job("Coding", "💻", spot: b[0], .type, lines: ["Just one more commit.", "It compiles! Don't touch it.", "Naming things is hard.", "TODO: fix later."]) { n in
                Off.booth(n, color: 0x6f8fb3, number: 1)
                monitor(n, 0x58a6ff, seed: 3); keyboard(n); mug(n, x: 0.6)
            },
            Job("Code review", "🔍", spot: b[1], .read, lines: ["LGTM. Maybe.", "Nit: trailing whitespace.", "Please add a test.", "Who wrote this? …oh."]) { n in
                Off.booth(n, color: 0x7aa38a, number: 2)
                monitor(n, 0x7ee787, seed: 5, style: 1)
                JP.blink(n.box(0.16, 0.16, 0.03, JP.glow(0x4ade80), 0.7, 1.55, 1.38), 0.9)
                n.box(0.4, 0.04, 0.3, Gfx.mat(0xf8fafc, r: 0.8), -0.5, 0.92, 1.0)
            },
            Job("Debugging", "🐞", spot: b[2], .scan, lines: ["It works on my machine.", "Explaining it to the duck…", "Why is it null?", "Print statements. Many."]) { n in
                Off.booth(n, color: 0xa36f6f, number: 3)
                monitor(n, 0xff6b6b, seed: 7, style: 2); keyboard(n)
                let duck = n.group("duck", 0.62, 0.9, 1.0)
                duck.ball(0.12, Gfx.mat(0xfacc15, r: 0.5), 0, 0.1, 0)
                duck.ball(0.08, Gfx.mat(0xfacc15, r: 0.5), 0.05, 0.25, 0.05)
                duck.box(0.07, 0.03, 0.05, Gfx.mat(0xf97316), 0.05, 0.24, 0.12)
                JP.bob(duck, 0.03, 0.6)
            },
            Job("Stand-up notes", "📋", spot: b[3], .plot, lines: ["Yesterday I… did stuff.", "No blockers. Probably.", "Let's take it offline.", "Moving the ticket right."]) { n in
                Off.booth(n, color: 0xb59a6b, number: 4)
                n.box(1.2, 0.8, 0.05, Gfx.mat(0xe5e7eb, r: 0.4, m: 0.4), 0, 1.6, 1.4)
                n.box(1.1, 0.7, 0.03, Gfx.texMat(Off.kanban(), r: 0.5), 0, 1.6, 1.43)
                keyboard(n)
            },
            Job("Deploying", "🚀", spot: b[4], .tinker, lines: ["Friday deploy. What could go wrong?", "Shipping it!", "Rollback plan? …Vibes.", "Please don't page me."]) { n in
                Off.booth(n, color: 0x7a7fb3, number: 5)
                monitor(n, 0x4ade80, seed: 9, style: 1)
                let btn = n.cyl(0.14, 0.08, JP.glow(0x22c55e), 0.55, 0.94, 0.95)
                JP.pulse(btn, 0.1, 0.5)
                n.cyl(0.18, 0.04, Gfx.mat(0x374151, m: 0.6), 0.55, 0.9, 0.95)
            },
            Job("Design mock-up", "🎨", spot: b[5], .paint, lines: ["Can we make the logo bigger?", "Pixel-perfect. Almost.", "More whitespace.", "That's not the hex I wanted."]) { n in
                Off.booth(n, color: 0xb37ab0, number: 6)
                n.box(1.0, 0.65, 0.05, Gfx.mat(0x111827, r: 0.4), 0, 1.4, 1.35)
                for (i, c) in [0xfb7185, 0xfacc15, 0x38bdf8, 0x4ade80].enumerated() {
                    n.box(0.4, 0.25, 0.03, JP.glow(UInt32(c)), -0.25 + CGFloat(i % 2) * 0.5, 1.28 + CGFloat(i / 2) * 0.28, 1.38)
                }
                n.box(0.35, 0.02, 0.25, Gfx.mat(0x111827), 0.55, 0.9, 0.95)
            },
            Job("Support tickets", "🎧", spot: b[6], .type, lines: ["Have you tried turning it off and on?", "Ticket #4096, urgent.", "Customer says it's broken.", "Closing as 'works as designed'."]) { n in
                Off.booth(n, color: 0x6fa3a3, number: 7)
                monitor(n, 0xfbbf24, seed: 13, style: 1); keyboard(n)
                n.add(SCNTorus(ringRadius: 0.14, pipeRadius: 0.02), Gfx.mat(0x111827), at: SCNVector3(-0.6, 1.0, 1.0))
                n.box(0.3, 0.05, 0.2, Gfx.mat(0xf8fafc, r: 0.8), 0.6, 0.93, 0.98)
                JP.blink(n.box(0.2, 0.04, 0.15, JP.glow(0xf87171), 0.6, 0.98, 0.98), 0.7)
            },
            Job("Sprint planning", "🗓️", spot: b[7], .cards, lines: ["Is it a 5 or an 8?", "Estimates are just guesses.", "Scope creep incoming.", "Let's call it 'a quick fix'."]) { n in
                Off.booth(n, color: 0x9a8fb3, number: 8)
                for (i, c) in [0xfef08a, 0xbbf7d0, 0xbfdbfe].enumerated() {
                    n.box(0.22, 0.02, 0.32, Gfx.mat(UInt32(c), r: 0.8), -0.3 + CGFloat(i) * 0.3, 0.92, 1.0).eulerAngles = SCNVector3(0, CGFloat(i) * 0.3 - 0.3, 0)
                }
                n.box(0.9, 0.7, 0.04, Gfx.mat(0xf8fafc, r: 0.6), 0, 1.5, 1.4)
                for r in 0..<3 { for c in 0..<4 { n.box(0.16, 0.12, 0.02, Gfx.mat((r + c) % 3 == 0 ? 0xfca5a5 : 0xe5e7eb, r: 0.8), -0.33 + CGFloat(c) * 0.22, 1.3 + CGFloat(r) * 0.2, 1.43) } }
            }
        ]
    }
}
