---
title: Retrieval architecture, graphify and semantic search over the wiki
sources: [retrieval/ref/graphify-sqlite-embeddings-handoff-2026-08-11.md]
sources_note: >
  The raw capture is held on disk but gitignored. It is a handoff brief that
  enumerates private projects by name, and this wiki is public. The capture is
  verbatim and unedited (raw files are never edited to make them publishable),
  so the whole file stays local and only this reading ships. Everything below is
  written to stand on its own without it.
ingested: 2026-08-11
topics: [retrieval, graphify, semantic-search, embeddings, sqlite-vec]
type: synthesis
---

# Graphify and semantic search: how this workspace finds things in its own wiki

## Summary

This workspace has two retrieval layers, one built and one designed. Graphify
turns a folder of research into a knowledge graph with community detection and a
per-edge record of whether a relationship was stated in a source or inferred by
a model. A semantic search layer over the same corpus, embeddings stored in
SQLite, is planned and not built.

The central finding is that **the graph is not the weak part of retrieval, the
doorway into it is.** Graph traversal is excellent once you are standing at the
right node. Choosing that node is currently a keyword lottery, because
`graphify query` picks its starting nodes by lowercasing the question, keeping
terms longer than three characters, and counting how many appear as substrings
of each node label. No stemming, no synonyms, no similarity. Ask "how do we keep
the wiki from drifting" and nothing matches a node labelled "source-of-truth
rule", so the query returns nothing and the caller falls back to reading the
index by hand.

That reframes what embeddings are for here. They are not a second retrieval
system competing with the graph. They are a replacement for one specific broken
component, the entry-point finder, and everything downstream of it stays as is.

This reading rests on two independent designs for the same layer, one written
from model recall with no sources and one carrying real decision history, plus
direct verification against the tooling installed here. Where two independent
derivations landed on the same answer, that is noted, because independent
convergence is the strongest available evidence a technical choice is sound.

## What both designs agreed on, independently

The two were written without contact. Where they agree, it is not two readings
of one document, it is two derivations from the same constraints reaching the
same point.

They converged on the substantive technical choices. Both land on `sqlite-vec`
rather than `sqlite-vss`, and for the same reason: the older library is
superseded by the same author's successor, which drops the Faiss dependency and
ships as a single portable C extension. Both reject a served vector database at
this corpus size in favor of a file on disk. Both specify hybrid retrieval,
running lexical BM25 through FTS5 alongside dense vector search and fusing with
reciprocal rank fusion, on the reasoning that dense-only search regresses badly
on exact identifiers, filenames, and proper nouns, which is a large share of how
questions actually get asked against a wiki. Both insist the embedding model
name and dimension are stored in the database and that a mismatch refuses to
query rather than silently mixing vector spaces, which is the failure mode that
degrades quality without ever raising an error. Both prefer a scheduled rebuild
over a file-write hook. Both conclude that brute-force search is correct here and
that building an approximate index would add tuning and recall loss to buy back
nothing.

Independent convergence on that many parameters is reasonable evidence the
shape is right.

## What decision history settles that guesswork missed

Four things the local plan simply did not have.

**The schema needs to be normalized, because deletion is the hard part.** The
local plan had one flat table of chunks. The prior design splits `files` from `chunks`
with a foreign key and `ON DELETE CASCADE`, and that is not a tidiness
preference. The governing rule is that `git rm` is the deletion API: if removing
a markdown file does not eventually remove its rows in the derived store, the
architecture is wrong. A cascade makes that automatic. A flat table makes orphan
rows possible, and an orphan row in a derived store is drift by definition.

**Chunks should carry a join key back to graph node ids, and a file-level join
will not substitute.** This is the single most consequential omission, and the
one graph that exists here quantifies why. It holds 361 nodes drawn from only 34
distinct source files, averaging about ten nodes per file and peaking at forty
for one document. Graphify nodes are entities, not files. So mapping twenty
chunks to their files and those files to nodes yields hundreds of candidate
start nodes, when the traversal wants three. A file-level join is a fan-out, not
a join, and it discards exactly the precision the embeddings just bought.

The path key is also messier than it looks. Graphify's `source_file` is relative
to the graph's own project root rather than the repo root, so a repo-relative
key never matches and fails as an empty result rather than an error. And it is
not internally consistent: nodes from the AST pass carry bare filenames like
`crawl.py` while nodes from the semantic pass carry project-relative paths, so
any mapping has to normalize both sides and tolerate misses.

Get that column right and the composition follows: vector search picks the entry
nodes, the existing traversal runs unchanged, and the per-edge audit trail
survives on the retrieval path. Two alternatives were weighed and both lose.
Running the two retrievers independently and fusing their file lists needs no
chunk-to-node mapping at all, which makes it the honest fallback if the mapping
proves expensive, but it duplicates work and the two result sets share no
ranking basis. Letting embeddings replace the graph outright discards the audit
trail, which was the explicit reason for choosing a graph over a vector store to
begin with.

One caveat that both designs understate: `graphify query` takes a
natural-language string and has no flag for seeding traversal from known node
ids. So this is a fork, a patched entry point, or a reimplementation of the
traversal against `graph.json`, which is a readable file and not hard to walk.
Calling it a one-function change is wrong.

