#!/usr/bin/env bash
set -uo pipefail
#
# wiki-embed-daily.sh
#
# Keep the semantic-search index in step with the wiki. Run by launchd once a
# day, right after graphify-daily. See scripts/routines/install.sh.
#
# Usage:
#   ./scripts/routines/wiki-embed-daily.sh            # incremental reindex
#   ./scripts/routines/wiki-embed-daily.sh --status   # corpus sizing, no work
#
# ---------------------------------------------------------------------------
# STATUS: the indexer this routine drives does not exist yet.
#
# The design is docs/semantic-search-plan.md. The evidence behind it is
# research/retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md.
#
# It is deliberately not implemented yet. The handoff brief records a decision
# (ADR-0026 on the other machine) that the retrieval eval harness runs BEFORE
# and AFTER any retrieval change, and that the question set is expanded with
# paraphrase-heavy cases first, so the questions are not written to flatter the
# implementation. Neither the harness nor a baseline exists in this checkout.
# Shipping an embeddings layer before that gate would make it impossible to say
# afterwards whether it helped.
#
# So this routine is scheduled now and runs preflight every day. The moment
# scripts/wiki-embed.sh lands it starts doing real work with no change here.
# Until then `--status` reports the real corpus sizing, which is the input the
# implementation needs anyway.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INDEXER="$WORKSPACE_DIR/scripts/wiki-embed.sh"

LOG_DIR="${GRAPHIFY_ROUTINE_LOG_DIR:-$HOME/Library/Logs}"
LOG_FILE="$LOG_DIR/wiki-embed-daily.log"
mkdir -p "$LOG_DIR"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MODE="run"
case "${1:-}" in
    --status) MODE="status" ;;
    "")       ;;
    *)        echo "unknown argument: $1" >&2; exit 2 ;;
esac

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

log "=== wiki-embed-daily start (mode=$MODE) ==="

# --- discover the wikis this would index ------------------------------------
#
# One index per wiki root, written next to the wiki it indexes. Never one index
# spanning the parent and a package: packages/*/ is gitignored for
# confidentiality reasons and a merged index would launder that boundary away.

# `repositories/` holds independent clones of upstream repos (see
# packages/artium/AGENTS.md). Their research/ trees belong to those projects,
# not to us. Indexing them would mix upstream content into our index and put
# other people's material behind our search.
WIKIS=()
while IFS= read -r d; do
    [ -n "$d" ] && WIKIS[${#WIKIS[@]}]="$d"
done < <(
    find "$WORKSPACE_DIR" \
        -type d \( -name node_modules -o -name .git -o -name graphify-out \
                   -o -name .venv -o -name repositories \) -prune -o \
        -type d -name research -print 2>/dev/null | sort
)

TOTAL_FILES=0; TOTAL_WORDS=0

for wiki in ${WIKIS[@]+"${WIKIS[@]}"}; do
    name="${wiki#"$WORKSPACE_DIR"/}"

    # log.md is bookkeeping, not prose. Indexing it floods every result set.
    files=$(find "$wiki" -type f -name '*.md' ! -name 'log.md' 2>/dev/null | wc -l | tr -d ' ')
    words=0
    if [ "$files" -gt 0 ]; then
        words=$(find "$wiki" -type f -name '*.md' ! -name 'log.md' -print0 2>/dev/null \
                | xargs -0 cat 2>/dev/null | wc -w | tr -d ' ')
    fi
    raw=$(find "$wiki" -type f -name '*.md' -path '*/ref/*' 2>/dev/null | wc -l | tr -d ' ')
    syn=$((files - raw))

    TOTAL_FILES=$((TOTAL_FILES + files))
    TOTAL_WORDS=$((TOTAL_WORDS + words))

    # ~800-token chunks with 15% overlap, ~1.33 tokens per word.
    chunks=$(( (words * 133 / 100) / 800 * 115 / 100 + 1 ))
    log "  $name: $files files ($raw raw, $syn synthesis), $words words, ~$chunks chunks"
done

log "  TOTAL: $TOTAL_FILES files, $TOTAL_WORDS words across ${#WIKIS[@]} wikis"

if [ "$MODE" = "status" ]; then
    log "=== status only, no indexing attempted ==="
    exit 0
fi

# --- preflight ---------------------------------------------------------------

if [ ! -x "$INDEXER" ]; then
    log "indexer not built yet: scripts/wiki-embed.sh"
    log "  design:   docs/semantic-search-plan.md"
    log "  evidence: research/retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md"
    log "  blocked on: an eval baseline. Expand the question set with paraphrase"
    log "              cases and record a before-score, then implement."
    log "=== done (no-op) ==="
    exit 0   # exit 0 on purpose: a scheduled job that is correctly idle is not a failure
fi

INDEXED=0; FAILED=0
for wiki in ${WIKIS[@]+"${WIKIS[@]}"}; do
    name="${wiki#"$WORKSPACE_DIR"/}"
    root="$(dirname "$wiki")"
    log "indexing $name"
    if ( cd "$root" && "$INDEXER" "$wiki" >>"$LOG_FILE" 2>&1 ); then
        INDEXED=$((INDEXED+1)); log "  ok $name"
    else
        FAILED=$((FAILED+1)); log "  FAILED $name (see $LOG_FILE)"
    fi
done

log "=== done: $INDEXED indexed, $FAILED failed ==="

if [ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

[ $FAILED -eq 0 ]
