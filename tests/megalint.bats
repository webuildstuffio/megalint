#!/usr/bin/env bats
# Megalint regression tests
# Run: bats tools/megalint/tests/megalint.bats

setup() {
  SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  AGENTS_DIR="$REPO_ROOT/agents"
  SHARED_DIR="$REPO_ROOT/_shared"
  MEGALINT="$SCRIPT_DIR/megalint.sh"
}

# ─── Core functionality ──────────────────────────────────────────────────────

@test "megalint --help exits 0 and shows usage" {
  run "$MEGALINT" --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"--format"* ]]
}

@test "megalint rejects invalid --format" {
  run "$MEGALINT" --format foobar
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Unknown format"* ]]
  [[ "$output" == *"json, md, or both"* ]]
}

@test "megalint runs and produces combined results for a real agent" {
  [[ -d "$AGENTS_DIR" ]] || skip "No agents dir"
  first_agent=$(ls -1 "$AGENTS_DIR" 2>/dev/null | grep -v template | head -1)
  [[ -n "$first_agent" ]] || skip "No agents"
  output=$(printf 'n\n' | timeout 30 "$MEGALINT" "$first_agent" 2>&1) || true
  [[ "$output" == *"Tool 1: AgentLinter"* ]]
  [[ "$output" == *"COMBINED RESULTS"* ]]
}

# ─── Safety regressions ──────────────────────────────────────────────────────

@test "megalint uses safe parsing instead of eval" {
  run grep -n 'eval "\$COST_INFO"\|eval "\$SCORING"' "$MEGALINT"
  [[ "$status" -ne 0 ]]
}

@test "megalint has trap for temp cleanup" {
  grep -q 'trap cleanup EXIT' "$MEGALINT"
}

# ─── Home-Grow deduplication ─────────────────────────────────────────────────

@test "megalint delegates to homegrow/run.sh instead of inline checks" {
  grep -q 'bash "$SCRIPT_DIR/apps/homegrow/run.sh"' "$MEGALINT"
  ! grep -q 'add "OK|shared|' "$MEGALINT"
}

@test "run.sh excludes template from agent discovery" {
  [[ -d "$AGENTS_DIR" ]] || skip "agents dir missing"
  output=$("$SCRIPT_DIR/apps/homegrow/run.sh" "$AGENTS_DIR" "$SHARED_DIR" 2>/dev/null)
  [[ -d "$AGENTS_DIR/template" ]] && [[ "$output" != *"|template|"* ]]
}

@test "run.sh roster count excludes template" {
  [[ -d "$AGENTS_DIR" ]] || skip "agents dir missing"
  [[ -f "$SHARED_DIR/AGENT_ROSTER.md" ]] || skip "AGENT_ROSTER missing"
  run "$SCRIPT_DIR/apps/homegrow/run.sh" "$AGENTS_DIR" "$SHARED_DIR"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"OK|roster|"* ]]
}

# ─── Portability ─────────────────────────────────────────────────────────────

@test "checks.sh works from a subdirectory (not just repo root)" {
  [[ -d "$AGENTS_DIR" ]] || skip "agents dir missing"
  cd "$REPO_ROOT/tools"
  run bash megalint/apps/homegrow/checks.sh
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  [[ -n "$output" ]]
}

@test "promptlint helper scripts have no hardcoded user paths" {
  for f in "$SCRIPT_DIR/apps/promptlint/run.sh" "$SCRIPT_DIR/apps/promptlint/activate.sh"; do
    [[ -f "$f" ]] || continue
    ! grep -qE '/Users/[^/]+|/home/[^/]+' "$f"
  done
}

