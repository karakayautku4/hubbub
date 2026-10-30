# Contributing to Hubbub

Thanks for helping! Bug reports, new providers, themes and docs are all welcome.

## Build and test

Requirements: macOS 14+, Xcode or the Command Line Tools (Swift 5.9+).

```sh
swift build -c release                               # compile
scripts/run-selftests.sh                             # all headless self-tests (what CI runs)
.build/release/Hubbub --selftest-providers       # a single headless self-test, e.g. fixtures for every provider
.build/release/Hubbub --selftest                 # needs a GUI session: scene + picking smoke test
.build/release/Hubbub --snapshot out.png         # renders every theme to a PNG (GUI session)
.build/release/Hubbub --snapshot-ui out.png      # renders the popover UI (GUI session)
./build-app.sh                                        # Hubbub.app
./make-dmg.sh                                         # dist/Hubbub-<version>.dmg
```

Before opening a PR: build, run `scripts/run-selftests.sh`, and for visual changes attach a `--snapshot` image.

## Code layout

```
Sources/Hubbub/
  App.swift, ContentView.swift      menu bar app, popover UI, settings
  SessionMonitor.swift              polling loop, merges all providers, Copilot CLI parser
  Providers/                        AgentProvider protocol, registry, SessionBuilder, one file per provider, self-test
  Models.swift                      SessionInfo, SubAgent, ToolCallRecord, Quota
  QuotaService.swift                Copilot quota (undocumented endpoint, see docs/QUOTA.md)
  Metrics*.swift, Insights*.swift,  cost/context metrics, stuck detection, history
  StuckDetector.swift, UsageHistory.swift
  Theme.swift, Environments.swift,  themes, 3D scenes, characters, simulation
  Characters.swift,
  World.swift, Stage.swift
docs/        PROVIDERS.md (log schemas, Crew Events), THEMES.md
tools/       crew-emit (example emitter)
```

## Adding a provider

1. Look at a real log of the tool. Only read *structure* (types, tool names, timestamps, token counts); never copy
   or store message text.
2. Create `Sources/Hubbub/Providers/<Name>Provider.swift` with a `struct <Name>Provider: AgentProvider`:
   `id`, `displayName`, `symbol` (SF Symbol), `dataHint`, `isAvailable` (data folder exists), `scan()`.
3. In `scan()` use `ProviderKit.recentFiles` (last 24 h, newest first) and `ProviderKit.readTail` (big files), and write
   a pure `static func parse(...) -> SessionInfo` that feeds a `SessionBuilder`:
   `toolStart/toolEnd`, `subStart/subEnd` (sub-agents), `approvalRequested/Resolved`, token fields. `build()` derives
   working/idle/offline. Use `ProviderKit.OfflineCache` to avoid reparsing finished sessions.
4. Never crash: skip malformed lines, tolerate missing keys, cap file sizes.
5. Register it in `ProviderRegistry.all` (`AgentProvider.swift`).
6. Add a synthetic fixture check to `ProviderSelfTest.swift` (no real user data in the repo).
7. Document the source and its verification status in `docs/PROVIDERS.md`.

If the tool can be adapted to write [Crew Events](docs/PROVIDERS.md#crew-events-integrate-any-tool), that needs no code at all.

## Adding a theme

See [docs/THEMES.md](docs/THEMES.md).

## Style

- Swift, 4-space indent, small focused functions, comments only where something is non-obvious.
- No new dependencies without discussion; the app is pure SwiftUI + SceneKit.
- Keep everything local: no telemetry, no new network calls.
- Never log tokens, message content or file contents.

## Pull requests

Keep PRs focused, describe what/why, and fill in the PR template. By contributing you agree your work is MIT licensed.
