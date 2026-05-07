## 1. Repository and Build System Setup

- [x] 1.1 Create new local directory `~/worksapce/ClaudeUsage/` and initialize as a git repository.
- [x] 1.2 Create `Package.swift` declaring an executable target `ClaudeUsageApp`, platforms `[.macOS(.v13)]`, no external dependencies.
- [x] 1.3 Scaffold the `Sources/ClaudeUsageApp/` directory tree per the layout in `design.md` (App / MenuBar / MainWindow / Services / Persistence / Models, plus `Tests/`).
- [x] 1.4 Copy and adapt `Resources/Info.plist` from the old repo, setting `CFBundleIdentifier = dev.louisdeng.claudeusage`, `LSMinimumSystemVersion = 13.0`, `LSUIElement = true`, `CFBundleName = ClaudeUsage`.
- [x] 1.5 Generate `Resources/ClaudeUsage.icns` (can reuse the old icon for v1, restyle later).
- [x] 1.6 Write `tools/build-app.sh` that runs `swift build -c release --arch arm64 --arch x86_64`, assembles `ClaudeUsage.app/Contents/{MacOS,Resources}`, copies `Info.plist` and `.icns`, runs `codesign --force --deep --sign F690B9DA81D392695487D52D35F6B37E7A362495 ClaudeUsage.app` (with ad-hoc fallback), and optionally `open`s the result.
- [x] 1.7 Verify `swift build` succeeds on an empty `App.swift` containing only `@main struct App { static func main() {} }`.
- [x] 1.8 Add `.gitignore` for `.build/`, `.swiftpm/`, `*.app`, `*.xcodeproj/xcuserdata/`.
- [x] 1.9 Add `LICENSE` (MIT, `Copyright (c) 2026 Louis Deng`) at repo root, with a trailing notice that points to `LICENSE-CLAUDEUSAGEBAR` for the upstream-derived portions.
- [x] 1.10 Add `LICENSE-CLAUDEUSAGEBAR` containing the upstream MIT license text verbatim (preserving its `Copyright (c) 2026 ClaudeUsageBar` line) plus a short header listing which source files include derived portions.
- [x] 1.11 Add a placeholder `README.md` with a "Credits" section that names `Artzainnn/ClaudeUsageBar` and explains the salvage scope (API integration only).
- [x] 1.12 Add file-level notice headers to each Swift file that includes derived code (initially `Sources/ClaudeUsageApp/Services/ClaudeAPI.swift` and `Sources/ClaudeUsageApp/Services/CookieKeychain.swift`):
- [x] 1.13 Add `Makefile` at repo root with `build / install / run / test / clean / help` targets; `tools/build-app.sh` becomes pure-build (drop the `--open` flag, Makefile's `run` target replaces it).
  ```swift
  // Portions of this file are derived from ClaudeUsageBar (MIT licensed).
  // Source: https://github.com/Artzainnn/ClaudeUsageBar
  // Copyright (c) 2026 ClaudeUsageBar — see LICENSE-CLAUDEUSAGEBAR for full terms.
  ```

## 2. Models and Persistence

- [x] 2.1 Define `Bucket` enum (`fiveHour`, `sevenDay`, `sevenDaySonnet`) with `rawValue` matching the SQL `bucket` column strings.
- [x] 2.2 Define `UsageSample` struct: `(ts: Date, bucket: Bucket, util: Double, resetsAt: Date)`.
- [x] 2.3 Implement `UsageStore.swift`: open or create the SQLite database at `~/Library/Application Support/dev.louisdeng.claudeusage/usage.sqlite`, run DDL on first creation, expose `insert(samples:)` and `query(bucket:from:to:)`.
- [x] 2.4 Implement reset-event detection helper (walks ordered samples, emits events when `resets_at` increases).
- [x] 2.5 Implement `SQLITE_BUSY` retry (3 attempts, short delay) and graceful error logging for other SQLite errors.
- [x] 2.6 Write `Tests/ClaudeUsageAppTests/UsageStoreTests.swift` covering: fresh DB creation, insert + query roundtrip, `INSERT OR REPLACE` on duplicate `(ts, bucket)`, empty-range query.
- [x] 2.7 Write `Tests/ClaudeUsageAppTests/ResetDetectionTests.swift` covering: single reset, no reset, multiple consecutive resets.

## 3. Claude API Integration

- [x] 3.1 Salvage and refactor `CookieKeychain` from the old repo into `Services/CookieKeychain.swift`. Update service name to `dev.louisdeng.claudeusage.session`.
- [x] 3.2 Implement `Services/ClaudeAPI.swift` with `fetchOrgId(cookie:)` and `fetchUsage(cookie:orgId:)` async methods. Carry over the cookie-then-bootstrap fallback logic and the multi-signal auth-failure detection (status, redirect, content-type) from the old code.
- [x] 3.3 Define a `ClaudeAPIError` enum with cases for `sessionExpired`, `parseError(String)`, `httpError(Int)`, `network(Error)`.
- [x] 3.4 Parse the usage response into an array of `UsageSample` (one per present bucket) using ISO8601 with fractional seconds for `resets_at`.
- [x] 3.5 Tolerate absent `seven_day_sonnet`; do not error.
- [x] 3.6 Unit-test the parser with three fixture JSONs: full Pro response, non-Pro response (no `seven_day_sonnet`), malformed response.

## 4. UsageManager Orchestration

- [x] 4.1 Implement `Services/UsageManager.swift` as `@MainActor ObservableObject` (or `@Observable` if dropping macOS 13 compat — see Open Question in design.md) holding `latestSample: [Bucket: UsageSample]`, `isLoading`, `errorMessage`, `hasFetchedData`, `hasWeeklySonnet`, `sessionCookie`.
- [x] 4.2 Implement the polling loop: 5-minute `Timer`, calls `ClaudeAPI`, on success inserts into `UsageStore` and updates published state.
- [x] 4.3 On `sessionExpired` error, set a flag the menu bar and Settings views can read to show a "please re-sign in" affordance.
- [x] 4.4 Trigger an immediate fetch on app launch and after the user saves a new cookie.
- [x] 4.5 Threshold-crossing detection for notifications: track `lastNotifiedThreshold` per 5-hour window; reset on `resets_at` change.

## 5. App Shell and Activation Policy

- [x] 5.1 Implement `App.swift` with `@main` entry point and `AppDelegate: NSApplicationDelegate` that constructs the `UsageManager`, `StatusItemController`, and `MainWindowController`.
- [x] 5.2 In `applicationDidFinishLaunching`, set `NSApp.setActivationPolicy(.accessory)` and create the status item.
- [x] 5.3 Implement `MainWindowController` that lazily creates the main window. On first show, switch policy to `.regular` and call `NSApp.activate(ignoringOtherApps: true)`.
- [x] 5.4 Observe `NSWindow.willCloseNotification`; when the last main window closes, switch policy back to `.accessory`.
- [x] 5.5 Ensure re-opening a window when one is already open just brings it to front (no duplicate).
- [x] 5.6 In `applicationDidFinishLaunching`, read `NSApplication.launchIsDefaultUserInfoKey`. If true (user-initiated launch), call `mainWindowController.show()` so the main window appears. Login-item auto-launches stay menu-bar-only. Implement `applicationShouldHandleReopen(_:hasVisibleWindows:)` to surface the main window when the user re-`open`s an already-running instance.

## 6. Menu Bar Display

- [x] 6.1 Implement `MenuBar/StatusItemController.swift` owning the `NSStatusItem` and a `NSPopover` (or `NSPanel`) for the popover.
- [x] 6.2 Render the status item icon with a percentage label when `latestSample[.fiveHour]` is non-nil; show a neutral icon when not yet fetched.
- [x] 6.3 Implement color-coded icon (green ≤50, yellow 51–75, orange 76–90, red >90) based on 5-hour utilization.
- [x] 6.4 Wire left-click to toggle the popover, right-click to show a context menu with "Open Main Window", "Toggle Usage (⌘U)", separator, "Quit ClaudeUsage".
- [x] 6.5 Implement `MenuBar/PopoverView.swift` showing current usage for all available buckets, an "Open Main Window" button, and a "Settings…" button (which opens the main window with the Settings tab).
- [x] 6.6 ~~Implement `Services/HotKey.swift` (Carbon-based ⌘U registration) and call it on launch only if the hotkey-enabled UserDefaults flag is true.~~ Superseded 2026-05-07: scrapped from v1 — `HotKey.swift` was implemented and then removed; popover stays reachable via menu bar status item left-click only.

## 7. Main Window

- [x] 7.1 Implement `MainWindow/MainWindowController.swift` building a tabbed/sidebar window with three sections: Menubar Preview, Dashboard, Settings.
- [x] 7.2 Implement `MainWindow/MenuBarPreviewView.swift` showing a live preview of the current status item icon and the latest sample values.
- [x] 7.3 Implement `MainWindow/DashboardView.swift` containing the range selector and the two `Chart` views (5-hour and 7-day). Wire them to `UsageStore.query(bucket:from:to:)`.
- [x] 7.4 Render reset events as `RuleMark` with dashed style on each chart.
- [x] 7.5 Render the 7-day chart as two lines (`LineMark`) when both `seven_day` and `seven_day_sonnet` data exist; one line otherwise.
- [x] 7.6 Wire `chartXSelection` to a SwiftUI tooltip overlay showing timestamp and utilization.
- [x] 7.7 Re-query the store and re-render charts when `UsageManager` publishes a new sample (use `.onChange` or `@Published` subscription).
- [x] 7.8 Handle the empty-data state with a placeholder ("No data yet — wait for the first poll").

## 8. Settings UI

- [x] 8.1 Implement `MainWindow/SettingsView.swift` as a SwiftUI `Form` with sections: Cookie, Notifications, Hotkey, Open at login.
- [x] 8.2 Cookie section: redacted preview of stored cookie, paste-and-save text field, "Sign out" button. Saving triggers an immediate fetch via `UsageManager`.
- [x] 8.3 Notifications section: master toggle. (Threshold list 25/50/75/90 is fixed in v1; not user-configurable.)
- [x] 8.4 ~~Hotkey section: toggle that registers/deregisters the global ⌘U hotkey via `HotKey.swift`. Show Accessibility prompt only when toggling on without permission.~~ Superseded 2026-05-07: dropped along with task 6.6.
- [x] 8.5 Open at login section: toggle backed by `SMAppService.mainApp` register/unregister.
- [x] 8.6 All toggles persist to `UserDefaults` and are restored on next launch.

## 9. Notifications

- [x] 9.1 Implement notification delivery using the modern `UserNotifications` framework (not the deprecated `NSUserNotification` from the old code).
- [x] 9.2 Request notification permission on first enable.
- [x] 9.3 Wire `UsageManager`'s threshold-crossing logic to `UNUserNotificationCenter` to deliver one notification per crossing per 5-hour window.

## 10. Verification and Polish

- [x] 10.1 Build via `tools/build-app.sh` and install to `/Applications/ClaudeUsage.app`. (Build done; install to `/Applications/` is a manual step — see "How to verify" in this PR.)
- [ ] 10.2 Verify menu bar icon appears at AX position Y≈4 (per the macOS 26 troubleshooting check from the old repo's `TROUBLESHOOTING.md`).
- [ ] 10.3 Smoke test: paste valid cookie, see first sample within 10 seconds, watch icon color update.
- [ ] 10.4 Open main window, verify Dock icon appears; close window, verify it disappears.
- [ ] 10.5 Verify Dashboard charts render with at least 3 polls' worth of data; verify reset markers appear after the first 5-hour reset (~5h after first poll).
- [ ] 10.6 Verify hover tooltips show correct timestamp and value.
- [x] 10.7 ~~Verify ⌘U hotkey works globally after Accessibility grant.~~ Superseded 2026-05-07: hotkey feature removed.
- [ ] 10.8 Verify "Open at login" by toggling on, rebooting, and checking app starts in menu-bar-only mode.
- [ ] 10.9 Verify SQLite file exists at expected path and grows by 3 rows per successful poll (or 2 rows for non-Pro users).

## 11. Repository Publishing

- [ ] 11.1 Create new GitHub repo `louisdengtw/ClaudeUsage` (start private; flip to public when ready).
- [ ] 11.2 Push initial commit. Configure local `user.email` to the GitHub noreply address (`281707863+louisdengtw@users.noreply.github.com`) to avoid email-privacy push rejection.
- [ ] 11.3 Move (or copy) `openspec/` from this fork into the new repo so the design history travels with the code.
- [x] 11.4 ~~Archive the old fork repo `louisdengtw/ClaudeUsageBar` on GitHub.~~ Superseded 2026-05-07: leave the old fork untouched (no archive, no banner, no rename).

## 12. Frame Pivot and Quit Semantics (added 2026-05-07)

Reframes the app from "menu bar primary" to "window primary with menu bar accessory". Captured as Decision 1 amendment in design.md and reflected in `specs/app-shell/spec.md`. Supersedes task 5.6 (the launch-flow patch landed as part of this pivot, not as a standalone fix).

- [x] 12.1 Update `design.md` Decision 1 with the 2026-05-07 amendment (window-first identity, state transitions, Quit semantics, standard macOS menu bar, history table). Original Decision 1 retained for trail.
- [x] 12.2 Rewrite `specs/app-shell/spec.md` to consolidate prior scenarios with new Quit semantics and standard menu bar requirements; supersedes task 5.6.
- [x] 12.3 Programmatically construct `NSApp.mainMenu` with Application / File / Edit / View / Window / Help menus. Built once in `applicationDidFinishLaunching` via the new `App/MainMenuBuilder.swift` so it persists across `.accessory` ↔ `.regular` transitions. View menu hosts a Toggle Sidebar item (⌃⌘S) that posts `.toggleSidebar` for `MainWindowContent` to act on.
- [x] 12.4 Implement `applicationShouldTerminate(_:)` on `AppDelegate`: if `userInitiatedQuit` is true return `.terminateNow`; otherwise close all visible main windows and return `.terminateCancel`.
- [x] 12.5 Implement `applicationShouldTerminateAfterLastWindowClosed(_:)` to return `false`.
- [x] 12.6 `StatusItemController.quitAction` now calls `AppDelegate.requestRealQuit()` (sets the flag, then invokes terminate). The right-click context menu's Quit item lost its ⌘Q key equivalent so the system doesn't double-bind it.
- [ ] 12.7 Verify behaviour after implementation: ⌘Q with window focused → window closes, process stays; app menu Quit → same; status item right-click Quit → process terminates; window close (X / ⌘W) → menu bar only; login launch → menu bar only; subsequent `open` → re-opens window.

## 13. UI Design Pass (Claude Design hand-off, 2026-05-07)

Visuals translated from `claude.ai/design` mockups (`Popover + MenuBar.html` + `Dashboard.html`). The functional surface (data flow, persistence, polling) was already in place; this group is purely the look-and-feel layer landing across status item, popover, sidebar, and dashboard.

- [x] 13.1 Stats-style menu bar icon: 3 stacked columns (5H / 7D / SON), per-column threshold colors, label 8pt + value 10pt SF Pro, rendered via `ImageRenderer` on every state / appearance change. New file `MenuBar/StatsIconView.swift`; `StatusItemController` swapped over from SF Symbol + tint approach.
- [x] 13.2 Popover redesign (D + B blend): header with Pro chip + sync indicator (green dot + "Xs ago"), per-bucket cards with sparkline (last 12 samples from store), 28-segment tick bar, threshold-tinted percentage, "resets in Xh Ym" countdown; `.borderedProminent` + `.bordered` button pair in footer. 320 × 280 inside the standard `NSPopover`.
- [x] 13.3 Main window restructure: replace `TabView` with `NavigationSplitView`. Sidebar contains brand chip (Anthropic-orange gradient C), title + version/Pro line, three nav rows (Dashboard / Menu Bar / Settings) with selection highlight, and sync footer (dot + relative time).
- [x] 13.4 Dashboard redesign: top toolbar (title + trend description + segmented range selector) above two cards, each card has SwiftUI Charts area chart with linear-gradient fill (0.30 → 0.02), crisp 1.6pt monotone line, dashed reset `RuleMark`s, hover crosshair + dot pair (state-driven via `chartXSelection` on macOS 14+, falls back gracefully on 13), big mono readout in card header. `UsageColor` helper now shared across status item, popover, dashboard.
- [x] 13.5 Threshold color thresholds aligned with mockups: ≥90 red, ≥75 orange, ≥50 yellow, else green. Replaces the prior 50/75/90 banding with the design's 50/75/90 cuts (semantically the same, hex values harmonized with the design palette).
