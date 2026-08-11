# Semantic search over the wiki (sqlite-vec)

Status: plan, not built. Nothing in this document is wired up yet.

Sources: [research/retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md](../research/retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md)

Revision note. The first draft of this plan was written from model recall with no sources behind it. It has since been reconciled against a handoff brief from a prior session on another machine, which carries the recorded decisions (ADR-0002 Q7/Q9/Q10, ADR-0023, ADR-0025, ADR-0026) that constrain this design. Where the two agreed, the agreement is now noted as independent convergence. Where they differed, the brief generally won, because it has decision history behind it and this document had only inference.

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
**FTS5** alongside for lexical recall, fused with **reciprocal rank fusion at
k=60**.

Why fuse at all, in plain terms: dense vector search is a colleague who
understood what you meant but is vague on names, and lexical search is a
colleague with perfect recall for exact strings and no idea what you meant. Ask
both. Reciprocal rank fusion is the reconciliation rule, and it works by
throwing away the scores entirely, since a cosine similarity of 0.83 and a BM25
score of 11.2 are not on the same scale and never will be. It keeps only the
ranks and scores each result as the sum of `1 / (k + rank)` across the lists it
appeared in. A document placing third in both beats one placing first in one and
absent from the other. Pin `k=60`, the conventional default, so it does not
become an undocumented magic number.

Dense-only is not an option here: it regresses badly on exact identifiers,
filenames, and proper nouns, and a large share of real questions against this
wiki are of the form "what did ADR-0026 decide."

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

The interesting version is not either/or, and the reason is worth stating
precisely, because it is the strongest argument for building this at all.

`graphify query` finds its starting nodes by lowercasing the question, keeping
terms longer than three characters, and counting how many of them appear as
substrings of each node label. That is the entire retrieval step. No stemming,
no synonyms, no embeddings. Ask "how do we keep the wiki from drifting" and
nothing matches a node labelled "source-of-truth rule", so the query returns
nothing and the caller falls back to reading `index.md` by hand. Graph traversal
is excellent once you are at the right node. Getting to the right node is a
keyword lottery.

So the graph is not the weak part. The doorway into it is. Embeddings should
replace the doorway and change nothing else:

**Option A, the recommended one.** Embeddings find the entry, the graph expands.

1. Embed the question, KNN for the top ~20 chunks. Entry points by meaning.
2. Take those chunks' `graph_node_id` values as the traversal start set, in
   place of the substring match, then expand and return the subgraph as today.
3. Answer from the union, citing chunk-level line ranges.

It preserves community detection, the traversal, and the `EXTRACTED` /
`INFERRED` / `AMBIGUOUS` audit trail on every edge, which is the property that
made the graph worth choosing over a pure vector store in the first place.

**Be honest about the cost of step 2.** `graphify query` takes a natural-language
question string and has no flag to seed traversal from explicit node ids
(verified against 0.9.32). The commands that expand from a node you already know
are `graphify explain "<label>"`, `graphify path "A" "B"`, and `graphify affected
"X"`. So Option A is either a small fork, a patched entry point, or a
reimplementation of the traversal against `graph.json` directly, which is a
readable file and not hard to walk. It is not free, and any estimate that calls
it a one-function change is wrong.

**Option B, the fallback.** Run graph traversal and vector search independently
and fuse the resulting file lists with RRF. Easier to build, because it needs no
chunk-to-node mapping at all, which makes it the live fallback if Option A's
mapping turns out to be more work than the fork is worth. The cost is duplicated
work and two result sets with no shared ranking basis. Decide between A and B
when the mapping is attempted, not before, and do not discover B for the first
time at that moment.

**Option C, rejected.** Embeddings replace the graph for retrieval, and the
graph is kept only for relationship questions. Cleaner conceptually, and it
discards the audit trail on the retrieval path, which is too high a price. An
opaque similarity score cannot tell you whether a connection was stated in a
source or invented by a model. `GOVERNANCE.md` already asserts the same thing
from the other direction: the graph is derived, lossy, and partly inferred, so
when an answer needs to be right you follow `source_file` back to the raw
capture.

