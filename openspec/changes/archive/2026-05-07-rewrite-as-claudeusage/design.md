## Context

The current `ClaudeUsageBar` is a single-file (1588 lines) Swift menu bar app forked from `Artzainnn/ClaudeUsageBar`. It polls `claude.ai/api/organizations/{org_id}/usage` every 5 minutes via a session cookie pasted from the browser, displays the 5-hour utilization in the menu bar, and shows a popover with three progress bars (5h / 7d / 7d-Sonnet). All settings live in a collapsible section inside the popover. No history is persisted — only the most recent sample lives in memory.

The new `TokenTrace` app keeps the same data source but reshapes the app around a main window with a dashboard for historical analysis, while keeping the menu bar entry as a quick-glance surface.

The user is the sole consumer (personal-use app). No other contributors, no users to migrate. macOS 26 is the development target. The user has a self-signed code-signing cert (hash `F690B9DA81D392695487D52D35F6B37E7A362495`) in their login keychain.

## Goals / Non-Goals

**Goals:**
- Preserve the working `claude.ai` web API integration without re-doing the reverse engineering.
- Add persistent history so trends across days and weeks become visible, not just the current snapshot.
- Move settings out of the popover into a real window, freeing the popover to focus on quick info.
- Ship a v1 that is genuinely usable in a few days, not a 6-month rewrite.
- Establish a multi-file structure that makes future additions (per-conversation tracking, heatmaps, alternative auth) tractable.

**Non-Goals:**
- Solving the cookie-paste auth UX in v1. Hand-pasted Cookie header stays.
- Per-conversation or per-message tracking. Out of scope until `/api/organizations/{id}/conversations` is reverse-engineered (deferred backlog).
- Backwards compatibility with the old app's data, settings, or bundle ID — there is no historical data to bring forward, and old `UserDefaults` / Keychain entries do not need migration (user can re-enter cookie once).
- Cross-platform (still macOS-only).
- DMG installer, notarization, App Store distribution. Manual `cp` to `/Applications/` is fine for personal use.
- Adaptive polling (faster when window open, slower when idle). v1 is constant 5-minute cadence.

## Decisions

### Decision 1 — App activation policy: hybrid `LSUIElement` with dynamic switching

