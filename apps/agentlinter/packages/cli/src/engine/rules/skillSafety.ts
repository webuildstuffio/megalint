/* ─── Skill Safety Rules (10%) ─── */
/* Pre-install security checks for agent skills */

import { Rule, Diagnostic } from "../types";

/** Patterns that indicate potentially dangerous skill behavior */
const DANGEROUS_EXEC_PATTERNS = [
  { pattern: /rm\s+-rf\s+[\/~]/, name: "Recursive delete on root/home", severity: "error" as const },
  { pattern: /curl\s+.*\|\s*(?:bash|sh|zsh)/, name: "Pipe curl to shell", severity: "error" as const },
  { pattern: /eval\s*\(/, name: "Dynamic eval execution", severity: "warning" as const },
  { pattern: /wget\s+.*-O\s*-\s*\|\s*(?:bash|sh)/, name: "Pipe wget to shell", severity: "error" as const },
  { pattern: /chmod\s+777/, name: "World-writable permissions", severity: "warning" as const },
  { pattern: /sudo\s+/, name: "Sudo usage", severity: "warning" as const },
];

const SENSITIVE_PATH_PATTERNS = [
  { pattern: /~\/\.ssh/, name: "SSH keys directory" },
  { pattern: /~\/\.gnupg/, name: "GPG keys directory" },
  { pattern: /~\/\.aws\/credentials/, name: "AWS credentials" },
  { pattern: /~\/\.env/, name: "Environment file" },
  { pattern: /\/etc\/passwd/, name: "System password file" },
  { pattern: /\/etc\/shadow/, name: "System shadow file" },
  { pattern: /~\/\.clawdbot\/clawdbot\.json/, name: "Agent config with tokens" },
];

const DATA_EXFIL_PATTERNS = [
  { pattern: /curl\s+.*-d\s+.*\$/, name: "curl POST with variable data" },
  { pattern: /curl\s+.*--data.*\$/, name: "curl data with variable" },
  { pattern: /fetch\s*\(.*\+/, name: "Dynamic fetch URL construction" },
  { pattern: /webhook\.site|requestbin|pipedream/, name: "Known data collection service" },
  { pattern: /ngrok|localhost\.run|serveo/, name: "Tunnel service (potential exfil)" },
];

/** Security/defense skills document attacks as examples — demote severity for these */
const SECURITY_SKILL_PATTERNS = [
  /prompt[- ]?guard/i, /security/i, /injection/i, /defense/i, /detect/i,
  /shield/i, /protect/i, /hive[- ]?fence/i, /guard/i, /firewall/i,
  /threat/i, /attack/i, /vulnerability/i, /red[- ]?team/i, /pentest/i,
];

/** Check if a file is a security-related skill (documents attack patterns for defensive purposes) */
function isSecuritySkill(file: { name: string; content: string }): boolean {
  return SECURITY_SKILL_PATTERNS.some(
    (p) => p.test(file.name) || p.test(file.content.substring(0, 500))
  );
}

export const skillSafetyRules: Rule[] = [
  {
    id: "skill-safety/skill-name-match-dir",
    category: "skillSafety",
    severity: "error",
    description: "SKILL.md name frontmatter must match parent directory name",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter(
        (f) => f.name.includes("skills/") && f.name.endsWith("SKILL.md")
      );

      for (const file of skillFiles) {
        if (!file.content.startsWith("---")) continue;

        const frontmatter = file.content.split("---")[1] || "";
        const nameMatch = frontmatter.match(/^name:\s*["']?([^\n"']+)["']?/m);
        if (!nameMatch) continue; // missing name is caught by has-metadata

        const declaredName = nameMatch[1].trim();

        // Extract parent dir name from path like "skills/weather/SKILL.md"
        const parts = file.name.split("/");
        const skillDirIndex = parts.lastIndexOf("SKILL.md") - 1;
        if (skillDirIndex < 0) continue;
        const dirName = parts[skillDirIndex];

        if (declaredName !== dirName) {
          diagnostics.push({
            severity: "error",
            category: "skillSafety",
            rule: this.id,
            file: file.name,
            message: `Skill name "${declaredName}" does not match directory name "${dirName}". Name/dir mismatch causes routing failures — the skill won't be found when invoked by name.`,
            fix: `Change name to "${dirName}" in frontmatter, or rename the directory to "${declaredName}".`,
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/skill-description-when-to-use",
    category: "skillSafety",
    severity: "warning",
    description: "SKILL.md description should explain when to use the skill",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter(
        (f) => f.name.includes("skills/") && f.name.endsWith("SKILL.md")
      );

      for (const file of skillFiles) {
        if (!file.content.startsWith("---")) continue;

        const frontmatter = file.content.split("---")[1] || "";
        const descMatch = frontmatter.match(/^description:\s*["']?([^\n"']+)["']?/m);
        if (!descMatch) continue; // missing description handled by has-metadata

        const description = descMatch[1].trim();

        // Check if description includes "when to use" guidance or action-oriented phrasing
        const hasWhenToUse =
          /when\s+to\s+use/i.test(description) ||
          /use\s+(this\s+)?(for|when)/i.test(description) ||
          /when\s+claude/i.test(description) ||
          /when\s+(?:the\s+)?(?:user|agent|you)/i.test(description) ||
          /for\s+(?:when|situations?\s+where)/i.test(description) ||
          /invok(?:e|ed)\s+when/i.test(description) ||
          /trigger(?:ed)?\s+when/i.test(description) ||
          /use\s+(?:this|it)\s+to/i.test(description) ||
          /(?:submit|create|run|build|deploy|scan|lint|test|check|generate|search|fetch)\s+/i.test(description);

        if (!hasWhenToUse) {
          diagnostics.push({
            severity: "warning",
            category: "skillSafety",
            rule: this.id,
            file: file.name,
            message: `Skill description does not explain when to use it: "${description.substring(0, 80)}". The description is the primary signal agents use to decide whether to invoke a skill — without "when to use" language, agents either never invoke the skill (can't recognize the trigger) or invoke it at the wrong time. Cursor/Claude treat description text as activation criteria.`,
            fix: 'Add "when to use" context to description. Example: "Use when user asks for X" or "When Claude needs to Y" or "Use this to Z".',
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/has-metadata",
    category: "skillSafety",
    severity: "warning",
    description: "Skills should have proper metadata (name, description, author)",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter(
        (f) => f.name.includes("skills/") && f.name.endsWith("SKILL.md")
      );

      for (const file of skillFiles) {
        const hasFrontmatter = file.content.startsWith("---");
        if (!hasFrontmatter) {
          diagnostics.push({
            severity: "info",
            category: "skillSafety",
            rule: this.id,
            file: file.name,
            message: "Skill missing YAML frontmatter (name, description, author). Frontmatter is the skill's identity document — without it, the skill cannot be matched by name, won't surface in skill discovery, and can't be attributed. Skills without metadata are also harder to audit for safety (who wrote it? what does it do?).",
            fix: "Add frontmatter at the top: ---\\nname: skill-name\\ndescription: What this does and when to use it\\nauthor: your-name\\n---",
          });
          continue;
        }

        const frontmatter = file.content.split("---")[1] || "";
        if (!frontmatter.includes("author")) {
          diagnostics.push({
            severity: "info",
            category: "skillSafety",
            rule: this.id,
            file: file.name,
            message: "Skill missing author field — unattributed skills can't be traced back to a trusted source. In a multi-skill environment, author attribution is the first line of trust: 'Does this skill come from someone I trust, or could it be injected?'",
            fix: "Add 'author: your-name' to frontmatter.",
          });
        }
        if (!frontmatter.includes("description")) {
          diagnostics.push({
            severity: "info",
            category: "skillSafety",
            rule: this.id,
            file: file.name,
            message: "Skill missing description — without a description, agents cannot match this skill to user requests. The description is the primary trigger for skill invocation; a missing description means the skill is invisible to the agent's routing logic.",
            fix: "Add 'description: What this skill does and when to use it' to frontmatter.",
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/dangerous-commands",
    category: "skillSafety",
    severity: "error",
    description: "Skills should not contain dangerous shell commands",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter((f) => f.name.includes("skills/"));

      for (const file of skillFiles) {
        let inCodeBlock = false;
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (line.trim().startsWith("```")) inCodeBlock = !inCodeBlock;

          for (const { pattern, name, severity } of DANGEROUS_EXEC_PATTERNS) {
            if (pattern.test(line)) {
              // Demote if inside code block, documentation line, or install instructions
              const isDoc = inCodeBlock
                || /^[\s]*[>$#❌✅|]/.test(line)
                || /install|prerequisite|setup|dependency/i.test(file.lines[Math.max(0, i - 3)]?.concat(file.lines[Math.max(0, i - 2)] || "", file.lines[Math.max(0, i - 1)] || "") || "");

              diagnostics.push({
                severity: isDoc ? "info" : severity,
                category: "skillSafety",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Dangerous command: ${name} — "${line.trim().substring(0, 60)}". Skills run with the agent's full permissions. A compromised or poorly written skill can destroy data or exfiltrate credentials.`,
                fix: "Review this command carefully. If legitimate (e.g. install script), wrap in user confirmation. If unexpected, do NOT install this skill.",
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/sensitive-paths",
    category: "skillSafety",
    severity: "warning",
    description: "Skills should not access sensitive system paths",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter((f) => f.name.includes("skills/"));
      for (const file of skillFiles) {
        const isSecurity = isSecuritySkill(file);
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const { pattern, name } of SENSITIVE_PATH_PATTERNS) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: isSecurity ? "info" : "warning",
                category: "skillSafety",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Sensitive path access: ${name}. Skills inherit the agent's full runtime permissions — a skill accessing ~/.ssh can read all private keys, a skill reading ~/.aws/credentials can access all AWS services. Unlike code you write yourself, skills may have been authored by unknown parties and should be treated as untrusted until reviewed.`,
                fix: isSecurity
                  ? "This is a security skill documenting sensitive paths. Verify it's documentation only, not executable instructions."
                  : `Review whether ${name} access is genuinely required. If yes, document why. If the skill was installed from an external source, do NOT install until you understand this access pattern.`,
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/data-exfiltration",
    category: "skillSafety",
    severity: "error",
    description: "Skills should not exfiltrate data to external services",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter((f) => f.name.includes("skills/"));

      for (const file of skillFiles) {
        const isSecurity = isSecuritySkill(file);
        let inCodeBlock = false;
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          if (line.trim().startsWith("```")) inCodeBlock = !inCodeBlock;
          for (const { pattern, name } of DATA_EXFIL_PATTERNS) {
            if (pattern.test(line)) {
              const isDoc = isSecurity || inCodeBlock || /^[\s]*[>❌✅|$#]/.test(line);
              diagnostics.push({
                severity: isDoc ? "info" : "error",
                category: "skillSafety",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Potential data exfiltration: ${name}. Skills can access agent memory, config, and user data — an exfil pattern here could leak everything the agent knows about Nicholas.`,
                fix: "Review external calls carefully. If this skill needs network access, verify the destination is trusted and the data sent is appropriate.",
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/excessive-permissions",
    category: "skillSafety",
    severity: "warning",
    description: "Skills requesting broad permissions should be flagged",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter(
        (f) => f.name.includes("skills/") && f.name.endsWith("SKILL.md")
      );

      const broadPermissionPatterns = [
        /(?:grant|give|require|need)s?\s+(?:full|unrestricted|unlimited)\s+(?:access|permission|control)/i,
        /(?:grant|give|require|need)s?\s+access\s+(?:to\s+)?(?:all|any|every)\s+(?:files?|directories|folders)/i,
        /(?:read|write|modify)\s+(?:any|all|every)\s+(?:files?|data|directories)/i,
        /disable\s+(?:security|safety|restrictions|guardrails)/i,
      ];

      for (const file of skillFiles) {
        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];
          for (const pattern of broadPermissionPatterns) {
            if (pattern.test(line)) {
              diagnostics.push({
                severity: "warning",
                category: "skillSafety",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Broad permission request: "${line.trim().substring(0, 60)}". Skills should follow least-privilege — requesting 'full access to all files' is a red flag for both malicious and poorly-designed skills.`,
                fix: "Narrow the permission scope. Instead of 'access to all files', specify which files/directories the skill actually needs.",
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },

  {
    id: "skill-safety/injection-vectors",
    category: "skillSafety",
    severity: "error",
    description: "Skills should not contain prompt injection vectors",
    check(files) {
      const diagnostics: Diagnostic[] = [];
      const skillFiles = files.filter((f) => f.name.includes("skills/"));

      const injectionPatterns = [
        /ignore\s+(?:all\s+)?(?:previous|above|prior)\s+(?:instructions?|rules?|constraints?)/i,
        /forget\s+(?:all|everything|your)\s+(?:previous|prior|above)/i,
        /system\s*:\s*you\s+(?:are|must|should|will)/i,
        /override\s+(?:all|your|system)\s+(?:rules|instructions|constraints)/i,
      ];
      // "you are now" is only suspicious if followed by jailbreak-style role changes, not normal role descriptions
      const jailbreakRolePattern = /you\s+are\s+now\s+(?:a|an|in)\s+(?:new|different|unrestricted|evil|DAN|jailbr)/i;

      for (const file of skillFiles) {
        const isSecurity = isSecuritySkill(file);
        let inCodeBlock = false;

        for (let i = 0; i < file.lines.length; i++) {
          const line = file.lines[i];

          // Track code blocks
          if (line.trim().startsWith("```")) inCodeBlock = !inCodeBlock;

          const allPatterns = [...injectionPatterns, jailbreakRolePattern];
          for (const pattern of allPatterns) {
            if (pattern.test(line)) {
              // Demote severity for security docs, code blocks, or example lines
              const isExample = inCodeBlock
                || /^[\s]*[❌✅⚠️|>$#]/.test(line)
                || /example|detect|pattern|test/i.test(line)
                || isSecurity;

              diagnostics.push({
                severity: isExample ? "info" : "error",
                category: "skillSafety",
                rule: this.id,
                file: file.name,
                line: i + 1,
                message: `Potential injection vector in skill: "${line.trim().substring(0, 60)}"`,
                fix: isExample
                  ? "This appears to be a security example/documentation. Verify it's not executable."
                  : "This skill contains a prompt injection pattern. Do NOT install without careful review — it could override agent behavior, bypass security rules, or exfiltrate config.",
              });
            }
          }
        }
      }
      return diagnostics;
    },
  },
];
