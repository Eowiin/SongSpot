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

## 2. Build

SongSpot serves the web client from **`/play/` on the same origin as the API**
(`https://songspot.eowinstudio.com/play/`). Same origin is the whole point: the
browser sends no cross-origin request, so CORS and the WebSocket origin
allowlist have nothing to allow, and there is no extra DNS record or
certificate to keep alive.

```bash
BASE_HREF=/play/ ./scripts/build_web.sh
# or, to publish in the same step:
BASE_HREF=/play/ WEB_ROOT=/var/www/songspot-web ./scripts/build_web.sh
```

`BASE_HREF` must match the path nginx serves the bundle from, or every asset
request 404s. The output is a fully static bundle in `songspot_mobile/build/web`.

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

The bundle is static files inside the existing nginx server block — no second
block, no second certificate. Add this **above** the `location /` that proxies
to Django, so the marketing site and the API keep their routes:

```nginx
# Flutter web client. Same server block as the API: same origin, no CORS.
location /play/ {
    alias /var/www/songspot-web/;
    try_files $uri $uri/ /play/index.html;   # single-page app fallback

    # Hashed build assets never change under the same name.
    location ~* \.(?:js|wasm|json|png|jpg|svg|ttf|otf|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}

# Never cache the entrypoint, or users get pinned to an old build.
location = /play/index.html {
    alias /var/www/songspot-web/index.html;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}
location = /play/flutter_service_worker.js {
    alias /var/www/songspot-web/flutter_service_worker.js;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
}
```

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

- **Album art does not render on the web build.** `Image.network` in the game
  screen fetches the cover (HTTP 200, correct bytes) but paints nothing, with no
  exception and without firing `errorBuilder`. Ruled out: CORS (the CDN sends
  `access-control-allow-origin: *` and an in-page `fetch`/XHR of the same URL
  returns the full body), Deezer specifically (a same-origin PNG fails the same
  way), the `BackdropFilter` reveal blur (disabling it changes nothing), and
  progressive JPEG (Chrome's `createImageBitmap` and `ImageDecoder` both decode
  the covers fine). Not yet root-caused — the artwork box shows as a flat
  placeholder in the browser.
