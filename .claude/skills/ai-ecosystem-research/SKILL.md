---
name: ai-ecosystem-research
description: >
  Search the broader AI ecosystem (newsletters, YouTube, web/forums, GitHub trending) for
  AI infrastructure movement filtered through the workspace's 5 core domains — NOT
  Cowork-only. Use this skill whenever the user wants a wider-than-Cowork weekly sweep,
  AI infra digest, ecosystem trend brief, or "what's moving across AI tooling this week."
  Triggers: "AI ecosystem research," "weekly AI sweep," "what's new across AI," "broader
  AI digest," "AI infra trends." Pairs with news-research / youtube-research
  / newsletter-digest (those are Cowork-scoped slices); this skill is the broader filter.
  Reads .claude/context/domains-scope.md to know what's in/out of scope.
---

# AI Ecosystem Research

Cast a wide net across the AI ecosystem and return a markdown digest filtered through the workspace's 5 core domains. The 3 existing Cowork-scoped research skills (`newsletter-digest`, `news-research`, `youtube-research`) handle Anthropic-specific signal. **This skill handles everything else** — agent frameworks, video/voice/image gen, MCP servers, web app tooling, monorepo patterns, marketing automation, design systems.

This skill is called by the `infra-improver` agent in parallel with the 3 Cowork skills. It can also be invoked manually.

## Why this skill exists

A routine wider sweep surfaces overlap between your in-house tooling and public skills before you reinvent something that already exists as a plugin. Without it, those discoveries happen by accident. This skill is the wider sweep.

## Prerequisites

- **Gmail MCP** for newsletter sources (`gmail_search_messages`, `gmail_read_message`)
- **WebSearch** for YouTube discovery (`site:youtube.com` queries)
- **yt-transcript.py** for video transcripts (free, no API key — `python3 .claude/skills/youtube-research/yt-transcript.py VIDEO_ID_OR_URL`)
- **WebSearch + WebFetch** for forums + GitHub
- Read access to `.claude/context/domains-scope.md`

## Workflow

### Step 0: Load the domain scope

Read `.claude/context/domains-scope.md` first. Extract the 5 in-scope domains, the 2 excluded, and the `Install Now` allowlist. Use these to filter every search result downstream.

### Step 1: Source sweep (parallel where possible)

Calculate the date 7 days ago from today as `after:YYYY/M/D` for Gmail, `since:YYYY-MM-DD` for forums.

Run these source families. For each, run all the queries; deduplicate; keep only items relevant to one of the 5 in-scope domains.

#### Newsletters (via Gmail MCP)

| Newsletter | Search query | Domain bias |
|---|---|---|
| TLDR | `from:tldrnewsletter.com after:YYYY/M/D` | Wide-net AI news |
| The Rundown AI | `from:therundown.ai after:YYYY/M/D -subject:workshop -subject:tutorial -subject:course` | AI tools + agents |
| Ben's Bites | `from:bensbites.com after:YYYY/M/D` | Agent frameworks + product news |
| Latent Space | `from:substack.com subject:AINews after:YYYY/M/D` | Engineering depth |
| Stratechery | `from:stratechery.com after:YYYY/M/D` | Strategy / business model angle |

For each newsletter, fetch full body via `gmail_read_message`. Skip issues that don't touch any of the 5 domains.

#### YouTube (via WebSearch + yt-transcript.py)

Run these `WebSearch` queries in parallel (extract YouTube URLs from results):

1. `site:youtube.com "AI agents 2026" after:YYYY-MM-DD`
2. `site:youtube.com "claude code workflow" after:YYYY-MM-DD`
3. `site:youtube.com "video generation Veo" OR "AI video generation" after:YYYY-MM-DD`
4. `site:youtube.com "AI design tools" OR "figma make" after:YYYY-MM-DD`
5. `site:youtube.com "MCP servers" after:YYYY-MM-DD`
6. `site:youtube.com "agent orchestration" after:YYYY-MM-DD`

Plus recent videos from these channels (one search each):
- `site:youtube.com "Matt Berman" AI after:YYYY-MM-DD`
- `site:youtube.com "AI Jason" after:YYYY-MM-DD`
- `site:youtube.com "Cole Medin" after:YYYY-MM-DD`
- `site:youtube.com "Nate Herk" after:YYYY-MM-DD`
- `site:youtube.com "Riley Brown" AI after:YYYY-MM-DD`
- `site:youtube.com "Greg Isenberg" startup after:YYYY-MM-DD`

(Use the date 7 days ago for all `after:` values.)

Deduplicate by video ID. Filter to past 7 days. Rank by view count where available. Take top 8 for transcription.

