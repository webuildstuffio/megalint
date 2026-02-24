/* ─── Remote-Ready Score Rules (5%) ─── */
/* Checks if the workspace is ready for remote/headless agent execution */

import { Rule, Diagnostic } from "../types";

export const remoteReadyRules: Rule[] = [
  {
    id: "remote-ready/workspace-path-specified",
    category: "remoteReady",
    severity: "info",
    description: "Workspace path should be explicitly documented for remote execution",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (!mainFile) return [];

      const allContent = files
        .filter((f) => !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      // Check for explicit workspace path
      const hasWorkspacePath =
        /workspace.*[:=]\s*[`'"]?\/[^\s`'"]+/i.test(allContent) ||
        /repo.*[:=]\s*[`'"]?\/[^\s`'"]+/i.test(allContent) ||
        /working\s+dir(?:ectory)?.*[:=]\s*[`'"]?\/[^\s`'"]+/i.test(allContent) ||
        /cwd.*[:=]\s*[`'"]?\/[^\s`'"]+/i.test(allContent) ||
        /\bworkdir\b.*\/[^\s]+/i.test(allContent) ||
        // Common patterns: "repo=/Users/..." or "host=..." lines
        /(?:repo|workspace|workdir|cwd)\s*=\s*\/[^\s]+/i.test(allContent);

      if (!hasWorkspacePath) {
        return [
          {
            severity: "info",
            category: "remoteReady",
            rule: this.id,
            file: mainFile.name,
            message:
              "No explicit workspace path found. Remote/headless agents need a documented workspace path to locate files, execute commands from the right directory, and resolve relative paths correctly. Without it, shell commands and file operations fail silently at an incorrect working directory. Only applies to remote deployments — local agents can skip this.",
            fix: 'If deploying remotely, add workspace path in TOOLS.md or AGENTS.md. Example: "repo=/Users/username/project"',
          },
        ];
      }
      return [];
    },
  },

  {
    id: "remote-ready/env-vars-documented",
    category: "remoteReady",
    severity: "warning",
    description: "Required environment variables should be documented",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      const toolsFile = files.find((f) => f.name === "TOOLS.md");
      if (!mainFile && !toolsFile) return [];

      const allContent = files
        .filter((f) => !f.name.startsWith("memory/") && !f.name.startsWith("compound/"))
        .map((f) => f.content)
        .join("\n");

      // Check if environment variables are referenced but not documented
      const hasEnvVarUsage =
        /\$\{?[A-Z][A-Z0-9_]{2,}\}?/.test(allContent) || // ${VAR_NAME} or $VAR_NAME
        /process\.env\.[A-Z_]+/.test(allContent) ||
        /os\.environ/i.test(allContent);

      const hasEnvDocumentation =
        /env(?:ironment)?\s+var(?:iable)?s?/i.test(allContent) ||
        /required.*(?:env|environment)/i.test(allContent) ||
        /\.env\s+(?:file|setup|config)/i.test(allContent) ||
        /export\s+[A-Z_]+=/.test(allContent) ||
        /\bENV:\b/i.test(allContent);

      if (hasEnvVarUsage && !hasEnvDocumentation) {
        return [
          {
            severity: "warning",
            category: "remoteReady",
            rule: this.id,
            file: toolsFile?.name || mainFile?.name || "(workspace)",
            message:
              "Environment variables are referenced but not documented. When deploying on a new machine or handing off to another operator, undocumented env vars become silent failure points — the agent starts, finds no API key, and either crashes or silently falls back to no-auth mode. A documented env var list is the difference between a deployable system and a system that only runs on the original developer's machine.",
            fix: "Add an 'Environment Variables' section to TOOLS.md listing all required env vars, their purpose, and example values (redact actual secrets).",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "remote-ready/model-settings-specified",
    category: "remoteReady",
    severity: "info",
    description: "Model settings should be explicitly configured for reproducible remote execution",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      const toolsFile = files.find((f) => f.name === "TOOLS.md");
      if (!mainFile && !toolsFile) return [];

      const allContent = files
        .filter((f) => !f.name.startsWith("memory/") && !f.name.startsWith("compound/"))
        .map((f) => f.content)
        .join("\n");

      // Check for model specification
      const hasModelConfig =
        /default[_-]?model\s*[:=]/i.test(allContent) ||
        /model\s*[:=]\s*["']?(?:anthropic|openai|google|xai|gpt|claude|gemini|grok)/i.test(allContent) ||
        /\bmodel\s*=\s*[a-z]+\/[a-z-]+/i.test(allContent) ||
        /claude-(?:opus|sonnet|haiku)/i.test(allContent) ||
        /gpt-4/i.test(allContent) ||
        // Runtime section with model info
        /Runtime.*model=/i.test(allContent);

      if (!hasModelConfig) {
        return [
          {
            severity: "info",
            category: "remoteReady",
            rule: this.id,
            file: toolsFile?.name || mainFile?.name || "(workspace)",
            message:
              "No model settings found. Without a documented model, remote deployments inherit whatever default the runtime provides — which may change across versions, cost significantly more, or produce different behavior. Pinning the model gives reproducible outputs and prevents surprise cost increases when provider defaults change.",
            fix: "Document the default model in TOOLS.md. Example: 'default_model: anthropic/claude-opus-4-5'",
          },
        ];
      }
      return [];
    },
  },
];
