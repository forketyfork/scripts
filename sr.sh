#!/usr/bin/env bash
# Complete speech recognition and diarization pipeline for audio files
# Converts audio to WAV, runs Whisper transcription, performs speaker diarization,
# and merges results into a markdown file with speaker attribution

set -eu

# The script expects 2 arguments: file name and language, e.g., en, de, ru...
if [ $# != 2 ]; then
	printf "%b" "Expected 2 arguments: file name and language.\n" >&2
	exit 1
fi

# Convert to absolute paths and extract file information
filename="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
input_dir="$(dirname "$filename")"
basename_no_ext=$(basename "$filename" | sed 's/\.[^.]*$//')

# Define output file paths in the input directory
filename_wav="${filename}.wav"
srt_file="${input_dir}/${basename_no_ext}.srt"
diarization_file="${input_dir}/${basename_no_ext}_diarization.txt"

language="$2"
# Extract recording date from file modification time
recording_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$filename")
final_md_file="${input_dir}/${recording_date} ${basename_no_ext}.md"

# Set up working directory and cleanup handler
script_dir="$(cd "$(dirname "$0")" && pwd)"
pushd "$script_dir" >/dev/null
trap 'popd > /dev/null' EXIT
whisper_cpp_path="$HOME/dev/github/ggml-org/whisper.cpp"

# Convert audio to format required by Whisper (16kHz mono WAV)
if [ ! -f "${filename_wav}" ]; then
	echo "Converting to WAV format..."
	ffmpeg -i "${filename}" -ac 1 -ar 16000 "${filename_wav}"
else
	echo "WAV file already exists, skipping conversion"
fi

# Run Whisper transcription with optimized settings for v3 model
if [ ! -f "${srt_file}" ]; then
	echo "Running speech recognition..."
	# settings to avoid the v3 model repeating stuff, taken from https://github.com/ggml-org/whisper.cpp/issues/1507#issuecomment-1816263320
	"${whisper_cpp_path}/build/bin/whisper-cli" \
		-m "${whisper_cpp_path}/models/ggml-large-v3.bin" \
		-f "${filename_wav}" \
		--language "${language}" \
		--entropy-thold 2.8 \
		--max-context 64 \
		--beam-size 5 \
		--output-srt \
		--output-file "${input_dir}/${basename_no_ext}"

	# Handle case where Whisper outputs to wrong directory
	if [ ! -f "${srt_file}" ] && [ -f "${basename_no_ext}.srt" ]; then
		echo "Moving SRT file to correct location..."
		mv "${basename_no_ext}.srt" "${srt_file}"
	fi
else
	echo "SRT file already exists, skipping speech recognition"
fi

# Set up Python environment for diarization
if [ ! -d "venv" ]; then
	virtualenv venv --no-setuptools --no-wheel --activators bash
fi

# Activate virtual environment and install dependencies
source ./venv/bin/activate
if ! pip show pyannote-audio >/dev/null 2>&1; then
	pip install pyannote-audio
fi

# Perform speaker diarization to identify who spoke when
if [ ! -f "${diarization_file}" ]; then
	echo "Running diarization..."
	if python3 diarize.py "${filename_wav}" >"${diarization_file}"; then
		echo "Diarization completed successfully"
	else
		echo "Error: Diarization failed" >&2
		exit 1
	fi
else
	echo "Diarization file already exists, skipping diarization"
fi

# Combine transcript and speaker data into final markdown output
if [ ! -f "${final_md_file}" ]; then
	echo "Running merge..."
	if python3 merge_diarization.py "${diarization_file}" "${srt_file}" "${recording_date}" "${basename_no_ext}"; then
		# Ensure output file is in the correct directory
		if [ -f "${recording_date} ${basename_no_ext}.md" ] && [ "${recording_date} ${basename_no_ext}.md" != "${final_md_file}" ]; then
			mv "${recording_date} ${basename_no_ext}.md" "${final_md_file}"
		fi
		echo "Merge completed successfully - output written to ${final_md_file}"
	else
		echo "Error: Merge failed" >&2
		exit 1
	fi
else
	echo "Final merged file already exists, skipping merge"
fi