**An eval harness is a gate, not a nicety.** The recorded decision is that the
retrieval eval runs before and after any retrieval change. The subtle part is
the instruction to expand the question set first: the last recorded run scored
11 of 12 with a perfect file hit rate, which has no headroom to demonstrate an
improvement, and the questions to add are the paraphrase-heavy ones the lexical
matcher is known to fail. Writing them before implementing is what stops them
from being written to flatter the implementation. Neither the harness nor a
baseline exists in this checkout, which means the honest order of work puts
measurement before the indexer.

**Three regressions are documented with their causes.** Every graphify build must
run with the working directory inside the project that owns the graph, because
graphify resolves its output directory from the detected project root and
building a package graph from the parent root overwrites the parent's. First
extractions stay manual, because they are expensive and can trip a corpus-size
warning that needs a human answer. And incremental detection must never be run
once per scope path, because each per-path call sees every file outside its own
path as deleted and the merge step then prunes those nodes. That last one cost
53 of 90 nodes in the parent graph on 2026-05-07.

## Where the prior design is stale, verified against the installed tooling

The prior design states that the graphify binary does only cheap deterministic
operations, that there is no update flag on it, and that the full extraction
pipeline requires an agent harness to orchestrate parallel subagents. It names
version 0.3.15.

That version number is still pinned in this repo's skill directory, but the
installed binary is **0.9.32**, which is six minor versions ahead and has a
different surface. It now exposes `extract` for headless AST plus semantic
extraction with a selectable backend, along with `update`, `check-update`
(described in its own help as cron-safe), `cluster-only`, `label`, `affected`,
`god-nodes`, `merge-graphs`, a global cross-repo graph, and `reflect`. Headless
automation is available at this version, which is what makes a daily local
routine viable without an agent session in the loop.

Two smaller corrections. It locates the graphify skill at a machine-global
path; here it is repo-local at 1,300 lines. And the scope-file convention it
documents is a workspace-local invention implemented by their own scripts, not a
graphify feature: 0.9.32 reads `.graphifyignore` and `.gitignore` and has no
knowledge of `.graphify-scope`.

Several capabilities the prior design describes as bespoke local scripts now ship in
the CLI. The query feedback loop it documents as a skill-internal Python call is
`graphify save-result` and `graphify reflect`. The cron-safe detection probe is
`graphify check-update`. A cross-graph merge exists as `graphify merge-graphs`,
though pointedly not the same design, since it produces one merged graph, which
the brief's own federation section rejects and which this repo forbids on
confidentiality grounds. Anyone reimplementing from that tooling section
would rebuild a meaningful fraction of what already ships.

One rule from the prior design does still hold, and it caught a real defect. Its
instruction to load `graph.json` with `edges='links'` reflects that clustered
output stores edges under `links` while raw extraction uses `edges`, and reading
the wrong key yields an empty result with no error. The summary block of
`scripts/graph-refresh.sh`, written before this brief was ingested, read only
`edges` and therefore reported zero edges on every graph it built. Fixed by
reading `links` with an `edges` fallback, which immediately surfaced the audit
trail the summary was supposed to show: 486 EXTRACTED, 67 INFERRED, 1 AMBIGUOUS.

The prior design is behind on one point in the other direction. It insists that
`built_at` is the filesystem mtime of `graph.json` and not a field inside it. At
0.9.32 there is now such a field, `built_at_commit`, carrying the repo HEAD at
build time. That is strictly better than an mtime, which changes on copy,
restore, and rsync, and which forces a date comparison against the log. A commit
SHA turns the freshness gap into an exact `git diff` returning the precise list
of files the graph has not seen.

## Where this workspace is ahead of the prior design

The prior design describes a three-layer wiki: raw sources in topic directories, a
curated index, an append-only log. It has no concept of a `ref/` directory,
because the raw/synthesis split shipped here after it was written. Its schema
carries a `shareability` column distinguishing client-shared from internal
material, but nothing that distinguishes evidence from inference.

Those are different axes and a search index needs both. Shareability governs who
may see a chunk. Provenance governs whether a chunk can be quoted as something a
source said or only as something this workspace previously concluded. Flattening
them into "documents" destroys the boundary at exactly the moment it matters,
which is when an agent is assembling an answer and deciding what it is allowed
to assert.

## Sizing, measured here rather than assumed

Excluding `log.md` as bookkeeping and the cloned upstream repos under
`repositories/`, this workspace holds **46 markdown files, roughly 126,000 words,
about 320 chunks across 5 wikis**. The larger corpus it describes holds 1,178 files and 1.78
million words, roughly 4,000 chunks.

Both are small. A brute-force cosine scan over 320 vectors is microseconds and
over 4,000 is still under ten milliseconds. Embedding cost for a full cold
reindex of the larger corpus is under ten cents at current small-model pricing.
Neither cost nor scale is a design constraint. Cold-rebuild wall clock and the
operational burden of staying fresh are the real ones, which is the argument for
incremental content-hash detection and a scheduled rebuild.

## The open decision

The prior design assumes one index spanning every package, with a `shareability` column
as the boundary, and that assumption is load-bearing for its cross-package
search ambition. This workspace instead builds one index per wiki, written next
to the wiki it indexes, on the grounds that `packages/*/` is gitignored for
confidentiality reasons and a merged index would launder that boundary away.

These are genuinely in tension. Physical separation is safer, a single index is
more capable, and today's incident in which Artium material reached a public
repository is evidence for the safer reading. The question that has to be
answered before the schema is fixed is whether asking one question across all
projects is wanted enough to accept a query filter as the only thing standing
between client material and a public artifact.

The raw capture behind this reading is held locally and not committed, for the
reason given in `sources_note` above.
