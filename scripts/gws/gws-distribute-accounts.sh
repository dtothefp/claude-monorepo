#!/usr/bin/env bash
set -euo pipefail

# Distributes .gws-accounts.json, credentials, and gitignore entries to child
# projects based on the "projects" field in each account entry. Each child
# project gets a registry containing all accounts mapped to it (supports
# multi-account projects).
#
# Usage:
#   gws-distribute-accounts.sh              # distribute to all mapped projects
#   gws-distribute-accounts.sh eyeboga      # distribute to a specific project
#   gws-distribute-accounts.sh --list       # show account-to-project mapping
#
# What gets distributed to each child project:
#   .gws-accounts.json        registry with all accounts mapped to that project
#   .credentials/<alias>.json copied from parent for each mapped account
#   .gitignore                ensures .credentials/, .gws-accounts.json, .bin/ are ignored

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY="$WORKSPACE_DIR/.gws-accounts.json"

GWS_GITIGNORE_ENTRIES=(
    ".credentials/"
    ".gws-accounts.json"
    ".bin/"
)

if [ ! -f "$REGISTRY" ]; then
    echo "Error: No .gws-accounts.json found at $WORKSPACE_DIR" >&2
    exit 1
fi

# --list mode: show mapping and exit
if [ "${1:-}" = "--list" ]; then
    echo "=== Account → Project Mapping ==="
    echo ""
    ACCOUNTS=$(jq -r '.accounts | keys[]' "$REGISTRY")
    for ACCOUNT in $ACCOUNTS; do
        EMAIL=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].email' "$REGISTRY")
        PROJECTS=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].projects // [] | join(", ")' "$REGISTRY")
        if [ -z "$PROJECTS" ]; then
            echo "  $ACCOUNT ($EMAIL) → parent only (no child projects)"
        else
            echo "  $ACCOUNT ($EMAIL) → $PROJECTS"
        fi
    done
    exit 0
fi

# Ensure gitignore entries exist in a project
ensure_gitignore() {
    local PROJECT_DIR="$1"
    local GITIGNORE="$PROJECT_DIR/.gitignore"

    [ -f "$GITIGNORE" ] || touch "$GITIGNORE"

    local ADDED=0
    for ENTRY in "${GWS_GITIGNORE_ENTRIES[@]}"; do
        if ! grep -qxF "$ENTRY" "$GITIGNORE"; then
            echo "$ENTRY" >> "$GITIGNORE"
            ADDED=$((ADDED + 1))
        fi
    done

    if [ $ADDED -gt 0 ]; then
        echo "    + Added $ADDED gitignore entries"
    fi
}

TARGET_PROJECT="${1:-}"

echo "=== gws Account Distributor ==="
echo ""

# Build a map of project -> list of account aliases
# Use temp files keyed by project name since bash can't have arrays of arrays
TMPDIR_MAP=$(mktemp -d)
trap 'rm -rf "$TMPDIR_MAP"' EXIT

ALL_ACCOUNTS=$(jq -r '.accounts | keys[]' "$REGISTRY")

for ACCOUNT in $ALL_ACCOUNTS; do
    PROJECTS=$(jq -r --arg a "$ACCOUNT" '.accounts[$a].projects // [] | .[]' "$REGISTRY")
    for PROJECT in $PROJECTS; do
        echo "$ACCOUNT" >> "$TMPDIR_MAP/$PROJECT"
    done
done

# Collect unique project names that have at least one account
ALL_PROJECTS=$(ls "$TMPDIR_MAP" 2>/dev/null || true)

DISTRIBUTED=0

