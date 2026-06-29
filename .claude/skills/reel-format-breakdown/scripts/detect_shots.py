#!/usr/bin/env python3
"""Run ffmpeg scene-change detection and emit shot_boundaries.json.

Usage: detect_shots.py <video.mp4> <out.json>

Uses scene threshold 0.3. Falls back to fixed 2.0s interval if fewer than 3 boundaries detected.
"""
import json
import re
import subprocess
import sys
from pathlib import Path


def ffprobe_duration(video: str) -> float:
    out = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", video],
        text=True,
    )
    return float(out.strip())


def detect_scene_changes(video: str, threshold: float = 0.3) -> list[float]:
    proc = subprocess.run(
        ["ffmpeg", "-i", video, "-filter:v",
         f"select='gt(scene,{threshold})',showinfo",
         "-vsync", "vfr", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    times = []
    for line in proc.stderr.splitlines():
        m = re.search(r"pts_time:([\d.]+)", line)
        if m and "Parsed_showinfo" in line:
            times.append(float(m.group(1)))
    return sorted(set(times))


def build_interval_fallback(duration: float, interval: float = 2.0) -> list[float]:
    times = []
    t = interval
    while t < duration:
        times.append(t)
        t += interval
    return times


def main():
    video, out_path = sys.argv[1], sys.argv[2]
    duration = ffprobe_duration(video)
    scene_starts = detect_scene_changes(video)
    mode = "scene"
    # If scene detection is sparse or any resulting shot would exceed 8s, merge in interval sampling
    combined = sorted(set(scene_starts))
    max_gap = max(
        [combined[0]] + [combined[i+1] - combined[i] for i in range(len(combined)-1)] + [duration - (combined[-1] if combined else 0)]
    ) if combined else duration
    if len(combined) < 5 or max_gap > 8.0:
        interval = build_interval_fallback(duration, interval=2.0)
        combined = sorted(set(combined + interval))
        mode = "scene+interval" if scene_starts else "interval"
    starts = combined
    all_starts = [0.0] + starts
    # Deduplicate and sort
    all_starts = sorted(set(round(t, 3) for t in all_starts))
    boundaries = []
    for i, t_start in enumerate(all_starts):
        t_end = all_starts[i + 1] if i + 1 < len(all_starts) else duration
        if t_end - t_start < 0.3:  # skip shots shorter than 0.3s (detection noise)
            continue
        boundaries.append({
            "index": len(boundaries),
            "t_start": round(t_start, 3),
            "t_end": round(t_end, 3),
            "duration_s": round(t_end - t_start, 3),
        })
    data = {
        "total_duration_s": round(duration, 3),
        "detection_mode": mode,
        "scene_threshold": 0.3 if mode == "scene" else None,
        "interval_s": 2.0 if mode == "interval" else None,
        "boundaries": boundaries,
    }
    Path(out_path).write_text(json.dumps(data, indent=2))
    print(f"{len(boundaries)} shots detected (mode={mode}, duration={duration:.1f}s)")


if __name__ == "__main__":
    main()
