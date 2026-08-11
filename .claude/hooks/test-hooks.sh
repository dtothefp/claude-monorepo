#!/usr/bin/env bash
# test-hooks.sh
#
# Regression tests for the hooks in this directory. Run after editing any
# hook, and add a case whenever a new input shape is discovered in the wild.
#
#   ./.claude/hooks/test-hooks.sh
#
# Why this exists: wiki-ingest-suggest.sh was silently broken for the exact
# @-mention form Claude Code's UI produces (path in double quotes) from
# whenever it was written until 2026-08-06. Every other input shape worked,
# so nothing looked wrong. A hook that fails by emitting {} is invisible;
# only a test tells you.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0

# Built at runtime on purpose. A literal em dash cannot appear in this file:
# em-dash-lint.sh blocks any Write containing one, and this path is not under
# ref/ or memory/, so the exemptions do not apply. The test would be
# unwritable if it hardcoded the character it is testing for.
EMDASH=$(printf '\xe2\x80\x94')
ENDASH=$(printf '\xe2\x80\x93')

# fires <expected: yes|no> <json-quoted prompt> <description>
fires() {
    local expect="$1" prompt="$2" desc="$3"
    local out got
    out=$(printf '%s' "{\"prompt\":$prompt}" | "$HOOKS_DIR/wiki-ingest-suggest.sh" 2>/dev/null)
    if printf '%s' "$out" | grep -q additionalContext; then got=yes; else got=no; fi
    if [ "$got" = "$expect" ]; then
        printf '  ok    %s\n' "$desc"; pass=$((pass+1))
    else
        printf '  FAIL  %s (expected %s, got %s)\n' "$desc" "$expect" "$got"; fail=$((fail+1))
    fi
}

# blocks <expected: yes|no> <file_path> <content> <description>
blocks() {
    local expect="$1" path="$2" content="$3" desc="$4"
    local rc got
    printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$path\",\"content\":\"$content\"}}" \
        | "$HOOKS_DIR/em-dash-lint.sh" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 2 ]; then got=yes; else got=no; fi
    if [ "$got" = "$expect" ]; then
        printf '  ok    %s\n' "$desc"; pass=$((pass+1))
    else
        printf '  FAIL  %s (expected block=%s, got %s)\n' "$desc" "$expect" "$got"; fail=$((fail+1))
    fi
}

echo "wiki-ingest-suggest.sh: should fire"
fires yes '"/Users/x/a.zip here"'                  'bare path, leading'
fires yes '"look at /Users/x/a.zip"'               'bare path, mid-sentence'
fires yes '"@/Users/x/a.zip"'                      '@path, unquoted'
fires yes '"@\"/Users/x/a.zip\""'                  '@"path" quoted (the real UI form)'
fires yes '"@\"/Users/x/a.zip\"\nwhat is this"'    'quoted @path plus following text'
fires yes '"~/Downloads/a.zip"'                    'tilde path'

echo "wiki-ingest-suggest.sh: should stay silent"
fires no  '"review this /Users/x/a.zip"'           'override: review this'
fires no  '"/Users/x/a.zip do not save"'           'override: do not save'
fires no  '"/Users/x/a.zip dont save it"'          'override: dont save'
fires no  '"/Users/x/a.zip fix this"'              'override: fix this'
fires no  '"what is the engagement status"'        'no path present'
fires no  '""'                                     'empty prompt'

echo "em-dash-lint.sh"
blocks yes '/tmp/x/note.md'          "a ${EMDASH} b"  'plain file with em dash is blocked'
blocks yes '/tmp/x/note.md'          "a ${ENDASH} b"  'plain file with en dash is blocked'
blocks no  '/tmp/x/note.md'          'a, b, c'        'plain file without dashes passes'
blocks no  '/tmp/x/ref/source.md'    "a ${EMDASH} b"  'ref/ capture with em dash passes (verbatim rule)'
blocks no  '/x/.claude/projects/p/memory/m.md' "a ${EMDASH} b" 'memory file with em dash passes'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
