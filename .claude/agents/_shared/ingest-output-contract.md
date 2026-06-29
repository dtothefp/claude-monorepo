# Ingest Agent Output Contract

This is the **shared output contract** every ingest agent (`social-ingest`, `personal-ingest`, `document-ingest`) must conform to. Like a class interface — different implementations, same shape on the wire.

## Why this exists

Without a shared contract, ingest agents diverge: one returns a synthesis, another dumps file paths, a third writes a spec. The user reads the agent's reply, not the markdown files it produced. Inconsistent reply shape means the user has to re-learn the agent's habits each time. This contract eliminates that.

The find agents (`research-professor`, `workspace-cartographer`, `project-status-scout`) each have their own output shape baked into their prompt. The ingest category gets one shared shape because the on-screen deliverable is always the same: a synthesis the user can read in 30 seconds + a footer of where the artifacts landed.

## The contract

Every ingest agent's reply MUST follow this shape:

```
<1-4 paragraphs of synthesis prose. The deliverable. Flowing natural language,
no bold-labeled fact blocks, no inline file paths, no `:line` references.
This is what the user reads. The user does NOT read the markdown files this
agent produced. ~250-500 words. Cap at 600. If the synthesis can't fit, the
agent is being asked to summarize too many sources at once — split into
multiple ingest runs, not a longer reply.>

---
Captured:
- <relative/path/to/source-of-truth-file.md> — <one-line description>
- <relative/path/to/asset-folder/> — <one-line description if assets exist>
- <relative/path/to/log-or-index-update> — <which file, what changed>

Notion:
- <Page Title> → <https://notion.so/...>

Suggested next:
- <one-line action — usually a TODO.md candidate>
- <up to 3 total>
```

## What goes in the synthesis

- **Lead with the most important finding**, not with what you did. The user knows you scraped/transcribed/ingested — that's why they invoked you.
- **Synthesize, don't relay.** Pick the most notable points and write them as prose. Do not mirror the source's structure or section headings.
- **Cite sparingly inline** if a quoted fact really needs attribution. Most paths belong in the Captured footer, not the prose.
- **No path lists masquerading as content.** "I created [foo.md](foo.md), [bar.md](bar.md), and [baz.md](baz.md)" is not a synthesis. That's the Captured footer.
- **Tensions and contradictions are valuable.** If the new material conflicts with existing wiki conclusions, name that explicitly. The find agents value this; ingest agents should too.

## What goes in Captured

