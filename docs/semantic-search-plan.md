# Semantic search over the wiki (sqlite-vec)

Status: plan, not built. Nothing in this document is wired up yet.

## The gap

Three retrieval paths exist today and none of them does similarity.

- `research/index.md` is curated and human-maintained. It finds what someone
  remembered to write down.
- `grep` finds exact strings. It misses paraphrase, which is most of the value in
  a wiki written by a model that varies its wording run to run.
- `/graphify` finds *structure*: entities, citations, call edges, communities. It
  answers "what is connected to what." It does not answer "what reads like this."

The missing path is: given a sentence, find the passages that mean roughly the
same thing, across every file, without knowing what words they used. That is an
embedding index, and it belongs next to the graph rather than instead of it.

## Decision

**sqlite-vec** for storage and search, **local embeddings** for the vectors,
**FTS5** alongside for lexical recall, fused with **reciprocal rank fusion**.

One file, `research/.wiki-index.db`, gitignored, regenerated from the wiki the
same way `graphify-out/` is.

### Why sqlite-vec

It is a loadable SQLite extension that adds `vec0` virtual tables and brute-force
KNN. At this corpus size that is not a compromise, it is the correct answer:

- The whole parent wiki plus every package wiki is on the order of 10^3 to 10^4
  chunks. Brute-force cosine over 10^4 x 768 float32 is a few milliseconds. An
  ANN index would add build time, tuning, and recall loss to buy back nothing.
- No server, no daemon, no port. It is a file. It backs up, copies, and deletes
  like a file, and an agent can open it with two lines of Python.
- It sits in the same database as FTS5, so hybrid search is one query against one
  connection rather than a join across two systems.
- The graph and the index can share a primary key (`source_file`), so a vector
  hit can hand off to `graphify query` without a translation layer.

### What was ruled out

- **sqlite-vss.** Superseded by sqlite-vec from the same author. Do not start
  here.
- **Chroma, LanceDB, Qdrant, pgvector.** All fine tools, all a server or a new
  storage engine to operate, all aimed at a scale this wiki will not reach. The
  moment the corpus is genuinely large the migration is a re-embed, which is
  cheap, so there is no lock-in cost to starting small.
- **DuckDB VSS.** Better at analytics over the corpus, worse at being a thing an
  agent opens mid-conversation. SQLite is already everywhere.
- **Embeddings via a hosted API as the default.** Would put a key in the loop for
  a workflow that should run offline on a plane. Kept as an option, not the
  default. See below.

### Embedding model

Default to a local model, for the same reason `transcribe.sh` runs mlx-whisper
locally: no key, no per-run cost, works offline, and the wiki is small enough
that quality-per-dollar is not the binding constraint.

Two credible local paths, both already plausible on this machine:

| Path | Model | Dim | Notes |
|---|---|---|---|
| Ollama | `nomic-embed-text` or `embeddinggemma` | 768 | Easiest. One `ollama pull`, HTTP on localhost, no Python deps. |
| MLX | an MLX embedding model | 384 to 768 | Matches the existing mlx-whisper pattern, Apple Silicon only, no daemon. |

If a hosted model is ever wanted for quality, the two that matter are Voyage
(Anthropic's recommended embedding partner, since Anthropic ships no embedding
model of its own) and OpenAI `text-embedding-3-small`. Both would read their key
from `.env`, never from the tree.

**Pick one and write it down in the DB.** The dimension is baked into the `vec0`
table definition, and vectors from two different models are not comparable even
at the same dimension. Store `model` and `dim` in a `meta` table and have the
indexer refuse to append to a database built with a different model.

## Where it sits in the pipeline

Adds one row to the retrieval table in `AGENTS.md`:

| Need | Use |
|---|---|
| "What do we know about X?" | `wiki-query` skill (graph-first) |
| "What else reads like this passage?" | semantic search (this) |
| Substantive synthesis across many sources | `research-professor` agent |

The interesting version is not either/or. `wiki-query` becomes:

1. Embed the question, KNN for the top ~20 chunks. This finds entry points by
   meaning, which is what the graph is bad at.
2. Map those chunks to their `source_file`, look those files up as graph nodes,
   and expand one or two hops with `graphify query`. This finds the neighbors,
   which is what embeddings are bad at.
3. Answer from the union, citing chunk-level line ranges.

That is GraphRAG, assembled from two tools already in the repo instead of a
framework.

## Schema

```sql
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
);  -- model, dim, indexer_version, built_at

CREATE TABLE chunks (
  id           INTEGER PRIMARY KEY,
  source_file  TEXT NOT NULL,   -- repo-relative, joins to the graph
  wiki         TEXT NOT NULL,   -- 'research' or 'packages/<name>/research'
  topic        TEXT,            -- the topic subdir
  provenance   TEXT NOT NULL,   -- 'raw' | 'synthesis'   <-- load-bearing
  heading      TEXT,            -- nearest enclosing heading
  line_start   INTEGER,
  line_end     INTEGER,
  content_hash TEXT NOT NULL,   -- sha256 of the chunk, for incremental rebuild
  text         TEXT NOT NULL
);

CREATE VIRTUAL TABLE chunks_vec USING vec0(
  chunk_id     INTEGER PRIMARY KEY,
  embedding    FLOAT[768],
  provenance   TEXT PARTITION KEY   -- lets a query stay inside one layer
);

CREATE VIRTUAL TABLE chunks_fts USING fts5(
  text, content='chunks', content_rowid='id'
);
```

