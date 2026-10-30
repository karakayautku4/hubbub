# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Use GitHub's
[private vulnerability reporting](../../security/advisories/new) on this repository. Include steps to reproduce and the
affected version. You can expect an initial answer within a week.

## Scope and design

Hubbub is a local, read-only viewer:

- It reads session logs of AI coding agents from your home folder (e.g. `~/.copilot`, `~/.claude`, `~/.codex`,
  `~/.gemini`, `~/.hubbub`). It never writes to them.
- The only network requests are the ones listed in the README's Privacy section: the GitHub Copilot quota lookup
  (`api.github.com/copilot_internal/user`, token from `GH_TOKEN`/`GITHUB_TOKEN` or `gh auth token`), opt-in per-provider
  usage lookups, and the update check. Tokens are kept in memory only, never written to disk or logged. Without a
  token the quota bar is simply hidden.
- **Undocumented endpoints.** The Copilot quota lookup (and the opt-in Anthropic, ChatGPT and Cursor usage lookups) use
  endpoints that are not documented public APIs. They can change, break or be restricted without notice. Hubbub treats
  them as optional: on schema drift it shows "Quota unavailable (API changed)" and keeps working from local data, and the
  Copilot call can be disabled entirely. See [docs/QUOTA.md](docs/QUOTA.md). Your token is only ever sent to the
  provider that issued it.
- Opt-in features have their own surface: *Reply from Hubbub* uses a per-user Unix socket (mode 0600) and optional
  terminal control ([docs/REPLY.md](docs/REPLY.md)); *Team sync* writes metadata-only snapshots to a folder you choose.
  Both are off by default.
- No telemetry, analytics or crash reporting.
- Message text from sessions is not stored by the app; only short tool descriptions (command/path) are displayed.

Reports about anything that breaks these properties are especially welcome.

## Supported versions

Only the latest release receives fixes.
