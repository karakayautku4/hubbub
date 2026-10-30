import SwiftUI
import SceneKit

/// Developer aid: `Hubbub --snapshot out.png` simulates a few seconds and renders every theme.
@MainActor
enum Snapshot {
    static func render(to path: String) {
        func sub(_ n: String, tool: String?, ago: Double) -> SubAgent {
            SubAgent(id: n, name: n, displayName: n, model: "gpt-5", startedAt: Date().addingTimeInterval(-ago), tool: tool, busy: true,
                     actions: [ActionRecord(id: n, time: Date(), tool: tool ?? "view", detail: "src/main.swift")])
        }
        var session = SessionInfo(id: "a", name: "Build feature", cwd: "/x", model: "m", lastEvent: Date(), state: .working,
                                  currentTool: "bash",
                                  subagents: [sub("rubber-duck", tool: "grep", ago: 20), sub("explore", tool: "edit", ago: 20),
                                              sub("task", tool: "bash", ago: 20), sub("review", tool: "web_fetch", ago: 20)],
                                  inputTokens: 0, outputTokens: 0, toolCalls: 0)
        // CREW_FAKE_AGENTS=N renders N sub-agents (every 5th one running a tool, the rest idle at their jobs).
        if let n = ProcessInfo.processInfo.environment["CREW_FAKE_AGENTS"].flatMap(Int.init) {
            session.subagents = (0..<max(n - 1, 0)).map { i in
                var s = sub("agent-\(i)", tool: ["grep", "edit", "bash", "web_fetch"][i % 4], ago: 30)
                s.busy = i % 5 == 4
                return s
            }
        }
        let fake = ProcessInfo.processInfo.environment["CREW_FAKE_METRICS"] != nil && session.subagents.count == 4
        func faked(_ base: SessionInfo, late: Bool) -> SessionInfo {
            var x = base
            x.model = "claude-sonnet-4.5"
            x.startedAt = Date().addingTimeInterval(-(3 * 86400 + 4 * 3600))
            x.contextTokens = 70_000; x.contextLimit = 128_000; x.toolCalls = 40; x.failures = 1; x.costCredits = late ? 4.4 : 4
            let ctx: [Double] = [0.15, 0.5, 0.8, late ? 0.3 : 0.97]
            for i in x.subagents.indices {
                x.subagents[i].contextLimit = 100; x.subagents[i].contextTokens = Int(ctx[i] * 100)
                x.subagents[i].toolCalls = 30; x.subagents[i].failures = i == 3 ? 6 : 0
                x.subagents[i].costCredits = i == 0 && late ? 1.3 : 1
                x.subagents[i].waitingApproval = i == 1
            }
            return x
        }
        let seconds = Double(CommandLine.arguments.last.flatMap(Double.init) ?? 9)
        let w = 1272, h = 716
        let failAgo = Double(ProcessInfo.processInfo.environment["SNAP_FAIL_AGO"] ?? "") ?? 3.2
        var images: [NSImage] = []
        // SNAP_CUSTOM=<theme.json> renders just that community theme.
        var targets: [(Theme, CustomTheme?)] = Theme.allCases.map { ($0, nil) }
        if let p = ProcessInfo.processInfo.environment["SNAP_CUSTOM"], let d = FileManager.default.contents(atPath: p), case .success(let c) = CustomTheme.parse(d) {
            targets = [(c.baseTheme, c)]
        }
        if let only = ProcessInfo.processInfo.environment["SNAP_THEME"] { targets = targets.filter { $0.0.rawValue == only } }
        for (th, custom) in targets {
            let stage = Stage()
            let debug = ProcessInfo.processInfo.environment["SNAP_DEBUG"] != nil
            var worst = 0
            stage.custom = custom
            stage.sessions = [fake ? faked(session, late: false) : session]
            stage.theme = th
            var t = 1000.0
            var failed = fake ? faked(session, late: true) : session
            failed.lastFailureAt = Date()
            var fired = false
            while t < 1000 + seconds {
                if !fired, t > 1000 + seconds - failAgo { stage.sessions = [failed]; fired = true }
                stage.tick(t: t, render: true); t += 1.0 / 30
                if debug, t > 1000 + seconds - 1 { worst = max(worst, stage.overlappingPillCount()) }
            }
            if ProcessInfo.processInfo.environment["SNAP_DEBUG"] != nil { func ndc(_ y: Double, _ z: Double) -> Double {
                let c = simd_inverse(stage.camera.simdWorldTransform) * simd_float4(0, Float(y), Float(z), 1)
                return Double(c.y / -c.z) / tan(Double(stage.camera.camera?.fieldOfView ?? 41) * .pi / 360)
            }
            print("ndc top", ndc(5.6, -0.4), "z8", ndc(0, 8), "z9.2", ndc(0, 9.2), "fov", stage.camera.camera?.fieldOfView ?? 0, "dir", stage.camera.camera?.projectionDirection.rawValue ?? -1)
            print("pillOverlaps last", stage.overlappingPillCount(), "worst in last second", worst); print("cam", stage.camera.position, "fit", stage.cameraRig.fitTarget, "tilt", stage.cameraRig.tiltTarget, "shift", stage.cameraRig.lookShiftZ); print(th.rawValue, "arena", stage.arenaExtent, "props", stage.jobPropCount); if let sim = stage.world.sim(for: "a") { print(sim.all.map { "\(Int(Environments.wx($0.pos.x)))/\(Int(Environments.wz($0.pos.y)))" }.joined(separator: " ")) } }
            if let img = stage.snapshot(width: w, height: h) { images.append(img) }
        }
        let canvas = NSImage(size: NSSize(width: w * min(2, images.count), height: h * ((images.count + 1) / 2)))
        canvas.lockFocus()
        for (i, img) in images.enumerated() { img.draw(at: NSPoint(x: (i % 2) * w, y: ((images.count + 1) / 2 - 1 - i / 2) * h), from: NSRect(origin: .zero, size: img.size), operation: .copy, fraction: 1) }
        canvas.unlockFocus()
        guard let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    static func selfTest() {
        let stage = Stage()
        stage.theme = .prison
        let s = SessionInfo(id: "a", name: "x", cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: "bash",
                            subagents: [SubAgent(id: "s1", name: "task", displayName: "task", model: "m", startedAt: Date().addingTimeInterval(-30), tool: "bash", busy: true)],
                            inputTokens: 0, outputTokens: 0, toolCalls: 0)
        stage.sessions = [s]
        let v = StageSCNView(frame: NSRect(x: 0, y: 0, width: 636, height: 358))
        v.scene = stage.scene; v.pointOfView = stage.camera; v.stage = stage; stage.view = v
        let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = v; w.orderFrontRegardless()
        var t = 1000.0
        for _ in 0..<200 { stage.tick(t: t, render: true); t += 1.0 / 30 }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        guard let sub = stage.world.sim(for: "a")?.subs.first else { print("no sub"); return }
        let p = v.projectPoint(SCNVector3(Environments.wx(sub.pos.x), 1.5, Environments.wz(sub.pos.y)))
        print("sub at", sub.pos, "screen", p)
        stage.pointerDown(CGPoint(x: p.x, y: p.y), in: v)
        print("selected:", stage.selected?.name ?? "nil")
        stage.pointerDragged(CGPoint(x: p.x + 80, y: p.y - 30), in: v)
        print("dragged pos:", stage.world.sim(for: "a")?.subs.first?.pos ?? .zero)
        stage.pointerUp()
        let f = v.projectPoint(SCNVector3(0, 0, 6))
        stage.pointerDown(CGPoint(x: f.x, y: f.y), in: v)
        print("captain route:", stage.world.sim(for: "a")?.captain.route ?? [])
    }

    /// Renders the real popover content (as the menu bar window would) to a PNG.
    static func renderUI(to path: String) {
        let monitor = SessionMonitor()
        monitor.start()
        let quota = QuotaService()
        quota.start()
        let host = NSHostingView(rootView: ContentView(monitor: monitor, quotaService: quota))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("fitting size:", size)
    }
}
