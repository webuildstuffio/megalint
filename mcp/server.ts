#!/usr/bin/env bun
/**
 * megalint MCP server — exposes megalint tools to AI agents via stdio.
 *
 * Install in ~/.cursor/mcp.json or claude_desktop_config.json:
 *   {
 *     "megalint": {
 *       "command": "bun",
 *       "args": ["run", "/path/to/megalint/mcp/server.ts"]
 *     }
 *   }
 *
 * Tools:
 *   megalint_lint     — Run megalint on a path
 *   megalint_rules    — List all rules
 *   megalint_report   — Get a specific or latest report
 *   megalint_trends   — Score trends across reports
 *   megalint_config   — Current scoring configuration
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawn } from "node:child_process";
import { readdir, readFile, stat } from "node:fs/promises";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..");
const MEGALINT = join(ROOT, "megalint.sh");
const REPORTS_DIR = join(ROOT, ".reports");

// ── Rules registry ──────────────────────────────────────────────────────────

const RULES = [
  { id: "skill/file-exists", severity: "ERROR", description: "SKILL.md must exist in each skill directory", mode: "skills" },
  { id: "skill/description", severity: "WARN", description: "SKILL.md has a clear description/purpose statement", mode: "skills" },
  { id: "skill/when-to-use", severity: "WARN", description: "When-to-use / trigger guidance for agents", mode: "skills" },
  { id: "skill/structure", severity: "WARN", description: "Structured headings (≥2 sections)", mode: "skills" },
  { id: "skill/dangerous-commands", severity: "ERROR", description: "No rm -rf /, sudo rm, curl|sh, etc.", mode: "skills" },
  { id: "skill/actionable", severity: "WARN", description: "Steps, bullets, or code examples present", mode: "skills" },
  { id: "skill/injection", severity: "WARN", description: "No prompt injection patterns", mode: "skills" },
  { id: "skill/file-count", severity: "INFO", description: "Reasonable number of files per skill (≤5)", mode: "skills" },
  { id: "skill/scope-boundaries", severity: "INFO", description: "Defines what the skill should NOT do", mode: "skills" },
  { id: "skill/examples", severity: "INFO", description: "Concrete examples or code blocks present", mode: "skills" },
  { id: "skill/output-format", severity: "INFO", description: "Output format specification", mode: "skills" },
  { id: "skill/error-handling", severity: "INFO", description: "Error recovery / fallback instructions", mode: "skills" },
  { id: "skill/secrets", severity: "ERROR", description: "No hardcoded secrets, API keys, or PII", mode: "skills" },
  { id: "skill/restrictions", severity: "INFO", description: "Safety restrictions present (NEVER/MUST NOT)", mode: "skills" },
  { id: "skill/tool-boundaries", severity: "INFO", description: "Tool use boundaries (prefer X over Y)", mode: "skills" },
  { id: "skill/idempotent", severity: "WARN", description: "Destructive ops have safeguards (confirm/dry-run/backup)", mode: "skills" },
  { id: "prompt/identity", severity: "INFO", description: "Prompt has role/identity definition", mode: "prompts" },
  { id: "prompt/output-format", severity: "INFO", description: "Output format guidance present", mode: "prompts" },
  { id: "prompt/dangerous-commands", severity: "ERROR", description: "No rm -rf /, sudo rm, curl|sh, etc.", mode: "prompts" },
  { id: "prompt/injection", severity: "WARN", description: "No prompt injection patterns", mode: "prompts" },
  { id: "prompt/scope", severity: "INFO", description: "Scope / task boundaries defined", mode: "prompts" },
  { id: "prompt/examples", severity: "INFO", description: "Concrete examples present", mode: "prompts" },
  { id: "prompt/constraints", severity: "INFO", description: "Emphatic constraints (NEVER/MUST NOT markers)", mode: "prompts" },
];

// ── Helpers ──────────────────────────────────────────────────────────────────

function runMegalint(args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [MEGALINT, ...args], {
      cwd: ROOT,
      env: { ...process.env, TERM: "dumb" },
      timeout: 120_000,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d: Buffer) => (stdout += d.toString()));
    child.stderr.on("data", (d: Buffer) => (stderr += d.toString()));
    child.on("close", (code) => resolve({ stdout, stderr, code }));
    child.on("error", (e) => resolve({ stdout: "", stderr: e.message, code: 1 }));
  });
}

async function listReportFiles(): Promise<string[]> {
  try {
    const files = await readdir(REPORTS_DIR);
    return files.filter((f) => f.endsWith(".json")).sort().reverse();
  } catch {
    return [];
  }
}

async function readReportFile(id: string): Promise<object | null> {
  for (const name of [`${id}.json`, `report_${id}.json`]) {
    try {
      const raw = await readFile(join(REPORTS_DIR, name), "utf-8");
      return JSON.parse(raw);
    } catch { /* try next */ }
  }
  return null;
}

async function loadConfig(): Promise<Record<string, string | number>> {
  try {
    const raw = await readFile(join(ROOT, "megalint.conf"), "utf-8");
    const conf: Record<string, string | number> = {};
    for (const line of raw.split("\n")) {
      const m = line.match(/^(\w+)=(\S+)/);
      if (m) {
        const val = m[2].replace(/#.*$/, "").trim();
        conf[m[1]] = isNaN(Number(val)) ? val : Number(val);
      }
    }
    return conf;
  } catch {
    return {};
  }
}

// ── MCP Server ──────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "megalint",
  version: "1.0.0",
});

