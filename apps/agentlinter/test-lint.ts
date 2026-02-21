#!/usr/bin/env npx ts-node
/* ─── Quick test: lint a workspace ─── */

import { scanWorkspace, lint, formatTerminal, formatJSON } from "./src/engine";

const workspace = process.argv[2] || "/Users/gimseojun/clawd";

console.log(`\nScanning workspace: ${workspace}\n`);

const files = scanWorkspace(workspace);
console.log(`Found ${files.length} files: ${files.map((f) => f.name).join(", ")}\n`);

const result = lint(workspace, files);

// Terminal output
console.log(formatTerminal(result));

// Also save JSON
const fs = require("fs");
fs.writeFileSync("lint-result.json", formatJSON(result));
console.log("📄 Full JSON result saved to lint-result.json");
