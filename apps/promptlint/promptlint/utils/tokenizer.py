"""
Tokenizer utility - handles token counting for various models.
"""

from typing import Dict, Optional


class Tokenizer:
    """Token counting for different models."""
    
    # Approximate tokens per word (fallback if tiktoken unavailable)
    TOKENS_PER_WORD = 1.3
    
    # Model-specific token estimates (fallback)
    MODEL_MULTIPLIERS = {
        'gpt-4o': 1.0,
        'gpt-4o-mini': 1.0,
        'claude-3.5-sonnet': 1.0,
        'claude-3.5-haiku': 1.0,
    }
    
    _tiktoken_available = False
    _encodings: Dict[str, any] = {}
    
    def __init__(self):
        """Initialize tokenizer."""
        try:
            import tiktoken
            self._tiktoken_available = True
            self.tiktoken = tiktoken
        except ImportError:
            self._tiktoken_available = False
            self.tiktoken = None
    
    def count_tokens(self, text: str, model: str = 'gpt-4o') -> int:
        """Count tokens in text for a given model."""
        if self._tiktoken_available:
            return self._count_with_tiktoken(text, model)
        else:
            return self._count_with_fallback(text, model)
    
    def _count_with_tiktoken(self, text: str, model: str) -> int:
        """Count tokens using tiktoken (most accurate)."""
        try:
            # Map model names to tiktoken encoding names
            encoding_map = {
                'gpt-4o': 'o200k_base',
                'gpt-4o-mini': 'o200k_base',
                'gpt-4-turbo': 'cl100k_base',
                'gpt-3.5-turbo': 'cl100k_base',
            }
            
            encoding_name = encoding_map.get(model, 'cl100k_base')
            
            if encoding_name not in self._encodings:
                self._encodings[encoding_name] = self.tiktoken.get_encoding(encoding_name)
            
            encoding = self._encodings[encoding_name]
            tokens = encoding.encode(text)
            return len(tokens)
        except Exception:
            # Fallback if tiktoken fails
            return self._count_with_fallback(text, model)
    
    def _count_with_fallback(self, text: str, model: str) -> int:
        """Fallback token counting using word estimation."""
        words = len(text.split())
        multiplier = self.MODEL_MULTIPLIERS.get(model, 1.0)
        return int(words * self.TOKENS_PER_WORD * multiplier)
    
    @staticmethod
    def estimate_output_tokens(
        input_prompt: str,
        complexity: str = 'normal'
    ) -> int:
        """
        Estimate output tokens based on prompt characteristics.
        
        Complexity levels affect output estimation:
        - simple: ~50-100 tokens
        - normal: ~100-500 tokens
        - complex: ~500-2000 tokens
        - reasoning: ~2000-5000 tokens
        """
        word_count = len(input_prompt.split())
        
        # Base estimation: roughly 2x input tokens for normal tasks
        base_estimate = int(word_count * 1.3)
        
        # Adjust by complexity
        complexity_multipliers = {
            'simple': 0.5,
            'normal': 2.0,
            'complex': 3.5,
            'reasoning': 5.0,
        }
        
        multiplier = complexity_multipliers.get(complexity, 2.0)
        estimate = int(base_estimate * multiplier)
        
        # Clamp to reasonable bounds
        return max(50, min(5000, estimate))
