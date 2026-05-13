## Context

TokenTrace already persists every poll into `Application Support/dev.louisdeng.tokentrace/usage.sqlite` and renders a live Dashboard via SwiftUI Charts. The data path (`UsageStore.query(bucket:from:to:)` + `ResetDetection.detect(_:)`) is stable and reused across capabilities. What is missing is a way to produce a **portable artifact** from that data — something the owner can attach to a report or share without TokenTrace installed.

The Dashboard's current range selector (`DashboardRange` enum + segmented `RangePicker`) is hard-coded to four presets and resets to `last7d` on every launch (it lives in `@State`, not `AppSettings`). The Export feature needs custom date ranges anyway, so this change unifies the range-selection UX rather than letting Dashboard and Export drift apart.

Relevant constraints:
- macOS 13+ (SwiftUI Charts), self-signed/ad-hoc signed local builds.
- Menu-bar-first app; main window is opened on demand. There is **no existing File menu / NSSavePanel scaffolding**.
- AppSettings currently exposes only `notificationsEnabled` + `openAtLoginEnabled` and is intentionally minimal per the `app-settings` spec.
- No remote/back-end. Pure-local app.

## Goals / Non-Goals

**Goals:**
- Produce a single self-contained `.html` file viewable offline in any modern browser.
- Reuse the existing data layer (`UsageStore`, `ResetDetection`) unchanged.
- Provide one unified `RangePickerView` used by both Dashboard and Export.
- Persist Dashboard range across launches; do NOT persist Export range.
- Leave the door open for a quality pass on the HTML template using the `frontend-design` skill at implementation time.

**Non-Goals:**
- Native PDF export — macOS Print-to-PDF on the generated HTML is sufficient for v1.
- Scheduled / automated exports, email send, save-to-cloud.
- Saved presets / templates ("My weekly report"), comparison reports (two ranges side-by-side).
- Downsampling for very large ranges (defer until a real performance issue surfaces; current data volume is ~150 samples/day, trivially handled by Chart.js).
- Timezone selection or non-locale time formatting.
- Migrating the existing `samples` SQLite schema (untouched).

## Decisions

### Decision 1 — Output format: self-contained HTML with inline Chart.js, not PDF or PNG

**Choice:** Render to a single `.html` file with Chart.js bundled inline as a static asset, and report data injected as JSON literals.

**Why:**
- HTML carries interactive tooltips and matches Dashboard fidelity.
- macOS Print-to-PDF reaches PDF in two clicks from the generated HTML — free PDF path without writing code.
- "Inline Chart.js" (not CDN) means the artifact works offline on a recipient's machine, which is the whole point of an exported report.

**Alternatives considered:**
- *PDF via PDFKit / SwiftUI ImageRenderer*: native-feel and pinned, but loses interactivity, requires re-implementing layout, and is overkill given Print-to-PDF is free.
- *Markdown with embedded SVG*: portable, but charts are static and authoring the SVG by hand is more code than reusing Chart.js.
- *CDN-loaded Chart.js*: ~80 KB smaller HTML but breaks offline. Wrong call for a "report I email someone" scenario.

### Decision 2 — Unified `RangeSelection` is a Codable sum type

**Choice:** Introduce

```swift
enum RangePreset: String, Codable { case last24h, last7d, last30d, all }
enum RangeSelection: Codable, Equatable {
    case preset(RangePreset)
    case custom(from: Date, to: Date)
}
```

`RangePickerView` binds to `RangeSelection`. Mutating From/To on a `preset` selection auto-converts the binding into `.custom`. The current `DashboardRange` enum is deleted.

**Why:**
- A single representation drives both UI and persistence. The view derives chip-selected state from the case; the resolver derives `(from, to)` dates from preset semantics.
- Codable + JSON-in-UserDefaults is simpler than two parallel keys (`mode` + `from` + `to`).

**Alternatives considered:**
- *Three parallel keys in UserDefaults* (mode + fromDate + toDate): more brittle, easy to get out of sync, requires manual encoding of "all".
- *Computed `from`/`to` derived live from `Preset` only*: doesn't model custom ranges at all — abandoned.