## Schema

Normalized into `files` and `chunks`, not one flat table. The reason is not
tidiness, it is the deletion rule: `git rm` is the deletion API, and a foreign
key with `ON DELETE CASCADE` is what makes removing one file row take its chunks
and vectors with it. A flat table makes orphan rows possible, and an orphan row
in a derived store is drift.

```sql
CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT
);  -- model, dim, indexer_version, built_at

-- one row per source markdown file
CREATE TABLE files (
  id            INTEGER PRIMARY KEY,
  wiki          TEXT NOT NULL,   -- 'research' or 'packages/<name>/research'
  path          TEXT NOT NULL,   -- relative to the GRAPH's project root, see below
  content_sha256 TEXT NOT NULL,  -- file-level, cheap change and deletion detection
  mtime         REAL NOT NULL,
  provenance    TEXT NOT NULL,   -- 'raw' | 'synthesis', derived from the path
  doc_date      TEXT,            -- frontmatter date:, for recency ranking
  status        TEXT,            -- frontmatter status:, e.g. 'superseded'
  indexed_at    TEXT NOT NULL,
  UNIQUE(wiki, path)
);

-- one row per chunk
CREATE TABLE chunks (
  id            INTEGER PRIMARY KEY,
  file_id       INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  ordinal       INTEGER NOT NULL,  -- position within the file
  heading_path  TEXT,              -- 'Section 8 > 8.3 Entity resolution'
  line_start    INTEGER,
  line_end      INTEGER,
  token_count   INTEGER NOT NULL,
  content_sha256 TEXT NOT NULL,    -- chunk-level, so one edited section re-embeds one section
  graph_node_id TEXT,              -- nullable join back to graph.json node id
  text          TEXT NOT NULL
);

CREATE VIRTUAL TABLE chunks_vec USING vec0(
  chunk_id     INTEGER PRIMARY KEY,
  embedding    FLOAT[768],
  provenance   TEXT PARTITION KEY   -- lets a query stay inside one layer
);

CREATE VIRTUAL TABLE chunks_fts USING fts5(
  text, content='chunks', content_rowid='id'
);

-- The cascade above does NOT reach either virtual table. See below.
CREATE TRIGGER chunks_ad AFTER DELETE ON chunks BEGIN
  INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.id, old.text);
  DELETE FROM chunks_vec WHERE chunk_id = old.id;
END;
```

**Two hashes, not one.** `files.content_sha256` answers "did this file change,
and does it still exist," which is what makes deletion detection and the
skip-unchanged path cheap. `chunks.content_sha256` answers "which sections of
the changed file actually differ," which is what keeps a one-paragraph edit in a
forty-section document from re-embedding all forty. File-level alone is
wasteful, chunk-level alone cannot detect a deleted file. Both is correct.

**The cascade does not reach the virtual tables, and this is the trap.**
`ON DELETE CASCADE` propagates only to ordinary tables that declare the foreign
key. `chunks_fts` is an external-content FTS5 table, which by design does not
observe changes to its content table and requires an explicit `'delete'` command.
`chunks_vec` is a `vec0` virtual table with no foreign key to anything. So a
`git rm` would cascade `files` to `chunks` and stop, leaving the lexical index
and the vectors full of orphans that still match queries. The trigger above is
what actually honors the deletion rule. Note that the FTS5 delete command needs
the *old* text, which is why it fires on `AFTER DELETE` with `old.text` in hand.

**`PRAGMA foreign_keys = ON` per connection**, or SQLite ignores the cascade
entirely and every deletion silently orphans its chunks. This is off by default
and is the single easiest way to get this schema wrong.

### About `path`, and why the join is harder than it looks

`files.path` has to match graphify's `source_file` or the join returns nothing,
silently, looking exactly like "the graph had no hits." Two things make that
harder than string equality.

First, graphify's `source_file` is relative to the **graph's project root**, not
to the monorepo root. A graph built for a wiki at `packages/<name>/research/`
emits `research/<topic>/<file>.md`, relative to `packages/<name>/`. A
repo-relative key would never match it.

