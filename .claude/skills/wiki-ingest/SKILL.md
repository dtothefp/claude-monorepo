# Wiki Ingest Skill

## Description

Structured workflow for adding a new source (URL, file, pasted text) to a
`research/` wiki. Fetches or reads the source, lands it as an immutable
dated raw file under the right topic subdirectory, updates the relevant
`index.md` summaries with a cross-reference, and lets the
`research-log-append.sh` PostToolUse hook record the change in `log.md`
automatically.

This is the inbound counterpart to `wiki-reconcile`. Reconcile audits an
existing tree and backfills gaps; ingest is what you run *as* a new source
arrives so the wiki stays in shape without needing reconciliation later.

## Triggers

- "ingest this URL into research"
- "add this source to the wiki"
- "drop this article into research"
- "wiki ingest"
- "save this for the research wiki"
- User pastes a URL or file path with intent to capture it as research

## Inputs

One of:
- **URL** — fetched via WebFetch
- **File path** — read locally (e.g. a PDF transcript already downloaded
  into `context/`)
- **Pasted text** — used directly

Optional:
- **Target project** — if not specified, infer from cwd. The skill works
  in both the parent workspace and any child project.
- **Topic hint** — if the user names the topic, use it; otherwise infer
  from existing `research/<topic>/` directories or propose a new one.

## Workflow

### Step 1: Locate the research root

Determine which `research/` directory to write into:

1. If the user passed a path inside a project, walk up to the project
   root and use `<project>/research/`.
2. Otherwise use the cwd's nearest `research/` ancestor.
3. If no `research/` directory exists in the current project, ask the
   user to confirm the target before creating one. Do not silently
   scaffold a wiki in the wrong place.

### Step 2: Fetch or read the source

- **URL**: WebFetch the page. Capture title, author, publish date if
  visible, and the main body content.
- **File path**: Read the file. If it is a PDF, use the PDF skill or
  extract text via the appropriate tool.
- **Pasted text**: Use as-is. Ask the user for a title and source
  attribution if not obvious.

If the fetch fails, stop and report the error. Do not write a stub.

### Step 3: Summarize and extract

Produce:
- A one-paragraph summary (2-4 sentences) of the source's main claim
  or finding.
- A list of topics + entities mentioned (people, products, concepts,
  child projects this is relevant to).
- A proposed topic slug for the file's home directory.

### Step 4: Choose the topic directory

1. List existing `research/<topic>/` subdirectories.
2. Match the proposed topic against existing ones (case-insensitive,
   substring + semantic match).
3. If a clear match exists, use it.
4. If no match, propose a new topic slug to the user and confirm
   before creating the directory.
5. Loose top-level files (no topic) are allowed but discouraged. If
   the source is genuinely cross-topic, ask the user where it belongs.

### Step 5: Write the raw source as an immutable dated file

Filename format: `YYYY-MM-DD-<slug>.md`

- Date is today's date (use the current date, not the source's publish
  date — the date in the filename means "ingested on").
- Slug is a short kebab-case description, 3-6 words, derived from the
  title.
- If the same slug already exists for today, append `-2`, `-3`, etc.

File contents (markdown):

```markdown
---
title: <source title>
source: <url or original file path>
ingested: YYYY-MM-DD
author: <if known>
published: <if known>
topics: [topic1, topic2]
---

# <source title>

**Source:** <url>
**Ingested:** YYYY-MM-DD

## Summary

<one-paragraph summary from Step 3>

## Full content

<the fetched body, lightly cleaned of nav chrome>
```

The Karpathy rule: this file is immutable evidence. Never edit it
later to "fix" it. If the source is updated, ingest a new dated file
and mark the old one superseded in the wiki (Step 7).

### Step 6: Update the topic index.md

Read `research/<topic>/index.md` if it exists; if not, scaffold one
using the same template `wiki-reconcile` uses. Then:

1. Add a bullet under the topic's "Sources" or "Files" section linking
   to the new file with a one-line description.
2. If this source shifts the topic's overall conclusion, update the
   topic summary paragraph at the top of the index. Show the diff to
   the user and confirm before writing.
3. If the topic is brand new, also add a bullet to the *parent*
   `research/index.md` pointing at the new topic's index.

### Step 7: Handle supersession (if applicable)

If the user signals that this new source replaces an older one (or you
detect it: same title, same author, more recent), do not delete or
edit the old file. Instead:

1. Add a `**Superseded by:** [link](path)` line to the *top* of the
   old file, just under the H1.
2. Update the topic index to point at the new file as the canonical
   source, and demote the old one to a "Historical" or "Superseded"
   subsection.

### Step 8: Let the hook record the log entry

The `research-log-append.sh` PostToolUse hook fires automatically when
files under `research/` are written. It will append a `Updated`
entry to `log.md` for the new file. Verify this happened — read
`log.md` after writing and confirm the new entry is there. If the hook
did not fire (different cwd, missing hook, etc.), append manually
using the format:

```
- YYYY-MM-DD: Ingested [`<rel_path>`](<rel_path>)
```

### Step 9: Summary

Print a short summary:
- Path of the new raw file
- Topic it landed in
- Whether `index.md` was updated (and at which level: topic + parent)
- Whether anything was superseded
- Confirmation that `log.md` got the entry

Do not commit. The user runs vault-sync or commits manually.

## Notes

- Ingest is the steady-state inbound flow. Reconcile is the bulk
  cleanup pass. They share conventions but never the same trigger.
- Ingest never touches files outside the target project's `research/`
  tree. If the user wants the same source in two projects, run ingest
  twice with different project targets.
- The hook's de-dupe is by `path + date`, so a single ingest of a new
  file produces exactly one log entry. Multiple edits to the same file
  on the same day collapse to one entry, which is the intended
  behavior.
- For very long sources (full books, multi-hour transcripts), ask the
  user whether to store the full content inline or save it to
  `context/` and link from the research file. Default to inline up to
  ~50KB of markdown, link out beyond that.
- If the fetched content looks like it came from a paywalled or
  bot-blocked page (truncated, login wall text, very short), flag this
  to the user before writing the file. Better to fail loud than to
  ingest a junk capture.
