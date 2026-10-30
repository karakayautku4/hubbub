<div align="center">

<img src="docs/images/icon.png" width="128" alt="Hubbub app icon">

# Hubbub

**Your AI coding agents, as a tiny living 3D world in the macOS menu bar.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#-install)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20SceneKit-F05138?logo=swift&logoColor=white)](docs/ARCHITECTURE.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![CI](https://github.com/karakayautku4/hubbub/actions/workflows/ci.yml/badge.svg)](https://github.com/karakayautku4/hubbub/actions/workflows/ci.yml)
[![Local-first](https://img.shields.io/badge/telemetry-none-brightgreen)](#-privacy)

<img src="docs/images/hero.gif" width="720" alt="Hubbub: agents working in the Space Station theme">

*Every session is a scene. Every sub-agent is a character with a silly job.*

[Website](https://karakayautku4.github.io/hubbub/) · [Features](#-features) · [Install](#-install) · [Themes](#-themes) · [Screenshots](#-screenshots) · [Privacy](#-privacy) · [FAQ](#-faq)

</div>

> **Unofficial.** Hubbub is an independent project, not affiliated with, endorsed by or sponsored by GitHub, Microsoft, Anthropic, OpenAI, Google, Cursor or xAI. Names and logos belong to their owners ([docs/IP_NOTES.md](docs/IP_NOTES.md)).

## 📑 Contents

- [What is it?](#-what-is-it) · [Features](#-features) · [Install](#-install) · [Quick start](#-quick-start)
- [Supported providers](#-supported-providers) · [Themes](#-themes) · [Screenshots](#-screenshots)
- [Keyboard shortcuts](#-keyboard-shortcuts) · [URL scheme & CLI](#-url-scheme--cli) · [Privacy](#-privacy)
- [Performance](#-performance) · [Status & caveats](#-status--caveats) · [FAQ](#-faq)
- [Contributing](#-contributing) · [Roadmap](#-roadmap) · [License](#-license) · [Credits](#-credits)

## 👀 What is it?

Hubbub watches the local session logs of your AI coding agents and turns each running session into a small interactive 3D scene. Sub-agents become characters doing a themed job: chefs in a kitchen, sheep on a farm, impostors on a ship. At a glance you see who is **working, stuck, failed or waiting for your approval**, plus context, tokens, cost and quota. It lives in the menu bar and opens as a popover (or a bigger window with `⌘E`).

## ✨ Features

<details open>
<summary><b>🧑‍🍳 Agents as characters</b></summary>

Each session is a stage; the main agent is the lead (Commander, Farmer, Head Chef…) and every sub-agent (`explore`, `task`, `review`…) gets a nameplate, a job and speech bubbles. Stuck, failed and approval-needed states are visible on the stage, not just in a list.
</details>

<details open>
<summary><b>🎭 9 themes</b></summary>

Space Station, Restaurant Kitchen, Prison, Football Match (fictional clubs), Sheep Farm, Sneaky Ship, Spell Academy, Galactic Fleet and Hillside Quest. All procedural SceneKit art; see the [gallery](#-themes). Community themes are a JSON file away ([docs/THEMES.md](docs/THEMES.md)).
</details>

<details>
<summary><b>📊 Quota & cost (honest)</b></summary>

Copilot shows a quota bar (needs a GitHub token; uses an undocumented endpoint, see [caveats](#-status--caveats)). Cost is shown as **Copilot credits** as reported in the logs. Hubbub does not invent dollar prices; any dollar estimate only comes from a price table you source yourself and is labelled "est." ([docs/COST.md](docs/COST.md)). Other providers show token totals.
</details>

<details>
<summary><b>🗂️ Sessions, History, Insights, Awards</b></summary>

Live tab with tokens, context and cost; a searchable **History**; **Insights** with a weekly chart; **Details** per session (tool calls, failure rate); and an **Awards** tab for level, XP and badges.
</details>

<details>
<summary><b>💬 Reply from Hubbub (opt-in, experimental)</b></summary>

Answer an agent's question or approve/deny from the menu bar. Off by default; delivery to real terminals is not yet verified everywhere, see [docs/REPLY.md](docs/REPLY.md).
</details>

<details>
<summary><b>🎥 Camera, zoom, day/night & weather</b></summary>

Zoom and pan the stage, jump to a fullscreen view, and enjoy subtle time-of-day and weather ambience (switchable in Settings).
</details>

<details>
<summary><b>🐑 Mascots, XP & achievements</b></summary>

A mascot per theme, levels, XP, badges and cosmetics. Optional surprise guests, race mode, sounds and a floating mini HUD (all off by default).
</details>

<details>
<summary><b>🎃 Halloween mode</b></summary>

Pumpkins, ghosts and bats over every theme, plus cobwebs and a spider in the app UI. Automatic Oct 24 – Nov 1, or force On/Off in Settings → Appearance ([docs/HALLOWEEN.md](docs/HALLOWEEN.md)).
</details>

<details>
<summary><b>🔌 Multi-provider, 🔢 menu-bar percent, ♿ accessibility</b></summary>

Copilot CLI, Claude Code, Codex CLI, Gemini CLI, Cursor and a generic event format, each with a provider badge. The menu-bar item can show quota percent. VoiceOver narration of the stage, status by icon as well as colour, and Reduce Motion / Contrast / Transparency support.
</details>

## 📦 Install

<div align="center">

[![Download Hubbub for macOS](https://img.shields.io/badge/%E2%AC%87%EF%B8%8F%20Download%20Hubbub-for%20macOS%2014%2B-7c5cdc?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/karakayautku4/hubbub/releases/latest/download/Hubbub.dmg)

Universal app: Apple silicon and Intel. Free, no account needed.

</div>

1. **Download** `Hubbub.dmg` (button above) and open it.
2. **Drag Hubbub to Applications** in the window that appears.
3. **Open Hubbub** from Applications. A small icon appears in the menu bar (there is no Dock icon).

> Hubbub is signed with an Apple Developer ID and notarized, so it opens with no warning. If macOS still complains
> (e.g. a build you compiled yourself), go to **System Settings → Privacy & Security → Open Anyway**.

Requires macOS 14 (Sonoma) or later. Prefer Homebrew? `brew tap karakayautku4/hubbub && brew install --cask hubbub` (see [packaging/homebrew](packaging/homebrew/README.md)).

<details>
<summary>Build from source</summary>

Needs a Swift toolchain (Xcode or Command Line Tools).

```sh
git clone https://github.com/karakayautku4/hubbub.git
cd hubbub
./build-app.sh        # builds Hubbub.app (ad-hoc signed; releases are Developer ID signed + notarized)
open Hubbub.app
./make-dmg.sh         # optional: universal DMG in dist/ (see docs/RELEASING.md)
```

Just want to run the binary? `swift build -c release && .build/release/Hubbub`

Maintainers: see [docs/RELEASING.md](docs/RELEASING.md).
</details>

## 🚀 Quick start

1. Launch Hubbub; a rocket appears in the menu bar. Press `⌥⌘C` or click it.
2. Use any supported agent. Providers whose data folder exists are enabled automatically (Settings → Providers).
3. Pick a theme from the toolbar menu, or with `hubbub://theme/farm`.
4. Hit `⌘E` for the big window, `⌘4` for Awards.

## 🔌 Supported providers

| Agent | Data source | Sub-agents | Status |
|---|---|---|---|
| GitHub Copilot CLI | `~/.copilot/session-state` | yes | Verified, plus quota bar |
| Claude Code | `~/.claude/projects` | yes | From documented format, fixture-tested |
| OpenAI Codex CLI | `~/.codex/sessions` | no | From documented format, fixture-tested |
| Gemini CLI | `~/.gemini/tmp` | no | Best effort |
| Cursor | Cursor `state.vscdb` (read-only) | no | Best effort |
| xAI Grok & anything else | `~/.hubbub/events/*.jsonl` | yes | Via Crew Events: you emit one JSON line per event ([docs/PROVIDERS.md](docs/PROVIDERS.md), `tools/crew-emit`) |

Log formats of these tools are not guaranteed stable; an update to a CLI can break parsing.

## 🎭 Themes

Click a theme to expand an animated preview.

<table>
<tr>
<td align="center"><a href="#t-space"><img src="docs/images/themes/space.jpg" width="260"></a><br><b>Space Station</b></td>
<td align="center"><a href="#t-kitchen"><img src="docs/images/themes/kitchen.jpg" width="260"></a><br><b>Kitchen</b></td>
<td align="center"><a href="#t-prison"><img src="docs/images/themes/prison.jpg" width="260"></a><br><b>Prison</b></td>
</tr>
<tr>
<td align="center"><a href="#t-football"><img src="docs/images/themes/football.jpg" width="260"></a><br><b>Football</b></td>
<td align="center"><a href="#t-farm"><img src="docs/images/themes/farm.jpg" width="260"></a><br><b>Sheep Farm</b></td>
<td align="center"><a href="#t-impostor"><img src="docs/images/themes/impostor.jpg" width="260"></a><br><b>Sneaky Ship</b></td>
</tr>
<tr>
<td align="center"><a href="#t-wizard"><img src="docs/images/themes/wizard.jpg" width="260"></a><br><b>Spell Academy</b></td>
<td align="center"><a href="#t-galactic"><img src="docs/images/themes/galactic.jpg" width="260"></a><br><b>Galactic Fleet</b></td>
<td align="center"><a href="#t-fellowship"><img src="docs/images/themes/fellowship.jpg" width="260"></a><br><b>Hillside Quest</b></td>
</tr>
</table>

<a id="t-space"></a><details><summary>🚀 Space Station</summary><img src="docs/images/themes/space.gif" width="560" alt="Space Station"></details>
<a id="t-kitchen"></a><details><summary>🍳 Restaurant Kitchen</summary><img src="docs/images/themes/kitchen.gif" width="560" alt="Kitchen"></details>
<a id="t-prison"></a><details><summary>⛓️ Prison</summary><img src="docs/images/themes/prison.gif" width="560" alt="Prison"></details>
<a id="t-football"></a><details><summary>⚽ Football Match (fictional clubs)</summary><img src="docs/images/themes/football.gif" width="560" alt="Football"></details>
<a id="t-farm"></a><details><summary>🐑 Sheep Farm</summary><img src="docs/images/themes/farm.gif" width="560" alt="Farm"></details>
<a id="t-impostor"></a><details><summary>🕵️ Sneaky Ship</summary><img src="docs/images/themes/impostor.gif" width="560" alt="Sneaky Ship"></details>
<a id="t-wizard"></a><details><summary>🪄 Spell Academy</summary><img src="docs/images/themes/wizard.gif" width="560" alt="Spell Academy"></details>
<a id="t-galactic"></a><details><summary>🛸 Galactic Fleet</summary><img src="docs/images/themes/galactic.gif" width="560" alt="Galactic Fleet"></details>
<a id="t-fellowship"></a><details><summary>🏔️ Hillside Quest</summary><img src="docs/images/themes/fellowship.gif" width="560" alt="Hillside Quest"></details>

### 🎃 Halloween mode

<table><tr>
<td><img src="docs/images/halloween-wizard.gif" width="400" alt="Halloween Spell Academy"></td>
<td><img src="docs/images/halloween-farm.gif" width="400" alt="Halloween Sheep Farm"></td>
</tr></table>

## 🖼️ Screenshots

Synthetic demo data only. The sandboxed capture setup is in [`scripts/make-screenshots.sh`](scripts/make-screenshots.sh).

<table>
<tr><td align="center"><b>Live</b></td><td align="center"><b>Live, Halloween</b></td></tr>
<tr>
<td><img src="docs/images/ui/live-light.png" width="380" alt="Live tab"></td>
<td><img src="docs/images/ui/live-halloween.png" width="380" alt="Live tab, Halloween mode"></td>
</tr>
<tr><td align="center"><b>Insights</b></td><td align="center"><b>History</b></td></tr>
<tr>
<td><img src="docs/images/ui/insights-light.png" width="380" alt="Insights"></td>
<td><img src="docs/images/ui/history-light.png" width="380" alt="History"></td>
</tr>
<tr><td align="center"><b>Awards</b></td><td align="center"><b>Session details</b></td></tr>
<tr>
<td><img src="docs/images/ui/awards-light.png" width="380" alt="Awards"></td>
<td><img src="docs/images/ui/details-light.png" width="380" alt="Details"></td>
</tr>
</table>

**Expand window** (`⌘E`):

<img src="docs/images/ui/expand-light.png" width="760" alt="Expand window">

<details>
<summary>⚙️ Settings tabs</summary>

<table>
<tr>
<td align="center">General<br><img src="docs/images/ui/settings-general-light.png" width="240"></td>
<td align="center">Appearance<br><img src="docs/images/ui/settings-appearance-light.png" width="240"></td>
</tr>
<tr>
<td align="center">Providers<br><img src="docs/images/ui/settings-providers-light.png" width="240"></td>
<td align="center">Notifications<br><img src="docs/images/ui/settings-alerts-light.png" width="240"></td>
</tr>
</table>

An *Advanced* tab holds sync, Reply and sound options. Screenshots are light mode only for now.
</details>

## ⌨️ Keyboard shortcuts

| Keys | Action |
|---|---|
| `⌥⌘C` | Open the popover from anywhere (global hotkey, configurable) |
| `⌘1` `⌘2` `⌘3` `⌘4` | Live / Insights / History / Awards |
| `⌘E` | Expand / collapse the window |
| `⌘,` | Settings |
| `⌘F` | Search history |
| `⌘R` | Refresh |
| `⌘+` | Zoom in (the stage also has − / + buttons) |
| `←` `→` | Previous / next session |
| `⌘[` or `Esc` | Back |
| `⌘W` / `⌘Q` | Close / quit |

## 🔗 URL scheme & CLI

| URL | Opens |
|---|---|
| `hubbub://open` | The popover |
| `hubbub://session/<id>` | A session |
| `hubbub://insights` · `history` · `achievements` | That tab |
| `hubbub://settings[/general\|appearance\|providers\|alerts\|advanced]` | Settings |
| `hubbub://theme/<name>` | Switch theme |
| `hubbub://refresh` | Re-scan sessions |

```sh
open "hubbub://theme/farm"
.build/release/Hubbub --status          # one-line summary for scripts / status bars
.build/release/Hubbub --status --json
```

More in [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

## 🔒 Privacy

Local-first: **no telemetry, no analytics, no accounts, no crash reporting.** Message content is never stored or sent; only tool names, short descriptions, timestamps and token counts are shown. Hubbub reads other tools' files read-only.

| Network call | When | Sent |
|---|---|---|
| `api.github.com/copilot_internal/user` (undocumented) | Copilot quota bar, if a GitHub token exists | your GitHub token, to GitHub |
| `api.anthropic.com`, `chatgpt.com`, `cursor.com` usage endpoints (undocumented) | only after you opt in per provider | that provider's own token, to that provider |
| `api.github.com/repos/<owner>/<repo>/releases/latest` | update check, ≤ once / 24 h, can be disabled | nothing identifying |

Nothing else goes over the network. Details: [SECURITY.md](SECURITY.md), [docs/QUOTA.md](docs/QUOTA.md).

## ⚡ Performance

Measured on the author's Mac while developing (see `scripts/perf-check.sh` and `Hubbub --selftest-perf` to reproduce on yours):

- Metrics scan of a large session history: **12.2 s / 1042 MB → 3.0 s / 29 MB** after optimisation.
- Idle memory: **~370 MB → ~80 MB**; idle CPU ≈ 0 %.

Numbers vary by machine and data; details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## ⚠️ Status & caveats

- **v0.1.0**: first public release, signed and notarized release.
- **Quota endpoints are undocumented** and may change; Hubbub then shows "Quota unavailable".
- **Reply-from-Hubbub** is opt-in and experimental; delivery into real terminals is unverified.
- **Claude Code / Codex** parsing follows the documented formats and fixtures; **Gemini / Cursor** are best effort; Grok needs you to emit events.
- Screenshots are light mode only; the Awards tab looks sparse with demo data.

## ❓ FAQ

<details><summary>Does it send my code or prompts anywhere?</summary>No. See <a href="#-privacy">Privacy</a>.</details>
<details><summary>Do I need a GitHub token?</summary>Only for the Copilot quota bar. Without it everything else works.</details>
<details><summary>Why macOS 14?</summary>That is the deployment target in <code>Package.swift</code>.</details>
<details><summary>Can I add my own theme or provider?</summary>Yes: <a href="docs/CREATING_THEMES.md">themes</a>, <a href="CONTRIBUTING.md#adding-a-provider">providers</a>.</details>
<details><summary>How do I regenerate the images?</summary><code>scripts/make-gifs.sh</code> (GIFs, theme stills) and <code>scripts/make-screenshots.sh</code> (UI). Both need a GUI session and Pillow.</details>

## 🤝 Contributing

PRs welcome: [CONTRIBUTING.md](CONTRIBUTING.md), [docs/CREATING_THEMES.md](docs/CREATING_THEMES.md), [docs/PROVIDERS.md](docs/PROVIDERS.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [Code of Conduct](CODE_OF_CONDUCT.md).

## 🗺️ Roadmap

- ✅ Signed and notarized DMG
- ✅ Homebrew cask (karakayautku4/homebrew-hubbub)
- Verify Reply delivery across terminals
- Dark-mode screenshots
- More themes and providers

## 📄 License

MIT, see [LICENSE](LICENSE).

## 🙏 Credits

Provider glyphs from [Simple Icons](https://simpleicons.org) (CC0). All scenes and jokes are original and procedural; the football theme uses fictional clubs. Trademarks belong to their owners; Hubbub is not affiliated with any of them ([docs/IP_NOTES.md](docs/IP_NOTES.md)).