Second, it is not internally consistent. Nodes from the AST pass carry bare
filenames (`crawl.py`) while nodes from the semantic pass carry project-relative
paths. Any mapping has to normalize both sides and tolerate misses.

So populate `graph_node_id` by normalizing both to project-root-relative, then
picking the node whose span best covers the chunk. Leave it null when nothing
matches and never guess. And do not expect a file-level join to substitute: the
live graph has 361 nodes over 34 distinct source files, averaging about 10 nodes
per file and peaking at 40 for a single document. Mapping 20 chunks to files and
files to nodes yields hundreds of start nodes, which throws away exactly the
precision the embeddings just bought.

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

Split on `##` and `###` boundaries. Merge any section under roughly 200 tokens
into its neighbor, split any section over roughly 1000 tokens at paragraph
boundaries, and target roughly 800 tokens with about 15% overlap. Carry the full
heading path into the embedded text (`# Topic > ## Section\n\n<body>`), because a
heading is usually the only place the subject of a section is named and the body
pronouns back to it. "Section 5.3" means nothing standalone.

Preserve frontmatter `date`, `status`, and `title` as retrievable metadata. A
chunk from a file marked `status: superseded` stays retrievable but ranks down:
superseded is a statement about currency, not about wrongness, and the old
reading is often exactly what someone is looking for.

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

Incremental by content hash: walk the wiki, compare file hashes to skip
unchanged files entirely, then within changed files embed only the chunk hashes
not already present. A no-op run over an unchanged wiki should touch zero
vectors and finish in well under a second, because that is what makes it safe to
call from a timer.

### The deletion sweep must be scoped to the path you walked

This is the one correctness rule to get right before writing any code, because
the failure is silent and destructive.

"Delete rows whose source file is gone" is correct only if the sweep is
restricted to rows under the root just walked. Run `wiki-embed.sh research/`
and then `wiki-embed.sh research/retrieval`, and a naive reading of that
sentence deletes every chunk outside `research/retrieval`, because from the
second run's point of view those files were not found and must have been
removed.

This exact bug, in the graph rather than the index, dropped the parent graph
from 90 nodes to 37 on 2026-05-07 on the other machine. Detection was run once
per scope path, and each pass concluded that everything outside its own path had
been deleted. The fix there was to union the scope paths before comparing
against the manifest, with a manifest entry counting as deleted only if it lives
inside a walked path and is missing from disk.

So: a row is deleted only if its `path` is under the walked root **and** the
file is gone. Rows outside the walked root are never touched, no matter what the
walk did or did not find.

### Scheduling

`scripts/routines/wiki-embed-daily.sh` runs it under launchd at 03:45, half an
hour after the graph rebuild, because populating `graph_node_id` needs a current
graph. `install.sh` in the same directory manages both jobs.

A PostToolUse hook firing on every wiki write was considered and rejected: it
puts a model load on the critical path of a file save, and the index being a few
hours stale has never cost anything.

### Freshness should be a commit, not a timestamp

Store the repo HEAD in `meta` at build time rather than a wall-clock instant.
graphify 0.9.32 already does this, writing `built_at_commit` into `graph.json`,
and it is strictly better than an mtime: mtime changes on copy, restore, and
rsync, and it forces a date comparison against `log.md` entries to work out what
the index has not seen. A commit SHA turns the freshness gap into an exact
question with an exact answer, `git diff <built_at_commit>..HEAD -- research/`,
which returns the precise file list to read directly.

Use the same value for both derived stores. Two stores with two independent
staleness boundaries is a retrieval bug waiting to happen.

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
- **No agent ever writes to the database.** Only the indexer inserts. An agent
  that wants to remember something writes a markdown file under `research/` and
  lets the next reindex pick it up. This is the rule most likely to break
  silently: someone adds a helpful "remember this" tool that inserts a chunk
  with no markdown behind it, everything works, and then the next full rebuild
  deletes it without a word, because a full rebuild is defined as reproducing
  the markdown exactly.
