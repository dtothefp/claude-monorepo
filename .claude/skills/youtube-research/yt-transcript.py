#!/usr/bin/env python3
"""
Fetch a YouTube transcript and print cleaned text to stdout.

Usage:
    python3 yt-transcript.py VIDEO_ID_OR_URL [--lang en] [--timestamps]

Accepts:
    - 11-char video ID: wLdb3FHn7BA
    - Full URL: https://www.youtube.com/watch?v=wLdb3FHn7BA
    - Short URL: https://youtu.be/wLdb3FHn7BA

Requires: pip install youtube-transcript-api
"""

from __future__ import annotations

import argparse
import re
import sys
from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api._errors import (
    TranscriptsDisabled,
    NoTranscriptFound,
    VideoUnavailable,
    RequestBlocked,
    YouTubeRequestFailed,
)


def extract_video_id(input_str: str) -> str:
    """Extract 11-char video ID from a URL or return the input if it's already an ID."""
    patterns = [
        r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/)([A-Za-z0-9_-]{11})',
        r'^([A-Za-z0-9_-]{11})$',
    ]
    for pattern in patterns:
        m = re.search(pattern, input_str.strip())
        if m:
            return m.group(1)
    print(f"Error: could not extract a YouTube video ID from: {input_str}", file=sys.stderr)
    sys.exit(1)


def clean_text(text: str) -> str:
    text = re.sub(r'\[.*?\]', '', text)
    text = re.sub(r'\s+', ' ', text)
    return text.strip()


def fetch(video_id: str, languages: list[str], timestamps: bool) -> str:
    api = YouTubeTranscriptApi()
    transcript = api.fetch(video_id=video_id, languages=languages)
    if timestamps:
        lines = []
        for s in transcript.snippets:
            mins = int(s.start // 60)
            secs = int(s.start % 60)
            lines.append(f"[{mins:02d}:{secs:02d}] {clean_text(s.text)}")
        return '\n'.join(lines)
    else:
        return ' '.join(clean_text(s.text) for s in transcript.snippets)


def main() -> None:
    parser = argparse.ArgumentParser(description='Fetch YouTube transcript to stdout')
    parser.add_argument('video', help='YouTube video ID or URL')
    parser.add_argument('--lang', nargs='+', default=['en'], metavar='LANG',
                        help='Language priority list (default: en)')
    parser.add_argument('--timestamps', action='store_true',
                        help='Include [MM:SS] timestamps')
    args = parser.parse_args()

    video_id = extract_video_id(args.video)

    try:
        text = fetch(video_id, args.lang, args.timestamps)
        print(text)
    except TranscriptsDisabled:
        print(f"Error: transcripts are disabled for {video_id}", file=sys.stderr)
        sys.exit(1)
    except NoTranscriptFound:
        print(f"Error: no transcript found in {args.lang} for {video_id}", file=sys.stderr)
        sys.exit(1)
    except VideoUnavailable:
        print(f"Error: video {video_id} is unavailable", file=sys.stderr)
        sys.exit(1)
    except (RequestBlocked, YouTubeRequestFailed) as e:
        print(f"Error: YouTube blocked the request — {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
