## Why

The in-app Dashboard is the only way to see TokenTrace's usage history, but it is bound to a running Mac with TokenTrace installed and cannot be shared as an artifact. When the owner needs to attach usage trends to a report — for personal review, billing reconciliation, or sharing with someone who does not run TokenTrace — there is no way to extract a snapshot. Today this has to be improvised with an ad-hoc SQLite + script workflow, which is fragile, not reproducible inside the app, and produces output of inconsistent quality. Now that usage data has been accumulating reliably for a week, the user wants this to be a first-class, repeatable feature.

A second observation surfaced while exploring this: the Dashboard's range selector is locked to four fixed presets (24h / 7d / 30d / All) and cannot zoom into a specific incident or report window. A custom date range is needed both for the export picker and for general dashboard use, so the range UI is unified in this change rather than diverging.

## What Changes

- Add a self-contained export of the SQLite usage data, opened via an **Export Report…** button on the Dashboard (and File menu / ⌘E as secondary entry points).
- Export dialog lets the user pick: report title, **output format (PDF or HTML)**, date range (using the unified range widget), and which buckets to include (defaults: PDF, `five_hour` ✓, `seven_day` ✓, `seven_day_sonnet` ✗).
- HTML output is a single self-contained `.html` file with Chart.js bundled inline; PDF output is rendered by piping the same HTML through `WKWebView.createPDF` so the artifact is system-fonts-embedded and print-stable. Both are offline-portable. Default filename `claude-usage-report-{from}_to_{to}.{html|pdf}`.
- Report content: title + date-range header + per-bucket summary cards (peak / average / sample count) + one trend chart per selected bucket with reset markers (reusing `ResetDetection.detect`).
- Replace the Dashboard's fixed segmented range selector with a unified **chip presets (24h / 7d / 30d / All) + custom From/To** widget. Editing From/To deselects the chip and enters Custom state.
- The Dashboard persists the user's last range selection across app launches via `AppSettings`. The Export dialog does NOT persist — it always re-defaults to "Last 7d" on each open to prevent silent reuse of an old period.

## Capabilities

### New Capabilities
- `usage-export`: Produce a portable HTML or PDF report from the local SQLite usage store, parameterised by title, output format, date range, and bucket selection.

### Modified Capabilities
- `usage-dashboard`: Replace the fixed segmented range selector with chip presets + custom From/To date pickers; remember the last selection across launches.

## Impact

- **New code**
  - SwiftUI sheet for the export picker (lives in `MainWindow/`).
  - HTML template (Resources) with placeholders for title / date range / per-bucket data / reset events.
  - Inline Chart.js asset bundled in the app resources (~80 KB minified) so the output is offline-portable.
  - A shared `RangeSelection` type + `RangePickerView` reused by Dashboard and Export.
- **Modified code**
  - `DashboardView.swift`: replace `DashboardRange` enum + `RangePicker` with the new shared widget; bind to persisted selection.
  - `AppSettings.swift`: new key for serialized last-used dashboard range (Codable enum → JSON in UserDefaults).
- **Reused, unchanged**
  - `UsageStore.query(bucket:from:to:)` and `ResetDetection.detect(_:)` are used by the report generator unchanged.
- **No external dependencies added.** Chart.js is bundled as a static asset, not fetched.
- **No data model / persistence schema changes.** `samples` table unchanged.
- **Out of scope for v1**: scheduled exports, email/share-sheet send, saved presets, native PDF, downsampling for very large ranges, timezone selection.
