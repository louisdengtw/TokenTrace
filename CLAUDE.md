# TokenTrace

Native macOS app for monitoring + visualizing personal `claude.ai` subscription
usage over time. Polls the same `/api/organizations/{id}/usage` endpoint
upstream `Artzainnn/ClaudeUsageBar` reverse-engineered, stores each poll in a
local SQLite store, and renders trends + reset markers in a SwiftUI Charts
dashboard. Menu bar item is a quick-glance accessory, not the main surface.

The local working directory is still named `ClaudeUsage` (legacy) but the
product, repo, and bundle ID are all `TokenTrace` / `dev.louisdeng.tokentrace`.

## Start here

Read `openspec/changes/rewrite-as-claudeusage/` — that is the source of truth.
The change directory name keeps the historical "rewrite-as-claudeusage" label
because the project was originally framed as a rewrite of ClaudeUsageBar; the
product was renamed to TokenTrace mid-development.

| File | What |
|---|---|
| `proposal.md` | Why + scope + 6 capabilities |
| `design.md` | Architecture decisions (Decision 1 has a 2026-05-07 amendment) |
| `specs/<capability>/spec.md` | Per-capability requirements & scenarios |
| `tasks.md` | 13 groups |

Progress: `openspec status --change rewrite-as-claudeusage`.

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
- Min macOS: **13.0** (SwiftUI Charts requirement).
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
- No remote yet. GitHub repo `louisdengtw/TokenTrace` not yet created.
  Group 11 in tasks.md covers that.

## Current state

- Most of v1 implemented (groups 1–9, plus the 12/13 design pivot work
  added during exploration).
- Verification group 10: 8/9 manual smoke tests passed; 10.8 (open at login
  reboot test) outstanding.
- Group 11 (publishing): not yet executed.
- **`usage-export` change in flight** (branch `feat/usage-export`) — adds an
  HTML report export and unifies the Dashboard's range selector to chip
  presets + custom From/To. See `openspec/changes/usage-export/`.

## Export Report feature

Open via Dashboard toolbar's "Export Report…" button, File → Export Report…,
or ⌘E. Produces a self-contained HTML file with Chart.js inlined — opens
offline in any browser. Bundled assets:

- `Sources/TokenTraceApp/Resources/chart.umd.min.js` (Chart.js 4.4.1, pinned)
- `Sources/TokenTraceApp/Resources/report.html.template` (sentinel-token
  template; substitutes happen in `Services/ReportGenerator.swift`)

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
