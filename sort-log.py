#!/usr/bin/env python3
"""Sort ### HH:MM entries within the ## Log section of an Obsidian daily note.

Usage: sort-log.py <file>

Entries are sorted chronologically by the HH:MM in their ### header.
Content before ## Log and after ## Log (e.g. ## Slack DM Summary) is preserved.
"""

import re
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: sort-log.py <file>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]

    with open(filepath, "r") as f:
        content = f.read()

    # Find ## Log section
    log_match = re.search(r"^## Log\s*\r?\n", content, re.MULTILINE)
    if not log_match:
        print("No ## Log section found", file=sys.stderr)
        sys.exit(1)

    log_start = log_match.end()

    # Find next ## section after Log (e.g. ## Slack DM Summary)
    next_section = re.search(r"^## ", content[log_start:], re.MULTILINE)
    if next_section:
        log_end = log_start + next_section.start()
    else:
        log_end = len(content)

    before = content[:log_start]
    log_body = content[log_start:log_end]
    after = content[log_end:]

    # Preserve original trailing whitespace of the log section
    log_body_stripped = log_body.rstrip("\r\n")
    trailing_ws = log_body[len(log_body_stripped):] or "\n"

    headers = list(re.finditer(r"^### ", log_body, re.MULTILINE))

    if not headers:
        print(f"No log entries to sort in {filepath}")
        sys.exit(0)

    preamble = log_body[:headers[0].start()]

    entries = []
    for i, h in enumerate(headers):
        start = h.start()
        end = headers[i + 1].start() if i + 1 < len(headers) else len(log_body)
        entries.append(log_body[start:end].rstrip("\r\n"))

    def sort_key(block):
        m = re.match(r"### (\d{2}):(\d{2})", block)
        if m:
            return (int(m.group(1)), int(m.group(2)))
        return (99, 99)

    entries.sort(key=sort_key)

    sorted_log = preamble + "\n\n".join(entries) + trailing_ws

    result = before + sorted_log + after

    with open(filepath, "w") as f:
        f.write(result)

    print(f"Sorted {len(entries)} log entries in {filepath}")


if __name__ == "__main__":
    main()
