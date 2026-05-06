## ADDED Requirements

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

Right-clicking the status item SHALL display a context menu with at minimum: "Open Main Window", "Toggle Usage (⌘U)", a separator, and "Quit ClaudeUsage".

#### Scenario: Selecting Open Main Window

- **WHEN** the user right-clicks the status item and selects "Open Main Window"
- **THEN** the main window opens (per the app-shell capability)

#### Scenario: Selecting Quit

- **WHEN** the user selects "Quit ClaudeUsage"
- **THEN** the application terminates

### Requirement: Global ⌘U hotkey toggles popover

The application SHALL register a global Carbon hotkey for ⌘U that toggles the popover from anywhere. This requires Accessibility permission, which the app SHALL request only when the hotkey is enabled in settings.

#### Scenario: Hotkey enabled and Accessibility granted

- **WHEN** the user presses ⌘U from any other application
- **THEN** the popover toggles open or closed
- **AND** the active app is not switched

#### Scenario: Hotkey enabled but Accessibility not granted

- **WHEN** the hotkey is enabled in settings but Accessibility permission is not granted
- **THEN** the app prompts the user to grant Accessibility permission via System Settings
- **AND** until granted, ⌘U does nothing globally (still works only when ClaudeUsage is the active app)

#### Scenario: Hotkey disabled

- **WHEN** the user disables the hotkey in settings
- **THEN** the app deregisters the global hotkey
- **AND** does not request Accessibility permission
