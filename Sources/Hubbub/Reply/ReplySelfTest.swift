import Foundation
import Darwin

/// `Hubbub --selftest-reply`: fixtures only. No GUI automation, no real terminals, no user data touched.
/// The socket round-trip runs against a scratch folder, never the real reply socket.
enum ReplySelfTest {
    struct FakeRunner: CommandRunner {
        var handler: (String, [String]) -> CommandResult
        func run(_ exe: String, _ args: [String]) -> CommandResult { handler(exe, args) }
    }

    @MainActor static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "ok   " : "FAIL ", name)
            if !ok { failures += 1 }
        }
        parsing(check)
        logIntegration(check)
        formatting(check)
        locating(check)
        channels(check)
        hookProtocol(check)
        socketRoundTrip(check)
        center(check)
        print(failures == 0 ? "reply selftest OK" : "reply selftest FAILED (\(failures))")
        return failures == 0
    }

    // MARK: Question parsing

    static func parsing(_ check: (String, Bool) -> Void) {
        let simple = QuestionParser.copilotAskUser(id: "c1", args: ["question": "Which target?", "choices": ["Markdown (Recommended)", "Confluence"], "allow_freeform": false])
        check("ask_user choices → 2 options, no free text", simple?.kind == .choice && simple?.options.count == 2 && simple?.allowsFreeText == false)
        let free = QuestionParser.copilotAskUser(id: "c2", args: ["question": "What constraint?"])
        check("ask_user without choices → free text", free?.kind == .freeText && free?.allowsFreeText == true)
        let oneField = QuestionParser.copilotAskUser(id: "c3", args: ["message": "Pick one", "requestedSchema": ["properties": ["g": ["type": "string", "title": "Graphics", "enum": ["A", "B", "C"]]]]])
        check("schema with one enum → options", oneField?.kind == .choice && oneField?.options.map(\.label) == ["A", "B", "C"] && oneField?.canAnswerInApp == true)
        let multi = QuestionParser.copilotAskUser(id: "c4", args: ["message": "Pick", "requestedSchema": ["properties": [
            "alive": ["type": "array", "title": "Alive", "items": ["type": "string", "enum": ["x", "y"]]],
            "g": ["type": "string", "title": "Graphics", "enum": ["A"]]]]])
        check("multi-field form is read-only", multi?.canAnswerInApp == false && multi?.unsupportedFields.count == 2)
        let multiSel = QuestionParser.copilotAskUser(id: "c5", args: ["message": "Pick", "requestedSchema": ["properties": ["alive": ["type": "array", "title": "Alive", "items": ["type": "string", "enum": ["x"]]]]]])
        check("multi-select is read-only", multiSel?.canAnswerInApp == false)
        check("ask_user garbage → nil", QuestionParser.copilotAskUser(id: "x", args: ["foo": 1]) == nil)

        let shell = QuestionParser.copilotPermission(data: ["requestId": "r1", "permissionRequest": ["kind": "shell", "fullCommandText": "git status", "intention": "Check status"]])
        check("permission shell → approve/deny with command", shell?.isPermission == true && shell?.detail == "Check status\ngit status" && shell?.options.count == 2)
        let write = QuestionParser.copilotPermission(data: ["requestId": "r2", "permissionRequest": ["kind": "write", "fileName": "/a/b.py", "diff": "secret diff"]])
        check("permission write shows file, not diff", write?.title == "Change a file?" && write?.detail == "/a/b.py")
        check("permission without id → nil", QuestionParser.copilotPermission(data: ["permissionRequest": ["kind": "shell"]]) == nil)

        let claude = QuestionParser.claudeAskUserQuestion(id: "t1", input: ["questions": [["question": "Which DB?", "header": "DB", "multiSelect": false,
            "options": [["label": "Postgres", "description": "relational"], ["label": "SQLite"]]]]])
        check("Claude AskUserQuestion → options with detail", claude?.options.count == 2 && claude?.options.first?.detail == "relational" && claude?.canAnswerInApp == true)
        let claude2 = QuestionParser.claudeAskUserQuestion(id: "t2", input: ["questions": [["question": "A?", "options": []], ["question": "B?", "header": "B"]]])
        check("Claude multi-question is read-only", claude2?.canAnswerInApp == false)

        let nasty = QuestionText.clean("rm\u{202E} -rf\u{0007}\nok\t/", limit: 100)
        check("sanitizer strips control + bidi", nasty == "rm -rf ok /")
        check("sanitizer truncates", QuestionText.clean(String(repeating: "a", count: 50), limit: 10).count == 10)
    }

    // MARK: Detection from logs

    static func logIntegration(_ check: (String, Bool) -> Void) {
        func lines(_ objs: [[String: Any]]) -> [Substring] {
            objs.map { Substring(String(decoding: (try? JSONSerialization.data(withJSONObject: $0)) ?? Data(), as: UTF8.self)) }
        }
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        let ask: [String: Any] = ["type": "assistant", "timestamp": ts, "cwd": "/w",
            "message": ["id": "m", "content": [["type": "tool_use", "id": "q1", "name": "AskUserQuestion",
                "input": ["questions": [["question": "Which?", "options": [["label": "One"], ["label": "Two"]]]]]]]]]
        let pending = ClaudeCodeProvider.parse(lines: lines([ask]), id: "abc12345", modified: now)
        check("claude log: pending question surfaced", pending.pendingQuestion?.title == "Which?" && pending.waitingApproval)
        let answered = ClaudeCodeProvider.parse(lines: lines([ask, ["type": "user", "timestamp": ts, "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "q1"]]]]]),
                                                id: "abc12345", modified: now)
        check("claude log: cleared after tool_result", answered.pendingQuestion == nil && !answered.waitingApproval)

        // Copilot events.jsonl in a scratch folder
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hubbub/reply-selftest-\(getpid())-log", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ events: [[String: Any]]) {
            let text = events.map { String(decoding: (try? JSONSerialization.data(withJSONObject: $0)) ?? Data(), as: UTF8.self) }.joined(separator: "\n")
            try? text.write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        }
        let perm: [String: Any] = ["type": "permission.requested", "timestamp": ts,
            "data": ["requestId": "rq1", "permissionRequest": ["kind": "shell", "fullCommandText": "ls -la"]]]
        let askStart: [String: Any] = ["type": "tool.execution_start", "timestamp": ts,
            "data": ["toolCallId": "tc1", "toolName": "ask_user", "arguments": ["question": "Go?", "choices": ["Yes", "No"]]]]
        write([perm, askStart])
        let a = SessionMonitor.parse(dir: dir, modified: now)
        check("copilot log: newest pending question surfaced", a?.pendingQuestion != nil && a?.waitingApproval == true)
        write([perm, ["type": "permission.completed", "timestamp": ts, "data": ["requestId": "rq1", "result": ["kind": "approved"]]], askStart])
        let b = SessionMonitor.parse(dir: dir, modified: now)
        check("copilot log: permission resolved, ask_user still pending", b?.pendingQuestion?.title == "Go?")
        write([perm, askStart, ["type": "tool.execution_complete", "timestamp": ts, "data": ["toolCallId": "tc1", "success": true]],
               ["type": "permission.completed", "timestamp": ts, "data": ["requestId": "rq1"]]])
        let c = SessionMonitor.parse(dir: dir, modified: now)
        check("copilot log: everything answered → none pending", c?.pendingQuestion == nil && c?.waitingApproval == false)
        write([perm, ["type": "session.shutdown", "timestamp": ts, "data": [:]]])
        check("copilot log: ended session shows nothing", SessionMonitor.parse(dir: dir, modified: now)?.pendingQuestion == nil)
    }

    // MARK: Keystrokes

    static func formatting(_ check: (String, Bool) -> Void) {
        let perm = QuestionParser.genericApproval(id: "p", title: "Run?", detail: "ls", tool: "shell")
        let choice = QuestionParser.copilotAskUser(id: "c", args: ["question": "Q", "choices": ["a", "b", "c"], "allow_freeform": false])!
        let free = QuestionParser.copilotAskUser(id: "f", args: ["question": "Q"])!
        func keys(_ a: ReplyAnswer, _ q: PendingQuestion) -> [KeyStroke]? { if case .success(let k) = ReplyFormatter.keys(for: a, question: q, provider: "copilot") { return k }; return nil }
        check("approve → Enter", keys(.approve, perm) == [.enter])
        check("deny → Escape", keys(.deny, perm) == [.escape])
        check("choice 2 → Down Down Enter", keys(.choice(2), choice) == [.down, .down, .enter])
        check("choice 0 → Enter", keys(.choice(0), choice) == [.enter])
        check("choice out of range rejected", keys(.choice(5), choice) == nil)
        check("approve on a choice question rejected", keys(.approve, choice) == nil)
        check("free text → text + Enter, sanitized", keys(.text("hello\nworld\u{1B}[B"), free) == [.text("hello world[B"), .enter])
        check("empty text rejected", keys(.text("  "), free) == nil)
        check("text on strict choice rejected", keys(.text("x"), choice) == nil)
        check("text length capped", { if case .text(let t)? = keys(.text(String(repeating: "a", count: 5000)), free)?.first { return t.count == ReplyFormatter.maxTextLength }; return false }())
        check("raw bytes for iTerm", [KeyStroke.down, .enter].map(\.raw).joined() == "\u{1B}[B\r")
    }

    // MARK: Finding the terminal

    static let psFixture = """
      100     1 ??       /Applications/Foo.app/Contents/MacOS/Foo --flag
    19012 18000 ttys000  copilot
    19230 19012 ttys000  /opt/homebrew/Caskroom/copilot-cli/1.0.19/copilot --session-id 346e5e54-db48-4c06-bb09-9b9bd6d53236
    20000 19999 ttys004  node /usr/local/bin/claude --resume 11111111-2222-3333-4444-555555555555
    20100 19999 ttys005  claude
    20200 19999 ttys006  claude
    30000     1 ??       sh -c copilot-detached-supervisor
    """

    static func locating(_ check: (String, Bool) -> Void) {
        let rows = TTYLocator.parsePS(psFixture)
        check("ps parsed", rows.count == 7 && rows[2].tty == "ttys000" && rows[2].command.contains("--session-id"))
        let none: (Int32) -> String? = { _ in nil }
        check("locate by session id", TTYLocator.locate(provider: "copilot", rawID: "346e5e54-db48-4c06-bb09-9b9bd6d53236", cwd: "", hintPIDs: [], rows: rows, cwdOf: none) == .found(tty: "ttys000", how: "session id"))
        check("locate Claude by --resume id", TTYLocator.locate(provider: "claude", rawID: "11111111-2222-3333-4444-555555555555", cwd: "", hintPIDs: [], rows: rows, cwdOf: none) == .found(tty: "ttys004", how: "session id"))
        check("locate by lock pid", TTYLocator.locate(provider: "copilot", rawID: "zzzzzzzz-unknown", cwd: "", hintPIDs: [19230], rows: rows, cwdOf: none) == .found(tty: "ttys000", how: "process lock"))
        check("two agents in same cwd → ambiguous", TTYLocator.locate(provider: "claude", rawID: "none-none-none", cwd: "/w", hintPIDs: [], rows: rows, cwdOf: { $0 == 20100 || $0 == 20200 ? "/w" : nil }) == .ambiguous(2))
        check("unique cwd match", TTYLocator.locate(provider: "claude", rawID: "none-none-none", cwd: "/w", hintPIDs: [], rows: rows, cwdOf: { $0 == 20100 ? "/w" : "/other" }) == .found(tty: "ttys005", how: "working directory"))
        check("no match → notFound", TTYLocator.locate(provider: "codex", rawID: "none-none-none", cwd: "/w", hintPIDs: [], rows: rows, cwdOf: { _ in "/w" }) == .notFound)
        check("processes without tty ignored", TTYLocator.locate(provider: "copilot", rawID: "zzzzzzzz-unknown", cwd: "", hintPIDs: [30000], rows: rows, cwdOf: none) == .notFound)
    }

    // MARK: Channels (fake runner)

    @MainActor static func channels(_ check: (String, Bool) -> Void) {
        let env = ReplyEnvironment(fileExists: { $0 == "/opt/homebrew/bin/tmux" }, isAppRunning: { $0 == "com.apple.Terminal" })
        check("tmux pane parse", TmuxPanes.parse("%1\t/dev/ttys000\n%2\t/dev/ttys001\n") == ["/dev/ttys000": "%1", "/dev/ttys001": "%2"])
        check("tmux commands", TmuxPanes.commands(for: [.text("-hi"), .enter, .down, .escape], pane: "%1") == [
            ["send-keys", "-t", "%1", "-l", "--", "-hi"], ["send-keys", "-t", "%1", "Enter"], ["send-keys", "-t", "%1", "Down"], ["send-keys", "-t", "%1", "Escape"]])

        final class Box { var calls: [[String]] = [] }
        let box = Box()
        let tmux = FakeRunner { exe, args in
            box.calls.append([exe] + args)
            if args.first == "list-panes" { return CommandResult(status: 0, out: "%7\t/dev/ttys000\n", err: "") }
            return CommandResult(status: 0, out: "", err: "")
        }
        check("tmux delivers to matching pane", TmuxChannel(runner: tmux, env: env).deliver([.text("hi"), .enter], tty: "ttys000") == .sent("tmux")
              && box.calls.last == ["/opt/homebrew/bin/tmux", "send-keys", "-t", "%7", "Enter"])
        check("tmux: other tty → not applicable", { if case .notApplicable = TmuxChannel(runner: tmux, env: env).deliver([.enter], tty: "ttys009") { return true }; return false }())
        let tmuxDown = FakeRunner { _, _ in CommandResult(status: 1, out: "", err: "no server running") }
        check("tmux: no server → not applicable", { if case .notApplicable = TmuxChannel(runner: tmuxDown, env: env).deliver([.enter], tty: "ttys000") { return true }; return false }())
        let tmuxRefuse = FakeRunner { _, a in a.first == "list-panes" ? CommandResult(status: 0, out: "%7\t/dev/ttys000\n", err: "") : CommandResult(status: 1, out: "", err: "can't find pane") }
        check("tmux: send failure reported", { if case .failed = TmuxChannel(runner: tmuxRefuse, env: env).deliver([.enter], tty: "ttys000") { return true }; return false }())

        check("Terminal payload: text+Enter", AppleScriptChannel.payload([.text("yes"), .enter], for: .terminal) == "yes")
        check("Terminal payload: bare Enter", AppleScriptChannel.payload([.enter], for: .terminal) == "")
        check("Terminal payload: arrows unsupported", AppleScriptChannel.payload([.down, .enter], for: .terminal) == nil)
        check("Terminal payload: Escape unsupported", AppleScriptChannel.payload([.escape], for: .terminal) == nil)
        check("iTerm payload: raw bytes", AppleScriptChannel.payload([.down, .enter], for: .iterm) == "\u{1B}[B\r")
        check("script never embeds the tty/payload", !AppleScriptChannel.script(for: .terminal).joined().contains("ttys") && AppleScriptChannel.script(for: .iterm).joined().contains("write text payload newline NO"))

        let osa = FakeRunner { exe, args in
            box.calls.append([exe] + args)
            return CommandResult(status: 0, out: "ok\n", err: "")
        }
        check("Terminal.app delivers via osascript argv", AppleScriptChannel(app: .terminal, runner: osa, env: env).deliver([.text("go"), .enter], tty: "ttys001") == .sent("Terminal")
              && Array(box.calls.last!.suffix(3)) == ["--", "/dev/ttys001", "go"])
        let osaDenied = FakeRunner { _, _ in CommandResult(status: 1, out: "", err: "execution error: Not authorized to send Apple events to Terminal. (-1743)") }
        if case .failed(let m) = AppleScriptChannel(app: .terminal, runner: osaDenied, env: env).deliver([.enter], tty: "ttys001") { check("Automation denied → explained", m.contains("Automation")) } else { check("Automation denied → explained", false) }
        let osaNone = FakeRunner { _, _ in CommandResult(status: 0, out: "notfound\n", err: "") }
        check("tab not found → not applicable", { if case .notApplicable = AppleScriptChannel(app: .terminal, runner: osaNone, env: env).deliver([.enter], tty: "ttys001") { return true }; return false }())
        check("app not running → not applicable (never launched)", { if case .notApplicable = AppleScriptChannel(app: .iterm, runner: osa, env: env).deliver([.enter], tty: "ttys001") { return true }; return false }())

        // End-to-end with fakes: ps → locate → tmux
        func full(_ tmuxOut: String, apps: Set<String> = []) -> TTYDelivery {
            let r = FakeRunner { exe, args in
                switch exe {
                case "/bin/ps": return CommandResult(status: 0, out: psFixture, err: "")
                case "/usr/sbin/lsof": return CommandResult(status: 0, out: "p1\nn/w\n", err: "")
                case "/opt/homebrew/bin/tmux": return args.first == "list-panes" ? CommandResult(status: 0, out: tmuxOut, err: "") : CommandResult(status: 0, out: "", err: "")
                default: return CommandResult(status: 0, out: "notfound", err: "")
                }
            }
            return TTYDelivery(runner: r, env: ReplyEnvironment(fileExists: { $0 == "/opt/homebrew/bin/tmux" }, isAppRunning: { apps.contains($0) }))
        }
        let ctx = ReplyContext(provider: "copilot", rawID: "346e5e54-db48-4c06-bb09-9b9bd6d53236", cwd: "/w")
        check("end-to-end tmux", full("%1\t/dev/ttys000\n").deliver([.enter], ctx: ctx) == .sent(via: "tmux"))
        if case .failed(let m) = full("%1\t/dev/ttys099\n").deliver([.enter], ctx: ctx) { check("no usable channel → failed with explanation", m.contains("tmux, iTerm2 or Terminal.app")) } else { check("no usable channel → failed with explanation", false) }
        if case .failed(let m) = full("").deliver([.enter], ctx: ReplyContext(provider: "gemini", rawID: "nope-nope-nope", cwd: "/w")) { check("unknown session → couldn't find terminal", m.contains("find the terminal")) } else { check("unknown session → couldn't find terminal", false) }
        let ambiguous = ReplyContext(provider: "claude", rawID: "nope-nope-nope", cwd: "/w")
        if case .failed(let m) = full("").deliver([.enter], ctx: ambiguous) { check("two matching terminals → won't guess", m.contains("won't guess")) } else { check("two matching terminals → won't guess", false) }

        let specs = ReplyNotifications.actionSpecs(for: QuestionParser.copilotAskUser(id: "c", args: ["question": "Q", "choices": ["a", "b", "c", "d", "e"], "allow_freeform": true])!, viaHook: false)
        check("notification: ≤3 options + text reply", specs.map(\.id) == ["opt.0", "opt.1", "opt.2", "text"])
        check("notification: permission Approve/Deny (+terminal for hooks)",
              ReplyNotifications.actionSpecs(for: QuestionParser.genericApproval(id: "p", title: "t", detail: nil, tool: nil), viaHook: true).map(\.id) == ["approve", "deny", "terminal"])
        let form = QuestionParser.copilotAskUser(id: "m", args: ["message": "x", "requestedSchema": ["properties": ["a": ["type": "array", "items": ["enum": ["1"]]]]]])!
        check("notification: unsupported form has no actions", ReplyNotifications.actionSpecs(for: form, viaHook: false).isEmpty)
    }

    // MARK: Hook protocol

    static func hookProtocol(_ check: (String, Bool) -> Void) {
        func req(_ format: String, _ input: [String: Any], timeout: Double = 30) -> Data {
            (try? JSONSerialization.data(withJSONObject: ["v": 1, "format": format, "timeout": timeout, "input": input])) ?? Data()
        }
        let c = ReplyHookProtocol.parseRequest(req("claude", ["session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "rm -rf x", "description": "cleanup"], "cwd": "/w"]))
        check("claude input parsed", c?.sessionKey == "claude:s1" && c?.toolName == "Bash" && c?.detail == "cleanup\nrm -rf x" && c?.timeout == 30)
        let p = ReplyHookProtocol.parseRequest(req("copilot", ["sessionId": "abc", "toolName": "bash", "toolInput": "{\"command\":\"ls\"}"]))
        check("copilot input parsed (camelCase, JSON-string args)", p?.sessionKey == "abc" && p?.detail == "ls")
        check("bad version / format / missing fields rejected",
              ReplyHookProtocol.parseRequest(Data("{\"v\":2}".utf8)) == nil && ReplyHookProtocol.parseRequest(req("other", ["session_id": "s", "tool_name": "x"])) == nil
              && ReplyHookProtocol.parseRequest(req("claude", ["tool_name": "x"])) == nil && ReplyHookProtocol.parseRequest(Data("nope".utf8)) == nil)
        check("timeout clamped", ReplyHookProtocol.parseRequest(req("claude", ["session_id": "s", "tool_name": "x"], timeout: 99999))?.timeout == 300)
        check("claude allow output", ReplyHookProtocol.render(format: "claude", decision: .allow, message: nil) == "{\"hookSpecificOutput\":{\"decision\":{\"behavior\":\"allow\"},\"hookEventName\":\"PermissionRequest\"}}")
        check("claude deny output has reason", ReplyHookProtocol.render(format: "claude", decision: .deny, message: nil).contains("Denied by the user in Hubbub"))
        check("copilot allow output", ReplyHookProtocol.render(format: "copilot", decision: .allow, message: nil) == "{\"behavior\":\"allow\"}")
        check("copilot deny output", ReplyHookProtocol.render(format: "copilot", decision: .deny, message: nil).contains("\"behavior\":\"deny\""))
        check("passthrough prints nothing", ReplyHookProtocol.render(format: "claude", decision: .passthrough, message: nil).isEmpty)

        let claudeCfg = ReplyHookConfig.claude(executable: "/Applications/Hubbub.app/Contents/MacOS/Hubbub")
        let copilotCfg = ReplyHookConfig.copilot(executable: "/Applications/Hubbub.app/Contents/MacOS/Hubbub")
        check("generated Claude config", claudeCfg.contains("\"PermissionRequest\"") && claudeCfg.contains("--reply-hook") && (try? JSONSerialization.jsonObject(with: Data(claudeCfg.utf8))) != nil)
        check("generated Copilot config", copilotCfg.contains("\"permissionRequest\"") && copilotCfg.contains("\"exec\"") && (try? JSONSerialization.jsonObject(with: Data(copilotCfg.utf8))) != nil)
    }

    // MARK: Real socket round trip in a scratch folder

    static func socketRoundTrip(_ check: (String, Bool) -> Void) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hubbub/reply-selftest-\(getpid())", isDirectory: true)
        let path = dir.appendingPathComponent("r.sock").path
        defer { try? FileManager.default.removeItem(at: dir) }

        final class Seen: @unchecked Sendable { var inputs: [HookInput] = []; var finished = 0; var gone = 0; let lock = NSLock() }
        let seen = Seen()
        // Test stand-in for the user: decides by tool name. The product never answers by itself.
        let server = ReplyServer(path: path, handler: { input, box in
            seen.lock.lock(); seen.inputs.append(input); seen.lock.unlock()
            switch input.toolName {
            case "Allow": box.resolve(.allow)
            case "Deny": box.resolve(.deny, message: "nope")
            case "Pass": box.resolve(.passthrough)
            default: break
            }
        }, finished: { box in seen.lock.lock(); seen.finished += 1; if box.gone { seen.gone += 1 }; seen.lock.unlock() })
        do { try server.start() } catch { check("server starts (\(error))", false); return }
        defer { server.stop() }

        var st = stat()
        check("socket is 0600", stat(path, &st) == 0 && (st.st_mode & 0o777) == 0o600 && (st.st_mode & S_IFMT) == S_IFSOCK)
        var dst = stat()
        check("folder is 0700", stat(dir.path, &dst) == 0 && (dst.st_mode & 0o777) == 0o700)

        func call(_ tool: String, format: String = "claude", timeout: TimeInterval = 5) -> String {
            let input = (try? JSONSerialization.data(withJSONObject: ["session_id": "s1", "sessionId": "s1", "tool_name": tool, "toolName": tool, "tool_input": ["command": "x"]])) ?? Data()
            return ReplyHookClient.run(format: format, stdin: input, timeout: timeout, socketPath: path)
        }
        check("round trip allow (claude)", call("Allow").contains("\"behavior\":\"allow\""))
        check("round trip deny carries message", call("Deny").contains("nope"))
        check("round trip allow (copilot)", call("Allow", format: "copilot") == "{\"behavior\":\"allow\"}")
        check("round trip passthrough → empty output", call("Pass").isEmpty)
        let t0 = Date()
        check("no answer → falls through at timeout", call("Wait", timeout: 5).isEmpty && Date().timeIntervalSince(t0) >= 4.5 && Date().timeIntervalSince(t0) < 9)

        // client that disappears is detected
        let gone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = ReplyHookClient.run(format: "claude", stdin: Data("{\"session_id\":\"g\",\"tool_name\":\"Wait\"}".utf8), timeout: 5, socketPath: path)
            gone.signal()
        }
        Thread.sleep(forTimeInterval: 0.5)
        check("server saw the pending request", seen.lock.withLock { seen.inputs.contains { $0.sessionID == "g" } })
        _ = gone.wait(timeout: .now() + 8)

        // garbage and oversize input never produce a decision
        func raw(_ bytes: Data) -> String {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(fd) }
            var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &addr.sun_path) { r in for (i, b) in Array(path.utf8).enumerated() { r[i] = b } }
            let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            guard rc == 0 else { return "connect failed" }
            var nosig: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
            _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, bytes.count) }
            var tv = timeval(tv_sec: 4, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var buf = [UInt8](repeating: 0, count: 512)
            let n = read(fd, &buf, buf.count)
            return n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
        }
        check("malformed request → passthrough, no decision", raw(Data("not json\n".utf8)).contains("passthrough"))
        check("oversized request dropped", !raw(Data(repeating: 65, count: ReplyHookProtocol.maxRequestBytes + 4096)).contains("allow"))

        server.stop()
        check("stop removes the socket", !FileManager.default.fileExists(atPath: path))
        check("client without server → empty output immediately", ReplyHookClient.run(format: "claude", stdin: Data("{\"session_id\":\"a\",\"tool_name\":\"b\"}".utf8), timeout: 5, socketPath: path).isEmpty)
        check("client with invalid stdin → empty output", ReplyHookClient.run(format: "claude", stdin: Data("junk".utf8), timeout: 5, socketPath: path).isEmpty)
    }

    // MARK: ReplyCenter state machine (no sockets, no UI)

    @MainActor static func center(_ check: (String, Bool) -> Void) {
        let c = ReplyCenter.shared
        let input = HookInput(format: "claude", sessionID: "s9", toolName: "Bash", detail: "ls", cwd: "/w", timeout: 30)
        let box = DecisionBox()
        guard let r = c.addHookRequest(input, box) else { check("hook request registered", false); return }
        var info = SessionInfo(id: "claude:s9", name: "demo", cwd: "/w", model: "", lastEvent: Date(), state: .working, currentTool: nil,
                               subagents: [], inputTokens: 0, outputTokens: 0, toolCalls: 0)
        info.provider = "claude"
        check("hook question shown for matching session", c.question(for: info)?.id == r.id && c.question(for: info)?.source == .hook)
        check("wrong nonce refused", !c.resolveHook(requestID: r.id, nonce: "deadbeef", decision: .allow) && box.decision == nil)
        check("unknown request refused", !c.resolveHook(requestID: "nope", nonce: r.nonce, decision: .allow))
        check("nonce is random hex", r.nonce.count == 32 && ReplyCenter.randomNonce() != ReplyCenter.randomNonce())
        check("text answer refused on hook question", { c.reply(.text("hi"), session: info, question: r.question); return box.decision == nil }())
        c.reply(.approve, session: info, question: r.question)
        check("approve resolves the hook with allow", box.decision?.0 == .allow)
        check("status says sent, not confirmed", { if case .sent = c.status["claude:s9"] { return true }; return false }())
        check("second resolve refused (single use)", !c.resolveHook(requestID: r.id, nonce: r.nonce, decision: .deny) && box.decision?.0 == .allow)
        var later = info; later.lastEvent = Date().addingTimeInterval(2)
        c.observe([later])
        check("confirmed only after the agent's log moves on", c.status["claude:s9"] == .confirmed)
        c.dismissStatus("claude:s9")

        // log question without opt-in: refuses, never types
        UserDefaults.standard.removeObject(forKey: ReplyKey.terminal)
        var logged = info; logged.id = "codex:z"; logged.provider = "codex"
        logged.pendingQuestion = QuestionParser.genericApproval(id: "cx", title: "Run?", detail: "ls", tool: "exec")
        check("terminal channel off by default", c.availability(session: logged, question: logged.pendingQuestion!) == .off("Replying from Hubbub is off"))
        c.reply(.approve, session: logged, question: logged.pendingQuestion!)
        check("reply refused while channel is off", { if case .failed = c.status["codex:z"] { return true }; return false }())
        c.reply(.approve, session: logged, question: QuestionParser.genericApproval(id: "stale", title: "x", detail: nil, tool: nil))
        check("stale question id refused", { if case .failed(let m) = c.status["codex:z"] { return m.contains("isn't pending") }; return false }())
        c.dismissStatus("codex:z")
        logged.state = .offline
        check("offline session shows no question", c.question(for: logged) == nil)
    }
}
