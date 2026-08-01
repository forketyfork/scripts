#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# open-prs.sh — List all currently open GitHub pull requests either authored
# by a user or opened in any of that user's repositories, newest first.
#
# Usage: open-prs.sh [GITHUB_USER]
#   GITHUB_USER defaults to the currently authenticated gh user

usage() {
	cat <<EOF
Usage: $(basename "$0") [GITHUB_USER]

Lists all open GitHub pull requests either authored by GITHUB_USER or opened
in any repository owned by GITHUB_USER, sorted by creation date (newest first).

  GITHUB_USER   GitHub username to query (default: currently authenticated gh user)

Requires: gh (authenticated), jq
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

handle_error() {
	echo "Error on line $1" >&2
}
trap 'handle_error $LINENO' ERR

for tool in gh jq; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "Error: required tool '$tool' not found in PATH" >&2
		exit 1
	fi
done

by_author=""
by_owner=""
cleanup() {
	[[ -n "$by_author" && -f "$by_author" ]] && rm -f "$by_author"
	[[ -n "$by_owner" && -f "$by_owner" ]] && rm -f "$by_owner"
}
trap cleanup EXIT

readonly gh_user="${1:-$(gh api user --jq .login)}"

by_author=$(mktemp)
by_owner=$(mktemp)
readonly by_author by_owner

gh search prs --author="$gh_user" --state=open --limit=1000 \
	--json repository,title,number,createdAt,url,author >"$by_author"

gh search prs --owner="$gh_user" --state=open --limit=1000 \
	--json repository,title,number,createdAt,url,author >"$by_owner"

prs=$(jq -s '
	add
	| unique_by(.url)
	| sort_by(.createdAt)
	| reverse
' "$by_author" "$by_owner")

count=$(jq 'length' <<<"$prs")

if [[ "$count" -eq 0 ]]; then
	echo "No open pull requests found for '$gh_user' or their repositories."
	exit 0
fi

echo "Open pull requests authored by '$gh_user' or in their repositories ($count, newest first):"
echo

jq -r '
	.[] |
	"\(.createdAt | split("T")[0])  \(.repository.nameWithOwner) #\(.number)  (by \(.author.login))\n  \(.title)\n  \(.url)\n"
' <<<"$prs"
