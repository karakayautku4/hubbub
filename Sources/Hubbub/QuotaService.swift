import Foundation

@MainActor
final class QuotaService: ObservableObject {
    @Published var quota: Quota?
    /// Human-readable problem; when `quota` is non-nil the data shown is stale.
    @Published var error: String?
    @Published var isStale = false
    /// True when no GitHub token is available; the quota bar is hidden instead of showing errors.
    @Published var noToken = false
    @Published var forecast: String?
    private var token: String?
    private var timer: Timer?
    private var backoffUntil: Date?
    private static let cacheKey = "cachedQuota"

    init() {
        if let d = UserDefaults.standard.dictionary(forKey: Self.cacheKey) {
            func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            quota = Quota(entitlement: num("entitlement"), remaining: num("remaining"),
                          percentRemaining: num("percentRemaining"), used: num("used"),
                          resetDate: d["resetDate"] as? String ?? "", plan: d["plan"] as? String ?? "",
                          unlimited: d["unlimited"] as? Bool ?? false)
            forecast = quota.flatMap { UsageHistory.shared.forecast($0) }
            isStale = true
        }
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        var clearToken = false
        /// The undocumented endpoint changed or disappeared: stop showing numbers that may be wrong.
        var apiChanged = false
        var errorDescription: String? { message }
    }

    func refresh() {
        if let b = backoffUntil, b > Date() { return }
        guard ProviderRegistry.shared.isEnabled("copilot"), CopilotQuotaAPI.isEnabled else { return }
        Task {
            do {
                if token == nil { token = await Self.loadToken() }
                guard let token else {
                    noToken = true
                    error = nil
                    backoffUntil = Date().addingTimeInterval(600)
                    return
                }
                noToken = false
                var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
                req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 20
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    let limited = http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
                    switch http.statusCode {
                    case 429, 403 where limited:
                        let wait = Double(http.value(forHTTPHeaderField: "retry-after") ?? "") ?? 300
                        backoffUntil = Date().addingTimeInterval(min(max(wait, 60), 900))
                        throw Failure(message: "GitHub rate limit reached – retrying later")
                    case 401, 403:
                        self.token = nil
                        throw Failure(message: "Sign in again with `gh auth login`")
                    case 200..<300: break
                    case 404, 410, 422:
                        throw Failure(message: CopilotQuotaAPI.unavailableMessage, apiChanged: true)
                    default: throw Failure(message: "GitHub API error (HTTP \(http.statusCode))")
                    }
                }
                guard let q = CopilotQuotaAPI.parse(data) else {
                    throw Failure(message: CopilotQuotaAPI.unavailableMessage, apiChanged: true)
                }
                quota = q
                error = nil
                isStale = false
                backoffUntil = nil
                UserDefaults.standard.set(["entitlement": q.entitlement, "remaining": q.remaining,
                                           "percentRemaining": q.percentRemaining, "used": q.used,
                                           "resetDate": q.resetDate, "plan": q.plan, "unlimited": q.unlimited],
                                          forKey: Self.cacheKey)
                UsageHistory.shared.record(q)
                forecast = UsageHistory.shared.forecast(q)
                Notifier.shared.quota(q)
            } catch {
                if let f = error as? Failure {
                    self.error = f.message
                    if f.apiChanged {
                        // Local-only fallback: drop the cached numbers, keep sessions/tokens working, and retry rarely.
                        quota = nil
                        forecast = nil
                        isStale = false
                        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
                        backoffUntil = Date().addingTimeInterval(3600)
                        return
                    }
                } else if error is URLError || (error as NSError).domain == NSURLErrorDomain {
                    self.error = quota != nil ? "Offline – showing last known data" : "Offline – no data yet"
                } else {
                    self.error = error.localizedDescription
                }
                isStale = quota != nil
            }
        }
    }

    /// GUI apps get a minimal PATH, so ask the user's login shell where a tool lives (nix, asdf, custom prefixes).
    private nonisolated static func shellLookup(_ tool: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v \(tool)"]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = Pipe(); p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let end = Date().addingTimeInterval(3)
        while p.isRunning && Date() < end { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return out.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: out) ? out : nil
    }

    private static func loadToken() async -> String? {
        if let t = ProcessInfo.processInfo.environment["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"] { return t }
        return await Task.detached { () -> String? in
            let home = NSHomeDirectory()
            var candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/opt/local/bin/gh", "/usr/bin/gh", home + "/.local/bin/gh", home + "/bin/gh"]
            if let found = Self.shellLookup("gh") { candidates.insert(found, at: 0) }
            for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = ["auth", "token"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do { try p.run() } catch { continue }
                let out = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus == 0,
                   let s = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    return s
                }
            }
            return nil
        }.value
    }
}

/// The Copilot quota lookup uses an undocumented GitHub endpoint that can change without notice (see docs/QUOTA.md).
enum CopilotQuotaAPI {
    static let unavailableMessage = "Quota unavailable (API changed). Sessions still work locally."
    static let docsURL = URL(string: "https://github.com/karakayautku4/hubbub/blob/main/docs/QUOTA.md")!
    /// Kill switch: `defaults write <bundle id> copilotQuotaEnabled -bool NO` disables the call entirely.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "copilotQuotaEnabled") as? Bool ?? true }

    static func parse(_ data: Data) -> Quota? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let snaps = root["quota_snapshots"] as? [String: Any],
              let p = snaps["premium_interactions"] as? [String: Any] else { return nil }
        func num(_ k: String) -> Double { (p[k] as? NSNumber)?.doubleValue ?? 0 }
        return Quota(entitlement: num("entitlement"), remaining: num("quota_remaining"),
                     percentRemaining: num("percent_remaining"), used: num("credits_used"),
                     resetDate: root["quota_reset_date"] as? String ?? "",
                     plan: root["copilot_plan"] as? String ?? "",
                     unlimited: p["unlimited"] as? Bool ?? false)
    }
}