- **A superseded chunk stays retrievable and ranks down.** It does not get
  removed. Supersession is a statement about which reading is current, not about
  what the evidence said, and the older reading is often exactly what someone is
  looking for. Without the `status` column the retired conclusion ranks
  identically to the current one, which defeats the whole supersession
  discipline.
- **Scope files, if they ever arrive.** There are none in this repo today. If
  `.graphify-scope` is ever adopted, the indexer has to read it too, or graphify
  indexes a subset while the indexer indexes everything and the two silently
  disagree about what the corpus is.
- **The database is gitignored.** Add `*.wiki-index.db*` (and the `-wal` and
  `-shm` siblings) to `.gitignore`. It is a build artifact and it would carry
  client material from package wikis into a public repo, which is the exact
  failure mode that just cost this repo a file move.
- **Package wikis stay in their package.** One database per wiki root, written
  next to the wiki it indexes. Do not build a single cross-tier index in the
  parent, because `packages/*/` is gitignored for confidentiality reasons and a
  merged index would launder that boundary away.

## The eval gate comes first, and it is not optional

This is the biggest correction the handoff brief forced on this plan. The
recorded decision (ADR-0026) is that the retrieval eval harness runs **before
and after** any retrieval change, and that gate exists precisely so nobody can
ship a retrieval change and then argue about whether it helped.

Two things make this sharper than a normal "write tests" instruction.

First, **expand the question set before implementing, not after.** The last
recorded run on the other machine was 12 questions, 11 answerable, with a file
hit rate of 1.0. A perfect score has no headroom: you cannot demonstrate an
improvement against it. The questions to add are specifically the
paraphrase-heavy ones the current lexical matcher is known to fail, since those
are the ones embeddings are supposed to fix. Writing them first is what stops
them from being written to flatter the implementation.

Second, **neither the harness nor a baseline exists in this checkout.** So the
honest order of work is: port or rebuild the harness, expand the questions,
record a baseline, then build the indexer. `scripts/routines/wiki-embed-daily.sh`
is already scheduled and deliberately no-ops until then.

## Rollout

Each phase is independently useful and independently abandonable.

| Phase | Deliverable | Done when |
|---|---|---|
| 0 | Retrieval eval harness plus a paraphrase-heavy question set | A recorded baseline score with real headroom, not 11/12 |
| 1 | Decide the model, confirm extension loading works on this machine | `sqlite_vec.load()` succeeds and returns a version string |
| 2 | Chunker only, no embeddings, dump chunks to JSON | Boundaries look right by eye on a long document with deep headings |
| 3 | `wiki-embed.sh` build path, `files` + `chunks` + `chunks_vec` populated | Cold build of all 5 wikis well under a minute |
| 4 | `--query`, plain KNN | Beats the recorded baseline on the paraphrase questions |
| 5 | FTS5 + RRF hybrid (k=60) | Beats either leg alone, and does not regress the exact-identifier questions |
| 6 | `graph_node_id` populated, `wiki-query` using KNN for its BFS start set | Delta reported per question, not just in aggregate |

Two proofs are acceptance criteria in their own right, because they are what
keep the derived store from drifting away from the markdown:

- **The deletion proof.** `git rm` a research file, run the reindex, confirm zero
  remaining rows for that path in `files`, `chunks`, `chunks_fts`, and
  `chunks_vec`.
- **The rebuild proof.** Delete the database entirely, reindex from markdown,
  confirm identical retrieval results. As long as `rm -f *.wiki-index.db &&
  wiki-embed --rebuild` fully restores the index, drift cannot accumulate. Drift
  is not prevented by careful design, it is prevented by making the markdown
  side cheap to regenerate everything from.

## Sizing, measured rather than guessed

Run `./scripts/routines/wiki-embed-daily.sh --status` for current numbers. As of
2026-08-11 on this machine, after excluding `log.md` and the cloned upstream
repos under `repositories/`:

**46 markdown files, ~126,000 words, roughly 320 chunks across 5 wikis.**

