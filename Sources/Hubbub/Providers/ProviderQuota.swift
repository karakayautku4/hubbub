import Foundation
import SQLite3
import SwiftUI

/// One usage window of a provider (e.g. "5 hours", "Weekly", "Premium requests").
struct QuotaWindow: Equatable {
    var label: String
    /// 0...100; nil when the provider reports usage without a limit.
    var percentUsed: Double?
    var resetsAt: Date?
    var detail: String?
}

struct ProviderQuota: Equatable {
    var windows: [QuotaWindow]
    var plan: String = ""
    var fetchedAt = Date()
    var maxPercent: Double? { windows.compactMap(\.percentUsed).max() }
}

/// Credentials for one provider's own usage endpoint. Held in memory only, never logged or persisted.
struct QuotaCredential: Sendable {
    var token: String
    var extra: String = ""
    var expires: Date?
}

enum QuotaFailure: Error, Equatable {
    case notAvailable(String)    // no local credentials / access denied
    case unauthorized            // endpoint rejected the token
    case rateLimited(TimeInterval)
    case http(Int)
    case unexpected
    case offline
}

/// Per-provider remote usage endpoints. Cursor, Claude Code and Codex endpoints are undocumented/internal
/// and may change without notice; parsing is defensive and any mismatch surfaces as "Unexpected response".
enum QuotaEndpoints {
    static let ids = ["cursor", "claude", "codex"]

    static func hasAPI(_ id: String) -> Bool { ids.contains(id) }

    /// What is read and where it is sent, shown next to the opt-in toggle.
    static func explanation(_ id: String) -> String {
        switch id {
        case "cursor": "Reads Cursor's access token from its local state.vscdb and sends it only to cursor.com."
        case "claude": "Reads the Claude Code login (Keychain or ~/.claude/.credentials.json) and sends it only to api.anthropic.com."
        case "codex": "Reads the token in ~/.codex/auth.json and sends it only to chatgpt.com."
        default: "No public usage API – only local token totals are shown."
        }
    }

    // MARK: Parsing (pure, fixture-tested)

    static func parseClaude(_ data: Data) -> ProviderQuota? {
        guard let root = obj(data) else { return nil }
        let spec: [(String, String)] = [("five_hour", "5 hours"), ("seven_day", "Weekly"), ("seven_day_opus", "Weekly Opus"), ("seven_day_sonnet", "Weekly Sonnet")]
        var out: [QuotaWindow] = []
        for (k, label) in spec {
            guard let w = root[k] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            out.append(QuotaWindow(label: label, percentUsed: clamp(u), resetsAt: (w["resets_at"] as? String).flatMap(isoDate)))
        }
        return out.isEmpty ? nil : ProviderQuota(windows: out)
    }

