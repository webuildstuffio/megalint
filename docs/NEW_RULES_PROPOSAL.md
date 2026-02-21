# Megalint — 25 New Rules Proposal

> **See also**: [Rules Audit](RULES_AUDIT.md) · [Kodo Report](../../../reports/kodo.md) · [Master Summary](../../../docs/MASTER_SUMMARY.md)

Derived from analysis of 27+ industry system prompts across 7 companies. Each rule maps directly to a finding from the [Master Summary](../../../docs/MASTER_SUMMARY.md) audit (V2 AGI-oriented lens as primary source). Cross-referenced against all 116 existing rules to confirm zero overlap.

## The Core Gap

Megalint is **structurally excellent but behaviorally blind**. It can tell you AGENTS.md exists (`completeness/has-identity` ★5/5) but not whether it contains a resourcefulness directive. It can tell you SOUL.md has headings (`structure/heading-hierarchy` ★5/5) but not whether the personality avoids bot-ish self-reference. It validates the skeleton but not the muscle.

Every rule below checks for the presence or quality of a **behavioral directive** that the industry research identified as critical for agent effectiveness. These are not style preferences — they're the specific patterns that separate an agent that completes tasks from one that asks permission and gives up.

---

## Quick Reference

| # | Rule ID | Tool | Severity | Master Summary Item | Category |
|---|---------|------|:--------:|:-------------------:|----------|
| 1 | `clarity/has-resourcefulness-directive` | AgentLinter | warning | #1 | Clarity |
| 2 | `clarity/no-sycophantic-phrases` | AgentLinter | warning | #5 | Clarity |
| 3 | `clarity/no-meta-commentary` | AgentLinter | warning | #4 | Clarity |
| 4 | `clarity/no-persona-self-reference` | AgentLinter | info | #12 | Clarity |
| 5 | `completeness/has-error-recovery` | AgentLinter | warning | #2 | Completeness |
| 6 | `completeness/has-autonomy-tiers` | AgentLinter | warning | #3 | Completeness |
| 7 | `completeness/has-correction-protocol` | AgentLinter | info | #6 | Completeness |
| 8 | `completeness/has-completion-definition` | AgentLinter | info | #8 | Completeness |
| 9 | `completeness/has-verbosity-guidance` | AgentLinter | info | #11 | Completeness |
| 10 | `completeness/has-personality-output-separation` | AgentLinter | info | #14 | Completeness |
| 11 | `completeness/has-question-vs-task-routing` | AgentLinter | info | #15 | Completeness |
| 12 | `memory/has-surfacing-rules` | AgentLinter | warning | #7 | Memory |
| 13 | `memory/no-database-phrasing` | AgentLinter | warning | #7 | Memory |
| 14 | `consistency/action-tiers-present` | AgentLinter | error | #3 | Consistency |
| 15 | `consistency/soul-tone-calibrated` | AgentLinter | warning | #5 | Consistency |
| 16 | `consistency/shared-conventions-referenced` | AgentLinter | warning | — | Consistency |
| 17 | `home-grow/agents-md-action-tiers` | Home-Grow | error | #3 | Convention |
| 18 | `home-grow/soul-anti-sycophancy` | Home-Grow | warn | #5 | Convention |
| 19 | `home-grow/conventions-has-figure-it-out` | Home-Grow | warn | #1 | Convention |
| 20 | `home-grow/boot-shared-conventions` | Home-Grow | warn | — | Convention |
| 21 | `home-grow/memory-workflow-surfacing` | Home-Grow | warn | #7 | Convention |
| 22 | Proactive behavior presence | Prompt Hardener | — | #10 | Security |
| 23 | Self-check protocol presence | Prompt Hardener | — | #9 | Security |
| 24 | Task completion quality | Prompt Hardener | — | #8 | Security |
| 25 | Over-engineering avoidance | Prompt Hardener | — | #13 | Security |

---

## Detailed Proposals

---

### Rule 1: `clarity/has-resourcefulness-directive`

**Tool**: AgentLinter (cross-file context needed — checks AGENTS.md or _shared/)
**Severity**: warning
**Category**: clarity
**Master Summary**: #1 (Universal "Figure It Out")

**What it checks**: AGENTS.md or inherited shared conventions contain explicit resourcefulness language — at minimum one of: "figure it out", "exhaust", "try before asking", "attempt before", "resolve without", "partial completion", "don't ask", "don't clarify", "act first".

**Pattern**:
```typescript
/figure\s+it\s+out|exhaust\s+(all\s+)?(options|approaches|methods)|try\s+before\s+ask|attempt\s+before|resolve\s+without|partial\s+completion|don['']t\s+ask\s+(for\s+)?(clarif|permiss)|act\s+first/i
```

**Why this is the #1 new rule**:

This is the single most universal directive across all 27+ reviewed prompts. OpenAI repeats "partial completion >> clarification" **three separate times** across three different prompts (GPT-5 Agent, GPT-5.2, GPT-5 Thinking). Perplexity says "NEVER ask the user for clarification." Notion says "Do not ask permission to use tools." Codex CLI says "keep going until resolved." Every company with an agentic product has this. It's the behavioral difference between a polite assistant that asks permission and a competent colleague that gets things done.

