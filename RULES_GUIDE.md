# Megalint Rules Guide

See `README.md` for quick start and usage. This doc covers internals, rule inventory, and how to extend.

## Table of Contents

- [Where Checks Live](#where-checks-live)
- [Check Inventory](#check-inventory)
- [Adding New Rules](#adding-new-rules)
- [Decision Flowchart](#decision-flowchart-where-to-add)
- [Adding to Multiple Tools?](#adding-to-multiple-tools)
- [Known Issues & Improvement Suggestions](#known-issues--improvement-suggestions)
- [Config Reference](#config-reference)

---

## Where Checks Live

| Tool | Language | Check Source | Rebuild? | Disable Individual Checks? |
|------|----------|-------------|:--------:|:--------------------------:|
| **AgentLinter** | TypeScript | `apps/agentlinter/packages/cli/src/engine/rules/*.ts` | Yes (`bun run build`) | No (some context-gated via `applicableContexts`) |
| **PromptLint** | Python | `apps/promptlint/promptlint/analyzers/*.py` | No | No |
| **Home-Grow** | Bash | `apps/homegrow/run.sh` (31 checks as functions) + `apps/homegrow/rules.conf` | No | Yes (`CHECK_*=0` in `rules.conf`) |
| **Prompt Hardener** | Python | `apps/prompt-hardener/src/prompt_hardener/evaluate.py` | No | Yes (`apply_techniques` list) |

---

## Check Inventory

### AgentLinter — 86 rules, 9 categories

Each category = one `.ts` file exporting a `Rule[]` array. All merged in `index.ts` → `allRules`. Types and category weights defined in `types.ts`.

| Category | File | Count | Severities (rule-level) |
|----------|------|:-----:|-------------------------|
| Structure | `structure.ts` | 8 | 1 critical, 3 warning, 4 info |
| Clarity | `clarity.ts` | 17 | 2 error, 7 warning, 8 info |
| Completeness | `completeness.ts` | 15 | 4 warning, 11 info |
| Security | `security.ts` | 5 | 1 critical, 3 warning, 1 info |
| Consistency | `consistency.ts` | 14 | 4 error, 8 warning, 2 info |
| Memory | `memory.ts` | 9 | 4 warning, 5 info |
| Runtime | `runtime.ts` | 7 | 2 error, 4 warning, 1 info |
| Skill Safety | `skillSafety.ts` | 8 | 4 error, 4 warning |
| Remote-Ready | `remoteReady.ts` | 3 | 2 warning, 1 info |
| **Total** | | **86** | **2 critical, 12 error, 39 warning, 33 info** |

Category scoring weights (from `types.ts`): clarity 20%, security 14%, completeness 13%, memory 13%, consistency 11%, structure 10%, skill safety 8%, runtime 6%, remote-ready 5%.

<details>
<summary>Full rule ID list (86 rules)</summary>

**Structure (8):** `structure/has-main-file` `structure/has-sections` `structure/heading-hierarchy` `structure/file-size` `structure/modular-files` `structure/no-empty-sections` `structure/has-file-map` `structure/has-version-or-update-date`

**Clarity (17):** `clarity/no-vague-instructions` `clarity/actionable-instructions` `clarity/has-examples` `clarity/no-contradictions` `clarity/instruction-density` `clarity/naked-conditional` `clarity/compound-instruction` `clarity/escape-hatch-missing` `clarity/ambiguous-pronoun` `clarity/sentence-complexity` `clarity/priority-signal-missing` `clarity/undefined-term` `clarity/english-config-files` `clarity/has-resourcefulness-directive` `clarity/no-meta-commentary` `clarity/no-sycophantic-phrases` `clarity/no-persona-self-reference`

**Completeness (15):** `completeness/has-identity` `completeness/has-tools` `completeness/has-boundaries` `completeness/has-user-context` `completeness/has-error-awareness` `completeness/has-output-format` `completeness/has-workflow` `completeness/verification-criteria-required` `completeness/has-autonomy-tiers` `completeness/has-correction-protocol` `completeness/has-completion-definition` `completeness/has-verbosity-guidance` `completeness/has-personality-output-separation` `completeness/has-question-vs-task-routing` `completeness/has-error-recovery`

**Security (5):** `security/no-secrets` `security/has-injection-defense` `security/has-permission-boundaries` `security/no-pii-exposure` `security/env-var-references`

**Consistency (14):** `consistency/referenced-files-exist` `consistency/naming-convention` `consistency/no-duplicate-instructions` `consistency/identity-alignment` `consistency/permission-conflict` `consistency/tone-voice-alignment` `consistency/language-mixing` `consistency/circular-dependency` `consistency/timezone-locale-drift` `consistency/priority-conflict` `consistency/outdated-cross-references` `consistency/action-tiers-present` `consistency/shared-conventions-referenced` `consistency/soul-tone-calibrated`

**Memory (9):** `memory/has-memory-strategy` `memory/has-handoff-protocol` `memory/has-file-based-notes` `memory/no-mental-notes` `memory/has-context-window-awareness` `memory/has-state-tracking` `memory/has-learning-loop` `memory/no-database-phrasing` `memory/has-surfacing-rules`

**Runtime (7):** `runtime/config-exists` `runtime/gateway-bind` `runtime/auth-mode` `runtime/token-strength` `runtime/dm-policy` `runtime/group-policy` `runtime/config-secrets`

**Skill Safety (8):** `skill-safety/skill-name-match-dir` `skill-safety/skill-description-when-to-use` `skill-safety/has-metadata` `skill-safety/dangerous-commands` `skill-safety/sensitive-paths` `skill-safety/data-exfiltration` `skill-safety/excessive-permissions` `skill-safety/injection-vectors`

**Remote-Ready (3):** `remote-ready/workspace-path-specified` `remote-ready/env-vars-documented` `remote-ready/model-settings-specified`

**Removed rules:** `clarity/action-without-context` (dead code — never fired on MDS agents), `completeness/has-priorities` (duplicate of `clarity/priority-signal-missing`)

</details>

### PromptLint — 3 analyzers

Each analyzer = Python class in `apps/promptlint/promptlint/analyzers/`. Returns a 0-10 score per file.

| Analyzer | File | What It Checks |
|----------|------|----------------|
| Clarity | `clarity.py` | Structure presence, examples, output format, step-by-step refs, ambiguous phrases (14 patterns), vague quantities (6 patterns), conflict pairs (16 pairs), variable usage. Relaxed checks for narrative files (USER.md, MEMORY.md, BOOT.md) and identity files (IDENTITY.md, SOUL.md) |
| Security | `security.py` | Injection patterns: 6 high-risk (-3.0 each), 3 medium-risk (-0.5 each). Skips lines with restriction language (defensive instructions). Removed: placeholder/template variable FPs, dead low-risk patterns |
| Cost | `cost.py` | Token count vs TOKEN_BUDGET_GUIDE.md thresholds: reasonable (1725), moderate/WARN (2588), high/system-base (4865), very-high/system-WARN (7298). Variable count, instruction count |

### Home-Grow — 31 checks (individually toggleable)

All checks live in `apps/homegrow/run.sh` as functions. Config in `apps/homegrow/rules.conf` — set any `CHECK_*=0` to disable. `megalint.sh` calls `run.sh` as a subprocess; no inlined copy.

| # | Check | What It Validates | Fail = |
|:-:|-------|-------------------|--------|
| 1 | shared_files | 5 files exist in `shared/` + user dirs have `USER_CORE.md` | error |
| 2 | required_files | 8 files per agent folder (AGENTS, SOUL, IDENTITY, USER, TOOLS, HEARTBEAT, MEMORY, BOOT) | error |
| 3 | boot_refs | BOOT.md refs `USER_CORE.md` and `AGENT_ROSTER.md` | warn |
| 4 | boot_structure | BOOT.md has Standard/Boot/Recovery section with checklist items | warn |
| 5 | roster_count | AGENT_ROSTER.md rows match agent dir count (subset mode = info) | error/info |
| 6 | bootstrap_cleanup | No stale BOOTSTRAP.md in agents with memory/ dir | warn |
| 7 | anti_sycophancy | SOUL.md opens with anti-sycophancy line (first 10 lines) | warn |
| 8 | ~~action_tiers~~ | ~~AGENTS.md has Action Tiers~~ — **superseded by check 17** | — |
| 9 | tone_table | SOUL.md has tone calibration (Flat/Alive or tone section heading) | warn |
| 10 | continuity_line | SOUL.md has continuity line ("wake up fresh" / "files are my memory") | warn |
| 11 | security_section | AGENTS.md has `## Security` heading or `SECURITY_RULES.md` ref | warn |
| 12 | memory_workflow | AGENTS.md or MEMORY.md refs `memory/workflow` directive or has memory section | warn |
| 13 | heartbeat | HEARTBEAT.md contract has task lines if active | warn |
| 14 | token_budgets | Per-file tiktoken count vs budget targets (2-tier: INFO/WARN) | warn (disabled by default — handled by Token Budget pillar) |
| 15 | timezone | USER.md has timezone info (word-bounded `ET`/`CT`/`PT`/`UTC`, `eastern`, `America/`, `Asia/`, `Europe/`) | warn |
| 16 | canonical_wording | Sensitive terms use canonical phrasing (ADHD, Discord, OpenClaw, etc.) | warn |
| 17 | action_tiers_strict | AGENTS.md has structured action tier headings/table rows, counts 4 tiers (Always/When Asked/Ask First/Never) | error (0-1 tiers) / warn (2 tiers) |
| 18 | conventions_resourcefulness | `shared/CONVENTIONS.md` has "figure it out" / resourcefulness directive | warn |
| 19 | boot_conventions_ref | BOOT.md references `CONVENTIONS.md` | warn |
| 20 | memory_surfacing | `shared/MEMORY_WORKFLOW.md` has natural surfacing guidance | warn |
| 21 | soul_tone_calibrated | SOUL.md has calibrated tone signal (direct/warm/honest/authentic/skip filler) | warn |
| 22 | imports_section | AGENTS.md has `## Directives` section; scans all 6 config files (AGENTS.md, SOUL.md, TOOLS.md, HEARTBEAT.md, MEMORY.md, BOOT.md) for @import lines | error |
| 23 | imports_valid_paths | All import paths resolve to existing directive files under shared/directives/ | error |
| 24 | directives_exist | All 28 directive files from manifest.conf exist in shared/directives/ | error |
| 25 | imports_completeness | Agent imports match manifest.conf requirements for its type | warn |
| 26 | imports_no_duplication | No inline content duplicating imported directive text outside @import lines | warn |
| 27 | imports_boot_integration | BOOT.md references imports/directives when agent uses directive imports | warn |
| 28 | imports_tools_dedup | TOOLS.md doesn't duplicate shared tool content from imported directives | warn |
| 29 | imports_user_dedup | USER.md doesn't duplicate USER_CORE content | warn |
| 30 | legacy_shared_files | Old monolithic shared files (SECURITY_RULES, MEMORY_WORKFLOW, etc.) cleaned up | warn |
| 31 | orphan_directives | No directive files unused by any agent | info |

### Prompt Hardener — 6 default techniques, 13 sub-criteria

Defined in `evaluate.py`. LLM scores each 0-10 with ❌/⚠️/✅ marks. Default techniques are tuned for OpenClaw (private single-user system, not a consumer chatbot).

**Default techniques:**

| Technique | Sub-criteria | What It Evaluates |
|-----------|:------------:|-------------------|
| Instruction Defense | 4 | Inappropriate inputs (injection, not content moderation), persona switching, new instructions, prompt attacks |
| Role Consistency | 1 | System messages don't include user input (USER.md facts = system config, not user queries) |
| Proactive Behavior | 2 | Resourcefulness directive (act first, ask never), anti-sycophancy (filler banning) |
| Self-Check Quality | 2 | Error recovery protocol (retry/diagnose/try differently), verification criteria (definition of done) |
| Task Completion | 2 | Persistence directive (keep going until resolved), no premature closure |
| Scope Management | 2 | Action tiers define scope (Always/When Asked/Ask First/Never), autonomy calibration |

**Available but not default** (removed from defaults for OpenClaw — either not applicable or duplicate):

| Technique | Sub-criteria | Why Not Default |
|-----------|:------------:|-----------------|
| Spotlighting | 2 | OpenClaw agents receive user messages via gateway, no inline user input in system prompts |
| Random Sequence Enclosure | 2 | OpenClaw config files don't use RSE markers, always scored 0 |
| Secrets Exclusion | 1 | Duplicates AgentLinter `security/no-secrets` which is deterministic and more precise |

### Summary

| Tool | Checks | Can Disable? |
|------|:------:|:------------:|
| AgentLinter | 86 | No (some context-gated via `applicableContexts`) |
| PromptLint | ~25 sub-checks across 3 analyzers | No |
| Home-Grow | 31 (1 superseded, 1 disabled by default) | Yes (`rules.conf`) |
| Prompt Hardener | 13 default sub-criteria across 6 techniques (+5 optional) | Yes (`apply_techniques`) |
| **Total** | **~155** | **Home-Grow + Hardener** |

---

## Adding New Rules

### To AgentLinter (most common)

**Adding a rule to an existing category:**

1. Open the category file (e.g., `clarity.ts`)
2. Add a rule object to the exported array:

```typescript
{
  id: "clarity/my-new-check",
  category: "clarity",
  severity: "warning",  // critical | error | warning | info
  description: "One-line summary of what this checks",
  // Optional: only fire in OpenClaw workspace mode
  // applicableContexts: ["openclaw-runtime"],
  check(files) {
    const diagnostics: Diagnostic[] = [];
    for (const file of files) {
      if (!file.name.endsWith(".md")) continue;
      for (let i = 0; i < file.lines.length; i++) {
        if (/your-pattern/i.test(file.lines[i])) {
          diagnostics.push({
            severity: "warning",
            category: "clarity",
            rule: this.id,
            file: file.name,
            line: i + 1,
            message: `What's wrong: "${file.lines[i].trim().substring(0, 60)}"`,
            fix: "How to fix it",
          });
        }
      }
    }
    return diagnostics;
  },
},
```

3. Rebuild: `cd apps/agentlinter/packages/cli && bun run build`
4. Test: `./megalint.sh agent-name`

**Adding a new category (rare):**

1. Create `rules/myCategory.ts` — export a `Rule[]` array
2. Edit `types.ts`:
   - Add to `Category` type union
   - Add to `CATEGORY_WEIGHTS` (weights must sum to 1.0)
   - Add to `CATEGORY_LABELS`
   - Add to `SEVERITY_DEDUCTIONS`
3. Edit `rules/index.ts` — import and spread into `allRules`
4. Rebuild

**Key types** (from `types.ts`):

| Type | Fields |
|------|--------|
| `Rule` | `id`, `category`, `severity`, `description`, `applicableContexts?`, `check(files) → Diagnostic[]` |
| `Diagnostic` | `severity`, `category`, `rule`, `file`, `line?`, `message`, `fix?` |
| `FileInfo` | `name`, `path`, `content`, `lines`, `sections`, `context` |
| `Severity` | `"critical" \| "error" \| "warning" \| "info"` |

Note: a rule's `severity` field is its declared default, but `check()` can emit diagnostics with different severities (e.g., `skill-safety/dangerous-commands` is `severity: "error"` but demotes to `"info"` inside code blocks).

### To PromptLint

1. Open the analyzer file (`clarity.py`, `security.py`, or `cost.py`)
2. Add patterns to existing constant lists, or add a new `_check_*` method
3. Wire into the `analyze()` method:
   - Call your new check
   - Adjust `score` using a weight from the `WEIGHTS` dict
   - Append to `issues` or `suggestions` list
4. Test: `./megalint.sh agent-name`

**To add a new analyzer** (new scoring dimension):

1. Create `analyzers/myanalyzer.py` with a class exposing `analyze(parsed) → (score, issues, suggestions)`
2. Wire it into the main scoring pipeline (check `apps/promptlint/promptlint/core/` for the orchestrator)
3. Update `megalint.sh` scoring section to include the new dimension

### To Home-Grow

1. Add a function `check_mycheck()` to `apps/homegrow/run.sh` using `emit` for output:

```bash
check_mycheck() {
  for agent in "${AGENTS[@]}"; do
    local f="$AGENTS_DIR/$agent/AGENTS.md"
    [[ ! -f "$f" ]] && continue
    if rg -q 'my_pattern' "$f" 2>/dev/null; then
      emit OK "$agent" "my check passed"
    else
      emit WARN "$agent" "my check failed"
    fi
  done
}
```

2. Add `CHECK_MYCHECK=1` to `apps/homegrow/rules.conf`
3. Add the runner line at the bottom of `run.sh`: `[[ "$CHECK_MYCHECK" == "1" ]] && check_mycheck`
4. Test: `./megalint.sh agent-name`

### To Prompt Hardener

1. Edit `evaluate.py`
2. Add your technique key to the default `apply_techniques` list:
```python
apply_techniques = [
    "instruction_defense",
    "role_consistency",
    "proactive_behavior",
    "self_check",
    "task_completion",
    "scope_management",
    "my_new_technique",  # add here
]
```
3. Add a `json_format_sections` entry with sub-criteria:
```python
if "my_new_technique" in apply_techniques:
    json_format_sections["My New Technique"] = {
        "Sub-criterion description": {
            "satisfaction": "0-10",
            "mark": "❌/⚠️/✅",
            "comment": "...",
        },
    }
