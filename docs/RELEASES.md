# Release Process

Version format in `pubspec.yaml`: **`major.minor.patch+build`**

| Segment | Meaning | Example |
|---|---|---|
| `major` | Breaking redesign | 1.x.x → 2.0.0 |
| `minor` | New feature | 1.1.x → 1.2.0 |
| `patch` | Bug fix | 1.1.0 → 1.1.1 |
| `+build` | Auto-incremented on every deploy | +3 → +4 |

---

## Deploy (Fastlane)

Version bumping is **automatic** — no need to run anything before deploying.

### iOS

```bash
cd songspot_mobile/ios

fastlane testflight              # patch bump → TestFlight
fastlane testflight bump:minor   # minor bump → TestFlight
fastlane app_store bump:minor    # minor bump → App Store (direct)
```

> iOS build number is fetched from TestFlight and auto-incremented (independent of pubspec).

### Android

```bash
cd songspot_mobile/android

fastlane internal                # patch bump → Internal Testing
fastlane internal bump:minor     # minor bump → Internal Testing

# After testing — promote without rebuilding:
fastlane closed_testing          # Internal → Alpha (closed test)
fastlane production              # Alpha → Production
```

---

## Typical release flow

```
1. fastlane testflight bump:minor    (iOS — new feature)
2. fastlane internal bump:minor      (Android — new feature)
   → test both on devices
3. fastlane app_store                (iOS — submit for review)
4. fastlane closed_testing           (Android — promote to alpha)
   fastlane production               (Android — promote to production)
```

---

## Manual version bump (without deploying)

```bash
# From repo root:
./bump_version.sh patch   # 1.1.0+2 → 1.1.1+3
./bump_version.sh minor   # 1.1.0+2 → 1.2.0+3
./bump_version.sh major   # 1.1.0+2 → 2.0.0+3
```

---

## CI (GitHub Actions — future)

When adding mobile CI, pass the `bump:` parameter as a workflow input:

```yaml
# .github/workflows/deploy-ios.yml
on:
  workflow_dispatch:
    inputs:
      bump:
        description: 'Version bump type'
        default: 'patch'
        type: choice
        options: [patch, minor, major]

jobs:
  deploy:
    steps:
      - uses: actions/checkout@v4
      - run: cd songspot_mobile/ios && fastlane testflight bump:${{ inputs.bump }}
```

Required secrets for iOS CI: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_P8_FILE`
Required secrets for Android CI: `GOOGLE_PLAY_KEY_JSON` (content of `google-play-key.json`)