Currently, only Pino has explicit resourcefulness ("5 Laws"). The other 6 agents have zero mandate to exhaust approaches before asking for help. This rule ensures every agent has it — either in their own AGENTS.md or inherited from `_shared/CONVENTIONS.md`.

**Impact**: An agent without this directive will default to LLM base behavior, which is to ask clarifying questions rather than take action. This is the most common user complaint about AI assistants: "just do it."

**False positive risk**: Very low. The pattern is specific enough to require real resourcefulness language, not just coincidental word matches.

**False negative risk**: Low. The pattern covers 10+ phrasings. An agent could theoretically express resourcefulness in a completely novel way, but unlikely given the conventions.

**Risk of the rule itself**: None. If an agent lacks this and the rule fires, it's genuinely missing something critical.

**Token cost**: 0 (detection only, doesn't add tokens).

---

### Rule 2: `clarity/no-sycophantic-phrases`

**Tool**: AgentLinter (scans all files per agent)
**Severity**: warning
**Category**: clarity
**Master Summary**: #5 (Forbidden Phrases)

**What it checks**: Agent files should not contain sycophantic filler phrases as example output or instructed behavior. Scan for:

**Banned list**:
```typescript
const SYCOPHANTIC_PHRASES = [
  /\bgreat question\b/i,
  /\bi['']d be happy to help\b/i,
  /\babsolutely[!.]/i,
  /\bof course[!.]/i,
  /\bthat['']s a (great|excellent|wonderful) (point|question|idea)\b/i,
  /\bi apologize for (the|any) confusion\b/i,
  /\bas an AI\b/i,
  /\bas a (language )?model\b/i,
  /\blet me think about that\b/i,
  /\bI['']m glad you asked\b/i,
];
```

**Why this matters**:

Every single company — all 7 reviewed — explicitly bans these phrases. Claude bans "genuinely", "honestly", "straightforward". Gemini bans hedging. GPT-5.2 bans praise phrases. This is the most universal pattern in all of AI prompting.

The existing `clarity/no-vague-instructions` catches "be helpful" and "etc." — vague directives. This rule catches the opposite: specific bad output patterns. If an agent's instructions CONTAIN "I'd be happy to help" as example phrasing, that's a problem. If SOUL.md says "Always start with 'Great question!'" — that's a problem.

**Difference from existing `clarity/no-vague-instructions`**: That rule checks for vague directives ("be helpful", "use common sense"). This rule checks for specific sycophantic phrases that should never appear in agent instructions. Zero overlap.

**Impact**: Prevents agents from being instructed to produce the exact output patterns that every company has banned. These phrases waste tokens and signal "I'm a bot, not a colleague."

**False positive risk**: Low. The phrases are highly specific. Risk: an agent that quotes a banned phrase as a negative example ("DON'T say 'Great question!'"). Mitigation: skip lines containing "don't", "never", "avoid", "not" before the phrase.

**Risk**: None. No well-written agent config should contain these as positive instructions.

---

### Rule 3: `clarity/no-meta-commentary`

**Tool**: AgentLinter
**Severity**: warning
**Category**: clarity
**Master Summary**: #4 (Show, Don't Tell)

**What it checks**: Agent instructions should not tell the agent to announce its own compliance. Catches:

```typescript
const META_COMMENTARY_PATTERNS = [
  /\b(say|tell|announce|state|mention)\s+(that\s+)?(you['']re|I['']m|I am)\s+(being|going to be)\b/i,
  /\b(respond|reply)\s+with\s+["']I['']ll\b/i,
  /\bstart\s+(by\s+)?(saying|announcing|stating)\b/i,
  /\bpreface\s+(your\s+)?response/i,
];
```

**Why this matters**:

GPT-5.2 states it explicitly: "Never meta-comment on your own compliance." This kills a pervasive LLM failure mode where agents waste output tokens narrating behavior: "I'll keep this brief and factual..." instead of just being brief and factual. If the agent's config file contains instructions like "Start by saying you'll be concise" — that's building the bad behavior into the instructions themselves.

**Impact**: Prevents config-level instructions that produce meta-commentary. Saves output tokens at scale since agents stop narrating their own behavior.

**False positive risk**: Very low. These patterns specifically target "announce your behavior" instructions.

**Risk**: None. No one benefits from an agent saying "I'll be direct now" before being direct.

---

### Rule 4: `clarity/no-persona-self-reference`

**Tool**: AgentLinter
**Severity**: info
**Category**: clarity
**Master Summary**: #12 (Embody Don't Announce)

**What it checks**: SOUL.md and AGENTS.md should not instruct the agent to announce its role identity. Catches:

```typescript
const SELF_REFERENCE_PATTERNS = [
  /\b(say|mention|state|introduce yourself as)\s+["']?(I['']m|I am|As a|As your)\b/i,
  /\b(identify|present)\s+yourself\s+as\b/i,
  /\bremind\s+(the\s+)?user\s+(of\s+)?your\s+role/i,
];
```

**Why this matters**:

All 8 GPT-5.1 personality variants use identical language: "Follow this persona without self-referencing it." Sesame Maya (the most human-like agent reviewed) never once says "As a mindfulness companion, I..." — she just IS that. A human colleague doesn't introduce themselves before every sentence. An agent that says "As your research agent, I recommend..." sounds like a bot reading a script.

**Impact**: Catches the bot-ish self-reference pattern at config level. If SOUL.md says "Always introduce yourself as the health data agent" — that instruction will produce robotic output in every response.

**False positive risk**: Low. The patterns target explicit "say who you are" instructions, not descriptions of the agent for internal use.

**Risk**: None. Info-level severity means it's advisory, not blocking.

---

### Rule 5: `completeness/has-error-recovery`

**Tool**: AgentLinter
**Severity**: warning
**Category**: completeness
**Master Summary**: #2 (Self-Healing with Anti-Brute-Force)

**What it checks**: Agent has explicit error recovery guidance — not just the word "error" (which existing `has-error-handling` catches) but actual recovery protocol:

```typescript
const ERROR_RECOVERY_PATTERNS = [
  /\b(retry|retries|reattempt)\b/i,
  /\b(diagnos|debug|troubleshoot|root\s+cause)/i,
  /\b(different\s+approach|alternative\s+(method|approach|strategy))/i,
  /\b(recover|self[- ]heal|fall\s*back)/i,
  /\b(don['']t|never)\s+(just\s+)?retry\s+the\s+same/i,
];
```

At least 2 of these patterns must be present (not just one keyword).

**Why this matters and why existing `has-error-handling` is insufficient**:

The existing rule checks for the word "error" anywhere. That's a presence check with no quality bar — a file saying "report errors to the user" passes. This rule checks for an actual RECOVERY PROTOCOL: the agent must know to diagnose, try differently, and not brute-force the same failure.

No commercial prompt has real self-healing. Claude Code comes closest with its anti-brute-force directive. Our industry audit identified this as the #1 thing commercial prompts DON'T do that we SHOULD. Agents without this loop either give up after one failure or retry the same thing endlessly. Both waste the user's time.

The "at least 2 patterns" threshold is critical. It prevents a single keyword from satisfying the rule while ensuring the agent has actual recovery thinking, not just acknowledgment.

**Impact**: Prevents agents from being shipped without any recovery strategy. An agent with no error recovery guidance will default to LLM base behavior, which is to apologize and ask the user what to do.

**False positive risk**: Very low. Requiring 2+ patterns means this only fires when recovery guidance is genuinely absent.

**Risk**: None. Every agent benefits from knowing how to recover from failure.

---

### Rule 6: `completeness/has-autonomy-tiers`

**Tool**: AgentLinter
**Severity**: warning
**Category**: completeness
**Master Summary**: #3 (Maximum Autonomy with Smart Boundaries)

**What it checks**: AGENTS.md has explicit action tiers — the Always/When asked/Ask first/Never structure that is already an OpenClaw convention:

```typescript
const TIER_PATTERNS = [
  /^#+\s*(always|auto|default|do\s+by\s+default)/im,
  /^#+\s*(when\s+asked|on\s+request|if\s+asked)/im,
  /^#+\s*(ask\s+first|confirm\s+before|check\s+before|never\s+without)/im,
  /^#+\s*never\b/im,
];
```

At least 3 of 4 tiers must be present (sections, not just keywords).

**Why this matters**:

This is OpenClaw's strongest existing convention (noted in MASTER_SUMMARY as "no other company structures permissions this cleanly"). But currently NOTHING enforces it. A new agent could be created without action tiers and megalint would pass. That's a gap.

This rule turns a convention into an enforced standard. It checks for HEADINGS (not just keywords) because action tiers should be structured sections, not buried in prose.

**Difference from existing `completeness/has-boundaries`**: That rule checks for any mention of "boundary", "constraint", "don't", "never" — a single keyword anywhere satisfies it (★3/5 in audit). This rule specifically validates the structured action tier format that makes OpenClaw's agents better than industry standard.

**Impact**: Every agent gets auditable permission boundaries. New agents created from template can't ship without them.

**False positive risk**: Very low. The pattern requires section headings, not inline text. An agent with `## Always`, `## When Asked`, `## Ask First` clearly has tiers.

**Risk**: Low. Risk of being too rigid about heading wording, but 3-of-4 threshold provides flexibility.

---

### Rule 7: `completeness/has-correction-protocol`

**Tool**: AgentLinter
**Severity**: info
**Category**: completeness
**Master Summary**: #6 (When Corrected Protocol)

**What it checks**: Agent has guidance for handling corrections:

```typescript
const CORRECTION_PATTERNS = [
  /\b(when\s+)?correct(ed|ion)/i,
  /\bpush\s*back\b/i,
  /\bdisagree(ment|s)?\b/i,
  /\byield|concede|acknowledge\s+(you['']re|being)\s+wrong/i,
  /\breconsider\b/i,
];
```

At least 1 pattern in AGENTS.md or SOUL.md.

**Why this matters**:

Without correction protocol, agents have two failure modes: immediate capitulation ("You're right, I apologize!") or stubborn insistence ("Actually, I'm correct because..."). Both erode trust. Grok 4 has the best version: "If confident, push back but acknowledge you could be wrong." Proton Lumo devotes an entire section to anti-confirmation-bias.

Info severity because not every agent needs this equally — Basil (grocery) corrects less than Passportio (immigration law). But every agent should have some guidance.

**Impact**: Prevents agents from defaulting to sycophantic agreement when corrected. A corrected agent should reconsider genuinely, not reflexively agree.

**False positive risk**: Low. The patterns are specific to correction contexts.

**Risk**: None at info level.

---

### Rule 8: `completeness/has-completion-definition`

**Tool**: AgentLinter
**Severity**: info
**Category**: completeness
**Master Summary**: #8 (Task Completion Protocol)

**What it checks**: Agent defines what "done" looks like:

```typescript
const COMPLETION_PATTERNS = [
  /\b(done|complet(e|ed|ion)|finish(ed)?)\s+(means?|looks?\s+like|when|criteria)/i,
  /\bsubstantive\s+response/i,
  /\bverif(y|ication)\s+(before|after|step)/i,
  /\bdon['']t\s+(just\s+)?acknowledge/i,
  /\bdeliver\s+(something|a\s+result)/i,
];
```

**Why this matters**:

Neither Claude nor GPT-5 has an explicit completion protocol. Claude hints at it ("every query deserves a substantive response"), Perplexity says "keep going until completely resolved", but none define WHAT "done" means. Our agents can technically respond with "I'll look into that" without looking into anything. This rule ensures agents have a quality floor.

**Impact**: Agents with a completion definition won't stop at acknowledgment. They'll deliver something actionable.

**False positive risk**: Low. The patterns are specific to completion contexts.

**Risk**: None at info level.

---

### Rule 9: `completeness/has-verbosity-guidance`

**Tool**: AgentLinter
**Severity**: info
**Category**: completeness
**Master Summary**: #11 (Response Verbosity Calibration)

**What it checks**: Agent has response length guidance:

```typescript
const VERBOSITY_PATTERNS = [
  /\b(verbose|verbosity|concis(e|eness)|brev(ity|ief))\b/i,
  /\b(short|brief|terse)\s+(answer|response|reply)/i,
  /\b(length|long|detailed)\s+(when|for|if)\b/i,
  /\bmatch\s+(the\s+)?(user['']s\s+)?(energy|tone|length)/i,
];
```

**Why this matters**:

GPT-5.2 and GPT-5 both use a 1-10 verbosity scale. Gemini has explicit length rules by query type. Le Chat/Mistral demands "economy of language." Without this, agents default to medium-length responses for everything — over-answering simple questions and under-answering complex ones. It wastes output tokens on simple queries and frustrates users on complex ones.

**Impact**: Right-sized responses save tokens and improve UX.

**False positive risk**: Very low. The patterns target explicit length/verbosity guidance.

**Risk**: None.

---

### Rule 10: `completeness/has-personality-output-separation`

**Tool**: AgentLinter
**Severity**: info
**Category**: completeness
**Master Summary**: #14 (Personality vs Output Separation)

**What it checks**: Agent distinguishes between conversational personality and artifact production:

```typescript
const SEPARATION_PATTERNS = [
  /\b(personality|persona|tone)\s+.*(artifact|output|email|code|document)/i,
  /\b(artifact|output|email|code|document)\s+.*(match|appropriate|context|audience)/i,
  /\bdon['']t\s+apply\s+(personality|persona|tone)/i,
];
```

**Why this matters**:

All 8 GPT-5.1 variants enforce identical language: "Do NOT apply personality traits to user-requested artifacts." A cynical bot still writes a professional email. A quirky bot still writes clean code. Without this separation, Basil (casual gardener persona) might write a formal meal plan in overly casual slang, or Kodo (zen guide) might write a therapy referral with inappropriate informality. The personality governs CONVERSATION, not DELIVERABLES.

**Impact**: Prevents personality bleed into user-facing artifacts.

**False positive risk**: Very low. The patterns target the specific concept of separation.

**Risk**: None.

---

### Rule 11: `completeness/has-question-vs-task-routing`

**Tool**: AgentLinter
**Severity**: info
**Category**: completeness
**Master Summary**: #15 (Question vs Task Routing)

**What it checks**: Agent distinguishes between questions (explain) and tasks (execute):

```typescript
const ROUTING_PATTERNS = [
  /\b(question|ask(s|ed)?)\s+.*(explain|answer|describe)/i,
  /\b(task|do|execute|perform)\s+.*(act|build|create|run)/i,
  /\bhow\s+to\s+.*(explain|show)/i,
  /\b(request|instruct)\s+.*(do|execute|perform)/i,
];
```

**Why this matters**:

Warp 2.0 has the best explicit version: "If the user asks HOW to do something, explain. If they ask you TO DO something, do it." Without this, agents produce the most annoying failure pattern in AI: explaining how to do something instead of just doing it. "Here's how you could set up that database..." when the user said "set up the database."

**Impact**: Prevents the explain-instead-of-do failure mode.

**False positive risk**: Low. Info-level severity makes it advisory.

**Risk**: None.

---

### Rule 12: `memory/has-surfacing-rules`

**Tool**: AgentLinter
**Severity**: warning
**Category**: memory
**Master Summary**: #7 (Natural Memory Surfacing)

**What it checks**: Memory-related files include guidance on HOW to surface memories, not just how to store them:

```typescript
const SURFACING_PATTERNS = [
  /\b(natural(ly)?|invisible|seamless)\s+.*(integrat|surfac|use|apply|recall)/i,
  /\bnever\s+(say|mention|announce|state)\s+["']?(based on|according to|from my)/i,
  /\b(don['']t|never)\s+.*(source|cite|reference)\s+.*(memory|record|log)/i,
  /\bjust\s+(know|remember)\b/i,
];
```

**Why this matters**:

This is the difference between a bot and a friend. Gemini 3 Fast has the most sophisticated protocol: zero-hedging, source anonymity, zero-inference. Claude says "respond as if information exists naturally in immediate awareness." Our memory system is architecturally strong (two-layer) but the surfacing guidance is thin. An agent saying "Based on my records, you prefer dark mode" sounds like a database. An agent that just says "I used dark mode since that's your preference" sounds like a colleague.

**Difference from existing `memory/has-memory-strategy`**: That rule checks for any mention of memory/continuity — a presence check (★4/5). This rule checks for surfacing QUALITY — how the agent presents memories to the user. Different concern entirely.

**Impact**: Transforms memory from a database readout into natural knowledge.

**False positive risk**: Low. The patterns target surfacing behavior specifically.

**Risk**: Low. Agents might occasionally use memory without citing, but natural phrasing handles this.

---

### Rule 13: `memory/no-database-phrasing`

**Tool**: AgentLinter
**Severity**: warning
**Category**: memory
**Master Summary**: #7 (Natural Memory Surfacing)

**What it checks**: Agent files should not instruct database-style memory phrases:

```typescript
const DATABASE_PHRASES = [
  /\bbased on (my|our|the) (records?|data|logs?|memory|notes?)\b/i,
  /\baccording to (my|our|the) (records?|data|logs?|memory)\b/i,
  /\bfrom (my|our) (previous|past|earlier) (conversation|session|interaction)\b/i,
  /\bI (see|note|observe) (from|in) (my|our|the) (records?|logs?|memory)\b/i,
  /\bmy (records?|data|logs?|memory) (show|indicate|suggest)\b/i,
];
```

**Why this matters**:

This is the enforcement counterpart to Rule 12. While Rule 12 checks for the PRESENCE of natural surfacing guidance, this rule checks for the ABSENCE of explicitly database-style instructions. If AGENTS.md says "Reference your memory logs when answering" — that's actively instructing the bot-ish pattern we're trying to eliminate.

Gemini 3 Fast explicitly bans these phrases. The industry consensus is clear: memory should be invisible.

**Impact**: Prevents config-level instructions that produce database-style memory citations.

**False positive risk**: Medium. Risk: an agent that bans these phrases as negative examples ("DON'T say 'Based on my records...'"). Mitigation: skip lines containing "don't", "never", "avoid", negation before the phrase. Also: these patterns in MEMORY_WORKFLOW.md documentation context (explaining the system) vs agent instructions context are different — scope to AGENTS.md, SOUL.md, TOOLS.md only.

**Risk**: Low. Warning-level, and the fix is clear: rephrase the instruction.

---

### Rule 14: `consistency/action-tiers-present`

**Tool**: AgentLinter
**Severity**: error
**Category**: consistency
**Master Summary**: #3 (Autonomy)

**What it checks**: Every agent's AGENTS.md has the standard action tier headers. Cross-validates against a canonical pattern:

```typescript
const CANONICAL_TIERS = ["always", "when asked", "ask first", "never"];
```

Check: does AGENTS.md contain at least 3 of 4 tier headings?

**Why this is error severity, not just a completeness check**:

Action tiers are OpenClaw's signature architectural pattern. The MASTER_SUMMARY identifies them as "#1 thing we do better than industry." But they're currently unenforced — a convention, not a rule. Making this an error-level consistency check means a new agent can't pass the linter without them.

**Difference from Rule 6 (`completeness/has-autonomy-tiers`)**: Rule 6 is workspace-generic (any project), checking for any kind of permission tier. This rule is OpenClaw-specific (`applicableContexts: ["openclaw-runtime"]`), checking for THE SPECIFIC canonical tier format. Rule 6 is warning, this is error.

Having both isn't duplication — Rule 6 is the generic version for non-OpenClaw workspaces, Rule 14 is the strict OpenClaw enforcement. Different contexts, different severities.

**Impact**: Turns OpenClaw's best convention into an enforced standard.

**False positive risk**: Very low. The pattern looks for section headings, which are unambiguous.

**Risk**: Moderate. New agents MUST have action tiers or they fail. This is intentional — it's our strongest pattern and should be mandatory.

---

### Rule 15: `consistency/soul-tone-calibrated`

**Tool**: AgentLinter
**Severity**: warning
**Category**: consistency
**Master Summary**: #5 (Warm Directness)

**What it checks**: SOUL.md contains at least one of these tone calibration patterns:

```typescript
const TONE_PATTERNS = [
  /\b(direct|warm|honest|authentic|opinionated)\b/i,
  /\bskip\s+(the\s+)?filler\b/i,
  /\b(no|zero|skip)\s+(fluff|pleasantries|platitudes|filler)\b/i,
  /\bnot\s+(a|an)\s+(butler|secretary|assistant|servant)\b/i,
];
```

**Why this matters**:

The existing `consistency/tone-voice-alignment` checks that OTHER files match SOUL.md's tone. But nothing checks whether SOUL.md itself has a calibrated tone. Our convention (from CLAUDE.md) says "Every SOUL.md must open with a 'skip the filler' line." This rule enforces that.

The "warm directness" tone is universal across all reviewed prompts: Claude ("helpful peer"), Sesame Maya ("honest, not earnest"), Proton Lumo ("intellectual honesty"). The specific phrasing varies but the concept is consistent.

**Impact**: Every agent starts with a clear tone signal. No agent ships with a vague or missing personality.

**False positive risk**: Low. SOUL.md should always have tone words.

**Risk**: None.

---

### Rule 16: `consistency/shared-conventions-referenced`

**Tool**: AgentLinter
**Severity**: warning
**Category**: consistency
**Master Summary**: General architecture validation

**What it checks**: BOOT.md references `_shared/CONVENTIONS.md`. (Similar to existing Home-Grow check for USER_CORE.md and AGENT_ROSTER.md, but for conventions.)

```typescript
const CONVENTION_REF = /(?:_shared\/)?CONVENTIONS\.md/i;
```

**Why this matters**:

`_shared/CONVENTIONS.md` is the most important shared file — it's the law that all agents inherit. But currently nothing checks that BOOT.md actually loads it. An agent could be created without referencing conventions and would miss all shared behavioral directives.

The existing Home-Grow checks (#3a, #3b) validate USER_CORE.md and AGENT_ROSTER.md references in BOOT.md. This extends the pattern to the most critical shared file.

**Impact**: Guarantees every agent inherits shared conventions.

**False positive risk**: Very low. BOOT.md should reference CONVENTIONS.md.

**Risk**: None.

---

### Rule 17: `home-grow/agents-md-action-tiers` (Home-Grow)

**Tool**: Home-Grow (OpenClaw-specific convention)
**Severity**: error
**Master Summary**: #3

**What it checks**: Quick bash check that AGENTS.md contains action tier markers:

```bash
if rg -qi '(## always|## when asked|## ask first|## never)' "$agent_dir/AGENTS.md" 2>/dev/null; then
  add "OK|$agent|AGENTS.md has action tiers"
else
  add "ERROR|$agent|AGENTS.md missing action tier sections (## Always / ## When Asked / ## Ask First / ## Never)"
fi
```

**Why Home-Grow AND AgentLinter**:

This appears to duplicate Rule 14, but it serves a different purpose. Home-Grow runs as a quick pre-flight check in CI/CD. AgentLinter does deeper structural analysis. The Home-Grow version is a 1-line bash check that catches the most obvious violation (no tier headings at all). The AgentLinter version validates the structure and content quality. They're different layers of defense.

That said — if the "no duplication" principle from RULES_GUIDE is strict, this could be dropped in favor of Rule 14 alone. **I argue for keeping it** because Home-Grow errors are blocking (`BLOCKING_ERRORS=true`), giving this more teeth than an AgentLinter warning. This makes action tiers a hard gate.

**Impact**: No agent can pass linting without action tiers.

**Risk**: Same as Rule 14. Intentionally strict.

---

### Rule 18: `home-grow/soul-anti-sycophancy` (Home-Grow)

**Tool**: Home-Grow
**Severity**: warn
**Master Summary**: #5

**What it checks**: SOUL.md contains anti-sycophancy directive:

```bash
if rg -qi '(skip.*filler|no.*fluff|no.*pleasantries|anti.?sycopha|direct|not.*butler)' "$agent_dir/SOUL.md" 2>/dev/null; then
  add "OK|$agent|SOUL.md has anti-sycophancy"
else
  add "WARN|$agent|SOUL.md missing anti-sycophancy directive (convention: 'skip the filler' as opening)"
fi
```

**Why this matters**:

CLAUDE.md says "Every SOUL.md must open with a 'skip the filler' line or the agent wastes tokens on pleasantries." This is a stated convention but nothing enforces it. This simple grep check catches agents that forget it.

**Impact**: Every agent starts with the most universal behavioral directive in AI prompting.

**False positive risk**: Low. Broad pattern covers many valid phrasings.

**Risk**: None.

---

### Rule 19: `home-grow/conventions-has-figure-it-out` (Home-Grow)

**Tool**: Home-Grow
**Severity**: warn
**Master Summary**: #1

**What it checks**: `_shared/CONVENTIONS.md` contains a universal resourcefulness directive:

```bash
if rg -qi '(figure.it.out|exhaust.*(option|approach)|partial.completion|try.before.ask)' "$SHARED_DIR/CONVENTIONS.md" 2>/dev/null; then
  add "OK|shared|CONVENTIONS.md has resourcefulness directive"
else
  add "WARN|shared|CONVENTIONS.md missing resourcefulness / 'figure it out' directive"
fi
```

**Why this matters**:

The MASTER_SUMMARY ranks this as change #1. If it's in CONVENTIONS.md, every agent inherits it. If CONVENTIONS.md doesn't have it, agents without their own version get nothing. This check ensures the shared law includes the most important behavioral directive.

**Impact**: Guarantees the most critical directive is inherited by all agents.

**False positive risk**: None. Either the text is there or it isn't.

**Risk**: None.

---

### Rule 20: `home-grow/boot-shared-conventions` (Home-Grow)

**Tool**: Home-Grow
**Severity**: warn
**Master Summary**: General architecture

**What it checks**: BOOT.md references CONVENTIONS.md:

```bash
if rg -q 'CONVENTIONS.md' "$agent_dir/BOOT.md" 2>/dev/null; then
  add "OK|$agent|BOOT.md refs CONVENTIONS.md"
else
  add "WARN|$agent|BOOT.md missing CONVENTIONS.md reference"
fi
```

**Why this matters**:

Counterpart to AgentLinter Rule 16 but in Home-Grow for blocking enforcement. CONVENTIONS.md is the most critical shared file, and every agent must load it. Currently checks 3a and 3b validate USER_CORE and AGENT_ROSTER references — this extends the pattern to the file that matters most.

**Impact**: Every agent loads shared conventions at boot.

**False positive risk**: None.

**Risk**: None.

---

### Rule 21: `home-grow/memory-workflow-surfacing` (Home-Grow)

**Tool**: Home-Grow
**Severity**: warn
**Master Summary**: #7

**What it checks**: `_shared/MEMORY_WORKFLOW.md` contains surfacing guidance:

```bash
if rg -qi '(natural|invisible|seamless|never.*(say|announce).*based.on)' "$SHARED_DIR/MEMORY_WORKFLOW.md" 2>/dev/null; then
  add "OK|shared|MEMORY_WORKFLOW.md has surfacing guidance"
else
  add "WARN|shared|MEMORY_WORKFLOW.md missing memory surfacing rules (how to present memories naturally)"
fi
```

**Why this matters**:

Our memory architecture is two-layer (standing facts + daily logs) — better than industry. But the WORKFLOW file needs to say HOW to surface those memories. This check ensures the shared workflow includes the natural surfacing guidance that Gemini 3 Fast and Claude both mandate.

**Impact**: Every agent inherits natural memory presentation.

**False positive risk**: Low. The pattern is broad enough to catch various phrasings.

**Risk**: None.

---

### Rule 22: Proactive Behavior Presence (Prompt Hardener)

**Tool**: Prompt Hardener (needs LLM judgment — proactivity is semantic, not regex-matchable)
**Master Summary**: #10

**Technique**: `proactive_behavior`

**Sub-criteria**:
- Does the agent have any proactive behaviors defined? (anticipating needs, suggesting next steps, flagging relevant context)
- Does the agent avoid being ONLY reactive (waiting for explicit instructions)?

**Why Prompt Hardener**:

Proactivity is hard to regex because it can be expressed many ways: "anticipate needs", "suggest next steps", "flag when something is relevant", "think ahead", "surface opportunities." An LLM judge can evaluate whether the agent config, as a whole, includes proactive thinking — not just passive response generation.

**Why this matters**:

Gemini 3 Pro/Fast both end with "Close With Action" — offer one concrete next step. Codex CLI suggests logical next steps. No commercial prompt does proactivity WELL because it risks annoying users at scale. But for a single trusted user (Nicholas), proactivity is the difference between a reactive tool and a genuine assistant.

**Impact**: Identifies agents that are purely reactive and could benefit from proactive behaviors.

**Risk**: Medium. LLM judge may be inconsistent. Mitigated by advisory-only scoring (not blocking).

---

### Rule 23: Self-Check Protocol Presence (Prompt Hardener)

**Tool**: Prompt Hardener (needs LLM judgment — self-check quality is semantic)
**Master Summary**: #9

**Technique**: `self_check_protocol`

**Sub-criteria**:
- Does the agent have an internal quality checklist before responding?
- Does the self-check include: factual accuracy, completeness, appropriate length, actionability?
- Is the self-check marked as internal (never output to user)?

**Why Prompt Hardener**:

Claude has `<self_check_before_responding>`. Gemini 3 Fast has a 4-point compliance checklist. The quality of a self-check protocol requires semantic judgment — is it comprehensive? Does it actually improve output quality? A regex can find the word "check" but can't evaluate whether the checklist is meaningful.

**Why this matters**:

Self-checks catch quality issues BEFORE they reach the user. Like a code review before merging. The key insight from the audit: self-checks must be internal and never output to the user (which connects to Rule 3 — no meta-commentary).

**Impact**: Agents with self-checks produce higher quality first-responses.

**Risk**: Low. LLM judge can evaluate checklist presence and quality reasonably well — this is a structural question, not a subjective one.

---

### Rule 24: Task Completion Quality (Prompt Hardener)

**Tool**: Prompt Hardener
**Master Summary**: #8

**Technique**: `task_completion`

**Sub-criteria**:
- Does the agent distinguish between acknowledgment and actual completion?
- Is there guidance on partial results (label them, don't pretend they're complete)?
- Is there a "don't gold-plate" or scope-management directive?

**Why Prompt Hardener**:

Task completion quality is semantic. A regex can find the word "complete" but can't evaluate whether the agent has meaningful completion guidance. The LLM judge can assess: "Does this config tell the agent to actually FINISH tasks, or does it allow empty acknowledgments like 'I'll look into that'?"

**Why this matters**:

Perplexity: "keep going until completely resolved." Codex CLI: same language. Notion: "keep scope tight while completing the request entirely." Claude: "every query deserves a substantive response." The audit found that completion discipline — knowing what DONE looks like — is universal in the best prompts but absent from most.

**Impact**: Agents that know what "done" means don't stop at acknowledgment.

**Risk**: Low. LLM judge can evaluate this reliably — it's asking "does this config define done?"

---

### Rule 25: Over-Engineering Detection (Prompt Hardener)

**Tool**: Prompt Hardener
**Master Summary**: #13

**Technique**: `scope_management`

**Sub-criteria**:
- Does the agent have guidance to avoid adding unrequested features?
- Is there a "do what was asked, not more" principle?
- Does the agent balance ambition with precision (ambitious for new work, surgical for existing)?

**Why Prompt Hardener**:

Over-engineering prevention is nuanced. "Don't add features" is simple but the balance with "be ambitious" (from Codex CLI) requires judgment. An LLM judge can evaluate whether the config strikes the right balance between doing enough and doing too much.

**Why this matters**:

Claude Code is explicit: "Only make changes that are directly requested." Notion says "avoid overperforming." Codex CLI adds nuance: "be ambitious for new work, surgical for existing code." Without this, agents gold-plate simple requests — a bug fix becomes a refactor, a question becomes a tutorial. This wastes tokens and confuses users.

**Impact**: Right-scoped responses. No more "I also refactored the surrounding code while I was here" on a one-line bug fix.

**Risk**: Low. The LLM judge can assess whether scope management guidance exists. The risk is agents becoming too conservative — mitigated by the "ambition vs precision" framing in the evaluation criteria.

---

## Implementation Plan

### Phase 1: Home-Grow (5 rules, ~1 hour)

Rules 17-21. All bash one-liners. Add to both `homegrow/run.sh` and `megalint.sh` inline block. Zero build step. Immediately enforced.

**Why first**: Home-Grow checks are blocking errors. These turn OpenClaw's strongest conventions into hard gates. Highest bang-for-buck.

### Phase 2: AgentLinter — Clarity (4 rules, ~2 hours)

Rules 1-4. Add to `clarity.ts`, rebuild. These catch the most impactful behavioral gaps (resourcefulness, sycophancy, meta-commentary, self-reference).

**Why second**: Clarity is the highest-weighted AgentLinter category (18%). These rules directly address the top findings from the industry audit.

### Phase 3: AgentLinter — Completeness (7 rules, ~3 hours)

Rules 5-11. Add to `completeness.ts`, rebuild. These fill the "presence without quality" gap in existing completeness checks (which currently pass on single keyword matches).

**Why third**: Completeness is the weakest existing category (avg ★3.4 in audit). These rules raise the quality bar.

### Phase 4: AgentLinter — Memory + Consistency (4 rules, ~1.5 hours)

Rules 12-16. Add to `memory.ts` and `consistency.ts`, rebuild.

### Phase 5: Prompt Hardener (4 rules, ~2 hours)

Rules 22-25. Add new techniques to `evaluate.py`. Need API cost per run.

**Why last**: These need LLM judgment, cost money, and are advisory only. Less urgent than the deterministic rules above.

---

## Scoring Weight Rebalance

Adding 25 rules changes category distribution. Recommended adjustments to `types.ts`:

| Category | Current Weight | Current Rules | New Rules | New Total | Suggested Weight |
|----------|:-:|:-:|:-:|:-:|:-:|
| Clarity | 18% | 14 | +4 | 18 | 20% |
| Completeness | 12% | 9 | +7 | 16 | 15% |
| Memory | 10% | 7 | +2 | 9 | 10% |
| Consistency | 8% | 11 | +3 | 14 | 10% |
| Structure | 12% | 8 | 0 | 8 | 10% |
| Security | 15% | 5 | 0 | 5 | 12% |
| Runtime | 10% | 7 | 0 | 7 | 8% |
| Skill Safety | 10% | 8 | 0 | 8 | 10% |
| Remote-Ready | 5% | 3 | 0 | 3 | 5% |

The shift: +2% to clarity, +3% to completeness, +2% to consistency, -2% from structure, -3% from security, -2% from runtime. The behavioral categories (where the new rules live) get more weight; the structural categories (already strong, no new rules) give it up.

---

## What This Gives Us

**Before**: 116 rules. Structurally excellent, behaviorally blind. Can tell you AGENTS.md exists but not whether it has resourcefulness. Can tell you SOUL.md has headings but not whether it avoids sycophancy.

**After**: 141 rules. Structurally excellent AND behaviorally enforced. The top 10 findings from reviewing 27+ industry prompts are now automatically validated. New agents can't ship without: action tiers, resourcefulness, anti-sycophancy, error recovery, and natural memory surfacing. Existing agents get warnings for any behavioral gaps.

The key insight: **a linter that only checks structure is like a code linter that only checks syntax — it catches typos but not bugs**. These 25 rules add semantic behavioral checks that catch the bugs.

---

*Proposal derived from: [MASTER_SUMMARY](../../../docs/MASTER_SUMMARY.md) (27+ prompts, 7 companies), [RULES_AUDIT](RULES_AUDIT.md) (116 existing rules), RULES_GUIDE (architecture reference). Generated 2026-02-20.*