- The **dated source-of-truth file** (always — every ingest produces at least one immutable dated file under `research/<topic>/` or a project's `research/`)
- The **asset folder** if media was downloaded (videos, images, audio clips). One bullet per folder, not per file.
- Any **`log.md` / `index.md` updates** that happened (one bullet per update)
- Any **memory pointer** drafted (path + memory file name)

## What goes in Notion

Always exactly one bullet. Either:
- `<Page Title> → <URL>` — the human-readable mirror that `notion-publisher` created, OR
- `Skipped — <reason>` — if the user opted out of Notion mirroring, or the project has no Notion config

## What goes in Suggested next

- 1-4 actions max. Empty section is fine if there's no obvious follow-up.
- Frame as TODO candidates: imperative verbs, each item is something a future session could pick up.
- Examples: "Schedule outreach to creator X for creator-led promo" or "Spin off a deeper decode of the top reel via reel-format-breakdown."

### Suggested next must be DISTINCT from action items already auto-routed

The two categories must not overlap. Before composing Suggested next, the agent MUST scan the action items already routed to TODO in earlier steps and remove any candidate suggestion that matches one of them. Categorize cleanly:

- **Action items** — anything the source material itself stated, implied, or asked. Includes user-stated commitments, open questions raised in the source, decisions the source flagged as pending. These auto-route to TODO `## Inbox` because the source provided them.
- **Suggested next** — the agent's *own additional* recommendations. Things the source didn't raise but the agent judges would help, given context across the wider project. Examples: "promote this transcript into a positioning doc once a precursor lands," "this conflicts with the existing X memo — reconcile," "consider scheduling a follow-up scrape of related creator Y."

If a candidate item is already in the action-items list, it is NOT a Suggested next. Period. Re-surfacing it produces duplicate TODO entries on the prompt. The agent must dedupe before composing Suggested next.

Test for whether a candidate belongs in Suggested next: "did the source itself say this, OR did I (the agent) come up with it from cross-context judgment?" If the source said it, it's an action item. If the agent originated it, it's a Suggested next.

### Suggested next must be prompt-routed to TODO, not just displayed

Action items extracted from the source material auto-route to the project's `TODO.md` `## Inbox` (high confidence — the user already committed to them or the source explicitly raised them). **Suggested next items are different**: they're agent-generated recommendations and need user approval before persisting. Display-only wastes the suggestion (it gets re-derived in some future session). Auto-routing pollutes TODO with agent noise.

The middle path: at the end of every ingest run with a non-empty Suggested next list, fire `AskUserQuestion` with `multiSelect: true`, listing each suggestion as a checkbox option with all options checked by default. The user clicks once to accept all, or unchecks the noise. Selected items get appended to the same TODO.md `## Inbox` the action items landed in (or `## Backlog` for projects without an Inbox section).

Skip the prompt entirely if Suggested next is empty.

Prompt template:

```
question: "Add these suggestions to <project>/TODO.md?"
header: "Add suggestions?"
multiSelect: true
options:
  - label: "<suggestion 1, ≤60 chars>"
    description: "<full text of suggestion 1, with file path or context>"
  - label: "<suggestion 2, ≤60 chars>"
    description: "<full text of suggestion 2>"
  - <up to 4 total>
```

The user gets an "Other" auto-option to add a custom item; if they use it, append the custom text as a new TODO entry too.

After the prompt resolves, append the selected items as TODO bullets in the same shape the project's TODO.md uses, with the source attribution `from <agent-name> <YYYY-MM-DD>: <one-line context>`. Then proceed to the on-screen reply, where the Suggested next footer shows the items that were added (with a "(added to TODO)" tag) and the items that were dismissed (without the tag).

## Forbidden behaviors

Every ingest agent's `Do not` section MUST include these:

- Do not return a list of file paths as the answer. Synthesis is the deliverable; paths go in Captured.
- Do not write the synthesis as bold-labeled fact blocks pulled from sources.
- Do not exceed ~500 words in the on-screen synthesis. If it can't fit, the ingest scope was too broad — split it.
- Do not skip the Notion mirror. Call `notion-publisher` before reporting done. If skipping is the right call, say so explicitly in Notion: footer.
- Do not duplicate the source-of-truth markdown content into the on-screen reply. The user has the file path; the reply is the synthesis ABOUT it.
- Do not invent file paths. Every path in Captured must exist.

## The standard storage recipe

In addition to the on-screen contract, every ingest agent writes the same shape on disk. **The file-write step is `wiki-ingest`'s discipline** — every ingest agent must conform to it rather than reinventing.

The canonical reference is [`.claude/skills/wiki-ingest/SKILL.md`](../../skills/wiki-ingest/SKILL.md). Specifically:

- **File path + naming** (its Step 5): `research/<topic>/<YYYY-MM-DD>-<slug>.md`. Date is the ingest date, NOT the source's publish date. Slug is kebab-case 3-6 words.
- **Frontmatter shape** (its Step 5): `title`, `source`, `ingested`, optional `author` / `published` / `topics`. Plus any agent-specific fields (e.g. `attendees` for personal-ingest, `deep_decoded_reels` for social-ingest).
- **Immutability** (its rule throughout): the raw source file is never edited later. If the source updates, ingest a new dated file and mark the old one with `**Superseded by:** <link>` (its Step 7).
- **Log hook** (its Step 8): the `research-log-append.sh` PostToolUse hook auto-fires when files under `research/` are written. Verify after writing; only manually append if the hook didn't fire.
- **Topic index update** (its Step 6): only when the new source shifts a conclusion. Adding to a topic's "Sources" list is fine without a conclusion change.

Ingest agents don't bypass `wiki-ingest`; they either invoke it as a skill (the simplest path, used by `document-ingest`) or follow its discipline directly when they need to add their own structured fields (`social-ingest`, `personal-ingest`). Either way, the file shape on disk is identical regardless of which ingest agent produced it.

Beyond the file write itself:

1. **Source-of-truth file** — per wiki-ingest discipline above.
2. **Asset folder** (if media was captured) — `research/<topic>/<YYYY-MM-DD>-<slug>/` next to the source-of-truth file. wiki-ingest does not handle this; the calling agent does.
3. **`log.md` append** — handled by hook + verification per wiki-ingest Step 8.
4. **`index.md` update** — per wiki-ingest Step 6.
5. **Memory pointer** (optional). Draft a `feedback_*.md` only if the agent surfaces a generalizable rule (not project-specific). Pointer points at the source-of-truth file, and the rule itself stays short. wiki-ingest does not handle this; the calling agent does.
6. **Notion mirror** — call `notion-publisher` agent with the source-of-truth path + project hint. The publisher reads the project's `context/notion-databases.json`, picks the right parent page, converts markdown to blocks, and creates the page. wiki-ingest does not handle this; the calling agent delegates to `notion-publisher`.

## Notion-publisher integration

Every ingest agent ends its pipeline with a delegation:

```
After writing the source-of-truth file and updating log/index, call the
notion-publisher agent with:
- source_path: absolute path to the dated markdown file
- project: the project slug (or "parent" for parent-workspace research)
- title: the human-readable Notion page title
- summary: the same synthesis you put in the on-screen reply (notion-publisher
  uses this as the page's first block so the Notion reader gets the same
  takeaway without scrolling)
```

`notion-publisher` returns a Notion URL or a `Skipped — <reason>` string. That value goes directly into the Notion: section of the on-screen reply.

## When to skip parts of the recipe

- **No Notion mirror**: only when the project has no `context/notion-databases.json` AND no obvious parent Notion page. `notion-publisher` reports this as `Skipped — no notion config for <project>` and the ingest agent surfaces that string. Do not fail the run.
- **No memory pointer**: default. Only draft one when the rule is genuinely generalizable across projects.
- **No `index.md` update**: default. Only update if the new material changes a conclusion.

## Reference

- Source-of-truth file format: see [`.claude/skills/wiki-ingest/SKILL.md`](../../skills/wiki-ingest/SKILL.md) Step 5.
- Per-project Notion config shape: `packages/<project>/context/notion-databases.json` (see any project with Notion configured for a populated example).
- Synthesis discipline reference: [`research-professor.md`](../research-professor.md) Output shape section. The ingest contract inherits its "synthesis is the deliverable, paths are footer" rule.
