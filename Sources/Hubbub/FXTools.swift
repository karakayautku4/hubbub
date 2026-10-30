import SceneKit
import AppKit

/// Developer tools for scene effects and mascots.
@MainActor
enum FXTools {
    /// `n` agents total (captain + n-1 subagents); every 5th is running a tool, the rest idle at their jobs.
    static func fakeSession(agents n: Int) -> SessionInfo {
        var s = demoSession()
        s.subagents = (0..<max(n - 1, 0)).map { i in
            SubAgent(id: "agent-\(i)", name: "agent-\(i)", displayName: "agent-\(i)", model: "m", startedAt: Date().addingTimeInterval(-30),
                     tool: ["grep", "edit", "bash", "web_fetch"][i % 4], busy: i % 5 == 4)
        }
        return s
    }

    private static func demoSession(failed: Bool = false) -> SessionInfo {
        func sub(_ n: String, _ tool: String) -> SubAgent {
            SubAgent(id: n, name: n, displayName: n, model: "m", startedAt: Date().addingTimeInterval(-30), tool: tool, busy: true)
        }
        var s = SessionInfo(id: "a", name: "Demo", cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: "bash",
                            subagents: [sub("explore", "edit"), sub("task", "bash"), sub("review", "grep")],
                            inputTokens: 0, outputTokens: 0, toolCalls: 0)
        if failed { s.lastFailureAt = Date() }
        return s
    }

    /// `--fxshot <theme> <out.png> <seconds>`: runs the stage in real time (so particles and actions advance) and saves the final frame.
    /// Use HUBBUB_FX=failure|success|celebration|spawn to replay an effect every 2.5 s.
    static func shot(theme: String, path: String, seconds: Double) {
        let stage = Stage()
        stage.theme = Theme(rawValue: theme) ?? .space
        // FX_SEQ=3,20,3 steps the agent count through the list (seconds/len each); FX_EVERY=<s> also saves out-<n>.png frames.
        // FX_SIZE=WxH sets the viewport; FX_ZOOM=<z> sets the user zoom.
        let env = ProcessInfo.processInfo.environment
        let seq = (env["FX_SEQ"] ?? env["CREW_FAKE_AGENTS"] ?? "").split(separator: ",").compactMap { Int($0) }
        stage.sessions = [seq.isEmpty ? demoSession() : fakeSession(agents: seq[0])]
        let dims = (env["FX_SIZE"] ?? "960x540").split(separator: "x").compactMap { Double($0) }
        let v = StageSCNView(frame: NSRect(x: 0, y: 0, width: dims.first ?? 960, height: dims.last ?? 540))
        if let z = env["FX_ZOOM"].flatMap({ Double($0) }) { stage.setZoom(CGFloat(z)) }
        v.scene = stage.scene; v.pointOfView = stage.camera; v.stage = stage; stage.view = v
        v.rendersContinuously = true
        let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = v; w.orderFrontRegardless()
        func save(_ to: String) {
            let img = v.snapshot()
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: to))
            }
        }
        let every = env["FX_EVERY"].flatMap { Double($0) }
        var nextShot = every ?? .infinity, frame = 0, step = 0
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let el = Date().timeIntervalSince(start)
            if seq.count > 1 {
                let k = min(Int(el / (seconds / Double(seq.count))), seq.count - 1)
                if k != step { step = k; stage.sessions = [fakeSession(agents: seq[k])] }
            }
            stage.tick(t: Date().timeIntervalSinceReferenceDate, render: true)
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
            if el >= nextShot {
                nextShot += every ?? 0
                save(path.replacingOccurrences(of: ".png", with: "-\(frame).png")); frame += 1
                print("frame \(frame - 1) t=\(String(format: "%.1f", el)) agents=\(seq.isEmpty ? 3 : seq[step]) arena=\(stage.arenaExtent) props=\(stage.jobPropCount)")
            }
        }
        save(path)
    }

    /// Every theme builds a mascot, a failure/success/celebration/spawn plays without leaving nodes behind, and the sim emits effects.
    static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL:", m); ok = false } }
        for th in Theme.allCases {
            let fx = SceneFX()
            let sim = RoomSim(theme: th)
            var t = 1000.0
            sim.update(session: demoSession(), theme: th, t: t, dt: 0.03)
            for _ in 0..<150 { t += 0.04; sim.update(session: demoSession(), theme: th, t: t, dt: 0.04) }
            sim.simulateFailure(t: t)
            check(sim.pendingEffects.contains { if case .failure = $0 { true } else { false } }, "\(th) failure effect emitted")
            fx.tick(sim: sim, all: [sim], theme: th, t: t)
            check(fx.root.childNodes.contains { $0.name == "mascot" }, "\(th) mascot present")
            for e in [SceneEffect.success(.zero), .spawn(.zero), .celebration, .failure(CGPoint(x: 160, y: 120))] { fx.play(e, theme: th, t: t) }
            check(fx.root.childNodes.count > 3, "\(th) effect nodes added")
            for _ in 0..<60 { t += 0.05; fx.tick(sim: sim, all: [sim], theme: th, t: t) }
        }
        UserDefaults.standard.set(false, forKey: "showMascot")
        let off = SceneFX(), sim = RoomSim(theme: .space)
        off.tick(sim: sim, all: [sim], theme: .space, t: 1)
        check(!off.root.childNodes.contains { $0.name == "mascot" }, "mascot toggle off")
        UserDefaults.standard.removeObject(forKey: "showMascot")
        print(ok ? "fx selftest OK" : "fx selftest FAILED")
        return ok
    }
}
