#!/usr/bin/env sh
# Convert a file to 1-channel 16 kHz WAV and run through the OpenAI Whisper model

set -eu

# The script expects 2 arguments: file name and language, e.g., en, de, ru...
if [ $# != 2 ]
then
    printf "%b" "Expected 2 arguments: file name and language.\n" >&2
    exit 1
fi

filename="$1"
filename_wav="$1.wav"
basename_no_ext=$(basename "$filename" | sed 's/\.[^.]*$//')
language="$2"
# Extract recording date from file modification time
recording_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$filename")
whisper_cpp_path="$HOME/dev/github/ggerganov/whisper.cpp"

# convert the input file to 1-channel 16 kHz wav file
ffmpeg -i "${filename}" -ac 1 -ar 16000 "${filename_wav}"

# run the speech recognition with large-v3 model
# settings to avoid the v3 model repeating stuff, taken from https://github.com/ggml-org/whisper.cpp/issues/1507#issuecomment-1816263320
"${whisper_cpp_path}/build/bin/whisper-cli" \
    -m "${whisper_cpp_path}/models/ggml-large-v3.bin" \
    -f "${filename_wav}" \
    --language "${language}" \
    --entropy-thold 2.8 \
    --max-context 64 \
    --beam-size 5 \
    --output-srt \
    --output-file "${basename_no_ext}"

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
if python3 diarize.py "${filename_wav}" > "${basename_no_ext}_diarization.txt"; then
    echo "Diarization completed successfully"
else
    echo "Error: Diarization failed" >&2
    deactivate
    exit 1
fi

# merge the transcript with diarization
if python3 merge_diarization.py "${basename_no_ext}_diarization.txt" "${basename_no_ext}.srt" "${recording_date}" "${basename_no_ext}"; then
    echo "Merge completed successfully - output written to ${recording_date} ${basename_no_ext}.md"
else
    echo "Error: Merge failed" >&2
    deactivate
    exit 1
fi

# deactivate the virtual environment
deactivate

# remove the temporary wav file only if everything succeeded
rm "${filename_wav}"
