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
language="$2"
whisper_cpp_path="$HOME/dev/github/ggerganov/whisper.cpp"

# convert the input file to 1-channel 16 kHz wav file
ffmpeg -i "${filename}" -ac 1 -ar 16000 "${filename_wav}"

# run the speech recognition with large-v3 model
"${whisper_cpp_path}/build/bin/main" -m "${whisper_cpp_path}/models/ggml-large-v3.bin" -f "${filename_wav}" --print-colors --language "${language}" --no-timestamps

# remove the temporary wav file
rm "${filename_wav}"