`Info.plist` declares `LSUIElement = true`, so by default the app is a menu-bar-only "agent" with no Dock icon. When the user opens the main window (via the popover button or the menu bar item's right-click menu), the app calls `NSApp.setActivationPolicy(.regular)` so the Dock icon appears and the window can receive focus normally. When the last main window closes (`windowWillClose` notification), the policy switches back to `.accessory` so the Dock icon disappears.

**Alternatives considered:**
- *Always `.regular` (Dock icon permanently)*: simpler, but loses the lightweight menu-bar-only feel that justified picking this app over a browser tab.
- *Always `.accessory` (no Dock icon ever)*: makes window focus-stealing awkward; macOS treats accessory apps oddly when they have visible windows.
- *Separate "menu bar helper" + "main app" processes*: way too much for a personal-use app.

**Why this choice:** matches the established pattern in macOS productivity apps (Stats, Bartender, Ice, Hidden Bar). Users get the right mental model in each mode.

### Decision 1 — Updated 2026-05-07: window-first with menu bar accessory

Reframes Decision 1's identity: TokenTrace's primary surface is the dashboard window, not the menu bar. The status item is an accessory — at-a-glance utilization when the window isn't visible, plus the home of out-of-band actions (popover, real Quit). The technical scaffolding (`LSUIElement = true`, dynamic activation policy) is **retained** because it serves resource hygiene (the Dock icon hides when no window is visible). What changes is the user-visible default behavior, the Quit semantics, and the absence of a standard macOS menu bar.

#### State transitions

| Trigger                                                       | Resulting state                                |
| ---                                                           | ---                                            |
| User-initiated launch (Finder, `open`, Spotlight, Launchpad)  | menu bar + Dock + window (`.regular`)          |
| SMAppService login launch                                     | menu bar only (`.accessory`); no window        |
| Close window (red button / ⌘W)                                | retreat to menu bar only (`.accessory`)        |
| ⌘Q / app-menu Quit                                            | intercepted; closes window, app stays running  |
| Status item right-click → Quit TokenTrace                    | terminate process                              |

#### Quit semantics

- ⌘Q and the app menu's Quit item both fire `NSApp.terminate(_:)`.
- `applicationShouldTerminate(_:)` intercepts, closes all windows, and returns `.terminateCancel` unless an internal flag (`userInitiatedQuit`) is set.
- Only the status item right-click "Quit TokenTrace" sets that flag before invoking terminate.
- `applicationShouldTerminateAfterLastWindowClosed(_:)` returns `false`, so closing the last window via the red button or ⌘W never auto-terminates.
- Pattern follows Stats: the app teaches the user that *close ≠ quit* by leaving the menu bar item visible after window close.

#### Standard macOS menu bar

When the window is in focus, the system menu bar hosts the conventional six-menu structure (Application / File / Edit / View / Window / Help), built programmatically as `NSApp.mainMenu`. The previous decision had no `mainMenu` defined; constructing it is part of this pivot.

#### Why pivoted

The original Decision 1 inherited ClaudeUsageBar's identity (a status-bar agent that happens to have a popover). TokenTrace's value proposition is **persistent history + dashboard analytics** — the menu bar is one of two surfaces, not the primary surface. Reframing avoids design pressure to treat the dashboard as a side feature.

The pivot was identified during implementation, before v1 ship. It is captured here as an amendment rather than overwriting the original Decision 1, so the design history (what we initially thought, what we observed, why we changed) survives in the spec artifact and not just in git log.

#### Decision 1 history

| Date       | Decision                                                                                                                                |
| ---        | ---                                                                                                                                     |
| (original) | Hybrid menu bar app; LSUIElement + dynamic activation policy switching                                                                  |
| 2026-05-07 | Reframed to window-first with menu bar accessory; added Quit semantics (⌘Q intercepted, real Quit only via status item); added standard macOS menu bar |

### Decision 2 — Persistence: SQLite via stdlib `SQLite3` C API

Use the C `SQLite3` framework that ships with macOS, not a third-party wrapper like GRDB or SQLite.swift.

**Schema:**
```sql
CREATE TABLE samples (
  ts          INTEGER NOT NULL,    -- poll time, unix epoch seconds
  bucket      TEXT    NOT NULL,    -- 'five_hour' | 'seven_day' | 'seven_day_sonnet'
  util        REAL    NOT NULL,    -- 0–100 percentage
  resets_at   INTEGER NOT NULL,    -- unix epoch seconds
  PRIMARY KEY (ts, bucket)
);
CREATE INDEX idx_samples_bucket_ts ON samples(bucket, ts);
```

Each successful poll inserts up to 3 rows (one per bucket present in the response — `seven_day_sonnet` is Pro-only and may be absent). Conflict resolution: `INSERT OR REPLACE` to handle clock skew or retries.

**Storage location:** `~/Library/Application Support/dev.louisdeng.tokentrace/usage.sqlite`.

**Estimated growth:** 5-min poll × 3 buckets × 365 days ≈ 315,000 rows/year. At ~40 bytes/row uncompressed plus indexes, ≈ 15-20 MB/year worst case. Acceptable indefinitely; no retention policy needed in v1.

**Alternatives considered:**
- *GRDB.swift*: cleaner Swift API, schema migrations, query DSL. Adds a Swift Package dependency and ~MB of binary size. Overkill for a 4-column single-table schema.
- *Core Data*: too much boilerplate, no real benefit for time-series data.
- *Append-only NDJSON file*: trivially simple but every dashboard query loads the entire history into memory. Becomes painful past ~50k rows.

**Why this choice:** zero new dependencies, schema is small enough that hand-written SQL is clearer than any ORM, and SwiftUI Charts can stream rows directly from a query result.

### Decision 3 — Charts: SwiftUI Charts (system framework, macOS 13+)

Use Apple's `Charts` framework (`import Charts`). Bumps `LSMinimumSystemVersion` from 12.0 → 13.0.

Each chart is a `Chart` view containing:
- `LineMark` per bucket for the utilization series.
- `RuleMark` per detected reset event for the vertical dashed reset markers (`dash:` line style).
- `.chartXSelection` modifier for the hover tooltip.
- `.chartXScale(domain:)` driven by the range selector state.

**Reset event detection:** at query time, walk the time-ordered samples per bucket. A reset occurred between sample N and sample N+1 if `samples[N+1].resets_at > samples[N].resets_at`. The reset's display time is `samples[N].resets_at` (the previous window's end). This is more robust than detecting `util` value drops, which could be confused with quiet periods.

