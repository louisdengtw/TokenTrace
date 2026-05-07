## ADDED Requirements

### Requirement: Resolve organization ID from session cookie

The system SHALL determine the user's organization ID by first inspecting the stored session cookie for a `lastActiveOrg=<id>` segment, and falling back to a `GET https://claude.ai/api/bootstrap` request that reads `account.lastActiveOrgId` from the JSON response.

#### Scenario: Cookie contains lastActiveOrg

- **WHEN** the stored cookie includes a `lastActiveOrg=<uuid>` pair
- **THEN** the system extracts and uses that UUID as the organization ID
- **AND** does not issue a bootstrap request

#### Scenario: Bootstrap fallback succeeds

- **WHEN** the stored cookie has no `lastActiveOrg` segment
- **AND** the bootstrap request returns HTTP 200 with a JSON body containing `account.lastActiveOrgId`
- **THEN** the system uses that value as the organization ID

#### Scenario: Bootstrap returns no account (auth failure)

- **WHEN** the bootstrap request succeeds with HTTP 200 but the JSON body has `account: null` or is missing the field
- **THEN** the system marks the session as expired and surfaces "Session expired — please re-sign in" to the user

### Requirement: Fetch usage data via authenticated request

The system SHALL `GET https://claude.ai/api/organizations/{org_id}/usage` with the full session cookie as the `Cookie` header and standard browser-like `Accept`, `Origin`, `Referer`, and `User-Agent` headers, parsing the JSON response into utilization values per bucket.

#### Scenario: Successful fetch with all three buckets

- **WHEN** the response body contains `five_hour`, `seven_day`, and `seven_day_sonnet` objects
- **THEN** the system parses `utilization` (0–100) and `resets_at` (ISO-8601) from each
- **AND** stores one sample per bucket with the current poll timestamp

#### Scenario: Pro features absent

- **WHEN** the response body omits `seven_day_sonnet`
- **THEN** the system parses only `five_hour` and `seven_day`
- **AND** does not record a `seven_day_sonnet` sample
- **AND** sets a `hasWeeklySonnet` flag to false for UI consumption

#### Scenario: Unparseable response

- **WHEN** the response body is not valid JSON or is missing both `five_hour` and `seven_day`
- **THEN** the system logs the response prefix (first 300 bytes) and the HTTP status
- **AND** surfaces "Parse error" to the user
- **AND** does not write any samples to the store

### Requirement: Detect authentication failure across multiple signals

The system SHALL treat any of the following as a session-expired condition: HTTP 401 or 403; final URL path containing `/login`; non-JSON response Content-Type when JSON was expected.

#### Scenario: Status 401

- **WHEN** the response has HTTP status 401 or 403
- **THEN** the system marks the session as expired and surfaces "Session expired — please re-sign in"

#### Scenario: Redirect to login

- **WHEN** the final URL path of the response contains `/login`
- **THEN** the system marks the session as expired (regardless of status code)

#### Scenario: HTML response when JSON expected

- **WHEN** the response Content-Type is `text/html` and the request was to a `/api/...` endpoint
- **THEN** the system marks the session as expired

### Requirement: Store and retrieve session cookie via Keychain

The system SHALL persist the user-provided session cookie in the macOS Keychain (generic password class, service `dev.louisdeng.tokentrace.session`) and read it from there on every fetch. The cookie SHALL NOT be persisted in `UserDefaults` or any plaintext file.

#### Scenario: Saving a freshly-pasted cookie

- **WHEN** the user pastes a cookie into the Settings UI and clicks Save
- **THEN** the cookie is written to the Keychain
- **AND** the in-memory copy is updated for immediate use by the next fetch

#### Scenario: Clearing the cookie

- **WHEN** the user clicks "Sign out" in the Settings UI
- **THEN** the Keychain entry is deleted
- **AND** the in-memory cookie is cleared
- **AND** the menu bar shows a sign-in prompt instead of a percentage

#### Scenario: Keychain prompts for access

- **WHEN** the operating system prompts for Keychain access on first read
- **THEN** the user is prompted to "Always Allow" so subsequent fetches do not block
