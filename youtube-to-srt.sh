#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# YouTube to SRT subtitle generation script
# Downloads YouTube video, extracts audio, and generates SRT subtitles using Whisper

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	cleanup_temp_files
	exit $ec
}
trap handle_error ERR

cleanup_temp_files() {
	if [[ -n "${video_file:-}" && -f "$video_file" ]]; then
		echo "Cleaning up video file..." >&2
		rm -f "$video_file"
	fi
	if [[ -n "${audio_file:-}" && -f "$audio_file" ]]; then
		echo "Cleaning up audio file..." >&2
		rm -f "$audio_file"
	fi
}
trap cleanup_temp_files EXIT

usage() {
	cat <<'EOF'
Usage: youtube-to-srt.sh <youtube-url> <language> [output-file]

Downloads a YouTube video and generates SRT subtitles using Whisper.

Arguments:
  youtube-url   YouTube video URL to download and transcribe
  language      Language code for transcription (e.g., en, de, ru)
  output-file   Optional: Output SRT file path (default: video-title.srt)

Examples:
  youtube-to-srt.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ" en
  youtube-to-srt.sh "https://youtu.be/dQw4w9WgXcQ" ru my-video.srt
EOF
	exit 1
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
	usage
fi

readonly youtube_url="$1"
readonly language="$2"
readonly output_srt="${3:-}"

# Check required tools
for tool in yt-dlp ffmpeg; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Error: Required tool '$tool' not found. Please install it first." >&2
		exit 1
	fi
done

# Check whisper setup
readonly whisper_cpp_path="$HOME/dev/github/ggml-org/whisper.cpp"
readonly whisper_model="${whisper_cpp_path}/models/ggml-large-v3.bin"
readonly whisper_bin="${whisper_cpp_path}/build/bin/whisper-cli"

if [[ ! -f "$whisper_bin" ]]; then
	echo "Error: whisper-cli binary not found at '$whisper_bin'" >&2
	echo "Please build whisper.cpp first or check the path." >&2
	exit 1
fi

if [[ ! -f "$whisper_model" ]]; then
	echo "Error: whisper model not found at '$whisper_model'" >&2
	echo "Please download the ggml-large-v3.bin model first." >&2
	exit 1
fi

# Store current working directory before creating temp dir
original_dir="$(pwd)"
readonly original_dir

# Create temporary directory for processing
temp_dir=$(mktemp -d)
readonly temp_dir
trap 'rm -rf "$temp_dir"' EXIT

pushd "$temp_dir" >/dev/null

# Download video using yt-dlp
echo "Downloading video from YouTube..." >&2
video_info=$(yt-dlp --print "%(title)s" "$youtube_url" 2>/dev/null | head -n1)
readonly video_info

# Clean up video title for filename
video_title=$(echo "$video_info" | tr '/' '-' | tr '[:space:]' '_' | sed 's/[^a-zA-Z0-9._-]//g')
readonly video_title

# Set output filename in original directory
if [[ -n "$output_srt" ]]; then
	# Use absolute path for provided output file
	if [[ "$output_srt" = /* ]]; then
		final_srt_file="$output_srt"
	else
		final_srt_file="${original_dir}/$output_srt"
	fi
else
	final_srt_file="${original_dir}/${video_title}.srt"
fi
readonly final_srt_file

echo "Video title: $video_info" >&2
echo "Output SRT file: $final_srt_file" >&2

# Download video file
yt-dlp -f "best[ext=mp4]/best" -o "video.%(ext)s" "$youtube_url" || {
	echo "Failed to download video from YouTube" >&2
	exit 1
}

# Find the downloaded video file
video_file=$(find . -name "video.*" -type f | head -n1)
readonly video_file

if [[ ! -f "$video_file" ]]; then
	echo "Error: Downloaded video file not found" >&2
	exit 1
fi

echo "Video downloaded successfully: $video_file" >&2

# Extract audio from video (16kHz mono WAV for Whisper)
readonly audio_file="audio.wav"
echo "Extracting audio from video..." >&2
ffmpeg -i "$video_file" -ac 1 -ar 16000 -y "$audio_file" || {
	echo "Failed to extract audio from video" >&2
	exit 1
}

echo "Audio extraction completed" >&2

# Generate subtitles using Whisper
echo "Generating subtitles with Whisper..." >&2
"$whisper_bin" \
	-m "$whisper_model" \
	-f "$audio_file" \
	--language "$language" \
	--entropy-thold 2.8 \
	--max-context 64 \
	--beam-size 5 \
	--output-srt \
	--output-file "output" || {
	echo "Failed to generate subtitles with Whisper" >&2
	exit 1
}

# Check if SRT file was created
if [[ -f "output.srt" ]]; then
	# Move SRT file to final location
	mv "output.srt" "$final_srt_file" || {
		echo "Failed to move SRT file to final location" >&2
		exit 1
	}
	echo "Subtitles generated successfully: $final_srt_file" >&2
else
	echo "Error: SRT file was not created by Whisper" >&2
	exit 1
fi

popd >/dev/null

echo "YouTube to SRT conversion completed successfully!" >&2
echo "Output: $final_srt_file" >&2
