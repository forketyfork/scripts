#!/usr/bin/env python3
"""Performs speaker diarization on audio files using pyannote.audio.

Takes a WAV file and outputs speaker segments with timestamps.
"""

import argparse
import os
import sys
import torch
from pyannote.audio import Pipeline


def main():
    """Main function to run speaker diarization."""
    parser = argparse.ArgumentParser(description="Run speaker diarization on a WAV file")
    parser.add_argument("filename", help="Path to the WAV audio file")
    args = parser.parse_args()

    # Validate input file exists
    if not os.path.isfile(args.filename):
        print(f"Error: Audio file '{args.filename}' not found.", file=sys.stderr)
        sys.exit(1)

    # Load pre-trained speaker diarization model
    try:
        pipeline = Pipeline.from_pretrained(
            "pyannote/speaker-diarization-3.1", 
            use_auth_token=True
        )
    except Exception as e:
        print(f"Error loading pipeline: {e}", file=sys.stderr)
        print("Make sure you have a valid Hugging Face token configured.", file=sys.stderr)
        sys.exit(1)

    # Detect and use best available device (Apple Silicon MPS, CUDA, or CPU)
    if torch.backends.mps.is_available():
        device = torch.device("mps")
        print(f"Using Apple Silicon GPU (MPS): {device}", file=sys.stderr)
        pipeline.to(device)
    elif torch.cuda.is_available():
        device = torch.device("cuda")
        print(f"Using CUDA GPU: {device}", file=sys.stderr)
        pipeline.to(device)
    else:
        device = torch.device("cpu")
        print(f"Using CPU: {device}", file=sys.stderr)

    # Process audio file and identify speaker segments
    try:
        diarization = pipeline(args.filename)
    except Exception as e:
        print(f"Error during diarization: {e}", file=sys.stderr)
        sys.exit(1)

    # Output speaker segments with timestamps
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        print(f"{turn.start:.3f}s - {turn.end:.3f}s: {speaker}")


if __name__ == "__main__":
    main()

