#!/usr/bin/env bash
set -euo pipefail

# megalint.sh — Unified prompt linter for OpenClaw MDS
# Runs 4 tools in parallel, merges results into a consistent report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

AGENTS_DIR="$REPO_ROOT/src/agents"
SHARED_DIR="$REPO_ROOT/src/shared"

# Env overrides (highest priority)
[[ -n "${MEGALINT_AGENTS_DIR:-}" ]] && AGENTS_DIR="$MEGALINT_AGENTS_DIR"
[[ -n "${MEGALINT_SHARED_DIR:-}" ]] && SHARED_DIR="$MEGALINT_SHARED_DIR"

command -v rg >/dev/null 2>&1 || { printf '\033[31m%s\033[0m\n' "ripgrep (rg) not found — install for Home-Grow checks"; exit 1; }

AGENTLINTER_BIN="$SCRIPT_DIR/apps/agentlinter/packages/cli/dist/bin.js"
PROMPTLINT_BIN="$SCRIPT_DIR/apps/promptlint/.venv/bin/promptlint"
HARDENER_BIN="$SCRIPT_DIR/apps/prompt-hardener/.venv/bin/prompt-hardener"

PY="$SCRIPT_DIR/apps/promptlint/.venv/bin/python"
[[ -x "$PY" ]] || { printf '\033[31m%s\033[0m\n' "Python venv not found at $PY — run: cd apps/promptlint && uv venv .venv && uv pip install -e ."; exit 1; }
NODE="$(command -v node 2>/dev/null)" || { printf '\033[31m%s\033[0m\n' "node not found — install Node.js"; exit 1; }

red()    { printf "\033[31m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
green()  { printf "\033[32m%s\033[0m" "$1"; }
cyan()   { printf "\033[36m%s\033[0m" "$1"; }
bold()   { printf "\033[1m%s\033[0m" "$1"; }
dim()    { printf "\033[2m%s\033[0m" "$1"; }

score_color() {
  [[ "$1" == "N/A" ]] && { dim "$1"; return; }
  local s
  s=$(printf "%.0f" "$1" 2>/dev/null || echo 0)
  if [[ $s -ge 90 ]]; then green "$1"
  elif [[ $s -ge 70 ]]; then yellow "$1"
  else red "$1"; fi
}

# ─── Load .env ────────────────────────────────────────────────────────────────

for envfile in "$SCRIPT_DIR/.env" "$REPO_ROOT/.env"; do
  if [[ -f "$envfile" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$envfile"
    set +a
    break
  fi
done

# ─── Load config ──────────────────────────────────────────────────────────────

WEIGHT_STRUCTURE=25; WEIGHT_QUALITY=18; WEIGHT_CONSISTENCY=22; WEIGHT_SECURITY=20; WEIGHT_BUDGET=15
PASS_THRESHOLD=70; BLOCKING_ERRORS=true
GRADE_S=97; GRADE_A_PLUS=95; GRADE_A=93; GRADE_A_MINUS=90
GRADE_B_PLUS=87; GRADE_B=83; GRADE_B_MINUS=80
GRADE_C_PLUS=77; GRADE_C=73; GRADE_C_MINUS=70; GRADE_D=60

CONF_FILE="$SCRIPT_DIR/megalint.conf"
# shellcheck source=/dev/null
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# ─── Parse flags ─────────────────────────────────────────────────────────────

YES_FLAG=true
HELP_FLAG=false
MODEL_FLAG=""
FORMAT_FLAG=""
THRESHOLD_FLAG=""
BLOCKING_FLAG=""
AGENTS_DIR_FLAG=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  # shellcheck source=/dev/null
  case "$1" in
    --yes|-y)              YES_FLAG=true; shift ;;
    --no-yes)              YES_FLAG=false; shift ;;
    --help|-h)             HELP_FLAG=true; shift ;;
    --model|-m)            MODEL_FLAG="$2"; shift 2 ;;
    --model=*)             MODEL_FLAG="${1#*=}"; shift ;;
    --format|-f)           FORMAT_FLAG="$2"; shift 2 ;;
    --format=*)            FORMAT_FLAG="${1#*=}"; shift ;;
    --pass-threshold)      THRESHOLD_FLAG="$2"; shift 2 ;;
    --pass-threshold=*)    THRESHOLD_FLAG="${1#*=}"; shift ;;
    --no-blocking)         BLOCKING_FLAG="false"; shift ;;
    --agents-dir|-d)       AGENTS_DIR_FLAG="$2"; shift 2 ;;
    --agents-dir=*)        AGENTS_DIR_FLAG="${1#*=}"; shift ;;
    --config|-c)           source "$2"; shift 2 ;;
    --config=*)            source "${1#*=}"; shift ;;
    *)                     POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done

