#!/usr/bin/env bash
# wiki-ingest-suggest.sh
#
# UserPromptSubmit hook. Detects when the user has attached file paths
# to their prompt (via the Claude Code + button, drag-drop, or bare
# path mention) and injects an additionalContext instruction telling
# Claude to run the wiki-ingest skill on each file UNLESS the user's
# message explicitly says otherwise ("fix this", "review this",
# "don't save", etc.).
#
# Emits {} (no-op) when:
#   - no prompt text is found
#   - no file paths detected in the prompt
#   - the prompt contains an override phrase
#
# Otherwise emits:
#   { "hookSpecificOutput": {
#       "hookEventName": "UserPromptSubmit",
#       "additionalContext": "..."
#   } }

set -euo pipefail

# Read hook payload from stdin. Support both shapes Claude Code has
# used (top-level .prompt and nested .hook_input.prompt) so this keeps
# working across versions.
PAYLOAD=$(cat)

PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // .hook_input.prompt // empty' 2>/dev/null || true)

if [ -z "$PROMPT" ]; then
    echo '{}'
    exit 0
fi

# Override phrases. If any appear, stay out of the way.
OVERRIDE_RE='fix this|review this|edit this|summarize in chat|don.?t save|don.?t ingest|just read|read only|no wiki|skip wiki'
if printf '%s' "$PROMPT" | grep -qiE "$OVERRIDE_RE"; then
    echo '{}'
    exit 0
fi

# Detect file paths. Two heuristics:
# 1) Absolute paths beginning with / or ~ that look like real files
#    (contain a dot for extension or end in a common dir).
# 2) Claude Code @-mentions: @path/to/file
#
# KNOWN GOTCHA (recorded 2026-04-08): this regex is heuristic. It only
# matches absolute paths ending in an extension and @-mentions. If
# Claude Code's `+` button ever inlines an attached file as an embedded
# blob (rather than expanding it into the prompt as a path), this hook
# will silently emit `{}` and the wiki-ingest skill will not be
# suggested for that attach.
#
# The first real file attach via the `+` button will tell us whether
# this assumption holds. If the hook misses, the backstop is the
# "Auto wiki-ingest on file attach" rule in CLAUDE.md (parent repo
# root) — Claude will still invoke wiki-ingest from the prose rule even
# though the hook did not fire.
#
# If this regex needs to grow: the place to look is the input PAYLOAD
# above (jq -r '.' on it during a real attach to see what shape Claude
# Code actually emits) — do not guess at the schema.
FILES=$(printf '%s' "$PROMPT" | grep -oE '(@|^|[[:space:]])((/|~/)[A-Za-z0-9._/-]+\.[A-Za-z0-9]+|@[A-Za-z0-9._/-]+)' 2>/dev/null | sed 's/^[[:space:]]*//; s/^@//' | sort -u || true)

if [ -z "$FILES" ]; then
    echo '{}'
    exit 0
fi

# Compose additionalContext. Keep it short — this goes into the
# model's context on every matching prompt.
COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')

CONTEXT=$(jq -n --arg files "$FILES" --arg n "$COUNT" '
"The user attached \($n) file(s) to this prompt:\n\($files)\n\nUnless the user'"'"'s message explicitly tells you otherwise, invoke the wiki-ingest skill on each attached file and route the output under the appropriate research/<topic>/ directory. Honor the Karpathy governance rules: append a one-line entry to research/log.md and update research/index.md if the ingest changes a topic conclusion."
')

jq -n --arg ctx "$(printf '%s' "$CONTEXT" | jq -r .)" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
