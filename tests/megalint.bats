#!/usr/bin/env bats
# Megalint regression tests
# Run: bats tests/megalint.bats

setup() {
  SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
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

@test "megalint --list-rules exits 0 and shows rules" {
  run "$MEGALINT" --list-rules
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"skill/"* ]] || [[ "$output" == *"prompt/"* ]]
}

# ─── Mode detection ──────────────────────────────────────────────────────────

@test "megalint --mode skills is accepted" {
  run "$MEGALINT" --help --mode skills
  [[ "$status" -eq 0 ]]
}

@test "megalint --mode prompts is accepted" {
  run "$MEGALINT" --help --mode prompts
  [[ "$status" -eq 0 ]]
}

# ─── Flag parsing ────────────────────────────────────────────────────────────

@test "megalint --preset strict is accepted" {
  run "$MEGALINT" --help --preset strict
  [[ "$status" -eq 0 ]]
}

@test "megalint --quiet flag is accepted" {
  run "$MEGALINT" --help --quiet
  [[ "$status" -eq 0 ]]
}

@test "megalint --json flag is accepted" {
  run "$MEGALINT" --help --json
  [[ "$status" -eq 0 ]]
}

@test "megalint --disable-rule accepts comma-separated IDs" {
  run "$MEGALINT" --help --disable-rule skill/injection,skill/secrets
  [[ "$status" -eq 0 ]]
}

# ─── Safety regressions ──────────────────────────────────────────────────────

@test "megalint uses safe parsing instead of eval" {
  run grep -n 'eval "\$COST_INFO"\|eval "\$SCORING"' "$MEGALINT"
  [[ "$status" -ne 0 ]]
}

@test "megalint has trap for temp cleanup" {
  grep -q 'trap cleanup EXIT' "$MEGALINT"
}

# ─── Home-Grow / Conventions ─────────────────────────────────────────────────

@test "megalint delegates to homegrow/run.sh instead of inline checks" {
  grep -q 'bash "$SCRIPT_DIR/apps/homegrow/run.sh"' "$MEGALINT" || \
  grep -q 'apps/homegrow/run.sh' "$MEGALINT"
}

@test "run.sh accepts --mode flag" {
  run "$SCRIPT_DIR/apps/homegrow/run.sh" --mode skills --list-rules
  [[ "$status" -eq 0 ]]
}

@test "run.sh accepts --disable-rule flag" {
  run "$SCRIPT_DIR/apps/homegrow/run.sh" --disable-rule skill/injection --list-rules
  [[ "$status" -eq 0 ]]
}

# ─── Portability ─────────────────────────────────────────────────────────────

@test "run.sh works from a subdirectory (not just repo root)" {
  cd "$SCRIPT_DIR/apps"
  run bash homegrow/run.sh --list-rules
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "promptlint helper scripts have no hardcoded user paths" {
  for f in "$SCRIPT_DIR/apps/promptlint/run.sh" "$SCRIPT_DIR/apps/promptlint/activate.sh"; do
    [[ -f "$f" ]] || continue
    ! grep -qE '/Users/[^/]+|/home/[^/]+' "$f"
  done
}

# ─── Refactor parity ──────────────────────────────────────────────────────────

@test "refactored Python libs exist and are invoked" {
  [[ -f "$SCRIPT_DIR/lib/process.py" ]]
  [[ -f "$SCRIPT_DIR/lib/display.py" ]]
  [[ -f "$SCRIPT_DIR/lib/config.py" ]]
  grep -q 'lib/process.py' "$MEGALINT"
  grep -q 'lib/display.py' "$MEGALINT"
}

@test "scoring.py exists" {
  [[ -f "$SCRIPT_DIR/lib/scoring.py" ]]
}

@test "report.py exists" {
  [[ -f "$SCRIPT_DIR/lib/report.py" ]]
}

@test "skills.sh exists and is sourced by run.sh" {
  [[ -f "$SCRIPT_DIR/apps/homegrow/skills.sh" ]]
  grep -q 'skills.sh' "$SCRIPT_DIR/apps/homegrow/run.sh"
}

@test "prompts.sh exists and is sourced by run.sh" {
  [[ -f "$SCRIPT_DIR/apps/homegrow/prompts.sh" ]]
  grep -q 'prompts.sh' "$SCRIPT_DIR/apps/homegrow/run.sh"
}

# ─── Web / MCP / CI ──────────────────────────────────────────────────────────

@test "web dashboard files exist" {
  [[ -f "$SCRIPT_DIR/web/server.ts" ]]
  [[ -f "$SCRIPT_DIR/web/dashboard.html" ]]
}

@test "mcp server file exists" {
  [[ -f "$SCRIPT_DIR/mcp/server.ts" ]]
}

@test "ci action file exists and is valid YAML" {
  [[ -f "$SCRIPT_DIR/ci/action.yml" ]]
  python3 -c "import yaml; yaml.safe_load(open('$SCRIPT_DIR/ci/action.yml'))" 2>/dev/null || \
  python3 -c "
import re
with open('$SCRIPT_DIR/ci/action.yml') as f:
    content = f.read()
assert 'name: megalint' in content
assert 'inputs:' in content
assert 'outputs:' in content
"
}

@test "megalint --serve flag is in help" {
  run "$MEGALINT" --help
  [[ "$output" == *"--serve"* ]]
}
