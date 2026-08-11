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
# NOTE (2026-08-06): "don.?t" matches "dont" and "don't" but NOT "do not",
# so "do not save this" silently failed to suppress. Grouped alternation
# now covers both spellings across the common verbs.
OVERRIDE_RE='fix this|review this|edit this|summarize in chat|(don.?t|do not) (save|ingest|add|file)|just read|read only|no wiki|skip wiki'
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
# RESOLVED (2026-08-06): the first real attach happened and the assumption
# did NOT hold, though not for the predicted reason. The file was not
# inlined as a blob; it was expanded as an @-mention with the path in
# DOUBLE QUOTES:
#
#     @"/Users/dfp/Downloads/personal-fiserv-kb-export.zip"
#
# The old regex allowed `@` followed immediately by `/` or `~`, so the
# opening quote broke the match and the hook emitted {} silently. Every
# other form (bare path, unquoted @path, tilde path) worked fine, which
# is why this went unnoticed: it failed only on the exact shape the UI
# actually produces. The prose backstop in CLAUDE.md did NOT save it
# either; the attach was handled because the user asked about the file
# directly, not because anything auto-fired.
#
# `@"?` on both branches fixes it, and the sed strips the leading quote.
# The trailing quote is excluded naturally since `"` is not in the path
# charset.
#
# If this regex needs to grow again: dump the input PAYLOAD (jq -r '.')
# during a real attach to see what shape Claude Code actually emits. Do
# not guess at the schema, and add a case to the test block in
# hooks/README.md rather than testing by hand.
FILES=$(printf '%s' "$PROMPT" | grep -oE '(@"?|^|[[:space:]])((/|~/)[A-Za-z0-9._/-]+\.[A-Za-z0-9]+|@"?[A-Za-z0-9._/-]+)' 2>/dev/null | sed 's/^[[:space:]]*//; s/^@//; s/^"//' | sort -u || true)

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
