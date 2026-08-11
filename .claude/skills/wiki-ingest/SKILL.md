# Wiki Ingest Skill

## Description

Structured workflow for adding a new source (URL, file, pasted text) to a
`research/` wiki. Fetches or reads the source, lands it as a pair of
immutable dated files under the right topic subdirectory (the raw capture
in `ref/`, the model-authored synthesis alongside it), updates the
relevant `index.md` summaries with a cross-reference, and lets the
`research-log-append.sh` PostToolUse hook record the change in `log.md`
automatically.

The raw/synthesis split is the core discipline here: `ref/` holds only
what the source said, everything outside `ref/` is model-authored, and
the boundary is a property of the path rather than a heading inside a
file. See Step 5.

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

Every ingest writes **two files**, not one: the raw capture and the
synthesis. They share a filename and differ only by directory.

```
research/<topic>/
├── index.md
├── YYYY-MM-DD-<slug>.md          <- synthesis. LLM-authored. Cites the ref.
└── ref/
    └── YYYY-MM-DD-<slug>.md      <- raw capture. NEVER LLM-authored.
```

**Why two files.** A single file mixing a model's summary with the
fetched body is only one careless edit away from losing the boundary,
and a later agent summarizing that file cannot tell which sentences are
evidence and which are inference. Splitting them makes provenance a
property of the path, which survives editing, grep, and re-ingestion.

#### 5a. The raw file: `research/<topic>/ref/<YYYY-MM-DD>-<slug>.md`

This is the immutable evidence layer. It holds **only** what the source
actually said. No summary, no interpretation, no restructuring of the
argument.

```markdown
---
title: <source title>
source: <url or original file path>
author: <if known, else omit the key>
published: <source's own publish date, if known, else omit>
ingested: YYYY-MM-DD
type: raw
---

Source: <human-readable description of where this came from>
Link: <url or path>
Retrieved: YYYY-MM-DD

<the fetched body, verbatim>
```

Rules for `ref/` files, in priority order:

1. **Never LLM-authored.** The body is a copy, not a rendering. Cleaning
   nav chrome, ads, and cookie banners out of fetched HTML is allowed.
   Rewording, condensing, reordering, or "fixing" the source is not.
