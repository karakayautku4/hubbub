import SceneKit

/// `Hubbub --selftest-jobs`: catalog sizes, slot assignment, layout spacing, arena fit and zoom math.
@MainActor
enum JobsSelfTest {
    static func run() -> Bool {
        var fails: [String] = []
        func check(_ ok: Bool, _ msg: @autoclosure () -> String) { if !ok { fails.append(msg()) } }

        for theme in Theme.allCases {
            let name = theme.rawValue
            let jobs = Jobs.catalog(for: theme)
            check(jobs.count >= Jobs.minJobs, "\(name): only \(jobs.count) jobs")
            check(Set(jobs.map(\.name)).count == jobs.count, "\(name): duplicate job names")
            for j in jobs {
                check(j.lines.count >= 3, "\(name)/\(j.name): needs >= 3 lines")
                check(!j.emoji.isEmpty, "\(name)/\(j.name): no emoji")
                let node = SCNNode()
                j.prop(node)
                check(node.childNodes.count > 0, "\(name)/\(j.name): empty prop")
            }
            let slots = Jobs.slots(for: theme)
            check(slots.count >= 30, "\(name): only \(slots.count) slots")
            var minD = CGFloat.infinity
            for a in slots.indices { for b in slots.indices where b > a {
                minD = min(minD, hypot(slots[a].pos.x - slots[b].pos.x, slots[a].pos.y - slots[b].pos.y))
            } }
            check(minD >= 30, "\(name): slots only \(Int(minD)) apart \(slots.prefix(10).map { "\(Int($0.pos.x)),\(Int($0.pos.y))" })")
            let stations = theme.stations.map(\.pos) + [theme.coffee, theme.post]
            for s in slots {
                check(!stations.contains { hypot($0.x - s.pos.x, $0.y - s.pos.y) < 26 }, "\(name): slot \(s.index) sits on a station")
            }

            // Sequential joins N=1..30: nobody shares a slot, picks are deterministic and independent of join order of others.
            var taken = Set<Int>()
            var picks: [String: Int] = [:]
            for i in 0..<Jobs.maxAgents {
                let id = "agent-\(i)"
                let s = Jobs.pickSlot(id: id, taken: taken, theme: theme)
                check(!taken.contains(s), "\(name): agent \(i) shares slot \(s)")
                check(Jobs.pickSlot(id: id, taken: taken, theme: theme) == s, "\(name): pick not deterministic")
                taken.insert(s); picks[id] = s
            }
            check(taken.count == Jobs.maxAgents, "\(name): \(taken.count) distinct slots for \(Jobs.maxAgents) agents")
            let ext = Jobs.extent(of: Array(taken), theme: theme)
            check(ext.xHalf <= 60 && ext.zFar <= 30, "\(name): extent \(ext) unreasonable")
            check(Jobs.extent(of: [], theme: theme).xHalf == 14.6, "\(name): empty extent not base")
        }

        // Arena fit and zoom math.
        var last: CGFloat = 0
        for x in stride(from: CGFloat(14.6), through: 40, by: 2) {
            let f = ArenaMath.fit(xHalf: x, zFar: 7.8, aspect: 1.78)
            check(f >= 1 && f >= last, "fit not monotonic at \(x)")
            last = f
        }
        check(ArenaMath.fit(xHalf: 14.6, zFar: 7.8, aspect: 1.78) == 1, "base arena should not zoom out")
        check(ArenaMath.clampZoom(100) == ArenaMath.zoomRange.upperBound, "zoom upper clamp")
        check(ArenaMath.clampZoom(0.01) == ArenaMath.zoomRange.lowerBound, "zoom lower clamp")
        check(ArenaMath.clampZoom(.nan) == 1, "zoom NaN")
        check(ArenaMath.steppedZoom(1, direction: 1) == ArenaMath.zoomStep, "zoom in step")
        check(ArenaMath.steppedZoom(ArenaMath.zoomStep, direction: -1) == 1, "zoom back snaps to fit")
        var z: CGFloat = 1
        for _ in 0..<50 { z = ArenaMath.steppedZoom(z, direction: 1) }
        check(z == ArenaMath.zoomRange.upperBound, "repeated zoom in clamps")
        for _ in 0..<50 { z = ArenaMath.zoom(z, scrollDelta: -40) }
        check(z == ArenaMath.zoomRange.lowerBound, "scroll out clamps")
        check(ArenaMath.zoom(1, magnification: 0.5) > 1 && ArenaMath.zoom(1, magnification: -0.5) < 1, "pinch direction")

        // Live stage: agents get distinct slots and zoom is remembered per session.
        let stage = Stage()
        stage.theme = .kitchen
        stage.sessions = [session(id: "s1", subs: 11), session(id: "s2", subs: 1)]
        stage.selectedSessionID = "s1"
        var t = 1000.0
        for _ in 0..<300 { stage.tick(t: t, render: true); t += 1.0 / 30 }
        if let sim = stage.world.sim(for: "s1") {
            let slots = sim.all.map(\.jobSlot)
            check(Set(slots).count == slots.count && !slots.contains(-1), "live: duplicate/missing slots \(slots)")
            check(stage.arenaExtent.xHalf > 14.6 || stage.arenaExtent.zFar > 7.8, "live: arena did not grow for 12 agents")
        } else { fails.append("live: no sim") }
        stage.setZoom(2)
        check(stage.zoomLevel == 2 && !stage.isFitted, "stage zoom set")
        stage.selectedSessionID = "s2"
        for _ in 0..<5 { stage.tick(t: t, render: true); t += 1.0 / 30 }
        check(stage.isFitted, "zoom must be per session")
        stage.selectedSessionID = "s1"
        for _ in 0..<5 { stage.tick(t: t, render: true); t += 1.0 / 30 }
        check(stage.zoomLevel == 2, "zoom restored for session")
        stage.resetZoom()
        check(stage.isFitted, "reset zoom")

        // Regression: model must survive a tail window that no longer contains session.start / model_change.
        let mdir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("hubbub-selftest-model-\(getpid())")
        try? FileManager.default.createDirectory(at: mdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mdir) }
        let filler = String(repeating: "x", count: 4000)
        let head = "{\"type\":\"session.start\",\"data\":{\"sessionId\":\"m\"},\"timestamp\":\"2026-01-01T00:00:00.000Z\"}\n"
            + "{\"type\":\"session.model_change\",\"data\":{\"newModel\":\"claude-sonnet-5.5\"},\"timestamp\":\"2026-01-01T00:00:01.000Z\"}\n"
        let body = (0..<700).map { _ in "{\"type\":\"assistant.message\",\"data\":{\"content\":\"\(filler)\"},\"timestamp\":\"2026-01-01T00:00:02.000Z\"}\n" }.joined()
        try? (head + body).write(to: mdir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        check(SessionMonitor.parse(dir: mdir, modified: Date())?.model == "claude-sonnet-5.5", "model blank when session.start is outside the tail window")

        for th in Theme.allCases { propOverlaps(theme: th, slotLimit: Jobs.maxAgents).forEach { fails.append("prop overlaps set: " + $0) } }

        for f in fails { print("FAIL \(f)") }
        print(fails.isEmpty ? "jobs self-test OK" : "jobs self-test FAILED (\(fails.count))")
        return fails.isEmpty
    }

