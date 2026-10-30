import SwiftUI

/// Lightweight update check against the GitHub Releases API (no Sparkle, no signing infrastructure needed).
/// Opt-out via the "updateCheckAuto" default; fails silently when offline.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable, Sendable {
        let version: String
        /// Release page (notes).
        let url: URL
        /// Direct DMG asset when the release has one.
        var assetURL: URL?
        var downloadTarget: URL { assetURL ?? url }
    }

    enum Outcome: Equatable, Sendable {
        case release(Release)
        case noReleases
        case failure(String)
    }

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    nonisolated static let liveTransport: Transport = { try await URLSession.shared.data(for: $0) }
    /// Replaced by the self-test only.
    nonisolated(unsafe) static var transport: Transport = liveTransport

    /// "owner/repo", overridable through the HubbubRepo Info.plist key (placeholder until the repo is public).
    nonisolated static var repo: String { Bundle.main.object(forInfoDictionaryKey: "HubbubRepo") as? String ?? "karakayautku4/hubbub" }
    nonisolated static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastResult: String?
    @Published private(set) var lastFailed = false

    private let d = UserDefaults.standard
    private var autoEnabled: Bool { d.object(forKey: "updateCheckAuto") as? Bool ?? true }

    /// Called on launch: honors the opt-out and the 24h interval.
    func checkIfDue() {
        guard autoEnabled, Bundle.main.bundleIdentifier != nil else { return }
        let last = d.double(forKey: "updateLastCheck")
        if Date().timeIntervalSince1970 - last >= 24 * 3600 { check(manual: false) }
    }

    /// Manual checks always end in a visible `lastResult`; automatic ones stay silent on failure.
    func check(manual: Bool) {
        guard !checking else { return }
        checking = true
        if manual {
            lastFailed = false
            lastResult = "Checking…"
        }
        Task {
            let outcome = await Self.fetchLatest(transport: Self.transport, current: Self.currentVersion)
            checking = false
            switch outcome {
            case .failure(let why):
                if manual { lastResult = "Couldn't check: \(why)"; lastFailed = true }
            case .noReleases:
                d.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")
                available = nil
                if manual { lastResult = "No releases published yet (you're on v\(Self.currentVersion))" }
            case .release(let rel):
                d.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")
                let newer = Self.isNewer(rel.version, than: Self.currentVersion)
                let skipped = d.string(forKey: "updateSkipped") == rel.version
                available = newer && (manual || !skipped) ? rel : nil
                if manual {
                    // An explicit check overrides an earlier snooze/skip.
                    if newer { d.removeObject(forKey: "updateRemindAfter"); d.removeObject(forKey: "updateSkipped") }
                    lastResult = newer ? "Version \(rel.version) available" : "You're up to date (v\(Self.currentVersion))"
                }
            }
            objectWillChange.send()
        }
    }

    /// Hides the pill for a day without skipping the version.
    var snoozed: Bool { Date().timeIntervalSince1970 < d.double(forKey: "updateRemindAfter") }
    func remindLater() {
        d.set(Date().timeIntervalSince1970 + 24 * 3600, forKey: "updateRemindAfter")
        objectWillChange.send()
    }

    func skip() {
        if let r = available { d.set(r.version, forKey: "updateSkipped") }
        available = nil
    }

    func download() {
        if let r = available { NSWorkspace.shared.open(r.downloadTarget) }
    }

    /// Menu-driven check (status item menu): runs a manual check and reports in an alert, since no UI may be open.
    func checkWithAlert() {
        check(manual: true)
        Task {
            while checking { try? await Task.sleep(nanoseconds: 100_000_000) }
            let alert = NSAlert()
            alert.messageText = available.map { "Version \($0.version) available" } ?? (lastFailed ? "Couldn't check for updates" : "Hubbub")
            alert.informativeText = lastResult ?? ""
            if available != nil { alert.addButton(withTitle: "Download") }
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, available != nil { download() }
        }
    }

    nonisolated static func fetchLatest(transport: Transport, current: String) async -> Outcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return .failure("bad repository") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Hubbub/\(current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await transport(req)
            return parse(data: data, response: resp as? HTTPURLResponse)
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .failure("you appear to be offline")
            case .timedOut: return .failure("GitHub timed out")
            default: return .failure(e.localizedDescription)
            }
        } catch { return .failure(error.localizedDescription) }
    }

    nonisolated static func parse(data: Data, response: HTTPURLResponse?) -> Outcome {
        guard let response else { return .failure("no response from GitHub") }
        switch response.statusCode {
        case 200: break
        // Private repositories also answer 404 to anonymous requests.
        case 404: return .noReleases
        case 403, 429:
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            return .failure(remaining == "0" || response.statusCode == 429 ? "GitHub rate limit reached, try again later" : "GitHub refused the request (HTTP 403)")
        default: return .failure("GitHub returned HTTP \(response.statusCode)")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String, !tag.isEmpty else { return .failure("unexpected response from GitHub") }
        if obj["draft"] as? Bool == true || obj["prerelease"] as? Bool == true { return .noReleases }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard let html = obj["html_url"] as? String, let page = URL(string: html), page.scheme == "https" else {
            return .failure("unexpected response from GitHub")
        }
        var asset: URL?
        let assets = (obj["assets"] as? [[String: Any]] ?? []).compactMap { a -> (String, URL)? in
            guard let n = a["name"] as? String, let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)),
                  u.scheme == "https" else { return nil }
            return (n, u)
        }
        asset = assets.first { $0.0 == "Hubbub-\(version).dmg" }?.1 ?? assets.first { $0.0.lowercased().hasSuffix(".dmg") }?.1
        return .release(Release(version: version, url: page, assetURL: asset))
    }

    /// Numeric semver comparison; a pre-release suffix ("-beta") sorts below the same release.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parse(_ s: String) -> (nums: [Int], pre: Bool) {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("v") { t.removeFirst() }
            let core = t.split(separator: "+")[0]
            let parts = core.split(separator: "-", maxSplits: 1)
            let nums = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
            return (nums, parts.count > 1)
        }
        let x = parse(a), y = parse(b)
        for i in 0..<max(x.nums.count, y.nums.count, 3) {
            let p = i < x.nums.count ? x.nums[i] : 0, q = i < y.nums.count ? y.nums[i] : 0
            if p != q { return p > q }
        }
        return !x.pre && y.pre
    }

    nonisolated static func selfTest() -> Bool {
        let cases: [(String, String, Bool)] = [
            ("0.2.1", "0.2.0", true), ("0.2.0", "0.2.0", false), ("0.1.9", "0.2.0", false),
            ("0.10.0", "0.9.0", true), ("1.0", "0.9.9", true), ("v1.2.3", "1.2.3", false),
            ("1.0.0", "1.0.0-beta", true), ("1.0.0-beta", "1.0.0", false), ("2.0.0", "1.99.99", true),
            ("1.0.0+5", "1.0.0", false),
        ]
        var ok = true
        func check(_ name: String, _ cond: Bool) { if !cond { print("FAIL \(name)"); ok = false } }
        for (a, b, want) in cases where isNewer(a, than: b) != want {
            print("FAIL isNewer(\(a), \(b)) expected \(want)"); ok = false
        }

        func http(_ code: Int, _ json: String, _ headers: [String: String] = [:]) -> Transport {
            { req in (Data(json.utf8), HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: headers)!) }
        }
        func run(_ t: @escaping Transport) -> Outcome {
            nonisolated(unsafe) var out: Outcome = .failure("unset")
            let sem = DispatchSemaphore(value: 0)
            Task.detached { out = await fetchLatest(transport: t, current: "0.2.0"); sem.signal() }
            sem.wait()
            return out
        }
        func release(_ tag: String, extra: String = "") -> String {
            "{\"tag_name\":\"\(tag)\",\"html_url\":\"https://github.com/o/r/releases/tag/\(tag)\"\(extra)}"
        }
        func version(_ o: Outcome) -> String? { if case .release(let r) = o { return r.version } else { return nil } }

        check("404 → noReleases", run(http(404, "{\"message\":\"Not Found\"}")) == .noReleases)
        if case .failure(let m) = run(http(403, "{}", ["X-RateLimit-Remaining": "0"])) { check("403 rate limit text", m.contains("rate limit")) } else { check("403 rate limit", false) }
        if case .failure = run(http(500, "{}")) {} else { check("500 fails", false) }
        if case .failure(let m) = run({ _ in throw URLError(.notConnectedToInternet) }) { check("offline text", m.contains("offline")) } else { check("offline", false) }
        if case .failure = run(http(200, "not json")) {} else { check("malformed JSON fails", false) }
        if case .failure = run(http(200, "{\"tag_name\":5}")) {} else { check("wrong shape fails", false) }
        check("v-prefix stripped", version(run(http(200, release("v0.3.0")))) == "0.3.0")
        check("newer detected", version(run(http(200, release("v0.3.0")))).map { isNewer($0, than: "0.2.0") } == true)
        check("equal not newer", version(run(http(200, release("v0.2.0")))).map { isNewer($0, than: "0.2.0") } == false)
        check("older not newer", version(run(http(200, release("v0.1.0")))).map { isNewer($0, than: "0.2.0") } == false)
        check("prerelease ignored", run(http(200, release("v9.0.0", extra: ",\"prerelease\":true"))) == .noReleases)
        check("draft ignored", run(http(200, release("v9.0.0", extra: ",\"draft\":true"))) == .noReleases)
        check("http page rejected", { if case .failure = run(http(200, "{\"tag_name\":\"v1\",\"html_url\":\"http://x\"}")) { return true } else { return false } }())
        let assets = ",\"assets\":[{\"name\":\"Hubbub-0.3.0.zip\",\"browser_download_url\":\"https://x/z.zip\"},{\"name\":\"Other.dmg\",\"browser_download_url\":\"https://x/o.dmg\"},{\"name\":\"Hubbub-0.3.0.dmg\",\"browser_download_url\":\"https://x/h.dmg\"}]"
        if case .release(let r) = run(http(200, release("v0.3.0", extra: assets))) {
            check("asset prefers Hubbub-<ver>.dmg", r.downloadTarget.absoluteString == "https://x/h.dmg")
        } else { check("asset release", false) }
        if case .release(let r) = run(http(200, release("v0.3.0"))) {
            check("no asset → release page", r.downloadTarget == r.url)
        } else { check("no-asset release", false) }

        print(ok ? "update selftest OK" : "update selftest FAILED")
        return ok
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var checker = UpdateChecker.shared
    @AppStorage("updateCheckAuto") private var auto = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Check for updates automatically", isOn: $auto)
            HStack(spacing: 8) {
                Button("Check for Updates") { checker.check(manual: true) }.controlSize(.small).disabled(checker.checking)
                if checker.checking { ProgressView().controlSize(.small) }
                if let r = checker.lastResult {
                    Text(r).font(.caption2).foregroundStyle(checker.lastFailed ? Color.orange : Color.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(r)
                }
                if let a = checker.available, !checker.checking {
                    Button("Download") { checker.download() }.controlSize(.small)
                    Button("Release notes") { NSWorkspace.shared.open(a.url) }.controlSize(.small).buttonStyle(.link)
                }
                Spacer()
                Text("v\(UpdateChecker.currentVersion)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .animation(nil, value: checker.lastResult)
    }
}
