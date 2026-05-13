# cookie-import Specification

## Purpose
TBD - created by archiving change cookie-import. Update Purpose after archive.
## Requirements
### Requirement: Cookie input accepts multiple shapes

The cookie input parser SHALL accept any of three input shapes and resolve them to a canonical cookie header string: (a) a raw cookie header, (b) a string prefixed with `Cookie:` (case-insensitive) where the prefix is stripped, (c) a full `curl` command from a browser DevTools "Copy as cURL" action where the value of the `-H 'cookie: …'` (or `--header 'cookie: …'`) flag is extracted. Header-name matching for the cURL extraction SHALL be case-insensitive.

#### Scenario: Raw cookie header

- **WHEN** the user submits `sessionKey=eyJ...; lastActiveOrg=...; cf_bm=...`
- **THEN** the parser returns the string unchanged
- **AND** downstream save proceeds

#### Scenario: Header-prefixed string

- **WHEN** the user submits `Cookie: sessionKey=eyJ...; lastActiveOrg=...`
- **THEN** the parser returns `sessionKey=eyJ...; lastActiveOrg=...` with the prefix stripped

#### Scenario: cURL command from Chromium DevTools

- **WHEN** the user submits `curl 'https://claude.ai/api/organizations/.../usage' -H 'accept: */*' -H 'cookie: sessionKey=eyJ...; lastActiveOrg=abc' -H 'user-agent: ...'`
- **THEN** the parser returns `sessionKey=eyJ...; lastActiveOrg=abc`

#### Scenario: cURL command spanning multiple lines

- **WHEN** the user submits a curl command with `\` line continuations across multiple lines
- **THEN** the parser collapses the continuations before extraction
- **AND** returns the cookie value from the `-H 'cookie: …'` flag

#### Scenario: cURL command using --header

- **WHEN** the user submits `curl --header "Cookie: sessionKey=eyJ..." 'https://claude.ai/...'`
- **THEN** the parser returns `sessionKey=eyJ...` (case-insensitive on the header name)

### Requirement: Parser rejects input without sessionKey

The parser SHALL reject any input whose resolved cookie string does not contain a `sessionKey=` segment, returning a structured error that names the accepted input shapes and SHALL NOT cause any Keychain write.

#### Scenario: Pasted text contains no sessionKey

- **WHEN** the user submits a string that does not contain `sessionKey=`
- **THEN** the parser returns an error explaining accepted formats (raw header, `Cookie:`-prefixed, or curl command)
- **AND** the Keychain is not modified

#### Scenario: cURL command has no Cookie header

- **WHEN** the user submits a curl command that has no `-H 'cookie: …'` or `--header 'Cookie: …'` flag
- **THEN** the parser returns an error
- **AND** the Keychain is not modified

### Requirement: tokentrace URL scheme registration

The application SHALL register the `tokentrace` URL scheme via `Info.plist` `CFBundleURLTypes` and SHALL route URLs of the form `tokentrace://import?cookie=<urlencoded>` to a foreground confirmation flow. Other paths under the `tokentrace` scheme SHALL be ignored without state change.

#### Scenario: Receiving a well-formed import URL

- **WHEN** the operating system invokes TokenTrace with `tokentrace://import?cookie=sessionKey%3DeyJ...%3B%20lastActiveOrg%3Dabc`
- **THEN** the app activates, brings the main window to front, and opens the Settings tab
- **AND** the paste field is pre-filled with the URL-decoded cookie value
- **AND** the cookie is NOT written to Keychain at this point

#### Scenario: Receiving an import URL with no cookie parameter

- **WHEN** the OS invokes TokenTrace with `tokentrace://import` (missing query) or `tokentrace://import?cookie=` (empty value)
- **THEN** the app activates and surfaces an explanatory error in Settings
- **AND** the Keychain is not modified

#### Scenario: Receiving an import URL with an undecodable cookie

- **WHEN** the OS invokes TokenTrace with a `tokentrace://import?cookie=` URL whose value cannot be URL-decoded to a valid UTF-8 string
- **THEN** the app surfaces an error in Settings naming the failure
- **AND** the Keychain is not modified

