## Why

Cookie acquisition is TokenTrace's highest-friction step. The shipped flow asks users to find a request in DevTools, locate the `Cookie:` header, double-click-select its value, and paste — about seven manual steps. An earlier in-app WebView attempt (commit `7233746` in the predecessor `ClaudeUsageBar` fork) tried to skip DevTools by driving the magic-link sign-in flow inside an app-hosted view, but the email round-trip (mail app → click link → return) ended up more painful than the DevTools dance, and ToS posture was worse. We now have a clearer diagnosis: the bottleneck isn't *pasting*, it's *finding*. Two cheap, parallel paths address it without our app driving claude.ai's auth.

## What Changes

- **Flexible paste parser**: the cookie input field accepts either a raw cookie header (current format) **or** a full `curl` command (DevTools → Network → right-click any request → "Copy as cURL"). The parser detects shape and extracts the `Cookie` value. This collapses the user's DevTools work from "find Cookie field, select value carefully" to "right-click, Copy as cURL, paste".
- **"Open claude.ai" button**: Settings gains a button that opens the user's default browser to `https://claude.ai`, removing the URL-typing step and signalling where to start.
- **`tokentrace://` URL scheme**: TokenTrace registers a custom URL scheme. Receiving `tokentrace://import?cookie=<urlencoded>` triggers the same code path as a paste-and-save: parse → validate → Keychain → first poll.
- **Firefox/Zen WebExtension (`tokentrace-import`)**: a small WebExtension that, when the user clicks its toolbar action while signed in to claude.ai, reads the relevant cookies via `browser.cookies.getAll({domain: "claude.ai"})` (httpOnly accessible from extension context), assembles a cookie header, and hands it to TokenTrace via `tokentrace://import?cookie=…`. Distributed via AMO **unlisted self-distribution** — Mozilla automated signing only, no human review, no public listing.
- **No change** to ToS posture: the user still acquires the cookie from their own browser session; we only smooth the handoff. README's existing neutral wording stays.
- **Out of scope**: in-app WebView sign-in is explicitly *not* revived. Chrome/Safari extensions are deferred (different stores, different review surfaces). Magic-link automation is dropped for good.

## Capabilities

### New Capabilities

- `cookie-import`: covers the flexible paste parser, the `tokentrace://` URL scheme contract (path, query parameters, error handling), the Firefox WebExtension's required behavior (which cookies it reads, how it builds the header, how it hands off), and the AMO unlisted distribution constraint.

### Modified Capabilities

- `app-settings`: the existing "Cookie management UI" requirement gains: (a) the paste field SHALL accept curl-command input as an alternative form, (b) an "Open claude.ai" affordance, (c) a discoverable hint pointing to the WebExtension when relevant.

## Impact

- **New code**:
  - `Sources/TokenTraceApp/Services/CookieParser.swift` (new) — shape detection + extraction.
  - `Sources/TokenTraceApp/Services/URLSchemeHandler.swift` (new) — `tokentrace://import` routing.
  - `extension/` (new) — Firefox WebExtension source (manifest v3, popup or direct toolbar action, `cookies` + `host_permissions` for `claude.ai`).
- **Modified code**:
  - `Sources/TokenTraceApp/MainWindow/SettingsView.swift` — accept curl, add "Open claude.ai" button, hint about extension.
  - `Sources/TokenTraceApp/Services/UsageManager.swift` — expose the same save-cookie entry point used by the URL scheme handler.
  - `Sources/TokenTraceApp/AppDelegate.swift` (or equivalent) — wire `application(_:open:options:)` to the URL scheme handler.
  - `Info.plist` (in build script) — register `CFBundleURLTypes` for `tokentrace`.
- **Build / distribution**:
  - WebExtension built as a standalone artifact (zip → AMO upload → signed `.xpi` download). One-time AMO developer account setup.
  - No new runtime dependencies for the macOS app.
- **Specs touched**: new `cookie-import` capability spec; delta to `app-settings`; `claude-api-integration` is **not** modified (the Keychain storage and `org_id` resolution requirements are unchanged — only acquisition input methods grow).
- **Tests**: parser gets unit tests covering each input shape (raw header, curl from Chromium, curl from Firefox, curl from Safari, header with `Cookie:` prefix, malformed input). URL scheme handler tested via a synthetic URL. Extension manually verified against Zen.
