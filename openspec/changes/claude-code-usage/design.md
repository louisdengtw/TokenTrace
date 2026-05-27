## Context

TokenTrace already persists subscription utilisation samples into `Application Support/dev.louisdeng.tokentrace/usage.sqlite` (table `samples`) and renders them in the Dashboard via SwiftUI Charts with a unified `RangePickerView`. The data path is stable.

This change adds a **second, independent data stream** sourced from `~/.claude/projects/**/*.jsonl` — the Claude Code CLI's local transcripts. Empirical survey of the owner's machine, **recursive walk** (2026-05-26):

- 354 MB, 678 JSONL files, ~46 k `type: "assistant"` lines.
- Subagent sessions live at depth 4: `<project-encoded>/<session-uuid>/subagents/agent-*.jsonl` — must recurse.
- Models in practice: `claude-opus-4-7` (~85%), `claude-sonnet-4-6` (~14%), `<synthetic>` (~0.4%, all-zero usage).
- `isSidechain: true` is **18.5% of all assistant lines (8,523 rows)** — all of them in `subagents/` files. *Earlier sampling that reported "0% sidechain" was wrong; it shallow-globbed `*/*.jsonl` and never entered `subagents/` sub-directories.*
- All sidechain rows carry the **parent project's `cwd` verbatim** (e.g. a subagent invoked from a session for `/Users/x/foo` writes lines with `cwd = "/Users/x/foo"`). This means cwd-based attribution naturally merges subagent token consumption into the parent project — no special filter is required to satisfy the "sidechain into parent" semantics.
- Sidechain rows are **NOT mirrored** into the parent JSONL file. Every sidechain `uuid` appears only in its `subagents/*.jsonl` file. Therefore recursive ingest adds 8,523 unique rows (not duplicates).
- Cross-file `uuid` collisions exist for non-sidechain reasons (resumed sessions, etc.): 5,241 cases (~11%) with identical payload (correctly deduped by `INSERT OR IGNORE`), and 54 cases (~0.1%) with diverging payload (rare CC edge cases — log a warning, accept the dedup).
- The `usage.iterations` array always has length 0 or 1; when present its sum equals the outer fields. Outer fields are authoritative.
- Each assistant line carries `uuid` (per-logical-message), `requestId`, `sessionId`, `timestamp` (ISO8601), `cwd`, `gitBranch`, `isSidechain`, and `message.model` + `message.usage`. Message *content* (`message.content`) is present but the ingester never reads it.

Existing constraints (post-change):

- macOS **14+** — this change bumps the platform floor from 13 to 14 (Decision 10) to get clean dual-Y-axis Swift Charts and `chartXSelection` (hover sync).
- No migration framework — schema is `Persistence/Schema.swift`'s `allDDL` array of `CREATE IF NOT EXISTS` statements iterated at `UsageStore.init`. New tables are added by appending DDL.
- `RangePreset` lives in `Models/RangeSelection.swift` as a `String`-backed `CaseIterable` enum (`last24h`, `last7d`, `last30d`, `all`). Adding a case is non-breaking for the persisted `Codable` form.
- `DashboardView`'s `range` state is already hoisted to the view level and persisted via `AppSettings.dashboardRangeSelection`. Tabs can share it trivially. `DashboardView.swift` currently uses `chartXSelectionIfAvailable` (a 13-vs-14 shim); after the floor bump this helper is redundant but is left in place for this change to avoid scope creep.

## Goals / Non-Goals

**Goals:**
- Ingest `~/.claude/projects/` JSONL incrementally and idempotently.
- One row per `type: "assistant"` line, keyed on `uuid` for dedup.
- Project identity = JSONL record's `cwd` field, verbatim.
- Display per-project token cost over time, stacked, with subscription utilisation visible on the same time axis.
- Range chip set extended by one preset (`90d`), shared with the existing Subscription tab.
- User-editable `cwd → display name` alias map, surfaced from a sheet in the CC tab header. No regex, no auto-merge.