#### Scenario: Receiving an unrecognised tokentrace path

- **WHEN** the OS invokes TokenTrace with `tokentrace://something-else` or any path other than `import`
- **THEN** the app may activate but does not modify any state
- **AND** the URL is not logged with its query string

### Requirement: URL scheme imports require foreground user confirmation

The application SHALL NOT silently write a cookie received via the `tokentrace://import` URL to the Keychain. The only path from URL-scheme reception to Keychain SHALL pass through an explicit user click on the Settings "Save" button.

#### Scenario: Hostile process attempts silent overwrite

- **WHEN** any local process invokes `open tokentrace://import?cookie=…` while TokenTrace is running with a valid cookie already stored
- **THEN** the existing Keychain cookie is unchanged until the user explicitly clicks "Save"
- **AND** the user sees the incoming cookie pre-filled in Settings before any save action is possible

#### Scenario: User dismisses the import without saving

- **WHEN** the import URL pre-fills Settings and the user closes the window or clicks "Cancel"
- **THEN** the Keychain is not modified
- **AND** the next time Settings opens, the paste field is empty

### Requirement: WebExtension cookie handoff

The TokenTrace WebExtension SHALL, when its toolbar action is activated while the user is signed into claude.ai, read claude.ai cookies via `browser.cookies.getAll({domain: "claude.ai"})`, build a header value by joining cookie `name=value` pairs with `; `, URL-encode the resulting string once, and hand off to the host application by opening `tokentrace://import?cookie=<encoded>`. The extension SHALL NOT display, persist, or transmit the cookie value to any destination other than the host application.

#### Scenario: Toolbar action with valid cookies

- **WHEN** the user clicks the extension toolbar icon while signed into claude.ai
- **THEN** the extension calls `browser.cookies.getAll({domain: "claude.ai"})`
- **AND** opens `tokentrace://import?cookie=<urlencoded-header>`
- **AND** does not show the cookie value in any extension UI

#### Scenario: Toolbar action with no cookies available

- **WHEN** the user clicks the toolbar icon and `browser.cookies.getAll` returns an empty list
- **THEN** the extension surfaces a message advising the user to sign into claude.ai first
- **AND** does not invoke the `tokentrace://` URL scheme

#### Scenario: Toolbar action with cookies but no sessionKey

- **WHEN** the cookie list returned by `browser.cookies.getAll` contains entries but none named `sessionKey`
- **THEN** the extension surfaces a "not signed in" message
- **AND** does not invoke the URL scheme

### Requirement: WebExtension minimum permissions

The WebExtension manifest SHALL declare only the permissions strictly required for cookie handoff: `cookies` permission and `https://claude.ai/*` host permission. The manifest SHALL NOT declare any content scripts, background fetch capability, broad host permissions, or any third-party origin.

#### Scenario: Manifest inspection at build time

- **WHEN** the manifest is validated as part of the build or AMO submission
- **THEN** `permissions` is exactly `["cookies"]`
- **AND** `host_permissions` is exactly `["https://claude.ai/*"]`
- **AND** `content_scripts` is absent or empty
- **AND** no other origin appears in any permission key

### Requirement: WebExtension distribution via AMO unlisted self-distribution

The extension SHALL be distributed exclusively as a Mozilla-signed `.xpi` artifact obtained via AMO unlisted self-distribution. The artifact SHALL be hosted by the project (e.g., GitHub Releases) and SHALL NOT be published to AMO listed search until a separate, recorded decision changes this requirement.

#### Scenario: Releasing a new extension version

- **WHEN** a new extension version is prepared for release
- **THEN** it is submitted to addons.mozilla.org marked "On your own" (self-distribution)
- **AND** the Mozilla-signed `.xpi` returned by AMO is published as a release asset by the project
- **AND** the version does not appear in the public AMO search index

#### Scenario: User installs the extension

- **WHEN** a user follows the published install instructions
- **THEN** they install the signed `.xpi` via `about:addons` → "Install Add-on From File"
- **AND** the install is permanent and survives browser restarts

