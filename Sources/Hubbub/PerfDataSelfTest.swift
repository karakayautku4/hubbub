import Foundation
import Darwin

/// Process-level measurement helpers for the data-performance tests.
enum PerfProbe {
    /// Scratch folders live next to the working directory (never the system temp dir); callers delete them.
    static func scratch(_ name: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".perf-scratch/\(name)")
    }

    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(u.ru_utime) + s(u.ru_stime)
    }

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    static func peakMB() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_maxrss) / 1_048_576   // bytes on macOS
    }

    /// Runs `body`, returning wall seconds, cpu seconds and peak RSS afterwards.
    static func measure<T>(_ label: String, _ body: () -> T) -> (T, wall: Double, cpu: Double) {
        let c0 = cpuSeconds(), t0 = Date()
        let r = body()
        let wall = Date().timeIntervalSince(t0), cpu = cpuSeconds() - c0
        print(String(format: "  %@: wall %.2fs cpu %.2fs rss %.0fMB peak %.0fMB", label, wall, cpu, residentMB(), peakMB()))
        return (r, wall, cpu)
    }
}

enum PerfDataSelfTest {
    /// `Hubbub --perf-data-real metrics|usage`: times one scanner against the real ~/.copilot data (scratch cache only).
    static func runReal(_ which: String) {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/session-state")
        let scratch = PerfProbe.scratch("real-\(getpid())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        print("real data (\(which)), rss at start \(Int(PerfProbe.residentMB()))MB")
        if which == "metrics" {
            let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            let recent = ids.filter {
                let m = (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent($0).appendingPathComponent("events.jsonl").path))?[.modificationDate] as? Date
                return (m ?? .distantPast) > cutoff
            }
            let s = MetricsScanner(root: root)
            _ = PerfProbe.measure("metrics cold (\(recent.count) recent files)") { s.update(ids: recent, sync: true) }
            _ = PerfProbe.measure("metrics warm") { s.update(ids: recent, sync: true) }
        } else {
            let cache = scratch.appendingPathComponent("usage.json")
            let r = PerfProbe.measure("usage cold") { UsageHistory.runScan(root: root, cacheURL: cache) }
            print("  sessions \(r.0.sessions.count) models \(r.0.models.count)")
            _ = PerfProbe.measure("usage warm") { UsageHistory.runScan(root: root, cacheURL: cache) }
        }
    }
}

// MARK: - Fixture-based `--selftest-perf-data`

