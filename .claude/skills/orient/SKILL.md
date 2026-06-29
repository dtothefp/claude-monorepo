---
name: orient
description: Get the lay of the land on a new idea or topic before starting work. Spawns the three workspace-navigation agents (workspace-cartographer, research-professor, project-status-scout) in parallel and synthesizes their findings into one brief. Use when the user comes in with a new idea, an unfamiliar topic, or asks "what do we know about X" / "is there related work" / "where does this fit". Do NOT use for narrow questions that one agent alone can answer.
---

# Orient Skill

Surveys the workspace for anything related to an incoming idea or topic, in one shot. Three agents run in parallel; you synthesize their outputs into a single brief.

## When to invoke

- "I have a new idea: …" / "thinking about …" / "want to explore …"
- "What do we know about …?"
- "Lay of the land on …"
- "Is there related work on …?"

Skip when the question is narrow enough for one agent (e.g. "where does the auth logic live" -> cartographer alone; "status of project-alpha" -> scout alone).

## Inputs

- `topic` — the idea, question, or topic in the user's words (required)
- Optional `project` — if the user named a specific project, pass it to the scout. Otherwise infer from topic; if no clear project match, skip the scout.

## Pipeline

1. **Parse the topic.** Pull out 3-6 keywords. Identify any project names mentioned.

2. **Spawn 2-3 agents in parallel** (single message, multiple `Agent` tool calls):
   - `workspace-cartographer` with `query: "Where does <topic> live and which projects touch it?"` — finds pointers.
   - `research-professor` with `question: "What do we know about <topic>? What's our current thinking?"` — finds reasoning.
   - `project-status-scout` with `project_name: <project>` — only if a specific project is named or strongly implied.

3. **Wait for all to return.** Each agent persists its full output to `context/agent-runs/`. Their chat replies are short by design.

4. **Synthesize a brief** in this shape:

```
Orient: <topic>

Where it lives (cartographer):
- <file path> — <one-line tag>
- <file path> — <one-line tag>

What we think (professor):
<2-3 sentences pulled from the professor's prose, with citations>

Project state (scout, if invoked):
<1-line status of the named project>

Suggested next moves:
- <action grounded in the findings>
- <action>
```

5. **Persist the brief** to `context/orient-runs/<UTC-timestamp>-<slug>.md` with full agent outputs linked.

## Failure modes

- All three agents return empty → say so plainly. The workspace genuinely has nothing on this topic. Suggest the user run `wiki-ingest` if they have a source to seed it with.
- Cartographer and professor disagree on where something lives → surface the conflict. The professor's body-read wins for substantive claims; the cartographer's index pointer wins for "where does the file actually sit".
- Topic is too broad (e.g. "marketing") → push back: ask the user to narrow before spawning. Do not spawn agents on a topic that will return everything.

## Do not

- Do not spawn agents sequentially. Parallel only.
- Do not re-do the agents' work yourself. Trust their citations and persisted runs.
- Do not exceed ~40 lines of chat output. The brief is a pointer to the persisted run, not the run itself.
- Do not invoke for narrow questions one agent can answer alone. Use the agent directly.
- Do not save anything to `research/answers/` — that is the professor's call, on explicit user request only.
