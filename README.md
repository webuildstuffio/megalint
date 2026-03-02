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
| Directive imports (## Directives, paths, dedup across 6 config files) | | | **Yes** | |

### Directive import enforcement (Home-Grow)

Home-Grow enforces the directive import system: agents use `## Directives` in AGENTS.md plus @import() lines across SOUL.md, TOOLS.md, HEARTBEAT.md, MEMORY.md, and BOOT.md to pull shared directive files instead of inline duplication. Flags are configurable in `apps/homegrow/rules.conf`.

| Rule | Flag | Severity | Description |
|------|------|----------|-------------|
| check_imports_section | CHECK_IMPORTS_SECTION | ERROR | AGENTS.md must have ## Directives section |
| check_imports_valid_paths | CHECK_IMPORTS_VALID_PATHS | ERROR | All import paths resolve to directive files |
| check_directives_exist | CHECK_DIRECTIVES_EXIST | ERROR | All 28 directive files present in shared/directives/ |
| check_imports_completeness | CHECK_IMPORTS_COMPLETENESS | WARN | Agent imports match manifest.conf requirements |
| check_imports_no_duplication | CHECK_IMPORTS_NO_DUPLICATION | WARN | No inline content duplicating imported directives |
| check_imports_boot_integration | CHECK_IMPORTS_BOOT_INTEGRATION | WARN | BOOT.md references @import directives |
| check_imports_tools_dedup | CHECK_IMPORTS_TOOLS_DEDUP | WARN | TOOLS.md doesn't duplicate shared tool content |
| check_imports_user_dedup | CHECK_IMPORTS_USER_DEDUP | WARN | USER.md doesn't duplicate USER_CORE content |
| check_legacy_shared_files | CHECK_LEGACY_SHARED_FILES | WARN | Old monolithic shared files cleaned up |
| check_orphan_directives | CHECK_ORPHAN_DIRECTIVES | INFO | No directive files unused by any agent |

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

`megalint.conf` controls weights, thresholds, and grade scale. All values are editable:

```bash
WEIGHT_STRUCTURE=25     # AgentLinter — workspace structure, clarity, rules
WEIGHT_QUALITY=18       # PromptLint — per-file clarity (0-10 scaled to 0-100)
WEIGHT_CONSISTENCY=22   # Home-Grow — cross-agent consistency checks
WEIGHT_SECURITY=20      # Prompt Hardener — LLM-powered injection testing
WEIGHT_BUDGET=15        # Token Budget — per-file length vs budget scoring

PASS_THRESHOLD=70       # minimum score to pass
BLOCKING_ERRORS=true    # any ERROR = fail regardless of score
```

CLI flags override config values for a single run.

## Output

Reports are saved to `dev-tools/megalint/.reports/` (gitignored).

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
      "structure": { "score": 84, "weight": 25, "tool": "AgentLinter" },
      "quality": { "score": 87.3, "weight": 18, "tool": "PromptLint" },
      "consistency": { "score": 90, "weight": 22, "tool": "Home-Grow" },
      "security": { "score": 40, "weight": 20, "tool": "Prompt Hardener" },
      "budget": { "score": 99, "weight": 15, "tool": "Token Budget" }
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
cp dev-tools/megalint/.env.example dev-tools/megalint/.env
# Edit .env → set ANTHROPIC_API_KEY
```

Only needed for Tool 4 (Prompt Hardener). Tools 1-3 are free and run without keys.

## Models

| Model | Input $/MTok | Output $/MTok | Best for |
|-------|:------------:|:-------------:|----------|
| `claude-sonnet-4-6` | $3 | $15 | Fast default, good accuracy |
| `claude-opus-4-6` | $5 | $25 | Deepest analysis |

## Scoring

All five pillars contribute to the combined score via weighted pillars:

| Pillar | Tool | How | Default Weight |
|--------|------|-----|:-:|
| Structure | AgentLinter | Raw 0-100 score | 25% |
| Quality | PromptLint | avg(clarity, security, cost) * 10 → 0-100 | 18% |
| Consistency | Home-Grow | (OK×1.0 + WARN×0.5 + ERR×0.0) / total × 100 | 22% |
| Security | Prompt Hardener | (satisfied_checks / total_checks) * 100 | 20% |
| Token Budget | Length check | Per-file tokens vs budget (LOAD_WEIGHTS) | 15% |

When a tool is skipped (e.g., Hardener without API key), its weight redistributes proportionally.

**Pass/fail:** Score >= threshold (default 70) AND no blocking errors. Configurable via `megalint.conf` or CLI.

**Grade scale:** S (97+), A+ (95+), A (93+), A- (90+), B+ (87+), B (83+), B- (80+), C+ (77+), C (73+), C- (70+), D (60+), F (&lt;60)

**Display format:** `84 (B+)` — score first, grade in brackets, used consistently everywhere.

## Modifying the Tools

All tools are cloned directly into this repo (no `.git`). Edit source directly:

- **AgentLinter rules:** `apps/agentlinter/packages/cli/src/engine/rules/` → rebuild with `bun run build`
- **PromptLint analyzers:** `apps/promptlint/promptlint/analyzers/` → no build needed
- **Prompt Hardener:** `apps/prompt-hardener/src/prompt_hardener/` → no build needed
- **Home-Grow checks:** `apps/homegrow/run.sh` (all checks as functions) + `apps/homegrow/rules.conf` (per-check toggles + budgets). Called by `megalint.sh` — no inlining.

## Directory Layout

```
dev-tools/megalint/
  megalint.sh            # Unified runner (all 4 tools)
  megalint.conf          # Scoring weights, thresholds, grade scale
  apps/                  # Self-contained tool apps
    agentlinter/         # TypeScript, workspace-level linting
    promptlint/          # Python, per-file quality scoring
    prompt-hardener/     # Python, LLM-powered security testing
    homegrow/            # Bash, OpenClaw-specific consistency checks
      run.sh             # 31 checks as functions (single source of truth)
      rules.conf         # Per-check toggles + token budget targets
  lib/                   # Extracted Python modules (testable, lintable)
    config.py            # Single source of truth for weights, grades, pricing
    process.py           # Tool adapters, process_all, writes summary.json
    display.py           # Reads summary.json, prints terminal output
    scoring.py           # 5-pillar scoring engine
    report.py            # JSON + Markdown report generator
  tests/
    megalint.bats        # Regression and parity tests
  .env.example           # API key template (committed)
  .env                   # Your API keys (gitignored)
  .reports/              # All output (gitignored)
  README.md              # This file
```

## Tests

```bash
bats dev-tools/megalint/tests/megalint.bats
```

Covers: help/format validation, temp cleanup, no-eval parsing, homegrow delegation, template exclusion, portability, and refactored Python libs (config, process, display).

## Status

- **Stream A** (safety): done ✅  
- **Stream B** (dead code): done ✅  
- **Stream C** (portability): done ✅  
- **Stream D1** (homegrow dedup): done ✅  
- **D2-D7** (Python extraction): done ✅  

See **[BUGS.md](BUGS.md)** for full tracker.

## Deep Dive

See **[ANALYSIS.md](ANALYSIS.md)** for: per-check analysis with ratings and failure modes for all 31 Home-Grow checks and 10 Prompt Hardener sub-criteria.

## Reinstalling Dependencies

If you move or rename the `dev-tools/megalint/` directory, recreate the Python venvs (shebangs encode absolute paths):

```bash
cd dev-tools/megalint/apps/agentlinter/packages/cli && bun install && bun run build
cd dev-tools/megalint/apps/promptlint && uv venv .venv && uv pip install -e . --python .venv/bin/python
cd dev-tools/megalint/apps/prompt-hardener && uv venv .venv && uv pip install -e . --python .venv/bin/python
```
