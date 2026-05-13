# app-settings Specification

## Purpose

User-facing configuration surface for TokenTrace: cookie management UI (paste / view / clear), notifications toggle and threshold logic, and open-at-login. Settings live in the main window's Settings tab — not in the popover — and persist across app relaunches via `UserDefaults`.
## Requirements
### Requirement: Settings live in the main window, not the popover

All user-configurable settings SHALL be presented in a "Settings" tab within the main window. The popover SHALL NOT contain any settings UI beyond a button that opens the main window's Settings tab.

#### Scenario: Opening Settings from the popover

- **WHEN** the user clicks "Settings…" in the popover
- **THEN** the main window opens with the Settings tab active

#### Scenario: Popover stays minimal

- **WHEN** the user opens the popover
- **THEN** no toggles, text fields, or buttons other than navigation actions appear in it

### Requirement: Cookie management UI

The Settings tab SHALL provide controls to: (1) view a redacted preview of the currently stored cookie, (2) paste and save a new cookie, (3) clear the stored cookie ("Sign out"), (4) open the user's default browser to `https://claude.ai` to begin cookie acquisition, (5) discover the optional WebExtension that streamlines the handoff for Firefox-family browsers. The paste-and-save control SHALL accept any input shape supported by the `cookie-import` capability's parser (raw cookie header, `Cookie:`-prefixed string, or curl command).

#### Scenario: Viewing the stored cookie

- **WHEN** a cookie is stored and the user opens Settings
- **THEN** the UI shows a preview such as `sessionKey=eyJ...●●●●●● (45 chars)` without revealing the full secret

#### Scenario: Pasting a raw cookie header

- **WHEN** the user pastes a raw cookie string containing `sessionKey=…` and clicks "Save"
- **THEN** the cookie is written to the Keychain (per the claude-api-integration capability)
- **AND** an immediate fetch is triggered to validate it

#### Scenario: Pasting a curl command

- **WHEN** the user pastes a `curl` command from a browser DevTools "Copy as cURL" action and clicks "Save"
- **THEN** the input is parsed by the cookie-import capability's parser
- **AND** the extracted cookie value is written to the Keychain
- **AND** an immediate fetch is triggered to validate it

#### Scenario: Pasting input that fails parser validation

- **WHEN** the user pastes text that does not contain `sessionKey=` and clicks "Save"
- **THEN** Settings shows an inline error explaining accepted input shapes
- **AND** the Keychain is not modified

#### Scenario: Opening claude.ai from Settings

- **WHEN** the user clicks the "Open claude.ai" affordance in the cookie section
- **THEN** the user's default browser launches and navigates to `https://claude.ai/settings/usage`
- **AND** focus does not leave Settings unnecessarily (the user can switch back to paste)

The `/settings/usage` path is chosen over the bare `https://claude.ai` because that page issues the same `/api/organizations/{id}/usage` request TokenTrace polls, so the user's "Copy as cURL" in DevTools Network lands on the right request without searching.

#### Scenario: Discovering the WebExtension

- **WHEN** the user views the cookie section in Settings
- **THEN** a hint or link is visible directing the user to the published WebExtension install instructions
- **AND** the hint is unobtrusive enough that users on non-Firefox browsers are not confused

#### Scenario: Sign out

- **WHEN** the user clicks "Sign out"
- **THEN** the cookie is cleared from the Keychain
- **AND** the menu bar status item shows the signed-out state

### Requirement: Notifications toggle and threshold logic

The Settings tab SHALL provide a master "Enable notifications" toggle. When enabled, the system SHALL deliver one local notification when the 5-hour utilization first crosses each of the thresholds 25%, 50%, 75%, and 90%, with each threshold firing at most once per 5-hour window.

#### Scenario: Crossing 75% for the first time in a window

- **WHEN** notifications are enabled and the 5-hour utilization rises from 60% to 78%
- **THEN** one notification is delivered with text mentioning the 75% threshold

#### Scenario: Threshold already fired in current window

- **WHEN** the 75% notification has already fired this window and utilization briefly drops to 70% then rises to 80%
- **THEN** no duplicate 75% notification is delivered

#### Scenario: Window reset re-arms thresholds

- **WHEN** the 5-hour window resets (utilization drops to 0)
- **THEN** the threshold tracker is reset
- **AND** subsequent crossings in the new window deliver notifications again

#### Scenario: Notifications disabled

- **WHEN** the user toggles notifications off
- **THEN** no notifications are delivered regardless of threshold crossings

<!-- Removed 2026-05-07: Hotkey enable/disable requirement was dropped from v1
     when the global ⌘U hotkey itself was scrapped.
     See tasks.md task 8.4 for the historical scope. -->

### Requirement: Open at login

The Settings tab SHALL provide an "Open at login" toggle. When on, the system SHALL register the app with the macOS launch services so it starts on user login.

#### Scenario: Enabling open-at-login

- **WHEN** the user toggles "Open at login" on
- **THEN** the app is registered as a login item via `SMAppService.mainApp`
- **AND** the toggle persists across app restarts

#### Scenario: Disabling open-at-login

- **WHEN** the user toggles "Open at login" off
- **THEN** the app is unregistered from launch services
- **AND** subsequent reboots do not auto-launch the app

### Requirement: Settings persistence

All Settings tab toggles SHALL persist via `UserDefaults` (or equivalent), survive app relaunches, and be restored on next launch without user action.

#### Scenario: Restoring after relaunch

- **WHEN** the user disables notifications and quits the app
- **AND** then re-launches the app
- **THEN** the notifications toggle remains off
- **AND** no notifications are delivered until re-enabled

