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

# ─── Config defaults (overridden by rules.conf) ──────────────────────────────

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

BUDGET_AGENTS_MD=800
BUDGET_SOUL_MD=200
BUDGET_IDENTITY_MD=80
BUDGET_USER_MD=350
BUDGET_TOOLS_MD=200
BUDGET_HEARTBEAT_MD=100
BUDGET_MEMORY_MD=500

CONF_FILE="$SCRIPT_DIR/rules.conf"
# shellcheck source=rules.conf
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# ─── Helpers ──────────────────────────────────────────────────────────────────

emit() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

estimate_tokens() {
  local words
  words=$(wc -w < "$1" | tr -d ' ')
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

# ═══════════════════════════════════════════════════════════════════════════════
# Checks — each function emits STATUS|context|message lines
# ═══════════════════════════════════════════════════════════════════════════════

# ─── 1. Shared files exist ────────────────────────────────────────────────────

check_shared_files() {
  for f in USER_CORE.md AGENT_ROSTER.md SECURITY_RULES.md MEMORY_WORKFLOW.md TOOLS_BASE.md CONVENTIONS.md; do
    if [[ -f "$SHARED_DIR/$f" ]]; then
      emit OK shared "$f exists"
    else
      emit ERROR shared "$f missing — shared config is inherited by ALL agents at boot. Missing shared files break the entire system, not just one agent"
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

# ─── 3. BOOT.md references _shared/ files ────────────────────────────────────

check_boot_refs() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    if rg -q '_shared/USER_CORE.md' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs USER_CORE.md"
    else
      emit WARN "$agent" "BOOT.md missing USER_CORE.md ref — without this, agent doesn't load shared user context on startup"
    fi
    if rg -q '_shared/AGENT_ROSTER.md' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs AGENT_ROSTER.md"
    else
      emit WARN "$agent" "BOOT.md missing AGENT_ROSTER.md ref — without this, agent doesn't know what other agents exist for delegation"
    fi
  done
}

# ─── 4. BOOT.md structure (Standard section + checklist) ─────────────────────

check_boot_structure() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    local has_standard has_checklist
    has_standard=$(rg -q '^## Standard' "$boot" 2>/dev/null && echo 1 || echo 0)
    has_checklist=$(rg -q '^\- \[ \]' "$boot" 2>/dev/null && echo 1 || echo 0)
    if [[ "$has_standard" == "1" && "$has_checklist" == "1" ]]; then
      emit OK "$agent" "BOOT.md has Standard section with checklist"
    elif [[ "$has_checklist" == "1" ]]; then
      emit OK "$agent" "BOOT.md has checklist items"
    elif [[ "$has_standard" == "1" ]]; then
      emit WARN "$agent" "BOOT.md has Standard section but no checklist items — boot checklists ensure nothing is skipped on startup (read memory, check tasks, load context)"
    else
      emit WARN "$agent" "BOOT.md missing Standard section and checklist format — agents need a structured startup sequence to restore context after restart"
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
    [[ "$(basename "$d")" == "template" ]] && continue
    ((actual_dirs++))
  done
  if [[ "$roster_count" -eq "$actual_dirs" ]]; then
    emit OK roster "count matches ($roster_count agents)"
  else
    emit ERROR roster "AGENT_ROSTER.md lists $roster_count, found $actual_dirs agent dirs — roster drift means agents can't find each other for delegation"
  fi
}

# ─── 6. Bootstrap cleanup ────────────────────────────────────────────────────

check_bootstrap_cleanup() {
  for agent in "${AGENTS[@]}"; do
    [[ -f "$AGENTS_DIR/$agent/BOOTSTRAP.md" ]] \
      && emit WARN "$agent" "BOOTSTRAP.md still exists — delete after bootstrapping. BOOTSTRAP.md runs once on first boot, keeping it wastes tokens on every subsequent startup"
  done
}

# ─── 7. SOUL.md anti-sycophancy opener ───────────────────────────────────────

