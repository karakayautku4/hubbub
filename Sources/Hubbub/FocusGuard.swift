import Foundation
import Intents

/// Holds back notifications during quiet hours or while a system Focus is active, then posts one catch-up summary.
/// Focus state comes from the public `INFocusStatusCenter` API (needs a one-time user authorization); quiet hours need nothing.
@MainActor
final class FocusGuard: ObservableObject {
    static let shared = FocusGuard()

    struct Held {
        var title: String; var body: String; var sessionID: String?; var id: String
        var category: String? = nil
        var info: [String: Any] = [:]
    }

    enum Key {
        static let respectFocus = "respectFocus"
        static let quietEnabled = "quietHoursEnabled"
        static let quietStart = "quietHoursStart"   // minutes since midnight
        static let quietEnd = "quietHoursEnd"
    }

    @Published private(set) var focusActive = false
    @Published private(set) var heldCount = 0
    private var held: [Held] = []
    private var timer: Timer?
    private var releasing = false
    private var wasSuppressing = false

    private var defaults: UserDefaults { .standard }
    var respectFocus: Bool { defaults.object(forKey: Key.respectFocus) as? Bool ?? true }
    var quietEnabled: Bool { defaults.bool(forKey: Key.quietEnabled) }
    var quietStart: Int { defaults.object(forKey: Key.quietStart) as? Int ?? 22 * 60 }
    var quietEnd: Int { defaults.object(forKey: Key.quietEnd) as? Int ?? 7 * 60 }

    var focusAuthorized: Bool { INFocusStatusCenter.default.authorizationStatus == .authorized }

    var quietNow: Bool { quietEnabled && QuietHours.contains(minute: QuietHours.minuteOfDay(Date()), start: quietStart, end: quietEnd) }
    var isSuppressing: Bool { quietNow || (respectFocus && focusActive) }

    func requestFocusAccess(_ done: @escaping @MainActor () -> Void = {}) {
        INFocusStatusCenter.default.requestAuthorization { _ in Task { @MainActor in self.evaluate(); done() } }
    }

    func start() {
        guard timer == nil else { return }
        evaluate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.evaluate() } }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-reads Focus/quiet state; flushes held notifications on the transition back to normal.
    func evaluate() {
        let focus = respectFocus && focusAuthorized && (INFocusStatusCenter.default.focusStatus.isFocused ?? false)
        if focus != focusActive { focusActive = focus }
        let now = isSuppressing
        if wasSuppressing && !now { release() }
        wasSuppressing = now
    }

    /// Returns true when the notification was held back (caller must not deliver it).
    func intercept(_ item: Held) -> Bool {
        guard !releasing else { return false }
        evaluate()
        guard isSuppressing else { return false }
        held.append(item)
        if held.count > 50 { held.removeFirst(held.count - 50) }
        heldCount = held.count
        return true
    }

    private func release() {
        let items = held
        held = []
        heldCount = 0
        guard !items.isEmpty else { return }
        releasing = true
        defer { releasing = false }
        if let c = Self.catchUp(items) { Notifier.shared.post(c.title, c.body) }
        else if let one = items.first { Notifier.shared.post(one.title, one.body, sessionID: one.sessionID, id: one.id, category: one.category, info: one.info) }
    }

    /// Summary for several held notifications; nil when 0 or 1 (a single one is simply delivered as it was).
    nonisolated static func catchUp(_ items: [Held]) -> (title: String, body: String)? {
        guard items.count > 1 else { return nil }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for i in items { if counts[i.title] == nil { order.append(i.title) }; counts[i.title, default: 0] += 1 }
        let body = order.prefix(4).map { counts[$0]! > 1 ? "\($0) (\(counts[$0]!))" : $0 }.joined(separator: ", ") + (order.count > 4 ? "…" : "")
        return ("\(items.count) notifications while you were away", body)
    }
}
