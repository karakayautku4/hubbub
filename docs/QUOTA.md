# Copilot quota and the undocumented endpoint

Hubbub's Copilot quota bar ("premium requests used / remaining, reset date, forecast") reads
`GET https://api.github.com/copilot_internal/user`.

> **Risk:** this endpoint is **not part of GitHub's documented public API**. GitHub can change its response, require
> different authentication, rate-limit it or remove it at any time, and its use by third-party tools is not covered by
> any stability promise. Hubbub is unofficial and unaffiliated (see [IP_NOTES.md](IP_NOTES.md)).

## What Hubbub does about it

- **Optional and fail-soft.** Nothing else in Hubbub depends on the quota. Session monitoring, the scene, metrics and
  notifications work from local files only.
- **Graceful degradation.** If the response no longer has the expected shape, or GitHub answers 404/410/422, the
  quota bar shows **"Quota unavailable (API changed). Sessions still work locally."** with a *Why?* link to this page.
  Hubbub then discards the cached numbers (they could be wrong), hides the percentage in the menu bar, and retries only
  about once an hour. Other errors keep their own messages: sign-in needed, rate limit, offline (last known data is
  shown and marked stale).
- **Local-only fallback.** Without a quota you still get token totals, context usage, cost estimates and
  history computed from the local session logs. Credit figures from local logs are **estimates**.
- **Kill switch.** To stop the request completely:
  ```sh
  defaults write dev.hubbub.app copilotQuotaEnabled -bool NO     # re-enable with -bool YES or `defaults delete`
  ```
  Disabling the Copilot provider in Settings → Providers has the same effect.
- **Parser tests.** `Hubbub --selftest-quota` checks the parser against a known-good payload and against schema drift.

## Data handling

Your GitHub token comes from `GH_TOKEN` / `GITHUB_TOKEN` or `gh auth token`. It is held in memory only, never written
to disk or logged, and sent only to `api.github.com`. The request fires at most once a minute, and not at all when no
token exists.

## If it breaks

Open an issue with the HTTP status you see in Settings (do not paste tokens). A fix is usually a one-line change in
`CopilotQuotaAPI.parse` in `Sources/Hubbub/QuotaService.swift`. Other providers' usage endpoints
(Anthropic, ChatGPT, Cursor) are likewise undocumented, opt-in per provider, and degrade to token totals.

See [COST.md](COST.md) for how credits and dollar estimates are displayed.