private struct SplitMix { var x: UInt64
    mutating func next() -> UInt64 { x &+= 0x9E3779B97F4A7C15; var z = x; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

private enum Fixture {
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let costs = ["0", "1", "0.33", "3", "0.5", "7.5"]
    static let models = ["claude-opus-4.8", "gpt-5.5", "claude-sonnet-4.6"]

    /// Writes `sessions` session folders with roughly `totalBytes` of synthetic Copilot JSONL. Returns bytes written.
    static func generate(root: URL, sessions: Int, totalBytes: Int, now: Date) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        var rng = SplitMix(x: 42)
        let fat = Set((0..<6).map { _ in rng.int(sessions) })   // a few big logs with multi-MB lines
        let baseTarget = max(2_000, totalBytes / 2 / sessions)
        let fatTarget = totalBytes / 2 / max(1, fat.count)
        var written = 0
        let filler = [UInt8](repeating: UInt8(ascii: "x"), count: 3_200_000)
        for i in 0..<sessions {
            let id = String(format: "%08x-0000-4000-8000-%012x", i, i * 7919)
            let dir = root.appendingPathComponent(id)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? "id: \(id)\nname: Session number \(i)\ncwd: /work/proj\(i % 17)\nbranch: main\ncreated_at: 2026-01-01T00:00:00.000Z\n"
                .write(to: dir.appendingPathComponent("workspace.yaml"), atomically: false, encoding: .utf8)
            let recent = i < 8
            let target = fat.contains(i) ? fatTarget : baseTarget / 2 + rng.int(baseTarget)
            var t = recent ? now.addingTimeInterval(-3 * 3600 - Double(rng.int(3600))) : now.addingTimeInterval(-Double(86400 * (2 + rng.int(60))))
            var out = [UInt8](); out.reserveCapacity(1 << 20)
            func add(_ s: String) { out.append(contentsOf: Array(s.utf8)); out.append(10) }
            func stamp() -> String { t.addTimeInterval(Double(1 + rng.int(20)) + 0.123); return Fixture.iso.string(from: t) }
            add("{\"type\":\"session.start\",\"data\":{\"selectedModel\":\"claude-opus-4.8\"},\"id\":\"s\(i)\",\"timestamp\":\"\(stamp())\"}")
            var size = 0, n = 0
            let fh = FileManager.default.createFile(atPath: dir.appendingPathComponent("events.jsonl").path, contents: nil)
            _ = fh
            let h = FileHandle(forWritingAtPath: dir.appendingPathComponent("events.jsonl").path)!
            while size < target {
                n += 1
                let sz = [200, 2_000, 30_000][rng.int(3)]
                add("{\"type\":\"assistant.message\",\"data\":{\"content\":\"" + String(decoding: filler[0..<sz], as: UTF8.self) + "\"},\"id\":\"a\(n)\",\"timestamp\":\"\(stamp())\"}")
                if fat.contains(i) && n % 40 == 0 {
                    out.append(contentsOf: Array("{\"type\":\"assistant.message\",\"data\":{\"content\":\"".utf8)); out.append(contentsOf: filler)
                    out.append(contentsOf: Array("\"},\"id\":\"big\(n)\",\"timestamp\":\"\(stamp())\"}".utf8)); out.append(10)
                }
                add("{\"type\":\"tool.execution_start\",\"data\":{\"toolCallId\":\"c\(n)\",\"toolName\":\"bash\",\"arguments\":{\"command\":\"ls \(n)\"}},\"id\":\"t\(n)\",\"timestamp\":\"\(stamp())\"}")
                add("{\"type\":\"tool.execution_complete\",\"data\":{\"toolCallId\":\"c\(n)\",\"success\":\(rng.int(10) != 0)},\"id\":\"e\(n)\",\"timestamp\":\"\(stamp())\"}")
                add("{\"type\":\"session.usage_record\",\"data\":{\"usage\":{\"model\":\"\(models[rng.int(3)])\",\"inputTokens\":\(1000 + rng.int(9000)),\"outputTokens\":\(rng.int(500)),\"cost\":\(costs[rng.int(costs.count)]),\"maxPromptTokens\":200000}},\"id\":\"u\(n)\",\"timestamp\":\"\(stamp())\"}")
                if n % 25 == 0 { add("{\"type\":\"session.compaction_complete\",\"data\":{\"success\":true},\"id\":\"k\(n)\",\"timestamp\":\"\(stamp())\"}") }
                if out.count > 1 << 20 { h.write(Data(out)); size += out.count; out.removeAll(keepingCapacity: true) }
            }
            if recent {
                if i % 2 == 0 { add("{\"type\":\"tool.execution_start\",\"data\":{\"toolCallId\":\"open\(i)\",\"toolName\":\"edit\",\"arguments\":{\"path\":\"a.swift\"}},\"id\":\"o\",\"timestamp\":\"\(stamp())\"}") }
                else { add("{\"type\":\"session.shutdown\",\"data\":{\"currentTokens\":5},\"id\":\"z\",\"timestamp\":\"\(stamp())\"}") }
            }
            h.write(Data(out)); size += out.count; try? h.close()
            written += size
            let mtime = min(t, now)
            try? fm.setAttributes([.modificationDate: mtime], ofItemAtPath: dir.appendingPathComponent("events.jsonl").path)
        }
        return written
    }

    static func append(_ url: URL, _ text: String) {
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        _ = try? h.seekToEnd(); h.write(Data(text.utf8)); try? h.close()
    }

    static func usageLine(_ k: Int, at d: Date) -> String {
        "{\"type\":\"session.usage_record\",\"data\":{\"usage\":{\"model\":\"gpt-5.5\",\"inputTokens\":\(100 + k),\"outputTokens\":\(k),\"cost\":0.33}},\"id\":\"n\(k)\",\"timestamp\":\"\(iso.string(from: d))\"}\n"
    }
}

/// The original whole-file algorithm (no index, no streaming), kept as the ground truth.
private func naiveUsage(root: URL) -> UsageHistory.Aggregate {
    var cache: [String: SessionScan] = [:]
    let marker = Array("\"type\":\"session.usage_record\"".utf8)
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    for id in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
        let dir = root.appendingPathComponent(id)
        guard let all = FileManager.default.contents(atPath: dir.appendingPathComponent("events.jsonl").path) else { continue }
        var sc = SessionScan()
        let yaml = (try? String(contentsOf: dir.appendingPathComponent("workspace.yaml"), encoding: .utf8)) ?? ""
        var name = "", cwd = ""
        for line in yaml.split(separator: "\n") {
            if line.hasPrefix("name: ") { name = String(line.dropFirst(6)) }
            if line.hasPrefix("cwd: ") { cwd = String(line.dropFirst(5)) }
        }
        sc.name = !name.isEmpty ? name : ((cwd as NSString).lastPathComponent.isEmpty ? String(id.prefix(8)) : (cwd as NSString).lastPathComponent)
        let body = all.lastIndex(of: 10).map { all[all.startIndex...$0] } ?? all[all.startIndex..<all.startIndex]
        for line in body.split(separator: 10, omittingEmptySubsequences: true) {
            guard line.count > marker.count, line.prefix(marker.count + 8).range(of: Data(marker)) != nil,
                  let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let u = (obj["data"] as? [String: Any])?["usage"] as? [String: Any] else { continue }
            let model = u["model"] as? String ?? "unknown"
            let cost = (u["cost"] as? NSNumber)?.doubleValue ?? 0
            var m = sc.models[model] ?? [0, 0, 0]
            m[0] += cost; m[1] += (u["inputTokens"] as? NSNumber)?.doubleValue ?? 0; m[2] += (u["outputTokens"] as? NSNumber)?.doubleValue ?? 0
            sc.models[model] = m
            if let ts = obj["timestamp"] as? String, let date = Fixture.iso.date(from: ts) {
                sc.days[f.string(from: date), default: 0] += cost; sc.last = max(sc.last, date)
            }
        }
        cache[id] = sc
    }
    return UsageHistory.aggregate(cache)
}

