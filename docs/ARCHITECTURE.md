# Architecture

Hubbub is a single-target SwiftUI + SceneKit menu bar app (`Sources/Hubbub`, no dependencies).
Data flows one way: **providers → monitor → stage → views**.

```
 agent logs on disk                         ┌────────────┐
 ~/.copilot ~/.claude ~/.codex …  ──scan──▶ │ Providers/ │  one AgentProvider per tool, pure parsers
 ~/.hubbub/events/*.jsonl                   └─────┬──────┘
                                                  │ [SessionInfo]
                                            ┌─────▼──────────┐
                                            │ SessionMonitor │  polls, merges, derives attention (stuck/failed)
                                            └─────┬──────────┘
                           ┌──────────────────────┼───────────────────────┐
                     ┌─────▼─────┐          ┌─────▼─────┐           ┌─────▼──────┐
                     │ ContentView│          │   Stage   │           │ MenuBar    │
                     │ SwiftUI UI │          │ SceneKit  │           │ label/icon │
                     └────────────┘          └─────┬─────┘           └────────────┘
                                             World / RoomSim (simulation) + Environments / Characters (3D)
```

## Layers

| Layer | Files | Notes |
|---|---|---|
| Providers | `Providers/*` | `AgentProvider` protocol, `ProviderRegistry`, `SessionBuilder` (tool/sub-agent/approval events to `SessionInfo`). Parsers are pure functions over text, tested with synthetic fixtures in `ProviderSelfTest`. |
| Monitor | `SessionMonitor.swift`, `StuckDetector.swift`, `Metrics.swift`, `UsageHistory.swift` | Timer-driven polling; only reads files, never writes to them. |
| Simulation | `World.swift` | One `RoomSim` per session: actors walk between stations, speak, celebrate or panic. No SceneKit types. |
| Scene | `Stage.swift`, `Environments.swift`, `Characters.swift`, `SceneEffects.swift`, `Themes/*`, `CameraRig.swift`, `Ambience.swift` | Builds the room for a theme from SceneKit primitives, syncs rigs with the simulation each tick, runs effects. The tick is driven by the visible view only, so a closed popover costs nothing. |
| UI | `ContentView.swift`, `SettingsView.swift`, `SessionDetailView.swift`, `InsightsView.swift`, … | SwiftUI popover. |
| Accessibility | `Accessibility.swift` | Preference overrides (Reduce motion, contrast, transparency), VoiceOver narration of the stage, announcements. |
| Self-tests | `*SelfTest.swift`, `Snapshot.swift`, `PerfSelfTest.swift` | Run from the binary itself (`--selftest*`), see below. |

## The theme contract

`Theme` (`Theme.swift`) is the registry. Every case answers: title, icon, blurb, role names, station labels, speech,
colours. `Environments.swift` and `Characters.swift` dispatch on it to theme-specific builders (see `Themes/*.swift` and
[CREATING_THEMES.md](CREATING_THEMES.md)). Community themes (`CustomThemes.swift`) wrap a built-in theme and override palette and wording.

## Self-tests and tooling

| Command | Needs GUI | Checks |
|---|---|---|
| `--selftest-providers` | no | provider parsers on fixtures |
| `--selftest-themes`, `-export`, `-budget`, `-quota`, `-notifications`, `-update`, `-a11y` | no | unit-style checks |
| `--selftest` | yes | scene builds, picking works |
| `--selftest-perf` | Metal device | steady-state tick/render time, CPU and memory per theme |
| `--snapshot out.png`, `--snapshot-ui out.png` | yes | render themes / popover |

Performance thresholds and how to tune them: [scripts/perf-check.sh](../scripts/perf-check.sh).

## Privacy-relevant boundaries

- File reads: provider folders listed in the README, plus `~/.hubbub` (events, settings data). Files are opened read-only.
- Network: the Copilot quota lookup and the update check only; see README → Privacy.
- Preferences live in `UserDefaults`; no credentials are persisted.
