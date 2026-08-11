#!/usr/bin/env bash
set -euo pipefail

# Interactive auth helper for Google Workspace CLI multi-account setup.
# Authenticates each account in .gws-accounts.json and exports credentials.
#
# Usage:
#   gws-auth-setup.sh [--client-id ID --client-secret SECRET] \
#                     [--account NAME] [--no-cloud-scopes] [target-dir] [account]
#
# Flags:
#   --no-cloud-scopes  Request Workspace scopes only, omitting
#                      https://www.googleapis.com/auth/cloud-platform. Use this
#                      for any account on a Workspace domain you do NOT
#                      administer (e.g. an employer's). Carrying a Cloud scope
#                      subjects the token to Google Cloud session control's
#                      ~16h reauth clock, which surfaces as invalid_rapt, and
#                      you cannot turn that policy off without super-admin.
#                      Equivalent to "scopes": "workspace-no-cloud" in the
#                      account's .gws-accounts.json entry, which is preferred
#                      because it survives re-runs.
#
# Positional arguments (order-independent):
#   - A workspace directory containing .gws-accounts.json (defaults to the
#     parent of scripts/).
#   - An account alias. If given (positionally or via --account), only that
#     account is authenticated. The alias is resolved against the TARGET dir's
#     registry, so it works for child projects too, not just the parent.
#
# Examples:
#   ./scripts/gws/gws-auth-setup.sh                          # all accounts, parent
#   ./scripts/gws/gws-auth-setup.sh personal                 # just personal, parent
#   ./scripts/gws/gws-auth-setup.sh packages/my-app          # all accounts, child
#   ./scripts/gws/gws-auth-setup.sh packages/my-app work     # just `work` in child
#   ./scripts/gws/gws-auth-setup.sh packages/my-app --account work   # same, explicit
#   ./scripts/gws/gws-auth-setup.sh --client-id ID --client-secret SECRET

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Two levels up: this script lives in <root>/scripts/gws/.
DEFAULT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

CLIENT_ID=""
CLIENT_SECRET=""
TARGET_DIR=""
ACCOUNT_FILTER=""
NO_CLOUD_SCOPES=0
POSITIONALS=()

# Parse args. Account-vs-dir disambiguation is deferred until after the target
# registry is known, so a positional account alias resolves against the target
# project's registry (e.g. `work` inside packages/my-app) rather than
# only the parent's.
while [ $# -gt 0 ]; do
    case "$1" in
        --client-id)
            CLIENT_ID="$2"
            shift 2
            ;;
        --client-secret)
            CLIENT_SECRET="$2"
            shift 2
            ;;
        --account)
            ACCOUNT_FILTER="$2"
            shift 2
            ;;
        --no-cloud-scopes)
            NO_CLOUD_SCOPES=1
            shift
            ;;
        *)
            POSITIONALS+=("$1")
            shift
            ;;
    esac
done

# A positional that names an existing directory is the target dir; anything else
# is an account alias (validated against the target registry below).
for arg in ${POSITIONALS[@]+"${POSITIONALS[@]}"}; do
    if [ -d "$arg" ]; then
        TARGET_DIR="$arg"
    elif [ -z "$ACCOUNT_FILTER" ]; then
        ACCOUNT_FILTER="$arg"
    fi
done

TARGET_DIR="${TARGET_DIR:-$DEFAULT_DIR}"

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

REGISTRY="$TARGET_DIR/.gws-accounts.json"
CRED_DIR="$TARGET_DIR/.credentials"

# Validate the account filter against the target registry (now that it's known).
if [ -n "$ACCOUNT_FILTER" ] && [ -f "$REGISTRY" ]; then
    if ! jq -e --arg a "$ACCOUNT_FILTER" '.accounts[$a]' "$REGISTRY" >/dev/null 2>&1; then
        echo "Error: account '$ACCOUNT_FILTER' not found in $REGISTRY" >&2
        echo "Available: $(jq -r '.accounts | keys | join(", ")' "$REGISTRY")" >&2
        exit 1
    fi
fi

# Check gws is installed
if ! command -v gws >/dev/null 2>&1; then
    echo "Error: gws not found. Install with: brew install googleworkspace-cli" >&2
    echo "Note: The formula is 'googleworkspace-cli', NOT 'gws' (that's a different tool)." >&2
    exit 1
fi

# Check or create registry
if [ ! -f "$REGISTRY" ]; then
    echo "No .gws-accounts.json found at $TARGET_DIR"
    echo "Creating template registry..."

    cat > "$REGISTRY" <<'TEMPLATE'
{
  "accounts": {
    "personal": {
      "email": "REPLACE_ME@gmail.com",
      "credential_file": ".credentials/personal.json",
      "description": "Personal Gmail and Drive"
    }
  },
  "default": "personal"
}
TEMPLATE

    echo "Created $REGISTRY. Edit it to add your accounts, then re-run this script."
    exit 0
