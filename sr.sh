#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Complete speech recognition and diarization pipeline for audio files
# Converts audio to WAV, runs Whisper transcription, performs speaker diarization,
# and merges results into a markdown file with speaker attribution

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

cleanup_on_success() {
	# Remove intermediate files only on successful completion
	if [[ -f "$filename_wav" ]]; then
		echo "Cleaning up intermediate WAV file..." >&2
		rm -f "$filename_wav"
	fi
	if [[ -f "$srt_file" ]]; then
		echo "Cleaning up intermediate SRT file..." >&2
		rm -f "$srt_file"
	fi
	if [[ -f "$diarization_file" ]]; then
		echo "Cleaning up intermediate diarization file..." >&2
		rm -f "$diarization_file"
	fi
}

usage() {
	cat <<'EOF'
Usage: sr.sh <audio-file> <language>

Complete speech recognition and diarization pipeline for audio files.
Converts audio to WAV, runs Whisper transcription, performs speaker diarization,
and merges results into a markdown file with speaker attribution.

Arguments:
  audio-file  Path to the audio file to process
  language    Language code (e.g., en, de, ru)
EOF
	exit 1
}

if [[ $# -ne 2 ]]; then
	usage
fi

readonly audio_file="$1"
readonly language="$2"

if [[ ! -f "$audio_file" ]]; then
	echo "Error: Audio file '$audio_file' not found." >&2
	exit 1
fi

# Convert to absolute paths and extract file information
filename="$(cd "$(dirname "$audio_file")" && pwd)/$(basename "$audio_file")"
readonly filename
input_dir="$(dirname "$filename")"
readonly input_dir
basename_no_ext=$(basename "$filename" | sed 's/\.[^.]*$//')
readonly basename_no_ext

# Define output file paths in the input directory
readonly filename_wav="${filename}.wav"
readonly srt_file="${input_dir}/${basename_no_ext}.srt"
readonly diarization_file="${input_dir}/${basename_no_ext}_diarization.txt"

# Extract recording date from file modification time (cross-platform)
get_file_date() {
	local file="$1"
	# Test if we have GNU stat (supports --version) or BSD stat
	if stat --version >/dev/null 2>&1; then
		# GNU stat (Linux/Nix)
		stat -c "%y" "$file" | cut -d' ' -f1
	else
		# BSD stat (native macOS)
		stat -f "%Sm" -t "%Y-%m-%d" "$file"
	fi
}

recording_date=$(get_file_date "$filename")
readonly recording_date
readonly meetings_dir="$HOME/Zettelkasten/meetings"
readonly final_md_file="${meetings_dir}/${recording_date} ${basename_no_ext}.md"

# Set up working directory and cleanup handler
script_dir="$(cd "$(dirname "$0")" && pwd)"
readonly script_dir
readonly whisper_cpp_path="$HOME/dev/github/ggml-org/whisper.cpp"

if [[ ! -d "$whisper_cpp_path" ]]; then
	echo "Error: whisper.cpp directory not found at '$whisper_cpp_path'" >&2
	exit 1
fi

# Ensure the meetings directory exists
if [[ ! -d "$meetings_dir" ]]; then
	mkdir -p "$meetings_dir" || {
		echo "Error: Could not create meetings directory at '$meetings_dir'" >&2
		exit 1
	}
fi

pushd "$script_dir" >/dev/null
trap 'popd >/dev/null' EXIT

# Convert audio to format required by Whisper (16kHz mono WAV)
if [[ ! -f "$filename_wav" ]]; then
	echo "Converting to WAV format..." >&2
	ffmpeg -i "$filename" -ac 1 -ar 16000 "$filename_wav" || {
		echo "Failed to convert audio to WAV format" >&2
		exit 1
	}
else
	echo "WAV file already exists, skipping conversion" >&2
fi

# Run Whisper transcription with optimized settings for v3 model
readonly whisper_model="${whisper_cpp_path}/models/ggml-large-v3.bin"
readonly whisper_bin="${whisper_cpp_path}/build/bin/whisper-cli"

if [[ ! -f "$whisper_bin" ]]; then
	echo "Error: whisper-cli binary not found at '$whisper_bin'" >&2
	exit 1
fi

if [[ ! -f "$whisper_model" ]]; then
	echo "Error: whisper model not found at '$whisper_model'" >&2
	exit 1
fi

if [[ ! -f "$srt_file" ]]; then
	echo "Running speech recognition..." >&2
	# settings to avoid the v3 model repeating stuff, taken from https://github.com/ggml-org/whisper.cpp/issues/1507#issuecomment-1816263320
	"$whisper_bin" \
		-m "$whisper_model" \
		-f "$filename_wav" \
		--language "$language" \
		--entropy-thold 2.8 \
		--max-context 64 \
		--beam-size 5 \
		--output-srt \
		--output-file "${input_dir}/${basename_no_ext}" || {
		echo "Failed to run speech recognition" >&2
		exit 1
	}

	# Handle case where Whisper outputs to wrong directory
	if [[ ! -f "$srt_file" ]] && [[ -f "${basename_no_ext}.srt" ]]; then
		echo "Moving SRT file to correct location..." >&2
		mv "${basename_no_ext}.srt" "$srt_file" || {
			echo "Failed to move SRT file" >&2
			exit 1
		}
	fi
else
	echo "SRT file already exists, skipping speech recognition" >&2
fi

# Set up Python environment for diarization
if [[ ! -d "venv" ]]; then
	echo "Creating Python virtual environment..." >&2
	virtualenv venv --no-setuptools --no-wheel --activators bash || {
		echo "Failed to create virtual environment" >&2
		exit 1
	}
fi

# Activate virtual environment and install dependencies
echo "Activating virtual environment..." >&2
# shellcheck disable=SC1091  # venv/bin/activate is created at runtime by virtualenv
source ./venv/bin/activate || {
	echo "Failed to activate virtual environment" >&2
	exit 1
}

if ! pip show pyannote-audio >/dev/null 2>&1; then
	echo "Installing pyannote-audio..." >&2
	pip install pyannote-audio || {
		echo "Failed to install pyannote-audio" >&2
		exit 1
	}
fi

# Perform speaker diarization to identify who spoke when
readonly diarize_script="diarize.py"

if [[ ! -f "$diarize_script" ]]; then
	echo "Error: diarize.py script not found" >&2
	exit 1
fi

if [[ ! -f "$diarization_file" ]]; then
	echo "Running diarization..." >&2
	python3 "$diarize_script" "$filename_wav" >"$diarization_file" || {
		echo "Error: Diarization failed" >&2
		exit 1
	}
	echo "Diarization completed successfully" >&2
else
	echo "Diarization file already exists, skipping diarization" >&2
fi

# Combine transcript and speaker data into final markdown output
readonly merge_script="merge_diarization.py"

if [[ ! -f "$merge_script" ]]; then
	echo "Error: merge_diarization.py script not found" >&2
	exit 1
fi

if [[ ! -f "$final_md_file" ]]; then
	echo "Running merge..." >&2
	python3 "$merge_script" "$diarization_file" "$srt_file" "$recording_date" "$basename_no_ext" || {
		echo "Error: Merge failed" >&2
		exit 1
	}

	# Ensure output file is in the correct directory
	readonly temp_md_file="${recording_date} ${basename_no_ext}.md"
	if [[ -f "$temp_md_file" ]] && [[ "$temp_md_file" != "$final_md_file" ]]; then
		mv "$temp_md_file" "$final_md_file" || {
			echo "Failed to move output file to final location" >&2
			exit 1
		}
	fi
	echo "Merge completed successfully - output written to $final_md_file" >&2
else
	echo "Final merged file already exists, skipping merge" >&2
fi

# Clean up intermediate files on successful completion
cleanup_on_success

echo "Speech recognition and diarization pipeline completed successfully." >&2
