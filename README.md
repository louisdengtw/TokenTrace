# ClaudeUsage

Native macOS menu bar + main window app that polls `claude.ai` for personal usage and visualizes history.

- Menu bar status item with color-coded 5-hour utilization.
- Main window with a Dashboard tab (5-hour and 7-day trend charts), a Menubar Preview tab, and a Settings tab.
- Persistent local SQLite history; no telemetry, nothing leaves the device.
- Min macOS 13.0. Bundle ID `dev.louisdeng.claudeusage`.

## Build

```sh
./tools/build-app.sh
open build/ClaudeUsage.app
```

The build script produces a universal binary, assembles `ClaudeUsage.app/Contents/{MacOS,Resources}`, and signs with the user's local self-signed cert (falling back to ad-hoc).

## Auth

A full `Cookie` header from `claude.ai` is pasted into Settings and stored in the macOS Keychain (service `dev.louisdeng.claudeusage.session`). Solving the OAuth / cookie-extraction UX is out of scope for v1.

## Credits

This project was bootstrapped from [`Artzainnn/ClaudeUsageBar`](https://github.com/Artzainnn/ClaudeUsageBar) (MIT). The salvage scope is **API integration only**: the `/api/bootstrap` → `org_id` → `/api/organizations/{id}/usage` flow, the multi-signal auth-failure detection, and the Keychain wrapper. Everything else (app shell, menu bar, dashboard, settings, persistence, build system) is a fresh rewrite.

The upstream MIT license is preserved verbatim in [`LICENSE-CLAUDEUSAGEBAR`](LICENSE-CLAUDEUSAGEBAR). Each derived source file additionally carries an in-source notice.

## License

MIT — see [`LICENSE`](LICENSE).
