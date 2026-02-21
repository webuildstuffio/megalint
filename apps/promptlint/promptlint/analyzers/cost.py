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
    
    TOKEN_THRESHOLDS = {
        'low': 500,
        'moderate': 1000,
        'high': 2000,
        'very_high': 4000,
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
        
        # Check for expensive patterns
        if input_tokens > self.TOKEN_THRESHOLDS['very_high']:
            issues.append(Issue(
                severity='high',
                category='cost',
                description=f'Very high token count: {input_tokens} tokens',
                suggestion='Consider breaking prompt into smaller parts or removing unnecessary context',
            ))
        elif input_tokens > self.TOKEN_THRESHOLDS['high']:
            issues.append(Issue(
                severity='medium',
                category='cost',
                description=f'High token count: {input_tokens} tokens',
                suggestion='Review for unnecessary verbosity or redundant instructions',
            ))
        
        # Score calculation
        score = 10.0
        if input_tokens > self.TOKEN_THRESHOLDS['very_high']:
            score += self.WEIGHTS['high_tokens']
        elif input_tokens > self.TOKEN_THRESHOLDS['high']:
            score += self.WEIGHTS['moderate_tokens']
        
        # Normalize to 0-10
        score = max(0.0, min(10.0, score))
        
        # Add optimization suggestions
        if len(parsed.variables) > 5:
            suggestions.append(f'Many variables ({len(parsed.variables)}) detected - ensure they are all necessary')
        
        if len(parsed.examples) == 0:
            suggestions.append('Adding examples increases tokens but improves output quality (consider tradeoff)')
        
        if len(parsed.instructions) > 10:
            suggestions.append('Many instructions detected - consider combining related instructions')
        
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
