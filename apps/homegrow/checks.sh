#!/usr/bin/env bash
# Standalone wrapper for homegrow/run.sh — works from any cwd
# Computes REPO_ROOT from script location, verifies rg, calls run.sh
# Usage: tools/megalint/homegrow/checks.sh [agent...]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
AGENTS_DIR="$REPO_ROOT/agents"
SHARED_DIR="$REPO_ROOT/_shared"

exec "$SCRIPT_DIR/run.sh" "$AGENTS_DIR" "$SHARED_DIR" "$@"
