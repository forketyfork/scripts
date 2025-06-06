from pyannote.audio import Pipeline
import argparse
import torch

# Parse command-line argument
parser = argparse.ArgumentParser(description="Run speaker diarization on a WAV file")
parser.add_argument("filename", help="Path to the WAV audio file")
args = parser.parse_args()

# Load the diarization pipeline 
pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", use_auth_token=True)

# Use Apple Silicon GPU if available (Metal Performance Shaders)
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

# Run diarization
diarization = pipeline(args.filename)

# Print results
for turn, _, speaker in diarization.itertracks(yield_label=True):
    print(f"{turn.start:.3f}s - {turn.end:.3f}s: {speaker}")

