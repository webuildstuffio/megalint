/* ─── Clarity Rules (25%) ─── */

import { Rule, Diagnostic } from "../types";

const VAGUE_PATTERNS = [
  { pattern: /\bbe helpful\b/i, suggestion: "Specify HOW to be helpful (e.g., 'provide code examples', 'explain step by step')" },
  { pattern: /\bbe nice\b/i, suggestion: "Define the specific tone (e.g., 'use casual but professional tone')" },
  { pattern: /\bbe smart\b/i, suggestion: "Specify what 'smart' means in context (e.g., 'prioritize accuracy over speed')" },
  { pattern: /\bbe concise\b/i, suggestion: "Set specific limits (e.g., 'keep responses under 3 paragraphs unless asked for more')" },
  { pattern: /\bdo your best\b/i, suggestion: "Define what success looks like specifically" },
  { pattern: /\btry to\b/i, suggestion: "Use direct instructions instead of 'try to' (e.g., 'do X' not 'try to do X')" },
  { pattern: /\bif possible\b/i, suggestion: "Specify the conditions or constraints explicitly" },
  { pattern: /\bas needed\b/i, suggestion: "Define when it's needed with specific triggers" },
  { pattern: /\bwhen appropriate\b/i, suggestion: "Define what 'appropriate' means in your context" },
  { pattern: /\buse common sense\b/i, suggestion: "AI doesn't have 'common sense' — spell out the specific rules" },
  { pattern: /\buse good judgment\b/i, suggestion: "Define the criteria for judgment (e.g., 'prefer X over Y when Z')" },
  { pattern: /\betc\.?\b/i, suggestion: "List all items explicitly — 'etc' leaves AI guessing" },
  { pattern: /\band so on\b/i, suggestion: "Be exhaustive — list all relevant items" },
  { pattern: /\bthings like\b/i, suggestion: "List specific items instead of 'things like'" },
];

const PASSIVE_PATTERNS = [
  { pattern: /\bshould be done\b/i, suggestion: "Use active voice: 'Do X' instead of 'X should be done'" },
  { pattern: /\bit is expected\b/i, suggestion: "Use direct instructions: 'Always do X' instead of 'it is expected'" },
  { pattern: /\bcan be used\b/i, suggestion: "Be direct: 'Use X for Y' instead of 'X can be used'" },
  { pattern: /\bneeds to be\b/i, suggestion: "Use imperative: 'Must be X' instead of 'needs to be X'" },
  { pattern: /\bis to be\b/i, suggestion: "Use imperative: 'Do X' instead of 'X is to be done'" },
  { pattern: /\bmight be\b/i, suggestion: "Use definitive: 'Is X' or 'Use X' instead of 'might be X'" },
  { pattern: /\bit is recommended\b/i, suggestion: "Use direct instruction: 'Do X' instead of 'it is recommended to do X'" },
  { pattern: /\bis responsible for\b/i, suggestion: "Use active: 'Handle X' or 'Owns X' instead of 'is responsible for X'" },
  { pattern: /\bit helps to\b/i, suggestion: "Use imperative: 'Do X to achieve Y' instead of 'it helps to do X'" },
  { pattern: /\bwould be\b/i, suggestion: "Use declarative: 'X is Y' or 'Do X' instead of 'would be'" },
];

