# Megalint Refactor Proposal

> **Status**: Implemented  
> **Date**: 2025-02-24  
> **Completed**: 2025-02-24  
> **Scope**: Structural refactor of megalint orchestration layer. No changes to tool internals (AgentLinter rules, PromptLint analyzers, Hardener techniques, Home-Grow checks).

---

## The Problem

`megalint.sh` is a 1155-line bash monolith that does everything: CLI parsing, tool orchestration, result processing for all 5 pillars, inline Python computation, terminal display, scoring, and report generation. This makes it:

- **Hard to maintain** — changing display format for one tool means editing a 1155-line bash file
- **Hard to debug** — data flows bash → inline-Python-heredoc → stdout → bash-variable → Python-script → stdout → bash-variable, across 15+ inline Python snippets
- **Hard to extend** — adding a new tool/pillar requires edits in 6+ places across the monolith
- **Fragile** — inline Python embedded in bash strings breaks on quoting edge cases and can't be linted or tested independently
- **Full of duplication** — model pricing in 2 places, token budgets in 3 places, token counting fallbacks in 2 places, grade thresholds piped as Python list literals

### Specific DRY Violations

| Duplicated Thing | Location 1 | Location 2 | Location 3 |
|-----------------|------------|------------|------------|
| Model pricing table | `megalint.sh` L797-800 | `lib/report.py` L16-25 | — |
| Token budget values | `homegrow/rules.conf` | `megalint.sh` L617-624 | `scoring.py` (via JSON) |
| Token count fallback | `megalint.sh` L609-613 | `homegrow/run.sh` L94-106 | — |
| Grade scale | `megalint.conf` | `megalint.sh` L59-61 (defaults) | Passed to scoring.py as Python literal |
| Config defaults | `megalint.sh` L57-61 | `megalint.conf` | — |
| ENV override logic | `megalint.sh` L588-591 | `homegrow/run.sh` L83-88 | — |

### Architectural Problems

1. **No tool adapter pattern** — each tool has bespoke execution + parsing baked inline. ~100 lines of custom bash+Python per tool.
2. **15+ inline Python snippets** — untestable, unlintable, break on special characters.
3. **Bash doing data transformation** — bash is good at process orchestration, terrible at JSON manipulation and arithmetic. We're fighting the language.
4. **Display and data interleaved** — scoring computation is tangled with terminal color output. Can't get scores without also printing.
5. **Config loaded 3 ways** — `megalint.conf` sourced in bash, `rules.conf` sourced in bash, then values serialized to JSON for Python. Each handoff is a failure point.

---

## Proposed Architecture

### Principle: Bash orchestrates processes. Python processes data.

```
megalint.sh (slim: ~200 lines)          Python layer (new)
┌──────────────────────────┐            ┌──────────────────────────┐
│ 1. Parse CLI flags       │            │ lib/config.py            │
│ 2. Load config (1 source)│───────────▶│   - loads megalint.conf  │
│ 3. Discover agents       │            │   - loads rules.conf     │
│ 4. Run tools in parallel │            │   - env var overrides    │
│ 5. Call process.py       │───────────▶│   - single source of     │
│ 6. Exit with code        │            │     truth for all values │
└──────────────────────────┘            ├──────────────────────────┤
                                        │ lib/process.py (new)     │
      Tool outputs (unchanged)          │   - reads all tool output│
      ┌─────────┐                       │   - adapters per tool    │
      │ AL JSON  │──────────────────────▶│   - computes all scores │
      │ PL JSON  │──────────────────────▶│   - computes all display│
      │ HG txt   │──────────────────────▶│   - writes JSON summary │
      │ PH JSON  │──────────────────────▶│     to tmp dir          │
      │ budgets  │──────────────────────▶│                          │
      └─────────┘                       ├──────────────────────────┤
                                        │ lib/display.py (new)     │
                                        │   - reads JSON summary   │
                                        │   - prints terminal out  │
                                        │   - ANSI colors          │
                                        ├──────────────────────────┤
                                        │ lib/scoring.py (existing)│
                                        │   - called by process.py │
                                        │   - pure function now    │
                                        ├──────────────────────────┤
                                        │ lib/report.py (existing) │
                                        │   - called by process.py │
                                        │   - reads JSON summary   │
                                        └──────────────────────────┘
```

