## MODIFIED Requirements

### Requirement: Quit reaches termination only via the menu bar status item

The application SHALL intercept all standard Quit attempts (⌘Q, the application menu's "Quit TokenTrace" item, any programmatic `NSApp.terminate(_:)` invocation without prior consent) and route them to "close all windows" behavior, leaving the process running with the menu bar item visible. Real process termination SHALL be reachable from user-initiated affordances that set an internal `userInitiatedQuit` flag before invoking terminate. Two such affordances exist:

1. **"Quit TokenTrace"** in the menu bar status item's right-click context menu.
2. **The power-icon button** in the main window's sidebar footer, rendered to the right of the sync-status indicator and hidden when the sidebar is collapsed.

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

- **WHEN** the user selects "Quit TokenTrace" from the application menu (left of the macOS menu bar) while the main window is in focus
- **THEN** the same intercept-and-close behavior applies as for ⌘Q

#### Scenario: Real Quit from the status item

- **WHEN** the user right-clicks the menu bar status item and selects "Quit TokenTrace"
- **THEN** the status item's quit handler sets `userInitiatedQuit = true`
- **AND** invokes `NSApp.terminate(_:)`
- **AND** `applicationShouldTerminate(_:)` returns `.terminateNow`
- **AND** the process terminates and both the menu bar item and any window disappear

#### Scenario: Real Quit from the main window sidebar footer

- **WHEN** the user clicks the power-icon button in the main window's sidebar footer
- **THEN** the button's action invokes `AppDelegate.requestRealQuit()`
- **AND** `requestRealQuit()` sets `userInitiatedQuit = true` and invokes `NSApp.terminate(_:)`
- **AND** `applicationShouldTerminate(_:)` returns `.terminateNow`
- **AND** the process terminates and both the menu bar item and the main window disappear

#### Scenario: Sidebar collapsed hides the quit affordance

- **WHEN** the user collapses the main window sidebar to its narrow rail (icon-only)
- **THEN** the power-icon button is not rendered
- **AND** the only remaining real-quit affordance is the menu bar status item right-click menu