for PROJECT in $ALL_PROJECTS; do
    # Filter to target project if specified
    if [ -n "$TARGET_PROJECT" ] && [ "$PROJECT" != "$TARGET_PROJECT" ]; then
        continue
    fi

    PROJECT_DIR="$WORKSPACE_DIR/packages/$PROJECT"
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "  Warning: $PROJECT_DIR does not exist, skipping." >&2
        continue
    fi

    # Read all account aliases for this project (in order they appear in the registry)
    PROJECT_ACCOUNTS=()
    while IFS= read -r ACCT; do
        PROJECT_ACCOUNTS+=("$ACCT")
    done < "$TMPDIR_MAP/$PROJECT"

    DEFAULT_ACCOUNT="${PROJECT_ACCOUNTS[0]}"
    ACCOUNT_COUNT="${#PROJECT_ACCOUNTS[@]}"

    if [ "$ACCOUNT_COUNT" -gt 1 ]; then
        echo "  $PROJECT → ${PROJECT_ACCOUNTS[*]} (default: $DEFAULT_ACCOUNT)"
    else
        FIRST="${PROJECT_ACCOUNTS[0]}"
        EMAIL=$(jq -r --arg a "$FIRST" '.accounts[$a].email' "$REGISTRY")
        echo "  $PROJECT → $FIRST ($EMAIL)"
    fi

    # 1. Build merged registry JSON for all accounts mapped to this project
    CHILD_REGISTRY="$PROJECT_DIR/.gws-accounts.json"
    DEFAULT_CS=$(jq -r '.default_client_secret_file // empty' "$REGISTRY")
    ACCOUNTS_JSON="{}"
    for ACCT in "${PROJECT_ACCOUNTS[@]}"; do
        EMAIL=$(jq -r --arg a "$ACCT" '.accounts[$a].email' "$REGISTRY")
        CRED_FILE=$(jq -r --arg a "$ACCT" '.accounts[$a].credential_file' "$REGISTRY")
        DESC=$(jq -r --arg a "$ACCT" '.accounts[$a].description' "$REGISTRY")
        PROJECT_ID=$(jq -r --arg a "$ACCT" '.accounts[$a].project_id // empty' "$REGISTRY")
        ACCT_CS=$(jq -r --arg a "$ACCT" '.accounts[$a].client_secret_file // empty' "$REGISTRY")
        ACCOUNTS_JSON=$(echo "$ACCOUNTS_JSON" | jq \
            --arg alias "$ACCT" \
            --arg email "$EMAIL" \
            --arg cred "$CRED_FILE" \
            --arg desc "$DESC" \
            --arg pid "$PROJECT_ID" \
            --arg csf "$ACCT_CS" \
            '.[$alias] = (
                {"email": $email, "credential_file": $cred, "description": $desc}
                + (if $pid != "" then {"project_id": $pid} else {} end)
                + (if $csf != "" then {"client_secret_file": $csf} else {} end)
            )')
    done

    if [ -n "$DEFAULT_CS" ]; then
        echo "{\"accounts\": $ACCOUNTS_JSON, \"default\": \"$DEFAULT_ACCOUNT\", \"default_client_secret_file\": \"$DEFAULT_CS\"}" \
            | jq '.' > "$CHILD_REGISTRY"
    else
        echo "{\"accounts\": $ACCOUNTS_JSON, \"default\": \"$DEFAULT_ACCOUNT\"}" \
            | jq '.' > "$CHILD_REGISTRY"
    fi
    echo "    + Account registry (${#PROJECT_ACCOUNTS[@]} account(s))"

    # 2. Copy credentials for all mapped accounts
    mkdir -p "$PROJECT_DIR/.credentials"
    for ACCT in "${PROJECT_ACCOUNTS[@]}"; do
        CRED_FILE=$(jq -r --arg a "$ACCT" '.accounts[$a].credential_file' "$REGISTRY")
        PARENT_CRED="$WORKSPACE_DIR/$CRED_FILE"
        if [ -f "$PARENT_CRED" ]; then
            rm -f "$PROJECT_DIR/$CRED_FILE"
            cp "$PARENT_CRED" "$PROJECT_DIR/$CRED_FILE"
            echo "    + Credentials copied ($ACCT)"
        else
            echo "    - Credentials not yet available for $ACCT (run gws-auth-setup.sh first)"
        fi

        # Per-account OAuth client secret (only if the account overrides the default)
        ACCT_CS=$(jq -r --arg a "$ACCT" '.accounts[$a].client_secret_file // empty' "$REGISTRY")
        if [ -n "$ACCT_CS" ]; then
            PARENT_CS="$WORKSPACE_DIR/$ACCT_CS"
            if [ -f "$PARENT_CS" ]; then
                mkdir -p "$PROJECT_DIR/$(dirname "$ACCT_CS")"
                cp "$PARENT_CS" "$PROJECT_DIR/$ACCT_CS"
                echo "    + client_secret copied ($ACCT)"
            else
                echo "    - client_secret not yet available at $PARENT_CS"
            fi
        fi
    done

    # 2b. Copy the shared default client_secret_file (if the registry sets one)
    if [ -n "$DEFAULT_CS" ]; then
        PARENT_DEFAULT_CS="$WORKSPACE_DIR/$DEFAULT_CS"
        if [ -f "$PARENT_DEFAULT_CS" ]; then
            mkdir -p "$PROJECT_DIR/$(dirname "$DEFAULT_CS")"
            cp "$PARENT_DEFAULT_CS" "$PROJECT_DIR/$DEFAULT_CS"
            echo "    + default client_secret copied"
        else
            echo "    - default client_secret not yet available at $PARENT_DEFAULT_CS"
        fi
    fi

    # 3. Copy .bin/gws binary if parent has one and project doesn't
    if [ -x "$WORKSPACE_DIR/.bin/gws" ] && [ ! -f "$PROJECT_DIR/.bin/gws" ]; then
        mkdir -p "$PROJECT_DIR/.bin"
        cp "$WORKSPACE_DIR/.bin/gws" "$PROJECT_DIR/.bin/gws"
        chmod +x "$PROJECT_DIR/.bin/gws"
        echo "    + .bin/gws binary"
    fi

    # 4. Copy gws-multi.sh wrapper (always overwrite, parent is the source of truth)
    mkdir -p "$PROJECT_DIR/scripts"
    cp "$WORKSPACE_DIR/scripts/gws-multi.sh" "$PROJECT_DIR/scripts/gws-multi.sh"
    chmod +x "$PROJECT_DIR/scripts/gws-multi.sh"
    echo "    + gws-multi.sh wrapper"

    # 5. Copy gws skill (always overwrite, parent is the source of truth)
    mkdir -p "$PROJECT_DIR/.claude/skills/gws"
    cp "$WORKSPACE_DIR/.claude/skills/gws/SKILL.md" "$PROJECT_DIR/.claude/skills/gws/SKILL.md"
    echo "    + gws skill"

    # 6. Ensure gitignore entries
    ensure_gitignore "$PROJECT_DIR"

    DISTRIBUTED=$((DISTRIBUTED + 1))
    echo ""
done

if [ $DISTRIBUTED -eq 0 ]; then
    if [ -n "$TARGET_PROJECT" ]; then
        echo "No mapping found for project '$TARGET_PROJECT'."
        echo "Run with --list to see all mappings."
    else
        echo "No projects to distribute to. Add 'projects' arrays to .gws-accounts.json."
    fi
else
    echo "Done: distributed to $DISTRIBUTED projects (registry + credentials + gitignore)."
fi
