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

This mirrors Stats, Day One, Linear, and other window-primary apps with menu bar accessories — manual launches surface the dashboard; login-item auto-launches stay invisible.

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

### Requirement: Dynamic activation policy switching

The application SHALL run with `NSApplication.ActivationPolicy.regular` while at least one main window is visible, and switch back to `.accessory` when the last main window closes. This keeps the Dock icon scoped to "there is a window to see"; the polling loop continues regardless.

#### Scenario: Opening the main window while in accessory mode

- **WHEN** the application is in `.accessory` mode (login-launched, or after a previous window close) and the user opens the main window via the popover, status item right-click, or app menu
- **THEN** the activation policy switches to `.regular`
- **AND** the Dock icon appears
- **AND** the main window appears centered with keyboard focus

#### Scenario: Re-opening the main window when one is already visible

- **WHEN** the main window is already open and the user invokes "Open Main Window" again
- **THEN** the existing window is brought to the front (no second window is created)

#### Scenario: Closing the main window

- **WHEN** the user closes the main window via the red close button or ⌘W
- **THEN** the activation policy switches back to `.accessory`
- **AND** the Dock icon disappears
- **AND** the menu bar status item remains visible
- **AND** the polling loop continues running

### Requirement: Quit reaches termination only via the menu bar status item

The application SHALL intercept all standard Quit attempts (⌘Q, the application menu's "Quit ClaudeUsage" item, any programmatic `NSApp.terminate(_:)` invocation without prior consent) and route them to "close all windows" behavior, leaving the process running with the menu bar item visible. Real process termination SHALL be reachable only by selecting "Quit ClaudeUsage" from the menu bar status item's right-click context menu, which sets an internal `userInitiatedQuit` flag before invoking terminate.

`applicationShouldTerminateAfterLastWindowClosed(_:)` SHALL return `false`, so closing the last window via the red button or ⌘W never auto-terminates.

#### Scenario: ⌘Q with main window visible

- **WHEN** the user presses ⌘Q while the main window is in focus
- **THEN** `applicationShouldTerminate(_:)` is invoked
- **AND** the `userInitiatedQuit` flag is `false`
- **AND** the main window closes
- **AND** `applicationShouldTerminate(_:)` returns `.terminateCancel`
- **AND** the process keeps running with the menu bar item visible
- **AND** the polling loop continues

#### Scenario: App menu Quit selection

- **WHEN** the user selects "Quit ClaudeUsage" from the application menu (left of the macOS menu bar) while the main window is in focus
- **THEN** the same intercept-and-close behavior applies as for ⌘Q

#### Scenario: Real Quit from the status item

- **WHEN** the user right-clicks the menu bar status item and selects "Quit ClaudeUsage"
- **THEN** the status item's quit handler sets `userInitiatedQuit = true`
- **AND** invokes `NSApp.terminate(_:)`
- **AND** `applicationShouldTerminate(_:)` returns `.terminateNow`
- **AND** the process terminates and both the menu bar item and any window disappear

### Requirement: Standard macOS menu bar when window is in focus

When the application is in `.regular` activation policy with a main window visible, the system menu bar SHALL host the conventional six-menu structure constructed programmatically as `NSApp.mainMenu`:

- **Application** (titled "ClaudeUsage"): About ClaudeUsage, Settings…, Services, Hide ClaudeUsage, Hide Others, Show All, Quit ClaudeUsage (⌘Q)
- **File**: Close (⌘W)
- **Edit**: Undo, Redo, Cut, Copy, Paste, Select All (so the cookie paste field in Settings has standard editing affordances)
- **View**: placeholder for v1; may be empty
- **Window**: Minimize (⌘M), Zoom
- **Help**: ClaudeUsage Help (placeholder for v1)

#### Scenario: Menu bar populated when window is focused

- **WHEN** the main window has keyboard focus
- **THEN** the macOS menu bar shows the six menus above
- **AND** ⌘Q (bound to the application menu's Quit item) is intercepted per the Quit semantics requirement
- **AND** ⌘W (bound to the File menu's Close item) closes the window per the dynamic activation policy requirement

#### Scenario: Menu bar definition persists across mode switches

- **WHEN** the application transitions between `.accessory` and `.regular` activation policies
- **THEN** `NSApp.mainMenu` remains defined (constructed once at launch)
- **AND** the next time a main window becomes frontmost, the six menus are immediately available
