#!/usr/bin/env python3
"""Compares this repository's Swift code with another repository's, line by line.

    scripts/check-overlap.py /path/to/other/repo

A line counts when it is at least 40 characters long after trimming, is not a comment, and appears in
both (the words Kai and Sentient are treated as the same word). Generic framework calls such as
`panel.orderFrontRegardless()` show up as shared lines; copied logic shows up as a file with many.
It is a screening tool, not legal advice. Run it when adopting code or ideas from another project.
"""
import os
import re
import sys

MIN_LEN = 40
THRESHOLD = 25   # shared lines in one file worth a closer look


def norm(line):
    line = re.sub(r"Kai|Sentient", "X", line.strip())
    return re.sub(r"\s+", " ", line)


def lines_of(path):
    found = set()
    try:
        with open(path, encoding="utf-8", errors="ignore") as handle:
            for raw in handle:
                text = norm(raw)
                if len(text) >= MIN_LEN and not text.startswith("//"):
                    found.add(text)
    except OSError:
        pass
    return found


def swift_files(root):
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in (".git", ".build", "dist")]
        for name in files:
            if name.endswith(".swift"):
                yield os.path.join(base, name)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    other = set()
    for path in swift_files(sys.argv[1]):
        other |= lines_of(path)
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    rows = []
    for path in swift_files(here):
        mine = lines_of(path)
        if mine:
            rows.append((len(mine & other), len(mine), os.path.relpath(path, here)))
    rows.sort(reverse=True)
    flagged = [r for r in rows if r[0] >= THRESHOLD]
    for shared, total, path in rows[:10]:
        print(f"{shared:4d} shared of {total:5d}  {path}")
    print(f"\n{len(flagged)} file(s) with {THRESHOLD}+ shared lines.")
    sys.exit(1 if flagged else 0)


if __name__ == "__main__":
    main()
