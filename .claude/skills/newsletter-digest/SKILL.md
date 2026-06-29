---
name: newsletter-digest
description: >
  Fetch the user's tech newsletter emails from Gmail and extract everything related to
  Claude and Claude Cowork into a weekly markdown digest. Use this skill whenever the user
  asks to summarize their newsletters for Claude/Cowork news, catch up on Claude updates
  from their email, or produce a weekly Cowork newsletter digest. Also trigger when the
  user says 'summarize my newsletters', 'what did my newsletters say about Claude',
  'newsletter digest', 'catch me up on Cowork from my emails', 'weekly newsletter summary',
  or 'what did I miss about Claude in my newsletters'. Trigger even for casual requests
  like 'digest my email newsletters' or 'any Cowork stuff in my newsletters this week'.
---

# Newsletter Digest — Claude & Cowork Focus

Extract Claude, Cowork, Claude Code, and Anthropic news from the user's tech newsletter
emails into a single focused weekly digest. The user is a senior engineer and AI consultant
evaluating Cowork for client recommendations — this digest feeds directly into that work.

## Gmail Account

Newsletters are delivered to your inbox (set the address that works for you). Use the Gmail MCP
connector (`gmail_search_messages`, `gmail_read_message`) to access them.

## Newsletter sources

Calculate the date 7 days ago from today and use it in every query as `after:YYYY/M/D`.

Search for each source separately so zero-result sources are visible. Run all searches,
then read the results.

| Newsletter | Search query |
|---|---|
| TLDR | `from:tldrnewsletter.com after:YYYY/M/D` |
| The Rundown AI | `from:therundown.ai after:YYYY/M/D -subject:workshop -subject:tutorial -subject:course` |
| Latent Space / AI News | `from:substack.com subject:AINews after:YYYY/M/D` |
| Robinhood Snacks | `from:snacks.robinhood.com after:YYYY/M/D` |
| Morning Brew | `from:morningbrew.com after:YYYY/M/D` |
| Ben's Bites | `from:bensbites.com after:YYYY/M/D` |
| The Neuron | `from:theneurondaily.com after:YYYY/M/D` |
| ByteByteGo | `from:bytebytego.com after:YYYY/M/D` |
| The Pragmatic Engineer | `from:pragmaticengineer.com after:YYYY/M/D` |

Use `gmail_search_messages` for each query, then `gmail_read_message` for each result
to get the full body.

If a newsletter returns zero results, note "No issues received" in the output.

## Workflow

1. **Fetch** — run all source searches with the date filter, note which return results
2. **Read** — fetch full message body for each result
3. **Filter** — keep only content mentioning Claude, Cowork, Claude Code, Anthropic, or direct competitive comparisons (Claude vs GPT/Gemini). Drop everything else.
4. **Deduplicate** — if multiple newsletters covered the same story, mention it once and note all sources
5. **Flag capabilities** — identify anything that represents a new or changed capability in Claude/Cowork
6. **Write** — compose the digest using the template below

For daily newsletters like TLDR (7 issues/week), scan all issues but extract only
Claude-relevant mentions — don't read every word.

## Output

Save to `research/YYYY-MM-DD_newsletters.md`. Don't overwrite existing files for the same date.

```markdown
# Claude & Cowork Newsletter Digest — YYYY-MM-DD

**Period:** YYYY-MM-DD to YYYY-MM-DD
**Scanned:** [all newsletter names — mark which had Claude content, which had none]

## TL;DR
<!-- 2-3 sentences max. The #1 Claude/Cowork development and why it matters. Write last. -->

## Claude & Anthropic Updates
<!-- Model releases, API changes, company news. Per item: what, source + date, why it matters.
     Keep each item to 1-2 sentences. -->

## Cowork & Claude Code Developments
<!-- New features, workflow changes, capability additions.
     If nothing: "No Cowork/Claude Code developments this week." -->

## Competitive Landscape
<!-- How newsletters framed Claude vs competitors. Benchmarks, feature comparisons.
     Only if actually covered — don't editorialize. Omit section if nothing. -->

## New Capabilities Flagged
<!-- Actionable items the user or clients can act on NOW.
     Format: "- **[Capability]**: [What it enables] — [Consulting implication]"
     If nothing: "No new capabilities flagged." -->

## Cowork vs Claude Code Boundary
<!-- Anything that shifts the decision boundary between these tools.
     If nothing: "No boundary changes noted." -->

## Sources
<!-- Per newsletter with Claude content:
     - Name (date): "Subject" — what was relevant -->
```

## Guidelines

- **800 words max.** A quiet week can be 150 words. Don't pad.
- **Claude-only filter.** This is not a general tech digest. If a story doesn't touch Claude, Cowork, Anthropic, or the competitive landscape, it's out.
- **Source everything.** Every claim needs a newsletter name and date.
- **New Capabilities is the money section.** Be specific and actionable — "Claude is getting better" is useless; "Claude Code auto-mode eliminates permission dialogs for trusted commands" is useful.
- **Flag conflicts.** If something contradicts existing research docs, call it out.
- **Note missing newsletters.** Some subscriptions (Morning Brew, Ben's Bites, The Neuron, ByteByteGo, Pragmatic Engineer) are new and may not have delivered yet.
