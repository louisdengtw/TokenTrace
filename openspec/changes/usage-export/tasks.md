## 1. Shared range model and widget

- [x] 1.1 Add `RangePreset` enum (`last24h`, `last7d`, `last30d`, `all`) with `Codable` conformance
- [x] 1.2 Add `RangeSelection` enum (`.preset(RangePreset)`, `.custom(from: Date, to: Date)`) with `Codable + Equatable` and a `resolved(now:oldestSample:)` method returning `(start: Date, end: Date)`
- [x] 1.3 Implement `RangePickerView` SwiftUI component: chip row (24h/7d/30d/All) + From/To `DatePicker` pair, with chip → custom auto-conversion on date edit
- [x] 1.4 Enforce non-inverted state in `RangePickerView` (if user sets From > To, adjust the non-edited side)
- [ ] 1.5 Snapshot the existing Dashboard look-and-feel; sanity check the new picker fits the same toolbar real estate

## 2. AppSettings persistence for Dashboard range

- [x] 2.1 Add `dashboardRangeSelection` key in `AppSettings.swift` storing JSON-encoded `RangeSelection`
- [x] 2.2 Decode on read; fall back to `.preset(.last7d)` on missing or corrupted value (per spec scenario)
- [x] 2.3 Encode + write on every user-initiated range change

## 3. Dashboard refactor (separate commit, must remain testable)

- [x] 3.1 Delete `DashboardRange` enum and the old segmented `RangePicker` from `DashboardView.swift`
- [x] 3.2 Replace `@State private var range: DashboardRange = .last7d` with state bound to `AppSettings.dashboardRangeSelection`
- [x] 3.3 Compute `[start, end]` via `RangeSelection.resolved(now:oldestSample:)` and feed both charts
- [ ] 3.4 Manual smoke: app launches, range chip click reflects in both charts, From/To edit enters Custom, restart preserves selection
- [ ] 3.5 Verify reactive update on new poll still works (range + selection state preserved)

## 4. Chart.js asset bundled in Resources

- [x] 4.1 Drop `chart.umd.min.js` (pinned version) into the app's Resources directory; record version + source URL in a header comment of the loader
- [x] 4.2 Wire the asset into the Xcode build (target membership) so it ships inside the .app
- [x] 4.3 Add a Swift helper `ChartJSAsset.bundledContents() -> String` that reads it at runtime

## 5. HTML report template

- [x] 5.1 Create `report.html.template` in Resources with sentinel tokens: `__TITLE__`, `__DATE_RANGE__`, `__DURATION_DAYS__`, `__CHART_JS__`, `__REPORT_JSON__`, `__GENERATED_AT__`, `__DB_PATH__`
- [x] 5.2 Template lays out: header (title + date range + duration) → summary card row → one `<section>` per bucket containing a summary card + canvas → footer
- [x] 5.3 Inline CSS: typography hierarchy, neutral palette, card grouping, chart container spacing — first pass good enough to read as a report, not styled to perfection yet
- [x] 5.4 Inline JS: parse `__REPORT_JSON__`, render one Chart.js line chart per bucket with reset markers as vertical annotations and color-blind-safe line colors
- [ ] 5.5 Hand-fill placeholders once and open the template in Safari + Chrome to verify it renders without network

## 6. Report generator (Swift side)

- [x] 6.1 Define `ReportRequest` (title, range, buckets) and `ReportData` (per-bucket samples + reset events + summary stats) value types
- [x] 6.2 Query each requested bucket via `UsageStore.query(bucket:from:to:)`
- [x] 6.3 Compute peak / average / sample count per bucket; treat empty buckets as "no data"
- [x] 6.4 Detect reset events per bucket via `ResetDetection.detect(_:)`
- [x] 6.5 Encode `ReportData` to JSON (timestamps as epoch millis, utils as Double)
- [x] 6.6 Load template, perform sentinel substitution (all tokens replaced exactly once), return final HTML string
- [x] 6.7 Bucket order in output follows canonical sequence: `five_hour`, `seven_day`, `seven_day_sonnet`

## 7. Export sheet UI

