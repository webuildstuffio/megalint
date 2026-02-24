#!/usr/bin/env python3
"""Megalint scoring engine — computes 5-pillar weighted score from tool results.

Pillars:
  1. Structure    (AgentLinter)     — 0-100 from AgentLinter's weighted category scores
  2. Quality      (PromptLint)      — 0-100, converted from PromptLint's per-file 0-10 scores
  3. Consistency  (Home-Grow)       — 0-100, weighted pass rate across convention checks
  4. Security     (Prompt Hardener) — 0-100, weighted satisfaction across LLM-judged techniques
  5. Token Budget (per-file length) — 0-100, linear scoring: 100 at budget → 0 at 3× budget

All pillars output on the same 0-100 scale with 1-decimal precision.
Combined score = weighted average of active pillars (skipped pillars redistribute weight).

Input:  JSON file with raw metrics (--input path)
Output: KEY=VAL pairs to stdout for bash consumption
"""

import json
import os
import sys


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "--input":
        print("Usage: scoring.py --input <metrics.json>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[2]) as f:
        m = json.load(f)

    agent_count = m["agent_count"]
    total_al = m["total_al_score"]
    total_pl_clarity = m["total_pl_clarity"]
    total_pl_security = m["total_pl_security"]
    total_pl_cost = m["total_pl_cost"]
    total_pl_files = m["total_pl_files"]
    hg_passes = m["hg_passes"]
    hg_infos = m.get("hg_infos", 0)
    hg_warnings = m["hg_warnings"]
    hg_errors = m["hg_errors"]
    hardener_ran = m["hardener_ran"]
    ph_dir = m["ph_dir"]

    w_st = m["weight_structure"]
    w_ql = m["weight_quality"]
    w_co = m["weight_consistency"]
    w_se = m["weight_security"]
    w_bu = m.get("weight_budget", 0)
    pass_thr = m["pass_threshold"]
    blocking = m["blocking_errors"]
    grades = m["grades"]

    # Pillar 1: Structure (AgentLinter) — already 0-100, average across agents
    pillar_structure = round(total_al / max(agent_count, 1), 1)

    # Pillar 2: Quality (PromptLint) = clarity score only, scaled to 0-100
    # PromptLint security always scores 10/10 for MDS files (it checks for
    # injection patterns IN the text, which config files never contain — real
    # security assessment comes from the Prompt Hardener pillar).
    # PromptLint cost is excluded — the Token Budget pillar handles file-size
    # scoring with per-file budgets, which is more granular.
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
    # OK = 1.0, INFO = 0.75 (minor heads-up), WARN = 0.5 (should fix), ERROR = 0.0
    total_checks = hg_passes + hg_infos + hg_warnings + hg_errors
    if total_checks > 0:
        weighted = (hg_passes * 1.0 + hg_infos * 0.75 + hg_warnings * 0.5) / total_checks
        pillar_consistency = round(weighted * 100, 1)
    else:
        pillar_consistency = 100.0

    # Pillar 4: Security (Prompt Hardener)
    RSE_CATEGORY_NAMES = {"random_sequence_enclosure", "rse", "random sequence enclosure"}
    pillar_security = None
    ph_satisfied = 0
    ph_total = 0
    if hardener_ran and os.path.isdir(ph_dir):
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
                            sat = int(check_val["satisfaction"])
                            if is_rse and sat == 0:
                                continue
                            ph_total += 1
                            ph_satisfied += sat
            except (json.JSONDecodeError, OSError, ValueError):
                pass
        if ph_total > 0:
            pillar_security = round((ph_satisfied / (ph_total * 10)) * 100, 1)

    # Pillar 5: Token Budget — per-file length scoring
    # Scores each file: 100 at/under budget, 0 at 3× budget, linear between
    # Per-agent: average of file scores. Fleet: average of agent averages.
    pillar_budget = None
    budget_data_path = m.get("budget_data_path", "")
    budget_per_agent = {}
    budget_per_file = {}
    budget_total_tokens = 0
    budget_total_budget = 0
    if budget_data_path and os.path.isfile(budget_data_path):
        try:
            with open(budget_data_path) as f:
                bd = json.load(f)
            if bd:
                agent_avgs = []
                for agent_name, agent_data in bd.items():
                    files = agent_data.get("files", {})
                    if not files:
                        continue
                    file_scores = []
                    for fname, fd in files.items():
                        file_scores.append(fd["score"])
                        budget_total_tokens += fd["tokens"]
                        budget_total_budget += fd["budget"]
                        key = f"{agent_name}/{fname}"
                        budget_per_file[key] = fd["score"]
                    agent_avg = sum(file_scores) / len(file_scores)
                    budget_per_agent[agent_name] = round(agent_avg, 1)
                    agent_avgs.append(agent_avg)
                if agent_avgs:
                    pillar_budget = round(sum(agent_avgs) / len(agent_avgs), 1)
        except (json.JSONDecodeError, OSError):
            pass

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

    print(f"PILLAR_STRUCTURE={pillar_structure}")
    print(f"PILLAR_QUALITY={pillar_quality if pillar_quality is not None else 'N/A'}")
    print(f"PILLAR_CONSISTENCY={pillar_consistency}")
    print(f"PILLAR_SECURITY={pillar_security if pillar_security is not None else 'N/A'}")
    print(f"PILLAR_BUDGET={pillar_budget if pillar_budget is not None else 'N/A'}")
    print(f"PH_SATISFIED={ph_satisfied}")
    print(f"PH_TOTAL={ph_total}")
    print(f"AVG_PL_CLARITY={avg_cl}")
    print(f"AVG_PL_SECURITY={avg_se}")
    print(f"AVG_PL_COST={avg_co}")
    print(f"BUDGET_TOTAL_TOKENS={budget_total_tokens}")
    print(f"BUDGET_TOTAL_BUDGET={budget_total_budget}")
    print(f"COMBINED={combined}")
    print(f"GRADE={grade}")
    print(f"PASSED={'true' if passed else 'false'}")
    print(f"HAS_BLOCKING={'true' if has_blocking else 'false'}")

    # Per-agent budget scores for display (sanitize names for bash)
    for agent, sc in budget_per_agent.items():
        safe_name = agent.replace("-", "_").replace(" ", "_")
        print(f"BUDGET_AGENT_{safe_name}={sc}")


if __name__ == "__main__":
    main()
