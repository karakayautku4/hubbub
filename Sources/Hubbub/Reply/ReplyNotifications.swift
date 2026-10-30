import Foundation
import UserNotifications

/// Actionable notifications (Approve / Deny / option buttons / text reply). Buttons only appear when a reply
/// channel is usable; every button press is a user action, and nothing is answered automatically.
@MainActor
enum ReplyNotifications {
    private static var categories: [String: UNNotificationCategory] = [:]
    private static var order: [String] = []

    private static var inBundle: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func categoryID(for q: PendingQuestion) -> String { "hubbub.q.\(q.id)" }

    /// Pure: which actions a notification offers for a question. (identifier, title, destructive)
    static func actionSpecs(for q: PendingQuestion, viaHook: Bool) -> [(id: String, title: String, destructive: Bool, text: Bool)] {
        if q.isPermission {
            var a: [(id: String, title: String, destructive: Bool, text: Bool)] = [("approve", "Approve", false, false), ("deny", "Deny", true, false)]
            if viaHook { a.append(("terminal", "Ask in terminal", false, false)) }
            return a
        }
        guard q.canAnswerInApp else { return [] }
        var a = q.options.prefix(q.allowsFreeText ? 3 : 4).map { (id: "opt.\($0.index)", title: String($0.label.prefix(40)), destructive: false, text: false) }
        if q.allowsFreeText || q.kind == .freeText { a.append(("text", "Reply…", false, true)) }
        return a
    }

    private static func register(_ q: PendingQuestion, viaHook: Bool) -> String? {
        let specs = actionSpecs(for: q, viaHook: viaHook)
        guard !specs.isEmpty else { return nil }
        let actions: [UNNotificationAction] = specs.map { s in
            if s.text {
                return UNTextInputNotificationAction(identifier: s.id, title: s.title, options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Your reply")
            }
            return UNNotificationAction(identifier: s.id, title: s.title, options: s.destructive ? [.destructive] : [])
        }
        let id = categoryID(for: q)
        categories[id] = UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [])
        order.append(id)
        while order.count > 20 { categories[order.removeFirst()] = nil }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories.values))
        return id
    }

    private static func send(title: String, body: String, id: String, category: String?, info: [String: Any]) {
        guard inBundle, NotifyKey.isOn(NotifyKey.approval) else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.userInfo = info
        if let category { c.categoryIdentifier = category }
        Notifier.attachIcon(to: c)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    static func postHook(_ r: HookRequest, sessionName: String?) {
        let q = r.question
        let cat = register(q, viaHook: true)
        let body = [q.detail, "Answer here, or the terminal prompt appears after \(Int(r.input.timeout))s."].compactMap { $0 }.joined(separator: "\n")
        send(title: sessionName.map { "\($0): \(q.title)" } ?? q.title, body: body, id: "hook-\(r.id)", category: cat,
             info: ["sessionID": r.input.sessionKey, "questionID": r.id, "nonce": r.nonce])
    }

    /// Log-detected question with a usable reply channel; nil category means plain notification.
    static func categoryForLogQuestion(session s: SessionInfo, question q: PendingQuestion) -> (category: String?, info: [String: Any]) {
        let info: [String: Any] = ["sessionID": s.id, "questionID": q.id]
        guard ReplyCenter.shared.availability(session: s, question: q) == .terminal else { return (nil, info) }
        return (register(q, viaHook: false), info)
    }

    static func clear(requestID: String) {
        guard inBundle else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["hook-\(requestID)"])
    }
}
