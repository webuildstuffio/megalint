#!/usr/bin/env bash

# Quick runner for PromptLint
# Usage: ./run.sh score examples/good_prompt.txt
#        ./run.sh diff examples/basic.txt examples/good.txt
#        ./run.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -z "${VIRTUAL_ENV:-}" ]]; then
  source .venv/bin/activate
fi

python -m promptlint.cli "$@"
