# PromptLint

> A developer tool for analyzing, scoring, and optimizing LLM prompts with built-in security scanning and cost estimation.

## Overview

PromptLint is a CLI tool that helps developers write better prompts by providing actionable feedback on clarity, cost efficiency, and security. It's designed as Phase 1 of a larger vision (PromptIR) but delivers immediate value as a standalone linting tool.

**Think of it as:** ESLint for prompts, with diff capabilities and security scanning.

---

## Quick Start

### Installation

```bash
# Install from PyPI
pip install promptlint

# Verify installation
promptlint --help
```

### Basic Usage

```bash
# Score a prompt
promptlint score examples/good_prompt.txt

# Compare two prompt versions
promptlint diff examples/basic_prompt.txt examples/good_prompt.txt

# Security analysis
promptlint security examples/injection_prompt.txt

# Cost estimation across models
promptlint estimate examples/good_prompt.txt

# List supported models
promptlint models
```

---

## Features

### 1. Prompt Scoring

Scores prompts on three dimensions:

- **✨ Clarity (0-10)**: How well-structured and unambiguous the prompt is
  - Checks for clear instructions
  - Detects ambiguous phrases ("as needed", "maybe", "try to")
  - Validates output format specification
  - Identifies conflicting instructions

- **💰 Cost Efficiency (0-10)**: Token count and API cost estimates
  - Counts input tokens using tiktoken
  - Estimates output tokens based on complexity
  - Calculates cost for multiple models
  - Identifies expensive patterns

- **🛡️ Security (0-10)**: Detects prompt injection vulnerabilities
  - Finds injection patterns (e.g., "ignore all previous instructions")
  - Detects unvalidated variables
  - Checks for risky operations
  - Rates overall security risk

### 2. Prompt Diffing

Compare two prompt versions and see impact:

```bash
promptlint diff old_prompt.txt new_prompt.txt
```

Shows:
- Line-by-line changes
- Clarity, cost, and security deltas
- Cost impact across models
- Recommendation on whether the change improves the prompt

### 3. Security Analysis

Dedicated security scanning:

```bash
promptlint security prompt.txt
```

Detects:
- Prompt injection attempts
- Unguarded user input
- Risky patterns (code execution, information disclosure)
- Provides severity ratings and remediation suggestions

### 4. Cost Estimation

Estimate costs across models:

```bash
promptlint estimate my_prompt.txt
# Shows costs for GPT-4o, GPT-4o-mini, and Claude 3.5 Sonnet by default

# Or specify models:
promptlint estimate my_prompt.txt --models gpt-4o,gpt-4-turbo,claude-3.5-haiku
```

---

## Architecture

PromptLint uses a modular pipeline architecture:

```
Raw Prompt → Parser → Analyzers → Reporters → Output
                      ├─ Clarity Analyzer
                      ├─ Cost Analyzer  
                      └─ Security Analyzer
```

Learn more in [HOW_IT_WORKS.md](HOW_IT_WORKS.md) and [ANALYSIS_TECHNIQUES.md](ANALYSIS_TECHNIQUES.md).

## CLI Commands

### `promptlint score [PROMPT_FILE]`

Score a single prompt.

**Options:**
- `--model, -m`: Primary model (default: gpt-4o)
- `--format, -f`: Output format (console, json, markdown)
- `--output, -o`: Save to file

**Examples:**

```bash
promptlint score my_prompt.txt
promptlint score my_prompt.txt --model gpt-4o-mini --format json
promptlint score my_prompt.txt --format markdown --output report.md
```

### `promptlint diff [OLD] [NEW]`

Compare two prompts.

**Options:**
- `--format, -f`: Output format (console, json, markdown)
- `--output, -o`: Save to file
- `--models, -m`: Comma-separated models to compare

**Examples:**

```bash
promptlint diff old.txt new.txt
promptlint diff old.txt new.txt --models gpt-4o,claude-3.5-sonnet
promptlint diff old.txt new.txt --format json --output diff.json
```

### `promptlint security [PROMPT_FILE]`

Security analysis only.

**Options:**
- `--format, -f`: Output format (console, json, markdown)
- `--output, -o`: Save to file

**Examples:**

```bash
promptlint security risky_prompt.txt
promptlint security risky_prompt.txt --format markdown --output security_report.md
```

### `promptlint estimate [PROMPT_FILE]`

Cost estimation across models.

**Options:**
- `--models, -m`: Comma-separated models

**Examples:**

```bash
promptlint estimate my_prompt.txt
promptlint estimate my_prompt.txt --models gpt-4o,gpt-4o-mini,claude-3.5-sonnet
```

### `promptlint models`

List supported models and pricing.

---

## Testing

Run the comprehensive test suite:

```bash
# Using pytest
pytest tests/

# Or with poetry
poetry run pytest tests/

# With coverage
poetry run pytest tests/ --cov=promptlint
```

