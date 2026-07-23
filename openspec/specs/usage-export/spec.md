# usage-export Specification

## Purpose

Export TokenTrace usage data over a user-chosen time range as a single self-contained report file (PDF or HTML), suitable for offline viewing and sharing. The report includes per-bucket summary stats, trend charts with reset markers, and source metadata, rendered consistently across both formats via a shared HTML template.
## Requirements
### Requirement: Export entry points

TokenTrace SHALL expose the export feature via a primary entry point — an "Export Report…" button in the Dashboard toolbar — and at least one secondary entry point — a File menu command bound to the keyboard shortcut ⌘E. Both entry points SHALL invoke a tab-aware dispatch: when the Dashboard's active tab is **Subscription** they open the existing subscription export sheet (`ExportSheetView`); when the active tab is **Claude Code** they open the Claude Code export sheet (`CCExportSheetView`). The toolbar button's label SHALL reflect the destination: `"Export Report…"` for Subscription, `"Export Claude Code…"` for Claude Code.

#### Scenario: Subscription tab — toolbar button

- **GIVEN** the Dashboard's active tab is Subscription
- **WHEN** the user clicks the toolbar button (labelled "Export Report…")
- **THEN** `ExportSheetView` opens modally over the main window
- **AND** the sheet's content is unchanged from prior behaviour

#### Scenario: Claude Code tab — toolbar button

- **GIVEN** the Dashboard's active tab is Claude Code
- **WHEN** the user clicks the toolbar button (now labelled "Export Claude Code…")
- **THEN** `CCExportSheetView` opens modally over the main window

#### Scenario: File menu / ⌘E on Subscription tab

- **GIVEN** the Dashboard's active tab is Subscription
- **WHEN** the user invokes File → Export Report… or presses ⌘E
- **THEN** `ExportSheetView` opens

#### Scenario: File menu / ⌘E on Claude Code tab

- **GIVEN** the Dashboard's active tab is Claude Code
- **WHEN** the user invokes File → Export Report… or presses ⌘E
- **THEN** `CCExportSheetView` opens
- **AND** the File menu item's title reflects the destination ("Export Claude Code…")

### Requirement: Export sheet default state

Every time the export sheet opens, it SHALL initialise its fields to a fixed default state, independent of any prior export session or the Dashboard's current state.

The defaults are:
- Title: `"Claude Usage Report"`
- Format: `PDF`
- Range selection: preset `"Last 7d"` (preset of `last7d` from the shared range widget)
- Buckets: `five_hour` checked, `seven_day` checked, every model-scoped weekly bucket unchecked

#### Scenario: First open in a session

- **WHEN** the user opens the export sheet for the first time after launching the app
- **THEN** the title field shows "Claude Usage Report"
- **AND** the format toggle shows "PDF" selected
- **AND** the range widget shows "Last 7d" with the "7d" chip selected
- **AND** the bucket checkboxes show: `five_hour` ✓, `seven_day` ✓, and each scoped model row ✗

#### Scenario: Reopen after a prior export

- **WHEN** the user successfully exports a report with title "Q1 Recap", format HTML, range Custom 2026-01-01..2026-03-31, and only `seven_day` selected, then later reopens the export sheet
- **THEN** the sheet is restored to defaults: title "Claude Usage Report", format PDF, range "Last 7d", buckets `five_hour` ✓ + `seven_day` ✓ + scoped rows ✗

### Requirement: Range selection uses the shared range widget

The export sheet SHALL use the same `RangePickerView` widget that the Dashboard uses (chip presets `24h / 7d / 30d / All` plus custom From/To). When the user picks the "All" preset, the range SHALL resolve to start = the oldest sample's timestamp in the store and end = now.

#### Scenario: User picks a preset

- **WHEN** the user clicks the "30d" chip in the export sheet
- **THEN** the range resolves to start = now − 30 × 86400, end = now

#### Scenario: User edits From or To

- **WHEN** the user changes the From date picker to a value different from the currently-selected preset's start
- **THEN** the chips become deselected and the widget enters Custom state with the user's From/To values

