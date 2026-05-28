## ADDED Requirements

### Requirement: Local transcript ingestion

The system SHALL ingest Claude Code's local JSONL transcripts found under `~/.claude/projects/`, recursively to whatever directory depth is required to reach per-session subagent transcripts at `<project-encoded>/<session-uuid>/subagents/agent-*.jsonl` (depth 4 from `~/.claude/projects/` on current CC versions). One row SHALL be written per JSONL line where `type == "assistant"`, `message.model != "<synthetic>"`, and `message.usage` is present.

The ingester SHALL run on a background queue and SHALL be triggered (a) automatically when the Dashboard's Claude Code tab becomes visible, and (b) on demand via a "Refresh" affordance in that tab.

#### Scenario: Cold ingest of a project with assistant lines

- **GIVEN** `~/.claude/projects/-Users-x-foo/<uuid>.jsonl` contains 100 lines, 80 of which are `type: "assistant"` with non-synthetic models and non-empty usage
- **WHEN** the ingester runs for the first time
- **THEN** exactly 80 rows are inserted into `cc_message`
- **AND** the remaining 20 lines (other `type`s, or `<synthetic>` lines, or assistant lines with no usage) produce no rows

#### Scenario: Subagent transcripts are included

- **GIVEN** `~/.claude/projects/-Users-x-foo/<session-uuid>/subagents/agent-abc.jsonl` exists with 30 qualifying assistant lines
- **WHEN** the ingester runs
- **THEN** 30 rows are inserted from that file, attributed by the `cwd` field on each line

#### Scenario: Non-JSONL siblings are ignored

- **GIVEN** the project directory contains a `*.meta.json` file beside a `*.jsonl` file
- **WHEN** the ingester runs
- **THEN** the `.meta.json` file is not opened or parsed

### Requirement: Project identity from JSONL `cwd` field

Each ingested record SHALL be attributed to a project by the `cwd` value on the JSONL line itself, NOT by the encoded directory name in `~/.claude/projects/`.

#### Scenario: Hyphen-ambiguous directory name

- **GIVEN** a directory named `-Users-louisdeng-workspace-bmo-analysis-add-mac-dev` containing lines whose `cwd` is `/Users/louisdeng/workspace/bmo-analysis-add-mac-dev`
- **WHEN** the ingester runs
- **THEN** the inserted rows carry `cwd = "/Users/louisdeng/workspace/bmo-analysis-add-mac-dev"` verbatim, not a guessed split

#### Scenario: Mixed cwds within one JSONL file

- **GIVEN** a JSONL file where the first 10 assistant lines have `cwd = "/a"` and the next 10 have `cwd = "/b"` (user `cd`-ed mid-session)
- **WHEN** the ingester runs
- **THEN** 10 rows are inserted with `cwd = "/a"` and 10 with `cwd = "/b"`

### Requirement: Idempotent re-ingest

The ingester SHALL be safe to run repeatedly: re-running over already-processed data SHALL NOT produce duplicate rows in `cc_message`.

#### Scenario: Re-run after a clean prior run

- **GIVEN** the ingester previously processed a JSONL file and inserted 80 rows
- **WHEN** the ingester runs again on the same unchanged file
- **THEN** the total row count in `cc_message` for that file is still 80
- **AND** no `INSERT` errors are raised (duplicates are silently ignored via the per-line `uuid` primary key)

#### Scenario: Re-run after a crash mid-file

- **GIVEN** an earlier ingest crashed after inserting rows for the first 40 of 80 qualifying lines, leaving no checkpoint entry persisted
- **WHEN** the ingester runs again
- **THEN** all 80 rows are present, with the 40 from the first run preserved and the remaining 40 inserted (re-attempts for the first 40 are no-ops)

### Requirement: Incremental ingest with byte-offset checkpoints

For each JSONL file, the ingester SHALL persist a checkpoint `(file_path, byte_offset, file_size, mtime)` after successfully processing it to end-of-file. Subsequent runs SHALL resume reading from `byte_offset` if the file's current `size >= byte_offset` and current `mtime` is not earlier than the stored `mtime`. Otherwise the ingester SHALL discard the checkpoint and re-read the file from offset 0.

#### Scenario: File grows after first ingest

