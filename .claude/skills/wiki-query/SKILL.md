---
name: wiki-query
description: Answer a research question against the knowledge graph and wiki. Graphify-first when a graph exists, index + freshness fallback otherwise. Optionally files the answer back as a new wiki entry only when the user explicitly says save it.
---

# Wiki Query Skill

## Description

Answer a research question against a Karpathy-style three-layer wiki
(`research/index.md` + topic subdirs + `research/log.md`), using the
graphify knowledge graph as the primary retrieval layer when one exists.

The retrieval pipeline is always:

1. **Graphify-first.** Query the knowledge graph for the most relevant
   nodes and their cross-document edges. Graphify finds connections the
   index never captures — concepts that appear across multiple files
   without any human linking them.
2. **Freshness gap.** Check `research/log.md` for files ingested after
   the graph's last build. Read those directly — they aren't in the graph yet.
3. **Index for structure.** Read `research/index.md` (and any sub-index
   the question maps to) to understand human-curated hierarchy and
   spot any files graphify didn't score highly but the index calls canonical.
4. **Read the sources.** Open the files the graph and index identified.
   Graphify gives you a prioritized reading list; the index gives you
   structural context and freshness coverage.
5. **Synthesize with citations.**

This is the third skill in the wiki triad:
- `wiki-ingest` — inbound, adds new sources to the wiki
- `wiki-lint` — periodic, audits the wiki for orphans
- `wiki-query` — outbound, answers questions from the wiki

## Triggers

- "what do we know about X"
- "what does the research say about X"
- "query the wiki for X"
- "ask the wiki X"
- "wiki-query"
- Any research question answerable from existing `research/` content

## Scope detection

Works in both the parent workspace and any child project. The wiki is the
one rooted at the closest `research/` directory:

1. If `./research/index.md` exists, query that wiki.
2. Else walk upward until a `research/index.md` is found.
3. Else stop and tell the user there is no wiki here; suggest `wiki-reconcile`.

## Workflow

### Step 0 — Graphify-first (mandatory when graph exists)

```bash
ls graphify-out/graph.json 2>/dev/null && echo "graph_present" || echo "no_graph"
```

**If graph is present:**

```bash
graphify query "QUESTION" --budget 1500
```

Replace QUESTION with the user's exact question. This runs a BFS traversal
of the graph and returns the most relevant nodes with their source file paths
and community context.

Also read the build timestamp:

```bash
python3 -c "import os; from pathlib import Path; p=Path('graphify-out/graph.json'); print(p.stat().st_mtime if p.exists() else '')" 2>/dev/null
```

Record the `built_at` timestamp. This defines the freshness boundary.

The graphify output is your **primary reading list**: the `src=` fields on
each returned node tell you which files to read. Read those files in Step 2.

**If no graph exists:** skip to Step 1. Flag at end of answer: "No graphify
graph for this research tree — run `/graphify research/` to build one."

### Step 1 — Freshness gap

Read the last 50 lines of `research/log.md`:

```bash
tail -50 research/log.md
```

Any entry dated **after** the `built_at` timestamp from Step 0 represents
a file graphify hasn't seen yet. Add those files to your read list. If no
graph exists, read the full `log.md` and use it (together with `index.md`)
to route to raw files.

### Step 2 — Index for structure

Read `research/index.md`. You are reading it for two reasons:

1. To check if the human-curated index calls a specific file canonical for
   this topic that graphify didn't score highly. If the index points at
   something graphify missed, add it to the read list.
2. If the question maps to a topic with its own sub-index
   (`research/<topic>/index.md`), read that too.

Do NOT use the index as your primary file router when a graph exists —
graphify already did that. Use it to catch what graphify missed.

If there is no graph, the index is your primary router: identify relevant
topics, follow the links to raw files, do not grep the corpus.

### Step 3 — Read the sources

Read the files identified by graphify + freshness gap + index review.
Do not skim — read completely for substantive answers.

Freshness-gap files take priority over graph-identified files if they are
newer and address the same topic. Newer wins.

If a file is marked superseded in `log.md`, note it but still read it for
context; state in the answer that it has been superseded.

