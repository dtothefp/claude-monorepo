#!/usr/bin/env bash
set -uo pipefail
#
# graphify-daily.sh
#
# Rebuild every knowledge graph in the workspace that already exists. Run by
# launchd once a day. See scripts/routines/install.sh.
#
# Usage:
#   ./scripts/routines/graphify-daily.sh              # rebuild all existing graphs
#   ./scripts/routines/graphify-daily.sh --dry-run    # list what it would do
#   ./scripts/routines/graphify-daily.sh --check      # report staleness only
#
# ---------------------------------------------------------------------------
# Rules this script exists to enforce. Each one is here because breaking it
# caused a real regression, recorded in
# research/retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md.
#
# 1. PER-PROJECT ISOLATION. Every graphify invocation runs with cwd inside the
#    project that owns the graph. graphify resolves `graphify-out/` from the
#    detected project root, so building a package's graph from the parent root
#    writes into the PARENT's graphify-out and clobbers the parent graph.
#
# 2. FIRST RUNS ARE MANUAL. This script only rebuilds corpora that already have
#    a graph.json. A first extraction is expensive and can trip graphify's
#    corpus-size warning, which needs a human to answer. Projects with a scope
#    file but no graph are reported as "awaiting first run" and skipped.
#
# 3. ONE ROOT PER PROJECT, NEVER A LOOP OVER SCOPE PATHS. Calling incremental
#    detection once per scope path makes every file outside that path look
#    deleted, and the merge step then prunes those nodes. This cost 53 of 90
#    nodes in the parent graph on 2026-05-07 on the other machine. graphify
#    0.9.32 has no native `.graphify-scope` support (it reads `.graphifyignore`
#    and `.gitignore`), so a multi-path scope file is handled here by rooting at
#    the common ancestor and warning, never by looping.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
REFRESH="$WORKSPACE_DIR/scripts/graph-refresh.sh"

LOG_DIR="${GRAPHIFY_ROUTINE_LOG_DIR:-$HOME/Library/Logs}"
LOG_FILE="$LOG_DIR/graphify-daily.log"
mkdir -p "$LOG_DIR"

# launchd hands the job a minimal PATH. Everything below needs the user's tools.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

MODE="run"
case "${1:-}" in
    --dry-run) MODE="dry" ;;
    --check)   MODE="check" ;;
    "")        ;;
    *)         echo "unknown argument: $1" >&2; exit 2 ;;
esac

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

log "=== graphify-daily start (mode=$MODE) ==="

if [ ! -x "$REFRESH" ]; then
    log "FATAL: $REFRESH missing or not executable"
    exit 1
fi

# --- discover corpora --------------------------------------------------------
#
# A project is rebuildable if it already has graphify-out/graph.json. Search the
# parent and every package, but never descend into graphify-out itself or into
# node_modules.

