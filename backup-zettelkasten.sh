#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Creates an encrypted backup of Zettelkasten vault and uploads it to iCloud and Google Drive
# The backup excludes .obsidian directory and is encrypted using age with a public key

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

usage() {
	cat <<'EOF'
Usage: backup-zettelkasten.sh

Creates an encrypted backup of Zettelkasten vault and uploads it to iCloud and Google Drive.
The backup excludes .obsidian directory and is encrypted using age with a public key.
EOF
	exit 1
}

# Configuration
readonly vault_dir="$HOME/Zettelkasten"
timestamp=$(date +%F-%H%M)
readonly timestamp
readonly backup_name="zettelkasten-$timestamp.tar.gz.age"
readonly tmp_backup="$HOME/$backup_name"
readonly age_key_file="$HOME/.config/age/key.txt"

readonly icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ObsidianBackups"
readonly gdrive_remote="gdrive:ObsidianBackups"

# Cleanup function
cleanup() {
	rm -f "$tmp_backup"
}
trap cleanup EXIT

# Validate required directories and files
if [[ ! -d "$vault_dir" ]]; then
	echo "Error: Zettelkasten vault directory not found at '$vault_dir'" >&2
	exit 1
fi

if [[ ! -f "$age_key_file" ]]; then
	echo "Error: Age key file not found at '$age_key_file'" >&2
	exit 1
fi

echo "Creating encrypted archive..." >&2

# Extract public key from age key file for encryption
pubkey=$(grep '^# public key:' "$age_key_file" | cut -d' ' -f4) || {
	echo "Failed to extract public key from age key file" >&2
	exit 1
}
readonly pubkey

if [[ -z "$pubkey" ]]; then
	echo "Error: No public key found in age key file" >&2
	exit 1
fi

# Create compressed tar archive excluding .obsidian and pipe to age for encryption
tar -czf - --exclude=".obsidian" -C "$vault_dir" . | /run/current-system/sw/bin/age -r "$pubkey" >"$tmp_backup" || {
	echo "Failed to create encrypted backup archive" >&2
	exit 1
}

echo "Copying to iCloud..." >&2
mkdir -p "$icloud_dir" || {
	echo "Failed to create iCloud backup directory" >&2
	exit 1
}

cp "$tmp_backup" "$icloud_dir/" || {
	echo "Failed to copy backup to iCloud" >&2
	exit 1
}

echo "Uploading to Google Drive via rclone..." >&2
/run/current-system/sw/bin/rclone copy "$tmp_backup" "$gdrive_remote" || {
	echo "Failed to upload backup to Google Drive" >&2
	exit 1
}

echo "Backup complete: $backup_name" >&2

# Send macOS desktop notification
if command -v terminal-notifier >/dev/null 2>&1 && [[ "$OSTYPE" == "darwin"* ]]; then
	user_name="$(stat -f%Su /dev/console)"
	readonly user_name
	user_id="$(id -u "$user_name")"
	readonly user_id

	/bin/launchctl asuser "$user_id" sudo -u "$user_name" \
		terminal-notifier -title "Zettelkasten Backup" -message "Backup complete" 2>/dev/null || {
		echo "Warning: Failed to send desktop notification" >&2
	}
else
	echo "Warning: terminal-notifier not available, skipping desktop notification" >&2
fi

echo "Zettelkasten backup completed successfully." >&2
