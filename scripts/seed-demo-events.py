#!/usr/bin/env python3
"""Writes a few synthetic Crew Events sessions for the README screenshots.

usage: seed-demo-events.py <fake-home> <live-pid>
Fills <fake-home>/.hubbub/events (Crew Events) and <fake-home>/.copilot/session-state (Copilot CLI format) with
invented sessions. <live-pid> is any running process id: Copilot treats a session as live while its lock's pid exists.
Nothing here comes from real sessions.
"""
import json, sys, time, pathlib, datetime

home = pathlib.Path(sys.argv[1])
livepid = int(sys.argv[2])
out = home / ".hubbub/events"
out.mkdir(parents=True, exist_ok=True)
now = time.time()


def write(session, events):
    with open(out / f"{session}.jsonl", "w") as f:
        for ago, ev in events:
            f.write(json.dumps({"ts": now - ago, **ev}) + "\n")


def tool(i, ago, name, detail, agent=None, ok=True, dur=2):
    base = {"id": str(i), "tool": name, "detail": detail}
    if agent:
        base["agent"] = agent
    return [(ago, {"event": "tool_start", **base}), (ago - dur, {"event": "tool_end", "id": str(i), "ok": ok, **({"agent": agent} if agent else {})})]


# 1: busy Claude Code session with three sub-agents, one still running a tool
ev = [(900, {"event": "session_start", "name": "Refactor auth module", "model": "claude-sonnet-4.5", "provider": "claude", "cwd": "/work/acme-api", "branch": "feature/auth"})]
for a, role in (("a1", "explore"), ("a2", "task"), ("a3", "review")):
    ev.append((800, {"event": "subagent_start", "agent": a, "tool": role, "display_name": role}))
ev += tool(1, 700, "grep", "src/auth", "a1") + tool(2, 600, "view", "src/auth/session.ts", "a1")
ev += tool(3, 500, "edit", "src/auth/token.ts", "a2") + tool(4, 400, "bash", "npm test", "a2", ok=False, dur=30)
ev += tool(5, 300, "edit", "src/auth/token.ts", "a2") + tool(6, 200, "bash", "npm test", "a2", dur=25)
ev += tool(7, 100, "view", "src/auth/guard.ts", "a3")
ev.append((20, {"event": "tool_start", "id": "8", "tool": "bash", "detail": "npm run lint", "agent": "a2"}))
ev.append((10, {"event": "message", "input_tokens": 182000, "output_tokens": 14000, "context_tokens": 86000, "context_limit": 200000}))
write("claude-auth", ev)

# 2: Codex session waiting for approval
ev = [(500, {"event": "session_start", "name": "Fix flaky tests", "model": "gpt-5-codex", "provider": "codex", "cwd": "/work/acme-web"})]
ev += tool(11, 400, "grep", "retry(", None) + tool(12, 300, "edit", "tests/checkout.spec.ts", None)
ev.append((15, {"event": "approval_request", "id": "13", "tool": "bash", "detail": "rm -rf node_modules && npm ci"}))
ev.append((10, {"event": "message", "input_tokens": 64000, "output_tokens": 5200, "context_tokens": 52000, "context_limit": 128000}))
write("codex-flaky", ev)

# 3: Copilot-style idle session
ev = [(1500, {"event": "session_start", "name": "Write release notes", "model": "claude-sonnet-4.5", "provider": "copilot", "cwd": "/work/acme-docs"})]
ev += tool(21, 1400, "view", "CHANGELOG.md", None) + tool(22, 1300, "edit", "docs/release-0.2.md", None)
ev.append((200, {"event": "message", "input_tokens": 22000, "output_tokens": 3100, "context_tokens": 18000, "context_limit": 128000}))
write("copilot-notes", ev)


# --- Copilot CLI format sessions ---
root = home / ".copilot/session-state"


