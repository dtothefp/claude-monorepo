# Governance

How memory and the research wiki stay clean over time. Short list, because a short list gets followed.

## Memory

Claude Code keeps a persistent memory across sessions. The rules:

- One file per topic. Update the existing file, don't create a v2.
- Only save what a future session can't figure out from the code or git history.
- Consolidate over append. If two notes overlap, merge them.

## Research wiki

`research/` has three layers (the Karpathy pattern):

1. **Raw sources** in topic subdirs (`research/<topic>/`). Immutable once written. If something changes, add a new dated file and mark the old one superseded.
2. **`research/index.md`** is the curated entry point. The one file you read to know what we know. Update it when a conclusion changes.
3. **`research/log.md`** is an append-only changelog. One line per new artifact, newest at the bottom. A PostToolUse hook (`.claude/hooks/research-log-append.sh`) appends here automatically when you write a wiki file, so you rarely touch it by hand.

Rules:

- New file means append one line to `log.md`, and update `index.md` if it changes a conclusion.
- Never rewrite history. Add, supersede, don't delete.
- Keep entries short. If one runs past a few paragraphs, split it.
- Filename convention: `<topic>-YYYY-MM-DD.md`. Date in frontmatter, not the filename prefix.

## The knowledge graph

`/graphify <path>` builds a knowledge graph over the wiki. It rebuilds on demand. The retrieval skills (`wiki-query`, `research-professor`) are graph-first when a graph exists, and fall back to the index plus a freshness check on `log.md` otherwise. Anything ingested after the last graph build is in the freshness gap, so the retrieval agents read those raw files directly.

## Decisions

Big architectural calls get a short ADR in `decisions/`, numbered `0001-`, `0002-`. One file per decision. It captures what you chose, why, and what you ruled out. You write it once and never touch it again, so future-you knows the reasoning.
