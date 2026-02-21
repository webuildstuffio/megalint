#!/usr/bin/env bash
# PromptLint activation script (portable)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source .venv/bin/activate
export PATH="$SCRIPT_DIR/.venv/bin:$PATH"
alias promptlint="python -m promptlint.cli"
echo "✅ PromptLint environment activated!"
echo "Try: promptlint --help"
