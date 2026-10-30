import Foundation
import Security

enum ReplyKey {
    static let hook = "reply.hook.enabled"
    static let terminal = "reply.tty.enabled"
}

enum ReplyStatus: Equatable {
    case sending
    /// Dispatched to a channel. Not yet confirmed by the agent's log.
    case sent(via: String, at: Date)
    case confirmed
    case unconfirmed
    case failed(String)

    var text: String {
        switch self {
        case .sending: "Sending…"
        case .sent(let via, _): "Sent via \(via) — waiting for the agent to pick it up"
        case .confirmed: "Answered ✓ — the agent has continued"
        case .unconfirmed: "Couldn't confirm the agent received it — check your terminal"
        case .failed(let r): "Couldn't deliver — answer in your terminal. (\(r))"
        }
    }
}

struct HookRequest: Identifiable {
    let id: String
    let nonce: String
    let input: HookInput
    let box: DecisionBox
    let createdAt: Date

    var question: PendingQuestion {
        PendingQuestion(id: id, kind: .permission, title: "Allow \(input.toolName)?",
                        detail: input.detail.isEmpty ? nil : input.detail, options: QuestionParser.approveDeny,
                        source: .hook, toolName: input.toolName, askedAt: createdAt, nonce: nonce)
    }
}

enum ReplyAvailability: Equatable {
    case hook
    case terminal
    case off(String)
}

/// Owns the opt-in channels and every user-initiated reply. Nothing here answers on its own.
@MainActor
final class ReplyCenter: ObservableObject {
    static let shared = ReplyCenter()

    @Published private(set) var hookRequests: [HookRequest] = []
    @Published private(set) var status: [String: ReplyStatus] = [:]
    @Published private(set) var serverError: String?

    private var server: ReplyServer?
    private var lastSessions: [SessionInfo] = []
    private var sentFor: [String: (question: String, at: Date, viaHook: Bool)] = [:]
    static let confirmWindow: TimeInterval = 25

    var hookEnabled: Bool { UserDefaults.standard.bool(forKey: ReplyKey.hook) }
    var terminalEnabled: Bool { UserDefaults.standard.bool(forKey: ReplyKey.terminal) }

    static func supportsTerminal(_ provider: String) -> Bool { TTYLocator.processNames[provider] != nil }

    // MARK: Lifecycle

    /// Starts or stops the hook socket to match the opt-in setting.
    func applySettings() {
        if hookEnabled, server == nil {
            let s = ReplyServer(path: ReplyHookProtocol.socketPath(),
                                handler: { input, box in Task { @MainActor in ReplyCenter.shared.hookArrived(input, box) } },
                                finished: { box in Task { @MainActor in ReplyCenter.shared.hookFinished(box) } })
            do { try s.start(); server = s; serverError = nil } catch { serverError = (error as? ReplyError)?.message ?? error.localizedDescription }
        } else if !hookEnabled, let s = server {
            s.stop(); server = nil
            for r in hookRequests { r.box.resolve(.passthrough) }
            hookRequests = []
        }
        objectWillChange.send()
    }

    var socketActive: Bool { server?.isRunning ?? false }

    // MARK: Questions

    func question(for s: SessionInfo) -> PendingQuestion? {
        if let r = hookRequests.first(where: { $0.input.sessionKey == s.id }) { return r.question }
        return s.state == .offline ? nil : s.pendingQuestion
    }

    func availability(session s: SessionInfo, question q: PendingQuestion) -> ReplyAvailability {
        if q.source == .hook { return .hook }
        guard terminalEnabled else { return .off("Replying from Hubbub is off") }
        guard q.canAnswerInApp else { return .off("This form has several questions") }
        guard Self.supportsTerminal(s.provider) else { return .off("Hubbub can't reach this app's terminal") }
        return .terminal
    }

    // MARK: Hook requests

    private func hookArrived(_ input: HookInput, _ box: DecisionBox) {
        guard hookEnabled, let r = addHookRequest(input, box) else { box.resolve(.passthrough); return }
        ReplyNotifications.postHook(r, sessionName: lastSessions.first { $0.id == input.sessionKey }?.name)
    }

    /// Registers a request for the UI; nil when it must fall through to the terminal prompt.
    func addHookRequest(_ input: HookInput, _ box: DecisionBox) -> HookRequest? {
        guard hookRequests.count < 8, input.toolName != "AskUserQuestion" else { return nil }
        let r = HookRequest(id: UUID().uuidString, nonce: Self.randomNonce(), input: input, box: box, createdAt: Date())
        hookRequests.append(r)
        return r
    }

    private func hookFinished(_ box: DecisionBox) {
        if let r = hookRequests.first(where: { $0.box === box }) { ReplyNotifications.clear(requestID: r.id) }
        hookRequests.removeAll { $0.box === box }
    }

    /// Resolves a hook request only if both id and single-use nonce match a pending request.
    @discardableResult
    func resolveHook(requestID: String, nonce: String, decision: HookDecision) -> Bool {
        guard let r = hookRequests.first(where: { $0.id == requestID && $0.nonce == nonce }), r.box.decision == nil else { return false }
        r.box.resolve(decision)
        if decision != .passthrough { markSent(sessionID: r.input.sessionKey, question: r.id, via: "the hook", viaHook: true) }
        else { status[r.input.sessionKey] = nil }
        return true
    }

