# Themes

A theme decides how a session looks: the 3D environment, the characters, station labels and wording.
Themes are Swift code; there is no asset pipeline (scenes are built from SceneKit primitives).

## Existing themes

`Space Station`, `Restaurant Kitchen`, `Prison`, `Football Match` (fictional clubs), `Sheep Farm`, `Sneaky Ship`, `Spell Academy`, `Galactic Fleet`, `Hillside Quest`.

Theme content must be original: no real clubs, brands, characters, catchphrases or places from other works. See [IP_NOTES.md](IP_NOTES.md).


## Community themes (JSON, no Swift needed)

Drop a `.json` file into `~/Library/Application Support/Hubbub/Themes/` and it shows up under **Community themes**
in Settings. A pack picks one of the built-in 3D sets (`base`) and overrides colours and wording. On first run, if the
folder is empty, `example-cyberpunk.json` is copied there. Settings has **Reload themes** and **Open themes folder**
buttons; the folder is also rescanned whenever Settings opens. Files that fail validation are skipped and listed in red in
Settings (`file.json: reason`); they never crash the app. The selection is stored as `custom:<id>` in the `theme` default.

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique, letters/digits/`-`/`_` |
| `title`, `emoji` | yes | Picker label and menu bar icon |
| `base` | yes | `space`, `kitchen`, `prison`, `football` or `farm` (the 3D set to reuse) |
| `blurb` | no | Description under the picker |
| `palette` | no | `background`, `ambient`, `keyLight`, `fillLight`, `accent` as `#rrggbb` (accent also tints the board, sign, info panel and outfit trim) |
| `characters` | no | `captainTitle`, `subagentRole`, `captainShirt`, `shirts` (sub-agent shirt colours), `skins` |
| `stations` | no | Up to 4 of `{ "kind", "label", "emoji" }`; kind 0 search/read, 1 edit/create, 2 bash, 3 other (omit `kind` to use list order) |
| `phrases` | no | Speech-bubble pools: `idle` (tired/break), `working`, `success`, `failure` |
| `labels` | no | `boardTitle`, `roomNoun` (HUD "Hideout: name"), `quota`, `empty`, `idle`, `thinking` |
| `ageSign` | no | `title` / `subtitle` templates; placeholders `{days}`, `{age}`, `{minutes}` |

Every optional field falls back to the base theme's value. Full example:

```json
{
  "id": "cyberpunk",
  "title": "Neon Station",
  "emoji": "🌃",
  "base": "space",
  "blurb": "A neon-soaked orbital hub. The fixer runs the crew of runners.",
  "palette": {
    "background": "#07020f",
    "ambient": "#8a6bd8",
    "keyLight": "#ffd0f2",
    "fillLight": "#00e5ff",
    "accent": "#ff2bd6"
  },
  "characters": {
    "captainTitle": "Fixer",
    "subagentRole": "runner",
    "captainShirt": "#2b0f4a",
    "shirts": ["#1c1c3a", "#3a1240", "#0f3a4a", "#4a1030"],
    "skins": ["#f2c9a0", "#c68642", "#8d5524", "#ffdbb4"]
  },
  "stations": [
    { "kind": 0, "label": "Net scan", "emoji": "🛰️" },
    { "kind": 1, "label": "Chrome workshop", "emoji": "🦾" },
    { "kind": 2, "label": "Overclock bay", "emoji": "⚡️" },
    { "kind": 3, "label": "Black market", "emoji": "💾" }
  ],
  "phrases": {
    "idle": ["Need some synth-coffee…", "Neon flickers…"],
    "working": ["Jacking in", "Rerouting the grid", "Patching the firewall"],
    "success": ["Gig complete! 💰", "Ice broken! 🧊"],
    "failure": ["Flatlined! 🚨", "Trace detected! 💥"]
  },
  "labels": {
    "boardTitle": "THE CREW",
    "roomNoun": "Hideout",
    "quota": "Credits",
    "empty": "The grid is quiet…",
    "idle": "💭 Waiting for a gig",
    "thinking": "🧠 Hacking the mainframe…"
  },
  "ageSign": { "title": "🌃 Night {days}", "subtitle": "online {age}" }
}
```

Validate packs headlessly with `.build/release/Hubbub --selftest-themes`; render one with
`SNAP_CUSTOM=path/to/pack.json .build/release/Hubbub --snapshot out.png`.

## Anatomy

| File | Responsibility |
|---|---|
| `Theme.swift` | `Theme` enum: title, icon, blurb, role names (`captainRole`, `subRole`), quota label, empty text, stations per theme, tool → station mapping (`toolKind`), per-tool speech/labels |
| `Environments.swift` | Builds the 3D room (floor, walls, props, lights) for each theme |
| `Characters.swift` | The captain and sub-agent characters, names and looks |
| `World.swift` / `Stage.swift` | Simulation (walking between stations, effects) and the SceneKit view |
| `Snapshot.swift` | `--snapshot` renders every theme to a PNG for review |

## Adding a theme

1. Add a case to `Theme` in `Theme.swift` and fill every `switch` the compiler complains about
   (title, icon, blurb, roles, labels, empty text, idle text, preview colors, stations).
2. Define 4 stations (one per tool kind: `0` search/read, `1` edit, `2` shell, `3` other) plus the captain `post`.
3. Build the environment in `Environments.swift` (use the helpers in `Gfx.swift`; keep geometry coordinates in the
   same 0–320 × 0–200 plan space the other themes use).
4. Add characters/outfits in `Characters.swift` if the theme needs new ones.
5. Verify visually: `swift build -c release && .build/release/Hubbub --snapshot out.png` and look at the result.
6. Add the theme to the README feature list and add a screenshot.

## Guidelines

- Keep it work-safe and kind: no real people, no trademarks you do not have the right to use.
- Failures and approvals must be visible in every theme (the existing themes show a red card / sick sheep / alarm, etc.).
- Performance: the scene runs inside a menu bar popover; keep the node count modest and reuse geometry.
