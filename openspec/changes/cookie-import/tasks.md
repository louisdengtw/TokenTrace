## 1. Cookie parser

- [x] 1.1 Create `Sources/TokenTraceApp/Services/CookieParser.swift` with a `CookieParser.parse(_ raw: String) -> Result<String, CookieParserError>` entry point
- [x] 1.2 Implement shape detection: `curl ` prefix → curl branch; `Cookie:` (case-insensitive) prefix → strip branch; otherwise raw branch
- [x] 1.3 Implement curl extraction: collapse `\<newline>` continuations, regex on `-H ['"]cookie:\s*([^'"]+)['"]` and `--header ['"]cookie:\s*([^'"]+)['"]` (case-insensitive on header name)
- [x] 1.4 Implement final `sessionKey=` validation gate, returning a structured `CookieParserError` enum (`.missingSessionKey`, `.curlMissingCookieHeader`, `.malformed(String)`)
- [x] 1.5 Add `Tests/CookieParserTests.swift` covering all spec scenarios: raw header, `Cookie:` prefix, single-line curl, multi-line curl with `\`, `--header` form, mixed case header name, no-sessionKey rejection, curl-without-cookie rejection
- [x] 1.6 Wire `CookieParser` into `UsageManager.saveCookie(_:)` so raw cookie and parsed cookie share the same downstream Keychain write path

## 2. Settings UI changes

- [x] 2.1 Update `SettingsView.cookieSection` paste field placeholder to mention both formats ("paste cookie header or curl command")
- [x] 2.2 On Save, route through `CookieParser.parse`; on `.failure`, render an inline `Label` with the parser's error message instead of writing
- [x] 2.3 Add an "Open claude.ai" button in the cookie section that calls `NSWorkspace.shared.open(URL(string: "https://claude.ai")!)`
- [x] 2.4 Add a small footer link (e.g., "Skip the dance — install the Firefox/Zen add-on") that opens the published install instructions URL; placeholder URL until extension is published in group 5
- [x] 2.5 Verify the "viewing the stored cookie" redacted preview and "Sign out" scenarios still pass after the Save-path refactor *(manual: build, paste a cookie, reopen Settings, check preview / sign out)*

## 3. tokentrace:// URL scheme

- [x] 3.1 Add `CFBundleURLTypes` entry for the `tokentrace` scheme to the build pipeline (likely `tools/build-app.sh` Info.plist generation)
- [x] 3.2 Create `Sources/TokenTraceApp/Services/URLSchemeHandler.swift` with a single entry point `handle(_ url: URL) -> URLSchemeOutcome` that recognises only `tokentrace://import?cookie=…`; other paths return `.ignored`
- [x] 3.3 Wire `application(_:open:options:)` (or SwiftUI `.onOpenURL`) in the app shell to dispatch incoming URLs to `URLSchemeHandler`
- [x] 3.4 On `tokentrace://import?cookie=<encoded>`, URL-decode the value, activate the app, switch to the Settings tab, and pre-fill the paste field with the decoded value — but do NOT write to Keychain yet
- [x] 3.5 Surface explicit errors (in the Settings inline error slot) for missing cookie param, empty cookie value, or undecodable percent-encoding
- [x] 3.6 Audit logging: ensure neither `URLSchemeHandler` nor the AppDelegate dispatcher logs the URL's query string at any log level
- [x] 3.7 Add a test (XCTest or local harness) that simulates `URLSchemeHandler.handle(_:)` with each spec scenario URL and asserts the outcome

## 4. Foreground confirmation safety

- [x] 4.1 Confirm — by code path inspection — that there is no path from `URLSchemeHandler` to `CookieKeychain.save(_:)` that bypasses the Settings "Save" button
- [x] 4.2 Manual test: run TokenTrace with a stored valid cookie, then `open 'tokentrace://import?cookie=sessionKey%3Devil'` from Terminal, verify Keychain still holds the original cookie until the user clicks Save
- [x] 4.3 Manual test: dismiss the Settings window after URL-scheme pre-fill, reopen Settings, verify the paste field is empty (no leak across window lifecycle)

## 5. Firefox/Zen WebExtension

- [x] 5.1 Create `extension/` directory with `manifest.json` (manifest_version 3, `permissions: ["cookies"]`, `host_permissions: ["https://claude.ai/*"]`, action with default popup or click handler)
- [x] 5.2 Implement the toolbar action: call `browser.cookies.getAll({domain: "claude.ai"})`, build `name=value; …` header, validate it contains `sessionKey`, URL-encode once, open `tokentrace://import?cookie=<encoded>`
- [x] 5.3 Handle empty / no-sessionKey case: show a popup message instructing the user to sign in to claude.ai first
- [x] 5.4 Spike: verify Zen permits `tabs.create({url: "tokentrace://…"})` for custom URL schemes; if not, fall back to `window.location.href` from a popup *(manual: load extension via about:debugging in Zen and click the toolbar icon while signed into claude.ai)*
- [x] 5.5 Add minimal extension icons (16/32/48/128 px); reuse TokenTrace app icon palette
- [x] 5.6 Smoke test in `about:debugging` Temporary Add-on mode: sign into claude.ai, click toolbar icon, verify TokenTrace receives the import URL and pre-fills Settings *(manual)*

## 6. AMO unlisted distribution

- [ ] 6.1 Create AMO developer account if not already present (one-time) *(manual)*
- [ ] 6.2 Submit extension as **unlisted** / "On your own" self-distribution *(manual)*
- [ ] 6.3 Wait for automated signing; on rejection, fix manifest and resubmit *(manual)*
- [ ] 6.4 Download the signed `.xpi` and host it as a GitHub Release asset *(manual)*
- [x] 6.5 Document install steps in `extension/README.md`: download `.xpi`, `about:addons` → ⚙ → "Install Add-on From File"
- [ ] 6.6 Update the Settings hint URL (task 2.4) to point at the install docs *(deferred — placeholder URL `https://github.com/louisdengtw/TokenTrace#firefox-extension` already in code; resolve when README anchor is added in 7.1 follow-up)*

## 7. Documentation & release

- [x] 7.1 Update root `README.md` "Auth" section: mention the curl-paste alternative and the Firefox/Zen extension; keep the neutral ToS posture
- [x] 7.2 Note the new URL scheme in `README.md` (or a separate doc) so curious users understand what `tokentrace://` is for
- [x] 7.3 Cut a v1.1 release tag once parser + URL scheme + Settings UI ship; extension tagging is independent (`extension-v0.1.0`) *(manual: `git tag v1.1` after smoke tests)*
- [ ] 7.4 After at least one full week of personal use, archive this change with `openspec archive cookie-import` *(manual)*
