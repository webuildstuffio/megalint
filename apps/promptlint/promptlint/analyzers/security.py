"""
Security Analyzer - detects prompt injection vulnerabilities and unsafe patterns.
"""

import re
from typing import List, Tuple
from ..core.models import ParsedPrompt, Issue


class SecurityAnalyzer:
    """Analyzes prompts for security vulnerabilities."""
    
    # High-risk injection patterns
    HIGH_RISK_PATTERNS = [
        (r'\bignore\s+(all\s+)?previous\s+(instructions|commands|prompt)', 'Prompt override attempt'),
        (r'\breveal\s+(\w+\s+)?system\s+prompt', 'System prompt leakage attempt'),
        (r'\bshow\s+(me\s+)?(\w+\s+)?(system\s+)?prompt', 'System prompt disclosure attempt'),
        (r'\b(act|pretend|role-play)\s+as\s+.*\s+and\s+(ignore|forget|disregard)', 'Role confusion attack'),
        (r'\bforgot\s+all\s+previous\s+instructions', 'Instruction override attempt'),
        (r'\b(execute|eval|run|compile)\s+(?!.*\b(changes|review|quality|style|standards?|linting)\b).*\bcode\b', 'Code execution risk'),
    ]

    # Lines containing restriction language are defensive, not offensive
    RESTRICTION_PATTERN = re.compile(
        r'\b(never|don\'t|do\s+not|must\s+not|shall\s+not|prohibited|forbidden|restricted)\b',
        re.IGNORECASE,
    )
    
    # Medium-risk patterns (placeholder patterns removed — {var}, ${var}, <tag> are
    # normal template/markdown syntax, not injection vectors. They were causing
    # every MDS file to score 0 due to massive false positives.)
    MEDIUM_RISK_PATTERNS = [
        (r'\beval\s*[\(\{"\']', 'Potential code execution via eval()'),
        (r'\breturn\s+internal', 'Potential information disclosure'),
        (r'\bdebug\s+mode', 'Debug mode reference'),
    ]
    
    # LOW_RISK_PATTERNS removed — were defined but never scored (dead code).
    # They matched "translate", "summarize", "explain" as positive signals
    # but were never wired into the analyze() method.
    
    @classmethod
    def analyze(cls, parsed: ParsedPrompt) -> Tuple[float, List[Issue], List[str]]:
        """
        Analyze prompt for security issues.
        
        Returns (score, issues, suggestions)
        """
        issues = []
        suggestions = []
        score = 10.0
        
        text_lower = parsed.raw_text.lower()
        text = parsed.raw_text
        lines = text.splitlines()
        
        # Check high-risk patterns
        for pattern, description in cls.HIGH_RISK_PATTERNS:
            for line_num, line in enumerate(lines, 1):
                if re.search(pattern, line, re.IGNORECASE):
                    if cls.RESTRICTION_PATTERN.search(line):
                        continue
                    issues.append(Issue(
                        severity='high',
                        category='security',
                        description=f'HIGH RISK: {description}',
                        location=line_num,
                        suggestion='Remove or rephrase this instruction to prevent prompt injection',
                        why=f'{description} in a config file creates an attack surface: pasted external content could trigger this pattern and override agent behavior. OpenClaw agents process Discord/Telegram messages that may contain injected instructions — a system prompt that itself contains override-style language weakens the agent\'s resistance to injection attacks.',
                    ))
                    score -= 3.0
        
        # Check medium-risk patterns
        for pattern, description in cls.MEDIUM_RISK_PATTERNS:
            for line_num, line in enumerate(lines, 1):
                if re.search(pattern, line):
                    issues.append(Issue(
                        severity='medium',
                        category='security',
                        description=f'MEDIUM RISK: {description}',
                        location=line_num,
                        suggestion='Consider adding input validation or sanitization',
                        why=f'{description} may create unintended code execution paths or information disclosure. In a private single-user system the risk is lower, but config files load into LLM context on every message — patterns here can be triggered by crafted user inputs.',
                    ))
                    score -= 0.5
        
        # Unguarded variables check removed — MDS config files use template
        # variables ({agent_name}, {topic}, etc.) that are system-level config,
        # not user-input placeholders needing sanitization. The check was costing
        # -1.0 per variable, tanking scores for normal template syntax.
        
        # Normalize score
        score = max(0.0, min(10.0, score))
        
        # Add suggestions
        if len(parsed.variables) > 0:
            suggestions.append('Consider documenting validation rules for all variables')
        
        if score < 5.0:
            suggestions.append('High security risk detected - review and test thoroughly before production use')
        elif score < 7.0:
            suggestions.append('Medium security risk - add input validation to reduce attack surface')
        
        return score, issues, suggestions
    
