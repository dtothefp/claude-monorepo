# Research Index

The curated entry point to the shared knowledge wiki. This is the one file you read to know what's in here. Update it when a conclusion changes, not every time a file lands.

Raw sources live in topic subdirs (`research/<topic>/`), immutable once written. The append-only changelog is in [log.md](log.md). The retrieval agents (`research-professor`, `wiki-query`) read this index plus the knowledge graph.

## Topics

<!-- Add a section per topic as you ingest. Example:

### ai-tooling
What we know about the AI tooling landscape. Key files:
- `ai-tooling/some-source-2026-06-29.md` (one-line summary of the conclusion)

-->

### retrieval

How this workspace finds things in its own wiki: the knowledge graph, the planned embeddings layer, and the decisions constraining both.

Current conclusion: the graph is not the weak part of retrieval, the doorway into it is. `graphify query` picks its traversal starting nodes by substring-matching question terms against node labels, with no stemming or synonyms, so a paraphrased question finds nothing and falls back to reading the index by hand. The planned fix is narrow rather than architectural: use vector search to choose the graph's entry points and change nothing else, which preserves community detection and the per-edge record of whether a connection was stated in a source or inferred by a model. Nothing is built yet, and an eval baseline is a prerequisite rather than a follow-up.

- [`retrieval/graphify-and-embeddings-2026-08-11.md`](retrieval/graphify-and-embeddings-2026-08-11.md), the current reading. Where two independently written designs for the embeddings layer converged (sqlite-vec, hybrid FTS5 plus KNN fused with RRF, brute force at this scale, a model-and-dimension check that refuses rather than silently mixing vector spaces), and the four things decision history settles that guesswork had missed: cascade deletes so `git rm` really is the deletion API, a chunk-to-graph-node join key without which vector precision is thrown away, an eval baseline as a prerequisite rather than a follow-up, and three documented regressions worth never repeating. Also records where the tooling has moved on: graphify 0.9.32 ships a headless `extract`, so unattended rebuilds no longer need an agent session.
