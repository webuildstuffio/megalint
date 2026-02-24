#!/usr/bin/env bash
set -euo pipefail

# megalint.sh — Unified prompt linter for OpenClaw MDS
# Runs 4 tools in parallel, merges results into a consistent report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

AGENTS_DIR="$REPO_ROOT/src/agents-refined"
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
  MEGALINT_BUDGET_AGENTS_MD  Override AGENTS.md token budget (default: 1150)
  MEGALINT_BUDGET_SOUL_MD    Override SOUL.md token budget (default: 350)
  MEGALINT_BUDGET_*_MD       Override any file budget (IDENTITY, USER, TOOLS, etc.)
  MEGALINT_TIER_INFO         Override INFO multiplier (default: 1.25)
  MEGALINT_TIER_WARN         Override WARN multiplier (default: 1.50)

Scoring (5 pillars, configurable in megalint.conf):
  Structure    25%   AgentLinter    — workspace structure, clarity, rules
  Quality      18%   PromptLint     — per-file clarity score (0-10 → 0-100)
  Consistency  22%   Home-Grow      — cross-agent consistency checks
  Security     20%   Prompt Hardener — LLM injection testing (skipped = redistributed)
  Token Budget 15%   Length scoring  — per-file token usage vs budget (100 at budget → 0 at 3×)

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
  MEGALINT_BUDGET_SOUL_MD=300 ./megalint.sh               # Raise SOUL.md budget
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

