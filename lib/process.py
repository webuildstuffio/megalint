#!/usr/bin/env python3
"""Megalint process layer — parses all tool outputs, computes scores, writes summary.json.

Supports three modes:
  - agents:  OpenClaw MDS workspaces (AGENTS.md, SOUL.md, etc.)
  - skills:  Skill directories (SKILL.md + supporting files)
  - prompts: Individual .md prompt files

Reads tool outputs from tmp_dir, runs scoring, writes tmp_dir/summary.json.
"""

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Optional

# Ensure lib is importable
_SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from lib.config import load_config, Config, LOAD_WEIGHTS, STANDARD_FILES, Mode  # noqa: E402


def _get_standard_files(mode: Mode = "agents") -> tuple[str, ...]:
    """Return expected file list for a given mode."""
    return STANDARD_FILES.get(mode, STANDARD_FILES["agents"])


def _get_load_weights(mode: Mode = "agents") -> dict[str, int]:
    """Return load frequency weights for a given mode."""
    return LOAD_WEIGHTS.get(mode, LOAD_WEIGHTS["agents"])


def _discover_md_files(item_dir: str, mode: Mode = "agents") -> list[str]:
    """Discover .md files to lint in a directory based on mode.

    agents: only STANDARD_FILES
    skills: SKILL.md + all other .md files found
    prompts: all .md files
    """
    if mode == "agents":
        return list(_get_standard_files("agents"))

    found = []
    if not os.path.isdir(item_dir):
        return found
    for f in sorted(os.listdir(item_dir)):
        if f.endswith(".md"):
            found.append(f)

    if mode == "skills":
        # SKILL.md first, then others
        if "SKILL.md" in found:
            found.remove("SKILL.md")
            found.insert(0, "SKILL.md")
    return found


def process_agentlinter(al_dir: str, agents: List[str]) -> Dict[str, Any]:
    """Parse AgentLinter JSON outputs. Returns dict with scores, per_agent (score, categories, diagnostics)."""
    result: Dict[str, Any] = {"scores": {}, "per_agent": {}}
    if not os.path.isdir(al_dir):
        return result

    for agent in agents:
        al_file = os.path.join(al_dir, f"{agent}.json")
        if not os.path.isfile(al_file):
            continue
        try:
            with open(al_file) as f:
                d = json.load(f)
        except (json.JSONDecodeError, OSError):
            result["scores"][agent] = 0
            result["per_agent"][agent] = {
                "score": 0,
                "categories": [],
                "diagnostics": [],
            }
            continue

        score = d.get("score", 0)
        diags = d.get("diagnostics", [])
        cats = d.get("categories", [])

        result["scores"][agent] = score
        agent_warnings = sum(1 for x in diags if x.get("severity") == "warning" and x.get("file") != "(workspace)")
        result["per_agent"][agent] = {
            "score": score,
            "agent_warnings": agent_warnings,
            "categories": [
                {"name": c.get("name", ""), "score": c.get("score", 0)}
                for c in cats
            ],
            "diagnostics": [
                {
                    "severity": x.get("severity", ""),
                    "file": x.get("file", ""),
                    "line": x.get("line"),
                    "message": (x.get("message", "") or "")[:120],
                    "fix": (x.get("fix", "") or "")[:100],
                    "rule": x.get("rule", ""),
                }
                for x in diags
                if x.get("severity") in ("critical", "error", "warning")
            ],
        }
    return result


