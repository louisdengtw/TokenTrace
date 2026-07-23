# usage-dashboard Specification

## Purpose

SwiftUI Charts–based historical view in TokenTrace's main window: two stacked trend charts (5-hour and 7-day utilization), vertical dashed lines marking reset events, multi-line plotting for `seven_day` plus any model-scoped weekly series (dynamically labelled by model name), a 24h / 7d / 30d / All range selector, hover tooltips, and reactive updates when a new poll lands.
## Requirements
### Requirement: Two stacked trend charts

The Dashboard view SHALL render two charts vertically: a "5-hour Session Utilization" chart on top, and a "7-day Weekly Utilization" chart below. Each SHALL plot utilization (0–100%) on the Y axis and time on the X axis.

#### Scenario: Both charts visible on first open

- **WHEN** the user opens the Dashboard tab
- **THEN** both charts are visible
- **AND** the X axis ranges of both charts match the currently selected time range

#### Scenario: Empty data state

- **WHEN** the user opens the Dashboard with no samples in the database yet
- **THEN** each chart shows a placeholder ("No data yet — wait for the first poll") instead of an empty plot area

### Requirement: Reset events rendered as vertical dashed lines

Each chart SHALL render a vertical dashed line at every reset event detected by the persistence layer for the buckets it displays.

#### Scenario: 5-hour chart shows session resets

- **WHEN** the visible time range contains 6 reset events for the `five_hour` bucket
- **THEN** the top chart shows 6 vertical dashed lines at those timestamps

#### Scenario: 7-day chart shows weekly resets

- **WHEN** the visible time range spans 14 days
- **THEN** the bottom chart shows up to 2 vertical dashed lines at the `seven_day` reset times
- **AND** the same set of vertical lines applies to `seven_day` and every model-scoped weekly series (resets coincide)

### Requirement: Multi-line plotting on the weekly chart

The 7-day chart SHALL render one line labeled "Overall" for `seven_day`, plus one additional visually distinguishable line per model-scoped weekly series present in the visible range, each labeled with its model display name (e.g. "Fable", "Sonnet"). Line colors SHALL be assigned deterministically per model name; the "Sonnet" series keeps its historical color.

#### Scenario: Scoped Fable data in range

- **WHEN** samples for both `seven_day` and the "Fable" scoped series exist in range
- **THEN** the chart shows two lines with a legend identifying "Overall" and "Fable"

#### Scenario: Range spanning a model rotation

- **WHEN** the visible range contains a historical "Sonnet" scoped tail and a current "Fable" scoped series
- **THEN** the chart shows three lines — "Overall", "Sonnet", and "Fable" — each with a distinct color

#### Scenario: No scoped data in range

- **WHEN** no model-scoped samples exist in range
- **THEN** the chart shows only the "Overall" line and the legend omits scoped entries

### Requirement: Range selector controls visible time window

The Dashboard SHALL provide a range selector consisting of preset chips (`24h`, `7d`, `30d`, **`90d`**, `All`) and a custom From/To date picker pair. Selecting a preset chip SHALL update the active tab's chart(s) X-axis domain to that range. Editing either the From or the To date picker to a value not matching the currently-selected preset SHALL deselect all chips, place the selector into Custom state, and update the active tab's charts to the user-specified `[From, To]` interval. The selector SHALL NOT enter an inverted state where From > To.

#### Scenario: User clicks the "90d" chip

- **WHEN** the user clicks the "90d" preset chip
- **THEN** the active tab's charts re-query with start = now − 90 × 86400 and end = now
- **AND** the X-axis domain on all visible charts updates to that range

#### Scenario: User edits the From date into Custom state

- **WHEN** the user changes the From date picker to a value different from the currently-selected preset's start
- **THEN** the selector enters Custom state (no chip is highlighted)
- **AND** the active tab's charts re-query with start = the new From date and end = the current To date

#### Scenario: User attempts to set From later than To

- **WHEN** the user attempts to set From > To via either date picker
- **THEN** the selector prevents the inverted state by adjusting whichever value was not just edited so that From ≤ To

### Requirement: Hover tooltip displays sample value

