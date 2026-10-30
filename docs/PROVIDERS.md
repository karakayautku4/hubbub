# Providers

Hubbub reads sessions from *providers*. Each provider turns a tool's local logs into the same
`SessionInfo` model (a session, its tool calls, sub-agents, tokens, state). Providers are enabled per
user in **Settings → Providers**; ones whose data folder exists are enabled automatically.

| Provider | id | Data read | Status |
|---|---|---|---|
| GitHub Copilot CLI | `copilot` | `~/.copilot/session-state/<id>/{workspace.yaml,events.jsonl}` | Verified against real data |
| Claude Code | `claude` | `~/.claude/projects/<project>/<session>.jsonl` (`CLAUDE_CONFIG_DIR` honoured) | Implemented from the documented log format, **synthetic fixtures only** (no real `~/.claude/projects` data on the verification machine, 2026-10-29) |
| OpenAI Codex CLI | `codex` | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (`CODEX_HOME` honoured) | Implemented from the documented log format, **synthetic fixtures only** (no `~/.codex` on the verification machine, 2026-10-29) |
| Gemini CLI | `gemini` | `~/.gemini/tmp/<project>/chats/session-*.json[l]` | Best effort, **synthetic fixtures only** (no `~/.gemini` on the verification machine); the format changes between releases |
| Cursor | `cursor` | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (SQLite, opened read-only; copied to `~/Library/Caches/Hubbub` if locked) | Best effort, **partially verified on real data** (header/composer rows read correctly; headers with a NULL `lastUpdatedAt` fall back to `createdAt`). The tables `composerHeaders` and `cursorDiskKV` (`composerData:<id>`) were checked on a real install, but that install had no completed agent runs, so the `bubbleId:` tool/token fields (`toolFormerData.name/status`, `tokenCount`) come from knowledge of the format and synthetic fixtures |
| xAI Grok | `grok` | `~/.hubbub/events/grok-*.jsonl`, or events with `"provider":"grok"` | Alias of Crew Events; no official local Grok logs exist, so nothing is read unless you emit events |
| Crew Events (generic) | `crew` | `~/.hubbub/events/<session>.jsonl` | Verified; use this for anything else |

Nothing is ever uploaded. Only structure (tool names, timestamps, token counts, short tool arguments such as a
command or file path shown in the UI) is read; message text is never stored.

Session ids are prefixed with the provider id (`claude:<id>`) to avoid collisions. Copilot ids stay unprefixed
for backwards compatibility with stored history.

## State detection

Providers that have no process lock decide the state from the log:

- `working`: a tool call or sub-agent is running, or an event arrived in the last 15 s
- `idle`: the last event is under 10 minutes old
- `offline`: older than 10 minutes, or the session logged an end/abort

## Tool names

The scene maps tool names to stations by keyword (`Theme.toolKind`): `0` search/read (`grep`, `glob`, `view`,
`read`, `search`, `list`, `find`), `1` edit/create (`edit`, `write`, `patch`, `create`), `2` shell (`bash`, `shell`,
`run`, `test`, `exec`), `3` everything else. `ProviderKit.canonicalTool` normalises native names
(e.g. Claude `Read` → `view`, Gemini `run_shell_command` → `bash`).

## Crew Events: integrate any tool

Append one JSON object per line to `~/.hubbub/events/<session>.jsonl` (the file name is the session id;
override the folder with `HUBBUB_EVENTS_DIR`). Sessions appear within ~2 s and disappear 10 minutes
after the last event (or immediately on `session_end`). Unknown fields and unknown event types are ignored.

