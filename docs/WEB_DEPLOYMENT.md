# Web Client Deployment

SongSpot's web client is the **same Flutter app** as the mobile builds, compiled
for the browser (`songspot_mobile/web/`). There is no second codebase: the game
logic, the duel WebSocket protocol and the scoring rules are shared, which is
what makes cross-platform 1v1 work without any extra server code.

## What is platform-specific

| Concern | Mobile | Web |
| --- | --- | --- |
| WebSocket transport | `IOWebSocketChannel` (custom headers, ping interval) | browser `WebSocket` — auth token goes in the query string |
| Token storage | Keychain / Keystore | WebCrypto + `localStorage` (`flutter_secure_storage_web`) |
| Audio focus | `audio_session` | browser-managed; the plugin call is skipped |
| Push notifications | FCM | not enabled — the settings toggles are hidden |
| Data export | temp file + native share sheet | browser download (Blob + `<a download>`) |
| Layout | phone layout | same screens, widened past 900px (see below) |

The conditional imports live in `lib/services/websocket_channel_factory.dart`,
`lib/services/file_saver.dart` and `lib/services/boot_splash.dart`.

## Layout

There is no separate desktop UI. `lib/config/responsive.dart` gives every screen the
same vocabulary:

- `Breakpoints.wide` (900px) and `context.isWide` — the single switch between the
  phone layout and the desktop one.
- `context.pageGutter` — page margin that grows with the viewport.
- `ResponsiveCenter(maxWidth:)` — bounds content without boxing in the background.
- `gridColumnsFor(width)` — column count for tile grids.

Above the breakpoint: the home cards sit side by side, the category grid grows to
3–4 columns, and the solo and duel game screens split into two columns (artwork and
playback on the left, input on the right). Below it, every screen keeps the exact
phone layout — in particular the guess field stays pinned above the soft keyboard,
which is why the game and duel screens have separate `_buildWide*` / `_buildNarrow*`
bodies rather than one adaptive tree. **Change the narrow body when you change phone
behaviour.**

## Playing with a keyboard and a mouse

A browser player never touches the screen, so the two inputs a phone build can
ignore have to be handled explicitly.

**Keyboard.** `lib/widgets/guess_field.dart` is the shared search box used by
the solo game and the duel:

| Key | Effect |
| --- | --- |
| `↑` / `↓` | move the highlight through the results |
| `Enter` | pick the highlighted result (the first one by default) |
| `Esc` | clear the box |
| `Space` / `R` | replay the snippet |
| `Enter` (answer revealed) | next song / see results |

The arrow keys work because `GuessField` binds them in a `Shortcuts` widget
*nearer* than `DefaultTextEditingShortcuts`, which lives at the app root; the
actions disable themselves when there is nothing to navigate so the keys fall
back to moving the caret. The same trick gates `Space` and `R`: the game and
duel screens hold a dedicated `_shortcutFocus` node, and the replay action only
fires while that node has primary focus — so `Space` still types a space in the
guess box and still activates whichever button was tabbed to.
`test/guess_field_test.dart` covers the lot.

On a wide viewport the guess box takes focus when a track loads and the results
hang *below* it, like any browser dropdown. On a phone the list stays *above*
the box, because the box is pinned over the soft keyboard.

**Pointer.** `lib/widgets/pressable.dart` wraps anything clickable in a pointer
cursor, a hover lift and a focus ring. A bare `GestureDetector` gives none of
those in a browser, which made half the home screen read as decoration. Use
`Pressable` for new tappable surfaces; `ListTile` and the Material buttons
already carry their own hover states.

## Design language

The app and the marketing site share one system, and the tokens are mirrored on
both sides — `lib/config/app_theme.dart` and the `:root` block in
`songspot_backend/templates/site/base.html`. Same palette, near-square corners
(4px on controls, 6px on large surfaces), hairline rules instead of shadows, and
heavy uppercase display type. `AppTheme.display/title/kicker/action` are the
type ramp; `SectionLabel` and `RuledPanel` in `lib/widgets/pressable.dart` are
the shared editorial pieces. Change a token in one place and change it in the
other, or the two drift.

## 1. Point the build at a backend

The web build bundles `songspot_mobile/.env` as an asset, same as mobile:

```
API_BASE_URL=https://songspot.eowinstudio.com/api
```

`ApiConfig.wsBaseUrl` derives the WebSocket origin from this
(`https://` → `wss://`, `/api` suffix stripped), so there is nothing else to set.

> The `.env` is publicly readable in a web build. Keep secrets out of it — it
> currently holds only public URLs.

The `.env` on a developer's machine is not the one that ships: it is untracked,
and the one on a Mac set up for local work points at `localhost:8000`. The
deploy workflow writes its own from the repository variables below, so a local
`.env` can never reach the deployed client. **A store build has no such
safeguard** — Fastlane bundles whatever `.env` is on the machine, so check it
before building for the App Store or Play Store.

## 2. Build and publish

SongSpot serves the web client from **`/play/` on the same origin as the API**
(`https://songspot.eowinstudio.com/play/`). Same origin is the whole point: the
browser sends no cross-origin request, so CORS and the WebSocket origin
allowlist have nothing to allow, and there is no extra DNS record or
certificate to keep alive.

`BASE_HREF` must match the path nginx serves the bundle from, or every asset
request 404s.

### Automatically (`.github/workflows/web-deploy.yml`)

A push to `main` that touches the bundle — `songspot_mobile/**` minus the
`android/`, `ios/` and `test/` trees — builds the release bundle and rsyncs it
to the VPS. `workflow_dispatch` runs the same thing on demand, which is how to
redeploy without a code change.

