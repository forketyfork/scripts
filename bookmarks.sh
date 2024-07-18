#!/bin/sh

# This script extracts the URLs from the Safari Reading List and prints each URL on a separate line.
# It uses plutil and is therefore not very performant, as plutil extracts each URL
# by reading and parsing the plist file each time.
# A better alternative would be to parse the file and extract all URLs at once,
# but this script gets the job done.

set -eu

bookmarks_file="$HOME/Library/Safari/Bookmarks.plist"
tmp_file=/tmp/Bookmarks.plist.tmp
reading_list_title="com.apple.ReadingList"

# copy the Bookmarks.plist file to avoid overwriting it
cp "$bookmarks_file" $tmp_file

# find number of root children in the plist file (those are the top level bookmarks)
root_count="$(plutil -extract Children raw -expect array $tmp_file)"
if [ "$root_count" = "0" ]; then
	echo "Didn't find root children in the $bookmarks_file file"
	exit 1
fi

# iterate through the root children and find the reading list by the title, save its index in the array to reading_list_idx
reading_list_idx=no
for i in $(seq 0 $((root_count - 1))); do
	title="$(plutil -extract "Children.$i.Title" raw -expect string $tmp_file)"
	if [ "$title" = $reading_list_title ]; then
		reading_list_idx=$i
		break
	fi
done

# we didn't find the reading list, exit with an error
if [ "$reading_list_idx" = "no" ]; then
	echo "Didn't find $reading_list_title in the $bookmarks_file file"
	exit 1
fi

# find the number of saved articles
count="$(plutil -extract "Children.$reading_list_idx.Children" raw -expect array $tmp_file)"
if [ "$count" = "0" ]; then
	echo "No articles in the Reading List"
	exit 0
fi

# iterate through the numbers of articles, 0..count-1
for i in $(seq 0 $((count - 1))); do
	# extract the article URL and output it in raw (string) format
	plutil -extract "Children.$reading_list_idx.Children.$i.URLString" raw -expect string $tmp_file
done

# clean up the temporary file
rm -f $tmp_file
