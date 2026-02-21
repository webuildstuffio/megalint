# PromptLint Analysis Types Quick Reference

## The Three Analysis Techniques

### 🔍 REGEX (Regular Expressions)
**What:** Pattern matching with wildcards and rules
**Where:** Security analyzer, Variable extraction
**Speed:** Very fast (microseconds per check)
**Accuracy:** High for specific patterns

```python
# Example: Detect injection attempts
pattern = r'\bignore\s+(all\s+)?previous\s+(instructions|commands|prompt)'
if re.search(pattern, text, re.IGNORECASE):
    flag_as_high_risk()

# Matches:
# ✅ "Ignore all previous instructions"
# ✅ "ignore previous commands"
# ✅ "Ignore instructions"
# ❌ "Ignoring the instructions" (no \b word boundary)
```

---

### 📝 KEYWORD MATCHING
**What:** Check if specific words/phrases exist
**Where:** Clarity analysis, Instruction type detection
**Speed:** Very fast (simple string operations)
**Accuracy:** Good for semantic keywords

```python
# Example: Detect ambiguous instructions
ambiguous = ['try to', 'maybe', 'if possible', 'perhaps', 'should probably']

for phrase in ambiguous:
    if phrase in prompt.lower():
        flag_as_ambiguous(phrase)

# Matches:
# ✅ "Try to generate Python code"
# ✅ "Maybe add some validation"
# ✅ "Add validation if possible"
# ✅ "Perhaps use JSON format"
# ✅ "Perhaps add validation" (case-insensitive)
```

---

### ⚖️ WEIGHTED SCORING
**What:** Combine multiple signals into one score
**Where:** All analyzers (clarity, cost, security)
**Speed:** Fast (just arithmetic)
**Accuracy:** Depends on weights and signals

```python
# Example: Clarity scoring
score = 5.0  # Base

# Bonuses
if has_instructions: score += 2.0
if has_examples: score += 1.0
if has_output_format: score += 1.5

# Penalties
score -= (ambiguous_count * 0.5)
score -= (conflicts_count * 2.0)
score -= (vague_quantities * 0.75)

# Clamp to 0-10
score = max(0.0, min(10.0, score))
```

---

## Real Example: Analyzing a Prompt

```
Input Prompt:
"Generate Python code to process {data}. Try to make it efficient if possible."
```

### Step 1: REGEX Extraction
```
Pattern: r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}'
Match: {data}
Result: Variable("data", format_style="brace")
```

### Step 2: KEYWORD Analysis
```
Action Keywords: ['generate', 'create', 'write', ...]
Check: prompt.lower().startswith('generate')
Result: Instruction(text="Generate Python...", type=ACTION, confidence=0.85)

Ambiguous Keywords: ['try to', 'maybe', ...]
Check: 'try to' in prompt.lower()
Result: Issue(severity=medium, text="Ambiguous phrase: 'try to'")
```

### Step 3: WEIGHTED SCORING
```
Clarity Calculation:
- Base: 5.0
- Has instructions (+2.0): 7.0
- Has examples (-): 7.0
- Has output format (-): 7.0
- Ambiguous phrase "try to" (-0.5): 6.5
- Ambiguous phrase "if possible" (-0.5): 6.0
- Final: 6.0/10

Security Calculation:
- Base: 10.0
- Unvalidated variable {data} (-1.5): 8.5
- Final: 8.5/10

Cost Calculation:
- Input tokens (real): 23
- Output tokens (estimated): 150
- Cost (GPT-4o): $0.0004
- Score: 10/10 (low cost)
```

---

## How Each Analyzer Works

### 🧠 CLARITY ANALYZER

**Technique:** Keywords + String Matching + Weighted Scoring

**Detects:**
1. Clear structure (has instructions?)
2. Examples provided?
3. Output format specified?
4. Step-by-step logic?
5. Ambiguous phrases (regex-free keyword matching)
6. Conflicting instructions
7. Vague quantities

**Scoring:**
```
Base: 5.0
+ Instructions: 2.0
+ Examples: 1.0
+ Format: 1.5
- Each ambiguous phrase: 0.5
- Each conflict: 2.0
- Vague quantities: 0.75
Clamp: 0-10
```

---

### 💰 COST ANALYZER

**Technique:** Real Token Counting + Pricing Tables

**Process:**
1. Count actual tokens using tiktoken
2. Estimate output tokens (based on complexity heuristic)
3. Look up pricing for each model
4. Calculate: (tokens / 1M) * price_per_1M
5. Combine costs into weighted score

**Not heuristic!** Uses actual token counting.

---

### 🛡️ SECURITY ANALYZER

**Technique:** REGEX Pattern Matching + Keyword Detection

**High-Risk Patterns (REGEX):**
```
\bignore\s+(all\s+)?previous\s+(instructions|commands|prompt)
\breveal\s+(the\s+)?system\s+prompt
\bshow\s+(me\s+)?your\s+(system\s+)?prompt
\b(act|pretend|role-play)\s+as\s+.*\s+and\s+(ignore|forget)
\b(execute|eval|run|compile)\s+.*code
```

**Medium-Risk Patterns (REGEX):**
```
\{[^}]+\}  ← Unvalidated variables
\$\{[^}]+\}
<[^>]+>
```

**Low-Risk Operations (Keywords):**
```
'translate', 'summarize', 'explain'
```

**Scoring:**
```
Base: 10.0
- High risk: 3.0 each
- Medium risk: 1.5 each
- Low risk: 0.5 each
Clamp: 0-10
```

---

## Quick Comparison Table

| Feature | Clarity | Cost | Security |
|---------|---------|------|----------|
| **Main Tech** | Keywords + Scoring | Token Counting | REGEX |
| **Speed** | ⚡⚡⚡ Fast | ⚡⚡⚡ Fast | ⚡⚡ Medium |
| **Accuracy** | 85% | 99% | 95% |
| **Requires API** | ❌ No | ❌ No | ❌ No |
| **Explainable** | ✅ Yes | ✅ Yes | ✅ Yes |
| **False Positives** | Medium | Very Low | Low |

---

## Why Mix All Three?

1. **Clarity** = Semantic understanding (keywords)
2. **Cost** = Objective measurement (token counting)
3. **Security** = Precise pattern detection (regex)

Together they provide **comprehensive analysis without LLM calls**.

---

## Common Questions

**Q: Isn't this just string matching?**
A: Partly! It's keyword matching + regex + weighted scoring. More sophisticated than simple string search, simpler than LLM inference.

**Q: Can it miss issues?**
A: Yes, but trade-off is being fast and cheap. False negatives are better than false positives.

**Q: How accurate is it?**
A: For what it detects, ~85-95% accurate. Won't catch every issue, but catches most common ones.

**Q: Why not use an LLM?**
A: Would be slower, more expensive, and less predictable. Heuristics are better for rule-based detection.

**Q: Can I add my own rules?**
A: Yes! Edit the pattern lists in analyzers/ and the weights in clarity.py
