#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Extracts URLs from Safari Reading List and prints them line by line
# Uses plutil to parse Safari's Bookmarks.plist file - inefficient as it re-parses for each URL
# A better approach would be to parse once and extract all URLs, but this works
# Fails silently if no articles exist in the Reading List
#
# See: https://forketyfork.github.io/blog/2024/07/28/how-to-export-saved-urls-from-safari-reading-list/

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

usage() {
	cat <<'EOF'
Usage: bookmarks.sh

Extracts URLs from Safari Reading List and prints them line by line.
Uses plutil to parse Safari's Bookmarks.plist file.
EOF
	exit 1
}

readonly bookmarks_file="$HOME/Library/Safari/Bookmarks.plist"
readonly tmp_file="/tmp/Bookmarks.plist.tmp.$$"
readonly reading_list_title="com.apple.ReadingList"

# Cleanup function
cleanup() {
	rm -f "$tmp_file"
}
trap cleanup EXIT

if [[ ! -f "$bookmarks_file" ]]; then
	echo "Error: Safari bookmarks file not found at '$bookmarks_file'" >&2
	exit 1
fi

# Copy plist to temp file to avoid modifying original
cp "$bookmarks_file" "$tmp_file" || {
	echo "Failed to copy bookmarks file to temporary location" >&2
	exit 1
}

# Find number of root children (top-level bookmark folders)
root_count="$(plutil -extract Children raw -expect array "$tmp_file")" || {
	echo "Failed to extract root children from bookmarks file" >&2
	exit 1
}

if [[ "$root_count" = "0" ]]; then
	echo "No root children found in the bookmarks file" >&2
	exit 1
fi

# Find Reading List folder by searching for its special title
reading_list_idx=""
for i in $(seq 0 $((root_count - 1))); do
	title="$(plutil -extract "Children.$i.Title" raw -expect string "$tmp_file" 2>/dev/null)" || continue
	if [[ "$title" = "$reading_list_title" ]]; then
		reading_list_idx=$i
		break
	fi
done

# Exit if Reading List folder not found
if [[ -z "$reading_list_idx" ]]; then
	echo "Reading List not found in the bookmarks file" >&2
	exit 1
fi

# Count articles in Reading List
count="$(plutil -extract "Children.$reading_list_idx.Children" raw -expect array "$tmp_file")" || {
	echo "Failed to extract Reading List children" >&2
	exit 1
}

if [[ "$count" = "0" ]]; then
	echo "No articles in the Reading List" >&2
	exit 0
fi

# Extract and print each article URL
for i in $(seq 0 $((count - 1))); do
	plutil -extract "Children.$reading_list_idx.Children.$i.URLString" raw -expect string "$tmp_file" 2>/dev/null || {
		echo "Warning: Failed to extract URL for article $i" >&2
		continue
	}
done

echo "Successfully extracted $count URLs from Safari Reading List" >&2
