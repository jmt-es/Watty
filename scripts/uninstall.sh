#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/launch-agent.sh
source "$SCRIPT_DIR/lib/launch-agent.sh"

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-}"
PURGE=0
REMOVED_COUNT=0

usage() {
  cat <<USAGE
Usage: scripts/uninstall.sh [options]

Removes the $APP_NAME app, its LaunchAgent and its logs.

  --purge             also remove preferences, cached data and the battery history
                      in ~/Library/Application Support/$APP_NAME
  --install-dir DIR   where $APP_NAME.app was installed (default: ~/Applications, or \$INSTALL_DIR)
  --bin-dir DIR       also remove the '$CLI_COMMAND' link from DIR (or \$BIN_DIR)
  -h, --help          show this help

Installed with Homebrew? Use: brew services stop $CLI_COMMAND && brew uninstall $CLI_COMMAND
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge)
        PURGE=1
        shift
        ;;
      --install-dir)
        [[ $# -ge 2 ]] || die "--install-dir needs a directory"
        INSTALL_DIR="$2"
        shift 2
        ;;
      --bin-dir)
        [[ $# -ge 2 ]] || die "--bin-dir needs a directory"
        BIN_DIR="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
  done
  INSTALL_DIR="$(expand_home "$INSTALL_DIR")"
  BIN_DIR="$(expand_home "$BIN_DIR")"
}

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
    log "Removed $path"
  fi
}

remove_cli_link() {
  local link="$BIN_DIR/$CLI_COMMAND" destination
  [[ -L "$link" ]] || return 0
  destination="$(readlink "$link")"
  [[ "$destination" == */"$APP_NAME.app/Contents/MacOS/$CLI_PRODUCT" ]] || return 0
  remove_path "$link"
}

purge_user_data() {
  if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    defaults delete "$BUNDLE_ID"
  fi
  remove_path "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  remove_path "$HOME/Library/Application Support/$APP_NAME"
  remove_path "$HOME/Library/Caches/$BUNDLE_ID"
}

main() {
  parse_args "$@"
  require_macos
  require_home

  local target_app="$INSTALL_DIR/$APP_NAME.app"
  [[ "$target_app" == */"$APP_NAME.app" ]] || die "Refusing to remove '$target_app'"

  unload_launch_agent
  stop_app "$target_app"

  remove_path "$LAUNCH_AGENT_PLIST"
  remove_path "$target_app"
  remove_path "$LOG_DIR"
  [[ -z "$BIN_DIR" ]] || remove_cli_link
  [[ "$PURGE" == "0" ]] || purge_user_data

  if [[ "$REMOVED_COUNT" -eq 0 ]]; then
    log "Nothing to remove for $APP_NAME in $INSTALL_DIR"
  else
    log "$APP_NAME uninstalled"
  fi
}

main "$@"
