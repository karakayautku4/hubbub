import Foundation

/// A question an agent is blocked on: a permission request, a multiple-choice question or a free-text question.
/// Parsed read-only from session logs (or received from an opt-in hook); nothing here ever answers anything.
struct PendingQuestion: Equatable, Identifiable {
    enum Kind: Equatable { case permission, choice, freeText }
    enum Source: Equatable { case log, hook }

    struct Option: Equatable, Identifiable {
        var id: Int { index }
        let index: Int
        let label: String
        var detail: String? = nil
    }

    /// toolCallId / requestId from the log, or the hook request id.
    var id: String
    var kind: Kind
    var title: String
    var detail: String? = nil
    var options: [Option] = []
    var allowsFreeText = false
    /// Extra form fields that can only be answered in the terminal (multi-field or multi-select forms).
    var unsupportedFields: [String] = []
    var source: Source = .log
    var toolName: String? = nil
    var askedAt: Date? = nil
    /// Only for `.hook` questions: single-use token the UI/notification must echo to resolve the request.
    var nonce: String? = nil

    var isPermission: Bool { kind == .permission }
    var canAnswerInApp: Bool { unsupportedFields.isEmpty }
}

enum QuestionText {
    static let maxTitle = 600
    static let maxDetail = 500

    /// Removes control and bidi-override characters and bounds the length; agent-provided text is untrusted.
    static func clean(_ s: String, limit: Int, keepNewlines: Bool = false) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u == "\n" || u == "\r" { out.append(keepNewlines && u == "\n" ? "\n" : " "); continue }
            if u == "\t" { out.append(" "); continue }
            if u.value < 0x20 || u.value == 0x7F || (0x80...0x9F).contains(u.value) { continue }
            if (0x202A...0x202E).contains(u.value) || (0x2066...0x2069).contains(u.value) || u.value == 0x200E || u.value == 0x200F { continue }
            out.append(u)
        }
        let t = String(out).trimmingCharacters(in: .whitespaces)
        return t.count > limit ? String(t.prefix(limit - 1)) + "…" : t
    }
}

enum QuestionParser {
    /// Copilot CLI `ask_user`: either `{question, choices?, allow_freeform?}` or `{message, requestedSchema:{properties}}`.
    static func copilotAskUser(id: String, args: [String: Any], at: Date? = nil) -> PendingQuestion? {
        if let q = args["question"] as? String {
            let choices = (args["choices"] as? [Any])?.compactMap { $0 as? String } ?? []
            let free = args["allow_freeform"] as? Bool ?? choices.isEmpty
            return PendingQuestion(
                id: id, kind: choices.isEmpty ? .freeText : .choice,
                title: QuestionText.clean(q, limit: QuestionText.maxTitle),
                options: options(choices), allowsFreeText: free, toolName: "ask_user", askedAt: at)
        }
        guard let msg = args["message"] as? String else { return nil }
        let title = QuestionText.clean(msg, limit: QuestionText.maxTitle)
        let props = (args["requestedSchema"] as? [String: Any])?["properties"] as? [String: Any] ?? [:]
        var fields: [(name: String, title: String, kind: String, choices: [String])] = []
        for (name, raw) in props.sorted(by: { $0.key < $1.key }) {
            guard let p = raw as? [String: Any] else { continue }
            let t = QuestionText.clean(p["title"] as? String ?? name, limit: 120)
            if let e = p["enum"] as? [Any] { fields.append((name, t, "single", e.compactMap { $0 as? String })) }
            else if (p["type"] as? String) == "array", let e = (p["items"] as? [String: Any])?["enum"] as? [Any] {
                fields.append((name, t, "multi", e.compactMap { $0 as? String }))
            } else { fields.append((name, t, p["type"] as? String ?? "text", [])) }
        }
        if fields.isEmpty { return PendingQuestion(id: id, kind: .freeText, title: title, allowsFreeText: true, toolName: "ask_user", askedAt: at) }
        if fields.count == 1, fields[0].kind == "single" {
            return PendingQuestion(id: id, kind: .choice, title: title.isEmpty ? fields[0].title : title,
                                   options: options(fields[0].choices), toolName: "ask_user", askedAt: at)
        }
        if fields.count == 1, fields[0].kind == "string" || fields[0].kind == "text" {
            return PendingQuestion(id: id, kind: .freeText, title: title, allowsFreeText: true, toolName: "ask_user", askedAt: at)
        }
        return PendingQuestion(id: id, kind: .choice, title: title, unsupportedFields: fields.map(\.title),
                               toolName: "ask_user", askedAt: at)
    }

