## 1. Platform and build infrastructure

- [x] 1.1 Update `Package.swift` `platforms` from `.macOS(.v13)` to `.macOS(.v14)`
- [x] 1.2 Update `CLAUDE.md`'s "Min macOS" line and the SwiftUI Charts note (and `Resources/Info.plist` `LSMinimumSystemVersion`)
- [x] 1.3 Build clean to confirm nothing else referenced 13-only fallback semantics; do NOT remove the existing `chartXSelectionIfAvailable` shim (out of scope for this change). Note: surfaces 2 `onChange(of:perform:)` deprecation warnings in `SettingsView.swift`, harmless, leave as follow-up
- [x] 1.4 In `tools/build-app.sh`, make `APP_NAME` and `BUNDLE_ID` env-overridable (default `TokenTrace` / `dev.louisdeng.tokentrace`); `plutil -replace` the identity keys (CFBundleIdentifier, CFBundleName, CFBundleDisplayName, CFBundleExecutable, CFBundleIconFile) so non-default values produce a separately-installable .app
- [x] 1.5 In `Makefile`, add `dev` / `dev-install` / `dev-run` targets exporting `APP_NAME=TokenTraceDev BUNDLE_ID=dev.louisdeng.tokentrace.dev` and acting on `build/TokenTraceDev.app` / `/Applications/TokenTraceDev.app`; `dev-run` `pkill` targets `TokenTraceDev` only, not `TokenTrace`
- [x] 1.6 Smoke: `make build` produces `TokenTrace.app` unchanged (verified: bundle id `dev.louisdeng.tokentrace`); `make dev-run` produces and launches `TokenTraceDev.app` alongside production (verified: bundle id `dev.louisdeng.tokentrace.dev`, runs alongside production with no menu-bar collision)

## 2. UI prototype with stub data

The chart is the highest-risk visual element in this change. Build it first with hardcoded data so the dual-axis Swift Charts layout, the four-component sub-stack per project, and hover synchronisation can be evaluated before committing to the data layer.

