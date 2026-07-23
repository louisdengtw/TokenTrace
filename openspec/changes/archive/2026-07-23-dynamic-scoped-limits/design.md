# Design: dynamic-scoped-limits

## Context

The claude.ai usage endpoint now returns:

```json
{
  "five_hour":  { "utilization": 1.0, "resets_at": "..." },     // still live, float
  "seven_day":  { "utilization": 3.0, "resets_at": "..." },     // still live, float
  "seven_day_sonnet": null,                                      // permanently null
  "seven_day_opus": null, "seven_day_cowork": null, ...          // legacy tombstones
  "limits": [
    { "kind": "session",       "group": "session", "percent": 1, "resets_at": "...", "scope": null },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 3, "resets_at": "...", "scope": null },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 5, "resets_at": "...",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null } }
  ]
}
```

Verified live 2026-07-23 with the app's own cookie + URLSession path. Sonnet
traffic increments only `session` / `weekly_all`; the scoped model is chosen
server-side (currently Fable) and cannot be influenced by the client.

Current code: `Bucket` is a closed `String` enum (`five_hour`, `seven_day`,
`seven_day_sonnet`); `parseUsage` reads only the three top-level keys;
`hasWeeklySonnet` gates every Sonnet surface; SQLite `samples.bucket` is TEXT.

## Goals / Non-Goals

**Goals:**
- Capture and display any model-scoped weekly limit the server reports, with
  its server-provided display name, without code changes when the model rotates.
- Keep historical `seven_day_sonnet` rows visible as the Sonnet scoped series.
- Survive both API shapes (with/without `limits[]`) — no regression for old
  fixtures or a temporary server rollback.

**Non-Goals:**
- Surfacing other `limits[]` kinds (`seven_day_oauth_apps`-style, surface
  scopes, `extra_usage`, `spend`). Only `weekly_scoped` with a model name.
- DB schema migration or rewriting historical rows.
- Claude Code tab (unaffected — transcript-derived, different pipeline).

## Decisions

### D1 — `Bucket` becomes an enum with an associated value

```swift
enum Bucket: Hashable, Codable, Sendable {
    case fiveHour
    case sevenDay
    case weeklyScoped(model: String)   // "Fable", "Sonnet", ...
}
```

- `key: String` (computed) replaces `rawValue` for DB round-trip:
  `"five_hour"`, `"seven_day"`, `"weekly_scoped:<model>"`.
- `init?(key: String)` parses those forms **plus** legacy
  `"seven_day_sonnet"` → `.weeklyScoped(model: "Sonnet")`. Historical rows
  therefore merge into the Sonnet scoped series with zero migration.
- New scoped rows are always written as `weekly_scoped:<model>`; queries for
  `.weeklyScoped("Sonnet")` match both keys
  (`WHERE bucket IN ('weekly_scoped:Sonnet','seven_day_sonnet')`).
- Alternative considered: keep `String` raw enum and add cases per model —
  rejected, that's the bug we're fixing. Alternative: free-form struct —
  rejected, loses exhaustive switching for the two fixed windows.
- `CaseIterable` is dropped; the only call sites enumerating buckets already
  build their lists conditionally.

### D2 — Parse precedence: top-level keys first, `limits[]` for scoped + fallback

- `five_hour` / `seven_day`: keep reading the top-level objects (still live,
  float-precision `utilization`). If a top-level key is missing/null but a
  matching `limits[]` entry exists (`session` / `weekly_all`), fall back to
  its integer `percent` + `resets_at`.
- Scoped series: from `limits[]`, take every entry with
  `kind == "weekly_scoped"` and a non-empty `scope.model.display_name`;
  emit `.weeklyScoped(model:)` samples (`percent` → util). Entries without a
  model name (surface scopes etc.) are skipped and logged.
- Legacy `seven_day_sonnet` top-level object, when non-null (old fixtures /
  rollback), still parses → `.weeklyScoped("Sonnet")`.
- Dedup rule: if both sources yield the same scoped model, `limits[]` wins.
- The "missing both five_hour and seven_day" guard stays, now satisfied by
  either source.

### D3 — `hasWeeklySonnet` → `scopedModels: [String]`

`TokenTraceResponse.hasWeeklySonnet: Bool` becomes
`scopedModels: [String]` (order of appearance, deduped).
`UsageManager.hasWeeklySonnet` becomes `@Published scopedModels: [String]`
(reset on sign-out just like today). All `hasWeeklySonnet` gates become
`!scopedModels.isEmpty` / iteration. `latestSample: [Bucket: UsageSample]`
keys work unchanged (`Hashable` synthesized).

### D4 — Display rules

- **Dashboard 7-day chart**: one secondary line per scoped model *present in
  the queried range* (a 30d window can legitimately show both a Sonnet tail
  and a Fable series). Store gains
  `distinctScopedModels(from:to:) -> [String]`. Line color from a fixed
  Okabe-Ito-derived palette assigned by sorted model name; "Sonnet" keeps its
  existing `#009E73` for continuity.
- **Menu bar**: popover row label = model display name; stats-icon column
  label = first 3 letters uppercased (`FAB`, `SON`). Shown only for models in
  the *latest* poll (`scopedModels`), matching today's behavior.
- **Export (subscription report)**: canonical bucket order =
  `[fiveHour, sevenDay] + scoped models in range (sorted)`; per-model toggle
  rows replace the single Sonnet toggle; section title
  `7-Day Window — <Model>`; colors follow the dashboard palette.

### D5 — No DB migration

`samples.bucket` is already TEXT with no CHECK constraint; new keys are just
new strings. Downgrade safety: an older binary reading `weekly_scoped:Fable`
rows fails `Bucket(rawValue:)` and its queries simply never match them — no
crash, acceptable.

## Risks / Trade-offs

- [API churn again — `limits[]` renamed/reshaped] → per-entry tolerant
  parsing (skip + log), top-level fallback retained; parser fixtures for both
  shapes pinned in tests.
- [Integer `percent` loses fractional precision in fallback path] → only
  matters when top-level keys vanish; accepted (1% granularity is what the
  claude.ai UI shows anyway).
- [Model display name changes spelling (e.g. "Fable" → "Fable 5")] → forks a
  new series/color. Accepted for v1; alias-folding would need `scope.model.id`
  which is currently null.
- [Two sources for Sonnet series (legacy + new key)] → confined to the store
  query layer (D1's IN-clause); UI sees one series.

## Migration Plan

Ship as one PR. No data migration. Rollback = revert commit; old binary
ignores `weekly_scoped:*` rows (D5).

## Open Questions

- None blocking. Palette exact hues picked at implementation time against
  both light/dark chart backgrounds.
