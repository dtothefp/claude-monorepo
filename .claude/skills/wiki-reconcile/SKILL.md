# Wiki Reconcile Skill

## Description

Reconciles a `research/` directory against the Karpathy wiki pattern (raw
sources / curated `index.md` / append-only `log.md`). Scaffolds missing
wiki files, backfills `log.md` entries for files the auto-append hook
never saw, and prompts the user to update topic conclusions in `index.md`
when new material has shifted the picture.

Use this whenever a `research/` tree drifts from the wiki pattern: brand
new child project that was created before the hook landed, a research
directory that received bulk imports, or any time the user wants a fresh
audit of the wiki layer.

## Triggers

- "reconcile the wiki"
- "wiki reconcile"
- "backfill research log"
- "audit research directory"
- "set up the wiki layer for this project"
- "fix the research index"

## Inputs

- **Target directory**: a path to a `research/` directory. If not given,
  ask the user. In the parent workspace, default to
  `project-tracker-parent/research/`. In a child project, default to
  `<project>/research/`.

## Workflow

### Step 1: Locate the research root

If the user passed a path inside `research/` (e.g. `research/marketing/`),
walk up to the nearest `research/` ancestor and treat that as the root.
The reconcile always operates on the top-level `research/` for that
project, not on a sub-topic, because `index.md` and `log.md` live at
the root.

### Step 2: Scaffold missing wiki files

If `index.md` is missing, create it from this template:

```markdown
# Research Wiki

Curated entry point for this project's research. Each topic below links
to the canonical page or sub-index for that area. Add a new bullet
whenever a new topic lands and prune or rewrite topic summaries when
the underlying research shifts.

## Topics

<!-- one bullet per topic, e.g. -->
<!-- - **Topic name** ([link](path)) — one-line conclusion -->

---

For the chronological journal of changes, see [log.md](log.md).
```

If `log.md` is missing, create it from this template (matches the hook's
scaffold so the two stay in sync):

```markdown
# Research Log

Append-only chronological record of additions and updates to this
research wiki. One line per entry. Newest at the top.

Format: `YYYY-MM-DD: <change> ([link](path))`

---

```

### Step 3: Inventory the research tree

Walk the research root and collect every `*.md` file (and any other
content files like `.txt`, `.pdf`) excluding:
- `index.md`
- `log.md`
- dotfiles
- anything under a `.git/` or `.obsidian/` path

For each file, capture: relative path, basename, last-modified date,
and (for markdown) the first H1 or frontmatter `title` if present.

### Step 4: Backfill log.md

Read the existing `log.md`. For each file from Step 3, check whether
its relative path is mentioned anywhere in `log.md`. If not, it is a
backfill candidate.

For backfill candidates:
1. Group them by topic directory (e.g. `marketing/`, top-level, etc.)
2. Show the user the list of missing entries grouped by topic, with
   inferred dates (file mtime in `YYYY-MM-DD` form)
3. Ask: "Backfill these entries with their mtime dates, or pick a
   different date for a batch?"
4. Insert the entries into `log.md` immediately after the `---`
   separator, newest at the top, using the same format as the hook:
   `- YYYY-MM-DD: Added [`<rel_path>`](<rel_path>)`

If the same file already has any entry on any date in `log.md`, skip
it. The hook handles future updates; reconcile only fills gaps.

### Step 5: Reconcile index.md

Read `index.md` and parse the existing topics list. Compare against
the topic directories discovered in Step 3.

For each topic directory under `research/` (one level deep, e.g.
`research/marketing/`, `research/launch/`, etc.):

1. Check whether the topic has a bullet in `index.md`'s Topics section.
2. If missing, draft a one-line conclusion based on the files in that
   directory (read its own sub-index if one exists, otherwise read the
   first one or two files to infer the topic) and propose adding it.
3. If present, list the files that have changed or been added since
   the topic conclusion was last written (use git log on `index.md`
   to find when the topic line was last touched, then compare against
   file mtimes in that subdirectory). Ask the user whether the topic
   summary needs rewriting.

For loose files at the top of `research/` (not under a topic
subdirectory), ask the user whether they belong to an existing topic,
deserve a new topic, or should be left as ungrouped reference material.

### Step 6: Show the diff and confirm

Before writing changes to `index.md`, show the proposed diff (added
bullets, rewritten conclusions) and ask for confirmation. Write
`log.md` changes directly without prompting since they are append-only
and reversible.

### Step 7: Summary

Print a short summary:
- Files scaffolded (`index.md` / `log.md` if created)
- Number of `log.md` entries backfilled
- Number of `index.md` topics added or rewritten
- Any files left ungrouped that need human judgment

Do not commit. The user runs vault-sync or commits manually.

## Notes

- Reconcile is idempotent: running it twice in a row should be a no-op
  on the second run.
- Reconcile never deletes anything from `log.md`. The append-only
  invariant is sacred.
- Reconcile may rewrite topic conclusions in `index.md`. That is the
  whole point: `index.md` is the LLM-curated layer and is meant to
  drift as the underlying research evolves.
- This skill is the manual counterpart to the
  `.claude/hooks/research-log-append.sh` PostToolUse hook. The hook
  handles the steady state (every Write/Edit appends a log entry); the
  skill handles bulk backfill and the parts the hook can't do (topic
  curation in `index.md`).
