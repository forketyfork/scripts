#!/usr/bin/env bash
set -euo pipefail

# yt-transcript.sh — Fetch auto-generated captions from a YouTube video.
#
# Usage: yt-transcript.sh <youtube-url> [language]
#   language  BCP-47 code (default: en)
#
# Prints the video header (title | channel | duration) to stderr and the
# cleaned transcript to stdout, so the output can be piped or redirected.

usage() {
	cat <<'EOF'
Usage: yt-transcript.sh <youtube-url> [language]

Fetches auto-generated captions for a YouTube video using yt-dlp and
prints the cleaned transcript to stdout.

Arguments:
  youtube-url  YouTube video URL (watch, youtu.be, or Shorts)
  language     BCP-47 language code (default: en)

Examples:
  yt-transcript.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  yt-transcript.sh "https://youtu.be/dQw4w9WgXcQ" de
EOF
	exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
	usage
fi

readonly url="$1"
readonly lang="${2:-en}"

if ! command -v yt-dlp >/dev/null 2>&1; then
	echo "Error: yt-dlp is not installed." >&2
	exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Print metadata to stderr
yt-dlp --skip-download --print "%(title)s | %(channel)s | %(duration_string)s" "$url" >&2

# Download auto-generated captions; some videos serve the native-language track as
# HLS m3u8 with CSS cue styling that trips yt-dlp's VTT merger (exit 1, no file).
yt-dlp \
	--skip-download \
	--write-auto-subs \
	--sub-lang "$lang" \
	--sub-format vtt \
	--output "$tmp_dir/%(id)s.%(ext)s" \
	"$url" >/dev/null 2>&1 || true

sub_file=$(find "$tmp_dir" -name "*.vtt" | head -n1)

# Fallback: the translated-back variant (e.g. de-de-*) is delivered as a plain
# file rather than HLS and avoids the parse error.
if [[ -z "$sub_file" ]]; then
	yt-dlp \
		--skip-download \
		--write-auto-subs \
		--sub-lang "${lang}-.*" \
		--sub-format srt \
		--output "$tmp_dir/%(id)s.%(ext)s" \
		"$url" >/dev/null 2>&1 || true
	sub_file=$(find "$tmp_dir" -name "*.srt" | head -n1)
fi

if [[ -z "$sub_file" ]]; then
	echo "Error: no auto-generated captions found for language '$lang'." >&2
	exit 1
fi

# Strip HTML tags, remove VTT/SRT metadata/timestamps/blank lines, deduplicate
if [[ "$sub_file" == *.vtt ]]; then
	sed 's/<[^>]*>//g' "$sub_file" |
		grep -v '^WEBVTT\|^Style\|cue\|^Kind:\|^Language:\|^##\|^\s*$\|-->\|^[0-9][0-9]:[0-9][0-9]' |
		awk '!seen[$0]++'
else
	grep -Ev '^[[:space:]]*[0-9]+[[:space:]]*$|-->|^[[:space:]]*$' "$sub_file" |
		awk '!seen[$0]++'
fi
