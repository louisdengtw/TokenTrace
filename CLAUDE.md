# ClaudeUsage

Native macOS menu bar + main-window app that polls `claude.ai` for usage and visualizes history. Greenfield rewrite of `Artzainnn/ClaudeUsageBar`; salvages only the API integration.

## Start here

Read `openspec/changes/rewrite-as-claudeusage/` — that is the source of truth.

| File | What |
|---|---|
| `proposal.md` | Why + scope + 6 capabilities |
| `design.md` | Architecture decisions, trade-offs, open questions |
| `specs/<capability>/spec.md` | Per-capability requirements & scenarios |
| `tasks.md` | 11 groups, ~60 tasks. **Start at task 1.1.** |

Progress: `openspec status --change rewrite-as-claudeusage`.
Implementation: `/opsx:apply` walks tasks one at a time.

## Salvage map (old repo)

Only copy these from `~/worksapce/ClaudeUsageBar/app/ClaudeUsageBar.swift`:

| What | Approx lines | Notes |
|---|---|---|
| `CookieKeychain` enum | 370–435 | Change service to `dev.louisdeng.claudeusage.session` |
| `fetchOrganizationId` | 568–642 | Cookie-then-bootstrap fallback, auth-fail detection |
| `fetchUsageWithOrgId` + `parseUsageData` | 668–890 | Multi-signal auth detection, ISO8601 parsing |

Do **not** copy: AppDelegate glue, the popover `UsageView`, settings UI, custom `NSTextField` paste hacks. Rewrite cleaner per `design.md` §5 (module layout).

**Every salvaged file must carry a file-level notice header** (per task 1.12). The notice points to `LICENSE-CLAUDEUSAGEBAR` at the repo root, which preserves upstream's MIT terms verbatim. Repo-root `LICENSE` is Louis's own MIT for the new code; it ends with a pointer to `LICENSE-CLAUDEUSAGEBAR`.

```swift
// Portions of this file are derived from ClaudeUsageBar (MIT licensed).
// Source: https://github.com/Artzainnn/ClaudeUsageBar
// Copyright (c) 2026 ClaudeUsageBar — see LICENSE-CLAUDEUSAGEBAR for full terms.
```

## Build & sign on this Mac

- Bundle ID: **`dev.louisdeng.claudeusage`**. Never `com.claude.usagebar` — macOS 26 has it blacklisted (see "If menu bar icon disappears" below).
- Self-signed cert in login keychain: `F690B9DA81D392695487D52D35F6B37E7A362495` ("LouisLocalSign"). Build script should prefer it, fall back to ad-hoc.
- Min macOS: **13.0** (SwiftUI Charts requirement).
- After rebuild, always `pkill -x ClaudeUsage` before `open` — `open` won't replace a running app of the same bundle ID.
- Every rebuild invalidates Accessibility grant and prompts Keychain again. Not a bug; ad-hoc signing's fault.

## If menu bar icon disappears (macOS 26 bundle ID poisoning)

Diagnose: `osascript -e 'tell application "System Events" to tell process "ClaudeUsage" to get position of menu bar items of menu bar 1'`
- `Y = 4` → healthy
- `Y = -1` or `Y > 50` → blacklisted

Reboot + `lsregister -r` are **not** enough. Deep reset:

```sh
pkill -x ClaudeUsage
defaults delete dev.louisdeng.claudeusage 2>/dev/null
rm -rf ~/Library/{Preferences,Caches,Application\ Support,Saved\ Application\ State,HTTPStorages,WebKit,Containers,Group\ Containers}/dev.louisdeng.claudeusage*
tccutil reset All dev.louisdeng.claudeusage
rm -rf /Applications/ClaudeUsage.app
cp -R <build>/ClaudeUsage.app /Applications/
killall ControlCenter NotificationCenter cfprefsd
sleep 3
open /Applications/ClaudeUsage.app
```

Full recipe with backstory: `~/worksapce/ClaudeUsageBar/TROUBLESHOOTING.md`.

## Communicating with the user

- Replies in 繁中 + English, terse, tables for comparisons. No fluff, no end-of-turn restatement.
- First-time GitHub PR contributor; comfortable in terminal but **new to Swift / AppKit**. Frame Swift-specific reasoning explicitly when relevant.
- For PR scope concerns, offer to split rather than force-pushing rewrites.

## Git on this repo

- `user.email` already set locally to `281707863+louisdengtw@users.noreply.github.com` (GitHub email-privacy block otherwise rejects pushes).
- No remote yet. Repo `louisdengtw/ClaudeUsage` on GitHub not created. Tasks 11.1–11.2 cover that.

## Current state

- Repo initialized, no commits yet.
- Only `openspec/` is populated. No `Package.swift`, no `Sources/`, no app code.
- Task 1.1 partially done: directory + `git init` + openspec copied. Next: `Package.swift` (task 1.2).

## API endpoints used (for reference)

```
GET https://claude.ai/api/bootstrap                       → .account.lastActiveOrgId
GET https://claude.ai/api/organizations/{org_id}/usage    → {five_hour, seven_day, seven_day_sonnet}
                                                            each: { utilization (0-100), resets_at (ISO8601) }
```

Auth: full Cookie header pasted from browser (`sessionKey` is httpOnly so JS can't grab it; embedded WebView OAuth is blocked by Google Identity Services). Cookie stored in Keychain. Solving the auth UX is **out of scope for v1**.
