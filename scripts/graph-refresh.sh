#!/usr/bin/env bash
set -uo pipefail
#
# graph-refresh.sh
#
# Rebuild the knowledge graph for a research wiki, headlessly.
#
# This is the unattended counterpart to the `/graphify` skill. The skill drives
# the same pipeline through Claude Code subagents, which is what you want when
# you are sitting there and can answer its questions. This script calls
# `graphify extract`, the CLI's own headless path, which is what you want from a
# cron job, a launchd timer, or a pre-commit sweep.
#
# Usage:
#   ./scripts/graph-refresh.sh                          # research/ in this repo
#   ./scripts/graph-refresh.sh packages/artium/research # any other wiki
#   ./scripts/graph-refresh.sh <path> --check           # is a rebuild pending?
#   ./scripts/graph-refresh.sh <path> --full            # ignore caches, re-extract all
#   ./scripts/graph-refresh.sh <path> --code-only       # AST only, no LLM, no key
#
# Backend selection, in order:
#   1. $GRAPHIFY_BACKEND if you set it explicitly.
#   2. graphify's own auto-detection, if any provider key is in the environment.
#   3. claude-cli, which shells out to `claude -p` and rides your Claude Code
#      subscription auth.
#
# (3) is the default here on purpose. This repo's hard rule is that no API key
# ever lands in the tree, and the wiki is small enough that subscription auth is
# the cheapest correct answer. graphify deliberately excludes claude-cli from
# its own auto-detection, so it has to be passed explicitly.
#
# Output lands in <corpus-root>/graphify-out/, which .gitignore already covers.
# The graph is a build artifact: it regenerates from research/ and is never
# committed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

TARGET=""
MODE="incremental"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --check)      MODE="check"; shift ;;
        --full)       MODE="full"; shift ;;
        --code-only)  EXTRA_ARGS+=("--code-only"); shift ;;
        --deep)       EXTRA_ARGS+=("--mode" "deep"); shift ;;
        -h|--help)    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*)          EXTRA_ARGS+=("$1"); shift ;;
        *)            TARGET="$1"; shift ;;
    esac
done

TARGET="${TARGET:-$WORKSPACE_DIR/research}"
if [ ! -d "$TARGET" ]; then
    echo "error: no such directory: $TARGET" >&2
    exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

# --- graphify present? -------------------------------------------------------

if ! command -v graphify >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: graphify is not installed.

  uv tool install graphifyy      # recommended, keeps it off system python
  pipx install graphifyy
  pip install graphifyy

Then re-run this script.
EOF
    exit 1
fi

# --- where does graphify-out go? ---------------------------------------------
#
# Walk up from the corpus looking for a project marker, so the build artifact
# lands at the root of whatever owns the wiki rather than wherever the shell
# happened to be. A wiki inside packages/<name>/ gets its output inside that
# package, which keeps gitignored material gitignored.

CORPUS_ROOT="$TARGET"
while [ "$CORPUS_ROOT" != "/" ]; do
    if [ -e "$CORPUS_ROOT/CLAUDE.md" ] || [ -e "$CORPUS_ROOT/AGENTS.md" ] || [ -d "$CORPUS_ROOT/.git" ]; then
        break
    fi
    CORPUS_ROOT="$(dirname "$CORPUS_ROOT")"
done
[ "$CORPUS_ROOT" = "/" ] && CORPUS_ROOT="$WORKSPACE_DIR"

GRAPH_JSON="$CORPUS_ROOT/graphify-out/graph.json"

echo "Corpus: $TARGET"
echo "Output: $CORPUS_ROOT/graphify-out/"

# --- --check: is a rebuild pending? ------------------------------------------
#
# `graphify check-update` is the CLI's own cron-safe probe. It reads the
# needs_update flag rather than doing any work, so a timer can call this every
# hour and only escalate to a real rebuild when something actually changed.

if [ "$MODE" = "check" ]; then
    if [ ! -f "$GRAPH_JSON" ]; then
        echo "status: no graph yet, run without --check to build one"
        exit 0
    fi
    graphify check-update "$TARGET"
    exit $?
fi

# --- backend -----------------------------------------------------------------

BACKEND="${GRAPHIFY_BACKEND:-}"
if [ -z "$BACKEND" ]; then
    if [ -n "${GEMINI_API_KEY:-}${ANTHROPIC_API_KEY:-}${OPENAI_API_KEY:-}${DEEPSEEK_API_KEY:-}${MOONSHOT_API_KEY:-}" ]; then
        BACKEND=""   # let graphify auto-detect from the key that is set
    else
        BACKEND="claude-cli"
    fi
fi

# The claude-cli backend shells out to `claude` and resolves it with which(), so
# it has to be a host binary on $PATH. Note that having the Claude Code desktop
# app installed is NOT sufficient: the copy it ships under
# "Application Support/Claude/claude-code-vm/<version>/claude" is a Linux build
# for the app's sandbox VM and will not exec on the macOS host. Checked on
# 2026-08-11, do not add it as a fallback. The standalone CLI is a separate
# install.
if [ "$BACKEND" = "claude-cli" ] && ! command -v claude >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: no LLM backend available for the semantic half of extraction.

Pick one:
  - install the standalone CLI:  npm i -g @anthropic-ai/claude-code
  - export a provider key:       GEMINI_API_KEY / ANTHROPIC_API_KEY / ...
  - run `/graphify <path>` inside a Claude Code session, which drives the same
    pipeline through subagents and needs neither of the above
  - re-run with --code-only to skip semantics entirely (AST only, no model)
EOF
    exit 1
fi

CMD=(graphify extract "$TARGET" --out "$CORPUS_ROOT")
[ -n "$BACKEND" ] && CMD+=(--backend "$BACKEND")
[ "$MODE" = "full" ] && CMD+=(--force)
[ ${#EXTRA_ARGS[@]} -gt 0 ] && CMD+=("${EXTRA_ARGS[@]}")

echo "Backend: ${BACKEND:-auto}"
echo "Running: ${CMD[*]}"
echo ""

"${CMD[@]}"
RC=$?

echo ""
if [ $RC -ne 0 ]; then
    echo "graphify exited $RC. The previous graph, if any, is untouched."
    exit $RC
fi

# --- summary -----------------------------------------------------------------

if [ -f "$GRAPH_JSON" ]; then
    python3 - "$GRAPH_JSON" <<'PY'
import json, sys
from collections import Counter
g = json.load(open(sys.argv[1]))
nodes = g.get("nodes", [])
# Clustered output stores edges under "links", raw extraction under "edges".
# Reading only "edges" silently reports zero on every clustered graph, which is
# every graph this script builds. Same trap as loading with networkx's default
# edges="edges", which yields an empty graph without erroring.
edges = g.get("links") or g.get("edges", [])
conf = Counter(e.get("confidence", "?") for e in edges)
comms = {n.get("community") for n in nodes if n.get("community") is not None}
print(f"{len(nodes)} nodes, {len(edges)} edges, {len(comms)} communities")
if conf:
    print("  edges by provenance: " + ", ".join(f"{k} {v}" for k, v in conf.most_common()))
if g.get("built_at_commit"):
    print(f"  built at commit: {g['built_at_commit'][:12]}")
PY
    echo ""
    echo "  graph:  $CORPUS_ROOT/graphify-out/graph.json"
    echo "  html:   $CORPUS_ROOT/graphify-out/graph.html"
    echo "  report: $CORPUS_ROOT/graphify-out/GRAPH_REPORT.md"
    echo ""
    echo "Query it:  graphify query \"your question\" --graph $GRAPH_JSON"
fi
