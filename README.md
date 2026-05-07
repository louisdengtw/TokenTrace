# TokenTrace

A personal monitoring tool for your `claude.ai` subscription usage. It polls
your account's utilization on a cadence, stores it locally, and shows the
trend over time — the history view that Claude itself doesn't surface.

- Menu bar quick view: 5-hour / 7-day / 7-day Sonnet at a glance, color-coded.
- Dashboard: trend charts with reset markers, hover crosshair, and a range
  selector (24h / 7d / 30d / All).
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
