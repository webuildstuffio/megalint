# Megalint

Unified prompt linting for OpenClaw MDS agent workspaces. Four complementary tools run in parallel, producing a single merged report with consistent scoring.

## Quick Start

```bash
./megalint.sh                                  # Static analysis only (free)
./megalint.sh --yes                            # Include Prompt Hardener (API cost)
./megalint.sh --format both --yes              # Save JSON + Markdown reports
./megalint.sh passportio kodo --format md      # Specific agents, Markdown report
./megalint.sh --model claude-opus-4-6 -y       # Use Opus for deeper analysis
./megalint.sh --help                           # All options
```

## Why Four Tools?

Each tool solves a different layer of prompt quality. No single tool covers everything.

| Capability | AgentLinter | PromptLint | Home-Grow | Prompt Hardener |
|-----------|:-----------:|:----------:|:---------:|:---------------:|
| **Type** | Static (Node.js) | Static (Python) | Static (Bash) | LLM-powered (API) |
| **Scope** | Whole workspace | Per-file | Cross-agent | Per-agent |
| **Cost** | Free | Free | Free | ~$0.02/agent |
| **Speed** | ~1s/agent | ~0.5s/file | Instant | ~5s/agent |
| | | | | |
| File structure / naming | **Yes** | | **Yes** | |
| Required files present | | | **Yes** | |
| Section hierarchy | **Yes** | | | |
| Cross-file consistency | **Yes** | | | |
| Shared file references (BOOT→shared) | | | **Yes** | |
| Vague instructions / passive voice | **Yes** | **Yes** | | |
| Contradictions / conflicting directives | **Yes** | **Yes** | | |
| Ambiguous pronouns / naked conditionals | **Yes** | | | |
| Token cost estimation | | **Yes** | | |
| Secret patterns (API keys, tokens, PII) | **Yes** | **Yes** | | |
| Injection patterns (OWASP regex) | | **Yes** | | |
| Prompt injection defense | | | | **Yes** |
| Persona switching defense | | | | **Yes** |
| Spotlighting (input tagging) | | | | **Yes** |
| Random sequence enclosure | | | | **Yes** |
| Role consistency | | | | **Yes** |
| Anti-sycophancy opener | | | **Yes** | |
| Action tiers validation | | | **Yes** | |
| Tone calibration table | | | **Yes** | |
| Continuity line | | | **Yes** | |
| Timezone consistency | | | **Yes** | |
| Security section presence | | | **Yes** | |
| Memory workflow reference | | | **Yes** | |
| Heartbeat contract validation | | | **Yes** | |
| Token budget enforcement | | | **Yes** | |
| Agent roster count | | | **Yes** | |
| Canonical wording consistency | | | **Yes** | |
| Bootstrap cleanup | | | **Yes** | |
| Boot checklist structure | | | **Yes** | |
| Memory / session handoff | **Yes** | | | |
| Skill safety (dangerous commands) | **Yes** | | | |