Test categories:

- **Parser tests**: Variable/instruction extraction, example detection
- **Analyzer tests**: Clarity, cost, and security scoring
- **Differ tests**: Prompt comparison and impact analysis
- **Integration tests**: File I/O and end-to-end workflows

---

## Example Usage

### Example 1: Analyze a Prompt

```bash
$ promptlint score examples/good_prompt.txt

📊 Prompt Analysis Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━┓
┃ Metric        ┃ Score       ┃ Details            ┃
┡━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━┩
│ ✨ Clarity     │ 9.2/10 ✓    │ Excellent          │
│ 💰 Cost        │ 8.1/10 ✓    │ Reasonable         │
│ 🛡️ Security    │ 9.5/10 ✓    │ Low risk           │
└───────────────┴─────────────┴────────────────────┘

💡 Suggestions:
  • Adding examples would improve output quality

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Score: 8.9/10
```

### Example 2: Compare Prompts

```bash
$ promptlint diff examples/basic_prompt.txt examples/good_prompt.txt

📊 Prompt Comparison
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Added: +8 | Removed: -1 | Modified: 0

┏━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━┓
┃ Metric   ┃ Delta    ┃ Change %  ┃
┡━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━┩
│ Clarity  │ ↑ +2.5   │ +25%      │
│ Security │ → +0.0   │ 0%        │
│ Cost     │ ↑ +0.02  │ +8%       │
└──────────┴──────────┴───────────┘

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ 📋 Recommendation                                                              ┃
┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
┃ ✅ Clarity improved significantly                                             ┃
┃ ✅ This change improves the prompt overall                                    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Example 3: Security Analysis

```bash
$ promptlint security examples/injection_prompt.txt

🛡️ Security Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ High Severity Issues:
  • HIGH RISK: Prompt override attempt (line 2)
    → Remove or rephrase this instruction to prevent prompt injection

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall Security Score: 3/10
```

---

## Configuration

Future support for `.promptlint.yaml`:

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

## Technical Stack

- **Python 3.11+**
- **Typer**: CLI framework
- **Rich**: Terminal output formatting
- **Pydantic**: Data validation and models
- **tiktoken**: Token counting (OpenAI tokenizer)
- **PyYAML**: Configuration (optional, future)

### Dev Dependencies

- **pytest**: Testing
- **black**: Code formatting
- **ruff**: Linting
- **mypy**: Type checking

---

## Roadmap

### Phase 1 (Current): MVP ✅
- ✅ Prompt scoring (clarity, cost, security)
- ✅ Diff functionality
- ✅ CLI interface
- ✅ Multiple output formats
- ✅ Comprehensive tests
- ✅ Example prompts

### Phase 2 (Next): Enhancement
- LLM-based consistency testing
- Regression testing with snapshots
- VS Code extension
- Web UI for analysis

### Phase 3: PromptIR Evolution
- Graph visualization of prompt logic
- Optimization layer
- Execution simulation
- Multi-model comparison

### Phase 4: SaaS
- Team collaboration
- API access
- Enterprise features
- Prompt versioning

---

## Contributing

We welcome contributions! Whether you're fixing bugs, adding features, or improving documentation:

- **Fork the repository**: [github.com/fyunusa/promptlint](https://github.com/fyunusa/promptlint)
- **Create a feature branch**: `git checkout -b feature/your-feature`
- **Submit a Pull Request**

Areas for contribution:
- Enhanced heuristics for clarity scoring
- Support for more models and pricing data
- Plugin system for custom rules
- Performance optimizations
- Additional output formats
- Documentation and examples

Check out the [CONTRIBUTING.md](CONTRIBUTING.md) guide for detailed instructions.

---

## License

MIT

---

## Links

- **PyPI Package**: [pypi.org/project/promptlint](https://pypi.org/project/promptlint/)
- **GitHub Repository**: [github.com/fyunusa/promptlint](https://github.com/fyunusa/promptlint)
- **Author**: [Faisal Yunusa](https://github.com/fyunusa)

---

## Notes

- **Model pricing** is current as of November 2025. Check `utils/pricing.py` for updates.
- **Token counting** uses tiktoken when available for accuracy. Falls back to word-based estimation.
- **Security patterns** are based on common OWASP prompt injection techniques.
- **Clarity heuristics** combine structural analysis with common best practices.

---

## Troubleshooting

### "tiktoken not found" warning

Token counting will use word-based fallback. Install tiktoken for accuracy:

```bash
poetry add tiktoken
```

### No cost estimates shown

Check that models are supported:

```bash
promptlint models
```

Add unsupported models to `utils/pricing.py`.

### Parser not finding expected instructions

The parser uses heuristics. Help by:
- Using imperative verbs (generate, create, analyze, etc.)
- Starting instructions on new lines
- Being explicit about the task

---

**Made with ❤️ for prompt engineers everywhere.**
