#!/usr/bin/env python3
"""Upload Reel MP4 to Gemini File API and extract a shot-by-shot format breakdown as JSON.

Usage: analyze_video.py <video.mp4> <shot_boundaries.json> <audio.json> <prompt.txt> <out.json>

Requires GEMINI_API_KEY in environment or in
  <repo-root>/.env
Uses gemini-2.5-pro primary with gemini-2.5-flash fallback on 503.
"""
import json
import os
import re
import sys
import time
from pathlib import Path


def load_api_key() -> None:
    if os.environ.get("GEMINI_API_KEY"):
        return
    env_path = Path(__file__).resolve().parents[3] / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("GEMINI_API_KEY="):
                val = line.split("=", 1)[1].strip().strip('"').strip("'")
                os.environ["GEMINI_API_KEY"] = val
                return
    raise SystemExit("GEMINI_API_KEY not found in env or parent .env")


def extract_json(text: str) -> dict:
    """Pull the first JSON object out of a Gemini response (handles fenced blocks)."""
    fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fence:
        return json.loads(fence.group(1))
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        return json.loads(text[start:end + 1])
    raise ValueError("No JSON object found in Gemini response")


def main():
    video_path, bounds_path, audio_path, prompt_path, out_path = sys.argv[1:6]
    load_api_key()
    from google import genai
    from google.genai import errors as genai_errors

    client = genai.Client()

    print(f"[1/5] uploading {video_path} ...", flush=True)
    t0 = time.time()
    f = client.files.upload(file=video_path)
    print(f"  uploaded: {f.name} state={f.state} ({time.time()-t0:.1f}s)", flush=True)

    print("[2/5] polling until ACTIVE ...", flush=True)
    start_poll = time.time()
    while f.state.name == "PROCESSING":
        if time.time() - start_poll > 300:
            raise SystemExit("Gemini upload stuck in PROCESSING >5min, aborting")
        time.sleep(2)
        f = client.files.get(name=f.name)
    print(f"  final: {f.state.name} ({time.time()-t0:.1f}s)", flush=True)
    if f.state.name != "ACTIVE":
        raise SystemExit(f"Gemini file not ACTIVE: {f.state.name}")

    prompt_template = Path(prompt_path).read_text()
    bounds = json.loads(Path(bounds_path).read_text())
    audio = json.loads(Path(audio_path).read_text())

    audio_segments = []
    for seg in audio.get("segments", []):
        audio_segments.append({
            "t_start": round(seg.get("start", 0.0), 3),
            "t_end": round(seg.get("end", 0.0), 3),
            "text": seg.get("text", "").strip(),
        })

    prompt = prompt_template.replace(
        "{{SHOT_BOUNDARIES_JSON}}", json.dumps(bounds, indent=2)
    ).replace(
        "{{AUDIO_SEGMENTS_JSON}}", json.dumps(audio_segments, indent=2)
    )

    for model_name in ("gemini-2.5-pro", "gemini-2.5-flash"):
        print(f"[3/5] calling {model_name} ...", flush=True)
        t1 = time.time()
        try:
            resp = client.models.generate_content(model=model_name, contents=[f, prompt])
            print(f"  ({time.time()-t1:.1f}s)", flush=True)
            break
        except genai_errors.APIError as e:
            print(f"  {model_name} failed: {e}", flush=True)
            if model_name == "gemini-2.5-flash":
                raise
            continue

    text = resp.text
    print("[4/5] parsing response ...", flush=True)
    data = extract_json(text)
    data["_meta"] = {
        "model": model_name,
        "elapsed_s": round(time.time() - t0, 1),
        "raw_response_preview": text[:400],
    }

    print(f"[5/5] writing {out_path}", flush=True)
    Path(out_path).write_text(json.dumps(data, indent=2))
    print(f"TOTAL: {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()
