#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/launch-agent.sh
source "$SCRIPT_DIR/lib/launch-agent.sh"

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BIN_DIR="${BIN_DIR:-}"
LAUNCH_AGENT="${LAUNCH_AGENT:-0}"
RUN_TESTS="${RUN_TESTS:-0}"
OPEN_APP="${OPEN_APP:-1}"
BUILD_DIR="$ROOT_DIR/build"

usage() {
  cat <<USAGE
Usage: scripts/install.sh [options]

Builds $APP_NAME from source and installs it. Needs the Xcode Command Line Tools.

  --install-dir DIR   install $APP_NAME.app into DIR (default: ~/Applications, or \$INSTALL_DIR)
  --bin-dir DIR       also link the '$CLI_COMMAND' command into DIR (or \$BIN_DIR)
  --launch-agent      start $APP_NAME at login with a LaunchAgent (or LAUNCH_AGENT=1)
  --run-tests         run 'swift test' first; XCTest needs a full Xcode (or RUN_TESTS=1)
  --no-open           do not open the app after installing (or OPEN_APP=0)
  -h, --help          show this help

An existing LaunchAgent from a previous install is refreshed automatically.
USAGE
}

require_flag() {
  case "$2" in
    0 | 1) ;;
    *) die "$1 must be 0 or 1, got '$2'" ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
      --launch-agent)
        LAUNCH_AGENT=1
        shift
        ;;
      --run-tests)
        RUN_TESTS=1
        shift
        ;;
      --no-open)
        OPEN_APP=0
        shift
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
  require_flag LAUNCH_AGENT "$LAUNCH_AGENT"
  require_flag RUN_TESTS "$RUN_TESTS"
  require_flag OPEN_APP "$OPEN_APP"
  INSTALL_DIR="$(expand_home "$INSTALL_DIR")"
  BIN_DIR="$(expand_home "$BIN_DIR")"
}

install_app() {
  local source_app="$1" target_app="$2"
  [[ "$target_app" == */"$APP_NAME.app" ]] || die "Refusing to replace '$target_app'"

  log "Installing $target_app"
  rm -rf "$target_app"
  ditto "$source_app" "$target_app"
  xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
}

link_cli() {
  local target_app="$1" bin_dir link
  bin_dir="$(absolute_path "$BIN_DIR")"
  link="$bin_dir/$CLI_COMMAND"
  if [[ -e "$link" && ! -L "$link" ]]; then
    die "Refusing to overwrite $link, which is not a symlink"
  fi
  ln -sf "$target_app/Contents/MacOS/$CLI_PRODUCT" "$link"
  log "Linked $link"
}

main() {
  parse_args "$@"
  require_macos
  require_home
  require_commands ditto xattr

  if [[ "$RUN_TESTS" == "1" ]]; then
    log "Running tests"
    swift test --package-path "$ROOT_DIR"
  fi

  "$SCRIPT_DIR/build-app.sh" --output-dir "$BUILD_DIR"

  local target_app refresh_agent=0
  target_app="$(absolute_path "$INSTALL_DIR")/$APP_NAME.app"
  if [[ "$LAUNCH_AGENT" == "1" || -f "$LAUNCH_AGENT_PLIST" ]]; then
    refresh_agent=1
  fi

  unload_launch_agent
  stop_app "$target_app"
  install_app "$BUILD_DIR/$APP_NAME.app" "$target_app"
  [[ -z "$BIN_DIR" ]] || link_cli "$target_app"

  if [[ "$refresh_agent" == "1" ]]; then
    install_launch_agent "$target_app"
  elif [[ "$OPEN_APP" == "1" ]]; then
    open "$target_app" || warn "Could not open $target_app"
  fi

  log "Installed $APP_NAME $APP_VERSION at $target_app"
}

main "$@"