```
4. Add criteria section text and rubric examples in the same pattern as existing techniques
5. Test: `./megalint.sh --yes agent-name`

---

## Decision Flowchart: Where to Add

```
Can regex catch it?
├─ NO (needs semantic/LLM judgment) → Prompt Hardener
└─ YES
   ├─ OpenClaw-specific convention? (file existence, field values, cross-agent consistency)
   │  └─ YES → Home-Grow
   ├─ Needs cross-file or workspace-level context?
   │  └─ YES → AgentLinter
   ├─ Per-file quality/cost/injection pattern?
   │  └─ YES → PromptLint
   └─ Unclear → AgentLinter (most capable default)
```

| Check type | Best tool | Example |
|------------|-----------|---------|
| File X must exist | Home-Grow | Required agent files |
| Field Y must contain Z | Home-Grow | Timezone in USER.md |
| Cross-agent count mismatch | Home-Grow | Roster count |
| Vague wording pattern | AgentLinter | "be helpful" detection |
| Contradiction between files | AgentLinter | Permission conflicts |
| Secret/PII leaked | AgentLinter | API key regex |
| Prompt vulnerable to jailbreak | Prompt Hardener | Persona switching |
| File costs too many tokens | PromptLint | Token threshold |
| Dangerous command in skill | AgentLinter | `rm -rf /` in SKILL.md |

---

## Adding to Multiple Tools?

**Don't.** Pick the tool with the most context for your check type. Duplicating creates noise and maintenance burden.

Existing overlaps (secret detection, vague wording, contradiction checks) exist because the tools evolved independently with different pattern sets. They're not intentional duplication — they just catch slightly different things. For new checks, pick one tool.

---

## Known Issues & Improvement Suggestions

### Bugs / Drift

| Issue | Impact | Fix |
|-------|--------|-----|
| ~~Home-Grow duplication~~ | — | ✅ Fixed: all checks in `apps/homegrow/run.sh`, inline copy deleted |
| ~~checks.sh hardcoded agent list~~ | — | ✅ Fixed: run.sh uses dynamic discovery, template excluded |
| ~~Roster count logic differs~~ | — | ✅ Fixed: both exclude template from agent/roster count |
| ~~PromptLint outputs all 0s~~ | — | ✅ Fixed: removed FP-causing patterns (template variables, unguarded variables), relaxed checks for narrative/identity files |
| ~~Prompt Hardener false positives~~ | — | ✅ Fixed: removed spotlighting/RSE/secrets (not applicable to OpenClaw), added OpenClaw-specific techniques (proactive behavior, self-check, task completion, scope management) with detailed rubrics |

### Functionality Improvements

| Suggestion | Effort | Impact |
|------------|--------|--------|
| **Per-rule disable config** — add `DISABLED_RULES=` list to `megalint.conf` for AgentLinter/Home-Grow | Medium | Reduces noise from known-acceptable violations (e.g., `clarity/escape-hatch-missing` on security rules) |
| **AgentLinter rule severity vs diagnostic severity** — rules like `skill-safety/has-metadata` declare `severity: "warning"` but emit `severity: "info"` diagnostics | Low | Audit rules so declared severity matches emitted diagnostics, or document the convention |
| ~~Extract embedded Python from megalint.sh~~ | — | ✅ Done: `lib/scoring.py` + `lib/report.py` extracted |
| **PromptLint error surfacing** — don't swallow stderr, log failures so broken analyzers are visible | Low | Prevents silent 0-score bugs |
| ~~Home-Grow per-check disable~~ | — | ✅ Done: `CHECK_*=0` in `apps/homegrow/rules.conf` disables individual checks |
| **Prompt Hardener determinism** — run each technique N times and average scores | Medium | Reduces score variance between runs |

---

## Config Reference

### `megalint.conf` — Scoring

| Setting | Default | Effect |
|---------|:-------:|--------|
| `WEIGHT_STRUCTURE` | 25 | AgentLinter share of combined score |
| `WEIGHT_QUALITY` | 18 | PromptLint share |
| `WEIGHT_CONSISTENCY` | 22 | Home-Grow share |
| `WEIGHT_SECURITY` | 20 | Prompt Hardener share |
| `WEIGHT_BUDGET` | 15 | Token Budget pillar share |
| `PASS_THRESHOLD` | 70 | Minimum combined score to pass |
| `BLOCKING_ERRORS` | true | Any Home-Grow ERROR = fail regardless of score |

Grade scale: S (≥97), A+ (≥95), A (≥93), A- (≥90), B+ (≥87), B (≥83), B- (≥80), C+ (≥77), C (≥73), C- (≥70), D (≥60), F (<60).

### `apps/homegrow/rules.conf` — Check toggles + token budgets

| Setting | Default | Effect |
|---------|:-------:|--------|
| `CHECK_*` | 1 | Enable (1) or disable (0) individual Home-Grow checks |
| `CHECK_TOKEN_BUDGETS` | 0 | Disabled — handled by Token Budget pillar to avoid double-counting |
| `BUDGET_AGENTS_MD` | 1725 | Token budget for AGENTS.md (tiktoken cl100k_base) |
| `BUDGET_SOUL_MD` | 525 | Token budget for SOUL.md |
| `BUDGET_IDENTITY_MD` | 175 | Token budget for IDENTITY.md |
| `BUDGET_USER_MD` | 715 | Token budget for USER.md |
| `BUDGET_TOOLS_MD` | 525 | Token budget for TOOLS.md |
| `BUDGET_HEARTBEAT_MD` | 225 | Token budget for HEARTBEAT.md |
| `BUDGET_MEMORY_MD` | 975 | Token budget for MEMORY.md |
| `TIER_INFO` | 1.25 | Budget multiplier for INFO severity (25% over base) |
| `TIER_WARN` | 1.50 | Budget multiplier for WARN severity (50% over base) |

Override priority: env vars (`MEGALINT_BUDGET_*`, `MEGALINT_TIER_*`) > `rules.conf` > defaults in `run.sh`.