- [x] 2.1 Create `MainWindow/CCUsageView.swift` with the chart structure: single `Chart` with dual Y axis (`AxisMarks(position: .leading)` for weighted volume, `.trailing` for utilisation), stacked `AreaMark` on left axis with four sub-bands per project, `LineMark` on right axis for `five_hour` (solid) + `seven_day` (dashed). Note: per-project four-sub-band sub-stack deferred — current implementation uses one stacked area per project; the four-component breakdown surfaces in the project totals list's Mix bar and in the hover tooltip
- [x] 2.2 Add `MainWindow/CCUsagePreviewData.swift` with hardcoded fixtures: 3–4 fake projects with realistic 7-day distributions; fake subscription samples for 5h/7d that visibly correlate with one of the projects' activity peaks (so hover utility is demonstrable on the prototype)
- [x] 2.3 Add a TEMPORARY "Claude Code" tab to `DashboardView.swift` pointing at `CCUsageView` (the proper `TabView` refactor in group 11 will subsume this — keep this hack minimal so it's easy to replace later); gated behind `bundleIdentifier?.hasSuffix(".dev")` so production is untouched
- [x] 2.4 Header row: Refresh + Manage projects… + info-caveat affordances rendered as static placeholders (buttons visible, do nothing yet)
- [x] 2.5 `chartXSelection(value: $selectedDate)` + `chartOverlay` for hover guideline + unified tooltip, driven by the stub data; tooltip shows per-project weighted volume + 5h/7d utilisation at the cursor
- [x] 2.6 Legend below the chart, mapping project → colour (colour-blind-safe palette as first cut)
- [x] 2.7 Run the app; capture screenshots in both light and dark mode. Out of original scope but added during prototype iteration: stats strip (Total / Top project / Peak 5h util), project totals card with weighted-contribution Mix bar, Opus/Sonnet split per project, tab-aware Export button + stub `CCExportSheetView` (drives Decision 11 in design.md)

## 3. Prototype gate (owner review)

- [x] 3.1 Owner reviews the running prototype + screenshots
- [x] 3.2 Decide path: **(i)** Visual is acceptable — continue to group 4; prototype view code retained, group 12 just swaps stubs for real queries; skip group 16 except 16.3 (resize test). Detour during gate: tab-aware Export was added (new Decision 11 + Group 13 + `usage-export` spec delta).

## 4. Schema additions

- [x] 4.1 Append `createCCMessageTable` DDL to `Persistence/Schema.swift` (`uuid` PK, four token columns, `ts`, `cwd`, `model`, `session_id`, `request_id`, `is_sidechain`, `file_path`)
- [x] 4.2 Append `createCCMessageTsIndex` and `createCCMessageCwdTsIndex` to `Schema.swift`
- [x] 4.3 Append `createCCIngestCheckpointTable` (`file_path` PK, `byte_offset`, `file_size`, `mtime`)
- [x] 4.4 Append `createProjectAliasTable` (`cwd` PK, `display_name`)
- [x] 4.5 Confirm `UsageStore.init` iterates the extended `allDDL`; manually verify the new tables on a fresh DB file (verified via `sqlite3 ~/Library/Application\ Support/dev.louisdeng.tokentrace.dev/usage.sqlite ".tables"` after first dev launch). Also fixed an isolation bug discovered during verification: `UsageStore.defaultDatabaseURL()` hard-coded the path to `dev.louisdeng.tokentrace`, causing the dev variant to share production data; now derives the dir from `Bundle.main.bundleIdentifier`, with the legacy claudeusage migration gated to the production bundle only

## 5. Weighted token volume model

- [x] 5.1 Add `Models/CCWeightedVolume.swift` with weight constants (1.0 / 5.0 / 1.25 / 0.1) and inline comment citing the Anthropic API pricing source (date the citation)
- [x] 5.2 Add `func weightedTotal(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Double` helper
- [x] 5.3 Unit tests `CCWeightedVolumeTests`: representative record (700.0), cache-heavy edge (10000.0), zero record (0.0), Int overflow guard, plus a weight-constants-match-spec lock test (5 tests total, all pass)

## 6. Range chip — add 90d

- [x] 6.1 Add `case last90d` to `RangePreset` in `Models/RangeSelection.swift`, between `last30d` and `all`
- [x] 6.2 Extend `label` to return `"90d"`
- [x] 6.3 Extend `resolved(now:oldestSample:)` to return `now − 90·86400 ... now`. Also extended `trendDescription` for completeness
- [x] 6.4 Unit test `RangeSelectionTests`: `last90d` round-trips through `Codable`, resolves correctly, decodes unchanged from older AppSettings payloads that store `last24h/7d/30d/all`, and the picker's `.allCases` ordering is locked. 7 tests, all pass

## 7. AppSettings — last-active tab persistence

- [x] 7.1 Add `lastDashboardTab: DashboardTab` to `AppSettings.swift` (new top-level `enum DashboardTab: String { case subscription, claudeCode }`). NOTE: temporary duplication with `DashboardTabKey` in `DashboardView.swift` (same cases) — group 11 will consolidate when the proper TabView refactor lands
- [x] 7.2 Default to `.subscription` when no prior value is stored
- [x] 7.3 Encode-on-write, decode-on-read with `subscription` fallback for unknown/corrupt values. Tests: default-when-absent, write-then-read round-trip, corrupt-string fallback, unknown-future-case fallback. 4 tests, all pass

## 8. CCUsageStore (data layer)

- [x] 8.1 Add `Persistence/CCUsageStore.swift`. Also added `Models/CCMessage.swift` for the row value type (separate from the store class — used by both store and ingester)
- [x] 8.2 `insertMessages(_ rows: [CCMessage])` — batched `INSERT OR IGNORE` in a single transaction; returns `(inserted: Int, ignored: Int)` by reading `sqlite3_changes` per row
- [x] 8.3 `tokensByProject(from:to:bucket:) -> [ProjectSeries]` — group by `(cwd, bucket_floor(ts))` in SQL, sum the four token components; `ProjectBucket.weightedTotal` derives from `CCWeightedVolume`
- [x] 8.4 Alias lookup applied at query time in Swift (single `SELECT cwd, display_name FROM project_alias` once; map applied during merge). Synthesised fallback = last two non-empty path components, or full `cwd` when fewer
- [x] 8.5 Zero-fill: every project series spans all bucket boundaries in `[from, to]`; absent boundaries are emitted with zero counts. Implementation: post-SQL pass that walks `bucketBoundaries(from:to:secondsPerBucket:)` per project
- [x] 8.6 Projects with no rows in `[from, to]` are naturally omitted because the SQL `WHERE` only returns rows in range; only cwds that survive the WHERE appear in the result
- [x] 8.7 `oldestCCMessageTimestamp() -> Date?` — `SELECT MIN(ts)` with null-handling
- [x] 8.8 `aliases() -> [String: String]`, `setAlias(cwd:displayName:)` (INSERT OR REPLACE), `removeAlias(cwd:)` (DELETE)
- [x] 8.9 `observedCwds() -> [String]` — `SELECT DISTINCT cwd FROM cc_message ORDER BY cwd`
- [x] 8.10 Unit tests `CCUsageStoreTests`: insert + dedup counts, empty insert no-op, two-project zero-fill (project A days 0–2, project B days 1–3, range days 0–4 → 5 buckets each with zero entries at absent days), absent project omitted from result, empty range returns `[]`, inverted range returns `[]`, alias merge with per-bucket sum, alias overrides synthesised label, single-component cwd returns full path, oldest timestamp empty / populated, aliases CRUD (empty / set / replace / remove / remove-unknown-no-op), observedCwds distinct + sorted. 18 tests, all pass

## 9. CCUsageIngester (file walking + parsing + checkpoints)

- [x] 9.1 Add `Services/CCUsageIngester.swift`. Also extended `CCUsageStore` with `checkpoint(forFile:)` / `setCheckpoint(forFile:byteOffset:fileSize:mtime:)` + `CheckpointRecord` (could not be in Group 8 since 8's scope was message tables only)
- [x] 9.2 Recursive directory walk via `FileManager.default.enumerator(at:includingPropertiesForKeys:options:)` filtering on `pathExtension == "jsonl"` and `isRegularFile`. Subagent files at depth 4 are reached because the enumerator is recursive by default
- [x] 9.3 Checkpoint lookup with the documented resume/rescan rule. Path canonicalisation added (`URL.resolvingSymlinksInPath`) so the checkpoint key is stable across macOS's `/var/folders → /private/var/folders` symlink (and any future symlinked root)
- [x] 9.4 Line-buffered tail read; `tail.lastIndex(of: 0x0A)` finds the last newline; only bytes up to and including that newline are consumed. The partial trailing line stays in the file for the next run
- [x] 9.5 Filter implemented in `parseAssistantLine` — wrong `type`, `<synthetic>` model, or missing `usage` returns nil
- [x] 9.6 Privacy invariant: `JSONLine` Decodable struct declares only the projection keys (no `content`). `JSONDecoder` reads past the content bytes during tokenisation but never materialises them into a Swift String/Data. Verified by test 10.9 (sqlite file contents grep'd for the secret marker — absent)
- [x] 9.7 Outer `usage.*_tokens` fields only; `iterations` is not in `JSONLine`, so it's silently ignored
- [x] 9.8 Batched flush at `flushEvery = 1000` rows
- [x] 9.9 `uuidPayloadDivergence` accumulator scoped to the ingest run (not per-file), so cross-file divergence is also detected. INSERT OR IGNORE handles the DB-level first-seen-wins; the counter is the observability hook
- [x] 9.10 On EOF, `setCheckpoint(forFile:byteOffset: startOffset + consumableEnd, fileSize:, mtime:)`
- [x] 9.11 `ingest() async -> IngestSummary` via `DispatchQueue.global(qos: .utility).async` + `withCheckedContinuation`. IngestSummary is the documented tuple plus a `coldScanOccurred` Bool driving 9.12
- [x] 9.12 `coldScanOccurred` flag in `IngestSummary` — true iff any file in the run required a cold scan (no prior checkpoint, or shrunk/regressed mtime). The CCUsageView will drive the "Indexing…" indicator off this flag

## 10. CCUsageIngester tests (with fixtures)

- [x] 10.1 Fixtures generated programmatically per-test via `assistantLine(...)` + `writeJSONL(...)` helpers in `CCUsageIngesterTests` — keeps fixtures next to the assertions that use them rather than shipping a static `Tests/Fixtures/cc-projects/` tree
- [x] 10.2 `testColdIngestProducesExpectedRowsAndSubagentAttribution`: 3 main + 2 subagent rows → 5 inserted, subagent rows attributed to parent cwd. Plus `testNonJsonlSiblingsIgnored` confirming `.meta.json` is skipped
- [x] 10.3 `testReIngestIsIdempotent`: 2 rows on first run, 0 inserted on second; `coldScanOccurred=false` on the second run
- [x] 10.4 `testSyntheticAndMissingUsageSkippedButOffsetAdvances`: synthetic + missing-usage lines yield 0 rows; appending a new line afterwards and re-ingesting consumes only the new line (proves offset advanced past the filtered ones)
- [x] 10.5 `testPartialTrailingLineDoesNotConsume`: file ends mid-line → only complete line ingested; checkpoint byte_offset equals position right after the only `\n`; completing the line + appending more on a second pass picks them up
- [x] 10.6 `testSameUuidSamePayloadDedups`: same uuid in two files with identical payload → inserted=1, ignored=1, divergences=0
- [x] 10.7 `testSameUuidDifferentPayloadCountsDivergenceAndFirstSeenWins`: same uuid in two files with different payload → inserted=1, ignored=1, divergences=1
- [x] 10.8 `testIterationsAreIgnoredOuterFieldsAuthoritative`: fixture with both outer usage and `iterations[]` mirror; verify only outer values land in `cc_message` (no double-count)
- [x] 10.9 `testMessageContentNotPersisted`: line carries a 2KB+ unique-marker `content`; after ingest, grep the sqlite file's bytes for the marker — must be absent. Locks in the privacy invariant by inspection of persisted state. Plus `testFileGrowsScenarioReadsOnlyNewBytes` and `testEmptyProjectsRoot` for spec coverage of file-grows scenario and empty-dir behaviour. 11 tests total, all pass; suite is now 83 tests

## 11. DashboardView → TabView refactor (replaces temporary tab from group 2)

- [x] 11.1 Replaced the dev-bundle-gated temporary tab with an unconditional `TabView`; both production and dev now show the two-tab layout. Local prototype enum `DashboardTabKey` removed in favour of `DashboardTab` from `AppSettings.swift` (group 7's enum)
- [x] 11.2 Range state was already on `DashboardView` (prototype-era); no change needed beyond verifying both tabs read from the same `@State private var range`
- [x] 11.3 `selectedTab` initialised from `AppSettings.lastDashboardTab` on view appear; `.onChange(of: selectedTab)` writes back. Restart restores the last-active tab
- [x] 11.4 New `earliestDataAcrossSources` computed property picks `min(oldestSubscriptionSample, oldestCCMessage)` (nil-safe). The range picker's `oldestSample:` parameter and `reload()`'s `range.resolved(...)` both use it
- [ ] 11.5 Smoke: requires owner verification in TokenTraceDev (build is up, PID-tagged); test plan: tabs render, range chip changes reflect on both tabs, switch tab preserves range, restart preserves selected tab

## 12. CCUsageView plumb-in (replace stubs from group 2)

- [x] 12.1 Stub `[CCProjectSeries]` from `CCUsagePreviewData` replaced by `ccStore.tokensByProject(from:to:bucket:)`. CCUsageView now takes `ccStore`, `ccIngester`, and `usageStore` injected via initializer (sourced from `usageManager`)
- [x] 12.2 `bucket` computed property: `rangeDays ≤ 1 → .hour`, `≤ 30 → .day`, otherwise `.week`
- [x] 12.3 Subscription samples now come from `usageStore.query(bucket: .fiveHour/.sevenDay, from:to:)`
- [x] 12.4 Refresh button calls `ccIngester.ingest()` on Task; bumps `refreshTick` afterwards to force SwiftUI to re-evaluate the computed query properties
- [ ] 12.5 Manage projects… still disabled (sheet built in group 14); button label + tooltip preserved
- [x] 12.6 `isIndexing` `@State` flag toggled around the ingest await; Refresh button swaps icon and label to "Indexing…" during the run and is disabled. The full per-spec `coldScanOccurred` plumbing (only show indicator on first-run-style scans) is in `IngestSummary` but not yet wired — current UX shows the indicator on every Refresh, which is acceptable for the prototype + first-run UX since most ingests are sub-second
- [x] 12.7 Tooltip rewritten to consume `CCUsageStore.ProjectSeries` / `ProjectBucket`. Per-project rows sorted desc by weighted, top-project's four components shown, 5h/7d util pulled from the real subscription series
- [x] 12.8 `MainWindow/CCUsagePreviewData.swift` deleted. Also added `CCUsageStore.modelBreakdown(forCwd:from:to:includeWorktrees:)` so the project totals card can show Opus/Sonnet split from real data (was previously hard-coded per project in the stub)

**Polish round after first-real-data review (not in original 12.x scope):**

- [x] 12.P1 **Top-N + "Other" grouping** — `displayedProjects` keeps the 8 highest-weighted projects individually and folds the rest into a single gray "Other (N)" synthesised series. Bounds chart marks, legend chips, tooltip rows, and totals-card rows alike. Picked 8 as the per-row palette length so colours don't repeat in the visible set.
- [x] 12.P2 **Query-result caching via `@State`** — `projectsAll`, `displayedProjects`, `aggregates`, `fiveHour`, `sevenDay` cached and refreshed only on appear / range change / post-ingest. Eliminates the N+1 modelBreakdown SQL storm that hit every body re-evaluation on a populated DB.
- [x] 12.P3 **Configurable display name depth** via `AppSettings.ccProjectNameDepth` (default 1). Default behaviour now drops "workspace/" prefix etc. Setting added to SettingsView's new "Claude Code" section.
- [x] 12.P4 **Worktree fold** via `AppSettings.ccMergeWorktrees` (default true). `tokensByProject` folds `.worktree(s)/...` cwds into the parent; representative cwd is the parent path. `modelBreakdown` gains an `includeWorktrees: Bool` param that LIKE-sweeps parent + descendants so the Opus/Sonnet split reflects all folded sources. Toggle added to SettingsView.
- [x] 12.P5 **Inline hover reveal** — row tooltip shows the full cwd as an in-flow line below the hovered row (pushes the next row down a few px). Replaces a failed `.help()` attempt and a broken overlay attempt; layout stays consistent.
- [x] 12.P6 5 new `CCUsageStoreTests` cases covering depth=1/2 synthesis, worktree fold default + disabled, and alias-inheritance through fold. Suite is 87 green.

## 13. Claude Code export (CCExportSheetView plumb-in + CCReportGenerator + cc-report template)

- [ ] 13.1 Add `Resources/cc-report.html.template` with sentinel tokens (`__TITLE__`, `__DATE_RANGE__`, `__DURATION_DAYS__`, `__CHART_JS__`, `__STATS_JSON__`, `__SERIES_JSON__`, `__PROJECT_TOTALS_JSON__`, `__INCLUDE_OVERLAY__`, `__INCLUDE_TOTALS__`, `__GENERATED_AT__`, `__DB_PATH__`)
- [ ] 13.2 Template layout: header → stats strip → stacked-area chart (with optional overlay) → project totals list (conditional) → footer, mirroring `CCUsageView`'s on-screen structure
- [ ] 13.3 Inline CSS: typography hierarchy consistent with `report.html.template`; calm neutral palette; colour-blind-safe project colours
- [ ] 13.4 Inline JS: parse `__SERIES_JSON__`, render Chart.js stacked area with project breakdown; if `__INCLUDE_OVERLAY__` is true, draw `five_hour` (solid) and `seven_day` (dashed) on a secondary 0–100% Y axis sharing the X axis
- [ ] 13.5 Add `Services/CCReportGenerator.swift`: `CCReportRequest` (title, format, range, includeOverlay, includeProjectTotals), `CCReportData` (stats strip values, per-project per-bucket series, project totals with mix + Opus/Sonnet split), `generateHTML(_ request:) -> String`, `generatePDF(html:) async throws -> Data` via existing `PDFRenderer`
- [ ] 13.6 Bucket aggregation by range size: hour ≤ 24h, day ≤ 30d, week otherwise (matches `CCUsageView`)
- [ ] 13.7 Replace `CCExportSheetView`'s stub Save with the real flow: `NSSavePanel` with default filename `claude-code-report-{from}_to_{to}.{ext}`, allowed content type tracks format; on confirm call `CCReportGenerator`; on cancel preserve selections
- [ ] 13.8 Disable Save in `CCExportSheetView` when `CCUsageStore.tokensByProject(...)` returns empty for the selected range; show inline "No Claude Code activity in the selected range"
- [ ] 13.9 Replace prototype's stub Projects list in `CCExportSheetView` with real `CCUsageStore.observedCwds()` for the selected range
- [ ] 13.10 Wire `DashboardView`'s toolbar Export button: read `selectedTab`; open `ExportSheetView` or `CCExportSheetView` accordingly; button label flips between "Export Report…" and "Export Claude Code…"
- [ ] 13.11 Wire File menu / ⌘E (`MainMenuBuilder.swift`): same tab-aware dispatch; menu item title flips with `selectedTab`
- [ ] 13.12 Unit tests `CCReportGeneratorTests`: fixture-driven HTML output passes sentinel substitution (all tokens replaced exactly once); JSON-encoded series round-trips; PDF render path returns non-empty data on a small fixture
- [ ] 13.13 Page-handling for PDF: add `@page` rules to `cc-report.html.template` (landscape A4 or portrait with chart scale-to-fit), and `page-break-inside: avoid` on stats strip + project totals rows. The existing usage-export PDF path is portrait A4 single-axis lines; the new dual-axis stacked area + project totals list is qualitatively wider, so verify with a 4+ project × 30-day fixture that nothing overflows horizontally. Decide page orientation before the manual smoke
- [ ] 13.14 Manual smoke: export from each tab, open exported HTML offline (network disconnected), confirm zero non-`file://` requests via browser Network panel; open PDF on a fresh machine without TokenTrace, confirm layout matches HTML twin and pages break sensibly

## 14. ProjectAliasSheet

- [ ] 14.1 Build `MainWindow/ProjectAliasSheet.swift`
- [ ] 14.2 Populate from `CCUsageStore.observedCwds()` + `aliases()`; show one row per observed `cwd`
- [ ] 14.3 Show cwd in monospaced muted text; alias in editable `TextField`; placeholder shows the synthesised fallback label
- [ ] 14.4 Swipe-to-delete (or context-menu "Clear alias") removes the alias and falls back to synthesised label
- [ ] 14.5 Two cwds with the same alias text are not warned — the docs/spec explicitly support sum-merge by alias
- [ ] 14.6 Done button closes the sheet; the chart re-queries on dismiss so changes are reflected immediately

## 15. Empty-data states (per spec)

- [ ] 15.1 Range has CC data but no subscription samples → chart shows stacked area alone; right axis still renders 0–100% scale without lines
- [ ] 15.2 Range has subscription samples but no CC data → chart shows subscription lines alone; legend area shows "No Claude Code activity in this range"
- [ ] 15.3 Range has neither → chart replaced with empty-state placeholder "No data in this range"
- [ ] 15.4 First-launch (no `cc_message` rows at all, `~/.claude/projects/` empty or absent) → CCUsageView shows a one-time onboarding card explaining where transcripts come from

## 16. Visual polish via frontend-design skill

This group's tasks depend on the gate decision in group 3:
- If 3.2 path (i) was chosen, only 16.3 remains.
- If 3.2 path (ii) was chosen, 16.1 and 16.2 have already happened during the gate; treat them as audit + finalise steps here.

- [ ] 16.1 Apply / verify `frontend-design` skill output on `CCUsageView` AND `cc-report.html.template`: production-grade dashboard tab + report, consistent with the existing Subscription tab and existing `report.html.template`, calm palette, colour-blind-safe project colours
- [ ] 16.2 Side-by-side review on light + dark mode against the pre-polish version (CCUsageView in-app + cc-report.html template in browser)
- [ ] 16.3 Resize-test the CCUsageView tab at narrow window widths; chart legend should wrap or scroll instead of overflowing

## 17. Verification — walk every spec scenario

`claude-code-usage` capability:
- [ ] 17.1 Cold ingest of a project with assistant lines produces exact expected row count
- [ ] 17.2 Subagent transcripts included (manual `sqlite3` query: `SELECT count(*) FROM cc_message WHERE is_sidechain = 1`)
- [ ] 17.3 Non-JSONL siblings (`.meta.json`) ignored
- [ ] 17.4 Hyphen-ambiguous directory: row `cwd` is the JSONL value, not a guess
- [ ] 17.5 Mixed cwds within one JSONL file produce two distinct project totals
- [ ] 17.6 Re-run is idempotent
- [ ] 17.7 Re-run after mid-file crash recovers all rows
- [ ] 17.8 File-grows scenario: append 50 lines, ingest reads only the new bytes
- [ ] 17.9 File-truncated scenario: shrink the file, ingest rescans from 0, deduplicated by uuid
- [ ] 17.10 Partial-trailing-line: file ends mid-line, offset stays at last `\n`
- [ ] 17.11 Privacy: instrument the parser in a debug build to confirm `message.content` is never accessed (assertion-on-touch)
- [ ] 17.12 Weighted volume table-driven scenarios produce expected values
- [ ] 17.13 Sidechain scenario: subagent line attributed to parent cwd; `is_sidechain = 1` row visible directly in DB
- [ ] 17.14 Project aggregation zero-fill: two projects with different active days produce equal-length series
- [ ] 17.15 Alias merge: two cwds with identical alias produce a single merged series with zero-fill applied to the merged result
- [ ] 17.16 Ingest does not block UI: open CCUsageView on first launch with the full 354 MB / 678-file dataset, switch back to Subscription tab during indexing, verify subscription chart remains interactive

`usage-dashboard` capability:
- [ ] 17.17 "90d" chip resolves to `now − 90·86400 ... now`
- [ ] 17.18 Edit From into Custom state deselects chips
- [ ] 17.19 From > To prevented interactively
- [ ] 17.20 "All" spans both stores — verify with a DB where CC predates samples and vice versa
- [ ] 17.21 Range persists across tab switches
- [ ] 17.22 Last-active tab persists across app restart (set CC, quit, relaunch)
- [ ] 17.23 Two-projects-with-data scenario: stacked area visible, four-component sub-stack visible per project, legend shows both
- [ ] 17.24 Subscription lines: 5h solid, 7d dashed, both 0–100%
- [ ] 17.25 X axis updates with range
- [ ] 17.26 Hover synchronisation: tooltip shows both data sources when both have values at the cursor X
- [ ] 17.27 Empty-data scenarios 15.1–15.3 all reach the documented states

`usage-export` capability (tab-aware extension):
- [ ] 17.28 Toolbar Export label flips with active tab ("Export Report…" / "Export Claude Code…")
- [ ] 17.29 Subscription tab — toolbar button opens existing `ExportSheetView` unchanged
- [ ] 17.30 Claude Code tab — toolbar button opens `CCExportSheetView`
- [ ] 17.31 File menu / ⌘E — dispatch matches active tab
- [ ] 17.32 CC export sheet defaults on every open (title, format PDF, range Last 7d, both Include toggles, All projects)
- [ ] 17.33 CC export Save disabled when range contains zero CC records; inline message shown
- [ ] 17.34 CC export default filename `claude-code-report-{from}_to_{to}.{ext}`
- [ ] 17.35 CC HTML opens offline; browser Network panel reports zero non-`file://` requests
- [ ] 17.36 CC PDF opens on a fresh machine without TokenTrace; layout matches the HTML twin
- [ ] 17.37 Subscription overlay toggle off → exported chart contains no subscription lines and no secondary Y axis
- [ ] 17.38 Project totals toggle off → exported report omits the project totals list section

## 18. Documentation

- [ ] 18.1 Add a brief CC-tab note to `CLAUDE.md` (where `~/.claude/projects/` lives, the privacy guarantee, the "weighted token volume" naming, the tab-aware Export behaviour)
- [ ] 18.2 Update the "Min macOS" line in `CLAUDE.md` to 14.0
- [ ] 18.3 If README mentions features, add the Claude Code tab + tab-aware Export to the list

## 19. Pre-PR review

- [ ] 19.1 Run the `simplify` skill against the new files in `Persistence/`, `Services/`, `Models/`, `MainWindow/`, `Resources/`
- [ ] 19.2 `openspec validate claude-code-usage` clean
- [ ] 19.3 Self-review: confirm none of the new code reads `message.content` and the divergence counter is wired
- [ ] 19.4 Manual smoke against a fresh DB (delete `usage.sqlite`, relaunch, open CCUsageView) and confirm onboarding + first ingest path