    /// Copilot CLI `permission.requested` event data.
    static func copilotPermission(data: [String: Any], at: Date? = nil) -> PendingQuestion? {
        guard let rid = data["requestId"] as? String else { return nil }
        let req = data["permissionRequest"] as? [String: Any] ?? [:]
        let kind = req["kind"] as? String ?? "tool"
        let intention = (req["intention"] as? String).map { QuestionText.clean($0, limit: 200) }
        var detail: String?
        let title: String
        switch kind {
        case "shell":
            title = "Run a shell command?"
            detail = req["fullCommandText"] as? String
        case "write":
            title = "Change a file?"
            detail = req["fileName"] as? String
        case "read": title = "Read a file?"; detail = req["path"] as? String ?? req["fileName"] as? String
        case "url": title = "Open a URL?"; detail = (req["urls"] as? [String])?.joined(separator: ", ") ?? req["url"] as? String
        case "mcp":
            title = "Use an MCP tool?"
            detail = [req["serverName"] as? String, req["toolName"] as? String].compactMap { $0 }.joined(separator: " · ")
        default: title = "Allow this action?"
        }
        var d = detail.map { QuestionText.clean($0, limit: QuestionText.maxDetail) }
        if let i = intention, !i.isEmpty { d = d.map { "\(i)\n\($0)" } ?? i }
        return PendingQuestion(id: rid, kind: .permission, title: title, detail: d, options: approveDeny,
                               toolName: kind, askedAt: at)
    }

    /// Claude Code `AskUserQuestion` tool input: `{questions:[{question, header, options:[{label, description}], multiSelect}]}`.
    static func claudeAskUserQuestion(id: String, input: [String: Any], at: Date? = nil) -> PendingQuestion? {
        guard let qs = input["questions"] as? [[String: Any]], let first = qs.first,
              let text = first["question"] as? String else { return nil }
        let opts = (first["options"] as? [[String: Any]] ?? []).enumerated().compactMap { i, o -> PendingQuestion.Option? in
            guard let l = o["label"] as? String else { return nil }
            return PendingQuestion.Option(index: i, label: QuestionText.clean(l, limit: 160),
                                          detail: (o["description"] as? String).map { QuestionText.clean($0, limit: 200) })
        }
        var unsupported: [String] = []
        if qs.count > 1 { unsupported = qs.dropFirst().compactMap { ($0["header"] as? String) ?? ($0["question"] as? String) } }
        if first["multiSelect"] as? Bool == true { unsupported.append("multi-select") }
        return PendingQuestion(id: id, kind: opts.isEmpty ? .freeText : .choice, title: QuestionText.clean(text, limit: QuestionText.maxTitle),
                               options: opts, allowsFreeText: true, unsupportedFields: unsupported, toolName: "AskUserQuestion", askedAt: at)
    }

    /// Codex approval / elicitation events and Gemini `awaiting_approval` calls: a generic approve/deny question.
    static func genericApproval(id: String, title: String, detail: String?, tool: String?, at: Date? = nil) -> PendingQuestion {
        PendingQuestion(id: id, kind: .permission, title: title,
                        detail: detail.map { QuestionText.clean($0, limit: QuestionText.maxDetail) },
                        options: approveDeny, toolName: tool, askedAt: at)
    }

    static let approveDeny = [PendingQuestion.Option(index: 0, label: "Approve"), PendingQuestion.Option(index: 1, label: "Deny")]

    private static func options(_ labels: [String]) -> [PendingQuestion.Option] {
        labels.enumerated().map { PendingQuestion.Option(index: $0, label: QuestionText.clean($1, limit: 160)) }
    }
}
