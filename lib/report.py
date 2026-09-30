#!/usr/bin/env python3
"""Megalint report generator — produces JSON and/or Markdown reports.

Input:  JSON file with all data (--input path)
Flags:  --format json|md|both  --output-dir path
Output: Report file(s) written to output-dir

Accepts either old format (from megalint.sh) or new summary format (from process.py).
"""

import json
import os
import re
import sys

# Ensure lib is importable when run as script
_SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)

from lib.config import get_pricing_for_model  # noqa: E402


def _build_api_usage(m):
    """Build API usage summary from actual token counts."""
    tokens_in = m.get("hardener_tokens_in", 0)
    tokens_out = m.get("hardener_tokens_out", 0)
    if tokens_in == 0 and tokens_out == 0:
        return None
    model = m.get("hardener_model", "")
    pricing = get_pricing_for_model(model)
    cost_in = (tokens_in / 1e6) * pricing["input"]
    cost_out = (tokens_out / 1e6) * pricing["output"]
    return {
        "input_tokens": tokens_in,
        "output_tokens": tokens_out,
        "total_tokens": tokens_in + tokens_out,
        "cost_input": round(cost_in, 6),
        "cost_output": round(cost_out, 6),
        "cost_total": round(cost_in + cost_out, 6),
        "model": model,
        "calls": m.get("agents_scanned", len(m.get("agents_list", []))),
    }


def _normalize_input(m):
    """Convert new summary format to flat format for build_report_data.
    Returns (flat_m, agents_prebuilt, hg_checks_prebuilt).
    New format: meta, agentlinter, promptlint, homegrow, budget, hardener, scoring.
    """
    if "meta" in m and "scoring" in m:
        meta = m.get("meta", {})
        git = meta if isinstance(meta.get("git_commit"), str) else meta.get("git", {})
        if not isinstance(git, dict):
            git = {}
        scoring = m.get("scoring", {})
        homegrow = m.get("homegrow", {})
        agentlinter = m.get("agentlinter", {})
        promptlint = m.get("promptlint", {})
        hardener = m.get("hardener")

        # Build agents_data from agentlinter.per_agent + promptlint.per_agent
        al_per = agentlinter.get("per_agent", {})
        pl_per = promptlint.get("per_agent", {})
        agent_names = sorted(set(al_per.keys()) | set(pl_per.keys()))
        if not agent_names and "agents_list" in meta:
            agent_names = meta["agents_list"]

        agents = {}
        for name in agent_names:
            ad = {"agent": name}
            al_data = al_per.get(name, {})
            ad["agentlinter"] = {
                "score": al_data.get("score", 0),
                "categories": al_data.get("categories", {}),
                "diagnostics": al_data.get("diagnostics", []),
            }
            pl_data = pl_per.get(name, {})
            pl_files = pl_data.get("files", {})
            ad["promptlint"] = {
                fname: {
                    "clarity": fd.get("clarity", 0),
                    "security": fd.get("security", 0),
                    "cost_efficiency": fd.get("cost_efficiency", 0),
                    "overall": fd.get("overall", 0),
                    "issues": fd.get("issues", []),
                }
                for fname, fd in pl_files.items()
            }
            if hardener and isinstance(hardener, dict):
                eval_per = hardener.get("eval_per_agent", {})
                if name in eval_per:
                    ad["prompt_hardener"] = eval_per[name]
            agents[name] = ad

        flat = {
            "run_id": meta.get("run_id", ""),
            "timestamp": meta.get("timestamp", ""),
            "git_commit": meta.get("git_commit") or git.get("commit", ""),
            "git_branch": meta.get("git_branch") or git.get("branch", ""),
            "git_dirty": meta.get("git_dirty", git.get("dirty", False)),
            "git_msg": meta.get("git_msg") or git.get("message", ""),
            "agents_list": agent_names,
            "hardener_model": meta.get("hardener_model") or meta.get("model"),
            "hardener_tokens_in": meta.get("hardener_tokens_in", 0),
            "hardener_tokens_out": meta.get("hardener_tokens_out", 0),
            "combined": scoring.get("combined", 0),
            "grade": scoring.get("grade", "F"),
            "passed": scoring.get("passed", False),
            "pass_threshold": scoring.get("pass_threshold", 70),
            "blocking_errors": scoring.get("blocking_errors", True),
            "hg_passes": homegrow.get("passes", 0),
            "hg_infos": homegrow.get("infos", 0),
            "hg_warnings": homegrow.get("warnings", 0),
            "hg_errors": homegrow.get("errors", 0),
            "avg_pl_clarity": scoring.get("avg_pl_clarity", 0),
            "avg_pl_security": 0,
            "avg_pl_cost": 0,
        }
        flat["pillar_structure"] = scoring.get("pillar_structure", 0)
        pq = scoring.get("pillar_quality")
        flat["pillar_quality"] = pq if pq is not None and pq != "N/A" else None
        flat["pillar_consistency"] = scoring.get("pillar_consistency", 0)
        ps = scoring.get("pillar_security")
        flat["pillar_security"] = ps if ps is not None and ps != "N/A" else None
        pb = scoring.get("pillar_budget")
        flat["pillar_budget"] = pb if pb is not None and pb != "N/A" else None
        weights = scoring.get("weights", {}) or scoring.get("pillars", {})
        if isinstance(weights, dict) and "structure" in weights:
            flat["weight_structure"] = weights.get("structure", 25)
            flat["weight_quality"] = weights.get("quality", 18)
            flat["weight_consistency"] = weights.get("consistency", 22)
            flat["weight_security"] = weights.get("security", 20)
            flat["weight_budget"] = weights.get("budget", 15)
        else:
            flat["weight_structure"] = 25
            flat["weight_quality"] = 18
            flat["weight_consistency"] = 22
            flat["weight_security"] = 20
            flat["weight_budget"] = 15
        return flat, agents, homegrow.get("checks", [])
    return m, None, None


