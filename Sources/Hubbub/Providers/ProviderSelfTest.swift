import Foundation

/// `Hubbub --selftest-providers`: parses synthetic fixtures for every provider (headless, no UI, no real data).
enum ProviderSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "ok   " : "FAIL ", name)
            if !ok { failures += 1 }
        }
        func lines(_ objs: [[String: Any]]) -> [Substring] {
            objs.map { Substring(String(decoding: (try? JSONSerialization.data(withJSONObject: $0)) ?? Data(), as: UTF8.self)) }
        }
        let now = Date()
        func ts(_ ago: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago)) }

        // Claude Code: one running Read, a running Task sub-agent with a sidechain Bash, a failed Edit
        let claude = ClaudeCodeProvider.parse(lines: lines([
            ["type": "assistant", "timestamp": ts(30), "cwd": "/work/demo", "gitBranch": "main",
             "message": ["id": "m1", "model": "claude-sonnet-4", "usage": ["input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 100],
                         "content": [["type": "tool_use", "id": "t1", "name": "Edit", "input": ["file_path": "a.swift"]],
                                     ["type": "tool_use", "id": "t2", "name": "Task", "input": ["subagent_type": "explore", "description": "look"]]]]],
            ["type": "user", "timestamp": ts(25), "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "is_error": true]]]],
            ["type": "assistant", "timestamp": ts(3), "isSidechain": true,
             "message": ["id": "m2", "content": [["type": "tool_use", "id": "t3", "name": "Bash", "input": ["command": "ls"]]]]],
        ]), id: "abc12345", modified: now)
        check("claude: id prefixed", claude.id == "claude:abc12345" && claude.provider == "claude")
        check("claude: working with sub-agent", claude.state == .working && claude.subagents.count == 1)
        check("claude: sidechain tool on sub-agent", claude.subagents.first?.tool == "bash" && claude.subagents.first?.busy == true)
        check("claude: failure + tokens + model", claude.failures == 1 && claude.inputTokens == 10 && claude.outputTokens == 5 && claude.model == "claude-sonnet-4")
        check("claude: malformed lines ignored", ClaudeCodeProvider.parse(lines: ["{not json", "[]", ""], id: "x", modified: now.addingTimeInterval(-7200)).state == .offline)

        // Codex
        let codex = CodexProvider.parse(lines: lines([
            ["timestamp": ts(40), "type": "session_meta", "payload": ["id": "u", "cwd": "/work/cx", "git": ["branch": "dev"]]],
            ["timestamp": ts(39), "type": "turn_context", "payload": ["model": "gpt-5-codex"]],
            ["timestamp": ts(20), "type": "response_item", "payload": ["type": "function_call", "name": "shell", "call_id": "c1", "arguments": "{\"command\":[\"ls\"]}"]],
            ["timestamp": ts(19), "type": "response_item", "payload": ["type": "function_call_output", "call_id": "c1", "output": "{\"metadata\":{\"exit_code\":2}}"]],
            ["timestamp": ts(2), "type": "response_item", "payload": ["type": "function_call", "name": "apply_patch", "call_id": "c2", "arguments": "{}"]],
            ["timestamp": ts(1), "type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": 100, "cached_input_tokens": 40, "output_tokens": 7], "model_context_window": 200000]]],
        ]), id: "u", modified: now)
        check("codex: meta + model", codex.cwd == "/work/cx" && codex.model == "gpt-5-codex" && codex.branch == "dev")
        check("codex: failed exit code + running patch", codex.failures == 1 && codex.currentTool == "edit" && codex.state == .working)
        check("codex: tokens", codex.inputTokens == 60 && codex.outputTokens == 7 && codex.contextLimit == 200000)
        check("codex: session id from filename", CodexProvider.sessionID(from: "rollout-2025-01-02T03-04-05-0198a1b2-1111-2222-3333-444455556666") == "0198a1b2-1111-2222-3333-444455556666")

        // Gemini
        let gem = GeminiProvider.parse(meta: ["sessionId": "g1", "startTime": ts(100)], messages: [
            ["type": "gemini", "timestamp": ts(5), "model": "gemini-2.5-pro", "tokens": ["input": 50, "output": 4, "thoughts": 1],
             "toolCalls": [["id": "a", "name": "read_file", "status": "success", "args": ["path": "x"]],
                           ["id": "b", "name": "run_shell_command", "status": "executing", "args": ["command": "ls"]]]]
        ], id: "g1", modified: now)
        check("gemini: running shell", gem.currentTool == "bash" && gem.toolCalls == 2 && gem.state == .working)
        check("gemini: tokens", gem.inputTokens == 50 && gem.outputTokens == 5)

        // Crew events
        let crew = CrewEventsProvider.parse(lines: lines([
            ["event": "session_start", "ts": ts(60), "name": "My script", "model": "gpt-4o", "cwd": "/work/s"],
            ["event": "subagent_start", "ts": ts(50), "agent": "w1", "tool": "researcher"],
            ["event": "tool_start", "ts": ts(5), "id": 7, "tool": "grep", "agent": "w1"],
            ["event": "approval_request", "ts": ts(4), "id": "p"],
            ["event": "message", "ts": ts(3), "input_tokens": 12, "output_tokens": 3],
        ]), id: "s", modified: now)
        check("crew: name + sub-agent + approval", crew.name == "My script" && crew.subagents.count == 1 && crew.waitingApproval)
        check("crew: sub-agent tool + tokens", crew.subagents.first?.tool == "grep" && crew.inputTokens == 12)
        let ended = CrewEventsProvider.parse(lines: lines([["event": "session_end", "ts": ts(1)]]), id: "e", modified: now)
        check("crew: session_end -> offline", ended.state == .offline)

        // Cursor (synthetic composerData/bubble fixtures)
        let cur = CursorProvider.parse(
            composer: ["modelConfig": ["modelName": "claude-4-sonnet"]],
            bubbles: [["toolFormerData": ["name": "read_file", "toolCallId": "a", "status": "completed"]],
                      ["toolFormerData": ["name": "edit_file", "toolCallId": "b", "status": "error"], "tokenCount": ["inputTokens": 9, "outputTokens": 2]],
                      ["toolFormerData": ["name": "run_terminal_cmd", "toolCallId": "c", "status": "loading"]]],
            id: "c1", created: now.addingTimeInterval(-60), modified: now, cwd: "/work/cur")
        check("cursor: model + tokens + failure", cur.model == "claude-4-sonnet" && cur.inputTokens == 9 && cur.failures == 1 && cur.provider == "cursor")
        check("cursor: running terminal -> bash", cur.currentTool == "bash" && cur.state == .working && cur.id == "cursor:c1")
        check("cursor: tool mapping", CursorProvider.mapTool("codebase_search") == "grep" && CursorProvider.mapTool("read_file") == "view" && CursorProvider.mapTool("delete_file") == "edit")
        check("cursor: empty data -> offline", CursorProvider.parse(composer: nil, bubbles: [], id: "e", created: nil, modified: now.addingTimeInterval(-7200)).state == .offline)

        // Grok (alias of crew events)
        let grokLines = lines([["event": "session_start", "ts": ts(30), "provider": "grok", "model": "grok-4"],
                               ["event": "tool_start", "ts": ts(2), "id": 1, "tool": "bash"]])
        let grok = GrokProvider.parse(lines: grokLines, id: "grok-demo", modified: now)
        check("grok: provider + running bash", grok.provider == "grok" && grok.id == "grok:grok-demo" && grok.currentTool == "bash" && grok.model == "grok-4")
        check("grok: alias detection", CrewEventsProvider.aliasProvider(file: "Grok-x", lines: []) == "grok"
              && CrewEventsProvider.aliasProvider(file: "job", lines: grokLines) == "grok"
              && CrewEventsProvider.aliasProvider(file: "job", lines: lines([["event": "message"]])) == nil)

        let reg = ProviderRegistry.shared
        check("registry: unique ids", Set(reg.all.map(\.id)).count == reg.all.count)
        print(failures == 0 ? "All provider checks passed" : "\(failures) provider check(s) FAILED")
        return failures == 0
    }
}
