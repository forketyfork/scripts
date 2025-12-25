# scripts

A collection of utility scripts for various tasks including audio processing, Safari bookmarks extraction, and Zettelkasten backup management.

## Audio Processing Scripts

- **[sr.sh](sr.sh)**: Comprehensive audio-to-text pipeline using Whisper speech recognition with speaker diarization
  - Converts audio files to 16kHz WAV format
  - Runs OpenAI Whisper large-v3 model for transcription
  - Performs speaker diarization using pyannote-audio
  - Merges transcription with speaker labels into markdown format
  - Usage: `./sr.sh <audio_file> <language_code>`

- **[diarize.py](diarize.py)**: Speaker diarization script using pyannote-audio
  - Identifies different speakers in audio files
  - Supports Apple Silicon GPU acceleration (MPS) and CUDA
  - Usage: `python diarize.py <audio_file.wav>`

- **[merge_diarization.py](merge_diarization.py)**: Merges Whisper transcription with speaker diarization
  - Combines SRT subtitle files with diarization output
  - Creates speaker-labeled markdown transcripts
  - Usage: `python merge_diarization.py <diarization.txt> <output.srt> <YYYY-MM-DD> <audio_filename>`

- **[whisper-rebuild.sh](whisper-rebuild.sh)**: Rebuilds whisper.cpp with Core ML support for Apple Silicon
  - Updates whisper.cpp repository
  - Builds with Core ML optimization for faster inference on Apple Silicon
  - Generates Core ML models for the large-v3 Whisper model

- **[youtube-to-srt.sh](youtube-to-srt.sh)**: Downloads YouTube videos and generates SRT subtitles
  - Downloads video from YouTube using yt-dlp
  - Extracts audio and converts to 16kHz mono WAV format
  - Uses Whisper large-v3 model for subtitle generation
  - Automatically cleans up temporary video/audio files
  - Usage: `./youtube-to-srt.sh <youtube_url> <language_code> [output_file.srt]`

## Data Management Scripts

- **[backup-zettelkasten.sh](backup-zettelkasten.sh)**: Creates encrypted backups of Zettelkasten/Obsidian vault
  - Creates timestamped encrypted archives using age encryption
  - Backs up to both iCloud and Google Drive via rclone
  - Excludes .obsidian configuration files from backup

- **[decrypt-zettelkasten.sh](decrypt-zettelkasten.sh)**: Restores encrypted Zettelkasten backups
  - Decrypts age-encrypted backup files
  - Extracts contents to timestamped restore directory
  - Usage: `./decrypt-zettelkasten.sh <backup-file.tar.gz.age>`

- **[cleanup-zettelkasten-backup.sh](cleanup-zettelkasten-backup.sh)**: Manages retention of Zettelkasten backups
  - Implements automated retention policy for backup files
  - Keeps all backups for current month
  - Keeps every 7th backup for previous month (1st, 8th, 15th file when sorted)
  - Keeps only first backup for each older month
  - Cleans up both iCloud and Google Drive locations
  - Shows confirmation with list of files to delete before removal
  - Usage: `./cleanup-zettelkasten-backup.sh`

## Utility Scripts

- **[bookmarks.sh](bookmarks.sh)**: Extracts URLs from macOS Safari Reading List
  - Parses Safari's Bookmarks.plist file
  - Outputs each saved article URL on a separate line
  - Handles cases where Reading List is empty

- **[convert_books.py](convert_books.py)**: Converts [Book Tracker](https://booktrack.app/) CSV exports to [Obsidian Bookshelf](https://weph.github.io/obsidian-bookshelf/) plugin format
  - Reads CSV files containing book data with semicolon delimiter
  - Converts each book into a markdown file with YAML frontmatter
  - Sanitizes filenames for filesystem compatibility
  - Formats dates and parses author names from CSV format
  - Creates reading journey timeline with start/end dates
  - Usage: `python convert_books.py <csv_file> <output_dir> [--delimiter=";"]`

- **[artifact_downloads.py](artifact_downloads.py)**: Monitors GitHub repositories for new artifact downloads
  - Checks repository releases every 60 seconds for download count changes
  - Outputs timestamped messages when new downloads are detected
  - Supports GitHub API authentication for higher rate limits
  - Validates repository names and handles rate limiting gracefully
  - Requires `artifact_repos.txt` file with list of repositories to monitor
  - Usage: `python3 artifact_downloads.py` (set `GITHUB_TOKEN` environment variable for authentication)

## Git Hooks

The repository includes pre-commit and post-commit hooks for shell script quality:

- **[hooks/pre-commit](hooks/pre-commit)**: Formats and lints shell scripts
  - Runs `shfmt` for consistent formatting
  - Runs `shellcheck` for static analysis
  - Automatically stages formatted files

- **[hooks/post-commit](hooks/post-commit)**: Updates git index after formatting changes

To install the hooks after cloning:
```sh
git config --local core.hooksPath hooks
```

## Setup

This repository uses [Nix](https://nixos.org/) with [direnv](https://direnv.net/) for reproducible dependency management.

### Prerequisites

1. **Install Nix** (if not already installed):
   ```sh
   # Single-user installation (recommended for macOS)
   curl -L https://nixos.org/nix/install | sh
   
   # Enable flakes (add to ~/.config/nix/nix.conf or /etc/nix/nix.conf)
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

2. **Install direnv** (if not already installed):
   ```sh
   # Via Nix
   nix profile install nixpkgs#direnv
   
   # Or via Homebrew on macOS
   brew install direnv
   
   # Add to your shell profile (.bashrc, .zshrc, etc.)
   eval "$(direnv hook bash)"  # or zsh, fish, etc.
   ```

### Getting Started

1. **Clone and enter the repository**:
   ```sh
   git clone <repository-url>
   cd scripts
   ```

2. **Allow direnv to load the environment**:
   ```sh
   direnv allow
   ```
   
   This will automatically:
   - Set up a Nix development shell with all dependencies
   - Provide Python 3 with virtualenv support (scripts manage their own ML packages)
   - Configure git hooks for shell script formatting
   - Create a `.env` template file

3. **Configure environment variables** (edit the generated `.env` file):
   ```sh
   # GitHub token for artifact_downloads.py (optional but recommended)
   GITHUB_TOKEN=your_token_here
   
   # Zettelkasten vault directory (for backup scripts)
   ZETTELKASTEN_DIR=$HOME/Documents/Zettelkasten
   
   # Google Drive remote for rclone (configure with: rclone config)
   GDRIVE_REMOTE=gdrive:backups
   ```

4. **GitHub Token Setup** (recommended for artifact_downloads.py):
   - Visit [GitHub Settings > Tokens](https://github.com/settings/tokens)
   - Create a new token with `public_repo` scope
   - Add it to your `.env` file

### Special Requirements

- **whisper.cpp**: Needs to be built separately at `~/dev/github/ggml-org/whisper.cpp`
  - Run `./whisper-rebuild.sh` to build it with Core ML support
- **rclone**: Configure Google Drive access with `rclone config`
- **age encryption**: Set up key file at `~/.config/age/key.txt` for backup scripts

### Available Dependencies

The Nix flake provides all necessary dependencies:
- **Audio processing**: ffmpeg, Python 3 with virtualenv (ML packages installed on-demand)
- **Video downloads**: yt-dlp 
- **Encryption**: age
- **Cloud storage**: rclone
- **Shell tools**: shfmt, shellcheck
- **Development**: git, direnv, terminal-notifier (macOS)
