# SongSpot

A music guessing game in the spirit of Heardle: a short snippet plays, you guess the song, and each miss reveals a longer one. Play solo, in private rooms with friends, or in real-time 1v1 duels.

SongSpot is built as a full-stack portfolio project: a Django backend, a Flutter client for iOS, Android and the web, and the CI/CD and monitoring around them.

## Stack

| Layer | Technology |
|---|---|
| Mobile / web | Flutter, Provider |
| Backend | Django 6, Django REST Framework, JWT (SimpleJWT) |
| Real time | Django Channels, Daphne, Redis |
| Database | PostgreSQL |
| Security | django-axes, django-ratelimit, throttling per endpoint |
| Monitoring | Sentry, Grafana |
| Delivery | GitHub Actions, Fastlane, Docker Compose, nginx on a VPS |

## Repository layout

- `songspot_backend/`: Django project (`authentication`, `game` apps)
- `songspot_mobile/`: Flutter app (iOS, Android, web)
- `docs/`: API reference, deployment, search benchmarks and design notes
- `scripts/`: deployment, backup and benchmark tooling
- `.github/workflows/`: CI, backend and web deployment

## Running it locally

See [`docs/LOCAL_DEV_GUIDE.md`](docs/LOCAL_DEV_GUIDE.md). Copy `songspot_backend/.env.example` and `songspot_mobile/.env.example` and fill in your own values; no credentials are shipped with the repository.

## Music and data

SongSpot does not host or redistribute any audio. Track metadata and 30-second previews are fetched from the [Deezer API](https://developers.deezer.com/) and remain the property of Deezer and the respective rights holders. This project is not affiliated with or endorsed by Deezer. The game is not distributed commercially.

## License

Copyright © 2026 Ethan Saux.

Released under the [GNU Affero General Public License v3.0](LICENSE). If you run a modified version of this software as a network service, you must make your modified source available to its users.
