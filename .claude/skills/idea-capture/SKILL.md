# Idea Capture Skill

## Description

Quick-capture skill for logging ideas and tasks to the parent TODO.md Inbox.
Everything goes to Inbox first. You triage into the right project during review.

## Triggers

- "/idea", "capture idea", "log idea", "quick idea"
- "I have an idea", "new idea", "add idea"
- "track this", "remember this", "log this"

## Usage

```
/idea "Build an agentic trading bot for Polymarket"
/idea "Notion integration for cross-project visibility"
/idea "Fix obsidian-git sync" daily-task P1
```

Everything goes to the **parent workspace TODO.md** `## Inbox` section.
No routing, no project slugs. During review, move ideas to the right
project's TODO.md when ready to act on them.

## Labels

Use labels to set the state tag:

| Label | State tag | When to use |
|-------|-----------|------------|
| `idea` (default) | `idea` | New product ideas, feature ideas, things to explore |
| `daily-task` | `backlog` | Operational work that needs doing now |
| `research` | `idea` | Things to investigate or learn about |

If the user doesn't specify a label, default to `idea`.

## Priority

| Tag | Meaning |
|-----|---------|
| `P0` | Urgent, do today |
| `P1` | High priority |
| `P2` | Medium (default if not specified) |
| `P3` | Low priority, whenever |

## How It Works

1. Parse the user's input to extract the idea text, optional label, and optional priority
2. Read the parent `TODO.md` file
3. Find the `## Inbox` section
4. Append the new item at the end of the Inbox section using the Edit tool:
   ```
   - [ ] Idea text here `P2` `idea`
   ```
5. If a description is provided beyond the title, add it as a blockquote:
   ```
   - [ ] Idea text here `P2` `idea`
     > Additional context or description
   ```
6. Confirm to the user what was captured

## Example

User says: `/idea "Build a self-serve onboarding flow"`

Append to `## Inbox` in `TODO.md`:
```markdown
- [ ] Build a self-serve onboarding flow `P2` `idea`
```

User says: `/idea "Fix deploy workflow" daily-task P1`

Append:
```markdown
- [ ] Fix deploy workflow `P1` `backlog`
```

## Important

- **Always append to the parent workspace TODO.md**, never to a child project's TODO.md
- Use the Edit tool to insert the line at the end of the `## Inbox` section
  (before the next `---` or `##` heading, or at the end of the file if Inbox is last)
- If the TODO.md has no `## Inbox` section, create one at the bottom of the file
- Escape any backticks in the idea title
- After capturing, display the item as confirmation (just the formatted line)
