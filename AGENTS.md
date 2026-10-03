# AGENTS.md — megalint

Megalint lints AI prompts, skills, and agent workspaces: a bash orchestrator runs 4 tools and merges them into one scored report (0–100, letter grade S–F, pass/fail). Ships as a local CLI, a GitHub Actions composite action, a Bun web dashboard, and an MCP server. This file is the review context for AI reviewers (Qodo pr-agent, Claude Code) — maintain it when architecture or invariants change.

## Stack

- **Orchestrator**: bash (`megalint.sh`, `set -euo pipefail`) — requires ripgrep and bash ≥4 (`declare -A`)
- **Tool 1 AgentLinter**: TypeScript, runs via Node (`apps/agentlinter/packages/cli/dist/bin.js`), installed with bun
- **Tool 2 PromptLint**: Python ≥3.11 (typer, rich, pydantic, tiktoken), per-app venv at `apps/promptlint/.venv`
- **Tool 3 Homegrow**: pure bash + rg convention checks (`apps/homegrow/run.sh`, `skills.sh`, `prompts.sh`)
- **Tool 4 Prompt Hardener**: Python (pinned deps incl. `anthropic`), needs `ANTHROPIC_API_KEY` in `.env`
- **Web/MCP**: Bun + TypeScript, `"type": "module"`, `@modelcontextprotocol/sdk ^1.12.1` — `web/server.ts` (port 7777), `mcp/server.ts` (stdio)
- **Tests**: bats — `bats tests/megalint.bats` (25 regression tests). CI pins: Node 20, Python 3.12, `ubicloud-standard-2` runners
- **Config**: `megalint.conf` + `apps/homegrow/rules.conf` — both bash-sourceable; `lib/config.py` is the single parser
- **Setup**: `./setup.sh` installs everything; missing optional deps degrade (see Non-negotiables)

## Architecture

Data flow through `megalint.sh`:

1. Parse flags, auto-detect mode (`SKILL.md` → skills, `AGENTS.md`+`SOUL.md` → agents, else prompts), discover items
2. Tools 1–3 run as parallel background jobs, writing JSON into a `mktemp` run dir
3. Tool 4 (Prompt Hardener) runs sequentially after — LLM API calls with printed cost estimate (default `--yes` auto-approves)
4. `lib/process.py` merges raw outputs → `summary.json`; `lib/scoring.py` computes the weighted score; `lib/display.py` renders and returns the exit code (0 pass / 1 fail); `lib/report.py` writes `.reports/`

