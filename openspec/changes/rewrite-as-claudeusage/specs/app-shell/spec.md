## ADDED Requirements

### Requirement: Login-item launch presents menu bar only

When the application is launched automatically as a login item (via `SMAppService.mainApp` or any other non-user-initiated path), the application SHALL present only the menu bar status item, with no Dock icon and no main window.

The system SHALL distinguish login-item launches from user-initiated launches by reading `NSApplication.launchIsDefaultUserInfoKey` from the `applicationDidFinishLaunching` notification's userInfo. A value of `false` (or an absent key) indicates a non-user-initiated launch.

#### Scenario: Launch when login-item enabled

- **WHEN** the system starts and the app launches via the "open at login" service
- **THEN** the menu bar status item appears
- **AND** no Dock icon is shown
- **AND** no main window is shown
- **AND** the application does not steal focus from the active app

### Requirement: User-initiated launch shows the main window

When the application is launched directly by the user (double-clicking in Finder, `open` from a terminal, Spotlight, Launchpad), the main window SHALL be shown automatically as part of `applicationDidFinishLaunching`, switching activation policy to `.regular` so the Dock icon appears.

This mirrors the established pattern used by Stats, Bartender, Ice — manual launches surface the configuration UI; login-item auto-launches stay invisible.

#### Scenario: User double-clicks the app icon

- **WHEN** the user double-clicks `/Applications/ClaudeUsage.app` (or runs `open /Applications/ClaudeUsage.app`)
- **THEN** the menu bar status item appears
- **AND** the main window appears centered on the active screen
- **AND** the Dock icon appears

#### Scenario: User reopens the app while it's already running

- **WHEN** the app is running and the user invokes `open` against the bundle again, or clicks the Dock icon while it is visible
- **THEN** `applicationShouldHandleReopen(_:hasVisibleWindows:)` is invoked
- **AND** if no main window is visible, the main window is shown
- **AND** if a main window is already visible, it is brought to the front (no second window is created)

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
