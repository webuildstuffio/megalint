# Token Budget Tuning Guide

Research-backed recommendations for megalint token budgets. Based on context window performance research (Anthropic context engineering, Chroma "Context Rot" study, "Lost in the Middle" / Liu et al., Goldberg et al. "Same Task More Tokens"), OpenClaw bootstrap injection behavior, and production agent engineering practices.

**This is the source of truth for token budgets.** All other files (`CONVENTIONS.md`, `CLAUDE.md`, `rules.conf`, etc.) reference or mirror these values.

## Core Principle

Workspace files should consume **5–10% of total context**. Bigger windows should NOT mean proportionally bigger system prompts — extra headroom goes to conversation history, tool outputs, and response buffer. Budget scaling should be **sub-linear**: doubling context from 131k→256k justifies ~1.5–1.7× budget increase, not 2×.

## Current Budgets (131k context window)

Conservative increase from the original lean baseline, backed by research that supports up to 2× ("Balanced" tier). May increase further if we move to 256k models or agents consistently need more room. The multiplier system (INFO ×1.25 / WARN ×1.50) stays unchanged.

| File | Base | INFO (×1.25) | WARN (×1.50) |
|------|------|-------------|-------------|
| AGENTS.md | **1,725** | 2,156 | 2,588 |
| SOUL.md | **525** | 656 | 788 |
| IDENTITY.md | **175** | 219 | 263 |
| USER.md | **715** | 894 | 1,073 |
| TOOLS.md | **525** | 656 | 788 |
| HEARTBEAT.md | **225** | 281 | 338 |
| MEMORY.md | **975** | 1,219 | 1,463 |
| **Total** | **4,865** | **6,081** | **7,298** |
| **% of 131k** | **3.7%** | **4.6%** | **5.6%** |

Adding typical tool schemas (~7,000 tokens) puts total system overhead at ~9.1% — well within the 10% ceiling.

## Future: 256k Context Window Budgets

If running 256k models, scale to ~1.6× of the current base (not 2×). These values provide richer files while staying under 5% of context.

| File | 256k Base | INFO (×1.25) | WARN (×1.50) |
|------|----------|-------------|-------------|
| AGENTS.md | 2,750 | 3,438 | 4,125 |
| SOUL.md | 850 | 1,063 | 1,275 |
| IDENTITY.md | 275 | 344 | 413 |
| USER.md | 1,150 | 1,438 | 1,725 |
| TOOLS.md | 850 | 1,063 | 1,275 |
| HEARTBEAT.md | 350 | 438 | 525 |
| MEMORY.md | 1,550 | 1,938 | 2,325 |
| **Total** | **7,775** | **9,719** | **11,663** |
| **% of 256k** | **3.0%** | **3.8%** | **4.6%** |

Override via env vars:

```bash
MEGALINT_BUDGET_AGENTS_MD=2750
MEGALINT_BUDGET_SOUL_MD=850
MEGALINT_BUDGET_IDENTITY_MD=275
MEGALINT_BUDGET_USER_MD=1150
MEGALINT_BUDGET_TOOLS_MD=850
MEGALINT_BUDGET_HEARTBEAT_MD=350
MEGALINT_BUDGET_MEMORY_MD=1550
```

## Multiplier System (unchanged)

The graduated scoring approach stays as-is:

- **Base** — target budget. Score is 100 at or below base.
- **INFO** (base × 1.25) — heads-up, approaching limit. 25% over.
- **WARN** (base × 1.50) — over budget, should trim. 50% over.
- **Score curve** — linear drop from 100 at base → 0 at 5× base.
- **Never blocking** — token budgets affect score only, never cause ERROR.

## Per-File Scaling Priorities

Not all files deserve equal scaling. Priority order for spending additional tokens:

1. **MEMORY.md** — highest ROI. User-specific, high-variance, directly impacts personalization quality. Scale first.
2. **AGENTS.md** — most critical structurally (injected into sub-agents too), but move procedures to Skills before growing this file.
3. **USER.md** — stable but benefits from richer preference capture.
4. **SOUL.md / TOOLS.md** — moderate scaling. Keep SOUL directive-focused, keep TOOLS terse.
5. **HEARTBEAT.md** — scale last. 48×/day injection means every token here costs ~48× more per day.
6. **IDENTITY.md** — minimal scaling. Name + emoji + tagline doesn't need more than 175 tokens.

## What NOT to Do

- **Don't scale proportionally with context window.** 131k→256k should be ~1.6× budget increase, not 2×.
- **Don't fill the budget just because it exists.** A file at 60% of budget is better than one padded to 100%.
- **Don't put procedures in AGENTS.md.** Move workflows to `skills/` — they load on-demand, not every turn.
- **Don't ignore HEARTBEAT.md cost.** 225 tokens × 48 fires/day = 10,800 tokens/day. Keep it lean even with the raised budget.

## Research References

- Anthropic context engineering guidance: context is "a finite resource with diminishing marginal returns"
- Chroma "Context Rot" study (July 2025): all 18 tested LLMs show non-uniform degradation as input grows
- Goldberg et al. "Same Task, More Tokens" (EMNLP 2025): reasoning degradation starts at ~3,000 tokens of input
- Liu et al. "Lost in the Middle" (TACL 2024): >30% performance drop for info in context middle vs. edges
- Claude Opus 4.6 MRCR benchmark: 17-point accuracy drop (93%→76%) from 200K→1M context
- OpenClaw GitHub Issue #9157: workspace file injection wastes 93.5% of token budget
- Community consensus: 5–10% of context for system prompt, remainder for conversation + tools + response
