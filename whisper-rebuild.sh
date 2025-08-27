#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Rebuilds whisper.cpp with Apple Core ML acceleration support
# Updates to latest version, generates Core ML model, and compiles with optimizations

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

usage() {
	cat <<'EOF'
Usage: whisper-rebuild.sh

Rebuilds whisper.cpp with Apple Core ML acceleration support.
Updates to latest version, generates Core ML model, and compiles with optimizations.
EOF
	exit 1
}

readonly whisper_dir="$HOME/dev/github/ggml-org/whisper.cpp"

if [[ ! -d "$whisper_dir" ]]; then
	echo "Error: whisper.cpp directory not found at $whisper_dir" >&2
	exit 1
fi

echo "Navigating to whisper.cpp directory and updating..." >&2
pushd "$whisper_dir" >/dev/null
trap 'popd >/dev/null' EXIT

echo "Pulling latest changes..." >&2
git pull || {
	echo "Failed to pull latest changes" >&2
	exit 1
}

echo "Setting up clean Python environment..." >&2
virtualenv venv --python="python3.12" --clear --no-setuptools --no-wheel --activators bash || {
	echo "Failed to create virtual environment" >&2
	exit 1
}

# shellcheck disable=SC1091  # venv/bin/activate is created at runtime by virtualenv
source ./venv/bin/activate || {
	echo "Failed to activate virtual environment" >&2
	exit 1
}

echo "Installing required packages..." >&2
pip install ane_transformers openai-whisper coremltools || {
	echo "Failed to install required packages" >&2
	exit 1
}

echo "Generating Core ML optimized large-v3 model..." >&2
./models/generate-coreml-model.sh large-v3 || {
	echo "Failed to generate Core ML model" >&2
	exit 1
}

echo "Configuring build with Core ML acceleration..." >&2
cmake -B build -DWHISPER_COREML=1 || {
	echo "Failed to configure build" >&2
	exit 1
}

echo "Building with optimizations..." >&2
cmake --build build -j --config Release || {
	echo "Failed to build whisper.cpp" >&2
	exit 1
}

echo "Cleaning up virtual environment..." >&2
deactivate

echo "Whisper.cpp rebuild completed successfully." >&2
