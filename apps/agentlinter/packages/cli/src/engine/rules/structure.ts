/* ─── Structure Rules (20%) ─── */

import { Rule, FileInfo, Diagnostic } from "../types";

export const structureRules: Rule[] = [
  {
    id: "structure/has-main-file",
    category: "structure",
    severity: "critical",
    description: "Workspace must have a CLAUDE.md or AGENTS.md file",
    check(files) {
      const hasMain = files.some(
        (f) =>
          f.name === "CLAUDE.md" ||
          f.name === "AGENTS.md" ||
          f.name === ".claude/CLAUDE.md"
      );
      if (!hasMain) {
        return [
          {
            severity: "critical",
            category: "structure",
            rule: this.id,
            file: "(workspace)",
            message:
              "No CLAUDE.md or AGENTS.md found. This is the entry point that defines everything — operational rules, action tiers, tool preferences. Without it, the agent has no instructions beyond base LLM behavior. In OpenClaw MDS, AGENTS.md is the primary config file that loads on every message.",
            fix: "Create AGENTS.md with action tiers (Always/When Asked/Ask First/Never), tool preferences, and operational rules. See agents/template/AGENTS.md for the skeleton.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "structure/has-sections",
    category: "structure",
    severity: "warning",
    description: "Main file should have organized sections with headings",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (mainFile && mainFile.sections.length < 3) {
        diagnostics.push({
          severity: "warning",
          category: "structure",
          rule: this.id,
          file: mainFile.name,
          message: `Only ${mainFile.sections.length} section(s) found. Flat instruction files dilute priority — the model treats everything as equally important. Structured sections (## Always, ## When Asked, ## Memory) create implicit priority through grouping.`,
          fix: "Add sections per CONVENTIONS.md: ## Always, ## When Asked, ## Ask First, ## Never for action tiers. Add ## Memory, ## Tools as needed.",
        });
      }
      return diagnostics;
    },
  },

  {
    id: "structure/heading-hierarchy",
    category: "structure",
    severity: "info",
    description: "Headings should follow a logical hierarchy (no skipping levels)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      for (const file of files) {
        if (!file.name.endsWith(".md")) continue;
        // Skip agent workspace dirs — research/log docs don't need strict heading hierarchy
        if (file.name.startsWith("compound/") || file.name.startsWith("memory/")) continue;
        let prevLevel = 0;
        for (const section of file.sections) {
          if (prevLevel > 0 && section.level > prevLevel + 1) {
            diagnostics.push({
              severity: "info",
              category: "structure",
              rule: this.id,
              file: file.name,
              line: section.startLine + 1,
              message: `Heading level skipped: h${prevLevel} → h${section.level}. Skipped heading levels confuse document structure parsing — both for humans editing and for LLMs interpreting the hierarchy of instructions.`,
              fix: `Use h${prevLevel + 1} instead of h${section.level}. Keep heading levels sequential: h1 → h2 → h3.`,
            });
          }
          prevLevel = section.level;
        }
      }
      return diagnostics;
    },
  },

  {
    id: "structure/file-size",
    category: "structure",
    severity: "warning",
    description: "Files should not be excessively long (readability)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      for (const file of files) {
        if (file.name === "CLAUDE.md" || file.name === "AGENTS.md") {
          if (file.lines.length > 500) {
            diagnostics.push({
              severity: "warning",
              category: "structure",
              rule: this.id,
              file: file.name,
              message: `File is ${file.lines.length} lines. In OpenClaw MDS, each file loads on every message — a 500-line monolith wastes tokens and makes maintenance painful. Split into focused files that each serve one purpose.`,
              fix: "Split per MDS convention: SOUL.md (personality ≤200 tokens), USER.md (user context ≤350), TOOLS.md (tool prefs ≤200), AGENTS.md (rules ≤800). Each file has a token budget because it loads every message.",
            });
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "structure/modular-files",
    category: "structure",
    severity: "info",
    description: "Using multiple focused files is better than one monolith",
    check(files) {
      const mdFiles = files.filter((f) => f.name.endsWith(".md"));
      if (mdFiles.length === 1 && mdFiles[0].lines.length > 100) {
        return [
          {
            severity: "info",
            category: "structure",
            rule: this.id,
            file: mdFiles[0].name,
            message:
              "Only 1 file found with 100+ lines. Consider splitting into modular files for better organization.",
            fix: "Create separate files: SOUL.md (personality), USER.md (user context), TOOLS.md (tool documentation)",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "structure/no-empty-sections",
    category: "structure",
    severity: "warning",
    description: "Core agent files should not have empty sections",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      // Only check core agent files, not compound/working docs
      const coreFiles = files.filter(
        (f) =>
          !f.name.startsWith("compound/") &&
          !f.name.startsWith("memory/") &&
          f.name.endsWith(".md")
      );
      for (const file of coreFiles) {
        // Skip intentionally inactive HEARTBEAT.md files (convention: comment-only = inactive)
        if (file.name === "HEARTBEAT.md" && /keep this file empty|skip heartbeat/i.test(file.content)) {
          continue;
        }
        for (let idx = 0; idx < file.sections.length; idx++) {
          const section = file.sections[idx];
          const bodyLines = section.content
            .split("\n")
            .slice(1)
            .filter((l) => l.trim().length > 0);
          // A section is truly empty only if it has no body AND no subsections follow immediately
          const nextSection = file.sections[idx + 1];
          const hasSubsection =
            nextSection && nextSection.level > section.level;
          if (bodyLines.length === 0 && !hasSubsection) {
            diagnostics.push({
              severity: "warning",
              category: "structure",
              rule: this.id,
              file: file.name,
              line: section.startLine + 1,
              message: `Empty section: "${section.heading}". Empty sections waste tokens and signal incomplete config — the model sees a heading with no content and has to guess what belongs there.`,
              fix: `Add content to "${section.heading}" or remove the heading entirely. If it's a placeholder for future content, use a TODO comment.`,
            });
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "structure/has-file-map",
    category: "structure",
    severity: "info",
    description: "A file map helps agents navigate the workspace",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (!mainFile) return [];

      const hasTreeChars = mainFile.content.includes("├") || mainFile.content.includes("└");
      const hasKeyword = /file.?map|directory|tree|layout|repo|structure/i.test(mainFile.content);

      // Bullet-based file listings: 3+ bullet lines referencing .md files or paths with /
      const bulletFileRefs = mainFile.lines.filter(
        (l) => /^\s*[-*]\s.*\.(md|txt|sh|ts|py|json|yaml|yml)\b/.test(l) ||
               /^\s*[-*]\s.*\//.test(l)
      );
      const hasBulletTree = bulletFileRefs.length >= 3;

      const hasFileMap =
        hasTreeChars ||
        (hasKeyword && mainFile.content.includes("```")) ||
        (hasKeyword && hasBulletTree);

      if (!hasFileMap && files.length > 5) {
        return [
          {
            severity: "info",
            category: "structure",
            rule: this.id,
            file: mainFile.name,
            message:
              `No file map found. With ${files.length} files, a directory tree helps the agent understand the workspace layout and know where to look for config, memory, and skills.`,
            fix: "Add a ## File Map section with tree structure (├── / └──) or bullet list showing all agent files and their purpose.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "structure/has-version-or-update-date",
    category: "structure",
    severity: "info",
    description: "Files should indicate when they were last updated",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const coreFiles = files.filter(
        (f) =>
          !f.name.startsWith("compound/") &&
          !f.name.startsWith("memory/") &&
          (f.name === "CLAUDE.md" || f.name === "AGENTS.md" || f.name === "TOOLS.md")
      );
      for (const file of coreFiles) {
        // Require explicit version/date patterns, not just the word "date"
        const hasDate =
          /(?:last\s+)?updated?\s*[:=]\s*\d{4}/i.test(file.content) ||
          /(?:last\s+)?modified\s*[:=]\s*\d{4}/i.test(file.content) ||
          /\bv\d+\.\d+/.test(file.content) ||
          /version\s*[:=]\s*[\d"']/i.test(file.content) ||
          /\d{4}-\d{2}-\d{2}/.test(file.content);
        if (!hasDate) {
          diagnostics.push({
            severity: "info",
            category: "structure",
            rule: this.id,
            file: file.name,
            message: "No version or update date found. Without timestamps, there's no way to tell if instructions are current or stale — especially important when multiple people or agents edit config files.",
            fix: "Add a version comment or 'Last updated: YYYY-MM-DD' at the top or bottom.",
          });
        }
      }
      return diagnostics;
    },
  },
];