check_anti_sycophancy() {
  for agent in "${AGENTS[@]}"; do
    local soul="$AGENTS_DIR/$agent/SOUL.md"
    [[ ! -f "$soul" ]] && continue
    if head -10 "$soul" | rg -qi 'skip.*(filler|great question|happy to help|hedging|commentary)|just answer.*start with|start with the (answer|diff|evidence)' 2>/dev/null; then
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
    [[ ! -f "$soul" ]] && continue
    if rg -qi 'wake up fresh|files are my memory|session.*fresh|fresh.*context|these files.*memory' "$soul" 2>/dev/null; then
      emit OK "$agent" "SOUL.md has continuity line"
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
    if rg -q 'SECURITY_RULES.md' "$f" 2>/dev/null || rg -qi '^##.*security' "$f" 2>/dev/null; then
      emit OK "$agent" "AGENTS.md has security section"
    else
      emit WARN "$agent" "AGENTS.md missing security section. Agents process untrusted input (forwarded messages, URLs) — without security guidance they have no injection defense. Reference _shared/SECURITY_RULES.md or add ## Security"
    fi
  done
}

# ─── 12. AGENTS.md memory workflow reference ─────────────────────────────────

check_memory_workflow() {
  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/AGENTS.md"
    [[ ! -f "$f" ]] && continue
    if rg -q 'MEMORY_WORKFLOW' "$f" 2>/dev/null || rg -qi '^##.*memory' "$f" 2>/dev/null; then
      emit OK "$agent" "AGENTS.md has memory workflow"
    else
      emit WARN "$agent" "AGENTS.md missing memory workflow — without this, the agent can store memories but doesn't know HOW to surface them naturally. See docs/MASTER_SUMMARY.md #7"
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
      task_lines=$(rg -c '^- ' "$hb" 2>/dev/null || echo 0)
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

# ─── 14. Token budgets ───────────────────────────────────────────────────────

check_token_budgets() {
  local budgeted_files=(AGENTS.md SOUL.md IDENTITY.md USER.md TOOLS.md HEARTBEAT.md MEMORY.md)
  for agent in "${AGENTS[@]}"; do
    for fname in "${budgeted_files[@]}"; do
      local f="$AGENTS_DIR/$agent/$fname"
      [[ ! -f "$f" ]] && continue
      local tokens budget
      tokens=$(estimate_tokens "$f")
      budget=$(get_budget "$fname")
      [[ "$budget" -eq 0 ]] && continue
      if [[ $tokens -gt $budget ]]; then
        emit WARN "$agent" "$fname ~${tokens} tokens (budget: ≤${budget}). Every file loads on every message — extra tokens compound fast. HEARTBEAT.md at 100 tokens fires ~48x/day = ~4,800 tokens/day"
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
    "autism|mild autism traits"
    "bipolar|Bipolar II"
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
    (rg -qi '^#+\s*(when asked|on request|if asked|notify)' "$f" 2>/dev/null || rg -qi '\*\*(when asked|on request|notify after)\*\*' "$f" 2>/dev/null) && ((tier_count++))
    (rg -qi '^#+\s*(ask first|confirm before|check before)' "$f" 2>/dev/null || rg -qi '\*\*(ask first|confirm before|check before)\*\*' "$f" 2>/dev/null) && ((tier_count++))
    (rg -qi '^#+\s*never\b' "$f" 2>/dev/null || rg -qi '\*\*never\*\*' "$f" 2>/dev/null) && ((tier_count++))
    if [[ "$tier_count" -ge 3 ]]; then
      emit OK "$agent" "AGENTS.md has $tier_count/4 action tiers"
    elif [[ "$tier_count" -ge 1 ]]; then
      emit WARN "$agent" "AGENTS.md has only $tier_count/4 action tiers (need ≥3). Action tiers are OpenClaw's strongest pattern — no other company structures permissions this cleanly. See docs/MASTER_SUMMARY.md #3, docs/AGI_FOCUSED_AUDIT.md §II Theme 1"
    else
      emit ERROR "$agent" "AGENTS.md missing action tiers (## Always / ## When Asked / ## Ask First / ## Never). Action tiers are OpenClaw's signature architecture — they map agent autonomy into auditable structured tiers. Every agent must have them. See docs/MASTER_SUMMARY.md #3, docs/AGI_FOCUSED_AUDIT.md §IV Rules Tier 1"
    fi
  done
}

# ─── 18. CONVENTIONS.md has resourcefulness directive ─────────────────────────

check_conventions_resourcefulness() {
  local f="$SHARED_DIR/CONVENTIONS.md"
  [[ ! -f "$f" ]] && return
  if rg -qi '(figure.it.out|exhaust.*(option|approach)|partial.completion|try.before.ask|don.t ask.*(clarif|permiss))' "$f" 2>/dev/null; then
    emit OK shared "CONVENTIONS.md has resourcefulness directive"
  else
    emit WARN shared "CONVENTIONS.md missing resourcefulness / 'figure it out' directive. This is the #1 universal finding across all 27+ industry prompts reviewed — every agentic company (OpenAI, Anthropic, Perplexity, Notion) demands agents act first and ask never. Without this in shared conventions, 6 of 7 agents have no mandate to exhaust approaches before asking. See docs/MASTER_SUMMARY.md #1, docs/AGI_FOCUSED_AUDIT.md §II Theme 1"
  fi
}

# ─── 19. BOOT.md references CONVENTIONS.md ────────────────────────────────────

check_boot_conventions_ref() {
  for agent in "${AGENTS[@]}"; do
    local boot="$AGENTS_DIR/$agent/BOOT.md"
    [[ ! -f "$boot" ]] && continue
    if rg -q 'CONVENTIONS.md' "$boot" 2>/dev/null; then
      emit OK "$agent" "BOOT.md refs CONVENTIONS.md"
    else
      emit WARN "$agent" "BOOT.md missing CONVENTIONS.md reference. CONVENTIONS.md is the most critical shared file — it's the law all agents inherit. Without loading it at boot, the agent misses all shared behavioral directives (resourcefulness, self-healing, communication laws). See docs/AGI_FOCUSED_AUDIT.md §IV Rules Tier 1 Rule 4"
    fi
  done
}

# ─── 20. MEMORY_WORKFLOW.md has surfacing guidance ────────────────────────────

check_memory_surfacing() {
  local f="$SHARED_DIR/MEMORY_WORKFLOW.md"
  [[ ! -f "$f" ]] && return
  if rg -qi '(natural|invisible|seamless|never.*(say|announce).*based.on|just.*(know|remember))' "$f" 2>/dev/null; then
    emit OK shared "MEMORY_WORKFLOW.md has surfacing guidance"
  else
    emit WARN shared "MEMORY_WORKFLOW.md missing memory surfacing rules. This is the difference between a bot ('Based on my records, you prefer dark mode') and a friend who just knows. Gemini 3 Fast has the most sophisticated protocol: zero-hedging, source anonymity. Claude says 'respond as if information exists naturally in immediate awareness.' See docs/MASTER_SUMMARY.md #7, docs/AGI_FOCUSED_AUDIT.md §II Theme 4"
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
[[ "$CHECK_TOKEN_BUDGETS" == "1" ]]     && check_token_budgets
[[ "$CHECK_TIMEZONE" == "1" ]]          && check_timezone
[[ "$CHECK_CANONICAL_WORDING" == "1" ]] && check_canonical_wording
[[ "$CHECK_ACTION_TIERS_STRICT" == "1" ]]     && check_action_tiers_strict
[[ "$CHECK_CONVENTIONS_RESOURCEFULNESS" == "1" ]] && check_conventions_resourcefulness
[[ "$CHECK_BOOT_CONVENTIONS_REF" == "1" ]]     && check_boot_conventions_ref
[[ "$CHECK_MEMORY_SURFACING" == "1" ]]         && check_memory_surfacing
[[ "$CHECK_SOUL_TONE_CALIBRATED" == "1" ]]     && check_soul_tone_calibrated
