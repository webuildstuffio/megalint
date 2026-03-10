#!/usr/bin/env bash
set -uo pipefail

# homegrow/run.sh — OpenClaw-specific consistency checks
# Single source of truth. Called by megalint.sh or standalone.
#
# Usage: run.sh AGENTS_DIR SHARED_DIR [agent...]
# Output: STATUS|context|message (one per line to stdout)
#
# All check logic lives here as individual functions.
# megalint.sh only orchestrates, scores, and reports.

command -v rg >/dev/null 2>&1 || { echo "ERROR: ripgrep (rg) not installed — required for checks" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Args ─────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
  echo "Usage: run.sh AGENTS_DIR SHARED_DIR [agent...]" >&2
  exit 1
fi

AGENTS_DIR="$1"; shift
SHARED_DIR="$1"; shift

if [[ $# -gt 0 ]]; then
  AGENTS=("$@")
else
  AGENTS=()
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    [[ "$(basename "$d")" == "template" ]] && continue
    AGENTS+=("$(basename "$d")")
  done
fi

# ─── Config defaults (overridden by rules.conf, then env vars) ────────────────

CHECK_SHARED_FILES=1
CHECK_REQUIRED_FILES=1
CHECK_BOOT_REFS=1
CHECK_BOOT_STRUCTURE=1
CHECK_ROSTER_COUNT=1
CHECK_BOOTSTRAP_CLEANUP=1
CHECK_ANTI_SYCOPHANCY=1
CHECK_ACTION_TIERS=1
CHECK_TONE_TABLE=1
CHECK_CONTINUITY_LINE=1
CHECK_SECURITY_SECTION=1
CHECK_MEMORY_WORKFLOW=1
CHECK_HEARTBEAT=1
CHECK_TOKEN_BUDGETS=1
CHECK_TIMEZONE=1
CHECK_CANONICAL_WORDING=1
CHECK_ACTION_TIERS_STRICT=1
CHECK_CONVENTIONS_RESOURCEFULNESS=1
CHECK_BOOT_CONVENTIONS_REF=1
CHECK_MEMORY_SURFACING=1
CHECK_SOUL_TONE_CALIBRATED=1
CHECK_IMPORTS_SECTION=1
CHECK_IMPORTS_VALID_PATHS=1
CHECK_DIRECTIVES_EXIST=1
CHECK_IMPORTS_COMPLETENESS=1
CHECK_IMPORTS_NO_DUPLICATION=1
CHECK_IMPORTS_BOOT_INTEGRATION=1
CHECK_IMPORTS_TOOLS_DEDUP=1
CHECK_IMPORTS_USER_DEDUP=1
CHECK_LEGACY_SHARED_FILES=1
CHECK_ORPHAN_DIRECTIVES=1
CHECK_TODO_FILE=1

BUDGET_AGENTS_MD=1725
BUDGET_SOUL_MD=525
BUDGET_IDENTITY_MD=175
BUDGET_USER_MD=715
BUDGET_TOOLS_MD=525
BUDGET_HEARTBEAT_MD=225
BUDGET_MEMORY_MD=975

# Token budget severity multipliers (relative to base budget)
# INFO  = base * TIER_INFO  — heads-up, approaching limit
# WARN  = base * TIER_WARN  — over budget, should trim
# Max severity is WARN — blocking ERRORs reserved for structural issues.
TIER_INFO=1.25
TIER_WARN=1.50

CONF_FILE="$SCRIPT_DIR/rules.conf"
# shellcheck source=rules.conf
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# Env var overrides (highest priority) — set any MEGALINT_BUDGET_* or MEGALINT_TIER_*
# e.g. MEGALINT_BUDGET_AGENTS_MD=1000 MEGALINT_TIER_INFO=1.30
for _var in AGENTS_MD SOUL_MD IDENTITY_MD USER_MD TOOLS_MD HEARTBEAT_MD MEMORY_MD; do
  _env="MEGALINT_BUDGET_${_var}"
  [[ -n "${!_env:-}" ]] && declare "BUDGET_${_var}=${!_env}"
done
[[ -n "${MEGALINT_TIER_INFO:-}" ]]  && TIER_INFO="$MEGALINT_TIER_INFO"
[[ -n "${MEGALINT_TIER_WARN:-}" ]]  && TIER_WARN="$MEGALINT_TIER_WARN"

# ─── Helpers ──────────────────────────────────────────────────────────────────

emit() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

estimate_tokens() {
  local megalint_root="${SCRIPT_DIR}/../.."
  local py="${megalint_root}/apps/promptlint/.venv/bin/python"
  local counter="${megalint_root}/lib/tiktoken_count.py"
  if [[ -x "$py" && -f "$counter" ]]; then
    local count
    count=$("$py" "$counter" "$1" 2>/dev/null) && [[ -n "$count" ]] && { echo "$count"; return; }
  fi
  local words
  words=$(wc -w < "$1" 2>/dev/null | tr -d ' ')
  [[ -z "$words" || "$words" -eq 0 ]] && { echo 0; return; }
  echo $(( (words * 13 + 9) / 10 ))
}

estimate_tokens_with_imports() {
  local file="$1"
  local shared_dir="$2"

  # Create a temporary file to build the expanded content
  local temp_expanded
  temp_expanded=$(mktemp)

  # Process line by line with sed and shell commands
  while IFS= read -r line; do
    if echo "$line" | grep -q '^@import('; then
      # Extract import path using sed
      import_path=$(echo "$line" | sed 's/@import(//' | sed 's/)//')
      directive_file="$shared_dir/directives/${import_path}.md"

      if [[ -f "$directive_file" ]]; then
        # Append the directive content
        cat "$directive_file" >> "$temp_expanded"
        echo "" >> "$temp_expanded"
      else
        # Keep the original import line if directive not found
        echo "$line" >> "$temp_expanded"
      fi
    else
      # Keep the original line
      echo "$line" >> "$temp_expanded"
    fi
  done < "$file"

  # Count tokens in the expanded content
  local megalint_root="${SCRIPT_DIR}/../.."
  local py="${megalint_root}/apps/promptlint/.venv/bin/python"
  local counter="${megalint_root}/lib/tiktoken_count.py"
  if [[ -x "$py" && -f "$counter" ]]; then
    local count
    count=$("$py" "$counter" "$temp_expanded" 2>/dev/null) && [[ -n "$count" ]] && { rm "$temp_expanded"; echo "$count"; return; }
  fi

  # Fallback: word-based estimation
  local words
  words=$(wc -w < "$temp_expanded" 2>/dev/null | tr -d ' ')
  rm "$temp_expanded"
  [[ -z "$words" || "$words" -eq 0 ]] && { echo 0; return; }
  echo $(( (words * 13 + 9) / 10 ))
}

get_budget() {
  case "$1" in
    AGENTS.md)    echo "$BUDGET_AGENTS_MD" ;;
    SOUL.md)      echo "$BUDGET_SOUL_MD" ;;
    IDENTITY.md)  echo "$BUDGET_IDENTITY_MD" ;;
    USER.md)      echo "$BUDGET_USER_MD" ;;
    TOOLS.md)     echo "$BUDGET_TOOLS_MD" ;;
    HEARTBEAT.md) echo "$BUDGET_HEARTBEAT_MD" ;;
    MEMORY.md)    echo "$BUDGET_MEMORY_MD" ;;
    *)            echo 0 ;;
  esac
}