2. If structural markup had to be normalized (a Notion export flattened
   to plain markdown, a PDF's columns linearized), say so in a short note
   under the `Retrieved:` line, and say that wording is unchanged.
3. Immutable. Never edit later to "fix" it. If the source is updated,
   ingest a new dated file and supersede the old one (Step 7).

#### 5b. The synthesis file: `research/<topic>/<YYYY-MM-DD>-<slug>.md`

This is the layer the retrieval agents read first. It is explicitly
model-authored and must cite the raw file it came from.

```markdown
---
title: <source title>
sources: [<topic>/ref/<YYYY-MM-DD>-<slug>.md]
ingested: YYYY-MM-DD
topics: [topic1, topic2]
type: synthesis
---

# <source title>

## Summary

<one-paragraph summary from Step 3>

## Notes

<the useful detail, in your own words, with the source's own claims
attributed. Quote sparingly and only when the exact wording matters.>

See [ref/<YYYY-MM-DD>-<slug>.md](ref/<YYYY-MM-DD>-<slug>.md) for the
full source.
```

If a synthesis draws on more than one raw file, list every one of them
in `sources:`. A synthesis with an empty or missing `sources:` list is a
lint error, because it means a model wrote something with no evidence
behind it.

#### 5c. Delegated research: the subagent rule

The split fails silently the moment research is handed to a subagent, because
the subagent is the only thing that ever touches the primary sources. If it
returns a report and nothing else, the evidence is destroyed at the point of
contact and no later step can recover it. The synthesis looks complete, cites
plausible URLs, and is unreproducible.

**Never instruct a research subagent to avoid writing files when it will fetch
primary sources.** "Do not write any files, return the report as your final
message" is the exact instruction that causes this. It feels like good context
hygiene and it is evidence destruction.

Any subagent that fetches primary sources MUST:

1. Write each source it actually reads to the appropriate `ref/` directory as it
   goes, verbatim, with the `Source:` / `Link:` / `Retrieved:` header. One file
   per source document. Not one file per research topic.
2. Return **both** its synthesis and the list of `ref/` paths it wrote.
3. Treat its own report as synthesis. A subagent's summary is model-authored by
   definition and never belongs in `ref/`, no matter how faithful it is.

The calling agent then writes synthesis citing those `ref/` paths, exactly as if
it had fetched the sources itself.

**One file per source document is the load-bearing part.** It is what forces
exhaustive enumeration. A note about a financial trend across four quarters
cannot be written from one summarized "financial picture" capture; it requires
four earnings releases sitting in `ref/` as four files. The discipline surfaces
the trend as a byproduct of following it. A single blended capture hides exactly
the thing you were looking for.

**When a source cannot be captured**, say so in `sources_note` and treat it as a
gap to close rather than a normal outcome. Legitimate cases: material behind a
paywall, an ephemeral UI, a recording with no transcript. Not legitimate: the
agent had the source and did not save it.

#### The frontmatter schema

Key names follow Obsidian Web Clipper's vocabulary where one exists, so
clipped and agent-ingested material share a spelling. There is no formal
standard for provenance frontmatter; this is the closest thing to a
widely-deployed convention.

| Key | Where | Meaning |
|---|---|---|
| `title` | both | Human-readable title. Always present. |
| `source` | ref only | **Singular.** The one origin: a URL or original file path. |
| `sources` | synthesis only | **Plural, a list.** Paths of the `ref/` files this synthesis rests on. |
| `ingested` | both | Date this landed in the wiki. Not the source's publish date. |
| `type` | both | `raw` in `ref/`, `synthesis` outside it. |
| `author` | ref, optional | The source's author. |
| `published` | ref, optional | The source's own publish date. |
| `topics` | synthesis, optional | Topic slugs for cross-referencing. |
| `confidentiality` | both, optional | Free text. Required for client material. |

`source` versus `sources` is a meaning distinction, not a style choice:
a raw capture has exactly one origin, a synthesis can rest on several.
Do not use them interchangeably. Agent-specific keys (`attendees`,
`meeting_date`, `duration`) are fine to add on top.

### Step 6: Update the topic index.md

Read `research/<topic>/index.md` if it exists; if not, scaffold one
using the same template `wiki-reconcile` uses. Then:

1. Add a bullet under the topic's "Sources" or "Files" section linking
   to the new **synthesis** file with a one-line description. The index
   never links to `ref/` directly; readers reach the raw capture through
   the synthesis that cites it.
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
   old **synthesis** file, just under the H1.
2. Update the topic index to point at the new file as the canonical
   source, and demote the old one to a "Historical" or "Superseded"
   subsection.

The old `ref/` file is left completely untouched. Superseding is a
statement about which reading is current, not about what the evidence
said, and the raw layer never acquires editorial annotations.

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
- Path of the new synthesis file and its `ref/` counterpart
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
  user whether to store the full content in `ref/` or leave it in
  `context/` and point `source:` at it. Default to inline in `ref/` up
  to ~50KB of markdown, link out beyond that. A `ref/` file that links
  out instead of holding the body still needs its `Source:` / `Link:` /
  `Retrieved:` header, so the provenance trail stays complete.
- Both files are written in the same run. An ingest that produces a
  synthesis with no `ref/` counterpart is incomplete, not a shortcut.
  The one exception is a source that is already a raw file in the tree
  (re-synthesizing an existing capture), in which case point `sources:`
  at the existing `ref/` path and write no new raw file.
- If the fetched content looks like it came from a paywalled or
  bot-blocked page (truncated, login wall text, very short), flag this
  to the user before writing the file. Better to fail loud than to
  ingest a junk capture.
