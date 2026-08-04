#!/usr/bin/env bash
set -euo pipefail

# Credential health check for all registered gws accounts.
# Checks that credential files exist, contain refresh tokens, and can
# successfully authenticate against Google's API.
#
# Usage: refresh-gws-creds.sh [workspace-dir]
# Defaults to the parent of the scripts/ directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
REGISTRY="$WORKSPACE_DIR/.gws-accounts.json"
# Use the target workspace's own wrapper when it has one. gws-multi.sh resolves
# its registry relative to its own location, so probing a child project's
# accounts through the parent wrapper silently checks the wrong registry
# (this is how one account's expired token went undetected for weeks).
if [ -x "$WORKSPACE_DIR/scripts/gws-multi.sh" ]; then
    WRAPPER="$WORKSPACE_DIR/scripts/gws-multi.sh"
else
    WRAPPER="$SCRIPT_DIR/gws-multi.sh"
fi

if [ ! -f "$REGISTRY" ]; then
    echo "Error: Account registry not found at $REGISTRY" >&2
    exit 1
fi

FAILED=0
TOTAL=0

for ACCOUNT in $(jq -r '.accounts | keys[]' "$REGISTRY"); do
    TOTAL=$((TOTAL + 1))
    EMAIL=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].email' "$REGISTRY")
    CRED_FILE=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].credential_file' "$REGISTRY")
    CRED_PATH="$WORKSPACE_DIR/$CRED_FILE"

    echo "Checking $ACCOUNT ($EMAIL)..."

    # Check file exists
    if [ ! -f "$CRED_PATH" ]; then
        echo "  FAIL: Credential file missing at $CRED_PATH"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Check refresh_token is present
    if ! jq -e 'has("refresh_token") or (.credential | has("refresh_token"))' "$CRED_PATH" >/dev/null 2>&1; then
        echo "  FAIL: No refresh_token found in $CRED_PATH"
        FAILED=$((FAILED + 1))
        continue
    fi

    # Attempt a lightweight API call to test the token. `gmail users getProfile`
    # is a single tiny call (returns mailbox stats), avoiding the timeouts and
    # rate issues that `+triage` can hit on large mailboxes. Retry once after 30s
    # to absorb transient Gmail API blips before alerting.
    PROBE=("$WRAPPER" "$ACCOUNT" gmail users getProfile --params '{"userId":"me"}')
    if "${PROBE[@]}" >/dev/null 2>&1; then
        echo "  OK: Credentials valid"
    else
        echo "  First probe failed, retrying in 30s..."
        sleep 30
        if "${PROBE[@]}" >/dev/null 2>&1; then
            echo "  OK: Credentials valid (recovered after retry)"
        else
            echo "  FAIL: API call failed twice (token may be expired or revoked)"
            echo "        Re-run: gws-auth-setup.sh to re-authenticate $EMAIL"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo "Results: $((TOTAL - FAILED))/$TOTAL accounts healthy"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "To fix failed accounts, run from the parent workspace:"
    echo "  ./scripts/gws-auth-setup.sh $WORKSPACE_DIR"
    exit 1
fi
