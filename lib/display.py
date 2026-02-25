#!/usr/bin/env python3
"""Megalint display — reads summary.json and prints full terminal report with ANSI colors.

Replaces ~400 lines of bash display code in megalint.sh.

Usage: display.py --summary PATH [--log-file PATH]
Returns: exit 0 if passed, 1 if failed
"""

import argparse
import json
import sys
from pathlib import Path

# ANSI codes
RED = "\033[31m"
YELLOW = "\033[33m"
GREEN = "\033[32m"
CYAN = "\033[36m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"


def red(s: str) -> str:
    return f"{RED}{s}{RESET}"


def yellow(s: str) -> str:
    return f"{YELLOW}{s}{RESET}"


def green(s: str) -> str:
    return f"{GREEN}{s}{RESET}"


def cyan(s: str) -> str:
    return f"{CYAN}{s}{RESET}"


def bold(s: str) -> str:
    return f"{BOLD}{s}{RESET}"


def dim(s: str) -> str:
    return f"{DIM}{s}{RESET}"


def score_color(val) -> str:
    """Green if >=90, yellow if >=70, else red. N/A -> dim."""
    if val == "N/A" or val is None:
        return dim("N/A")
    try:
        s = int(float(val))
    except (ValueError, TypeError):
        return str(val)
    if s >= 90:
        return green(str(val))
    if s >= 70:
        return yellow(str(val))
    return red(str(val))