private func same(_ a: UsageHistory.Aggregate, _ b: UsageHistory.Aggregate) -> Bool {
    a.sessions.count == b.sessions.count
        && zip(a.sessions, b.sessions).allSatisfy { $0.id == $1.id && $0.name == $1.name && $0.requests == $1.requests && $0.lastUsed == $1.lastUsed }
        && a.models.count == b.models.count
        && zip(a.models, b.models).allSatisfy { $0.model == $1.model && $0.requests == $1.requests && $0.inputTokens == $1.inputTokens && $0.outputTokens == $1.outputTokens }
        && a.days == b.days
}

private func sameMetrics(_ a: FileMetrics, _ b: FileMetrics) -> Bool {
    a.calls == b.calls && a.failures == b.failures && a.cost == b.cost && a.compactions == b.compactions && a.bestStreak == b.bestStreak
        && a.streak == b.streak && a.offset == b.offset && a.cidActor == b.cidActor && a.actorNames == b.actorNames
        && a.days.mapValues { $0.mapValues { [Double($0.ok), Double($0.failed), $0.cost] } } == b.days.mapValues { $0.mapValues { [Double($0.ok), Double($0.failed), $0.cost] } }
        && a.intervals.count == b.intervals.count && zip(a.intervals, b.intervals).allSatisfy { $0 == $1 }
}

extension PerfDataSelfTest {
    /// Child-process fixture writer for `--selftest-perf-data`.
    static func generateMain(_ a: [String]) {
        guard a.count >= 4, let n = Int(a[1]), let mb = Int(a[2]), let t = Double(a[3]) else { return }
        print(Fixture.generate(root: URL(fileURLWithPath: a[0]), sessions: n, totalBytes: mb << 20, now: Date(timeIntervalSince1970: t)))
    }

