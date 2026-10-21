#!/usr/bin/env bash
# shellcheck disable=SC2034

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
readonly VERSION_FILE="$ROOT_DIR/Sources/WattyCore/WattyVersion.swift"
readonly DEFAULT_REPOSITORY="jmt-es/Watty"

readonly APP_NAME="Watty"
readonly APP_EXECUTABLE="Watty"
readonly CLI_PRODUCT="watty-cli"
readonly CLI_COMMAND="watty"

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_home() {
  [[ -n "${HOME:-}" && -d "$HOME" ]] || die "HOME must point to an existing directory"
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Watty builds and runs on macOS only"
}

require_developer_tools() {
  xcode-select -p >/dev/null 2>&1 ||
    die "The Xcode Command Line Tools are required; install them with: xcode-select --install"
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: $command_name"
  done
}

expand_home() {
  case "$1" in
    \~) printf '%s' "$HOME" ;;
    \~/*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

absolute_path() {
  mkdir -p "$1"
  (cd "$1" && pwd)
}

read_version_constant() {
  local name="$1" value
  [[ -f "$VERSION_FILE" ]] || die "Version file not found: $VERSION_FILE"
  value="$(sed -n -E "s/^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+${name}[[:space:]]*(:[[:space:]]*String)?[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\2/p" "$VERSION_FILE" | head -n 1)"
  [[ -n "$value" ]] || die "Could not read '$name' from $VERSION_FILE"
  printf '%s\n' "$value"
}

APP_VERSION="$(read_version_constant current)"
APP_BUILD="$(read_version_constant build)"
BUNDLE_ID="$(read_version_constant bundleIdentifier)"
readonly APP_VERSION APP_BUILD BUNDLE_ID

[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die "Invalid version '$APP_VERSION' in $VERSION_FILE"
[[ "$APP_BUILD" =~ ^[0-9]+$ ]] || die "Invalid build number '$APP_BUILD' in $VERSION_FILE"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid bundle identifier '$BUNDLE_ID' in $VERSION_FILE"
