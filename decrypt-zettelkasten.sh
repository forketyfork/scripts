#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Decrypts and restores a Zettelkasten backup created by backup-zettelkasten.sh
# Takes an encrypted .tar.gz.age file and extracts it to a timestamped directory

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

usage() {
	cat <<'EOF'
Usage: decrypt-zettelkasten.sh <backup-file.tar.gz.age>

Decrypts and restores a Zettelkasten backup created by backup-zettelkasten.sh.
Takes an encrypted .tar.gz.age file and extracts it to a timestamped directory.
EOF
	exit 1
}

if [[ $# -ne 1 ]]; then
	usage
fi

readonly enc_file="$1"
readonly age_key_file="$HOME/.config/age/key.txt"

if [[ ! -f "$enc_file" ]]; then
	echo "Error: File '$enc_file' not found." >&2
	exit 1
fi

if [[ ! -f "$age_key_file" ]]; then
	echo "Error: Age key file not found at '$age_key_file'" >&2
	exit 1
fi

out_dir_suffix=$(date +%F-%H%M)
readonly out_dir="./zettel-restore-$out_dir_suffix"

echo "Creating output directory: $out_dir" >&2
mkdir -p "$out_dir" || {
	echo "Failed to create output directory" >&2
	exit 1
}

echo "Decrypting $enc_file to $out_dir..." >&2

age -d -i "$age_key_file" "$enc_file" | tar -xzf - -C "$out_dir" || {
	echo "Failed to decrypt and extract backup" >&2
	exit 1
}

echo "Restore complete in: $out_dir" >&2
