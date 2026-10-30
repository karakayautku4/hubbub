# Creating themes

There are two ways to make a theme:

1. **Community theme (JSON)**: no code; recolour and reword one of the built-in 3D sets. See [THEMES.md](THEMES.md).
2. **Built-in theme (Swift)**: new 3D environment, characters, sounds and effects. This guide.

Use only original art and names; no real people, logos or trademarks.

## JSON theme in 2 minutes

Save as `~/Library/Application Support/Hubbub/Themes/my-theme.json`:

```json
{ "id": "my-theme", "title": "My Theme", "emoji": "🧪", "base": "space",
  "palette": { "accent": "#ff8800" }, "characters": { "captainTitle": "Boss" } }
```

Open Settings → Appearance → Reload. Validate headlessly with `Hubbub --selftest-themes`; preview with
`SNAP_CUSTOM=my-theme.json Hubbub --snapshot out.png`. All fields are documented in [THEMES.md](THEMES.md).

## Built-in theme walkthrough

Every built-in theme beyond the first five is one file in `Sources/Hubbub/Themes/<Name>Theme.swift`
(`WizardTheme.swift` is a good reference). The file follows this shape:

```swift
import AppKit
import SceneKit

private enum WZ { /* palette constants and small prop helpers (candle, banner, window …) */ }

extension Environments {
    static func wizard(_ root: SCNNode) { /* floor, walls, props, lights; fills `root` */ }
    static func wizardStation(_ kind: Int, _ n: SCNNode) { /* the 4 work stations, kind 0…3 */ }
}
extension Rig {
    static func wizardOutfit(captain: Bool, v: Int) -> (UInt32, UInt32, UInt32) { /* shirt, trousers, shoes */ }
    static func wizardAccessories(...) { /* hats, beards … */ }
    func wizardGauge(...) / wizardBeacon(...)   // context gauge and alert beacon looks
}
extension Stage {
    static func wizardLighting() -> (...)       // background, ambient, key, fill colours/intensities
    func wizardMotion(_ kind: Int) -> Motion    // which work animation per station
}
extension RoomSim  { func wizardFailure(t: Double) }          // what a failed task looks like
extension RoomSign { static func wizardAgeSign(...) -> NSImage }
extension SoundCenter { func wizardSynth(...) }               // synthesized sounds (no audio assets)
```

### Steps

1. **Register the case** in `Theme.swift`: add `case mytheme` to the enum and satisfy every `switch` the compiler flags
   (`title`, `icon`, `blurb`, role names, quota label, empty/idle/thinking text, preview colours, stations).
2. **Create `Themes/MyThemeTheme.swift`** with the extensions above. Use the helpers in `Gfx.swift`
   (`mat`, `box`, `ball`, `cyl`, `group`, `color`); build from primitives, there is no asset pipeline.
3. **Wire the dispatch** in the shared switches: `Environments.swift`, `Characters.swift`, `Stage.swift` (lighting and
   motion), `MetricsViz.swift` (medal, gauge, beacon, age sign), `Sounds.swift`, `Ambience.swift` (`outdoor`), `Mascot.swift`,
   `SceneEffects.swift` (palette, failure effect) and `Progression.swift` (rank names). The compiler points at the rest.
4. **Keep failures and approvals obvious** with shapes, motion and text, not just colour.
5. **Respect accessibility**: do not add flashing effects; gate looping ambient effects on `A11y.reduceMotion`.
6. **Verify**:
   ```sh
   swift build -c release
   .build/release/Hubbub --selftest-themes
   .build/release/Hubbub --selftest-perf          # your theme is included automatically
   scripts/make-screenshots.sh                    # visual check
   ```
7. Add the theme to the README feature list and `docs/THEMES.md`.

### Jobs (what idle agents do)

Every agent, captain and sub-agents alike, owns a themed **job**: a persistent spot on the map with a prop, a looping
work animation and a pool of funny speech lines. While a real tool call runs, the agent still walks to the station for
that tool kind and returns to its job spot afterwards. Add `Themes/Jobs+MyTheme.swift` (≥ 8 original jobs):

```swift
extension Jobs {
    static var mythemeCatalog: [Job] {
        let b = Jobs.base                                  // 8 template spots; the framework nudges any that touch a station
        return [
            Job("Spoon tunnel", "🥄", spot: b[0], .dig, lines: ["Day 412 with the spoon.", "…"]) { n in
                // `n` sits at the character's feet, the character faces +Z, so props usually live around z ≈ 1.
                JP.table(n)
                JP.bob(n.ball(0.1, JP.glow(0xffd24a), 0, 1.2, 1), 0.2, 0.7)   // cheap looping SCNAction
            },
            // …
        ]
    }
}
```

Then add `case .mytheme: list = mythemeCatalog` to `Jobs.catalog(for:)`. Notes:

- `JobAnim` picks the body animation (`type, hammer, stir, sweep, polish, juggle, stack, wrench, water, yoga, scan, dig,
  pushups, cards, dance, pump, paint, spell, read, tinker, aim, plot, smoke, flip, peel, taste, wash, chase, milk`);
  the poses live in `JobAnimations.swift`. Add a case there if you need a new one.
- `JP` has prop helpers (`table`, `barrel`, `crate`, `pole`, `bucket`, `screen`, `bob`, `sway`, `spin`, `pulse`, `blink`).
  Props are built once per occupied spot and reused; keep them to a handful of primitives and use `SCNAction` loops only.
- Assignment is deterministic (hash of the agent id over the first free spots), so no two agents share a spot until
  every spot is taken. Spots beyond the catalog form a lattice around the base arena.
- **Dynamic arena**: the playable area and camera framing grow smoothly with the number of occupied spots (up to 30
  agents). `ArenaExtension` (`Arena.swift`) adds oversized floor/wall slabs cloned from your environment (any node named
  `floor`, plus back walls ≥ 30 wide) and a few generic props, so name your floor node `floor` or `Environments.floor()`.
- Users can zoom with scroll/pinch, ⌘+ / ⌘− / ⌘0 or the +/−/fit control; zoom is kept per session.
- Verify: `Hubbub --selftest-jobs` (catalog size, slot uniqueness/spacing, zoom maths) and
  `CREW_FAKE_AGENTS=20 SNAP_THEME=mytheme Hubbub --snapshot out.png` (N = 3, 8 and 20 are the interesting cases).

### Performance budget

Keep the node count modest, reuse geometry/materials, and avoid per-frame allocations. `--selftest-perf` fails when the
frame tick, offscreen render, CPU or memory exceed the thresholds in `scripts/perf-check.sh`.

## External theme extensions

Theme packs that live outside this repository (third-party or private forks) can customize a theme without patching the
core through the `ThemeExtension` protocol (`Sources/Hubbub/ThemeExtension.swift`). Ship an `NSObject` subclass exposed to
the Objective-C runtime as `HubbubThemeExtension` (`@objc(HubbubThemeExtension)`); it is discovered once at launch.
Every hook returns `nil` to keep the built-in default: `outdoorLevel`, `music`, `raceMotif`, `raceLines`, `raceTitle`,
`guestPool`, `guestQuip`, `mascotKind`, `effectPalette`, `levelTitles`. With no extension present the app behaves exactly
as documented above.
