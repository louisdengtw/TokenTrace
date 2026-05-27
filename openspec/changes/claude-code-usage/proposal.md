## Why

The Dashboard answers "how close am I to my subscription limit?" but cannot answer "what is driving this peak?". The `claude.ai/api/.../usage` endpoint reports a single org-wide utilization number with no breakdown by activity, model, or project. When five-hour utilization crosses 80% the owner has no way to attribute it.

Claude Code (the CLI tool) writes a detailed local transcript for every assistant turn into `~/.claude/projects/<encoded-cwd>/<session>.jsonl`. Each line carries `model`, `cwd`, `timestamp`, and a full four-component token breakdown (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`). Ingesting that locally — alongside the subscription samples already in SQLite — turns the existing time series into something that can answer:

1. **"Which project consumed the most this week?"** — a pure local-files question, no joins needed.
2. **"During that 80% utilization window, what was I working on?"** — a join of CC tokens with the subscription series on the same time axis.

There is no plan to copy any existing GitHub repo for this; the upstream salvage in `ClaudeAPI.swift` (subscription endpoint) is unrelated to this feature, which operates entirely on local filesystem data.

## What Changes

- **Ingestion**: a new service recursively scans `~/.claude/projects/**/*.jsonl` (including the `<session>/subagents/` sub-directory where subagent transcripts live), parses every `type: "assistant"` line, and writes one row per assistant turn into SQLite. Resumes from a per-file byte offset checkpoint so re-runs are cheap.
- **Project identity**: keyed on the `cwd` field from the JSONL record (more reliable than the path-encoded directory name, which is ambiguous on hyphens). Subagent rows carry the parent project's `cwd`, so cwd-based attribution naturally merges subagent token consumption back into the parent project. User-editable display alias maps `cwd → display name`. **No auto-merge of git worktrees in v1** — the owner plans to migrate to `~/workspace/<repo>/.worktree/<branch>/` shortly, after which prefix collapse becomes obvious enough to revisit.
- **Token visualisation**: each project's contribution is rendered as a **stacked four-colour band** showing the four token components (input / output / cache_creation / cache_read). Total height is a "weighted token volume" — a fixed-weight linear combination derived from Anthropic API pricing ratios. This is a proxy for relative subscription-quota burn (the subscription's real quota formula is not public), not a dollar cost.
- **New Dashboard section**: a **time-axis overlay** chart — stacked area of per-project weighted token volume on the left axis, subscription utilization % as an overlaid line on the right axis, sharing one X axis. Hover surfaces the exact composition for that window. (This requires macOS 14+ Swift Charts APIs — see below.)
- **Range chips**: the existing unified `RangePickerView` gains a **90d** chip (the new view's most useful preset for trend-spotting), giving `24h / 7d / 30d / 90d / All` shared by both subscription and CC views.
- **Project alias UI**: minimal — a sheet opened from the CC view header. `cwd → display name` rows; delete-to-revert. No regex, no glob, no auto-grouping.
- **Platform floor bump**: minimum macOS is raised from **13 → 14** to access `chartXSelection` (hover) and the dual-Y-axis chart layout cleanly. The existing `chartXSelectionIfAvailable` shim in `DashboardView.swift` becomes redundant but is left alone in this change.
- **Tab-aware Export Report**: the Dashboard's "Export Report…" toolbar button (and File → Export / ⌘E) now dispatches by active tab. Subscription tab continues to open the existing `ExportSheetView` unchanged. Claude Code tab opens a new "Export Claude Code…" sheet that produces a portable HTML / PDF CC report (stats strip + per-project stacked area + project totals with mix breakdown + optional subscription utilisation overlay). The button label switches to match the active tab.

## Capabilities

### New Capabilities
- `claude-code-usage`: Ingest `~/.claude/projects/*/*.jsonl` incrementally into SQLite, aggregate by project and model, and expose a queryable time series with the same `from/to` shape as `usage-persistence`.

### Modified Capabilities
- `usage-dashboard`: Split into two tabs (Subscription / Claude Code) with a shared range selector. The Claude Code tab adds the project breakdown view (stacked area + subscription utilisation overlay on a dual Y axis) plus a stats strip and a project totals list with mix breakdown. Extend the shared range chip set to include 90d. (Alias persistence lives in the new `claude-code-usage` capability's SQLite tables, not `AppSettings` — see design Decision 8.)
- `usage-export`: Extend Export with a parallel Claude Code variant — a new export sheet, a new HTML template, and a tab-aware dispatch on the existing entry points (toolbar button, File menu, ⌘E). Subscription export behaviour and report content are preserved unchanged.

## Impact

- **New code**
  - `Services/CCUsageIngester.swift` — incremental JSONL scan, per-file offset checkpointing, line-by-line `type: "assistant"` parsing, batched inserts.
  - `Services/CCUsageStore.swift` — query API: `tokensByProject(from:to:granularity:)`, `tokensByModel(...)`, returning equivalent-cost-weighted aggregates plus raw four-component breakdown.
  - `MainWindow/CCUsageView.swift` — new SwiftUI tab: stats strip, single-chart stacked area + subscription utilisation overlay on a dual Y axis, and project totals list with mix breakdown. Header has a "Manage projects…" button that opens the alias sheet.
  - `MainWindow/ProjectAliasSheet.swift` — modal sheet listing `cwd → display name` rows, presented from the CC view header. No entry point from app Settings (keeps Settings minimal).
  - `MainWindow/CCExportSheetView.swift` — modal sheet for the Claude Code export (title / format / range / Include toggles / Projects list).
  - `Services/CCReportGenerator.swift` — query `CCUsageStore.tokensByProject` and optionally `UsageStore.query`, substitute the CC report template, return final HTML; PDF rendered via the existing `PDFRenderer` (`WKWebView.createPDF`) path.
  - `Resources/cc-report.html.template` — Chart.js-based stacked-area + dual-axis layout with the project totals list, reusing the existing inlined `chart.umd.min.js` asset.
- **Modified code**
  - `DashboardView.swift` — wrap the existing subscription chart and the new CCUsageView in a `TabView` with two tabs ("Subscription" / "Claude Code"). Range chip selection is shared between tabs via the existing persisted `AppSettings` key.
  - `RangePickerView` — add 90d chip; verify chip ordering and `RangeSelection` enum extension.
  - `UsageStore.swift` — additive DDL for new tables (`cc_message`, `cc_ingest_checkpoint`, `project_alias`).
- **Schema additions** (SQLite, additive, no migration risk to existing `samples`)
  - `cc_message(ts INTEGER, cwd TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER, cache_creation_tokens INTEGER, cache_read_tokens INTEGER, session_id TEXT, request_id TEXT, file_path TEXT)` with index on `(ts)` and `(cwd, ts)`.
  - `cc_ingest_checkpoint(file_path TEXT PRIMARY KEY, byte_offset INTEGER, last_seen_mtime INTEGER)`.
  - `project_alias(cwd TEXT PRIMARY KEY, display_name TEXT)`.
- **No external dependencies added.** Pure stdlib JSON + SQLite + SwiftUI Charts.
- **Performance budget**: on the owner's machine, `~/.claude/projects/` is 354 MB / 678 JSONL files / ~46 k qualifying assistant lines (recursive count, including `subagents/`). Initial full ingest target ≤ 10 s; incremental scan with no new content ≤ 200 ms.
- **Platform**: `Package.swift` `platforms` bumped from `.macOS(.v13)` to `.macOS(.v14)`. README / build script unchanged.
- **Out of scope for v1**:
  - **$ cost in dollars** — only "weighted token volume" relative units. Real billing is irrelevant for a subscription user.
  - **FSEvents / file-watcher** — incremental scan on Dashboard open is sufficient; live tailing is not worth the complexity.
  - **Auto-merging worktrees** via regex / git remote / common prefix — defer until the planned `.worktree/` directory migration, which makes prefix collapse trivial.
  - **Per-message / per-session drilldown** — only aggregates. Reading raw transcripts is out of scope.
  - **Cross-machine merge** — `~/.claude` is per-machine; users with multiple machines are out of scope.
  - **CC export advanced options** — v1 always includes every project observed in the selected range. No per-project filter in the sheet, no presets, no scheduled export, no share-sheet send.
