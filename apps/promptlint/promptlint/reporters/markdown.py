"""
Markdown Reporter - exports analysis results as Markdown.
"""

from typing import List
from ..core.models import ScoreResult, DiffReport, Issue


class MarkdownReporter:
    """Exports prompt analysis as Markdown."""
    
    @staticmethod
    def score_to_markdown(result: ScoreResult) -> str:
        """Convert ScoreResult to Markdown."""
        lines = [
            "# 📊 Prompt Analysis Report\n",
            "## Scores\n",
            f"- **Clarity**: {result.clarity_score:.1f}/10",
            f"- **Cost Efficiency**: {result.cost_score:.1f}/10",
            f"- **Security**: {result.security_score:.1f}/10",
            f"- **Overall**: {result.overall_score:.1f}/10\n",
        ]
        
        # Cost estimates
        if result.cost_estimates:
            lines.append("## Cost Estimates\n")
            lines.append("| Model | Input Tokens | Output Tokens | Total Cost |")
            lines.append("|-------|--------------|---------------|------------|")
            for model, estimate in result.cost_estimates.items():
                lines.append(
                    f"| {model} | {estimate.input_tokens} | "
                    f"{estimate.estimated_output_tokens} | ${estimate.total_cost:.4f} |"
                )
            lines.append("")
        
        # Issues
        if result.issues:
            lines.append("## Issues\n")
            
            high = [i for i in result.issues if i.severity == 'high']
            medium = [i for i in result.issues if i.severity == 'medium']
            low = [i for i in result.issues if i.severity == 'low']
            
            if high:
                lines.append("### ❌ High Severity\n")
                for issue in high:
                    lines.append(MarkdownReporter._format_issue(issue))
            
            if medium:
                lines.append("### ⚠️ Medium Severity\n")
                for issue in medium:
                    lines.append(MarkdownReporter._format_issue(issue))
            
            if low:
                lines.append("### ℹ️ Low Severity\n")
                for issue in low:
                    lines.append(MarkdownReporter._format_issue(issue))
        
        # Suggestions
        if result.suggestions:
            lines.append("## 💡 Suggestions\n")
            for suggestion in result.suggestions:
                lines.append(f"- {suggestion}")
            lines.append("")
        
        return "\n".join(lines)
    
    @staticmethod
    def diff_to_markdown(report: DiffReport) -> str:
        """Convert DiffReport to Markdown."""
        lines = [
            "# 📊 Prompt Comparison\n",
            "## Summary\n",
            f"- **Added Lines**: +{report.added_lines}",
            f"- **Removed Lines**: -{report.removed_lines}",
            f"- **Modified Lines**: {report.modified_lines}\n",
        ]
        
        # Deltas
        lines.append("## Impact Analysis\n")
        lines.append(f"- **Clarity**: {report.clarity_delta:+.1f}")
        lines.append(f"- **Security**: {report.security_delta:+.1f}")
        lines.append(f"- **Overall**: {report.overall_delta:+.1f}\n")
        
        # Cost deltas
        if report.cost_delta:
            lines.append("### Cost Changes\n")
            for model, delta in report.cost_delta.items():
                lines.append(f"- **{model}**: ${delta:+.4f}")
            lines.append("")
        
        # Recommendation
        lines.append("## 📋 Recommendation\n")
        lines.append(report.recommendation)
        lines.append("")
        
        # Text diff
        if report.text_changes:
            lines.append("## 📝 Changes\n")
            lines.append("```diff")
            lines.extend(report.text_changes)
            lines.append("```")
        
        return "\n".join(lines)
    
    @staticmethod
    def _format_issue(issue: Issue) -> str:
        """Format a single issue for Markdown."""
        location_str = f" (line {issue.location})" if issue.location else ""
        return (
            f"- **{issue.description}**{location_str}\n"
            f"  - Category: `{issue.category}`\n"
            f"  - Suggestion: {issue.suggestion}\n"
        )
