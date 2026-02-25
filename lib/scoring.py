#!/usr/bin/env python3
"""Megalint scoring engine — computes 5-pillar weighted score from tool results.

Pillars:
  1. Structure    (AgentLinter)     — 0-100 from AgentLinter's weighted category scores
  2. Quality      (PromptLint)       — 0-100, converted from PromptLint's per-file 0-10 scores
  3. Consistency  (Home-Grow)       — 0-100, weighted pass rate across convention checks
  4. Security     (Prompt Hardener) — 0-100, weighted satisfaction across LLM-judged techniques
  5. Token Budget (per-file length) — 0-100, linear scoring: 100 at budget → 0 at 5× budget

All pillars output on the same 0-100 scale with 1-decimal precision.
Combined score = weighted average of active pillars (skipped pillars redistribute weight).

Input:  JSON file with raw metrics (--input path)
Output: KEY=VAL pairs to stdout for bash consumption
"""

import json
import os
import sys

RSE_CATEGORY_NAMES = {"random_sequence_enclosure", "rse", "random sequence enclosure"}


def _ensure_grades(grades) -> list[tuple[int, str]]:
    """Ensure grades is a list of (int, str) tuples."""
    if not grades:
        return [
            (97, "S"), (95, "A+"), (93, "A"), (90, "A-"), (87, "B+"), (83, "B"),
            (80, "B-"), (77, "C+"), (73, "C"), (70, "C-"), (60, "D"),
        ]
    out = []
    for g in grades:
        if isinstance(g, (list, tuple)) and len(g) >= 2:
            out.append((int(g[0]), str(g[1])))
        elif isinstance(g, dict) and "0" in g and "1" in g:
            out.append((int(g["0"]), str(g["1"])))
    if out:
        out.sort(key=lambda x: -x[0])
        return out
    return [
        (97, "S"), (95, "A+"), (93, "A"), (90, "A-"), (87, "B+"), (83, "B"),
        (80, "B-"), (77, "C+"), (73, "C"), (70, "C-"), (60, "D"),
    ]


