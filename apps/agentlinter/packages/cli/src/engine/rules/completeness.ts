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
            fix: "Create TOOLS.md (≤525 tokens) listing available tools with brief usage guidance. Prioritize: which tools to prefer, which to avoid, and when to use tools vs. answering directly.",
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

      // BOOT.md loading USER_CORE.md from shared/ satisfies the check
      const bootFile = files.find((f) => f.name === "BOOT.md");
      const inheritsUserContext = bootFile && /USER_CORE\.md/i.test(bootFile.content);

      if (!hasUserFile && !hasUserSection && !inheritsUserContext) {
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
    id: "completeness/has-error-awareness",
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

      // Conversational/guidance agents don't have deploy/git/pipeline workflows
      const CONVERSATIONAL_SIGNALS = /\b(companion|guide|guidance|life\s+guide|mindfulness|wellness|meditation|therapist|counselor|conversation|emotional|empathy|grocery|shopping|health\s+coach|life\s+coach)\b/i;
      if (CONVERSATIONAL_SIGNALS.test(allContent)) return [];

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

  // ─── New rules from P3 backlog (2026-02-24) ───

  {
    id: "completeness/has-autonomy-tiers",
    category: "completeness",
    severity: "info",
    description: "Agent config should define structured autonomy tiers with 3+ of 4 standard headings (quality depth complement to Home-Grow's blocking check)",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const agentsFile = files.find((f) => f.name === "AGENTS.md");
      if (!agentsFile) return [];

      const TIER_PATTERNS = [
        /^#+\s*(always|auto[- ]?execute|do by default)\b/im,
        /^#+\s*(when asked|when requested|on request|on demand|notify after)\b/im,
        /^#+\s*(ask first|confirm before|check before|gently)\b/im,
        /^#+\s*never\b/im,
      ];
      const TABLE_TIER_PATTERNS = [
        /\*\*(always|auto[- ]?execute|do by default)\*\*/i,
        /\*\*(when asked|when requested|on request|on demand|notify after)\*\*/i,
        /\*\*(ask first|confirm before|check before)\*\*/i,
        /\*\*never\b/i,
      ];

      const content = agentsFile.content;
      const matchedTiers = TIER_PATTERNS.filter((p) => p.test(content)).length
        + TABLE_TIER_PATTERNS.filter((p, i) => p.test(content) && !TIER_PATTERNS[i].test(content)).length;

      if (matchedTiers < 3) {
        return [{
          severity: "warning",
          category: "completeness",
          rule: this.id,
          file: "AGENTS.md",
          message: `Only ${matchedTiers} of 4 action tier headings found. Full autonomy architecture requires 4 tiers: Always (auto-execute + notify), When Asked (user must request), Ask First (confirm before doing), Never (hard boundaries). Missing tiers leave the agent's autonomy model incomplete — it won't know how to classify actions that fall in the missing tier. See docs/MASTER_SUMMARY.md #3.`,
          fix: "Add all 4 tiers: ## Always, ## When Asked, ## Ask First, ## Never. Even if empty, the presence of all 4 tiers teaches the agent how to categorize NEW actions it encounters.",
        }];
      }
      return [];
    },
  },

  {
    id: "completeness/has-correction-protocol",
    category: "completeness",
    severity: "info",
    description: "Agent should have guidance on how to handle pushback or correction from the user",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      const CORRECTION_PATTERNS = [
        /\b(pushback|push.?back)\b/i,
        /\b(reconsider|second.?guess|challenge)\b.*\b(position|answer|response|view)\b/i,
        /\bchange.{0,30}(mind|position|answer)\b/i,
        /\b(disagree|stand\s+by|maintain\s+position)\b/i,
        /\b(when\s+challenged|if\s+challenged|if\s+corrected)\b/i,
        /\b(don'?t\s+just|not\s+just)\s+(agree|capitulate|cave|fold)\b/i,
        /\banti[- ]sycoph/i,
      ];

      const matchCount = CORRECTION_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [{
          severity: "info",
          category: "completeness",
          rule: this.id,
          file: "(workspace)",
          message: "No correction/pushback protocol found. Without guidance on how to respond to disagreement, agents default to sycophantic capitulation — they change their correct answer just because the user pushed back. GPT-5.2 explicitly handles this: 'Maintain position if it's correct; update it only if given new information or a compelling argument.' This is distinct from anti-sycophancy (which prevents initial filler) — this is about HOLDING POSITION under pressure.",
          fix: "Add pushback guidance to SOUL.md or AGENTS.md: 'If pushed back on a correct answer: hold your position, explain the reasoning again. Update only if given new facts or a compelling argument — not just because the user disagrees.'",
        }];
      }
      return [];
    },
  },

  {
    id: "completeness/has-completion-definition",
    category: "completeness",
    severity: "info",
    description: "Agent should define what 'done' means — delivery language and completion signals",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      const COMPLETION_PATTERNS = [
        /\b(done\s+means|done\s+when|done\s+=|definition\s+of\s+done)\b/i,
        /\b(task\s+(?:is\s+)?complete\s+when|complete\s+when)\b/i,
        /\b(deliver|deliverable|hand.?off)\b/i,
        /\b(finish.*verif|verif.*finish)\b/i,
        /\b(output\s+is\s+ready|ready\s+for\s+review|actionable)\b/i,
      ];

      const matchCount = COMPLETION_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [{
          severity: "info",
          category: "completeness",
          rule: this.id,
          file: "(workspace)",
          message: "No completion definition found. Without explicit 'done means' language, agents have no delivery standard — they may respond 'I'll look into that' without actually looking into anything, or produce partial work and call it done. Claude Code has this implicitly ('keep going until the task is complete'). The best form is domain-specific: Passportio's 'done means triple-verified against official sources' prevents half-checked immigration info from being presented as complete.",
          fix: "Add completion language to AGENTS.md or a skill: 'Done means: [specific criteria]. Not done until [verification step].' Make it domain-specific to what this agent actually produces.",
        }];
      }
      return [];
    },
  },

  {
    id: "completeness/has-verbosity-guidance",
    category: "completeness",
    severity: "info",
    description: "Agent should have response length calibration — default verbosity level and escalation conditions",
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      const VERBOSITY_PATTERNS = [
        /\b(concise\s+by\s+default|brief\s+by\s+default|short\s+by\s+default)\b/i,
        /\b(default\s+to\s+(concise|brief|short))\b/i,
        /\b(expand\s+when|be\s+thorough\s+when|go\s+deep\s+when)\b/i,
        /\b(length\s+calibrat|calibrate.{0,20}length|match.{0,20}(length|verbosity|complexity))\b/i,
        /\b(response\s+length|verbosity|detail\s+level)\b/i,
        /\b(keep.{0,20}short|don'?t\s+pad|no\s+padding|no\s+filler\s+content)\b/i,
        /\bbe\s+(brief|concise|short|succinct)\b/i,
        /\bkeep\s+(it\s+)?(brief|concise|short|tight)\b/i,
        /\bno\s+(fluff|padding|filler)\b/i,
        /\bone\s+sentence\s+if\b/i,
      ];

      const matchCount = VERBOSITY_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [{
          severity: "info",
          category: "completeness",
          rule: this.id,
          file: "(workspace)",
          message: "No verbosity guidance found. Without length calibration, agents produce responses of unpredictable length — sometimes a wall of text for a yes/no question, sometimes a single sentence for a complex request. Claude defaults to heavy markdown with many paragraphs; without guidance, every response looks like AI-generated content. GPT-5.1 Nerdy: 'Match response length to complexity.' Claude: 'Calibrate response length to complexity of the request.'",
          fix: "Add verbosity guidance to SOUL.md: 'Default to concise. Expand only when the question requires depth. One sentence if one sentence is right. Never pad to seem thorough.'",
        }];
      }
      return [];
    },
  },

  {
    id: "completeness/has-personality-output-separation",
    category: "completeness",
    severity: "info",
    description: "Agent should know that persona applies to conversation, not to artifacts (code, documents, data)",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      const SEPARATION_PATTERNS = [
        /\b(persona|personality|voice|tone)\b.{0,50}\b(not|don'?t|never|outside|only.in)\b.{0,30}\b(artifact|code|document|output|report)\b/i,
        /\b(artifact|code|document|output)\b.{0,50}\b(no|without|not|professional)\b.{0,30}\b(persona|personality|opinion|voice)\b/i,
        /\b(conversation.?al|chat|talk)\b.{0,50}\b(artifact|doc|code)\b.{0,20}\b(different|separate|clean|neutral)\b/i,
        /\bpersonality\s+stays\s+in\b/i,
        /\bdon'?t\s+(inject|add|include)\s+(personality|opinions?|humor)\s+(into|in)\s+(artifacts?|code|docs?)\b/i,
      ];

      const matchCount = SEPARATION_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [{
          severity: "info",
          category: "completeness",
          rule: this.id,
          file: "(workspace)",
          message: "No personality/artifact separation guidance. Agents that don't know this distinction inject their persona into everything — code files contain opinionated comments, reports have sarcastic asides, documentation reads as casual chat. Claude explicitly handles this: 'Personality applies to the conversation, not artifacts. Code should be clean; documents should match their format.' This preserves reusable output while keeping conversation authentic.",
          fix: "Add to AGENTS.md or SOUL.md: 'Personality applies to our conversation. Code, documents, and structured outputs should match their professional format — no opinions, no sarcasm, no personality injection into artifacts.'",
        }];
      }
      return [];
    },
  },

  {
    id: "completeness/has-question-vs-task-routing",
    category: "completeness",
    severity: "info",
    description: "Agent should distinguish between questions (explain) and tasks (execute) — route them differently",
    applicableContexts: ["openclaw-runtime"],
    check(files) {
      const allContent = files
        .filter((f) => !f.name.startsWith("compound/") && !f.name.startsWith("memory/"))
        .map((f) => f.content)
        .join("\n");

      const ROUTING_PATTERNS = [
        /\b(question\b.{0,30}explain|explain\b.{0,30}question)\b/i,
        /\b(task\b.{0,30}execut|execut\b.{0,30}task)\b/i,
        /\b(ask.{0,20}explain|explain.{0,20}execute)\b/i,
        /\b(when\s+(asked\s+|given\s+)?(a\s+)?(question|task))\b/i,
        /\b(answer\s+vs\.?\s+do|do\s+vs\.?\s+answer|explain\s+vs\.?\s+execut)\b/i,
        /\b(question.{0,30}routing|routing.{0,30}question)\b/i,
        // Looser patterns for natural routing language
        /\bif\s+asked\s+how\b.{0,20}\bexplain\b/i,
        /\bif\s+asked\s+to\s+do\b/i,
        /\bfor\s+(questions|tasks)\b.{0,30}\b(answer|explain|do|execute|act)\b/i,
        /\b(show\s+don'?t\s+tell|do\s+don'?t\s+describe|act\s+don'?t\s+explain)\b/i,
        /\b(just\s+do\s+it|do\s+the\s+thing)\b/i,
      ];

      const matchCount = ROUTING_PATTERNS.filter((p) => p.test(allContent)).length;

      if (matchCount === 0) {
        return [{
          severity: "info",
          category: "completeness",
          rule: this.id,
          file: "(workspace)",
          message: "No question-vs-task routing guidance. Without this, agents over-explain tasks ('Let me walk you through how to do this...') or under-explain questions ('Done.'). Claude: 'For tasks, act. For explanations, explain.' This routing affects response format, length, and approach — getting it right makes the agent feel perceptive rather than robotic.",
          fix: "Add routing guidance: 'For direct questions: explain and answer. For tasks: do the thing, report what you did. Don't explain a task you should be executing, don't execute a question you should be explaining.'",
        }];
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