- **GIVEN** a JSONL file had 1000 lines (byte_offset = 250000) at the previous run
- **WHEN** 50 new lines are appended (file size now 263000) and the ingester runs
- **THEN** only the bytes from offset 250000 onward are read and parsed
- **AND** rows for the new qualifying assistant lines are inserted
- **AND** the checkpoint is updated to the new size and mtime

#### Scenario: File was truncated or rewritten

- **GIVEN** a JSONL file had byte_offset = 250000 in the checkpoint but its current size is 100000 (i.e. shrunk)
- **WHEN** the ingester runs
- **THEN** the stored checkpoint is discarded
- **AND** the file is rescanned from offset 0
- **AND** existing rows in `cc_message` remain (deduplicated by `uuid`)

### Requirement: Partial last-line safety during active CC writes

If the ingester reads a JSONL file while the Claude Code CLI is actively appending to it, the final partial (non-newline-terminated) bytes SHALL NOT be parsed or inserted. The persisted `byte_offset` SHALL remain at the position of the last newline seen.

#### Scenario: File ends mid-line

- **GIVEN** a JSONL file's last 200 bytes form an incomplete JSON object with no trailing newline
- **WHEN** the ingester runs
- **THEN** all complete lines before that partial tail are processed normally
- **AND** no insert is attempted for the partial bytes
- **AND** the persisted `byte_offset` equals the position of the last newline character
- **AND** the next ingest run picks up the partial bytes plus whatever else CC appended after them

### Requirement: Ingester does not read message content

The ingester SHALL extract only the fields it needs (`type`, `uuid`, `timestamp`, `cwd`, `isSidechain`, `sessionId`, `requestId`, `message.model`, `message.usage`). It SHALL NOT decode or load `message.content` into memory beyond the raw byte buffer required for line-by-line JSON parsing.

#### Scenario: Content key is present but never decoded

- **GIVEN** an assistant line whose `message.content` is a multi-megabyte array
- **WHEN** the ingester processes that line
- **THEN** the row inserted into `cc_message` contains no copy of the content
- **AND** no field, log, or telemetry surface exposes the content

### Requirement: Weighted token volume

For any record `r`, the system SHALL compute its weighted token volume as:

`weighted(r) = 1.0 × r.input_tokens + 5.0 × r.output_tokens + 1.25 × r.cache_creation_tokens + 0.1 × r.cache_read_tokens`

These weights are constants in code, derived from public Anthropic API pricing ratios. The number is a *relative attribution proxy*, not a dollar cost and not a direct measure of subscription quota burn. Queries that present a single number per project per time bucket SHALL use this formula. UI surfaces that display the number SHALL label it "weighted tokens" or "weighted token volume" (not "cost" and not "tokens" alone).

#### Scenario: Computed total for a representative record

- **GIVEN** a record with `(input, output, cache_create, cache_read) = (100, 50, 200, 1000)`
- **WHEN** weighted volume is computed
- **THEN** the result equals `100·1.0 + 50·5.0 + 200·1.25 + 1000·0.1 = 700.0`

#### Scenario: Cache-heavy record reflects low cache_read weight

- **GIVEN** a record with `(0, 0, 0, 100000)`
- **WHEN** weighted volume is computed
- **THEN** the result equals `10000.0` (not `100000.0`)

### Requirement: Filtering synthetic and empty-usage records

The ingester SHALL skip JSONL lines where any of the following is true:
- `type != "assistant"`
- `message.model == "<synthetic>"`
- `message.usage` is absent or is `null`

Skipped lines SHALL still advance the read offset within the file, so the byte-offset checkpoint remains correct.

#### Scenario: Synthetic model

- **GIVEN** an assistant line with `message.model == "<synthetic>"` and an all-zero `usage` block
- **WHEN** the ingester processes the file
- **THEN** no row is inserted for that line
- **AND** the byte offset advances past it

#### Scenario: Assistant line with no usage block

- **GIVEN** an assistant line where `message.usage` is `null`
- **WHEN** the ingester processes the file
- **THEN** no row is inserted

### Requirement: Sidechain rows attributed to the parent project via `cwd`

Subagent (sidechain) rows from `<session>/subagents/agent-*.jsonl` files SHALL be ingested without filter. Their `cwd` field carries the parent session's project cwd, so the standard cwd-based attribution naturally merges their token consumption into the parent project's totals. The system SHALL record `isSidechain` from each JSONL line into `cc_message.is_sidechain` (1 if true, 0 otherwise) for diagnostic purposes; v1 aggregation queries SHALL sum sidechain and non-sidechain rows together.