[[ -n "$THRESHOLD_FLAG" ]] && PASS_THRESHOLD="$THRESHOLD_FLAG"
[[ -n "$BLOCKING_FLAG" ]] && BLOCKING_ERRORS="$BLOCKING_FLAG"
if [[ -n "$AGENTS_DIR_FLAG" ]]; then
  if [[ -d "$REPO_ROOT/$AGENTS_DIR_FLAG" ]]; then
    AGENTS_DIR="$REPO_ROOT/$AGENTS_DIR_FLAG"
  elif [[ -d "$AGENTS_DIR_FLAG" ]]; then
    AGENTS_DIR="$(cd "$AGENTS_DIR_FLAG" && pwd)"
  else
    echo "$(red "Agents directory not found: $AGENTS_DIR_FLAG")"; exit 1
  fi
fi

if [[ -n "$FORMAT_FLAG" ]] && [[ ! "$FORMAT_FLAG" =~ ^(json|md|both)$ ]]; then
  echo "$(red "Unknown format: $FORMAT_FLAG (use json, md, or both)")"; exit 1
fi

if [[ "$HELP_FLAG" == "true" ]]; then
  cat <<'HELP'

megalint — Unified prompt linter for OpenClaw MDS

Usage: ./megalint.sh [options] [agent-path...]

Options:
  -d, --agents-dir DIR       Override agents directory (auto-detects agents/ or src/agents/)
  -y, --yes                  Auto-approve Prompt Hardener API cost (default)
  --no-yes                   Prompt for confirmation before API calls
  -m, --model MODEL          Override model (claude-opus-4-6 | claude-sonnet-4-6)
  -f, --format FORMAT        Output report: json, md, or both (saved to .reports/)
  --pass-threshold N         Minimum score to pass (default: 70)
  --no-blocking              Don't fail on Home-Grow errors regardless of score
  -c, --config FILE          Load alternate config file
  -h, --help                 Show this help

Token Budget Tiers (2 levels, configurable in rules.conf):
  INFO   base × 1.25   25% over — heads-up
  WARN   base × 1.50   50% over — should trim
  (Token budgets never block — graduated scoring via Token Budget pillar)

Environment Variable Overrides:
  MEGALINT_AGENTS_DIR        Override agents directory
  MEGALINT_SHARED_DIR        Override shared directory
  MEGALINT_BUDGET_AGENTS_MD  Override AGENTS.md token budget (default: 1725)
  MEGALINT_BUDGET_SOUL_MD    Override SOUL.md token budget (default: 525)
  MEGALINT_BUDGET_*_MD       Override any file budget (IDENTITY, USER, TOOLS, etc.)
  MEGALINT_TIER_INFO         Override INFO multiplier (default: 1.25)
  MEGALINT_TIER_WARN         Override WARN multiplier (default: 1.50)

Scoring (5 pillars, configurable in megalint.conf):
  Structure    25%   AgentLinter    — workspace structure, clarity, rules
  Quality      18%   PromptLint     — per-file clarity score (0-10 → 0-100)
  Consistency  22%   Home-Grow      — cross-agent consistency checks
  Security     20%   Prompt Hardener — LLM injection testing (skipped = redistributed)
  Token Budget 15%   Length scoring  — per-file token usage vs budget (100 at budget → 0 at 5×)

Models:
  claude-opus-4-6      $5/MTok in, $25/MTok out  (default, strongest)
  claude-sonnet-4-6    $3/MTok in, $15/MTok out  (fast)

Examples:
  ./megalint.sh                                           # All agents (auto-detect)
  ./megalint.sh --agents-dir src/agents-planned           # All planned agents
  ./megalint.sh src/agents-planned/soren                  # Single agent by path
  ./megalint.sh --format both --yes                       # JSON + Markdown reports
  ./megalint.sh --pass-threshold 85                       # Stricter pass bar
  ./megalint.sh --no-blocking --agents-dir src/agents     # Prod agents, lenient
  MEGALINT_BUDGET_SOUL_MD=850 ./megalint.sh               # Override SOUL.md budget (256k tier)
  MEGALINT_TIER_WARN=1.40 ./megalint.sh                   # Tighter warn threshold

