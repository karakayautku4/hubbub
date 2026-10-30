# Integrations

## URL scheme

Hubbub registers `hubbub://` (declared in the generated `Info.plist`). Launch Services learns about it the first time the built app is opened.

| URL | Action |
| --- | --- |
| `hubbub://open` | Open the popover |
| `hubbub://session/<id>` | Open a session's detail view |
| `hubbub://insights`, `hubbub://history` | Open that tab |
| `hubbub://settings[/<tab>]` | Open Settings (`general`, `appearance`, `providers`, `alerts`, `sound`, `sync`, `about`) |
| `hubbub://theme/<name>` | Switch theme (built-in id such as `wizard`, or a community theme id/title) |
| `hubbub://refresh` | Rescan sessions and refresh quota |

Unknown routes and unknown settings tabs are ignored.

```sh
open "hubbub://theme/farm"
osascript -e 'open location "hubbub://insights"'
```

In Shortcuts use the **Open URLs** action with any of the links above.

## Command line status

```sh
Hubbub.app/Contents/MacOS/Hubbub --status          # human readable
Hubbub.app/Contents/MacOS/Hubbub --status --json   # machine readable
```

It scans local session logs and prints the last quota the running app cached (no network access, so the quota is marked `cached`). It exits without starting the UI. JSON shape: `{ "total", "working", "sessions": [{ id, name, provider, state, model, cwd, inputTokens, outputTokens, toolCalls, failures, waitingApproval, lastEvent }], "quota": { percentUsed, used, entitlement, resetDate, plan, unlimited, cached } }`.

### Raycast script command

Save as `hubbub-status.sh`, `chmod +x`, and add the folder in Raycast › Extensions › Script Commands.

```sh
#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Hubbub Status
# @raycast.mode inline
# @raycast.refreshTime 1m
# @raycast.packageName Hubbub
BIN="/Applications/Hubbub.app/Contents/MacOS/Hubbub"
"$BIN" --status --json | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin); q = d.get("quota")
print(f"{d[\"working\"]}/{d[\"total\"]} working" + (f" · quota {q[\"percentUsed\"]:.0f}%" if q else ""))'
```

### Alfred

Create a Script Filter or "Run Script" workflow step (language `/bin/bash`) with `/Applications/Hubbub.app/Contents/MacOS/Hubbub --status` as the script, and a second step "Open URL" with `hubbub://open`.

## Shortcuts / App Intents

Native App Intents would need Xcode's App Intents metadata extraction (`appintentsmetadataprocessor`), which `swift build` does not run, and the bundle is assembled by `build-app.sh`, so Shortcuts would never discover the actions. The URL scheme above (via **Open URLs**) and AppleScript `open location` cover the same ground.

## Desktop widget

A WidgetKit widget must be an app-extension (`.appex`) with its own target, entitlements and provisioning, which a SwiftPM executable can't produce. Instead Hubbub offers a floating **mini HUD** (Settings › Appearance › Mini HUD, or right-click the menu bar icon): theme icon, quota %, active agents and a status dot. It stays on top on every Space, can be dragged (position is remembered) or made click-through.

## Focus, quiet hours and daily summary

- **Focus**: with permission (Settings › Alerts & Budget › Focus & quiet hours › Allow, using the public `INFocusStatusCenter` API) notifications are held while any Focus is on.
- **Quiet hours**: an own schedule (may wrap past midnight) that works without any permission.
- When either ends, held notifications arrive as one "N notifications while you were away" summary (a single held one is delivered as it was).
- **End-of-day summary** (off by default): e.g. "12 sessions, 3 failures, 1.2M tokens, top provider Copilot"; clicking it opens Insights. Sent once per day, only within three hours after the chosen time.

## Launch at login

Settings › General › Startup & shortcuts uses `SMAppService.mainApp`; errors and the "needs approval" state are shown inline. It is only available when running from the `.app`.
