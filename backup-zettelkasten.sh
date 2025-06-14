#!/bin/bash
# Creates an encrypted backup of Zettelkasten vault and uploads it to iCloud and Google Drive
# The backup excludes .obsidian directory and is encrypted using age with a public key

set -euo pipefail

# === Config ===
VAULT_DIR="$HOME/Zettelkasten"
TIMESTAMP=$(date +%F-%H%M)
BACKUP_NAME="zettelkasten-$TIMESTAMP.tar.gz.age"
TMP_BACKUP="$HOME/$BACKUP_NAME"

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ObsidianBackups"
GDRIVE_REMOTE="gdrive:ObsidianBackups"

# === Backup ===
echo "[*] Creating encrypted archive..."
# Extract public key from age key file for encryption
PUBKEY=$(grep '^# public key:' ~/.config/age/key.txt | cut -d' ' -f4)
# Create compressed tar archive excluding .obsidian and pipe to age for encryption
tar -czf - --exclude=".obsidian" -C "$VAULT_DIR" . | /run/current-system/sw/bin/age -r "$PUBKEY" >"$TMP_BACKUP"

echo "[*] Copying to iCloud..."
mkdir -p "$ICLOUD_DIR"
cp "$TMP_BACKUP" "$ICLOUD_DIR/"

echo "[*] Uploading to Google Drive via rclone..."
rclone copy "$TMP_BACKUP" "$GDRIVE_REMOTE"

echo "[*] Cleaning up local temp file..."
rm "$TMP_BACKUP"

echo "[✓] Backup complete: $BACKUP_NAME"

# Send macOS desktop notification
USER_NAME="$(stat -f%Su /dev/console)"
USER_ID="$(id -u "$USER_NAME")"
/bin/launchctl asuser "$USER_ID" sudo -u "$USER_NAME" \
	/opt/homebrew/bin/terminal-notifier -title "Zettelkasten Backup" -message "Backup complete"
