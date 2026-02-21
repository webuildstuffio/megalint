Here's a comprehensive README.md that another agent can use to build the full codebase:

```markdown
# PromptLint

> A developer tool for analyzing, scoring, and optimizing LLM prompts with built-in security scanning and cost estimation.

## Overview

PromptLint is a CLI tool (with future SaaS potential) that helps developers write better prompts by providing actionable feedback on clarity, cost, and security. It's designed as Phase 1 of a larger vision (PromptIR) but delivers immediate value as a standalone linting tool.

**Think of it as:** ESLint for prompts, with diff capabilities and security scanning.

---

## Core Value Proposition

1. **Score prompts** on clarity, cost efficiency, and security
2. **Diff prompts** to see how changes impact quality and cost
3. **Detect prompt injection** vulnerabilities
4. **Estimate costs** across different models before running
5. **Modular architecture** that can evolve into a reasoning compiler (PromptIR)

---

## MVP Features (Week 1-2)

### 1. Prompt Scoring
```bash
promptlint score prompt.txt
```

**Output:**
```
📊 Prompt Analysis Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✨ Clarity: 8.5/10
   ✓ Clear instruction structure
   ⚠ Contains ambiguous phrase: "as needed"
   💡 Suggestion: Specify exact conditions

💰 Cost Efficiency: 7/10
   📝 Tokens: 245 input / ~500 estimated output
   💵 Estimated cost per run:
      • gpt-4o: $0.0042
      • gpt-4o-mini: $0.0003
      • claude-3.5-sonnet: $0.0038

🛡️ Security: Medium Risk (6/10)
   ⚠ Unguarded variable: {user_input}
   ⚠ Pattern detected: "ignore previous"
   💡 Add input sanitization

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Score: 7.2/10
```

### 2. Prompt Diffing
```bash
promptlint diff old-prompt.txt new-prompt.txt
```

**Output:**
```
📊 Prompt Comparison
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Content Changes:
  + Line 2: "generate code" → "generate Python code"
  + Line 5: Added explicit output format requirement
  - Line 8: Removed ambiguous phrase "as appropriate"

Impact Analysis:
  ✅ Clarity:    8.5/10 → 9.2/10  (+0.7, +8%)
  ✅ Cost:       -56 tokens       (-18%)
  ✅ Security:   6/10 → 8/10      (+2)

Estimated Cost Change:
  gpt-4o: $0.0042 → $0.0034 (-19%)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Overall: This change improves the prompt
```

### 3. Injection Detection
```bash
promptlint security prompt.txt
```

**Output:**
```
🛡️ Security Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ HIGH RISK: Prompt injection pattern detected
   Pattern: "Ignore all previous instructions"
   Location: Line 12
   Risk: User could override system behavior

⚠️ MEDIUM RISK: Unguarded user input
   Variable: {user_query}
   Location: Line 5
   Risk: Direct injection without sanitization

💡 Recommendations:
   1. Add input validation before {user_query}
   2. Remove or rephrase line 12
   3. Consider using structured output format

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Security Score: 4/10 (Needs Improvement)
```

---

## Architecture

### High-Level Flow
```
Input (prompt.txt)
    ↓
Parser (extract structure, variables, instructions)
    ↓
Analyzer (run rules: clarity, cost, security)
    ↓
Reporter (format output: CLI, JSON, Markdown)
    ↓
