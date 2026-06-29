# Claude Monorepo

A boilerplate for running your work out of one AI-agent workspace. One parent repo, one consistent memory, every project in one place, plus a ready-made research, ingestion, and discovery pipeline that any AI coding agent (Claude Code, Codex, Cursor, Gemini CLI) can drive.

> **New here? Read [START-HERE.md](START-HERE.md).** It's the runbook: what's in the box, how to clone projects down, what to wire up, and how the pieces fit.

## What this is

A parent workspace that sits above all your projects. It holds the high-level rules for how you work (`AGENTS.md`), a shared research wiki (`research/`), and a set of Claude Code skills and agents under `.claude/` for pulling the outside world into a local knowledge base and querying it back out.

The projects themselves live in `packages/`, each as its own independent git repo. This repo only tracks its own files.

## Why you'd use it

If you work across many projects with an AI agent, you re-explain context every session and your research scatters. This fixes both. One memory layer, one wiki, one pipeline for getting URLs, PDFs, voice notes, social posts, and newsletters into a queryable knowledge graph, and a clean three-tier structure for parent, projects, and deployable apps.

## The three tiers

```
claude-monorepo/             <- this repo (parent). Rules + task tracking + shared research + skills/agents.
├── AGENTS.md                <- how you work. Read first. (CLAUDE.md + GEMINI.md symlink to it)
├── README.md                <- you are here
├── START-HERE.md            <- the runbook
├── TODO.md                  <- cross-project task list
├── GOVERNANCE.md            <- memory + wiki rules
├── .env.example             <- the keys the pipeline can use (all optional)
├── .claude/
│   ├── skills/              <- /graphify, wiki-ingest, web-ingest, research skills, ...
│   ├── agents/              <- ingest + retrieval + discovery agents
│   └── hooks/               <- research-log auto-append, em-dash lint, ingest suggest
├── research/                <- the shared knowledge wiki (index + log + topic dirs)
├── decisions/              <- architecture decision records
├── scripts/                <- helper scripts (transcribe voice notes, ...)
└── packages/               <- each child project, its own repo (gitignored here)
```

Parent and projects work on `main`. Apps always work on a feature branch with a PR. Full rules in [AGENTS.md](AGENTS.md).

## What's in the pipeline

Three motions, all writing into the same wiki so everything stays queryable.

- **Ingest** new material: `web-ingest`, `document-ingest`, `personal-ingest`, `social-ingest` agents.
- **Retrieve** what you have: `wiki-query` skill, `research-professor`, `workspace-cartographer`, `project-status-scout` agents, or `/orient <topic>` to fan out all three.
- **Discover** what's new: `news-research`, `youtube-research`, `newsletter-digest`, `ai-ecosystem-research`, `ig-research` skills, `intelligence-agent` and `infra-improver` agents.

`/graphify <path>` turns the wiki into a navigable knowledge graph. `/menu` prints the full cheat-sheet. See [AGENTS.md](AGENTS.md) for the routing tables.

## Getting started

```bash
# clone this workspace
git clone https://github.com/dtothefp/claude-monorepo.git
cd claude-monorepo

# copy the env template and fill in whatever you use (all keys are optional)
cp .env.example .env

# clone your projects into packages/
cd packages/
git clone <repo-url> my-first-project
```

`packages/*/` is gitignored, so each project stays an independent repo. The parent only tracks its own files. Open the workspace in Claude Code (or your agent of choice) and type `/menu`.

## The one rule that matters most

Never commit secrets. API keys, passwords, tokens go in a `.env` file that's always gitignored. Every project ships a `.env.example` with placeholders. Deployed apps keep secrets in the host's secret store. See the Secrets section in [AGENTS.md](AGENTS.md).

## Credits

The knowledge-graph build uses the bundled `graphify` skill. Topic discovery pairs well with the MIT-licensed [last30days](https://github.com/mvanhorn/last30days-skill) skill (not bundled, install separately if you want it).

## License

MIT. See [LICENSE](LICENSE).
