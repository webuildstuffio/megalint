"""
Core data models for PromptLint - Pydantic-based internal representation.

These models form the foundation for prompt parsing, analysis, and the seed
of future PromptIR (Intermediate Representation) evolution.
"""

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field
from enum import Enum


class InstructionType(str, Enum):
    """Types of instructions in a prompt."""
    ACTION = "action"
    CONSTRAINT = "constraint"
    FORMAT = "format"
    META = "meta"


class Instruction(BaseModel):
    """Represents a single instruction or directive."""
    text: str
    line: int
    type: InstructionType
    confidence: float = Field(default=0.8, ge=0.0, le=1.0)


class Variable(BaseModel):
    """Represents a placeholder/variable in the prompt."""
    name: str
    location: int  # line number
    format_style: str = "standard"  # standard, double-brace, angle, etc.
    has_validation: bool = False
    has_default: bool = False


class Conditional(BaseModel):
    """Represents conditional logic in the prompt."""
    text: str
    line: int
    condition_type: str  # if/then, case, etc.


class ParsedPrompt(BaseModel):
    """Complete parsed representation of a prompt."""
    raw_text: str
    instructions: List[Instruction] = Field(default_factory=list)
    variables: List[Variable] = Field(default_factory=list)
    conditionals: List[Conditional] = Field(default_factory=list)
    output_format: Optional[str] = None
    examples: List[str] = Field(default_factory=list)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    
    @property
    def line_count(self) -> int:
        """Total number of lines in the prompt."""
        return len(self.raw_text.splitlines())
    
    @property
    def word_count(self) -> int:
        """Total number of words in the prompt."""
        return len(self.raw_text.split())


class Issue(BaseModel):
    """Represents a found issue in a prompt."""
    severity: str = Field(..., pattern="^(high|medium|low)$")
    category: str = Field(..., pattern="^(clarity|cost|security)$")
    description: str
    location: Optional[int] = None  # line number
    suggestion: str


class CostEstimate(BaseModel):
    """Cost estimation for a prompt."""
    input_tokens: int
    estimated_output_tokens: int
    total_cost: float
    model: str
    
    @property
    def total_tokens(self) -> int:
        """Sum of input and output tokens."""
        return self.input_tokens + self.estimated_output_tokens


class ScoreResult(BaseModel):
    """Complete scoring result for a prompt."""
    clarity_score: float = Field(..., ge=0.0, le=10.0)
    cost_score: float = Field(..., ge=0.0, le=10.0)
    security_score: float = Field(..., ge=0.0, le=10.0)
    overall_score: float = Field(..., ge=0.0, le=10.0)
    issues: List[Issue] = Field(default_factory=list)
    suggestions: List[str] = Field(default_factory=list)
    cost_estimates: Dict[str, CostEstimate] = Field(default_factory=dict)


class DiffReport(BaseModel):
    """Report of differences between two prompts."""
    text_changes: List[str] = Field(default_factory=list)
    clarity_delta: float
    cost_delta: Dict[str, float]  # model -> cost change
    security_delta: float
    overall_delta: float
    recommendation: str
    added_lines: int = 0
    removed_lines: int = 0
    modified_lines: int = 0