    static func parseCodex(_ data: Data, now: Date = Date()) -> ProviderQuota? {
        guard let root = obj(data) else { return nil }
        var out: [QuotaWindow] = []
        func add(_ w: Any?, fallback: String) {
            guard let w = w as? [String: Any], let u = (w["used_percent"] as? NSNumber)?.doubleValue else { return }
            let secs = (w["limit_window_seconds"] as? NSNumber)?.doubleValue
            var reset: Date?
            if let at = (w["reset_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: at) }
            else if let after = (w["reset_after_seconds"] as? NSNumber)?.doubleValue { reset = now.addingTimeInterval(after) }
            out.append(QuotaWindow(label: secs.map(windowLabel) ?? fallback, percentUsed: clamp(u), resetsAt: reset))
        }
        let rl = root["rate_limit"] as? [String: Any]
        add(rl?["primary_window"], fallback: "Short window")
        add(rl?["secondary_window"], fallback: "Weekly")
        let plan = (root["plan_type"] as? String) ?? ""
        return out.isEmpty ? nil : ProviderQuota(windows: out, plan: plan)
    }

    static func parseCursor(_ data: Data) -> ProviderQuota? {
        guard let root = obj(data) else { return nil }
        var start: Date?
        if let s = root["startOfMonth"] as? String { start = isoDate(s) }
        let reset = start.flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        var out: [QuotaWindow] = []
        for (k, v) in root.sorted(by: { $0.key < $1.key }) {
            guard let m = v as? [String: Any] else { continue }
            let used = (m["numRequestsTotal"] as? NSNumber ?? m["numRequests"] as? NSNumber)?.doubleValue
            guard let used else { continue }
            let label = k == "gpt-4" ? "Premium requests" : k
            if let max = (m["maxRequestUsage"] as? NSNumber)?.doubleValue, max > 0 {
                out.append(QuotaWindow(label: label, percentUsed: clamp(used / max * 100), resetsAt: reset,
                                       detail: "\(Int(used)) / \(Int(max))"))
            } else if used > 0 {
                out.append(QuotaWindow(label: label, percentUsed: nil, resetsAt: reset, detail: "\(Int(used)) requests"))
            }
        }
        return out.isEmpty ? nil : ProviderQuota(windows: out)
    }

    /// `sub` of a JWT is "auth0|user_xxx"; Cursor's cookie wants the part after the pipe.
    static func cursorUserID(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b), let sub = obj(d)?["sub"] as? String, !sub.isEmpty else { return nil }
        return sub.split(separator: "|").last.map(String.init)
    }

    static func parseClaudeCredentials(_ data: Data, now: Date = Date()) -> QuotaCredential? {
        guard let o = obj(data)?["claudeAiOauth"] as? [String: Any], let t = o["accessToken"] as? String, !t.isEmpty else { return nil }
        let exp = (o["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return QuotaCredential(token: t, expires: exp)
    }

    static func parseCodexAuth(_ data: Data) -> QuotaCredential? {
        guard let o = obj(data)?["tokens"] as? [String: Any], let t = o["access_token"] as? String, !t.isEmpty else { return nil }
        return QuotaCredential(token: t, extra: o["account_id"] as? String ?? "")
    }

    private static func obj(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 100) }
    private static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    static func windowLabel(_ seconds: Double) -> String {
        let h = seconds / 3600
        if h < 48 { return "\(Int(h.rounded())) hours" }
        return h >= 24 * 6 && h <= 24 * 8 ? "Weekly" : "\(Int((h / 24).rounded())) days"
    }

    // MARK: Credentials (blocking; call off the main thread)

    static func loadCredential(_ id: String) -> QuotaCredential? {
        let home = ProviderKit.home
        switch id {
        case "claude":
            if let d = try? Data(contentsOf: home.appendingPathComponent(".claude/.credentials.json")), let c = parseClaudeCredentials(d) { return c }
            // Keychain through the system `security` tool; denial or absence simply yields nil.
            guard let out = run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 20) else { return nil }
            return parseClaudeCredentials(Data(out.utf8))
        case "codex":
            let dir = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
            return (try? Data(contentsOf: dir.appendingPathComponent("auth.json"))).flatMap(parseCodexAuth)
        case "cursor":
            let url = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            guard let jwt = readItem(url, "cursorAuth/accessToken"), let uid = cursorUserID(fromJWT: jwt) else { return nil }
            return QuotaCredential(token: jwt, extra: uid)
        default: return nil
        }
    }

    private static func readItem(_ url: URL, _ key: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key=?", -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(st) == SQLITE_ROW, let c = sqlite3_column_text(st, 0) else { return nil }
        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private static func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Network (each token goes only to its own provider host)

    static func request(_ id: String, _ c: QuotaCredential) -> URLRequest? {
        var r: URLRequest
        switch id {
        case "claude":
            r = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            r.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
            r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        case "codex":
            r = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            r.setValue("Bearer \(c.token)", forHTTPHeaderField: "Authorization")
            if !c.extra.isEmpty { r.setValue(c.extra, forHTTPHeaderField: "ChatGPT-Account-Id") }
        case "cursor":
            guard let q = c.extra.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://cursor.com/api/usage?user=\(q)") else { return nil }
            r = URLRequest(url: url)
            r.setValue("WorkosCursorSessionToken=\(c.extra)%3A%3A\(c.token)", forHTTPHeaderField: "Cookie")
        default: return nil
        }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.timeoutInterval = 20
        return r
    }

    static func parse(_ id: String, _ data: Data) -> ProviderQuota? {
        switch id {
        case "claude": parseClaude(data)
        case "codex": parseCodex(data)
        case "cursor": parseCursor(data)
        default: nil
        }
    }

    static func fetch(_ id: String, _ c: QuotaCredential) async throws -> ProviderQuota {
        guard let req = request(id, c) else { throw QuotaFailure.unexpected }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        do {
            let (data, resp) = try await URLSession(configuration: cfg).data(for: req)
            if let h = resp as? HTTPURLResponse {
                switch h.statusCode {
                case 200..<300: break
                case 401, 403: throw QuotaFailure.unauthorized
                case 429: throw QuotaFailure.rateLimited(Double(h.value(forHTTPHeaderField: "retry-after") ?? "") ?? 300)
                default: throw QuotaFailure.http(h.statusCode)
                }
            }
            guard var q = parse(id, data) else { throw QuotaFailure.unexpected }
            q.fetchedAt = Date()
            return q
        } catch let f as QuotaFailure { throw f }
        catch { throw QuotaFailure.offline }
    }
}

/// Opt-in, cached, back-off aware remote usage for non-Copilot providers. Fetches only on demand
/// (popover/settings appear, manual refresh) plus a slow timer while at least one provider is opted in.
@MainActor
final class ProviderQuotaService: ObservableObject {
    static let shared = ProviderQuotaService()

    struct State: Equatable {
        var quota: ProviderQuota?
        var error: String?
        var notAvailable = false
        var loading = false
    }

    @Published private(set) var states: [String: State] = [:]
    private var credentials: [String: QuotaCredential] = [:]
    private var backoff: [String: Date] = [:]
    private var lastTry: [String: Date] = [:]
    private var denied: Set<String> = []
    private var timer: Timer?
    private let ttl: TimeInterval = 300

    static func optedIn(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: "providerQuota.enabled.\(id)") }

    func setOptedIn(_ id: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "providerQuota.enabled.\(id)")
        if on { denied.remove(id); refresh(id, force: true) }
        else { states[id] = nil; credentials[id] = nil; backoff[id] = nil }
        objectWillChange.send()
        updateTimer()
    }

