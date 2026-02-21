import crypto from "node:crypto";
import os from "node:os";
import { LintResult, CATEGORY_LABELS } from "./engine/types";

const API_URL = "https://agentlinter.com/api/reports";

export async function uploadReport(result: LintResult): Promise<{ id: string; url: string }> {
  const machineId = getMachineId();

  const payload = {
    machineId,
    score: result.totalScore,
    categories: result.categories.map((c) => ({
      name: CATEGORY_LABELS[c.category],
      score: c.score,
      weight: c.weight,
    })),
    diagnostics: result.diagnostics.map((d) => ({
      severity: d.severity,
      category: d.category,
      rule: d.rule,
      file: d.file,
      line: d.line,
      message: d.message,
      fix: d.fix,
    })),
    fileNames: result.files.map((f) => f.name),
    rulesChecked: new Set(result.diagnostics.map((d) => d.rule)).size || 46,
  };

  const response = await fetch(API_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Upload failed (${response.status}): ${errorText}`);
  }

  const data = await response.json();
  return {
    id: data.id,
    url: data.url || `https://agentlinter.com/r/${data.id}`,
  };
}

function getMachineId(): string {
  try {
    const hostname = os.hostname();
    const username = os.userInfo().username;
    return crypto.createHash("sha256").update(`${hostname}-${username}`).digest("hex").slice(0, 32);
  } catch {
    return crypto.createHash("sha256").update(os.hostname()).digest("hex").slice(0, 32);
  }
}
