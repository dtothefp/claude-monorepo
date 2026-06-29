# Start Here

This is the runbook for the Claude Monorepo boilerplate. It's written for two readers. You, the human, and the AI agent (Claude Code, Cursor, Codex, or Gemini CLI) working inside this repo with you. If you're the agent, treat this as your onboarding. Read [AGENTS.md](AGENTS.md) first, then this.

The repo gives you a parent workspace with one consistent memory across every project, plus a research, ingestion, and discovery pipeline that's ready to run. Your job is to make it yours: clone your projects in, wire up whatever connectors you use, and start ingesting.

---

## The mental model

Keep this picture straight and nothing gets lost.

- **Your cloud drive** is the library. Long-term reference, raw documents.
- **Your local machine** is the workshop. Where the building happens.
- **The chat model** (Claude, ChatGPT) is the strategy room. Thinking, planning, drafting.
- **The coding agent** (Claude Code, Codex) is the build crew. Writes and ships code.
- **GitHub** is the code truth. If it's not pushed, it doesn't exist.

This repo is the workshop's front desk. Three tiers stacked inside it:

```
claude-monorepo/             <- parent. Rules + tasks + shared research + skills/agents. Works on main.
└── packages/                <- each project, its own repo (gitignored here so they stay independent)
    └── <project>/
        └── app/             <- the deployable app (its own repo). Feature branches + PRs only.
```

Two rules follow from this:

1. The **parent** and the **projects** work on `main` directly. No branches, no PRs. Research and notes change too often for that overhead.
2. The **apps** (`packages/<name>/app/`) always work on a feature branch with a pull request. Never commit straight to an app's `main`.

---

## Step 1: Clone and configure

```bash
git clone https://github.com/dtothefp/claude-monorepo.git
cd claude-monorepo

# env template (all keys optional, fill in what you use)
cp .env.example .env

# bring your projects in
cd packages/
git clone <repo-url> <project-name>
cd ..
```

`packages/*/` is gitignored, so each project stays an independent repo on its own remote. That's deliberate. It keeps every repo shareable and deployable on its own. The parent only ever tracks its own files.

If `git clone` over SSH fails, you need an SSH key tied to your GitHub account. Run `ssh -T git@github.com` to test.

---

## Step 2: Wire up the pipeline (optional, do it as you need it)

The pipeline runs on free local tooling out of the box and reaches for paid APIs only when you ask it to. Set the keys you want in `.env`. Everything is optional.

| Capability | What it needs | Free without it? |
|---|---|---|
| Transcribe voice notes | `scripts/transcribe.sh` (mlx-whisper, local) | Yes, fully local |
| YouTube transcripts | `yt-transcript.py` (bundled) | Yes, no key |
| Build the knowledge graph | `/graphify` (bundled) | Yes |
| Ingest URLs / PDFs / text | WebFetch + `wiki-ingest` | Yes |
| Social / Instagram scraping | `APIFY_API_KEY` | No, needs Apify |
| Video analysis in discovery | `GEMINI_API_KEY` | No |
| Newsletter / Gmail research | Gmail MCP connector | No |
| Mirror research to Notion | Notion MCP connector | No |

Connectors (Gmail, Notion, Slack, Linear) are set up in your agent, not committed here. See the Tool Routing section in [AGENTS.md](AGENTS.md).

---

## Step 3: Try the pipeline

Ingest something, then query it.

```text
# in your agent, paste a URL or attach a PDF, or say:
"ingest https://example.com/some-article into research"

# then ask what you captured:
/orient that topic
# or
"what do we know about X?"
```

Then build the graph over everything you've collected:

```text
/graphify research/
```

Type `/menu` any time for the full list of agents and skills.

---

## Step 4: How app deploys work (if you add an app)

Apps live at `packages/<name>/app/` as their own repo and deploy through their own host (Vercel by default).

- Open a pull request against the app's `main`. The host builds a preview deploy and posts the URL on the PR.
- Merge to `main`. The host builds and ships production.

You never deploy by hand. You merge, and it deploys.

---

## Day to day

- **Capturing thoughts.** Drop a voice memo in and turn it into text with `./scripts/transcribe.sh ~/Downloads/your-memo.opus research/transcripts`. Local, free, no key.
- **Tracking work.** High-level tasks live in [TODO.md](TODO.md) here. Each project keeps its own list in `packages/<name>/TODO.md`.
- **Research.** Anything worth keeping goes in `research/` following [GOVERNANCE.md](GOVERNANCE.md). Raw notes in dated files, a curated `index.md`, an append-only `log.md`.
- **The one rule that matters most.** Never commit a secret. If you're unsure whether something is sensitive, treat it as sensitive and keep it in `.env`.

The rules your AI agent follows at every tier are in the `AGENTS.md` at that level (`CLAUDE.md` and `GEMINI.md` are symlinks, so every tool reads the same thing). Start with [AGENTS.md](AGENTS.md) here, then the one inside whichever project you're working in.