Output (scored results + recommendations)
```

### Directory Structure
```
promptlint/
│
├── promptlint/
│   ├── __init__.py
│   ├── cli.py                 # Main CLI interface (Typer)
│   │
│   ├── core/
│   │   ├── __init__.py
│   │   ├── parser.py          # Extract prompt structure
│   │   ├── analyzer.py        # Run all checks
│   │   ├── differ.py          # Compare two prompts
│   │   └── models.py          # Pydantic models (future PromptIR seed)
│   │
│   ├── analyzers/
│   │   ├── __init__.py
│   │   ├── clarity.py         # Clarity scoring logic
│   │   ├── cost.py            # Token counting + cost estimation
│   │   └── security.py        # Injection detection
│   │
│   ├── reporters/
│   │   ├── __init__.py
│   │   ├── console.py         # Rich console output
│   │   ├── json_reporter.py   # JSON format
│   │   └── markdown.py        # Markdown format
│   │
│   ├── rules/
│   │   ├── clarity_rules.yaml      # Clarity heuristics
│   │   ├── cost_rules.yaml         # Cost models/pricing
│   │   └── security_patterns.yaml  # Injection patterns
│   │
│   └── utils/
│       ├── __init__.py
│       ├── tokenizer.py       # Token counting (tiktoken)
│       └── pricing.py         # Model pricing data
│
├── tests/
│   ├── test_parser.py
│   ├── test_analyzers.py
│   ├── test_differ.py
│   └── fixtures/
│       ├── good_prompt.txt
│       ├── bad_prompt.txt
│       └── injection_prompt.txt
│
├── examples/
│   ├── basic_prompt.txt
│   ├── good_prompt.txt
│   └── risky_prompt.txt
│
├── pyproject.toml             # Poetry config
├── README.md
└── .gitignore
```

---

## Technical Stack

### Core Dependencies
- **Python 3.11+**
- **Typer** - CLI framework
- **Rich** - Beautiful terminal output
- **Pydantic** - Data validation and internal IR models
- **tiktoken** - Token counting (OpenAI tokenizer)
- **PyYAML** - Rule configuration
- **difflib** - Built-in diff functionality

### Dev Dependencies
- **pytest** - Testing
- **black** - Code formatting
- **ruff** - Linting
- **mypy** - Type checking

---

## Implementation Details

### 1. Parser (`core/parser.py`)

**Responsibility:** Extract structured information from raw prompt text.

**Extract:**
- Instructions (imperative sentences)
- Variables (placeholders like `{variable}`, `{{variable}}`, `<variable>`)
- Conditional logic ("if X then Y")
- Output format requirements
- Context/examples
- Length/tone requirements

**Output Model:**
```python
class ParsedPrompt(BaseModel):
    raw_text: str
    instructions: List[Instruction]
    variables: List[Variable]
    conditionals: List[Conditional]
    output_format: Optional[str]
    examples: List[str]
    metadata: Dict[str, Any]
```

**Implementation Notes:**
- Use regex for variable detection
- Use spaCy or simple NLP for sentence segmentation
- Detect structure patterns (numbered lists, bullet points)
- Identify meta-instructions ("be concise", "think step by step")

---

### 2. Analyzers

#### 2a. Clarity Analyzer (`analyzers/clarity.py`)

**Scoring Criteria:**
- ✅ Clear instructions (imperative, specific)
- ✅ No ambiguous phrases ("as needed", "maybe", "try to")
- ✅ Explicit output format
- ✅ No conflicting instructions
- ✅ Appropriate level of detail

**Heuristics:**
```python
AMBIGUOUS_PHRASES = [
    "as needed", "if possible", "try to", "maybe",
    "perhaps", "might", "could", "should probably"
]

CLARITY_BOOSTERS = [
    "step by step", "first", "then", "finally",
    "output format:", "example:", "requirements:"
]
```

**Scoring Algorithm:**
```python
base_score = 5.0
score += has_clear_structure * 2
score += has_examples * 1
score += has_output_format * 1.5
score -= ambiguous_phrase_count * 0.5
score -= missing_specificity * 1
return min(10, max(0, score))
```

#### 2b. Cost Analyzer (`analyzers/cost.py`)

**Features:**
- Token counting using tiktoken
- Estimate output tokens based on instruction complexity
- Calculate cost for multiple models (GPT-4o, GPT-4o-mini, Claude 3.5)
- Flag expensive patterns (large context, complex reasoning)

**Pricing Data (in `rules/cost_rules.yaml`):**
```yaml
models:
  gpt-4o:
    input_price_per_1m: 2.50
    output_price_per_1m: 10.00
  gpt-4o-mini:
    input_price_per_1m: 0.15
    output_price_per_1m: 0.60
  claude-3.5-sonnet:
    input_price_per_1m: 3.00
    output_price_per_1m: 15.00