### What Changes

| Component | Before | After |
|-----------|--------|-------|
| `megalint.sh` | 1155 lines, does everything | ~200 lines, orchestrates only |
| Inline Python | 15+ snippets in bash strings | 0 — all logic in `.py` files |
| `lib/process.py` | Doesn't exist | New: reads all tool output, computes everything, writes JSON |
| `lib/display.py` | Doesn't exist | New: reads JSON, prints colored terminal output |
| `lib/config.py` | Doesn't exist | New: single source of truth for all config |
| `lib/pricing.py` | Doesn't exist | New: model pricing (1 place, used by display + report) |
| `lib/scoring.py` | Reads JSON, prints KEY=VAL | Pure function called by process.py |
| `lib/report.py` | Standalone script | Called by process.py, no more own pricing table |
| `homegrow/run.sh` | Has own token counting fallback | Imports from lib/ (or stays self-contained, see below) |

### What Doesn't Change

- **AgentLinter** — TypeScript tool, rules, CLI. Untouched.
- **PromptLint** — Python tool, analyzers, CLI. Untouched.
- **Prompt Hardener** — Python tool, techniques, CLI. Untouched.
- **Home-Grow** — `run.sh` checks, `rules.conf` toggles. Untouched (except optionally deduplicating the token counting fallback).
- **Tool output formats** — JSON from AL/PL/PH, pipe-delimited text from HG. All unchanged.
- **CLI interface** — all existing flags work exactly the same.
- **bats tests** — same interface, tests still pass.

---

## Detailed Plan

### Phase 1: Extract Config (single source of truth)

**New file: `lib/config.py`**

Responsibilities:
- Load `megalint.conf` (weights, thresholds, grades)
- Load `homegrow/rules.conf` (budgets, tiers, check toggles)
- Apply env var overrides (`MEGALINT_BUDGET_*`, `MEGALINT_TIER_*`)
- Expose a single `Config` dataclass that everything else imports
- Include model pricing (currently duplicated in megalint.sh and report.py)

```python
@dataclass
class Config:
    # Weights
    weight_structure: int = 25
    weight_quality: int = 18
    weight_consistency: int = 22
    weight_security: int = 20
    weight_budget: int = 15

    # Thresholds
    pass_threshold: int = 70
    blocking_errors: bool = True

    # Grades (list of (threshold, label) tuples)
    grades: list[tuple[int, str]] = ...

    # Token budgets
    budgets: dict[str, int] = ...  # {"AGENTS.md": 1725, ...}

    # Tier multipliers
    tier_info: float = 1.25
    tier_warn: float = 1.50

    # Model pricing
    pricing: dict[str, dict[str, float]] = ...
```

This kills 3 DRY violations in one move (budget values, grade scale, pricing).

**Changes to `megalint.sh`**: Remove all inline config defaults (L57-61), remove budget ENV override logic (L588-591), remove grade piping. Just pass config path to Python.

### Phase 2: Extract Tool Adapters into `lib/process.py`

**New file: `lib/process.py`**

Replaces all 15 inline Python snippets in megalint.sh. One function per tool to parse its output:

```python
def process_agentlinter(al_dir: str, agents: list[str]) -> dict:
    """Parse AgentLinter JSON outputs → structured results."""

def process_promptlint(pl_dir: str, agents: list[str]) -> dict:
    """Parse PromptLint JSON outputs → structured results."""

def process_homegrow(hg_dir: str) -> dict:
    """Parse Home-Grow pipe-delimited text → structured results."""

def process_hardener(ph_dir: str) -> dict:
    """Parse Prompt Hardener eval JSONs → structured results."""

def process_budgets(agent_dirs: dict, config: Config) -> dict:
    """Compute per-file token budget scores."""

def process_all(tmp_dir: str, agents: list[str], agent_dirs: dict,
                config: Config, hardener_ran: bool) -> dict:
    """Master orchestrator: calls all above, runs scoring, writes summary JSON."""
```