#### Scenario: User picks "All" on a database with samples since 2026-04-15

- **WHEN** the user clicks the "All" chip
- **THEN** the resolved range is start = 2026-04-15 (the oldest sample's timestamp), end = now

### Requirement: Bucket selection

The export sheet SHALL provide one checkbox per usage bucket: `five_hour`, `seven_day`, plus one per model-scoped weekly series present in the store's data, labelled `7-day Window — <Model>` in the same style as the Dashboard. At least one bucket MUST be selected to enable the Save action.

#### Scenario: User unchecks every bucket

- **WHEN** the user unchecks all bucket checkboxes
- **THEN** the Save button is disabled
- **AND** a brief inline hint indicates "Select at least one bucket"

#### Scenario: User keeps the default selection

- **WHEN** the user opens the sheet and clicks Save without changing buckets
- **THEN** the report includes the `five_hour` and `seven_day` buckets only

#### Scenario: Scoped model rows reflect stored data

- **WHEN** the store contains scoped samples for "Sonnet" (historical) and "Fable" (current)
- **THEN** the sheet shows two scoped checkboxes: "7-day Window — Sonnet" and "7-day Window — Fable"

### Requirement: Save flow uses NSSavePanel with a format-derived default filename

When the user clicks Save, the app SHALL present a standard macOS save panel with a default filename derived from the selected range and format, in the form `claude-usage-report-{from}_to_{to}.{ext}` where `{ext}` is `pdf` or `html` according to the chosen format, using `yyyy-MM-dd` for both dates. The save panel's allowed content type SHALL match the chosen format (`.pdf` or `.html`).

#### Scenario: User accepts the default filename for PDF

- **WHEN** the user clicks Save with format PDF and range Custom 2026-05-07..2026-05-14 and accepts the default
- **THEN** the file is written as `claude-usage-report-2026-05-07_to_2026-05-14.pdf` at the user's chosen location

#### Scenario: User accepts the default filename for HTML

- **WHEN** the user clicks Save with format HTML and range Custom 2026-05-07..2026-05-14 and accepts the default
- **THEN** the file is written as `claude-usage-report-2026-05-07_to_2026-05-14.html` at the user's chosen location

#### Scenario: User edits the filename

- **WHEN** the user edits the filename in the save panel to "Q2-usage.pdf"
- **THEN** the file is written under that name

#### Scenario: User cancels the save panel

- **WHEN** the user dismisses the save panel without saving
- **THEN** no file is written and the export sheet remains open with the user's selections preserved (including format)

### Requirement: Output is a single self-contained file

The exported file SHALL be a single file that opens fully without any network access, in one of two formats selectable by the user:

- **HTML**: a single `.html` file with Chart.js bundled inline. The report data (per-sample timestamps and utilizations, reset events) SHALL be embedded as JSON literals within the HTML.
- **PDF**: a single `.pdf` file rendered from the same HTML via system WebKit (`WKWebView.createPDF`), with system fonts embedded by the renderer.

#### Scenario: Open the HTML report offline

- **WHEN** the recipient opens the exported HTML on a machine with no internet connection
- **THEN** the report renders all charts, summary, and headers identically to viewing it online

#### Scenario: Open the PDF report offline

- **WHEN** the recipient opens the exported PDF on a machine with no internet connection (and no TokenTrace installed)
- **THEN** the report renders all charts, summary, and headers identically to its on-screen original

#### Scenario: No external resource requests (HTML)

- **WHEN** the exported HTML is opened in a browser with the Network panel observed
- **THEN** zero outbound requests to non-`file://` origins are made

### Requirement: Export sheet exposes a format selector

The export sheet SHALL provide a format selector with two options — `PDF` and `HTML` — visually equivalent to a segmented control. The default selection is `PDF` per the Default state requirement. Changing the format SHALL update the save panel's default filename extension and allowed content type on the next Save.

#### Scenario: User picks HTML

- **WHEN** the user opens the export sheet, switches the format from PDF to HTML, and clicks Save with default range
- **THEN** the save panel offers `claude-usage-report-{from}_to_{to}.html` as default filename
- **AND** the save panel's allowed content type filter is `.html`

#### Scenario: User keeps default PDF

- **WHEN** the user opens the export sheet, leaves format at PDF, and clicks Save
- **THEN** the save panel offers `claude-usage-report-{from}_to_{to}.pdf` as default filename
- **AND** the save panel's allowed content type filter is `.pdf`

### Requirement: PDF render fidelity

The PDF output SHALL preserve the layout, typography, charts, and reset markers of the equivalent HTML output. Rendering is performed via WebKit's `createPDF` on an off-screen `WKWebView` loaded with the bundled HTML template, so the PDF inherits the template's `@page` rules (margins, page breaks, paper size). Empty-bucket placeholders SHALL render identically in both formats.

#### Scenario: PDF and HTML show the same content

- **WHEN** the same `(title, range, buckets)` request is exported twice — once as HTML, once as PDF
- **THEN** both files contain the same summary stats, the same charts (modulo PDF being non-interactive), the same reset-marker positions, and the same footer metadata

#### Scenario: PDF respects page breaks

- **WHEN** the report has more content than fits on a single page
- **THEN** WebKit paginates per the template's `@page` rule and individual trend sections are not split mid-chart whenever possible (`page-break-inside: avoid`)

#### Scenario: PDF render failure

- **WHEN** WebKit fails to load the template or produce the PDF
- **THEN** the export sheet shows an inline error and remains open with the user's selections preserved

### Requirement: Report layout and content

The exported report SHALL contain, in vertical order:
1. A header showing the user-provided title, the resolved date range, and the duration in days
2. One summary card per selected bucket showing sample count, peak utilization (%), and average utilization (%)
3. One trend chart per selected bucket, plotting utilization (0–100%) over time, with vertical dashed lines marking reset events detected via `ResetDetection.detect(_:)`
4. A footer showing the source path of the SQLite store and the generation timestamp

Buckets MUST appear in the canonical order: `five_hour`, `seven_day`, then model-scoped weekly buckets sorted by model name (skipping unselected buckets). Scoped sections are titled `7-Day Window — <Model>` with a per-model deterministic chart color; "Sonnet" keeps its historical color.

#### Scenario: Default selection (5H + 7D)

- **WHEN** the user exports with the default selection and a range that contains samples
- **THEN** the report header shows the title, date range, and duration
- **AND** the report contains exactly two summary cards (5-hour, 7-day) and two trend charts in that order
- **AND** the 7-day chart does NOT include any scoped model line

#### Scenario: Scoped bucket selected

- **WHEN** the user additionally selects the "Fable" scoped bucket and exports
- **THEN** the report contains three summary cards and three trend charts in canonical order
- **AND** the "7-Day Window — Fable" chart renders only that bucket's data (not merged into the `seven_day` chart)

#### Scenario: Reset markers appear on charts

- **WHEN** the selected range contains reset events for one of the selected buckets
- **THEN** the corresponding chart shows vertical dashed lines at those reset timestamps

### Requirement: Empty range handling

If the selected range contains zero samples across all selected buckets, the Save action SHALL be disabled in the export sheet and an inline message SHALL indicate "No samples in the selected range".

#### Scenario: User picks a range before any data exists

- **WHEN** the oldest sample in the store is 2026-05-07 and the user sets Custom From = 2026-01-01, To = 2026-04-30
- **THEN** the Save button is disabled
- **AND** the sheet displays "No samples in the selected range"

#### Scenario: One selected bucket has data, another does not

- **WHEN** `five_hour` has samples in the range but a selected scoped bucket does not
- **THEN** Save is enabled
- **AND** the report includes both summary cards, with the empty bucket showing "No data" instead of numeric stats and an empty chart with a "No samples" placeholder

### Requirement: Report visual quality

The HTML template SHALL be styled to read as a report artifact — with consistent typography hierarchy, a calm neutral palette, and clear separation between header / summary cards / charts / footer — rather than as a debug dump or demo scaffold.

#### Scenario: Visual review

- **WHEN** a reviewer opens the exported report in a desktop browser at default zoom
- **THEN** the title is clearly the dominant element, summary cards form a visibly grouped row or grid, and chart sections are visually separated from cards and footer
- **AND** colors used for the two trend lines are distinguishable for typical viewers (including the common red-green color-vision case)

### Requirement: Claude Code export sheet default state

Every time `CCExportSheetView` opens, it SHALL initialise its fields to a fixed default state, independent of any prior export session or the Dashboard's current state.

The defaults are:
- Title: `"Claude Code Activity Report"`
- Format: `PDF`
- Range selection: preset `"Last 7d"` (preset of `last7d` from the shared range widget)
- Include `Project totals + mix breakdown`: checked
- Include `Subscription utilisation overlay`: checked

#### Scenario: First open in a session

- **WHEN** the user opens `CCExportSheetView` for the first time after launching the app
- **THEN** the title field shows "Claude Code Activity Report"
- **AND** the format selector shows "PDF" selected
- **AND** the range widget shows "Last 7d" with the "7d" chip selected
- **AND** both Include toggles are checked

#### Scenario: Reopen after a prior CC export

- **WHEN** the user successfully exports a CC report with title "Q1 CC Review", format HTML, range Custom, and the subscription-overlay toggle unchecked, then later reopens the CC export sheet
- **THEN** the sheet is restored to defaults (title, format PDF, range Last 7d, both Include toggles checked)

### Requirement: Claude Code export sheet form layout

`CCExportSheetView` SHALL present, in vertical order: a header (sheet title + one-line description), a Title text field, a Format segmented selector (PDF / HTML), a Date range section using the shared `RangePickerView`, an Include section with two checkboxes (`Project totals + mix breakdown`, `Subscription utilisation overlay`), and a Projects-in-range section listing every observed cwd in the selected range as read-only monospaced text with a count in the section header. The footer SHALL contain Cancel and Save buttons.

The Projects-in-range section is informational — there is no per-project filter control in v1. The exported report always contains every project observed in the selected range.

#### Scenario: Sheet shows observed cwds

- **GIVEN** `cc_message` contains rows for four distinct cwds in the selected range
- **WHEN** the user opens the CC export sheet
- **THEN** the Projects-in-range section header reads "Projects in range (4)"
- **AND** the section lists those four cwd strings as read-only text
- **AND** there is no toggle or checkbox in the Projects section

#### Scenario: Range change updates the project list

- **GIVEN** the sheet is open with the 7d range selected and four cwds visible
- **WHEN** the user picks the 24h range and only one cwd has activity in that window
- **THEN** the Projects-in-range section header updates to "Projects in range (1)"
- **AND** only that cwd is listed

### Requirement: Claude Code export Save flow

When the user clicks Save in `CCExportSheetView`, the app SHALL present a standard `NSSavePanel` with a default filename `claude-code-report-{from}_to_{to}.{ext}` where `{ext}` is `pdf` or `html` according to the selected format. The save panel's allowed content type SHALL match the chosen format. On confirm, `CCReportGenerator` SHALL produce the file at the chosen URL; on cancel, no file is written and the sheet remains open with selections preserved.

#### Scenario: Default filename for CC PDF

- **GIVEN** range Custom 2026-05-07..2026-05-14 and format PDF
- **WHEN** the user clicks Save and accepts the default filename
- **THEN** the file is written as `claude-code-report-2026-05-07_to_2026-05-14.pdf`

#### Scenario: Default filename for CC HTML

- **GIVEN** range Custom 2026-05-07..2026-05-14 and format HTML
- **WHEN** the user clicks Save and accepts the default filename
- **THEN** the file is written as `claude-code-report-2026-05-07_to_2026-05-14.html`

#### Scenario: User cancels the save panel

- **WHEN** the user dismisses the save panel without saving
- **THEN** no file is written and the CC export sheet remains open with its prior selections (including format and Include toggles) preserved

### Requirement: Empty CC range handling

If the selected range contains zero `cc_message` rows, the Save action SHALL be disabled and an inline message SHALL indicate `"No Claude Code activity in the selected range"`.

#### Scenario: Range predates CC data

- **GIVEN** the oldest `cc_message.ts` is 2026-05-01 and the user picks Custom From = 2026-01-01, To = 2026-04-30
- **THEN** the Save button is disabled
- **AND** the sheet displays "No Claude Code activity in the selected range"

### Requirement: Claude Code report output is a single self-contained file

The exported CC file SHALL be a single file that opens fully without any network access, in one of two formats selectable by the user:

- **HTML**: a single `.html` file with the already-bundled `chart.umd.min.js` inlined and the per-bucket project data embedded as a JSON literal within the HTML.
- **PDF**: a single `.pdf` file rendered from the same HTML via `WKWebView.createPDF` (`PDFRenderer`), with system fonts embedded.

#### Scenario: Open the CC HTML report offline

- **WHEN** the recipient opens the exported CC HTML on a machine with no internet connection
- **THEN** all charts, the stats strip, and the project totals list render identically to viewing it online

#### Scenario: Open the CC PDF report offline

- **WHEN** the recipient opens the exported CC PDF on a machine with no internet connection and no TokenTrace installed
- **THEN** the report renders identically to its on-screen original

#### Scenario: No external resource requests (HTML)

- **WHEN** the exported CC HTML is opened in a browser with the Network panel observed
- **THEN** zero outbound requests to non-`file://` origins are made

### Requirement: Claude Code report layout and content

The exported CC report SHALL contain, in vertical order:

1. A header showing the user-provided title, the resolved date range, and the duration in days.
2. A **stats strip** showing total weighted token volume, the top project's name and its share of the total, and peak `five_hour` subscription utilisation in the range.
3. A **stacked area chart** of weighted token volume by project over time, with each project's four token components (input / output / cache_creation / cache_read) sub-stacked within its band. If the `Subscription utilisation overlay` toggle is on, a `five_hour` line (solid) and a `seven_day` line (dashed) SHALL be drawn on a secondary 0–100% Y axis sharing the same X axis.
4. If the `Project totals + mix breakdown` toggle is on, a **project totals list** sorted descending by weighted volume, each row showing project display name, a horizontal bar, weighted total, percentage of grand total, the four-component weighted-contribution mix bar, and the Opus / Sonnet split.
5. A footer showing the source SQLite store path and the generation timestamp.

#### Scenario: Default selection — both Include toggles on

- **WHEN** the user exports with both Include toggles checked and a range containing CC data and subscription samples
- **THEN** the report shows: header → stats strip → stacked-area chart WITH subscription overlay → project totals list → footer

#### Scenario: Subscription overlay toggle off

- **WHEN** the user unchecks `Subscription utilisation overlay` and exports
- **THEN** the report shows the same content except the chart contains no subscription lines and no secondary Y axis
- **AND** the stats strip still displays the peak 5h util drawn from the CC range (it is a numeric fact, not a chart element)

#### Scenario: Project totals toggle off

- **WHEN** the user unchecks `Project totals + mix breakdown` and exports
- **THEN** the project totals list section is omitted from the report
- **AND** the rest of the report is unchanged

### Requirement: Claude Code report visual quality

The CC HTML template SHALL be styled to read as a report artefact — consistent typography hierarchy with the existing `report.html.template`, calm neutral palette, clear separation between header / stats strip / chart / project totals / footer.

#### Scenario: Visual review

- **WHEN** a reviewer opens the exported CC report in a desktop browser at default zoom
- **THEN** the title is clearly the dominant element, the stats strip reads as a row of grouped values, the chart and project totals list are visually separated from each other and from header / footer
- **AND** the four project colours used in the stacked area are distinguishable for typical viewers including the common red-green colour-vision case

