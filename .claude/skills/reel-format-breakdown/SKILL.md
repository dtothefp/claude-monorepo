---
name: reel-format-breakdown
description: "Given an Instagram Reel URL, download the video and produce a thorough shot-by-shot format breakdown (cover, face-cam, real-broll, generated-broll, captions, narration, format role per shot) as a markdown beat-sheet we can mimic in our own Reels. Use this skill when the user wants to reverse-engineer, analyze the format of, or deeply break down an Instagram Reel. Triggers: 'break down this reel', 'reel format breakdown', 'reverse engineer this reel', 'analyze this reel', 'how is this reel structured'."
---

# reel-format-breakdown

Reverse-engineers an Instagram Reel's production format into a reusable beat-sheet we can mimic. Not for "is this worth riffing on" triage (that's `intelligence-agent`). This is for deep per-shot analysis of a reference creator's format so `script-agent` and `production-agent` can produce our own Reels in that same shape.

## Triggers

- "break down this reel [url]"
- "reel format breakdown"
- "reverse engineer this reel"
- "analyze the format of this reel"
- "how is this reel structured"

## Inputs

- `reel_url` (required) — the Instagram Reel URL, e.g. `https://www.instagram.com/reels/C7W7d6GStYA/`
- `notes` (optional) — free-text from the user about what they think the format is or why they care

## Output

One markdown beat-sheet at `research/marketing/reel-format-breakdowns/<handle>-<shortcode>-<YYYY-MM-DD>.md` in the **parent workspace** (cross-project research), plus a sibling working directory `research/marketing/reel-format-breakdowns/<handle>-<shortcode>/` with all artifacts (MP4, audio, keyframes, JSON).

One row appended to `research/marketing/reel-format-breakdowns/index.md`.

## Pipeline (execute in order)

### 1. Parse URL and set up working directory

- Extract `shortcode` (e.g. `C7W7d6GStYA`) from the URL. It's between `/reels/` or `/reel/` or `/p/` and the trailing slash.
- Set `PARENT=<repo-root>`
- Set `DATE=$(date +%Y-%m-%d)`
- `WORKDIR="$PARENT/research/marketing/reel-format-breakdowns/PENDING-<shortcode>"` (rename to `<handle>-<shortcode>` after step 2 when handle is known)
- `mkdir -p "$WORKDIR/shots"`

### 2. Apify scrape

Use the Apify MCP:
- `mcp__Apify__call-actor` with `actor="apify/instagram-scraper"` and input:
  ```json
  {"directUrls": ["<reel_url>"], "resultsType": "posts", "resultsLimit": 1, "addParentData": false}
  ```
- Then `mcp__Apify__get-actor-output` to fetch results. Take the first item.
- Capture: `videoUrl`, `displayUrl`, `ownerUsername`, `caption`, `videoDuration`, `likesCount`, `commentsCount`, `videoViewCount`, `videoPlayCount`, `timestamp`, `type`.
- Validate `type == "Video"`. If not, abort with a clear error — this skill is Reels only.
- Write `$WORKDIR/scrape.json` with the full captured object.
- Rename working dir: `mv "$WORKDIR" "$PARENT/research/marketing/reel-format-breakdowns/<ownerUsername>-<shortcode>"`. Reassign `WORKDIR` to the new path.

### 3. Download media

The `videoUrl` from Apify is a CDN URL that expires in hours — download immediately in the same session.

```bash
curl -sSL -o "$WORKDIR/video.mp4" "<videoUrl>"
curl -sSL -o "$WORKDIR/cover-ig.jpg" "<displayUrl>"
```

Validate `video.mp4` is non-empty and playable: `ffprobe -v error "$WORKDIR/video.mp4"` must exit 0.

### 4. First-frame grab

```bash
ffmpeg -y -i "$WORKDIR/video.mp4" -vframes 1 -q:v 2 "$WORKDIR/cover-frame0.jpg"
```

### 5. Shot-boundary detection

Run scene-change detection at threshold 0.3 (empirically good for IG Reels, which have harder cuts than cinema):

```bash
ffmpeg -i "$WORKDIR/video.mp4" -filter:v "select='gt(scene,0.3)',showinfo" -vsync vfr -f null - 2> "$WORKDIR/shots.log"
```

Parse `shots.log` stderr for lines containing `Parsed_showinfo` and extract `pts_time:<float>` values. These are the start-times of each new shot (after the first, which starts at 0.0). Write `$WORKDIR/shot_boundaries.json`:

```json
{
  "total_duration_s": <from ffprobe>,
  "boundaries": [
    {"index": 0, "t_start": 0.0, "t_end": 2.1},
    {"index": 1, "t_start": 2.1, "t_end": 4.3},
    ...
  ]
}
```

