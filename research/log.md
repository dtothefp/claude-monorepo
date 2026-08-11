# Research Log

Append-only changelog. One line per new artifact, newest at the bottom. The
`research-log-append.sh` PostToolUse hook adds entries automatically when you
write a file under any `research/` directory.

Format: `YYYY-MM-DD <topic>/<file> — one-line summary`

---

- 2026-08-11: `retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md`, verbatim capture of a prior design brief for graphify plus a SQLite embeddings layer, carrying the decision history behind it. Held on disk and gitignored: it enumerates private projects by name and this wiki is public, and a raw capture is never edited to make it publishable. Pulled from personal Drive via the gws CLI.

- 2026-08-11: [`retrieval/graphify-and-embeddings-2026-08-11.md`](retrieval/graphify-and-embeddings-2026-08-11.md), the public reading of it, written to stand alone. Two independently written designs converged on sqlite-vec, hybrid FTS5 plus KNN with RRF at k=60, and brute force at this scale. Decision history settles four things guesswork missed: cascade deletes, the chunk-to-node join key, an eval baseline as a prerequisite, and three regressions with their causes. The tooling claim is stale (0.9.32 ships a headless `extract`), and this workspace is ahead on the raw/synthesis provenance split.
