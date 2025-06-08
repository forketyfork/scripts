#!/bin/bash

set -euo pipefail

# === Config ===
VAULT_DIR="$HOME/Zettelkasten"
TIMESTAMP=$(date +%F-%H%M)
BACKUP_NAME="zettelcasten-$TIMESTAMP.tar.gz.age"
TMP_BACKUP="$HOME/$BACKUP_NAME"

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ObsidianBackups"
GDRIVE_REMOTE="gdrive:ObsidianBackups"

# === Backup ===
echo "[*] Creating encrypted archive..."
PUBKEY=$(grep '^# public key:' ~/.config/age/key.txt | cut -d' ' -f4)
tar -czf - --exclude=".obsidian" -C "$VAULT_DIR" . | /run/current-system/sw/bin/age -r "$PUBKEY" >"$TMP_BACKUP"

echo "[*] Copying to iCloud..."
mkdir -p "$ICLOUD_DIR"
cp "$TMP_BACKUP" "$ICLOUD_DIR/"

echo "[*] Uploading to Google Drive via rclone..."
rclone copy "$TMP_BACKUP" "$GDRIVE_REMOTE"

echo "[*] Cleaning up local temp file..."
rm "$TMP_BACKUP"

echo "[✓] Backup complete: $BACKUP_NAME"
