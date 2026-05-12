## Context

TokenTrace v1 ships with a single cookie acquisition path: open DevTools, find a request, copy the `Cookie` header value, paste into Settings. Empirically that's ~7 manual steps. A predecessor experiment (commit `7233746` in the `ClaudeUsageBar` fork) tried to skip DevTools by hosting an in-app `WKWebView` that drove claude.ai's email magic-link flow and harvested cookies via `WKHTTPCookieStore`. The Google Sign-In button was hidden because GIS refuses to render in WebView contexts. The remaining email round-trip (mail app → click link → return to app) turned out to be **more** painful than the DevTools dance, and the ToS posture (our app driving the auth flow) was worse than the user-pastes-their-own-cookie posture. That branch was abandoned; only `CookieKeychain.swift` was salvaged into TokenTrace.

Constraints that shape this design:
- `sessionKey` is httpOnly. No page-context JS (bookmarklet, content script, page-injected snippet) can read it.
- We control a macOS app and can register URL schemes, but cannot read another browser's cookie database.
- Browser **WebExtensions** can read httpOnly cookies via the `cookies` API (different sandbox from page JS).
- Louis uses Zen Browser (Firefox-based fork). Firefox WebExtensions install in Zen unchanged; AMO unlisted self-distribution gives a permanent install without public listing or human review.
- Anthropic ToS § 3 catches polling regardless of mechanism (per memory `project_anthropic_tos_compliance.md`); the user-acquires-own-cookie posture is the defensible stance, and this change preserves it.

## Goals / Non-Goals

**Goals:**
- Reduce cookie acquisition from ~7 steps to ~3 (universal path) and to ~1 (Zen/Firefox path).
- Keep the user as the actor that obtains the cookie from claude.ai. We never drive claude.ai auth.
- Add cookie acquisition as a *new* surface; do not modify the Keychain storage layer or `claude-api-integration` requirements.
- Be reversible: the feature lives in a self-contained capability that can be removed wholesale if Anthropic ToS shifts.

**Non-Goals:**
- Reviving the in-app WebView sign-in (B5). Permanently dropped.
- Chrome / Safari extensions. Different stores, different review surfaces, App Store requires paid Apple Developer; deferred until there's user demand.
- Magic-link automation of any kind.
- Multi-account support. The current `CookieKeychain` is single-slot; this change does not expand that.
- Solving the rolling-session-expiry problem (separate concern, deferred).

## Decisions

### D1. Two parallel paths, not one

| Path | Reach | Friction | When it wins |
|---|---|---|---|
| Flexible paste parser (B1.2) | Universal — any browser | ~3 steps (DevTools → Copy as cURL → paste) | Default fallback; works on first install before extension exists |
| Firefox/Zen WebExtension (B6) | Firefox + forks (Zen, LibreWolf, Waterfox) | ~1 step (click toolbar) | Daily use for Louis; future Firefox-using contributors |

**Why both, not just the cheaper one**: Extension is gated by AMO submission, requires a separate install, and excludes ~70% of browsers. Parser is universal and works the moment v1.1 ships. Extension layered on top is pure UX win for whoever installs it.

**Alternative rejected**: Ship parser only, defer extension. Rejected because the extension's incremental cost is small (~half day) and Louis's daily flow benefits the most.

### D2. Parser: shape detection by prefix

```
trim input
  ├─ matches /^curl\b/i              → curl mode: regex-extract -H 'cookie: …'
  ├─ matches /^Cookie:\s*/i          → strip prefix, return rest
  └─ otherwise                       → treat as raw cookie header
validate: must contain "sessionKey="; otherwise reject with explanatory error
```

Curl extraction regex (case-insensitive on the header name only):
```
-H\s+(['"])(?i:cookie):\s*([^'"]+)\1
--header\s+(['"])(?i:cookie):\s*([^'"]+)\1
```

Pre-pass collapses backslash-newline continuations so multi-line curl commands match.

**Alternative rejected**: full curl-command parser library. Overkill — we only need one header field and the realistic input shapes are bounded. ~50 lines of Swift + tests is enough.

**Edge cases declared out of scope**: Windows PowerShell `^^`-escaped curl; `Cookie:` values containing matched quote characters (claude.ai cookies are URL-safe in practice).

### D3. URL scheme `tokentrace://` over native messaging

| Mechanism | Pros | Cons |
|---|---|---|
| URL scheme | No host JSON file to install; works without extra setup; Firefox `tabs.create` invokes macOS handler | Cookie briefly visible in URL; any process can fire `open tokentrace://import?cookie=…` |
| Native messaging | Strict 1-to-1 binding between extension and app via JSON manifest at `~/Library/Application Support/Mozilla/NativeMessagingHosts/`; no cookie in URL | Extra installer step; harder to debug; brittle to path changes |

**Choice: URL scheme.** Simpler to ship, simpler to remove, doesn't require a separate post-install step. The "any process can fire it" concern is mitigated by D5 (foreground confirmation).

**Alternative rejected**: local HTTP listener on `localhost:<port>`. Forces us to bind a port (firewall prompt, port collision), worse trade-off than URL scheme.

### D4. AMO unlisted self-distribution

