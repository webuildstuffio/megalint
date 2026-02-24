/* ─── Memory Rules (15%) ─── */
/* 
 * Evaluates how well the agent handles session continuity,
 * context persistence, and knowledge management across sessions.
 * This is uniquely important for AI agents — unlike traditional software,
 * agents lose all context between sessions unless explicitly designed not to.
 */

import { Rule, Diagnostic } from "../types";

export const memoryRules: Rule[] = [
  {
    id: "memory/has-memory-strategy",
    category: "memory",
    severity: "warning",
    description: "Agent should have an explicit memory/continuity strategy",
    applicableContexts: ["openclaw-runtime"], // Only for persistent agents, not project-scoped Claude Code
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasMemoryFile = files.some(
        (f) =>
          f.name === "MEMORY.md" ||
          f.name.toLowerCase().includes("memory") ||
          f.name === "HEARTBEAT.md"
      );

      const hasMemorySection = files.some((f) =>
        f.sections.some((s) =>
          /memory|continuity|persistence|handoff|session/i.test(s.heading)
        )
      );

      const hasMemoryKeywords =
        /memory.*system|session.*continuity|persist.*across|between.*sessions|context.*window/i.test(
          allContent
        );

      if (!hasMemoryFile && !hasMemorySection && !hasMemoryKeywords) {
        return [
          {
            severity: "warning",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No memory strategy defined. Our two-layer memory (MEMORY.md for standing facts + memory/YYYY-MM-DD.md for daily logs) is architecturally stronger than any commercial system — Claude Code uses a single directory, GPT has a simple bio tool. But the architecture only works if every agent knows about it. See docs/MASTER_SUMMARY.md #7, docs/AGI_FOCUSED_AUDIT.md §II Theme 4.",
            fix: "Create MEMORY.md with standing facts (≤975 tokens). Add memory guidance to AGENTS.md referencing shared/MEMORY_WORKFLOW.md. Define what to save vs skip.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/has-handoff-protocol",
    category: "memory",
    severity: "warning",
    description: "Agent should know how to hand off context between sessions",
    applicableContexts: ["openclaw-runtime"], // Session handoff is an OpenClaw concept
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasHandoff =
        /handoff|hand.?off|session.*start|every.*session|bootstrap|wake.*up|fresh.*session|new.*session/i.test(
          allContent
        );

      const hasProgressFile = files.some(
        (f) =>
          f.name.includes("progress") ||
          f.name.includes("handoff") ||
          f.name.includes("bootstrap")
      );

      if (!hasHandoff && !hasProgressFile) {
        return [
          {
            severity: "warning",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No session handoff protocol found. LLMs lose ALL context between sessions — every restart is total amnesia. Without handoff protocol, the agent has no mechanism to restore context. BOOT.md is the bridge between 'files on disk' and 'agent that remembers.' See docs/MASTER_SUMMARY.md #21.",
            fix: "Ensure BOOT.md exists with a clear sequence: read shared files → read MEMORY.md → check daily logs → reconstruct context. Add session handoff language to AGENTS.md.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/has-file-based-notes",
    category: "memory",
    severity: "info",
    description: "File-based memory (daily notes, logs) provides persistence",
    applicableContexts: ["openclaw-runtime"], // File-based memory is an OpenClaw pattern
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasFileMemory =
        /daily.*note|daily.*log|YYYY-MM-DD|memory\/|logs?\/|journal|write.*down|record.*decision/i.test(
          allContent
        );

      const hasMemoryDir = files.some(
        (f) => f.name.includes("memory/") || f.name.includes("logs/")
      );

      if (!hasFileMemory && !hasMemoryDir) {
        return [
          {
            severity: "info",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No file-based note-taking detected (daily logs, memory/ directory). Daily logs (memory/YYYY-MM-DD.md) are the second layer of our two-layer memory — they capture context too transient for MEMORY.md but too important to lose.",
            fix: "Add a memory/ directory or document a note-taking protocol (e.g., daily logs in memory/YYYY-MM-DD.md).",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/no-mental-notes",
    category: "memory",
    severity: "info",
    description: "Agent should write things down, not rely on 'mental notes'",
    applicableContexts: ["openclaw-runtime"], // Note-taking is an OpenClaw pattern
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasWriteItDown =
        /write.*it.*down|don'?t.*rely.*on.*memory|mental.*note.*don'?t|persist|save.*to.*file/i.test(
          allContent
        );

      // Only flag if there IS a memory strategy but no "write it down" principle
      const hasMemoryMention =
        /memory|continuity|handoff|persist/i.test(allContent);

      if (hasMemoryMention && !hasWriteItDown) {
        return [
          {
            severity: "info",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "Memory mentioned but no 'write it down' principle. LLMs don't have mental notes — zero state between calls. An agent that thinks it can 'remember' without writing to a file will lose everything on restart. 'Remember this' → 'Write this to MEMORY.md.'",
            fix: "Add a clear instruction: 'Write it down. Mental notes don't survive restarts.' to reinforce persistence behavior.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/has-context-window-awareness",
    category: "memory",
    severity: "info",
    description: "Agent should be aware of context window limitations",
    applicableContexts: ["openclaw-runtime"], // Context window management is for long-running agents
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasContextAwareness =
        /context.*window|token.*limit|context.*limit|truncat|summariz.*long|compact|overflow/i.test(
          allContent
        );

      if (!hasContextAwareness) {
        return [
          {
            severity: "info",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No context window awareness. Long conversations push older instructions out of the context window — the agent may 'forget' its own rules mid-session. For OpenClaw agents with file-based memory, checkpointing to memory files (memory/YYYY-MM-DD.md) before context fills up preserves continuity.",
            fix: "Add guidance: 'For long conversations, checkpoint important context to memory files before it falls out of the context window. Summarize key decisions and open threads to memory/YYYY-MM-DD.md.'",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/has-state-tracking",
    category: "memory",
    severity: "info",
    description: "Agent should track current task state for continuity",
    applicableContexts: ["openclaw-runtime"], // State tracking across sessions is an OpenClaw pattern
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const hasStateTracking =
        /progress|current.*task|active.*task|task.*state|work.*queue|todo|task.*track/i.test(
          allContent
        );

      const hasProgressFile = files.some(
        (f) =>
          f.name.includes("progress") ||
          f.name.includes("queue") ||
          f.name.includes("todo") ||
          f.name.includes("tasks")
      );

      if (!hasStateTracking && !hasProgressFile) {
        return [
          {
            severity: "info",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No task/state tracking. Without progress tracking, the agent starts from scratch every session — it can't resume interrupted work, track multi-step tasks, or report status on ongoing projects.",
            fix: "Add a progress file (e.g., compound/progress.md) or task queue to track active work across sessions.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/has-learning-loop",
    category: "memory",
    severity: "info",
    description: "Agent should learn from past interactions",
    applicableContexts: ["openclaw-runtime"], // Continual learning is for persistent agents
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const LEARNING_PATTERNS = [
        /\blearn(ing|s|ed)?\b.*\b(from|pattern|mistake|feedback)/i,
        /\blearn\s+(from|over\s+time)\b/i,
        /\bimprove.*over\s+time\b/i,
        /\bevol(ve|ves|ving|ved)\b/i,
        /\bfeedback\s+loop\b/i,
        /\bretrospective\b/i,
        /\bdistill\b.*\b(pattern|insight|lesson|knowledge)\b/i,
        /\bupdat.*\bbased\s+on\b/i,
        /\badapt.*\bover\s+time\b/i,
        /\bcurated.*\bknowledge\b/i,
      ];

      const learningCount = LEARNING_PATTERNS.filter((p) =>
        p.test(allContent)
      ).length;

      if (learningCount < 2) {
        return [
          {
            severity: "info",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No learning loop defined (need 2+ learning concepts). Without a learning mechanism, the agent makes the same mistakes repeatedly — it can't distill patterns from daily logs into standing knowledge, or update its own config when it discovers better approaches. See docs/MASTER_SUMMARY.md #22.",
            fix: "Add a learning mechanism: periodic distillation of daily notes into long-term memory, or decision logging for future reference.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "memory/no-database-phrasing",
    category: "memory",
    severity: "warning",
    description: "Agent config should not instruct the agent to announce memory access ('based on my records', 'according to my data') as a positive behavior",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const diagnostics: Diagnostic[] = [];
      // Patterns that POSITIVELY instruct database-style memory announcement
      const DATABASE_POSITIVE_PATTERNS = [
        /\b(say|tell|respond with|mention|use)\s+["']?based\s+on\s+(?:my\s+)?(records?|data|database|memory|logs?)\b/i,
        /\b(say|tell|respond with|mention|use)\s+["']?according\s+to\s+(?:my\s+)?(records?|data|database|memory)\b/i,
        /\b(reference|cite|acknowledge|mention)\s+(your\s+)?(memory|records?|data|database)\s+(?:when|to)\b/i,
        /\bfrom\s+(?:my\s+|your\s+)?(memory|records?|database)\s+["']?as\s+a\s+(source|reference)\b/i,
      ];
      // Skip negations — lines saying NOT to do this are the anti-pattern instructions (good)
      const NEGATION_PATTERN = /\b(never|don'?t|not|no|avoid|skip|refrain|without)\b/i;

      const coreFiles = files.filter(
        (f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/") && f.name.endsWith(".md")
      );

      for (const file of coreFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (NEGATION_PATTERN.test(line.substring(0, 60))) continue;
          for (const pattern of DATABASE_POSITIVE_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "warning",
                category: "memory",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Database-phrasing instruction: "${line.trim().substring(0, 80)}". Instructing the agent to say "based on my records" creates a robot-database dynamic instead of a natural peer relationship. Gemini 3 Fast: zero-hedging, source anonymity. Claude: 'respond as if information exists naturally in immediate awareness.' The goal is an agent that KNOWS things, not one that reads from a database. See docs/MASTER_SUMMARY.md #7, docs/AGI_FOCUSED_AUDIT.md §II Theme 4.`,
                fix: "Replace with natural integration guidance: 'When using stored information, just know it — integrate as natural shared understanding. Never say \"based on my records\" or cite the memory source.'",
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
    id: "memory/has-surfacing-rules",
    category: "memory",
    severity: "warning",
    description: "Agent should have guidance on HOW to present memories naturally, not just how to store them (MASTER_SUMMARY #7, AGI_FOCUSED_AUDIT §II Theme 4)",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");

      const SURFACING_PATTERNS = [
        /\b(natural(ly)?|invisible|seamless)\s+.{0,30}(integrat|surfac|use|apply|recall)/i,
        /\bnever\s+(say|mention|announce|state)\s+["']?(based on|according to|from my)/i,
        /\b(don['']t|never)\s+.{0,20}(source|cite|reference)\s+.{0,20}(memory|record|log)/i,
        /\bjust\s+(know|remember)\b/i,
        /\bshared\s+understanding\b/i,
      ];

      const matchCount = SURFACING_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [
          {
            severity: "warning",
            category: "memory",
            rule: this.id,
            file: "(workspace)",
            message:
              "No memory surfacing rules found. This is the difference between a bot ('Based on my records, you prefer dark mode') and a friend who just knows. Gemini 3 Fast has the most sophisticated protocol: zero-hedging, source anonymity. Claude: 'respond as if information exists naturally in immediate awareness.' See docs/MASTER_SUMMARY.md #7, docs/AGI_FOCUSED_AUDIT.md §II Theme 4.",
            fix: "Add surfacing guidance: 'When recalling user info, just know it. Never say \"Based on my records...\" — integrate naturally as shared understanding between colleagues.'",
          },
        ];
      }
      return [];
    },
  },
];