**Alternatives considered:**
- *Charts library via SwiftPM (Swift Charts package, charts-ios, etc.)*: redundant given Apple's framework now ships and is good enough.
- *WebView + d3 / Chart.js*: heavyweight, breaks native feel, complicates data plumbing.
- *Custom Canvas-based drawing*: more control but a lot of work for stock chart needs.

**Why this choice:** native, zero dependencies, declarative SwiftUI API, integrates cleanly with `@Observable` data sources.

### Decision 4 — Build system: Swift Package + manual signing

Replace `app/build.sh` with a Swift Package (`Package.swift`) that produces an executable target. Wrap it in an `.app` bundle via a small shell helper (`tools/build-app.sh`) that:
1. `swift build -c release --arch arm64 --arch x86_64` for a universal binary.
2. Constructs `TokenTrace.app/Contents/{MacOS,Resources}` and copies `Info.plist` + `.icns`.
3. Runs `codesign --force --deep --sign F690B9DA81D392695487D52D35F6B37E7A362495 TokenTrace.app`.
4. Optionally `open` the result (mirroring the old `build.sh` behavior).

**Alternatives considered:**
- *Xcode project (`.xcodeproj` or `.xcodegen` config)*: more familiar to most macOS devs, but the user is new to Swift/AppKit and has been working from CLI. Swift Package + a shell wrapper is closer to the existing workflow.
- *Stay on `build.sh` with `swiftc` invocations*: works but doesn't scale to multiple modules; testing becomes painful.

**Why this choice:** lets `swift build` and `swift test` work out of the box, supports multi-file structure naturally, and the shell wrapper handles the few `.app` bundling steps that Swift Package Manager doesn't.

### Decision 5 — Module / source layout

```
TokenTrace/
├── Package.swift
├── Sources/
│   └── TokenTraceApp/
│       ├── App.swift                          ← @main, AppDelegate, activation policy
│       ├── MenuBar/
│       │   ├── StatusItemController.swift     ← NSStatusItem + icon updates
│       │   └── PopoverView.swift              ← quick-view SwiftUI body
│       ├── MainWindow/
│       │   ├── MainWindowController.swift     ← window lifecycle
│       │   ├── DashboardView.swift            ← the two charts + range selector
│       │   ├── SettingsView.swift             ← cookie / notif / login
│       │   └── MenuBarPreviewView.swift       ← shows current status item state
│       ├── Services/
│       │   ├── ClaudeAPI.swift                ← bootstrap + usage HTTP
│       │   ├── CookieKeychain.swift           ← (salvaged, lightly refactored)
│       │   └── UsageManager.swift             ← orchestrates poll → store → publish
│       ├── Persistence/
│       │   ├── UsageStore.swift               ← SQLite open/insert/query
│       │   └── Schema.swift                   ← DDL + migration helpers
│       └── Models/
│           ├── UsageSample.swift              ← (ts, bucket, util, resetsAt)
│           └── Bucket.swift                   ← enum: fiveHour, sevenDay, sevenDaySonnet
├── Resources/
│   ├── Info.plist
│   ├── TokenTrace.icns
│   └── Assets.xcassets
├── Tests/
│   └── TokenTraceAppTests/
│       ├── UsageStoreTests.swift
│       └── ResetDetectionTests.swift
├── tools/
│   └── build-app.sh
├── README.md
└── LICENSE
```

The `App.swift` is intentionally thin (lifecycle + DI wiring). `UsageManager` is the central observable that the menu bar and the dashboard both subscribe to.

### Decision 6 — UsageManager: single source of truth, observable

