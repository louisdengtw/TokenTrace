## Why

This repository is a fork of `Artzainnn/ClaudeUsageBar` that has accumulated significant local-only changes (cookie auto sign-in, removed donation UI, accessibility fixes) which cannot be merged upstream. The next planned features — a main window, persistent usage history, and an analytics dashboard — would require restructuring the entire 1588-line single-file Swift app, effectively a rewrite.

Rather than continuing to drift further from upstream while doing a de-facto rewrite, the work will move to a new standalone repository named `TokenTrace`, salvaging only the reverse-engineered claude.ai usage fetch logic from the current code.

## What Changes

- **BREAKING**: New repository (`TokenTrace`), new bundle ID (`dev.louisdeng.tokentrace`), no migration of historical data from the old app (none exists).
- **Window-first app with menu bar accessory**: `LSUIElement = true` is retained for resource hygiene (Dock icon hides when no window is visible), but the *primary* surface is the main window — user-initiated launches open the window automatically; SMAppService login launches stay menu-bar-only. The menu bar status item is a quick-glance accessory, not the main interaction. (See `design.md` Decision 1 update for the framing journey; the original "hybrid menu bar app" framing was reversed mid-implementation.)
- **New main window** with three sections: Menubar Preview, Dashboard, Settings. The popover from the menu bar still works as a quick view; the main window is for richer interaction.
- **Persistent usage history**: every poll (still 5-minute cadence) writes one row per bucket into a local SQLite store, enabling time-series analysis.
- **Dashboard with two trend charts**: 5-hour utilization and 7-day utilization (overall + Sonnet line), each with vertical dashed lines marking reset events derived from the `resets_at` field. Range selector (24h / 7d / 30d / All) and hover tooltips. No future-reset prediction line in v1.
- **Settings moves out of the popover** into the main window's Settings tab. Cookie management, notifications, and open-at-login all relocate.
- **Build system change**: switch from the bash `build.sh` script to a Swift Package layout with multi-file source organization (App / MenuBar / MainWindow / Services / Persistence / Models).
- **Minimum macOS version bumped to 13.0** (required by SwiftUI Charts; old app targeted 12.0).
- **Salvaged from old repo**: the `ClaudeAPI` request flow only — `/api/bootstrap` → `org_id` → `/api/organizations/{id}/usage`, plus the multi-signal auth-failure detection. Everything else is independent work, including the `CookieKeychain` (verified via fork commit history: Louis added it himself in his fork of `Artzainnn/ClaudeUsageBar`, not derived from upstream). Global hotkey was salvaged initially but dropped 2026-05-07 (see `tasks.md` 6.6).
- **Out of scope for v1**: per-conversation tracking, hour-of-day heatmap, future-reset prediction line, auth UX overhaul (no OAuth, no `~/.claude/.credentials.json` integration, no browser cookie auto-extraction), adaptive polling, DMG installer / notarization.

## Capabilities

### New Capabilities
- `app-shell`: hybrid `LSUIElement` activation, main window lifecycle, Dock icon coordination, menu bar / window coexistence.
- `claude-api-integration`: claude.ai web API client — bootstrap → org_id resolution, usage endpoint fetch, auth-failure detection, cookie/keychain management.
- `usage-persistence`: SQLite-backed time-series store for poll samples, including schema, write path, and query helpers used by the dashboard.
- `usage-dashboard`: SwiftUI Charts-based historical view with dual trend charts, reset markers, range selector, and hover tooltips.
- `menu-bar-display`: status item icon (color-coded by 5-hour utilization), popover quick view.
- `app-settings`: cookie management UI, notifications toggle and threshold logic, open-at-login.

### Modified Capabilities
<!-- None — this is a greenfield rewrite in a new repository, no existing specs. -->

## Impact