It reuses the backend deploy's SSH secrets (`VPS_SSH_PRIVATE_KEY`, `VPS_HOST`,
`VPS_USER`, and optionally `VPS_PORT` and `VPS_HOST_KEY`). Everything else is a
repository *variable*, with a default, because none of it is secret:

| Variable | Default | What it sets |
| --- | --- | --- |
| `WEB_API_BASE_URL` | `https://songspot.eowinstudio.com/api` | the API the bundle talks to |
| `WEB_SERVER_URL` | `https://songspot.eowinstudio.com` | origin behind the legal links in Settings |
| `WEB_BASE_HREF` | `/play/` | path nginx serves the bundle from |
| `VPS_WEB_ROOT` | `/var/www/songspot-web/play` | directory rsync writes to |
| `WEB_PUBLIC_URL` | `https://songspot.eowinstudio.com/play/` | URL the final check fetches |

The deploy user must own `VPS_WEB_ROOT` — the workflow runs no `sudo`. The last
step fetches the deployed page and fails the run unless the served `index.html`
carries the expected `<base href>`, which is the one way a base-href mismatch
shows up before players do: the index loads fine and every asset behind it 404s.

### By hand

The same build, for a first deploy or when Actions is not an option:

```bash
BASE_HREF=/play/ ./scripts/build_web.sh
rsync -avz --delete songspot_mobile/build/web/ <user>@<vps>:/var/www/songspot-web/play/
```

`WEB_ROOT=... ./scripts/build_web.sh` publishes in the same step, but its rsync
is *local* — it is for running the script on the VPS, which has no Flutter, not
for pushing from a laptop.

## 3. Backend configuration

**Nothing to configure.** Same-origin requests carry no `Origin` header
restriction to satisfy:

- `corsheaders` is not consulted, because the request is not cross-origin.
- `game.middleware.OriginValidatorMiddleware` sees an `Origin` matching the
  host and lets the duel WebSocket through.

`CORS_ALLOWED_ORIGINS` and `WEBSOCKET_ALLOWED_ORIGINS` stay empty in production.
They only matter if the web client is ever moved to its own subdomain, in which
case both must list it, and this section becomes required rather than optional.

In `DEBUG` with no origins configured, any `http://localhost:<port>` is allowed
so `flutter run -d chrome` works out of the box.

## 4. Serve it

One-time setup on the VPS, and the only part no workflow does for you. The
bundle is static files inside the existing nginx server block — no second
block, no second certificate. Add this **above** the `location /` that proxies
to Django, so the marketing site and the API keep their routes:

The bundle goes in a directory literally named `play` under the web root —
`/var/www/songspot-web/play/` — so the location can use `root` and let nginx
append the whole URI. `alias` would work too, but it does not survive contact
with `try_files` or with a nested location, and both are needed here.

```nginx
# Flutter web client. Same server block as the API: same origin, no CORS.
location /play/ {
    root /var/www/songspot-web;              # serves /var/www/songspot-web/play/...
    try_files $uri $uri/ /play/index.html;   # single-page app fallback

    # Flutter's web output carries NO content hash in its filenames: every
    # build ships main.dart.js, flutter_bootstrap.js and assets/ under those
    # same names. Anything cached long here pins a returning player to an old
    # main.dart.js beside a freshly fetched index.html — a mismatched app that
    # a reload does not fix. Revalidate instead: nginx answers an unchanged
    # file with a 304 and no body.
    add_header Cache-Control "no-cache";
}
```

That single `no-cache` covers the entrypoint, the service worker and the app
code in one rule. `no-cache` is not `no-store`: the browser keeps the file and
asks whether it is still current, so a returning player re-downloads only what
actually changed in the deploy.

The landing page links to `/play/` through the `play_url` template variable
(`songspot_backend/songspot/context_processors.py`), so if the path ever
changes, set `WEB_APP_URL` in the backend `.env` and the whole site follows.

HTTPS is not optional: `flutter_secure_storage_web` needs WebCrypto, which
browsers only expose in a secure context (`localhost` counts during dev).

## 5. Verify cross-platform 1v1

Matchmaking is ELO-based and entirely server-side — `MatchmakingConsumer` has no
notion of platform, so a web player and a phone player land in the same queue by
construction. To confirm end to end:

1. Sign in on the web client and on a phone with **two different accounts**.
2. Start a 1v1 on both within the same matchmaking window.
3. Both should reach the same `match_id` and play the same rounds in step.

If the browser side never leaves the queue, check the ASGI logs for
`WebSocket rejected disallowed origin=`. On the same-origin setup that should
never appear; if it does, the bundle is being served from a different host than
the API and `WEBSOCKET_ALLOWED_ORIGINS` has to list it.

## Known browser behaviours

- **Audio needs a user gesture.** The app never autoplays: `loadNextSong()` only
  loads audio, and playback always starts from a tap on the play control. That is
  what keeps it compatible with browser autoplay policies — keep it that way.
- **Media preload is deferred in background tabs.** A snippet may not finish
  loading until the tab is in the foreground. This is a browser policy, not an
  app bug, and it makes headless/background automation of the audio path
  unreliable.
- **Expired Deezer preview URLs fail slowly in the browser.** A stale
  `hdnea` token makes `setUrl` hang rather than error, so the client waits out its
  15s timeout before refreshing the URL and retrying. It recovers, but the first
  song after a long idle period can be slow to start.

## Known issues

None open. The album art used to paint nothing in the browser — `Image.network`
fetched the cover (HTTP 200, correct bytes) and drew a flat placeholder, with no
exception and no `errorBuilder`, after CORS, Deezer, the reveal blur and
progressive JPEG had each been ruled out. The covers render on the deployed
build (confirmed by playing it on 2026-08-30), so the guessing screen's rewrite
into `SnippetStage` and `CoverBackdrop` took the bug with it. Worth knowing if
it ever comes back, since none of the obvious causes was the cause.
