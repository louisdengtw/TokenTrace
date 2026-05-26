## MODIFIED Requirements

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

## ADDED Requirements

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

#### Scenario: First launch with no CC data

- **GIVEN** the user has just installed TokenTrace and `~/.claude/projects/` does not exist or is empty
- **WHEN** the user opens the Claude Code tab
- **THEN** the tab renders an empty-state message explaining that no Claude Code transcripts were found, with a hint about the expected directory
- **AND** the Subscription tab continues to function unaffected

#### Scenario: Last-active tab is remembered

- **WHEN** the user selects the Claude Code tab, quits the app, and relaunches it
- **THEN** the Dashboard opens with the Claude Code tab selected

### Requirement: Claude Code tab layout

The Claude Code tab SHALL render the following sections in vertical order:
1. A header row containing (a) a "Refresh" button that re-runs the ingester, (b) a "Manage projects…" button that opens the project alias sheet, and (c) a small info affordance with the weighted-token-volume caveat (a relative measure derived from API pricing ratios, not a direct subscription-quota burn measurement).
2. A **single chart** with two Y axes sharing one X axis:
   - **Left Y axis**: weighted token volume, auto-scaled. Renders as a stacked area, one band per project. Within each project's band, the four raw token components (input, output, cache_creation, cache_read) SHALL be visually distinguishable (e.g. as sub-stacked sub-bands of different shades of the project's base colour).
   - **Right Y axis**: subscription utilisation, fixed 0–100%. Renders as line marks. The `five_hour` series SHALL appear as a solid line; the `seven_day` series SHALL appear as a dashed line.
3. A legend below the chart mapping each project's colour to its display name.

The chart's X axis SHALL be driven by the active range selection.

#### Scenario: Two projects, both with data, plus subscription samples

- **GIVEN** the active range contains CC records for two projects ("TokenTrace" and "BMO") and subscription samples for `five_hour` and `seven_day`
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows two stacked areas (one per project) on the left axis
- **AND** within each project's band the four token components are visually distinguishable
- **AND** the chart shows a solid line for `five_hour %` and a dashed line for `seven_day %` on the right axis (0–100%)
- **AND** the legend lists "TokenTrace" and "BMO" with their respective colours

#### Scenario: X axis updates with range

- **WHEN** the user changes the range to "30d"
- **THEN** the chart re-renders with X-axis domain `[now − 30d, now]`
- **AND** both the stacked area and the utilisation lines re-scale to that domain

### Requirement: Hover synchronisation and unified tooltip on the Claude Code chart

Hovering on the Claude Code chart SHALL show a vertical guideline at the cursor's X position. A tooltip SHALL appear at the cursor showing, for that timestamp:
- Subscription utilisation values (`five_hour %` and `seven_day %`) if data exists at that point.
- Per-project weighted token volume contributions in descending order, with the four raw token components for the top project also shown.

#### Scenario: Hover surfaces both data sources

- **GIVEN** the cursor is at X position corresponding to 2026-05-20T14:00
- **WHEN** the user hovers there on the chart
- **THEN** a vertical guideline appears at that X position
- **AND** the tooltip shows the per-project breakdown at that time
- **AND** the tooltip also includes the subscription utilisation values at that time
- **AND** if either data source has no value at that timestamp, the tooltip omits that section but still shows the other

### Requirement: Empty-data handling on the Claude Code tab

If the active range contains no Claude Code records, the chart SHALL render the subscription utilisation lines alone (no stacked area) and SHALL display an inline note "No Claude Code activity in this range" in the legend area. If the active range additionally contains no subscription samples, the chart SHALL be replaced entirely with an empty-state placeholder.

#### Scenario: Active range predates CC data but has subscription samples

- **GIVEN** the oldest CC record is 2026-05-01 and the user picks Custom range 2026-04-15 to 2026-04-30
- **GIVEN** subscription samples exist in that range
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows the subscription utilisation lines alone
- **AND** the legend area shows "No Claude Code activity in this range"

#### Scenario: Active range has CC data but no subscription samples

- **GIVEN** CC records exist in the range but no subscription samples do (e.g. TokenTrace was not yet running)
- **WHEN** the Claude Code tab renders
- **THEN** the chart shows the stacked area alone
- **AND** the legend area does not show the "no subscription samples" message inline; the right Y axis still renders with its 0–100% scale but with no line marks

#### Scenario: Active range has neither

- **WHEN** the active range contains no CC records and no subscription samples
- **THEN** the chart is replaced with an empty-state placeholder ("No data in this range")