**Scoring pillars** (weights sum to 100; a skipped tool's weight redistributes proportionally):

| Pillar | Weight | Source |
|---|---|---|
| Structure | 25 | AgentLinter 0–100 |
| Quality | 18 | PromptLint clarity 0–10 → 0–100 |
| Consistency | 22 | Homegrow weighted pass rate (PASS=1.0, INFO=0.75, WARN=0.5, ERROR=0) |
| Security | 20 | Prompt Hardener satisfaction; RSE category excluded |
| Token Budget | 15 | Linear 100 at budget → 0 at 5× budget |

Pass = score ≥ `PASS_THRESHOLD` (70) **and** no blocking errors. Deployment surfaces: CLI, `ci/action.yml` (one self-updating PR comment + artifacts), `--serve` dashboard, MCP (5 tools).

## Conventions

- **Package managers**: bun for AgentLinter — **not a workspace**: `apps/agentlinter` and `apps/agentlinter/packages/cli` have independent lockfiles (hence two Dependabot entries). Python apps use `uv` or `pip3` venvs; CI uses `npm ci`/`pip install`
- **Tests encode invariants** — no `eval` on tool output, `trap cleanup EXIT` present, no hardcoded `/Users/`|`/home/` paths, lib parity (`process/display/config/scoring/report.py` invoked). Change tests with behavior, not after
- **Commits**: conventional prefixes (`fix:`, `docs:`, `chore:`, `deps:`, `ci:`), branches like `chore/topic`. Dependabot opens grouped monthly PRs (Mondays 05:00)
- **Rule IDs** are namespaced (`skill/...`, `prompt/...`) with ERROR/WARN/INFO severities; presets (`strict|balanced|minimal`) resolve to disabled-rule lists in `megalint.sh`
- Deep dives: `RULES_GUIDE.md`, `apps/homegrow/RULES.md`, `docs/TOKEN_BUDGET_GUIDE.md`

## Non-negotiables

1. **Never `eval` tool output.** Tool JSON/text is untrusted; parse with `while read` KEY=VAL loops. There is a regression test that fails if `eval "$COST_INFO"`-style code returns
2. **Graceful degradation**: every tool is optional. Missing dep → warn, skip pillar, redistribute weight, finish the run. A missing binary must never crash the run or corrupt the exit code
3. **Blocking semantics**: with `BLOCKING_ERRORS=true` (default), any Homegrow ERROR fails the run regardless of score. `ci/action.yml` `fail-on-error` builds on this — don't weaken it silently
4. **Token budgets never block** (max severity WARN) and `CHECK_TOKEN_BUDGETS` must stay `0` in rules.conf — pillar 5 owns length scoring; enabling both double-counts and produces false blocking errors
5. **`summary.json` is a public API**: `web/server.ts`, `mcp/server.ts`, and `ci/action.yml` all parse it. Also note `--json` always exits 0 — consumers must read `passed`/`has_blocking` from the JSON, not the exit code
6. **Supply chain**: `bunfig.toml` `minimumReleaseAge = 432000` (5-day npm-poison window) in both agentlinter locations must survive refactors. Secrets live only in `.env` (never committed); the secrets/injection rules scan for leaks
7. **Weights sum to 100** in `megalint.conf`, and `PASS_THRESHOLD` (70) aligns with `GRADE_C_MINUS` so there is no "C+ but FAIL" — keep both invariants when tuning
8. **Run hygiene**: all intermediates go in the `mktemp` run dir removed by `trap cleanup EXIT`; only final reports persist to `.reports/`

## Known traps

- **Dependabot cooldown (7d) must stay above the 5-day release-age window** — with the default 3-day cooldown, Dependabot selects versions bun then refuses to resolve, failing the job (documented in `dependabot.yml`)
- **`metrics-gate.yml` pins `webuildstuffio/repo-review` (private repo) by SHA** — Dependabot gets 403 (`git_dependencies_not_reachable`) and the whole github-actions update job fails, which is why it's ignored there; bump the pin manually via `chore:` commits
- **The rule registry is triplicated**: `apps/homegrow/run.sh` heredoc + `RULES[]` in `web/server.ts` + `RULES[]` in `mcp/server.ts`. Adding or changing a rule means editing all three (plus `RULES_GUIDE.md`) or the surfaces drift out of sync
- **`ci/action.yml` clones `main` at depth 1 into `/tmp`** when megalint isn't vendored — action behavior changes only reach consumers after merging to `main`
- **Prompt Hardener costs real money**: `megalint.sh` defaults to `claude-opus-4-6` ($5/$25 per MTok) while `.env.example` recommends `claude-sonnet-4-6` ($3/$15); `--yes` is the default and auto-approves spend. Keep API calls off the default path
- **Runners are Ubicloud (`ubicloud-standard-2`)** — `.github/actionlint.yaml` whitelists the label; new workflows using it fail actionlint without that file
- **Qodo tuning lives in a separate PUBLIC repo** (`webuildstuffio/pr-agent-settings`) — if it goes private the default token 404s and global tuning silently drops with no error surfaced

## Review focus

1. **Shell safety first**: `megalint.sh` and `apps/homegrow/*.sh` interpolate user input (paths, rule IDs, model names) into commands. Check quoting and word splitting; any new `eval` is a bug by definition
2. **Scoring math**: `lib/scoring.py` weight redistribution, grade boundaries, and the pass/blocking interaction. A skipped pillar silently reshaping the score is the #1 place for subtle bugs
3. **Schema stability**: anything touching `summary.json` shape or exit codes — verify all three consumers still parse correctly
4. **Degradation paths**: tool-invocation changes must keep the skip+warn behavior; a hard failure on a missing optional dependency is a regression
5. **Security-sensitive rules**: `skill/dangerous-commands`, `skill/secrets`, `skill/injection`, `prompt/injection` — pattern changes deserve adversarial reading for false negatives (missed secrets or injections in linted prompts)
6. **Portability**: scripts must work from any cwd, contain no hardcoded user paths, and avoid GNU-only coreutils flags (CI is Ubuntu, dev machines are macOS)