`UsageManager` is an `@MainActor @Observable` (or `ObservableObject` if staying on macOS 13 patterns) class that:
- Owns the polling timer.
- Holds the latest sample in memory (for menu bar / popover).
- Inserts each sample into `UsageStore`.
- Exposes `latestSample`, `isLoading`, `errorMessage`, `hasFetchedData`, etc. as published properties.
- Handles cookie loading from `CookieKeychain`, expired-session detection.

It does NOT own UI state like "is settings panel showing." That stays in views.

### Decision 7 — Bundle ID and signing

- New bundle ID: `dev.louisdeng.tokentrace` (avoids macOS 26's blacklist on `com.claude.usagebar`; documented in `TROUBLESHOOTING.md` of the old repo).
- Code signing: ad-hoc fallback for clean builds, but the build script prefers the user's local self-signed cert (hash `F690B9DA81D392695487D52D35F6B37E7A362495`) if present in the keychain.
- No notarization in v1.

## Risks / Trade-offs

- **Risk: claude.ai changes the `/api/organizations/{id}/usage` response shape.** → Mitigation: keep the parser tolerant (graceful absence of `seven_day_sonnet`, log unknown keys at debug level, fall back to "could not parse" with the response body in the log so the user can file an issue). The current code already does this; preserve the behavior.
- **Risk: SQLite write fails on every poll (disk full, sandbox issue).** → Mitigation: catch and log, but don't crash; menu bar still updates from in-memory `latestSample`. Surface a non-blocking warning in the dashboard if recent inserts have failed.
- **Risk: SwiftUI Charts performance with many points** (e.g., 30 days × 12 polls/hr × 24 hr = ~8.6k points per bucket, ×2 buckets = ~17k marks for the weekly chart at 30d range). → Mitigation: server-side downsampling at query time. For ranges beyond 7d, use SQL `GROUP BY` with bucketed time windows (e.g., one point per hour for 7d–30d, one per 6 hours for All). Implement only when measurements show actual lag.
- **Risk: macOS 26 blacklist hits the new bundle ID too.** → Mitigation: `dev.louisdeng.*` namespace was confirmed working in the old fork's testing. If it ever happens, the deep-reset procedure in `TROUBLESHOOTING.md` is now documented.
- **Risk: Activation policy switching causes window focus glitches.** → Mitigation: tested pattern in popular apps (Stats, Ice). Standard implementation; not novel.
- **Trade-off: macOS 13.0 minimum locks out anyone on macOS 12.** → Acceptable: personal-use app, user is on 26.
- **Trade-off: stdlib SQLite C API requires more boilerplate than GRDB.** → Acceptable: schema is one table; total persistence layer is probably ≤ 200 lines including tests. No dependency churn.
- **Trade-off: keeping cookie-paste auth in v1 means same friction as old app.** → Acceptable: solving auth UX is a separate, larger effort that warrants its own change. v1 ships sooner without it.

## Migration Plan

1. Develop the new app to working v1 in `~/worksapce/TokenTrace/` (new directory, new repo).
2. Install both apps in parallel: keep `dev.louisdeng.claudeusagebar` (old fork) running while the new `dev.louisdeng.tokentrace` is built and tested.
3. When confident, copy the session cookie from the old Keychain entry into the new app (one-time manual step via the new Settings UI).
4. Quit the old app; remove from `/Applications/`. Optionally clean up old Keychain entries via Keychain Access.
5. Archive the old fork repo on GitHub.

No rollback complications: the two apps are independent processes with independent stores.

## Open Questions

1. **Charts framework — `@Observable` (iOS 17 / macOS 14) vs `ObservableObject` (macOS 13)?** Sticking to `ObservableObject` keeps the macOS 13 floor; using `@Observable` would bump to macOS 14 but reduce boilerplate. Decision deferred to implementation; both work, and it can be migrated later.
2. **Range selector — should "All" cap at e.g. last 365 days for performance, or truly load everything?** Defer until there's enough data to test. Start with no cap.
3. **Should the Dashboard support exporting CSV / PNG?** Out of scope for v1, but worth noting as a likely v2 ask.
4. **Should the SettingsView use `Form` + `Section` (macOS native settings look) or a custom layout?** Defer to implementation; `Form` is the lower-risk default.
