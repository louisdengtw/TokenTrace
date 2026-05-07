## ADDED Requirements

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
- **AND** the same set of vertical lines applies to both `seven_day` and `seven_day_sonnet` (resets coincide)

### Requirement: Multi-line plotting on the weekly chart

The 7-day chart SHALL render two distinct lines when both `seven_day` and `seven_day_sonnet` data exist: one labeled "Overall" and one labeled "Sonnet", each visually distinguishable (different color or style).

#### Scenario: Pro user with Sonnet data

- **WHEN** samples for both `seven_day` and `seven_day_sonnet` exist in range
- **THEN** the chart shows two lines with a legend identifying each

#### Scenario: Non-Pro user without Sonnet data

- **WHEN** no `seven_day_sonnet` samples exist in range
- **THEN** the chart shows only the "Overall" line and the legend omits "Sonnet"

### Requirement: Range selector controls visible time window

The Dashboard SHALL provide a segmented control with options 24h, 7d, 30d, and All. Selecting an option SHALL update both charts' X-axis domain to that range, with "All" using the timestamp of the oldest sample as the start.

#### Scenario: User selects 7d

- **WHEN** the user clicks the "7d" segment
- **THEN** both charts re-query the store with start = now - 7 × 86400
- **AND** the X-axis domain on both charts updates to that range

#### Scenario: User selects All on a fresh database

- **WHEN** the user clicks "All" and only one day of data exists
- **THEN** the charts show that single day, not an awkward empty 30-day stretch

### Requirement: Hover tooltip displays sample value

Each chart SHALL show a tooltip when the user hovers over a data point, displaying the timestamp (formatted in the user's locale) and the utilization percentage.

#### Scenario: Hovering over a 5-hour data point

- **WHEN** the user moves the cursor over a sample on the top chart
- **THEN** a tooltip appears near the cursor showing the timestamp and the utilization value

#### Scenario: Hovering over the weekly chart with two lines

- **WHEN** the user hovers near a point on the weekly chart
- **THEN** the tooltip shows both the Overall and Sonnet values for the nearest sample

### Requirement: Reactive updates on new samples

The Dashboard SHALL refresh both charts when a new poll inserts samples into the store, without requiring the user to switch tabs or re-open the window.

#### Scenario: Background poll while dashboard is open

- **WHEN** a successful poll completes while the user is viewing the Dashboard
- **THEN** both charts update to include the new sample within 1 second
- **AND** the visible range and selection state are preserved
