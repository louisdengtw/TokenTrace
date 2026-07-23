# Proposal: dynamic-scoped-limits

## Why

The claude.ai usage API restructured its response: `seven_day_sonnet` (and every
other legacy `seven_day_*` model key) is now permanently `null`, and
model-scoped weekly limits moved into a generic `limits[]` array whose entries
carry the model name dynamically (`scope.model.display_name` — currently
"Fable"). TokenTrace still parses only the three hardcoded legacy keys, so the
model-scoped weekly line silently disappeared from the dashboard, menu bar, and
exports. Verified live on 2026-07-23: sonnet traffic registers only in
`session` / `weekly_all`; the server no longer tracks Sonnet separately.

## What Changes

- Parse the `limits[]` array (`session`, `weekly_all`, `weekly_scoped` kinds)
  as the primary source of utilization data, keeping the legacy top-level keys
  as a fallback for older API responses.
- Replace the hardcoded `seven_day_sonnet` bucket with dynamic model-scoped
  buckets: any `weekly_scoped` entry is captured, stored, and displayed with
  its server-provided model display name. **BREAKING** (internal): `Bucket`
  changes from a closed enum to a representation that admits dynamic scoped
  buckets; stored bucket keys gain a new `weekly_scoped:<model>` form.
- Existing `seven_day_sonnet` rows in SQLite remain readable and display as
  the "Sonnet" scoped series (historical continuity, no migration rewrite).
- Dashboard 7-day chart, menu bar popover/stats icon, and both export report
  surfaces label the scoped series with the dynamic model name instead of the
  literal "Sonnet".
- `hasWeeklySonnet` generalizes to "which scoped models are present".

## Capabilities

### New Capabilities

(none — this generalizes existing behavior; no new user-facing surface)

### Modified Capabilities

- `claude-api-integration`: parse `limits[]` (with legacy-key fallback);
  emit dynamic scoped buckets carrying model display names.
- `usage-persistence`: bucket column admits dynamic `weekly_scoped:<model>`
  keys; queries can enumerate distinct scoped buckets in a range; legacy
  `seven_day_sonnet` rows map to the Sonnet scoped series.
- `usage-dashboard`: 7-day chart overlays one line per scoped model present
  in range, labeled dynamically; subtitle/legend no longer hardcode "Sonnet".
- `menu-bar-display`: popover rows and stats-icon column derive label from
  the scoped model name (e.g. "FAB" / "Fable") instead of "SON" / "Sonnet".
- `usage-export`: bucket enumeration, section titles, and colors handle
  dynamic scoped buckets; toggle label reflects the model name.

## Impact

- `Sources/TokenTraceApp/Services/ClaudeAPI.swift` — parse `limits[]`;
  `TokenTraceResponse.hasWeeklySonnet` → scoped-model list.
- `Sources/TokenTraceApp/Models/Bucket.swift` — enum → struct/enum hybrid
  supporting dynamic scoped keys (design decision).
- `Sources/TokenTraceApp/Persistence/UsageStore.swift` — bucket key
  round-tripping; distinct-scoped-bucket query.
- `Sources/TokenTraceApp/Services/UsageManager.swift` — `hasWeeklySonnet`
  replacement, latestSample keying.
- `Sources/TokenTraceApp/MainWindow/DashboardView.swift`,
  `MenuBar/PopoverView.swift`, `MenuBar/StatsIconView.swift`,
  `MenuBar/StatusItemController.swift`, `MainWindow/MenuBarPreviewView.swift`
  — dynamic series/labels.
- `Sources/TokenTraceApp/Services/ReportGenerator.swift`,
  `MainWindow/ExportSheetView.swift` — dynamic bucket order/titles/colors.
- Tests: parser fixtures for the new `limits[]` shape (incl. null legacy
  keys), store round-trip of scoped keys, legacy-row mapping.
- No schema migration required (bucket column is already TEXT), but this is
  confirmed in design.
