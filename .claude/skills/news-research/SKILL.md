---
name: news-research
description: >
  Search the web for Claude Cowork announcements, new features, community discussions,
  and Anthropic news from the past 7 days, then summarize findings into a dated markdown
  file. Use this skill whenever the user asks to research Cowork news, check for Cowork
  updates, find recent Anthropic announcements about Cowork, look for community discussions
  about Cowork, or wants a digest of what's new with Claude Cowork. Also trigger when the
  user says things like 'what's new with Cowork', 'any Cowork updates', 'Cowork news',
  'research Cowork features', 'Cowork changelog', or 'weekly Cowork digest'. Use this even
  for general requests like 'catch me up on Cowork' or 'what did I miss in Cowork land'.
---

# Cowork News Research

You are a research agent that finds and synthesizes the latest Claude Cowork news. Your job
is to cast a wide net across official and community sources, then distill everything into a
single, scannable markdown file the user can skim in under 3 minutes.

## Why this skill exists

Cowork is evolving fast. The user is a senior engineer evaluating Cowork for client
recommendations. Missing a feature launch or breaking change means stale advice. This skill
automates the weekly scan so nothing slips through.

## Research process

### Step 1: Search across multiple source categories

Run **at least 5 distinct web searches** to cover different angles. The goal is breadth —
you're looking for signals across official channels, developer communities, and social media.

Suggested searches (adapt phrasing to get good results):

1. **Official announcements**: `Claude Cowork announcements 2026` or `Anthropic Cowork release`
2. **Changelog / docs**: `Claude Cowork changelog` or `site:docs.claude.com Cowork`
3. **Community discussion**: `Claude Cowork Reddit OR "Hacker News"` or `Claude Cowork discussion`
4. **Social / X (Twitter)**: `Claude Cowork Twitter` or `Boris Cherny Cowork`
5. **YouTube / video**: `Claude Cowork tutorial OR demo 2026`
6. **Feature-specific** (if you know of recent buzz): e.g., `Cowork MCP servers`, `Cowork scheduled tasks`, `Cowork plugins`

Use date-aware queries when possible (include the current year, or "this week", "past 7 days").

### Step 2: Deep-read promising results

For any search result that looks substantive (official blog post, detailed community thread,
changelog entry), use `WebFetch` to get the full content. Don't rely solely on search
snippets — they're often truncated or misleading.

Prioritize these sources (in order):
1. anthropic.com/news and anthropic.com/engineering
2. docs.claude.com (changelog, release notes)
3. Posts by Boris Cherny (Cowork creator) or verified Anthropic staff
4. Reddit r/ClaudeAI, r/anthropic
5. Hacker News threads
6. YouTube videos with significant view counts

### Step 3: Synthesize findings

Organize what you found into the output format below. The key editorial decisions:

- **Separate signal from noise.** A passing mention of Cowork in a general AI thread is not
  a finding. A detailed changelog entry or feature demo is.
- **Flag capability changes.** Anything that changes what Cowork can or can't do gets called
  out explicitly — these affect the user's client recommendations.
- **Note the Cowork vs Claude Code boundary.** If a finding clarifies when to use Cowork vs
  Claude Code (or shifts that boundary), flag it in the dedicated section.
- **Be honest about gaps.** If a search category turned up nothing, say so. "No Reddit
  discussion found this week" is more useful than silence.

## Output format

Save the file to the project's `/research/` directory with the filename pattern
`YYYY-MM-DD_cowork-news.md` using today's date.

Create the `/research/` directory if it doesn't exist.

Use this structure:

```markdown
# Cowork News Digest — YYYY-MM-DD

## TL;DR
<!-- 2-4 sentences. What's the single most important thing from this week? -->

## Key Findings

### Official Announcements
<!-- Anthropic blog posts, changelog entries, docs updates. Include URL and date for each. -->

### New or Updated Capabilities
<!-- Specific features, tools, integrations, or behavioral changes. Be concrete:
     "Cowork now supports X" not "improvements were made". -->

### Community Discussion
<!-- Reddit, HN, Twitter/X threads worth knowing about. Summarize the discussion,
     don't just link it. Note sentiment if there's a clear trend. -->

### Video & Tutorial Content
<!-- YouTube videos, walkthroughs, demos. Note channel, rough view count, and
     whether it reveals non-obvious techniques. -->

## Cowork vs Claude Code Boundary
<!-- Anything that clarifies or shifts when to use Cowork vs Claude Code.
     If nothing this week, say "No boundary-shifting findings this week." -->

## Consulting Relevance
<!-- How any of the above affects client recommendations.
     What would you tell a client differently based on this week's findings? -->

## Sources
<!-- Bulleted list of all URLs referenced above, with titles -->
```

## Important guidelines

- Every factual claim needs a source URL and date. No unsourced assertions.
- If the research turns up something that contradicts existing files in `/synthesis/`,
  flag the conflict explicitly — don't silently override prior conclusions.
- Keep the total digest under 800 words. This is a scan document, not a report.
- If you find nothing noteworthy, still create the file with a short "quiet week" note.
  Knowing that nothing changed is itself useful information.
- Use the user's existing folder structure. Check for `/research/` and create it if missing.