### Provenance is a first-class column, not a nice-to-have

This is the whole reason to build the index in-house rather than pointing a
generic RAG tool at `research/`. The wiki's core discipline is that `ref/` holds
what a source said and everything else holds what a model inferred. A search
index that flattens both into "documents" destroys that boundary at exactly the
moment it matters most, which is when an agent is assembling an answer and
deciding what it is allowed to assert.

So:

- `provenance` is derived from the path (`/ref/` in it or not), never from
  frontmatter, because the path is the thing the governance rules actually
  guarantee.
- Every result carries it, and any agent-facing output must show it.
- `--raw-only` and `--synthesis-only` are supported query modes. "Find me the
  evidence, not our reading of it" is a real question and it should be one flag.
- A chunk from `ref/` is quotable as evidence. A chunk from a synthesis file is
  quotable only as our own prior conclusion, and should be traced back to the
  `sources:` it cites before being treated as fact.

### Chunking

Split on markdown headings first, then pack sections to roughly 400 to 600 tokens
with about 15% overlap, never crossing a heading boundary at the top level.
Carry the heading path into the embedded text (`# Topic > ## Section\n\n<body>`),
because a heading is usually the only place the subject of the section is named
and the body pronouns back to it.

Frontmatter is indexed as its own chunk. It is short, it is high signal (title,
`sources:`, `topics:`), and embedding it separately keeps YAML noise out of the
prose chunks.

Skip: `log.md` (append-only bookkeeping, it would flood every result set),
`graphify-out/`, anything gitignored, and binaries.

## The routine

`scripts/wiki-embed.sh`, shaped like `scripts/graph-refresh.sh`:

```bash
./scripts/wiki-embed.sh                                  # research/
./scripts/wiki-embed.sh packages/artium/research         # any wiki
./scripts/wiki-embed.sh <path> --check                   # what is stale?
./scripts/wiki-embed.sh <path> --rebuild                 # drop and re-embed
./scripts/wiki-embed.sh <path> --query "how do evals work"
```

Incremental by content hash: walk the wiki, hash each chunk, embed only the
hashes not already in `chunks`, delete rows whose source file is gone. A no-op
run over an unchanged wiki should touch zero vectors and finish in well under a
second, because that is what makes it safe to call from a hook or a timer.

Two scheduling options, in increasing order of commitment:

1. **Manual, alongside the graph.** Run `graph-refresh.sh` and `wiki-embed.sh`
   after an ingest session. Simplest, and honest about how bursty ingestion
   actually is.
2. **A launchd timer.** Nightly, `--check` first, embed only if stale. The repo
   already has the pattern in `gws-healthcheck-alert.sh`.

A PostToolUse hook firing on every wiki write was considered and rejected: it
puts a model load on the critical path of a file save, and the index being a few
minutes stale has never cost anything.

## Gotchas that will actually bite

- **Extension loading is disabled in some Python builds.** macOS system Python's
  `sqlite3` is compiled without `enable_load_extension`, so `sqlite_vec.load()`
  fails with a confusing error. Use a Homebrew or `uv`-managed interpreter and
  assert the capability at startup with a clear message rather than letting it
  surface as a SQLite error 40 lines later.
- **Changing the embedding model invalidates the whole database.** Not partially.
  The indexer must compare `meta.model` and refuse rather than silently mixing
  vector spaces, which fails as slightly-worse results rather than as an error
  and is therefore very hard to notice.
- **Never write anything back into `ref/`.** The indexer reads the wiki and
  writes only to its own database. No sidecar files next to sources, no
  frontmatter stamping. The raw layer is immutable, including its metadata.
- **The database is gitignored.** Add `*.wiki-index.db*` (and the `-wal` and
  `-shm` siblings) to `.gitignore`. It is a build artifact and it would carry
  client material from package wikis into a public repo, which is the exact
  failure mode that just cost this repo a file move.
- **Package wikis stay in their package.** One database per wiki root, written
  next to the wiki it indexes. Do not build a single cross-tier index in the
  parent, because `packages/*/` is gitignored for confidentiality reasons and a
  merged index would launder that boundary away.

## Rollout

Each phase is independently useful and independently abandonable.

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | Decide the model, confirm extension loading works on this machine | `sqlite_vec.load()` succeeds and returns a version string |
| 1 | Chunker only, no embeddings, dump chunks to JSON | Chunk boundaries look right by eye on `ramp-up-synthesis` |
| 2 | `wiki-embed.sh` build path, `chunks` + `chunks_vec` populated | Full build on `packages/artium/research` under 60s |
| 3 | `--query`, plain KNN | "eval sampling design" returns the eval files above the Fiserv ones |
| 4 | FTS5 + RRF hybrid | Beats either leg alone on ten hand-written questions |
| 5 | `wiki-query` skill wired to it, graph expansion on top | The skill cites chunk line ranges and labels each hit raw or synthesis |

Stop after 3 if it turns out that is enough. It might be.

## Open questions

1. **Ollama or MLX for the local model.** Ollama is less code and one more daemon.
   MLX is more code and matches how transcription already works here.
2. **Does this ship in the public boilerplate?** The plan and scripts, yes. It is
   the kind of thing the repo exists to demonstrate. The databases never do.
3. **One database per wiki, or one per tier?** This plan assumes per wiki, on
   confidentiality grounds. Worth revisiting only if cross-wiki search turns out
   to be something you actually want, and if so it needs an explicit answer for
   what happens to client material.