def build_report_data(m):
    """Assemble the full report dict from input metrics.
    Accepts old format (from megalint.sh) or new summary format (from process.py).
    """
    m, agents_prebuilt, hg_checks_prebuilt = _normalize_input(m)
    if agents_prebuilt is not None and hg_checks_prebuilt is not None:
        agents_data = agents_prebuilt
        hg_results = hg_checks_prebuilt
    else:
        agents_data = {}
        for agent in m["agents_list"]:
            agent = agent.strip()
            if not agent:
                continue
            ad = {"agent": agent}

            al_file = os.path.join(m["al_dir"], f"{agent}.json")
            if os.path.exists(al_file):
                try:
                    with open(al_file) as f:
                        al = json.load(f)
                    ad["agentlinter"] = {
                        "score": al.get("score", 0),
                        "categories": {
                            c["name"]: c["score"] for c in al.get("categories", [])
                        },
                        "diagnostics": [
                            {
                                "severity": d.get("severity"),
                                "message": d.get("message"),
                                "rule": d.get("rule", ""),
                                "file": d.get("file", ""),
                                "line": d.get("line"),
                                "fix": d.get("fix", ""),
                            }
                            for d in al.get("diagnostics", [])
                        ],
                    }
                except (json.JSONDecodeError, OSError, KeyError):
                    ad["agentlinter"] = {"score": 0, "categories": {}, "diagnostics": []}

            pl_dir = os.path.join(m["pl_dir"], agent)
            if os.path.isdir(pl_dir):
                pl_files = {}
                for jf in sorted(os.listdir(pl_dir)):
                    if not jf.endswith(".json"):
                        continue
                    try:
                        with open(os.path.join(pl_dir, jf)) as f:
                            pd = json.load(f)
                        fname = jf.replace(".json", "")
                        sc = pd.get("scores", {})
                        pl_files[fname] = {
                            "clarity": sc.get("clarity", 0),
                            "security": sc.get("security", 0),
                            "cost_efficiency": sc.get("cost_efficiency", 0),
                            "overall": sc.get("overall", 0),
                            "issues": [
                                {
                                    "severity": i.get("severity", ""),
                                    "category": i.get("category", ""),
                                    "description": i.get("description", ""),
                                    "suggestion": i.get("suggestion", ""),
                                    "location": i.get("location"),
                                }
                                for i in pd.get("issues", [])
                            ],
                        }
                    except (json.JSONDecodeError, OSError):
                        pass
                ad["promptlint"] = pl_files

            ph_file = os.path.join(m["ph_dir"], f"{agent}_eval.json")
            if os.path.exists(ph_file):
                try:
                    with open(ph_file) as f:
                        ad["prompt_hardener"] = json.load(f)
                except (json.JSONDecodeError, OSError):
                    pass
            agents_data[agent] = ad

        hg_results = []
        hg_file = os.path.join(m["hg_dir"], "results.txt")
        if os.path.exists(hg_file):
            with open(hg_file) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    parts = line.split("|", 2)
                    if len(parts) == 3:
                        hg_results.append(
                            {"status": parts[0], "context": parts[1], "message": parts[2]}
                        )

    pillars = {
        "structure": {
            "score": m["pillar_structure"],
            "weight": m["weight_structure"],
            "tool": "AgentLinter",
        },
        "consistency": {
            "score": m["pillar_consistency"],
            "weight": m["weight_consistency"],
            "tool": "Home-Grow",
        },
    }
    pq = m.get("pillar_quality")
    if pq is not None and pq != "N/A":
        pillars["quality"] = {
            "score": float(pq) if not isinstance(pq, (int, float)) else pq,
            "weight": m["weight_quality"],
            "tool": "PromptLint",
        }
    ps = m.get("pillar_security")
    if ps is not None and ps != "N/A":
        pillars["security"] = {
            "score": float(ps) if not isinstance(ps, (int, float)) else ps,
            "weight": m["weight_security"],
            "tool": "Prompt Hardener",
        }
    pb = m.get("pillar_budget")
    if pb is not None and pb != "N/A":
        pillars["budget"] = {
            "score": float(pb) if not isinstance(pb, (int, float)) else pb,
            "weight": m.get("weight_budget", 15),
            "tool": "Token Budget",
        }

    return {
        "meta": {
            "run_id": m["run_id"],
            "timestamp": m["timestamp"],
            "git": {
                "commit": m["git_commit"],
                "branch": m["git_branch"],
                "dirty": m["git_dirty"],
                "message": m["git_msg"],
            },
            "model": m.get("hardener_model"),
            "agents_scanned": len(agents_data),
            "api_usage": _build_api_usage(m),
        },
        "scoring": {
            "combined": m["combined"],
            "grade": m["grade"],
            "passed": m["passed"],
            "pass_threshold": m["pass_threshold"],
            "blocking_errors": m["blocking_errors"],
            "pillars": pillars,
            "quality_detail": {
                "clarity": m["avg_pl_clarity"],
                "security_raw": m["avg_pl_security"],
                "cost_efficiency_raw": m["avg_pl_cost"],
                "note": "Quality pillar = clarity only (0-10 scaled to 0-100). PromptLint security checks for injection patterns, not defense. Real security via Prompt Hardener pillar. Cost excluded — handled by Token Budget pillar.",
            },
        },
        "agents": agents_data,
        "homegrow": {
            "passes": m.get("hg_passes", 0),
            "infos": m.get("hg_infos", 0),
            "warnings": m.get("hg_warnings", 0),
            "errors": m.get("hg_errors", 0),
            "checks": hg_results,
        },
    }


