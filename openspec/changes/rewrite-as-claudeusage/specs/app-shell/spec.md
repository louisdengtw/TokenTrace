## ADDED Requirements

### Requirement: Default menu-bar-only activation

The application SHALL launch with `LSUIElement = true`, presenting only a menu bar status item and no Dock icon by default.

#### Scenario: Cold launch with no window open

- **WHEN** the user launches `ClaudeUsage.app` from `/Applications/`
- **THEN** the menu bar status item appears
- **AND** no Dock icon is shown
- **AND** the application does not steal focus from the active app

#### Scenario: Launch when login-item enabled

- **WHEN** the system starts and the app launches via the "open at login" service
- **THEN** the same menu-bar-only state is presented (no window, no Dock icon)

### Requirement: Dynamic activation policy when main window opens

The application SHALL switch to `NSApplication.ActivationPolicy.regular` while at least one main window is visible, so that the Dock icon appears and the window participates in normal `Cmd+Tab` switching.

#### Scenario: Opening the main window from the popover

- **WHEN** the user clicks the "Open Main Window" button in the popover (or selects the same action from the menu bar item's right-click menu)
- **THEN** the main window appears centered on the active screen
- **AND** the Dock icon appears
- **AND** the application becomes active and the main window receives keyboard focus

#### Scenario: Re-opening when window already open

- **WHEN** the main window is already open and the user triggers "Open Main Window" again
- **THEN** the existing window is brought to the front (no second window is created)

### Requirement: Restore menu-bar-only state when window closes

The application SHALL switch back to `.accessory` activation policy when the last main window closes, hiding the Dock icon while keeping the process alive in the background.

#### Scenario: Closing the main window

- **WHEN** the user closes the main window via the red close button or `Cmd+W`
- **THEN** the Dock icon disappears
- **AND** the menu bar status item remains visible
- **AND** the polling loop continues running

#### Scenario: Quitting via menu bar

- **WHEN** the user selects "Quit ClaudeUsage" from the menu bar item's right-click menu
- **THEN** the process terminates and both the menu bar item and any open window disappear
