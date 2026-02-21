"""
Console Reporter - formats output for terminal display using Rich.
"""

from typing import List, Optional
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.text import Text
from ..core.models import ScoreResult, DiffReport, Issue, CostEstimate


class ConsoleReporter:
    """Formats prompt analysis for beautiful terminal output."""
    
    def __init__(self):
        """Initialize console reporter."""
        self.console = Console()
    
    def print_score_report(self, result: ScoreResult, title: str = "📊 Prompt Analysis Report"):
        """Print a formatted score report."""
        # Header
        self.console.print(f"\n{title}")
        self.console.print("━" * 80)
        
        # Scores panel
        scores_table = Table(show_header=False, pad_edge=True)
        scores_table.add_column("Metric", style="cyan")
        scores_table.add_column("Score", justify="right")
        scores_table.add_column("Details", style="dim")
        
        scores_table.add_row(
            "✨ Clarity",
            self._score_to_str(result.clarity_score),
            self._get_score_details(result.clarity_score),
        )
        scores_table.add_row(
            "💰 Cost Efficiency",
            self._score_to_str(result.cost_score),
            self._get_cost_details(result.cost_estimates),
        )
        scores_table.add_row(
            "🛡️ Security",
            self._score_to_str(result.security_score),
            self._get_security_details(result.security_score),
        )
        
        self.console.print(scores_table)
        self.console.print()
        
        # Issues
        if result.issues:
            self._print_issues(result.issues)
        
        # Suggestions
        if result.suggestions:
            self._print_suggestions(result.suggestions)
        
        # Overall score
        self.console.print("━" * 80)
        overall_text = Text(f"Overall Score: {result.overall_score:.1f}/10", style="bold yellow")
        self.console.print(overall_text)
        self.console.print()
    
    def print_diff_report(self, report: DiffReport):
        """Print a formatted diff report."""
        self.console.print("\n📊 Prompt Comparison")
        self.console.print("━" * 80)
        
        # Summary of changes
        summary = f"Added: +{report.added_lines} | Removed: -{report.removed_lines} | Modified: {report.modified_lines}"
        self.console.print(f"[dim]{summary}[/dim]")
        self.console.print()
        
        # Delta analysis
        delta_table = Table(show_header=True, pad_edge=True)
        delta_table.add_column("Metric", style="cyan")
        delta_table.add_column("Delta", justify="right")
        delta_table.add_column("Change %", justify="right")
        
        # Clarity
        clarity_arrow = "↑" if report.clarity_delta > 0 else "↓" if report.clarity_delta < 0 else "→"
        clarity_style = "green" if report.clarity_delta > 0.2 else "red" if report.clarity_delta < -0.2 else "dim"
        delta_table.add_row(
            "Clarity",
            Text(f"{clarity_arrow} {report.clarity_delta:+.1f}", style=clarity_style),
            Text(f"{(report.clarity_delta / 10) * 100:+.0f}%", style=clarity_style),
        )
        
        # Security
        security_arrow = "↑" if report.security_delta > 0 else "↓" if report.security_delta < 0 else "→"
        security_style = "green" if report.security_delta > 0.2 else "red" if report.security_delta < -0.2 else "dim"
        delta_table.add_row(
            "Security",
            Text(f"{security_arrow} {report.security_delta:+.1f}", style=security_style),
            Text(f"{(report.security_delta / 10) * 100:+.0f}%", style=security_style),
        )
        
        # Cost deltas
        for model, cost_delta in report.cost_delta.items():
            cost_arrow = "↓" if cost_delta < 0 else "↑" if cost_delta > 0 else "→"
            cost_style = "green" if cost_delta < 0 else "red" if cost_delta > 0 else "dim"
            delta_table.add_row(
                f"Cost ({model})",
                Text(f"{cost_arrow} ${cost_delta:+.4f}", style=cost_style),
                Text(f"{(cost_delta / (abs(cost_delta) + 0.00001)) * 100:+.0f}%", style=cost_style),
            )
        
        self.console.print(delta_table)
        self.console.print()
        
        # Recommendation
        panel = Panel(report.recommendation, title="📋 Recommendation", expand=False)
        self.console.print(panel)
        self.console.print()
    
    def print_security_report(self, result: ScoreResult):
        """Print security analysis focused report."""
        self.console.print("\n🛡️ Security Analysis")
        self.console.print("━" * 80)
        
        # Filter for security issues only
        security_issues = [i for i in result.issues if i.category == 'security']
        
        if security_issues:
            self._print_issues(security_issues)
        else:
            self.console.print("[green]✅ No security issues detected[/green]")
        
        self.console.print()
        self.console.print("━" * 80)
        score_style = "green" if result.security_score >= 8 else "yellow" if result.security_score >= 6 else "red"
        self.console.print(f"Overall Security Score: [{score_style}]{result.security_score:.1f}/10[/{score_style}]")
        self.console.print()
    
    def print_cost_estimate(self, result: ScoreResult):
        """Print cost estimation report."""
        self.console.print("\n💵 Cost Estimation")
        self.console.print("━" * 80)
        
        if not result.cost_estimates:
            self.console.print("[dim]No cost estimates available[/dim]")
            return
        
        table = Table(show_header=True, pad_edge=True)
        table.add_column("Model", style="cyan")
        table.add_column("Input Tokens", justify="right")
        table.add_column("Output Tokens (est.)", justify="right")
        table.add_column("Total Tokens", justify="right")
        table.add_column("Cost/Run", justify="right", style="yellow")
        
        for model, estimate in result.cost_estimates.items():
            table.add_row(
                model,
                str(estimate.input_tokens),
                str(estimate.estimated_output_tokens),
                str(estimate.total_tokens),
                f"${estimate.total_cost:.4f}",
            )
        
        self.console.print(table)
        self.console.print()
    
    def _print_issues(self, issues: List[Issue]):
        """Print issues in a formatted way."""
        # Group by severity
        high = [i for i in issues if i.severity == 'high']
        medium = [i for i in issues if i.severity == 'medium']
        low = [i for i in issues if i.severity == 'low']
        
        if high:
            self.console.print("[red bold]❌ High Severity Issues:[/red bold]")
            for issue in high:
                self._print_single_issue(issue, "red")
            self.console.print()
        
        if medium:
            self.console.print("[yellow bold]⚠️ Medium Severity Issues:[/yellow bold]")
            for issue in medium:
                self._print_single_issue(issue, "yellow")
            self.console.print()
        
        if low:
            self.console.print("[cyan bold]ℹ️ Low Severity Issues:[/cyan bold]")
            for issue in low:
                self._print_single_issue(issue, "cyan")
            self.console.print()
    
    def _print_single_issue(self, issue: Issue, color: str):
        """Print a single issue with details."""
        location_str = f" (line {issue.location})" if issue.location else ""
        self.console.print(f"  [{color}]•[/{color}] {issue.description}{location_str}")
        self.console.print(f"    [dim]→ {issue.suggestion}[/dim]")
    
    def _print_suggestions(self, suggestions: List[str]):
        """Print improvement suggestions."""
        self.console.print("[green bold]💡 Suggestions:[/green bold]")
        for suggestion in suggestions:
            self.console.print(f"  [green]•[/green] {suggestion}")
        self.console.print()
    
    @staticmethod
    def _score_to_str(score: float) -> str:
        """Convert score to formatted string with color."""
        if score >= 8.0:
            return f"[green]{score:.1f}/10[/green]"
        elif score >= 6.0:
            return f"[yellow]{score:.1f}/10[/yellow]"
        else:
            return f"[red]{score:.1f}/10[/red]"
    
    @staticmethod
    def _get_score_details(score: float) -> str:
        """Get descriptive details for a score."""
        if score >= 9.0:
            return "Excellent"
        elif score >= 7.0:
            return "Good"
        elif score >= 5.0:
            return "Fair"
        else:
            return "Needs improvement"
    
    @staticmethod
    def _get_cost_details(estimates: dict) -> str:
        """Get cost details summary."""
        if not estimates:
            return "Unable to calculate"
        
        costs = [e.total_cost for e in estimates.values()]
        avg_cost = sum(costs) / len(costs)
        
        if avg_cost < 0.001:
            return "Cheap"
        elif avg_cost < 0.01:
            return "Reasonable"
        else:
            return "Expensive"
    
    @staticmethod
    def _get_security_details(score: float) -> str:
        """Get security details based on score."""
        if score >= 8.0:
            return "Low risk"
        elif score >= 6.0:
            return "Medium risk"
        else:
            return "High risk"