    var active: [String] { QuotaEndpoints.ids.filter { Self.optedIn($0) && ProviderRegistry.shared.isEnabled($0) } }

    func start() { updateTimer(); refreshAll() }

    private func updateTimer() {
        if active.isEmpty { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        timer?.tolerance = 60
    }

    func refreshAll(force: Bool = false) { for id in active { refresh(id, force: force) } }

    func refresh(_ id: String, force: Bool = false) {
        guard Self.optedIn(id), ProviderRegistry.shared.isEnabled(id), states[id]?.loading != true else { return }
        let now = Date()
        if !force {
            if let b = backoff[id], b > now { return }
            if let t = lastTry[id], now.timeIntervalSince(t) < ttl { return }
        } else {
            denied.remove(id)
        }
        lastTry[id] = now
        var s = states[id] ?? State()
        s.loading = true
        states[id] = s
        let known = credentials[id]
        let skipLoad = denied.contains(id)
        Task {
            var cred = known
            if cred == nil && !skipLoad { cred = await Task.detached { QuotaEndpoints.loadCredential(id) }.value }
            guard var c = cred, c.expires.map({ $0 > Date() }) ?? true else {
                denied.insert(id)
                credentials[id] = nil
                finish(id, error: cred == nil ? nil : "Login expired – run the CLI once to refresh", notAvailable: cred == nil)
                backoff[id] = Date().addingTimeInterval(600)
                return
            }
            credentials[id] = c
            c.expires = nil
            do {
                let q = try await QuotaEndpoints.fetch(id, c)
                backoff[id] = nil
                states[id] = State(quota: q)
            } catch let f as QuotaFailure {
                switch f {
                case .unauthorized:
                    credentials[id] = nil
                    backoff[id] = Date().addingTimeInterval(600)
                    finish(id, error: "Login rejected – sign in again in the \(ProviderRegistry.shared.name(for: id)) app")
                case .rateLimited(let w):
                    backoff[id] = Date().addingTimeInterval(min(max(w, 120), 1800))
                    finish(id, error: "Rate limited – retrying later")
                case .http(let code):
                    backoff[id] = Date().addingTimeInterval(300)
                    finish(id, error: "Usage API error (HTTP \(code))")
                case .offline:
                    finish(id, error: states[id]?.quota != nil ? "Offline – showing last known data" : "Offline – no data yet")
                case .unexpected:
                    backoff[id] = Date().addingTimeInterval(900)
                    finish(id, error: "Unexpected response (endpoint may have changed)")
                case .notAvailable: finish(id, error: nil, notAvailable: true)
                }
            } catch { finish(id, error: "Usage unavailable") }
        }
    }

    private func finish(_ id: String, error: String?, notAvailable: Bool = false) {
        var s = states[id] ?? State()
        s.loading = false
        s.error = error
        s.notAvailable = notAvailable
        states[id] = s
    }

    /// Highest-utilization window of a provider, for the menu bar fallback.
    func headline(_ id: String) -> Double? { states[id]?.quota?.maxPercent }
}

// MARK: Views

func resetText(_ d: Date, now: Date = Date()) -> String {
    let s = Int(d.timeIntervalSince(now))
    if s <= 0 { return "resetting" }
    if s < 3600 { return "resets in \(max(s / 60, 1))m" }
    if s < 86400 { return "resets in \(s / 3600)h \(s % 3600 / 60)m" }
    return "resets in \(s / 86400)d \(s % 86400 / 3600)h"
}

/// Compact windows of one provider; used in the Providers tab.
struct ProviderQuotaWindows: View {
    let quota: ProviderQuota
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(quota.windows, id: \.label) { w in
                HStack(spacing: 6) {
                    Text(w.label).font(HubFont.caption).frame(minWidth: 56, maxWidth: 90, alignment: .leading).lineLimit(1)
                    if let p = w.percentUsed {
                        MiniBar(fraction: p / 100, color: p < 70 ? .green : p < 90 ? .orange : .red, height: 4).frame(minWidth: 30, maxWidth: 80)
                        Text("\(Int(p.rounded()))%").font(HubFont.captionDigits)
                    }
                    if let d = w.detail { Text(d).font(HubFont.captionDigits).foregroundStyle(.secondary) }
                    if let r = w.resetsAt { Text(resetText(r)).font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
    }
}

/// Opt-in toggle + status for one provider's remote usage (Providers tab).
struct ProviderQuotaRow: View {
    let id: String
    @ObservedObject var service = ProviderQuotaService.shared

    var body: some View {
        let on = ProviderQuotaService.optedIn(id)
        let st = service.states[id]
        VStack(alignment: .leading, spacing: 3) {
            if QuotaEndpoints.hasAPI(id) {
                HStack(spacing: 6) {
                    Toggle("Show usage limits", isOn: Binding(get: { on }, set: { service.setOptedIn(id, $0) }))
                        .toggleStyle(.checkbox).controlSize(.small).font(HubFont.caption)
                    if on, st?.loading == true { ProgressView().controlSize(.mini) }
                    Spacer()
                    if on { Button { service.refresh(id, force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).font(HubFont.caption).help("Refresh usage").accessibilityLabel("Refresh usage") }
                }
                Text(QuotaEndpoints.explanation(id)).font(HubFont.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if on {
                    if let q = st?.quota { ProviderQuotaWindows(quota: q) }
                    if st?.notAvailable == true { Text("Not available – no readable login found").font(HubFont.caption).foregroundStyle(.orange) }
                    else if let e = st?.error { Text(e).font(HubFont.caption).foregroundStyle(.orange).lineLimit(2) }
                }
            } else {
                Text(QuotaEndpoints.explanation(id)).font(HubFont.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 32)
    }
}

enum QuotaSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ n: String, _ ok: Bool) { print(ok ? "ok   " : "FAIL ", n); if !ok { failures += 1 } }
        func j(_ s: String) -> Data { Data(s.utf8) }

        let c = QuotaEndpoints.parseClaude(j(#"{"five_hour":{"utilization":37.5,"resets_at":"2030-01-01T10:00:00.123456+00:00"},"seven_day":{"utilization":120,"resets_at":null},"seven_day_opus":null}"#))
        check("claude: windows", c?.windows.map(\.label) == ["5 hours", "Weekly"])
        check("claude: percent + clamp", c?.windows.first?.percentUsed == 37.5 && c?.windows.last?.percentUsed == 100)
        check("claude: reset parsed", c?.windows.first?.resetsAt != nil && c?.windows.last?.resetsAt == nil)
        check("claude: garbage -> nil", QuotaEndpoints.parseClaude(j("{}")) == nil && QuotaEndpoints.parseClaude(j("nope")) == nil)

        let now = Date(timeIntervalSince1970: 1_000_000)
        let x = QuotaEndpoints.parseCodex(j(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_after_seconds":600},"secondary_window":{"used_percent":55.5,"limit_window_seconds":604800,"reset_at":1500000}}}"#), now: now)
        check("codex: labels", x?.windows.map(\.label) == ["5 hours", "Weekly"] && x?.plan == "plus")
        check("codex: reset after/at", x?.windows[0].resetsAt == now.addingTimeInterval(600) && x?.windows[1].resetsAt == Date(timeIntervalSince1970: 1_500_000))
        check("codex: missing rate_limit -> nil", QuotaEndpoints.parseCodex(j(#"{"plan_type":"free"}"#)) == nil)

        let cu = QuotaEndpoints.parseCursor(j(#"{"gpt-4":{"numRequests":120,"numRequestsTotal":150,"maxRequestUsage":500},"gpt-3.5-turbo":{"numRequests":9,"maxRequestUsage":null},"startOfMonth":"2030-01-01T00:00:00.000Z"}"#))
        check("cursor: premium percent", cu?.windows.first(where: { $0.label == "Premium requests" })?.percentUsed == 30)
        check("cursor: unlimited model keeps detail only", cu?.windows.first(where: { $0.label == "gpt-3.5-turbo" })?.percentUsed == nil
              && cu?.windows.first(where: { $0.label == "gpt-3.5-turbo" })?.detail == "9 requests")
        check("cursor: reset = next month", cu?.windows.first?.resetsAt != nil)

        let payload = Data(#"{"sub":"auth0|user_ABC"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        check("cursor: user id from JWT", QuotaEndpoints.cursorUserID(fromJWT: "h.\(payload).s") == "user_ABC" && QuotaEndpoints.cursorUserID(fromJWT: "bad") == nil)

        check("claude creds", QuotaEndpoints.parseClaudeCredentials(j(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":4102444800000}}"#))?.expires != nil
              && QuotaEndpoints.parseClaudeCredentials(j("{}")) == nil)
        check("codex auth: api-key-only -> nil", QuotaEndpoints.parseCodexAuth(j(#"{"OPENAI_API_KEY":"k"}"#)) == nil
              && QuotaEndpoints.parseCodexAuth(j(#"{"tokens":{"access_token":"a","account_id":"i"}}"#))?.extra == "i")
        check("requests only target own hosts", QuotaEndpoints.ids.allSatisfy { id in
            let h = QuotaEndpoints.request(id, QuotaCredential(token: "t", extra: "u"))?.url?.host ?? ""
            return ["cursor": "cursor.com", "claude": "api.anthropic.com", "codex": "chatgpt.com"][id] == h })
        check("no API for gemini/grok", !QuotaEndpoints.hasAPI("gemini") && !QuotaEndpoints.hasAPI("grok"))
        check("window label", QuotaEndpoints.windowLabel(18000) == "5 hours" && QuotaEndpoints.windowLabel(604800) == "Weekly")
        check("copilot: parses premium snapshot", CopilotQuotaAPI.parse(j(#"{"copilot_plan":"pro","quota_reset_date":"2030-01-01","quota_snapshots":{"premium_interactions":{"entitlement":300,"quota_remaining":120,"percent_remaining":40,"unlimited":false}}}"#))?.remaining == 120)
        check("copilot: schema drift -> nil (unavailable state)", CopilotQuotaAPI.parse(j(#"{"quota_snapshots":{"chat":{}}}"#)) == nil && CopilotQuotaAPI.parse(j("<html>")) == nil)
        print(failures == 0 ? "All quota checks passed" : "\(failures) quota check(s) FAILED")
        return failures == 0
    }
}
