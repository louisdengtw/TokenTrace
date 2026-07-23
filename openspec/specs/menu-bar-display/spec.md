# menu-bar-display Specification

## Purpose

`NSStatusItem`-based menu bar accessory for TokenTrace: display current 5-hour utilization with a color-coded icon (green/yellow/orange/red by threshold), toggle a quick-view popover on left-click, and surface a right-click context menu with "Open Main Window" and "Quit TokenTrace".

## Requirements

### Requirement: Status item shows current 5-hour utilization

The application SHALL maintain an `NSStatusItem` whose title (or icon overlay) displays the current `five_hour` utilization as a percentage, updated on every successful poll.

#### Scenario: Initial state before first fetch

- **WHEN** the app starts and no fetch has succeeded yet
- **THEN** the status item shows the Claude logo icon without a percentage
- **AND** the icon is in a neutral / inactive style

#### Scenario: Updated after successful fetch

- **WHEN** a poll returns `five_hour.utilization = 47`
- **THEN** the status item shows "47%" (or icon + "47%") within 1 second of the fetch completing

### Requirement: Color-coded icon by utilization threshold

The icon SHALL change color based on the latest 5-hour utilization: ≤ 50% green, 51–75% yellow, 76–90% orange, > 90% red.

#### Scenario: Crossing threshold upwards

- **WHEN** utilization rises from 49% to 52%
- **THEN** the icon color updates from green to yellow on the next status update

#### Scenario: Just-after-reset

- **WHEN** the 5-hour window resets and utilization drops to 0
- **THEN** the icon returns to green

### Requirement: Click toggles popover

Left-clicking the status item SHALL toggle a popover anchored to the status item, showing a quick-view of current usage. Clicking outside the popover SHALL close it.

#### Scenario: Open popover

- **WHEN** the user left-clicks the status item with no popover open
- **THEN** the popover appears anchored below the status item

#### Scenario: Click again to close

- **WHEN** the popover is open and the user left-clicks the status item again
- **THEN** the popover closes

#### Scenario: Click outside to dismiss

- **WHEN** the popover is open and the user clicks anywhere outside it
- **THEN** the popover closes automatically

### Requirement: Right-click context menu

Right-clicking the status item SHALL display a context menu with at minimum: "Open Main Window", "Toggle Usage (⌘U)", a separator, and "Quit TokenTrace".

#### Scenario: Selecting Open Main Window

- **WHEN** the user right-clicks the status item and selects "Open Main Window"
- **THEN** the main window opens (per the app-shell capability)

#### Scenario: Selecting Quit

- **WHEN** the user selects "Quit TokenTrace"
- **THEN** the application terminates

### Requirement: Scoped weekly usage surfaces with dynamic model labels

The popover quick-view and the stats-mode status icon SHALL derive any model-scoped weekly row/column from the latest poll's scoped model list, labeling it with the server-provided model display name — the popover row uses the full name (e.g. "Fable"), the stats icon column uses the first three letters uppercased (e.g. "FAB"). When the latest poll reports no scoped models, no scoped row/column is shown. Model names SHALL NOT be hardcoded.

#### Scenario: Latest poll has a Fable scoped limit

- **WHEN** the latest poll's scoped model list is ["Fable"]
- **THEN** the popover shows a "Fable" row with its utilization
- **AND** the stats-mode icon shows a "FAB" column

#### Scenario: No scoped limit in latest poll

- **WHEN** the latest poll's scoped model list is empty
- **THEN** the popover shows only the 5-hour and 7-day rows
- **AND** the stats-mode icon shows no scoped column

#### Scenario: Server rotates the scoped model

- **WHEN** a later poll reports scoped model "Opus" instead of "Fable"
- **THEN** the popover row and stats-icon column labels update to "Opus" / "OPU" without an app update

<!-- Removed 2026-05-07: Global ⌘U hotkey requirement was dropped from v1.
     The popover stays reachable via the menu bar status item left-click.
     See tasks.md task 6.6 for the historical scope. -->