Each chart SHALL show a tooltip when the user hovers over a data point, displaying the timestamp (formatted in the user's locale) and the utilization percentage.

#### Scenario: Hovering over a 5-hour data point

- **WHEN** the user moves the cursor over a sample on the top chart
- **THEN** a tooltip appears near the cursor showing the timestamp and the utilization value

#### Scenario: Hovering over the weekly chart with multiple lines

- **WHEN** the user hovers near a point on the weekly chart while scoped series are displayed
- **THEN** the tooltip shows the Overall value and each scoped model's value (labeled by model name) for the nearest sample

### Requirement: Reactive updates on new samples

The Dashboard SHALL refresh both charts when a new poll inserts samples into the store, without requiring the user to switch tabs or re-open the window.

#### Scenario: Background poll while dashboard is open

- **WHEN** a successful poll completes while the user is viewing the Dashboard
- **THEN** both charts update to include the new sample within 1 second
- **AND** the visible range and selection state are preserved

### Requirement: Range selection persists across launches

The Dashboard SHALL persist the user's most recent range selection (either preset or custom) and restore it on the next launch of the app. The restored state SHALL include both the selection mode (preset vs custom) and any associated dates.

#### Scenario: Relaunch with a previous preset selection

- **WHEN** the user previously selected the "30d" chip, quits the app, and relaunches it
- **THEN** the Dashboard opens with the "30d" chip selected and charts showing the last-30-day domain

#### Scenario: Relaunch with a previous Custom range

- **WHEN** the user previously set Custom From = 2026-04-01, To = 2026-04-30, quits the app, and relaunches it
- **THEN** the Dashboard opens in Custom state with those exact From/To dates restored
- **AND** the charts re-query the store with start = 2026-04-01 and end = 2026-04-30

#### Scenario: First launch with no stored selection

- **WHEN** the app is launched for the first time after install and no prior range selection is recorded
- **THEN** the Dashboard defaults to the "7d" preset chip

#### Scenario: Corrupted persisted selection

- **WHEN** the stored range selection cannot be decoded (corrupted, schema drift)
- **THEN** the Dashboard falls back silently to the "7d" preset chip
- **AND** the bad value is overwritten on the next user-initiated selection change

### Requirement: `All` preset spans subscription and Claude Code data combined

The `All` preset SHALL resolve to start = the timestamp of the oldest available data point across **both** the subscription `samples` table and the `cc_message` table (whichever is earlier), and end = now. If neither table has data, `All` SHALL resolve to start = now − 24h.

#### Scenario: CC data predates subscription samples

- **GIVEN** the oldest subscription sample is 2026-05-07 and the oldest CC record is 2026-04-20
- **WHEN** the user clicks the "All" chip
- **THEN** the resolved range start is 2026-04-20
- **AND** charts on both tabs render from that date

#### Scenario: Subscription samples predate CC data

- **GIVEN** the oldest subscription sample is 2026-04-01 and the oldest CC record is 2026-05-13
- **WHEN** the user clicks the "All" chip
- **THEN** the resolved range start is 2026-04-01

### Requirement: Range selection is shared across Dashboard tabs

The same range selector instance SHALL drive both the Subscription tab and the Claude Code tab. Switching tabs SHALL NOT reset the range.

#### Scenario: Range persists across tab switches

- **WHEN** the user selects "7d" on the Subscription tab, then switches to the Claude Code tab
- **THEN** the Claude Code tab opens with the "7d" chip selected and its charts already querying that range

### Requirement: Dashboard splits into Subscription and Claude Code tabs

The Dashboard SHALL present its content within two tabs labelled "Subscription" and "Claude Code". The Subscription tab SHALL contain the existing utilisation charts unchanged. The Claude Code tab SHALL contain the project breakdown view defined below. The range selector and any persisted last-range selection SHALL be shared between the tabs. The last-active tab SHALL be persisted in `AppSettings` under a new key (separate from `dashboardRangeSelection`) and restored on app relaunch.

#### Scenario: Tab labels and order

- **WHEN** the user opens the Dashboard
- **THEN** two tabs are visible, in the order: Subscription (selected by default on first launch), Claude Code

#### Scenario: First launch with no CC data — both tabs available

- **GIVEN** the user has just installed TokenTrace and `~/.claude/projects/` does not exist or is empty
- **WHEN** the user opens the Claude Code tab
- **THEN** the tab is selectable from the sidebar (i.e. the "no CC data yet" condition does not hide the tab)
- **AND** the tab's content reflects the empty state defined in the "Empty-data handling on the Claude Code tab" requirement below — specifically the first-launch onboarding card
- **AND** the Subscription tab continues to function unaffected

#### Scenario: Last-active tab is remembered

- **WHEN** the user selects the Claude Code tab, quits the app, and relaunches it
- **THEN** the Dashboard opens with the Claude Code tab selected

### Requirement: Claude Code tab layout

The Claude Code tab SHALL render the following sections in vertical order:
1. A header row containing (a) a "Refresh" button that re-runs the ingester, (b) a "Manage projects…" button that opens the project alias sheet, and (c) a small info affordance with the weighted-token-volume caveat (a relative measure derived from API pricing ratios, not a direct subscription-quota burn measurement).
2. A **single chart** with two Y axes sharing one X axis:
   - **Left Y axis**: weighted token volume, auto-scaled. Renders as a stacked area, one band per project. Within each project's band, the four raw token components (input, output, cache_creation, cache_read) SHALL be visually distinguishable (e.g. as sub-stacked sub-bands of different shades of the project's base colour).
   - **Right Y axis**: subscription utilisation, fixed 0–100%. Renders as a single line mark for the `five_hour` series, styled as a dotted amber stroke so it remains distinguishable from the project-coloured stacked area beneath it. The `seven_day` series is NOT overlaid on the Claude Code chart — its smooth ramp adds no information beyond what the 5h sawtooth + the Peak 5h Util stat in the stats strip already convey, and crowds the right axis without earning the pixels.