#### Scenario: Subagent line merges into parent project

- **GIVEN** a subagent file `~/.claude/projects/-Users-x-foo/<sid>/subagents/agent-X.jsonl` whose assistant lines carry `isSidechain: true`, `cwd = "/Users/x/foo"`, and 500 output tokens
- **WHEN** the project-breakdown query is executed for project `/Users/x/foo`
- **THEN** the weighted contribution of those subagent lines appears in `/Users/x/foo`'s totals
- **AND** no synthesised "subagent" project appears as a separate series

#### Scenario: is_sidechain column captured for forensics

- **GIVEN** a mix of sidechain and non-sidechain rows for the same project
- **WHEN** an operator inspects the `cc_message` table directly
- **THEN** the `is_sidechain` column distinguishes the two row types
- **AND** v1 query APIs do not expose any sidechain split

### Requirement: Project aggregation query with zero-fill

The store SHALL expose a query of the form `tokensByProject(from: Date, to: Date, bucket: TimeBucket) -> [ProjectSeries]`, where `bucket` is one of a small fixed set (e.g. `hour`, `day`, `week`) chosen automatically by the caller based on the active range. Each `ProjectSeries` carries the project's `cwd`, its effective display name (alias if set, otherwise synthesised from `cwd`), and an ordered list of buckets covering **every** bucket boundary in `[from, to]`. Buckets with no data for a project SHALL be present with zero values for all four token components and zero weighted volume. This zero-fill makes the result directly stackable as an area chart without visual gaps.

A project SHALL appear in the result if and only if it has at least one row with non-zero data anywhere within `[from, to]`. Projects with zero activity in the entire range are omitted.

#### Scenario: Two projects with overlapping but unequal activity

- **GIVEN** project `/a` has rows on days 1, 2, 3 and project `/b` has rows on days 2, 3, 4 within a 5-day range
- **WHEN** `tokensByProject(from:, to:, bucket: .day)` is called
- **THEN** the result contains exactly two `ProjectSeries`
- **AND** each series has exactly 5 buckets, one per day in the range
- **AND** `/a`'s bucket for day 4 has zero values, and `/b`'s bucket for day 1 has zero values

#### Scenario: Project absent from the entire range is omitted

- **GIVEN** project `/c` has rows only outside the requested range
- **WHEN** the query is executed
- **THEN** the result contains no `ProjectSeries` for `/c`

#### Scenario: Alias merges two cwds with the same display name

- **GIVEN** rows exist for `cwd = "/a"` (alias `"TT"`) and `cwd = "/b"` (alias `"TT"`)
- **WHEN** the query is executed
- **THEN** the result contains a single `ProjectSeries` with `displayName = "TT"`
- **AND** that series' buckets contain the per-bucket sum of contributions from both cwds (with zero-fill applied to the merged series, not to the underlying cwds individually)

### Requirement: Project alias management

The system SHALL allow the user to set, edit, and delete a display name for any `cwd` observed in `cc_message`. Aliases SHALL be persisted in the `project_alias` SQLite table with `cwd` as primary key. A `cwd` without an alias SHALL be displayed using a synthesised label derived from its trailing path components; how many components are used is controlled by `AppSettings.ccProjectNameDepth` (default `1` — see the "Configurable project label depth" requirement below).

#### Scenario: Set an alias

- **WHEN** the user opens the alias sheet and sets `"/Users/x/workspace/TokenTrace"` to display name `"TT"`
- **THEN** subsequent chart legends and tooltips for that cwd show `"TT"` instead of the synthesised label
- **AND** the alias persists across app restarts

#### Scenario: Delete an alias

- **GIVEN** an alias `"TT"` exists for `"/Users/x/workspace/TokenTrace"`
- **WHEN** the user removes it via the alias sheet
- **THEN** the synthesised label (at the current `ccProjectNameDepth`) is used again
- **AND** no row for that cwd remains in `project_alias`

#### Scenario: cwd shorter than the configured depth

- **GIVEN** a `cwd` of `/foo` (only one non-empty path component) and `ccProjectNameDepth = 2`
- **WHEN** the synthesised label is computed
- **THEN** the label is `/foo` (the full cwd, since two components are not available)

