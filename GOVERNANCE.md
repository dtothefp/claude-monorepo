# Governance

How memory and the research wiki stay clean over time. Short list, because a short list gets followed.

## Memory

Claude Code keeps a persistent memory across sessions. The rules:

- One file per topic. Update the existing file, don't create a v2.
- Only save what a future session can't figure out from the code or git history.
- Consolidate over append. If two notes overlap, merge them.

## Research wiki

`research/` has four layers (the Karpathy pattern, with the raw layer split out):

1. **Raw sources** in `research/<topic>/ref/`. What the source actually said, and nothing else. **Never LLM-authored.** Immutable once written.
2. **Synthesis** in `research/<topic>/`, one directory up from `ref/`. Model-authored readings of the raw layer. Every synthesis cites the `ref/` files it rests on in its `sources:` frontmatter.
3. **`research/index.md`** is the curated entry point. The one file you read to know what we know. Update it when a conclusion changes.
4. **`research/log.md`** is an append-only changelog. One line per new artifact, newest at the bottom. A PostToolUse hook (`.claude/hooks/research-log-append.sh`) appends here automatically when you write a wiki file, so you rarely touch it by hand.

### Why raw and synthesis are separate files

A single file mixing a model's summary with the fetched body loses the boundary the first time someone edits it, and a later agent summarizing that file cannot tell which sentences are evidence and which are inference. Errors compound quietly: a summary of a summary reads exactly as confident as the source. Putting the split in the path rather than in a heading makes provenance survive editing, grep, and re-ingestion.

The practical test: for any sentence in the wiki, you should be able to answer "did a human or a source say this, or did a model infer it?" by looking at which directory it lives in.

Rules:

- Every ingest writes **both** files. A synthesis with no `ref/` counterpart is incomplete.
- **Research subagents capture to `ref/` as they go.** Never tell an agent that will fetch primary sources not to write files. It is the single easiest way to destroy the evidence layer, because the subagent is the only thing that ever touches the sources. One file per source document, not one per topic.
- Nothing model-authored goes in `ref/`. Stripping nav chrome from fetched HTML is fine. Rewording, condensing, or reordering is not.
- `source:` (singular) on raw files, one origin each. `sources:` (a list) on synthesis files, pointing at `ref/` paths. This is a meaning distinction, not a style choice.
- `index.md` links to synthesis files, never into `ref/` directly.
- Supersession annotates the synthesis. The raw file is never touched, because superseding says which reading is current, not what the evidence said.
- New file means append one line to `log.md`, and update `index.md` if it changes a conclusion.
- Never rewrite history. Add, supersede, don't delete.
- Keep entries short. If one runs past a few paragraphs, split it.
- Filename convention: `<topic>-YYYY-MM-DD.md`. Date in frontmatter, not the filename prefix. The raw file and its synthesis share a filename.

The full frontmatter schema lives in [.claude/skills/wiki-ingest/SKILL.md](.claude/skills/wiki-ingest/SKILL.md) Step 5. Key names follow Obsidian Web Clipper's vocabulary where one exists, since there is no formal standard for provenance frontmatter and that is the closest thing to a widely-deployed convention.

## The knowledge graph

`/graphify <path>` builds a knowledge graph over the wiki. It rebuilds on demand. The retrieval skills (`wiki-query`, `research-professor`) are graph-first when a graph exists, and fall back to the index plus a freshness check on `log.md` otherwise. Anything ingested after the last graph build is in the freshness gap, so the retrieval agents read those raw files directly.

`scripts/graph-refresh.sh <path>` is the same build without a session around it, for cron or a post-ingest sweep. Rules that hold either way:

- **The graph is a build artifact.** `graphify-out/` is gitignored and never committed. If it is wrong, rebuild it, do not edit it.
- **One graph per wiki, written next to the wiki it indexes.** Never build a single graph spanning the parent and a package wiki. `packages/*/` is gitignored for confidentiality reasons and a merged graph would carry that material into a public repo.
- **The graph does not supersede `ref/`.** It is derived, lossy, and partly INFERRED. When an answer needs to be right, follow the node's `source_file` back to the raw capture.

Semantic search over the wiki (embeddings in SQLite) is planned, not built: [docs/semantic-search-plan.md](docs/semantic-search-plan.md). It is a companion to the graph, not a replacement. The graph answers "what is connected to what," embeddings answer "what reads like this."

## Decisions

Big architectural calls get a short ADR in `decisions/`, numbered `0001-`, `0002-`. One file per decision. It captures what you chose, why, and what you ruled out. You write it once and never touch it again, so future-you knows the reasoning.
