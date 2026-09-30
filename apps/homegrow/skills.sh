#!/usr/bin/env bash
# homegrow/skills.sh — Skill-specific convention checks
# Called by run.sh in skills mode. Uses emit() / AGENTS_DIR / AGENTS / DISABLED_RULES from parent.
#
# Rule IDs (prefix: skill/):
#   skill/file-exists          SKILL.md must exist
#   skill/description          Clear description/purpose statement
#   skill/when-to-use          When-to-use / trigger guidance
#   skill/structure            Structured headings (≥2)
#   skill/dangerous-commands   No rm -rf /, curl|sh, etc.
#   skill/actionable           Steps, bullets, or code examples present
#   skill/injection            No prompt injection patterns
#   skill/file-count           Reasonable number of files per skill
#   skill/scope-boundaries     Defines what the skill should NOT do
#   skill/examples             Concrete examples present
#   skill/output-format        Output format specification
#   skill/error-handling        Error recovery / fallback instructions
#   skill/secrets              No hardcoded secrets, API keys, or PII
#   skill/restrictions         Safety restrictions present (NEVER/MUST NOT)
#   skill/tool-boundaries      Tool use boundaries defined (if referencing tools)
#   skill/idempotent           No unreversible side effects without warning
#
# Citation: patterns derived from empirical analysis of 407 leaked system prompts
# across 33 companies (arxiv.org/abs/2609.31575, Sep 2026) and Claude Code's
# skill architecture (description + allowedTools + bundled files).

rule_enabled() {
  local rule_id="$1"
  [[ -z "${DISABLED_RULES:-}" ]] && return 0
  [[ ",$DISABLED_RULES," == *",$rule_id,"* ]] && return 1
  return 0
}

# ─── skill/file-exists ───────────────────────────────────────────────────────

check_skill_file_exists() {
  rule_enabled "skill/file-exists" || return 0
  for skill in "${AGENTS[@]}"; do
    local skill_dir="$AGENTS_DIR/$skill"
    [[ ! -d "$skill_dir" ]] && continue
    if [[ -f "$skill_dir/SKILL.md" ]]; then
      if [[ ! -s "$skill_dir/SKILL.md" ]]; then
        emit ERROR "$skill" "[skill/file-exists] SKILL.md is empty — must contain skill instructions"
      else
        emit OK "$skill" "[skill/file-exists] SKILL.md exists"
      fi
    else
      emit ERROR "$skill" "[skill/file-exists] SKILL.md missing — every skill must have a SKILL.md file"
    fi
  done
}

# ─── skill/description ───────────────────────────────────────────────────────

