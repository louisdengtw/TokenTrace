# claude-api-integration Delta

## MODIFIED Requirements

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
