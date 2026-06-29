# Claude Monorepo

> A research, ingestion, and discovery pipeline for any AI coding agent. Bring the outside world into a local knowledge wiki, then query it back out. Install it as a Claude Code plugin, or clone it as a whole workspace.

![license](https://img.shields.io/badge/license-MIT-blue)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-7c3aed)
![skills](https://img.shields.io/badge/skills-16-green)
![agents](https://img.shields.io/badge/agents-11-green)
![hooks](https://img.shields.io/badge/hooks-3-green)
![Shell](https://img.shields.io/badge/Shell-grey?logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Python-grey?logo=python&logoColor=white)
![Markdown](https://img.shields.io/badge/Markdown-grey?logo=markdown&logoColor=white)

This is a boilerplate. A parent workspace that gives any AI coding agent (Claude Code, Codex, Cursor, Gemini CLI) one consistent memory across every project you work on, plus a ready-made pipeline for pulling the outside world in (URLs, PDFs, voice notes, social, newsletters) and querying it back out. Clone it, strip the example, make it yours.

## Install

### As a Claude Code plugin

Pulls in the 16 skills, 11 agents, and 3 hooks without cloning the whole workspace.

```
/plugin marketplace add dtothefp/claude-monorepo
/plugin install claude-monorepo@dtothefp
```

### As a workspace (clone)

Get the full three-tier structure, the research wiki, and the docs.

```bash
git clone https://github.com/dtothefp/claude-monorepo.git
cd claude-monorepo
```

### Copy components manually

Grab only what you want. Every component is a plain file.

```bash
cp -r claude-monorepo/.claude/skills/web-ingest   your-project/.claude/skills/
cp    claude-monorepo/.claude/agents/research-professor.md your-project/.claude/agents/
```

## What's inside

This repo is a Claude Code plugin and a clonable workspace at the same time.

```
claude-monorepo/
|-- .claude-plugin/
|   |-- plugin.json          # Plugin manifest, points at .claude/
|   |-- marketplace.json     # Marketplace catalog for /plugin marketplace add
|
|-- .claude/
|   |-- skills/              # 16 skills (ingest, retrieve, discover, utility)
|   |-- agents/              # 11 agents (subagents for delegation)
|   |-- hooks/               # 3 hooks (lint, log-append, ingest-suggest)
|   |-- settings.json        # Wires the hooks in workspace mode
|
|-- AGENTS.md                # Central rules (CLAUDE.md + GEMINI.md symlink to it)
|-- README.md
|-- START-HERE.md            # Runbook
|-- GOVERNANCE.md            # Wiki and directory rules
|-- TODO.md
|-- LICENSE                  # MIT
|-- .env.example             # Placeholder keys, all optional
|
|-- packages/                # Your projects go here, one repo each (gitignored)
|-- research/                # The shared knowledge wiki
|   |-- index.md             # Curated entry point
|   |-- log.md               # Append-only changelog
|-- decisions/               # Architecture decision records
```

## The pipeline (the point of this repo)

A consistent way to bring the outside world into a local wiki, then query it. Everything writes into `research/`, and a `/graphify` build makes it queryable as a knowledge graph.

### Ingest (bring something in)

| Source | Use |
|---|---|
| A single URL, article, blog, thread | `web-ingest` agent |
| PDF, .docx, attached file, long pasted text | `document-ingest` agent |
| Voice memo, meeting notes, transcript | `personal-ingest` agent (pulls action items into TODO.md) |
| Social creator (Instagram, TikTok, YouTube) | `social-ingest` agent |

All ingest agents call the `wiki-ingest` skill. Every ingest produces a dated source file, a `research/log.md` entry, and an `index.md` cross-link, which makes it eligible for the next graph rebuild.

### Retrieve (answer from what you already have)

| Need | Use |
|---|---|
| "What do we know about X?" | `wiki-query` skill (graph-first) |
| Substantive synthesis across many sources | `research-professor` agent |
| "Where does X live?" structural question | `workspace-cartographer` agent |
| Current state of one project | `project-status-scout` agent |
| Lay of the land on a new topic | `/orient <topic>` (fans out the three above) |

### Discover (find new sources, tools, topics)

| Source | Use |
|---|---|
| Stay current on Claude tooling | `news-research`, `youtube-research`, `newsletter-digest` skills |
| Wider weekly AI-ecosystem sweep | `ai-ecosystem-research` skill / `infra-improver` agent |
| Trending creators, scraping a watchlist | `intelligence-agent` |
| Instagram keyword research | `ig-research` skill |

### The knowledge graph

`/graphify <path>` turns a folder of research into a navigable knowledge graph (interactive HTML, GraphRAG-ready JSON, a plain-language report). Point it at `research/` to build cross-document entity links the index alone never captures. The retrieval skills are graph-first when a graph exists and fall back to the index plus a freshness check otherwise.

Type `/menu` any time for the full navigation cheat-sheet.

## Works on every tool

The rules live in `AGENTS.md`. `CLAUDE.md` and `GEMINI.md` are symlinks to it, so the same instructions load in:

- **Claude Code** (native skills, agents, hooks, plugin install)
- **Cursor** (reads `AGENTS.md`)
- **Codex CLI** (reads `AGENTS.md`)
- **Gemini CLI** (reads `GEMINI.md`)

The skills and agents are plain markdown and shell. The graph build and a couple of media skills use Python. Nothing is locked to one vendor.

## Three tiers (workspace mode)

1. **Parent** (this repo). Cross-project rules, task tracking, the shared wiki. Works on `main`.
2. **Packages** (`packages/<name>/`). One independent git repo per project, gitignored from the parent so each stays on its own remote. Works on `main`.
3. **Apps** (`packages/<name>/app/`). The deployable app inside a project, its own repo, feature branches and PRs only.

To add a project:

```bash
cd packages/
git clone <repo-url> <name>
```

## Hooks (opinionated, easy to drop)

Three hooks ship wired up. They are deliberate about house style, so read before you adopt them.

- **em-dash-lint** (PreToolUse). Blocks any `Write`/`Edit` that contains an em or en dash. A style rule, not everyone's taste. Delete the hook entry to turn it off.
- **research-log-append** (PostToolUse). Appends a line to `research/log.md` when a wiki file is written. No-op outside the wiki.
- **wiki-ingest-suggest** (UserPromptSubmit). Nudges you to ingest when you paste something worth capturing.

In workspace mode they are wired in `.claude/settings.json`. In plugin mode they are wired in `plugin.json` via `${CLAUDE_PLUGIN_ROOT}`. Remove the ones you do not want.

## Secrets

Never commit keys. Real secrets live in a gitignored `.env`. This repo ships only `.env.example` with placeholders, and every key in it is optional. Wire up whichever connectors you use and document them in your own copy of `AGENTS.md`.

## Credits

The pipeline pattern borrows from Andrej Karpathy's three-layer wiki idea (immutable sources, a curated index, an append-only log). The plugin and marketplace format follows the Claude Code plugin spec.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 David Fox-Powell.