def iso(ago):
    return datetime.datetime.fromtimestamp(now - ago, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def copilot(sid, name, branch, start_ago, events, live=False):
    d = root / sid
    d.mkdir(parents=True, exist_ok=True)
    (d / "workspace.yaml").write_text(f"id: {sid}\ncwd: /work/acme-api\nname: {name}\nbranch: {branch}\ncreated_at: {iso(start_ago)}\n")
    lines = [{"type": "session.start", "timestamp": iso(start_ago), "data": {"selectedModel": "claude-sonnet-4.5"}}] + events
    with open(d / "events.jsonl", "w") as f:
        for e in lines:
            f.write(json.dumps(e) + "\n")
    if live:
        (d / f"inuse.{livepid}.lock").write_text("")
    # file mtime decides the order in the session list
    import os
    t = now - (start_ago if not live else 0)
    os.utime(d / "events.jsonl", (t, t))


def usage(ago, inp, out_, ctx, cost, agent=None):
    e = {"type": "session.usage_record", "timestamp": iso(ago),
         "data": {"usage": {"inputTokens": inp, "outputTokens": out_, "maxPromptTokens": 200000, "cost": cost, "model": "claude-sonnet-4.5"}}}
    if agent:
        e["agentId"] = agent
    return e


def tstart(ago, cid, name, args, agent=None, parent=None):
    d = {"toolCallId": cid, "toolName": name, "arguments": args}
    if parent:
        d["parentToolCallId"] = parent
    e = {"type": "tool.execution_start", "timestamp": iso(ago), "data": d}
    if agent:
        e["agentId"] = agent
    return e


def tend(ago, cid, ok=True, agent=None):
    e = {"type": "tool.execution_complete", "timestamp": iso(ago), "data": {"toolCallId": cid, "success": ok, **({} if ok else {"error": {"message": "exit code 1"}})}}
    if agent:
        e["agentId"] = agent
    return e


def sub(ago, cid, aid, name, display):
    return {"type": "subagent.started", "timestamp": iso(ago), "agentId": aid,
            "data": {"toolCallId": cid, "agentName": name, "agentDisplayName": display, "model": "claude-haiku-4.5"}}


# live: three sub-agents at work, one waiting for approval
ev = [sub(240, "s1", "g1", "explore", "Explore"), sub(235, "s2", "g2", "task", "Task"), sub(230, "s3", "g3", "code-review", "Review")]
ev += [tstart(1300, "t1", "grep", {"pattern": "refreshToken"}, "g1", "s1"), tend(1295, "t1", True, "g1"),
       tstart(1290, "t2", "view", {"path": "src/auth/session.ts"}, "g1", "s1"), tend(1285, "t2", True, "g1"),
       tstart(1150, "t3", "edit", {"path": "src/auth/token.ts"}, "g2", "s2"), tend(1145, "t3", True, "g2"),
       tstart(1120, "t4", "bash", {"command": "npm test"}, "g2", "s2"), tend(1100, "t4", False, "g2"),
       tstart(900, "t5", "edit", {"path": "src/auth/token.ts"}, "g2", "s2"), tend(895, "t5", True, "g2"),
       tstart(800, "t6", "bash", {"command": "npm test"}, "g2", "s2"), tend(770, "t6", True, "g2"),
       tstart(700, "t7", "view", {"path": "src/auth/guard.ts"}, "g3", "s3"), tend(690, "t7", True, "g3"),
       tstart(8, "t8", "web_fetch", {"url": "https://example.com/oauth"}, "g1", "s1"),
       tstart(6, "t9", "bash", {"command": "npm run lint"}, "g2", "s2"),
       usage(40, 54000, 3200, 0, 4.0), usage(30, 9000, 800, 0, 1.0, "g1"), usage(30, 22000, 1500, 0, 1.0, "g2"), usage(30, 5000, 400, 0, 1.0, "g3")]
copilot("demo-live", "Refactor auth module", "feature/auth", 3000, ev, live=True)

# history: finished sessions over the last days (feeds History / Insights / Awards)
for i, (name, ago_days, tok, cost) in enumerate([("Add rate limiting", 1.1, 180000, 6.0), ("Migrate to Postgres 16", 1.6, 420000, 14.5),
                                                  ("Fix flaky checkout tests", 2.3, 96000, 3.5), ("Write onboarding docs", 3.1, 61000, 2.0),
                                                  ("Upgrade dependencies", 4.4, 310000, 9.0), ("Profile slow endpoint", 5.2, 140000, 5.0),
                                                  ("Draft release notes", 6.1, 38000, 1.5)]):
    a = ago_days * 86400
    ev = [tstart(a - 60, f"h{i}a", "grep", {"pattern": "TODO"}), tend(a - 70, f"h{i}a"),
          tstart(a - 200, f"h{i}b", "edit", {"path": "src/app.ts"}), tend(a - 210, f"h{i}b"),
          usage(a - 300, tok * 3 // 4, tok // 4, 0, cost), {"type": "session.shutdown", "timestamp": iso(a - 400), "data": {}}]
    copilot(f"demo-h{i}", name, "main", a + 600, ev)