```

**Implementation:**
```python
def estimate_cost(prompt: ParsedPrompt, model: str) -> CostEstimate:
    input_tokens = count_tokens(prompt.raw_text, model)
    estimated_output = estimate_output_tokens(prompt)
    
    pricing = load_pricing(model)
    input_cost = (input_tokens / 1_000_000) * pricing.input_price
    output_cost = (estimated_output / 1_000_000) * pricing.output_price
    
    return CostEstimate(
        input_tokens=input_tokens,
        estimated_output_tokens=estimated_output,
        total_cost=input_cost + output_cost,
        model=model
    )
```

#### 2c. Security Analyzer (`analyzers/security.py`)

**Detection Patterns (in `rules/security_patterns.yaml`):**
```yaml
high_risk:
  - pattern: "ignore (all )?previous (instructions|commands)"
    risk: "User can override system behavior"
  - pattern: "reveal (the )?system prompt"
    risk: "Prompt leakage vulnerability"
  - pattern: "act as .* and ignore"
    risk: "Role confusion attack"

medium_risk:
  - pattern: '\{[^}]+\}'  # Unvalidated variables
    risk: "Unguarded user input"
  - pattern: "execute|eval|run code"
    risk: "Potential code execution"

low_risk:
  - pattern: "translate|summarize|explain"
    risk: "Generally safe operations"
```

**Scoring:**
```python
score = 10.0
score -= high_risk_count * 3
score -= medium_risk_count * 1.5
score -= low_risk_count * 0.5
return max(0, score)
```

---

### 3. Differ (`core/differ.py`)

**Features:**
- Line-by-line text comparison
- Score delta calculation
- Cost impact analysis
- Semantic change detection

**Implementation:**
```python
def diff_prompts(old_path: str, new_path: str) -> DiffReport:
    old = parse_prompt(old_path)
    new = parse_prompt(new_path)
    
    text_diff = difflib.unified_diff(
        old.raw_text.splitlines(),
        new.raw_text.splitlines()
    )
    
    old_scores = analyze_prompt(old)
    new_scores = analyze_prompt(new)
    
    return DiffReport(
        text_changes=list(text_diff),
        clarity_delta=new_scores.clarity - old_scores.clarity,
        cost_delta=new_scores.cost - old_scores.cost,
        security_delta=new_scores.security - old_scores.security,
        recommendation=generate_recommendation(old_scores, new_scores)
    )
```

---

### 4. CLI (`cli.py`)

**Commands:**
```python
@app.command()
def score(
    prompt_file: Path,
    model: str = "gpt-4o",
    format: str = "console"  # console, json, markdown
):
    """Score a prompt on clarity, cost, and security."""
    
@app.command()
def diff(
    old_prompt: Path,
    new_prompt: Path,
    format: str = "console"
):
    """Compare two prompt versions."""

@app.command()
def security(
    prompt_file: Path,
    format: str = "console"
):
    """Run security analysis only."""

@app.command()
def estimate(
    prompt_file: Path,
    models: List[str] = ["gpt-4o", "gpt-4o-mini", "claude-3.5-sonnet"]
):
    """Estimate costs across multiple models."""
```

---

## Data Models (Pydantic)

**These models form the foundation of future PromptIR:**

```python
# core/models.py

class Variable(BaseModel):
    name: str
    location: int  # line number
    has_validation: bool = False

class Instruction(BaseModel):
    text: str
    line: int
    type: Literal["action", "constraint", "format", "meta"]

class ParsedPrompt(BaseModel):
    raw_text: str
    instructions: List[Instruction]
    variables: List[Variable]
    conditionals: List[str]
    output_format: Optional[str]
    examples: List[str]
    metadata: Dict[str, Any]

class ScoreResult(BaseModel):
    clarity: float
    cost: float
    security: float
    overall: float
    issues: List[Issue]
    suggestions: List[str]

