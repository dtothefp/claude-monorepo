#!/usr/bin/env bash
set -uo pipefail
#
# install.sh
#
# Install, remove, or inspect the local daily routines. These are launchd user
# agents on this Mac. Nothing runs in the cloud, nothing needs a network, and
# nothing runs as root.
#
# Usage:
#   ./scripts/routines/install.sh install     # write plists and load them
#   ./scripts/routines/install.sh uninstall   # unload and delete plists
#   ./scripts/routines/install.sh status      # is it loaded, when did it last run
#   ./scripts/routines/install.sh run <name>  # trigger one now, synchronously
#
# Two jobs:
#   graphify-daily    03:15  rebuild every existing knowledge graph
#   wiki-embed-daily  03:45  reindex the semantic-search database
#
# The 30-minute gap is deliberate. The embedding indexer is meant to be able to
# join chunks back to graph node ids, so it wants the graph rebuilt first.
#
# Why launchd and not cron: launchd runs a missed job when the Mac wakes up,
# cron silently skips it. A laptop that is asleep at 03:15 most nights would
# get almost no cron runs. Also why RunAtLoad is false: you do not want a full
# rebuild kicking off the moment you log in.
#
# The plists are generated here rather than committed because they carry
# absolute paths that differ per machine and per user.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PREFIX="com.claude-monorepo"

JOBS="graphify-daily wiki-embed-daily"

hour_for() { case "$1" in graphify-daily) echo 3 ;; wiki-embed-daily) echo 3 ;; esac; }
min_for()  { case "$1" in graphify-daily) echo 15 ;; wiki-embed-daily) echo 45 ;; esac; }

write_plist() {
    local job="$1" label="$PREFIX.$job" plist="$AGENT_DIR/$label.plist"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/$job.sh</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$WORKSPACE_DIR</string>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$(hour_for "$job")</integer>
        <key>Minute</key>
        <integer>$(min_for "$job")</integer>
    </dict>

    <!-- false on purpose: do not kick off a rebuild at login -->
    <key>RunAtLoad</key>
    <false/>

    <!-- launchd's own capture. The scripts also write their own dated log. -->
    <key>StandardOutPath</key>
    <string>$LOG_DIR/$job.launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/$job.launchd.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>

    <!-- A rebuild is background work. Do not fight the user for CPU or disk. -->
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>Nice</key>
    <integer>5</integer>
</dict>
</plist>
PLIST
    echo "  wrote $plist"
}

cmd_install() {
    mkdir -p "$AGENT_DIR" "$LOG_DIR"
    local job label plist
    for job in $JOBS; do
        label="$PREFIX.$job"; plist="$AGENT_DIR/$label.plist"
        if [ ! -x "$SCRIPT_DIR/$job.sh" ]; then
            echo "error: $SCRIPT_DIR/$job.sh missing or not executable" >&2
            exit 1
        fi
        launchctl bootout "gui/$UID/$label" 2>/dev/null || true
        write_plist "$job"
        if launchctl bootstrap "gui/$UID" "$plist" 2>/dev/null; then
            echo "  loaded $label  ($(hour_for "$job")):$(min_for "$job") daily"
        else
            # bootstrap is the modern verb, load is the fallback on older macOS
            launchctl load "$plist" 2>/dev/null \
                && echo "  loaded $label (legacy verb)" \
                || echo "  WARN could not load $label, try: launchctl bootstrap gui/$UID $plist"
        fi
    done
    echo ""
    echo "Installed. Logs:"
    echo "  $LOG_DIR/graphify-daily.log"
    echo "  $LOG_DIR/wiki-embed-daily.log"
    echo ""
    echo "Trigger one now:  ./scripts/routines/install.sh run graphify-daily"
}

cmd_uninstall() {
    local job label plist
    for job in $JOBS; do
        label="$PREFIX.$job"; plist="$AGENT_DIR/$label.plist"
        launchctl bootout "gui/$UID/$label" 2>/dev/null \
            || launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist" && echo "  removed $label"
    done
    echo "Logs left in place at $LOG_DIR."
}

cmd_status() {
    local job label plist
    for job in $JOBS; do
        label="$PREFIX.$job"; plist="$AGENT_DIR/$label.plist"
        printf '%s\n' "$label"
        if [ -f "$plist" ]; then
            printf '  plist:   %s\n' "$plist"
        else
            printf '  plist:   NOT INSTALLED\n'
        fi
        if launchctl print "gui/$UID/$label" >/dev/null 2>&1; then
            printf '  loaded:  yes\n'
            launchctl print "gui/$UID/$label" 2>/dev/null \
                | grep -E '^\s+(last exit code|runs|state) =' | sed 's/^/  /'
        else
            printf '  loaded:  no\n'
        fi
        if [ -f "$LOG_DIR/$job.log" ]; then
            printf '  last run: %s\n' "$(grep '=== ' "$LOG_DIR/$job.log" | tail -1)"
        else
            printf '  last run: never\n'
        fi
        echo ""
    done
}

cmd_run() {
    local job="${1:-}"
    case " $JOBS " in *" $job "*) ;; *) echo "unknown job: $job (want one of: $JOBS)" >&2; exit 2 ;; esac
    echo "running $job now (foreground)"
    /bin/bash "$SCRIPT_DIR/$job.sh"
}

case "${1:-}" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    run)       cmd_run "${2:-}" ;;
    *)
        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
