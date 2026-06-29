# 0001: Workspace architecture (three tiers, one wiki)

Date: 2026-06-29
Status: accepted

## Context

Working across many projects with an AI agent has two recurring failure modes. You re-explain context every session, and your research scatters across chats, downloads, and notes apps where it's never queryable again. A single flat repo doesn't fix it either, because projects need to deploy and be shared on their own.

## Decision

A three-tier structure with one shared knowledge layer.

1. **Parent** (this repo). Cross-project rules, task tracking, and the shared research wiki. Works on `main` directly.
2. **Packages** (`packages/<name>/`). One independent git repo per project, gitignored from the parent so each stays on its own remote. Works on `main` directly.
3. **Apps** (`packages/<name>/app/`). The deployable app inside a project, its own repo, feature branches and PRs only.

All research, from every tier, writes into `research/` following the Karpathy three-layer pattern (immutable dated sources, a curated `index.md`, an append-only `log.md`). A `/graphify` build turns that wiki into a navigable knowledge graph so retrieval can find cross-document connections the index alone never captures.

## Why per-tier branching

Research and notes change too often to be worth PR overhead, so parent and packages commit to `main`. App code ships to users, so it gets the safety of feature branches, CI, and review. One-size-fits-all branching would either slow down notes or under-protect deploys.

## What we ruled out

- **One flat monorepo for everything.** Breaks independent deploy and sharing per project.
- **No shared wiki, research lives per project.** Loses cross-project synthesis, which is the main reason to have a parent at all.
- **PRs everywhere.** Too much friction for research that changes every session.
