## Why

This repository is a fork of `Artzainnn/ClaudeUsageBar` that has accumulated significant local-only changes (cookie auto sign-in, removed donation UI, accessibility fixes) which cannot be merged upstream. The next planned features — a main window, persistent usage history, and an analytics dashboard — would require restructuring the entire 1588-line single-file Swift app, effectively a rewrite.

Rather than continuing to drift further from upstream while doing a de-facto rewrite, the work will move to a new standalone repository named `ClaudeUsage`, salvaging only the reverse-engineered claude.ai usage fetch logic from the current code.

## What Changes

- **BREAKING**: New repository (`ClaudeUsage`), new bundle ID (`dev.louisdeng.claudeusage`), no migration of historical data from the old app (none exists).
- **Hybrid menu bar app**: defaults to `LSUIElement = true` (menu bar only), but dynamically switches activation policy to `.regular` when the main window is open so the Dock icon appears. Mirrors the pattern used by Stats / Bartender / Ice.
- **New main window** with three sections: Menubar Preview, Dashboard, Settings. The popover from the menu bar still works as a quick view; the main window is for richer interaction.
- **Persistent usage history**: every poll (still 5-minute cadence) writes one row per bucket into a local SQLite store, enabling time-series analysis.
- **Dashboard with two trend charts**: 5-hour utilization and 7-day utilization (overall + Sonnet line), each with vertical dashed lines marking reset events derived from the `resets_at` field. Range selector (24h / 7d / 30d / All) and hover tooltips. No future-reset prediction line in v1.
- **Settings moves out of the popover** into the main window's Settings tab. Cookie management, notifications, hotkey, and open-at-login all relocate.
- **Build system change**: switch from the bash `build.sh` script to a Swift Package layout with multi-file source organization (App / MenuBar / MainWindow / Services / Persistence / Models).
- **Minimum macOS version bumped to 13.0** (required by SwiftUI Charts; old app targeted 12.0).
- **Salvaged from old repo**: the `ClaudeAPI` request flow (`/api/bootstrap` → `org_id` → `/api/organizations/{id}/usage`), `CookieKeychain`, and the global hotkey registration. Everything else is rewritten.
- **Out of scope for v1**: per-conversation tracking, hour-of-day heatmap, future-reset prediction line, auth UX overhaul (no OAuth, no `~/.claude/.credentials.json` integration, no browser cookie auto-extraction), adaptive polling, DMG installer / notarization.

## Capabilities

### New Capabilities
- `app-shell`: hybrid `LSUIElement` activation, main window lifecycle, Dock icon coordination, menu bar / window coexistence.
- `claude-api-integration`: claude.ai web API client — bootstrap → org_id resolution, usage endpoint fetch, auth-failure detection, cookie/keychain management.
- `usage-persistence`: SQLite-backed time-series store for poll samples, including schema, write path, and query helpers used by the dashboard.
- `usage-dashboard`: SwiftUI Charts-based historical view with dual trend charts, reset markers, range selector, and hover tooltips.
- `menu-bar-display`: status item icon (color-coded by 5-hour utilization), popover quick view, global ⌘U hotkey.
- `app-settings`: cookie management UI, notifications toggle and threshold logic, hotkey enable/disable, open-at-login.

### Modified Capabilities
<!-- None — this is a greenfield rewrite in a new repository, no existing specs. -->

## Impact

- **Code**: entire `app/ClaudeUsageBar.swift` (1588 lines) is replaced by a multi-file Swift Package layout. Only the `fetchOrganizationId` / `fetchUsage` / `parseUsageData` logic and the `CookieKeychain` enum are carried over conceptually (rewritten to fit the new structure).
- **Build**: `app/build.sh` retired in favor of `swift build` / Xcode project from the Swift Package. Manual `codesign` step still required (self-signed cert hash `F690B9DA81D392695487D52D35F6B37E7A362495`).
- **Bundle / install**: new bundle ID `dev.louisdeng.claudeusage`. Avoids macOS 26's blacklist on `com.claude.usagebar` (per `TROUBLESHOOTING.md`). Installs to `/Applications/ClaudeUsage.app`. Old app can stay installed in parallel during transition.
- **Storage**: new SQLite database at `~/Library/Application Support/dev.louisdeng.claudeusage/usage.sqlite`. Estimated growth ~5 MB/year at 5-minute polling.
- **System version**: requires macOS 13.0+ (was 12.0+).
- **External dependencies**: SQLite via `GRDB.swift` or stdlib `SQLite3` C API (decided in design phase). SwiftUI Charts is system-provided.
- **Repository**: new repo on GitHub at `louisdengtw/ClaudeUsage`. MIT licensed. README credits `Artzainnn/ClaudeUsageBar` as inspiration for the API integration patterns. Not a GitHub fork relationship — independent repository.
- **This (old) repo**: continues to exist on `personal/main` for reference; `TROUBLESHOOTING.md` and `openspec/` artifacts stay as historical record. Eventually archive.