- [x] 7.1 Build `ExportSheetView` SwiftUI sheet with: Title `TextField`, embedded `RangePickerView`, three bucket `Toggle`s, Save/Cancel buttons
- [x] 7.2 Local `@State` only — do NOT read from or write to `AppSettings`; always init to defaults (title "TokenTrace Usage Report", range `.preset(.last7d)`, buckets `[five_hour, seven_day]`)
- [x] 7.3 Disable Save when zero buckets selected; show inline hint
- [x] 7.4 Disable Save when range resolves to zero samples across all selected buckets; show "No samples in the selected range"
- [x] 7.5 On Save, present `NSSavePanel` with default filename `claude-usage-report-{from}_to_{to}.html`
- [x] 7.6 On save panel confirm: generate HTML via the report generator and write to the chosen URL; surface write errors via an alert
- [x] 7.7 On save panel cancel: leave the sheet open with the user's selections preserved
- [x] 7.8 Per-bucket empty handling: if a bucket selected by the user has zero samples in range, the report shows "No data" stats and an empty-state chart placeholder for it (data layer responsibility — confirm UI surfaces it)

## 8. Entry points

- [x] 8.1 Add "Export Report…" button to the Dashboard toolbar (top-right) that opens the export sheet
- [x] 8.2 Add a `CommandGroup` for a File → Export Report… menu item with the keyboard shortcut ⌘E that opens the same sheet
- [ ] 8.3 Verify the File-menu / ⌘E path works regardless of which main-window tab is currently active

## 9. Visual polish pass using frontend-design skill

- [ ] 9.1 Run the `frontend-design` skill against `report.html.template` with the brief: production-quality TokenTrace usage report, calm neutral palette, typographic hierarchy, color-blind-safe line colors
- [ ] 9.2 Apply the skill's output to the template; manually review side-by-side against the pre-polish version
- [ ] 9.3 Cross-browser check: Safari + Chrome at default zoom on a typical macOS resolution

## 10. Verification

- [ ] 10.1 Spec scenario: Dashboard remembers last preset after relaunch
- [ ] 10.2 Spec scenario: Dashboard remembers last Custom range after relaunch
- [ ] 10.3 Spec scenario: Corrupted UserDefaults value falls back to last7d
- [ ] 10.4 Spec scenario: Export sheet defaults on every open (after a prior export with non-default values)
- [ ] 10.5 Spec scenario: All chip in export resolves to oldest sample
- [ ] 10.6 Spec scenario: Save disabled when no buckets selected
- [ ] 10.7 Spec scenario: Save disabled when range contains zero samples
- [ ] 10.8 Spec scenario: Default filename follows `claude-usage-report-{from}_to_{to}.html`
- [ ] 10.9 Spec scenario: Exported HTML opens offline (disconnect network, double-click file)
- [ ] 10.10 Spec scenario: Exported HTML makes zero non-`file://` requests (verify via browser Network panel)
- [ ] 10.11 Spec scenario: Reset markers render on the appropriate per-bucket charts
- [ ] 10.12 Spec scenario: Default selection produces exactly two summary cards + two charts (no Sonnet)
- [ ] 10.13 Spec scenario: All-three selection produces three sections in canonical bucket order
- [ ] 10.14 Confirm ⌘E does not conflict with any other binding in this app (no text-input contexts using "Use Selection for Find")
- [ ] 10.15 Open generated report on a fresh machine / VM without TokenTrace installed to validate portability

## 11. Update top-level docs

- [x] 11.1 Update `CLAUDE.md` with a brief note about the export feature and where the HTML template lives
- [x] 11.2 Add a one-liner in the README (if present) about exporting reports

## 12. PDF output via WKWebView

- [x] 12.1 Add `ReportFormat` enum (`html`, `pdf`) with `utType` + `fileExtension`
- [x] 12.2 Add `PDFRenderer.renderHTMLToPDF(html:)` — off-screen `WKWebView` + `createPDF`, with `loadFailed` / `renderFailed` error cases
- [x] 12.3 Add Format segmented picker to `ExportSheetView` (default `PDF`)
- [x] 12.4 Switch save panel allowed content type + default filename extension based on format
- [x] 12.5 Move save flow into a `Task` so PDF rendering can `await` without blocking the UI; show a small "Rendering…" indicator while in-flight
- [x] 12.6 Disable Cancel + Save while rendering to avoid double-tap / partial-write
- [ ] 12.7 Spec scenario: defaults — sheet opens with format = PDF
- [ ] 12.8 Spec scenario: save panel allowed type / default filename track the format
- [ ] 12.9 Spec scenario: PDF opens offline on a fresh machine (no TokenTrace, no network) and looks identical to its HTML twin
- [ ] 12.10 Spec scenario: page breaks — render a 30-day range and confirm trend sections do not split mid-chart
- [ ] 12.11 Spec scenario: PDF render failure surfaces an inline error and leaves sheet open
