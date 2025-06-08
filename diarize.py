#!/usr/bin/env python3
# Performs speaker diarization on audio files using pyannote.audio
# Takes a WAV file and outputs speaker segments with timestamps

from pyannote.audio import Pipeline
import argparse
import torch
parser = argparse.ArgumentParser(description="Run speaker diarization on a WAV file")
parser.add_argument("filename", help="Path to the WAV audio file")
args = parser.parse_args()

# Load pre-trained speaker diarization model
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", use_auth_token=True)

# Detect and use best available device (Apple Silicon MPS, CUDA, or CPU)
if torch.backends.mps.is_available():
    device = torch.device("mps")
    print(f"Using Apple Silicon GPU (MPS): {device}")
    pipeline.to(device)
elif torch.cuda.is_available():
    device = torch.device("cuda")
    print(f"Using CUDA GPU: {device}")
    pipeline.to(device)
else:
    device = torch.device("cpu")
    print(f"Using CPU: {device}")

# Process audio file and identify speaker segments
diarization = pipeline(args.filename)

# Output speaker segments with timestamps
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f"{turn.start:.3f}s - {turn.end:.3f}s: {speaker}")