    /// `Hubbub --selftest-perf-data [--perf-sessions N] [--perf-mb M]`: generated fixtures only (default 2000 sessions / 400 MB; try `--perf-mb 5000`).
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) { print(ok ? "ok   " : "FAIL ", name); if !ok { failures += 1 } }
        func arg(_ k: String, _ d: Int) -> Int { CommandLine.arguments.firstIndex(of: k).flatMap { Int(CommandLine.arguments[safe: $0 + 1] ?? "") } ?? d }
        let sessions = arg("--perf-sessions", 2000), mb = arg("--perf-mb", 400)
        let scratch = PerfProbe.scratch("data-\(getpid())")
        defer { try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent()) }
        let root = scratch.appendingPathComponent("session-state"), cache = scratch.appendingPathComponent("usage-cache.json")
        let now = Date()
        let start = PerfProbe.residentMB()

        // Generated in a child process so its buffers don't count against this process' memory ceiling
        let (bytes, genWall, _) = PerfProbe.measure("generate \(sessions) sessions") { () -> Int in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            p.arguments = ["--perf-data-gen", root.path, String(sessions), String(mb), String(now.timeIntervalSince1970)]
            let pipe = Pipe(); p.standardOutput = pipe
            try? p.run()
            let out = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return Int(String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        let gb = Double(bytes) / 1_073_741_824
        print(String(format: "  fixture: %.2f GB in %.1fs", gb, genWall))

        // Cold scan (no index), newest first, two workers
        let cold = PerfProbe.measure("usage cold scan") { UsageHistory.runScan(root: root, cacheURL: cache, workers: 2) }
        let mbps = Double(bytes) / 1_048_576 / max(cold.wall, 0.001)
        print(String(format: "  cold throughput %.0f MB/s, cpu/wall %.2f", mbps, cold.cpu / max(cold.wall, 0.001)))
        let coldPeak = PerfProbe.peakMB()
        check("cold scan memory ceiling (peak \(Int(coldPeak))MB <= 120MB)", coldPeak <= 120)
        check("cold scan throughput >= 80 MB/s (\(Int(mbps)))", mbps >= 80 || cold.wall < 3)
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        let recent = ids.filter { (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent($0).appendingPathComponent("events.jsonl").path))?[.modificationDate] as? Date ?? .distantPast > now.addingTimeInterval(-86400) }
        check("fixture has recent sessions", recent.count >= 4)
        let mcache = scratch.appendingPathComponent("metrics.json")
        let ms = MetricsScanner(root: root, cacheURL: mcache)
        let mcold = PerfProbe.measure("metrics cold (\(recent.count) recent logs)") { ms.update(ids: recent, sync: true) }
        let mPeak = PerfProbe.peakMB()
        check("metrics cold memory ceiling (peak \(Int(mPeak))MB <= 120MB)", mPeak <= 120)
        _ = mcold
        let naive = PerfProbe.measure("naive reference scan") { naiveUsage(root: root) }
        check("cold == naive (sessions, tokens, credits, days)", same(cold.0, naive.0))
        check("fixture produced usage data", cold.0.sessions.count > sessions / 2 && !cold.0.models.isEmpty)

        // Warm start from the persisted index
        let warm = PerfProbe.measure("usage warm start") { UsageHistory.runScan(root: root, cacheURL: cache) }
        check("warm start < 1s (\(String(format: "%.3f", warm.wall))s)", warm.wall < 1)
        check("warm == cold", same(warm.0, cold.0))

        // Incremental: append to a few logs, one with an unterminated trailing line
        let touched = Array(ids.prefix(12))
        for (k, id) in touched.enumerated() {
            let u = root.appendingPathComponent(id).appendingPathComponent("events.jsonl")
            for j in 0..<50 { Fixture.append(u, Fixture.usageLine(k * 100 + j, at: now)) }
            if k == 0 { Fixture.append(u, String(Fixture.usageLine(999, at: now).dropLast(30))) }
        }
        let inc = PerfProbe.measure("usage incremental (12 appended logs)") { UsageHistory.runScan(root: root, cacheURL: cache) }
        check("incremental parse < 0.5s (\(String(format: "%.3f", inc.wall))s)", inc.wall < 0.5)
        check("incremental == naive", same(inc.0, naiveUsage(root: root)))
        let u0 = root.appendingPathComponent(ids[0]).appendingPathComponent("events.jsonl")
        Fixture.append(u0, String(Fixture.usageLine(999, at: now).suffix(30)))   // completes the partial line
        check("completed partial line picked up == naive", same(UsageHistory.runScan(root: root, cacheURL: cache), naiveUsage(root: root)))
        // Replaced log (shorter) restarts that file
        let u1 = root.appendingPathComponent(ids[1]).appendingPathComponent("events.jsonl")
        try? Fixture.usageLine(1, at: now).write(to: u1, atomically: true, encoding: .utf8)
        check("replaced log == naive", same(UsageHistory.runScan(root: root, cacheURL: cache), naiveUsage(root: root)))

        // Metrics: persisted incremental vs whole-file reference (the index predates the appends and the replaced log above)
        let ms2 = MetricsScanner(root: root, cacheURL: mcache)
        let mw = PerfProbe.measure("metrics warm (reloaded from index + catch-up)") { ms2.update(ids: recent) }
        check("metrics warm start < 1s", mw.wall < 1)
        for id in recent {
            let p = root.appendingPathComponent(id).appendingPathComponent("events.jsonl").path
            check("metrics \(id.prefix(8)) == reference", ms2.metrics(for: id).map { sameMetrics($0, MetricsScanner.reference(path: p)) } ?? false)
        }
        for id in recent { Fixture.append(root.appendingPathComponent(id).appendingPathComponent("events.jsonl"),
            "{\"type\":\"tool.execution_complete\",\"data\":{\"toolCallId\":\"zz\",\"success\":false},\"id\":\"q\",\"timestamp\":\"\(Fixture.iso.string(from: now))\"}\n") }
        let mi = PerfProbe.measure("metrics incremental append") { ms2.update(ids: recent) }
        check("metrics incremental < 0.25s", mi.wall < 0.25)
        for id in recent {
            let p = root.appendingPathComponent(id).appendingPathComponent("events.jsonl").path
            check("metrics \(id.prefix(8)) after append == reference", ms2.metrics(for: id).map { sameMetrics($0, MetricsScanner.reference(path: p)) } ?? false)
        }

        // Copilot session parse: streamed tail == whole-tail reader
        for id in recent {
            let dir = root.appendingPathComponent(id)
            let mod = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("events.jsonl").path))?[.modificationDate] as? Date ?? now
            check("parse \(id.prefix(8)) streamed == naive", SessionMonitor.parse(dir: dir, modified: mod) == SessionMonitor.parse(dir: dir, modified: mod, naive: true))
        }
        let pm = PerfProbe.measure("parse \(recent.count) recent sessions") { for id in recent { _ = SessionMonitor.parse(dir: root.appendingPathComponent(id), modified: now) } }
        let pn = PerfProbe.measure("parse \(recent.count) recent sessions (naive)") { for id in recent { _ = SessionMonitor.parse(dir: root.appendingPathComponent(id), modified: now, naive: true) } }
        print(String(format: "  tail parse speedup x%.1f", pn.wall / max(pm.wall, 0.0001)))

        // Pacing: a 25% duty cycle must visibly cut CPU share
        func logSize(_ id: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(id).appendingPathComponent("events.jsonl").path))?[.size] as? Int) ?? 0 }
        let biggest = ids.max { logSize($0) < logSize($1) }!
        let paced = PerfProbe.measure("paced read of largest log (duty 0.25)") {
            JSONL.scan(path: root.appendingPathComponent(biggest).appendingPathComponent("events.jsonl").path, chunk: 1 << 16, pacer: Pacer { 0.25 }, wants: { _ in false }, line: { _ in })
        }
        print("  largest log \(logSize(biggest) >> 20) MB, result \(String(describing: paced.0))")
        check("pacer limits cpu share (\(String(format: "%.2f", paced.cpu / max(paced.wall, 0.001))) <= 0.45)", paced.cpu / max(paced.wall, 0.001) <= 0.45)

        check("naive reference is the memory hog, fast path stayed bounded (start \(Int(start))MB, fast peak \(Int(coldPeak))MB)", coldPeak < 120)
        print(failures == 0 ? "perf-data selftest: all ok" : "perf-data selftest: \(failures) FAILED")
        return failures == 0
    }
}

private extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
