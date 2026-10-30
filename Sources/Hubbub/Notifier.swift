import Foundation
import UserNotifications

/// Posts system notifications for finished sessions and low quota. Only works inside the .app bundle.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private var workingSince: [String: Date] = [:]
    private var lastState: [String: SessionState] = [:]
    private var coalescer = NotificationCoalescer()
    private var pendingFinished: [(id: String, name: String, body: String)] = []
    private var flushScheduled = false
    private let delegate = NotificationDelegate()

    private var inBundle: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }
    private var enabled: Bool { inBundle && (UserDefaults.standard.object(forKey: NotifyKey.master) as? Bool ?? true) }

    /// Installs the delegate so banners show while the app is active and clicks route to the session.
    func activate() {
        guard inBundle else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    func authorizationStatus(_ done: @escaping @MainActor (UNAuthorizationStatus) -> Void) {
        guard inBundle else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let st = s.authorizationStatus
            Task { @MainActor in done(st) }
        }
    }

    func requestAuthorization(_ done: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard inBundle else { done(false); return }
        activate()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    /// Adds the app icon as a thumbnail; the system moves the attached file, so a temp copy is used.
    nonisolated static func attachIcon(to c: UNMutableNotificationContent) {
        guard let src = Bundle.main.url(forResource: "NotificationIcon", withExtension: "png") else { return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hubbub-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: src, to: tmp)) != nil,
              let a = try? UNNotificationAttachment(identifier: "icon", url: tmp) else { return }
        c.attachments = [a]
    }

    func post(_ title: String, _ body: String, sessionID: String? = nil, id: String = UUID().uuidString,
              category: String? = nil, info: [String: Any] = [:]) {
        guard enabled else { return }
        if FocusGuard.shared.intercept(.init(title: title, body: body, sessionID: sessionID, id: id, category: category, info: info)) { return }
        activate()
        let center = UNUserNotificationCenter.current()
        // Users who skipped onboarding are asked once, the first time something needs delivering.
        if UserDefaults.standard.bool(forKey: "hasOnboarded") {
            center.getNotificationSettings { s in
                if s.authorizationStatus == .notDetermined { center.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            }
        }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        if let sessionID { c.userInfo = ["sessionID": sessionID] }
        if !info.isEmpty { c.userInfo = info }
        if let category { c.categoryIdentifier = category }
        Notifier.attachIcon(to: c)
        center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// Attention event (approval / stuck / failed) for a session; throttled to one per session and kind per minute.
    func attention(_ kind: String, key: String, session: SessionInfo, title: String, body: String) {
        guard NotifyKey.isOn(key), coalescer.allow("\(kind)-\(session.id)") else { return }
        if kind == "approval", let q = ReplyCenter.shared.question(for: session), q.source == .log {
            let r = ReplyNotifications.categoryForLogQuestion(session: session, question: q)
            let text = [q.title, q.detail].compactMap { $0 }.joined(separator: "\n")
            post(session.name, String(text.prefix(300)), sessionID: session.id, id: "\(kind)-\(session.id)", category: r.category, info: r.info)
            return
        }
        post(title, body, sessionID: session.id, id: "\(kind)-\(session.id)")
    }

    func sessions(_ list: [SessionInfo]) {
        for s in list {
            let prev = lastState[s.id]
            lastState[s.id] = s.state
            if s.state == .working, workingSince[s.id] == nil { workingSince[s.id] = Date() }
            if s.state != .working, prev == .working, let since = workingSince[s.id] {
                workingSince[s.id] = nil
                let elapsed = Date().timeIntervalSince(since)
                if elapsed > 20, NotifyKey.isOn(NotifyKey.finished), coalescer.allow("finished-\(s.id)") {
                    pendingFinished.append((s.id, s.name, NotificationText.finishedBody(elapsed: elapsed, calls: s.toolCalls, failures: s.failures)))
                    scheduleFlush()
                }
            }
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            flushScheduled = false
            let batch = pendingFinished
            pendingFinished = []
            if batch.count == 1, let f = batch.first { post(f.name, f.body, sessionID: f.id, id: "finished-\(f.id)") }
            else if batch.count > 1 {
                post(NotificationText.summary(count: batch.count), batch.prefix(3).map(\.name).joined(separator: ", ") + (batch.count > 3 ? "…" : ""))
            }
        }
    }

    /// Fires once per threshold (80%, 95% used) per reset cycle; state persists in UserDefaults.
    func quota(_ q: Quota?) {
        guard let q, !q.unlimited, q.entitlement > 0 else { return }
        let d = UserDefaults.standard
        if d.string(forKey: "notifiedResetDate") != q.resetDate {
            d.set(q.resetDate, forKey: "notifiedResetDate")
            d.set([Int](), forKey: "notifiedThresholds")
        }
        var done = d.array(forKey: "notifiedThresholds") as? [Int] ?? []
        let usedPct = 100 - q.percentRemaining
        for t in [80, 95] where usedPct >= Double(t) && !done.contains(t) {
            done.append(t)
            post("Copilot quota at \(t)%", "\(Int(q.used).formatted()) of \(Int(q.entitlement).formatted()) credits used" + (q.resetDate.isEmpty ? "" : " · resets \(q.resetDate)"))
        }
        d.set(done, forKey: "notifiedThresholds")
    }
}

/// Presents banners while the app is frontmost and routes clicks to the session.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["sessionID"] as? String
        let action = response.actionIdentifier
        if action != UNNotificationDefaultActionIdentifier, action != UNNotificationDismissActionIdentifier {
            let text = (response as? UNTextInputNotificationResponse)?.userText
            Task { @MainActor in ReplyCenter.shared.handleNotification(actionID: action, text: text, userInfo: info) }
        } else {
            Task { @MainActor in
                if let screen = info["screen"] as? String, id == nil { AppRouter.shared.open(screen: screen) } else { AppRouter.shared.open(sessionID: id) }
            }
        }
        completionHandler()
    }
}
