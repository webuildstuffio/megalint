"""
CLI Interface - main command-line interface for PromptLint.
"""

from pathlib import Path
from typing import Optional, List
import typer

from promptlint.core.parser import PromptParser
from promptlint.core.analyzer import Analyzer
from promptlint.core.differ import Differ
from promptlint.reporters.console import ConsoleReporter
from promptlint.reporters.json_reporter import JSONReporter
from promptlint.reporters.markdown import MarkdownReporter
from promptlint.utils.pricing import PricingData

app = typer.Typer(help="PromptLint - Analyze, score, and optimize LLM prompts.")


@app.command()
def score(
    prompt_file: Path = typer.Argument(..., help="Path to prompt file"),
    model: str = typer.Option("gpt-4o", "--model", "-m", help="Primary model to estimate costs for"),
    format: str = typer.Option("console", "--format", "-f", help="Output format (console, json, markdown)"),
    output: Optional[Path] = typer.Option(None, "--output", "-o", help="Output file (optional)"),
):
    """
    Score a prompt on clarity, cost efficiency, and security.
    
    Example:
        promptlint score my_prompt.txt
        promptlint score my_prompt.txt --model gpt-4o-mini --format json
    """
    try:
        # Parse prompt
        parsed = PromptParser.parse_file(str(prompt_file))
        
        # Get models for cost analysis
        models = [model] if model else PricingData.get_default_models()
        
        # Analyze
        result = Analyzer.analyze(parsed, models=models)
        
        # Format output
        if format == "json":
            output_text = JSONReporter.print_score_report(result)
        elif format == "markdown":
            output_text = MarkdownReporter.score_to_markdown(result)
        else:  # console
            reporter = ConsoleReporter()
            reporter.print_score_report(result)
            reporter.print_cost_estimate(result)
            return
        
        # Print or save
        if output:
            with open(output, 'w') as f:
                f.write(output_text)
            typer.echo(f"✅ Report saved to {output}")
        else:
            typer.echo(output_text)
    
    except FileNotFoundError:
        typer.echo(f"❌ Error: Prompt file not found: {prompt_file}", err=True)
        raise typer.Exit(1)
    except Exception as e:
        typer.echo(f"❌ Error: {str(e)}", err=True)
        raise typer.Exit(1)


@app.command()
def diff(
    old_prompt: Path = typer.Argument(..., help="Path to original prompt file"),
    new_prompt: Path = typer.Argument(..., help="Path to new prompt file"),
    format: str = typer.Option("console", "--format", "-f", help="Output format (console, json, markdown)"),
    output: Optional[Path] = typer.Option(None, "--output", "-o", help="Output file (optional)"),
    models: Optional[str] = typer.Option(None, "--models", "-m", help="Comma-separated models to compare"),
):
    """
    Compare two prompt versions and show impact analysis.
    
    Example:
        promptlint diff old_prompt.txt new_prompt.txt
        promptlint diff old_prompt.txt new_prompt.txt --format json
    """
    try:
        # Parse models
        model_list = None
        if models:
            model_list = [m.strip() for m in models.split(',')]
        else:
            model_list = PricingData.get_default_models()
        
        # Diff
        report = Differ.diff_prompts(str(old_prompt), str(new_prompt), models=model_list)
        
        # Format output
        if format == "json":
            output_text = JSONReporter.print_diff_report(report)
        elif format == "markdown":
            output_text = MarkdownReporter.diff_to_markdown(report)
        else:  # console
            reporter = ConsoleReporter()
            reporter.print_diff_report(report)
            return
        
        # Print or save
        if output:
            with open(output, 'w') as f:
                f.write(output_text)
            typer.echo(f"✅ Diff report saved to {output}")
        else:
            typer.echo(output_text)
    
    except FileNotFoundError as e:
        typer.echo(f"❌ Error: Prompt file not found: {str(e)}", err=True)
        raise typer.Exit(1)
    except Exception as e:
        typer.echo(f"❌ Error: {str(e)}", err=True)
        raise typer.Exit(1)


@app.command()
def security(
    prompt_file: Path = typer.Argument(..., help="Path to prompt file"),
    format: str = typer.Option("console", "--format", "-f", help="Output format (console, json, markdown)"),
    output: Optional[Path] = typer.Option(None, "--output", "-o", help="Output file (optional)"),
):
    """
    Run security analysis on a prompt.
    
    Detects prompt injection patterns and unguarded variables.
    
    Example:
        promptlint security my_prompt.txt
    """
    try:
        # Parse prompt
        parsed = PromptParser.parse_file(str(prompt_file))
        
        # Analyze
        result = Analyzer.analyze(parsed)
        
        # Format output
        if format == "json":
            output_text = JSONReporter.print_score_report(result)
        elif format == "markdown":
            output_text = MarkdownReporter.score_to_markdown(result)
        else:  # console
            reporter = ConsoleReporter()
            reporter.print_security_report(result)
            return
        
        # Print or save
        if output:
            with open(output, 'w') as f:
                f.write(output_text)
            typer.echo(f"✅ Report saved to {output}")
        else:
            typer.echo(output_text)
    
    except FileNotFoundError:
        typer.echo(f"❌ Error: Prompt file not found: {prompt_file}", err=True)
        raise typer.Exit(1)
    except Exception as e:
        typer.echo(f"❌ Error: {str(e)}", err=True)
        raise typer.Exit(1)


@app.command()
def estimate(
    prompt_file: Path = typer.Argument(..., help="Path to prompt file"),
    models: Optional[str] = typer.Option(None, "--models", "-m", help="Comma-separated models"),
):
    """
    Estimate costs across multiple models.
    
    Example:
        promptlint estimate my_prompt.txt
        promptlint estimate my_prompt.txt --models gpt-4o,claude-3.5-sonnet
    """
    try:
        # Parse models
        if models:
            model_list = [m.strip() for m in models.split(',')]
        else:
            model_list = PricingData.get_default_models()
        
        # Parse prompt
        parsed = PromptParser.parse_file(str(prompt_file))
        
        # Analyze
        result = Analyzer.analyze(parsed, models=model_list)
        
        # Print estimates
        reporter = ConsoleReporter()
        reporter.print_cost_estimate(result)
    
    except FileNotFoundError:
        typer.echo(f"❌ Error: Prompt file not found: {prompt_file}", err=True)
        raise typer.Exit(1)
    except Exception as e:
        typer.echo(f"❌ Error: {str(e)}", err=True)
        raise typer.Exit(1)


@app.command()
def models():
    """
    List supported models and their pricing.
    
    Example:
        promptlint models
    """
    supported = PricingData.get_supported_models()
    typer.echo("📋 Supported Models:\n")
    
    for model in supported:
        pricing = PricingData.get_pricing(model)
        typer.echo(
            f"  • {model}: "
            f"${pricing.input_price_per_1m}/1M input tokens, "
            f"${pricing.output_price_per_1m}/1M output tokens"
        )
    
    typer.echo()


if __name__ == "__main__":
    app()
