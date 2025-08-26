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

## Environment Setup

This repository uses [direnv](https://direnv.net/) for environment variable management:

1. **Install direnv** (if not already installed):
   ```sh
   # macOS
   brew install direnv
   
   # Add to your shell profile (.bashrc, .zshrc, etc.)
   eval "$(direnv hook bash)"  # or zsh, fish, etc.
   ```

2. **Configure environment variables**:
   ```sh
   # Edit .env file and add your GitHub token
   echo "GITHUB_TOKEN=your_token_here" > .env
   
   # Allow direnv to load the environment
   direnv allow
   ```

3. **GitHub Token Setup** (recommended for artifact_downloads.py):
   - Visit [GitHub Settings > Tokens](https://github.com/settings/tokens)
   - Create a new token with `public_repo` scope
   - Add it to your `.env` file

## Dependencies

- **Audio processing**: ffmpeg, whisper.cpp, Python with pyannote-audio
- **Video downloads**: yt-dlp (for YouTube video downloads)
- **Encryption**: age (for Zettelkasten backups)
- **Cloud storage**: rclone (for Google Drive sync)
- **Shell tools**: shfmt, shellcheck (for git hooks)
