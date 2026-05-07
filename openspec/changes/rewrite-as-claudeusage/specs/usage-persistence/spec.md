## ADDED Requirements

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

The system SHALL insert one row into the `samples` table for each bucket (`five_hour`, `seven_day`, `seven_day_sonnet`) that the API response contains, using the poll timestamp (unix epoch seconds) as `ts`. Concurrent inserts at the same `(ts, bucket)` SHALL be resolved via `INSERT OR REPLACE`.

#### Scenario: Pro user, all three buckets present

- **WHEN** a successful fetch returns `five_hour`, `seven_day`, and `seven_day_sonnet`
- **THEN** three rows are inserted, one per bucket, all sharing the same `ts`

#### Scenario: Non-Pro user, two buckets

- **WHEN** a successful fetch returns only `five_hour` and `seven_day`
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