tier_threshold() {
  awk "BEGIN{printf \"%d\", $1 * $2}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Checks — each function emits STATUS|context|message lines
# ═══════════════════════════════════════════════════════════════════════════════

# ─── 1. Shared files exist ────────────────────────────────────────────────────

check_shared_files() {
  [[ ! -d "$SHARED_DIR" ]] && { emit WARN shared "shared/ directory not found at $SHARED_DIR — skipping shared file checks"; return; }
  for f in AGENT_ROSTER.md CONVENTIONS.md; do
    if [[ -f "$SHARED_DIR/$f" ]]; then
      emit OK shared "$f exists"
    else
      emit ERROR shared "$f missing — shared config is inherited by ALL agents at boot. Missing shared files break the entire system, not just one agent"
    fi
  done
  if [[ -d "$SHARED_DIR/directives" ]]; then
    emit OK shared "directives/ directory exists"
  else
    emit ERROR shared "directives/ directory missing — agents use modular imports from directives/"
  fi
  for userdir in nick paro; do
    if [[ -d "$SHARED_DIR/$userdir" ]]; then
      if [[ -f "$SHARED_DIR/$userdir/USER_CORE.md" ]]; then
        emit OK shared "$userdir/USER_CORE.md exists"
      else
        emit WARN shared "$userdir/USER_CORE.md missing — user-specific shared config required for that user's agents"
      fi
      if [[ -f "$SHARED_DIR/$userdir/AGENT_ROSTER.md" ]]; then
        emit OK shared "$userdir/AGENT_ROSTER.md exists"
      else
        emit WARN shared "$userdir/AGENT_ROSTER.md missing — user-scoped roster reduces token load and enforces data boundaries"
      fi
    fi
  done
}

# ─── 2. Required files per agent ─────────────────────────────────────────────

check_required_files() {
  local required=(AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md MEMORY.md BOOT.md)
  for agent in "${AGENTS[@]}"; do
    local agent_dir="$AGENTS_DIR/$agent"
    [[ ! -d "$agent_dir" ]] && continue
    local missing=()
    for f in "${required[@]}"; do
      [[ ! -f "$agent_dir/$f" ]] && missing+=("$f")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      emit OK "$agent" "all required files present"
    else
      emit ERROR "$agent" "missing: ${missing[*]}. Each file serves a specific purpose and loads on every message — SOUL.md (personality), AGENTS.md (rules), USER.md (user context), etc"
    fi
  done
}

# ─── 3. BOOT.md references shared/ files ────────────────────────────────────

check_boot_refs() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    if rg -q 'USER_CORE\.md' "$boot" 2>/dev/null || rg -Fq '@import(boot/user-context-' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs user context (inline or @import)"
    elif rg -qi 'do NOT read.*user' "$boot" 2>/dev/null || rg -qi 'user-agnostic' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md explicitly skips USER_CORE.md (agent-specific)"
    else
      emit WARN "$agent" "BOOT.md missing user context — add @import(boot/user-context-nick), @import(boot/user-context-paro), or @import(boot/user-context-none)"
    fi
    if rg -q 'AGENT_ROSTER' "$boot" 2>/dev/null || rg -Fq '@import(boot/gateway-recovery)' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs AGENT_ROSTER (inline or via gateway-recovery)"
    else
      emit WARN "$agent" "BOOT.md missing AGENT_ROSTER.md ref — add @import(boot/gateway-recovery)"
    fi
  done
}

# ─── 4. BOOT.md structure (Standard section + checklist) ─────────────────────

check_boot_structure() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    local has_imports has_checklist
    has_imports=$(rg -q '^@import\(' "$boot" 2>/dev/null && echo 1 || echo 0)
    has_checklist=$(rg -q '^\- \[ \]' "$boot" 2>/dev/null && echo 1 || echo 0)
    if [[ "$has_imports" == "1" && "$has_checklist" == "1" ]]; then
      emit OK "$agent" "BOOT.md has @import directives + agent-specific checklist"
    elif [[ "$has_imports" == "1" ]]; then
      emit OK "$agent" "BOOT.md has @import directives"
    elif [[ "$has_checklist" == "1" ]]; then
      emit OK "$agent" "BOOT.md has checklist items (consider adding @import directives)"
    else
      emit WARN "$agent" "BOOT.md missing @import directives and checklist — agents need a structured startup sequence"
    fi
  done
}

# ─── 5. Roster count matches agent dirs ──────────────────────────────────────

