## ADDED Requirements

### Requirement: Export entry points

TokenTrace SHALL expose the export feature via a primary entry point — an "Export Report…" button in the Dashboard toolbar — and at least one secondary entry point — a File menu command bound to the keyboard shortcut ⌘E. All entry points SHALL invoke the same modal export sheet.

#### Scenario: User clicks the Dashboard toolbar button

- **WHEN** the user clicks "Export Report…" on the Dashboard toolbar
- **THEN** the export sheet opens modally over the main window

#### Scenario: User uses the File menu

- **WHEN** the user opens the File menu and chooses "Export Report…" (or presses ⌘E)
- **THEN** the export sheet opens modally over the main window
- **AND** it opens regardless of which main-window tab is currently active

### Requirement: Export sheet default state

Every time the export sheet opens, it SHALL initialise its fields to a fixed default state, independent of any prior export session or the Dashboard's current state.

The defaults are:
- Title: `"Claude Usage Report"`
- Format: `PDF`
- Range selection: preset `"Last 7d"` (preset of `last7d` from the shared range widget)
- Buckets: `five_hour` checked, `seven_day` checked, `seven_day_sonnet` unchecked

#### Scenario: First open in a session

- **WHEN** the user opens the export sheet for the first time after launching the app
- **THEN** the title field shows "Claude Usage Report"
- **AND** the format toggle shows "PDF" selected
- **AND** the range widget shows "Last 7d" with the "7d" chip selected
- **AND** the bucket checkboxes show: `five_hour` ✓, `seven_day` ✓, `seven_day_sonnet` ✗

#### Scenario: Reopen after a prior export

- **WHEN** the user successfully exports a report with title "Q1 Recap", format HTML, range Custom 2026-01-01..2026-03-31, and only `seven_day` selected, then later reopens the export sheet
- **THEN** the sheet is restored to defaults: title "Claude Usage Report", format PDF, range "Last 7d", buckets `five_hour` ✓ + `seven_day` ✓ + `seven_day_sonnet` ✗

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

The export sheet SHALL provide one checkbox per usage bucket (`five_hour`, `seven_day`, `seven_day_sonnet`) labelled in the same style as the Dashboard. At least one bucket MUST be selected to enable the Save action.

#### Scenario: User unchecks every bucket

- **WHEN** the user unchecks all three bucket checkboxes
- **THEN** the Save button is disabled
- **AND** a brief inline hint indicates "Select at least one bucket"

#### Scenario: User keeps the default selection

- **WHEN** the user opens the sheet and clicks Save without changing buckets
- **THEN** the report includes the `five_hour` and `seven_day` buckets only

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

Buckets MUST appear in the canonical order: `five_hour`, `seven_day`, `seven_day_sonnet` (skipping unselected buckets).

#### Scenario: Default selection (5H + 7D)

- **WHEN** the user exports with the default selection and a range that contains samples
- **THEN** the report header shows the title, date range, and duration
- **AND** the report contains exactly two summary cards (5-hour, 7-day) and two trend charts in that order
- **AND** the 7-day chart does NOT include a Sonnet line

#### Scenario: All three buckets selected

- **WHEN** the user selects all three buckets and exports
- **THEN** the report contains three summary cards and three trend charts in canonical order
- **AND** the `seven_day_sonnet` chart renders only that bucket's data (not merged into the `seven_day` chart)

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

- **WHEN** `five_hour` has samples in the range but `seven_day_sonnet` does not, and both are selected
- **THEN** Save is enabled
- **AND** the report includes both summary cards, with the empty bucket showing "No data" instead of numeric stats and an empty chart with a "No samples" placeholder

### Requirement: Report visual quality

The HTML template SHALL be styled to read as a report artifact — with consistent typography hierarchy, a calm neutral palette, and clear separation between header / summary cards / charts / footer — rather than as a debug dump or demo scaffold.

#### Scenario: Visual review

- **WHEN** a reviewer opens the exported report in a desktop browser at default zoom
- **THEN** the title is clearly the dominant element, summary cards form a visibly grouped row or grid, and chart sections are visually separated from cards and footer
- **AND** colors used for the two trend lines are distinguishable for typical viewers (including the common red-green color-vision case)