### Step 4 — Synthesize the answer

Rules:

- **Cite every factual claim** with a relative path like
  `research/<topic>/2026-03-15-source.md`. No claim without a citation.
- **Surface contradictions** between sources rather than picking one.
  If two sources disagree, say so and cite both. Trust the newer date.
- **Mark uncertainty.** If the wiki only has weak evidence for a claim,
  say "the wiki has limited evidence for this."
- **Note gaps.** If the question has no matching content, say so plainly.
  Offer to `web-ingest` a new source or run `wiki-ingest` on a document.
- **Do not invent.** No padding with general knowledge dressed up as a
  wiki finding.
- **Note cross-document edges.** If graphify found a node that connects
  two topics the index doesn't link (e.g. a competitor analysis file that
  shares entities with a brand-architecture file), call that out. That's
  the cross-document discovery graphify adds that pure index reading misses.

### Step 5 — Offer to file back, do not file back automatically

After presenting the answer, ask:

> Save this as a wiki entry under `research/answers/`? yes/no

Only if the user says yes, proceed to Step 6.

### Step 6 — File the answer back (only on explicit yes)

Write to `research/answers/<YYYY-MM-DD>-<slug>.md`:

- Frontmatter: `question`, `asked_at`, `sources_cited` (list of paths),
  `graph_used` (true/false), `graph_built_at` (timestamp or null)
- Body: the synthesized answer with citations preserved
- Footer: "Sources consulted" listing every file read

Update `research/index.md` under `## Answered questions` (create the
section if absent): `- [<question>](answers/<file>.md)`

The `research-log-append.sh` PostToolUse hook will append to `log.md`
automatically. Verify the entry; if the hook didn't fire, append manually.

## What this skill does NOT do

- Does not search the web. Use `wiki-ingest` on a new URL then re-query.
- Does not modify raw sources. They are immutable evidence.
- Does not auto-file answers. Manual file-back only.
- Does not run `wiki-lint`. Surface orphan/gap findings but don't fix them.

## Failure modes to avoid

- **Skipping graphify when graph.json exists.** Graphify-first is not
  optional. The whole point is reducing token cost and surfacing
  cross-document connections the index doesn't have.
- **Using graphify output as the answer.** Graphify returns nodes and
  pointers — read the actual source files. The node labels are summaries,
  not quotable evidence.
- **Grepping raw sources before reading graphify + index.** This defeats
  the layered architecture and wastes tokens.
- **Filing back without explicit yes.** Silence means no.
- **Citing the index as evidence.** The index is a map. Cite the source file.

## Example invocation

```
User: what do we know about Karpathy's wiki pattern in the marketing research?
```

0. `graphify query "Karpathy wiki pattern marketing research" --budget 1500`
   → returns nodes: "Karpathy Three-Layer Pattern", "wiki-ingest skill",
     "marketing/index.md", src files from research/
   Note built_at: 2026-05-04T02:00:00Z
1. `tail -50 research/log.md` → no entries after 2026-05-04T02:00:00Z, no freshness gap
2. Read `research/index.md` → confirms "marketing" sub-wiki pointer; no
   canonical file graphify missed
3. Read `research/marketing/index.md` and the graphify-flagged source file
4. Synthesize: "The wiki has one direct source on Karpathy's three-layer
   pattern: raw sources / curated index / append-only log. The graphify
   graph found a cross-document edge connecting it to the `wiki-ingest`
   skill's SKILL.md, which references the same pattern — the index doesn't
   capture this link."
5. Offer to save.

## Related

- `.claude/skills/wiki-ingest/SKILL.md` — sibling, inbound side
- `.claude/skills/wiki-lint/SKILL.md` — sibling, audit side
- `.claude/skills/wiki-reconcile/SKILL.md` — bootstrap when no wiki exists
- `.claude/agents/research-professor.md` — agent wrapper that calls this
  skill for substantive cross-project synthesis
- `.claude/hooks/research-log-append.sh` — PostToolUse hook for log.md
- `~/.claude/skills/graphify/SKILL.md` — builds and queries the graph
