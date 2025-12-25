#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Cleanup old Zettelkasten backups from iCloud and Google Drive
# Retention policy:
# - Keep all backups for current month
# - Keep every 7th backup for previous month (1st, 8th, 15th, etc. when sorted)
# - Keep only first backup of each older month

handle_error() {
	local ec=$?
	echo "Error on line $LINENO (exit code: $ec)" >&2
	exit $ec
}
trap handle_error ERR

usage() {
	cat <<'EOF'
Usage: cleanup-zettelkasten-backup.sh

Cleanup old Zettelkasten backups with the following retention policy:
- Keep all backups for current month
- Keep every 7th backup for previous month (1st, 8th, 15th, etc. when sorted)
- Keep only first backup of each older month

Shows confirmation before deleting files.
EOF
	exit 1
}

# Configuration
readonly icloud_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ObsidianBackups"
readonly gdrive_remote="gdrive:ObsidianBackups"
readonly backup_pattern="zettelkasten-*.tar.gz.age"
readonly rclone_bin="/run/current-system/sw/bin/rclone"

# Validate required tools
if [[ ! -x "$rclone_bin" ]]; then
	echo "Error: rclone is required but not found at '$rclone_bin'" >&2
	exit 1
fi

# Validate iCloud directory exists
if [[ ! -d "$icloud_dir" ]]; then
	echo "Error: iCloud backup directory not found at '$icloud_dir'" >&2
	exit 1
fi

# Get current and previous month in YYYY-MM format
current_month=$(date +%Y-%m)
readonly current_month
previous_month=$(date -v-1m +%Y-%m 2>/dev/null || date -d "1 month ago" +%Y-%m 2>/dev/null)
readonly previous_month

echo "Current month: $current_month" >&2
echo "Previous month: $previous_month" >&2
echo >&2

# Function to extract year-month from backup filename
get_year_month() {
	local filename=$1
	# Extract YYYY-MM from zettelkasten-YYYY-MM-DD-HHMM.tar.gz.age
	echo "$filename" | sed -E 's/zettelkasten-([0-9]{4}-[0-9]{2})-.*/\1/'
}

# Function to list backups from a location
list_backups() {
	local location=$1
	local -a files=()

	if [[ "$location" == "icloud" ]]; then
		if [[ -d "$icloud_dir" ]]; then
			while IFS= read -r -d '' file; do
				files+=("$(basename "$file")")
			done < <(find "$icloud_dir" -name "$backup_pattern" -print0 2>/dev/null || true)
		fi
	elif [[ "$location" == "gdrive" ]]; then
		# Use rclone to list files
		local rclone_output
		if ! rclone_output=$("$rclone_bin" ls "$gdrive_remote" 2>&1); then
			echo "Error: Failed to list Google Drive backups" >&2
			echo "$rclone_output" >&2
			exit 1
		fi
		while IFS= read -r line; do
			# rclone ls output format: "size filename"
			local filename
			filename=$(echo "$line" | awk '{print $2}')
			# shellcheck disable=SC2254  # backup_pattern is intentionally a glob pattern
			case "$filename" in
			$backup_pattern)
				files+=("$filename")
				;;
			esac
		done <<<"$rclone_output"
	fi

	# Sort files and ensure function returns 0 even if no files found
	if [[ ${#files[@]} -gt 0 ]]; then
		printf '%s\n' "${files[@]}" | sort
	fi
	return 0
}

# Get all backups from both locations and merge
declare -A all_backups
while IFS= read -r file; do
	all_backups["$file"]=1
done < <(list_backups icloud)

while IFS= read -r file; do
	all_backups["$file"]=1
done < <(list_backups gdrive)

# Convert to sorted array
mapfile -t sorted_backups < <(printf '%s\n' "${!all_backups[@]}" | sort)

if [[ ${#sorted_backups[@]} -eq 0 ]]; then
	echo "No backups found" >&2
	exit 0
fi

echo "Found ${#sorted_backups[@]} total backup(s)" >&2
echo >&2

# Group backups by month and determine which to keep
declare -A backups_by_month
declare -A files_to_keep

for file in "${sorted_backups[@]}"; do
	year_month=$(get_year_month "$file")
	backups_by_month["$year_month"]+="$file"$'\n'
done

# Process each month
for year_month in $(printf '%s\n' "${!backups_by_month[@]}" | sort); do
	mapfile -t month_files < <(echo -n "${backups_by_month[$year_month]}" | sort)

	if [[ "$year_month" == "$current_month" ]]; then
		# Keep all backups for current month
		echo "Month $year_month (current): keeping all ${#month_files[@]} backup(s)" >&2
		for file in "${month_files[@]}"; do
			files_to_keep["$file"]=1
		done
	elif [[ "$year_month" == "$previous_month" ]]; then
		if [[ ${#month_files[@]} -lt 7 ]]; then
			# Already cleaned up, keep all remaining backups
			echo "Month $year_month (previous): already cleaned up, keeping all ${#month_files[@]} backup(s)" >&2
			for file in "${month_files[@]}"; do
				files_to_keep["$file"]=1
			done
		else
			# Keep every 7th backup for previous month
			echo "Month $year_month (previous): keeping every 7th backup" >&2
			for ((i = 0; i < ${#month_files[@]}; i += 7)); do
				files_to_keep["${month_files[$i]}"]=1
				echo "  Keeping: ${month_files[$i]} (position $((i + 1)))" >&2
			done
		fi
	else
		# Keep only first backup for older months
		echo "Month $year_month (older): keeping only first backup" >&2
		files_to_keep["${month_files[0]}"]=1
		echo "  Keeping: ${month_files[0]}" >&2
	fi
done

echo >&2

# Determine files to delete
declare -a files_to_delete
for file in "${sorted_backups[@]}"; do
	if [[ ! -v files_to_keep["$file"] ]]; then
		files_to_delete+=("$file")
	fi
done

if [[ ! -v files_to_delete[0] ]]; then
	echo "No backups to delete" >&2
	exit 0
fi

# Show files to delete
echo "The following ${#files_to_delete[@]} backup(s) will be deleted:" >&2
for file in "${files_to_delete[@]+"${files_to_delete[@]}"}"; do
	echo "  - $file" >&2
done
echo >&2

# Ask for confirmation
read -r -p "Proceed with deletion? [y/N] " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
	echo "Aborted" >&2
	exit 0
fi

# Delete files from both locations
echo >&2
echo "Deleting backups..." >&2
for file in "${files_to_delete[@]+"${files_to_delete[@]}"}"; do
	# Delete from iCloud
	if [[ -f "$icloud_dir/$file" ]]; then
		echo "  Deleting from iCloud: $file" >&2
		rm -f "$icloud_dir/$file"
	fi

	# Delete from Google Drive
	if "$rclone_bin" ls "$gdrive_remote/$file" >/dev/null 2>&1; then
		echo "  Deleting from Google Drive: $file" >&2
		"$rclone_bin" delete "$gdrive_remote/$file"
	fi
done

echo >&2
echo "Cleanup complete. Deleted ${#files_to_delete[@]} backup(s)." >&2