For each selected video, run:
```bash
python3 .claude/skills/youtube-research/yt-transcript.py VIDEO_ID_OR_URL
```

If a transcript fails (stderr will explain), keep the metadata and skip that video.

#### Web / forums (via WebSearch + WebFetch)

Run **at least 6 distinct searches**:

1. Hacker News front page items mentioning AI agents / Claude / model releases — query: `site:news.ycombinator.com claude OR "AI agent" OR "model release" past week`
2. r/ClaudeAI top posts past week — query: `site:reddit.com/r/ClaudeAI past week`
3. r/LocalLLaMA top posts past week — query: `site:reddit.com/r/LocalLLaMA past week`
4. anthropic.com news — query: `site:anthropic.com/news after:YYYY-MM-DD`
5. Vercel blog — query: `site:vercel.com/blog after:YYYY-MM-DD`
6. AI design tools — query: `"figma make" OR "v0 dev" OR "lovable" OR "bolt new" updates past week`

Deep-read the top 2-3 results per search via `WebFetch`.

#### GitHub trending, individual-builder skills + MCPs (MANDATORY, hard quota)

This is the highest-signal source for the kind of tooling your workspace actually
installs (mattpocock-style skill drops, Karpathy-style repos, individual-builder MCPs).
Reddit and announcement-blog signal will drown this out without a quota.

**Quota rule.** The final brief MUST include at least 5 GitHub items from individual
builders. "Individual builder" means personal-account-owned repo (not Anthropic, Google,
Vercel, Meta, OpenAI, or Microsoft), first push within the last 90 days OR star count
jumped more than 2x in the past 7 days. If fewer than 5 qualify, expand the search
topics until you hit 5. Do not pad the brief with announcements instead.

Use WebFetch on:

- `https://github.com/trending?since=weekly`, filter for AI/agent/MCP/skill repos
- `https://github.com/topics/claude-code?o=desc&s=updated`
- `https://github.com/topics/claude-skill?o=desc&s=updated`
- `https://github.com/topics/claude-agent?o=desc&s=updated`
- `https://github.com/topics/mcp-server?o=desc&s=updated`
- `https://github.com/topics/ai-agents?o=desc&s=updated`

Plus search WebSearch for fast-rising builder repos:

- `site:github.com "claude skills" stars:>100 pushed:>YYYY-MM-DD`
- `site:github.com "agents.md" OR "AGENTS.md template" pushed:>YYYY-MM-DD`
- `site:github.com "awesome claude" OR "awesome mcp" pushed:>YYYY-MM-DD`

Capture per repo: name, owner type (individual or org), star count, stars-this-week
delta if visible, last commit date, one-line purpose, why it matters to one of the 5
domains.

#### PulseMCP, new + trending MCP servers (MANDATORY)

PulseMCP is the hand-reviewed front door to the MCP ecosystem (14,910+ servers as of
2026-05). Use WebFetch on:

- `https://www.pulsemcp.com/servers?sort=trending`, top-trending past week
- `https://www.pulsemcp.com/servers?sort=newest`, added in past 14 days

Quota: at least 2 PulseMCP items per brief if any qualify under the 5 domains.

#### HN Show items, builders posting their own tools

WebSearch: `site:news.ycombinator.com "Show HN" claude OR mcp OR agent past week`.

These are individual builders shipping the kind of tooling we install. Fetch the top 3
to 5 results via WebFetch, extract the linked repo or site, score against the 5 domains.

### Source-mix caps (HARD RULE, applies during synthesis)

Without caps, announcement journalism crowds out individual-builder tooling. Enforce:

- **Max 2 items** total across the brief from `{anthropic.com/news, blog.google,
  vercel.com/blog, simonwillison.net, releasebot.io, anthropic blog mirrors}`.
- **Max 1 Reddit sentiment item** in the body of "By Domain". last30days clusters
  belong in the appendix (`Creators worth tracking` and sentiment notes), not as
  primary domain items.
- **Minimum 5 GitHub individual-builder items** per the quota above.
- **Minimum 2 PulseMCP items** if any qualify.

If after applying caps you fall below the per-domain item count, leave the domain
short rather than backfilling with announcements. A short, signal-dense brief is
better than a padded one.

### Step 2: Filter through the 5 domains

For every item gathered in Step 1, ask:

1. Does it fit one of the 5 in-scope domains? If no → drop (or note in `Out-of-scope but flagged` appendix if it lands in one of the 2 excluded domains).
2. Which domain is the best fit? An item can list a primary + secondary domain if it spans two.
3. Does it match the `Install Now` allowlist? Tag accordingly.

Drop generic LLM hype with no architecture detail. Drop hype that doesn't change a workflow.

