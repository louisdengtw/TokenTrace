# usage-persistence Delta

## MODIFIED Requirements

### Requirement: Insert one row per bucket per successful poll

The system SHALL insert one row into the `samples` table for each bucket the parsed API response contains — the fixed windows (`five_hour`, `seven_day`) plus any model-scoped weekly buckets — using the poll timestamp (unix epoch seconds) as `ts`. Scoped buckets SHALL be stored with the bucket key `weekly_scoped:<model display name>`. Concurrent inserts at the same `(ts, bucket)` SHALL be resolved via `INSERT OR REPLACE`.

#### Scenario: Poll with a scoped Fable limit

- **WHEN** a successful fetch yields `five_hour`, `seven_day`, and a scoped sample for model "Fable"
- **THEN** three rows are inserted sharing the same `ts`, with bucket keys `five_hour`, `seven_day`, and `weekly_scoped:Fable`

#### Scenario: Poll without scoped limits

- **WHEN** a successful fetch yields only `five_hour` and `seven_day`
- **THEN** exactly two rows are inserted

#### Scenario: Duplicate insert at same timestamp

- **WHEN** a fetch attempts to insert a row whose `(ts, bucket)` already exists
- **THEN** the existing row is replaced (no UNIQUE-constraint error)

## ADDED Requirements

### Requirement: Legacy Sonnet rows merge into the Sonnet scoped series

Historical rows stored under the legacy bucket key `seven_day_sonnet` SHALL be readable without migration: a time-range query for the scoped bucket of model "Sonnet" SHALL match rows stored under either `seven_day_sonnet` or `weekly_scoped:Sonnet`, returned as one series in ascending `ts` order.

#### Scenario: Range spanning the key transition

- **WHEN** the store contains pre-change rows with bucket `seven_day_sonnet` and post-change rows with bucket `weekly_scoped:Sonnet`, and the dashboard queries the Sonnet scoped series over a range covering both
- **THEN** all matching rows from both keys are returned as a single ascending-`ts` series

### Requirement: Enumerate scoped models present in a range

The system SHALL expose a query returning the distinct scoped model names having at least one sample within a `(startTs, endTs)` window, treating legacy `seven_day_sonnet` rows as model "Sonnet".

#### Scenario: Range containing two scoped models

- **WHEN** the range contains legacy `seven_day_sonnet` rows and `weekly_scoped:Fable` rows
- **THEN** the query returns ["Sonnet", "Fable"] (order deterministic, e.g. sorted)

#### Scenario: Range with no scoped samples

- **WHEN** the range contains only `five_hour` and `seven_day` rows
- **THEN** the query returns an empty list
