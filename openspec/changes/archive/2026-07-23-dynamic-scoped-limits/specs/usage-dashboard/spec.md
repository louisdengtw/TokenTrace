# usage-dashboard Delta

## MODIFIED Requirements

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

### Requirement: Hover tooltip displays sample value

Each chart SHALL show a tooltip when the user hovers over a data point, displaying the timestamp (formatted in the user's locale) and the utilization percentage.

#### Scenario: Hovering over a 5-hour data point

- **WHEN** the user moves the cursor over a sample on the top chart
- **THEN** a tooltip appears near the cursor showing the timestamp and the utilization value

#### Scenario: Hovering over the weekly chart with multiple lines

- **WHEN** the user hovers near a point on the weekly chart while scoped series are displayed
- **THEN** the tooltip shows the Overall value and each scoped model's value (labeled by model name) for the nearest sample
