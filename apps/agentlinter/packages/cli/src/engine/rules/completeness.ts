/* ─── Completeness Rules (20%) ─── */

import { Rule, Diagnostic } from "../types";

export const completenessRules: Rule[] = [
  {
    id: "completeness/has-identity",
    category: "completeness",
    severity: "warning",
    description: "Agent should have a defined identity or persona",
    check(files) {
      const hasIdentityFile = files.some(
        (f) =>
          f.name === "SOUL.md" ||
          f.name === "IDENTITY.md" ||
          f.name.toLowerCase().includes("persona")
      );

      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      const hasIdentitySection = mainFile?.sections.some((s) =>
        /identity|persona|who you are|character|personality|role/i.test(s.heading)
      );

      if (!hasIdentityFile && !hasIdentitySection) {
        return [
          {
            severity: "warning",
            category: "completeness",
            rule: this.id,
            file: mainFile?.name || "(workspace)",
            message:
              "No identity/persona defined. Personality is the entire point of OpenClaw — commercial products strip it for brand safety, we build the opposite. Without identity, agents default to generic LLM output. Every company converges on 'warm directness' but we go further: actual voice, opinions, character. See docs/MASTER_SUMMARY.md #24.",
            fix: "Create SOUL.md: open with anti-sycophancy, define tone (direct/warm/honest), add calibration table (Sycophantic / Robotic / Alive). Answer: 'If this agent were a human, who would they be?' See agents/kodo/SOUL.md for reference.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-tools",
    category: "completeness",
    severity: "warning",
    description: "Agent should have tool documentation",
    check(files) {
      const hasToolsFile = files.some(
        (f) =>
          f.name === "TOOLS.md" || f.name.toLowerCase().includes("tools")
      );

      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      const hasToolsSection = mainFile?.sections.some((s) =>
        /tools|commands|capabilities|available tools/i.test(s.heading)
      );

      if (!hasToolsFile && !hasToolsSection) {
        return [
          {
            severity: "warning",
            category: "completeness",
            rule: this.id,
            file: mainFile?.name || "(workspace)",
            message:
              "No tool documentation found. Without TOOLS.md, the agent guesses which tools exist and how to use them — leading to failed tool calls, wrong parameters, and wasted cycles. See docs/MASTER_SUMMARY.md #19 on tool usage intelligence.",
            fix: "Create TOOLS.md (≤200 tokens) listing available tools with brief usage guidance. Prioritize: which tools to prefer, which to avoid, and when to use tools vs. answering directly.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-boundaries",
    category: "completeness",
    severity: "info",
    description: "Agent should have defined boundaries (advisory — action tiers in Home-Grow provide structured enforcement)",
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");
      // Require structured boundary evidence: a section heading OR 2+ strong denial keywords.
      // Previous version matched "don't" which appears in every file — zero signal.
      const hasBoundarySection = files.some((f) =>
        f.sections.some((s) =>
          /boundar|constraint|limitation|off.?limits|never\b|forbidden/i.test(s.heading)
        )
      );
      const strongDenials = [
        /\bforbidden\b/i,
        /\bprohibited\b/i,
        /\boff.?limits\b/i,
        /\bnot\s+allowed\b/i,
        /\bboundar/i,
        /\bconstraint/i,
        /\blimitation\b/i,
      ];
      const denialCount = strongDenials.filter((p) => p.test(allContent)).length;

      if (!hasBoundarySection && denialCount < 2) {
        const mainFile = files.find(
          (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
        );
        return [
          {
            severity: "info",
            category: "completeness",
            rule: this.id,
            file: mainFile?.name || "(workspace)",
            message:
              "No boundaries found. Action tiers (Always/When Asked/Ask First/Never) are OpenClaw's signature architecture — no other company structures permissions this cleanly. Without them, agents either do too much (destructive actions) or too little (ask permission for everything). See docs/MASTER_SUMMARY.md #3.",
            fix: "Add 4-tier structure to AGENTS.md: ## Always / ## When Asked / ## Ask First / ## Never — with concrete actions under each. See shared/CONVENTIONS.md for format.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-user-context",
    category: "completeness",
    severity: "info",
    description: "Providing user context helps personalization",
    applicableContexts: ["openclaw-runtime"], // Only for OpenClaw, not Claude Code
    check(files) {
      const hasUserFile = files.some(
        (f) =>
          f.name === "USER.md" || f.name.toLowerCase().includes("user")
      );

      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      const hasUserSection = mainFile?.sections.some((s) =>
        /user|human|owner|about.*you/i.test(s.heading)
      );

      if (!hasUserFile && !hasUserSection) {
        return [
          {
            severity: "info",
            category: "completeness",
            rule: this.id,
            file: "(workspace)",
            message:
              "No user context found. We serve one person — every agent should know who Nicholas is. Commercial products can't do this (millions of anonymous users). An agent without user context treats every interaction as a stranger encounter. With it: a conversation with a colleague who knows you.",
            fix: "Create USER.md with domain-specific lens on Nicholas. Reference shared/USER_CORE.md for shared facts — don't duplicate. Kodo needs emotional patterns, Basil needs dietary preferences, Forge needs tech stack.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-error-handling",
    category: "completeness",
    severity: "info",
    description: "Agent should have error awareness — mentions of errors, failures, edge cases (see also has-error-recovery for actual recovery protocol)",
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");
      // Require 2+ distinct error-handling concepts, not just any single keyword
      const patterns = [
        /\berror\b/i,
        /\bfail(ure|ed|s)?\b/i,
        /\bfallback\b/i,
        /\bedge case/i,
        /\bexception\b/i,
        /\brecover(y)?\b/i,
        /\bretry\b/i,
        /\btroubleshoot/i,
      ];
      const matchCount = patterns.filter((p) => p.test(allContent)).length;

      if (matchCount < 2) {
        return [
          {
            severity: "info",
            category: "completeness",
            rule: this.id,
            file: "(workspace)",
            message:
              "No error awareness found (need 2+ error-related concepts). The agent doesn't acknowledge things can fail — it won't crash, it'll just pretend nothing went wrong. That's worse than crashing because the user gets no signal. Even Claude Code's minimal 'When you encounter errors, fix them' dramatically improves handling. Distinct from has-error-recovery which checks for actual RECOVERY protocol.",
            fix: "Add error handling instructions: retry logic, fallback behavior, when to ask for help.",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-output-format",
    category: "completeness",
    severity: "info",
    description: "Defining expected output format improves consistency",
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");
      // Require 2+ distinct format-related concepts
      const patterns = [
        /\bformat(ting)?\b/i,
        /\boutput\b/i,
        /\bresponse.*style/i,
        /\bmarkdown\b/i,
        /\bjson\b/i,
        /\bstructured\b/i,
        /\btemplate\b/i,
      ];
      const matchCount = patterns.filter((p) => p.test(allContent)).length;

      if (matchCount < 2) {
        return [
          {
            severity: "info",
            category: "completeness",
            rule: this.id,
            file: "(workspace)",
            message:
              "No output format guidance found. Without format rules, agents alternate between bullet lists, prose, and markdown headers inconsistently. Claude defaults to heavy markdown (headers, bullets, bold) which reads as 'AI slop' in casual conversation.",
            fix: "Add format guidance: 'Default to prose in conversation. Use tables for comparisons, bullets for multi-item lists, code blocks for code. Headers only in long documents.'",
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-workflow",
    category: "completeness",
    severity: "info",
    description: "Defining workflows helps the agent handle multi-step tasks",
    check(files) {
      const allContent = files.map((f) => f.content).join("\n");
      // Require 2+ distinct workflow-related concepts
      const patterns = [
        /\bworkflow\b/i,
        /\bdeploy/i,
        /\bgit.*push/i,
        /\bstep.*by.*step/i,
        /\bprocedure\b/i,
        /\bpipeline\b/i,
        /\bphase\s+[1-9]/i,
      ];
      const matchCount = patterns.filter((p) => p.test(allContent)).length;

      if (matchCount < 2) {
        return [
          {
            severity: "info",
            category: "completeness",
            rule: this.id,
            file: "(workspace)",
            message:
              "No workflow documentation found. Without documented workflows, agents improvise multi-step processes differently every time — inconsistent deploy sequences, review flows, or task completion patterns.",
            fix: "Document multi-step processes as numbered steps in AGENTS.md or move to skills/ files. If the agent runs builds, deploys, or reviews, those sequences should be explicit.",
          },
        ];
      }
      return [];
    },
  },

  // completeness/has-priorities — REMOVED
  // Matched "must" and "important" which appear in every file — never fired.
  // Also duplicates clarity/priority-signal-missing which checks the same
  // concept with better analysis (counts bullets, checks for actual markers).

  {
    id: "completeness/verification-criteria-required",
    category: "completeness",
    severity: "warning",
    description: "Agent config should define how to verify task completion",
    check(files) {
      const mainFile = files.find(
        (f) => f.name === "CLAUDE.md" || f.name === "AGENTS.md"
      );
      if (!mainFile) return [];

      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      // Conversational/guidance agents don't have testable "done" states
      const CONVERSATIONAL_SIGNALS = /\b(companion|guide|guidance|life\s+guide|mindfulness|wellness|meditation|therapist|counselor|conversation|emotional|empathy)\b/i;
      const isConversational = CONVERSATIONAL_SIGNALS.test(allContent);

      const hasVerification =
        /how\s+to\s+verify/i.test(allContent) ||
        /success\s+criteria/i.test(allContent) ||
        /verification\s+criteria/i.test(allContent) ||
        /definition\s+of\s+done/i.test(allContent) ||
        /done\s+when/i.test(allContent) ||
        /task\s+(?:is\s+)?(?:complete|done|finished)\s+when/i.test(allContent) ||
        /how\s+(?:to\s+)?(?:check|confirm|validate)/i.test(allContent) ||
        /\btest\s+(?:the\s+)?(?:output|result|response)\b/i.test(allContent) ||
        /verify\s+(?:the\s+)?(?:output|result|task|work)/i.test(allContent);

      if (!hasVerification) {
        return [
          {
            severity: isConversational ? "info" : "warning",
            category: "completeness",
            rule: this.id,
            file: mainFile.name,
            message: isConversational
              ? 'No verification criteria found. For conversational agents, "done" is contextual — consider domain-specific completion signals rather than formal criteria.'
              : "No verification criteria found. Without a definition of 'done', agents can respond with 'I'll look into that' without actually looking into anything. See docs/MASTER_SUMMARY.md #8.",
            fix: 'Add verification language, domain-specific is best. Forge: "run tests before reporting done." Passportio: "triple-verify deadlines against official sources." Generic: "Task complete when: tested, verified, user can act on it."',
          },
        ];
      }
      return [];
    },
  },

  {
    id: "completeness/has-error-recovery",
    category: "completeness",
    severity: "warning",
    description: "Agent should have an explicit error RECOVERY protocol, not just error awareness (MASTER_SUMMARY #2, AGI_FOCUSED_AUDIT §II Theme 5)",
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      // Conversational agents don't execute tasks that fail in retryable ways
      const CONVERSATIONAL_SIGNALS = /\b(companion|guide|guidance|life\s+guide|mindfulness|wellness|meditation|therapist|counselor|conversation|emotional|empathy)\b/i;
      const isConversational = CONVERSATIONAL_SIGNALS.test(allContent);

      const ERROR_RECOVERY_PATTERNS = [
        /\b(retry|retries|reattempt)\b/i,
        /\b(diagnos|debug|troubleshoot|root\s+cause)/i,
        /\b(different\s+approach|alternative\s+(method|approach|strategy))/i,
        /\b(recover|self[- ]heal|fall\s*back)/i,
        /\b(don['']t|never)\s+(just\s+)?retry\s+the\s+same/i,
        /\badapt\b/i,
        /\btry\s+differently/i,
      ];

      const matchCount = ERROR_RECOVERY_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount < 2) {
        return [
          {
            severity: isConversational ? "info" : "warning",
            category: "completeness",
            rule: this.id,
            file: "(workspace)",
            message: isConversational
              ? "No error recovery protocol found. Conversational agents handle errors through honest uncertainty rather than retry semantics — this is lower priority for guidance/companion agents."
              : "No error recovery protocol found (need 2+ recovery concepts). Without recovery guidance, agents either retry the same broken thing endlessly or give up after one failure. See docs/MASTER_SUMMARY.md #2.",
            fix: 'Add error recovery protocol: "When things fail: 1) Diagnose root cause 2) Try a different approach 3) Verify the fix 4) Never brute-force the same failure."',
          },
        ];
      }
      return [];
    },
  },
];
