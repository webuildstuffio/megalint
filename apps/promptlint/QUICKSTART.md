# PromptLint Quick Start Guide

## Installation

### Prerequisites

- Python 3.11 or higher
- Poetry (install from https://python-poetry.org)

### Setup

```bash
cd /Users/fyunusa/Documents/promptlint

# Install dependencies
poetry install

# Verify installation
poetry run promptlint --help
```

## First Steps

### 1. Run Your First Score

```bash
poetry run promptlint score examples/good_prompt.txt
```

This will display a beautiful report with:
- Clarity score (how well-structured the prompt is)
- Cost estimate (tokens and API costs)
- Security assessment (injection vulnerability checks)

### 2. Compare Two Prompts

```bash
poetry run promptlint diff examples/basic_prompt.txt examples/good_prompt.txt
```

Shows what changed and the impact on quality and cost.

### 3. Security Check

```bash
poetry run promptlint security examples/injection_prompt.txt
```

Scans for prompt injection vulnerabilities and risky patterns.

### 4. Cost Comparison

```bash
poetry run promptlint estimate examples/good_prompt.txt
```

See how much the prompt would cost across different models.

## Project Files Overview

### Main Code (in `promptlint/`)

- **cli.py** - The CLI commands and main entry point
- **core/models.py** - Pydantic data models (ParsedPrompt, ScoreResult, etc.)
- **core/parser.py** - Extracts structure from prompts
- **core/analyzer.py** - Orchestrates all analysis
- **core/differ.py** - Compares two prompts
- **analyzers/** - Individual scorers (clarity, cost, security)
- **reporters/** - Output formatters (console, JSON, markdown)
- **utils/** - Helper utilities (tokenization, pricing)

### Tests (in `tests/`)

```bash
poetry run pytest tests/ -v
```

### Examples (in `examples/`)

- **basic_prompt.txt** - Minimal, vague prompt
- **good_prompt.txt** - Well-structured, clear prompt
- **ambiguous_prompt.txt** - Contains vague language
- **injection_prompt.txt** - Contains security issues

## Common Commands

```bash
# Score with specific model
poetry run promptlint score prompt.txt --model gpt-4o-mini

# Output as JSON
poetry run promptlint score prompt.txt --format json

# Save report to file
poetry run promptlint score prompt.txt --format markdown --output report.md

# Compare multiple models
poetry run promptlint estimate prompt.txt --models gpt-4o,gpt-4o-mini,claude-3.5-sonnet

# Run all tests
poetry run pytest tests/

# Check code quality
poetry run black promptlint/ tests/
poetry run ruff check promptlint/ tests/
```

## How It Works

1. **Parser** reads the prompt and extracts:
   - Instructions (what to do)
   - Variables (placeholders like {name})
   - Examples (input/output samples)
   - Output format hints

2. **Analyzers** score on three dimensions:
   - **Clarity**: How explicit and well-structured
   - **Cost**: Token count and API cost
   - **Security**: Injection vulnerabilities

3. **Reporters** format output:
   - Terminal (Rich formatting)
   - JSON (machine-readable)
   - Markdown (documentation)

## Example Workflow

```bash
# 1. Write a prompt
echo "Generate Python code" > my_prompt.txt

# 2. Score it
poetry run promptlint score my_prompt.txt

# 3. Improve it
echo "Generate clean, efficient Python code for a binary search algorithm with proper error handling and documentation." > my_prompt_v2.txt

# 4. Compare versions
poetry run promptlint diff my_prompt.txt my_prompt_v2.txt

# 5. Check security
poetry run promptlint security my_prompt_v2.txt

# 6. Export as JSON for automation
poetry run promptlint score my_prompt_v2.txt --format json > analysis.json
```

## Understanding Scores

Each dimension is scored 0-10:

- **8-10**: Excellent
- **6-8**: Good
- **5-6**: Fair
- **0-5**: Needs improvement

### Clarity Score Factors

✅ Increases:
- Clear, imperative instructions
- Output format specified
- Examples provided
- Step-by-step structure

❌ Decreases:
- Ambiguous phrases ("maybe", "try to", "as needed")
- No output format
- Conflicting instructions
- Vague quantities

### Cost Score Factors

✅ Increases:
- Few tokens (< 500)
- Simple tasks

❌ Decreases:
- Many tokens (> 2000)
- Complex reasoning required
- Long context

### Security Score Factors

✅ Increases:
- No risky patterns detected
- Validated variables
- Safe operations

❌ Decreases:
- Injection attempts ("ignore instructions")
- Unguarded variables
- Code execution risks
- Disclosure attempts

## Adding Custom Prompts

Create a text file and analyze:

```bash
cat > my_analysis_prompt.txt << 'EOF'
You are a code reviewer. Your task is to analyze Python code for quality issues.

Instructions:
1. Check for PEP 8 compliance
2. Identify performance issues  
3. Suggest improvements

Output format: JSON with arrays for each category

Example:
Input: def add(a,b): return a+b
Output: {"compliance": [], "performance": [], "suggestions": ["Add docstring"]}
EOF

poetry run promptlint score my_analysis_prompt.txt
```

## Troubleshooting

### Command not found: `promptlint`

Make sure you're running with poetry:

```bash
poetry run promptlint --help
```

Or install as a package:

```bash
poetry install
poetry shell  # activates virtual env
promptlint --help
```

### Import errors

Reinstall dependencies:

```bash
poetry install
poetry lock --no-update
poetry install
```

### Tests failing

Check Python version:

```bash
python --version  # Should be 3.11+
```

Run tests with verbose output:

```bash
poetry run pytest tests/ -vv
```

## Next Steps

1. **Explore the codebase**: Start with `promptlint/cli.py`
2. **Read the models**: Check `promptlint/core/models.py` for data structures
3. **Understand analyzers**: Each in `promptlint/analyzers/`
4. **Add features**: Consider custom rules or new analyzers
5. **Extend**: Build plugins or integrations

## Getting Help

- Check `README.md` for detailed documentation
- Review examples in `examples/` directory
- Read docstrings in source files
- Run tests to see expected behavior

---

**Ready to lint prompts? Run:** `poetry run promptlint score examples/good_prompt.txt`
