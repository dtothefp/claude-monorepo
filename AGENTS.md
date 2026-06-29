# Claude Monorepo: Parent Workspace

> `CLAUDE.md` and `GEMINI.md` at this repo root are symlinks to this file. Always edit `AGENTS.md` directly. The symlinks resolve to it so Claude Code, Cursor, Codex CLI, and Gemini CLI all read identical rules.

This is a boilerplate. A parent workspace that gives any AI coding agent (Claude Code, Codex, Cursor, Gemini CLI) one consistent memory across every project you work on, plus a ready-made research, ingestion, and discovery pipeline. Clone it, strip the example projects, and make it yours.

## What this workspace is

A parent repo that sits above all your projects. It holds the high-level rules for how you work, a shared research wiki, and a set of skills and agents for pulling the outside world in (URLs, PDFs, voice notes, social, newsletters) and querying it back out. The projects themselves live in `packages/`, each as its own independent git repo.

Three tiers:

1. **Parent** (this repo). Cross-project rules, task tracking, the shared research wiki. Lightweight.
2. **Packages** (`packages/<name>/`). One repo per project, with its own `AGENTS.md`. Gitignored from the parent so each stays independent.
3. **Apps** (`packages/<name>/app/`). The deployable web app inside a project. Its own repo, its own deploy.

To add a project:

```bash
cd packages/
git clone <repo-url> <name>
```

`packages/*/` is gitignored at the parent level, so every child repo stays on its own remote. The parent only tracks its own files.

## The research and discovery pipeline (the point of this repo)

The reason this boilerplate exists. A consistent way to bring the outside world into a local knowledge wiki, then query it. Everything writes into `research/` following the wiki rules below, and a daily knowledge-graph build makes it all queryable.

### Ingestion (bring something in)

| Source | Use |
|---|---|
| A single URL, article, blog, thread | `web-ingest` agent |
| PDF, .docx, attached file, long pasted text | `document-ingest` agent |
| Voice memo, meeting notes, transcript | `personal-ingest` agent (extracts action items to TODO.md) |
| Social creator (Instagram, TikTok, YouTube) | `social-ingest` agent |

All ingest agents call the `wiki-ingest` skill internally. Every ingest produces a dated source-of-truth file plus a `research/log.md` entry plus an `index.md` cross-link, which makes the file eligible for the next knowledge-graph rebuild. When you attach a file with no other instruction, `document-ingest` auto-fires.

### Retrieval (answer a question from what you already have)

| Need | Use |
|---|---|
| "What do we know about X?" | `wiki-query` skill (graph-first) |
| Substantive synthesis across many sources | `research-professor` agent |
| "Where does X live?" structural question | `workspace-cartographer` agent |
| Current state of one project | `project-status-scout` agent |
| Lay of the land on a new topic | `/orient <topic>` (fans out all three above) |

### Discovery (find new sources, tools, topics)

| Source | Use |
|---|---|
| Stay current on Claude tooling | `news-research`, `youtube-research`, `newsletter-digest` skills |
| Wider weekly AI-ecosystem sweep | `ai-ecosystem-research` skill / `infra-improver` agent |
| Trending creators in a niche, scraping a watchlist | `intelligence-agent` |
| Instagram keyword research | `ig-research` skill |

### The knowledge graph

`/graphify <path>` turns a folder of research into a navigable knowledge graph (interactive HTML + GraphRAG-ready JSON + a plain-language report). Point it at `research/` to build cross-document entity links the index alone never captures. The retrieval skills are graph-first when a graph exists and fall back to the index plus a freshness check otherwise.

Type `/menu` any time for the full navigation cheat-sheet.

## Tool routing

Check in order, use the first that works.

1. **CLI wrappers** if you keep per-account config files in the project root (Gmail/Drive/Calendar, Slack, Linear, Notion). These route API calls to the correct account when you juggle several.
2. **MCP connectors** if no CLI credentials are set up.
3. **Prompt the user** to set up an MCP if neither exists.

This boilerplate ships no credentials. Wire up whichever connectors you use and document them in your own copy of this file.

## Branching rules (per tier, strict)

Different rules per tier. Don't apply one to all.

- **Parent (this repo)**: work on `main` directly. No feature branches unless you ask for one.
- **Packages** (`packages/<name>/`): work on `main` directly. Research and notes evolve continuously, so PR overhead isn't worth it.
- **Apps** (`packages/<name>/app/`): ALWAYS work on a feature branch, never commit to an app's `main`. Open a PR, wait for CI to pass, then merge.

### Before touching any file in an app

1. `git branch --show-current` to confirm where you are.
2. If on `main`: `git pull`, then `git checkout -b <branch>` for the new work.
3. If on another branch: tell the user before changing anything.
4. Run the app's checks (format, lint, typecheck) locally before pushing.
5. Open the PR, wait for green CI, merge.

## Secrets (HARD RULE)

The one rule that, if broken, causes real damage.

- **Never commit API keys, passwords, or secrets.** Not in code, not in notes, not in prompts.
- Real secrets live in a `.env` file, which is always gitignored.
- Every project that needs secrets ships a `.env.example` with placeholder values so anyone cloning knows what's needed. See `.env.example` at this root.
- For deployed apps, secrets go in the host's secret store (Vercel env vars, GitHub Secrets), never in the repo.

If you ever see a real key about to be committed, stop and flag it.

## Directory rules

**Parent allowed paths:** `AGENTS.md`, `README.md`, `START-HERE.md`, `TODO.md`, `GOVERNANCE.md`, `.env.example`, `scripts/`, `packages/`, `research/`, `decisions/`, `.claude/`, `context/`

Don't create ad-hoc folders (`tmp/`, `output/`, `data/`). Scratch files go in `context/` (gitignored). Nothing in the parent root besides the top-level `.md` files and `.env.example`.

## Research wiki (Karpathy pattern)

`research/` is the shared knowledge layer. Three parts:

- Raw notes and sources in topic subdirs, never edited once written. Add new dated files instead.
- `research/index.md`, the curated entry point. Update when a conclusion changes.
- `research/log.md`, an append-only changelog. One line per new artifact. A PostToolUse hook appends here automatically when a wiki file is written.

Filename convention: `<topic>-YYYY-MM-DD.md`. Date in the file's frontmatter, not as a filename prefix. Full rules in [GOVERNANCE.md](GOVERNANCE.md).

## Transcribing voice notes

To turn a voice memo into text:

```bash
./scripts/transcribe.sh ~/Downloads/voice-note.opus research/transcripts
```

Runs locally on Apple Silicon (mlx-whisper), free, no API key, works offline after the first model download. Handles `.opus`, `.mp3`, `.m4a`, `.wav`. Pass a directory to batch-process a folder.

## How to talk to me

Set this to your own preference. A sensible default:

- Direct and technical. Short answers when the answer is short.
- Explain the why when it's a judgment call, skip the preamble when it isn't.
- No corporate filler. No "I'd be happy to", no "certainly", no "let's dive in".
- Contractions are fine, they read like a human wrote them.
- No em dashes or en dashes as punctuation (a lint hook enforces this on edits). Use commas, periods, or parens.