### Requirement: Configurable project label depth

The number of trailing `cwd` path components used to synthesise a project's display name SHALL be controlled by `AppSettings.ccProjectNameDepth`. The setting accepts `1` or `2`; the default is `1`. The user SHALL be able to change it from the app's Settings sheet. Changes apply on the next aggregation query (in practice: next range change or next Refresh on the Claude Code tab).

#### Scenario: Default depth = 1

- **GIVEN** the setting has never been written (default 1)
- **WHEN** `tokensByProject` is called for a cwd `/Users/x/workspace/TokenTrace` with no alias
- **THEN** the returned series has `displayName == "TokenTrace"`

#### Scenario: Depth = 2

- **GIVEN** the user sets `ccProjectNameDepth` to 2 in Settings
- **WHEN** `tokensByProject` is called for the same cwd
- **THEN** the returned series has `displayName == "workspace/TokenTrace"`

#### Scenario: Out-of-range values clamp

- **WHEN** a value outside `1..2` is written (e.g. 0 or 5)
- **THEN** the setter clamps to the valid range; later reads return a value in `1..2`

### Requirement: Worktree fold into parent project

When `AppSettings.ccMergeWorktrees` is true (the default), the project-aggregation query SHALL fold cwds containing a `.worktree` or `.worktrees` path segment into the parent path. The folded series uses the parent path as its representative `cwd`, and the synthesised display name is derived from the parent path (subject to the depth setting). Aliases set on the parent SHALL be inherited by all of its folded worktrees. Disabling the setting SHALL keep worktree cwds as separate series.

The query for per-project model breakdown SHALL match the same fold semantics: when fold is on, it aggregates rows whose `cwd` equals the parent OR matches `<parent>/.worktree/%` OR matches `<parent>/.worktrees/%`. When fold is off, only the exact cwd's rows are included.

#### Scenario: Default fold

- **GIVEN** three source cwds with token data — `/x/repo`, `/x/repo/.worktree/branch`, `/x/repo/.worktrees/agent-uuid`
- **WHEN** `tokensByProject` runs with `ccMergeWorktrees = true`
- **THEN** the result contains exactly one series
- **AND** that series's `displayName` is derived from `/x/repo` (depth=1 ⇒ `"repo"`)
- **AND** the bucket sums combine all three sources

#### Scenario: Fold disabled

- **GIVEN** the same three source cwds
- **WHEN** `ccMergeWorktrees` is false
- **THEN** the result contains three separate series

#### Scenario: Alias on parent inherited by folded worktrees

- **GIVEN** rows exist for `/x/repo` and `/x/repo/.worktree/branch`
- **GIVEN** the user sets alias `"Repo"` on `/x/repo`
- **WHEN** `tokensByProject` runs with fold on
- **THEN** a single series is returned with `displayName == "Repo"`

#### Scenario: Model breakdown sweeps worktree descendants when fold is on

- **GIVEN** a folded project where the parent and its worktrees contain a mix of Opus and Sonnet rows
- **WHEN** the CC tab's model split is computed for the folded series
- **THEN** the Opus/Sonnet ratio reflects rows across the parent AND its `.worktree(s)/...` descendants
- **AND** when fold is off, the ratio reflects only the exact representative cwd's rows

### Requirement: Ingest does not block the UI

The ingest operation SHALL execute off the main thread. While ingest is running, the Claude Code tab SHALL remain interactive: range chips SHALL be clickable, the alias sheet SHALL openable, and previously-queried data SHALL continue to render.

#### Scenario: Cold ingest on first launch

- **GIVEN** the user has never opened the Claude Code tab and `~/.claude/projects/` contains 50,000 qualifying lines
- **WHEN** the user opens the tab
- **THEN** the tab renders an "Indexing…" indicator
- **AND** the user can switch back to the Subscription tab and interact with it normally during the ingest
- **AND** when ingest completes, the Claude Code tab updates to show the project breakdown

#### Scenario: Incremental ingest on tab re-entry

- **GIVEN** ingest has previously completed and only a handful of new JSONL lines exist
- **WHEN** the user re-opens the Claude Code tab
- **THEN** no "Indexing…" indicator is shown (or it appears for less than ~200 ms and disappears)
- **AND** the new lines appear in the chart without a perceptible delay