def process_promptlint(pl_dir: str, items: List[str], mode: Mode = "agents") -> Dict[str, Any]:
    """Parse PromptLint JSON outputs. Returns per-item per-file scores (clarity, security, cost, overall)."""
    result: Dict[str, Any] = {"per_agent": {}, "totals": {"clarity": 0.0, "security": 0.0, "cost": 0.0, "files": 0}}
    if not os.path.isdir(pl_dir):
        return result

    total_clarity = total_security = total_cost = total_files = 0

    for item in items:
        item_dir = os.path.join(pl_dir, item)
        if not os.path.isdir(item_dir):
            continue
        files_data: Dict[str, Dict[str, float]] = {}
        item_clarity = item_security = item_cost = file_count = 0.0

        # Discover which json files exist (mode-aware)
        available_jsons = sorted(os.listdir(item_dir)) if os.path.isdir(item_dir) else []
        for jf_name in available_jsons:
            if not jf_name.endswith(".json"):
                continue
            jf = os.path.join(item_dir, jf_name)
            fname = jf_name.replace(".json", "")
            try:
                with open(jf) as f:
                    d = json.load(f)
            except (json.JSONDecodeError, OSError):
                continue
            if d.get("_error"):
                continue

            scores = d.get("scores", {})
            clarity = float(scores.get("clarity", 0))
            security = float(scores.get("security", 0))
            cost = float(scores.get("cost_efficiency", 0))
            overall = float(scores.get("overall", 0))

            files_data[fname] = {"clarity": clarity, "security": security, "cost": cost, "overall": overall}
            item_clarity += clarity
            item_security += security
            item_cost += cost
            file_count += 1
            total_clarity += clarity
            total_security += security
            total_cost += cost
            total_files += 1

        result["per_agent"][item] = {"files": files_data}
        if file_count > 0:
            result["per_agent"][item]["avg_clarity"] = round(item_clarity / file_count, 1)
            result["per_agent"][item]["avg_security"] = round(item_security / file_count, 1)
            result["per_agent"][item]["avg_cost"] = round(item_cost / file_count, 1)

    result["totals"]["clarity"] = round(total_clarity, 1)
    result["totals"]["security"] = round(total_security, 1)
    result["totals"]["cost"] = round(total_cost, 1)
    result["totals"]["files"] = int(total_files)
    return result


def process_homegrow(hg_dir: str) -> Dict[str, Any]:
    """Parse Home-Grow results.txt (STATUS|context|message lines). Returns passes, infos, warnings, errors, checks."""
    result: Dict[str, Any] = {"passes": 0, "infos": 0, "warnings": 0, "errors": 0, "checks": []}
    results_file = os.path.join(hg_dir, "results.txt")
    if not os.path.isfile(results_file):
        return result

    try:
        with open(results_file) as f:
            lines = f.read().splitlines()
    except OSError:
        return result

    for line in lines:
        line = line.strip()
        if not line:
            continue
        parts = line.split("|", 2)
        status = parts[0].strip() if len(parts) > 0 else ""
        context = parts[1].strip() if len(parts) > 1 else ""
        message = parts[2].strip() if len(parts) > 2 else ""

        check = {"status": status, "context": context, "message": message}
        result["checks"].append(check)

        if status == "OK":
            result["passes"] += 1
        elif status == "INFO":
            result["infos"] += 1
        elif status == "WARN":
            result["warnings"] += 1
        elif status == "ERROR":
            result["errors"] += 1

    return result


def process_hardener(ph_dir: str, agents: List[str], hardener_ran: bool) -> Optional[Dict[str, Any]]:
    """Parse Prompt Hardener eval JSONs. Returns per_agent data (with full eval for report), actual_tokens_in/out. None if not ran."""
    if not hardener_ran or not ph_dir or not os.path.isdir(ph_dir):
        return None

    result: Dict[str, Any] = {
        "ran": True,
        "per_agent": {},
        "eval_per_agent": {},  # full eval JSON per agent for report
        "actual_tokens_in": 0,
        "actual_tokens_out": 0,
        "ph_satisfied": 0,
        "ph_total": 0,
    }
    RSE_CATEGORY_NAMES = {"random_sequence_enclosure", "rse", "random sequence enclosure"}

    for agent in agents:
        eval_file = os.path.join(ph_dir, f"{agent}_eval.json")
        if not os.path.isfile(eval_file):
            continue
        try:
            with open(eval_file) as f:
                d = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue

        result["eval_per_agent"][agent] = d
        usage = d.get("_usage", {})
        ti = usage.get("input_tokens", 0)
        to = usage.get("output_tokens", 0)
        result["actual_tokens_in"] += ti
        result["actual_tokens_out"] += to

        agent_satisfied = 0
        agent_total = 0
        for cat_key, cat_val in d.items():
            if not isinstance(cat_val, dict):
                continue
            cat_name = cat_key.lower().replace("-", "_").replace(" ", "_")
            is_rse = cat_name in RSE_CATEGORY_NAMES
            for check_val in cat_val.values():
                if isinstance(check_val, dict) and "satisfaction" in check_val:
                    if is_rse:
                        continue
                    agent_satisfied += int(check_val["satisfaction"])
                    agent_total += 1

        result["per_agent"][agent] = {
            "satisfied": agent_satisfied,
            "total": agent_total,
            "tokens_in": ti,
            "tokens_out": to,
        }
        result["ph_satisfied"] += agent_satisfied
        result["ph_total"] += agent_total

    return result