def _section(title: str) -> None:
    print(bold(f"━━━ {title} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
    print()


def _header(meta: dict) -> None:
    print()
    print(bold("╔══════════════════════════════════════════════════════════════╗"))
    print()
    print(bold("║         Unified Prompt Linter — OpenClaw MDS               ║"))
    print()
    print(bold("╚══════════════════════════════════════════════════════════════╝"))
    print()
    commit = meta.get("git_commit", "unknown")
    branch = meta.get("git_branch", "unknown")
    dirty = meta.get("git_dirty", False)
    dirty_str = " [dirty]" if dirty else ""
    print(dim(f"  commit: {commit} ({branch}){dirty_str}"))
    print()
    print()


def _section_agentlinter(data: dict, agents: list) -> None:
    _section("Tool 1: AgentLinter")
    al = data.get("agentlinter") or {}
    scores = al.get("scores") or {}
    per_agent = al.get("per_agent") or {}
    total_criticals = 0
    agent_only_warnings = 0
    ws_rules: dict[str, int] = {}

    for agent in agents:
        pa = per_agent.get(agent) or {}
        diags = pa.get("diagnostics") or []
        score = scores.get(agent, pa.get("score", 0))
        agent_warns = pa.get("agent_warnings", 0)
        crits = sum(1 for d in diags if d.get("severity") in ("critical", "error"))
        total_criticals += crits
        agent_only_warnings += agent_warns
        for d in diags:
            if d.get("severity") == "warning" and d.get("file") == "(workspace)":
                rule = d.get("rule", "")
                if rule:
                    ws_rules[rule] = ws_rules.get(rule, 0) + 1

        sc = score_color(score)
        print(f"  {bold(agent)} {sc}/100")
        categories = pa.get("categories")
        if categories:
            if isinstance(categories, dict):
                for cname, cscore in categories.items():
                    print(f"    {cname:<17} {cscore}")
            else:
                for c in categories:
                    cname = c.get("name", "")
                    cscore = c.get("score", "")
                    if cname:
                        print(f"    {cname:<17} {cscore}")
        if crits > 0:
            print(f"    {red(f'{crits} error(s)')}")
        if agent_warns > 0:
            print(f"    {yellow(f'{agent_warns} warning(s)')}")

        if diags:
            print()
            for d in diags:
                sev = d.get("severity", "")
                if sev not in ("critical", "error", "warning"):
                    continue
                f = d.get("file", "")
                ln = d.get("line", "")
                loc = f"{f}:{ln}" if ln else f
                msg = (d.get("message", "") or "").replace("\n", " ")[:120]
                fix = (d.get("fix", "") or "").replace("\n", " ")[:100]
                if sev in ("critical", "error"):
                    print(f"  {red('🔴 ERROR')}  {loc}")
                else:
                    print(f"  {yellow('🟡 WARN')} {loc}")
                print(f"         {msg}")
                if fix:
                    print(f"         {cyan('💡 Fix:')} {fix}")
        print()

    print(f"  {bold('Totals:')} {total_criticals} error(s), {agent_only_warnings} warning(s)")
    if ws_rules:
        print()
        print(dim(f"  Shared-level warnings (affect all agents, fix once): {len(ws_rules)}"))
        for rule, count in ws_rules.items():
            print(dim(f"    {rule} (seen in {count}/{len(agents)} agents)"))
    print()


def _section_promptlint(data: dict, agents: list) -> None:
    _section("Tool 2: PromptLint")
    pl = data.get("promptlint") or {}
    per_agent = pl.get("per_agent") or {}

    for agent in agents:
        pa = per_agent.get(agent) or {}
        files_data = pa.get("files") or {}
        if isinstance(files_data, list):
            files_data = {f.get("fname", ""): f for f in files_data if f.get("fname")}

        print(f"  {bold(agent)}")
        for fname, fd in files_data.items():
            if isinstance(fd, bool):
                continue
            if fd.get("_error"):
                print(f"    {red('ERROR:')} PromptLint failed on {fname} — check binary/venv")
                continue
            overall = fd.get("overall", 0)
            try:
                oi = int(float(overall))
            except (ValueError, TypeError):
                oi = 0
            if oi >= 9:
                od = green(f"{overall}/10")
            elif oi >= 7:
                od = yellow(f"{overall}/10")
            else:
                od = red(f"{overall}/10")
            clarity = fd.get("clarity", 0)
            security = fd.get("security", 0)
            cost = fd.get("cost", fd.get("cost_efficiency", 0))
            print(f"    {fname:<18} {od}  ", end="")
            print(dim(f"(clarity:{clarity} sec:{security} cost:{cost})"))
        avg_cl = pa.get("avg_clarity")
        avg_se = pa.get("avg_security")
        avg_co = pa.get("avg_cost")
        if avg_cl is not None and (files_data or avg_cl != 0):
            print(dim(f"    avg: clarity:{avg_cl} sec:{avg_se} cost:{avg_co}"))
        print()
    print()


def _section_homegrow(data: dict) -> None:
    _section("Tool 3: Home-Grow Linter")
    hg = data.get("homegrow") or {}
    checks = hg.get("checks") or []
    passes = hg.get("passes", 0)
    infos = hg.get("infos", 0)
    warnings = hg.get("warnings", 0)
    errors = hg.get("errors", 0)

    if not checks:
        print(f"  {yellow('WARN:')} Home-Grow produced no output — check apps/homegrow/run.sh")
    else:
        for c in checks:
            status = c.get("status", "")
            ctx = c.get("context", "")
            msg = c.get("message", "")
            line = f"{ctx} — {msg}" if ctx else msg
            if status == "OK":
                print(f"  {green('OK')}    {line}")
            elif status == "INFO":
                print(f"  {cyan('INFO')}  {line}")
            elif status == "WARN":
                print(f"  {yellow('WARN')}  {line}")
            elif status == "ERROR":
                print(f"  {red('ERROR')} {line}")

    print()
    print(f"  {bold('Summary:')} {green(f'{passes} pass')} | {cyan(f'{infos} info')} | {yellow(f'{warnings} warn')} | {red(f'{errors} error')}")
    print()
    print()


def _section_budget(data: dict, agents: list) -> None:
    _section("Token Budgets")
    budget = data.get("budget") or {}
    per_agent = budget.get("per_agent") or {}
    fleet_avg = budget.get("fleet_avg")

    for agent in agents:
        pa = per_agent.get(agent) or {}
        avg = pa.get("avg")
        files = pa.get("files") or []
        if not files and avg is None:
            continue
        sc = score_color(avg) if avg is not None else dim("—")
        print(f"  {bold(agent)} {sc}/100")
        for f in files:
            fname = f.get("fname", "")
            tokens = f.get("tokens", 0)
            bud = f.get("budget", 0)
            score = f.get("score", 0)
            level = f.get("level", "")
            freq = f.get("freq", "")
            ratio = f"{tokens}/{bud}" if bud else f"{tokens}"
            sc_d = score_color(score)
            tag = ""
            if level == "ERROR":
                tag = f" {red('▲')}"
            elif level == "WARN":
                tag = f" {yellow('▲')}"
            elif level == "INFO":
                tag = f" {cyan('~')}"
            freq_tag = dim(f" {freq}") if freq else ""
            bar = f.get("bar", "░" * 10)
            print(f"    {fname:<15} {ratio:>8}  {sc_d}  {bar}{tag}{freq_tag}")
        print()

    if fleet_avg is not None and per_agent:
        print(f"  {bold('Fleet average:')} {score_color(fleet_avg)}/100 {dim('(weighted by load frequency)')}")
    print()
    print()


def _section_hardener(data: dict, agents: list, meta: dict) -> None:
    print(bold("━━━ Tool 4: Prompt Hardener ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
    print()
    hardener = data.get("hardener")
    if hardener is None or not hardener.get("ran"):
        reason = hardener.get("skip_reason", "No ANTHROPIC_API_KEY") if hardener else "No ANTHROPIC_API_KEY"
        print(f"  {yellow('SKIPPED')} — {reason}")
    else:
        model = hardener.get("model", "claude-opus-4-6")
        print(f"  {green('API key found')} — model: {model}")
        print()
        per_agent_ph = hardener.get("per_agent") or {}
        eval_per = hardener.get("eval_per_agent") or {}
        for agent in agents:
            pa = per_agent_ph.get(agent) or {}
            tokens_in = pa.get("tokens_in", 0)
            tokens_out = pa.get("tokens_out", 0)
            status = pa.get("status", "Done" if tokens_in or tokens_out else "No eval output")
            if status in ("Done", "saved") and (tokens_in or tokens_out):
                print(f"  {bold(agent)} — evaluating...")
                print(f"    {green('Done')} — {tokens_in} in / {tokens_out} out tokens")
            elif pa:
                print(f"  {bold(agent)} — evaluating...")
                print(f"    {yellow(status)}")
                if pa.get("reason"):
                    print(dim(f"    reason: {pa['reason']}"))
            print()
        ti = hardener.get("actual_tokens_in", 0)
        to = hardener.get("actual_tokens_out", 0)
        cost = hardener.get("actual_cost")
        if (ti or to) and cost is not None:
            print(f"  {bold('Actual usage:')} {ti} in / {to} out — ${cost:.6f}")
        elif ti or to:
            print(f"  {bold('Actual usage:')} {ti} in / {to} out")
        print()
    print()


def _section_combined(data: dict, agents: list) -> None:
    print()
    print(bold("╔══════════════════════════════════════════════════════════════╗"))
    print()
    print(bold("║                    COMBINED RESULTS                        ║"))
    print()
    print(bold("╚══════════════════════════════════════════════════════════════╝"))
    print()

    scoring = data.get("scoring") or {}
    combined = scoring.get("combined", 0)
    grade = scoring.get("grade", "F")
    passed = scoring.get("passed", True)
    has_blocking = scoring.get("has_blocking", False)
    pass_threshold = scoring.get("pass_threshold", 70)
    hg_errors = (data.get("homegrow") or {}).get("errors", 0)

    pill_s = scoring.get("pillar_structure", 0)
    pill_q = scoring.get("pillar_quality")
    pill_co = scoring.get("pillar_consistency", 0)
    pill_se = scoring.get("pillar_security")
    pill_bu = scoring.get("pillar_budget")

    weights = scoring.get("weights") or {}
    w_st = weights.get("structure", 25)
    w_ql = weights.get("quality", 18)
    w_co = weights.get("consistency", 22)
    w_se = weights.get("security", 20)
    w_bu = weights.get("budget", 15)

    # Effective weights when pillars are N/A
    ql = w_ql if pill_q not in ("N/A", None) else 0
    se = w_se if pill_se not in ("N/A", None) else 0
    bu = w_bu if pill_bu not in ("N/A", None) else 0
    tw = w_st + ql + w_co + se + bu
    tw = max(tw, 1)
    eff_st = round(w_st / tw * 100)
    eff_ql = round(ql / tw * 100) if ql else "—"
    eff_co = round(w_co / tw * 100)
    eff_se = round(se / tw * 100) if se else "—"
    eff_bu = round(bu / tw * 100) if bu else "—"

    grade_str = f"{score_color(combined)} ({grade})"
    print(f"  {bold('Score:')} {grade_str}")
    if passed:
        print(f"  {green('PASS')} (threshold: {pass_threshold})")
    else:
        if has_blocking:
            print(f"  {red('FAIL')} (blocking errors — {hg_errors} error(s))")
        else:
            print(f"  {red('FAIL')} (below threshold: {pass_threshold})")
    print()

    print(f"  {'Pillar':<24}  {'Score':<8}  Weight")
    print(f"  {'────────────────────':<24}  {'──────':<8}  ──────")
    print(f"  {'Structure (AgentLinter)':<24}  {score_color(pill_s)}  {eff_st}%")
    if pill_q not in ("N/A", None):
        print(f"  {'Quality (PromptLint)':<24}  {score_color(pill_q)}  {eff_ql}%")
    else:
        print(f"  {'Quality (PromptLint)':<24}  {dim('skipped')}  —")
    print(f"  {'Consistency (Home-Grow)':<24}  {score_color(pill_co)}  {eff_co}%")
    if pill_se not in ("N/A", None):
        print(f"  {'Security (Hardener)':<24}  {score_color(pill_se)}  {eff_se}%")
    else:
        print(f"  {'Security (Hardener)':<24}  {dim('skipped')}  —")
    if pill_bu not in ("N/A", None):
        print(f"  {'Token Budget (Length)':<24}  {score_color(pill_bu)}  {eff_bu}%")
    else:
        print(f"  {'Token Budget (Length)':<24}  {dim('N/A')}  —")
    print()

    pl_totals = (data.get("promptlint") or {}).get("totals") or {}
    pl_per = (data.get("promptlint") or {}).get("per_agent") or {}
    total_pl_files = pl_totals.get("files", 0)
    avg_cl = scoring.get("avg_pl_clarity")
    if avg_cl is None:
        avg_cl = pl_totals.get("avg_clarity")
    if avg_cl is None and pl_per:
        clarity_sum = sum(
            float(pa.get("avg_clarity", 0) or 0)
            for pa in pl_per.values()
            if pa.get("avg_clarity") is not None
        )
        n = sum(1 for pa in pl_per.values() if pa.get("avg_clarity") is not None)
        avg_cl = round(clarity_sum / n, 1) if n else 0
    hg = data.get("homegrow") or {}
    hg_p = hg.get("passes", 0)
    hg_i = hg.get("infos", 0)
    hg_w = hg.get("warnings", 0)
    hg_e = hg.get("errors", 0)
    ph_sat = scoring.get("ph_satisfied", 0)
    ph_tot = scoring.get("ph_total", 0)
    budget_tok = scoring.get("budget_total_tokens", 0)
    budget_bud = scoring.get("budget_total_budget", 0)

    print(dim(f"  Quality = clarity {avg_cl}/10 (avg across {total_pl_files} files)"))
    print()
    print(dim(f"  Consistency = {hg_p} pass / {hg_i} info / {hg_w} warn / {hg_e} err"))
    print()
    if pill_se not in ("N/A", None) and ph_tot > 0:
        avg_sat = round(ph_sat / ph_tot, 1)
        print(dim(f"  Security = avg {avg_sat}/10 across {ph_tot} checks"))
        print()
    if pill_bu not in ("N/A", None) and budget_bud > 0:
        pct = round(budget_tok / budget_bud * 100, 1)
        print(dim(f"  Token Budget = {budget_tok}/{budget_bud} tokens ({pct}% of capacity)"))
        print()

    # Per-agent breakdown (multi-agent only)
    if len(agents) > 1:
        al_scores = (data.get("agentlinter") or {}).get("scores") or {}
        pl_per = (data.get("promptlint") or {}).get("per_agent") or {}
        budget_per = (data.get("budget") or {}).get("per_agent") or {}
        print(f"  {'Agent':<16}  {'Struct.':<10}  {'Quality':<10}  {'Consist.':<10}  {'Security':<10}  {'Budget':<10}")
        print(f"  {'────────────':<16}  {'────────':<10}  {'────────':<10}  {'────────':<10}  {'────────':<10}  {'────────':<10}")
        for agent in agents:
            al_s = al_scores.get(agent, "—")
            pl_pa = pl_per.get(agent) or {}
            pl_overall = "—"
            avg_cl = pl_pa.get("avg_clarity")
            if avg_cl is not None:
                pl_overall = f"{float(avg_cl) * 10:.1f}"
            bu_pa = budget_per.get(agent) or {}
            bu_s = bu_pa.get("avg", "—")
            if bu_s is not None and bu_s != "—":
                bu_s = str(bu_s)
            print(f"  {agent:<16}  {str(al_s):<10}  {pl_overall:<10}  {'—':<10}  {'—':<10}  {str(bu_s):<10}")
        print()


def _footer(meta: dict, log_path: str | None) -> None:
    print()
    commit = meta.get("git_commit", "unknown")
    branch = meta.get("git_branch", "unknown")
    run_id = meta.get("run_id", "")
    print(dim(f"  commit: {commit} ({branch}) | run: {run_id}"))
    print()
    if log_path:
        print(dim(f"  Log: {log_path}"))
        print()


def display(summary_path: str, log_path: str | None = None) -> int:
    """Read summary.json and print full terminal report. Returns exit code."""
    path = Path(summary_path)
    if not path.exists():
        print(red(f"Summary file not found: {summary_path}"), file=sys.stderr)
        return 1
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(red(f"Failed to read summary: {e}"), file=sys.stderr)
        return 1

    meta = data.get("meta") or {}
    agents = meta.get("agents_list") or []

    _header(meta)
    _section_agentlinter(data, agents)
    _section_promptlint(data, agents)
    _section_homegrow(data)
    _section_budget(data, agents)
    _section_hardener(data, agents, meta)
    _section_combined(data, agents)
    _footer(meta, log_path)

    passed = (data.get("scoring") or {}).get("passed", True)
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Display megalint results from summary.json")
    parser.add_argument("--summary", required=True, help="Path to summary.json")
    parser.add_argument("--log-file", help="Path to log file (shown in footer)")
    args = parser.parse_args()
    return display(args.summary, args.log_file)


if __name__ == "__main__":
    sys.exit(main())
