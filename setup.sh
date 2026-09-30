#!/usr/bin/env bash
set -euo pipefail
#
# megalint setup — install all dependencies in one command
# Usage: ./setup.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

green()  { printf "\033[32m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
red()    { printf "\033[31m%s\033[0m" "$1"; }
bold()   { printf "\033[1m%s\033[0m" "$1"; }

ok()   { echo "  $(green "✓") $1"; }
skip() { echo "  $(yellow "·") $1"; }
fail() { echo "  $(red "✗") $1"; }

echo ""
echo "  ⚡ megalint setup"
echo ""

ERRORS=0

# ── Required: Python 3 ──────────────────────────────────────────────────────

if command -v python3 >/dev/null 2>&1; then
  PY_VER=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
  ok "Python $PY_VER"
else
  fail "Python 3 not found — install: brew install python3"
  ERRORS=$((ERRORS + 1))
fi

# ── Required: ripgrep ────────────────────────────────────────────────────────

if command -v rg >/dev/null 2>&1; then
  ok "ripgrep $(rg --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
else
  fail "ripgrep (rg) not found — install: brew install ripgrep"
  ERRORS=$((ERRORS + 1))
fi

# ── Optional: Node.js ────────────────────────────────────────────────────────

if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version)
  ok "Node.js $NODE_VER"
else
  skip "Node.js not found (optional — AgentLinter structure pillar will be skipped)"
fi

# ── Optional: Bun ────────────────────────────────────────────────────────────

if command -v bun >/dev/null 2>&1; then
  BUN_VER=$(bun --version 2>/dev/null || echo "?")
  ok "Bun $BUN_VER"
else
  skip "Bun not found (optional — web dashboard and MCP server need it)"
fi

# ── Optional: bats ───────────────────────────────────────────────────────────

if command -v bats >/dev/null 2>&1; then
  ok "bats (test runner)"
else
  skip "bats not found (optional — needed for: bats tests/megalint.bats)"
fi

echo ""

# ── Tool venvs ───────────────────────────────────────────────────────────────

UV_OR_PIP=""
if command -v uv >/dev/null 2>&1; then
  UV_OR_PIP="uv"
elif command -v pip3 >/dev/null 2>&1; then
  UV_OR_PIP="pip3"
fi

echo "  Setting up tool venvs..."

# PromptLint
PL_DIR="$SCRIPT_DIR/apps/promptlint"
if [[ -x "$PL_DIR/.venv/bin/python" ]]; then
  ok "PromptLint venv (exists)"
elif [[ -n "$UV_OR_PIP" ]]; then
  echo "  Installing PromptLint..."
  (
    cd "$PL_DIR"
    if [[ "$UV_OR_PIP" == "uv" ]]; then
      uv venv .venv 2>/dev/null
      uv pip install -e . --python .venv/bin/python 2>/dev/null
    else
      python3 -m venv .venv
      .venv/bin/pip install -e . 2>/dev/null
    fi
  ) && ok "PromptLint venv (installed)" || { skip "PromptLint install failed (quality pillar will be skipped)"; }
else
  skip "No uv or pip3 — PromptLint skipped (quality pillar will be skipped)"
fi

# Prompt Hardener
PH_DIR="$SCRIPT_DIR/apps/prompt-hardener"
if [[ -x "$PH_DIR/.venv/bin/python" ]]; then
  ok "Prompt Hardener venv (exists)"
elif [[ -n "$UV_OR_PIP" ]]; then
  echo "  Installing Prompt Hardener..."
  (
    cd "$PH_DIR"
    if [[ "$UV_OR_PIP" == "uv" ]]; then
      uv venv .venv 2>/dev/null
      uv pip install -e . --python .venv/bin/python 2>/dev/null
    else
      python3 -m venv .venv
      .venv/bin/pip install -e . 2>/dev/null
    fi
  ) && ok "Prompt Hardener venv (installed)" || { skip "Prompt Hardener install failed (security pillar will be skipped)"; }
else
  skip "No uv or pip3 — Prompt Hardener skipped (security pillar needs ANTHROPIC_API_KEY too)"
fi

# AgentLinter node_modules
AL_DIR="$SCRIPT_DIR/apps/agentlinter"
if [[ -d "$AL_DIR/node_modules" ]]; then
  ok "AgentLinter node_modules (exists)"
elif command -v bun >/dev/null 2>&1; then
  echo "  Installing AgentLinter..."
  (cd "$AL_DIR" && bun install 2>/dev/null) && ok "AgentLinter node_modules (installed)" || skip "AgentLinter install failed (structure pillar will be skipped)"
elif command -v npm >/dev/null 2>&1; then
  echo "  Installing AgentLinter..."
  (cd "$AL_DIR" && npm install 2>/dev/null) && ok "AgentLinter node_modules (installed)" || skip "AgentLinter install failed"
else
  skip "No bun or npm — AgentLinter skipped (structure pillar will be skipped)"
fi

# MCP SDK
if [[ -d "$SCRIPT_DIR/node_modules/@modelcontextprotocol" ]]; then
  ok "MCP SDK (exists)"
elif command -v bun >/dev/null 2>&1; then
  (cd "$SCRIPT_DIR" && bun install 2>/dev/null) && ok "MCP SDK (installed)" || skip "MCP SDK install failed"
else
  skip "No bun — MCP SDK skipped (MCP server needs it)"
fi

echo ""

# ── .env ─────────────────────────────────────────────────────────────────────

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  ok ".env file (exists)"
else
  skip ".env not found — copy .env.example and set ANTHROPIC_API_KEY for Prompt Hardener"
fi

echo ""

# ── Verify ───────────────────────────────────────────────────────────────────

if [[ $ERRORS -gt 0 ]]; then
  echo "  $(red "✗") $ERRORS required dependency missing — fix above and re-run ./setup.sh"
  exit 1
fi

echo "  $(green "✓") $(bold "Ready!") Run: ./megalint.sh --help"
echo ""
