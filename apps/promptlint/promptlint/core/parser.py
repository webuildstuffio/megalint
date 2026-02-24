"""
Parser module - extracts structure from raw prompt text.

Detects instructions, variables, conditionals, output formats, and examples.
"""

import re
from typing import List, Optional
from pathlib import Path

from .models import ParsedPrompt, Instruction, Variable, Conditional, InstructionType


class PromptParser:
    """Parses raw prompt text into structured data."""
    
    # Regex patterns for variable detection
    VARIABLE_PATTERNS = [
        (r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}', 'brace'),           # {variable}
        (r'\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}', 'double_brace'), # {{variable}}
        (r'<([a-zA-Z_][a-zA-Z0-9_]*)>', 'angle'),             # <variable>
        (r'\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}', 'dollar_brace'),  # ${variable}
    ]
    
    # Patterns for ambiguous/weak phrases
    AMBIGUOUS_PHRASES = {
        'as needed': 'Vague condition - specify exact conditions',
        'if possible': 'Soft requirement - make it clear if required',
        'try to': 'Weak instruction - use imperative form',
        'maybe': 'Ambiguous - be definitive',
        'perhaps': 'Ambiguous - be definitive',
        'might': 'Uncertain phrasing - be precise',
        'could': 'Uncertain phrasing - be precise',
        'should probably': 'Weak instruction - use clear directive',
        'approximately': 'Vague quantity - be specific',
        'roughly': 'Vague quantity - be specific',
        'around': 'Vague quantity - be specific',
    }
    
    # Patterns for clarity boosters
    CLARITY_BOOSTERS = [
        'step by step',
        'first', 'then', 'finally', 'next',
        'output format:', 'format:', 'example:', 'examples:',
        'requirements:', 'constraint:', 'constraints:',
        'rules:', 'rule:',
    ]
    
    # Patterns for output format detection
    OUTPUT_FORMAT_INDICATORS = [
        'json', 'xml', 'csv', 'yaml', 'markdown', 'html', 'plain text',
        'table', 'list', 'structured', 'numbered', 'bulleted'
    ]
    
    @classmethod
    def parse_file(cls, file_path: str) -> ParsedPrompt:
        """Parse a prompt from a file."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Prompt file not found: {file_path}")
        
        with open(path, 'r', encoding='utf-8') as f:
            raw_text = f.read()
        
        parsed = cls.parse(raw_text)
        parsed.metadata['file_name'] = path.name
        return parsed
    
    @classmethod
    def parse(cls, raw_text: str) -> ParsedPrompt:
        """Parse raw prompt text into structured representation."""
        parsed = ParsedPrompt(raw_text=raw_text)
        
        # Extract structure
        parsed.instructions = cls._extract_instructions(raw_text)
        parsed.variables = cls._extract_variables(raw_text)
        parsed.conditionals = cls._extract_conditionals(raw_text)
        parsed.output_format = cls._detect_output_format(raw_text)
        parsed.examples = cls._extract_examples(raw_text)
        
        # Add metadata
        parsed.metadata = {
            'has_examples': len(parsed.examples) > 0,
            'has_output_format': parsed.output_format is not None,
            'has_variables': len(parsed.variables) > 0,
            'has_conditionals': len(parsed.conditionals) > 0,
            'instruction_count': len(parsed.instructions),
            'variable_count': len(parsed.variables),
        }
        
        return parsed
    
    @classmethod
    def _extract_instructions(cls, text: str) -> List[Instruction]:
        """Extract imperative instructions from text."""
        instructions = []
        lines = text.splitlines()
        
        # Common instruction starting words
        action_keywords = [
            'generate', 'create', 'write', 'build', 'analyze', 'summarize',
            'explain', 'translate', 'format', 'convert', 'extract', 'identify',
            'list', 'describe', 'compare', 'evaluate', 'check', 'validate',
            'answer', 'respond', 'provide', 'return', 'output', 'show',
        ]
        
        constraint_keywords = [
            'do not', "don't", 'avoid', 'never', 'cannot', 'must not',
            'should not', 'without', 'except', 'ignore',
        ]
        
        format_keywords = [
            'format', 'structure', 'organize', 'arrange', 'order', 'sort',
            'json', 'xml', 'csv', 'yaml', 'markdown', 'html',
        ]
        
        meta_keywords = [
            'think', 'reasoning', 'step', 'process', 'logic', 'approach',
        ]
        
        for line_num, line in enumerate(lines, 1):
            stripped = line.strip().lower()
            if not stripped:
                continue
            
            # Determine instruction type
            instr_type = InstructionType.ACTION
            confidence = 0.6
            
            if any(kw in stripped for kw in constraint_keywords):
                instr_type = InstructionType.CONSTRAINT
                confidence = 0.85
            elif any(kw in stripped for kw in format_keywords):
                instr_type = InstructionType.FORMAT
                confidence = 0.9
            elif any(kw in stripped for kw in meta_keywords):
                instr_type = InstructionType.META
                confidence = 0.7
            elif any(stripped.startswith(kw) for kw in action_keywords):
                instr_type = InstructionType.ACTION
                confidence = 0.85
            
            if confidence > 0.5:  # Only include if reasonably confident
                instructions.append(
                    Instruction(
                        text=line.strip(),
                        line=line_num,
                        type=instr_type,
                        confidence=confidence,
                    )
                )
        
        return instructions
    
    @classmethod
    def _extract_variables(cls, text: str) -> List[Variable]:
        """Extract placeholder variables from text."""
        variables = []
        seen = set()
        
        for pattern, style in cls.VARIABLE_PATTERNS:
            for match in re.finditer(pattern, text, re.IGNORECASE):
                var_name = match.group(1)
                if var_name.lower() not in seen:
                    # Find line number
                    line_num = text[:match.start()].count('\n') + 1
                    variables.append(
                        Variable(
                            name=var_name,
                            location=line_num,
                            format_style=style,
                        )
                    )
                    seen.add(var_name.lower())
        
        return variables
    
    @classmethod
    def _extract_conditionals(cls, text: str) -> List[Conditional]:
        """Extract conditional logic patterns."""
        conditionals = []
        lines = text.splitlines()
        
        # Simple patterns for if/then logic
        if_pattern = re.compile(r'\bif\b.*\bthen\b', re.IGNORECASE)
        
        for line_num, line in enumerate(lines, 1):
            if if_pattern.search(line):
                conditionals.append(
                    Conditional(
                        text=line.strip(),
                        line=line_num,
                        condition_type='if_then',
                    )
                )
        
        return conditionals
    
    @classmethod
    def _detect_output_format(cls, text: str) -> Optional[str]:
        """Detect the requested output format."""
        text_lower = text.lower()
        
        for fmt in cls.OUTPUT_FORMAT_INDICATORS:
            if fmt in text_lower:
                return fmt
        
        return None
    
    @classmethod
    def _extract_examples(cls, text: str) -> List[str]:
        """Extract example inputs/outputs from text."""
        examples = []
        lines = text.splitlines()
        
        in_example = False
        example_lines = []
        
        for line in lines:
            lower = line.lower().strip()
            
            # Detect example markers — also capture inline content after the marker
            marker_found = False
            for marker in ['example:', 'example input:', 'sample:', 'input:', '>>>']:
                if marker in lower:
                    in_example = True
                    marker_found = True
                    idx = lower.index(marker) + len(marker)
                    remainder = line.strip()[idx:].strip()
                    if remainder:
                        example_lines.append(remainder)
                    break
            if marker_found:
                continue
            
            # Detect end of example
            if in_example and (line.strip() == '' or any(marker in lower for marker in ['question:', 'instruction:', 'note:', 'warning:'])):
                if example_lines:
                    examples.append('\n'.join(example_lines))
                example_lines = []
                in_example = False
                continue
            
            if in_example and line.strip():
                example_lines.append(line)
        
        # Don't keep incomplete examples
        if example_lines and len('\n'.join(example_lines)) > 20:
            examples.append('\n'.join(example_lines))
        
        return examples