**Fallback:** If fewer than 3 boundaries detected, fall back to fixed 2.0s interval sampling across the full duration. Flag `detection_mode: "interval"` in the JSON so downstream knows.

### 6. Keyframe extraction

For each shot boundary, grab one representative frame at the midpoint of that shot:

```bash
for each shot i with midpoint t_mid:
  ffmpeg -y -ss "$t_mid" -i "$WORKDIR/video.mp4" -vframes 1 -q:v 2 "$WORKDIR/shots/shot-$(printf %03d $i).png"
```

Use a helper script `scripts/extract_shots.sh` to do this (provided in this skill's `scripts/` directory).

### 7. Audio extraction + whisper

```bash
ffmpeg -y -i "$WORKDIR/video.mp4" -vn -acodec mp3 "$WORKDIR/audio.mp3"
mlx_whisper "$WORKDIR/audio.mp3" \
  --model mlx-community/whisper-large-v3-turbo \
  --output-format json \
  --output-dir "$WORKDIR" \
  --output-name audio
```

Produces `$WORKDIR/audio.json` with segment-level timestamps.

### 8. Gemini File API pass

Invoke the Python helper with the MP4, the shot boundaries JSON, the audio JSON, and the prompt file:

```bash
cd /tmp/gemini-smoke && source .venv/bin/activate && \
  python "$SKILL_DIR/scripts/analyze_video.py" \
    "$WORKDIR/video.mp4" \
    "$WORKDIR/shot_boundaries.json" \
    "$WORKDIR/audio.json" \
    "$SKILL_DIR/prompts/gemini_breakdown.txt" \
    "$WORKDIR/breakdown.json"
```

Where `$SKILL_DIR` is this skill's directory. The helper:
- Uploads the MP4 to Gemini File API
- Polls until ACTIVE
- Loads the shot_boundaries + audio JSON and embeds them in the prompt as context
- Calls `gemini-2.5-pro` with the MP4 file reference + prompt
- Falls back to `gemini-2.5-flash` on 503
- Writes the parsed JSON response to `breakdown.json`

### 9. Assemble markdown

Invoke `scripts/build_markdown.py`:

```bash
python "$SKILL_DIR/scripts/build_markdown.py" \
  "$WORKDIR/breakdown.json" \
  "$WORKDIR/scrape.json" \
  "$PARENT/research/marketing/reel-format-breakdowns/<handle>-<shortcode>-<DATE>.md"
```

The script reads both JSONs and emits the markdown template (see this skill's `prompts/markdown_template.md` for the exact shape).

### 10. Append to index

Append one row to `research/marketing/reel-format-breakdowns/index.md`:

```markdown
| 2026-04-22 | @handle | C7W7d6GStYA | face-cam → real-broll → generated-broll → repeat | 123.4k | [breakdown](handle-C7W7d6GStYA-2026-04-22.md) |
```

### 11. Report

Return a status line only. Not the full breakdown. Example:

> Breakdown complete: @handle / C7W7d6GStYA. 14 shots, archetype "face-cam → real-broll → generated-broll → repeat". Markdown: `research/marketing/reel-format-breakdowns/handle-C7W7d6GStYA-2026-04-22.md`. Open in Obsidian to review.

## Failure modes

- **Apify returns empty** — the URL may be private, deleted, or region-blocked. Abort with a message telling the user to verify the URL opens in a logged-out browser.
- **CDN URL 403/404** — the `videoUrl` expired. Re-scrape (rerun step 2) to get a fresh URL.
- **Gemini 503 on Pro** — fall back to Flash automatically in `analyze_video.py`.
- **Gemini upload stuck >5min in PROCESSING** — abort and retry once. If still stuck, abort the run with `breakdown.json: {"error": "upload_stuck"}` and a markdown report noting the failure (user can retry later).
- **Whisper produces empty transcript** — the Reel may be silent / music-only. That's fine — `breakdown.json` will have empty `narration` fields per shot and `on_screen_caption` will carry the weight.
- **Scene detection returns 0 boundaries** — fall back to 2.0s fixed interval (step 5 fallback).
- **handle contains special chars** — sanitize: strip `@`, replace any non-alphanumeric with `-`.

## Do not

- Do not extend `intelligence-agent` or write to Notion (Content Pipeline / Scrape Runs). This skill's output is a cross-project markdown reference, not a content candidate.
- Do not use the `gemini` CLI for video — it hallucinates on non-YouTube URLs. Use the Python SDK via File API.
- Do not process more than one Reel per invocation. If the user provides multiple URLs, run the skill once per URL sequentially.
- Do not commit the raw `video.mp4` or `audio.mp3` — add to gitignore. Keep JSON + PNGs + markdown versioned only.