fi

# Create credentials directory
mkdir -p "$CRED_DIR"

echo "=== Google Workspace CLI Auth Setup ==="
echo "Target: $TARGET_DIR"
if [ -n "$ACCOUNT_FILTER" ]; then
    echo "Account: $ACCOUNT_FILTER (only)"
fi
echo ""

# When a filter is set, only that account is in play, so the count reflects it.
if [ -n "$ACCOUNT_FILTER" ]; then
    ACCOUNTS="$ACCOUNT_FILTER"
else
    ACCOUNTS=$(jq -r '.accounts | keys[]' "$REGISTRY")
fi
TOTAL=$(echo "$ACCOUNTS" | wc -l | tr -d ' ')
CURRENT=0

for ACCOUNT in $ACCOUNTS; do
    CURRENT=$((CURRENT + 1))
    EMAIL=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].email' "$REGISTRY")
    CRED_FILE=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].credential_file' "$REGISTRY")
    CRED_PATH="$TARGET_DIR/$CRED_FILE"

    echo "[$CURRENT/$TOTAL] Account: $ACCOUNT ($EMAIL)"

    # Check if valid credentials already exist
    if [ -f "$CRED_PATH" ]; then
        echo "  Credential file exists at $CRED_PATH"
        read -rp "  Re-authenticate? (y/N) " REAUTH
        if [[ ! "$REAUTH" =~ ^[yY] ]]; then
            echo "  Skipped."
            echo ""
            continue
        fi
    fi

    echo ""
    echo "  Step 1: Browser will open for OAuth consent."
    echo "  Sign in as: $EMAIL"
    echo ""
    read -rp "  Press Enter to open browser..." _

    # Per-account isolated config dir. gws stores its keyring here, so each
    # account gets its own credential state and there is no global mutable
    # ~/.config/gws/credentials.enc to clobber. The wrapper uses the same dir
    # at runtime via GOOGLE_WORKSPACE_CLI_CONFIG_DIR. See feedback_gws_403_quota_project.md.
    GWS_CONFIG_DIR="$HOME/.config/gws/accounts/$ACCOUNT"
    mkdir -p "$GWS_CONFIG_DIR"

    # Pre-populate the per-account config dir with the source-of-truth
    # client_secret.json (so the gws auth login that follows uses the right
    # OAuth client and ends up with installed.project_id pre-corrected).
    SOURCE_CS=$(jq -r --arg a "$ACCOUNT" \
        '.accounts[$a].client_secret_file // .default_client_secret_file // empty' \
        "$REGISTRY")
    if [ -n "$SOURCE_CS" ] && [ -f "$TARGET_DIR/$SOURCE_CS" ]; then
        cp "$TARGET_DIR/$SOURCE_CS" "$GWS_CONFIG_DIR/client_secret.json"
    fi

    LOGIN_ARGS=()
    if [ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ]; then
        LOGIN_ARGS+=(--client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET")
    fi
    # Explicit scope list keeps all standard GWS scopes plus Search Console
    # (webmasters). Add new scopes here rather than relying on gws defaults,
    # which omit webmasters.
    #
    # gmail.modify covers messages but NOT users.settings.*, so the settings
    # scopes are listed separately. basic covers filters, forwarding, sendAs,
    # IMAP/POP and vacation; sharing covers delegates.
    #
    # WORKSPACE_SCOPES carries nothing from the Google Cloud family. That is
    # deliberate and load-bearing, see the cloud-platform note below.
    WORKSPACE_SCOPES="email,profile,openid,\
https://www.googleapis.com/auth/calendar,\
https://www.googleapis.com/auth/documents,\
https://www.googleapis.com/auth/drive,\
https://www.googleapis.com/auth/gmail.modify,\
https://www.googleapis.com/auth/gmail.settings.basic,\
https://www.googleapis.com/auth/gmail.settings.sharing,\
https://www.googleapis.com/auth/presentations,\
https://www.googleapis.com/auth/spreadsheets,\
https://www.googleapis.com/auth/tasks,\
https://www.googleapis.com/auth/contacts,\
https://www.googleapis.com/auth/webmasters,\
https://www.googleapis.com/auth/siteverification"

    # Why cloud-platform is separable.
    #
    # Google Cloud session control applies its reauthentication (RAPT) clock to
    # tokens that carry Google Cloud OAuth scopes. That clock, roughly 16h by
    # default, is what produces
    #   invalid_grant: reauth related error (invalid_rapt)
    # on Workspace-domain accounts. On domains we administer we turn the policy
    # off (admin console, or the GcpUserAccessBinding in package-gcp). On a
    # domain we do NOT administer, such as an employer's Workspace, that is not
    # an option, so the only lever left is to not carry a Cloud scope at all.
    #
    # Nothing gws does for Gmail/Drive/Docs/Sheets/Calendar/Contacts/Tasks or
    # Search Console needs it. gws's own help calls cloud-platform part of
    # `--full`, i.e. the opt-in extra rather than the baseline.
    #
    # Selection order: --no-cloud-scopes flag, then the account's "scopes" field
    # in the registry, then the default (include it, preserving the historical
    # behavior for the accounts already provisioned that way).
    #   "scopes": "workspace-no-cloud"  -> omit cloud-platform
    #   "scopes": "workspace"           -> include it (same as unset)
    CLOUD_SCOPE="https://www.googleapis.com/auth/cloud-platform"
    ACCT_SCOPE_MODE=$(jq -r --arg a "$ACCOUNT" \
        '.accounts[$a].scopes // empty' "$REGISTRY")

    if [ "$NO_CLOUD_SCOPES" = "1" ] || [ "$ACCT_SCOPE_MODE" = "workspace-no-cloud" ]; then
        echo "  Scopes: Workspace only, omitting $CLOUD_SCOPE"
        echo "          (keeps the token off Google Cloud session control's reauth clock)"
        LOGIN_ARGS+=(--scopes "$WORKSPACE_SCOPES")
    else
        LOGIN_ARGS+=(--scopes "$WORKSPACE_SCOPES,$CLOUD_SCOPE")
    fi
    GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$GWS_CONFIG_DIR" \
    GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND="file" \
        gws auth login "${LOGIN_ARGS[@]+"${LOGIN_ARGS[@]}"}"

    echo ""
    echo "  Step 2: Exporting credentials..."

    # Ensure credential subdirectory exists
    mkdir -p "$(dirname "$CRED_PATH")"

    GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$GWS_CONFIG_DIR" \
    GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND="file" \
        gws auth export --unmasked > "$CRED_PATH"

    # Validate
    if jq -e 'has("refresh_token") or (.credential | has("refresh_token"))' "$CRED_PATH" >/dev/null 2>&1; then
        echo "  OK: Credentials exported with refresh_token"
    else
        echo "  WARNING: No refresh_token found in exported credentials."
        echo "  The credential file may not work for offline access."
    fi

    # Step 3: Capture the OAuth client metadata for the wrapper to materialize.
    #
    # `gws auth login` writes <config_dir>/client_secret.json containing the
    # OAuth desktop client used for this login. We snapshot it into the
    # workspace's .credentials/ directory so the wrapper has a checked-in
    # source of truth to copy from on every invocation. Bootstrap case: if
    # the source file did not exist before this run, this captures it.
    #
    # We also rewrite installed.project_id to the canonical GCP project ID,
    # because Google's console downloader bakes the project NAME into that
    # field, not the project ID. Doing this once at capture time means the
    # wrapper never has to deal with it.
    LOGIN_CLIENT_SECRET="$GWS_CONFIG_DIR/client_secret.json"
    PROJECT_ID=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].project_id // empty' "$REGISTRY")
    TARGET_CS=$(jq -r --arg a "$ACCOUNT" \
        '.accounts[$a].client_secret_file // .default_client_secret_file // empty' \
        "$REGISTRY")

    if [ -n "$TARGET_CS" ] && [ -f "$LOGIN_CLIENT_SECRET" ]; then
        SAVED_PATH="$TARGET_DIR/$TARGET_CS"
        mkdir -p "$(dirname "$SAVED_PATH")"
        cp "$LOGIN_CLIENT_SECRET" "$SAVED_PATH"
        echo "  Saved client_secret to $SAVED_PATH"

        if [ -n "$PROJECT_ID" ] && command -v python3 >/dev/null 2>&1; then
            python3 - "$SAVED_PATH" "$PROJECT_ID" <<'PYEOF'
import json, sys
path, real = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
inst = d.get("installed") or d.get("web") or {}
if inst.get("project_id") != real:
    inst["project_id"] = real
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
    print(f"  Rewrote installed.project_id -> {real}")
PYEOF
        fi
    fi

    echo ""
done

echo "=== Auth setup complete ==="
echo ""
echo "Verify with:"
for ACCOUNT in $ACCOUNTS; do
    echo "  ./scripts/gws/gws-multi.sh $ACCOUNT oauth2 userinfo.get"
done
