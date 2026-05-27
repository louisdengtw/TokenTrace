# TokenTrace

Native macOS app for monitoring + visualizing personal `claude.ai` subscription
usage over time. Polls the same `/api/organizations/{id}/usage` endpoint
upstream `Artzainnn/ClaudeUsageBar` reverse-engineered, stores each poll in a
local SQLite store, and renders trends + reset markers in a SwiftUI Charts
dashboard. Menu bar item is a quick-glance accessory, not the main surface.

The local working directory is still named `ClaudeUsage` (legacy) but the
product, repo, and bundle ID are all `TokenTrace` / `dev.louisdeng.tokentrace`.

## Start here

Active in-flight change: `openspec/changes/claude-code-usage/`. Adds the Claude
Code tab (transcript-derived usage analysis from `~/.claude/projects/`) and a
tab-aware Export Report.

| File | What |
|---|---|
| `proposal.md` | Why + scope |
| `design.md` | Architecture decisions |
| `specs/<capability>/spec.md` | Per-capability requirements & scenarios |
| `tasks.md` | 19 groups; progress via `openspec status --change claude-code-usage` |

Earlier in-flight work is archived under `openspec/changes/archive/`:
- `2026-05-07-rewrite-as-claudeusage` — original rewrite/rename (Decision 1 has a 2026-05-07 amendment)
- `2026-05-13-cookie-import`, `2026-05-13-main-window-quit-affordance`, `2026-05-14-usage-export` — incrementals between then and now

## Salvage map (only one file is genuinely upstream-derived)

`Sources/TokenTraceApp/Services/ClaudeAPI.swift` carries logic adapted from
`~/workspace/ClaudeUsageBar/app/ClaudeUsageBar.swift`:

| What | Approx upstream lines | Notes |
|---|---|---|
| `fetchOrganizationId` | 568–642 | Cookie-then-bootstrap fallback, auth-fail detection |
| `fetchUsageWithOrgId` + `parseUsageData` | 668–890 | Multi-signal auth detection, ISO8601 parsing |

That file has an in-source notice header. `LICENSE-CLAUDEUSAGEBAR` at the repo
root preserves upstream's MIT terms verbatim.

