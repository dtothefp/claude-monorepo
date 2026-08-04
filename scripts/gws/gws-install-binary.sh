#!/usr/bin/env bash
set -euo pipefail

# Downloads the gws Linux arm64 binary from GitHub releases and installs it
# into .bin/gws for one or more target directories (for Cowork VM usage).
#
# Usage:
#   gws-install-binary.sh                          # install to parent workspace only
#   gws-install-binary.sh packages/my-app           # install to a specific project
#   gws-install-binary.sh --all                     # install to parent + all child projects
#   gws-install-binary.sh --version 0.23.0          # use a specific version
#   gws-install-binary.sh --all --version 0.23.0    # both flags

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

GWS_VERSION="0.22.5"
TARGETS=()
RESOLVED_TARGETS=()
INSTALL_ALL=false

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            INSTALL_ALL=true
            shift
            ;;
        --version)
            GWS_VERSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: gws-install-binary.sh [OPTIONS] [target-dir...]"
            echo ""
            echo "Downloads the gws Linux arm64 binary into .bin/gws for Cowork VM usage."
            echo ""
            echo "Options:"
            echo "  --all              Install to parent workspace + all child projects"
            echo "  --version VERSION  Use a specific gws version (default: $GWS_VERSION)"
            echo "  --help, -h         Show this help"
            echo ""
            echo "Examples:"
            echo "  gws-install-binary.sh                        # parent workspace only"
            echo "  gws-install-binary.sh packages/package-eyeboga       # specific project"
            echo "  gws-install-binary.sh --all                  # everywhere"
            echo "  gws-install-binary.sh --all --version 0.23.0 # everywhere, specific version"
            exit 0
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

# Resolve positional targets relative to cwd (not script dir)
RESOLVED_TARGETS=()
for T in "${TARGETS[@]+"${TARGETS[@]}"}"; do
    if [ -d "$T" ]; then
        RESOLVED_TARGETS+=("$(cd "$T" && pwd)")
    else
        echo "Warning: Target directory '$T' does not exist, skipping." >&2
    fi
done

