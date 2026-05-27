## 1. Platform and build infrastructure

- [x] 1.1 Update `Package.swift` `platforms` from `.macOS(.v13)` to `.macOS(.v14)`
- [x] 1.2 Update `CLAUDE.md`'s "Min macOS" line and the SwiftUI Charts note (and `Resources/Info.plist` `LSMinimumSystemVersion`)
- [x] 1.3 Build clean to confirm nothing else referenced 13-only fallback semantics; do NOT remove the existing `chartXSelectionIfAvailable` shim (out of scope for this change). Note: surfaces 2 `onChange(of:perform:)` deprecation warnings in `SettingsView.swift`, harmless, leave as follow-up
- [x] 1.4 In `tools/build-app.sh`, make `APP_NAME` and `BUNDLE_ID` env-overridable (default `TokenTrace` / `dev.louisdeng.tokentrace`); `plutil -replace` the identity keys (CFBundleIdentifier, CFBundleName, CFBundleDisplayName, CFBundleExecutable, CFBundleIconFile) so non-default values produce a separately-installable .app
- [x] 1.5 In `Makefile`, add `dev` / `dev-install` / `dev-run` targets exporting `APP_NAME=TokenTraceDev BUNDLE_ID=dev.louisdeng.tokentrace.dev` and acting on `build/TokenTraceDev.app` / `/Applications/TokenTraceDev.app`; `dev-run` `pkill` targets `TokenTraceDev` only, not `TokenTrace`
- [ ] 1.6 Smoke: `make build` produces `TokenTrace.app` unchanged; `make dev-run` produces and launches `TokenTraceDev.app` alongside production

## 2. UI prototype with stub data

The chart is the highest-risk visual element in this change. Build it first with hardcoded data so the dual-axis Swift Charts layout, the four-component sub-stack per project, and hover synchronisation can be evaluated before committing to the data layer.