Config: megalint.conf (weights, thresholds, grades)
Rules:  apps/homegrow/rules.conf (budgets, tier multipliers, check toggles)
Env:    .env (API keys — see .env.example)

HELP
  exit 0
fi

# ─── Git metadata ─────────────────────────────────────────────────────────────

GIT_COMMIT=$(cd "$REPO_ROOT" && command git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(cd "$REPO_ROOT" && command git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(cd "$REPO_ROOT" && command git diff --quiet 2>/dev/null && echo "false" || echo "true")
GIT_MSG=$(cd "$REPO_ROOT" && command git log -1 --format='%s' 2>/dev/null || echo "")

# ─── Setup ────────────────────────────────────────────────────────────────────

REPORT_DIR="$SCRIPT_DIR/.reports"
mkdir -p "$REPORT_DIR"
RUN_TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
RUN_ID="${GIT_COMMIT}_${RUN_TIMESTAMP}"
LOG_FILE="$REPORT_DIR/lint-run_${RUN_ID}.log"
TMPDIR_RUN=$(mktemp -d /tmp/megalint-XXXXXX)
cleanup() { command rm -rf "${TMPDIR_RUN:-}" 2>/dev/null; }
trap cleanup EXIT INT TERM

log() { printf '%s\n' "$1" >> "$LOG_FILE"; }
log_section() { log ""; log "═══ $1 ═══"; log ""; }

log "Run ID: $RUN_ID"
log "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "Git: commit=$GIT_COMMIT branch=$GIT_BRANCH dirty=$GIT_DIRTY"
log "Git message: $GIT_MSG"
log "Working directory: $REPO_ROOT"

# Determine agents + resolve directories
declare -A AGENT_DIRS=()
declare -a BROKEN_SYMLINKS=()
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
  AGENTS=()
  for arg in "${POSITIONAL_ARGS[@]}"; do
    arg="${arg%/}"
    resolved=""
    if [[ -d "$REPO_ROOT/$arg" ]]; then
      resolved="$REPO_ROOT/$arg"
    elif [[ -d "$arg" ]]; then
      resolved="$(cd "$arg" && pwd)"
    elif [[ -d "$AGENTS_DIR/$arg" ]]; then
      resolved="$AGENTS_DIR/$arg"
    else
      echo "$(red "Agent not found: $arg")"; exit 1
    fi
    name="$(basename "$resolved")"
    AGENTS+=("$name")
    AGENT_DIRS[$name]="$resolved"
  done
else
  AGENTS=()
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ "$name" == "template" || "$name" == "nick-template" ]] && continue
    AGENTS+=("$name")
    AGENT_DIRS[$name]="${d%/}"
  done
  # Broken symlinks don't match */ — scan separately with -L (true for any symlink) and ! -e (true when target missing)
  for entry in "$AGENTS_DIR"/*; do
    [[ -L "$entry" && ! -e "$entry" ]] || continue
    name="$(basename "$entry")"
    BROKEN_SYMLINKS+=("$name → $(readlink "$entry" 2>/dev/null || echo '?')")
  done
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
  echo "$(red "No agents found in $AGENTS_DIR")"; exit 1
fi

# Warn about broken symlinks
if [[ ${#BROKEN_SYMLINKS[@]} -gt 0 ]]; then
  for _bl in "${BROKEN_SYMLINKS[@]}"; do
    echo "  $(yellow "WARN:") Broken symlink skipped: $_bl"
    log "WARN: Broken symlink skipped: $_bl"
  done
  echo ""
fi

log "Agents: ${AGENTS[*]}"

# Standard agent definition files — only these are linted by PromptLint and Hardener.
# Production workspaces may contain extra .md files (research docs, reports, memory logs)
# that are NOT agent definitions and would distort quality/security scores.
STANDARD_MD_FILES=(AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md MEMORY.md BOOT.md)

# ═══════════════════════════════════════════════════════════════════════════════
# Run Tools 1, 2, 3 in parallel (Tool 4 needs user confirmation so runs after)
# ═══════════════════════════════════════════════════════════════════════════════

AL_DIR="$TMPDIR_RUN/agentlinter"
PL_DIR="$TMPDIR_RUN/promptlint"
HG_DIR="$TMPDIR_RUN/homegrow"
mkdir -p "$AL_DIR" "$PL_DIR" "$HG_DIR"

# ─── Tool 1: AgentLinter (background) ────────────────────────────────────────
(
  for agent in "${AGENTS[@]}"; do
    agent_dir="${AGENT_DIRS[$agent]}"
    [[ ! -d "$agent_dir" ]] && continue
    json=$($NODE "$AGENTLINTER_BIN" --json --no-share --no-audit "$agent_dir" 2>/dev/null || echo '{}')
    echo "$json" > "$AL_DIR/${agent}.json"
  done
) &
AL_PID=$!

# ─── Tool 2: PromptLint (background) ─────────────────────────────────────────
(
  for agent in "${AGENTS[@]}"; do
    agent_dir="${AGENT_DIRS[$agent]}"
    [[ ! -d "$agent_dir" ]] && continue
    mkdir -p "$PL_DIR/$agent"
    for fname in "${STANDARD_MD_FILES[@]}"; do
      mdfile="$agent_dir/$fname"
      [[ -f "$mdfile" ]] || continue
      outfile="$PL_DIR/$agent/$fname.json"
      if ! "$PROMPTLINT_BIN" score "$mdfile" --format json > "$outfile" 2>/dev/null; then
        echo '{"_error": true, "reason": "PromptLint binary failed"}' > "$outfile"
      fi
      # Verify JSON is valid and non-empty
      if [[ ! -s "$outfile" ]] || ! $PY -c "import json; json.load(open('$outfile'))" 2>/dev/null; then
        echo '{"_error": true, "reason": "Invalid or empty JSON output"}' > "$outfile"
      fi
    done
  done
) &
PL_PID=$!

# ─── Tool 3: Home-Grow Linter (background) ───────────────────────────────────
HG_AGENTS_DIR="$TMPDIR_RUN/hg_agents"
mkdir -p "$HG_AGENTS_DIR"
for _a in "${AGENTS[@]}"; do
  ln -sf "${AGENT_DIRS[$_a]}" "$HG_AGENTS_DIR/$_a"
done

(
  bash "$SCRIPT_DIR/apps/homegrow/run.sh" "$HG_AGENTS_DIR" "$SHARED_DIR" "${AGENTS[@]}" \
    > "$HG_DIR/results.txt" 2>/dev/null
) &
HG_PID=$!

# ─── Wait for parallel tools ─────────────────────────────────────────────────

echo "  Running tools 1-3 in parallel..."
wait $AL_PID || { log "WARN: AgentLinter exited $?"; echo "  $(yellow "WARN:") AgentLinter exited abnormally"; true; }
wait $PL_PID || { log "WARN: PromptLint exited $?"; echo "  $(yellow "WARN:") PromptLint exited abnormally"; true; }
wait $HG_PID || { log "WARN: Home-Grow exited $?"; echo "  $(yellow "WARN:") Home-Grow exited abnormally"; true; }
echo "  $(green "Done") — processing results"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Tool 4: Prompt Hardener (sequential — needs API calls, user confirmation)
# ═══════════════════════════════════════════════════════════════════════════════

HARDENER_AVAILABLE=false
HARDENER_MODEL=""
HARDENER_PROCEED=false
PH_COUNT=0

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  HARDENER_AVAILABLE=true
  HARDENER_API_MODE="claude"
  if [[ -n "$MODEL_FLAG" ]]; then HARDENER_MODEL="$MODEL_FLAG"
  else HARDENER_MODEL="${PROMPT_HARDENER_MODEL:-claude-opus-4-6}"; fi
fi

if [[ "$HARDENER_AVAILABLE" == "true" ]]; then
  log_section "Tool 4: Prompt Hardener"
  log "Model: $HARDENER_MODEL  API: $HARDENER_API_MODE"

  TOTAL_CHARS=0
  for agent in "${AGENTS[@]}"; do
    agent_dir="${AGENT_DIRS[$agent]}"
    [[ ! -d "$agent_dir" ]] && continue
    for mdfile in "$agent_dir"/*.md; do
      [[ -f "$mdfile" ]] || continue
      fchars=$(wc -c < "$mdfile" | tr -d ' ')
      TOTAL_CHARS=$((TOTAL_CHARS + fchars))
    done
  done

  COST_INFO=$($PY -c "
tc=$TOTAL_CHARS; na=${#AGENTS[@]}; m='$HARDENER_MODEL'
ct=tc/4; ov=1000; op=500
ti=ct+(ov*na); to=op*na
pricing={'claude-sonnet-4-6':{'i':3.0,'o':15.0},'claude-opus-4-6':{'i':5.0,'o':25.0},'claude-haiku-4.5':{'i':0.8,'o':4.0},'anthropic/claude-haiku-4.5':{'i':0.8,'o':4.0}}
p=pricing.get(m,{'i':3.0,'o':15.0})
ci=(ti/1e6)*p['i']; co=(to/1e6)*p['o']; ct_=ci+co
print('TOKENS_IN=%d' % ti)
print('TOKENS_OUT=%d' % to)
print('COST_TOTAL=%.6f' % ct_)
" 2>/dev/null)
  TOKENS_IN=0 TOKENS_OUT=0 COST_TOTAL=0.01
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != *"="* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    [[ -n "$key" ]] && declare -g "$key=$val"
  done <<< "$COST_INFO"

  printf "  %-20s %s\n" "Model:" "$HARDENER_MODEL"
  printf "  %-20s %s\n" "Agents:" "${#AGENTS[@]} (= ${#AGENTS[@]} API calls)"
  printf "  %-20s %s\n" "Est. tokens:" "~$TOKENS_IN in / ~$TOKENS_OUT out"
  printf "  %-20s %s\n" "Est. cost:" "\$$COST_TOTAL"
  echo ""
  log "Cost: model=$HARDENER_MODEL tokens_in=~$TOKENS_IN tokens_out=~$TOKENS_OUT cost=\$$COST_TOTAL"

  HARDENER_PROCEED=false
  if [[ "$YES_FLAG" == "true" ]]; then
    dim "  --yes flag set, proceeding"; echo ""
    HARDENER_PROCEED=true
  else
    printf "  Proceed? [y/N] "; read -r answer
    case "$answer" in [yY]|[yY][eE][sS]) HARDENER_PROCEED=true ;; esac
  fi
  echo ""

  if [[ "$HARDENER_PROCEED" == "true" ]]; then
    PH_DIR="$TMPDIR_RUN/hardener"
    mkdir -p "$PH_DIR"
    for agent in "${AGENTS[@]}"; do
      agent_dir="${AGENT_DIRS[$agent]}"
      [[ ! -d "$agent_dir" ]] && continue

      tmpraw="$TMPDIR_RUN/ph-raw-$agent-$$.md"
      for _ph_fname in "${STANDARD_MD_FILES[@]}"; do
        mdfile="$agent_dir/$_ph_fname"
        [[ -f "$mdfile" ]] || continue
        printf '\n\n--- %s ---\n' "$_ph_fname" >> "$tmpraw"
        command cat "$mdfile" >> "$tmpraw"
      done
      [[ ! -s "$tmpraw" ]] && { command rm -f "$tmpraw"; continue; }

      tmpfile="$TMPDIR_RUN/ph-$agent-$$.json"
      $PY -c "
import json
with open('$tmpraw') as f: content = f.read().strip()
data = {'messages': [{'role': 'system', 'content': content}]}
with open('$tmpfile', 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null
      command rm -f "$tmpraw"

      if [[ -f "$tmpfile" ]]; then
        PH_STDERR="$TMPDIR_RUN/ph-stderr-${agent}.txt"
        "$HARDENER_BIN" evaluate \
          --input-mode chat --input-format openai \
          --target-prompt-path "$tmpfile" \
          --eval-api-mode "$HARDENER_API_MODE" --eval-model "$HARDENER_MODEL" \
          --output-path "$PH_DIR/${agent}_eval.json" \
          --report-dir "$PH_DIR" \
          > /dev/null 2>"$PH_STDERR" || true
        command rm -f "$tmpfile"
        [[ -f "$PH_DIR/${agent}_eval.json" ]] && PH_COUNT=$((PH_COUNT + 1))
      fi
    done
    echo ""
  fi
fi

HARDENER_RAN=false
[[ "$HARDENER_PROCEED" == "true" && $PH_COUNT -gt 0 ]] && HARDENER_RAN=true

# ═══════════════════════════════════════════════════════════════════════════════
# Process all tool outputs → summary.json, display, report
# ═══════════════════════════════════════════════════════════════════════════════

# Write meta.json for process.py
printf '%s' "$GIT_MSG" > "$TMPDIR_RUN/_git_msg.txt"
for _a in "${AGENTS[@]}"; do
  printf '%s\t%s\n' "$_a" "${AGENT_DIRS[$_a]}"
done > "$TMPDIR_RUN/_agent_dirs.txt"

$PY -c "
import json, os
mf = '$TMPDIR_RUN/meta.json'
gf = '$TMPDIR_RUN/_git_msg.txt'
adf = '$TMPDIR_RUN/_agent_dirs.txt'
git_msg = ''
if os.path.isfile(gf):
    with open(gf) as f: git_msg = f.read().strip()
agent_dirs = {}
if os.path.isfile(adf):
    with open(adf) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split('\t', 1)
            if len(parts) >= 2:
                agent_dirs[parts[0]] = parts[1]
agents_list = list(agent_dirs.keys())
meta = {
    'run_id': '$RUN_ID',
    'git_commit': '$GIT_COMMIT',
    'git_branch': '$GIT_BRANCH',
    'git_dirty': '$GIT_DIRTY' == 'true',
    'git_msg': git_msg,
    'timestamp': '$(date -u "+%Y-%m-%dT%H:%M:%SZ")',
    'agents_list': agents_list,
    'agent_dirs': agent_dirs,
}
if '$HARDENER_RAN' == 'true':
    meta['hardener_model'] = '$HARDENER_MODEL'
with open(mf, 'w') as f:
    json.dump(meta, f, indent=2)
" 2>/dev/null

# Run process.py (parses tools, scores, writes summary.json)
PROC_ARGS=(--tmp-dir "$TMPDIR_RUN" --config "$CONF_FILE" --hardener-ran "$([ "$HARDENER_RAN" = "true" ] && echo true || echo false)")
[[ -n "$THRESHOLD_FLAG" ]] && PROC_ARGS+=(--pass-threshold "$PASS_THRESHOLD")
[[ "$BLOCKING_FLAG" = "false" ]] && PROC_ARGS+=(--no-blocking)
$PY "$SCRIPT_DIR/lib/process.py" "${PROC_ARGS[@]}" 2>/dev/null || true

# Add hardener tokens to summary meta for report (process already ran)
if [[ "$HARDENER_RAN" == "true" && -d "$TMPDIR_RUN/hardener" ]]; then
  PH_ACTUAL_IN=$($PY -c "
import json, os
t = 0
for f in os.listdir('$TMPDIR_RUN/hardener'):
    if f.endswith('_eval.json'):
        with open(os.path.join('$TMPDIR_RUN/hardener', f)) as fp:
            t += json.load(fp).get('_usage', {}).get('input_tokens', 0)
print(t)
" 2>/dev/null || echo 0)
  PH_ACTUAL_OUT=$($PY -c "
import json, os
t = 0
for f in os.listdir('$TMPDIR_RUN/hardener'):
    if f.endswith('_eval.json'):
        with open(os.path.join('$TMPDIR_RUN/hardener', f)) as fp:
            t += json.load(fp).get('_usage', {}).get('output_tokens', 0)
print(t)
" 2>/dev/null || echo 0)
  $PY -c "
import json
with open('$TMPDIR_RUN/summary.json') as f: s = json.load(f)
s['meta']['hardener_tokens_in'] = $PH_ACTUAL_IN
s['meta']['hardener_tokens_out'] = $PH_ACTUAL_OUT
s['meta']['hardener_model'] = '$HARDENER_MODEL'
with open('$TMPDIR_RUN/summary.json', 'w') as f: json.dump(s, f, indent=2)
" 2>/dev/null
fi

# Display full report
$PY "$SCRIPT_DIR/lib/display.py" --summary "$TMPDIR_RUN/summary.json" --log-file "$LOG_FILE"
EXIT_CODE=$?

# Report output (--format json|md|both)
if [[ -n "$FORMAT_FLAG" ]]; then
  $PY "$SCRIPT_DIR/lib/report.py" \
    --input "$TMPDIR_RUN/summary.json" \
    --format "$FORMAT_FLAG" \
    --output-dir "$REPORT_DIR" 2>/dev/null || true
fi

# Footer
echo ""
dim "  commit: $GIT_COMMIT ($GIT_BRANCH) | run: $RUN_ID"
echo ""
log ""
log "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
dim "  Log: $LOG_FILE"
echo ""

[[ "$EXIT_CODE" -ne 0 ]] && exit "$EXIT_CODE"
exit 0