**In short:**
- **AgentLinter** = ESLint for agent workspaces (structure + clarity + security rules)
- **PromptLint** = per-file quality scanner (clarity + cost + injection patterns)
- **Home-Grow** = OpenClaw-specific consistency checks (the stuff only we know to check)
- **Prompt Hardener** = active security testing via LLM (finds what regex can't)

## Options

| Flag | Description |
|------|-------------|
| `-y, --yes` | Skip cost confirmation for Prompt Hardener |
| `-m, --model MODEL` | Override model (`claude-sonnet-4-6` or `claude-opus-4-6`) |
| `-f, --format FORMAT` | Output report: `json`, `md`, or `both` |
| `--pass-threshold N` | Minimum score to pass (default: 70) |
| `--no-blocking` | Don't fail on Home-Grow errors regardless of score |
| `-c, --config FILE` | Load alternate config file |
| `-h, --help` | Show help |
| `[agent...]` | Lint specific agents (default: all) |

## Configuration

`megalint.conf` controls weights, deductions, thresholds, and grade scale. All values are editable:

```bash
WEIGHT_STRUCTURE=30     # AgentLinter weight
WEIGHT_QUALITY=25       # PromptLint weight
WEIGHT_CONSISTENCY=25   # Home-Grow weight
WEIGHT_SECURITY=20      # Prompt Hardener weight

# DEDUCT_ERROR=10       # legacy — consistency now uses percentage model
# DEDUCT_WARNING=3      # legacy — OK=1.0 WARN=0.5 ERR=0.0 / total × 100

PASS_THRESHOLD=70       # minimum score to pass
BLOCKING_ERRORS=true    # any ERROR = fail regardless of score
```

CLI flags override config values for a single run.

## Output

Reports are saved to `tools/megalint/.reports/` (gitignored).

Each run produces:
- **Log file** — `lint-run_{commit}_{timestamp}.log` (always)
- **JSON report** — `report_{commit}_{timestamp}.json` (with `--format json` or `both`)
- **Markdown report** — `report_{commit}_{timestamp}.md` (with `--format md` or `both`)

Intermediate files (tool stdout, Hardener evals) go to a temp directory and are cleaned up automatically (trap on EXIT/INT/TERM).

### Version Tracking

Every report includes git metadata for tracking progress over time:

```json
{
  "meta": {
    "run_id": "0c41d44_2026-02-20_16-15-47",
    "git": {
      "commit": "0c41d44",
      "branch": "main",
      "dirty": false,
      "message": "Add passportio agent and update shared configs"
    }
  }
}
```

Run ID = `{commit}_{timestamp}`, so you can compare scores across commits.

### Unified Report Format

All four tools merge into a single consistent structure:

```json
{
  "meta": { "run_id", "timestamp", "git": {...}, "model", "agents_scanned" },
  "scoring": {
    "combined": 84.2, "grade": "B+", "passed": true,
    "pass_threshold": 70, "blocking_errors": true,
    "pillars": {
      "structure": { "score": 84, "weight": 30, "tool": "AgentLinter" },
      "quality": { "score": 87.3, "weight": 25, "tool": "PromptLint" },
      "consistency": { "score": 90, "weight": 25, "tool": "Home-Grow" },
      "security": { "score": 40, "weight": 20, "tool": "Prompt Hardener" }
    },
    "quality_detail": { "clarity": 8.2, "security": 9.5, "cost": 8.5 }
  },
  "agents": {
    "kodo": {
      "agentlinter": { "score": 84, "categories": {...}, "diagnostics": [...] },
      "promptlint": { "AGENTS.md": { "clarity": 7.2, "security": 10, ... }, ... },
      "prompt_hardener": { "Spotlighting": {...}, "Instruction Defense": {...}, ... }
    }
  },
  "homegrow": { "passes": 58, "warnings": 4, "errors": 1, "checks": [...] }
}
```

## Dependencies

- **Node.js** — AgentLinter
- **ripgrep (rg)** — Home-Grow checks
- **Python 3** + venvs — PromptLint, Prompt Hardener

Install: `brew install node ripgrep` (macOS). Missing deps fail early with clear errors.

## Environment Setup

```bash
cp tools/megalint/.env.example tools/megalint/.env
# Edit .env → set ANTHROPIC_API_KEY
```

Only needed for Tool 4 (Prompt Hardener). Tools 1-3 are free and run without keys.

## Models

| Model | Input $/MTok | Output $/MTok | Best for |
|-------|:------------:|:-------------:|----------|
| `claude-sonnet-4-6` | $3 | $15 | Fast default, good accuracy |
| `claude-opus-4-6` | $5 | $25 | Deepest analysis |

## Scoring

All four tools contribute to the combined score via weighted pillars:

| Pillar | Tool | How | Default Weight |
|--------|------|-----|:-:|
| Structure | AgentLinter | Raw 0-100 score | 30% |
| Quality | PromptLint | avg(clarity, security, cost) * 10 → 0-100 | 25% |
| Consistency | Home-Grow | (OK×1.0 + WARN×0.5 + ERR×0.0) / total × 100 | 25% |
| Security | Prompt Hardener | (satisfied_checks / total_checks) * 100 | 20% |

When a tool is skipped (e.g., Hardener without API key), its weight redistributes proportionally.

**Pass/fail:** Score >= threshold (default 70) AND no blocking errors. Configurable via `megalint.conf` or CLI.

**Grade scale:** S (98+), A+ (96+), A (93+), A- (90+), B+ (85+), B (80+), B- (75+), C+ (68+), C (60+), C- (55+), D (50+), F (<50)

**Display format:** `84 (B+)` — score first, grade in brackets, used consistently everywhere.

## Modifying the Tools

All tools are cloned directly into this repo (no `.git`). Edit source directly:

- **AgentLinter rules:** `apps/agentlinter/packages/cli/src/engine/rules/` → rebuild with `bun run build`
- **PromptLint analyzers:** `apps/promptlint/promptlint/analyzers/` → no build needed
- **Prompt Hardener:** `apps/prompt-hardener/src/prompt_hardener/` → no build needed
- **Home-Grow checks:** `apps/homegrow/run.sh` (all checks as functions) + `apps/homegrow/rules.conf` (per-check toggles + budgets). Called by `megalint.sh` — no inlining.

## Directory Layout

```
tools/megalint/
  megalint.sh            # Unified runner (all 4 tools)
  megalint.conf          # Scoring weights, thresholds, grade scale
  apps/                  # Self-contained tool apps
    agentlinter/         # TypeScript, workspace-level linting
    promptlint/          # Python, per-file quality scoring
    prompt-hardener/     # Python, LLM-powered security testing
    homegrow/            # Bash, OpenClaw-specific consistency checks
      run.sh             # 16 checks as functions (single source of truth)
      rules.conf         # Per-check toggles + token budget targets
  lib/                   # Extracted Python modules (testable, lintable)
    scoring.py           # 4-pillar scoring engine
    report.py            # JSON + Markdown report generator
  .env.example           # API key template (committed)
  .env                   # Your API keys (gitignored)
  .reports/              # All output (gitignored)
  README.md              # This file
```

## Tests

```bash
# Stream A (safety): format validation, temp cleanup, no-eval parsing, wait codes
bats tools/megalint/test_megalint.bats

# Stream B (dead code): AL_CATS, PL_DETAILS, PH_SCORES removed; totals displayed
bats tools/megalint/tests/stream_b.bats

# Stream C (portability): dynamic agents, rg/node checks, REPO_ROOT
bats tools/megalint/tests/stream_c.bats
```

## Status

- **Stream A** (safety): done ✅  
- **Stream B** (dead code): done ✅  
- **Stream C** (portability): done ✅  
- **Stream D1** (homegrow dedup): done ✅  
- **D2-D7** (Python extraction): pending  

See **[BUGS.md](BUGS.md)** for full tracker.

## Deep Dive

See **[ANALYSIS.md](ANALYSIS.md)** for: per-check analysis with ratings and failure modes for all 16 Home-Grow checks and 10 Prompt Hardener sub-criteria.

## Reinstalling Dependencies

If you move or rename the `tools/megalint/` directory, recreate the Python venvs (shebangs encode absolute paths):

```bash
cd tools/megalint/apps/agentlinter/packages/cli && bun install && bun run build
cd tools/megalint/apps/promptlint && uv venv .venv && uv pip install -e . --python .venv/bin/python
cd tools/megalint/apps/prompt-hardener && uv venv .venv && uv pip install -e . --python .venv/bin/python
```