### Decision 3 — `AppSettings` extended; `app-settings` spec untouched

**Choice:** Add a new key `dashboardRangeSelection` (JSON-encoded `RangeSelection`) to `AppSettings.swift`. Do not modify the `app-settings` spec.

**Why:**
- `app-settings` spec is scoped to "Settings tab toggles" — `notificationsEnabled`, `openAtLoginEnabled`. The dashboard range is *UI state*, not a user-facing setting.
- Reusing the `AppSettings` enum keeps UserDefaults wrappers in one file (a code-organization concern, not a spec concern).
- The `usage-dashboard` spec gains a new Requirement ("Remembers last range selection across launches") — that's where the persistence requirement belongs.

**Alternatives considered:**
- *New `DashboardState.swift` wrapper file*: cleaner separation but unnecessary; one extra key in `AppSettings` is fine for now.
- *Expose range as a user setting in the Settings tab*: scope creep; users don't expect to configure ranges in Preferences.

### Decision 4 — Export does NOT persist; resets to "Last 7d" on every open

**Choice:** The export sheet opens with a fresh `RangeSelection.preset(.last7d)` regardless of any prior export, dashboard state, or sheet-close action.

**Why:**
- Safety: silent reuse of an old range produces wrong-period reports. The user explicitly raised this concern (notes-as-duration). Forcing a deliberate range pick on every export prevents foot-guns.
- Cost: zero — just don't write to UserDefaults from the export sheet.

**Alternatives considered:**
- *Pre-fill from current Dashboard range*: convenient but defeats the safety argument. If the user wants the same range as the dashboard, two clicks is fine.

### Decision 5 — Inline Chart.js as a bundled Resource, not from SPM / CocoaPods

**Choice:** Drop a `chart.umd.min.js` file into the app bundle (Resources). At export time, the HTML template embeds it inside `<script>…</script>` tags via string substitution.

**Why:**
- No package dependency added — the app is dependency-free today, keep it that way.
- One file, no build step. Manually pinning the version is acceptable for a single static asset.
- Bundle size impact is negligible (~80 KB minified).

**Alternatives considered:**
- *Generate via D3 or hand-rolled SVG*: months of work, not justified for a personal monitoring tool.
- *Use SwiftUI Charts to render to PNG and embed*: kills interactivity, and rendering off-screen SwiftUI views to images on macOS is fiddly.

### Decision 6 — Template + injection model: HTML template with sentinel tokens

**Choice:** Ship a `report.html.template` in Resources containing sentinel placeholders (e.g. `__TITLE__`, `__CHART_JS__`, `__DATA_JSON__`, `__BUCKETS__`). The Swift exporter loads the template, substitutes, writes.

**Why:**
- HTML/CSS authoring lives outside Swift code — friendlier to the eventual `frontend-design` polish pass.
- Sentinel substitution is dumb and predictable; no templating engine required.
- Easy to preview the template directly in a browser by hand-filling placeholders.

**Alternatives considered:**
- *Build the HTML string inline in Swift*: harder to design, harder to review visual changes.
- *Mustache/Stencil dependency*: overkill; only ~6 substitution points.

### Decision 7 — Entry points: Dashboard toolbar (primary), File menu + ⌘E (secondary)

**Choice:** A button labelled "Export Report…" lives in the Dashboard's toolbar (top-right). The same action is wired into a File menu command via `CommandGroup` (new) with the keyboard shortcut ⌘E. Both invoke the same sheet.

**Why:**
- Dashboard-button is the natural triggering surface for a menu-bar app whose main window is opened to look at charts.
- File-menu / ⌘E exists for keyboard-driven and macOS-convention users.

**Alternatives considered:**
- *Only File menu*: hidden for a menu-bar app where users may never glance at the menu bar.
- *Only Dashboard button*: misses keyboard / standard-menu users.
- *Right-click on the status item*: too hidden for a "produce an artifact" action.

