# Pre-public checklist

Status: ✅ done · 🟡 partial / in progress · ⬜ to do · 👤 owner action (not done by tooling).

## Content and legal

| Status | Item | Notes |
|---|---|---|
| ✅ | Trademark / IP scrub of public themes | Fictional football clubs; Impostor/Wizard/Galactic/Fellowship wording and names reworked. See [IP_NOTES.md](IP_NOTES.md). Re-run the grep pass (below) after any theme change. |
| ✅ | Asset licence statement | All scenes procedural; Simple Icons glyphs CC0; trademark notice in README and IP_NOTES. |
| ⬜ 👤 | Trademark search for "Hubbub" | Common word; check USPTO/EUIPO and app stores for software named Hubbub, and consider a more distinctive name before 1.0. |
| 🟡 | License headers | `LICENSE` is MIT ("Hubbub contributors"). Source files have no per-file headers; this is fine for MIT. Decide whether to add SPDX lines (`// SPDX-License-Identifier: MIT`). Confirm the copyright holder name in `LICENSE`. |
| ✅ | Undocumented quota API risk documented | README, SECURITY.md, [QUOTA.md](QUOTA.md); in-app "Quota unavailable (API changed)" state and kill switch. |
| ✅ | Unofficial / not-affiliated disclaimer | README, IP_NOTES. |

## Private content must not leak

| Status | Item | Notes |
|---|---|---|
| ✅ | Local-only files and scratch builds are not tracked | `.build-*` is in `.gitignore`; machine-local patterns live in `.git/info/exclude`. Verify with `git status --ignored` and `git ls-files \| grep -iE "\.app/\|\.dmg"`. |
| ✅ | Theme hook audit | Public sources contain no build-flag-specific blocks; third-party theme packs plug in through the generic `ThemeExtension` API (see `docs/CREATING_THEMES.md`). |
| ✅ | History rewrite | Re-check right before switching visibility: `git log --all --stat` and `git log --all -S"<private name>"`. If anything shows up, rewrite with `git filter-repo` *before* going public. |
| ⬜ | Scan for personal data | `docs/images/` must contain synthetic data only (`scripts/make-screenshots.sh` renders a sandboxed copy with invented sessions; `scripts/make-gifs.sh` uses fake agents). README visuals are generated; re-run both scripts after UI/theme changes. Check for usernames, paths, session titles in docs and fixtures. |

## Release and distribution

| Status | Item | Notes |
|---|---|---|
| ✅ | Developer ID signing and notarization | Optional and supported: set `SIGN_IDENTITY` / `NOTARY_PROFILE` for `scripts/release.sh` (setup in [RELEASING.md](RELEASING.md)). Until then builds are ad-hoc signed and users right-click → Open. Remove the `xattr` instructions from README and the cask caveats once notarized. |
| ⬜ | sha256 in the Homebrew cask | `scripts/release.sh` writes `version`/`sha256` into `packaging/homebrew/Casks/hubbub.rb` from the real DMG; commit it, then publish the `homebrew-hubbub` tap. Never guess it. |
| ⬜ | First tagged release | Run `scripts/release.sh --dry-run`, then `scripts/release.sh` (draft) and publish it on GitHub. Check that `https://github.com/karakayautku4/hubbub/releases/latest/download/Hubbub.dmg` downloads (needs the repo to be public). `VERSION` must match the tag. |
| ⬜ | Update-check repo | `HubbubRepo` in Info.plist (set in `build-app.sh`) must point at the public `owner/repo`. |

## Repository settings (after switching to public)

| Status | Item | Notes |
|---|---|---|
| ⬜ 👤 | Visibility → Public | Do the checklists above first. |
| ⬜ 👤 | Description and topics | e.g. `macos`, `menubar`, `swift`, `swiftui`, `scenekit`, `ai-agents`, `github-copilot`, `claude-code`, `codex`, `monitoring`. |
| ⬜ 👤 | Private vulnerability reporting | Enable under Settings → Code security (SECURITY.md links to it). |
| ⬜ 👤 | Branch protection on `main` | Require the CI job; block force pushes. |
| ⬜ 👤 | Discussions | Enable; add categories (Q&A, Ideas, Show and tell); link from README. |
| ⬜ 👤 | Issue and PR templates | Present in `.github/`; check the labels they reference exist. |
| ⬜ 👤 | Social preview image | Use `docs/images/theme-space.jpg` or a cropped hero. |
| ⬜ | Fresh-Mac install test | Download the DMG from the draft release on a clean Mac/user account, drag to Applications, confirm the first-run steps in the README work. |
| ✅ | CI | `.github/workflows/ci.yml` builds and runs every headless self-test (`scripts/run-selftests.sh`). |
| ⬜ | CODEOWNERS / Dependabot | Optional; there are no package dependencies, so Dependabot would only cover Actions. |

## Quick pre-flight commands

```sh
swift build -c release && scripts/run-selftests.sh
git ls-files | grep -iE "\.app/|\.dmg"                           # expect no output
git log --all --stat | grep -iE "\.app/|\.dmg"              # history check
```

