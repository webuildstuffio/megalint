# ⚡ megalint

**AI prompt, skill, and agent linter.** Four tools run in parallel → one scored report.

Lint your AI skills, system prompts, and agent workspaces for structure, quality, security, and convention adherence — backed by [empirical research](https://arxiv.org/abs/2609.31575) on 407 real-world system prompts across 33 companies.

[![License: MIT](https://img.shields.io/badge/license-MIT-7c6ff7?style=flat-square)](LICENSE)

---

## Install

```bash
git clone https://github.com/webuildstuffio/megalint.git
cd megalint
./setup.sh            # installs all dependencies (< 60 seconds)
```

**Verify:** `./megalint.sh --version` → `megalint 1.0.0`

> **Minimal install** — only `python3` and `ripgrep` are required. If Node.js or tool venvs are missing, megalint gracefully skips those tools and redistributes their weight to the remaining pillars.

<details>
<summary>Manual install (if you prefer)</summary>

```bash
# Required
brew install ripgrep python3             # macOS (apt-get on Linux)

# Optional — each enables one tool
brew install node                         # → AgentLinter (structure pillar)
cd apps/agentlinter && bun install && cd ../..  # → build AgentLinter CLI

cd apps/promptlint && uv venv .venv && uv pip install -e . --python .venv/bin/python && cd ../..
# → PromptLint (quality pillar)

cd apps/prompt-hardener && uv venv .venv && uv pip install -e . --python .venv/bin/python && cd ../..
# → Prompt Hardener (security pillar, needs ANTHROPIC_API_KEY in .env)
```

</details>

## Quick Start

```bash
# Lint one skill
./megalint.sh ~/.cursor/skills/bugfix

# Lint all skills in a directory
./megalint.sh --mode skills ~/.cursor/skills/

# Lint prompt files
./megalint.sh AGENTS.md CLAUDE.md

# Common options
./megalint.sh --preset balanced /path          # ERROR + WARN only (skip INFO)
./megalint.sh --disable-rule skill/examples    # disable specific rules
./megalint.sh --format json /path              # save JSON report to .reports/
./megalint.sh --json /path                     # JSON to stdout (pipe-friendly)
./megalint.sh -q /path                         # quiet: errors and warnings only
./megalint.sh --list-rules                     # show all rules with IDs
```

## Four Interfaces

### 1. CLI

```bash
./megalint.sh [options] [path...]
./megalint.sh --help                           # full options
```

### 2. Web Dashboard

```bash
./megalint.sh --serve                          # → http://localhost:7777
```

Rules explorer, report viewer, score trends, live lint runner, config viewer.

### 3. MCP Server

Add to `~/.cursor/mcp.json` (or `claude_desktop_config.json`):

```json
{
  "megalint": {
    "command": "bun",
    "args": ["run", "/absolute/path/to/megalint/mcp/server.ts"]
  }
}
```

**Tools:** `megalint_lint` · `megalint_rules` · `megalint_report` · `megalint_trends` · `megalint_config`

### 4. CI (GitHub Actions)

```yaml
# .github/workflows/megalint.yml
name: megalint
on:
  pull_request:
    paths: ['**/*.md', '.cursor/skills/**']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: webuildstuffio/megalint@main
        with:
          path: .cursor/skills
          mode: skills
          preset: balanced
          fail-on-error: true
          comment: true         # posts score as PR comment
```

See [`ci/megalint.example.yml`](ci/megalint.example.yml) for a full example.

## How Scoring Works

Five pillars, weighted (configurable in [`megalint.conf`](megalint.conf)):

| Pillar | Tool | What it measures | Default weight |
|--------|------|------------------|:--------------:|
| Structure | AgentLinter | File layout, headings, naming | 25% |
| Quality | PromptLint | Clarity, security, cost efficiency | 18% |
| Consistency | Conventions | Cross-item rule adherence | 22% |
| Security | Prompt Hardener | LLM injection defense | 20% |
| Budget | Token count | Token usage vs budget targets | 15% |

**Pass/fail:** score ≥ 70 AND no blocking errors (both configurable).

**Grades:** S (97+) · A+ (95) · A (93) · A- (90) · B+ (87) · B (83) · B- (80) · C+ (77) · C (73) · C- (70) · D (60) · F (<60)

When a tool is skipped (e.g. Hardener without API key, or PromptLint without venv), its weight redistributes proportionally to the remaining pillars.

## Rule Registry

23 rules with unique IDs. Control via `--disable-rule`, `--preset`, or `--list-rules`.

### Skill Rules (16)

| Rule | Sev | Description |
|------|:---:|-------------|
| `skill/file-exists` | ERROR | SKILL.md must exist |
| `skill/dangerous-commands` | ERROR | No `rm -rf /`, `curl\|sh`, etc. |
| `skill/secrets` | ERROR | No hardcoded API keys or PII |
| `skill/description` | WARN | Clear description/purpose statement |
| `skill/when-to-use` | WARN | Trigger guidance for agents |
| `skill/structure` | WARN | ≥2 markdown headings |
| `skill/actionable` | WARN | Steps, bullets, or code examples |
| `skill/injection` | WARN | No prompt injection patterns |
| `skill/idempotent` | WARN | Destructive ops have safeguards |
| `skill/file-count` | INFO | ≤5 files per skill |
| `skill/scope-boundaries` | INFO | Defines what the skill should NOT do |
| `skill/examples` | INFO | Concrete examples or code blocks |
| `skill/output-format` | INFO | Output format specification |
| `skill/error-handling` | INFO | Error recovery instructions |
| `skill/restrictions` | INFO | NEVER/MUST NOT safety markers |
| `skill/tool-boundaries` | INFO | Tool use boundaries |

### Prompt Rules (7)

| Rule | Sev | Description |
|------|:---:|-------------|
| `prompt/dangerous-commands` | ERROR | No destructive commands |
| `prompt/injection` | WARN | No injection patterns |
| `prompt/identity` | INFO | Role/identity definition |
| `prompt/output-format` | INFO | Output format guidance |
| `prompt/scope` | INFO | Scope/task boundaries |
| `prompt/examples` | INFO | Concrete examples |
| `prompt/constraints` | INFO | Emphatic constraints (NEVER/MUST NOT) |

### Presets

| Preset | Includes | Use when |
|--------|----------|----------|
| `strict` | All rules | Development, thorough review |
| `balanced` | ERROR + WARN | CI gates, day-to-day |
| `minimal` | ERROR only | Quick sanity check |

## Configuration

Edit `megalint.conf`:

```bash
WEIGHT_STRUCTURE=25     # pillar weights (must sum to 100)
WEIGHT_QUALITY=18
WEIGHT_CONSISTENCY=22
WEIGHT_SECURITY=20
WEIGHT_BUDGET=15

PASS_THRESHOLD=70       # minimum score to pass
BLOCKING_ERRORS=true    # any convention ERROR = fail regardless of score
```

CLI flags override config for a single run. See [`RULES_GUIDE.md`](RULES_GUIDE.md) for the full internals reference.

## Why Four Tools?

| Capability | AgentLinter | PromptLint | Conventions | Hardener |
|-----------|:-:|:-:|:-:|:-:|
| File structure / naming | ✓ | | ✓ | |
| Vague/passive instructions | ✓ | ✓ | | |
| Secret patterns | ✓ | ✓ | ✓ | |
| Injection defense (regex) | | ✓ | ✓ | |
| Injection defense (LLM) | | | | ✓ |
| Skill structure checks | | | ✓ | |
| Token cost estimation | | ✓ | | |
| Persona switching defense | | | | ✓ |
| **Cost** | Free | Free | Free | ~$0.02/item |

No single tool covers all layers. Together they catch what each misses.

## Project Structure

```
megalint.sh              # CLI runner (orchestrates all 4 tools)
megalint.conf            # Scoring config
setup.sh                 # One-command dependency installer
web/
  server.ts              # Web dashboard (Bun)
  dashboard.html         # SPA
mcp/
  server.ts              # MCP server (stdio)
ci/
  action.yml             # GitHub Actions composite action
  megalint.example.yml   # Example workflow
apps/
  agentlinter/           # Tool 1: structure (Node.js)
  promptlint/            # Tool 2: quality (Python, MIT)
  prompt-hardener/       # Tool 3: security (Python, Apache-2.0)
  homegrow/              # Tool 4: conventions (Bash)
    run.sh               # Dispatcher
    skills.sh            # 16 skill checks
    prompts.sh           # 7 prompt checks
    rules.conf           # Check toggles + token budgets
lib/
  config.py              # Weights, grades, pricing
  process.py             # Tool output processor
  scoring.py             # 5-pillar scoring engine
  display.py             # Terminal renderer
  report.py              # JSON/Markdown reports
  tiktoken_count.py      # Token counter
tests/
  megalint.bats          # 25 regression tests
```

## Tests

```bash
bats tests/megalint.bats    # 25 tests
```

## Requirements

| Dependency | Required | Why |
|------------|:--------:|-----|
| Python 3.10+ | ✓ | Scoring, reports, display |
| ripgrep (`rg`) | ✓ | Convention checks |
| Bash 4+ | ✓ | Shell scripts |
| Node.js 18+ | Optional | AgentLinter (Structure pillar) |
| Bun 1.0+ | Optional | Web dashboard, MCP server |

Optional: `ANTHROPIC_API_KEY` in `.env` for Prompt Hardener (Security pillar).

## Research

Rules derived from:

- **[arxiv 2609.31575](https://arxiv.org/abs/2609.31575)** — 407 leaked system prompts across 33 companies. 58% tool/protocol, 12.4% formatting, 5.4% safety, 2.9% identity.
- **Claude Code** — Skill architecture: `description` + `allowedTools` + bundled files. Reversibility, blast radius, tool boundaries.
- **ChatGPT** — Behavioral encoding through examples and constraints.
- **Devin** — Step-by-step workflows, scope limits.

## Third-Party Notices

megalint includes forked components. See [NOTICE](NOTICE) for full attribution.

| Component | License | Location |
|-----------|---------|----------|
| PromptLint | MIT | `apps/promptlint/` |
| Prompt Hardener | Apache 2.0 | `apps/prompt-hardener/` |
| AgentLinter | Internal | `apps/agentlinter/` |

## License

[MIT](LICENSE) — use freely for any purpose, commercial or otherwise.
