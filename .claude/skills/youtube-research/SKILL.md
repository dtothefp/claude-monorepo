---
name: youtube-research
description: "Transcribe a YouTube video and return the full transcript text. Trigger when the user gives a YouTube URL or video ID and wants a transcript, says 'transcribe this', 'get the transcript', 'what does this video say', or similar. No API key required."
---

# youtube-research

Fetch a YouTube video transcript and return it to the user.

## How to run

```bash
python3 .claude/skills/youtube-research/yt-transcript.py VIDEO_ID_OR_URL
```

Accepts:
- Bare video ID: `wLdb3FHn7BA`
- Full URL: `https://www.youtube.com/watch?v=wLdb3FHn7BA`
- Short URL: `https://youtu.be/wLdb3FHn7BA`

Options:
- `--timestamps` — prefix each line with `[MM:SS]` (useful for long videos)
- `--lang es en` — language priority list (default: `en`)

## Workflow

1. Run the script with the video ID or URL the user provided.
2. Return the transcript text inline — don't save to a file unless the user asks.
3. If the script errors (transcripts disabled, private video, no captions), tell the user why.

## If the user wants to save it

Save to the relevant project's `research/` directory as:
```
research/youtube-VIDEOID-YYYY-MM-DD.txt
```

No MCP connector required. The script uses the free `youtube-transcript-api` library installed at `/usr/local/lib/python3.x`.