That is two orders of magnitude smaller than the machine the handoff brief
describes (1,178 files, 1.78M words, roughly 4,000 chunks). Both are trivially
small for brute-force search. At 320 chunks a cosine scan is microseconds, and
at 4,000 it is still under 10ms. The conclusion holds across both: **do not
over-engineer the index.** No ANN structure, no tuning, no recall loss. If this
workspace ever grows to the other one's size, nothing here needs to change.

Embedding cost is not a design constraint either. At roughly $0.02 per million
tokens for a small hosted model, a full cold reindex of the larger corpus is
under ten cents. The real constraints are cold-rebuild wall clock and the
operational burden of keeping the thing fresh, which is why the routine is
incremental by content hash and why it is scheduled rather than hooked.

## Open questions

1. **Ollama or MLX for the local model.** Ollama is less code and one more daemon.
   MLX is more code and matches how transcription already works here. The handoff
   brief leans local-by-default with a hosted opt-in flag, for the same reason
   the SQLite path beat the hosted-vector-DB path in the first place: killing the
   external dependency was the whole point.
2. **Vector dimension follows from that choice** and is baked into the `vec0`
   table. This plan sketches `FLOAT[768]` for a local model. A hosted OpenAI
   small model would be `FLOAT[1536]`. Pick the model first, then the schema.
3. **Does this ship in the public boilerplate?** The plan and scripts, yes. It is
   the kind of thing the repo exists to demonstrate. The databases never do.
4. **One database per wiki, or one per tier?** This plan assumes per wiki, on
   confidentiality grounds, and today's incident where Artium material reached a
   public repo is the argument for physical separation over a column. The handoff
   brief instead assumes one index with a `shareability` column sourced from each
   package's `AGENTS.md` marker, which is what makes its cross-package search
   possible. These are genuinely in tension: physical separation is safer, a
   single index is more capable. **This one needs your decision**, and the honest
   framing is whether "ask one question across all projects" is a thing you
   actually want enough to defend a filter as the only boundary.
5. **The provenance axis is new and the brief does not have it.** The brief
   predates the raw/synthesis split that shipped here today, so its schema has
   `shareability` but no `provenance`. Those are different axes and both matter:
   one governs who may see a chunk, the other governs whether a chunk is evidence
   or inference. Keep both.
6. **Does this ever index code?** This plan is wiki-only. The recorded revisit
   trigger in ADR-0025 for reaching for a vector store at all was semantic search
   over *code*, and the brief lists onboarding to any `packages/*/app/` tree as
   grep-and-pray. If code is in scope it wants its own database and its own
   chunker, because AST-aware code chunking has almost nothing in common with
   markdown-heading chunking.

## Deferred, deliberately

Two of the three gaps the brief identifies are not addressed here, and should be
recorded as deferred rather than quietly dropped.

**Cross-package semantic search.** Unsolvable under one-index-per-wiki, since
two packages discussing the same concept in different vocabulary can only be
connected by something that sees both. This is the substance of open question 4.
There is a middle path neither document proposes: apply the shape the brief uses
for graph federation, where the merged artifact holds metadata about where
knowledge lives rather than the knowledge itself. A cross-wiki index carrying
only headings, entity labels, paths, and their vectors, never chunk bodies,
would route a question to the right wiki without ever co-locating client prose.

**Auto-resolving the federation review queue.** The narrowest and cheapest win
of the three, and not actionable here because no federation layer exists in this
checkout. When it is, note the trap the brief documents: the pair "weekly infra
brief 2026 05 14" versus "weekly infra brief 2026 05 25" sits at 0.93 string
similarity and is semantically near-identical while being two genuinely distinct
documents. Embedding similarity would make that pair *worse*, not better, so any
auto-merge rule has to special-case date-bearing labels.

## This should become an ADR

`GOVERNANCE.md` says big architectural calls get a short ADR in `decisions/`.
Choosing a storage engine, an embedding model, and a composition architecture is
a big architectural call, and on the other machine four ADRs constrain this same
decision. Once open questions 1 and 4 are answered, this document should be
distilled into `decisions/0002-semantic-search-over-the-wiki.md`, with this plan
kept as the working detail behind it.
