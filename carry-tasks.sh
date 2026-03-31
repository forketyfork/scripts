#!/usr/bin/env bash
set -euo pipefail

# carry-tasks.sh — Move unchecked TODO tasks from previous daily note to today's note.
#
# Usage: carry-tasks.sh [VAULT_PATH]
#   VAULT_PATH defaults to ~/Zettelkasten

VAULT="${1:-$HOME/Zettelkasten}"
DIARY_DIR="$VAULT/diary"
TEMPLATE="$VAULT/templates/Daily Note.md"

TODAY=$(date +%Y-%m-%d)
TODAY_FILE="$DIARY_DIR/$TODAY.md"

tmp_today=""
tmp_prev=""
tmp_tasks=""
cleanup() {
	if [[ -n "$tmp_today" && -f "$tmp_today" ]]; then rm -f "$tmp_today"; fi
	if [[ -n "$tmp_prev" && -f "$tmp_prev" ]]; then rm -f "$tmp_prev"; fi
	if [[ -n "$tmp_tasks" && -f "$tmp_tasks" ]]; then rm -f "$tmp_tasks"; fi
}
trap cleanup EXIT

# Find the most recent diary note before today
PREV_FILE=""
shopt -s nullglob
for f in "$DIARY_DIR"/*.md; do
	basename_f="$(basename "$f" .md)"
	[[ "$basename_f" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
	if [[ "$basename_f" < "$TODAY" ]]; then
		PREV_FILE="$f"
	fi
done
shopt -u nullglob

if [[ -z "$PREV_FILE" ]]; then
	echo "Error: No previous daily note found before $TODAY" >&2
	exit 1
fi

echo "Previous note: $PREV_FILE"
echo "Today's note:  $TODAY_FILE"

# Extract ## TODO section from previous note (from ## TODO up to next ## or EOF)
TODO_SECTION=$(awk '
    /^## TODO/ { found=1; next }
    found && /^## / { exit }
    found { print }
' "$PREV_FILE")

if [[ -z "$TODO_SECTION" ]]; then
	echo "No ## TODO section found in previous note. Nothing to carry."
	exit 0
fi

# Filter: keep only unchecked tasks (skip lines starting with - [x])
# Preserve non-task lines (headers, blank lines) as-is
UNCHECKED=$(echo "$TODO_SECTION" | awk '
    /^[[:space:]]*- \[x\]/ { next }
    /→ carried[[:space:]]*$/ { next }
    { print }
')

# Remove leading and trailing blank lines from UNCHECKED
UNCHECKED=$(printf '%s\n' "$UNCHECKED" | awk '
    {lines[NR] = $0}
    NF {if (!first) first = NR; last = NR}
    END {for (i = first; i <= last; i++) print lines[i]}
')

if [[ -z "$UNCHECKED" ]]; then
	echo "All tasks were completed. Nothing to carry."
	exit 0
fi

tmp_tasks=$(mktemp)
printf '%s\n' "$UNCHECKED" >"$tmp_tasks"

# Create today's note from template if it doesn't exist
if [[ ! -f "$TODAY_FILE" ]]; then
	if [[ ! -f "$TEMPLATE" ]]; then
		echo "Error: Template not found at $TEMPLATE" >&2
		exit 1
	fi
	# Replace {{date:YYYY-MM-DD}} placeholder with today's date
	sed "s/{{date:YYYY-MM-DD}}/$TODAY/g" "$TEMPLATE" >"$TODAY_FILE"
	echo "Created today's note from template."
fi

# Insert unchecked tasks into today's ## TODO section
# Strategy: find "## TODO" line in today's file and insert after it
if ! grep -q '^## TODO' "$TODAY_FILE"; then
	echo "Error: No ## TODO section found in today's note" >&2
	exit 1
fi

# Build the new today's file: insert unchecked tasks after ## TODO line,
# before any existing content in that section
tmp_today=$(mktemp)
awk -v tasks_file="$tmp_tasks" '
    !inserted && /^## TODO/ {
        print
        print ""
        while ((getline task_line < tasks_file) > 0) {
            print task_line
        }
        close(tasks_file)
        inserted=1
        next
    }
    { print }
' "$TODAY_FILE" >"$tmp_today"
mv "$tmp_today" "$TODAY_FILE"

echo "Carried unchecked tasks to today's note."

# Remove unchecked tasks from previous note
tmp_prev=$(mktemp)
in_todo=0
while IFS= read -r line; do
	if [[ "$line" =~ ^"## TODO" ]]; then
		in_todo=1
		echo "$line"
	elif [[ $in_todo -eq 1 && "$line" =~ ^"## " ]]; then
		in_todo=0
		echo "$line"
	elif [[ $in_todo -eq 1 && "$line" =~ ^[[:space:]]*-\ \[\ \] ]]; then
		# Unchecked task: skip (moved to today)
		continue
	else
		echo "$line"
	fi
done <"$PREV_FILE" >"$tmp_prev"
mv "$tmp_prev" "$PREV_FILE"

echo "Removed carried tasks from previous note."
echo "Done!"
