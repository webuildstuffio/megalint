"""
Cost Analyzer - calculates token counts and API costs for prompts.
"""

from typing import Dict, List, Tuple
from ..core.models import ParsedPrompt, Issue, CostEstimate
from ..utils.tokenizer import Tokenizer
from ..utils.pricing import PricingData


class CostAnalyzer:
    """Analyzes prompt costs and estimates API expenses."""
    
    # Weights for cost scoring
    WEIGHTS = {
        'reasonable_tokens': 0.0,
        'high_tokens': -2.0,
        'moderate_tokens': -0.5,
    }

    # Thresholds aligned with TOKEN_BUDGET_GUIDE.md (131k context window, base budgets).
    # Per-file thresholds use AGENTS.md as the reference (largest single file at 1725).
    # Total-system threshold uses the combined base budget (4865).
    # Scores drop only when a single file substantially exceeds AGENTS.md's WARN threshold,
    # or when total combined content exceeds the full system budget.
    TOKEN_THRESHOLDS = {
        'reasonable': 1725,   # AGENTS.md base — below this is fine, full score
        'moderate': 2588,     # AGENTS.md WARN threshold (base × 1.50) — approaching limit
        'high': 4865,         # Total system base budget — this is a full agent, not one file
        'very_high': 7298,    # Total system WARN threshold (4865 × 1.50) — significantly over
    }
    
    def __init__(self):
        """Initialize cost analyzer."""
        self.tokenizer = Tokenizer()
    
    def analyze(
        self,
        parsed: ParsedPrompt,
        models: List[str] = None,
    ) -> Tuple[float, Dict[str, CostEstimate], List[Issue], List[str]]:
        """
        Analyze prompt costs.
        
        Returns (score, cost_estimates_dict, issues, suggestions)
        """
        if models is None:
            models = PricingData.get_default_models()
        
        issues = []
        suggestions = []
        cost_estimates = {}
        
        # Count input tokens
        input_tokens = self.tokenizer.count_tokens(parsed.raw_text)
        
        # Estimate output tokens based on prompt complexity
        complexity = self._estimate_complexity(parsed)
        output_tokens = Tokenizer.estimate_output_tokens(
            parsed.raw_text,
            complexity=complexity
        )
        
        # Calculate costs for each model
        total_cost = 0.0
        for model in models:
            cost = PricingData.calculate_cost(model, input_tokens, output_tokens)
            if cost is not None:
                cost_estimates[model] = CostEstimate(
                    input_tokens=input_tokens,
                    estimated_output_tokens=output_tokens,
                    total_cost=cost,
                    model=model,
                )
                total_cost += cost
        
        # Check for expensive patterns — thresholds from TOKEN_BUDGET_GUIDE.md
        if input_tokens > self.TOKEN_THRESHOLDS['very_high']:
            issues.append(Issue(
                severity='high',
                category='cost',
                description=f'Very high token count: {input_tokens} tokens (WARN threshold: {self.TOKEN_THRESHOLDS["very_high"]})',
                suggestion='This exceeds the total system WARN budget (all files combined). Archive MEMORY.md entries to daily logs, move workflows to skills/, trim USER.md. See TOKEN_BUDGET_GUIDE.md.',
                why=f'At {input_tokens} tokens this content loads against a 131k context window — it\'s consuming over {round(input_tokens/131000*100)}% of available context before any conversation starts. TOKEN_BUDGET_GUIDE.md sets the total system base at 4,865 tokens (3.7% of 131k). Every extra token here compresses what fits in the conversation window.',
            ))
        elif input_tokens > self.TOKEN_THRESHOLDS['high']:
            issues.append(Issue(
                severity='medium',
                category='cost',
                description=f'High token count: {input_tokens} tokens (total system base: {self.TOKEN_THRESHOLDS["high"]})',
                suggestion='This is approaching the total combined system budget. Review for duplicated content (shared/ files already cover this?) or movable workflows. See TOKEN_BUDGET_GUIDE.md.',
                why=f'TOKEN_BUDGET_GUIDE.md targets 5–10% of context for system prompts. At {input_tokens} tokens this single analysis unit is already at the full-system baseline (4,865). Adding tool schemas (~7,000 tokens) would push total overhead near the 10% ceiling.',
            ))
        elif input_tokens > self.TOKEN_THRESHOLDS['moderate']:
            issues.append(Issue(
                severity='low',
                category='cost',
                description=f'File approaching AGENTS.md budget ceiling: {input_tokens} tokens (WARN: {self.TOKEN_THRESHOLDS["moderate"]})',
                suggestion='Approaching AGENTS.md WARN threshold. Move procedures to skills/ files — they load on-demand, not every turn. See TOKEN_BUDGET_GUIDE.md.',
                why=f'TOKEN_BUDGET_GUIDE.md sets AGENTS.md WARN threshold at 2,588 tokens (base 1,725 × 1.50). At {input_tokens} tokens this file is over budget and should be trimmed. HEARTBEAT.md is most expensive — 225 tokens × ~48 fires/day = ~10,800 tokens/day.',
            ))

        # Score calculation — penalty only when substantially over AGENTS.md WARN threshold
        score = 10.0
        if input_tokens > self.TOKEN_THRESHOLDS['very_high']:
            score += self.WEIGHTS['high_tokens']
        elif input_tokens > self.TOKEN_THRESHOLDS['high']:
            score += self.WEIGHTS['moderate_tokens']

        # Normalize to 0-10
        score = max(0.0, min(10.0, score))

        # Add informational suggestions
        if len(parsed.variables) > 5:
            suggestions.append(f'Many variables ({len(parsed.variables)}) detected — ensure they are all needed')

        if len(parsed.examples) == 0:
            suggestions.append('Adding examples increases tokens but improves output quality (tradeoff worth considering)')
        
        return score, cost_estimates, issues, suggestions
    
    @staticmethod
    def _estimate_complexity(parsed: ParsedPrompt) -> str:
        """
        Estimate prompt complexity to inform output token estimation.
        
        Returns: simple, normal, complex, or reasoning
        """
        # Count complexity indicators
        complex_keywords = [
            'analyze', 'evaluate', 'compare', 'think', 'reason',
            'step by step', 'reasoning', 'logic', 'complex',
        ]
        
        text_lower = parsed.raw_text.lower()
        complex_count = sum(1 for kw in complex_keywords if kw in text_lower)
        
        # Consider prompt structure
        if len(parsed.instructions) == 0:
            return 'simple'
        elif len(parsed.instructions) <= 3 and complex_count == 0:
            return 'simple'
        elif len(parsed.instructions) <= 6 and complex_count <= 1:
            return 'normal'
        elif complex_count >= 3 or len(parsed.instructions) > 10:
            return 'complex'
        elif 'step by step' in text_lower or 'reasoning' in text_lower:
            return 'reasoning'
        else:
            return 'normal'