### Step 3: Synthesize and save

Write the digest to `research/external/YYYY-MM-DD-ai-ecosystem.md`. Use this structure:

```markdown
# AI Ecosystem Research — YYYY-MM-DD

## TL;DR
<!-- 3-4 sentences. The single most important shift across all 5 domains this week. -->

## By Domain

### 1. AI media production engineering
<!-- 2-5 items. Format per item:
- **Item name** ([source URL](url)) — what changed, why it matters in 1 sentence, allowlist match (yes/no) -->

### 2. Content intelligence pipelines
<!-- same format -->

### 3. Agent orchestration + multi-model economics
<!-- same format -->

### 4. App factory
<!-- same format -->

### 5. Workspace + wiki governance
<!-- same format -->

## Creators worth tracking this week
<!-- Bullet list of 2-5 creators (with channel/handle URL) who shipped meaningfully this week -->

## Out-of-scope but flagged
<!-- Items that landed in the 2 excluded domains (healing-vertical business / authentic marketing).
     Just bullet pointers, no synthesis. Empty section if none. -->

## Search Metadata
- **Date:** YYYY-MM-DD
- **Sources scanned:** [list newsletters, channels, forums, GitHub topics]
- **Items considered:** [N before filter] → [M after filter]
- **Transcription failures:** [N, with titles]
- **Source families with zero hits:** [list]
```

### Step 3b (optional): Push the digest to your own store

If you keep a database or dashboard of research output, this is the point to POST the digest to it. Prepend YAML frontmatter (date, source list, topic) to the saved file, then call whatever ingest path you've wired up. Keep it non-blocking. The digest is already on disk from Step 3, so if the POST fails (network error, missing API key), log it and move on. It can be ingested manually later. Out of the box this boilerplate has no such store, so skip this step unless you've added one.

### Step 4: Return a scannable summary, not status-only

The digest is on disk (Step 3) — that satisfies `feedback_subagent_persist_to_disk` (which guards against compaction wipe-out, not against rich summaries). After persistence, return a scannable in-chat summary.

This skill is normally called by the `infra-improver` agent which then re-synthesizes everything — so keep this summary tighter than the agent's final brief. ~15-20 lines, plain ASCII, no em/en dashes.

```
ai-ecosystem-research — YYYY-MM-DD

Items by domain (after 5-domain filter)
  AI media production    {bar} {N}
  Content intelligence   {bar} {N}
  Agent orchestration    {bar} {N}
  App factory            {bar} {N}
  Workspace governance   {bar} {N}

  (bar uses ASCII blocks, scale 0-10 per domain. Example for N=6: ██████░░░░)

Top 5 highest-signal items this week
| # | Item                  | Domain          | Source         | Allowlist |
|---|-----------------------|-----------------|----------------|-----------|
| 1 | {name}                | {domain short}  | {source short} | yes/no    |
| 2 | ...                   | ...             | ...            | ...       |

Source families scanned: {N hits / M zero}
  Newsletters {hit/zero}, YouTube {hit/zero}, Web/forums {hit/zero}, GitHub trending {hit count}

Conflicts flagged with memory rules: {N or "none"}
Out-of-scope but noted (excluded domains): {N or "none"}

Digest: {absolute path}
```

When invoked standalone (not by the orchestrator), this is the user's direct read. When invoked by `infra-improver`, the orchestrator will compress this into the cross-domain table — but it still wants the table here, not raw text, so the synthesis is fast and lossless.

## Edge cases

- **Quiet week:** if a domain has zero items after filter, write `_No findings this week._` under that section. Don't pad.
- **Source down:** if Gmail MCP / YouTube MCP / WebSearch is unavailable, note which source family failed in the metadata block and proceed with what you have.
- **Item spans 3+ domains:** rare but real. List it under the primary domain and note "(also relevant to: domain-X, domain-Y)" inline.
- **Conflict with existing research:** if a finding contradicts something in `research/` (e.g. a memory rule about Veo continuity), flag the conflict in the item description with `[CONFLICTS WITH: <file path>]`.
- **Item is a creator's existing pet project:** if a "trend" is really one creator's recurring video, note as such; don't inflate signal.

## What this skill does NOT do

- Does not handle Cowork-specific news (use `news-research`)
- Does not handle Cowork-specific YouTube (use `youtube-research`)
- Does not handle Cowork-specific newsletter content (use `newsletter-digest`)
- Does not write the integrated 5-domain brief — that's the `infra-improver` agent's job, which calls this skill alongside the Cowork trio
- Does not install or download anything — pure research output
- Does not post to Slack — that's the orchestrator's job
