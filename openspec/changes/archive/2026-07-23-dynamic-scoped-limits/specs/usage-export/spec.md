# usage-export Delta

## MODIFIED Requirements

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
