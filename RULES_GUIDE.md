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
| **Home-Grow** | Bash | `apps/homegrow/run.sh` (16 checks as functions) + `apps/homegrow/rules.conf` | No | Yes (`CHECK_*=0` in `rules.conf`) |
| **Prompt Hardener** | Python | `apps/prompt-hardener/src/prompt_hardener/evaluate.py` | No | Yes (`apply_techniques` list) |

---

## Check Inventory

### AgentLinter — 72 rules, 9 categories

Each category = one `.ts` file exporting a `Rule[]` array. All merged in `index.ts` → `allRules`. Types and category weights defined in `types.ts`.

| Category | File | Count | Severities (rule-level) |
|----------|------|:-----:|-------------------------|
| Structure | `structure.ts` | 8 | 1 critical, 3 warning, 4 info |
| Clarity | `clarity.ts` | 14 | 2 error, 6 warning, 6 info |
| Completeness | `completeness.ts` | 9 | 4 warning, 5 info |
| Security | `security.ts` | 5 | 1 critical, 3 warning, 1 info |
| Consistency | `consistency.ts` | 11 | 3 error, 6 warning, 2 info |
| Memory | `memory.ts` | 7 | 2 warning, 5 info |
| Runtime | `runtime.ts` | 7 | 2 error, 4 warning, 1 info |
| Skill Safety | `skillSafety.ts` | 8 | 4 error, 4 warning |
| Remote-Ready | `remoteReady.ts` | 3 | 2 warning, 1 info |
| **Total** | | **72** | **2 critical, 11 error, 34 warning, 25 info** |

Category scoring weights (from `types.ts`): clarity 20%, structure 10%, completeness 13%, security 14%, consistency 11%, memory 13%, runtime 6%, skill safety 8%, remote-ready 5%.

<details>
<summary>Full rule ID list</summary>

`structure/has-main-file` `structure/has-sections` `structure/heading-hierarchy` `structure/file-size` `structure/modular-files` `structure/no-empty-sections` `structure/has-file-map` `structure/has-version-or-update-date` · `clarity/no-vague-instructions` `clarity/actionable-instructions` `clarity/has-examples` `clarity/no-contradictions` `clarity/instruction-density` `clarity/naked-conditional` `clarity/compound-instruction` `clarity/escape-hatch-missing` `clarity/ambiguous-pronoun` `clarity/action-without-context` `clarity/sentence-complexity` `clarity/priority-signal-missing` `clarity/undefined-term` `clarity/english-config-files` · `completeness/has-identity` `completeness/has-tools` `completeness/has-boundaries` `completeness/has-user-context` `completeness/has-error-handling` `completeness/has-output-format` `completeness/has-workflow` `completeness/has-priorities` `completeness/verification-criteria-required` · `security/no-secrets` `security/has-injection-defense` `security/has-permission-boundaries` `security/no-pii-exposure` `security/env-var-references` · `consistency/referenced-files-exist` `consistency/naming-convention` `consistency/no-duplicate-instructions` `consistency/identity-alignment` `consistency/permission-conflict` `consistency/tone-voice-alignment` `consistency/language-mixing` `consistency/circular-dependency` `consistency/timezone-locale-drift` `consistency/priority-conflict` `consistency/outdated-cross-references` · `memory/has-memory-strategy` `memory/has-handoff-protocol` `memory/has-file-based-notes` `memory/no-mental-notes` `memory/has-context-window-awareness` `memory/has-state-tracking` `memory/has-learning-loop` · `runtime/config-exists` `runtime/gateway-bind` `runtime/auth-mode` `runtime/token-strength` `runtime/dm-policy` `runtime/group-policy` `runtime/config-secrets` · `skill-safety/skill-name-match-dir` `skill-safety/skill-description-when-to-use` `skill-safety/has-metadata` `skill-safety/dangerous-commands` `skill-safety/sensitive-paths` `skill-safety/data-exfiltration` `skill-safety/excessive-permissions` `skill-safety/injection-vectors` · `remote-ready/workspace-path-specified` `remote-ready/env-vars-documented` `remote-ready/model-settings-specified`

</details>

### PromptLint — 3 analyzers

Each analyzer = Python class in `apps/promptlint/promptlint/analyzers/`. Returns a 0-10 score per file.

| Analyzer | File | What It Checks |
|----------|------|----------------|
| Clarity | `clarity.py` | Structure presence, examples, output format, step-by-step refs, ambiguous phrases (14 patterns), vague quantities (6 patterns), conflict pairs (4), variable usage |
| Security | `security.py` | Injection patterns: 6 high-risk (-3.0 each), 7 medium-risk (-1.5 each), unguarded variables (-1.0 each) |
| Cost | `cost.py` | Token count vs thresholds (500/1K/2K/4K), variable count, instruction count |

