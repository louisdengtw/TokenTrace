# TokenTrace

A personal monitoring tool for your `claude.ai` subscription usage. It polls
your account's utilization on a cadence, stores it locally, and shows the
trend over time — the history view that Claude itself doesn't surface.

- Menu bar quick view: 5-hour / 7-day / 7-day Sonnet at a glance, color-coded.
- Dashboard: trend charts with reset markers, hover crosshair, and a range
  selector with chip presets (24h / 7d / 30d / All) plus custom From/To.
- Export Report: produce a self-contained HTML report from your local data
  (Dashboard toolbar → Export Report…, or File menu / ⌘E).
- Persistent local SQLite store; nothing leaves your machine.
- Threshold notifications when you're approaching session limits.
- Native SwiftUI on macOS 13+.

## Build

```sh
make            # show targets
make build      # universal .app at build/TokenTrace.app
make install    # build + copy to /Applications/
make run        # build + install + relaunch
make test       # swift test
make clean
```

`make build` shells out to `tools/build-app.sh`, which produces a universal
binary, assembles `TokenTrace.app/Contents/{MacOS,Resources}`, and signs with
the user's local self-signed cert (falling back to ad-hoc).

## Auth

A full `Cookie` header from `claude.ai` is pasted into Settings and stored in
the macOS Keychain. The cookie never leaves your device. There is no
third-party OAuth and no programmatic sign-in — Anthropic does not currently
expose either for personal subscriptions, so manual paste is the only
practical path.

The Settings paste field accepts either a raw cookie header (`sessionKey=…`)
or a complete `curl` command from a browser DevTools "Copy as cURL" action —
the cookie value is extracted automatically. There is also an "Open
claude.ai" button that opens your default browser at the right URL, so
you don't need to retype it.

For Firefox / Zen / LibreWolf users, an optional WebExtension at
[`extension/`](extension/) skips the DevTools step entirely: install the
add-on, sign into claude.ai, click the toolbar icon, then click "Save" in
TokenTrace. See [`extension/README.md`](extension/README.md) for install
instructions. The add-on is distributed as a Mozilla-signed `.xpi` via AMO
unlisted self-distribution; it is not listed in the AMO public search.

The app registers a `tokentrace://` URL scheme used by the WebExtension to
hand off the cookie. URL-scheme imports are never silently saved — they
pre-fill the Settings paste field and require an explicit "Save" click.

## Credits

The reverse-engineered `claude.ai` web API integration in
`Sources/TokenTraceApp/Services/ClaudeAPI.swift` is derived from
[`Artzainnn/ClaudeUsageBar`](https://github.com/Artzainnn/ClaudeUsageBar)
(MIT). That file carries an in-source notice; upstream's MIT terms are
preserved verbatim in
[`LICENSE-CLAUDEUSAGEBAR`](LICENSE-CLAUDEUSAGEBAR).

Everything else — app shell, dashboard, persistence, build system,
settings, menu bar, popover, keychain integration — is independent work.

## License

MIT — see [`LICENSE`](LICENSE).
