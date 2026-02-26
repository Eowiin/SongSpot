fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android internal

```sh
[bundle exec] fastlane android internal
```

Bump version, build, and upload to internal testing track. Options: bump:patch|minor|major

### android closed_testing

```sh
[bundle exec] fastlane android closed_testing
```

Promote internal track to closed testing (alpha) — no build

### android production

```sh
[bundle exec] fastlane android production
```

Promote closed testing (alpha) track to production — no build

### android play_store

```sh
[bundle exec] fastlane android play_store
```

Bump version, build, and release directly to Play Store production. Options: bump:patch|minor|major

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
