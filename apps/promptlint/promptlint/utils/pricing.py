"""
Pricing module - contains model pricing data and cost calculation utilities.
"""

from typing import Dict, Optional
from dataclasses import dataclass


@dataclass
class ModelPricing:
    """Pricing information for a model."""
    input_price_per_1m: float  # Price per 1 million tokens
    output_price_per_1m: float  # Price per 1 million tokens


class PricingData:
    """Central pricing data for supported models."""
    
    # Pricing in USD, accurate as of November 2025
    PRICING: Dict[str, ModelPricing] = {
        'gpt-4o': ModelPricing(
            input_price_per_1m=2.50,
            output_price_per_1m=10.00,
        ),
        'gpt-4o-mini': ModelPricing(
            input_price_per_1m=0.15,
            output_price_per_1m=0.60,
        ),
        'gpt-4-turbo': ModelPricing(
            input_price_per_1m=10.00,
            output_price_per_1m=30.00,
        ),
        'gpt-3.5-turbo': ModelPricing(
            input_price_per_1m=0.50,
            output_price_per_1m=1.50,
        ),
        'claude-3.5-sonnet': ModelPricing(
            input_price_per_1m=3.00,
            output_price_per_1m=15.00,
        ),
        'claude-3.5-haiku': ModelPricing(
            input_price_per_1m=0.80,
            output_price_per_1m=4.00,
        ),
        'claude-3-opus': ModelPricing(
            input_price_per_1m=15.00,
            output_price_per_1m=75.00,
        ),
    }
    
    @classmethod
    def get_pricing(cls, model: str) -> Optional[ModelPricing]:
        """Get pricing for a model, returns None if not found."""
        return cls.PRICING.get(model.lower())
    
    @classmethod
    def calculate_cost(
        cls,
        model: str,
        input_tokens: int,
        output_tokens: int,
    ) -> Optional[float]:
        """
        Calculate cost for a model usage.
        
        Returns cost in USD, or None if model not found.
        """
        pricing = cls.get_pricing(model)
        if not pricing:
            return None
        
        input_cost = (input_tokens / 1_000_000) * pricing.input_price_per_1m
        output_cost = (output_tokens / 1_000_000) * pricing.output_price_per_1m
        
        return input_cost + output_cost
    
    @classmethod
    def get_supported_models(cls) -> list:
        """Get list of supported models."""
        return sorted(list(cls.PRICING.keys()))
    
    @classmethod
    def get_default_models(cls) -> list:
        """Get default models for comparison."""
        return ['gpt-4o', 'gpt-4o-mini', 'claude-3.5-sonnet']
