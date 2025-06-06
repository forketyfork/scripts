#!/usr/bin/env sh
# Convert a file to 1-channel 16 kHz WAV and run through the OpenAI Whisper model

set -eu

# The script expects 2 arguments: file name and language, e.g., en, de, ru...
if [ $# != 2 ]
then
    printf "%b" "Expected 2 arguments: file name and language.\n" >&2
    exit 1
fi

# Convert filename to absolute path before changing directories
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

# Change to the script's directory and set up cleanup
script_dir="$(cd "$(dirname "$0")" && pwd)"
pushd "$script_dir" > /dev/null
trap 'popd > /dev/null' EXIT
whisper_cpp_path="$HOME/dev/github/ggerganov/whisper.cpp"

# convert the input file to 1-channel 16 kHz wav file
if [ ! -f "${filename_wav}" ]; then
    echo "Converting to WAV format..."
    ffmpeg -i "${filename}" -ac 1 -ar 16000 "${filename_wav}"
else
    echo "WAV file already exists, skipping conversion"
fi

# run the speech recognition with large-v3 model
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
    
    # Check if whisper created the SRT file in the script directory instead
    if [ ! -f "${srt_file}" ] && [ -f "${basename_no_ext}.srt" ]; then
        echo "Moving SRT file to correct location..."
        mv "${basename_no_ext}.srt" "${srt_file}"
    fi
else
    echo "SRT file already exists, skipping speech recognition"
fi

# create python virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    virtualenv venv --no-setuptools --no-wheel --activators bash
fi

# activate the virtual environment
source ./venv/bin/activate

# install the required packages if not already installed
if ! pip show pyannote-audio > /dev/null 2>&1; then
    pip install pyannote-audio
fi

# run diarization with error handling
if [ ! -f "${diarization_file}" ]; then
    echo "Running diarization..."
    if python3 diarize.py "${filename_wav}" > "${diarization_file}"; then
        echo "Diarization completed successfully"
    else
        echo "Error: Diarization failed" >&2
        exit 1
    fi
else
    echo "Diarization file already exists, skipping diarization"
fi

# merge the transcript with diarization
if [ ! -f "${final_md_file}" ]; then
    echo "Running merge..."
    if python3 merge_diarization.py "${diarization_file}" "${srt_file}" "${recording_date}" "${basename_no_ext}"; then
        # Move the generated file to the input directory if it was created in the script directory
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

