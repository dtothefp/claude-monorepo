#!/usr/bin/env bash
# extract_shots.sh — Given video.mp4 + shot_boundaries.json, extract one keyframe per shot midpoint.
# Usage: extract_shots.sh <video.mp4> <shot_boundaries.json> <out_dir>
set -euo pipefail

VIDEO="$1"
BOUNDS="$2"
OUT="$3"

mkdir -p "$OUT"

python3 - "$VIDEO" "$BOUNDS" "$OUT" <<'PY'
import json, os, subprocess, sys
video, bounds_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
with open(bounds_path) as f:
    bounds = json.load(f)
for shot in bounds["boundaries"]:
    i = shot["index"]
    t_mid = (shot["t_start"] + shot["t_end"]) / 2
    out = os.path.join(out_dir, f"shot-{i:03d}.png")
    subprocess.run(
        ["ffmpeg", "-y", "-ss", f"{t_mid:.3f}", "-i", video, "-vframes", "1", "-q:v", "2", out],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(f"shot-{i:03d}.png @ {t_mid:.2f}s")
PY
