#!/usr/bin/env bash
# PreToolUse hook — blocks Write and Edit tool calls that contain em dashes (—)
# or en dashes (–) in the content being written.
#
# Why: em dash rule is in CLAUDE.md and memory, yet violated repeatedly across
# Slack drafts, emails, and copy. Hooks fire deterministically; memory does not.
#
# Protocol:
#   stdin  = JSON with tool_name + tool_input
#   exit 0 = allow
#   exit 2 = block; stderr is shown to Claude

set -euo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // ""')

if [[ "$tool_name" == "Write" ]]; then
  content=$(echo "$input" | jq -r '.tool_input.content // ""')
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
elif [[ "$tool_name" == "Edit" ]]; then
  content=$(echo "$input" | jq -r '.tool_input.new_string // ""')
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
else
  exit 0
fi

# Skip Claude internal scratch where em dashes are conventional.
# Memory notes use em dashes as separators in the established index format.
# The rule is about user-facing copy, not Claude's internal notes.
case "$file_path" in
  */.claude/projects/*/memory/*) exit 0 ;;
esac

# Check for em dash (—, U+2014) or en dash (–, U+2013)
if echo "$content" | grep -qP '[\x{2013}\x{2014}]' 2>/dev/null || \
   echo "$content" | grep -q $'—\|–'; then
  cat >&2 <<'MSG'
Em dash (—) or en dash (–) detected in output. These are banned.

Replace with:
  , (comma)      — for a pause or aside
  . (period)     — to break into two sentences
  () (parens)    — for an aside
  : (colon)      — only for code/structured fields, never prose lists

Rewrite the affected sentence and retry.
MSG
  exit 2
fi

exit 0