`CookieKeychain.swift` is **not** upstream-derived — Louis added it in his
fork (commit 7233746 "feat: add email auto sign-in with secure cookie storage
and refined UI"). No notice there.

## Build & sign on this Mac

- Bundle ID: **`dev.louisdeng.tokentrace`**. Never `com.claude.usagebar` —
  macOS 26 has it blacklisted (see "If menu bar icon disappears" below).
- Self-signed cert in login keychain: `F690B9DA81D392695487D52D35F6B37E7A362495`
  ("LouisLocalSign"). Build script prefers it, falls back to ad-hoc.
- Min macOS: **14.0** (SwiftUI Charts `chartXSelection` + clean dual-Y-axis for the Claude Code tab).
- After rebuild, always `pkill -x TokenTrace` before `open` — `open` won't
  replace a running app of the same bundle ID.
- Every rebuild invalidates Accessibility grant and prompts Keychain again.
  Not a bug; ad-hoc signing's fault.

## If menu bar icon disappears (macOS 26 bundle ID poisoning)

Diagnose:
```sh
osascript -e 'tell application "System Events" to tell process "TokenTrace" to get position of menu bar items of menu bar 1'
```
- `Y = 4` → healthy
- `Y = -1` or `Y > 50` → blacklisted

(On macOS 26 status items moved out of the per-process AX menu bar; if the
above returns the application menu bar items at Y=0, that's also healthy —
the blacklist signature is missing items, not Y=4 specifically.)

Reboot + `lsregister -r` are **not** enough. Deep reset:

```sh
pkill -x TokenTrace
defaults delete dev.louisdeng.tokentrace 2>/dev/null
rm -rf ~/Library/{Preferences,Caches,Application\ Support,Saved\ Application\ State,HTTPStorages,WebKit,Containers,Group\ Containers}/dev.louisdeng.tokentrace*
tccutil reset All dev.louisdeng.tokentrace
rm -rf /Applications/TokenTrace.app
cp -R <build>/TokenTrace.app /Applications/
killall ControlCenter NotificationCenter cfprefsd
sleep 3
open /Applications/TokenTrace.app
```

## Communicating with the user

- Replies in 繁中 + English, terse, tables for comparisons. No fluff, no
  end-of-turn restatement.
- First-time GitHub PR contributor; comfortable in terminal but **new to
  Swift / AppKit**. Frame Swift-specific reasoning explicitly when relevant.
- For PR scope concerns, offer to split rather than force-pushing rewrites.
- When Louis says "discuss requirements first", reset to first principles
  — don't take existing proposal/design/predecessor code as authority. See
  `feedback_requirements_first_no_predecessor_inheritance.md` in memory.

## Git on this repo

- `user.email` already set locally to
  `281707863+louisdengtw@users.noreply.github.com` (GitHub email-privacy block
  otherwise rejects pushes).
- `origin` = `https://github.com/louisdengtw/TokenTrace.git` (public). PR
  workflow: branch + PR every time, even though solo (see memory
  `feedback_pr_not_push_main.md`).

## Current state

- v1.0 → v1.1 (cookie-import, tagged + released 2026-05-12) → v1.2 (this
  change, plist bumped 2026-05-28; usage-export shipped without a release
  in between).
- All 19 groups of `claude-code-usage` done; change is on branch
  `feat/claude-code-usage`, ready for PR review + merge + archive.
- Subscription tab, menu bar accessory, Keychain cookie, threshold
  notifications, HTML/PDF report export, range chip + custom picker, and
  the new Claude Code tab + tab-aware Export — all live.

## Export Report feature

Toolbar Export button + File menu + ⌘E. Dispatch is **tab-aware** —
`MainWindowContent` reads `AppSettings.lastDashboardTab` on the
`.exportReportRequested` notification:

| Active tab | Sheet | Generator | Template |
|---|---|---|---|
| Subscription | `ExportSheetView` | `Services/ReportGenerator.swift` | `Resources/report.html.template` |
| Claude Code | `CCExportSheetView` | `Services/CCReportGenerator.swift` | `Resources/cc-report.html.template` |

Both produce a self-contained HTML or PDF (PDF flows through
`PDFRenderer.renderHTMLToPDF`). Chart.js 4.4.1 is inlined from
`Resources/chart.umd.min.js` — exported files open offline in any browser /
PDF reader (verified by Network panel showing zero non-`file://` requests).
Toolbar label flips between `Export Report…` and `Export Claude Code…`.

## Claude Code tab

Surfaces personal Claude Code (CLI) usage alongside the subscription view.
Data source: `~/.claude/projects/<hyphenated-path>/<session>.jsonl` — Claude
Code's transcript output. The ingester is at `Services/CCUsageIngester.swift`;
the store is `Persistence/CCUsageStore.swift`.

New tables (in the same `usage.sqlite`):

| Table | What |
|---|---|
| `cc_message` | One row per assistant message. `uuid` PK dedups across mirrors. Token counts only — never stores message bodies. |
| `cc_ingest_checkpoint` | Per-file `byte_offset` + `file_size` + `mtime` for incremental + truncation-safe re-scans. |
| `project_alias` | Per-cwd display name override (set via the "Manage projects…" sheet). |

### Privacy

The JSONL parser uses a `Codable` projection (`Services/CCUsageIngester.swift`
around line 213) that declares only `type` / `uuid` / `timestamp` / `cwd` /
`sessionId` / `requestId` / `isSidechain` / `message.model` /
`message.usage.*`. `message.content` is **never** in the projection —
`JSONDecoder` reads past those bytes but never materialises them as Swift
strings or `Data`. Locked by `CCUsageIngesterTests.testMessageContentNotPersisted`
plus a source-wide grep that turns up zero `.content` accesses anywhere in
`Sources/TokenTraceApp/`.

### "Weighted token volume"

The CC chart's left Y axis is **not** subscription quota — it's a relative
attribution proxy derived from public Anthropic API pricing ratios
(`Models/CCWeightedVolume.swift`):

| Component | Weight |
|---|---|
| `input_tokens` | ×1.0 |
| `output_tokens` | ×5.0 |
| `cache_creation_input_tokens` | ×1.25 |
| `cache_read_input_tokens` | ×0.1 |

Used to compare projects within a range. The right-axis dotted amber 5h util
line is the only quota-aware signal on the CC chart. `seven_day` is
intentionally NOT overlaid — the smooth ramp adds nothing on top of the 5h
sawtooth plus the Peak 5h Util stat in the stats strip, and crowds the right
axis. The info-circle affordance in the CC tab header repeats this caveat
to the user.

### Worktree fold

cwds containing a `.worktree`, `.worktrees`, or `.claude/worktrees` segment
fold into the parent repo's series so agent worktrees and side-by-side
branches don't fragment the project breakdown. There is also a workspace
root setting (Settings → Claude Code → `e.g. ~/workspace`); when set, any
cwd under that root folds to `<root>/<first-segment>` regardless of nesting
depth — handy for build dirs or scripts that sit alongside the repo.

## API endpoints used (for reference)

```
GET https://claude.ai/api/bootstrap                       → .account.lastActiveOrgId
GET https://claude.ai/api/organizations/{org_id}/usage    → {five_hour, seven_day, seven_day_sonnet}
                                                            each: { utilization (0-100), resets_at (ISO8601) }
```

Auth: full Cookie header pasted from browser (`sessionKey` is httpOnly so JS
can't grab it; embedded WebView OAuth is blocked by Google Identity Services).
Cookie stored in Keychain. Anthropic banned third-party OAuth in Feb 2026, so
cookie-paste remains the only viable path for a personal monitoring tool;
solving the auth UX further is **out of scope for v1**.
