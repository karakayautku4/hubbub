import Foundation

/// Flags sessions that look stuck (in use, silent for >5 min with a pending tool) or recently failed.
final class StuckDetector: @unchecked Sendable {
    static let shared = StuckDetector()
    static let stuckAfter: TimeInterval = 300
    static let failureWindow: TimeInterval = 120

    private var notified = Set<String>()
    private var notifiedFailed = Set<String>()
    private var notifiedApproval = Set<String>()
    private let lock = NSLock()

    static func level(for s: SessionInfo, now: Date = Date()) -> AttentionLevel {
        guard s.inUse else { return .none }
        if s.waitingOnTool, now.timeIntervalSince(s.lastEvent) > stuckAfter { return .stuck }
        if let f = s.lastFailureAt, now.timeIntervalSince(f) < failureWindow { return .failed }
        return .none
    }

    static func needsApproval(_ s: SessionInfo) -> Bool {
        s.inUse && (s.waitingApproval || s.subagents.contains { $0.waitingApproval })
    }

    func evaluate(_ sessions: [SessionInfo]) -> [String: AttentionLevel] {
        var out: [String: AttentionLevel] = [:]
        var approving = Set<String>()
        for s in sessions {
            let l = Self.level(for: s)
            if Self.needsApproval(s) { approving.insert(s.id); fire(&notifiedApproval, s, "approval", NotifyKey.approval, "Waiting for your approval", s.currentTool.map { "\(s.name) wants to run \($0)" } ?? "\(s.name) is waiting for approval") }
            guard l != .none else { continue }
            out[s.id] = l
            if l == .stuck { fire(&notified, s, "stuck", NotifyKey.stuck, "Session looks stuck", "\(s.name) has had no activity for over 5 minutes" + (s.currentTool.map { " (waiting on \($0))" } ?? "")) }
            if l == .failed { fire(&notifiedFailed, s, "failed", NotifyKey.failed, "Tool call failed", s.lastError.map { "\(s.name): \($0)" } ?? "\(s.name) had a failing tool call") }
        }
        lock.lock()
        notified.formIntersection(Set(out.filter { $0.value == .stuck }.keys))
        notifiedFailed.formIntersection(Set(out.filter { $0.value == .failed }.keys))
        notifiedApproval.formIntersection(approving)
        lock.unlock()
        return out
    }

    /// Emits once per episode (until the condition clears).
    private func fire(_ set: inout Set<String>, _ s: SessionInfo, _ kind: String, _ key: String, _ title: String, _ body: String) {
        lock.lock()
        let isNew = set.insert(s.id).inserted
        lock.unlock()
        guard isNew else { return }
        Task { @MainActor in Notifier.shared.attention(kind, key: key, session: s, title: title, body: body) }
    }
}