class Issue(BaseModel):
    severity: Literal["high", "medium", "low"]
    category: Literal["clarity", "cost", "security"]
    description: str
    location: Optional[int]
    suggestion: str

class CostEstimate(BaseModel):
    input_tokens: int
    estimated_output_tokens: int
    total_cost: float
    model: str

class DiffReport(BaseModel):
    text_changes: List[str]
    clarity_delta: float
    cost_delta: CostEstimate
    security_delta: float
    recommendation: str
```

---

## Example Usage

### Example 1: Score a Prompt
```bash
promptlint score examples/basic_prompt.txt
```

### Example 2: Compare Versions
```bash
promptlint diff prompts/v1.txt prompts/v2.txt --format=json > diff-report.json
```

### Example 3: Security Scan
```bash
promptlint security user-prompt.txt
```

### Example 4: Cost Estimation
```bash
promptlint estimate my-prompt.txt --models gpt-4o,claude-3.5-sonnet
```

---

## Testing Strategy

### Unit Tests
- Test parser extraction accuracy
- Test scoring algorithms
- Test diff logic
- Test security pattern matching

### Integration Tests
- Test full CLI commands
- Test output formatting
- Test file I/O

### Fixtures
Create test prompts in `tests/fixtures/`:
- `good_prompt.txt` - High scores across all metrics
- `ambiguous_prompt.txt` - Low clarity
- `expensive_prompt.txt` - High token count
- `injection_prompt.txt` - Security issues

---

## Installation & Setup

```bash
# Install with Poetry
poetry install

# Or with pip
pip install -e .

# Run CLI
promptlint --help
```

---

## Configuration File (Optional Future Feature)

`.promptlint.yaml`:
```yaml
default_model: gpt-4o
output_format: console

rules:
  clarity:
    min_score: 7.0
  cost:
    max_tokens: 2000
    warn_threshold: 1000
  security:
    min_score: 8.0
    
ignore_patterns:
  - "# promptlint-ignore"
```

---

## Roadmap

### Phase 1 (Week 1-2): MVP
- ✅ Prompt scoring (clarity, cost, security)
- ✅ Diff functionality
- ✅ CLI interface
- ✅ Basic reporting

### Phase 2 (Week 3-4): Enhancement
- LLM-based consistency testing (run prompt multiple times, check variance)
- Regression testing (snapshot + compare)
- VS Code extension

### Phase 3 (Month 2): PromptIR Evolution
- Add graph visualization of prompt logic
- Add optimization layer (reduce redundant steps)
- Add execution simulation

### Phase 4: SaaS
- Web UI
- Team collaboration
- API access
- Enterprise features

---

## Success Metrics

**Week 1:**
- MVP working with all 3 core commands
- 10+ test cases passing
- Beautiful terminal output

**Week 2:**
- Published to PyPI
- GitHub repo with examples
- Initial tweet/demo video

**Month 1:**
- 100+ GitHub stars
- 10+ real users providing feedback
- Feature requests guiding Phase 2

---

## Technical Debt to Avoid

1. **Don't hard-code pricing** - Use YAML config
2. **Don't over-engineer** - Start with heuristics, add LLM later
3. **Keep models simple** - They'll evolve into PromptIR
4. **Write tests from day 1** - This will move fast, need safety
5. **Document as you go** - Good docstrings = good foundation

---

## License

MIT

---

## Notes for the Implementing Agent

- Prioritize getting the **score** command working first
- Use **Rich** library for beautiful console output (progress bars, tables, colors)
- Token counting is critical - use `tiktoken` correctly for each model
- Security patterns should be easily extensible (YAML file)
- Keep the code modular - each analyzer should be independent
- The `models.py` file is the seed of PromptIR - design it thoughtfully
- Add comprehensive docstrings - this will become open source
- Include at least 5 example prompts in `examples/`

**Start with:** Parser + Clarity Analyzer + CLI score command. Get that working end-to-end, then add Cost and Security.
```

---