Submit to addons.mozilla.org marked **unlisted / self-distribution**:
- Mozilla performs **automated signing only** (manifest validation, API surface check). No human review.
- We download the signed `.xpi` and host it ourselves (e.g., GitHub Releases attachment).
- Users install via `about:addons` → ⚙ → "Install Add-on From File".
- Permanent install, survives browser restarts.

**Alternative rejected — `about:debugging` Temporary Add-on**: dies on browser restart; fine for development but bad daily UX.

**Alternative rejected — AMO listed**: requires human review (days), public listing, and we don't want random users finding the extension before we're ready. We can convert unlisted → listed later with one click if we ever want to.

**Alternative rejected — disable signature enforcement**: only works on Firefox Developer Edition / Nightly; Zen (release-channel based) almost certainly enforces signatures.

### D5. Foreground confirmation on URL scheme import

When TokenTrace receives `tokentrace://import?cookie=…`, it does **not** silently overwrite the stored cookie. It activates the app, opens Settings, pre-fills the paste field with the incoming cookie (redacted preview shown), and requires the user to click "Save".

**Why**: the URL scheme is a public attack surface — any local process or malicious webpage with a `<a href="tokentrace://import?cookie=evil">` can attempt to plant a hostile cookie. A foreground confirmation step neutralises this without making the happy path appreciably slower (one click).

**Alternative rejected**: silent import. One step shorter but converts the URL scheme into a remote-controlled cookie-write primitive. Not worth it.

### D6. WebExtension scope: cookies + claude.ai only

Manifest v3, minimal permissions:
```
permissions: ["cookies"]
host_permissions: ["https://claude.ai/*"]
```

Extension reads cookies via `browser.cookies.getAll({domain: "claude.ai"})`, builds the header by joining `name=value` pairs with `; `, URL-encodes once, and opens `tokentrace://import?cookie=<encoded>` via `browser.tabs.create` or `browser.windows.openURL` (whichever Zen accepts — see Open Questions).

No content scripts. No background fetch. No telemetry. No third-party origins. This minimal surface is what makes AMO automated signing fast.

### D7. Capability boundary

`cookie-import` owns: parser, URL scheme contract, extension contract.
`app-settings` owns: the Settings UI that exposes parser input and "Open claude.ai" button.
`claude-api-integration` is **not** modified — its requirements ("resolve org_id", "fetch usage", "store cookie in Keychain") are unchanged. The new entry points all converge on the existing `UsageManager.saveCookie(_:)` call.

This boundary makes the feature deletable: removing the `cookie-import` capability and the `app-settings` delta restores v1 behavior without touching the API client.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| AMO automated signing rejects extension | Minimal manifest (D6); cookies+host_permissions only; if rejected, dev path is `about:debugging` Temporary, ship parser-only path first |
| Zen blocks `tabs.create` to custom URL scheme | Spike early (Open Questions); fallback is `window.location.href = "tokentrace://…"` from popup; second fallback is "copy to clipboard" within the extension popup |
| Cookie leaks to shell history if user invokes URL scheme manually | Documented anti-pattern; `tokentrace://` not advertised as a CLI tool; AppDelegate handler does not log the URL |
| URL scheme abused by hostile webpage | D5 foreground confirmation neutralises silent overwrite |
| Anthropic ToS posture shifts | D7 capability isolation lets the entire feature be removed by deleting one capability and one delta; `claude-api-integration` unchanged |
| Parser misclassifies pasted text | `sessionKey=` validation gate catches all realistic miss-cases; explicit error message tells the user what to paste |
| Future cookie value contains characters that break our regex | Regression test with actual cookies; if we hit this, switch to a tolerant parser (worst case ~20 more lines) |

## Migration Plan

No data migration. Existing Keychain entry is unchanged; this change only adds new ways to write to it.

Rollout sequence:
1. Ship parser + "Open claude.ai" button + URL scheme handler in v1.1. No extension yet.
2. After v1.1 stabilises, build extension, submit to AMO unlisted, host signed `.xpi` on GitHub Releases.
3. Add a Settings hint pointing to the extension installation page.

Rollback: removing the `cookie-import` capability + `app-settings` delta + reverting Settings UI restores v1 behavior. Extension can stay published or be unpublished from AMO independently.

## Open Questions

1. **Does Zen pass `tabs.create({url: "tokentrace://…"})` through to macOS?** Firefox prompts on unknown schemes. May need popup workflow or `window.location.href` fallback. Resolve via spike before extension MVP.
2. **AMO unlisted turnaround time** for a cookies-only extension — minutes? hours? Decides whether we treat AMO as part of CI or as a one-time manual step. First submission will tell us.
3. **Confirmation UX for D5**: is "open Settings with pre-filled paste" the right shape, or is a dedicated modal sheet better? Defer until specs phase or implementation, when SwiftUI shape is concrete.
4. **Should the extension validate the cookie before handoff?** E.g., ping `/api/bootstrap` from the extension and confirm `account != null` before sending to TokenTrace. Pro: fewer "session expired" surprises. Con: doubles the request count and adds a permission. Lean toward no for v1.1.
5. **Does AMO-signed XPI need re-signing on every version bump?** Yes (each version is signed separately) — confirms whether we want to script the upload step.
