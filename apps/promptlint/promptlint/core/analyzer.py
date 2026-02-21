"""
Main analyzer - orchestrates all individual analyzers.
"""

from ..analyzers.clarity import ClarityAnalyzer
from ..analyzers.cost import CostAnalyzer
from ..analyzers.security import SecurityAnalyzer
from .models import ParsedPrompt, ScoreResult


class Analyzer:
    """Main analyzer that runs all checks on a prompt."""
    
    @staticmethod
    def analyze(
        parsed: ParsedPrompt,
        models: list = None,
    ) -> ScoreResult:
        """
        Analyze a parsed prompt across all dimensions.
        
        Returns comprehensive ScoreResult with all metrics.
        """
        # Run all analyzers
        clarity_score, clarity_issues, clarity_suggestions = ClarityAnalyzer.analyze(parsed)
        
        cost_analyzer = CostAnalyzer()
        cost_score, cost_estimates, cost_issues, cost_suggestions = cost_analyzer.analyze(
            parsed, models=models
        )
        
        security_score, security_issues, security_suggestions = SecurityAnalyzer.analyze(parsed)
        
        # Combine issues and suggestions
        all_issues = clarity_issues + cost_issues + security_issues
        all_suggestions = clarity_suggestions + cost_suggestions + security_suggestions
        
        # Calculate overall score (average of three)
        overall_score = (clarity_score + cost_score + security_score) / 3.0
        
        return ScoreResult(
            clarity_score=clarity_score,
            cost_score=cost_score,
            security_score=security_score,
            overall_score=overall_score,
            issues=all_issues,
            suggestions=all_suggestions,
            cost_estimates=cost_estimates,
        )
