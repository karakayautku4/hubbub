# Releasing

Goal: people download **Hubbub.dmg** from GitHub Releases, drag the app to Applications, done. No building.

## One command (local, recommended)

```sh
# 1. bump VERSION (e.g. 0.3.0) and commit; the working tree must be clean
# 2. draft release (default), or --publish, or --dry-run (builds everything, skips tag/push/gh)
scripts/release.sh --dry-run
scripts/release.sh            # creates tag v<VERSION>, pushes the tag, creates a DRAFT release
```

`scripts/release.sh` checks a clean tree and a valid `VERSION`, runs the self-tests,
runs `make-dmg.sh`, computes the sha256, creates the tag and a GitHub release (`gh release create`, generated notes) with
`Hubbub-<version>.dmg`, `Hubbub.dmg` and `SHA256SUMS.txt`, and updates `version`/`sha256` in
`packaging/homebrew/Casks/hubbub.rb` (the file is only edited; review, commit and push it yourself). Open the draft on
GitHub and press **Publish**. Needs `gh auth login` first.

## What `make-dmg.sh` produces (`dist/`)

| File | Purpose |
|---|---|
| `Hubbub-<version>.dmg` | Versioned asset. The in-app update check looks for a `Hubbub-<version>.dmg` asset, so keep this name. |
| `Hubbub.dmg` | Stable name for `https://github.com/karakayautku4/hubbub/releases/latest/download/Hubbub.dmg` (README button). |
| `SHA256SUMS.txt` | Checksums of both DMGs. |

The app is a universal binary (arm64 + x86_64; falls back to the native arch if the toolchain cannot build both). It builds in
`.build-dmg` (override with `SCRATCH=`), so it does not disturb `.build`. Note that `build-app.sh` rewrites `./Hubbub.app`: if
that is your live copy, run the release from a separate clone. The DMG window (background, icon positions, hidden toolbar) is
laid out through Finder/AppleScript; the first time, macOS asks to let Terminal control Finder. `NO_LAYOUT=1` skips this (the DMG
still works, just unstyled). The script mounts the result read-only and checks the app, `Applications` link, background, readme,
signature and `Hubbub --status`.

## Signing: ad-hoc (default) vs Developer ID + notarization (optional)

Without any setup the app is **ad-hoc signed** (`codesign --sign -`). It passes `codesign --verify --deep --strict`, but
Gatekeeper rejects it (`spctl` says "rejected") because it is not notarized: users open it once via right-click → Open
(see README and `Read Me First.html` inside the DMG).

With an Apple Developer ID the DMG opens with **no warning**. Environment variables switch it on:

| Variable | Meaning |
|---|---|
| `SIGN_IDENTITY` | e.g. `Developer ID Application: Jane Doe (ABCDE12345)`. Signs the app (hardened runtime, timestamp, `packaging/entitlements.plist`) and the DMG. |
| `NOTARY_PROFILE` | Name of a `notarytool` keychain profile. Notarizes the app and the DMG and staples both tickets. Requires `SIGN_IDENTITY`. |

If the identity or the tools are missing the script says so and falls back (ad-hoc / no notarization). Nothing secret is printed.
`packaging/entitlements.plist` holds `com.apple.security.automation.apple-events`, needed under the hardened runtime for the opt-in
"reply from Hubbub" feature that scripts Terminal; the app is not sandboxed, so nothing else is required.

### One-time setup (local)

1. Join the Apple Developer Program, then create a **Developer ID Application** certificate (Xcode → Settings → Accounts →
   Manage Certificates → + → Developer ID Application, or developer.apple.com → Certificates).
2. List it: `security find-identity -v -p codesigning` and copy the quoted name.
3. Create an app-specific password at appleid.apple.com → Sign-In and Security → App-Specific Passwords.
4. Store credentials in the keychain (prompts for the password; nothing lands in the repo):
   ```sh
   xcrun notarytool store-credentials "hubbub-notary" --apple-id "you@example.com" --team-id "ABCDE12345"
   ```
5. Release:
   ```sh
   SIGN_IDENTITY="Developer ID Application: Jane Doe (ABCDE12345)" NOTARY_PROFILE=hubbub-notary scripts/release.sh
   ```
   The script verifies with `stapler validate` and `spctl -a -t open --context context:primary-signature -vv`.

Official releases are Developer ID signed and notarized; the README and cask no longer carry `xattr` instructions.

### GitHub Actions (optional)

`release.yml` builds on a tag push or manually (Actions → Release → Run workflow, giving an existing tag). To sign there, add
repository secrets: `DEVELOPER_ID_P12_BASE64` (`base64 -i cert.p12 | pbcopy`, exported from Keychain Access with a password),
`DEVELOPER_ID_P12_PASSWORD`, `SIGN_IDENTITY`, and for notarization `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`,
`NOTARY_APP_PASSWORD` (the app-specific password). The workflow imports the certificate into a temporary keychain. Without
the secrets it builds ad-hoc. CI builds use `NO_LAYOUT=1` (Finder is not scriptable on hosted runners), so the DMG is
functional but unstyled; prefer the local script for the polished DMG.

**Billing caveat:** hosted macOS runners currently fail because of account billing. Until that is resolved, release locally with
`scripts/release.sh`; the workflow is a fallback.

## Homebrew

`release.sh` fills `version`/`sha256` in `packaging/homebrew/Casks/hubbub.rb` (never write the sha by hand). Copy the cask into
the `homebrew-hubbub` tap as described in `packaging/homebrew/README.md`.

## Before the first release

Private repositories hide release assets from the public, so the download button only works after the repo is public
([PUBLIC_CHECKLIST.md](PUBLIC_CHECKLIST.md)). The in-app update check likewise needs a public repo.
