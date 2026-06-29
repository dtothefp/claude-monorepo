# Transcribe Skill

## Description

Transcribes audio files (WhatsApp voice notes, meeting recordings, interviews)
to text using local mlx-whisper on Apple Silicon. Free, offline, no token cost.
Automatically routes the transcript into the research wiki via wiki-ingest.

## Triggers

- `/transcribe`
- "transcribe this audio"
- "transcribe these voice notes"
- User provides a path to an `.opus`, `.mp3`, `.m4a`, `.wav`, `.ogg`, or `.flac` file with intent to get text out of it

## Inputs

One of:
- **File path** — a single audio file (e.g. `~/Downloads/note.opus`)
- **Directory path** — a folder containing multiple audio files (batch mode)
- **No explicit path** — ask the user to provide the file path

Optional:
- **Output directory** — where to write the `.txt` transcript (defaults to same dir as audio)
- **Topic** — which `research/<topic>/` to file the transcript under for wiki-ingest
- **Project** — which child project to route the transcript to (if project-specific)

## Steps

### 1. Resolve the input

If the user's message contains a file path, use it directly. If it's a directory,
confirm batch processing all audio files in it. If no path given, ask:

> What file (or directory) do you want to transcribe?

### 2. Determine output destination

- If the transcript is project-specific: route to `packages/<project>/research/<topic>/`
- If cross-project or unspecified: route to `research/transcripts/` in the parent workspace
- Ask the user if neither is clear from context

### 3. Run the transcription

Call the script via Bash:

```bash
./scripts/transcribe.sh "<input-path>" "<output-dir>"
```

The script uses `mlx-whisper` with `mlx-community/whisper-large-v3-turbo` by default
(best quality/speed balance for Apple Silicon M-series). First run downloads the model
(~800MB, cached after that). Subsequent runs are fast.

To use a smaller/faster model:
```bash
MLX_WHISPER_MODEL=mlx-community/whisper-small ./scripts/transcribe.sh "<input>"
```

### 4. Report completion

Tell the user:
- Which files were transcribed
- Where the `.txt` files were saved
- Word count per transcript (from script output)

### 5. Offer wiki-ingest

After transcription, ask:

> Transcript saved. Want me to ingest it into the research wiki?

If yes (or if the user already indicated a topic), invoke the `wiki-ingest` skill
on the resulting `.txt` file(s), routing to the appropriate `research/<topic>/` directory.

Honor wiki governance: append to `research/log.md`, update `index.md` if the
transcript materially changes a topic conclusion.

## Notes

- The script handles batch processing when given a directory
- Transcripts are named `<original-filename>.txt`
- Supported formats: `.opus`, `.mp3`, `.m4a`, `.wav`, `.ogg`, `.flac`, `.webm`
- Model is cached in `~/.cache/huggingface/` after first download
- Override model with `MLX_WHISPER_MODEL` env var
- No API key needed, no internet required after first model download