3. A legend below the chart mapping each project's colour to its display name.

The chart's X axis SHALL be driven by the active range selection.

#### Scenario: Two projects, both with data, plus subscription samples

- **GIVEN** the active range contains CC records for two projects ("TokenTrace" and "BMO") and `five_hour` subscription samples
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows two stacked areas (one per project) on the left axis
- **AND** within each project's band the four token components are visually distinguishable
- **AND** the chart shows a dotted amber line for `five_hour %` on the right axis (0–100%)
- **AND** the chart does NOT render a `seven_day %` line — that series is intentionally excluded from the CC overlay
- **AND** the legend lists "TokenTrace" and "BMO" with their respective colours

#### Scenario: X axis updates with range

- **WHEN** the user changes the range to "30d"
- **THEN** the chart re-renders with X-axis domain `[now − 30d, now]`
- **AND** both the stacked area and the utilisation lines re-scale to that domain

### Requirement: Hover synchronisation and unified tooltip on the Claude Code chart

Hovering on the Claude Code chart SHALL show a vertical guideline at the cursor's X position. A tooltip SHALL appear at the cursor showing, for that timestamp:
- The `five_hour %` subscription utilisation value if a sample exists at that point. (The `seven_day` series is intentionally excluded — see the Right Y axis description above.)
- Per-project weighted token volume contributions in descending order, with the four raw token components for the top project also shown.

#### Scenario: Hover surfaces both data sources

- **GIVEN** the cursor is at X position corresponding to 2026-05-20T14:00
- **WHEN** the user hovers there on the chart
- **THEN** a vertical guideline appears at that X position
- **AND** the tooltip shows the per-project breakdown at that time
- **AND** the tooltip also includes the subscription utilisation values at that time
- **AND** if either data source has no value at that timestamp, the tooltip omits that section but still shows the other

### Requirement: Empty-data handling on the Claude Code tab

If the active range contains no Claude Code records, the chart SHALL render the subscription utilisation line alone (no stacked area) and SHALL display an inline note "No Claude Code activity in this range" in the legend area. If the active range additionally contains no subscription samples, the chart SHALL be replaced entirely with an empty-state placeholder. Independently, if the `cc_message` table is empty globally (the user has never ingested), the entire CC tab SHALL be replaced by a first-launch onboarding card.

#### Scenario: Active range predates CC data but has subscription samples

- **GIVEN** the oldest CC record is 2026-05-01 and the user picks Custom range 2026-04-15 to 2026-04-30
- **GIVEN** subscription samples exist in that range
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows the subscription utilisation line alone
- **AND** the legend area shows "No Claude Code activity in this range"

#### Scenario: Active range has CC data but no subscription samples

- **GIVEN** CC records exist in the range but no subscription samples do (e.g. TokenTrace was not yet running)
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows the stacked area alone
- **AND** the legend area does not show the "no subscription samples" message inline; the right Y axis still renders with its 0–100% scale but with no line marks

#### Scenario: Active range has neither

- **WHEN** the active range contains no CC records and no subscription samples
- **THEN** the chart is replaced with an empty-state placeholder ("No data in this range")

#### Scenario: First-launch onboarding (`cc_message` globally empty)

- **GIVEN** the `cc_message` table has zero rows (the ingester has never run, or has run but found no transcripts)
- **WHEN** the user opens the Claude Code tab
- **THEN** the entire tab body (stats strip, chart card, project totals card) is replaced by a single onboarding card containing:
  - a tray glyph
  - a heading "No Claude Code activity yet"
  - body text naming `~/.claude/projects/` as the expected source
  - a prominent "Refresh now" button that triggers the ingester
- **AND** as soon as a successful ingest produces at least one row, the normal CC tab layout takes over on the next render (the empty-in-range scenarios above govern from that point)

