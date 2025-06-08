#!/bin/bash
# Decrypts and restores a Zettelkasten backup created by backup-zettelkasten.sh
# Takes an encrypted .tar.gz.age file and extracts it to a timestamped directory

set -euo pipefail

# === Input ===
if [ $# -ne 1 ]; then
	echo "Usage: $0 <backup-file.tar.gz.age>"
	exit 1
fi

ENC_FILE="$1"

if [ ! -f "$ENC_FILE" ]; then
	echo "Error: File '$ENC_FILE' not found."
	exit 2
fi

# === Output Directory ===
OUT_DIR="./zettel-restore-$(date +%F-%H%M)"
mkdir -p "$OUT_DIR"

echo "[*] Decrypting $ENC_FILE to $OUT_DIR..."

# Decrypt using age private key and extract tar archive
age -d -i ~/.config/age/key.txt "$ENC_FILE" | tar -xzf - -C "$OUT_DIR"

echo "[✓] Restore complete in: $OUT_DIR"