# Build target list
if $INSTALL_ALL; then
    # If explicit targets given with --all, use those as base dirs
    if [ ${#RESOLVED_TARGETS[@]} -gt 0 ]; then
        BASE_DIR="${RESOLVED_TARGETS[0]}"
    else
        BASE_DIR="$WORKSPACE_DIR"
    fi
    RESOLVED_TARGETS=("$BASE_DIR")
    for PROJECT_DIR in "$BASE_DIR"/packages/*/; do
        [ -d "$PROJECT_DIR" ] && RESOLVED_TARGETS+=("$PROJECT_DIR")
    done
elif [ ${#RESOLVED_TARGETS[@]} -eq 0 ]; then
    RESOLVED_TARGETS=("$WORKSPACE_DIR")
fi
TARGETS=("${RESOLVED_TARGETS[@]}")

# Detect platform for download
PLATFORM="linux"
ARCH="arm64"
echo "=== gws Binary Installer ==="
echo "Version: $GWS_VERSION"
echo "Platform: ${PLATFORM}-${ARCH} (Cowork VM)"
echo "Targets: ${#TARGETS[@]} directories"
echo ""

# Fetch release info and find the right asset
echo "Fetching release info from GitHub..."
RELEASE_JSON=$(curl -sL "https://api.github.com/repos/googleworkspace/cli/releases/tags/v${GWS_VERSION}")

# Try common asset naming patterns
ASSET_URL=""
for PATTERN in \
    "google-workspace-cli-aarch64-unknown-${PLATFORM}-gnu.tar.gz" \
    "google-workspace-cli-aarch64-unknown-${PLATFORM}-musl.tar.gz" \
    "gws_${GWS_VERSION}_${PLATFORM}_${ARCH}.tar.gz" \
    "gws-${PLATFORM}-${ARCH}" \
    "gws_${PLATFORM}_${ARCH}" \
    "gws-${PLATFORM}-${ARCH}.tar.gz" \
    "gws_${GWS_VERSION}_${PLATFORM}_aarch64.tar.gz" \
    "gws-${PLATFORM}-aarch64" \
    "gws-v${GWS_VERSION}-${PLATFORM}-${ARCH}" \
; do
    URL=$(echo "$RELEASE_JSON" | jq -r --arg name "$PATTERN" '.assets[] | select(.name == $name) | .browser_download_url // empty')
    if [ -n "$URL" ]; then
        ASSET_NAME="$PATTERN"
        ASSET_URL="$URL"
        break
    fi
done

# If no exact match, list what's available and let user pick
if [ -z "$ASSET_URL" ]; then
    echo ""
    echo "Could not auto-detect the correct asset. Available assets for v${GWS_VERSION}:"
    echo ""
    echo "$RELEASE_JSON" | jq -r '.assets[] | "  \(.name)  (\(.size / 1048576 | floor)MB)"'
    echo ""

    # Try a fuzzy match on linux + arm/aarch
    FUZZY_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("linux.*(?:arm64|aarch64)"; "i")) | .browser_download_url' | head -1)
    FUZZY_NAME=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | test("linux.*(?:arm64|aarch64)"; "i")) | .name' | head -1)

    if [ -n "$FUZZY_URL" ]; then
        echo "Best guess: $FUZZY_NAME"
        read -rp "Use this asset? (Y/n) " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[nN] ]]; then
            ASSET_NAME="$FUZZY_NAME"
            ASSET_URL="$FUZZY_URL"
        fi
    fi

    if [ -z "$ASSET_URL" ]; then
        echo "Please specify the asset name from the list above:"
        read -rp "> " MANUAL_NAME
        ASSET_URL=$(echo "$RELEASE_JSON" | jq -r --arg name "$MANUAL_NAME" '.assets[] | select(.name == $name) | .browser_download_url // empty')
        ASSET_NAME="$MANUAL_NAME"
        if [ -z "$ASSET_URL" ]; then
            echo "Error: Asset '$MANUAL_NAME' not found in release." >&2
            exit 1
        fi
    fi
fi

echo "Downloading $ASSET_NAME..."

# Download to temp
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -L -o "$TMPDIR/$ASSET_NAME" "$ASSET_URL"

# Extract if it's a tarball, otherwise use directly
BINARY_PATH=""
if [[ "$ASSET_NAME" == *.tar.gz ]] || [[ "$ASSET_NAME" == *.tgz ]]; then
    echo "Extracting tarball..."
    tar -xzf "$TMPDIR/$ASSET_NAME" -C "$TMPDIR"
    # Find the binary in the extracted contents (may be named gws or google-workspace-cli)
    BINARY_PATH=$(find "$TMPDIR" \( -name "gws" -o -name "google-workspace-cli" \) -type f ! -name "*.tar.gz" ! -name "*.sha256" | head -1)
    if [ -z "$BINARY_PATH" ]; then
        echo "Error: Could not find binary in extracted tarball." >&2
        echo "Contents:" >&2
        find "$TMPDIR" -type f >&2
        exit 1
    fi
elif [[ "$ASSET_NAME" == *.zip ]]; then
    echo "Extracting zip..."
    unzip -q "$TMPDIR/$ASSET_NAME" -d "$TMPDIR"
    BINARY_PATH=$(find "$TMPDIR" \( -name "gws" -o -name "google-workspace-cli" \) -type f ! -name "*.zip" ! -name "*.sha256" | head -1)
    if [ -z "$BINARY_PATH" ]; then
        echo "Error: Could not find binary in extracted zip." >&2
        exit 1
    fi
else
    BINARY_PATH="$TMPDIR/$ASSET_NAME"
fi

chmod +x "$BINARY_PATH"

# Verify it's a real binary
if ! file "$BINARY_PATH" | grep -qi "executable\|ELF"; then
    echo "Warning: Downloaded file may not be a binary executable."
    file "$BINARY_PATH"
    read -rp "Continue anyway? (y/N) " PROCEED
    if [[ ! "$PROCEED" =~ ^[yY] ]]; then
        exit 1
    fi
fi

echo ""

# Install to each target
INSTALLED=0
for TARGET in "${TARGETS[@]}"; do
    # Resolve to absolute path
    TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || continue
    DEST="$TARGET/.bin/gws"

    mkdir -p "$TARGET/.bin"
    cp "$BINARY_PATH" "$DEST"
    chmod +x "$DEST"

    PROJECT_NAME=$(basename "$TARGET")
    echo "  Installed: $DEST ($PROJECT_NAME)"
    INSTALLED=$((INSTALLED + 1))
done

echo ""
echo "Done: installed gws v${GWS_VERSION} (linux-arm64) to $INSTALLED directories."
