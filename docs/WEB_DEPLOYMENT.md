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

## 1. Point the build at a backend

The web build bundles `songspot_mobile/.env` as an asset, same as mobile:

```
API_BASE_URL=https://api.yourdomain.com/api
```

`ApiConfig.wsBaseUrl` derives the WebSocket origin from this
(`https://` → `wss://`, `/api` suffix stripped), so there is nothing else to set.

> The `.env` is publicly readable in a web build. Keep secrets out of it — it
> currently holds only public URLs.

## 2. Build

```bash
./scripts/build_web.sh
# or, to publish in the same step:
WEB_ROOT=/var/www/songspot-web ./scripts/build_web.sh
```

Serving from a sub-path? Pass `BASE_HREF=/play/`.

The output is a fully static bundle in `songspot_mobile/build/web`.

## 3. Allow the web origin on the backend

CORS is the one backend change the web client needs. Mobile clients send no
`Origin` header and are unaffected by any of this.

In `songspot_backend/.env`:

```
CORS_ALLOWED_ORIGINS=https://play.yourdomain.com
# Optional: preview deployments
# CORS_ALLOWED_ORIGIN_REGEXES=^https://.*\.yourdomain\.com$
# Defaults to CORS_ALLOWED_ORIGINS when unset:
# WEBSOCKET_ALLOWED_ORIGINS=
```

Then restart the ASGI service. Two separate mechanisms use these:

- `corsheaders` gates the **REST API** (preflight + `Access-Control-Allow-Origin`).
- `game.middleware.OriginValidatorMiddleware` gates the **duel WebSockets**,
  closing browser connections from unknown origins with code `4003`. Connections
  with no `Origin` (native apps) always pass, and an empty allowlist disables the
  check so local development needs no configuration.

In `DEBUG` with no origins configured, any `http://localhost:<port>` is allowed
so `flutter run -d chrome` works out of the box.

## 4. Serve it

Add a second nginx server block next to the API one from `DEPLOYMENT_GUIDE.md`.
Point an `A` record for `play.yourdomain.com` at the VPS and issue a certificate
before enabling it.

```nginx
server {
    listen 80;
    server_name play.yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name play.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/play.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/play.yourdomain.com/privkey.pem;

    root /var/www/songspot-web;
    index index.html;

    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Hashed build assets never change under the same name.
    location ~* \.(?:js|wasm|json|png|jpg|svg|ttf|otf|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # Never cache the entrypoint, or users get pinned to an old build.
    location = /index.html {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    location = /flutter_service_worker.js {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # Single-page app: unknown paths fall back to the entrypoint.
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

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
`WebSocket rejected disallowed origin=` — that is `WEBSOCKET_ALLOWED_ORIGINS`
missing your web origin.

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