### Decision 8 — PDF output via `WKWebView.createPDF`, not a native PDF generator

**Choice:** Add PDF as a second output format alongside HTML. The PDF is produced by piping the same HTML through an off-screen `WKWebView` and calling `createPDF(configuration:)`. PDF becomes the default format on every fresh open of the export sheet.

**Why:**
- The HTML template is already styled with print CSS (`@page`, `page-break-inside: avoid`, pure-white paper, embedded fonts via system stack). Using WebKit for PDF means the print fidelity that the template was designed for is what actually ships, with zero extra layout code.
- WebKit ships with macOS — no third-party PDF library, no font-embedding work, no JS engine for chart rendering. The PDF renderer is ~70 lines of Swift.
- The "attach to a report" use case (the driving need for this whole change) is satisfied better by PDF than HTML: pinned layout, expected file type for the recipient, easy to embed in Notion / Confluence / Google Docs.
- HTML remains an option for the case where the user wants the interactive Chart.js tooltips (e.g., browsing the export themselves rather than sharing it).

**Alternatives considered:**
- *Native PDF via PDFKit / Quartz drawing*: would require re-implementing all chart drawing, typography, and layout. Massive scope explosion for a v1.
- *Spawn `wkhtmltopdf` or similar CLI*: external dependency, signing concerns, install friction — wrong for a personal Mac app.
- *Print-to-PDF via `NSPrintOperation`*: programmatic and works, but `createPDF` is the simpler and more direct API for "HTML → PDF Data".

## Risks / Trade-offs

- **Risk: Chart.js version drift / silent breakage** → Pin the bundled file with a comment recording version + source URL. Test the report opens in current Safari, Chrome on each rebuild that touches the template.
- **Risk: SwiftUI `DatePicker` for date-only on macOS has known quirks** (cramped UI, jumps on click) → Use `.compact` style with `displayedComponents: .date`; if it's too rough, fall back to a custom popover with `Text` + stepper. Decide during implementation.
- **Risk: `RangePickerView` refactor breaks Dashboard during partial implementation** → Land Dashboard refactor and export-sheet build-out in separate commits within the same PR; the refactor commit alone is testable (Dashboard still works) before export wiring is added.
- **Risk: Self-signed builds prompt Keychain access for the file write** → File-write to user-chosen location (via `NSSavePanel`) has no Keychain interaction; this is not in scope. Confirmed.
- **Risk: HTML template visual quality is "demo-grade" without a polish pass** → Implementation tasks reserve a slot for running the `frontend-design` skill against the template before the change is verified.
- **Trade-off: Inline Chart.js bloats every export by ~80 KB** → Acceptable. A 30-day report HTML is still well under 1 MB even with full data inlined.
- **Trade-off: Dashboard persists range, Export resets it — asymmetry is intentional** → Documented in Decision 4 so the asymmetry is not "fixed" by a later well-meaning refactor.

## Migration Plan

There is nothing to migrate.

- `AppSettings.dashboardRangeSelection` is a new key; if absent on first read, fall back to `.preset(.last7d)` (current default behaviour).
- `samples` SQLite schema unchanged.
- No remote state, no in-flight users to coordinate with.
- Rollback strategy: this is a single-user local app — reverting the commit and rebuilding is the rollback. The new UserDefaults key becomes orphaned but harmless.

## Open Questions

- **Q1.** Final styling direction for the HTML template — decided at implementation time via the `frontend-design` skill, not now.
- **Q2.** Should the Dashboard's "All" preset, when applied to Export, expand to the oldest sample's timestamp (consistent with Dashboard) or to "1 year ago" as a hard cap? Lean toward consistent-with-Dashboard. Confirm during specs phase.
- **Q3.** ⌘E is sometimes claimed by editing apps; macOS doesn't reserve it, but worth verifying no conflict with the standard "Find Selection" cluster (⌘E is "Use Selection for Find" in text fields). Likely benign for this app — no text editing — but flag for QA.
