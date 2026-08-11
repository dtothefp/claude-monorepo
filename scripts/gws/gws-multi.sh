#!/usr/bin/env bash
set -euo pipefail

# Multi-account Google Workspace CLI wrapper.
# Usage: gws-multi.sh [account-alias] <gws-subcommand> [args...]
# If account-alias is omitted, uses the "default" from .gws-accounts.json.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Two levels up: this script lives in <root>/scripts/gws/.
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
REGISTRY="$WORKSPACE_DIR/.gws-accounts.json"

if [ ! -f "$REGISTRY" ]; then
    echo "Error: Account registry not found at $REGISTRY" >&2
    echo "Create .gws-accounts.json or run gws-auth-setup.sh first." >&2
    exit 1
fi

# Determine if first arg is an account alias or a gws subcommand.
# Account aliases are keys in the registry; gws subcommands are not.
ACCOUNT=""
if [ $# -gt 0 ]; then
    MAYBE_ACCOUNT="$1"
    if jq -e --arg a "$MAYBE_ACCOUNT" '.accounts[$a]' "$REGISTRY" >/dev/null 2>&1; then
        ACCOUNT="$MAYBE_ACCOUNT"
        shift
    fi
fi

# Fall back to default account
if [ -z "$ACCOUNT" ]; then
    ACCOUNT=$(jq -r '.default // empty' "$REGISTRY")
    if [ -z "$ACCOUNT" ]; then
        echo "Error: No account specified and no default set in $REGISTRY" >&2
        exit 1
    fi
fi

# Resolve credential file and optional GCP project override
CRED_FILE=$(jq -r --arg acct "$ACCOUNT" '.accounts[$acct].credential_file // empty' "$REGISTRY")
PROJECT_ID=$(jq -r --arg acct "$ACCOUNT" '.accounts[$acct].project_id // empty' "$REGISTRY")

if [ -z "$CRED_FILE" ]; then
    echo "Error: Unknown account alias '$ACCOUNT'" >&2
    echo "Available accounts: $(jq -r '.accounts | keys | join(", ")' "$REGISTRY")" >&2
    exit 1
fi

CRED_PATH="$WORKSPACE_DIR/$CRED_FILE"

# The per-account keyring populated by `gws auth login`. This is the live,
# RAPT-aware credential store (see precedence note at the exec below).
GWS_CONFIG_DIR="$HOME/.config/gws/accounts/$ACCOUNT"
KEYRING_CRED="$GWS_CONFIG_DIR/credentials.enc"

# An account is usable if it has either a populated keyring (from auth login)
# or a portable exported credentials file. The keyring is preferred.
if [ ! -f "$KEYRING_CRED" ] && [ ! -f "$CRED_PATH" ]; then
    echo "Error: No credentials for account '$ACCOUNT'." >&2
    echo "Neither keyring ($KEYRING_CRED) nor export ($CRED_PATH) exists." >&2
    echo "Run ./scripts/gws/gws-auth-setup.sh $ACCOUNT to authenticate." >&2
    exit 1
fi

# Per-account isolated config directory.
#
# Background: gws stores credentials in a keyring under its config dir. When
# the keyring already contains credentials from a prior `gws auth login`, gws
# uses them and SILENTLY IGNORES the GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE env
# var. That means a single shared ~/.config/gws cannot serve multiple accounts:
# whichever account ran `auth login` last wins for every subsequent call,
# regardless of what env var you pass.
#
# Additionally, Google's GCP console writes the project NAME (not the project
# ID) into installed.project_id when you download an OAuth desktop client. gws
# sends that field verbatim as the x-goog-user-project header, Google can't
# resolve it, and returns a misleading 403 about Service Usage Consumer.
#
# Fix: give each account its own config dir at ~/.config/gws/accounts/<alias>.
# Materialize the per-account client_secret.json into that dir from a checked-in
# source of truth (with installed.project_id pre-corrected at capture time).
# Then point gws at the dir via GOOGLE_WORKSPACE_CLI_CONFIG_DIR. Combined with
# the per-account credentials file, this gives each account a fully isolated
# config + keyring with no global mutable state and no possibility of
# cross-account clobbering. See feedback_gws_403_quota_project.md and DFP-239.
# (GWS_CONFIG_DIR / KEYRING_CRED were resolved above.)
mkdir -p "$GWS_CONFIG_DIR"

CLIENT_SECRET_FILE=$(jq -r --arg acct "$ACCOUNT" \
    '.accounts[$acct].client_secret_file // .default_client_secret_file // empty' \
    "$REGISTRY")

if [ -n "$CLIENT_SECRET_FILE" ]; then
    CS_SRC="$WORKSPACE_DIR/$CLIENT_SECRET_FILE"
    CS_DST="$GWS_CONFIG_DIR/client_secret.json"
    if [ ! -f "$CS_SRC" ]; then
        echo "Error: client_secret source not found at $CS_SRC for account '$ACCOUNT'." >&2
        echo "Run ./scripts/gws/gws-auth-setup.sh $ACCOUNT to capture it." >&2
        exit 1
    fi
    if ! cmp -s "$CS_SRC" "$CS_DST"; then
        cp "$CS_SRC" "$CS_DST"
    fi
fi

# Find the gws binary: prefer host install, fall back to .bin/gws (Cowork VM)
GWS_BIN=""
if command -v gws >/dev/null 2>&1; then
    GWS_BIN="$(command -v gws)"
elif [ -x "/opt/homebrew/bin/gws" ]; then
    GWS_BIN="/opt/homebrew/bin/gws"
elif [ -x "/usr/local/bin/gws" ]; then
    GWS_BIN="/usr/local/bin/gws"
elif [ -x "$WORKSPACE_DIR/.bin/gws" ]; then
    GWS_BIN="$WORKSPACE_DIR/.bin/gws"
else
    echo "Error: gws binary not found." >&2
    echo "Install via 'brew install googleworkspace-cli' or place Linux binary at .bin/gws" >&2
    exit 1
fi

# Execute gws with the correct credentials
EXTRA_ENV=()
if [ -n "$PROJECT_ID" ]; then
    EXTRA_ENV+=(GOOGLE_WORKSPACE_PROJECT_ID="$PROJECT_ID")
fi

# Credential precedence: prefer the per-account keyring that `gws auth login`
# wrote into the config dir. It is the only store that carries Google's reauth
# proof token (RAPT), so accounts under Workspace session control stay valid
# after a reauth. The exported .credentials/<acct>.json is a portable snapshot
# that does NOT carry the RAPT, so once a reauth fires it goes stale and
# refreshing from it fails with invalid_rapt. Only fall back to the export when
# no keyring exists (e.g. Cowork VM bootstrap before any local auth login).
#
# Passing GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE makes gws load that file in
# preference to the keyring, so we must NOT pass it when the keyring is present.
if [ ! -f "$KEYRING_CRED" ]; then
    EXTRA_ENV+=(GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="$CRED_PATH")
fi

exec env \
    GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$GWS_CONFIG_DIR" \
    GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND="file" \
    "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}" \
    "$GWS_BIN" "$@"
