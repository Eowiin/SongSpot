#!/usr/bin/env bash
# Usage:
#   ./bump_version.sh patch    → 1.1.0 → 1.1.1
#   ./bump_version.sh minor    → 1.1.0 → 1.2.0
#   ./bump_version.sh major    → 1.1.0 → 2.0.0
#
# Always increments the build number (+N).

set -euo pipefail

PUBSPEC="pubspec.yaml"
PART="${1:-patch}"

current=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
semver="${current%+*}"   # e.g. 1.1.0
build="${current#*+}"    # e.g. 2

IFS='.' read -r major minor patch <<< "$semver"

case "$PART" in
  major) major=$((major + 1)); minor=0; patch=0 ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  patch) patch=$((patch + 1)) ;;
  *)
    echo "Usage: $0 [major|minor|patch]"
    exit 1
    ;;
esac

new_build=$((build + 1))
new_version="${major}.${minor}.${patch}+${new_build}"

# Update pubspec.yaml
sed -i '' "s/^version: .*/version: ${new_version}/" "$PUBSPEC"

echo "Bumped: ${current} → ${new_version}"