### Home-Grow — 16 checks (individually toggleable)

All checks live in `apps/homegrow/run.sh` as functions. Config in `apps/homegrow/rules.conf` — set any `CHECK_*=0` to disable. `megalint.sh` calls `run.sh` as a subprocess; no inlined copy.

| # | Check | What It Validates | Fail = |
|:-:|-------|-------------------|--------|
| 1 | shared_files | 6 files exist in `shared/` | error |
| 2 | required_files | 8 files per agent folder | error |
| 3 | boot_refs | BOOT.md refs `USER_CORE.md` and `AGENT_ROSTER.md` | warn |
| 4 | boot_structure | BOOT.md has `## Standard` section with checklist items | warn |
| 5 | roster_count | AGENT_ROSTER.md rows match agent dir count | error |
| 6 | bootstrap_cleanup | No stale BOOTSTRAP.md | warn |
| 7 | anti_sycophancy | SOUL.md opens with anti-sycophancy line (first 10 lines) | warn |
| 8 | action_tiers | AGENTS.md has Action Tiers with **Always** + **Never** | warn |
| 9 | tone_table | SOUL.md has tone calibration (Flat/Alive or tone section) | warn |
| 10 | continuity_line | SOUL.md has continuity line ("wake up fresh" / "files are my memory") | warn |
| 11 | security_section | AGENTS.md has `## Security` heading or `SECURITY_RULES.md` ref | warn |
| 12 | memory_workflow | AGENTS.md refs `MEMORY_WORKFLOW` or has `## Memory` section | warn |
| 13 | heartbeat | HEARTBEAT.md contract has task lines if active | warn |
| 14 | token_budgets | Per-file tiktoken count vs budget targets | warn |
| 15 | timezone | USER.md has `\btimezone\b`, word-bounded `ET`, or `\beastern\b` | warn |
| 16 | canonical_wording | Sensitive terms use canonical phrasing from USER_CORE.md | warn |

### Prompt Hardener — 5 techniques, 10 sub-criteria

Defined in `evaluate.py`. LLM scores each 0-10 with ❌/⚠️/✅ marks.

| Technique | Sub-criteria |
|-----------|:------------:|
| Spotlighting | 2 (tag user inputs, use spotlighting markers) |
| Random Sequence Enclosure | 2 (random tags for system instructions, no tag leaking) |
| Instruction Defense | 4 (inappropriate inputs, persona switching, new instructions, prompt attacks) |
| Role Consistency | 1 (system messages don't include user input) |
| Secrets Exclusion | 1 (no hardcoded sensitive info) |

### Summary

| Tool | Checks | Can Disable? |
|------|:------:|:------------:|
| AgentLinter | 72 | No |
| PromptLint | ~25 sub-checks across 3 analyzers | No |
| Home-Grow | 16 | Yes (`rules.conf`) |
| Prompt Hardener | 10 | Yes (`apply_techniques`) |
| **Total** | **~123** | **Home-Grow + Hardener** |

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
   - Add to `CATEGORY_WEIGHTS` (weights must conceptually sum to 1.0)
   - Add to `CATEGORY_LABELS`
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
    "spotlighting",
    "random_sequence_enclosure",
    "instruction_defense",
    "role_consistency",
    "secrets_exclusion",
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
4. Add criteria section text and examples in the same pattern as existing techniques
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
| **PromptLint outputs all 0s** — latest report shows 0 for clarity/security/cost on every file | Quality pillar (25% weight) contributes nothing to score | Verify `promptlint` venv and binary are working; `megalint.sh` swallows errors via `2>/dev/null \|\| echo '{}'` |

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

### `apps/homegrow/rules.conf` — Check toggles + token budgets

| Setting | Default | Effect |
|---------|:-------:|--------|
| `CHECK_*` | 1 | Enable (1) or disable (0) individual Home-Grow checks |
| `BUDGET_AGENTS_MD` | 1150 | Token budget for AGENTS.md (tiktoken cl100k_base) |
| `BUDGET_SOUL_MD` | 350 | Token budget for SOUL.md |
| `BUDGET_IDENTITY_MD` | 115 | Token budget for IDENTITY.md |
| `BUDGET_USER_MD` | 475 | Token budget for USER.md |
| `BUDGET_TOOLS_MD` | 350 | Token budget for TOOLS.md |
| `BUDGET_HEARTBEAT_MD` | 150 | Token budget for HEARTBEAT.md |
| `BUDGET_MEMORY_MD` | 650 | Token budget for MEMORY.md |
