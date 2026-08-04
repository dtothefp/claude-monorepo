#!/usr/bin/env bash
# Runs the gws credential healthcheck and alerts on failure.
#
# Intended to be run from cron every 6h:
#   0 */6 * * * /path/to/workspace/scripts/gws/gws-healthcheck-alert.sh
#
# On failure:
#   - Posts a Slack DM to the configured user (if scopes allow)
#   - Shows a macOS notification as fallback / secondary signal
#   - Appends full output to ~/Library/Logs/gws-healthcheck.log
#
# Exit code mirrors the underlying healthcheck (0 healthy, 1 any failure).
#
# Silent on success. Cron runs shouldn't spam either channel when nothing's wrong.

set -uo pipefail

# Ensure cron-minimal PATH includes homebrew + system binaries.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${GWS_HEALTHCHECK_LOG:-$HOME/Library/Logs/gws-healthcheck.log}"

# --- Slack alert destination ------------------------------------------------
# Set SLACK_ALERT_TARGET to either a Slack user ID (DM) or channel ID.
# The bot token in the chosen workspace must be able to post there:
#   - For a DM to a user ID: the bot needs im:write + the user must be in the workspace
#   - For a channel ID: the bot must be a member of that channel
# Leave SLACK_ALERT_TARGET empty to skip Slack posting entirely.
# Both are unset by default. Without SLACK_ALERT_TARGET the script skips Slack
# and relies on the macOS notification plus the log file.
SLACK_ALERT_ACCOUNT="${SLACK_ALERT_ACCOUNT:-}"   # alias from .slack-accounts.json
SLACK_ALERT_TARGET="${SLACK_ALERT_TARGET:-}"     # Slack user ID (DM) or channel ID

# ---------------------------------------------------------------------------

mkdir -p "$(dirname "$LOG_FILE")"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Sweep the parent registry AND every child project that carries its own
# .gws-accounts.json. Child-project accounts are invisible to the parent
# registry, and if they are never probed their token deaths surface only
# mid-task. Aggregate exit: 0 only if every registry is fully healthy.
EXIT=0
OUTPUT=""
for DIR in "$WORKSPACE_DIR" "$WORKSPACE_DIR"/packages/*/; do
    [ -f "$DIR/.gws-accounts.json" ] || continue
    REG_OUT="$("$SCRIPT_DIR/refresh-gws-creds.sh" "$DIR" 2>&1)" || EXIT=1
    OUTPUT="$OUTPUT
--- registry: $DIR ---
$REG_OUT"
done

{
    echo "=== $TIMESTAMP exit=$EXIT ==="
    echo "$OUTPUT"
    echo ""
} >> "$LOG_FILE"

if [ "$EXIT" -eq 0 ]; then
    exit 0
fi

# Extract list of failed account aliases for the alert body.
# refresh-gws-creds.sh prints "Checking <alias> (<email>)..." then "  FAIL: ..."
FAILED_ACCOUNTS="$(echo "$OUTPUT" \
    | awk '/^Checking / { sub(/\.\.\.$/, "", $2); acct=$2 } /^  FAIL:/ { print acct }' \
    | sort -u | paste -sd, -)"

MESSAGE=":rotating_light: gws healthcheck FAILED at ${TIMESTAMP}
Accounts failing: ${FAILED_ACCOUNTS:-unknown}
Host: $(hostname -s)

Fix:
  cd $WORKSPACE_DIR
  ./scripts/gws/refresh-gws-creds.sh         # see which accounts and why
  ./scripts/gws/gws-auth-setup.sh <alias>    # re-auth each failing account"

# --- Slack DM (best effort, never blocks the Mac notification) --------------
if [ -n "$SLACK_ALERT_TARGET" ] && [ -x "$SCRIPT_DIR/slack-multi.sh" ]; then
    SLACK_OUT="$("$SCRIPT_DIR/slack-multi.sh" "$SLACK_ALERT_ACCOUNT" send-message \
        --channel "$SLACK_ALERT_TARGET" \
        --text "$MESSAGE" 2>&1 || true)"
    echo "slack-alert-result: $SLACK_OUT" >> "$LOG_FILE"
fi

# --- macOS notification -----------------------------------------------------
# Always fire, even if Slack succeeded. The redundancy is intentional.
NOTIF_BODY="Accounts failing: ${FAILED_ACCOUNTS:-unknown}. See $LOG_FILE"
/usr/bin/osascript \
    -e "display notification \"$NOTIF_BODY\" with title \"gws healthcheck failed\" sound name \"Basso\"" \
    2>> "$LOG_FILE" || true

exit "$EXIT"
