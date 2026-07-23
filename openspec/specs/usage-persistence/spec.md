# usage-persistence Specification

## Purpose

SQLite-backed time-series store for TokenTrace usage samples. Database lives at `~/Library/Application Support/dev.louisdeng.tokentrace/usage.sqlite`. Each successful poll inserts one row per bucket; reset events are derived at query time by walking time-ordered samples. Time-range queries feed the dashboard. Write failures are logged and tolerated — they never break polling or the in-memory `latestSample`.

## Requirements

### Requirement: SQLite-backed sample store at user Application Support path

The system SHALL persist usage samples in a SQLite database at `~/Library/Application Support/dev.louisdeng.tokentrace/usage.sqlite`, creating the directory and database with the documented schema if either is missing.

#### Scenario: First launch on a fresh system

- **WHEN** the application starts and the database file does not exist
- **THEN** the parent directory is created (with intermediate directories as needed)
- **AND** the database file is created
- **AND** the `samples` table and `idx_samples_bucket_ts` index are created via DDL

#### Scenario: Subsequent launch with existing database

- **WHEN** the application starts and the database file already exists
- **THEN** the database is opened in read-write mode
- **AND** no destructive operations are run against it

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

### Requirement: Time-range queries for dashboard rendering

The system SHALL expose a query that returns rows for a given bucket within a `(startTs, endTs)` window, ordered by `ts` ascending, suitable for direct consumption by SwiftUI Charts.

#### Scenario: Last-24h query

- **WHEN** the dashboard requests the `five_hour` bucket with start = now - 86400 seconds and end = now
- **THEN** all matching rows are returned in ascending `ts` order
- **AND** the `idx_samples_bucket_ts` index is used (no full table scan)

#### Scenario: Empty range

- **WHEN** the requested range contains no samples
- **THEN** an empty array is returned (no error)

### Requirement: Reset event detection at query time

The system SHALL identify reset events for a given bucket by walking the time-ordered samples and emitting an event between sample N and sample N+1 whenever `samples[N+1].resets_at > samples[N].resets_at`. The event's display timestamp SHALL be `samples[N].resets_at`.

#### Scenario: Single reset between two polls

- **GIVEN** sample A at t=100 with resets_at=200, and sample B at t=210 with resets_at=400
- **WHEN** the dashboard queries reset events
- **THEN** one event is emitted with display timestamp 200

#### Scenario: No reset within the range

- **WHEN** all samples in the range share the same `resets_at`
- **THEN** no reset events are emitted

#### Scenario: Multiple consecutive resets

- **WHEN** three or more consecutive samples each have a strictly increasing `resets_at`
- **THEN** one event is emitted per increase

### Requirement: Tolerate write failures without crashing

The system SHALL log SQLite write errors and continue running. A failed insert SHALL NOT terminate the polling loop or prevent the in-memory `latestSample` from updating.

#### Scenario: Disk full during insert

- **WHEN** an `INSERT` returns `SQLITE_FULL` or any other error
- **THEN** the error is logged with the failing SQL and the bucket
- **AND** the menu bar status item still updates from the in-memory sample
- **AND** the next poll is still scheduled

#### Scenario: Database file locked

- **WHEN** an `INSERT` returns `SQLITE_BUSY`
- **THEN** the system retries up to 3 times with a short delay before logging and giving up

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
