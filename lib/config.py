#!/usr/bin/env python3
"""Megalint config loader — single source of truth for weights, thresholds, grades, pricing."""

import os
from dataclasses import dataclass, field
from pathlib import Path


_DEFAULT_GRADES = [
    (97, "S"),
    (95, "A+"),
    (93, "A"),
    (90, "A-"),
    (87, "B+"),
    (83, "B"),
    (80, "B-"),
    (77, "C+"),
    (73, "C"),
    (70, "C-"),
    (60, "D"),
]

# Load frequency weights — files that load every message matter more for budget scoring
LOAD_WEIGHTS = {
    "AGENTS.md": 3,     # every message
    "SOUL.md": 3,
    "IDENTITY.md": 3,
    "USER.md": 3,
    "TOOLS.md": 3,
    "HEARTBEAT.md": 2,   # ~48x/day
    "MEMORY.md": 1,      # DM sessions only
}

_DEFAULT_PRICING = {
    "claude-haiku-4.5": {"input": 0.8, "output": 4.0},
    "anthropic/claude-haiku-4.5": {"input": 0.8, "output": 4.0},
    "claude-haiku-4-5": {"input": 0.8, "output": 4.0},
    "claude-sonnet-4-5": {"input": 3.0, "output": 15.0},
    "anthropic/claude-sonnet-4-5": {"input": 3.0, "output": 15.0},
    "claude-sonnet-4-6": {"input": 3.0, "output": 15.0},
    "anthropic/claude-sonnet-4-6": {"input": 3.0, "output": 15.0},
    "claude-opus-4-6": {"input": 5.0, "output": 25.0},
    "anthropic/claude-opus-4-6": {"input": 5.0, "output": 25.0},
}


def _parse_bash_conf(path: str) -> dict:
    """Parse a bash-sourceable config file; return dict of KEY=value."""
    out = {}
    if not path or not os.path.isfile(path):
        return out
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip()
                if key:
                    out[key] = val
    return out


def _to_grades(raw: dict) -> list[tuple[int, str]]:
    """Build grades list from raw conf dict."""
    grade_map = [
        ("GRADE_S", "S"),
        ("GRADE_A_PLUS", "A+"),
        ("GRADE_A", "A"),
        ("GRADE_A_MINUS", "A-"),
        ("GRADE_B_PLUS", "B+"),
        ("GRADE_B", "B"),
        ("GRADE_B_MINUS", "B-"),
        ("GRADE_C_PLUS", "C+"),
        ("GRADE_C", "C"),
        ("GRADE_C_MINUS", "C-"),
        ("GRADE_D", "D"),
    ]
    result = []
    for key, label in grade_map:
        v = raw.get(key)
        if v is not None:
            try:
                result.append((int(v), label))
            except (ValueError, TypeError):
                pass
    if result:
        result.sort(key=lambda x: -x[0])
        return result
    return _DEFAULT_GRADES.copy()


def _to_budgets(raw: dict) -> dict[str, int]:
    """Build budgets dict from rules.conf style."""
    budget_keys = [
        "BUDGET_AGENTS_MD", "BUDGET_SOUL_MD", "BUDGET_IDENTITY_MD",
        "BUDGET_USER_MD", "BUDGET_TOOLS_MD", "BUDGET_HEARTBEAT_MD", "BUDGET_MEMORY_MD",
    ]
    defaults = {
        "AGENTS.md": 1725,
        "SOUL.md": 525,
        "IDENTITY.md": 175,
        "USER.md": 715,
        "TOOLS.md": 525,
        "HEARTBEAT.md": 225,
        "MEMORY.md": 975,
    }
    name_map = {
        "BUDGET_AGENTS_MD": "AGENTS.md",
        "BUDGET_SOUL_MD": "SOUL.md",
        "BUDGET_IDENTITY_MD": "IDENTITY.md",
        "BUDGET_USER_MD": "USER.md",
        "BUDGET_TOOLS_MD": "TOOLS.md",
        "BUDGET_HEARTBEAT_MD": "HEARTBEAT.md",
        "BUDGET_MEMORY_MD": "MEMORY.md",
    }
    out = dict(defaults)
    for env_key in budget_keys:
        env_var = f"MEGALINT_{env_key}"
        if env_var in os.environ:
            try:
                out[name_map[env_key]] = int(os.environ[env_var])
            except (ValueError, TypeError):
                pass
        elif raw.get(env_key) is not None:
            try:
                out[name_map[env_key]] = int(raw[env_key])
            except (ValueError, TypeError):
                pass
    return out


@dataclass
class Config:
    """Megalint configuration."""

    weight_structure: int = 25
    weight_quality: int = 18
    weight_consistency: int = 22
    weight_security: int = 20
    weight_budget: int = 15
    pass_threshold: int = 70
    blocking_errors: bool = True
    grades: list = field(default_factory=lambda: _DEFAULT_GRADES.copy())
    budgets: dict = field(default_factory=dict)
    tier_info: float = 1.25
    tier_warn: float = 1.50
    pricing: dict = field(default_factory=lambda: dict(_DEFAULT_PRICING))


def load_config(
    megalint_conf: str | None = None,
    rules_conf: str | None = None,
    script_dir: str | None = None,
) -> Config:
    """Load config from megalint.conf and rules.conf, with env overrides."""
    if script_dir is None:
        script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if megalint_conf is None:
        megalint_conf = os.path.join(script_dir, "megalint.conf")
    if rules_conf is None:
        rules_conf = os.path.join(script_dir, "apps", "homegrow", "rules.conf")

    mega = _parse_bash_conf(megalint_conf)
    rules = _parse_bash_conf(rules_conf)

    grades = _to_grades(mega)
    budgets = _to_budgets(rules)

    def _int(key: str, default: int) -> int:
        v = mega.get(key)
        if v is not None:
            try:
                return int(v)
            except (ValueError, TypeError):
                pass
        return default

    def _bool(key: str, default: bool) -> bool:
        v = mega.get(key)
        if v is not None:
            return str(v).lower() in ("true", "1", "yes")
        return default

    def _float(key: str, default: float) -> float:
        v = rules.get(key)
        if v is not None:
            try:
                return float(v)
            except (ValueError, TypeError):
                pass
        env_key = f"MEGALINT_{key}"
        if env_key in os.environ:
            try:
                return float(os.environ[env_key])
            except (ValueError, TypeError):
                pass
        return default

    return Config(
        weight_structure=_int("WEIGHT_STRUCTURE", 25),
        weight_quality=_int("WEIGHT_QUALITY", 18),
        weight_consistency=_int("WEIGHT_CONSISTENCY", 22),
        weight_security=_int("WEIGHT_SECURITY", 20),
        weight_budget=_int("WEIGHT_BUDGET", 15),
        pass_threshold=_int("PASS_THRESHOLD", 70),
        blocking_errors=_bool("BLOCKING_ERRORS", True),
        grades=grades,
        budgets=budgets if budgets else {
            "AGENTS.md": 1725, "SOUL.md": 525, "IDENTITY.md": 175,
            "USER.md": 715, "TOOLS.md": 525, "HEARTBEAT.md": 225, "MEMORY.md": 975,
        },
        tier_info=_float("TIER_INFO", 1.25),
        tier_warn=_float("TIER_WARN", 1.50),
        pricing=dict(_DEFAULT_PRICING),
    )


def get_pricing_for_model(model: str, config: Config | None = None) -> dict[str, float]:
    """Return input/output pricing per 1M tokens for a model. Fallback: Sonnet rates."""
    cfg = config or load_config()
    return cfg.pricing.get(model, {"input": 3.0, "output": 15.0})
