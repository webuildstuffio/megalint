#!/usr/bin/env python3
"""Count tokens in a file using tiktoken (cl100k_base encoding).

Usage: tiktoken_count.py <file_path>
Output: integer token count to stdout

Used by megalint.sh, homegrow/run.sh, and scoring.py for consistent
token counting across the entire linting pipeline.
"""

import sys

import tiktoken

_enc = tiktoken.get_encoding("cl100k_base")


def count_file(path: str) -> int:
    with open(path) as f:
        return len(_enc.encode(f.read()))


def count_text(text: str) -> int:
    return len(_enc.encode(text))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: tiktoken_count.py <file_path>", file=sys.stderr)
        sys.exit(1)
    print(count_file(sys.argv[1]))
