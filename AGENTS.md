# AGENTS.md — megalint

Megalint — AI prompt, skill, and agent linter. Runs 4 tools in parallel (AgentLinter, PromptLint, Conventions, Prompt Hardener) producing a single scored report.

## Modes

- `--mode skills` — lint skill directories (SKILL.md + supporting files) — primary use case
- `--mode prompts` — lint individual .md prompt files (system prompts, AGENTS.md, CLAUDE.md, etc.)
- `--mode agents` — lint OpenClaw MDS agent workspaces (legacy)
- `--mode auto` — detect from input structure (default)

Auto-detection: SKILL.md → skills, AGENTS.md+SOUL.md → agents, else prompts.

## Rule Registry

16 skill rules + 7 prompt rules, each with unique IDs (e.g., `skill/file-exists`).
Rule control: `--list-rules`, `--disable-rule ID,...`, `--preset strict|balanced|minimal`, `--quiet`.
Rules derived from arxiv 2609.31575 (407 leaked system prompts, 33 companies) + Claude Code skill architecture.

## Interfaces

- **CLI**: `./megalint.sh [options] [path...]` — primary interface. `--json` for machine output, `--format json|md|both` for reports.
- **Web**: `./megalint.sh --serve` or `bun run web/server.ts` — dashboard on port 7777. Shows rules, reports, trends, live lint, config.
- **MCP**: `bun run mcp/server.ts` — stdio MCP server with 5 tools: `megalint_lint`, `megalint_rules`, `megalint_report`, `megalint_trends`, `megalint_config`.
- **CI**: `ci/action.yml` — GitHub Actions composite action. Posts PR comments with score/grade. See `ci/megalint.example.yml`.

## Project Structure

```
megalint.sh              # Main CLI runner
megalint.conf            # Scoring weights, thresholds, grades
apps/
  agentlinter/           # Tool 1: workspace structure
  promptlint/            # Tool 2: per-file quality
  homegrow/              # Tool 3: convention checks (run.sh, skills.sh, prompts.sh)
  prompt-hardener/       # Tool 4: LLM security testing
lib/
  config.py              # Config loader
  process.py             # Tool output processor
  scoring.py             # 5-pillar scoring engine
  display.py             # Terminal report renderer
  report.py              # JSON/Markdown report generator
  tiktoken_count.py      # Token counter
web/
  server.ts              # Bun web server + API
  dashboard.html         # SPA dashboard
mcp/
  server.ts              # MCP stdio server
ci/
  action.yml             # GitHub Actions composite action
  megalint.example.yml   # Example CI workflow
tests/
  megalint.bats          # Regression tests (25 tests)
```

Part of the webuildstuffio org. See the repo README for setup and usage.
