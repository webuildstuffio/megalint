# Megalint — Remaining Work, Pruning & AGI Alignment Review

> **Last updated**: 2026-02-24. Source verified: all rule files, cost.py, evaluate.py, run.sh.
> All P0 and P1 items complete. All P2 items complete.

---

## What's Done — Full Audit Trail

### P0 (All Fixed)

- ✅ **PromptLint `eval` regex** — changed to `\beval\s*[\(\{"\']`, no longer fires on "evaluate"
- ✅ **Cost analyzer thresholds** — updated to TOKEN_BUDGET_GUIDE.md values (reasonable=1725, moderate=2588, high=4865, very_high=7298). Issues include `why` context and TOKEN_BUDGET_GUIDE.md references. Score drops only above 4,865 tokens (full system baseline).
- ✅ **`has-autonomy-tiers` demoted** — warning → info (was cascading noise on top of Home-Grow's error-level check)
- ✅ **Hardener RSE removed** — Random Sequence Enclosure was always scoring 0 for OpenClaw; removed from default technique list in `evaluate.py`
- ✅ **Canonical wording pruned** — removed personal `autism|mild autism traits` and `bipolar|Bipolar II` from `run.sh`; check now covers brands and proper nouns only

### P1 (All Fixed)

- ✅ **`has-workflow` conversational exclusion** — CONVERSATIONAL_SIGNALS pattern already present; skips Kodo, Basil, Huberman
- ✅ **`has-verbosity-guidance` expanded** — 10 patterns including "be brief", "keep it short", "no padding", "no fluff", "one sentence if"
- ✅ **`has-question-vs-task-routing` scoped** — added `applicableContexts: ["openclaw-runtime"]`
- ✅ **`permission-conflict` 3-word overlap** — already using `shared.length >= 3` in source
- ✅ **`priority-conflict` 3-word overlap** — already using `shared.length >= 3` in source
- ✅ **`has-file-map` gated** — already `applicableContexts: ["claude-code"]` in source
- ✅ **`has-version-or-update-date` gated** — already `applicableContexts: ["claude-code"]` in source
- ✅ **`workspace-path-specified` demoted** — already at `info` severity in source

### P2 (All Fixed)

- ✅ **`escape-hatch-missing` section suppression** — already has `inActionTierSection` tracking; skips all lines in `## Always` and `## Never` sections
- ✅ **`has-user-context` BOOT.md check** — already checks for BOOT.md referencing USER_CORE.md as alternative satisfaction condition
- ✅ **`has-context-window-awareness` message** — already OpenClaw-specific: "checkpoint to memory/YYYY-MM-DD.md before context fills up"
- ✅ **`modular-files` threshold** — raised from 100 → 200 lines
- ✅ **`specific_terms` dead code** — already removed from PromptLint ClarityAnalyzer
- ✅ **`conflicting_instructions` expanded** — 17 real conflict pairs (was 2)

### Broader Completions (Verified in Source)

- ✅ All 16 AgentLinter clarity rules (including `no-sycophantic-phrases`, `no-persona-self-reference`, escape-hatch section suppression)
- ✅ All 15 AgentLinter completeness rules (all new rules from backlog + conversational exclusions)
- ✅ All 9 AgentLinter memory rules (`no-database-phrasing`, `has-surfacing-rules`, tightened learning-loop)
- ✅ All AgentLinter consistency rules (3-word overlap for permission/priority conflict, timezone drift, outdated-cross-refs)
- ✅ Home-Grow: `check_action_tiers_strict`, `check_conventions_resourcefulness`, `check_boot_conventions_ref`, `check_memory_surfacing`, `check_soul_tone_calibrated` — all with rich context
- ✅ Prompt Hardener: removed `secrets_exclusion`, `spotlighting`, RSE — default now: instruction_defense, role_consistency, proactive_behavior, self_check, task_completion, scope_management

---

## AGI Goal Alignment — Final State

OpenClaw's core goals: **unbounded helpfulness, personality with teeth, no token anxiety, self-improving, human-like iteration**.

| Rule | Rating | Why It Matters |
|------|:------:|---------------|
| `clarity/has-resourcefulness-directive` | ★★★★★ | Core behavioral gap. Act first, ask never. |
| `completeness/has-error-recovery` | ★★★★★ | Self-healing is our #2 behavioral goal. |
| `memory/has-surfacing-rules` | ★★★★★ | Natural memory = friend not database. |
| `check_action_tiers_strict` | ★★★★★ | Our signature architecture. |
| `clarity/no-sycophantic-phrases` | ★★★★★ | Personality-first means no bot filler. |
| `clarity/no-meta-commentary` | ★★★★★ | Show don't tell. Direct action over narration. |
| `security/no-secrets` | ★★★★★ | Essential regardless of context. |
| `clarity/no-persona-self-reference` | ★★★★☆ | Embody, don't announce. |
| `completeness/has-correction-protocol` | ★★★★☆ | Hold ground under pressure. Anti-sycophancy under fire. |
| `memory/no-database-phrasing` | ★★★★☆ | Natural memory use. No "based on my records." |
| `completeness/has-personality-output-separation` | ★★★★☆ | Personality governs talk, not artifacts. |

### Previously Anti-Goal — All Resolved

| Was | Fixed |
|-----|-------|
| Cost analyzer penalized thorough agents with 10+ instructions | Thresholds now match TOKEN_BUDGET_GUIDE.md; penalty-free below 4,865 tokens |
| `has-autonomy-tiers` at warning duplicated Home-Grow error check | Demoted to info |
| Hardener RSE added fake "failure" signals | Removed from default techniques |
| `has-file-map` + `has-version-or-update-date` fired on MDS | Gated to `claude-code` context |
| Canonical wording checked personal medical details | Removed; checks brands/proper nouns only |
| `has-workflow` fired on life-guide and grocery agents | CONVERSATIONAL_SIGNALS exclusion added |

---

## What NOT to Do

- **Don't add more Hardener LLM-as-judge criteria** — non-deterministic, costs API calls, all 4 Hardener proposals from AGI_FOCUSED_AUDIT were correctly rejected
- **Don't add `memory/has-learning-loop` patterns** — already tightened to 2+ patterns, calibrated
- **Don't add per-rule disable mechanism** — P3 complexity, not worth it at current scale
- **Don't add Hardener N-run averaging** — adds API cost and latency for marginal gain
- **Don't remove tone-voice-alignment** — improved (contractions neutral, 3+ markers threshold). Leave unless new FPs surface.
- **Don't scale cost.py penalties to be harsher** — one user, private system. Cost analyzer is informational, not a gatekeeper.
- **Don't add PromptLint "why" field** — informational ROI is low vs. effort (30 min). Models.py change ripples through all reporters and tests. Skip.
