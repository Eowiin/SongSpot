# Stems Pack Guide

This guide explains how to store and serve stem-based packs for SongSpot.

## Overview

Packs are meant for "guess by instrument" gameplay. Each pack track stores up to four stem URLs:
- `vocals_url`
- `drums_url`
- `bass_url`
- `other_url`

These stems are attached to `PackTrack` and are independent from the daily song.

## Data Model

- `SongPack`: Pack metadata (name, description, price, icon)
- `PackTrack`: Links a `Track` to a pack + stem URLs

Fields added to `PackTrack`:
```
vocals_url
drums_url
bass_url
other_url
```

## Recommended Stem Format

- Format: MP3 or AAC for mobile compatibility
- Bitrate: 96-192 kbps
- Length: 20-30 seconds per stem (to match gameplay)
- Loudness: normalize stems so switching between instruments is consistent

## Storage

Store stems on a CDN or object storage (S3, GCS, Cloudflare R2). Use public HTTPS URLs.

Notes:
- Do not store stems in the repo.
- URLs should be stable; the app does not re-fetch stems unless you update URLs.
- For local development, stems are served from `MEDIA_URL` (`/media/`) when `DEBUG=True`.

## Generating Stems (Demucs)

Use the management command to generate stems and attach URLs to `PackTrack`:
```bash
python manage.py generate_pack_stems --pack-track-id <PACK_TRACK_UUID>
```

Generate stems for all tracks in a pack:
```bash
python manage.py generate_pack_stems --pack-id <PACK_UUID>
```

Generate stems for all missing stems:
```bash
python manage.py generate_pack_stems --all --missing-only
```

By default the command downloads the track preview URL and runs Demucs.
To use a local file:
```bash
python manage.py generate_pack_stems --pack-track-id <PACK_TRACK_UUID> --source /path/to/song.mp3
```

## SSL Setup (macOS)

If Demucs fails with `CERTIFICATE_VERIFY_FAILED` while downloading the model,
your local Python SSL certs are missing. Fix it once, then rerun the command:

```bash
python -m pip install --upgrade certifi
export SSL_CERT_FILE="$(python -m certifi)"
```

If you installed Python from python.org, you can also run:
```bash
/Applications/Python\ 3.13/Install\ Certificates.command
```

## Cleanup (Auto-Delete)

Stems are removed after a TTL (hours) using:
```bash
python manage.py cleanup_stems --max-age-hours 72
```

You can set the default TTL with:
```
STEM_TTL_HOURS=72
```

## Daily Preparation (UTC)

To preselect daily songs and daily pack tracks at a fixed UTC time:
```bash
python manage.py prepare_daily_content --generate-stems
```

## Admin Workflow (Manual)

1. Create a `SongPack` in Django admin.
2. Add `PackTrack` entries.
3. Paste stem URLs into the `vocals_url`, `drums_url`, `bass_url`, `other_url` fields.
4. Keep `order_in_pack` 1-30.

## API Responses

`GET /api/game/packs/{pack_id}/` includes:
```
tracks: [
  {
    track: { ... },
    order_in_pack: 1,
    vocals_url: "...",
    drums_url: "...",
    bass_url: "...",
    other_url: "..."
  }
]
```

Pack bundle session now returns absolute stem URLs:
```
GET /api/game/rooms/{room_id}/packs/{pack_id}/bundle/
{
  session: { ... },
  stems: [
    { type: "drums", url: "http://<host>/media/stems/..." },
    ...
  ]
}
```

## Mobile Playback

The pack detail screen loads stems directly from the URLs.
- If a stem URL is missing, the button is disabled.
- Stems are currently played using the same audio service as the daily song.

## Bundle Gameplay Rules

- Pack mode uses the same guess target as the daily song (title + artist).
- No time limit per stage.
- Fixed stage order: drums → bass → other → vocals.
- Each stage adds a new stem on top of the previous ones.
- One guess per stage (or skip to move forward).
- Points decrease by stage (4 → 3 → 2 → 1).
- Pack can be completed only once per user per room.
- Pack bundle uses the daily pack track (one new track per room/pack/day, UTC).

## Bundle Results + Chat

Leaderboard (per room/pack/day):
```
GET /api/game/rooms/{room_id}/packs/{pack_id}/bundle/leaderboard/
```

Chat (scoped per room/pack/day):
```
GET /api/game/rooms/{room_id}/packs/{pack_id}/bundle/messages/?limit=50&offset=0
POST /api/game/rooms/{room_id}/packs/{pack_id}/bundle/messages/
```

## Next Ideas (Optional)

- Add stem guessing sessions (scoring, streaks) in a dedicated endpoint.
- Add a stem preview endpoint to validate URLs before purchase.
- Support more stems (e.g., piano, guitar) if needed.