def compute_scores(metrics_dict: dict, config=None) -> dict:
    """Compute all pillar scores and combined result. Returns dict with keys:
    pillar_structure, pillar_quality, pillar_consistency, pillar_security, pillar_budget,
    ph_satisfied, ph_total, avg_pl_clarity, avg_pl_security, avg_pl_cost,
    budget_total_tokens, budget_total_budget, combined, grade, passed, has_blocking,
    budget_per_agent.

    Supports budget_data (inline dict) and ph_satisfied/ph_total (pre-computed).
    When config is None, uses defaults for weights/thresholds.
    """
    m = metrics_dict

    agent_count = m.get("agent_count", 0)
    total_al = m.get("total_al_score", 0)
    total_pl_clarity = m.get("total_pl_clarity", 0.0)
    total_pl_security = m.get("total_pl_security", 0.0)
    total_pl_cost = m.get("total_pl_cost", 0.0)
    total_pl_files = m.get("total_pl_files", 0)
    hg_passes = m.get("hg_passes", 0)
    hg_infos = m.get("hg_infos", 0)
    hg_warnings = m.get("hg_warnings", 0)
    hg_errors = m.get("hg_errors", 0)
    hardener_ran = m.get("hardener_ran", False)
    ph_dir = m.get("ph_dir", "")
    ph_satisfied_pre = m.get("ph_satisfied")
    ph_total_pre = m.get("ph_total")

    def _cfg(k, default):
        return m.get(k) if k in m and m[k] is not None else (getattr(config, k, default) if config else default)

    w_st = _cfg("weight_structure", 25)
    w_ql = _cfg("weight_quality", 18)
    w_co = _cfg("weight_consistency", 22)
    w_se = _cfg("weight_security", 20)
    w_bu = _cfg("weight_budget", 15)
    pass_thr = _cfg("pass_threshold", 70)
    blocking = _cfg("blocking_errors", True)
    grades = _ensure_grades(m.get("grades") or (config.grades if config else None))

    # Pillar 1: Structure (AgentLinter) — already 0-100, average across agents
    pillar_structure = round(total_al / max(agent_count, 1), 1)

    # Pillar 2: Quality (PromptLint) = clarity score only, scaled to 0-100
    total_pl_failures = m.get("total_pl_failures", 0)
    pl_tool_broken = total_pl_files > 0 and total_pl_failures == total_pl_files
    if pl_tool_broken:
        avg_cl = avg_se = avg_co = 0.0
        pillar_quality = None
    elif total_pl_files > 0:
        avg_cl = round(total_pl_clarity / total_pl_files, 1)
        avg_se = round(total_pl_security / total_pl_files, 1)
        avg_co = round(total_pl_cost / total_pl_files, 1)
        pillar_quality = round(avg_cl * 10, 1)
    else:
        avg_cl = avg_se = avg_co = 0.0
        pillar_quality = None

    # Pillar 3: Consistency (Home-Grow) — weighted pass rate
    total_checks = hg_passes + hg_infos + hg_warnings + hg_errors
    if total_checks > 0:
        weighted = (hg_passes * 1.0 + hg_infos * 0.75 + hg_warnings * 0.5) / total_checks
        pillar_consistency = round(weighted * 100, 1)
    else:
        pillar_consistency = 100.0

    # Pillar 4: Security (Prompt Hardener)
    pillar_security = None
    ph_satisfied = 0
    ph_total = 0
    if ph_satisfied_pre is not None and ph_total_pre is not None and hardener_ran:
        ph_satisfied = ph_satisfied_pre
        ph_total = ph_total_pre
        if ph_total > 0:
            pillar_security = round((ph_satisfied / (ph_total * 10)) * 100, 1)
    elif hardener_ran and ph_dir and os.path.isdir(ph_dir):
        for fn in os.listdir(ph_dir):
            if not fn.endswith("_eval.json"):
                continue
            try:
                with open(os.path.join(ph_dir, fn)) as f:
                    d = json.load(f)
                for cat_key, cat_val in d.items():
                    if not isinstance(cat_val, dict):
                        continue
                    cat_name = cat_key.lower().replace("-", "_").replace(" ", "_")
                    is_rse = cat_name in RSE_CATEGORY_NAMES
                    for check_val in cat_val.values():
                        if isinstance(check_val, dict) and "satisfaction" in check_val:
                            if is_rse:
                                continue
                            sat = int(check_val["satisfaction"])
                            ph_total += 1
                            ph_satisfied += sat
            except (json.JSONDecodeError, OSError, ValueError):
                pass
        if ph_total > 0:
            pillar_security = round((ph_satisfied / (ph_total * 10)) * 100, 1)

    # Pillar 5: Token Budget — per-file length scoring
    pillar_budget = None
    budget_data_path = m.get("budget_data_path", "")
    budget_data_inline = m.get("budget_data")
    budget_per_agent = {}
    budget_total_tokens = 0
    budget_total_budget = 0
    bd = budget_data_inline if isinstance(budget_data_inline, dict) else None
    if bd is None and budget_data_path and os.path.isfile(budget_data_path):
        try:
            with open(budget_data_path) as f:
                bd = json.load(f)
        except (json.JSONDecodeError, OSError):
            bd = None
    if bd:
        agent_avgs = []
        for agent_name, agent_data in bd.items():
            files = agent_data.get("files", {})
            if not files:
                continue
            weighted_sum = 0.0
            total_w = 0
            for fname, fd in files.items():
                w = fd.get("weight", 1)
                weighted_sum += fd["score"] * w
                total_w += w
                budget_total_tokens += fd["tokens"]
                budget_total_budget += fd["budget"]
            agent_avg = weighted_sum / total_w if total_w > 0 else 0.0
            budget_per_agent[agent_name] = round(agent_avg, 1)
            agent_avgs.append(agent_avg)
        if agent_avgs:
            pillar_budget = round(sum(agent_avgs) / len(agent_avgs), 1)

    # Weighted combination
    active_pillars = {
        "structure": (pillar_structure, w_st),
        "consistency": (pillar_consistency, w_co),
    }
    if pillar_quality is not None:
        active_pillars["quality"] = (pillar_quality, w_ql)
    if pillar_security is not None:
        active_pillars["security"] = (pillar_security, w_se)
    if pillar_budget is not None and w_bu > 0:
        active_pillars["budget"] = (pillar_budget, w_bu)

    total_weight = sum(w for _, w in active_pillars.values())
    combined = round(
        sum(s * w for s, w in active_pillars.values()) / max(total_weight, 1), 1
    )

    # Grade
    grade = "F"
    for thr, g in grades:
        if combined >= thr:
            grade = g
            break

    # Pass/fail
    has_blocking = blocking and hg_errors > 0
    passed = combined >= pass_thr and not has_blocking

    return {
        "PILLAR_STRUCTURE": pillar_structure,
        "PILLAR_QUALITY": pillar_quality,
        "PILLAR_CONSISTENCY": pillar_consistency,
        "PILLAR_SECURITY": pillar_security,
        "PILLAR_BUDGET": pillar_budget,
        "PH_SATISFIED": ph_satisfied,
        "PH_TOTAL": ph_total,
        "AVG_PL_CLARITY": avg_cl,
        "AVG_PL_SECURITY": avg_se,
        "AVG_PL_COST": avg_co,
        "BUDGET_TOTAL_TOKENS": budget_total_tokens,
        "BUDGET_TOTAL_BUDGET": budget_total_budget,
        "COMBINED": combined,
        "GRADE": grade,
        "PASSED": passed,
        "HAS_BLOCKING": has_blocking,
        "budget_per_agent": budget_per_agent,
    }


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "--input":
        print("Usage: scoring.py --input <metrics.json>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[2]) as f:
        m = json.load(f)

    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if script_dir not in sys.path:
        sys.path.insert(0, script_dir)
    from lib.config import load_config

    config = load_config(script_dir=script_dir)

    scores = compute_scores(m, config)

    print(f"PILLAR_STRUCTURE={scores['PILLAR_STRUCTURE']}")
    print(f"PILLAR_QUALITY={scores['PILLAR_QUALITY'] if scores['PILLAR_QUALITY'] is not None else 'N/A'}")
    print(f"PILLAR_CONSISTENCY={scores['PILLAR_CONSISTENCY']}")
    print(f"PILLAR_SECURITY={scores['PILLAR_SECURITY'] if scores['PILLAR_SECURITY'] is not None else 'N/A'}")
    print(f"PILLAR_BUDGET={scores['PILLAR_BUDGET'] if scores['PILLAR_BUDGET'] is not None else 'N/A'}")
    print(f"PH_SATISFIED={scores['PH_SATISFIED']}")
    print(f"PH_TOTAL={scores['PH_TOTAL']}")
    print(f"AVG_PL_CLARITY={scores['AVG_PL_CLARITY']}")
    print(f"AVG_PL_SECURITY={scores['AVG_PL_SECURITY']}")
    print(f"AVG_PL_COST={scores['AVG_PL_COST']}")
    print(f"BUDGET_TOTAL_TOKENS={scores['BUDGET_TOTAL_TOKENS']}")
    print(f"BUDGET_TOTAL_BUDGET={scores['BUDGET_TOTAL_BUDGET']}")
    print(f"COMBINED={scores['COMBINED']}")
    print(f"GRADE={scores['GRADE']}")
    print(f"PASSED={'true' if scores['PASSED'] else 'false'}")
    print(f"HAS_BLOCKING={'true' if scores['HAS_BLOCKING'] else 'false'}")

    for agent, sc in scores.get("budget_per_agent", {}).items():
        safe_name = agent.replace("-", "_").replace(" ", "_")
        print(f"BUDGET_AGENT_{safe_name}={sc}")


if __name__ == "__main__":
    main()