# macOS ships bash 3.2, which has no `mapfile` and no associative arrays. This
# script has to run under /bin/bash because that is what launchd resolves, so
# everything here stays 3.2-compatible.
GRAPHS=()
while IFS= read -r line; do
    [ -n "$line" ] && GRAPHS[${#GRAPHS[@]}]="$line"
done < <(
    find "$WORKSPACE_DIR" \
        -type d \( -name node_modules -o -name .git -o -name .venv \) -prune -o \
        -type f -path '*/graphify-out/graph.json' -print 2>/dev/null | sort
)

if [ ${#GRAPHS[@]} -eq 0 ]; then
    log "no graphs found. Build one first: /graphify <path> in a session."
fi

# --- resolve the corpus path for a project ----------------------------------
#
# Honors both scope-file conventions from the other machine, so a repo carrying
# them keeps working:
#   <root>/.graphify-scope           lines are paths relative to the root
#   <root>/research/.graphify-scope  lines are subdirs under research/
# The root one wins if both exist.

# Prints "<corpus path><TAB><flag>" on one line. flag is empty, or MULTIPATH
# when a scope file named more than one path and we collapsed to the ancestor.
resolve_corpus() {
    local root="$1" scope_file="" prefix="" paths=()
    if [ -f "$root/.graphify-scope" ]; then
        scope_file="$root/.graphify-scope"; prefix=""
    elif [ -f "$root/research/.graphify-scope" ]; then
        scope_file="$root/research/.graphify-scope"; prefix="research/"
    fi

    if [ -z "$scope_file" ]; then
        if [ -d "$root/research" ]; then printf '%s\t\n' "$root/research"; else printf '%s\t\n' "$root"; fi
        return
    fi

    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        [ -e "$root/$prefix$line" ] && paths[${#paths[@]}]="$prefix$line"
    done < "$scope_file"

    if [ ${#paths[@]} -eq 0 ]; then
        if [ -d "$root/research" ]; then printf '%s\t\n' "$root/research"; else printf '%s\t\n' "$root"; fi
    elif [ ${#paths[@]} -eq 1 ]; then
        printf '%s\t\n' "$root/${paths[0]}"
    else
        # Rule 3. Do not loop. Root at the common ancestor instead and let
        # .graphifyignore trim, so no file ever looks deleted to detection.
        local common="${paths[0]%%/*}" p
        for p in "${paths[@]}"; do
            if [ "${p%%/*}" != "$common" ]; then common=""; break; fi
        done
        if [ -n "$common" ] && [ -d "$root/$common" ]; then
            printf '%s\tMULTIPATH\n' "$root/$common"
        else
            printf '%s\tMULTIPATH\n' "$root"
        fi
    fi
}

REBUILT=0; SKIPPED=0; FAILED=0

for graph in "${GRAPHS[@]}"; do
    out_dir="$(dirname "$graph")"
    root="$(dirname "$out_dir")"
    name="${root#"$WORKSPACE_DIR"/}"
    [ "$root" = "$WORKSPACE_DIR" ] && name="_parent"

    resolved="$(resolve_corpus "$root")"
    corpus="${resolved%%	*}"
    multipath=""
    case "$resolved" in
        *MULTIPATH) multipath=" (multi-path scope, rooted at common ancestor)" ;;
    esac

    built_at="$(date -r "$graph" '+%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)"

    if [ "$MODE" = "check" ]; then
        # Freshness against log.md is the same signal the retrieval agents use:
        # anything logged after the graph's mtime is in the freshness gap.
        gap=0
        for logmd in "$root"/research/log.md "$root"/*/log.md; do
            [ -f "$logmd" ] && [ "$logmd" -nt "$graph" ] && gap=1
        done
        [ $gap -eq 1 ] && log "STALE   $name (graph $built_at, log.md newer)" \
                       || log "fresh   $name (graph $built_at)"
        continue
    fi

    if [ "$MODE" = "dry" ]; then
        log "would rebuild $name from ${corpus#"$WORKSPACE_DIR"/}$multipath"
        continue
    fi

    log "rebuilding $name from ${corpus#"$WORKSPACE_DIR"/}$multipath (graph built $built_at)"

    # Rule 1: cwd inside the owning project for the whole invocation.
    if ( cd "$root" && "$REFRESH" "$corpus" >>"$LOG_FILE" 2>&1 ); then
        REBUILT=$((REBUILT+1)); log "  ok $name"
    else
        FAILED=$((FAILED+1)); log "  FAILED $name (see $LOG_FILE)"
    fi
done

# --- report corpora awaiting a first (manual) run ---------------------------

while IFS= read -r scope; do
    root="$(dirname "$scope")"
    [ "$(basename "$root")" = "research" ] && root="$(dirname "$root")"
    [ -f "$root/graphify-out/graph.json" ] && continue
    name="${root#"$WORKSPACE_DIR"/}"
    log "awaiting first run (manual): $name    run:  /graphify ${name}/research"
    SKIPPED=$((SKIPPED+1))
done < <(find "$WORKSPACE_DIR" -type d -name node_modules -prune -o -name '.graphify-scope' -print 2>/dev/null)

log "=== done: $REBUILT rebuilt, $FAILED failed, $SKIPPED awaiting first run ==="

# Keep the log from growing without bound. 2000 lines is a few weeks of runs.
if [ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

[ $FAILED -eq 0 ]
