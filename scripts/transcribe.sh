#!/usr/bin/env bash
# transcribe.sh — Transcribe audio files using local mlx-whisper (Apple Silicon, free)
#
# Usage:
#   ./scripts/transcribe.sh <audio-file-or-dir> [output-dir] [--format txt|json]
#
# Examples:
#   ./scripts/transcribe.sh ~/Downloads/voice-note.opus
#   ./scripts/transcribe.sh ~/Downloads/voice-note.opus research/meetings
#   ./scripts/transcribe.sh ~/Downloads/voice-note.opus research/meetings --format json
#   ./scripts/transcribe.sh ~/Downloads/WhatsApp\ Audio/  research/meetings
#
# Outputs a .txt transcript (default) or .json (with segment timestamps) alongside the audio
# or in the specified output dir.
# Supported formats: .opus, .mp3, .m4a, .wav, .ogg, .flac, .webm
#
# Model options (set MLX_WHISPER_MODEL env var to override):
#   mlx-community/whisper-large-v3-turbo   (default: best quality/speed balance, ~800MB)
#   mlx-community/whisper-small             (fastest, smaller, less accurate)
#   mlx-community/whisper-large-v3          (highest accuracy, slower)

set -euo pipefail

MODEL="${MLX_WHISPER_MODEL:-mlx-community/whisper-large-v3-turbo}"
AUDIO_EXTENSIONS="opus|mp3|m4a|wav|ogg|flac|webm"
FORMAT="txt"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <audio-file-or-dir> [output-dir] [--format txt|json]" >&2
  exit 1
fi

INPUT="$1"
shift
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --format=*)
      FORMAT="${1#*=}"
      shift
      ;;
    *)
      if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$1"
        shift
      else
        echo "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ "$FORMAT" != "txt" && "$FORMAT" != "json" ]]; then
  echo "--format must be 'txt' or 'json' (got '$FORMAT')" >&2
  exit 1
fi

# Collect files to process
FILES=()
if [[ -d "$INPUT" ]]; then
  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(find "$INPUT" -maxdepth 1 -type f -regextype awk -regex ".*\.(${AUDIO_EXTENSIONS})" -print0 | sort -z)
  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No audio files found in $INPUT" >&2
    exit 1
  fi
else
  FILES=("$INPUT")
fi

echo "Transcribing ${#FILES[@]} file(s) with model: $MODEL"
echo ""

for FILE in "${FILES[@]}"; do
  BASENAME=$(basename "$FILE")
  NAME="${BASENAME%.*}"

  if [[ -n "$OUTPUT_DIR" ]]; then
    DEST="$OUTPUT_DIR"
  else
    DEST="$(dirname "$FILE")"
  fi

  mkdir -p "$DEST"

  echo "  -> $BASENAME"

  mlx_whisper "$FILE" \
    --model "$MODEL" \
    --output-format "$FORMAT" \
    --output-dir "$DEST" \
    --output-name "$NAME" \
    2>&1 | grep -v "^$" | sed 's/^/     /'

  OUTFILE="$DEST/${NAME}.${FORMAT}"
  if [[ -f "$OUTFILE" ]]; then
    if [[ "$FORMAT" == "txt" ]]; then
      WORDS=$(wc -w < "$OUTFILE")
      echo "     saved: $OUTFILE ($WORDS words)"
    else
      echo "     saved: $OUTFILE"
    fi
  fi
  echo ""
done

echo "Done. Transcripts written to: ${OUTPUT_DIR:-<same dir as input>}"
