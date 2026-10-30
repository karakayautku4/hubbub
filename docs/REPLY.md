# Reply from Hubbub

Answer an agent's approval request or question from Hubbub instead of switching to its terminal.
Everything here is **opt-in** (Settings → Alerts → "Reply from Hubbub"), **user-initiated** (Hubbub never answers on its own) and **local only**. Hubbub never edits your CLI configuration.

## What is possible per provider

| Provider | Detect question | Show in Hubbub | Deliver answer |
|---|---|---|---|
| Copilot CLI | Yes: `permission.requested` and `ask_user` in `events.jsonl` | Question, command, choices | Approve/Deny via `permissionRequest` hook; choices and free text via terminal typing |
| Claude Code | `AskUserQuestion` from the transcript; permission prompts only via the `PermissionRequest` hook (they are not in the transcript) | Yes | Approve/Deny via hook; choices and text via terminal typing |
| Codex | Approval requests and elicitations from the rollout log | Yes | Terminal typing only |
| Gemini | `awaiting_approval` | Yes | Terminal typing only |
| Cursor, Grok | No detection | Generic "needs attention" only | None |

A running interactive CLI cannot be answered by another process directly, so there are two delivery channels.

### 1. Terminal typing (opt-in)
Hubbub finds the session's terminal (session id in `ps`, then the lock-file pid, then a unique working directory; ambiguous matches are refused) and types the keys:

- **tmux**: `send-keys` to the pane owning the tty. No extra permission.
- **iTerm2**: `write text` to the session with that tty (macOS Automation permission).
- **Terminal.app**: text plus Return only. It cannot send arrows or Escape, so Deny and multi-option choices need tmux or iTerm2.

Keys: approve = Enter, deny = Escape, choice *i* = Down×i then Enter, text = text then Enter.
If nothing can deliver, Hubbub shows "Couldn't deliver — answer in your terminal".

### 2. Hook channel (opt-in, you install the hook)
A tiny client (`Hubbub --reply-hook claude|copilot`) is called by the CLI's permission hook and asks the running Hubbub over a Unix socket. Use Settings → "Copy Claude Code hook" / "Copy Copilot CLI hook" and paste the snippet into your own config:

- Claude Code: `~/.claude/settings.json` (`hooks.PermissionRequest`)
- Copilot CLI: `~/.copilot/hooks/hubbub.json` (`hooks.permissionRequest`)

Behavior: the hook always exits 0. If Hubbub is not running, the channel is off, you don't answer within the timeout (default 60 s), or anything fails, it prints nothing and the CLI shows its normal prompt. Caveat: while the hook waits, the CLI's own prompt is not yet visible. `AskUserQuestion` is always passed through.
Copilot ignores an allow when a sandbox bypass is requested and prompts anyway.

## Security model
- Socket: `~/Library/Application Support/Hubbub/reply/reply.sock`, mode 0600 inside a 0700 folder; peers with another uid are rejected.
- Per-request random nonce (single use); stale or unknown requests are ignored.
- Requests capped at 256 KB, at most 8 pending; text from agents is stripped of control and bidi characters.
- Replies are capped at 2000 characters.
- Delivery is never claimed from the send alone: "Confirmed" appears only when the agent's log shows the question resolved or activity resumed; otherwise "unconfirmed — check your terminal".

## Verification
`Hubbub --selftest-reply` runs fixture-based tests: parsing of real log shapes, key formatting, tty location, channel argv with a fake runner (no GUI automation), the hook protocol, and a real socket round trip (permissions, allow/deny/passthrough, timeout, disconnect, garbage/oversize input).

**Verified by tests:** the above. **Not verified on real systems:** typing into real Terminal.app/iTerm2/tmux, the key assumptions for each CLI's prompt UI, the Automation permission prompt, real hook execution inside Claude Code / Copilot CLI, and notification action rendering.