- **Code**: entire `app/ClaudeUsageBar.swift` (1588 lines) is replaced by a multi-file Swift Package layout. Only the `fetchOrganizationId` / `fetchUsage` / `parseUsageData` logic is carried over from upstream (rewritten to fit the new structure, with an in-source notice in `Sources/TokenTraceApp/Services/ClaudeAPI.swift`).
- **Build**: `app/build.sh` retired in favor of `swift build` / Xcode project from the Swift Package. Manual `codesign` step still required (self-signed cert hash `F690B9DA81D392695487D52D35F6B37E7A362495`).
- **Bundle / install**: new bundle ID `dev.louisdeng.tokentrace`. Avoids macOS 26's blacklist on `com.claude.usagebar` (per `TROUBLESHOOTING.md`). Installs to `/Applications/TokenTrace.app`. Old app can stay installed in parallel during transition.
- **Storage**: new SQLite database at `~/Library/Application Support/dev.louisdeng.tokentrace/usage.sqlite`. Estimated growth ~5 MB/year at 5-minute polling.
- **System version**: requires macOS 13.0+ (was 12.0+).
- **External dependencies**: SQLite via `GRDB.swift` or stdlib `SQLite3` C API (decided in design phase). SwiftUI Charts is system-provided.
- **Repository**: new repo on GitHub at `louisdengtw/TokenTrace`. MIT licensed. README credits `Artzainnn/ClaudeUsageBar` as inspiration for the API integration patterns. Not a GitHub fork relationship — independent repository.
- **This (old) repo**: continues to exist on `personal/main` for reference; `TROUBLESHOOTING.md` and `openspec/` artifacts stay as historical record. Eventually archive.

## Amendments (mid-authoring, 2026-05-07)

The change started life as "rewrite ClaudeUsage from ClaudeUsageBar's bones" and evolved during implementation. The change directory keeps its original name (`rewrite-as-claudeusage`) as a historical label; below are the deltas applied while the change was still in-progress:

| Section | Original | Amended |
|---|---|---|
| Product name | `ClaudeUsage`, bundle `dev.louisdeng.claudeusage` | **`TokenTrace`**, bundle `dev.louisdeng.tokentrace` — for trademark hygiene (avoid embedding "Claude" in a third-party tool that scrapes Anthropic's web API) and to leave room for future multi-provider expansion (Claude / Codex). |
| App identity | "Hybrid menu bar app" inheriting ClaudeUsageBar's status-bar-agent positioning | **Window-first monitoring + analysis tool**; menu bar is an accessory. The Dashboard (persistent history + visualization) is the value prop, not the menu bar quick view. See `design.md` Decision 1 update. |
| Salvage scope | "ClaudeAPI flow + CookieKeychain" | **Only ClaudeAPI flow.** Verified via fork commit `7233746` ("feat: add email auto sign-in with secure cookie storage and refined UI") that Louis authored `CookieKeychain` himself. The in-source notice on `CookieKeychain.swift` was removed; `LICENSE-CLAUDEUSAGEBAR` lists only `ClaudeAPI.swift`. |
| Quit semantics | (Not specified in original) | ⌘Q intercepted (closes window, app stays in menu bar); real Quit only via status item right-click. Stats convention. See `app-shell/spec.md`. |
| Standard macOS app menu | (Not specified) | Programmatic `NSApp.mainMenu` constructed at launch (Application / File / Edit / View / Window / Help). |
| ⌘U global hotkey | Salvaged from upstream | **Dropped from v1.** Marginal value vs the Accessibility-permission friction. See `tasks.md` 6.6. |
| Settings UI | Form with three sections (Cookie / Notifications / Login) | Shipped as-is for v1, but flagged as IA-deficient; redesign deferred to next feature that touches Settings. |
| App icon | Reuse old `ClaudeUsageBar.icns` | **Replaced** with a fresh icon Louis generated via Gemini Nano Banana. |

These were captured live in commit history; the journey itself is in `git log`. This section exists so a future reader of this archived change can see "the v1 that shipped" reflects this set of corrections, not the literal text in the sections above.
