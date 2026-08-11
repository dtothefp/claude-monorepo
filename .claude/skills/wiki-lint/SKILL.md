# Wiki Lint Skill

## Description

Read-only health check across all child project wikis (and the parent's
own `research/`). Reports drift between the raw evidence layer and the
curated `index.md` summaries, surfaces stale ADRs, and flags topic
summaries that have outgrown the "few paragraphs" guideline. Output is
delivered as a structured digest via your Slack connector, or written to a dated file if you do not use Slack.

This is the audit counterpart to `wiki-reconcile`. Reconcile mutates
(scaffolds files, backfills `log.md`, rewrites `index.md`). Lint never
writes to a wiki — it only reports. Run lint weekly to catch drift;
run reconcile manually when lint says a project needs cleanup.

## Triggers

- "wiki lint"
- "audit all wikis"
- "lint research directories"
- "wiki health check"
- "weekly wiki audit"

## Workflow

### Step 1: Discover wikis

Build a list of `research/` directories to audit:

1. The parent workspace's own `project-tracker-parent/research/`.
2. Every child project under `packages/*/research/` whose parent has
   a `CLAUDE.md` (skip the `.gitkeep` and any directory without a
   `CLAUDE.md`).

If a project has no `research/` directory at all, that is itself a
finding ("no wiki layer"). Record it but do not skip the project.

### Step 2: Per wiki, run the checks

For each `research/` root, gather:

#### 2a. Files unreferenced from any index.md

Walk the tree and collect every `*.md` and `*.txt` file (excluding
`index.md`, `log.md`, dotfiles, anything under `.git/` or
`.obsidian/`). For each file, grep across all `index.md` files in the
wiki for the file's relative path or basename.

A file is **unreferenced** if no `index.md` mentions it. Report the
list grouped by topic directory.

#### 2b. context/ files never ingested

For the same project, list everything in `context/` (recursive).
Cross-reference against `research/log.md`: if `log.md` does not
mention the basename, the file has not been ingested.

This is a soft signal — `context/` is allowed to hold raw imports
that are not research. Report the list as "candidates for
`wiki-ingest`" rather than as errors.

#### 2c. Stale ADRs (decisions/ vs research/)

For each ADR file in `decisions/`, extract the entities it mentions
(simple noun-phrase / proper-noun grep). Then look for any file in
`research/` newer than the ADR that mentions the same entity.

If a newer research file shares ≥2 distinct entities with an ADR,
flag the ADR as "potentially superseded — verify against
[research file]". This is a heuristic, not a verdict; the digest
should make that clear.

#### 2d. Oversized index.md summaries

Read each `index.md`. If any single topic section exceeds ~600 words
(rough proxy for "a few paragraphs"), flag it: `topic should be
split into a sub-topic with its own index.md`.

Skip the file's own intro / "What lives here" sections — only count
topic sections.

#### 2d-bis. Provenance split violations

The raw/synthesis split (GOVERNANCE.md, wiki-ingest Step 5) rots
silently if nothing checks it, because a broken pair still reads fine.
Four checks, in descending severity:

**Orphan synthesis (error).** For each `*.md` outside a `ref/` directory,
read its frontmatter. If `sources:` is missing or empty, flag it. Skip
files that are structure rather than research: `index.md`, `log.md`,
`CLAUDE.md`, `AGENTS.md`, `README.md`. Those describe the wiki rather
than making claims about the world, so they have nothing to cite. This means a model wrote something with no
evidence behind it, which is the exact failure the split exists to
prevent. Report as `no sources: <path>`.

**Dangling reference (error).** For each path listed in a synthesis
file's `sources:`, check the file exists. Flag any that do not resolve.
Report as `sources: points at missing <path>`.

**Orphan raw (warning).** For each file under a `ref/` directory, grep
every synthesis file's `sources:` for its path. If nothing cites it, the
evidence landed but no one read it. Report as `uncited ref`. This is a
weaker signal than the other three, since a deliberate raw-only capture
is legitimate.

**Suspected model prose in `ref/` (warning, heuristic).** Read the first
40 lines of each `ref/` file. Flag it if the `Source:` / `Link:` /
`Retrieved:` header is missing entirely, or if the body contains
headings like `## Summary`, `## Key takeaways`, `## Analysis`, or
`## What this means`. These are synthesis section names and should never
appear in a raw capture. Say explicitly in the digest that this one is a
heuristic and needs a human to confirm, since a source document can
legitimately contain its own summary section.

