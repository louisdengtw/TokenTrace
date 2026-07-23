# menu-bar-display Delta

## ADDED Requirements

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
