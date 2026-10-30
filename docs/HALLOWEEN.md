# Halloween mode

A seasonal overlay that works on top of every theme, in the 3D scene and in the app frame.

**Setting:** Settings → Appearance → Scene → *Halloween mode*: Auto (default, Oct 24 – Nov 1 by your calendar), On, or Off. Stored in `UserDefaults` as `halloweenMode` (`auto|on|off`).

**Debug:** `HUBBUB_HALLOWEEN=1` forces it on, `=0` forces it off, beating the setting. `HUBBUB_HALLOWEEN_DEBUG=boo,bat` triggers the BOO! gag and a bat flight within a few seconds. Example: `HUBBUB_HALLOWEEN=1 Hubbub --fxshot space out.png 4`.

## What it adds

- **Scene** (`Fun/HalloweenScene.swift`, one layer owned by `FunLayer`): carved pumpkins with a flickering emissive glow (no extra lights, just emissive materials and additive floor pools), tombstones, a skull and candy at the arena edges, three drifting ghosts, an occasional bat flight and a rare "BOO!". A faint purple vignette is attached to the camera, so it hugs the frame corners at any zoom or window size. About 45 nodes, shared geometry and materials, built lazily; while the mode is off the layer is hidden and does no work.
- **Keep-outs:** props sit in two columns just outside the job spots (`arena.xHalf - 0.5`) and follow arena growth; ghosts and bats stay high above the agents.
- **Reduce Motion:** no drifting, bats or BOO!; the glow stops flickering.
- **App UI** (`HalloweenChrome.swift`): cobwebs (about a fifth of the width) in both top corners with a hanging spider, two bats by the header, a glowing jack-o'-lantern in the bottom-left and a skull bottom-right, plus an orange accent (`.tint`). Decorations are non-interactive and hidden from VoiceOver; webs, spider and bats are dropped under Increase Contrast. Status colours and the menu bar text are unchanged. Preview: `--snapshot-halloween out.png [WxH] [dark] [settings]`.

## Test

`Hubbub --selftest-halloween` covers the date window (Oct 24 – Nov 1), Auto/On/Off, the env override and the node budget.