    private struct Box { var x0, x1, y0, y1, z0, z1: CGFloat; var name: String }

    /// World-space boxes of every solid-looking leaf under `root` (floors, walls, flat decals and ceiling pieces are skipped).
    private static func solids(_ root: SCNNode, relativeTo ref: SCNNode, label: String) -> [Box] {
        var out: [Box] = []
        func walk(_ n: SCNNode, _ path: String) {
            let here = n.name.map { path + "/" + $0 } ?? path
            if n.geometry != nil, !n.isHidden, n.opacity > 0.01 {
                let (lo, hi) = n.boundingBox
                var b = Box(x0: .infinity, x1: -.infinity, y0: .infinity, y1: -.infinity, z0: .infinity, z1: -.infinity, name: here)
                for cx in [lo.x, hi.x] { for cy in [lo.y, hi.y] { for cz in [lo.z, hi.z] {
                    let p = n.convertPosition(SCNVector3(cx, cy, cz), to: ref)
                    b.x0 = min(b.x0, p.x); b.x1 = max(b.x1, p.x); b.y0 = min(b.y0, p.y); b.y1 = max(b.y1, p.y); b.z0 = min(b.z0, p.z); b.z1 = max(b.z1, p.z)
                } } }
                if b.x1 - b.x0 < 12, b.z1 - b.z0 < 12, b.y1 > 0.3, b.y0 < 1.8, n.name != "floor", b.y1 - b.y0 > 0.12 { out.append(b) }
            }
            n.childNodes.forEach { walk($0, here) }
        }
        walk(root, label)
        return out
    }