    // MARK: Replying

    func reply(_ answer: ReplyAnswer, session s: SessionInfo, question q: PendingQuestion) {
        guard let current = question(for: s), current.id == q.id else {
            status[s.id] = .failed("That question isn't pending any more"); return
        }
        switch availability(session: s, question: q) {
        case .off(let why): status[s.id] = .failed(why)
        case .hook:
            guard let nonce = q.nonce else { return }
            switch answer {
            case .approve: _ = resolveHook(requestID: q.id, nonce: nonce, decision: .allow)
            case .deny: _ = resolveHook(requestID: q.id, nonce: nonce, decision: .deny)
            default: status[s.id] = .failed("Only approve or deny works through the hook")
            }
        case .terminal:
            switch ReplyFormatter.keys(for: answer, question: q, provider: s.provider) {
            case .failure(let e): status[s.id] = .failed(e.message)
            case .success(let keys):
                status[s.id] = .sending
                let ctx = Self.context(for: s)
                let sid = s.id, qid = q.id
                Task.detached {
                    let result = TTYDelivery().deliver(keys, ctx: ctx)
                    await MainActor.run { ReplyCenter.shared.finishDelivery(result, sessionID: sid, question: qid) }
                }
            }
        }
    }

    /// Hands the decision back to the CLI's own prompt (hook requests only).
    func askInTerminal(session s: SessionInfo, question q: PendingQuestion) {
        guard let nonce = q.nonce else { return }
        _ = resolveHook(requestID: q.id, nonce: nonce, decision: .passthrough)
    }

    func dismissStatus(_ sessionID: String) { status[sessionID] = nil; sentFor[sessionID] = nil }

    private func finishDelivery(_ r: DeliveryResult, sessionID: String, question: String) {
        switch r {
        case .sent(let via): markSent(sessionID: sessionID, question: question, via: via, viaHook: false)
        case .failed(let m): status[sessionID] = .failed(m)
        }
    }

    private func markSent(sessionID: String, question: String, via: String, viaHook: Bool) {
        let now = Date()
        status[sessionID] = .sent(via: via, at: now)
        sentFor[sessionID] = (question, now, viaHook)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((Self.confirmWindow + 0.5) * 1_000_000_000))
            self.evaluate(now: Date())
        }
    }

    /// Called whenever sessions refresh: confirms or times out sent replies using the agent's own log.
    func observe(_ sessions: [SessionInfo]) {
        lastSessions = sessions
        evaluate(now: Date())
    }

    private func evaluate(now: Date) {
        for (sid, sent) in sentFor {
            guard case .sent = status[sid] else { continue }
            let s = lastSessions.first { $0.id == sid }
            let resolved = sent.viaHook ? (s.map { $0.lastEvent > sent.at } ?? false)
                                        : (s.map { $0.pendingQuestion?.id != sent.question } ?? false)
            if resolved { status[sid] = .confirmed; sentFor[sid] = nil; scheduleClear(sid) }
            else if now.timeIntervalSince(sent.at) > Self.confirmWindow { status[sid] = .unconfirmed; sentFor[sid] = nil }
        }
    }

    private func scheduleClear(_ sid: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if self.status[sid] == .confirmed { self.status[sid] = nil }
        }
    }

    // MARK: Notification actions

    func handleNotification(actionID: String, text: String?, userInfo: [AnyHashable: Any]) {
        guard let sid = userInfo["sessionID"] as? String, let qid = userInfo["questionID"] as? String else { return }
        if let nonce = userInfo["nonce"] as? String {
            switch actionID {
            case "approve": resolveHook(requestID: qid, nonce: nonce, decision: .allow)
            case "deny": resolveHook(requestID: qid, nonce: nonce, decision: .deny)
            case "terminal": resolveHook(requestID: qid, nonce: nonce, decision: .passthrough)
            default: break
            }
            return
        }
        guard let s = lastSessions.first(where: { $0.id == sid }), let q = question(for: s), q.id == qid else { return }
        switch actionID {
        case "approve": reply(.approve, session: s, question: q)
        case "deny": reply(.deny, session: s, question: q)
        case "text": if let text { reply(.text(text), session: s, question: q) }
        default:
            if actionID.hasPrefix("opt."), let i = Int(actionID.dropFirst(4)) { reply(.choice(i), session: s, question: q) }
        }
    }

    // MARK: Helpers

    static func context(for s: SessionInfo) -> ReplyContext {
        let raw = s.id.hasPrefix("\(s.provider):") ? String(s.id.dropFirst(s.provider.count + 1)) : s.id
        var pids: [Int32] = []
        if s.provider == "copilot" {
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/session-state/\(raw)").path
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasPrefix("inuse.") && f.hasSuffix(".lock") {
                let parts = f.split(separator: ".")
                if parts.count >= 3, let pid = Int32(parts[1]), kill(pid, 0) == 0 { pids.append(pid) }
            }
        }
        return ReplyContext(provider: s.provider, rawID: raw, cwd: s.cwd, hintPIDs: pids)
    }

    static func randomNonce() -> String {
        var b = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, b.count, &b) != errSecSuccess { b = (0..<16).map { _ in UInt8.random(in: 0...255) } }
        return b.map { String(format: "%02x", $0) }.joined()
    }
}
