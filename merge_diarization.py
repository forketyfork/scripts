#!/usr/bin/env python3
"""Merges speaker diarization data with Whisper transcript to create speaker-attributed text.

Combines timing data from diarization with transcript text from SRT files.
Outputs markdown format with speaker labels for each text segment.

Usage:
  python merge_diarization.py diarization.txt output.srt YYYY-MM-DD audio_filename

Creates a markdown file named "YYYY-MM-DD audio_filename.md" with content like:
  [[SPEAKER_01]]: Hallo, hallo
  [[SPEAKER_00]]: Halli hallo!
"""

import argparse
import os
import re
import sys
from typing import Iterator, List, Tuple

TIME_RE = re.compile(
    r"(\d{2}):(\d{2}):(\d{2}),(\d{3})"  # HH:MM:SS,mmm
)

DIAR_RE = re.compile(
    r"(\d+(?:\.\d{1,3})?)s\s*-\s*(\d+(?:\.\d{1,3})?)s:\s*(\S+)"  # 0.000s - 3.142s: SPEAKER_01
)

def hms_to_seconds(h: str, m: str, s: str, ms: str) -> float:
    """Convert hours, minutes, seconds, milliseconds to total seconds."""
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0


def parse_srt(path: str) -> Iterator[Tuple[float, float, str]]:
    """Yield (start_seconds, end_seconds, text) for each caption block."""
    if not os.path.isfile(path):
        print(f"Error: SRT file '{path}' not found.", file=sys.stderr)
        sys.exit(1)
        
    try:
        with open(path, encoding="utf-8") as f:
            block = []
            for line in f:
                if line.strip():
                    block.append(line.rstrip("\n"))
                    continue

                # blank line → end of block
                if block:
                    # block[1] is the timing line, rest is text
                    timing_parts = block[1].split("-->")
                    start_match = TIME_RE.match(timing_parts[0].strip())
                    end_match = TIME_RE.match(timing_parts[1].strip())
                    if not start_match or not end_match:
                        raise ValueError(f"Bad SRT time in block: {block}")
                    start_secs = hms_to_seconds(*start_match.groups())
                    end_secs = hms_to_seconds(*end_match.groups())
                    text = " ".join(line.strip() for line in block[2:])
                    yield start_secs, end_secs, text
                    block = []

            # handle last block (EOF w/o trailing newline)
            if block:
                timing_parts = block[1].split("-->")
                start_match = TIME_RE.match(timing_parts[0].strip())
                end_match = TIME_RE.match(timing_parts[1].strip())
                start_secs = hms_to_seconds(*start_match.groups())
                end_secs = hms_to_seconds(*end_match.groups())
                text = " ".join(line.strip() for line in block[2:])
                yield start_secs, end_secs, text
    except (OSError, UnicodeDecodeError) as e:
        print(f"Error reading SRT file '{path}': {e}", file=sys.stderr)
        sys.exit(1)


def parse_diar(path: str) -> List[Tuple[float, float, str]]:
    """Return list of (start, end, speaker) sorted by start time."""
    if not os.path.isfile(path):
        print(f"Error: Diarization file '{path}' not found.", file=sys.stderr)
        sys.exit(1)
        
    segments = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                m = DIAR_RE.match(line)
                if not m:
                    continue
                start, end, spk = m.groups()
                segments.append((float(start), float(end), spk))
    except (OSError, UnicodeDecodeError) as e:
        print(f"Error reading diarization file '{path}': {e}", file=sys.stderr)
        sys.exit(1)
        
    segments.sort(key=lambda t: t[0])
    return segments


def join_consecutive_speaker_intervals(
    segments: List[Tuple[float, float, str]]
) -> List[Tuple[float, float, str]]:
    """Merge consecutive segments from same speaker to reduce fragmentation."""
    if not segments:
        return []
    
    joined = []
    current_start, current_end, current_speaker = segments[0]
    
    for start, end, speaker in segments[1:]:
        if speaker == current_speaker:
            # Same speaker, extend interval regardless of gaps
            current_end = max(current_end, end)
        else:
            # Different speaker, save current and start new
            joined.append((current_start, current_end, current_speaker))
            current_start, current_end, current_speaker = start, end, speaker
    
    # Add the last interval
    joined.append((current_start, current_end, current_speaker))
    return joined


def find_speaker_for_interval(
    srt_start: float,
    srt_end: float,
    diar_segments: List[Tuple[float, float, str]]
) -> str:
    """Match transcript segment to speaker by finding best time overlap."""
    best_speaker = "UNKNOWN"
    max_intersection = 0.0
    
    for diar_start, diar_end, speaker in diar_segments:
        # Find time overlap between transcript and speaker segments
        intersection_start = max(srt_start, diar_start)
        intersection_end = min(srt_end, diar_end)
        
        if intersection_start < intersection_end:
            # Intervals intersect
            intersection_size = intersection_end - intersection_start
            if intersection_size > max_intersection:
                max_intersection = intersection_size
                best_speaker = speaker
    
    # Fall back to last speaker if transcript is after all diarization data
    if best_speaker == "UNKNOWN" and diar_segments:
        last_diar_end = max(seg[1] for seg in diar_segments)
        if srt_start >= last_diar_end:
            # SRT interval is after all diarized intervals, use last speaker
            best_speaker = diar_segments[-1][2]
    
    return best_speaker


def merge(diar_path: str, srt_path: str, output_path: str) -> None:
    segments = parse_diar(diar_path)
    joined_segments = join_consecutive_speaker_intervals(segments)
    
    current_speaker = None
    current_text = []
    output_lines = []
    
    for srt_start, srt_end, text in parse_srt(srt_path):
        speaker = find_speaker_for_interval(srt_start, srt_end, joined_segments)
        
        if speaker == current_speaker and current_speaker is not None:
            # Same speaker, accumulate text
            current_text.append(text.strip())
        else:
            # Speaker changed - output accumulated text and start new segment
            if current_speaker is not None:
                # Clean up whitespace in accumulated text
                joined_text = ' '.join(current_text)
                cleaned_text = ' '.join(joined_text.split())
                output_lines.append(f"[[{current_speaker}]]: {cleaned_text}")
            current_speaker = speaker
            current_text = [text.strip()]
    
    # Output final speaker segment
    if current_speaker is not None:
        # Clean up whitespace in final text
        joined_text = ' '.join(current_text)
        cleaned_text = ' '.join(joined_text.split())
        output_lines.append(f"[[{current_speaker}]]: {cleaned_text}")
    
    # Write to output file
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            for line in output_lines:
                f.write(line + '\n')
    except OSError as e:
        print(f"Error writing output file '{output_path}': {e}", file=sys.stderr)
        sys.exit(1)
    
    print(f"Output written to: {output_path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Merge diarization and SRT")
    ap.add_argument("diarization", help="Text file with '0.0s - 3.1s: SPEAKER_X'")
    ap.add_argument("srt", help="Whisper .srt transcription file")
    ap.add_argument("date", help="Recording date in YYYY-MM-DD format")
    ap.add_argument("audio_filename", help="Original audio filename (without extension)")
    args = ap.parse_args()
    
    # Generate output filename
    output_filename = f"{args.date} {args.audio_filename}.md"
    
    merge(args.diarization, args.srt, output_filename)
