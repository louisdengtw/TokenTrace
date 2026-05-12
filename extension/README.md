# TokenTrace Cookie Import — Firefox / Zen WebExtension

Sends your `claude.ai` session cookie to the TokenTrace macOS app in one
click, so you don't have to open DevTools or paste cURL.

## How it works

1. You're signed into `claude.ai` in Firefox / Zen / LibreWolf.
2. You click the TokenTrace toolbar icon.
3. The extension reads `claude.ai` cookies via `browser.cookies.getAll`
   and assembles a `Cookie:` header.
4. It opens `tokentrace://import?cookie=<urlencoded>` in a new background
   tab, which macOS routes to the TokenTrace app.
5. TokenTrace activates, opens **Settings**, and pre-fills the paste field.
   **You still click "Save" yourself** — the app never silently overwrites
   your stored cookie.

The extension has minimum permissions: `cookies` plus the host permission
`https://claude.ai/*`. No content scripts, no telemetry, no background
fetches.

## Install

### Permanent (recommended for daily use)

1. Download the latest `tokentrace-import-<version>.xpi` from this repo's
   [Releases page](https://github.com/louisdengtw/TokenTrace/releases).
   The `.xpi` is signed by Mozilla (AMO unlisted self-distribution).
2. In Zen / Firefox, open `about:addons`.
3. Click the gear icon ⚙ → **"Install Add-on From File…"**.
4. Pick the downloaded `.xpi`.
5. Pin the TokenTrace icon to your toolbar.

### Temporary (development / testing)

1. Open `about:debugging#/runtime/this-firefox` in Zen / Firefox.
2. Click **"Load Temporary Add-on…"**.
3. Pick `extension/manifest.json` from this repo.

The temporary install disappears on browser restart — fine for testing.

## Build for AMO submission

Zip the contents of this directory (not the directory itself) into a single
`.zip` file:

```sh
cd extension/
zip -r ../tokentrace-import-0.1.0.zip . -x ".*" -x "README.md"
```

Submit to [addons.mozilla.org](https://addons.mozilla.org/en-US/developers/)
as **"On your own"** (self-distribution). Mozilla performs automated
validation and signing only — no human review for unlisted submissions.
Download the resulting signed `.xpi` and attach to a GitHub Release.

## License

MIT, same as the parent project.
