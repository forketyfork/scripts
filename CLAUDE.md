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

## Project Structure

- **whisper-rebuild.sh**: Rebuilds whisper.cpp with Core ML acceleration
- **sr.sh**: Speech recognition and diarization pipeline, requires Python scripts `diarize.py` and `merge_diarization.py`
- **backup-zettelkasten.sh**: Creates encrypted backups using age encryption and uploads to iCloud/Google Drive
- **decrypt-zettelkasten.sh**: Decrypts backups created by backup-zettelkasten.sh
- **bookmarks.sh**: Extracts URLs from Safari Reading List using plutil
