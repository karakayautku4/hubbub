import Foundation
import AppKit
import SceneKit

/// `Hubbub --selftest-perf [--perf-agents N] [--perf-seconds S]`: headless steady-state performance check for every theme.
/// Each theme runs a paced 30 fps loop (simulation tick plus scene sync, with an offscreen render every few frames) and is
/// checked against thresholds. Override thresholds with PERF_MAX_TICK_MS, PERF_MAX_RENDER_MS, PERF_MAX_CPU_PCT,
/// PERF_MAX_MEM_GROWTH_MB and PERF_MAX_MEM_MB.
final class WeakStage { weak var s: Stage?; init(_ s: Stage) { self.s = s } }
@MainActor
enum PerfSelfTest {
    struct Limits {
        var tickMs = 8.0        // p95 simulation + scene sync time per frame
        var renderMs = 60.0     // p95 offscreen render of a 636x358 frame
        var cpuPct = 30.0       // process CPU over the paced steady-state window (30 fps tick, one core = 100)
        var memGrowthMB = 60.0  // footprint growth during the steady-state window
        var memMB = 1500.0      // absolute footprint at the end of a theme
    }

    private static func env(_ k: String, _ d: Double) -> Double { ProcessInfo.processInfo.environment[k].flatMap(Double.init) ?? d }
    private static func arg(_ name: String, _ d: Double) -> Double {
        guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return d }
        return Double(CommandLine.arguments[i + 1]) ?? d
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    static func percentile(_ v: [Double], _ p: Double) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, Int(Double(s.count) * p))]
    }

    static func sessions(agents: Int) -> [SessionInfo] {
        let tools = ["grep", "edit", "bash", "view", "web_fetch"]
        let perSession = max(1, Int((Double(agents) / 3).rounded(.up)))
        var out: [SessionInfo] = []
        var made = 0
        for i in 0..<3 where made < agents {
            let n = min(perSession, agents - made)
            let subs = (0..<n).map { j -> SubAgent in
                let id = "s\(i)-\(j)", tool = tools[(i + j) % tools.count]
                return SubAgent(id: id, name: "agent-\(j)", displayName: "agent-\(j)", model: "gpt-5", startedAt: Date().addingTimeInterval(-60), tool: tool, busy: true,
                                actions: [ActionRecord(id: id, time: Date(), tool: tool, detail: "src/main.swift")])
            }
            made += n
            out.append(SessionInfo(id: "perf-\(i)", name: "Session \(i + 1)", cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: "bash",
                                   subagents: subs, inputTokens: 0, outputTokens: 0, toolCalls: 0))
        }
        return out
    }

    /// `--selftest-perf --perf-live [--perf-agents N] [--perf-seconds S] [--perf-theme T]`: the real SCNView in an on-screen window,
    /// real-time display link, process CPU (one core = 100) over the window. This is the popover-open cost, including SceneKit's render thread.
    private static func live() -> Bool {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        Stage.forceVisible = true
        let agents = Int(arg("--perf-agents", 8)), seconds = arg("--perf-seconds", 6)
        let only = CommandLine.arguments.firstIndex(of: "--perf-theme").map { CommandLine.arguments[$0 + 1] }
        print("perf-live: \(agents) agents, \(seconds)s per theme, real view")
        var ok = true
        for theme in Theme.allCases where only == nil || theme.rawValue == only {
            let stage = Stage()
            stage.sessions = sessions(agents: agents)
            stage.theme = theme
            let v = StageSCNView(frame: NSRect(x: 0, y: 0, width: 636, height: 358))
            v.stage = stage; v.scene = stage.scene; v.pointOfView = stage.camera
            v.antialiasingMode = .multisampling4X
            stage.view = v
            let w = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = v
            w.orderFrontRegardless()
            stage.start()
            RunLoop.main.run(until: Date().addingTimeInterval(2.5))
            // PERF_EXP=noaa,aa2,noshadow,nohdr,nobloom,noparticles,size2x experiments, comma separated.
            let exp = Set((ProcessInfo.processInfo.environment["PERF_EXP"] ?? "").split(separator: ",").map(String.init))
            if exp.contains("noaa") { v.antialiasingMode = .none }
            if exp.contains("aa2") { v.antialiasingMode = .multisampling2X }
            if exp.contains("size2x") { w.setContentSize(NSSize(width: 1272, height: 716)) }
            if exp.contains("base") { v.antialiasingMode = .multisampling4X }
            stage.scene.rootNode.enumerateHierarchy { n, _ in
                if exp.contains("base") {
                    if n.geometry != nil, n.name != "floor" { n.castsShadow = true }
                    if let l = n.light, l.castsShadow { l.shadowMapSize = CGSize(width: 2048, height: 2048); l.shadowSampleCount = 8 }
                }
                if exp.contains("noshadow"), let l = n.light { l.castsShadow = false }
                if exp.contains("noparticles") { n.particleSystems?.forEach { n.removeParticleSystem($0) } }
            }
            if exp.contains("nohdr") { stage.camera.camera?.wantsHDR = false }
            if exp.contains("nobloom") { stage.camera.camera?.bloomIntensity = 0 }
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            if !Stage.popoverVisible { print("  warning: stage window not considered visible (occlusion \(w.occlusionState.rawValue), visible \(w.isVisible))") }
            if CommandLine.arguments.contains("--perf-zoom") {
                let log = FrameLog()
                v.delegate = log
                let z = zoomSweep(stage: stage, log: log, seconds: seconds)
                print("perf-zoom \(agents)a \(theme.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) frames \(z.frames) p50 \(fmt(z.p50))ms p95 \(fmt(z.p95))ms max \(fmt(z.max))ms dropped(>25ms) \(z.dropped)")
                v.delegate = nil
                stage.setZoom(1)
                RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            }
            let wall0 = Date(), cpu0 = cpuSeconds()
            RunLoop.main.run(until: wall0.addingTimeInterval(seconds))
            let pct = (cpuSeconds() - cpu0) / Date().timeIntervalSince(wall0) * 100
            let limit = env("PERF_MAX_LIVE_CPU_PCT", 15)
            if pct > limit { ok = false }
            var drawn = 0, casters = 0, textured = 0
            var mats = Set<ObjectIdentifier>()
            stage.scene.rootNode.enumerateHierarchy { n, _ in
                if let g = n.geometry, !n.isHidden, n.opacity > 0 { drawn += g.elementCount; if n.castsShadow { casters += g.elementCount }
                    g.materials.forEach { mats.insert(ObjectIdentifier($0)); if $0.diffuse.contents is NSImage { textured += 1 } } }
            }
            print("  draw elements \(drawn), shadow casters \(casters), distinct materials \(mats.count), textured draws \(textured)")
            print("perf-live \(agents)a \(theme.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) cpu \(fmt(pct))%  \(pct > limit ? "FAIL" : "ok")")
            w.orderOut(nil)
            v.scene = nil; stage.view = nil
        }
        return ok
    }

    private final class FrameLog: NSObject, SCNSceneRendererDelegate {
        private let lock = NSLock()
        private var stamps: [Double] = []
        func renderer(_ r: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime t: TimeInterval) {
            lock.lock(); stamps.append(CACurrentMediaTime()); lock.unlock()
        }
        func reset() { lock.lock(); stamps = []; lock.unlock() }
        /// Frame intervals in ms.
        var intervals: [Double] { lock.lock(); defer { lock.unlock() }; return zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 } }
    }

    /// Scroll-wheel zoom sweep at 120 Hz event rate; reports frame-time percentiles and frames over 25 ms (dropped at 60 fps).
    private static func zoomSweep(stage: Stage, log: FrameLog, seconds: Double) -> (p50: Double, p95: Double, max: Double, dropped: Int, frames: Int) {
        log.reset()
        let t0 = Date()
        let tm = Timer(timeInterval: 1.0 / 120, repeats: true) { _ in
            let k = Date().timeIntervalSince(t0)
            MainActor.assumeIsolated { stage.scrollZoom(delta: CGFloat(4 * sin(k * 2 * .pi / 2.5))) }
        }
        RunLoop.main.add(tm, forMode: .common)
        RunLoop.main.run(until: t0.addingTimeInterval(seconds))
        tm.invalidate()
        let iv = log.intervals
        return (percentile(iv, 0.5), percentile(iv, 0.95), iv.max() ?? 0, iv.filter { $0 > 25 }.count, iv.count + 1)
    }

    static func run() -> Bool {
        if CommandLine.arguments.contains("--perf-live") { return live() }
        let explicit = CommandLine.arguments.contains("--perf-agents")
        let counts = explicit ? [Int(arg("--perf-agents", 8))] : [8, 24], seconds = arg("--perf-seconds", 3)
        var lim = Limits()
        lim.tickMs = env("PERF_MAX_TICK_MS", lim.tickMs); lim.renderMs = env("PERF_MAX_RENDER_MS", lim.renderMs)
        lim.cpuPct = env("PERF_MAX_CPU_PCT", lim.cpuPct); lim.memGrowthMB = env("PERF_MAX_MEM_GROWTH_MB", lim.memGrowthMB)
        lim.memMB = env("PERF_MAX_MEM_MB", lim.memMB)
        print("perf: agents \(counts), \(seconds)s per theme, 30 fps paced")
        var probe: [WeakStage] = []
        var ok = true
        var simT = 1000.0
        let dt = 1.0 / 30
        for agents in counts { for theme in Theme.allCases {
            let stage = Stage()
            probe.append(WeakStage(stage))
            stage.sessions = sessions(agents: agents)
            stage.theme = theme
            for _ in 0..<60 { autoreleasepool { stage.tick(t: simT, render: true) }; simT += dt }   // warm-up: build scene, spawn actors
            _ = stage.snapshot(width: 636, height: 358)
            let mem0 = footprintMB()
            var ticks: [Double] = [], renders: [Double] = []
            let wall0 = Date(), cpu0 = cpuSeconds()
            var frame = 0
            while Date().timeIntervalSince(wall0) < seconds {
                let frameStart = Date()
                let a = DispatchTime.now().uptimeNanoseconds
                stage.tick(t: simT, render: true); simT += dt
                ticks.append(Double(DispatchTime.now().uptimeNanoseconds - a) / 1e6)
                frame += 1
                if frame % 10 == 0 {
                    let b = DispatchTime.now().uptimeNanoseconds
                    autoreleasepool { _ = stage.snapshot(width: 636, height: 358) }
                    renders.append(Double(DispatchTime.now().uptimeNanoseconds - b) / 1e6)
                }
                let left = dt - Date().timeIntervalSince(frameStart)
                if left > 0 { RunLoop.main.run(until: Date().addingTimeInterval(left)) }
            }
            let wall = Date().timeIntervalSince(wall0)
            // Rendering is sampled on every 10th frame, so cpu reflects a 30 fps tick plus a 3 fps offscreen render.
            let cpuPct = (cpuSeconds() - cpu0) / wall * 100
            let tickP95 = percentile(ticks, 0.95), renderP95 = percentile(renders, 0.95)
            let mem = footprintMB(), growth = mem - mem0
            var fails: [String] = []
            if tickP95 > lim.tickMs { fails.append("tick p95 \(fmt(tickP95)) ms > \(fmt(lim.tickMs))") }
            if !renders.isEmpty, renderP95 > lim.renderMs { fails.append("render p95 \(fmt(renderP95)) ms > \(fmt(lim.renderMs))") }
            if cpuPct > lim.cpuPct { fails.append("cpu \(fmt(cpuPct))% > \(fmt(lim.cpuPct))%") }
            if growth > lim.memGrowthMB { fails.append("memory grew \(fmt(growth)) MB > \(fmt(lim.memGrowthMB))") }
            if mem > lim.memMB { fails.append("memory \(fmt(mem)) MB > \(fmt(lim.memMB))") }
            print("perf \(agents)a \(theme.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) tick p95 \(fmt(tickP95)) ms  render p95 \(renders.isEmpty ? "n/a" : fmt(renderP95)) ms  cpu \(fmt(cpuPct))%  mem \(fmt(mem)) MB (+\(fmt(growth)))  \(fails.isEmpty ? "ok" : "FAIL")")
            for f in fails { print("  FAIL \(theme.rawValue): \(f)") }
            if !fails.isEmpty { ok = false }
        } }
        print("PROBE alive stages \(probe.filter { $0.s != nil }.count) of \(probe.count)")
        if !explicit { ok = cycle(&simT) && ok }
        print(ok ? "perf self-test OK" : "perf self-test FAILED")
        return ok
    }

    struct SceneCounts { var nodes = 0, geometries = 0, materials = 0, lights = 0, particles = 0, actions = 0 }
    static func counts(_ scene: SCNScene) -> SceneCounts {
        var c = SceneCounts()
        var g = Set<ObjectIdentifier>(), m = Set<ObjectIdentifier>()
        scene.rootNode.enumerateHierarchy { n, _ in
            c.nodes += 1
            if let geo = n.geometry { g.insert(ObjectIdentifier(geo)); geo.materials.forEach { m.insert(ObjectIdentifier($0)) } }
            if n.light != nil { c.lights += 1 }
            c.particles += n.particleSystems?.count ?? 0
            if n.hasActions { c.actions += 1 }
        }
        c.geometries = g.count; c.materials = m.count
        return c
    }

    /// One long-lived stage cycled through every theme: switch latency, scene size and memory stability.
    private static func cycle(_ simT: inout Double) -> Bool {
        let agents = 8, dt = 1.0 / 30
        print("cycle: \(agents) agents, one stage, themes x3, then spawn/leave x20")
        let stage = Stage()
        stage.sessions = sessions(agents: agents)
        var switchMs: [Theme: [Double]] = [:]
        var mem0 = 0.0
        var sizes: [Theme: SceneCounts] = [:]
        for round in 0..<Int(env("PERF_CYCLE_ROUNDS", 3)) {
            for theme in Theme.allCases {
                let a = DispatchTime.now().uptimeNanoseconds
                autoreleasepool { stage.theme = theme; stage.tick(t: simT, render: true); simT += dt }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - a) / 1e6
                for _ in 0..<30 { autoreleasepool { stage.tick(t: simT, render: true) }; simT += dt }
                autoreleasepool { _ = stage.snapshot(width: 636, height: 358) }
                if round > 0 { switchMs[theme, default: []].append(ms) }
                if round == 0 { sizes[theme] = counts(stage.scene) }
            }
            if round == 0 { mem0 = footprintMB() }
            if ProcessInfo.processInfo.environment["MEMTRACE"] != nil { print("  round \(round) \(fmt(footprintMB()))") }
        }
        for theme in Theme.allCases {
            let c = sizes[theme]!, v = switchMs[theme] ?? []
            print("cycle \(theme.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) switch \(fmt(v.max() ?? 0)) ms  nodes \(c.nodes) geoms \(c.geometries) mats \(c.materials) lights \(c.lights) particles \(c.particles) actioned \(c.actions)")
        }
        let grew = footprintMB() - mem0
        let mem1 = footprintMB()
        let full = stage.sessions
        for i in 0..<Int(env("PERF_SPAWN_CYCLES", 20)) {
            autoreleasepool {
                stage.sessions = i % 2 == 0 ? [] : full
                for _ in 0..<15 { stage.tick(t: simT, render: true); simT += dt }
                _ = stage.snapshot(width: 636, height: 358)
            }
        }
        let growth = footprintMB() - mem0
        if ProcessInfo.processInfo.environment["MEMTRACE"] != nil { print("  spawn/leave grew \(fmt(footprintMB() - mem1)) MB") }
        let lim = env("PERF_MAX_CYCLE_GROWTH_MB", 150), swLim = env("PERF_MAX_SWITCH_MS", 400)
        let worst = switchMs.values.flatMap { $0 }.max() ?? 0
        var ok = true
        if growth > lim { print("  FAIL cycle: memory grew \(fmt(growth)) MB > \(fmt(lim)) after theme cycling + spawn/leave"); ok = false }
        if worst > swLim { print("  FAIL cycle: theme switch \(fmt(worst)) ms > \(fmt(swLim))"); ok = false }
        // Reused light nodes must end up identical to those of a freshly built stage.
        func lightSig(_ st: Stage) -> [String] {
            var out: [String] = []
            st.scene.rootNode.enumerateHierarchy { n, _ in
                if let l = n.light { out.append("\(l.type.rawValue) \(l.color) \(Int(l.intensity)) \(l.castsShadow) \(l.shadowSampleCount) \(l.attenuationEndDistance) \(n.position) \(n.eulerAngles)") }
            }
            return out
        }
        for theme in [Theme.wizard, .space, .farm] {
            stage.theme = theme; stage.tick(t: simT, render: true)
            let fresh = Stage(); fresh.theme = theme; fresh.tick(t: simT, render: true)
            if lightSig(stage) != lightSig(fresh) { print("  FAIL cycle: lights differ from a fresh stage for \(theme.rawValue)"); ok = false }
        }
        print("cycle memory growth after rounds 2-3 + spawn/leave: \(fmt(growth)) MB, worst switch \(fmt(worst)) ms")
        return ok
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}
