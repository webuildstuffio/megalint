"""
JSON Reporter - exports analysis results as JSON.
"""

import json
from typing import Dict, Any
from ..core.models import ScoreResult, DiffReport


class JSONReporter:
    """Exports prompt analysis as JSON."""
    
    @staticmethod
    def score_to_dict(result: ScoreResult) -> Dict[str, Any]:
        """Convert ScoreResult to dictionary."""
        return {
            'scores': {
                'clarity': result.clarity_score,
                'cost_efficiency': result.cost_score,
                'security': result.security_score,
                'overall': result.overall_score,
            },
            'cost_estimates': {
                model: {
                    'input_tokens': estimate.input_tokens,
                    'output_tokens': estimate.estimated_output_tokens,
                    'total_cost': estimate.total_cost,
                }
                for model, estimate in result.cost_estimates.items()
            },
            'issues': [
                {
                    'severity': issue.severity,
                    'category': issue.category,
                    'description': issue.description,
                    'location': issue.location,
                    'suggestion': issue.suggestion,
                }
                for issue in result.issues
            ],
            'suggestions': result.suggestions,
        }
    
    @staticmethod
    def diff_to_dict(report: DiffReport) -> Dict[str, Any]:
        """Convert DiffReport to dictionary."""
        return {
            'summary': {
                'added_lines': report.added_lines,
                'removed_lines': report.removed_lines,
                'modified_lines': report.modified_lines,
            },
            'deltas': {
                'clarity': report.clarity_delta,
                'security': report.security_delta,
                'overall': report.overall_delta,
                'cost': report.cost_delta,
            },
            'recommendation': report.recommendation,
            'text_changes': report.text_changes,
        }
    
    @staticmethod
    def to_json_string(data: Dict[str, Any], indent: int = 2) -> str:
        """Convert dictionary to JSON string."""
        return json.dumps(data, indent=indent)
    
    @staticmethod
    def print_score_report(result: ScoreResult) -> str:
        """Return formatted JSON score report."""
        return JSONReporter.to_json_string(JSONReporter.score_to_dict(result))
    
    @staticmethod
    def print_diff_report(report: DiffReport) -> str:
        """Return formatted JSON diff report."""
        return JSONReporter.to_json_string(JSONReporter.diff_to_dict(report))