def write_json(report, output_dir, run_id):
    os.makedirs(output_dir, exist_ok=True)
    outpath = os.path.join(output_dir, f"report_{run_id}.json")
    with open(outpath, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"JSON: {outpath}", file=sys.stderr)


# ── Token budget parsing from Home-Grow warnings ────────────────────────────

_TOKEN_RE = re.compile(
    r"^(.+\.md)\s+~(\d+)\s+tokens?\s+.*\(base:\s*(\d+)",
    re.IGNORECASE,
)


def _parse_token_violations(hg_checks):
    """Extract token budget violations from Home-Grow WARN lines."""
    violations = []
    for r in hg_checks:
        if r["status"] != "WARN":
            continue
        m = _TOKEN_RE.search(r["message"])
        if m:
            fname, est, budget = m.group(1), int(m.group(2)), int(m.group(3))
            ratio = round(est / budget, 1)
            violations.append(
                {
                    "agent": r["context"],
                    "file": fname,
                    "estimated": est,
                    "budget": budget,
                    "ratio": ratio,
                }
            )
    violations.sort(key=lambda v: v["ratio"], reverse=True)
    return violations


# ── Auto-generated recommendations ──────────────────────────────────────────

_PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2}


def _build_recommendations(report):
    """Generate prioritized recommendations from detected issues."""
    recs = []
    agents_data = report["agents"]
    hg_checks = report["homegrow"]["checks"]

    # High: token budget violations
    for v in _parse_token_violations(hg_checks):
        recs.append(
            {
                "priority": "high",
                "agent": v["agent"],
                "file": v["file"],
                "text": (
                    f"{v['file']} is {v['ratio']}x over token budget "
                    f"(~{v['estimated']} tokens, budget ≤{v['budget']})"
                ),
            }
        )

    # Medium: AgentLinter warnings
    for name, ad in agents_data.items():
        for d in ad.get("agentlinter", {}).get("diagnostics", []):
            sev = d.get("severity", "")
            if sev == "warning":
                rule = d.get("rule", "")
                msg = d.get("message", "")
                recs.append(
                    {
                        "priority": "medium",
                        "agent": name,
                        "file": d.get("file", ""),
                        "text": f"`{rule}` — {msg}" if rule else msg,
                    }
                )

    # Medium: PromptLint issues
    for name, ad in agents_data.items():
        for fname, pl in ad.get("promptlint", {}).items():
            for issue in pl.get("issues", []):
                sev = issue.get("severity", "info")
                if sev in ("medium", "high", "critical"):
                    recs.append(
                        {
                            "priority": "medium",
                            "agent": name,
                            "file": fname,
                            "text": issue.get("description", ""),
                        }
                    )

    # Medium: Home-Grow behavioral/convention warnings
    for r in hg_checks:
        if r["status"] != "WARN":
            continue
        if _TOKEN_RE.search(r["message"]):
            continue
        recs.append(
            {
                "priority": "medium",
                "agent": r["context"],
                "file": "",
                "text": r["message"],
            }
        )

    # High: AgentLinter critical/error diagnostics
    for name, ad in agents_data.items():
        for d in ad.get("agentlinter", {}).get("diagnostics", []):
            sev = d.get("severity", "")
            if sev in ("critical", "error"):
                rule = d.get("rule", "")
                msg = d.get("message", "")
                recs.append(
                    {
                        "priority": "high",
                        "agent": name,
                        "file": d.get("file", ""),
                        "text": f"`{rule}` — {msg}" if rule else msg,
                    }
                )

    # Low: Home-Grow errors
    for r in hg_checks:
        if r["status"] == "ERROR":
            recs.append(
                {
                    "priority": "high",
                    "agent": r["context"],
                    "file": "",
                    "text": r["message"],
                }
            )

    # Deduplicate: exact match on (agent, text), plus cross-source dedup
    # for AgentLinter workspace warnings vs Home-Grow shared warnings
    # which often describe the same underlying issue differently.
    seen = set()
    seen_topics = set()  # normalized keywords from workspace/shared warnings
    unique = []
    for r in recs:
        key = (r["agent"], r["text"])
        if key in seen:
            continue

        # Extract topic words for cross-source dedup (strip citations first)
        text_lower = r["text"].lower()
        text_no_refs = re.sub(r'see\s+docs/\S+', '', text_lower)
        _STOP = {"should", "without", "across", "every", "found",
                 "agents", "agent", "based", "between", "which",
                 "their", "these", "those", "memory", "before",
                 "after", "about", "other", "first", "using",
                 "never", "approach", "approaches", "master",
                 "summary", "focused", "audit", "theme", "rules"}
        topic_words = set(
            w for w in re.findall(r'[a-z]{5,}', text_no_refs)
            if w not in _STOP
        )
        is_shared = r.get("file", "") == "(workspace)" or r["agent"] == "shared"
        if is_shared and topic_words:
            frozen = frozenset(topic_words)
            # Check if a previous shared-level entry covers >=3 of the same topic words
            skip = False
            for prev_topics in seen_topics:
                overlap = frozen & prev_topics
                if len(overlap) >= 3:
                    skip = True
                    break
            if skip:
                continue
            seen_topics.add(frozen)

        seen.add(key)
        unique.append(r)

    unique.sort(key=lambda r: (_PRIORITY_ORDER.get(r["priority"], 9), r["agent"]))
    return unique