echo ""
bold "╔══════════════════════════════════════════════════════════════╗"
echo ""
bold "║         Unified Prompt Linter — OpenClaw MDS               ║"
echo ""
bold "╚══════════════════════════════════════════════════════════════╝"
echo ""
dim "  commit: $GIT_COMMIT ($GIT_BRANCH)$([ "$GIT_DIRTY" = "true" ] && echo " [dirty]")"
echo ""
echo ""

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
    for mdfile in "$agent_dir"/*.md; do
      [[ -f "$mdfile" ]] || continue
      fname=$(basename "$mdfile")
      # Skip BOOTSTRAP.md — ephemeral file deleted after first run, not ongoing quality signal
      [[ "$fname" == "BOOTSTRAP.md" ]] && continue
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
# Process Tool 1: AgentLinter
# ═══════════════════════════════════════════════════════════════════════════════

log_section "Tool 1: AgentLinter"
bold "━━━ Tool 1: AgentLinter ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

declare -A AL_SCORES
TOTAL_AL_SCORE=0
TOTAL_CRITICALS=0
TOTAL_WARNINGS=0
TOTAL_WS_WARNING_COUNT=0
AGENT_COUNT=0

# Track workspace-level warnings to deduplicate across agents
declare -A SEEN_WORKSPACE_WARNINGS=()

for agent in "${AGENTS[@]}"; do
  al_file="$AL_DIR/${agent}.json"
  [[ ! -f "$al_file" ]] && continue

  parsed=$($PY -c "
import json,sys
try:
    with open('$al_file') as _f: d=json.load(_f)
except (json.JSONDecodeError, OSError): d={}
score=d.get('score',0)
diags=d.get('diagnostics',[])
crits=sum(1 for x in diags if x.get('severity') in ('critical','error'))
warns=sum(1 for x in diags if x.get('severity')=='warning')
# Count workspace-level warnings separately for deduplication
ws_warns=sum(1 for x in diags if x.get('severity')=='warning' and x.get('file','')=='(workspace)')
agent_warns=warns-ws_warns
# Collect workspace-level warning rule IDs
ws_rules=[x.get('rule','') for x in diags if x.get('severity')=='warning' and x.get('file','')=='(workspace)']
cats=d.get('categories',[])
cat_str='|'.join(f\"{c['name']}:{c['score']}\" for c in cats)
ws_str=','.join(ws_rules) if ws_rules else ''
print(f'{score};;{crits};;{warns};;{cat_str};;{ws_str};;{agent_warns}')
" 2>/dev/null || echo "0;;0;;0;;;;;0")

  score=$(echo "$parsed" | awk -F';;' '{print $1}')
  criticals=$(echo "$parsed" | awk -F';;' '{print $2}')
  warnings=$(echo "$parsed" | awk -F';;' '{print $3}')
  cat_data=$(echo "$parsed" | awk -F';;' '{print $4}')
  ws_rules=$(echo "$parsed" | awk -F';;' '{print $5}')
  agent_warnings=$(echo "$parsed" | awk -F';;' '{print $6}')

  AL_SCORES[$agent]=$score
  TOTAL_AL_SCORE=$((TOTAL_AL_SCORE + score))
  TOTAL_CRITICALS=$((TOTAL_CRITICALS + criticals))
  TOTAL_WARNINGS=$((TOTAL_WARNINGS + warnings))
  TOTAL_WS_WARNING_COUNT=$((TOTAL_WS_WARNING_COUNT + warnings - agent_warnings))
  AGENT_COUNT=$((AGENT_COUNT + 1))
  log "AgentLinter | $agent | score=$score criticals=$criticals warnings=$warnings"

  # Track workspace-level warnings for dedup summary
  if [[ -n "$ws_rules" ]]; then
    IFS=',' read -ra wrules <<< "$ws_rules"
    for wr in "${wrules[@]}"; do
      [[ -z "$wr" ]] && continue
      SEEN_WORKSPACE_WARNINGS[$wr]=$(( ${SEEN_WORKSPACE_WARNINGS[$wr]:-0} + 1 ))
    done
  fi

  if [[ $score -ge 90 ]]; then sc="$(green "$score/100")"
  elif [[ $score -ge 70 ]]; then sc="$(yellow "$score/100")"
  else sc="$(red "$score/100")"; fi

  echo "  $(bold "$agent") $sc"
  if [[ -n "$cat_data" ]]; then
    IFS='|' read -ra cats <<< "$cat_data"
    for c in "${cats[@]}"; do
      cname="${c%%:*}"; cscore="${c##*:}"
      printf "    %-17s %s\n" "$cname" "$cscore"
    done
  fi
  [[ $criticals -gt 0 ]] && echo "    $(red "$criticals error(s)")"
  [[ ${agent_warnings:-0} -gt 0 ]] && echo "    $(yellow "$agent_warnings warning(s)")"
  echo ""
done
AGENT_ONLY_WARNINGS=$((TOTAL_WARNINGS - TOTAL_WS_WARNING_COUNT))
WS_UNIQUE_RULES=${#SEEN_WORKSPACE_WARNINGS[@]}

echo "  $(bold "Totals:") $TOTAL_CRITICALS error(s), $AGENT_ONLY_WARNINGS warning(s)"

# Show deduplicated workspace-level warnings
if [[ $WS_UNIQUE_RULES -gt 0 ]]; then
  echo ""
  dim "  Shared-level warnings (affect all agents, fix once): $WS_UNIQUE_RULES"
  for rule in "${!SEEN_WORKSPACE_WARNINGS[@]}"; do
    dim "    $rule (seen in ${SEEN_WORKSPACE_WARNINGS[$rule]}/${#AGENTS[@]} agents)"
  done
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Process Tool 2: PromptLint
# ═══════════════════════════════════════════════════════════════════════════════

log_section "Tool 2: PromptLint"
bold "━━━ Tool 2: PromptLint ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

declare -A PL_SCORES
TOTAL_PL_CLARITY=0
TOTAL_PL_SECURITY=0
TOTAL_PL_COST=0
TOTAL_PL_FILES=0
TOTAL_PL_FAILURES=0

for agent in "${AGENTS[@]}"; do
  pl_agent_dir="$PL_DIR/$agent"
  [[ ! -d "$pl_agent_dir" ]] && continue

  echo "  $(bold "$agent")"
  agent_clarity=0; agent_security=0; agent_cost=0; file_count=0

  for jf in "$pl_agent_dir"/*.json; do
    [[ -f "$jf" ]] || continue
    fname=$(basename "$jf" .json)

    # Check for tool failure sentinel
    if $PY -c "import json; d=json.load(open('$jf')); exit(0 if '_error' not in d else 1)" 2>/dev/null; then
      scores=$($PY -c "
import sys,json
with open('$jf') as _f: d=json.load(_f)
s=d.get('scores',{})
print(f\"{s.get('clarity',0):.1f} {s.get('security',0):.1f} {s.get('cost_efficiency',0):.1f} {s.get('overall',0):.1f}\")
" 2>/dev/null || echo "0.0 0.0 0.0 0.0")
    else
      echo "    $(red "ERROR:") PromptLint failed on $fname — check binary/venv"
      log "PromptLint  | $agent/$fname | ERROR: tool failure"
      TOTAL_PL_FAILURES=$((TOTAL_PL_FAILURES + 1))
      scores="0.0 0.0 0.0 0.0"
    fi

    clarity=$(echo "$scores" | awk '{print $1}')
    security=$(echo "$scores" | awk '{print $2}')
    cost=$(echo "$scores" | awk '{print $3}')
    overall=$(echo "$scores" | awk '{print $4}')

    overall_int=$(printf "%.0f" "$overall" 2>/dev/null || echo 0)
    if [[ $overall_int -ge 9 ]]; then od="$(green "$overall/10")"
    elif [[ $overall_int -ge 7 ]]; then od="$(yellow "$overall/10")"
    else od="$(red "$overall/10")"; fi

    printf "    %-18s %s  " "$fname" "$od"
    dim "(clarity:$clarity sec:$security cost:$cost)"
    echo ""

    agent_clarity=$(awk "BEGIN{printf \"%.1f\", $agent_clarity + $clarity}")
    agent_security=$(awk "BEGIN{printf \"%.1f\", $agent_security + $security}")
    agent_cost=$(awk "BEGIN{printf \"%.1f\", $agent_cost + $cost}")
    file_count=$((file_count + 1))
    TOTAL_PL_FILES=$((TOTAL_PL_FILES + 1))
    log "PromptLint  | $agent/$fname | clarity=$clarity security=$security cost=$cost overall=$overall"
  done

  if [[ $file_count -gt 0 ]]; then
    avg_clarity=$(awk "BEGIN{printf \"%.1f\", $agent_clarity / $file_count}")
    avg_security=$(awk "BEGIN{printf \"%.1f\", $agent_security / $file_count}")
    avg_cost=$(awk "BEGIN{printf \"%.1f\", $agent_cost / $file_count}")
    PL_SCORES[$agent]="$avg_clarity $avg_security $avg_cost"
    TOTAL_PL_CLARITY=$(awk "BEGIN{printf \"%.1f\", $TOTAL_PL_CLARITY + $agent_clarity}")
    TOTAL_PL_SECURITY=$(awk "BEGIN{printf \"%.1f\", $TOTAL_PL_SECURITY + $agent_security}")
    TOTAL_PL_COST=$(awk "BEGIN{printf \"%.1f\", $TOTAL_PL_COST + $agent_cost}")
    dim "    avg: clarity:$avg_clarity sec:$avg_security cost:$avg_cost"
    echo ""
  fi
  echo ""
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Process Tool 3: Home-Grow Linter
# ═══════════════════════════════════════════════════════════════════════════════

log_section "Tool 3: Home-Grow Linter"
bold "━━━ Tool 3: Home-Grow Linter ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

HG_ERRORS=0; HG_WARNINGS=0; HG_INFOS=0; HG_PASSES=0
declare -a HG_ISSUES=()

if [[ -s "$HG_DIR/results.txt" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    status=$(echo "$line" | cut -d'|' -f1)
    ctx=$(echo "$line" | cut -d'|' -f2)
    msg=$(echo "$line" | cut -d'|' -f3-)
    case "$status" in
      OK)    echo "  $(green "OK")    $ctx — $msg"; HG_PASSES=$((HG_PASSES + 1)); log "HomeGrow | OK | $ctx | $msg" ;;
      INFO)  echo "  $(cyan "INFO")  $ctx — $msg"; HG_INFOS=$((HG_INFOS + 1)); HG_ISSUES+=("INFO|$ctx|$msg"); log "HomeGrow | INFO | $ctx | $msg" ;;
      WARN)  echo "  $(yellow "WARN")  $ctx — $msg"; HG_WARNINGS=$((HG_WARNINGS + 1)); HG_ISSUES+=("WARN|$ctx|$msg"); log "HomeGrow | WARN | $ctx | $msg" ;;
      ERROR) echo "  $(red "ERROR") $ctx — $msg"; HG_ERRORS=$((HG_ERRORS + 1)); HG_ISSUES+=("ERROR|$ctx|$msg"); log "HomeGrow | ERROR | $ctx | $msg" ;;
    esac
  done < "$HG_DIR/results.txt"
else
  echo "  $(yellow "WARN:") Home-Grow produced no output — check apps/homegrow/run.sh"
  log "WARN: Home-Grow results.txt empty or missing"
fi

echo ""
echo "  $(bold "Summary:") $(green "$HG_PASSES pass") | $(cyan "$HG_INFOS info") | $(yellow "$HG_WARNINGS warn") | $(red "$HG_ERRORS error")"
echo ""
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Token Budget Analysis — per-file scored pillar
# ═══════════════════════════════════════════════════════════════════════════════

log_section "Token Budget Analysis"
bold "━━━ Token Budgets ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Load budget config (same source as Home-Grow)
HG_CONF="$SCRIPT_DIR/apps/homegrow/rules.conf"
[[ -f "$HG_CONF" ]] && source "$HG_CONF"
for _var in AGENTS_MD SOUL_MD IDENTITY_MD USER_MD TOOLS_MD HEARTBEAT_MD MEMORY_MD; do
  _env="MEGALINT_BUDGET_${_var}"
  [[ -n "${!_env:-}" ]] && declare "BUDGET_${_var}=${!_env}"
done

# Serialize AGENT_DIRS to JSON for Python
_ad_json="{"
for _a in "${AGENTS[@]}"; do
  _ad_json+="\"$_a\":\"${AGENT_DIRS[$_a]}\","
done
_ad_json="${_ad_json%,}}"

# Compute per-file and per-agent token budget scores
$PY -c "
import json, os, sys

sys.path.insert(0, '$SCRIPT_DIR/lib')
try:
    from tiktoken_count import count_file
    def estimate_tokens(path):
        return count_file(path)
except ImportError:
    def estimate_tokens(path):
        with open(path) as f:
            words = len(f.read().split())
        return (words * 13 + 9) // 10

agent_dirs = json.loads('$_ad_json')
budgets = {
    'AGENTS.md': int('${BUDGET_AGENTS_MD:-1150}'),
    'SOUL.md': int('${BUDGET_SOUL_MD:-350}'),
    'IDENTITY.md': int('${BUDGET_IDENTITY_MD:-115}'),
    'USER.md': int('${BUDGET_USER_MD:-475}'),
    'TOOLS.md': int('${BUDGET_TOOLS_MD:-350}'),
    'HEARTBEAT.md': int('${BUDGET_HEARTBEAT_MD:-150}'),
    'MEMORY.md': int('${BUDGET_MEMORY_MD:-650}'),
}

def score_file(tokens, budget):
    if budget <= 0:
        return 100.0
    if tokens <= budget:
        return 100.0
    # Linear drop: 100 at budget → 0 at 3× budget (soft guideline slope)
    over = tokens - budget
    headroom = budget * 2  # 2 budget-widths of headroom before score hits 0
    return max(0.0, round(100.0 * (1.0 - over / headroom), 1))

data = {}
for agent, agent_dir in agent_dirs.items():
    files = {}
    for fname, budget in budgets.items():
        fpath = os.path.join(agent_dir, fname)
        if not os.path.exists(fpath):
            continue
        tokens = estimate_tokens(fpath)
        sc = round(score_file(tokens, budget), 1)
        pct = round(tokens / budget * 100) if budget > 0 else 0
        files[fname] = {'tokens': tokens, 'budget': budget, 'score': sc, 'pct': pct}
    if files:
        avg = round(sum(f['score'] for f in files.values()) / len(files), 1)
        data[agent] = {'files': files, 'avg': avg}

with open('$TMPDIR_RUN/budget_data.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null

# Display budget scores
declare -A BUDGET_SCORES
TOTAL_BUDGET_SCORE=0
BUDGET_AGENT_COUNT=0

BUDGET_DISPLAY=$($PY -c "
import json, sys
with open('$TMPDIR_RUN/budget_data.json') as f:
    data = json.load(f)

for agent, ad in data.items():
    avg = ad['avg']
    print(f'AGENT_SCORE|{agent}|{avg}')
    for fname, fd in sorted(ad['files'].items()):
        tokens, budget, sc, pct = fd['tokens'], fd['budget'], fd['score'], fd['pct']
        bar_len = max(0, min(10, int(sc / 10)))
        bar = '█' * bar_len + '░' * (10 - bar_len)
        if sc >= 88:
            level = 'OK'
        elif sc >= 75:
            level = 'INFO'
        elif sc >= 50:
            level = 'WARN'
        else:
            level = 'ERROR'
        print(f'FILE|{agent}|{fname}|{tokens}/{budget}|{pct}%|{sc}|{bar}|{level}')
    print(f'AVG|{agent}|{avg}')

# Fleet average
if data:
    fleet = round(sum(a['avg'] for a in data.values()) / len(data), 1)
    print(f'FLEET|{fleet}')
" 2>/dev/null)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  kind=$(echo "$line" | cut -d'|' -f1)
  case "$kind" in
    AGENT_SCORE)
      agent=$(echo "$line" | cut -d'|' -f2)
      avg_sc=$(echo "$line" | cut -d'|' -f3)
      BUDGET_SCORES[$agent]="$avg_sc"
      TOTAL_BUDGET_SCORE=$(awk "BEGIN{printf \"%.1f\", $TOTAL_BUDGET_SCORE + $avg_sc}")
      BUDGET_AGENT_COUNT=$((BUDGET_AGENT_COUNT + 1))
      avg_int=$(printf "%.0f" "$avg_sc" 2>/dev/null || echo 0)
      if [[ $avg_int -ge 90 ]]; then sc_c="$(green "$avg_sc")"
      elif [[ $avg_int -ge 70 ]]; then sc_c="$(yellow "$avg_sc")"
      else sc_c="$(red "$avg_sc")"; fi
      echo "  $(bold "$agent") $sc_c/100"
      ;;
    FILE)
      fname=$(echo "$line" | cut -d'|' -f3)
      ratio=$(echo "$line" | cut -d'|' -f4)
      pct=$(echo "$line" | cut -d'|' -f5)
      sc=$(echo "$line" | cut -d'|' -f6)
      bar=$(echo "$line" | cut -d'|' -f7)
      level=$(echo "$line" | cut -d'|' -f8)
      sc_int=$(printf "%.0f" "$sc" 2>/dev/null || echo 0)
      if [[ $sc_int -ge 90 ]]; then sc_d="$(green "$sc")"
      elif [[ $sc_int -ge 50 ]]; then sc_d="$(yellow "$sc")"
      else sc_d="$(red "$sc")"; fi
      tag=""
      [[ "$level" == "ERROR" ]] && tag=" $(red "▲")"
      [[ "$level" == "WARN" ]] && tag=" $(yellow "▲")"
      [[ "$level" == "INFO" ]] && tag=" $(cyan "~")"
      printf "    %-15s %8s  %6s  %s%s\n" "$fname" "$ratio" "$sc_d" "$bar" "$tag"
      ;;
    AVG)
      echo ""
      ;;
    FLEET)
      fleet_avg=$(echo "$line" | cut -d'|' -f2)
      echo "  $(bold "Fleet average:") $(score_color "$fleet_avg")/100"
      log "Token Budgets | fleet_avg=$fleet_avg"
      ;;
  esac
done <<< "$BUDGET_DISPLAY"
echo ""
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Tool 4: Prompt Hardener (sequential — needs API calls)
# ═══════════════════════════════════════════════════════════════════════════════

bold "━━━ Tool 4: Prompt Hardener ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

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
  echo "  $(green "API key found") — model: $HARDENER_MODEL"
  echo ""

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
p={'claude-sonnet-4-6':{'i':3.0,'o':15.0},'claude-opus-4-6':{'i':5.0,'o':25.0}}.get(m,{'i':3.0,'o':15.0})
ci=(ti/1e6)*p['i']; co=(to/1e6)*p['o']; ct_=ci+co
print(f'TOKENS_IN={int(ti)}')
print(f'TOKENS_OUT={int(to)}')
print(f'COST_TOTAL={ct_:.6f}')
print(f'PRICE_IN={p[\"i\"]}')
print(f'PRICE_OUT={p[\"o\"]}')
" 2>/dev/null)
  TOKENS_IN=0 TOKENS_OUT=0 COST_TOTAL=0
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
    PH_ACTUAL_IN=0
    PH_ACTUAL_OUT=0

    for agent in "${AGENTS[@]}"; do
      agent_dir="${AGENT_DIRS[$agent]}"
      [[ ! -d "$agent_dir" ]] && continue

      tmpraw="$TMPDIR_RUN/ph-raw-$agent-$$.md"
      for mdfile in "$agent_dir"/*.md; do
        [[ -f "$mdfile" ]] || continue
        printf '\n\n--- %s ---\n' "$(basename "$mdfile")" >> "$tmpraw"
        command cat "$mdfile" >> "$tmpraw"
      done
      [[ ! -s "$tmpraw" ]] && { command rm -f "$tmpraw"; continue; }

      tmpfile="$TMPDIR_RUN/ph-$agent-$$.json"
      $PY -c "
import json, sys
with open('$tmpraw') as f: content = f.read().strip()
data = {'messages': [{'role': 'system', 'content': content}]}
with open('$tmpfile', 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null
      command rm -f "$tmpraw"

      if [[ -f "$tmpfile" ]]; then
        echo "  $(bold "$agent") — evaluating..."
        PH_STDERR="$TMPDIR_RUN/ph-stderr-${agent}.txt"
        "$HARDENER_BIN" evaluate \
          --input-mode chat --input-format openai \
          --target-prompt-path "$tmpfile" \
          --eval-api-mode "$HARDENER_API_MODE" --eval-model "$HARDENER_MODEL" \
          --output-path "$PH_DIR/${agent}_eval.json" \
          --report-dir "$PH_DIR" \
          > /dev/null 2>"$PH_STDERR" || true

        if [[ -f "$PH_DIR/${agent}_eval.json" ]]; then
          # Extract actual API token usage from eval result
          agent_usage=$($PY -c "
import json
with open('$PH_DIR/${agent}_eval.json') as f: d=json.load(f)
u=d.get('_usage',{})
print(f\"{u.get('input_tokens',0)} {u.get('output_tokens',0)}\")
" 2>/dev/null || echo "0 0")
          a_in=$(echo "$agent_usage" | awk '{print $1}')
          a_out=$(echo "$agent_usage" | awk '{print $2}')
          PH_ACTUAL_IN=$((PH_ACTUAL_IN + a_in))
          PH_ACTUAL_OUT=$((PH_ACTUAL_OUT + a_out))
          echo "    $(green "Done") — ${a_in} in / ${a_out} out tokens"
          log "Hardener | $agent | saved | tokens_in=$a_in tokens_out=$a_out"
          PH_COUNT=$((PH_COUNT + 1))
        else
          echo "    $(yellow "No eval output")"
          if [[ -s "$PH_STDERR" ]]; then
            _ph_err=$(tail -3 "$PH_STDERR" | head -1)
            echo "    $(dim "reason: $_ph_err")"
            log "Hardener | $agent | no json | stderr: $_ph_err"
          else
            log "Hardener | $agent | no json | no stderr"
          fi
        fi
        command rm -f "$tmpfile"
      fi
      echo ""
    done

    # Show actual usage totals
    if [[ $PH_COUNT -gt 0 ]]; then
      PH_ACTUAL_COST=$($PY -c "
m='$HARDENER_MODEL'
p={'claude-sonnet-4-6':{'i':3.0,'o':15.0},'claude-opus-4-6':{'i':5.0,'o':25.0}}.get(m,{'i':3.0,'o':15.0})
ci=($PH_ACTUAL_IN/1e6)*p['i']; co=($PH_ACTUAL_OUT/1e6)*p['o']
print(f'{ci+co:.6f}')
" 2>/dev/null || echo "0.000000")
      echo "  $(bold "Actual usage:") $PH_ACTUAL_IN in / $PH_ACTUAL_OUT out — \$$PH_ACTUAL_COST"
      log "Hardener | ACTUAL | tokens_in=$PH_ACTUAL_IN tokens_out=$PH_ACTUAL_OUT cost=\$$PH_ACTUAL_COST"
    fi
    echo ""
  else
    echo "  $(yellow "SKIPPED") — User declined"; echo ""
  fi
else
  echo "  $(yellow "SKIPPED") — No ANTHROPIC_API_KEY"; echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Combined Summary — 5-pillar scoring
# ═══════════════════════════════════════════════════════════════════════════════

HARDENER_RAN=false
[[ "$HARDENER_PROCEED" == "true" && $PH_COUNT -gt 0 ]] && HARDENER_RAN=true

echo ""
bold "╔══════════════════════════════════════════════════════════════╗"
echo ""
bold "║                    COMBINED RESULTS                        ║"
echo ""
bold "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Write scoring input as JSON
$PY -c "
import json, sys
with open('$TMPDIR_RUN/scoring_input.json', 'w') as _f:
    json.dump({
        'agent_count': $AGENT_COUNT,
        'total_al_score': $TOTAL_AL_SCORE,
        'total_pl_clarity': $TOTAL_PL_CLARITY,
        'total_pl_security': $TOTAL_PL_SECURITY,
        'total_pl_cost': $TOTAL_PL_COST,
        'total_pl_files': $TOTAL_PL_FILES,
        'total_pl_failures': $TOTAL_PL_FAILURES,
        'hg_passes': $HG_PASSES,
        'hg_infos': $HG_INFOS,
        'hg_warnings': $HG_WARNINGS,
        'hg_errors': $HG_ERRORS,
        'hardener_ran': '$HARDENER_RAN' == 'true',
        'ph_dir': '$TMPDIR_RUN/hardener',
        'weight_structure': $WEIGHT_STRUCTURE,
        'weight_quality': $WEIGHT_QUALITY,
        'weight_consistency': $WEIGHT_CONSISTENCY,
        'weight_security': $WEIGHT_SECURITY,
        'weight_budget': $WEIGHT_BUDGET,
        'budget_data_path': '$TMPDIR_RUN/budget_data.json',
        'pass_threshold': $PASS_THRESHOLD,
        'blocking_errors': '$BLOCKING_ERRORS' == 'true',
        'grades': [($GRADE_S,'S'),($GRADE_A_PLUS,'A+'),($GRADE_A,'A'),($GRADE_A_MINUS,'A-'),
                   ($GRADE_B_PLUS,'B+'),($GRADE_B,'B'),($GRADE_B_MINUS,'B-'),
                   ($GRADE_C_PLUS,'C+'),($GRADE_C,'C'),($GRADE_C_MINUS,'C-'),($GRADE_D,'D')]
    }, _f)
" 2>/dev/null
SCORING=$($PY "$SCRIPT_DIR/lib/scoring.py" --input "$TMPDIR_RUN/scoring_input.json" 2>/dev/null)
  PILLAR_STRUCTURE=0 PILLAR_QUALITY=N/A PILLAR_CONSISTENCY=0 PILLAR_SECURITY=N/A PILLAR_BUDGET=N/A
  PH_SATISFIED=0 PH_TOTAL=0 AVG_PL_CLARITY=0 AVG_PL_SECURITY=0 AVG_PL_COST=0
  BUDGET_TOTAL_TOKENS=0 BUDGET_TOTAL_BUDGET=0
  COMBINED=0 GRADE=F PASSED=false HAS_BLOCKING=false
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != *"="* ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    [[ -n "$key" ]] && declare -g "$key=$val"
  done <<< "$SCORING"

# ─── Display ──────────────────────────────────────────────────────────────────

grade_str() { echo "$(score_color "$1") ($2)"; }

if [[ $AGENT_COUNT -gt 0 ]]; then
  echo "  $(bold "Score:") $(grade_str "$COMBINED" "$GRADE")"
  if [[ "$PASSED" == "true" ]]; then
    echo "  $(green "PASS") (threshold: $PASS_THRESHOLD)"
  else
    echo -n "  $(red "FAIL")"
    if [[ "$HAS_BLOCKING" == "true" ]]; then
      echo " (blocking errors — $HG_ERRORS error(s))"
    else
      echo " (below threshold: $PASS_THRESHOLD)"
    fi
  fi
  echo ""

  read -r eff_st eff_ql eff_co eff_se eff_bu <<< "$($PY -c "
ql=$WEIGHT_QUALITY if '$PILLAR_QUALITY'!='N/A' else 0
se=$WEIGHT_SECURITY if '$PILLAR_SECURITY'!='N/A' else 0
bu=$WEIGHT_BUDGET if '$PILLAR_BUDGET'!='N/A' else 0
tw=$WEIGHT_STRUCTURE+ql+$WEIGHT_CONSISTENCY+se+bu
print(round($WEIGHT_STRUCTURE/tw*100), round(ql/tw*100) if ql else '—', round($WEIGHT_CONSISTENCY/tw*100), round(se/tw*100) if se else '—', round(bu/tw*100) if bu else '—')
" 2>/dev/null)"

  printf "  %-24s  %-8s  %s\n" "Pillar" "Score" "Weight"
  printf "  %-24s  %-8s  %s\n" "────────────────────" "──────" "──────"
  printf "  %-24s  %-8s  %s\n" "Structure (AgentLinter)" "$(score_color "$PILLAR_STRUCTURE")" "${eff_st}%"
  if [[ "$PILLAR_QUALITY" != "N/A" ]]; then
    printf "  %-24s  %-8s  %s\n" "Quality (PromptLint)" "$(score_color "$PILLAR_QUALITY")" "${eff_ql}%"
  else
    printf "  %-24s  %-8s  %s\n" "Quality (PromptLint)" "$(dim "skipped")" "—"
  fi
  printf "  %-24s  %-8s  %s\n" "Consistency (Home-Grow)" "$(score_color "$PILLAR_CONSISTENCY")" "${eff_co}%"
  if [[ "$PILLAR_SECURITY" != "N/A" ]]; then
    printf "  %-24s  %-8s  %s\n" "Security (Hardener)" "$(score_color "$PILLAR_SECURITY")" "${eff_se}%"
  else
    printf "  %-24s  %-8s  %s\n" "Security (Hardener)" "$(dim "skipped")" "—"
  fi
  if [[ "$PILLAR_BUDGET" != "N/A" ]]; then
    printf "  %-24s  %-8s  %s\n" "Token Budget (Length)" "$(score_color "$PILLAR_BUDGET")" "${eff_bu}%"
  else
    printf "  %-24s  %-8s  %s\n" "Token Budget (Length)" "$(dim "N/A")" "—"
  fi
  echo ""

  dim "  Quality = clarity $AVG_PL_CLARITY/10 (avg across ${TOTAL_PL_FILES} files)"
  echo ""
  dim "  Consistency = $HG_PASSES pass / $HG_INFOS info / $HG_WARNINGS warn / $HG_ERRORS err"
  echo ""
  if [[ "$PILLAR_SECURITY" != "N/A" ]]; then
    dim "  Security = avg $($PY -c "print(round($PH_SATISFIED/$PH_TOTAL,1) if $PH_TOTAL>0 else 0)" 2>/dev/null)/10 across $PH_TOTAL checks"
    echo ""
  fi
  if [[ "$PILLAR_BUDGET" != "N/A" && "$BUDGET_TOTAL_BUDGET" -gt 0 ]]; then
    budget_usage_pct=$($PY -c "print(round($BUDGET_TOTAL_TOKENS/$BUDGET_TOTAL_BUDGET*100,1))" 2>/dev/null)
    dim "  Token Budget = ${BUDGET_TOTAL_TOKENS}/${BUDGET_TOTAL_BUDGET} tokens (${budget_usage_pct}% of capacity)"
    echo ""
  fi

  # Per-agent breakdown table — only shown for multi-agent (2+) runs
  if [[ ${#AGENTS[@]} -gt 1 ]]; then
    printf "\n  %-16s  %-10s  %-10s  %-10s  %-10s  %-10s\n" "Agent" "Struct." "Quality" "Consist." "Security" "Budget"
    printf "  %-16s  %-10s  %-10s  %-10s  %-10s  %-10s\n" "────────────" "────────" "────────" "────────" "────────" "────────"
    for agent in "${AGENTS[@]}"; do
      al_s="${AL_SCORES[$agent]:-—}"
      pl_d="${PL_SCORES[$agent]:-N/A N/A N/A}"
      if [[ "$pl_d" != "N/A N/A N/A" ]]; then
        pl_overall=$($PY -c "c='$pl_d'.split()[0]; print(f'{float(c)*10:.1f}')" 2>/dev/null || echo "—")
      else
        pl_overall="—"
      fi
      bu_s="${BUDGET_SCORES[$agent]:-—}"
      printf "  %-16s  %-10s  %-10s  %-10s  %-10s  %-10s\n" "$agent" "$al_s" "$pl_overall" "—" "—" "$bu_s"
    done
    echo ""
  fi

  log_section "Combined Results"
  log "Run ID: $RUN_ID"
  log "Git: $GIT_COMMIT ($GIT_BRANCH) dirty=$GIT_DIRTY"
  log "Score: $COMBINED ($GRADE) — $([ "$PASSED" = "true" ] && echo "PASS" || echo "FAIL")"
  log "Pillars: structure=$PILLAR_STRUCTURE quality=$PILLAR_QUALITY consistency=$PILLAR_CONSISTENCY security=$PILLAR_SECURITY budget=$PILLAR_BUDGET"
  log "Weights: st=$WEIGHT_STRUCTURE ql=$WEIGHT_QUALITY co=$WEIGHT_CONSISTENCY se=$WEIGHT_SECURITY bu=$WEIGHT_BUDGET"
  log "HomeGrow: $HG_PASSES pass / $HG_INFOS info / $HG_WARNINGS warn / $HG_ERRORS err"
  log "Token Budget: $BUDGET_TOTAL_TOKENS / $BUDGET_TOTAL_BUDGET total"
  log "Threshold: $PASS_THRESHOLD  blocking=$BLOCKING_ERRORS"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Output structured report (--format json|md|both)
# ═══════════════════════════════════════════════════════════════════════════════

if [[ -n "$FORMAT_FLAG" ]]; then

# Write git message safely to file (avoids heredoc escaping issues)
printf '%s' "$GIT_MSG" > "$TMPDIR_RUN/_git_msg.txt"

# Build report input JSON
$PY -c "
import json, os
git_msg_file = '$TMPDIR_RUN/_git_msg.txt'
git_msg = ''
if os.path.exists(git_msg_file):
    with open(git_msg_file) as _gf:
        git_msg = _gf.read().strip()
with open('$TMPDIR_RUN/report_input.json', 'w') as _f:
    json.dump({
        'run_id': '$RUN_ID',
        'git_commit': '$GIT_COMMIT',
        'git_branch': '$GIT_BRANCH',
        'git_dirty': '$GIT_DIRTY' == 'true',
        'git_msg': git_msg,
        'timestamp': '$(date -u '+%Y-%m-%dT%H:%M:%SZ')',
        'agents_list': '$( IFS=,; echo "${AGENTS[*]}" )'.split(','),
        'hardener_model': '$HARDENER_MODEL' if '$HARDENER_AVAILABLE' == 'true' else None,
        'hardener_tokens_in': ${PH_ACTUAL_IN:-0},
        'hardener_tokens_out': ${PH_ACTUAL_OUT:-0},
        'combined': float('$COMBINED'),
        'grade': '$GRADE',
        'passed': '$PASSED' == 'true',
        'pass_threshold': $PASS_THRESHOLD,
        'blocking_errors': '$BLOCKING_ERRORS' == 'true',
        'pillar_structure': float('$PILLAR_STRUCTURE'),
        'pillar_quality': float('$PILLAR_QUALITY') if '$PILLAR_QUALITY' != 'N/A' else None,
        'pillar_consistency': float('$PILLAR_CONSISTENCY'),
        'pillar_security': float('$PILLAR_SECURITY') if '$PILLAR_SECURITY' != 'N/A' else None,
        'pillar_budget': float('$PILLAR_BUDGET') if '$PILLAR_BUDGET' != 'N/A' else None,
        'weight_structure': $WEIGHT_STRUCTURE,
        'weight_quality': $WEIGHT_QUALITY,
        'weight_consistency': $WEIGHT_CONSISTENCY,
        'weight_security': $WEIGHT_SECURITY,
        'weight_budget': $WEIGHT_BUDGET,
        'budget_total_tokens': $BUDGET_TOTAL_TOKENS,
        'budget_total_budget': $BUDGET_TOTAL_BUDGET,
        'avg_pl_clarity': float('$AVG_PL_CLARITY'),
        'avg_pl_security': float('$AVG_PL_SECURITY'),
        'avg_pl_cost': float('$AVG_PL_COST'),
        'hg_passes': $HG_PASSES,
        'hg_infos': $HG_INFOS,
        'hg_warnings': $HG_WARNINGS,
        'hg_errors': $HG_ERRORS,
        'al_dir': '$AL_DIR',
        'pl_dir': '$PL_DIR',
        'hg_dir': '$HG_DIR',
        'ph_dir': '$TMPDIR_RUN/hardener',
    }, _f)
" 2>/dev/null

$PY "$SCRIPT_DIR/lib/report.py" \
  --input "$TMPDIR_RUN/report_input.json" \
  --format "$FORMAT_FLAG" \
  --output-dir "$REPORT_DIR"

fi

# ─── Footer ───────────────────────────────────────────────────────────────────

echo ""
dim "  commit: $GIT_COMMIT ($GIT_BRANCH) | run: $RUN_ID"
echo ""
log ""
log "Finished: $(date '+%Y-%m-%d %H:%M:%S %Z')"
dim "  Log: $LOG_FILE"
echo ""

# Cleanup via trap; no manual rm needed

[[ "${PASSED:-true}" == "false" ]] && exit 1
exit 0
