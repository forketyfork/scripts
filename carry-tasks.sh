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

# Find the most recent diary note before today
PREV_FILE=""
for f in "$DIARY_DIR"/*.md; do
	basename_f="$(basename "$f" .md)"
	if [[ "$basename_f" < "$TODAY" ]]; then
		PREV_FILE="$f"
	fi
done

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
    { print }
')

# Remove trailing blank lines from UNCHECKED
UNCHECKED=$(printf '%s\n' "$UNCHECKED" | awk 'NF{p=1} p' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--) if(lines[i]~/[^ \t]/) {last=i; break} for(i=1;i<=last;i++) print lines[i]}')

if [[ -z "$UNCHECKED" ]]; then
	echo "All tasks were completed. Nothing to carry."
	exit 0
fi

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
tmpfile=$(mktemp)
awk -v tasks="$UNCHECKED" '
    /^## TODO/ {
        print
        print ""
        print tasks
        found_todo=1
        next
    }
    { print }
' "$TODAY_FILE" >"$tmpfile"
mv "$tmpfile" "$TODAY_FILE"

echo "Carried unchecked tasks to today's note."

# Mark unchecked tasks as carried in previous note
# Replace "- [ ] <text>" with "- <text> → carried"
# Also handle indented tasks
tmpfile=$(mktemp)
in_todo=0
while IFS= read -r line; do
	if [[ "$line" =~ ^"## TODO" ]]; then
		in_todo=1
		echo "$line"
	elif [[ $in_todo -eq 1 && "$line" =~ ^"## " ]]; then
		in_todo=0
		echo "$line"
	elif [[ $in_todo -eq 1 && "$line" =~ ^[[:space:]]*-\ \[\ \] ]]; then
		# Unchecked task: remove [ ] and append → carried
		echo "$line" | sed 's/- \[ \] /- /' | sed 's/$/ → carried/'
	else
		echo "$line"
	fi
done <"$PREV_FILE" >"$tmpfile"
mv "$tmpfile" "$PREV_FILE"

echo "Marked carried tasks in previous note."
echo "Done!"