- [ ] 2.1 Create `MainWindow/CCUsageView.swift` with the chart structure: single `Chart` with dual Y axis (`AxisMarks(position: .leading)` for weighted volume, `.trailing` for utilisation), stacked `AreaMark` on left axis with four sub-bands per project, `LineMark` on right axis for `five_hour` (solid) + `seven_day` (dashed)
- [ ] 2.2 Add `MainWindow/CCUsagePreviewData.swift` with hardcoded fixtures: 3–4 fake projects with realistic 7-day distributions; fake subscription samples for 5h/7d that visibly correlate with one of the projects' activity peaks (so hover utility is demonstrable on the prototype)
- [ ] 2.3 Add a TEMPORARY "Claude Code" tab to `DashboardView.swift` pointing at `CCUsageView` (the proper `TabView` refactor in group 11 will subsume this — keep this hack minimal so it's easy to replace later)
- [ ] 2.4 Header row: Refresh + Manage projects… + info-caveat affordances rendered as static placeholders (buttons visible, do nothing yet)
- [ ] 2.5 `chartXSelection(value: $selectedDate)` + `chartOverlay` for hover guideline + unified tooltip, driven by the stub data; tooltip shows per-project weighted volume + 5h/7d utilisation at the cursor
- [ ] 2.6 Legend below the chart, mapping project → colour (colour-blind-safe palette as first cut)
- [ ] 2.7 Run the app; capture screenshots in both light and dark mode

## 3. Prototype gate (owner review)

- [ ] 3.1 Owner reviews the running prototype + screenshots
- [ ] 3.2 Decide path:
    - **(i)** Visual is acceptable → continue to group 4; prototype view code is retained, group 12 just swaps stubs for real queries. Skip group 15 except 15.3 (resize test still applies).
    - **(ii)** Visual needs polish → invoke `frontend-design` skill now (effectively moving group 15 here); iterate until acceptable; then continue to group 4.
    - **(iii)** Layout is fundamentally wrong → return to `design.md` Decision 5, revise, redo group 2.

## 4. Schema additions

- [ ] 4.1 Append `createCCMessageTable` DDL to `Persistence/Schema.swift` (`uuid` PK, four token columns, `ts`, `cwd`, `model`, `session_id`, `request_id`, `is_sidechain`, `file_path`)
- [ ] 4.2 Append `createCCMessageTsIndex` and `createCCMessageCwdTsIndex` to `Schema.swift`
- [ ] 4.3 Append `createCCIngestCheckpointTable` (`file_path` PK, `byte_offset`, `file_size`, `mtime`)
- [ ] 4.4 Append `createProjectAliasTable` (`cwd` PK, `display_name`)
- [ ] 4.5 Confirm `UsageStore.init` iterates the extended `allDDL`; manually verify the new tables on a fresh DB file

## 5. Weighted token volume model

- [ ] 5.1 Add `Models/CCWeightedVolume.swift` with weight constants (1.0 / 5.0 / 1.25 / 0.1) and inline comment citing the Anthropic API pricing source (date the citation)
- [ ] 5.2 Add `func weightedTotal(input: Int, output: Int, cacheCreation: Int, cacheRead: Int) -> Double` helper
- [ ] 5.3 Unit tests `CCWeightedVolumeTests`: representative record (700.0), cache-heavy edge (10000.0), zero record (0.0), Int overflow guard

## 6. Range chip — add 90d

- [ ] 6.1 Add `case last90d` to `RangePreset` in `Models/RangeSelection.swift`, between `last30d` and `all`
- [ ] 6.2 Extend `label` to return `"90d"`
- [ ] 6.3 Extend `resolved(now:oldestSample:)` to return `now − 90·86400 ... now`
- [ ] 6.4 Unit test `RangeSelectionTests`: `last90d` round-trips through `Codable`, resolves correctly, and decodes unchanged from a JSON value that omits it (older AppSettings payload)

## 7. AppSettings — last-active tab persistence

- [ ] 7.1 Add `lastDashboardTab: DashboardTab` to `AppSettings.swift` (new `enum DashboardTab: String { case subscription, claudeCode }`)
- [ ] 7.2 Default to `.subscription` when no prior value is stored
- [ ] 7.3 Encode-on-write, decode-on-read with `subscription` fallback for unknown/corrupt values

## 8. CCUsageStore (data layer)

- [ ] 8.1 Add `Persistence/CCUsageStore.swift`
- [ ] 8.2 `insertMessages(_ rows: [CCMessage])` — batched `INSERT OR IGNORE` in a single transaction; return `(inserted: Int, ignored: Int)` so the divergence counter (task 9.9) can attribute correctly
- [ ] 8.3 `tokensByProject(from:to:bucket:) -> [ProjectSeries]` — group by `(cwd, bucket_floor(ts))`, sum the four token components, compute weighted total per bucket
- [ ] 8.4 Apply alias lookup at query time: join `project_alias` ON `cwd`, fall back to synthesised label (last two path components, or full cwd if fewer)
- [ ] 8.5 Implement zero-fill per spec: for every project that has any row in `[from, to]`, the returned series MUST include every bucket boundary in `[from, to]` (zero rows where no data)
- [ ] 8.6 Omit projects with zero activity across the entire range (do not return empty series)
- [ ] 8.7 `oldestCCMessageTimestamp() -> Date?` — for the "All" preset cross-source resolution
- [ ] 8.8 `aliases() -> [String: String]` and `setAlias(cwd:displayName:)` / `removeAlias(cwd:)`
- [ ] 8.9 `observedCwds() -> [String]` — returns all distinct cwds in `cc_message`, for the alias sheet UI
- [ ] 8.10 Unit tests against a fixture DB: two-project zero-fill (5-day range, project A on days 1–3, project B on days 2–4, expect 5 buckets each), alias merge (two cwds same alias sum together with zero-fill applied to the merged series), absent project omitted, empty range returns `[]`

## 9. CCUsageIngester (file walking + parsing + checkpoints)

- [ ] 9.1 Add `Services/CCUsageIngester.swift`
- [ ] 9.2 Recursive directory walk of `~/.claude/projects/`, returning every `*.jsonl` file path; verify subagent files at `<project>/<sid>/subagents/agent-*.jsonl` are reached
- [ ] 9.3 Checkpoint lookup: read `(file_path, byte_offset, file_size, mtime)` from `cc_ingest_checkpoint`; if `current_size >= byte_offset` and `current_mtime >= stored_mtime`, resume from `byte_offset`, else rescan from 0
- [ ] 9.4 Line-buffered parse from offset: consume ONLY past a confirmed `\n`. If the file trails off mid-line, do not consume those bytes; persisted offset stays at the last newline
- [ ] 9.5 Per-line filter: keep only `type == "assistant"` AND `message.model != "<synthetic>"` AND `message.usage` is non-null
- [ ] 9.6 Privacy invariant: parse only the projection `{type, uuid, timestamp, cwd, isSidechain, sessionId, requestId, message.{model, usage}}`. Do NOT decode `message.content` into a Swift value. Use a streaming/lenient decoder or hand-rolled selective key extraction
- [ ] 9.7 Use outer `usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}` — ignore `iterations`
- [ ] 9.8 Build batched `CCMessage` rows; flush every N rows (start with N=1000) to `CCUsageStore.insertMessages`
- [ ] 9.9 Implement `uuidPayloadDivergence` counter: track the gap between `(seen lines, inserted+ignored-same-payload)` to surface when same-uuid-different-payload events occur. Log at `info` level on increment; expose as a debug-menu readout (not user-visible UI)
- [ ] 9.10 On EOF, persist `(file_path, byte_offset=size_at_last_newline, file_size, mtime)` to `cc_ingest_checkpoint`
- [ ] 9.11 Run all of the above on a background `DispatchQueue`; expose `ingest() async -> IngestSummary` with `(filesScanned, rowsInserted, rowsIgnored, divergences, elapsed)`
- [ ] 9.12 First-run vs subsequent-run signal: ingester reports whether any file required offset-zero scan, so the CCUsageView can decide whether to show the "Indexing…" indicator

## 10. CCUsageIngester tests (with fixtures)

- [ ] 10.1 Build `Tests/Fixtures/cc-projects/` with at least: one normal project dir with two sessions, one with a `subagents/` subdir, one fixture file ending mid-line (no trailing newline), one fixture with `<synthetic>` and one with missing `usage`, one fixture with a uuid that collides cross-file with same payload, one fixture with uuid collision and DIFFERENT payload (the 0.1% case)
- [ ] 10.2 Test: cold ingest of normal project produces N rows for N qualifying assistant lines; sidechain rows from `subagents/` attributed to parent project's cwd (verify directly on `cc_message`)
- [ ] 10.3 Test: re-ingest is idempotent (run twice, row count unchanged)
- [ ] 10.4 Test: synthetic + missing-usage lines produce zero rows; offset still advances past them
- [ ] 10.5 Test: partial-trailing-line file's offset is the last `\n` position; appending the rest of the line + a newline + new lines causes the next ingest to read them correctly
- [ ] 10.6 Test: same-uuid same-payload duplicates dedup to one row
- [ ] 10.7 Test: same-uuid different-payload increments `uuidPayloadDivergence` by exactly the divergent count; first-seen wins (assert by inspecting which payload survives, ordered by walk order)
- [ ] 10.8 Test: `iterations` regression — fixture with multi-iteration usage; assert that `iterations` is ignored and outer fields are stored (cheap insurance against format drift; the design's empirical claim is that iterations always agrees with outer)
- [ ] 10.9 Test: a fixture line containing a multi-kilobyte `message.content` does NOT result in any memory residue (assert via not reading the field at all in test introspection of the parser projection)

## 11. DashboardView → TabView refactor (replaces temporary tab from group 2)

- [ ] 11.1 Replace the temporary "Claude Code" tab hack from group 2 with a proper `TabView`. Wrap the existing subscription chart contents in a `Tab("Subscription")` and `CCUsageView` in a `Tab("Claude Code")`
- [ ] 11.2 Hoist the existing range state so both tabs share it
- [ ] 11.3 Wire `AppSettings.lastDashboardTab` ↔ `TabView` selection
- [ ] 11.4 Update "All" preset resolution in `DashboardView` to call both `UsageStore.oldestSampleTimestamp()` and `CCUsageStore.oldestCCMessageTimestamp()` and pick the earlier; fall back to `now − 86400` when neither has data
- [ ] 11.5 Smoke: tabs render, range chip click reflects in whichever tab is active, switching tabs preserves range, restart preserves selected tab

## 12. CCUsageView plumb-in (replace stubs from group 2)

- [ ] 12.1 Replace stub `[ProjectSeries]` source with `CCUsageStore.tokensByProject(from:to:bucket:)` driven by the active range
- [ ] 12.2 Choose `bucket` automatically by range size: hour ≤ 24h, day ≤ 30d, week otherwise
- [ ] 12.3 Replace stub subscription samples with real `UsageStore.query(bucket:from:to:)` for `five_hour` + `seven_day`
- [ ] 12.4 Wire Refresh button to `CCUsageIngester.ingest()` + re-query on completion
- [ ] 12.5 Wire Manage projects… button to present `ProjectAliasSheet`
- [ ] 12.6 Wire "Indexing…" indicator visibility to the ingester's first-run-vs-subsequent signal
- [ ] 12.7 Update tooltip content to use real per-bucket data including the top project's four token components
- [ ] 12.8 Delete `MainWindow/CCUsagePreviewData.swift`

## 13. ProjectAliasSheet

- [ ] 13.1 Build `MainWindow/ProjectAliasSheet.swift`
- [ ] 13.2 Populate from `CCUsageStore.observedCwds()` + `aliases()`; show one row per observed `cwd`
- [ ] 13.3 Show cwd in monospaced muted text; alias in editable `TextField`; placeholder shows the synthesised fallback label
- [ ] 13.4 Swipe-to-delete (or context-menu "Clear alias") removes the alias and falls back to synthesised label
- [ ] 13.5 Two cwds with the same alias text are not warned — the docs/spec explicitly support sum-merge by alias
- [ ] 13.6 Done button closes the sheet; the chart re-queries on dismiss so changes are reflected immediately

## 14. Empty-data states (per spec)

- [ ] 14.1 Range has CC data but no subscription samples → chart shows stacked area alone; right axis still renders 0–100% scale without lines
- [ ] 14.2 Range has subscription samples but no CC data → chart shows subscription lines alone; legend area shows "No Claude Code activity in this range"
- [ ] 14.3 Range has neither → chart replaced with empty-state placeholder "No data in this range"
- [ ] 14.4 First-launch (no `cc_message` rows at all, `~/.claude/projects/` empty or absent) → CCUsageView shows a one-time onboarding card explaining where transcripts come from

## 15. Visual polish via frontend-design skill

This group's tasks depend on the gate decision in group 3:
- If 3.2 path (i) was chosen, only 15.3 remains.
- If 3.2 path (ii) was chosen, 15.1 and 15.2 have already happened during the gate; treat them as audit + finalise steps here.

- [ ] 15.1 Apply / verify `frontend-design` skill output on `CCUsageView`: production-grade dashboard tab consistent with the existing Subscription tab, calm palette, colour-blind-safe project colours
- [ ] 15.2 Side-by-side review on light + dark mode against the pre-polish version
- [ ] 15.3 Resize-test the tab at narrow window widths; chart legend should wrap or scroll instead of overflowing

## 16. Verification — walk every spec scenario

`claude-code-usage` capability:
- [ ] 16.1 Cold ingest of a project with assistant lines produces exact expected row count
- [ ] 16.2 Subagent transcripts included (manual `sqlite3` query: `SELECT count(*) FROM cc_message WHERE is_sidechain = 1`)
- [ ] 16.3 Non-JSONL siblings (`.meta.json`) ignored
- [ ] 16.4 Hyphen-ambiguous directory: row `cwd` is the JSONL value, not a guess
- [ ] 16.5 Mixed cwds within one JSONL file produce two distinct project totals
- [ ] 16.6 Re-run is idempotent
- [ ] 16.7 Re-run after mid-file crash recovers all rows
- [ ] 16.8 File-grows scenario: append 50 lines, ingest reads only the new bytes
- [ ] 16.9 File-truncated scenario: shrink the file, ingest rescans from 0, deduplicated by uuid
- [ ] 16.10 Partial-trailing-line: file ends mid-line, offset stays at last `\n`
- [ ] 16.11 Privacy: instrument the parser in a debug build to confirm `message.content` is never accessed (assertion-on-touch)
- [ ] 16.12 Weighted volume table-driven scenarios produce expected values
- [ ] 16.13 Sidechain scenario: subagent line attributed to parent cwd; `is_sidechain = 1` row visible directly in DB
- [ ] 16.14 Project aggregation zero-fill: two projects with different active days produce equal-length series
- [ ] 16.15 Alias merge: two cwds with identical alias produce a single merged series with zero-fill applied to the merged result
- [ ] 16.16 Ingest does not block UI: open CCUsageView on first launch with the full 354 MB / 678-file dataset, switch back to Subscription tab during indexing, verify subscription chart remains interactive

`usage-dashboard` capability:
- [ ] 16.17 "90d" chip resolves to `now − 90·86400 ... now`
- [ ] 16.18 Edit From into Custom state deselects chips
- [ ] 16.19 From > To prevented interactively
- [ ] 16.20 "All" spans both stores — verify with a DB where CC predates samples and vice versa
- [ ] 16.21 Range persists across tab switches
- [ ] 16.22 Last-active tab persists across app restart (set CC, quit, relaunch)
- [ ] 16.23 Two-projects-with-data scenario: stacked area visible, four-component sub-stack visible per project, legend shows both
- [ ] 16.24 Subscription lines: 5h solid, 7d dashed, both 0–100%
- [ ] 16.25 X axis updates with range
- [ ] 16.26 Hover synchronisation: tooltip shows both data sources when both have values at the cursor X
- [ ] 16.27 Empty-data scenarios 14.1–14.3 all reach the documented states

## 17. Documentation

- [ ] 17.1 Add a brief CC-tab note to `CLAUDE.md` (where `~/.claude/projects/` lives, the privacy guarantee, the "weighted token volume" naming)
- [ ] 17.2 Update the "Min macOS" line in `CLAUDE.md` to 14.0
- [ ] 17.3 If README mentions features, add the Claude Code tab to the list

## 18. Pre-PR review

- [ ] 18.1 Run the `simplify` skill against the new files in `Persistence/`, `Services/`, `Models/`, `MainWindow/`
- [ ] 18.2 `openspec validate claude-code-usage` clean
- [ ] 18.3 Self-review: confirm none of the new code reads `message.content` and the divergence counter is wired
- [ ] 18.4 Manual smoke against a fresh DB (delete `usage.sqlite`, relaunch, open CCUsageView) and confirm onboarding + first ingest path