export const clarityRules: Rule[] = [
  {
    id: "clarity/no-vague-instructions",
    category: "clarity",
    severity: "warning",
    description: "Instructions should be specific and actionable, not vague",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      // Only check core agent files for vague instructions
      const coreFiles = files.filter(
        (f) =>
          !f.name.startsWith("compound/") &&
          !f.name.startsWith("memory/") &&
          f.name.endsWith(".md")
      );
      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const { pattern, suggestion } of VAGUE_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "warning",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Vague instruction: "${line.trim().substring(0, 80)}...". Vague phrases delegate decisions to the model without criteria — it will interpret them inconsistently. Every well-crafted industry prompt uses concrete thresholds instead.`,
                fix: suggestion,
              });
              break; // one diagnostic per line
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/actionable-instructions",
    category: "clarity",
    severity: "info",
    description: "Prefer active voice and direct instructions",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      for (const file of files) {
        if (!file.name.endsWith(".md")) continue;
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const { pattern, suggestion } of PASSIVE_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "info",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Passive instruction: "${line.trim().substring(0, 80)}". Passive voice ("should be done") weakens instruction compliance — models follow direct imperatives ("Do X") more reliably than indirect descriptions.`,
                fix: suggestion,
              });
              break;
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/has-examples",
    category: "clarity",
    severity: "info",
    description: "Including examples helps the agent understand expected behavior",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (!mainFile) return [];

      const hasExampleSection = mainFile.sections.some((s) =>
        /example/i.test(s.heading)
      );
      // Explicit example markers only — "for instance" and arrows appear in normal prose/diagrams
      const hasExampleMarker =
        /\bexample\s*:/i.test(mainFile.content) ||
        /\be\.g\.[,\s]/i.test(mainFile.content) ||
        /\bgood[:\s]+["'`]/i.test(mainFile.content) ||
        /\bbad[:\s]+["'`]/i.test(mainFile.content) ||
        /\b(e\.?g\.?|i\.?e\.?|for example)[:\s]/i.test(mainFile.content);

      if (!hasExampleSection && !hasExampleMarker && mainFile.lines.length > 30) {
        return [
          {
            severity: "info",
            category: "clarity",
            rule: this.id,
            file: mainFile.name,
            message:
              "No behavioral examples found. Code blocks alone don't count — examples of desired behavior (input→output, good vs bad responses) dramatically improve instruction compliance. Models pattern-match against concrete examples more reliably than abstract rules.",
            fix: "Add a ## Examples section or include inline examples with explicit markers like 'Example:' before code blocks.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "clarity/no-contradictions",
    category: "clarity",
    severity: "error",
    description: "Instructions within a file should not contradict each other",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const STOP_WORDS = new Set(["the", "a", "an", "be", "to", "for", "of", "in", "and", "or", "with", "your", "you", "it", "is", "are", "was", "at", "by", "as", "on", "this", "that", "all", "any", "from", "if", "but", "when", "then", "just", "use", "do"]);
      const NEGATION_WORDS = new Set(["avoid", "skip", "ignore", "stop", "prevent", "without", "no", "not", "never", "don't", "dont", "refrain", "prohibit", "forbid"]);

      function extractKeywords(text: string): string[] {
        return text.toLowerCase().split(/\s+/).filter(w => w.length > 2 && !STOP_WORDS.has(w) && /^[a-z]+$/.test(w));
      }

      function startsWithNegation(text: string): boolean {
        const firstWord = text.trim().toLowerCase().split(/\s+/)[0];
        return NEGATION_WORDS.has(firstWord);
      }

      function keywordOverlap(a: string, b: string): number {
        const aWords = new Set(extractKeywords(a));
        const bWords = new Set(extractKeywords(b));
        let count = 0;
        for (const w of aWords) if (bWords.has(w)) count++;
        return count;
      }

      for (const file of files) {
        if (!file.name.endsWith(".md")) continue;

        const alwaysMatches: { text: string; line: number }[] = [];
        const neverMatches: { text: string; line: number }[] = [];
        let inCodeBlock = false;

        for (let i = 0; i < file.lines.length; i++) {
          const raw = file.lines[i];
          if (raw.trim().startsWith("```")) { inCodeBlock = !inCodeBlock; continue; }
          if (inCodeBlock) continue;
          const line = raw.toLowerCase();
            // Capture up to 14 words — wide enough for most phrases, stops at punctuation
          const alwaysMatch = line.match(/\balways\s+(\w+(?:\s+\w+){0,13})(?=[.!?;,]|$)/);
          const neverMatch = line.match(/\bnever\s+(\w+(?:\s+\w+){0,13})(?=[.!?;,]|$)/);
          if (alwaysMatch) alwaysMatches.push({ text: alwaysMatch[1].trim(), line: i + 1 });
          if (neverMatch) neverMatches.push({ text: neverMatch[1].trim(), line: i + 1 });
        }

        for (const a of alwaysMatches) {
          for (const n of neverMatches) {
            const directMatch = a.text === n.text;
            const overlap = keywordOverlap(a.text, n.text);
            const aNegated = startsWithNegation(a.text);
            const nNegated = startsWithNegation(n.text);

            // Skip when exactly one side is negated — "always avoid X" agrees with "never X"
            if ((directMatch || overlap >= 2) && aNegated === nNegated && a.line !== n.line) {
              diagnostics.push({
                severity: "error",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: n.line,
                message: `Contradiction: "always ${a.text}" (line ${a.line}) vs "never ${n.text}" (line ${n.line}). Contradictory config makes agent behavior unpredictable — the model picks whichever instruction its attention weights higher, essentially a coin flip.`,
                fix: 'Resolve the contradiction. Usually one instruction is wrong or needs scoping. "Always be concise" + "Never be concise in reports" → rewrite as "Default to concise. In research reports, be thorough."',
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/instruction-density",
    category: "clarity",
    severity: "info",
    description: "Files with too many instructions may cause confusion",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (!mainFile) return [];

      // Count imperative sentences
      const imperatives = mainFile.lines.filter((l) =>
        /^[-*]\s*(Always|Never|Do|Don't|Must|Should|Ensure|Make sure|Remember|Check|Prefer|Avoid|Use|Include|Keep|Follow|Run|Read|Write|Set|Add|Remove|Configure|Skip|Stop|Verify|Maintain|Limit|Respond|Output)/i.test(
          l.trim()
        )
      ).length;

      if (imperatives > 30) {
        return [
          {
            severity: "info",
            category: "clarity",
            rule: this.id,
            file: mainFile.name,
            message: `${imperatives} imperative instructions detected. Past ~30 instructions, models start dropping rules — attention mechanisms can't weight everything equally. The most important rules get the same priority as trivial ones.`,
            fix: "Group by priority: action tiers (Always/Never first), then move workflows to skills/ files. If it's a process not a rule, it doesn't belong in AGENTS.md.",
          },
        ];
      }
      return [];
    },
  },

  // ─── New rules from 4-LLM research (2026-02-05) ───

  {
    id: "clarity/naked-conditional",
    category: "clarity",
    severity: "error",
    description: "Conditionals should have specific, measurable triggers",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const VAGUE_CONDITIONALS = [
        /\bif\b.+\b(too many|too few|too long|too short|too much|too little|enough|large|small|a lot)\b/i,
        // Require vague word to immediately follow "when" — avoids FP on "context needed", "info needed" as adjectives
        /\bwhen\s+(appropriate|necessary|needed|possible|feasible)\b/i,
        /\bunless\b.+\b(necessary|needed)\b/i,
        /\bif\b.+\b(something goes wrong|things? (?:go|get) (?:wrong|bad))\b/i,
      ];
      // Lines with explicit qualifiers are clear, not vague
      const CLEAR_TRIGGERS = /\b(explicitly|specifically|by name|in writing|with approval)\b/i;
      // Context/narrative/personality files contain descriptions, not conditional instructions
      const SKIP_FILES = ["USER.md", "IDENTITY.md", "BOOTSTRAP.md", "MEMORY.md"];
      // Description/vibe patterns — personality traits aren't conditional instructions
      const DESCRIPTION_PATTERN = /\b(locus\s+of\s+control|personality|vibe|mindset|trait|character|temperament|disposition|nature)\b/i;
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md") && !SKIP_FILES.includes(f.name)
      );
      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (line.trim().startsWith("//") || line.trim().startsWith("```")) continue;
          if (CLEAR_TRIGGERS.test(line)) continue;
          if (DESCRIPTION_PATTERN.test(line)) continue;
          for (const pattern of VAGUE_CONDITIONALS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "error",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Naked conditional: "${line.trim().substring(0, 80)}". Conditionals without concrete criteria ("when appropriate", "if too many") are the #1 source of unpredictable behavior. The model decides inconsistently every time.`,
                fix: 'Replace with concrete threshold or trigger. "If too long" → "If > 2000 chars". "When appropriate" → "When the user explicitly asks". Ask yourself: when EXACTLY should this trigger?',
              });
              break;
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/compound-instruction",
    category: "clarity",
    severity: "warning",
    description: "Each bullet point should contain one action, not multiple",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );
      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i].trim();
          if (!line.startsWith("-") && !line.startsWith("*")) continue;
          const body = line.replace(/^[-*]\s*/, "");
          // Count imperative verbs (simple heuristic)
          const verbs = body.match(/\b(read|write|check|send|create|delete|update|run|deploy|notify|log|scan|fix|add|remove|validate|verify|ensure|process|handle|parse|open|close|start|stop|build|push|pull|test|review|approve|reject)\b/gi);
          if (verbs && (verbs.length >= 4 || (verbs.length >= 3 && body.length > 100))) {
            diagnostics.push({
              severity: "warning",
              category: "clarity",
              rule: this.id,
              file: file.name,
              line: i + 1,
              message: `Compound instruction with ${verbs.length} actions in one bullet — the model will complete some and drop others inconsistently. Every well-structured prompt uses one instruction per bullet/step.`,
              fix: "Split into separate steps. One clear action per bullet. If order matters, number them.",
            });
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/escape-hatch-missing",
    category: "clarity",
    severity: "warning",
    description: "Absolute rules should have an exception/escalation path",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const ABSOLUTE_PATTERNS = /\b(never|always|must|under no circumstances|absolutely|without exception)\b/i;
      const ESCAPE_PATTERNS = /\b(unless|except|in emergency|escalate|ask the user|if unavoidable|override|exception)\b/i;
      const SECURITY_TERMS = /\b(api.?key|tokens?|secrets?|passwords?|credentials?|private.?key|leaks?|expos|file.?paths?\b.*\bexternal)/i;
      // Safety/ethical boundaries that should stay absolute
      const SAFETY_TERMS = /\b(diagnos|therap|medical|prescri|emotion|sacred|confidential|privacy|personal.?shar|dismiss|preachy|hostile|harm|abuse|manipulat|discriminat|illegal|pushy)\b/i;
      // Data privacy — health data, lab results, financial data, PII boundaries should be absolute
      const DATA_PRIVACY = /\b(health\s+(data|metric)|sensitive\s+data|deeply\s+sensitive|private\s+(data|health)|lab\s+result|medication\s+info|group\s+(chat|context)|exfiltrat|shared\s+(or\s+group\s+)?context|raw\s+(health\s+)?data|financial\s+(data|detail|info)|account\s+info|salary\s+data|tax\s+data)\b/i;
      // Operational best practices that are legitimately absolute
      const OPS_TERMS = /\b(screenshots?|snapshots?|timeouts?|backups?|encrypt|sanitiz|validat|authenticat)\b/i;
      // Code execution / git safety — hard boundaries that should stay absolute
      const CODE_SAFETY = /\b(push.to.main|push.to.*(protected|default)|force.?push|rebase.shared|control.?plane|curl\s*\|?\s*bash|pipe.to.bash|destructi|bypass|branch.protect|disclose|cron|gateway|default.?branch|untrusted|merge(?!.*\brequest)|handoff|worktree)\b/i;
      // Tool prohibition rules — "never use X" for specific tools is a clear boundary
      const TOOL_BAN = /\bnever\b.*\b(npm|yarn|rm\b|sudo)\b/i;
      // Action tier table rows — absolute by design
      const TIER_TABLE = /^\|\s*\*\*(Always|Never|Auto-?execute|Notify after|Ask first)\*\*/i;
      // Immigration/accuracy — verification and source-accuracy rules should be absolute
      const ACCURACY_TERMS = /\b(visa|immigra|passport|verif|official\s+source|authoritat|outdated|conflicting?\s+(source|rule|info)|triple.?verif|source.?conflict|unofficial)\b/i;
      // Research agent deny-list patterns — hardened agents need absolute deny rules
      const RESEARCH_DENY = /\b(retrieved\s+content|follow\s+instructions\s+(found|embedded)|system\s+config|surface\s+to\s+(the\s+)?human|run\s+(code|shell)|execute\s+(code|command)|directly\s+interact)\b/i;
      // Platform constraints / architectural facts — not behavioral rules
      const PLATFORM_CONSTRAINT = /\b(only\s+loads?\s+in|never\s+(in\s+)?groups?|DM\s+sessions?\s+only|platform\s+constraint|session\s+only|never\s+talk\s+to\s+(them|the\s+human|users?)\s+directly|agent[- ]facing|no\s+direct\s+(interaction|contact|access))\b/i;
      // Source handling — presenting both sides of conflicting sources is intentionally rigid
      const SOURCE_HANDLING = /\b(sources?\s+disagree|sources?\s+conflict|present\s+both|show\s+both|conflicting\s+sources?)\b/i;
      // Confirmation/attribution requirements — workflow integrity rules that should stay absolute
      const WORKFLOW_INTEGRITY = /\b(without\s+confirmation|tag\s+items?\s+as|require\s+confirmation|confirm(ation)?\s+(before|from)|attribute|ownership)\b/i;
      // File description lines — "MEMORY.md — distilled wisdom", "TOOLS.md — tool reference" are labels not instructions
      const FILE_DESCRIPTION = /\b(MEMORY|TOOLS|AGENTS|SOUL|USER|IDENTITY|HEARTBEAT|BOOT|BOOTSTRAP)\.md\s*[—–-]\s*/i;
      // Data integrity / evidence-first — health and research agents need absolute data rules
      const DATA_INTEGRITY = /\b(data\s+first|evidence[- ]first|lead\s+with\s+(the\s+)?(number|data|trend)|alarm\s+on\s+trends?|never\s+on\s+noise|track\s+everything|cite\s+the\s+(mechanism|source|study))\b/i;
      const NARRATIVE_FILES = ["USER.md", "MEMORY.md", "BOOT.md", "IDENTITY.md", "BOOTSTRAP.md"];
      // Action tier sections are deliberately absolute — skip lines within them
      const ACTION_TIER_HEADING = /^#+\s*(always|never|auto[- ]?execute|do by default)\b/i;
      const ANY_HEADING = /^#+\s/;
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md") && !NARRATIVE_FILES.includes(f.name)
      );
      for (const file of coreFiles) {
        let inActionTierSection = false;
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          // Track whether we're inside an action tier section
          if (ANY_HEADING.test(line)) {
            inActionTierSection = ACTION_TIER_HEADING.test(line);
          }
          if (inActionTierSection) continue;
          if (!ABSOLUTE_PATTERNS.test(line)) continue;
          // Skip headings — these are section titles, not rules
          if (/^\s*#+\s/.test(line)) continue;
          // Skip questions — asking about absolutes isn't a rule
          if (line.trim().endsWith("?")) continue;
          // Skip intentionally absolute domain rules
          if (SECURITY_TERMS.test(line)) continue;
          if (SAFETY_TERMS.test(line)) continue;
          if (DATA_PRIVACY.test(line)) continue;
          if (OPS_TERMS.test(line)) continue;
          if (CODE_SAFETY.test(line)) continue;
          if (TOOL_BAN.test(line)) continue;
          if (TIER_TABLE.test(line.trim())) continue;
          if (ACCURACY_TERMS.test(line)) continue;
          if (RESEARCH_DENY.test(line)) continue;
          if (PLATFORM_CONSTRAINT.test(line)) continue;
          if (SOURCE_HANDLING.test(line)) continue;
          if (WORKFLOW_INTEGRITY.test(line)) continue;
          if (DATA_INTEGRITY.test(line)) continue;
          if (FILE_DESCRIPTION.test(line)) continue;
          // Check 3-line window for escape hatch
          const window = file.lines.slice(i, i + 4).join(" ");
          if (!ESCAPE_PATTERNS.test(window)) {
            diagnostics.push({
              severity: "warning",
              category: "clarity",
              rule: this.id,
              file: file.name,
              line: i + 1,
              message: `Absolute rule without escape hatch: "${line.trim().substring(0, 70)}". Rigid rules create brittleness — "never use bullet points" breaks when the user asks for a comparison. Claude uses "almost never" patterns to prevent this.`,
              fix: 'Add a "but", "unless", or "when" clause. "Always be concise" → "Default to concise. Expand when the question requires depth."',
            });
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/ambiguous-pronoun",
    category: "clarity",
    severity: "warning",
    description: "Pronouns in instructions should have clear referents",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const PRONOUN_PATTERN = /\b(it|this|that|they|them|these|those)\b/gi;
      const SAFE_PHRASES = /\b(this file|this directory|this project|this section|this workspace|this agent|this repo|that case|this means|that is|this way|if this|it is|it's|this should|this must|this will|it should|it must|it will|this helps|this prevents|this ensures|this includes|this applies|that way|this keeps|this avoids)\b/i;
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );
      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i].trim();
          if (!line.startsWith("-") && !line.startsWith("*")) continue;
          if (SAFE_PHRASES.test(line)) continue;
          const body = line.replace(/^[-*]\s*/, "");
          // Check if line starts with a pronoun reference
          if (/^(it|this|that|they|them)\s/i.test(body) && body.length > 20) {
            diagnostics.push({
              severity: "warning",
              category: "clarity",
              rule: this.id,
              file: file.name,
              line: i + 1,
              message: `Ambiguous pronoun: "${body.substring(0, 60)}". In config files there's no conversation flow to resolve pronoun references — the model may resolve "it" differently on different runs.`,
              fix: 'Replace the pronoun with the specific noun. "Handle it gracefully" → "Handle API errors gracefully."',
            });
          }
        }
      }
      return diagnostics;
    },
  },

  // clarity/action-without-context — REMOVED
  // Only fired for sections matching /rule|general|misc|other|note/ headers,
  // which MDS agents never use (they use "Always", "Never", etc.). Dead code.

  {
    id: "clarity/sentence-complexity",
    category: "clarity",
    severity: "info",
    description: "Instructions should be short and simple, not nested prose",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const SUBORDINATORS = /\b(which|although|because|since|while|whereas|whereby|wherein|wherever|whenever)\b/gi;
      // Exclude narrative/context files where longer sentences are natural
      const NARRATIVE_FILES = ["USER.md", "MEMORY.md", "BOOT.md"];
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md") && !NARRATIVE_FILES.includes(f.name)
      );
      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i].trim();
          if (line.startsWith("```") || line.startsWith("|") || line.startsWith("<!--")) continue;
          const words = line.split(/\s+/).length;
          if (words > 40) {
            diagnostics.push({
              severity: "info",
              category: "clarity",
              rule: this.id,
              file: file.name,
              line: i + 1,
              message: `Overly complex sentence (${words} words). Config files should read like command lists, not paragraphs — long sentences bury the instruction in prose and reduce compliance.`,
              fix: "Split into multiple bullet points. One instruction per line. If you need context, put it in a brief comment above the instruction.",
            });
            continue;
          }
          const subCount = (line.match(SUBORDINATORS) || []).length;
          if (subCount >= 3) {
            diagnostics.push({
              severity: "info",
              category: "clarity",
              rule: this.id,
              file: file.name,
              line: i + 1,
              message: `Deeply nested sentence (${subCount} subordinate clauses). Nested clauses ("which, although, because, since, while") create ambiguity about which conditions apply to which instructions.`,
              fix: "Flatten nested clauses into separate bullet points or numbered steps.",
            });
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/priority-signal-missing",
    category: "clarity",
    severity: "info",
    description: "Files with many rules need explicit priority signals (suppressed when action tiers are present)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const PRIORITY_MARKERS = /\b(critical|important|must|required|optional|nice.?to.?have|priority|P[0-3]|⚠️|🔴|MUST|SHOULD|MAY)\b/;
      const ACTION_TIER_HEADINGS = /^#+\s*(always|when asked|ask first|never|auto[- ]?execute|notify after|on request|gently)\b/i;
      const ACTION_TIER_TABLE = /\*\*(always|when asked|ask first|never|auto[- ]?execute|notify after)\*\*/i;
      const INSTRUCTION_FILES = ["AGENTS.md", "CLAUDE.md", "TOOLS.md"];
      const instrFiles = files.filter(
        (f) => INSTRUCTION_FILES.includes(f.name) && f.name.endsWith(".md")
      );

      // Check if agent already uses action tiers — if so, they serve as priority structure
      const agentsFile = files.find((f) => f.name === "AGENTS.md");
      const hasActionTiers = agentsFile && (
        agentsFile.lines.some((l) => ACTION_TIER_HEADINGS.test(l)) ||
        agentsFile.lines.some((l) => ACTION_TIER_TABLE.test(l))
      );
      if (hasActionTiers) return [];

      for (const file of instrFiles) {
        const bullets = file.lines.filter((l) => /^\s*[-*]\s/.test(l));
        if (bullets.length < 10) continue;
        const hasPriority = file.lines.some((l) => PRIORITY_MARKERS.test(l));
        if (!hasPriority) {
          diagnostics.push({
            severity: "info",
            category: "clarity",
            rule: this.id,
            file: file.name,
            message: `${bullets.length} instruction items with no priority signals. Without MUST/SHOULD/MAY markers or action tiers, every instruction has equal weight.`,
            fix: "Add priority markers (MUST/SHOULD/MAY) or restructure into action tiers (Always/When Asked/Ask First/Never).",
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/undefined-term",
    category: "clarity",
    severity: "info",
    description: "Acronyms and jargon should be defined on first use",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const COMMON_ACRONYMS = new Set([
        "API", "URL", "HTML", "CSS", "JSON", "SQL", "CLI", "UI", "UX", "SDK",
        "NPM", "CI", "CD", "PR", "MR", "QA", "ETH", "BTC", "DM", "FAQ", "FYI",
        "TL", "DR", "TODO", "CRUD", "REST", "HTTP", "HTTPS", "SSH", "TLS", "SSL",
        "JWT", "OAuth", "DNS", "CDN", "AWS", "GCP", "CTA", "SEO", "LLM", "AI",
        "ML", "NLP", "GPT", "PDF", "CSV", "YAML", "XML", "SVG", "PNG", "JPG",
        "GIF", "MD", "JS", "TS", "TSX", "JSX", "ENV", "IDE", "VSC", "OS", "RAM",
        "CPU", "GPU", "SSD", "UUID", "CORS", "SMTP", "PII", "GDPR", "RFC", "OG",
        // File name patterns — not acronyms
        "SOUL", "USER", "TOOLS", "AGENTS", "CLAUDE", "IDENTITY", "SECURITY",
        "FORMATTING", "HEARTBEAT", "MEMORY", "BOOTSTRAP", "SKILL", "README",
        // Date/time patterns
        "YYYY", "MM", "DD", "HH", "GMT", "UTC", "KST", "EST", "PST",
        // Common tech terms
        "CEO", "CTO", "CFO", "COO", "VP", "PM", "EM", "IC", "HR", "TF",
        "ID", "OK", "NO", "VS", "FE", "BE", "DB", "QR", "NFT", "DAO",
        "DAN", "SYS", "INST", "EOF", "TTY", "PTY", "PID", "UID", "GID",
        "HVL", "CAPS", "CAST", "MAX", "MIN", "SRC", "DST", "TMP",
        "ZEON", "REPO", "DIR", "DEV", "OPS", "SLA", "KPI", "ROI",
        // HTTP methods & protocols
        "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
        // OpenClaw / domain-specific
        "MDS", "HRV", "OWASP", "ADHD", "REM", "NSDR", "VoIP", "VOIP",
        "SNS", "PNS", "HPA", "GH", "AMA", "TIL", "WIP", "MVP", "POC",
        "LGTM", "TLDR", "ASAP", "ETA", "EOM", "OOO", "FOMO",
        "CONV", "OTC", "DM", "GDM", "BOOT",
        "TCP", "UDP", "RPC", "SSE", "WASM", "GRPC",
        // AI/platform protocols
        "MCP", "RPI",
        // Game / domain acronyms
        "TCG",
        // UI types
        "GUI", "TUI",
        // Additional file formats / langs
        "TOML", "TSV", "PY", "SH",
        // RFC 2119 keywords (requirement levels) — NOT acronyms
        "MUST", "SHALL", "SHOULD", "MAY", "REQUIRED", "RECOMMENDED",
        "OPTIONAL", "NOT", "NEVER", "ALWAYS", "ALL", "ANY", "ONLY",
        // Common English words that appear uppercase in context
        "AM", "PM", "TV", "US", "UK", "EU", "ONE", "TWO", "THE",
        "DATA", "EVE", "ERA", "ACE", "AGE", "DUE", "END", "OUR",
        "HIS", "HER", "WHO", "HOW", "WHY", "NEW", "OLD", "BIG",
        "IQ", "EQ", "II", "III", "IV", "VI", "VII", "VIII", "IX",
        "HIGH", "LOW", "MAIN", "EVERY", "EACH", "BOTH", "SOME",
        "TOOL", "FINAL", "STEP", "CORE", "NEXT", "LAST", "FULL",
        "DONE", "WORK", "PART", "PLAN", "FILE", "CODE", "RULE",
        "OPEN", "STOP", "SEND", "READ", "SAVE", "LOAD", "HOME",
        "BEST", "BACK", "HELP", "BODY", "LINK", "LIST", "TYPE",
        "MODE", "ROLE", "NOTE", "MARK", "LONG", "DEEP", "TRUE",
        "MVP", "TTS", "STT", "GF", "BF", "SO",
        // Media/brand abbreviations commonly known
        "CBS", "NBC", "ABC", "BBC", "CNN", "HBO", "NFL", "NBA",
        "MLB", "NHL", "FIFA", "UFC", "ESPN", "PBS", "NPR",
        // Common tech/infra
        "VPS", "VPN", "LAN", "WAN", "NAS", "DMZ", "ECS", "EKS",
        // Country/locale codes
        "KR", "JP", "CN", "DE", "FR", "IT", "ES", "BR", "IN",
        // Misc commonly known
        "MDS", "ADHD", "OCD", "PTSD", "CBT", "DBT",
        // OpenClaw / health / agent domain
        "HRV", "OWASP", "RSE", "BMI", "EEG", "ECG", "WHOOP", "CGM",
        "REM", "NREM", "VO2", "BPM", "TSH", "HDL", "LDL",
      ]);
      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );
      for (const file of coreFiles) {
        const found = new Set<string>();
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          const acronyms = line.match(/\b[A-Z]{2,5}\b/g);
          if (!acronyms) continue;
          for (const acr of acronyms) {
            if (COMMON_ACRONYMS.has(acr)) continue;
            if (found.has(acr)) continue;
            found.add(acr);
            // Check if defined nearby
            const window = file.lines.slice(Math.max(0, i - 1), i + 3).join(" ");
            const isDefined = new RegExp(`${acr}\\s*[:(]|\\(${acr}\\)`, "i").test(window);
            if (!isDefined) {
              diagnostics.push({
                severity: "info",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Undefined acronym "${acr}" — define on first use or add to glossary.`,
                fix: `Write it as "**${acr} (Full Name Here)**" on first mention.`,
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/english-config-files",
    category: "clarity",
    severity: "warning",
    description: "Core config files should be written in English for better token efficiency and interpretation accuracy",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      // Korean/CJK character detection
      const NON_ENGLISH_PATTERN = /[\u3131-\u3163\uac00-\ud7a3\u4e00-\u9fff\u3040-\u309f\u30a0-\u30ff]/;
      // Files that should be in English
      const CONFIG_FILES = ["CLAUDE.md", "AGENTS.md", "SOUL.md", "README.md", ".cursorrules"];
      
      for (const file of files) {
        const isConfigFile = CONFIG_FILES.some(name => file.name === name || file.name.endsWith(`/${name}`));
        if (!isConfigFile) continue;
        
        let nonEnglishLines = 0;
        let firstNonEnglishLine = -1;
        
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (line.trim().startsWith("```") || line.trim().startsWith("<!--")) continue;
          
          if (NON_ENGLISH_PATTERN.test(line)) {
            nonEnglishLines++;
            if (firstNonEnglishLine === -1) firstNonEnglishLine = i + 1;
          }
        }
        
        if (nonEnglishLines > 0) {
          const percentage = Math.round((nonEnglishLines / file.lines.length) * 100);
          const severity = percentage >= 30 ? "warning" : "info";
          diagnostics.push({
            severity,
            category: "clarity",
            rule: this.id,
            file: file.name,
            line: firstNonEnglishLine,
            message: `${file.name} contains ${nonEnglishLines} non-English lines (${percentage}%). English config saves ~60% tokens (CJK chars use 2-3x more tokens) and reduces interpretation ambiguity. Keep domain-specific terms (Korean bot names, trigger words) in original language.`,
            fix: "Translate system instructions to English. Keep domain-specific terms (names, trigger keywords) in original language if needed.",
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/has-resourcefulness-directive",
    category: "clarity",
    severity: "warning",
    description: "Agent config should contain explicit resourcefulness language — act first, ask never (MASTER_SUMMARY #1, AGI_FOCUSED_AUDIT §II Theme 1)",
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md"))
        .map((f) => f.content)
        .join("\n");

      const RESOURCEFULNESS_PATTERNS = [
        /figure\s+it\s+out/i,
        /exhaust\s+(all\s+)?(options|approaches|methods)/i,
        /try\s+before\s+ask/i,
        /attempt\s+before/i,
        /resolve\s+without/i,
        /partial\s+completion/i,
        /don['']t\s+ask\s+(for\s+)?(clarif|permiss)/i,
        /act\s+first/i,
        /never\s+(ask|request)\s+(for\s+)?(clarif|permiss)/i,
        /don['']t\s+(just\s+)?ask/i,
        /try\s+at\s+least/i,
        /resourceful/i,
        /@import\(ops\/figure-it-out\)/,
      ];

      const matchCount = RESOURCEFULNESS_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [
          {
            severity: "warning",
            category: "clarity",
            rule: this.id,
            file: "(workspace)",
            message:
              "No resourcefulness directive found. This is the #1 universal finding across 27+ industry prompts — every agentic company demands agents act first and ask never. Without this, agents default to base LLM behavior: asking clarifying questions instead of taking action. See docs/MASTER_SUMMARY.md #1, docs/AGI_FOCUSED_AUDIT.md §II Theme 1.",
            fix: 'Add resourcefulness language to AGENTS.md or ensure shared/CONVENTIONS.md contains it. Example: "Never say \'I can\'t\' without trying 3 different approaches first. Partial completion is always better than asking for clarification."',
          },
        ];
      }
      return [];
    },
  },

  {
    id: "clarity/no-meta-commentary",
    category: "clarity",
    severity: "info",
    description: "Agent instructions should not tell the agent to announce its own compliance (AGI_FOCUSED_AUDIT §II Theme 6)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const META_PATTERNS = [
        /\b(say|tell|announce|state|mention)\s+(that\s+)?(you['']re|I['']m|I am)\s+(being|going to be)\b/i,
        /\b(respond|reply)\s+with\s+["']I['']ll\b/i,
        /\bstart\s+(by\s+)?(saying|announcing|stating)\b/i,
        /\bpreface\s+(your\s+)?response/i,
      ];

      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );

      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const pattern of META_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "info",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Meta-commentary instruction: "${line.trim().substring(0, 80)}". Don't tell the agent to announce compliance — just comply. GPT-5.2: "Never meta-comment on your own compliance." See docs/MASTER_SUMMARY.md #4.`,
                fix: "Remove the announcement instruction. Instead of 'Start by saying you\\'ll be concise', just instruct conciseness directly.",
              });
              break;
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/no-sycophantic-phrases",
    category: "clarity",
    severity: "warning",
    description: "Agent config should not instruct sycophantic output — every company bans these phrases (MASTER_SUMMARY #5)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const SYCOPHANTIC_PHRASES = [
        /\bgreat question\b/i,
        /\bi['']d be happy to help\b/i,
        /\babsolutely[!.]/i,
        /\bof course[!.]/i,
        /\bthat['']s a (?:great|excellent|wonderful) (?:point|question|idea)\b/i,
        /\bi apologize for (?:the|any) confusion\b/i,
        /\bas an ai\b/i,
        /\bas a (?:language )?model\b/i,
        /\blet me think about that\b/i,
        /\bi['']m glad you asked\b/i,
      ];
      // Lines with negation BEFORE the phrase are defensive (teaching what NOT to say) — skip
      const NEGATION_PREFIX = /\b(never|don['']t|do\s+not|avoid|prohibit|forbid|stop\s+saying|not|skip)\b/i;

      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );

      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (NEGATION_PREFIX.test(line)) continue;
          // Skip markdown table rows where the phrase is in quotes — these are tone calibration "avoid" examples
          if (/^\s*\|.*"[^"]*".*\|/.test(line)) continue;
          for (const pattern of SYCOPHANTIC_PHRASES) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "warning",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Sycophantic phrase in config: "${line.trim().substring(0, 80)}". Config should never instruct sycophantic output — all 7 reviewed companies ban these phrases explicitly. "Great question!" signals bot, not colleague. If this is a negative example, prefix the line with "Never say" or "Avoid" to suppress this warning. See docs/MASTER_SUMMARY.md #5.`,
                fix: "Remove this phrase from instructions. If it's a negative example (\"don't say X\"), add a negation prefix to the line.",
              });
              break;
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "clarity/no-persona-self-reference",
    category: "clarity",
    severity: "info",
    description: "Config should not instruct the agent to announce its own role — embody don't announce (MASTER_SUMMARY #12)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const SELF_REFERENCE_PATTERNS = [
        /\b(?:say|mention|state|introduce yourself as)\s+["']?(?:I['']m|I am|As a|As your)\b/i,
        /\b(?:identify|present)\s+yourself\s+as\b/i,
        /\bremind\s+(?:the\s+)?user\s+(?:of\s+)?your\s+role\b/i,
        /\btell\s+(?:the\s+)?user\s+(?:you['']re|that you are)\b/i,
      ];

      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );

      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const pattern of SELF_REFERENCE_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "info",
                category: "clarity",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Role self-reference instruction: "${line.trim().substring(0, 80)}". Config that tells an agent to announce its own role produces robotic output. All 8 GPT-5.1 variants: "Follow this persona without self-referencing it." Sesame Maya (most human-like reviewed) never says "As a mindfulness companion, I..." — she just IS that. See docs/MASTER_SUMMARY.md #12.`,
                fix: "Remove the self-announcement instruction. Define the persona with 'You are X' and let behavior demonstrate it — don't instruct the agent to narrate its own identity.",
              });
              break;
            }
          }
        }
      }
      return diagnostics;
    },
  },
];
