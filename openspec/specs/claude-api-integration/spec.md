# claude-api-integration Specification

## Purpose

Reverse-engineered claude.ai web API client for TokenTrace: resolve `org_id` (cookie inspection then `/api/bootstrap` fallback), fetch usage from `/api/organizations/{org_id}/usage`, parse the fixed-window buckets (`five_hour`, `seven_day`) plus any dynamic model-scoped weekly buckets from the response `limits[]` array (with legacy `seven_day_sonnet` folded into the Sonnet scoped series), detect authentication failure across multiple signals (HTTP 401/403, redirect-to-login, HTML-when-JSON-expected), and persist the user-supplied session cookie in the macOS Keychain.

## Requirements

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

Fixed-window buckets (`five_hour`, `seven_day`) SHALL be read from the top-level response objects when present and non-null; when a top-level key is missing or null, the system SHALL fall back to the matching `limits[]` entry (`kind == "session"` for `five_hour`, `kind == "weekly_all"` for `seven_day`), using its `percent` as utilization and its `resets_at`.

Model-scoped weekly buckets SHALL be read from the `limits[]` array: every entry with `kind == "weekly_scoped"` and a non-empty `scope.model.display_name` SHALL produce one scoped sample carrying that display name. Entries lacking a model display name SHALL be skipped and logged. A non-null legacy top-level `seven_day_sonnet` object SHALL also parse as the scoped sample for model "Sonnet"; if both sources yield the same model, the `limits[]` entry wins.

The parse result SHALL expose the ordered, deduplicated list of scoped model names present in the response for UI consumption.

#### Scenario: Current API shape with a scoped Fable limit

- **WHEN** the response contains top-level `five_hour` and `seven_day` objects, `seven_day_sonnet: null`, and a `limits[]` array whose `weekly_scoped` entry has `scope.model.display_name == "Fable"` with `percent` and `resets_at`
- **THEN** the system parses `five_hour` and `seven_day` utilization from the top-level objects
- **AND** records one scoped sample for model "Fable" with the entry's `percent` as utilization
- **AND** does NOT record any sample for `seven_day_sonnet`
- **AND** reports `["Fable"]` as the scoped model list

#### Scenario: Legacy API shape without limits array

- **WHEN** the response contains top-level `five_hour`, `seven_day`, and a non-null `seven_day_sonnet` object, and no `limits[]` array
- **THEN** the system parses all three as before, with `seven_day_sonnet` recorded as the scoped sample for model "Sonnet"
- **AND** reports `["Sonnet"]` as the scoped model list

#### Scenario: No scoped limit present

- **WHEN** the response has `seven_day_sonnet: null` and no `weekly_scoped` entry in `limits[]`
- **THEN** the system parses only `five_hour` and `seven_day`
- **AND** reports an empty scoped model list

#### Scenario: Top-level keys absent, limits fallback

- **WHEN** the response omits top-level `five_hour` and `seven_day` but `limits[]` contains `session` and `weekly_all` entries
- **THEN** the system records `five_hour` and `seven_day` samples from those entries' `percent` and `resets_at`

#### Scenario: Unparseable response

- **WHEN** the response body is not valid JSON or yields neither a `five_hour` nor a `seven_day` sample from any source
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
