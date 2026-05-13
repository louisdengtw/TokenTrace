## MODIFIED Requirements

### Requirement: Range selector controls visible time window

The Dashboard SHALL provide a range selector consisting of preset chips (`24h`, `7d`, `30d`, `All`) and a custom From/To date picker pair. Selecting a preset chip SHALL update both charts' X-axis domain to that range, with the `All` preset resolving to start = the timestamp of the oldest sample in the store and end = now. Editing either the From or the To date picker to a value not matching the currently-selected preset SHALL deselect all chips, place the selector into Custom state, and update both charts' X-axis domain to the user-specified `[From, To]` interval. The selector SHALL NOT enter an inverted state where From > To.

#### Scenario: User clicks the "7d" chip

- **WHEN** the user clicks the "7d" preset chip
- **THEN** both charts re-query the store with start = now − 7 × 86400 and end = now
- **AND** the X-axis domain on both charts updates to that range
- **AND** the "7d" chip appears visually selected, and From/To display the resolved dates

#### Scenario: User selects "All" on a fresh database

- **WHEN** the user clicks the "All" chip and only one day of data exists
- **THEN** the charts show that single day, not an awkward empty 30-day stretch

#### Scenario: User edits the From date

- **WHEN** the user changes the From date picker to a value different from the currently-selected preset's start
- **THEN** the selector enters Custom state (no chip is highlighted)
- **AND** both charts re-query the store with start = the new From date and end = the current To date

#### Scenario: User attempts to set From later than To

- **WHEN** the user attempts to set From > To via either date picker
- **THEN** the selector prevents the inverted state by adjusting whichever value was not just edited so that From ≤ To
- **AND** the charts never re-query with an inverted range

## ADDED Requirements

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