check_roster_count() {
  [[ ! -f "$SHARED_DIR/AGENT_ROSTER.md" ]] && return
  local roster_count actual_dirs=0
  roster_count=$(rg -c '^\| \*\*' "$SHARED_DIR/AGENT_ROSTER.md" 2>/dev/null || echo 0)
  for d in "$AGENTS_DIR"/*/; do
    [[ -d "$d" ]] || continue
    local bn; bn="$(basename "$d")"
    [[ "$bn" == "template" || "$bn" == "nick-template" ]] && continue
    ((actual_dirs++))
  done
  if [[ "$roster_count" -eq "$actual_dirs" ]]; then
    emit OK roster "count matches ($roster_count agents)"
  elif [[ "$actual_dirs" -lt "$roster_count" ]]; then
    emit INFO roster "linting $actual_dirs of $roster_count rostered agents (subset mode)"
  else
    emit WARN roster "AGENT_ROSTER.md lists $roster_count but found $actual_dirs agent dirs — update roster"
  fi
}

# ─── 6. Bootstrap cleanup ────────────────────────────────────────────────────

check_bootstrap_cleanup() {
  for agent in "${AGENTS[@]}"; do
    if [[ -f "$AGENTS_DIR/$agent/BOOTSTRAP.md" ]]; then
      # Resolve symlinks — megalint passes a temp dir with symlinks to real agent dirs
      local real_path
      real_path="$(readlink -f "$AGENTS_DIR/$agent" 2>/dev/null || echo "$AGENTS_DIR/$agent")"
      # agents-planned/ agents haven't launched yet — BOOTSTRAP.md is always expected
      if [[ "$real_path" == *agents-planned* ]]; then
        emit OK "$agent" "BOOTSTRAP.md present (agent not yet bootstrapped)"
      elif [[ -f "$AGENTS_DIR/$agent/memory" ]] || [[ -d "$AGENTS_DIR/$agent/memory" ]]; then
        emit WARN "$agent" "BOOTSTRAP.md still exists — agent has memory/ dir, likely already bootstrapped. Delete BOOTSTRAP.md to avoid wasting tokens on every startup"
      else
        emit OK "$agent" "BOOTSTRAP.md present (agent not yet bootstrapped)"
      fi
    fi
  done
}

# ─── 7. SOUL.md anti-sycophancy opener ───────────────────────────────────────

check_anti_sycophancy() {
  for agent in "${AGENTS[@]}"; do
    local soul="$AGENTS_DIR/$agent/SOUL.md"
    [[ ! -f "$soul" ]] && continue
    if head -10 "$soul" | rg -qi 'skip.*(filler|fluff|flattery|great question|happy to help|hedging|commentary|disclaimers|pep.talk|pleasantries|niceties|formalities|sugar.coat)|no.*(filler|fluff|flattery|pleasantries|preamble)|just answer.*start with|start with the (answer|diff|evidence|number|action|signal)' 2>/dev/null; then
      emit OK "$agent" "SOUL.md has anti-sycophancy opener"
    else
      emit WARN "$agent" "SOUL.md missing anti-sycophancy opener in first lines. Anti-sycophancy as the OPENING LINE is one of OpenClaw's strongest patterns — position matters, instructions at the start get disproportionate model attention. All 7 reviewed companies ban filler phrases, no exceptions. See docs/MASTER_SUMMARY.md General Trends #1"
    fi
  done
}

# ─── 8. AGENTS.md action tiers ───────────────────────────────────────────────
# Superseded by check 17 (check_action_tiers_strict) which does proper 4-tier
# counting with both heading and table-row formats. Kept as disabled alias.

# ─── 9. SOUL.md tone calibration table ───────────────────────────────────────

check_tone_table() {
  for agent in "${AGENTS[@]}"; do
    local soul="$AGENTS_DIR/$agent/SOUL.md"
    [[ ! -f "$soul" ]] && continue
    if rg -qi '(tone|voice)' "$soul" 2>/dev/null && rg -qi '\b(flat|avoid|alive|do this)\b' "$soul" 2>/dev/null; then
      emit OK "$agent" "SOUL.md has tone calibration"
    elif rg -qi '^##.*(tone|voice|calibration)' "$soul" 2>/dev/null; then
      emit OK "$agent" "SOUL.md has tone section"
    else
      emit WARN "$agent" "SOUL.md missing tone calibration table. Without a Sycophantic/Robotic/Alive calibration table, the agent has no concrete target for HOW to sound — just vague guidance. See docs/MASTER_SUMMARY.md #5"
    fi
  done
}

# ─── 10. SOUL.md continuity line ─────────────────────────────────────────────

check_continuity_line() {
  for agent in "${AGENTS[@]}"; do
    local soul="$AGENTS_DIR/$agent/SOUL.md"
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$soul" ]] && continue
    if rg -qi 'wake up fresh|files are my memory|session.*fresh|fresh.*context|these files.*memory|start.*(clean|scratch|blank)|no.*(memory|retention).*(between|across).*session|each.*(session|conversation).*new' "$soul" 2>/dev/null; then
      emit OK "$agent" "SOUL.md has continuity line"
    elif [[ -f "$boot" ]] && rg -Fq '@import(boot/session-start)' "$boot" 2>/dev/null; then
      emit OK "$agent" "SOUL.md continuity covered by @import(boot/session-start) in BOOT.md"
    else
      emit WARN "$agent" "SOUL.md missing continuity line. Agents wake up with zero context every session — if the agent doesn't KNOW this, it'll hallucinate continuity instead of reading its memory files. Add: 'You wake up fresh each session. Your files ARE your memory — read them.'"
    fi
  done
}

# ─── 11. AGENTS.md security section ──────────────────────────────────────────

check_security_section() {
  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/AGENTS.md"
    [[ ! -f "$f" ]] && continue
    if rg -q 'security/hostile-content' "$f" 2>/dev/null; then
      emit OK "$agent" "AGENTS.md imports security directives"
    elif rg -q 'SECURITY_RULES.md' "$f" 2>/dev/null || rg -qi '^##.*security' "$f" 2>/dev/null; then
      emit OK "$agent" "AGENTS.md has security section (legacy format)"
    else
      emit WARN "$agent" "AGENTS.md missing security — add security/hostile-content + security/no-exfiltrate in ## Directives"
    fi
  done
}

# ─── 12. AGENTS.md memory workflow reference ─────────────────────────────────

check_memory_workflow() {
  for agent in "${AGENTS[@]}"; do
    local found=0
    for cf in AGENTS.md MEMORY.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ -f "$cf_path" ]] && rg -q 'memory/workflow' "$cf_path" 2>/dev/null && { found=1; break; }
    done
    if [[ "$found" -eq 1 ]]; then
      emit OK "$agent" "imports memory workflow directive"
    elif rg -q 'MEMORY_WORKFLOW' "$AGENTS_DIR/$agent/AGENTS.md" 2>/dev/null; then
      emit OK "$agent" "has memory workflow (legacy format)"
    else
      emit WARN "$agent" "missing @import(memory/workflow) — add to MEMORY.md"
    fi
  done
}

# ─── 13. HEARTBEAT.md contract ───────────────────────────────────────────────

check_heartbeat() {
  for agent in "${AGENTS[@]}"; do
    local hb="$AGENTS_DIR/$agent/HEARTBEAT.md"
    [[ ! -f "$hb" ]] && continue
    if rg -q '^CONTRACT:' "$hb" 2>/dev/null; then
      local task_lines
      task_lines=$(rg -c '^(- |\d+\. |\*\*)' "$hb" 2>/dev/null || echo 0)
      if [[ "$task_lines" -gt 0 ]]; then
        emit OK "$agent" "active heartbeat with $task_lines task(s)"
      else
        emit WARN "$agent" "HEARTBEAT has CONTRACT but no task lines — active CONTRACT with no tasks wastes ~100 tokens 48x/day (~4,800 tokens/day). Comment out CONTRACT line if no checks needed"
      fi
    else
      emit OK "$agent" "HEARTBEAT intentionally inactive"
    fi
  done
}

# ─── 14. Token budgets (2-tier: INFO → WARN) ─────────────────────────────────
# Thresholds are configurable via TIER_INFO/TIER_WARN multipliers
# and per-file budgets via BUDGET_*_MD or env vars MEGALINT_BUDGET_*

check_token_budgets() {
  echo "DEBUG: check_token_budgets called" >&2
  # Max severity is WARN — Token Budget pillar handles graduated scoring.
  # Blocking ERRORs are reserved for structural issues, not length.
  local budgeted_files=(AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md MEMORY.md)
  for agent in "${AGENTS[@]}"; do
    for fname in "${budgeted_files[@]}"; do
      local f="$AGENTS_DIR/$agent/$fname"
      [[ ! -f "$f" ]] && continue
      local tokens budget thr_info thr_warn
      # Use estimate_tokens_with_imports for files that may contain @import directives
      if [[ "$fname" == "AGENTS.md" || "$fname" == "MEMORY.md" || "$fname" == "TOOLS.md" || "$fname" == "BOOT.md" ]]; then
        tokens=$(estimate_tokens_with_imports "$f" "$SHARED_DIR")
        # Debug output
        echo "DEBUG: $fname expanded tokens: $tokens" >&2
      else
        tokens=$(estimate_tokens "$f")
      fi
      budget=$(get_budget "$fname")
      [[ "$budget" -eq 0 ]] && continue
      thr_info=$(tier_threshold "$budget" "$TIER_INFO")
      thr_warn=$(tier_threshold "$budget" "$TIER_WARN")
      if [[ $tokens -gt $thr_warn ]]; then
        emit WARN "$agent" "$fname ~${tokens} tokens — over budget (base: ${budget}, warn: ≥${thr_warn}). Should trim"
      elif [[ $tokens -gt $thr_info ]]; then
        emit INFO "$agent" "$fname ~${tokens} tokens — approaching budget (base: ${budget}, info: ≥${thr_info}). Consider trimming"
      fi
    done
  done
}

# ─── 15. USER.md timezone ────────────────────────────────────────────────────

check_timezone() {
  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/USER.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi '\btimezone\b' "$f" 2>/dev/null \
      || rg -qw 'ET' "$f" 2>/dev/null \
      || rg -qw 'CT' "$f" 2>/dev/null \
      || rg -qw 'PT' "$f" 2>/dev/null \
      || rg -qw 'UTC' "$f" 2>/dev/null \
      || rg -qi '\b(eastern|central|pacific|mountain)\b' "$f" 2>/dev/null \
      || rg -qi '\b(EST|CST|PST|MST|KST|GMT)\b' "$f" 2>/dev/null \
      || rg -qi 'America/' "$f" 2>/dev/null \
      || rg -qi 'Asia/' "$f" 2>/dev/null \
      || rg -qi 'Europe/' "$f" 2>/dev/null; then
      emit OK "$agent" "USER.md has timezone"
    else
      emit WARN "$agent" "USER.md missing timezone — agents schedule reminders, track deadlines, and format times. Without timezone they default to UTC or guess"
    fi
  done
}

# ─── 16. Canonical wording consistency ────────────────────────────────────────

check_canonical_wording() {
  # topic_keyword|canonical_phrase
  # If a file mentions the topic but not in canonical form, warn.
  local checks=(
    "adhd|ADHD"
    "korea\b|South Korea"
    "korean\b|Korean"
    "discord\b|Discord"
    "telegram\b|Telegram"
    "whatsapp\b|WhatsApp"
    "openai\b|OpenAI"
    "anthropic\b|Anthropic"
    "openclaw\b|OpenClaw"
    "clawdbot\b|Clawdbot"
  )
  for agent in "${AGENTS[@]}"; do
    for f in "$AGENTS_DIR/$agent/USER.md" "$AGENTS_DIR/$agent/MEMORY.md"; do
      [[ ! -f "$f" ]] && continue
      local bn
      bn=$(basename "$f")
      for entry in "${checks[@]}"; do
        local topic="${entry%%|*}" canonical="${entry#*|}"
        if rg -qi "$topic" "$f" 2>/dev/null; then
          if rg -q "$canonical" "$f" 2>/dev/null; then
            emit OK "$agent" "$bn uses canonical '$canonical'"
          else
            emit WARN "$agent" "$bn mentions $topic but not as '$canonical' — use the canonical phrasing for consistency across all agent files"
          fi
        fi
      done
    done
  done
}

# ─── 17. AGENTS.md action tier HEADINGS (strict) ─────────────────────────────

check_action_tiers_strict() {
  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/AGENTS.md"
    [[ ! -f "$f" ]] && continue
    local tier_count=0
    # Accept heading format (## Always), table-row format (| **Always** |), and alternate names
    (rg -qi '^#+\s*(always|auto|do by default)' "$f" 2>/dev/null || rg -qi '\*\*(always|auto-?execute|do by default)\*\*' "$f" 2>/dev/null) && ((tier_count++))
    (rg -qi '^#+\s*(when asked|when requested|on request|on demand|if asked|notify)' "$f" 2>/dev/null || rg -qi '\*\*(when asked|when requested|on request|on demand|notify after)\*\*' "$f" 2>/dev/null) && ((tier_count++))
    (rg -qi '^#+\s*(ask first|confirm before|check before)' "$f" 2>/dev/null || rg -qi '\*\*(ask first|confirm before|check before)\*\*' "$f" 2>/dev/null) && ((tier_count++))
    (rg -qi '^#+\s*never\b' "$f" 2>/dev/null || rg -qi '\*\*never\b' "$f" 2>/dev/null) && ((tier_count++))
    if [[ "$tier_count" -ge 3 ]]; then
      emit OK "$agent" "AGENTS.md has $tier_count/4 action tiers"
    elif [[ "$tier_count" -ge 1 ]]; then
      emit WARN "$agent" "AGENTS.md has only $tier_count/4 action tiers (need ≥3). Action tiers are OpenClaw's strongest pattern — no other company structures permissions this cleanly. See docs/MASTER_SUMMARY.md #3, docs/AGI_FOCUSED_AUDIT.md §II Theme 1"
    else
      emit ERROR "$agent" "AGENTS.md missing action tiers (## Always / ## When Asked / ## Ask First / ## Never). Action tiers are OpenClaw's signature architecture — they map agent autonomy into auditable structured tiers. Every agent must have them. See docs/MASTER_SUMMARY.md #3, docs/AGI_FOCUSED_AUDIT.md §IV Rules Tier 1"
    fi
  done
}

# ─── 18. Resourcefulness directive exists ─────────────────────────────────────

check_conventions_resourcefulness() {
  local f="$SHARED_DIR/directives/ops/figure-it-out.md"
  if [[ -f "$f" ]]; then
    emit OK shared "directives/ops/figure-it-out.md exists (resourcefulness directive)"
  else
    emit WARN shared "directives/ops/figure-it-out.md missing — resourcefulness / 'figure it out' directive. This is the #1 universal finding across all 27+ industry prompts reviewed — every agentic company (OpenAI, Anthropic, Perplexity, Notion) demands agents act first and ask never. Without this, agents have no mandate to exhaust approaches before asking. See docs/MASTER_SUMMARY.md #1, docs/AGI_FOCUSED_AUDIT.md §II Theme 1"
  fi
}

# ─── 19. BOOT.md references CONVENTIONS.md or imports/directives ─────────────

check_boot_conventions_ref() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    if rg -qi 'CONVENTIONS' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs CONVENTIONS.md"
    elif rg -qi '(import|directive)' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs imports/directives (replaces CONVENTIONS.md)"
    else
      emit WARN "$agent" "BOOT.md missing CONVENTIONS.md or imports/directives reference"
    fi
  done
}

# ─── 20. MEMORY_WORKFLOW.md has surfacing guidance ────────────────────────────

check_memory_surfacing() {
  local f="$SHARED_DIR/directives/memory/surfacing.md"
  if [[ -f "$f" ]]; then
    if rg -qi '(natural.*(surfac|recall|integrat)|never.*(say|announce).*based.on|just.*(know|remember)|integrate naturally)' "$f" 2>/dev/null; then
      emit OK shared "directives/memory/surfacing.md has surfacing guidance"
    else
      emit WARN shared "directives/memory/surfacing.md exists but missing surfacing rules"
    fi
  else
    emit WARN shared "directives/memory/surfacing.md missing — agents need memory surfacing guidance"
  fi
}

# ─── 21. SOUL.md has calibrated tone signal ───────────────────────────────────

check_soul_tone_calibrated() {
  for agent in "${AGENTS[@]}"; do
    local soul="$AGENTS_DIR/$agent/SOUL.md"
    [[ ! -f "$soul" ]] && continue
    if rg -qi '(direct|warm|honest|authentic|opinionated|skip.*(filler|fluff)|no.*(fluff|pleasantries|platitudes)|just\s+(answer|help)|concise\s+by\s+default|not\s+vibes?|have\s+actual\s+positions?|clinically\s+direct)' "$soul" 2>/dev/null; then
      emit OK "$agent" "SOUL.md has calibrated tone"
    else
      emit WARN "$agent" "SOUL.md missing tone calibration signal. Every reviewed company converges on 'warm directness' — Claude ('helpful peer'), Sesame Maya ('honest, not earnest'), Proton Lumo ('intellectual honesty'). Without a clear tone signal, agents default to generic LLM output. See docs/MASTER_SUMMARY.md #5, docs/AGI_FOCUSED_AUDIT.md §II Theme 3"
    fi
  done
}

# ─── 22. Directives section exists in AGENTS.md ──────────────────────────────

check_imports_section() {
  for agent in "${AGENTS[@]}"; do
    local agents_f="$AGENTS_DIR/$agent/AGENTS.md"
    [[ ! -f "$agents_f" ]] && continue
    if ! rg -q '^## (Directives|Imports)' "$agents_f" 2>/dev/null; then
      emit ERROR "$agent" "AGENTS.md missing ## Imports (or ## Directives) section — shared directive imports belong here"
      continue
    fi
    local total=0
    for cf in AGENTS.md BOOT.md MEMORY.md TOOLS.md SOUL.md HEARTBEAT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ -f "$cf_path" ]] && total=$((total + $(rg -c '^@import\(' "$cf_path" 2>/dev/null || echo 0)))
    done
    if [[ "$total" -gt 0 ]]; then
      emit OK "$agent" "@import directives across config files: $total total"
    else
      emit WARN "$agent" "AGENTS.md has ## Imports/Directives section but no @import() lines found in any config file"
    fi
  done
}

# ─── 23. Import paths resolve to existing directive files ────────────────────

check_imports_valid_paths() {
  for agent in "${AGENTS[@]}"; do
    local bad=0 total=0
    for cf in AGENTS.md BOOT.md MEMORY.md TOOLS.md SOUL.md HEARTBEAT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ ! -f "$cf_path" ]] && continue
      while IFS= read -r line; do
        if [[ "$line" =~ ^'@import('(.+)')' ]]; then
          local path="${BASH_REMATCH[1]}"
          path="${path%.md}"
          ((total++))
          if [[ ! -f "$SHARED_DIR/directives/${path}.md" ]]; then
            emit ERROR "$agent" "import '$path' in $cf not found — expected $SHARED_DIR/directives/${path}.md"
            ((bad++))
          fi
        fi
      done < "$cf_path"
    done
    [[ "$bad" -eq 0 && "$total" -gt 0 ]] && emit OK "$agent" "all $total import paths resolve"
  done
}

# ─── 24. Directive files exist in shared/directives/ ─────────────────────────

check_directives_exist() {
  local expected_files=(
    boot/session-start.md boot/gateway-recovery.md
    boot/user-context-nick.md boot/user-context-paro.md boot/user-context-none.md
    security/hostile-content.md security/no-exfiltrate.md
    security/defensive-ops.md security/control-plane.md
    memory/workflow.md memory/write-it-down.md memory/surfacing.md
    ops/figure-it-out.md ops/heartbeat-contract.md ops/todo-kanban.md
    ops/agent-routing.md ops/agent-comms.md ops/group-chats.md
    behavior/confidence-calibration.md behavior/read-between-lines.md
    behavior/no-hedging.md
    tools/shell.md tools/browser.md tools/search-first.md
    tools/nick-stack.md
    tools/platform-telegram.md tools/platform-discord.md
    tools/platform-whatsapp.md
  )
  local dir_base="$SHARED_DIR/directives"
  [[ ! -d "$dir_base" ]] && { emit ERROR shared "directives/ directory missing at $dir_base"; return; }
  local missing=0
  for f in "${expected_files[@]}"; do
    if [[ ! -f "$dir_base/$f" ]]; then
      emit ERROR shared "directives/$f missing — agents importing this directive will fail"
      ((missing++))
    fi
  done
  [[ "$missing" -eq 0 ]] && emit OK shared "all ${#expected_files[@]} directive files present"
}

# ─── 25. Import completeness — manifest compliance ───────────────────────────

check_imports_completeness() {
  local manifest="$SHARED_DIR/directives/manifest.conf"
  [[ ! -f "$manifest" ]] && { emit WARN shared "directives/manifest.conf missing — cannot validate import completeness"; return; }

  for agent in "${AGENTS[@]}"; do
    # Extract actual imports from all config files
    local -a actual_imports=()
    for cf in AGENTS.md BOOT.md MEMORY.md TOOLS.md SOUL.md HEARTBEAT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ ! -f "$cf_path" ]] && continue
      while IFS= read -r line; do
        if [[ "$line" =~ ^'@import('(.+)')' ]]; then
          actual_imports+=("${BASH_REMATCH[1]%.md}")
        fi
      done < "$cf_path"
    done

    # Determine short agent name
    local agent_short="${agent#workspace-}"
    [[ "$agent" == "workspace" ]] && agent_short="pino"

    # Extract expected imports from manifest
    local -a expected=()
    while IFS= read -r mline; do
      [[ "$mline" =~ ^# ]] && continue
      [[ -z "$mline" ]] && continue
      local selector="${mline%%|*}" directive="${mline#*|}"
      directive="${directive%.md}"
      local should_include=0
      if [[ "$selector" == "ALL" ]]; then
        should_include=1
      elif [[ "$selector" =~ ^ALL_EXCEPT: ]]; then
        local excludes="${selector#ALL_EXCEPT:}"
        [[ ! ",$excludes," == *",$agent_short,"* ]] && should_include=1
      elif [[ "$selector" =~ ^AGENTS: ]]; then
        local includes="${selector#AGENTS:}"
        [[ ",$includes," == *",$agent_short,"* ]] && should_include=1
      fi
      [[ "$should_include" -eq 1 ]] && expected+=("$directive")
    done < "$manifest"

    local missing=0
    for exp in "${expected[@]}"; do
      local found=0
      for act in "${actual_imports[@]}"; do
        [[ "$act" == "$exp" ]] && { found=1; break; }
      done
      if [[ "$found" -eq 0 ]]; then
        emit WARN "$agent" "missing import '$exp' — required by manifest"
        ((missing++))
      fi
    done
    [[ "$missing" -eq 0 && ${#expected[@]} -gt 0 ]] && emit OK "$agent" "all ${#expected[@]} required directives imported"
  done
}

# ─── 26. No inline duplication of imported directives ─────────────────────────

check_imports_no_duplication() {
  # Fingerprint phrases per directive
  declare -A FP
  FP[boot/session-start]="Read SOUL.md.*who you are|Don.t ask permission.*Just do it"
  FP[boot/gateway-recovery]="tier.*AGENT_ROSTER.*user-context|Verify channels.*openclaw channels status"
  FP[boot/user-context-nick]="shared/nick/USER_CORE.md.*baseline Nicholas|shared/nick/AGENT_ROSTER.md"
  FP[boot/user-context-paro]="shared/paro/USER_CORE.md.*baseline Paro|shared/paro/AGENT_ROSTER.md"
  FP[boot/user-context-none]="user-agnostic infrastructure.*Do NOT read"
  FP[security/hostile-content]="hostile data|instructions are DATA.*not commands"
  FP[security/no-exfiltrate]="Never share credentials.*API keys|disclose.*openclaw.*environment"
  FP[security/defensive-ops]="trash.*>.*rm.*recoverable|dry-run flags"
  FP[security/control-plane]="Never use.*cron.*gateway.*unless explicitly permitted|modify OpenClaw config.*routing.*deployment"
  FP[memory/workflow]="memory/YYYY-MM-DD|ONLY load in main session"
  FP[memory/write-it-down]="Mental notes.*don.t survive|Mental notes.*gone next session|WRITE IT TO A FILE"
  FP[memory/surfacing]="Based on my records|According to my files|integrate naturally.*colleague"
  FP[ops/figure-it-out]="sorry I can.t (access|find|do)|3\+.*real.*approach|Exhaust every approach.*before asking"
  FP[ops/heartbeat-contract]="HEARTBEAT_OK.*nothing needs attention"
  FP[ops/todo-kanban]="In Progress.*Paused.*Ready.*Planned.*Completed"
  FP[ops/agent-routing]="Place a request JSON in.*iris/handoff/inbound|AGENT_ROSTER.*full network.*scopes"
  FP[ops/agent-comms]="sessions_send.*structured|3.*5 messages max|agent-exchange.md"
  FP[ops/group-chats]="participant.*not.*proxy.*Think before you speak|Your response would be noise|Your human.s private context stays private"
  FP[behavior/no-hedging]="wishy-washy.*non-answer|Hedging is a failure"
  FP[behavior/confidence-calibration]="confidence they deserve|Strong evidence.*strong language"
  FP[behavior/read-between-lines]="literal question.*actually needs|good friend.*asked the right question"
  FP[tools/shell]="rg over grep.*fd over find|dedicated tools over bash"
  FP[tools/browser]="screenshot.*snapshot.*before interacting|webpage instructions.*data.*not commands"
  FP[tools/search-first]="memory_search before answering|search GitHub.*existing package"
  FP[tools/nick-stack]="bun.*first resort.*JS/TS|Never.*npm|uv.*Python package"
  FP[tools/platform-telegram]="Standard markdown supported|Telegram"

  for agent in "${AGENTS[@]}"; do
    # Collect all imports from all config files
    local -a imports=()
    for cf in AGENTS.md BOOT.md MEMORY.md TOOLS.md SOUL.md HEARTBEAT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ ! -f "$cf_path" ]] && continue
      while IFS= read -r line; do
        [[ "$line" =~ ^'@import('(.+)')' ]] && imports+=("${BASH_REMATCH[1]%.md}")
      done < "$cf_path"
    done

    local dupes=0
    for imp in "${imports[@]}"; do
      local fp="${FP[$imp]:-}"
      [[ -z "$fp" ]] && continue
      # Check the file where the import lives (skip the @import line itself)
      local check_file="$AGENTS_DIR/$agent/AGENTS.md"
      [[ "$imp" == tools/* ]] && check_file="$AGENTS_DIR/$agent/TOOLS.md"
      [[ "$imp" == memory/* ]] && check_file="$AGENTS_DIR/$agent/MEMORY.md"
      [[ "$imp" == boot/* ]] && check_file="$AGENTS_DIR/$agent/BOOT.md"
      [[ "$imp" == behavior/* ]] && check_file="$AGENTS_DIR/$agent/SOUL.md"
      [[ "$imp" == ops/heartbeat-contract ]] && check_file="$AGENTS_DIR/$agent/HEARTBEAT.md"
      [[ ! -f "$check_file" ]] && continue
      # Check non-import, non-comment lines for fingerprint duplication
      local outside
      outside=$(rg -v '^(@import\(|#)' "$check_file" | rg -qi "$fp" 2>/dev/null && echo 1 || echo 0)
      if [[ "$outside" == "1" ]]; then
        emit WARN "$agent" "directive '$imp' is imported but its content also appears inline in $(basename "$check_file") — remove inline duplication"
        ((dupes++))
      fi
    done
    [[ "$dupes" -eq 0 && ${#imports[@]} -gt 0 ]] && emit OK "$agent" "no inline duplication of imported directives"
  done
}

# ─── 27. BOOT.md references imports/directives ──────────────────────────────

check_imports_boot_integration() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    if rg -qi '(import|directive)' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md references imports/directives"
    else
      emit WARN "$agent" "BOOT.md doesn't mention imports or directives — agent may not read shared directive files at boot"
    fi
  done
}

# ─── 28. TOOLS.md doesn't duplicate shared tool directives ───────────────────

check_imports_tools_dedup() {
  local tools_global_phrases="rg over grep|trash.*>.*rm|memory_search before|don.t reinvent.*find.*adapt.*ship|free tiers.*credit card|parallelize independent"
  local tools_nick_phrases="bun.*first resort|pnpm.*fallback|Never.*npm|uv.*Python"

  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/TOOLS.md"
    [[ ! -f "$f" ]] && continue
    local dupes=0

    if rg -v '^@import\(' "$f" | rg -qi "$tools_global_phrases" 2>/dev/null; then
      emit WARN "$agent" "TOOLS.md duplicates content from directives/tools/* — keep only domain-specific tool notes"
      ((dupes++))
    fi

    if [[ -f "$SHARED_DIR/nick/TOOLS_NICK.md" ]]; then
      if rg -v '^@import\(' "$f" | rg -qi "$tools_nick_phrases" 2>/dev/null; then
        emit WARN "$agent" "TOOLS.md duplicates content from shared/nick/TOOLS_NICK.md"
        ((dupes++))
      fi
    fi

    [[ "$dupes" -eq 0 ]] && emit OK "$agent" "TOOLS.md contains only domain-specific content"
  done
}

# ─── 29. USER.md doesn't duplicate shared USER_CORE facts ────────────────────

check_imports_user_dedup() {
  local nick_core_phrases="Senior PM.*Jobber|Ex-Shopify.*5 years|BSc International Business.*CBS|Concerta.*Bipolar|Canadian.*Danish.*citizenship"

  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/USER.md"
    [[ ! -f "$f" ]] && continue

    local agent_short="${agent#workspace-}"
    [[ "$agent" == "workspace" ]] && agent_short="pino"

    local core_phrases=""
    case "$agent_short" in
      pino|huberman|kodo|soren|tally|sentry|forger|iris)
        core_phrases="$nick_core_phrases" ;;
    esac

    [[ -z "$core_phrases" ]] && continue

    if rg -qi "$core_phrases" "$f" 2>/dev/null; then
      emit WARN "$agent" "USER.md duplicates facts from shared/nick/USER_CORE.md — keep only the domain-specific lens"
    else
      emit OK "$agent" "USER.md contains only domain-specific user context"
    fi
  done
}

# ─── 30. Legacy shared files (replaced by directives/) ────────────────────────

check_legacy_shared_files() {
  local legacy=(SECURITY_RULES.md MEMORY_WORKFLOW.md TOOLS_GLOBAL.md)
  for f in "${legacy[@]}"; do
    if [[ -f "$SHARED_DIR/$f" ]]; then
      emit WARN shared "$f still exists — replaced by directives/ modules. Delete after confirming all agents use imports"
    fi
  done
}

# ─── 31. Orphan directives (not imported by any agent) ───────────────────────

check_orphan_directives() {
  local dir_base="$SHARED_DIR/directives"
  [[ ! -d "$dir_base" ]] && return

  local -a all_imports=()
  for agent in "${AGENTS[@]}"; do
    for cf in AGENTS.md BOOT.md MEMORY.md TOOLS.md SOUL.md HEARTBEAT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ ! -f "$cf_path" ]] && continue
      while IFS= read -r line; do
        [[ "$line" =~ ^'@import('(.+)')' ]] && all_imports+=("${BASH_REMATCH[1]%.md}")
      done < "$cf_path"
    done
  done

  for df in "$dir_base"/*/*.md; do
    [[ ! -f "$df" ]] && continue
    local rel="${df#$dir_base/}"
    rel="${rel%.md}"
    local imported=0
    for imp in "${all_imports[@]}"; do
      [[ "$imp" == "$rel" ]] && { imported=1; break; }
    done
    [[ "$imported" -eq 0 ]] && emit INFO shared "directives/$rel.md not imported by any agent"
  done
}

