## MODIFIED Requirements

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
