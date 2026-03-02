#!/usr/bin/env python3
"""Count tokens in a file using tiktoken (cl100k_base encoding).

Usage: tiktoken_count.py <file_path> [--expand-imports <shared_dir>]
Output: integer token count to stdout

Used by megalint.sh, homegrow/run.sh, and scoring.py for consistent
token counting across the entire linting pipeline.

When --expand-imports is provided, @import() directives are expanded
with their actual directive content before token counting.
"""

import os
import re
import sys

import tiktoken

_enc = tiktoken.get_encoding("cl100k_base")


def count_file(path: str, expand_imports: str | None = None) -> int:
    with open(path) as f:
        content = f.read()

    if expand_imports:
        content = expand_import_directives(content, expand_imports)

    return len(_enc.encode(content))


def expand_import_directives(content: str, shared_dir: str) -> str:
    """Expand @import(directive) directives with their actual content."""
    # Find all @import() directives
    import_pattern = re.compile(r'@import\(([^)]+)\)')

    def replace_import(match):
        import_path = match.group(1)
        directive_file = os.path.join(shared_dir, "directives", f"{import_path}.md")

        if os.path.isfile(directive_file):
            try:
                with open(directive_file, 'r') as f:
                    directive_content = f.read()
                return directive_content
            except (OSError, IOError):
                # If we can't read the directive, keep the import as-is
                return match.group(0)
        else:
            # If directive doesn't exist, keep the import as-is
            return match.group(0)

    return import_pattern.sub(replace_import, content)


def count_text(text: str) -> int:
    return len(_enc.encode(text))


if __name__ == "__main__":
    if len(sys.argv) < 2 or len(sys.argv) > 4:
        print("Usage: tiktoken_count.py <file_path> [--expand-imports <shared_dir>]", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[1]
    expand_imports = None

    if len(sys.argv) >= 3 and sys.argv[2] == "--expand-imports":
        if len(sys.argv) != 4:
            print("Usage: tiktoken_count.py <file_path> [--expand-imports <shared_dir>]", file=sys.stderr)
            sys.exit(1)
        expand_imports = sys.argv[3]

    print(count_file(file_path, expand_imports))
