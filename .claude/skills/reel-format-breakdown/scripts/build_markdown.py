#!/usr/bin/env python3
"""Render the final markdown beat-sheet from breakdown.json + scrape.json.

Usage: build_markdown.py <breakdown.json> <scrape.json> <out.md> <workdir_rel>

workdir_rel is the relative path from the markdown file's directory to the working directory
(e.g. 'handle-shortcode') so image references in the markdown resolve correctly.
"""
import json
import sys
from pathlib import Path


def esc(s: str) -> str:
    if not s:
        return ""
    return s.replace("|", "\\|").replace("\n", " ").strip()


def main():
    breakdown_path, scrape_path, out_path, workdir_rel = sys.argv[1:5]
    breakdown = json.loads(Path(breakdown_path).read_text())
    scrape = json.loads(Path(scrape_path).read_text())

    handle = scrape.get("ownerUsername", "unknown")
    shortcode = scrape.get("shortCode", "unknown")
    url = scrape.get("url") or f"https://www.instagram.com/reels/{shortcode}/"
    likes = scrape.get("likesCount", 0)
    comments = scrape.get("commentsCount", 0)
    plays = scrape.get("videoPlayCount") or scrape.get("videoViewCount") or 0
    caption = scrape.get("caption", "") or ""
    posted = scrape.get("timestamp", "")

    cover = breakdown.get("cover", {})
    archetype = breakdown.get("format_archetype", "unknown")
    duration = breakdown.get("total_duration_s", 0)
    shots = breakdown.get("shots", [])
    pattern = breakdown.get("pattern_summary", "")
    checklist = breakdown.get("replication_checklist", [])

    lines = []
    lines.append(f"---")
    lines.append(f"source_url: {url}")
    lines.append(f"owner: '@{handle}'")
    lines.append(f"shortcode: {shortcode}")
    stem_parts = Path(out_path).stem.split("-")
    scraped_date = "-".join(stem_parts[-3:]) if len(stem_parts) >= 3 else ""
    lines.append(f"scraped: {scraped_date}")
    lines.append(f"duration_s: {duration}")
    lines.append(f"format_archetype: \"{archetype}\"")
    lines.append(f"likes: {likes}")
    lines.append(f"comments: {comments}")
    lines.append(f"plays: {plays}")
    lines.append(f"posted: {posted}")
    lines.append(f"---")
    lines.append("")
    lines.append(f"# Reel format breakdown — @{handle} / {shortcode}")
    lines.append("")
    lines.append(f"**Source:** {url}  ")
    lines.append(f"**Duration:** {duration}s · **Likes:** {likes:,} · **Comments:** {comments:,} · **Plays:** {plays:,}  ")
    lines.append(f"**Format archetype:** `{archetype}`")
    lines.append("")
    lines.append("## Caption")
    lines.append("")
    lines.append("> " + (caption.replace("\n", "\n> ") if caption else "_(empty)_"))
    lines.append("")
    lines.append("## Cover")
    lines.append("")
    lines.append(f"![feed thumbnail]({workdir_rel}/cover-ig.jpg)")
    lines.append(f"![opening frame]({workdir_rel}/cover-frame0.jpg)")
    lines.append("")
    lines.append(f"- **Description:** {cover.get('description','')}")
    lines.append(f"- **Hook mechanism:** {cover.get('hook_mechanism','')}")
    lines.append(f"- **Text overlay:** {cover.get('text_overlay','') or '_(none)_'}")
    lines.append("")
    lines.append("## Shot-by-shot")
    lines.append("")
    for s in shots:
        idx = s.get("index", 0)
        t0 = s.get("t_start", 0)
        t1 = s.get("t_end", 0)
        cat = s.get("category", "?")
        role = s.get("format_role", "?")
        lines.append(f"### Shot {idx:02d} · {t0:.1f}s–{t1:.1f}s · `{cat}` · role: `{role}`")
        lines.append("")
        kf = s.get("keyframe_path", f"shots/shot-{idx:03d}.png")
        lines.append(f"![shot {idx}]({workdir_rel}/{kf})")
        lines.append("")
        cap = s.get("on_screen_caption", "")
        narr = s.get("narration", "")
        vis = s.get("visual_description", "")
        lines.append(f"- **Caption (on-screen):** {cap or '_(none)_'}")
        lines.append(f"- **Narration:** {narr or '_(silent / music only)_'}")
        lines.append(f"- **Visual:** {vis}")
        if s.get("caption_confidence") == "low":
            lines.append(f"- **⚠️  Low caption confidence** — verify manually")
        if s.get("merged_from_indices"):
            lines.append(f"- **Merged from shots:** {s['merged_from_indices']}")
        lines.append("")
    lines.append("## Pattern summary")
    lines.append("")
    lines.append(pattern)
    lines.append("")
    lines.append("## Replication checklist")
    lines.append("")
    for item in checklist:
        lines.append(f"- [ ] {item}")
    lines.append("")
    lines.append("## Raw artifacts")
    lines.append("")
    lines.append(f"- MP4 (gitignored): `{workdir_rel}/video.mp4`")
    lines.append(f"- Audio (gitignored): `{workdir_rel}/audio.mp3`")
    lines.append(f"- Transcript JSON: `{workdir_rel}/audio.json`")
    lines.append(f"- Shot boundaries: `{workdir_rel}/shot_boundaries.json`")
    lines.append(f"- Full breakdown JSON: `{workdir_rel}/breakdown.json`")
    lines.append(f"- Apify scrape JSON: `{workdir_rel}/scrape.json`")
    lines.append("")

    Path(out_path).write_text("\n".join(lines))
    print(f"wrote {out_path} ({len(shots)} shots)")


if __name__ == "__main__":
    main()
