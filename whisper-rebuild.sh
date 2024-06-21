#!/usr/bin/env bash
# Rebuild  whisper.cpp with Core ML support

set -eu

# go to the project directory
pushd ~/dev/github/ggerganov/whisper.cpp

# pull the latest revision (assuming we're on master)
git pull

# switch to the python virtual environment and activate it
virtualenv venv --clear --no-setuptools --no-wheel
source ./venv/bin/activate

# install the required packages
pip install ane_transformers openai-whisper coremltools

# generate the large-v3 model
./models/generate-coreml-model.sh large-v3

# clean the build artifacts
make clean

# build whisper.cpp with Core ML support
WHISPER_COREML=1 make -j

# deactivate the virtual environment
deactivate

# get back to the initial directory
popd
