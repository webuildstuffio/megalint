#!/usr/bin/env bun
/**
 * megalint web dashboard — bun serve
 *
 * Usage:  bun run web/server.ts [--port 3000] [--reports-dir .reports]
 *         megalint.sh --serve            (shorthand)
 *
 * API:
 *   GET /                       → dashboard SPA
 *   GET /api/rules              → all rules with metadata
 *   GET /api/reports            → list of report files (newest first)
 *   GET /api/reports/:id        → single report JSON
 *   GET /api/latest             → most recent report
 *   GET /api/trends             → score trends across reports
 *   POST /api/lint              → run megalint on a path (body: { path, mode?, preset? })
 */

import { readdir, readFile, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";

const ROOT = resolve(import.meta.dir, "..");
const args = process.argv.slice(2);

function flag(name: string, fallback: string): string {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
}

const PORT = parseInt(flag("--port", process.env.MEGALINT_PORT || "7777"), 10);
const REPORTS_DIR = resolve(flag("--reports-dir", join(ROOT, ".reports")));
const MEGALINT = join(ROOT, "megalint.sh");

// ── Rules registry ──────────────────────────────────────────────────────────

interface Rule {
  id: string;
  severity: "ERROR" | "WARN" | "INFO";
  description: string;
  mode: "skills" | "prompts" | "agents";
  citation?: string;
}

const RULES: Rule[] = [
  // skill rules
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
  // prompt rules
  { id: "prompt/identity", severity: "INFO", description: "Prompt has role/identity definition", mode: "prompts" },
  { id: "prompt/output-format", severity: "INFO", description: "Output format guidance present", mode: "prompts" },
  { id: "prompt/dangerous-commands", severity: "ERROR", description: "No rm -rf /, sudo rm, curl|sh, etc.", mode: "prompts" },
  { id: "prompt/injection", severity: "WARN", description: "No prompt injection patterns", mode: "prompts" },
  { id: "prompt/scope", severity: "INFO", description: "Scope / task boundaries defined", mode: "prompts" },
  { id: "prompt/examples", severity: "INFO", description: "Concrete examples present", mode: "prompts" },
  { id: "prompt/constraints", severity: "INFO", description: "Emphatic constraints (NEVER/MUST NOT markers)", mode: "prompts" },
];

// ── API helpers ─────────────────────────────────────────────────────────────

async function listReports(): Promise<{ id: string; ts: string; path: string }[]> {
  try {
    const files = await readdir(REPORTS_DIR);
    const jsonFiles = files.filter((f) => f.endsWith(".json")).sort().reverse();
    return Promise.all(
      jsonFiles.map(async (f) => {
        const p = join(REPORTS_DIR, f);
        const s = await stat(p);
        return { id: f.replace(".json", ""), ts: s.mtime.toISOString(), path: p };
      })
    );
  } catch {
    return [];
  }
}

async function readReport(id: string): Promise<object | null> {
  try {
    const raw = await readFile(join(REPORTS_DIR, `${id}.json`), "utf-8");
    return JSON.parse(raw);
  } catch {
    // try report_ prefix
    try {
      const raw = await readFile(join(REPORTS_DIR, `report_${id}.json`), "utf-8");
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }
}

async function latestReport(): Promise<object | null> {
  const reports = await listReports();
  if (reports.length === 0) return null;
  const raw = await readFile(reports[0].path, "utf-8");
  return JSON.parse(raw);
}

async function buildTrends(): Promise<object[]> {
  const reports = await listReports();
  const trends: object[] = [];
  for (const r of reports.slice(0, 50)) {
    try {
      const raw = await readFile(r.path, "utf-8");
      const d = JSON.parse(raw);
      const meta = d.meta || d;
      const scoring = d.scoring || d;
      trends.push({
        id: r.id,
        ts: meta.timestamp || r.ts,
        combined: scoring.combined ?? d.combined ?? null,
        grade: scoring.grade ?? d.grade ?? null,
        passed: scoring.passed ?? d.passed ?? null,
        pillar_structure: scoring.pillar_structure ?? d.pillar_structure ?? null,
        pillar_quality: scoring.pillar_quality ?? d.pillar_quality ?? null,
        pillar_consistency: scoring.pillar_consistency ?? d.pillar_consistency ?? null,
        pillar_security: scoring.pillar_security ?? d.pillar_security ?? null,
        pillar_budget: scoring.pillar_budget ?? d.pillar_budget ?? null,
        git_commit: meta.git_commit ?? d.git_commit ?? "",
        git_branch: meta.git_branch ?? d.git_branch ?? "",
      });
    } catch { /* skip corrupt */ }
  }
  return trends;
}

function runLint(path: string, mode?: string, preset?: string): Promise<object> {
  return new Promise((resolve, reject) => {
    const args = ["--json"];
    if (mode) args.push("--mode", mode);
    if (preset) args.push("--preset", preset);
    args.push(path);

    const child = spawn("bash", [MEGALINT, ...args], {
      cwd: ROOT,
      env: { ...process.env, TERM: "dumb" },
      timeout: 120_000,
    });

    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d: Buffer) => (stdout += d.toString()));
    child.stderr.on("data", (d: Buffer) => (stderr += d.toString()));
    child.on("close", (code: number | null) => {
      try {
        resolve(JSON.parse(stdout));
      } catch {
        resolve({ error: true, code, stdout: stdout.slice(0, 2000), stderr: stderr.slice(0, 2000) });
      }
    });
    child.on("error", (e: Error) => reject(e));
  });
}

// ── HTML dashboard ──────────────────────────────────────────────────────────

const dashboardHtml = await readFile(join(import.meta.dir, "dashboard.html"), "utf-8");

// ── Server ──────────────────────────────────────────────────────────────────

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });

Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    if (path === "/" || path === "/index.html") {
      return new Response(dashboardHtml, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    if (path === "/api/rules") return json(RULES);

    if (path === "/api/reports") {
      return json(await listReports());
    }

    if (path === "/api/latest") {
      const report = await latestReport();
      return report ? json(report) : json({ error: "No reports found" }, 404);
    }

    if (path === "/api/trends") {
      return json(await buildTrends());
    }

    if (path.startsWith("/api/reports/")) {
      const id = path.replace("/api/reports/", "");
      const report = await readReport(id);
      return report ? json(report) : json({ error: "Not found" }, 404);
    }

    if (path === "/api/lint" && req.method === "POST") {
      try {
        const body = (await req.json()) as { path: string; mode?: string; preset?: string };
        if (!body.path) return json({ error: "path required" }, 400);
        const result = await runLint(body.path, body.mode, body.preset);
        return json(result);
      } catch (e: any) {
        return json({ error: e.message }, 500);
      }
    }

    if (path === "/api/config") {
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
        return json(conf);
      } catch {
        return json({});
      }
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`\n  ⚡ megalint dashboard → http://localhost:${PORT}\n`);
console.log(`  Reports dir: ${REPORTS_DIR}`);
console.log(`  API: /api/rules · /api/reports · /api/latest · /api/trends · /api/lint\n`);
