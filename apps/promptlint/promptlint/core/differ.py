"""
Differ module - compares two prompts and shows impact analysis.
"""

import difflib
from typing import List, Dict
from ..core.models import ParsedPrompt, DiffReport
from ..core.parser import PromptParser
from ..core.analyzer import Analyzer
from ..utils.pricing import PricingData


class Differ:
    """Compares two prompts and analyzes differences."""
    
    @staticmethod
    def diff_prompts(
        old_path: str,
        new_path: str,
        models: List[str] = None,
    ) -> DiffReport:
        """
        Compare two prompt files and generate diff report.
        
        Returns DiffReport with changes and impact analysis.
        """
        # Parse both prompts
        old_prompt = PromptParser.parse_file(old_path)
        new_prompt = PromptParser.parse_file(new_path)
        
        return Differ.diff(old_prompt, new_prompt, models=models)
    
    @staticmethod
    def diff(
        old_prompt: ParsedPrompt,
        new_prompt: ParsedPrompt,
        models: List[str] = None,
    ) -> DiffReport:
        """
        Compare two parsed prompts.
        
        Returns DiffReport with changes and impact analysis.
        """
        if models is None:
            models = PricingData.get_default_models()
        
        # Generate text diff
        old_lines = old_prompt.raw_text.splitlines(keepends=True)
        new_lines = new_prompt.raw_text.splitlines(keepends=True)
        
        diff_gen = difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile='old_prompt',
            tofile='new_prompt',
            lineterm='',
        )
        text_changes = list(diff_gen)
        
        # Count line changes
        added_lines = sum(1 for line in text_changes if line.startswith('+') and not line.startswith('+++'))
        removed_lines = sum(1 for line in text_changes if line.startswith('-') and not line.startswith('---'))
        modified_lines = min(added_lines, removed_lines)
        added_lines -= modified_lines
        removed_lines -= modified_lines
        
        # Analyze both prompts
        old_scores = Analyzer.analyze(old_prompt, models=models)
        new_scores = Analyzer.analyze(new_prompt, models=models)
        
        # Calculate deltas
        clarity_delta = new_scores.clarity_score - old_scores.clarity_score
        security_delta = new_scores.security_score - old_scores.security_score
        overall_delta = new_scores.overall_score - old_scores.overall_score
        
        # Calculate cost deltas
        cost_delta = {}
        for model in models:
            old_cost = old_scores.cost_estimates.get(model)
            new_cost = new_scores.cost_estimates.get(model)
            
            if old_cost and new_cost:
                delta = new_cost.total_cost - old_cost.total_cost
                cost_delta[model] = delta
        
        # Generate recommendation
        recommendation = Differ._generate_recommendation(
            clarity_delta,
            security_delta,
            overall_delta,
            cost_delta,
        )
        
        return DiffReport(
            text_changes=text_changes,
            clarity_delta=clarity_delta,
            cost_delta=cost_delta,
            security_delta=security_delta,
            overall_delta=overall_delta,
            recommendation=recommendation,
            added_lines=added_lines,
            removed_lines=removed_lines,
            modified_lines=modified_lines,
        )
    
    @staticmethod
    def _generate_recommendation(
        clarity_delta: float,
        security_delta: float,
        overall_delta: float,
        cost_delta: Dict[str, float],
    ) -> str:
        """Generate a human-readable recommendation based on deltas."""
        points = []
        
        # Clarity feedback
        if clarity_delta > 1.0:
            points.append("✅ Clarity improved significantly")
        elif clarity_delta > 0.2:
            points.append("✅ Clarity improved")
        elif clarity_delta < -1.0:
            points.append("⚠️ Clarity decreased significantly")
        elif clarity_delta < -0.2:
            points.append("⚠️ Clarity decreased")
        
        # Security feedback
        if security_delta > 1.0:
            points.append("✅ Security improved")
        elif security_delta < -1.0:
            points.append("⚠️ Security risk increased")
        
        # Cost feedback
        avg_cost_delta = sum(cost_delta.values()) / len(cost_delta) if cost_delta else 0
        if avg_cost_delta < -0.001:
            percent_change = (avg_cost_delta / abs(avg_cost_delta + 0.00001)) * 100
            points.append(f"💰 Cost decreased (~{abs(percent_change):.0f}%)")
        elif avg_cost_delta > 0.001:
            percent_change = (avg_cost_delta / abs(avg_cost_delta + 0.00001)) * 100
            points.append(f"💰 Cost increased (~{percent_change:.0f}%)")
        
        # Overall recommendation
        if overall_delta > 0.5:
            overall = "✅ This change improves the prompt overall"
        elif overall_delta < -0.5:
            overall = "⚠️ This change may reduce prompt quality"
        else:
            overall = "→ Neutral change - no significant impact"
        
        if not points:
            return overall
        
        return "\n".join(points) + "\n" + overall
