import { scanWorkspace, lint, formatJSON } from "./src/engine";

async function main() {
  const files = scanWorkspace("/Users/gimseojun/clawd");
  const result = lint("/Users/gimseojun/clawd", files);
  const json = JSON.parse(formatJSON(result));

  const payload = {
    machineId: "zeon-mac-mini-001",
    score: json.score,
    categories: json.categories.map((c: any) => ({ name: c.name, score: c.score, weight: c.weight })),
    diagnostics: json.diagnostics,
    fileNames: json.files,
    rulesChecked: 46,
  };

  const res = await fetch("https://agentlinter.com/api/reports", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await res.json();
  console.log(JSON.stringify(data, null, 2));
}

main();
