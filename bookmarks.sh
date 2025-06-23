#!/bin/sh
# Extracts URLs from Safari Reading List and prints them line by line
# Uses plutil to parse Safari's Bookmarks.plist file - inefficient as it re-parses for each URL
# A better approach would be to parse once and extract all URLs, but this works
# Fails silently if no articles exist in the Reading List
#
# See: https://forketyfork.github.io/blog/2024/07/28/how-to-export-saved-urls-from-safari-reading-list/

set -eu

bookmarks_file="$HOME/Library/Safari/Bookmarks.plist"
tmp_file=/tmp/Bookmarks.plist.tmp
reading_list_title="com.apple.ReadingList"

# Copy plist to temp file to avoid modifying original
cp "$bookmarks_file" $tmp_file

# Find number of root children (top-level bookmark folders)
root_count="$(plutil -extract Children raw -expect array $tmp_file)"
if [ "$root_count" = "0" ]; then
	echo "Didn't find root children in the $bookmarks_file file"
	exit 1
fi

# Find Reading List folder by searching for its special title
reading_list_idx=no
for i in $(seq 0 $((root_count - 1))); do
	title="$(plutil -extract "Children.$i.Title" raw -expect string $tmp_file)"
	if [ "$title" = $reading_list_title ]; then
		reading_list_idx=$i
		break
	fi
done

# Exit if Reading List folder not found
if [ "$reading_list_idx" = "no" ]; then
	echo "Didn't find $reading_list_title in the $bookmarks_file file"
	exit 1
fi

# Count articles in Reading List
count="$(plutil -extract "Children.$reading_list_idx.Children" raw -expect array $tmp_file)"
if [ "$count" = "0" ]; then
	echo "No articles in the Reading List"
	exit 0
fi

# Extract and print each article URL
for i in $(seq 0 $((count - 1))); do
	plutil -extract "Children.$reading_list_idx.Children.$i.URLString" raw -expect string $tmp_file
done

# Clean up temporary file
rm -f $tmp_file