def process_budgets(item_dirs: Dict[str, str], config: Config, shared_dir: str = "") -> Dict[str, Any]:
    """Compute per-file token budget scores using tiktoken_count and config.budgets.

    In skills/prompts mode, also scores any .md files without explicit budgets
    using a default budget (3000 tokens for skills, 5000 for prompts).
    """
    result: Dict[str, Any] = {"per_agent": {}, "fleet_avg": 0.0}

    try:
        from lib.tiktoken_count import count_file
    except ImportError:
        def count_file(path: str, expand_imports=None) -> int:
            with open(path) as f:
                words = len(f.read().split())
            return (words * 13 + 9) // 10

    def score_file(tokens: int, budget: int) -> float:
        if budget <= 0:
            return 100.0
        if tokens <= budget:
            return 100.0
        over = tokens - budget
        headroom = budget * 4
        return max(0.0, round(100.0 * (1.0 - over / headroom), 1))

    mode = config.mode
    load_weights = _get_load_weights(mode)
    default_budget = {"skills": 3000, "prompts": 5000}.get(mode, 0)

    item_avgs = []
    for item, item_dir in item_dirs.items():
        if not os.path.isdir(item_dir):
            continue
        files_data: Dict[str, Dict[str, Any]] = {}

        # For skills/prompts: discover all .md files and score them
        if mode in ("skills", "prompts"):
            md_files = _discover_md_files(item_dir, mode)
            for fname in md_files:
                fpath = os.path.join(item_dir, fname)
                if not os.path.exists(fpath):
                    continue
                budget = config.budgets.get(fname, default_budget)
                tokens = count_file(fpath, shared_dir if shared_dir else None)
                sc = score_file(tokens, budget)
                pct = round(tokens / budget * 100) if budget > 0 else 0
                w = load_weights.get(fname, 1)
                files_data[fname] = {
                    "tokens": tokens,
                    "budget": budget,
                    "score": sc,
                    "pct": pct,
                    "weight": w,
                }
        else:
            # Agents mode: only budgeted files
            for fname, budget in config.budgets.items():
                fpath = os.path.join(item_dir, fname)
                if not os.path.exists(fpath):
                    continue
                tokens = count_file(fpath, shared_dir if shared_dir else None)
                sc = score_file(tokens, budget)
                pct = round(tokens / budget * 100) if budget > 0 else 0
                w = load_weights.get(fname, 1)
                files_data[fname] = {
                    "tokens": tokens,
                    "budget": budget,
                    "score": sc,
                    "pct": pct,
                    "weight": w,
                }
        if not files_data:
            continue
        weighted_sum = sum(f["score"] * f["weight"] for f in files_data.values())
        total_weight = sum(f["weight"] for f in files_data.values())
        avg = round(weighted_sum / total_weight, 1) if total_weight > 0 else 0.0
        freq_map = {3: "×msg", 2: "×hb", 1: "×dm"}
        files_list = []
        for fname, fd in files_data.items():
            sc = fd.get("score", 0)
            bar_len = max(0, min(10, int(sc / 10)))
            bar = "█" * bar_len + "░" * (10 - bar_len)
            level = "OK" if sc >= 88 else ("INFO" if sc >= 75 else ("WARN" if sc >= 50 else "ERROR"))
            freq = freq_map.get(fd.get("weight", 1), "")
            files_list.append({
                "fname": fname,
                "tokens": fd["tokens"],
                "budget": fd["budget"],
                "score": sc,
                "pct": fd["pct"],
                "weight": fd.get("weight", 1),
                "bar": bar,
                "level": level,
                "freq": freq,
            })
        result["per_agent"][item] = {"files": files_list, "avg": avg, "files_raw": files_data}
        item_avgs.append(avg)

    if item_avgs:
        result["fleet_avg"] = round(sum(item_avgs) / len(item_avgs), 1)
    return result


