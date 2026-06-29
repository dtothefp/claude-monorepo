---
name: menu
description: Print the workspace navigation cheat-sheet (the discovery agents, ingest agents, and other top-level entry points). Use when the user types `/menu` or asks to see the workspace navigation menu.
---

# Menu Skill

On invocation, output the block below verbatim and stop. No tool calls, no preamble, no follow-up commentary.

---

## 🧭 Workspace navigation

**Discover what we already know**
- `/orient <topic>` fans out all three discovery agents below on a new idea
- `workspace-cartographer` answers "where does X live?" (structure, pointers)
- `research-professor` answers "what do we think about X?" (synthesis from the wiki)
- `project-status-scout` reports the current state of one named project

**Ingest new material into the wiki**
- `web-ingest` files a single URL into the research wiki (article, blog, thread)
- `document-ingest` handles PDFs, URLs, articles, pasted text (auto-fires on attached files)
- `personal-ingest` handles meeting notes, voice memos, transcripts (routes action items to TODO.md)
- `social-ingest` handles IG / TikTok / YouTube / competitor creators and teardowns

**Research and discovery**
- `news-research`, `youtube-research`, `newsletter-digest` keep you current on Claude tooling
- `ai-ecosystem-research` runs a wider weekly sweep across the AI ecosystem
- `intelligence-agent` scrapes a creator watchlist or discovers new creators in a niche
- `infra-improver` produces a weekly AI-infra brief (what to install, evaluate, publish back)

**Build the knowledge graph**
- `/graphify <path>` turns a folder of research into a navigable knowledge graph
