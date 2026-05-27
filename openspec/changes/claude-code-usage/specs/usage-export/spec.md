## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Claude Code export sheet default state

Every time `CCExportSheetView` opens, it SHALL initialise its fields to a fixed default state, independent of any prior export session or the Dashboard's current state.

The defaults are:
- Title: `"Claude Code Activity Report"`
- Format: `PDF`
- Range selection: preset `"Last 7d"` (preset of `last7d` from the shared range widget)
- Include `Project totals + mix breakdown`: checked
- Include `Subscription utilisation overlay`: checked
- `All projects` selection: checked

#### Scenario: First open in a session

- **WHEN** the user opens `CCExportSheetView` for the first time after launching the app
- **THEN** the title field shows "Claude Code Activity Report"
- **AND** the format selector shows "PDF" selected
- **AND** the range widget shows "Last 7d" with the "7d" chip selected
- **AND** both Include toggles are checked
- **AND** the All-projects toggle is checked

#### Scenario: Reopen after a prior CC export

- **WHEN** the user successfully exports a CC report with title "Q1 CC Review", format HTML, range Custom, and the subscription-overlay toggle unchecked, then later reopens the CC export sheet
- **THEN** the sheet is restored to defaults (title, format PDF, range Last 7d, both toggles checked, All projects checked)

### Requirement: Claude Code export sheet form layout

`CCExportSheetView` SHALL present, in vertical order: a header (sheet title + one-line description), a Title text field, a Format segmented selector (PDF / HTML), a Date range section using the shared `RangePickerView`, an Include section with two checkboxes (`Project totals + mix breakdown`, `Subscription utilisation overlay`), and a Projects section showing the observed `cwd` set with an `All projects` toggle. The footer SHALL contain Cancel and Save buttons.

The Projects section in v1 SHALL list the observed cwds read-only beyond the All toggle (no per-row check boxes). Toggling All off SHALL surface no behavioural change in v1 (the report still includes every project); a per-project picker is out of scope.

#### Scenario: Sheet shows observed cwds

- **GIVEN** `cc_message` contains rows for four distinct cwds in the selected range
- **WHEN** the user opens the CC export sheet
- **THEN** the Projects section shows those four cwd strings (read-only text), preceded by an All-projects toggle

#### Scenario: All-projects toggle is informational in v1

- **WHEN** the user unchecks the All-projects toggle and then clicks Save
- **THEN** the generated report still contains every project observed in the range (the toggle has no effect on output in v1)

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
