#!/usr/bin/env bash
# PostToolUse hook: auto-append to research/log.md when files are written
# or edited under any research/ directory.
#
# Wired up in .claude/settings.json. Receives the Claude Code hook payload
# on stdin as JSON and exits 0 silently in all non-applicable cases so it
# never blocks tool execution.
#
# Behavior:
#   - Triggers only on Write/Edit tool events.
#   - Triggers only when the touched file lives somewhere under a `research/`
#     directory.
#   - Skips index.md and log.md themselves to avoid recursion.
#   - Walks up to find the nearest `research/` ancestor and appends a one-line
#     entry to that directory's log.md, creating log.md if missing.
#   - De-dupes entries for the same path on the same date.

set -euo pipefail

# Read Claude Code hook payload from stdin
PAYLOAD=$(cat)

# Extract tool name; only Write/Edit are interesting
TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.tool_name // empty')
case "$TOOL_NAME" in
    Write|Edit) ;;
    *) exit 0 ;;
esac

# Extract the file path the tool acted on
FILE_PATH=$(echo "$PAYLOAD" | jq -r '.tool_input.file_path // empty')
[ -n "$FILE_PATH" ] || exit 0

# Only care about files inside a `research/` directory
if [[ "$FILE_PATH" != */research/* ]]; then
    exit 0
fi

# Skip the wiki bookkeeping files themselves to avoid recursion
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" = "log.md" ] || [ "$BASENAME" = "index.md" ]; then
    exit 0
fi

# Skip .gitkeep and other dotfiles
if [[ "$BASENAME" == .* ]]; then
    exit 0
fi

# Resolve the research/ root for this file
# /a/b/research/marketing/foo.md -> /a/b/research
RESEARCH_ROOT="${FILE_PATH%/research/*}/research"
LOG_FILE="$RESEARCH_ROOT/log.md"

# If log.md does not exist yet (e.g. first write into a fresh project),
# scaffold it with the standard header so the wiki layer comes alive
# automatically the first time research lands.
if [ ! -f "$LOG_FILE" ]; then
    mkdir -p "$RESEARCH_ROOT"
    cat > "$LOG_FILE" <<'HEADER'
# Research Log

Append-only chronological record of additions and updates to this
research wiki. One line per entry. Newest at the top.

Format: `YYYY-MM-DD: <change> ([link](path))`

---

HEADER
fi

# Compute path relative to the research/ root for clean log links
REL_PATH="${FILE_PATH#"$RESEARCH_ROOT"/}"
DATE=$(date +%Y-%m-%d)

# De-dupe: if there's already an entry for this path on this date, do nothing.
# This avoids one entry per keystroke when Claude makes several small Edits
# to the same file in a row.
if grep -Fq "$DATE" "$LOG_FILE" 2>/dev/null && \
   grep -F "$REL_PATH" "$LOG_FILE" 2>/dev/null | grep -Fq "$DATE"; then
    exit 0
fi

# Insert the new entry immediately after the `---` separator so newest is on top.
ENTRY="- $DATE: Updated [\`$REL_PATH\`]($REL_PATH)"
TMP=$(mktemp)
awk -v entry="$ENTRY" '
    BEGIN { inserted = 0 }
    /^---$/ && inserted == 0 {
        print
        print ""
        print entry
        inserted = 1
        next
    }
    { print }
    END {
        # If there was no `---` separator, append at the end so we never
        # silently drop an entry.
        if (inserted == 0) {
            print ""
            print entry
        }
    }
' "$LOG_FILE" > "$TMP" && mv "$TMP" "$LOG_FILE"

exit 0
