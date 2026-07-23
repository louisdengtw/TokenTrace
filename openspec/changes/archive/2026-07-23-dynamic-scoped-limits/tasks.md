# Tasks: dynamic-scoped-limits

## 1. Bucket model

- [x] 1.1 Rewrite `Models/Bucket.swift`: enum with `fiveHour`, `sevenDay`, `weeklyScoped(model: String)`; `key: String` computed property (`weekly_scoped:<model>`); `init?(key:)` accepting the two fixed keys, `weekly_scoped:*`, and legacy `seven_day_sonnet` → `.weeklyScoped("Sonnet")`; manual `Codable` via `key`; drop `CaseIterable`
- [x] 1.2 Fix all compile errors from the enum change across `Sources/TokenTraceApp/` (rawValue → key, exhaustive switches gain `.weeklyScoped` case)
- [x] 1.3 Unit tests: key round-trip for all forms, legacy-key mapping, Hashable dictionary keying

## 2. Parser (ClaudeAPI)

- [x] 2.1 Extend `parseUsage`: read `limits[]` — `weekly_scoped` entries with `scope.model.display_name` → scoped samples; skip+log unnamed scopes; `session`/`weekly_all` as fallback when top-level `five_hour`/`seven_day` missing/null
- [x] 2.2 Keep legacy non-null `seven_day_sonnet` parsing → scoped "Sonnet"; dedup rule limits-wins; replace `hasWeeklySonnet` with `scopedModels: [String]` in `TokenTraceResponse`
- [x] 2.3 Parser tests: current-shape fixture (null tombstones + Fable scoped), legacy-shape fixture, no-scoped fixture, top-level-absent fallback fixture, unnamed-scope skip

## 3. Persistence (UsageStore)

- [x] 3.1 `query(bucket:from:to:)` for `.weeklyScoped("Sonnet")` matches both `weekly_scoped:Sonnet` and `seven_day_sonnet` keys (single ascending series)
- [x] 3.2 Add `distinctScopedModels(from:to:) -> [String]` (legacy rows count as "Sonnet"; deterministic order)
- [x] 3.3 Store tests: scoped-key insert/query round-trip, legacy+new merged series, distinct-models enumeration

## 4. UsageManager

- [x] 4.1 Replace `hasWeeklySonnet` with `@Published scopedModels: [String]` (cleared on sign-out); update `latestSample` merge for scoped buckets
- [x] 4.2 Update all `hasWeeklySonnet` call sites (`StatusItemController`, `PopoverView`, `MenuBarPreviewView`, `MainWindowContent`, `DashboardView`)

## 5. Dashboard

- [x] 5.1 7-day chart: query `distinctScopedModels` for the visible range; overlay one series per model with dynamic label
- [x] 5.2 Deterministic per-model color palette (Sonnet keeps `#009E73`); legend + subtitle text dynamic
- [x] 5.3 Tooltip shows Overall + each scoped model's value labeled by name

## 6. Menu bar

- [x] 6.1 `PopoverView`: scoped rows from `scopedModels`, full display name label
- [x] 6.2 `StatsIconView` + `StatusItemController`: scoped column with 3-letter uppercased label (FAB/SON); `MenuBarPreviewView` follows
- [x] 6.3 Manual verify: popover + stats icon render with live Fable data

## 7. Export

- [x] 7.1 `ExportSheetView`: scoped checkboxes built from store's distinct scoped models (default unchecked), label `7-day Window — <Model>`
- [x] 7.2 `ReportGenerator`: dynamic canonical order (`fiveHour`, `sevenDay`, scoped sorted by name), dynamic section titles + colors
- [x] 7.3 Export an HTML + PDF report containing a scoped bucket; visually verify (self-check before asking user)

## 8. Docs & wrap-up

- [x] 8.1 Update `CLAUDE.md` (API endpoints section: `limits[]` shape; remove hardcoded seven_day_sonnet references)
- [x] 8.2 Full build + test run; `pkill -x TokenTrace` + relaunch + live-poll sanity check (Fable line appears on 7-day chart)
- [x] 8.3 Branch `feat/dynamic-scoped-limits`, PR, ready for review