server.tool(
  "megalint_lint",
  "Run megalint on a path. Returns scored JSON results with convention checks, pillar scores, and grade.",
  {
    path: z.string().describe("Absolute path to a skill directory, prompt file, or parent directory to lint"),
    mode: z.enum(["auto", "skills", "prompts", "agents"]).optional().describe("Lint mode (default: auto-detect)"),
    preset: z.enum(["strict", "balanced", "minimal"]).optional().describe("Rule preset"),
    disable_rules: z.string().optional().describe("Comma-separated rule IDs to disable"),
    quiet: z.boolean().optional().describe("Suppress OK/INFO output"),
  },
  async ({ path, mode, preset, disable_rules, quiet }) => {
    const args = ["--json"];
    if (mode && mode !== "auto") args.push("--mode", mode);
    if (preset) args.push("--preset", preset);
    if (disable_rules) args.push("--disable-rule", disable_rules);
    if (quiet) args.push("--quiet");
    args.push(path);

    const { stdout, stderr, code } = await runMegalint(args);

    try {
      const result = JSON.parse(stdout);
      const scoring = result.scoring || result;
      const meta = result.meta || result;
      const summary = [
        `Score: ${Math.round(scoring.combined ?? result.combined ?? 0)} (${scoring.grade ?? result.grade ?? '?'})`,
        `Passed: ${scoring.passed ?? result.passed ?? false}`,
        `Mode: ${meta.mode ?? '?'}`,
        `Items: ${(meta.agents_list || []).length}`,
      ].join("\n");

      return {
        content: [
          { type: "text" as const, text: summary },
          { type: "text" as const, text: "```json\n" + JSON.stringify(result, null, 2) + "\n```" },
        ],
      };
    } catch {
      return {
        content: [{ type: "text" as const, text: `megalint exited ${code}\n\nstdout:\n${stdout.slice(0, 3000)}\n\nstderr:\n${stderr.slice(0, 1000)}` }],
        isError: true,
      };
    }
  }
);

server.tool(
  "megalint_rules",
  "List all megalint rules with severity, mode, and description. Optionally filter by mode or severity.",
  {
    mode: z.enum(["skills", "prompts"]).optional().describe("Filter by mode"),
    severity: z.enum(["ERROR", "WARN", "INFO"]).optional().describe("Filter by severity"),
  },
  async ({ mode, severity }) => {
    let filtered = RULES;
    if (mode) filtered = filtered.filter((r) => r.mode === mode);
    if (severity) filtered = filtered.filter((r) => r.severity === severity);

    const table = filtered
      .map((r) => `${r.id.padEnd(28)} ${r.severity.padEnd(6)} ${r.mode.padEnd(8)} ${r.description}`)
      .join("\n");

    return {
      content: [{
        type: "text" as const,
        text: `${filtered.length} rules:\n\n${table}\n\nCitation: arxiv 2609.31575 + Claude Code skill architecture`,
      }],
    };
  }
);

server.tool(
  "megalint_report",
  "Get a specific megalint report by ID, or the latest report.",
  {
    id: z.string().optional().describe("Report ID (filename without .json). Omit for latest."),
  },
  async ({ id }) => {
    let report: object | null;
    if (id) {
      report = await readReportFile(id);
    } else {
      const files = await listReportFiles();
      if (files.length === 0) {
        return { content: [{ type: "text" as const, text: "No reports found in .reports/ — run megalint with --format json to generate reports." }] };
      }
      const raw = await readFile(join(REPORTS_DIR, files[0]), "utf-8");
      report = JSON.parse(raw);
    }

    if (!report) {
      return { content: [{ type: "text" as const, text: `Report not found: ${id}` }], isError: true };
    }

    return {
      content: [{ type: "text" as const, text: "```json\n" + JSON.stringify(report, null, 2) + "\n```" }],
    };
  }
);

server.tool(
  "megalint_trends",
  "Get score trends across recent megalint reports. Shows combined score, grade, and pass/fail over time.",
  {
    limit: z.number().optional().describe("Max reports to include (default: 20)"),
  },
  async ({ limit }) => {
    const files = await listReportFiles();
    const max = limit || 20;
    const trends: object[] = [];

    for (const f of files.slice(0, max)) {
      try {
        const raw = await readFile(join(REPORTS_DIR, f), "utf-8");
        const d = JSON.parse(raw);
        const meta = d.meta || d;
        const scoring = d.scoring || d;
        trends.push({
          id: f.replace(".json", ""),
          timestamp: meta.timestamp,
          combined: scoring.combined ?? d.combined,
          grade: scoring.grade ?? d.grade,
          passed: scoring.passed ?? d.passed,
          git_commit: (meta.git_commit || "").slice(0, 7),
          git_branch: meta.git_branch || "",
        });
      } catch { /* skip */ }
    }

    if (trends.length === 0) {
      return { content: [{ type: "text" as const, text: "No trend data — run megalint with --format json" }] };
    }

    const table = (trends as any[])
      .map((t) => `${t.id.slice(0, 30).padEnd(32)} ${String(Math.round(t.combined ?? 0)).padStart(3)} ${(t.grade ?? '?').padEnd(3)} ${t.passed ? '✓' : '✗'} ${t.git_commit}`)
      .join("\n");

    return {
      content: [{ type: "text" as const, text: `${trends.length} reports:\n\n${"Report".padEnd(32)} Scr Grd P? Commit\n${"─".repeat(60)}\n${table}` }],
    };
  }
);

server.tool(
  "megalint_config",
  "Get current megalint scoring configuration: pillar weights, thresholds, and grade scale.",
  {},
  async () => {
    const conf = await loadConfig();
    return {
      content: [{ type: "text" as const, text: "```json\n" + JSON.stringify(conf, null, 2) + "\n```" }],
    };
  }
);

// ── Start ───────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