# ── Markdown report writer ──────────────────────────────────────────────────


def write_markdown(report, output_dir, run_id):
    os.makedirs(output_dir, exist_ok=True)
    outpath = os.path.join(output_dir, f"report_{run_id}.md")
    meta = report["meta"]
    scoring = report["scoring"]
    agents_data = report["agents"]
    hg = report["homegrow"]
    hg_checks = hg["checks"]
    pillars = scoring["pillars"]

    git = meta["git"]
    combined = scoring["combined"]
    grade = scoring["grade"]
    passed = scoring["passed"]
    pass_thr = scoring["pass_threshold"]
    blocking_on = scoring["blocking_errors"]

    L = []

    # ── Header ───────────────────────────────────────────────────────────────

    L.append("# Megalint Report")
    L.append("")
    L.append("| Field | Value |")
    L.append("|-------|-------|")
    L.append(f"| Run ID | `{meta['run_id']}` |")
    L.append(f"| Timestamp | {meta['timestamp']} |")
    dirty_tag = " [dirty]" if git["dirty"] else ""
    L.append(f"| Git | `{git['commit']}` ({git['branch']}){dirty_tag} |")
    L.append(f"| Commit | {git['message']} |")
    if meta.get("model"):
        L.append(f"| Model | {meta['model']} |")
    L.append(f"| Agents | {len(agents_data)} |")
    api_usage = meta.get("api_usage")
    if api_usage:
        L.append(
            f"| API tokens | {api_usage['input_tokens']:,} in / "
            f"{api_usage['output_tokens']:,} out "
            f"({api_usage['total_tokens']:,} total) |"
        )
        L.append(f"| API cost | ${api_usage['cost_total']:.4f} |")
    L.append("")

    # ── Combined score ───────────────────────────────────────────────────────

    result_str = "PASS" if passed else "FAIL"
    L.append(f"## Score: {combined} ({grade}) — {result_str}")
    L.append("")
    L.append("| Pillar | Score | Weight | Tool |")
    L.append("|--------|:-----:|:------:|------|")
    tw = sum(p["weight"] for p in pillars.values())
    for name, p in pillars.items():
        ew = round(p["weight"] / tw * 100)
        L.append(f"| {name.title()} | {p['score']} | {ew}% | {p['tool']} |")
    if "quality" not in pillars:
        L.append("| Quality | skipped | — | PromptLint |")
    if "security" not in pillars:
        L.append("| Security | skipped | — | Prompt Hardener |")
    if "budget" not in pillars:
        L.append("| Budget | skipped | — | Token Budget |")
    L.append("")
    L.append(
        f"Threshold: {pass_thr} | Blocking errors: {'on' if blocking_on else 'off'}"
    )
    L.append("")

    # ── Per-Agent summary ────────────────────────────────────────────────────

    L.append("## Per-Agent Scores")
    L.append("")
    L.append("| Agent | Structure | Quality | Clarity |")
    L.append("|-------|:---------:|:-------:|:-------:|")
    for name, ad in agents_data.items():
        al_s = ad.get("agentlinter", {}).get("score", "—")
        pl = ad.get("promptlint", {})
        if pl:
            vals = list(pl.values())
            cl = round(
                sum(v.get("clarity", 0) for v in vals) / max(len(vals), 1), 1
            )
            ql = round(cl * 10, 1)
        else:
            cl = "—"
            ql = "—"
        L.append(f"| {name} | {al_s} | {ql} | {cl} |")
    L.append("")

    # ── Per-File PromptLint scores ───────────────────────────────────────────

    for name, ad in agents_data.items():
        pl = ad.get("promptlint", {})
        if not pl:
            continue
        L.append(f"## Per-File PromptLint Scores — {name}")
        L.append("")
        L.append("| File | Clarity | Security | Cost | Overall |")
        L.append("|------|:-------:|:--------:|:----:|:-------:|")
        sorted_files = sorted(pl.items(), key=lambda x: x[1].get("overall", 0), reverse=True)
        for fname, scores in sorted_files:
            L.append(
                f"| {fname} | {round(scores.get('clarity', 0), 1)} "
                f"| {round(scores.get('security', 0), 1)} "
                f"| {round(scores.get('cost_efficiency', 0), 1)} "
                f"| {round(scores.get('overall', 0), 1)} |"
            )
        L.append("")

        # Per-file issues
        file_issues = []
        for fname, scores in sorted_files:
            for issue in scores.get("issues", []):
                sev = issue.get("severity", "info")
                desc = issue.get("description", "")
                if desc:
                    file_issues.append(
                        (fname, desc, sev, issue.get("suggestion", ""), issue.get("location"))
                    )
        if file_issues:
            L.append(f"### PromptLint Issues — {name}")
            L.append("")
            for fname, desc, sev, suggestion, location in file_issues:
                loc_str = f" ({location})" if location else ""
                L.append(f"- **{fname}**{loc_str}: {desc} [{sev}]")
                if suggestion:
                    L.append(f"  - *Suggestion*: {suggestion}")
            L.append("")

    # ── AgentLinter categories ───────────────────────────────────────────────

    for name, ad in agents_data.items():
        al = ad.get("agentlinter", {})
        cats = al.get("categories", {})
        diags = al.get("diagnostics", [])
        if not cats:
            continue

        L.append(f"## AgentLinter Categories — {name}")
        L.append("")
        L.append("| Category | Score |")
        L.append("|----------|:-----:|")
        for cat_name in sorted(cats.keys()):
            L.append(f"| {cat_name} | {cats[cat_name]} |")
        L.append("")

        # Diagnostics grouped by severity
        warnings = [d for d in diags if d.get("severity") == "warning"]
        errors = [d for d in diags if d.get("severity") in ("critical", "error")]

        if errors:
            L.append(f"### Errors — {name}")
            L.append("")
            for d in errors:
                rule = d.get("rule", "—")
                msg = d.get("message", "")
                fix = d.get("fix", "")
                fline = d.get("file", "")
                line = d.get("line")
                loc = f"{fline}" if fline else ""
                if line:
                    loc += f":{line}"
                L.append(f"- **`{rule}`**{(' (' + loc + ')') if loc else ''}: {msg}")
                if fix:
                    L.append(f"  - *Fix*: {fix}")
            L.append("")

        if warnings:
            L.append(f"### Warnings — {name}")
            L.append("")
            for d in warnings:
                rule = d.get("rule", "—")
                msg = d.get("message", "")
                fix = d.get("fix", "")
                fline = d.get("file", "")
                line = d.get("line")
                loc = f"{fline}" if fline else ""
                if line:
                    loc += f":{line}"
                L.append(f"- **`{rule}`**{(' (' + loc + ')') if loc else ''}: {msg}")
                if fix:
                    L.append(f"  - *Fix*: {fix}")
            L.append("")

    # ── Multi-agent structure categories comparison ──────────────────────────

    if len(agents_data) > 1:
        all_cats = set()
        for ad in agents_data.values():
            all_cats.update(ad.get("agentlinter", {}).get("categories", {}).keys())
        cat_list = sorted(all_cats)
        if cat_list:
            L.append("## Structure Categories (All Agents)")
            L.append("")
            L.append("| Agent | " + " | ".join(cat_list) + " |")
            L.append("|-------|" + "|".join(":---:" for _ in cat_list) + "|")
            for name, ad in agents_data.items():
                cats = ad.get("agentlinter", {}).get("categories", {})
                L.append(
                    f"| {name} | "
                    + " | ".join(str(cats.get(c, "—")) for c in cat_list)
                    + " |"
                )
            L.append("")

    # ── Security evaluation ──────────────────────────────────────────────────

    has_ph = any("prompt_hardener" in ad for ad in agents_data.values())
    if has_ph:
        L.append("## Security Evaluation")
        L.append("")
        all_ph_cats = set()
        _ph_metadata_keys = {"_usage", "_meta", "_config", "_model", "_timestamp"}
        for ad in agents_data.values():
            ph = ad.get("prompt_hardener", {})
            for k, v in ph.items():
                if isinstance(v, dict) and k not in _ph_metadata_keys:
                    all_ph_cats.add(k)
        ph_cats = sorted(all_ph_cats)
        L.append("| Agent | " + " | ".join(ph_cats) + " |")
        L.append("|-------|" + "|".join(":---:" for _ in ph_cats) + "|")
        for name, ad in agents_data.items():
            ph = ad.get("prompt_hardener", {})
            row = []
            for cat in ph_cats:
                if cat in ph and isinstance(ph[cat], dict):
                    vals = [
                        int(v.get("satisfaction", 0))
                        for v in ph[cat].values()
                        if isinstance(v, dict)
                    ]
                    avg = round(sum(vals) / max(len(vals), 1), 1) if vals else "—"
                    row.append(str(avg))
                else:
                    row.append("—")
            L.append(f"| {name} | " + " | ".join(row) + " |")
        L.append("")

    # ── Home-Grow consistency ────────────────────────────────────────────────

    L.append("## Home-Grow Consistency")
    L.append("")
    L.append("| Result | Count |")
    L.append("|--------|:-----:|")
    L.append(f"| PASS | {hg['passes']} |")
    L.append(f"| INFO | {hg.get('infos', 0)} |")
    L.append(f"| WARN | {hg['warnings']} |")
    L.append(f"| ERROR | {hg['errors']} |")
    L.append("")

    # Token budget violations (extracted from Home-Grow WARN lines)
    token_violations = _parse_token_violations(hg_checks)
    if token_violations:
        L.append("### Token Budget Violations")
        L.append("")
        L.append("| Agent | File | Estimated | Budget | Over By |")
        L.append("|-------|------|:---------:|:------:|:-------:|")
        for v in token_violations:
            L.append(
                f"| {v['agent']} | {v['file']} "
                f"| ~{v['estimated']} | ≤{v['budget']} | {v['ratio']}x |"
            )
        L.append("")

    # Non-token consistency issues
    non_token_issues = [
        r
        for r in hg_checks
        if r["status"] != "OK" and not _TOKEN_RE.search(r["message"])
    ]
    if non_token_issues:
        L.append("### Other Consistency Issues")
        L.append("")
        L.append("| Status | Agent | Message |")
        L.append("|--------|-------|---------|")
        for r in non_token_issues:
            L.append(f"| {r['status']} | {r['context']} | {r['message']} |")
        L.append("")

    # ── Recommended prompt changes ───────────────────────────────────────────

    recs = _build_recommendations(report)
    if recs:
        L.append("## Recommended Changes")
        L.append("")
        for priority in ("high", "medium", "low"):
            group = [r for r in recs if r["priority"] == priority]
            if not group:
                continue
            L.append(f"### {priority.title()} Priority")
            L.append("")
            for i, r in enumerate(group, 1):
                loc = f"**{r['agent']}**"
                if r.get("file"):
                    loc += f" / {r['file']}"
                L.append(f"{i}. {loc} — {r['text']}")
            L.append("")

    # ── Footer ───────────────────────────────────────────────────────────────

    L.append("---")
    L.append("")
    L.append(
        f"*Generated by megalint | "
        f"`{git['commit']}` ({git['branch']}){dirty_tag} | "
        f"{meta['timestamp']}*"
    )
    L.append("")

    with open(outpath, "w") as f:
        f.write("\n".join(L) + "\n")
    print(f"MD: {outpath}", file=sys.stderr)


def main():
    if len(sys.argv) < 5:
        print(
            "Usage: report.py --input <data.json> --format json|md|both --output-dir <dir>",
            file=sys.stderr,
        )
        sys.exit(1)

    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] in ("--input", "--format", "--output-dir") and i + 1 < len(
            sys.argv
        ):
            args[sys.argv[i].lstrip("-").replace("-", "_")] = sys.argv[i + 1]
            i += 2
        else:
            i += 1

    for req in ("input", "format", "output_dir"):
        if req not in args:
            print(f"Missing --{req.replace('_', '-')}", file=sys.stderr)
            sys.exit(1)
    with open(args["input"]) as f:
        m = json.load(f)

    report = build_report_data(m)
    fmt = args["format"]
    output_dir = args["output_dir"]
    run_id = m.get("run_id") or m.get("meta", {}).get("run_id", "unknown")

    if fmt in ("json", "both"):
        write_json(report, output_dir, run_id)
    if fmt in ("md", "both"):
        write_markdown(report, output_dir, run_id)


if __name__ == "__main__":
    main()
