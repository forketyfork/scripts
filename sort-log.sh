#!/usr/bin/env python3
"""Sort ### HH:MM entries within the ## Log section of an Obsidian daily note.

Usage: sort-log.sh <file>

Entries are sorted chronologically by the HH:MM in their ### header.
Content before ## Log and after ## Log (e.g. ## Slack DM Summary) is preserved.
"""

import re
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: sort-log.sh <file>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]

    with open(filepath, "r") as f:
        content = f.read()

    # Find ## Log section
    log_match = re.search(r"^## Log\s*\n", content, re.MULTILINE)
    if not log_match:
        print("No ## Log section found", file=sys.stderr)
        sys.exit(0)

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

    # Split into ### blocks
    blocks = re.split(r"(?=^### )", log_body, flags=re.MULTILINE)

    preamble = ""
    entries = []
    for block in blocks:
        if not block.strip():
            continue
        if block.startswith("### "):
            entries.append(block)
        else:
            preamble += block

    # Extract HH:MM for sorting
    def sort_key(block):
        m = re.match(r"### (\d{2}):(\d{2})", block)
        if m:
            return (int(m.group(1)), int(m.group(2)))
        # Entries without time (e.g. ### — Title) go to the end
        return (99, 99)

    entries.sort(key=sort_key)

    # Reassemble
    sorted_log = preamble + "".join(entries)
    sorted_log = sorted_log.rstrip("\n") + "\n\n"

    result = before + sorted_log + after

    with open(filepath, "w") as f:
        f.write(result)

    print(f"Sorted {len(entries)} log entries in {filepath}")


if __name__ == "__main__":
    main()