def process_all(
    tmp_dir: str,
    config_path: str = "",
    hardener_ran: bool = False,
    pass_threshold_override: Optional[int] = None,
    blocking_errors_override: Optional[bool] = None,
    mode: Mode = "agents",
) -> Dict[str, Any]:
    """Main orchestrator: read meta, run all processors, call scoring, return full summary dict."""
    meta_file = os.path.join(tmp_dir, "meta.json")
    if not os.path.isfile(meta_file):
        raise FileNotFoundError(f"meta.json not found in {tmp_dir}")

    with open(meta_file) as f:
        meta = json.load(f)

    # Support mode from meta.json (set by megalint.sh)
    mode = meta.get("mode", mode)
    agents = meta.get("agents_list", [])
    agent_dirs = meta.get("agent_dirs", {})
    if not agents and agent_dirs:
        agents = list(agent_dirs.keys())
    if not agent_dirs:
        agent_dirs = meta.get("agent_dirs", {})

    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config = load_config(
        megalint_conf=config_path or os.path.join(script_dir, "megalint.conf"),
        rules_conf=os.path.join(script_dir, "apps", "homegrow", "rules.conf"),
        script_dir=script_dir,
        mode=mode,
    )

    al_dir = os.path.join(tmp_dir, "agentlinter")
    pl_dir = os.path.join(tmp_dir, "promptlint")
    hg_dir = os.path.join(tmp_dir, "homegrow")
    ph_dir = os.path.join(tmp_dir, "hardener")

    agentlinter = process_agentlinter(al_dir, agents)
    promptlint = process_promptlint(pl_dir, agents, mode)
    homegrow = process_homegrow(hg_dir)
    shared_dir = meta.get("shared_dir", os.path.join(script_dir, "..", "..", "src", "shared"))
    budget = process_budgets(agent_dirs, config, shared_dir)
    hardener = process_hardener(ph_dir, agents, hardener_ran)

    # Build metrics for scoring
    agent_count = len([a for a in agents if agentlinter["scores"].get(a) is not None])
    total_al = sum(agentlinter["scores"].get(a, 0) for a in agents)
    pl_totals = promptlint.get("totals", {})
    total_pl_clarity = pl_totals.get("clarity", 0)
    total_pl_security = pl_totals.get("security", 0)
    total_pl_cost = pl_totals.get("cost", 0)
    total_pl_files = pl_totals.get("files", 0)
    total_pl_failures = 0  # Could be tracked if PL reports _error

    # For scoring, pass raw files dict (agent -> {files: {fname: {score, weight, tokens, budget}}})
    budget_for_scoring = {}
    for agent, ad in budget.get("per_agent", {}).items():
        raw = ad.get("files_raw")  # files_raw is the dict; files is the display list
        if raw is None:
            raw = ad.get("files")
        if isinstance(raw, dict):
            budget_for_scoring[agent] = {"files": raw}
        elif isinstance(raw, list):
            files_dict = {
                f["fname"]: {
                    "score": f["score"],
                    "weight": f.get("weight", 1),
                    "tokens": f["tokens"],
                    "budget": f["budget"],
                }
                for f in raw
            }
            budget_for_scoring[agent] = {"files": files_dict}
    if not budget_for_scoring:
        budget_for_scoring = budget.get("per_agent") or {}

    metrics = {
        "agent_count": agent_count,
        "total_al_score": total_al,
        "total_pl_clarity": total_pl_clarity,
        "total_pl_security": total_pl_security,
        "total_pl_cost": total_pl_cost,
        "total_pl_files": total_pl_files,
        "total_pl_failures": total_pl_failures,
        "hg_passes": homegrow.get("passes", 0),
        "hg_infos": homegrow.get("infos", 0),
        "hg_warnings": homegrow.get("warnings", 0),
        "hg_errors": homegrow.get("errors", 0),
        "hardener_ran": hardener_ran,
        "ph_dir": ph_dir,
        "weight_structure": config.weight_structure,
        "weight_quality": config.weight_quality,
        "weight_consistency": config.weight_consistency,
        "weight_security": config.weight_security,
        "weight_budget": config.weight_budget,
        "pass_threshold": pass_threshold_override if pass_threshold_override is not None else config.pass_threshold,
        "blocking_errors": blocking_errors_override if blocking_errors_override is not None else config.blocking_errors,
        "grades": config.grades,
        "budget_data": budget_for_scoring,
    }
    if hardener and hardener.get("ph_satisfied") is not None and hardener.get("ph_total") is not None:
        metrics["ph_satisfied"] = hardener["ph_satisfied"]
        metrics["ph_total"] = hardener["ph_total"]

    from lib.scoring import compute_scores

    raw_scoring = compute_scores(metrics, config)

    # Normalize to summary schema (lowercase keys for display/report)
    key_map = {
        "PILLAR_STRUCTURE": "pillar_structure",
        "PILLAR_QUALITY": "pillar_quality",
        "PILLAR_CONSISTENCY": "pillar_consistency",
        "PILLAR_SECURITY": "pillar_security",
        "PILLAR_BUDGET": "pillar_budget",
        "PH_SATISFIED": "ph_satisfied",
        "PH_TOTAL": "ph_total",
        "AVG_PL_CLARITY": "avg_pl_clarity",
        "AVG_PL_SECURITY": "avg_pl_security",
        "AVG_PL_COST": "avg_pl_cost",
        "BUDGET_TOTAL_TOKENS": "budget_total_tokens",
        "BUDGET_TOTAL_BUDGET": "budget_total_budget",
        "COMBINED": "combined",
        "GRADE": "grade",
        "PASSED": "passed",
        "HAS_BLOCKING": "has_blocking",
    }
    scoring = {}
    for k, v in raw_scoring.items():
        scoring[key_map.get(k, k)] = v

    # Build budget totals for scoring output
    budget_total_tokens = 0
    budget_total_budget = 0
    for ad in budget.get("per_agent", {}).values():
        files = ad.get("files_raw") or ad.get("files", {})
        if isinstance(files, dict):
            items = files.values()
        elif isinstance(files, list):
            items = files
        else:
            items = ()
        for fd in items:
            budget_total_tokens += fd.get("tokens", 0)
            budget_total_budget += fd.get("budget", 0)

    scoring_dict = dict(scoring)
    scoring_dict["budget_total_tokens"] = budget_total_tokens
    scoring_dict["budget_total_budget"] = budget_total_budget
    scoring_dict["pass_threshold"] = config.pass_threshold
    scoring_dict["weights"] = {
        "structure": config.weight_structure,
        "quality": config.weight_quality,
        "consistency": config.weight_consistency,
        "security": config.weight_security,
        "budget": config.weight_budget,
    }

    summary_meta = {
        "run_id": meta.get("run_id", ""),
        "git_commit": meta.get("git_commit", ""),
        "git_branch": meta.get("git_branch", ""),
        "git_dirty": meta.get("git_dirty", False),
        "git_msg": meta.get("git_msg", ""),
        "timestamp": meta.get("timestamp", ""),
        "agents_list": agents,
        "mode": mode,
        "disabled_rules": meta.get("disabled_rules", ""),
        "preset": meta.get("preset", ""),
        "quiet": meta.get("quiet", False),
    }
    if hardener:
        summary_meta["hardener_tokens_in"] = hardener.get("actual_tokens_in", 0)
        summary_meta["hardener_tokens_out"] = hardener.get("actual_tokens_out", 0)
    summary = {
        "meta": summary_meta,
        "agentlinter": agentlinter,
        "promptlint": promptlint,
        "homegrow": homegrow,
        "budget": budget,
        "hardener": hardener,
        "scoring": scoring_dict,
    }

    summary_path = os.path.join(tmp_dir, "summary.json")
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)

    return summary


def main():
    parser = argparse.ArgumentParser(description="Process megalint tool outputs into summary.json")
    parser.add_argument("--tmp-dir", required=True, help="Temporary directory with tool outputs and meta.json")
    parser.add_argument("--config", default="", help="Path to megalint.conf (optional)")
    parser.add_argument("--hardener-ran", default="false", choices=("true", "false"), help="Whether Prompt Hardener ran")
    parser.add_argument("--pass-threshold", type=int, default=None, help="Override pass threshold (optional)")
    parser.add_argument("--no-blocking", action="store_true", help="Override blocking_errors to false")
    parser.add_argument("--mode", default="agents", choices=("agents", "skills", "prompts"), help="Linting mode")
    args = parser.parse_args()

    hardener_ran = args.hardener_ran.lower() == "true"
    blocking_override = False if args.no_blocking else None
    process_all(
        args.tmp_dir,
        config_path=args.config or "",
        hardener_ran=hardener_ran,
        pass_threshold_override=args.pass_threshold,
        blocking_errors_override=blocking_override,
        mode=args.mode,
    )


if __name__ == "__main__":
    main()
