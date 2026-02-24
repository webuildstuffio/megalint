"""
Clarity Analyzer - evaluates prompt clarity and specificity.
"""

import re
from typing import List, Tuple
from ..core.models import ParsedPrompt, Issue, ScoreResult
from ..core.parser import PromptParser


class ClarityAnalyzer:
    """Analyzes prompt clarity and provides suggestions."""
    
    # Heuristic weights
    WEIGHTS = {
        'clear_structure': 2.0,
        'has_examples': 1.0,
        'has_output_format': 1.5,
        'step_by_step': 1.0,
        'ambiguous_phrases': -0.5,
        'conflicting_instructions': -1.0,
        'vague_quantities': -0.75,
    }
    
    @classmethod
    def analyze(cls, parsed: ParsedPrompt) -> Tuple[float, List[Issue], List[str]]:
        """
        Analyze prompt clarity.
        
        Returns (score, issues, suggestions)
        """
        issues = []
        suggestions = []
        score = 5.0  # Base score
        
        # Narrative/context files get relaxed clarity checks
        file_name = parsed.metadata.get('file_name', '')
        is_narrative = file_name in ('MEMORY.md', 'USER.md', 'BOOT.md', 'HEARTBEAT.md')
        is_identity = file_name in ('IDENTITY.md', 'SOUL.md')
        
        # Check for clear structure
        if len(parsed.instructions) > 0:
            score += cls.WEIGHTS['clear_structure']
        else:
            issues.append(Issue(
                severity='high',
                category='clarity',
                description='No clear instructions detected',
                suggestion='Add explicit imperative instructions (start with action verbs like "Always", "Never", "Use", "Respond")',
                why='Agents without explicit instructions fall back to base LLM behavior — polite, verbose, and permission-seeking. OpenClaw agents should act first and ask never. Every instruction is a behavioral directive that overrides the default.',
            ))
        
        # Check for examples (don't penalize identity/narrative files for lacking them)
        if len(parsed.examples) > 0:
            score += cls.WEIGHTS['has_examples']
        elif not is_narrative and not is_identity:
            suggestions.append('Add examples to clarify expected input/output')
        
        # Check for output format (don't penalize identity/narrative files)
        if parsed.output_format is not None:
            score += cls.WEIGHTS['has_output_format']
        elif not is_narrative and not is_identity:
            suggestions.append('Specify expected output format (JSON, markdown, etc.)')
        
        # Check for step-by-step (broadened beyond literal "step")
        text_lower = parsed.raw_text.lower()
        has_steps = (
            any('step' in instr.text.lower() for instr in parsed.instructions)
            or bool(re.search(r'^\s*[1-9]\.\s', parsed.raw_text, re.MULTILINE))
            or bool(re.search(r'\b(first|then|next|finally|after that)\b', text_lower))
            or bool(re.search(r'\bphase\s+[1-9]\b', text_lower))
        )
        if has_steps:
            score += cls.WEIGHTS['step_by_step']
        
        # Skip ambiguous phrase checks for narrative/context files entirely —
        # "could", "might", "around" are natural language in journals and user descriptions,
        # not ambiguous instructions. Only flag in instruction files (AGENTS.md, TOOLS.md, etc.)
        if not is_narrative:
            ambiguous_issues = cls._check_ambiguous_phrases(parsed)
            issues.extend(ambiguous_issues)
            score -= len(ambiguous_issues) * abs(cls.WEIGHTS['ambiguous_phrases'])
        
        # Check for vague quantities (reduced penalty for narrative files)
        vague_quantities = cls._check_vague_quantities(parsed)
        if vague_quantities:
            vague_penalty = cls.WEIGHTS['vague_quantities'] * (0.15 if is_narrative else 1.0)
            for line_num, phrase, suggestion in vague_quantities:
                issues.append(Issue(
                    severity='medium',
                    category='clarity',
                    description=f'Vague quantity: "{phrase}"',
                    location=line_num,
                    suggestion=suggestion,
                    why=f'Vague quantities ("{phrase}") force the model to estimate thresholds that should be explicit. Two runs with the same prompt may interpret "many" as 5 or 50, causing wildly inconsistent behavior at boundary conditions.',
                ))
                score += vague_penalty
        
        # Check for conflicting instructions
        conflicts = cls._check_conflicts(parsed)
        if conflicts:
            for conflict_desc in conflicts:
                issues.append(Issue(
                    severity='high',
                    category='clarity',
                    description=conflict_desc,
                    suggestion='Review instructions for contradictions — scope one instruction to specific contexts ("be brief in DMs, thorough in reports") to eliminate the conflict.',
                    why='Contradictory instructions make agent behavior unpredictable. The model picks whichever instruction its attention weights higher — essentially a coin flip. Every contradicted instruction reduces effective instruction count.',
                ))
                score += cls.WEIGHTS['conflicting_instructions']
        
        # Check variable usage
        if len(parsed.variables) > 0 and not parsed.metadata.get('has_examples'):
            suggestions.append('Provide example values for variables to improve clarity')
        
        # Intentionally brief files (IDENTITY.md, SOUL.md) shouldn't be penalized
        # for lacking examples, output format, or step-by-step — they're personality
        # definitions, not instruction sets. Floor at 8.0 if no actual issues found.
        if is_identity and len([i for i in issues if i.severity in ('high', 'medium')]) == 0:
            score = max(score, 8.0)
        
        # Normalize score to 0-10
        score = max(0.0, min(10.0, score))
        
        return score, issues, suggestions
    
    @classmethod
    def _check_ambiguous_phrases(cls, parsed: ParsedPrompt) -> List[Issue]:
        """Detect ambiguous and weak phrases using word-boundary matching."""
        issues = []
        ambiguous_phrases = PromptParser.AMBIGUOUS_PHRASES
        
        lines = parsed.raw_text.splitlines()
        
        for line_num, line in enumerate(lines, 1):
            line_lower = line.lower()
            for phrase, suggestion in ambiguous_phrases.items():
                if re.search(r'\b' + re.escape(phrase) + r'\b', line_lower):
                    issues.append(Issue(
                        severity='medium',
                        category='clarity',
                        description=f'Ambiguous phrase: "{phrase}"',
                        location=line_num,
                        suggestion=suggestion,
                        why=f'Ambiguous phrases delegate judgment to the model without criteria. "{phrase}" means something different to every model run — it will interpret it inconsistently across sessions. Every well-crafted industry prompt (Claude, GPT-5, Gemini) uses concrete thresholds instead.',
                    ))
        
        return issues
    
    @classmethod
    def _check_vague_quantities(cls, parsed: ParsedPrompt) -> List[Tuple[int, str, str]]:
        """Detect vague quantity expressions in instruction context."""
        results = []
        lines = parsed.raw_text.splitlines()
        
        # Narrative files get relaxed quantity checking
        file_name = parsed.metadata.get('file_name', '')
        is_narrative = file_name in ('MEMORY.md', 'USER.md', 'BOOT.md', 'HEARTBEAT.md')
        
        vague_patterns = [
            ('many', 'Specify exact number instead of "many"'),
            ('few', 'Specify exact number instead of "few"'),
            ('large', 'Define "large" precisely (size, length, etc.)'),
            ('small', 'Define "small" precisely (size, length, etc.)'),
            ('a lot', 'Specify quantity instead of "a lot"'),
            ('some', 'Be more specific than "some"'),
        ]
        
        # Words that when following "large"/"small" indicate descriptive use, not vague quantity
        DESCRIPTOR_NOUNS = re.compile(
            r'\b(large|small)\s+(family|group|team|company|organization|number|amount|'
            r'part|portion|collection|set|scale|volume|dataset|community|network|audience)\b',
            re.IGNORECASE
        )
        
        if is_narrative:
            return results
        
        for line_num, line in enumerate(lines, 1):
            line_lower = line.lower()
            for vague_word, suggestion in vague_patterns:
                if f' {vague_word} ' in f' {line_lower} ':
                    # Skip "large/small" when used as descriptive adjective with a noun
                    if vague_word in ('large', 'small') and DESCRIPTOR_NOUNS.search(line):
                        continue
                    results.append((line_num, vague_word, suggestion))
        
        return results
    
    @classmethod
    def _check_conflicts(cls, parsed: ParsedPrompt) -> List[str]:
        """Detect conflicting instructions.
        
        Only flags direct contradictions — same-phrase pairs that are
        genuinely incompatible. Removed ('ignore', 'consider') pair
        because those words appear in non-conflicting contexts constantly.
        """
        conflicts = []
        
        text_lower = parsed.raw_text.lower()
        
        # Only flag pairs that are almost always contradictory
        conflict_pairs = [
            (('be brief', 'be detailed'), 'Cannot be both brief and detailed'),
            (('be concise', 'elaborate on everything'), 'Cannot be both concise and elaborate on everything'),
            (('never ask', 'always ask'), 'Cannot both never ask and always ask for clarification'),
            (('respond in english', 'respond in korean'), 'Cannot respond in both English and Korean'),
            (('respond in english', 'always use korean'), 'Cannot respond in both English and Korean'),
            (('always use markdown', 'never use markdown'), 'Cannot both always and never use markdown'),
            (('always use bullet', 'never use bullet'), 'Cannot both always and never use bullets'),
            (('be informal', 'be formal'), 'Cannot be both formal and informal'),
            (('be casual', 'be professional'), 'Cannot be both casual and professional in the same context'),
            (('be formal', 'be casual'), 'Cannot be both formal and casual'),
            (('be direct', 'be diplomatic'), 'Cannot be both direct and diplomatic without scoping'),
            (('be verbose', 'be concise'), 'Cannot be both verbose and concise'),
            (('always confirm', 'never confirm'), 'Cannot both always and never ask for confirmation'),
            (('short responses', 'long responses'), 'Cannot require both short and long responses without scoping'),
            (('keep it short', 'be thorough'), 'Cannot keep short and be thorough without scoping'),
            (('proactive', 'only respond when asked'), 'Cannot be both proactive and only respond when asked'),
            (('respond immediately', 'wait before responding'), 'Cannot respond immediately and wait'),
        ]
        
        for (phrase1, phrase2), description in conflict_pairs:
            if phrase1 in text_lower and phrase2 in text_lower:
                conflicts.append(description)
        
        return conflicts
