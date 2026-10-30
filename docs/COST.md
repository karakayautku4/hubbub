# Cost in Hubbub

Hubbub shows what it can measure and never invents prices.

## Units

| Provider | What is shown | Unit |
|---|---|---|
| GitHub Copilot CLI | `usage_record` cost from the session log | **credits** (premium requests), not dollars |
| Claude Code, Codex, Cursor, Gemini, Grok, Crew | tokens only | tokens |

Credits and dollars are different units and are **never added together**. When both exist, Insights shows them side by side.

## Dollar estimates

A `$` figure appears only when `~/Library/Application Support/Hubbub/prices.json` contains a row for the model **with both `source` (URL) and `asOf` (YYYY-MM-DD)**. Rows without them are ignored. The shipped defaults contain no prices.

* Estimates are always written `~$0.42` and labelled `est.` (tokens × list price; ignores cache and your plan).
* Rows older than 180 days are flagged in the tooltip.
* Unknown model or no row: the cost tile is hidden / shows `—`, with “no price set”.
* Copilot credits are converted only if a `credits` row has `usdPerCredit`, `source` and `asOf`.

```json
{
  "version": 1,
  "currency": "USD",
  "models": [
    { "match": "my-model", "inPerM": 1.0, "outPerM": 2.0, "cachedInPerM": null,
      "source": "https://vendor.example/pricing", "asOf": "2026-01-31" }
  ],
  "credits": [
    { "provider": "copilot", "usdPerCredit": null, "source": null, "asOf": null }
  ]
}
```

`match` is a case-insensitive *contains* on the model name; the first documented row wins. Prices are USD per million tokens. Edit the file (Settings ▸ Providers ▸ Prices ▸ Reveal prices.json); changes load on reload. An invalid file is ignored and the defaults stay in effect.

## Per-day attribution and duration

Session records store lifetime totals, so Insights ("Today", "Week", tokens-per-day chart, provider/model comparison) uses a per-day ledger (`SessionRecord.days`, `yyyy-MM-dd` in the local calendar) and counts only the share that falls inside the range.

- **Copilot:** exact. Each `session.usage_record` event's tokens/credits are bucketed by its own timestamp. Per-day values only grow when merged, so the 2 MB read window sliding forward never lowers a day.
- **Other providers (no per-event usage):** growth since the previous snapshot is attributed to the day it was observed (the session's last event day). Accurate to the scan interval.
- **Records from before this existed** (no `days`): the lifetime total is spread evenly over the days between start and last event. That is an estimate, but a multi-day session no longer lands on a single day. Live sessions replace the estimate with real data as they are re-read.

Durations are *active time*: the sum of gaps between consecutive events, each gap capped at 30 minutes, and never more than the wall-clock span. Records without active time show at most 8 h. Limitation: for sessions longer than the 2 MB read window, active time and Copilot per-day data cover only what has been read while Hubbub was running.

See also [QUOTA.md](QUOTA.md). Self-test: `Hubbub --selftest-fmt` (includes a multi-day session).
