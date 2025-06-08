#!/usr/bin/env bash
# Rebuilds whisper.cpp with Apple Core ML acceleration support
# Updates to latest version, generates Core ML model, and compiles with optimizations

set -eu

# Navigate to whisper.cpp directory and update
pushd ~/dev/github/ggml-org/whisper.cpp
git pull

# Set up clean Python environment with required packages
virtualenv venv --clear --no-setuptools --no-wheel --activators bash
source ./venv/bin/activate

pip install ane_transformers openai-whisper coremltools

# Generate Core ML optimized large-v3 model
./models/generate-coreml-model.sh large-v3

# Configure and build with Core ML acceleration
cmake -B build -DWHISPER_COREML=1

cmake --build build -j --config Release

# Clean up and return to original directory
deactivate
popd