| Field | Type | Meaning |
|---|---|---|
| `event` | string, required | `session_start`, `session_end`, `tool_start`, `tool_end`, `subagent_start`, `subagent_end`, `message`, `failure`, `approval_request`, `approval_granted` (or `approval_denied`) |
| `ts` | ISO-8601 string or epoch seconds/ms | default: file modification time |
| `session` | string | informational; the file name is authoritative |
| `name` | string | display name of the session (room name) |
| `cwd`, `branch`, `model` | string | project folder, git branch, model |
| `source` | string | shown instead of the model when none is given (e.g. `aider`) |
| `id` | string or number | call id: pairs `tool_start` with `tool_end`, `approval_request` with `approval_granted` |
| `tool` | string | tool name (`bash`, `grep`, `edit`, ...); for `subagent_start` the role/type |
| `detail` | string | short description (command, path), truncated to 80 chars |
| `agent` | string | sub-agent id. On `subagent_start`/`subagent_end` it identifies the sub-agent; on tool events it attributes the call to it |
| `display_name` | string | sub-agent display name |
| `ok`, `error` | bool, string | result of `tool_end` (`ok: false` counts as a failure) |
| `input_tokens`, `output_tokens` | int | **added** to the session totals on every event that carries them |
| `context_tokens`, `context_limit` | int | current context size / window (sets the context meter) |

Always send a unique `id` on `tool_start` and the same `id` on `tool_end`; a call without a matching end is
considered running for up to 10 minutes.

### Shell

```sh
tools/crew-emit mybot session_start name="Nightly refactor" model=gpt-4o cwd="$PWD"
tools/crew-emit mybot tool_start id=1 tool=bash detail="npm test"
tools/crew-emit mybot tool_end id=1 ok=true
tools/crew-emit mybot message input_tokens=1200 output_tokens=300
tools/crew-emit mybot session_end
```

Without the helper, one line of plain shell is enough:

```sh
mkdir -p ~/.hubbub/events
echo '{"event":"tool_start","id":"1","tool":"bash","detail":"make"}' >> ~/.hubbub/events/mybot.jsonl
```

### Python (OpenAI API scripts, Aider wrappers, custom agents)

```python
import json, os, time, pathlib

def emit(session, event, **fields):
    d = pathlib.Path(os.environ.get("HUBBUB_EVENTS_DIR", pathlib.Path.home() / ".hubbub/events"))
    d.mkdir(parents=True, exist_ok=True)
    with open(d / f"{session}.jsonl", "a") as f:
        f.write(json.dumps({"ts": time.time(), "event": event, **fields}) + "\n")

emit("my-agent", "session_start", name="Research bot", model="gpt-4o")
emit("my-agent", "tool_start", id="1", tool="web_search", detail="swift concurrency")
emit("my-agent", "tool_end", id="1", ok=True)
emit("my-agent", "message", input_tokens=900, output_tokens=120)
```

## Writing a new provider

See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-provider). In short: add a `struct MyProvider: AgentProvider`
in `Sources/Hubbub/Providers/`, translate the log into `SessionBuilder` calls (`toolStart`, `toolEnd`,
`subStart`, `subEnd`, `approvalRequested`, tokens), register it in `ProviderRegistry.all`, and add a fixture check to
`ProviderSelfTest`.

## Cursor

Cursor keeps agent/composer history in SQLite. Hubbub lists non-archived, non-subagent rows of `composerHeaders`
updated in the last 24 h, reads the model from `composerData:<id>.modelConfig.modelName`, and inspects the last
24 bubbles (`bubbleId:<composer>:<bubble>`) for tool names, tool status and token counts. The workspace folder comes
from `workspaceStorage/<workspaceId>/workspace.json`. Cursor only records the last update time, so tool start/end
times are approximated by it and a tool without a final status counts as running while the session is fresh.
The standalone `cursor-agent` CLI (`~/.cursor`) keeps no readable session log that Hubbub supports yet.
If Cursor changes its schema the provider simply shows nothing; it never writes to the database.

## Grok (xAI)

xAI has no official local session log and the community `grok-cli` only stores settings (`~/.grok`), so Grok is
supported through Crew Events: files named `grok-*.jsonl` (or any file whose events contain `"provider":"grok"`)
appear as Grok sessions with the xAI glyph (Simple Icons has no xAI mark; the "X" glyph is used). Example for a
script calling the xAI API (OpenAI-compatible, `https://api.x.ai/v1`):

```sh
S=grok-$(date +%s)
tools/crew-emit $S session_start name="Grok agent" model=grok-4 cwd="$PWD" provider=grok
tools/crew-emit $S tool_start id=1 tool=bash detail="npm test"
tools/crew-emit $S tool_end id=1 ok=true
tools/crew-emit $S message input_tokens=1200 output_tokens=300   # usage from the API response
tools/crew-emit $S session_end
```
