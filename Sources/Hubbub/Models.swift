import Foundation

enum SessionState: String {
    case working, idle, offline
}

struct ActionRecord: Equatable, Identifiable {
    let id: String
    let time: Date
    let tool: String
    let detail: String
}

enum AttentionLevel: Int, Comparable {
    case none, failed, stuck
    static func < (a: AttentionLevel, b: AttentionLevel) -> Bool { a.rawValue < b.rawValue }
}

enum CallStatus { case running, ok, failed }

struct ToolCallRecord: Equatable, Identifiable {
    let id: String
    let time: Date
    let tool: String
    let detail: String
    var status: CallStatus
}

struct SubAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let model: String
    let startedAt: Date
    var tool: String? = nil
    var busy = false
    var actions: [ActionRecord] = []
    var contextTokens = 0
    var contextLimit = 0
    var toolCalls = 0
    var failures = 0
    var costCredits: Double = 0
    var waitingApproval = false

    var contextFraction: Double { contextLimit > 0 ? min(1, Double(contextTokens) / Double(contextLimit)) : 0 }
    var successRate: Double { toolCalls > 0 ? 1 - Double(failures) / Double(toolCalls) : 1 }
}

struct SessionInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var cwd: String
    var model: String
    var lastEvent: Date
    var state: SessionState
    var currentTool: String?
    var subagents: [SubAgent]
    var inputTokens: Int
    var outputTokens: Int
    var toolCalls: Int
    var actions: [ActionRecord] = []
    var lastFailureAt: Date? = nil
    var branch: String = ""
    var startedAt: Date? = nil
    var lastError: String? = nil
    var recentCalls: [ToolCallRecord] = []
    var inUse = false
    var waitingOnTool = false
    var contextTokens = 0
    var contextLimit = 0
    var failures = 0
    var costCredits: Double = 0
    var waitingApproval = false
    /// What the agent is blocked on, when it can be read from the log (display only).
    var pendingQuestion: PendingQuestion? = nil
    /// Tokens/credits per local day from the event timeline (empty when the provider has no per-event usage).
    var dayUsage: [String: DayUsage] = [:]
    /// Sum of gaps between events (idle gaps capped), nil when unknown.
    var activeSeconds: TimeInterval? = nil

    var contextFraction: Double { contextLimit > 0 ? min(1, Double(contextTokens) / Double(contextLimit)) : 0 }
    var age: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    var successRate: Double { toolCalls > 0 ? 1 - Double(failures) / Double(toolCalls) : 1 }

    /// Id of the AgentProvider that produced this session ("copilot", "claude", "codex", "gemini", "crew").
    var provider: String = "copilot"

    var folder: String { (cwd as NSString).lastPathComponent }
}

struct Quota: Equatable {
    var entitlement: Double
    var remaining: Double
    var percentRemaining: Double
    var used: Double
    var resetDate: String
    var plan: String
    var unlimited: Bool
}