**Non-Goals:**
- Dollar-denominated cost. Only "weighted token volume" via fixed weights — see Decision 6.
- File-system watcher / FSEvents. Re-scan happens on Dashboard open.
- Cross-machine ingest / sync.
- Per-session or per-message drilldown. Aggregates only.
- Reading `server_tool_use` (web_search / web_fetch counts). Captured in JSONL but ignored in v1; can be re-ingested later since data stays on disk.
- Anonymisation. Sharing limited to file export (Decision 11) — no share-sheet integration, no scheduled or emailed exports.

## Decisions

### Decision 1 — Project identity = JSONL `cwd` field, not encoded directory name

The directory name `~/.claude/projects/<encoded>/` is the cwd with `/` → `-` substitution, which is ambiguous on hyphens (`-Users-louisdeng-workspace-bmo-analysis-add-mac-dev` cannot reliably round-trip). The JSONL record's `cwd` field is the original unambiguous path.

**Consequence**: ingester reads `cwd` from each assistant line, not from the directory name. If multiple cwd values appear in a single JSONL file (unusual but possible if `claude` is invoked across `cd`s within one session), each line is attributed correctly. The directory name is used only for filesystem walking.

### Decision 2 — Incremental ingest with byte-offset checkpoints and `uuid` dedup

Strategy:

1. On Claude Code tab appearance (and on the manual "Refresh" button), recursively walk `~/.claude/projects/**/*.jsonl`. The recursion must reach depth 4 so that `<project>/<session-uuid>/subagents/agent-*.jsonl` files are included.
2. For each file, look up `(file_path)` in `cc_ingest_checkpoint`. If present and `stat.size >= checkpoint.byte_offset` and `stat.mtime` ≥ recorded mtime, resume from `byte_offset`. Otherwise rescan from 0.
3. Stream-parse from offset, **line-buffered, only past a confirmed newline**. If the read trails off mid-line (CC is actively appending), the partial bytes are NOT consumed and the recorded `byte_offset` remains at the last newline. The next ingest run picks up the partial line plus whatever was appended.
4. For each complete line where `type == "assistant"` AND `message.model != "<synthetic>"` AND `message.usage` is present, build a row keyed on `uuid` and `INSERT OR IGNORE INTO cc_message ...`.
5. After EOF, write `(file_path, file_size, mtime)` back to `cc_ingest_checkpoint`.

**Why `uuid` PK with `INSERT OR IGNORE` is correct here**:

| Pattern | Count on this machine | What happens with uuid PK |
|---|---|---|
| Subagent line, sole occurrence in `subagents/` file | 8,523 unique rows | Inserted once. ✓ |
| Subagent line mirrored to parent JSONL | 0 (never observed) | n/a |
| Same uuid, same payload, two non-subagent files (resumed sessions, etc.) | 5,241 | Second `INSERT` ignored — correct dedup. ✓ |
| Same uuid, different payload | 54 (~0.1%) | Second `INSERT` ignored; first-seen wins by walk order. We log a `uuidPayloadDivergence` counter for observability but do not block ingest. |

The 54-row edge is a known CC-side anomaly; loss is silent but bounded and observable.

**Privacy invariant**: the ingester reads `type`, `uuid`, `timestamp`, `cwd`, `isSidechain`, `sessionId`, `requestId`, and `message.{model, usage}`. It does **not** read `message.content` (the prompt/response text). The streaming parser projects only the required keys before constructing the row, so content never enters memory beyond the JSON byte buffer.

Performance budget on this machine (678 files, 46 k qualifying lines):
- Cold scan: target ≤ 10 s on M-class hardware. The original ≤ 3 s budget was hand-wavy under `JSONDecoder`-per-line; we relax it and rely on the visible "Indexing…" indicator.
- Incremental scan, no new data: ≤ 200 ms (678 `stat` calls + 678 checkpoint lookups).

Run on a background `DispatchQueue` so the UI doesn't block. Surface a spinner only on first run; subsequent runs are silent.

### Decision 3 — Filter `<synthetic>` and empty-usage rows; ingest sidechain unchanged