    /// Job props must not intersect the set dressing (stations, furniture) of their theme, nor each other.
    static func propOverlaps(theme: Theme, slotLimit: Int) -> [String] {
        let env = Environments.build(theme)
        let host = SCNNode(); host.addChildNode(env)
        let envBoxes = solids(env, relativeTo: host, label: "env")
        let jobs = Jobs.catalog(for: theme), slots = Jobs.slots(for: theme)
        var report: [String] = []
        var props: [(Int, [Box])] = []
        for s in slots.prefix(slotLimit) {
            let g = SCNNode()
            g.position = SCNVector3(Environments.wx(s.pos.x), 0, Environments.wz(s.pos.y))
            g.eulerAngles = SCNVector3(0, Jobs.facing(atLogicalX: s.pos.x), 0)
            jobs[s.jobIndex % jobs.count].prop(g)
            host.addChildNode(g)
            let mine = solids(g, relativeTo: host, label: jobs[s.jobIndex % jobs.count].name)
            props.append((s.index, mine))
            for a in mine { for b in envBoxes {
                let ox = min(a.x1, b.x1) - max(a.x0, b.x0), oz = min(a.z1, b.z1) - max(a.z0, b.z0), oy = min(a.y1, b.y1) - max(a.y0, b.y0)
                if ox > 0.15, oz > 0.15, oy > 0.15 { report.append("\(theme.rawValue) slot \(s.index)@\(Int(s.pos.x)),\(Int(s.pos.y)) \(a.name) x \(b.name) (\(String(format: "%.1f", ox))x\(String(format: "%.1f", oz)))") }
            } }
        }
        for i in props.indices { for j in props.indices where j > i {
            var hit: (Box, Box, CGFloat)?
            for a in props[i].1 { for b in props[j].1 {
                let ox = min(a.x1, b.x1) - max(a.x0, b.x0), oz = min(a.z1, b.z1) - max(a.z0, b.z0), oy = min(a.y1, b.y1) - max(a.y0, b.y0)
                if ox > 0.15, oz > 0.15, oy > 0.15, hit == nil { hit = (a, b, min(ox, oz)) }
            } }
            if let h = hit { report.append("\(theme.rawValue) slots \(props[i].0)&\(props[j].0) props touch: \(h.0.name) x \(h.1.name)") }
        } }
        return report
    }

    private static func session(id: String, subs: Int) -> SessionInfo {
        let list = (0..<subs).map { i in
            SubAgent(id: "\(id)-\(i)", name: "a\(i)", displayName: "a\(i)", model: "m", startedAt: Date().addingTimeInterval(-30), tool: "bash", busy: i % 3 == 0)
        }
        return SessionInfo(id: id, name: id, cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: "bash",
                           subagents: list, inputTokens: 0, outputTokens: 0, toolCalls: 0)
    }
}
