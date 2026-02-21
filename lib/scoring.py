#!/usr/bin/env python3
"""Megalint scoring engine — computes 4-pillar weighted score from tool results.

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
    hg_warnings = m["hg_warnings"]
    hg_errors = m["hg_errors"]
    hardener_ran = m["hardener_ran"]
    ph_dir = m["ph_dir"]

    w_st = m["weight_structure"]
    w_ql = m["weight_quality"]
    w_co = m["weight_consistency"]
    w_se = m["weight_security"]
    pass_thr = m["pass_threshold"]
    blocking = m["blocking_errors"]
    grades = m["grades"]

    # Pillar 1: Structure (AgentLinter)
    pillar_structure = round(total_al / max(agent_count, 1))

    # Pillar 2: Quality (PromptLint) — weighted: clarity 40%, security 30%, cost 30%
    if total_pl_files > 0:
        avg_cl = round(total_pl_clarity / total_pl_files, 1)
        avg_se = round(total_pl_security / total_pl_files, 1)
        avg_co = round(total_pl_cost / total_pl_files, 1)
        pillar_quality = round((avg_cl * 0.40 + avg_se * 0.30 + avg_co * 0.30) * 10, 1)
    else:
        avg_cl = avg_se = avg_co = 0
        pillar_quality = 0

    # Pillar 3: Consistency (Home-Grow) — percentage-based
    total_checks = hg_passes + hg_warnings + hg_errors
    if total_checks > 0:
        weighted = (hg_passes * 1.0 + hg_warnings * 0.5) / total_checks
        pillar_consistency = round(weighted * 100)
    else:
        pillar_consistency = 100

    # Pillar 4: Security (Prompt Hardener)
    # RSE (Random Sequence Enclosure) is optional — scores 0/10 when not implemented
    # but shouldn't drag down security scores for agents that intentionally skip it.
    # We exclude checks scoring 0 under RSE-related categories from the average.
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
                            # Skip RSE checks that score 0 (optional technique not implemented)
                            if is_rse and sat == 0:
                                continue
                            ph_total += 1
                            ph_satisfied += sat
            except (json.JSONDecodeError, OSError, ValueError):
                pass
        if ph_total > 0:
            pillar_security = round((ph_satisfied / (ph_total * 10)) * 100, 1)

    # Weighted combination
    active_pillars = {
        "structure": (pillar_structure, w_st),
        "quality": (pillar_quality, w_ql),
        "consistency": (pillar_consistency, w_co),
    }
    if pillar_security is not None:
        active_pillars["security"] = (pillar_security, w_se)

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
    print(f"PILLAR_QUALITY={pillar_quality}")
    print(f"PILLAR_CONSISTENCY={pillar_consistency}")
    print(f"PILLAR_SECURITY={pillar_security if pillar_security is not None else 'N/A'}")
    print(f"PH_SATISFIED={ph_satisfied}")
    print(f"PH_TOTAL={ph_total}")
    print(f"AVG_PL_CLARITY={avg_cl}")
    print(f"AVG_PL_SECURITY={avg_se}")
    print(f"AVG_PL_COST={avg_co}")
    print(f"COMBINED={combined}")
    print(f"GRADE={grade}")
    print(f"PASSED={'true' if passed else 'false'}")
    print(f"HAS_BLOCKING={'true' if has_blocking else 'false'}")


if __name__ == "__main__":
    main()