**Synthetic / empty-usage**: lines where `message.model == "<synthetic>"` (~0.4% of assistant lines, all-zero usage) or `message.usage` is null/missing are dropped at parse time and never reach SQLite. They have no diagnostic value at the aggregate level.

**Sidechain rows (subagent invocations)**: ingested without filter, attributed to the parent project via their `cwd` field (verified empirically — all 8,523 sidechain rows on this machine carry the parent's cwd). The `cc_message` row schema includes an `is_sidechain INTEGER NOT NULL DEFAULT 0` column so the data is captured; v1 query layer sums sidechain and non-sidechain together. This satisfies the product decision "subagent token consumption merged into the parent project" with zero extra logic.

If a future product decision splits sidechain out (e.g. a "subagent activity" sub-segment within each project's bar), the column is already there.

### Decision 4 — Ignore the `iterations` array, use outer `usage` fields

Across ~37 k assistant lines surveyed, `iterations` was always either `null` or a single-element array whose values matched the outer `usage.{input,output,cache_creation_input,cache_read_input}_tokens`. Storing both would be redundant. Persist only the four outer fields.

If a future CC version emits multi-iteration entries with diverging sums, we will revisit. The raw JSONL is preserved on disk, so re-ingest into a richer schema is always possible.

### Decision 5 — True dual-Y-axis overlay (single chart) on macOS 14

With the platform floor bumped to macOS 14 (Decision 10), Swift Charts exposes both `chartYScale` per series via `AxisMarks(position: .leading/.trailing)` and `chartXSelection(value:)` for hover. This is the cleanest expression of the product intent ("see attribution and subscription utilisation on the same time axis") and is what the user originally asked for.

The **Claude Code tab** renders **a single chart** with:

```
┌─────────────────────────────────────────────────────┐
│  Wgt tokens                            Util %       │
│      ▲                                      ▲       │
│      │ ▓▓▓▓░░▒▒▒▒  ← stacked area, per project,    │
│      │ ▓▓▓▓░░▒▒▒▒    weighted token volume         │
│      │ ⋯ ╱╲ ⋯⋯╱⋯╲   ← 5h util %, dotted amber       │
│      └────────────────────────────────────────►     │
│      Range = active RangeSelection                  │
└─────────────────────────────────────────────────────┘
```

- Left Y axis: weighted token volume, auto-scaled.
- Right Y axis: subscription utilisation, fixed 0–100%.
- One utilisation series shares the right axis: `five_hour`, rendered as a dotted amber line. `seven_day` is intentionally NOT overlaid here — the smooth ramp adds nothing on top of the 5h sawtooth plus the Peak 5h Util stat in the stats strip, and crowds the right axis. Decision logged after prototype iteration (commit `bbf5723`).
- `chartXSelection(value: $selectedDate)` drives the cursor → unified tooltip via `chartOverlay`.

For the **stacked area to render without visual artefacts at gaps**, the project-aggregation query MUST zero-fill missing buckets for each project that has any row in the active range (i.e. each project's series is rectangular in time over `[from, to]` at the chosen bucket granularity). The store, not the view, performs this zero-fill — see the spec requirement.

### Decision 6 — "Weighted token volume" (not "cost"), weights from API pricing ratios

The CC tab needs a single Y-axis number to stack and compare across projects. Calling it "cost" would mislead — the user is on a subscription, and Anthropic does not publish the quota formula that maps each token component to quota burn. API pay-as-you-go pricing ratios are the only public proxy.

The number is therefore named **"weighted token volume"** in the UI and code. Weights:

| Component | Weight |
|---|---|
| `input_tokens` | 1.0 |
| `output_tokens` | 5.0 |
| `cache_creation_input_tokens` | 1.25 |
| `cache_read_input_tokens` | 0.1 |

These constants live in `Models/CCWeightedVolume.swift` with an inline comment citing the Anthropic pricing source. Not user-tunable in v1. If pricing shifts meaningfully, ship a patch release; the change is one-line.

The CC view header includes a small caveat affordance (an info button or footnote) explaining that "weighted token volume" is a relative measure derived from API pricing ratios, not a direct measure of subscription quota burn.

The chart's stacked-area segments still show the **raw four token components in distinct colours within each project's band** (so cache hit rate is visible). Total band height = the weighted sum. The hover tooltip shows raw token counts plus the weighted total.

### Decision 7 — Add `last90d` to `RangePreset`

Append a `last90d` case between `last30d` and `all`. Label `"90d"`. `resolved(now:oldestSample:)` returns `now - 90·86400 ... now`. Codable round-trips by raw string; old persisted values (which never wrote `last90d`) decode unchanged.

The chip order in the picker becomes `24h · 7d · 30d · 90d · All`. No other call-sites need to change because `RangePreset.allCases` drives the UI.

### Decision 8 — Alias sheet, no Settings entry

A "Manage projects…" button in the CC tab header opens a modal sheet:

```
┌─ Project aliases ──────────────────────────────┐
│  cwd                                  alias    │
│  /Users/louisdeng/workspace/TokenTrace TT      │
│  /Users/louisdeng/workspace/bmo-analysis BMO   │
│  [+]                                           │
│                                       [Done]   │
└────────────────────────────────────────────────┘
```

Rows are `cwd → display name`. Editing is inline (`TextField` on the alias column). The cwd column shows all cwds observed in `cc_message`; rows with no alias fall back to a synthesised label (the last two path components, e.g. `workspace/TokenTrace`). Delete-to-revert is a row swipe action.

Persistence: new `project_alias` SQLite table (not `AppSettings`, because the count is unbounded and lives next to `cc_message`).

The user's last-active Dashboard tab is persisted via a NEW `AppSettings` key (`lastDashboardTab: String`, default `"subscription"`), separate from `dashboardRangeSelection`. Two unrelated pieces of state, two keys.

### Decision 9 — Schema additions (additive DDL)

Three new tables, all in `Persistence/Schema.swift`, appended to `allDDL`:

```sql
CREATE TABLE IF NOT EXISTS cc_message (
  uuid           TEXT    PRIMARY KEY,
  ts             INTEGER NOT NULL,         -- unix seconds, UTC
  cwd            TEXT    NOT NULL,
  model          TEXT    NOT NULL,
  input_tokens          INTEGER NOT NULL DEFAULT 0,
  output_tokens         INTEGER NOT NULL DEFAULT 0,
  cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens     INTEGER NOT NULL DEFAULT 0,
  session_id     TEXT    NOT NULL,
  request_id     TEXT,
  is_sidechain   INTEGER NOT NULL DEFAULT 0,
  file_path      TEXT    NOT NULL          -- source jsonl, for diagnostics
);
CREATE INDEX IF NOT EXISTS idx_ccm_ts          ON cc_message(ts);
CREATE INDEX IF NOT EXISTS idx_ccm_cwd_ts      ON cc_message(cwd, ts);

CREATE TABLE IF NOT EXISTS cc_ingest_checkpoint (
  file_path     TEXT    PRIMARY KEY,
  byte_offset   INTEGER NOT NULL,
  file_size     INTEGER NOT NULL,
  mtime         INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS project_alias (
  cwd          TEXT PRIMARY KEY,
  display_name TEXT NOT NULL
);
```

No backfill needed — `IF NOT EXISTS` makes first-launch-after-upgrade trivial. Existing `samples` table is untouched.

### Decision 11 — Export Report becomes tab-aware (two parallel sheets)

The existing "Export Report…" button lives on the Dashboard's global toolbar above the new TabView. When users on the Claude Code tab click it, their expectation is to export the visible tab — but the existing `ExportSheetView` and `ReportGenerator` only understand subscription buckets.

Three options were considered (post-prototype-gate):

1. Disable Export on the Claude Code tab with a "Coming in v2" affordance.
2. Move Export from the global toolbar to a per-tab header so the location signals scope.
3. Tab-aware dispatch on the existing toolbar button — same surface, different sheet by active tab.

**Option 3 chosen.** It preserves the toolbar's global look-and-feel while delivering the user's expected semantics, and the toolbar layout doesn't shuffle. The two sheets are kept as **separate views** (rather than one polymorphic sheet) because their input controls genuinely differ: Subscription needs bucket checkboxes; CC needs the project filter + the Include toggles (project totals + subscription overlay). Forcing one sheet to be both would create a polymorphism without value.

Approach:

- **Subscription path unchanged.** `ExportSheetView`, `ReportGenerator`, `report.html.template` — all preserved as-is.
- **CC path runs in parallel.** New `CCExportSheetView` (built during the prototype phase as a stub, plumbed in tasks), new `CCReportGenerator`, new `cc-report.html.template`.
- **Entry-point dispatch.** Toolbar button and File menu / ⌘E both read the currently-selected `DashboardTabKey` and present the matching sheet. The toolbar button label switches accordingly: `"Export Report…"` vs `"Export Claude Code…"`.
- **CC report content** mirrors the on-screen CC tab: header (title + resolved date range + duration) → stats strip (total / top project / peak 5h util) → stacked-area chart with dual Y axis (project breakdown left, optional subscription overlay right) → project totals list with mix-breakdown bars and Opus/Sonnet split → footer (source DB path + generation timestamp).
- **CC report assets** reuse the inlined `chart.umd.min.js` already bundled for `usage-export`. Chart.js can render stacked areas with two scales natively, so the dual-axis trick used in the live SwiftUI chart (rescale-and-relabel-trailing-axis) is unnecessary here.
- **PDF** flows through the same `PDFRenderer.renderHTMLToPDF(html:)` path as `usage-export`; no new WebKit code.
- **Defaults** match the live tab: title `"Claude Code Activity Report"`, format PDF, range `Last 7d`, both Include toggles ON. Per the existing usage-export spec, the sheet is stateless across opens — every open resets to defaults.
- **Projects section is informational, not interactive**, in v1. It lists every observed cwd in the selected range with a count in the section header; toggling or filtering at the project level is out of scope (no anti-feature controls that pretend to filter but don't).

**Two follow-up notes:**

1. (Future scaling) If a v2 report variant emerges (e.g. range-comparison, monthly-recap), the right move is to factor out a `ReportSheetChrome` view (header + Title + Format + RangePicker + Save panel + footer) and let each variant sheet supply only its body — not to keep adding fully-independent sheets. With three variants the polymorphism penalty starts to bite.
2. (Report-vs-screen intent) v1's CC report mirrors the on-screen Claude Code tab section-for-section. This is a deliberate v1 expedient: the user's mental model is the same between live view and exported artefact, and the same `frontend-design` pass can polish both. A future iteration can diverge — denser typography, additional aggregate sections, landscape print orientation — once practice shows the on-screen layout reads poorly on paper.

### Decision 12 — Configurable label depth + worktree fold

Real `~/.claude/projects/` data on the owner's machine includes ~50 distinct cwds covering worktrees (`<repo>/.worktree/<branch>`), agent worktrees (`<repo>/.worktrees/agent-<uuid>`), system tools (`/opt/...`), and the home dir itself. Showing every cwd as its own project row was both visually overwhelming and a real attribution problem (one logical project — say a repo and its worktrees — fragmenting into many low-volume rows). Two related decisions land in v1 to address it:

**Label depth setting.** `AppSettings.ccProjectNameDepth` (default `1`, valid `1..2`) controls how many trailing path components are used when synthesising a project's display name. Depth 1 — the new default — drops noisy parent prefixes ("DynaRAG" instead of "workspace/DynaRAG"). Depth 2 — the old default — is available for users whose monorepo layout means the last folder name isn't unique. Exposed in the Settings sheet's new "Claude Code" section. Aliases set in the Manage projects sheet always override the synthesised label, regardless of depth.

**Worktree fold.** `AppSettings.ccMergeWorktrees` (default `true`) folds cwds containing a `.worktree` or `.worktrees` segment into the parent path during aggregation. The fold happens **before** alias lookup, so an alias set on the parent is inherited by all of its worktrees automatically. The fold runs in `tokensByProject` and the matching pattern is also applied by `modelBreakdown(forCwd:includeWorktrees:)` so the Opus/Sonnet column reflects the parent + all its `.worktree(s)/...` descendants via a single SQL LIKE sweep. The representative cwd for a folded series is the *parent* path (not the first-seen worktree), so tooltips and downstream queries see the clean path.

The fold is opinionated about `.worktree(s)` segment names — they're the conventions both `git worktree` users and Claude Code's agent task system actually use. A false-positive match would require a non-worktree directory literally named `.worktree` or `.worktrees`; we accept that as vanishingly rare and out-of-scope for v1.

Disabling either setting (via the Settings sheet) takes effect on the next reload — typically the next range change or Refresh on the Claude Code tab.

### Decision 10 — Bump platform floor from macOS 13 to macOS 14

`Package.swift`'s `platforms: [.macOS(.v13)]` becomes `.macOS(.v14)`. Rationale:

- The CC tab's central UX is the time-axis overlay with hover-synchronised tooltips. The clean API for both — dual-Y-axis (`AxisMarks(position: .leading/.trailing)` with `chartYScale` per series) and `chartXSelection(value:)` — is macOS 14+.
- The Subscription tab's existing `chartXSelectionIfAvailable` shim (a `@available(macOS 14, *)` graceful-degradation helper) is now redundant. It's left in place for this change to avoid scope creep; a future cleanup change can remove it.
- The owner is the only known user, on macOS 26. There is no installed base impact.

The README and build script do not need to change — `xcodebuild` already inherits the platform from `Package.swift`.

## Module / file plan

| File | Status | Purpose |
|---|---|---|
| `Persistence/Schema.swift` | modified | append three `CREATE` statements to `allDDL` |
| `Persistence/CCUsageStore.swift` | new | `insertMessages([…])`, `tokensByProject(from:to:bucket:)`, `aliases()`, `setAlias(cwd:displayName:)` |
| `Services/CCUsageIngester.swift` | new | walk, checkpoint, parse, insert; called from Dashboard on appear and from a manual "Refresh" button |
| `Models/CCWeightedVolume.swift` | new | weight constants + `weightedTotal(...)` helper |
| `Package.swift` | modified | platforms `.macOS(.v13)` → `.macOS(.v14)` |
| `AppSettings.swift` | modified | add `lastDashboardTab`, `ccProjectNameDepth`, and `ccMergeWorktrees` keys |
| `MainWindow/SettingsView.swift` | modified | new "Claude Code" section: project label depth picker + worktree merge toggle (Decision 12) |
| `Models/RangeSelection.swift` | modified | add `last90d` case, `label`, resolution |
| `MainWindow/DashboardView.swift` | modified | wrap existing chart + new CCUsageView in a `TabView` |
| `MainWindow/CCUsageView.swift` | new | two-chart layout, range chip reused, "Manage projects…" button |
| `MainWindow/ProjectAliasSheet.swift` | new | the modal sheet |
| `MainWindow/CCStackedAreaChart.swift` | new | the upper sub-chart (factored out for clarity) |
| `MainWindow/CCExportSheetView.swift` | new | tab-aware export sheet for the Claude Code report (Decision 11) |
| `Services/CCReportGenerator.swift` | new | turn `CCUsageStore` + optional `UsageStore` query results into final HTML via the CC template |
| `Resources/cc-report.html.template` | new | Chart.js stacked-area + dual-axis + project totals list, sentinel-token substitution like the existing `report.html.template` |
| `DashboardView.swift` | modified (further) | tab-aware Export button (label + dispatch by `selectedTab`); File-menu / ⌘E uses the same dispatch |

Tests: `CCUsageIngesterTests` (fixture JSONL files in `Tests/Fixtures/cc-projects/` including a `subagents/` subdir and a deliberately-partial-trailing-line file), `CCWeightedVolumeTests` (table-driven), `RangeSelectionTests` (extend to cover 90d).

## Alternatives considered

- **Cost in $ instead of weighted-volume units** — rejected: subscription users have no $ exposure; numbers would feel authoritative when they are not. "Weighted token volume" is honest about being a proxy.
- **Stacked sub-charts sharing X axis instead of true overlay** — drafted as Decision 5 when the floor was macOS 13; abandoned after the macOS 14 bump (Decision 10) made the cleaner overlay available.
- **Live FSEvents watcher** — rejected: cost vs. value is poor for a Dashboard the user opens deliberately. A "Refresh" button covers the rare same-session re-check. If 678 stat calls per tab-open becomes painful, revisit.
- **`request_id` or composite `(uuid, file_path)` as primary key** — `uuid` PK with `INSERT OR IGNORE` is correct because the 5,241 cross-file uuid collisions on this machine are dedup intent (same logical message, written to multiple files). A composite PK would re-introduce double-counting that the simple PK avoids. The 54 same-uuid-different-payload edge is logged via a divergence counter; we accept silent first-seen-wins.
- **Filtering sidechain rows entirely (option A-i)** — rejected (owner picked A-iii). Sidechain represents real subagent work that consumed quota; merging into the parent project gives an honest project-level total.
- **Treating sidechain as a separate project (option A-ii)** — rejected: would require synthesising a label per session and would clutter the chart with many short-lived "project"s.
- **Storing `iterations` JSON blob** — rejected as redundant (Decision 4). Raw JSONL on disk is the fallback.
- **Storing `server_tool_use` counts** — captured in JSONL but ignored in v1 schema; can be added later without re-ingest impact (re-scan from offset 0 by clearing the checkpoint table).
- **Range chips replacing 24h with 90d instead of adding** — the user wanted both; 24h is useful for the subscription tab (5h windows are visible), 90d is useful for the CC tab.

## Risks

- **JSONL format drift.** If a future CC version renames `message.usage.input_tokens` or moves the field, the ingester silently writes zeros. Mitigation: a small assertion at parse time — if `message.usage` is present and the four expected token keys are all absent, log + count, surface as a warning banner in the CC tab.
- **`<JSONL appended mid-read>`.** The CLI may be actively writing a JSONL file when the ingester reads it. Decision 2 step 3 handles this: only complete (newline-terminated) lines are consumed; the partial trailing line is left for the next ingest. The byte offset stays at the last newline.
- **Very large `~/.claude/projects/`.** A user with 5 GB of transcripts may exceed the 10 s budget on cold start. Mitigation: cold scan runs on a background queue, the CC tab shows a "Indexing…" state, queries against partial data work fine.
- **Weighted-volume weights drift from real subscription burn.** Pricing-derived weights are a proxy. The chart's purpose is *attribution* ("which project consumed the most"), not absolute quota accounting. The UI caveat (Decision 6) tells the user that the CC-tab and Subscription-tab numbers are not on the same scale.
- **uuid-payload-divergence silent loss.** 54 cases (~0.1%) of same-uuid-different-payload exist on this machine. INSERT OR IGNORE silently keeps first-seen. The divergence counter surfaces growth in this number but does not block ingest.
- **Multiple cwd's in one session.** Possible if the user `cd`s within a `claude` session; per-line attribution handles it correctly but the synthesised "session" identity blurs.
- **`.worktree(s)` segment false positives.** A non-worktree directory literally named `.worktree` or `.worktrees` would be folded into its parent. Vanishingly rare on real installs (these names are git/CC conventions) but possible. If it ever bites, the user can disable `ccMergeWorktrees` in Settings.

## Open questions

1. Should the alias sheet allow grouping multiple cwds under one alias (many-to-one), or strictly one display name per cwd? Strict one-to-one is simpler and matches Decision 8's schema (`cwd PRIMARY KEY`); many-to-one needs a `group_id`. Recommend strict one-to-one for v1; the user can give two cwds the same `display_name` string and the query layer will sum them on display (no schema change needed).
2. Where does the legend live — inside the chart or below it? Below is safer for many-project cases (10+ projects scrolls horizontally instead of overflowing the plot). Defer to implementation.
