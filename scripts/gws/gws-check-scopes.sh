#!/usr/bin/env bash
set -euo pipefail

# Show the OAuth scopes actually granted to a gws account, and flag whether the
# token carries a Google Cloud scope.
#
# Why this exists: the ~16h `invalid_grant: reauth related error (invalid_rapt)`
# comes from Google Cloud session control, which applies its reauthentication
# clock to tokens carrying Google Cloud OAuth scopes. On domains we administer
# we disable that policy. On a domain we do not administer (an employer's
# Workspace) the only lever is to not request a Cloud scope in the first place.
#
# This script tells you which side of that line an account is on. What you
# INTENDED (the registry's "scopes" field) and what Google actually GRANTED can
# differ, because the grant is whatever the consent screen approved, and a
# re-auth against a stale cached consent can quietly keep an old scope set.
# Only the minted token is evidence.
#
# Usage:
#   gws-check-scopes.sh [account ...]     # default: every account in registry
#   gws-check-scopes.sh --dir <path> [account ...]
#
# Exit: 0 if every checked account minted a token, 1 if any failed to refresh.
# A present Cloud scope is reported loudly but is not itself a failure, since
# it is correct for the domains we administer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Two levels up: this script lives in <root>/scripts/gws/.
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

ACCOUNTS_ARGV=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            WORKSPACE_DIR="$(cd "$2" && pwd)"
            shift 2
            ;;
        *)
            ACCOUNTS_ARGV+=("$1")
            shift
            ;;
    esac
done

REGISTRY="$WORKSPACE_DIR/.gws-accounts.json"
if [ ! -f "$REGISTRY" ]; then
    echo "Error: Account registry not found at $REGISTRY" >&2
    exit 1
fi

if [ ${#ACCOUNTS_ARGV[@]} -gt 0 ]; then
    ACCOUNTS=("${ACCOUNTS_ARGV[@]}")
else
    while IFS= read -r a; do ACCOUNTS+=("$a"); done < <(jq -r '.accounts | keys[]' "$REGISTRY")
fi

FAILED=0

for ACCOUNT in "${ACCOUNTS[@]}"; do
    EMAIL=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].email // "?"' "$REGISTRY")
    WANT=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].scopes // "workspace (default, includes cloud-platform)"' "$REGISTRY")
    CRED_FILE=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].credential_file // empty' "$REGISTRY")

    echo "=== $ACCOUNT ($EMAIL)"
    echo "    registry intent: $WANT"

    CRED_PATH="$WORKSPACE_DIR/$CRED_FILE"
    if [ -z "$CRED_FILE" ] || [ ! -f "$CRED_PATH" ]; then
        echo "    SKIP: no exported credential file at ${CRED_PATH:-<unset>}"
        echo "          (the keyring may still be valid; this check needs the export)"
        echo ""
        continue
    fi

    # Mint an access token from the refresh token and ask Google what scopes it
    # actually carries. Deliberately does not print the tokens themselves.
    RESULT=$(python3 - "$CRED_PATH" <<'PYEOF' 2>&1 || true
import json, sys, urllib.parse, urllib.request, urllib.error

path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
d = d.get("credential", d)

missing = [k for k in ("client_id", "client_secret", "refresh_token") if k not in d]
if missing:
    print("ERR missing field(s) in credential file: " + ", ".join(missing))
    sys.exit(0)

body = urllib.parse.urlencode({
    "client_id": d["client_id"],
    "client_secret": d["client_secret"],
    "refresh_token": d["refresh_token"],
    "grant_type": "refresh_token",
}).encode()

try:
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    tok = json.load(urllib.request.urlopen(req, timeout=30))
except urllib.error.HTTPError as e:
    detail = ""
    try:
        detail = json.load(e).get("error_description") or json.load(e).get("error") or ""
    except Exception:
        pass
    print(f"ERR refresh failed ({e.code}) {detail}")
    sys.exit(0)
except Exception as e:
    print(f"ERR refresh failed: {e}")
    sys.exit(0)

scopes = sorted(tok.get("scope", "").split())
cloud = [s for s in scopes if "/auth/cloud-platform" in s or "/auth/cloud-identity" in s or "/auth/pubsub" in s]
print("OK " + ("CLOUD" if cloud else "NOCLOUD"))
for s in scopes:
    print("   " + ("<< CLOUD  " if s in cloud else "          ") + s)
PYEOF
)

    STATUS=$(echo "$RESULT" | head -1)
    case "$STATUS" in
        "OK NOCLOUD")
            echo "    granted: no Google Cloud scope. Not subject to Cloud session control's reauth clock."
            ;;
        "OK CLOUD")
            echo "    granted: CARRIES A GOOGLE CLOUD SCOPE."
            echo "             Fine on a domain you administer with the reauth policy disabled."
            echo "             On a domain you do NOT administer this is the invalid_rapt cause."
            echo "             Fix: set \"scopes\": \"workspace-no-cloud\" in .gws-accounts.json,"
            echo "             then ./scripts/gws/gws-auth-setup.sh --account $ACCOUNT"
            ;;
        *)
            echo "    $STATUS"
            FAILED=$((FAILED + 1))
            ;;
    esac

    echo "$RESULT" | tail -n +2
    echo ""
done

exit "$FAILED"
