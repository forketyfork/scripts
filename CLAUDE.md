# Guidelines

## Shell Script Best Practices

- After any changes to the shell scripts, run shellcheck and fix all warnings.
- If you disable any shellcheck rule in the code, add a comment on why it's safe to disable.
- All shell scripts should follow these patterns:
  - Use `#!/usr/bin/env bash` shebang
  - Set strict mode: `set -euo pipefail` and `IFS=$'\n\t'`
  - Include error handling: `handle_error()` function with `trap handle_error ERR`
  - Include `usage()` function with proper documentation
  - Use `readonly` for variables that shouldn't change
  - For SC2155 warnings, use separate declare and assign: `var=$(command)` then `readonly var`
  - Add proper cleanup with `trap cleanup EXIT` when needed
  - Quote all variable expansions and file paths
  - Redirect error messages to stderr with `>&2`
  - Validate required files/directories exist before proceeding
  - Check for required tools with `command -v tool >/dev/null 2>&1`

## Python Script Best Practices

- Use type hints for function parameters and return values
- Include comprehensive docstrings for modules and functions
- Implement proper error handling with try/except blocks
- Validate input files exist before processing
- Use `sys.stderr` for error messages and `sys.exit()` for error codes
- Structure scripts with a `main()` function and `if __name__ == "__main__":`
- Import modules in alphabetical order, separating standard library from third-party
- Use specific exception types rather than bare `except:`
- Check for required dependencies and provide helpful error messages

## Project Structure

- **whisper-rebuild.sh**: Rebuilds whisper.cpp with Core ML acceleration
- **sr.sh**: Speech recognition and diarization pipeline, requires Python scripts `diarize.py` and `merge_diarization.py`
- **diarize.py**: Performs speaker diarization using pyannote.audio, outputs timestamped speaker segments
- **merge_diarization.py**: Merges diarization data with Whisper SRT transcripts to create speaker-attributed markdown
- **backup-zettelkasten.sh**: Creates encrypted backups using age encryption and uploads to iCloud/Google Drive
- **decrypt-zettelkasten.sh**: Decrypts backups created by backup-zettelkasten.sh
- **bookmarks.sh**: Extracts URLs from Safari Reading List using plutil
- **artifact_downloads.py**: Monitors GitHub repositories for new artifact downloads, outputs timestamped messages with download counts

## artifact_downloads.py Configuration

The script requires a text file listing GitHub repositories to monitor (default: `artifact_repos.txt`). Each line should contain a repository in the format `owner/repo`.

### Environment Variables:
- `GITHUB_TOKEN`: Optional GitHub personal access token for higher API rate limits (recommended)
- `ARTIFACT_REPOS_FILE`: Path to repository list file (default: `artifact_repos.txt`)

### Usage:
```bash
# Create repository list
echo "forketyfork/claude-nein" > artifact_repos.txt
echo "owner/another-repo" >> artifact_repos.txt

# Run with authentication (recommended)
export GITHUB_TOKEN="your_token_here"
python3 artifact_downloads.py

# Run without authentication (60 requests/hour limit)
python3 artifact_downloads.py
```

### Output Format:
```
YYYY-MM-DD HH:MM:SS Artifact downloaded: owner/repo:filename.zip (+N)
```