check_skill_description() {
  rule_enabled "skill/description" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local first_line
    first_line=$(head -1 "$f" | tr -d '#' | xargs)
    if [[ ${#first_line} -gt 10 ]]; then
      emit OK "$skill" "[skill/description] SKILL.md has description"
    elif rg -qi '(description|purpose|what this|overview|about|this skill)' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/description] SKILL.md has description"
    else
      emit WARN "$skill" "[skill/description] SKILL.md has no clear description — add a summary of what this skill does. Every leaked system prompt starts with identity/purpose (2.9% of all prompt tokens across 33 companies — arxiv 2609.31575)"
    fi
  done
}

# ─── skill/when-to-use ───────────────────────────────────────────────────────

check_skill_when_to_use() {
  rule_enabled "skill/when-to-use" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi '(when to use|use (this|when)|trigger|invoke|run this|apply this|activate|if the user|should be used)' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/when-to-use] SKILL.md has when-to-use guidance"
    else
      emit WARN "$skill" "[skill/when-to-use] SKILL.md missing when-to-use guidance — agents need to know WHEN to invoke this skill. Claude Code skills use description field for this (claude-code skill architecture)"
    fi
  done
}

# ─── skill/structure ─────────────────────────────────────────────────────────

check_skill_structure() {
  rule_enabled "skill/structure" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local heading_count
    heading_count=$(rg -c '^#+\s' "$f" 2>/dev/null || echo 0)
    if [[ "$heading_count" -ge 2 ]]; then
      emit OK "$skill" "[skill/structure] SKILL.md has $heading_count sections"
    elif [[ "$heading_count" -eq 1 ]]; then
      emit INFO "$skill" "[skill/structure] SKILL.md has only 1 heading — consider adding more structure"
    else
      emit WARN "$skill" "[skill/structure] SKILL.md has no headings — structured skills with clear sections are more reliably followed. Top prompts use heading hierarchy for 12.4% of content (formatting/style — arxiv 2609.31575)"
    fi
  done
}

# ─── skill/dangerous-commands ────────────────────────────────────────────────

check_skill_dangerous_commands() {
  rule_enabled "skill/dangerous-commands" || return 0
  local dangerous_patterns='rm -rf\s+/|rm -rf\s+~|rm -rf\s+\$HOME|sudo\s+rm|mkfs\.|dd\s+if=|>\s*/dev/sd|chmod\s+777|curl.*\|\s*(ba)?sh|wget.*\|\s*(ba)?sh'
  for skill in "${AGENTS[@]}"; do
    local skill_dir="$AGENTS_DIR/$skill"
    [[ ! -d "$skill_dir" ]] && continue
    local found=0
    for f in "$skill_dir"/*.md "$skill_dir"/*.sh "$skill_dir"/*.py "$skill_dir"/*.ts "$skill_dir"/*.js; do
      [[ -f "$f" ]] || continue
      if rg -qP "$dangerous_patterns" "$f" 2>/dev/null; then
        local fname
        fname=$(basename "$f")
        emit ERROR "$skill" "[skill/dangerous-commands] $fname contains dangerous commands (rm -rf /, sudo rm, curl|sh). Claude Code: 'carefully consider the reversibility and blast radius of actions'"
        found=1
      fi
    done
    [[ "$found" -eq 0 ]] && emit OK "$skill" "[skill/dangerous-commands] no dangerous commands found"
  done
}

# ─── skill/actionable ────────────────────────────────────────────────────────

check_skill_actionable() {
  rule_enabled "skill/actionable" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local has_steps has_bullets raw_fences has_code
    has_steps=$(rg -c '^\d+\.\s' "$f" 2>/dev/null || echo 0)
    has_bullets=$(rg -c '^[-*]\s' "$f" 2>/dev/null || echo 0)
    raw_fences=$(rg -c '^```' "$f" 2>/dev/null || echo 0)
    has_code=$(( raw_fences / 2 ))
    local total=$((has_steps + has_bullets + has_code))
    if [[ "$total" -ge 3 ]]; then
      emit OK "$skill" "[skill/actionable] actionable content ($has_steps steps, $has_bullets bullets, $has_code code blocks)"
    elif [[ "$total" -ge 1 ]]; then
      emit INFO "$skill" "[skill/actionable] some structure — consider adding more steps/examples"
    else
      emit WARN "$skill" "[skill/actionable] prose-only — add numbered steps, bullet lists, or code examples. Devin/Claude Code define step-by-step workflow patterns (leaked prompt analysis)"
    fi
  done
}

# ─── skill/injection ─────────────────────────────────────────────────────────

check_skill_injection() {
  rule_enabled "skill/injection" || return 0
  local injection_patterns='ignore (all )?previous|disregard (all )?instructions|you are now|new instructions|forget (all|everything|your)|override (your|all)|reveal.*system prompt|leak.*system prompt|print.*system prompt|jailbreak'
  for skill in "${AGENTS[@]}"; do
    local skill_dir="$AGENTS_DIR/$skill"
    [[ ! -d "$skill_dir" ]] && continue
    local found=0
    for f in "$skill_dir"/*.md; do
      [[ -f "$f" ]] || continue
      if rg -qi "$injection_patterns" "$f" 2>/dev/null; then
        local fname
        fname=$(basename "$f")
        emit WARN "$skill" "[skill/injection] $fname matches injection patterns — verify this is defensive, not vulnerable. 56% of vendors use non-disclosure; only 7/62 combine ≥3 injection-boundary techniques (arxiv 2609.31575 Table 5)"
        found=1
      fi
    done
    [[ "$found" -eq 0 ]] && emit OK "$skill" "[skill/injection] no injection patterns detected"
  done
}

# ─── skill/file-count ────────────────────────────────────────────────────────

check_skill_file_count() {
  rule_enabled "skill/file-count" || return 0
  for skill in "${AGENTS[@]}"; do
    local skill_dir="$AGENTS_DIR/$skill"
    [[ ! -d "$skill_dir" ]] && continue
    local md_count=0
    for f in "$skill_dir"/*.md; do
      [[ -f "$f" ]] && ((md_count++))
    done
    if [[ "$md_count" -le 5 ]]; then
      emit OK "$skill" "[skill/file-count] $md_count .md file(s)"
    elif [[ "$md_count" -le 10 ]]; then
      emit INFO "$skill" "[skill/file-count] $md_count .md files — consider consolidating"
    else
      emit WARN "$skill" "[skill/file-count] $md_count .md files — skills should be focused; split into multiple skills if scope is too broad"
    fi
  done
}

# ─── skill/scope-boundaries ──────────────────────────────────────────────────
# Every top leaked prompt defines what the model should NOT do. Claude Code:
# "NEVER run destructive git commands unless the user explicitly requests"

check_skill_scope_boundaries() {
  rule_enabled "skill/scope-boundaries" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi '(do not .{0,30}(use|run|call|change|modify|delete|edit)|don.t .{0,30}(use|run|call|change|modify|delete)|never .{0,20}(use|run|call|change|modify|delete|apply)|must not|should not|out of scope|not responsible|not (for|designed|intended) )' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/scope-boundaries] has scope boundaries"
    else
      emit INFO "$skill" "[skill/scope-boundaries] no scope boundaries found — consider defining what the skill should NOT do. 5.4% of top prompt tokens are safety/boundary rules (arxiv 2609.31575)"
    fi
  done
}

# ─── skill/examples ──────────────────────────────────────────────────────────
# Best system prompts include concrete examples. ChatGPT: "encode behavioral
# patterns through examples and constraints" (leaked prompt analysis).

check_skill_examples() {
  rule_enabled "skill/examples" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local raw_fences has_code_blocks has_example_keyword
    raw_fences=$(rg -c '^```' "$f" 2>/dev/null || echo 0)
    has_code_blocks=$(( raw_fences / 2 ))
    has_example_keyword=$(rg -ci '(example|e\.g\.|for instance|sample|such as|like this|here.s|demonstration)' "$f" 2>/dev/null || echo 0)
    if [[ "$has_code_blocks" -ge 1 || "$has_example_keyword" -ge 2 ]]; then
      emit OK "$skill" "[skill/examples] has examples ($has_code_blocks code blocks, $has_example_keyword example references)"
    else
      emit INFO "$skill" "[skill/examples] no examples found — concrete examples improve model adherence. ChatGPT encodes behavior through examples, not just rules"
    fi
  done
}

# ─── skill/output-format ─────────────────────────────────────────────────────
# 12.4% of leaked prompt content is formatting/style instructions (arxiv 2609.31575).

check_skill_output_format() {
  rule_enabled "skill/output-format" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi '(output|format|respond|response|return|reply|produce|generate|emit|print|write).*(json|markdown|yaml|xml|list|table|bullet|numbered|code|text|csv|html|plain)' "$f" 2>/dev/null \
      || rg -qi '(format|output|respond) (in|as|with|using|should be)' "$f" 2>/dev/null \
      || rg -qi '## (output|format|response)' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/output-format] has output format guidance"
    else
      emit INFO "$skill" "[skill/output-format] no output format — consider specifying expected format. 12.4% of top prompt content is formatting/style (arxiv 2609.31575)"
    fi
  done
}

# ─── skill/error-handling ────────────────────────────────────────────────────
# Claude Code: defines "what to do when a command fails, how to retry"

check_skill_error_handling() {
  rule_enabled "skill/error-handling" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi '(error|fail|fallback|retry|recover|exception|catch|handle|graceful|degrade|abort|timeout|bail|troubleshoot|if.*fails|when.*wrong|if.*broken)' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/error-handling] has error handling guidance"
    else
      emit INFO "$skill" "[skill/error-handling] no error handling — consider adding fallback/retry instructions. Every top coding agent defines error recovery (Claude Code, Devin, Cursor)"
    fi
  done
}

# ─── skill/secrets ────────────────────────────────────────────────────────────
# Hardcoded API keys, tokens, passwords in skill files.

check_skill_secrets() {
  rule_enabled "skill/secrets" || return 0
  local secret_patterns='(api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|bearer|password|passwd|secret[_-]?key)\s*[=:]\s*["\x27]?[A-Za-z0-9+/=_-]{16,}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|gho_[a-zA-Z0-9]{30,}|xoxb-[0-9]{10,}'
  for skill in "${AGENTS[@]}"; do
    local skill_dir="$AGENTS_DIR/$skill"
    [[ ! -d "$skill_dir" ]] && continue
    local found=0
    for f in "$skill_dir"/*.md; do
      [[ -f "$f" ]] || continue
      if rg -qP "$secret_patterns" "$f" 2>/dev/null; then
        local fname
        fname=$(basename "$f")
        emit ERROR "$skill" "[skill/secrets] $fname may contain hardcoded secrets (API keys, tokens)"
        found=1
      fi
    done
    [[ "$found" -eq 0 ]] && emit OK "$skill" "[skill/secrets] no hardcoded secrets detected"
  done
}

# ─── skill/restrictions ──────────────────────────────────────────────────────
# The strictest language guards operational behavior. Among 4,725 rule-lines with
# emphatic markers, tool/function protocol (639), file safety (478), formatting (468)
# dominate. (arxiv 2609.31575 Fig. 7)

check_skill_restrictions() {
  rule_enabled "skill/restrictions" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local restriction_count
    restriction_count=$(rg -c '\b(NEVER|MUST NOT|DO NOT|IMPORTANT|CRITICAL|REQUIRED|STRICTLY|ALWAYS|FORBIDDEN|PROHIBITED)\b' "$f" 2>/dev/null || echo 0)
    if [[ "$restriction_count" -ge 3 ]]; then
      emit OK "$skill" "[skill/restrictions] $restriction_count emphatic markers (NEVER/MUST NOT/etc.)"
    elif [[ "$restriction_count" -ge 1 ]]; then
      emit OK "$skill" "[skill/restrictions] $restriction_count emphatic marker(s)"
    else
      emit INFO "$skill" "[skill/restrictions] no emphatic restrictions — consider adding NEVER/MUST NOT for critical constraints. Top prompts average 11.4:1 tool-protocol vs safety restrictions (arxiv 2609.31575)"
    fi
  done
}

# ─── skill/tool-boundaries ───────────────────────────────────────────────────
# 58% of all leaked prompt content is tool/protocol rules (arxiv 2609.31575).

check_skill_tool_boundaries() {
  rule_enabled "skill/tool-boundaries" || return 0
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    local refs_tools
    refs_tools=$(rg -ci '(tool|command|function|api|endpoint|call|invoke|execute|run|shell|bash|terminal|cli)' "$f" 2>/dev/null || echo 0)
    if [[ "$refs_tools" -lt 2 ]]; then
      emit OK "$skill" "[skill/tool-boundaries] few tool references — boundary check not applicable"
      continue
    fi
    if rg -qi '(prefer|use|instead of|rather than|not.*use|avoid.*using|do not.*call|only use)' "$f" 2>/dev/null; then
      emit OK "$skill" "[skill/tool-boundaries] has tool use boundaries"
    else
      emit INFO "$skill" "[skill/tool-boundaries] references tools but no usage boundaries — consider specifying preferred tools/approaches. Claude Code: 'Prefer dedicated tools over Bash when one fits'"
    fi
  done
}

# ─── skill/idempotent ────────────────────────────────────────────────────────
# Claude Code: "Carefully consider the reversibility and blast radius of actions"

check_skill_idempotent() {
  rule_enabled "skill/idempotent" || return 0
  local destructive_patterns='(deploy|publish|release|push|send|post|delete|drop|truncate|migrate|install|uninstall|upgrade|remove|destroy|reset|format|overwrite)'
  for skill in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$skill/SKILL.md"
    [[ ! -f "$f" ]] && continue
    if rg -qi "$destructive_patterns" "$f" 2>/dev/null; then
      if rg -qi '(confirm|approval|review|dry.run|preview|check first|reversible|backup|rollback|undo|cautio)' "$f" 2>/dev/null; then
        emit OK "$skill" "[skill/idempotent] references destructive ops with safeguards"
      else
        emit WARN "$skill" "[skill/idempotent] references destructive operations without safeguards — add confirmation/dry-run/backup guidance. Claude Code: 'check with the user before proceeding' for irreversible actions"
      fi
    else
      emit OK "$skill" "[skill/idempotent] no destructive operations"
    fi
  done
}

# ─── Run all enabled skill checks ────────────────────────────────────────────

check_skill_file_exists
check_skill_description
check_skill_when_to_use
check_skill_structure
check_skill_dangerous_commands
check_skill_actionable
check_skill_injection
check_skill_file_count
check_skill_scope_boundaries
check_skill_examples
check_skill_output_format
check_skill_error_handling
check_skill_secrets
check_skill_restrictions
check_skill_tool_boundaries
check_skill_idempotent
