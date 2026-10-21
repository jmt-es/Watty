#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CHANGELOG="$ROOT_DIR/CHANGELOG.md"
HOMEBREW_FORMULA="jmt-es/tap/watty"

usage() {
  cat <<USAGE
Usage: scripts/release-notes.sh [VERSION]

Prints the GitHub release notes for VERSION (default: the version in
WattyVersion.swift): its CHANGELOG.md section plus install instructions.
USAGE
}

changelog_section() {
  [[ -f "$CHANGELOG" ]] || die "Changelog not found: $CHANGELOG"
  awk -v heading="## [$1]" '
    index($0, heading) == 1 { capturing = 1; next }
    capturing && /^## \[/ { exit }
    capturing { print }
  ' "$CHANGELOG"
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
  esac

  local version="${1:-$APP_VERSION}" section
  section="$(changelog_section "$version")"
  [[ -n "${section//[[:space:]]/}" ]] || die "CHANGELOG.md has no entry for version $version"

  cat <<NOTES
## What's new

$section

## Install

Homebrew is the recommended way to install Watty. It builds the app from source on your Mac, so macOS never quarantines it:

\`\`\`sh
brew install $HOMEBREW_FORMULA
brew services start $CLI_COMMAND
\`\`\`

## Prebuilt app

\`$APP_NAME-$version-macos.zip\` is a universal build for Apple Silicon and Intel. It is signed ad hoc: it has no Apple Developer ID and is not notarized, so macOS blocks the first launch of a downloaded copy. Move $APP_NAME.app to /Applications, then open System Settings, go to Privacy & Security and choose Open Anyway, or run:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/$APP_NAME.app
\`\`\`

Verify the download with the attached checksum file:

\`\`\`sh
shasum -a 256 -c $APP_NAME-$version-macos.zip.sha256
\`\`\`
NOTES
}

main "$@"