**Key design**: `process_all` writes a single `summary.json` to the tmp dir. This JSON contains everything needed for both display and reporting. No more bash-variable-tennis.

**Changes to `megalint.sh`**: Replace ~600 lines of inline Python + bash processing with:

```bash
$PY "$SCRIPT_DIR/lib/process.py" \
  --tmp-dir "$TMPDIR_RUN" \
  --agents "${AGENTS[@]}" \
  --agent-dirs-json "$_ad_json" \
  --config "$CONF_FILE" \
  --hardener-ran "$HARDENER_RAN"
```

### Phase 3: Extract Display into `lib/display.py`

**New file: `lib/display.py`**

Reads `summary.json` from Phase 2, prints all terminal output with ANSI colors.

```python
def display_results(summary_path: str, format_flag: str = "") -> int:
    """Print full terminal report. Returns exit code (0=pass, 1=fail)."""
```

Sections:
- Tool 1: AgentLinter (per-agent scores, categories, diagnostics)
- Tool 2: PromptLint (per-agent per-file scores)
- Tool 3: Home-Grow (check results, summary)
- Token Budgets (per-agent per-file bars)
- Tool 4: Prompt Hardener (if ran)
- Combined Results (pillars, grade, per-agent breakdown)

**Changes to `megalint.sh`**: Replace ~400 lines of display code with:

```bash
$PY "$SCRIPT_DIR/lib/display.py" --summary "$TMPDIR_RUN/summary.json"
EXIT_CODE=$?
```

### Phase 4: Refactor Scoring + Reporting to Use Config

**Changes to `lib/scoring.py`**:
- Import `Config` from `lib/config.py`
- Accept config object instead of raw JSON with all values inlined
- Become a pure function callable from `process.py` (no more standalone `--input` CLI)
- Keep `if __name__ == "__main__"` for backward compat during migration

**Changes to `lib/report.py`**:
- Import pricing from `lib/config.py` (delete local `_MODEL_PRICING` dict)
- Accept `summary.json` as input instead of the current raw metrics JSON
- Simplify `build_report_data` — most data is pre-computed in summary.json

### Phase 5: Slim Down megalint.sh

After phases 1-4, `megalint.sh` becomes:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Deps ────────────────────────────────────────────────────
PY="$SCRIPT_DIR/apps/promptlint/.venv/bin/python"
NODE="$(command -v node)"
# ... (5 lines of dep checks)

# ─── CLI Parsing ─────────────────────────────────────────────
# ... (same flag parsing, ~30 lines)

# ─── Discover Agents ─────────────────────────────────────────
# ... (agent discovery, ~40 lines — unchanged)

# ─── Setup ───────────────────────────────────────────────────
TMPDIR_RUN=$(mktemp -d /tmp/megalint-XXXXXX)
trap 'rm -rf "$TMPDIR_RUN"' EXIT INT TERM

# Write agent metadata for Python
$PY -c "import json; json.dump({...}, open('$TMPDIR_RUN/meta.json','w'))"

# ─── Run Tools 1-3 in parallel ──────────────────────────────
# ... (same parallel execution, ~40 lines)
wait $AL_PID $PL_PID $HG_PID

# ─── Run Tool 4: Prompt Hardener ─────────────────────────────
# ... (same sequential execution, ~30 lines — cost estimation moves to Python)

# ─── Process + Display ──────────────────────────────────────
$PY "$SCRIPT_DIR/lib/process.py" \
  --tmp-dir "$TMPDIR_RUN" \
  --config "$CONF_FILE" \
  --format "${FORMAT_FLAG:-}"

