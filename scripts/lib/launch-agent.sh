#!/usr/bin/env bash
# shellcheck disable=SC2034

readonly LAUNCH_AGENT_LABEL="${WATTY_LAUNCH_AGENT_LABEL:-$BUNDLE_ID}"
readonly LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly LAUNCH_AGENT_PLIST="$LAUNCH_AGENTS_DIR/$LAUNCH_AGENT_LABEL.plist"
readonly LOG_DIR="$HOME/Library/Logs/$APP_NAME"
readonly STOP_POLL_ATTEMPTS=20
readonly STOP_POLL_INTERVAL=0.25

launchd_domain() {
  printf 'gui/%s' "$(id -u)"
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

render_launch_agent_plist() {
  local app_path="$1" executable stdout_log stderr_log
  executable="$(xml_escape "$app_path/Contents/MacOS/$APP_EXECUTABLE")"
  stdout_log="$(xml_escape "$LOG_DIR/stdout.log")"
  stderr_log="$(xml_escape "$LOG_DIR/stderr.log")"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$executable</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$stdout_log</string>
    <key>StandardErrorPath</key>
    <string>$stderr_log</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
}

launch_agent_loaded() {
  launchctl print "$(launchd_domain)/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1
}

unload_launch_agent() {
  if launch_agent_loaded; then
    log "Unloading LaunchAgent $LAUNCH_AGENT_LABEL"
    launchctl bootout "$(launchd_domain)/$LAUNCH_AGENT_LABEL" ||
      warn "launchctl could not unload $LAUNCH_AGENT_LABEL"
  fi
}

install_launch_agent() {
  local app_path="$1"
  [[ -x "$app_path/Contents/MacOS/$APP_EXECUTABLE" ]] ||
    die "No executable at $app_path/Contents/MacOS/$APP_EXECUTABLE"

  mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
  unload_launch_agent
  render_launch_agent_plist "$app_path" >"$LAUNCH_AGENT_PLIST"
  plutil -lint "$LAUNCH_AGENT_PLIST" >/dev/null || die "Generated an invalid LaunchAgent: $LAUNCH_AGENT_PLIST"

  launchctl enable "$(launchd_domain)/$LAUNCH_AGENT_LABEL" ||
    warn "launchctl could not enable $LAUNCH_AGENT_LABEL"
  launchctl bootstrap "$(launchd_domain)" "$LAUNCH_AGENT_PLIST" ||
    die "launchctl could not load $LAUNCH_AGENT_PLIST; log out and back in, or start the app with: open \"$app_path\""

  log "LaunchAgent installed: $LAUNCH_AGENT_PLIST"
  log "Logs: $LOG_DIR"
}

app_process_ids() {
  local executable="$1/Contents/MacOS/$APP_EXECUTABLE"
  ps -axww -o pid=,command= | awk -v executable="$executable" '
    {
      pid = $1
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
    }
    $0 == executable || index($0, executable " ") == 1 { print pid }
  '
}

stop_app() {
  local app_path="$1" pid attempt
  [[ -n "$(app_process_ids "$app_path")" ]] || return 0

  log "Stopping the running $APP_NAME"
  while IFS= read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < <(app_process_ids "$app_path")

  for ((attempt = 0; attempt < STOP_POLL_ATTEMPTS; attempt++)); do
    [[ -z "$(app_process_ids "$app_path")" ]] && return 0
    sleep "$STOP_POLL_INTERVAL"
  done
  warn "$APP_NAME is still running from $app_path; quit it from its menu"
}
