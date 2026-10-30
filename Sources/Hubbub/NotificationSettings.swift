import SwiftUI
import UserNotifications

enum NotifyKey {
    static let master = "notifications"
    static let approval = "notifyApproval"
    static let stuck = "notifyStuck"
    static let failed = "notifyFailed"
    static let finished = "notifyFinished"

    static func isOn(_ key: String) -> Bool {
        let d = UserDefaults.standard
        let fallback = key != failed
        return (d.object(forKey: master) as? Bool ?? true) && (d.object(forKey: key) as? Bool ?? fallback)
    }
}

/// At most one notification per key (session + kind) within `window` seconds.
struct NotificationCoalescer {
    var window: TimeInterval = 60
    private var last: [String: Date] = [:]

    mutating func allow(_ key: String, now: Date = Date()) -> Bool {
        if let t = last[key], now.timeIntervalSince(t) < window { return false }
        last[key] = now
        if last.count > 200 { last = last.filter { now.timeIntervalSince($0.value) < window } }
        return true
    }
}

enum NotificationText {
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m >= 60 { return "\(m / 60)h \(m % 60)m" }
        return m >= 1 ? "\(m)m" : "\(max(1, Int(s)))s"
    }

    static func finishedBody(elapsed: TimeInterval, calls: Int, failures: Int) -> String {
        var parts = ["Finished after \(duration(elapsed))"]
        if calls > 0 { parts.append("\(calls) call\(calls == 1 ? "" : "s")") }
        if failures > 0 { parts.append("\(failures) failed") }
        return parts.joined(separator: " · ")
    }

    static func summary(count: Int) -> String { "\(count) sessions finished" }
}

enum NotificationSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL \(m)"); ok = false } }
        var c = NotificationCoalescer()
        let t0 = Date()
        check(c.allow("a", now: t0), "first allowed")
        check(!c.allow("a", now: t0.addingTimeInterval(30)), "repeat within 60s blocked")
        check(c.allow("b", now: t0.addingTimeInterval(30)), "other key allowed")
        check(c.allow("a", now: t0.addingTimeInterval(61)), "allowed after window")
        check(NotificationText.finishedBody(elapsed: 725, calls: 84, failures: 2) == "Finished after 12m · 84 calls · 2 failed", "rich body")
        check(NotificationText.finishedBody(elapsed: 30, calls: 1, failures: 0) == "Finished after 30s · 1 call", "short body")
        check(NotificationText.finishedBody(elapsed: 3900, calls: 0, failures: 0) == "Finished after 1h 5m", "hours body")
        check(NotificationText.summary(count: 3) == "3 sessions finished", "summary")
        print(ok ? "notifications selftest OK" : "notifications selftest FAILED")
        return ok
    }
}

/// Per-type notification toggles; embedded in Settings → Notifications.
struct NotificationSettingsView: View {
    @AppStorage(NotifyKey.master) private var master = true
    @AppStorage(NotifyKey.approval) private var approval = true
    @AppStorage(NotifyKey.stuck) private var stuck = true
    @AppStorage(NotifyKey.finished) private var finished = true
    @AppStorage(NotifyKey.failed) private var failed = false
    @State private var status: UNAuthorizationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Notify me when a session…", isOn: $master).accessibilityLabel("Notifications enabled")
            Group {
                Toggle("needs approval", isOn: $approval)
                Toggle("looks stuck", isOn: $stuck)
                Toggle("finishes", isOn: $finished)
                Toggle("has a failed tool call", isOn: $failed)
            }
            .padding(.leading, 16).disabled(!master)
            if status == .denied {
                HStack(spacing: 6) {
                    Text("Blocked in macOS.").font(.caption).foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(u) }
                    }.controlSize(.small)
                }
            } else if status == .notDetermined {
                Button("Allow notifications…") { Notifier.shared.requestAuthorization { _ in refresh() } }.controlSize(.small)
            }
        }
        .font(.callout)
        .onAppear { refresh() }
    }

    private func refresh() {
        Notifier.shared.authorizationStatus { status = $0 }
    }
}