exit $?
```

~200 lines. Bash does what bash is good at (processes, pipes, parallel). Python does what Python is good at (JSON, math, formatting).

---

## File Inventory (Before → After)

### Before (current)

```
lib/
  scoring.py       (200 lines — standalone, KEY=VAL output)
  report.py        (740 lines — standalone, has own pricing table)
  tiktoken_count.py (32 lines — good, no changes)
megalint.sh        (1155 lines — monolith)
megalint.conf      (31 lines — good, no changes)
```

### After (proposed)

```
lib/
  config.py         (~100 lines — NEW: single source of truth)
  process.py        (~300 lines — NEW: all tool parsing + scoring)
  display.py        (~250 lines — NEW: terminal output)
  scoring.py        (~150 lines — SIMPLIFIED: pure function, no CLI)
  report.py         (~550 lines — SIMPLIFIED: no own pricing, reads summary)
  tiktoken_count.py  (32 lines — unchanged)
megalint.sh         (~200 lines — SLIMMED: orchestration only)
megalint.conf       (31 lines — unchanged)
```

**Net line count**: ~1600 before → ~1580 after. Not about reducing lines — about putting them in the right place.

---

## Migration Strategy

### Approach: Incremental, never-broken

Each phase is a standalone PR that keeps megalint fully functional. No big-bang rewrite.

| Phase | PR | Risk | Test |
|-------|----|------|------|
| 1. Extract config | Small, additive | Low — new file, old code still works | Unit test config loading |
| 2. Extract process | Medium, replaces inline Python | Medium — most complex step | Run megalint before/after, diff outputs |
| 3. Extract display | Medium, replaces bash display | Low — pure output, easy to verify | Visual comparison of terminal output |
| 4. Refactor scoring/report | Small, internal rewiring | Low — same inputs/outputs | Existing bats tests + report diff |
| 5. Slim megalint.sh | Deletion-heavy | Low — everything already moved | Full regression (bats + manual) |

### Verification at each phase

```bash
# Before each PR: capture baseline output
./megalint.sh --format both 2>&1 | tee /tmp/megalint-before.txt

# After each PR: compare
./megalint.sh --format both 2>&1 | tee /tmp/megalint-after.txt
diff <(grep -v 'timestamp\|Run ID\|commit:' /tmp/megalint-before.txt) \
     <(grep -v 'timestamp\|Run ID\|commit:' /tmp/megalint-after.txt)
```

---

## Benefits

| Before | After |
|--------|-------|
| Adding a tool = edit megalint.sh in 6 places | Adding a tool = add one adapter function in process.py |
| Pricing change = edit 2 files | Pricing change = edit config.py |
| Budget change = edit 3 files | Budget change = edit rules.conf (single source) |
| Inline Python can't be tested | All Python is importable and testable |
| Inline Python can't be linted | All Python passes pylint/mypy |
| Debugging = printf in bash | Debugging = Python debugger, structured JSON |
| Display changes require understanding all 1155 lines | Display changes = edit display.py only |

---

## What This Proposal Does NOT Do

- **No tool changes** — AgentLinter rules, PromptLint analyzers, Hardener techniques, Home-Grow checks all stay exactly as-is
- **No new features** — this is pure refactor, same behavior
- **No new dependencies** — uses the same Python venv and Node already required
- **No CLI changes** — all flags and env vars work identically
- **No config format changes** — megalint.conf and rules.conf keep their bash-sourceable format (config.py just parses them)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Output drift (subtle display differences) | Capture before/after snapshots, diff everything except timestamps |
| Hardener cost estimation changes | Keep exact same arithmetic, just move it to Python |
| Breaking homegrow standalone mode | homegrow/run.sh stays fully self-contained, no forced dependency on lib/ |
| Over-engineering | Stop at Phase 5. No abstract base classes, no plugin system, no YAML configs. Just clean functions. |

---

## Decision Needed

This proposal is ready for review. The phases are independent — we could do just Phase 1+2 for the biggest wins (kill inline Python, single config source) and defer the rest.

Recommended order if doing partial: **Phase 1 → Phase 2 → Phase 5** (biggest ROI, ~80% of the benefit).
