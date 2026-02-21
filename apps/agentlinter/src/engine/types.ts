/* ─── AgentLinter Core Types ─── */

export type Severity = "critical" | "error" | "warning" | "info";

export type Category =
  | "structure"
  | "clarity"
  | "completeness"
  | "security"
  | "consistency"
  | "memory"
  | "runtime"
  | "skillSafety"
  | "remoteReady";

export interface Diagnostic {
  severity: Severity;
  category: Category;
  rule: string;
  file: string;
  line?: number;
  message: string;
  fix?: string; // suggested fix description
}

export interface FileInfo {
  name: string;
  path: string;
  content: string;
  lines: string[];
  sections: Section[];
}

export interface Section {
  heading: string;
  level: number;
  startLine: number;
  endLine: number;
  content: string;
}

export interface CategoryScore {
  category: Category;
  score: number; // 0-100
  weight: number; // 0-1
  diagnostics: Diagnostic[];
}

export interface LintResult {
  workspace: string;
  files: FileInfo[];
  categories: CategoryScore[];
  totalScore: number;
  diagnostics: Diagnostic[];
  timestamp: string;
}

export interface Rule {
  id: string;
  category: Category;
  severity: Severity;
  description: string;
  check: (files: FileInfo[]) => Diagnostic[];
}

export const CATEGORY_WEIGHTS: Record<Category, number> = {
  structure: 0.10,
  clarity: 0.20,
  completeness: 0.13,
  security: 0.14,
  consistency: 0.11,
  memory: 0.13,
  runtime: 0.06,
  skillSafety: 0.08,
  remoteReady: 0.05,
};

export interface SeverityDeductions {
  critical: number;
  error: number;
  warning: number;
  info: number;
  infoCap: number;
  warningCap: number; // max warnings per-rule that contribute
  bonusCap: number;   // max total bonus per category
}

export const SEVERITY_DEDUCTIONS: Record<Category, SeverityDeductions> = {
  security:     { critical: 35, error: 22, warning: 8,  info: 2, infoCap: 12, warningCap: 3, bonusCap: 6 },
  runtime:      { critical: 30, error: 22, warning: 7,  info: 1, infoCap: 8,  warningCap: 3, bonusCap: 6 },
  skillSafety:  { critical: 30, error: 20, warning: 7,  info: 1, infoCap: 8,  warningCap: 3, bonusCap: 6 },
  clarity:      { critical: 25, error: 20, warning: 7,  info: 1, infoCap: 10, warningCap: 3, bonusCap: 8 },
  consistency:  { critical: 25, error: 20, warning: 7,  info: 2, infoCap: 10, warningCap: 3, bonusCap: 6 },
  structure:    { critical: 25, error: 18, warning: 7,  info: 2, infoCap: 10, warningCap: 3, bonusCap: 8 },
  completeness: { critical: 25, error: 18, warning: 7,  info: 1, infoCap: 10, warningCap: 3, bonusCap: 8 },
  memory:       { critical: 25, error: 18, warning: 6,  info: 1, infoCap: 8,  warningCap: 3, bonusCap: 8 },
  remoteReady:  { critical: 20, error: 15, warning: 5,  info: 1, infoCap: 6,  warningCap: 3, bonusCap: 8 },
};

export const CATEGORY_LABELS: Record<Category, string> = {
  structure: "Structure",
  clarity: "Clarity",
  completeness: "Completeness",
  security: "Security",
  consistency: "Consistency",
  memory: "Memory",
  runtime: "Runtime Config",
  skillSafety: "Skill Safety",
  remoteReady: "Remote-Ready",
};
