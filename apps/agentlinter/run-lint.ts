import { scanWorkspace, lint, formatTerminal, formatJSON } from "./src/engine";

const workspace = "/Users/gimseojun/clawd";
console.log(`Scanning: ${workspace}\n`);

const files = scanWorkspace(workspace);
const result = lint(workspace, files);

console.log(formatTerminal(result));
console.log("\n--- JSON ---\n");
console.log(formatJSON(result));