**Uncaptured external sources (warning).** For each synthesis file, check whether
any entry in `sources:` is a bare external URL or a description of a live system
(a Slack channel, an MCP call, "screenshots") rather than a path to a local
`ref/` file. Flag those as `cited but never captured`. This is the signature of
research that was delegated to a subagent told not to write files, and it means
the claim cannot be re-verified from the repo. Report the count per wiki, since
one is a judgement call and a dozen is a process failure.

Also check frontmatter key discipline while reading: `source` (singular)
belongs only on `ref/` files, `sources` (plural list) only on synthesis
files. Flag files carrying the wrong one, or both, as `frontmatter key
mismatch`.

#### 2e. Missing wiki bookkeeping

If `research/index.md` or `research/log.md` is missing, flag it and
recommend running `wiki-reconcile` for that project. Do not scaffold
them — that's reconcile's job.

#### 2f. Topic dirs with no index.md

For each `research/<topic>/` subdirectory, check whether it has its
own `index.md`. If a topic has more than ~3 files and no sub-index,
flag it as "needs sub-index".

### Step 3: Compose the digest

Build a markdown digest with one section per wiki. Order projects
with findings first, clean wikis last (or omit clean ones if the
digest would otherwise be too long).

Format:

```markdown
# Wiki Lint — YYYY-MM-DD

Summary: N wikis audited, M with findings.

## <project-name>

**Findings: N**

### Provenance split (N errors, M warnings)
- ERROR `research/<topic>/file.md`: no `sources:`, nothing backs this
- ERROR `research/<topic>/other.md`: `sources:` points at missing `ref/gone.md`
- WARN `research/<topic>/ref/thing.md`: uncited by any synthesis
- WARN `research/<topic>/ref/thing.md`: has `## Summary`, possible model prose (heuristic, verify by hand)
- WARN `research/<topic>/file.md`: has `source:`, synthesis files take `sources:`

### Unreferenced files (N)
- `research/<topic>/file.md` — last modified YYYY-MM-DD

### context/ candidates for ingest (N)
- `context/<file>` — never ingested

### Potentially superseded ADRs (N)
- `decisions/<adr>.md` — see `research/<file>.md` (newer, 3 shared entities)

### Oversized index.md sections (N)
- `research/<topic>/index.md` — "Topic Name" section is ~820 words

### Structural issues
- Missing `research/log.md`
- `research/marketing/` has 7 files but no `index.md`

---

## <next-project>

_All clean._
```

### Step 4: Deliver via Slack

Send the digest as a Slack DM to yourself using your Slack MCP connector or a CLI wrapper. Drop this step if you do not use Slack.

Cap the Slack message at 4000 chars. If it would exceed that:
1. Send a top-line summary (counts per project) inline.
2. Save the full digest to a temp file under
   `research/wiki-lint-YYYY-MM-DD.md` and note its path in the
   Slack message.

If there are zero findings across all wikis, send a single-line
"all clean" message rather than a full digest.

### Step 5: Summary

Print to the terminal:
- Number of wikis audited
- Number with findings
- Number of findings by category
- Confirmation the Slack DM was sent

Do not write to any `index.md`, `log.md`, or `research/` file (other
than the spillover digest in Step 4 if the message overflows). Lint
is read-only by contract. Mutations are reconcile's job.

## Notes

- This skill is the natural input for the `wiki-lint-weekly` cron
  in `~/.claude/scheduled-tasks/wiki-lint-weekly/`.
- Findings are advisory. Lint never auto-fixes. The user reviews the
  digest and runs `wiki-reconcile` or `wiki-ingest` as needed.
- Heuristics (stale ADR detection, oversized sections) will produce
  false positives. The digest should always say "verify" rather than
  "broken" for heuristic findings.
- If Slack delivery is not configured or
  fails, fall back to writing the digest to
  `research/wiki-lint-YYYY-MM-DD.md` and printing the path. Never
  silently drop the digest.
- Lint should be cheap — single pass through each `research/` tree,
  no LLM calls per file. Aim for the whole audit to finish in well
  under a minute even with 15+ child projects.