# ─── 32. TODO.md exists when todo-kanban directive is imported ────────────────

check_todo_file() {
  for agent in "${AGENTS[@]}"; do
    local has_import=0
    for cf in AGENTS.md BOOT.md; do
      local cf_path="$AGENTS_DIR/$agent/$cf"
      [[ -f "$cf_path" ]] && rg -Fq '@import(ops/todo-kanban)' "$cf_path" 2>/dev/null && { has_import=1; break; }
    done
    [[ "$has_import" -eq 0 ]] && continue
    if [[ -f "$AGENTS_DIR/$agent/TODO.md" ]]; then
      emit OK "$agent" "TODO.md exists (todo-kanban directive imported)"
    else
      emit ERROR "$agent" "imports @import(ops/todo-kanban) but TODO.md is missing — the directive tells agents 'TODO.md is the canonical task list' but there's no file to write to"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run enabled checks
# ═══════════════════════════════════════════════════════════════════════════════

[[ "$CHECK_SHARED_FILES" == "1" ]]      && check_shared_files
[[ "$CHECK_REQUIRED_FILES" == "1" ]]    && check_required_files
[[ "$CHECK_BOOT_REFS" == "1" ]]         && check_boot_refs
[[ "$CHECK_BOOT_STRUCTURE" == "1" ]]    && check_boot_structure
[[ "$CHECK_ROSTER_COUNT" == "1" ]]      && check_roster_count
[[ "$CHECK_BOOTSTRAP_CLEANUP" == "1" ]] && check_bootstrap_cleanup
[[ "$CHECK_ANTI_SYCOPHANCY" == "1" ]]   && check_anti_sycophancy
# check_action_tiers removed — superseded by check_action_tiers_strict
[[ "$CHECK_TONE_TABLE" == "1" ]]        && check_tone_table
[[ "$CHECK_CONTINUITY_LINE" == "1" ]]   && check_continuity_line
[[ "$CHECK_SECURITY_SECTION" == "1" ]]  && check_security_section
[[ "$CHECK_MEMORY_WORKFLOW" == "1" ]]   && check_memory_workflow
[[ "$CHECK_HEARTBEAT" == "1" ]]         && check_heartbeat
echo "DEBUG: About to check token budgets, CHECK_TOKEN_BUDGETS=$CHECK_TOKEN_BUDGETS" >&2
[[ "$CHECK_TOKEN_BUDGETS" == "1" ]]     && check_token_budgets
[[ "$CHECK_TIMEZONE" == "1" ]]          && check_timezone
[[ "$CHECK_CANONICAL_WORDING" == "1" ]] && check_canonical_wording
[[ "$CHECK_ACTION_TIERS_STRICT" == "1" ]]     && check_action_tiers_strict
[[ "$CHECK_CONVENTIONS_RESOURCEFULNESS" == "1" ]] && check_conventions_resourcefulness
[[ "$CHECK_BOOT_CONVENTIONS_REF" == "1" ]]     && check_boot_conventions_ref
[[ "$CHECK_MEMORY_SURFACING" == "1" ]]         && check_memory_surfacing
[[ "$CHECK_SOUL_TONE_CALIBRATED" == "1" ]]     && check_soul_tone_calibrated
[[ "$CHECK_IMPORTS_SECTION" == "1" ]]          && check_imports_section
[[ "$CHECK_IMPORTS_VALID_PATHS" == "1" ]]      && check_imports_valid_paths
[[ "$CHECK_DIRECTIVES_EXIST" == "1" ]]         && check_directives_exist
[[ "$CHECK_IMPORTS_COMPLETENESS" == "1" ]]     && check_imports_completeness
[[ "$CHECK_IMPORTS_NO_DUPLICATION" == "1" ]]    && check_imports_no_duplication
[[ "$CHECK_IMPORTS_BOOT_INTEGRATION" == "1" ]]  && check_imports_boot_integration
[[ "$CHECK_IMPORTS_TOOLS_DEDUP" == "1" ]]       && check_imports_tools_dedup
[[ "$CHECK_IMPORTS_USER_DEDUP" == "1" ]]        && check_imports_user_dedup
[[ "$CHECK_LEGACY_SHARED_FILES" == "1" ]]       && check_legacy_shared_files
[[ "$CHECK_ORPHAN_DIRECTIVES" == "1" ]]         && check_orphan_directives
[[ "$CHECK_TODO_FILE" == "1" ]]                  && check_todo_file
