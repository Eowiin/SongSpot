fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios testflight

```sh
[bundle exec] fastlane ios testflight
```

Bump version, build, and distribute to TestFlight. Options: bump:patch|minor|major

### ios app_store

```sh
[bundle exec] fastlane ios app_store
```

Bump version, build, and release directly to App Store. Options: bump:patch|minor|major

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
