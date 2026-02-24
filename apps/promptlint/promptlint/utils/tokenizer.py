"""
Tokenizer utility — all counting uses tiktoken (cl100k_base).
"""

from typing import Dict

import tiktoken


class Tokenizer:
    """Token counting using tiktoken cl100k_base encoding."""

    _enc = tiktoken.get_encoding("cl100k_base")

    def count_tokens(self, text: str, model: str = 'gpt-4o') -> int:
        """Count tokens in text using tiktoken cl100k_base."""
        return len(self._enc.encode(text))

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
        input_tokens = len(Tokenizer._enc.encode(input_prompt))

        complexity_multipliers = {
            'simple': 0.5,
            'normal': 2.0,
            'complex': 3.5,
            'reasoning': 5.0,
        }

        multiplier = complexity_multipliers.get(complexity, 2.0)
        estimate = int(input_tokens * multiplier)

        return max(50, min(5000, estimate))
