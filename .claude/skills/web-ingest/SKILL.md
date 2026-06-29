---
name: web-ingest
description: Fetch a URL, extract its content, and file it into the research wiki via wiki-ingest. Handles paywalled previews, JavaScript-heavy pages, and multi-page threads. Wraps WebFetch + wiki-ingest with routing judgment.
---

# Web Ingest Skill

## Description

Fetch a URL and file it into the right wiki as a dated, immutable research artifact. This is the URL-first counterpart to `document-ingest` (which handles file uploads, PDFs, pasted text). The two skills share the same output contract — both produce a dated source file + log.md entry + index.md update.

Trigger: user pastes a URL and says "ingest this", "save this article", "add this to research", or hands you a URL alongside a topic.

## What this wraps

| Source type | Approach |
|---|---|
| Standard article / blog / Substack | WebFetch direct |
| Thread (Twitter/X, HN, Reddit) | WebFetch thread URL; concatenate top-N comments if multi-page |
| Paywalled or JS-heavy page | WebFetch reader-mode fallback; note partial if extraction is thin |
| YouTube video page | Redirect to youtube-research skill |
| PDF linked from a URL | Redirect to document-ingest (PDF skill handles extraction) |
| Raw GitHub file | WebFetch raw.githubusercontent.com URL |

## Inputs

Required:
- `url` — the URL to fetch

Optional:
- `topic` — where in research/ to file it (e.g. `agent-economy`, `infra`, `marketing`). If omitted, infer from URL domain + content.
- `project` — file into `packages/<project>/research/` instead of parent research/. If omitted, file into parent wiki.
- `note` — one-line context note to prepend to the frontmatter (e.g. "Cited by infra-improver 2026-05-04").

## Workflow

### Step 1 — Fetch

Use `WebFetch` on the URL. If the result is thin (<200 words) or appears to be a JavaScript placeholder:
- Try appending `?format=text` or the /print or /amp variant if the domain supports it.
- Note in the frontmatter: `extraction: partial`.
- Never silently file a thin artifact as if it were complete.

For thread URLs (Twitter, HN, Reddit):
- Fetch the main URL.
- Extract the original post/article plus top 3-5 comments/replies that add signal.
- Discard low-signal replies.

### Step 2 — Determine topic and project

If `topic` was not passed:
1. Scan the URL domain and page title for topic signals (e.g. `github.com/...claude...` → `ai-infra`; `substack.com` about marketing → `marketing`).
2. Read `research/index.md` topic list to find the closest match.
3. If no close match exists, file under `research/external/` with a note suggesting a new topic.

If `project` was not passed:
- Default to parent wiki (`research/`).
- Use a project wiki only when the content is clearly scoped to one project's domain (e.g. a competitor analysis for one project (`packages/project-alpha/research/`)).

### Step 3 — Call wiki-ingest

Invoke the `wiki-ingest` skill with:
- `source_type`: `web`
- `source_url`: the original URL
- `content`: the extracted text
- `topic`: determined in Step 2
- `project`: determined in Step 2
- `note`: pass through if provided, else generate a one-liner from the page title + date

Wiki-ingest handles the dated filename, frontmatter, log.md append, and index.md update. Do not replicate that logic here.

### Step 4 — Return ingest output contract

Return the same output shape as wiki-ingest and document-ingest:

```
Ingested: <title or URL>
Filed at: research/<topic>/<YYYY-MM-DD>-<slug>.md
Topic: <topic>
Log entry: appended
Index updated: yes | no (gap flagged)
Extraction: complete | partial (note why)
```

If extraction was partial, also flag: "Consider re-ingesting when a better source is available."

## Failure modes

- **Fetch returns 403/401:** tell the user the URL is access-controlled. Suggest they paste the text directly and use `document-ingest` instead.
- **PDF redirect:** tell the user "This URL points to a PDF — routing to document-ingest." Then call document-ingest.
- **YouTube URL:** tell the user "This is a YouTube URL — routing to youtube-research." Then call that skill.
- **Content is thin (<200 words) after fallback attempts:** file with `extraction: partial` and surface the issue. Do not pretend the artifact is complete.
- **No matching topic in index.md:** file to `research/external/` and flag the new topic for the user to add to the index.

## What this skill does NOT do

- Does not scrape login-walled pages. For those, the user must paste the content.
- Does not generate analysis or synthesis. It files the raw source. Synthesis is wiki-query's job.
- Does not post to Notion. If the user wants a Notion mirror, they can pass the result to `notion-publisher`.
- Does not update the graphify graph. The daily graphify scheduled task picks up new wiki files automatically.

## Related

- `wiki-ingest` — the downstream skill that handles dated filing + log + index
- `document-ingest` — handles file uploads, PDFs, pasted text, same output contract
- `wiki-query` — queries the wiki, including files added by web-ingest
- `youtube-research` — specialized skill for YouTube content
- `news-research` — web search + analysis (discovery mode, vs. web-ingest's single-URL capture mode)
