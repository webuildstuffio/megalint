/* ─── Runtime Config Rules (13%) ─── */
/* Checks clawdbot.json / openclaw.json for security misconfigurations */

import { Rule, Diagnostic } from "../types";

/**
 * Try to parse JSON config from a FileInfo that represents clawdbot.json / openclaw.json
 */
function getConfigJSON(files: { name: string; content: string }[]): { json: Record<string, unknown>; fileName: string } | null {
  const configFile = files.find(
    (f) => f.name === "clawdbot.json" || f.name === "openclaw.json" || f.name === ".clawdbot/clawdbot.json"
  );
  if (!configFile) return null;
  try {
    return { json: JSON.parse(configFile.content), fileName: configFile.name };
  } catch {
    return null;
  }
}

function getNestedValue(obj: Record<string, unknown>, path: string): unknown {
  const parts = path.split(".");
  let current: unknown = obj;
  for (const part of parts) {
    if (current == null || typeof current !== "object") return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}

export const runtimeRules: Rule[] = [
  {
    id: "runtime/config-exists",
    category: "runtime",
    severity: "info",
    description: "Agent runtime config file should exist for full analysis",
    check(files) {
      const configFile = files.find(
        (f) => f.name === "clawdbot.json" || f.name === "openclaw.json" || f.name === ".clawdbot/clawdbot.json"
      );
      if (!configFile) {
        return [{
          severity: "info",
          category: "runtime",
          rule: this.id,
          file: "(workspace)",
          message: "No runtime config (clawdbot.json / openclaw.json) found. Runtime checks skipped.",
          fix: "If using Clawdbot/OpenClaw, ensure clawdbot.json exists in ~/.clawdbot/ or project root.",
        }];
      }
      return [];
    },
  },

  {
    id: "runtime/gateway-bind",
    category: "runtime",
    severity: "error",
    description: "Gateway must bind to loopback (localhost) only",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const bind = getNestedValue(config.json, "gateway.bind") as string | undefined;
      if (bind && !["loopback", "localhost", "127.0.0.1", "::1"].includes(bind)) {
        return [{
          severity: "error",
          category: "runtime",
          rule: this.id,
          file: config.fileName,
          message: `Gateway bind is "${bind}" — exposes agent to the network. Must be loopback.`,
          fix: 'Set gateway.bind to "loopback" or remove the key (default is loopback).',
        }];
      }
      return [];
    },
  },

  {
    id: "runtime/auth-mode",
    category: "runtime",
    severity: "error",
    description: "Gateway authentication must be enabled",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const authMode = getNestedValue(config.json, "gateway.auth.mode") as string | undefined;
      if (authMode && ["off", "none"].includes(authMode)) {
        return [{
          severity: "error",
          category: "runtime",
          rule: this.id,
          file: config.fileName,
          message: `Auth mode is "${authMode}" — anyone who can reach the gateway can control your agent.`,
          fix: 'Set gateway.auth.mode to "token" and configure a strong token.',
        }];
      }
      return [];
    },
  },

  {
    id: "runtime/token-strength",
    category: "runtime",
    severity: "warning",
    description: "Gateway auth token should be at least 32 characters",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const authMode = getNestedValue(config.json, "gateway.auth.mode") as string | undefined;
      if (authMode === "password") return []; // Don't judge password length

      const token = getNestedValue(config.json, "gateway.auth.token") as string | undefined;
      if (token) {
        if (token.length < 16) {
          return [{
            severity: "error",
            category: "runtime",
            rule: this.id,
            file: config.fileName,
            message: `Auth token is only ${token.length} characters — vulnerable to brute-force.`,
            fix: "Use a token of at least 32 characters. Generate one with: openssl rand -hex 32",
          }];
        }
        if (token.length < 32) {
          return [{
            severity: "warning",
            category: "runtime",
            rule: this.id,
            file: config.fileName,
            message: `Auth token is ${token.length} characters — consider using 32+.`,
            fix: "Generate a stronger token: openssl rand -hex 32",
          }];
        }
      }
      return [];
    },
  },

  {
    id: "runtime/dm-policy",
    category: "runtime",
    severity: "warning",
    description: "Open DM policy should have allowFrom restrictions",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const diagnostics: Diagnostic[] = [];

      const channels = getNestedValue(config.json, "channels") as Record<string, unknown> | undefined;
      if (!channels || typeof channels !== "object") return [];

      for (const [name, channelConfig] of Object.entries(channels)) {
        if (!channelConfig || typeof channelConfig !== "object") continue;
        const ch = channelConfig as Record<string, unknown>;
        const dmPolicy = ch.dmPolicy as string | undefined;
        const allowFrom = ch.allowFrom as unknown[] | undefined;

        if (dmPolicy === "open" && (!allowFrom || allowFrom.length === 0)) {
          diagnostics.push({
            severity: "warning",
            category: "runtime",
            rule: this.id,
            file: config.fileName,
            message: `Channel "${name}": DM policy is "open" with no allowFrom — anyone can command your agent.`,
            fix: `Add allowFrom with authorized user IDs, or set dmPolicy to "pairing".`,
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "runtime/group-policy",
    category: "runtime",
    severity: "warning",
    description: "Group policy should use allowlist",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const diagnostics: Diagnostic[] = [];

      const channels = getNestedValue(config.json, "channels") as Record<string, unknown> | undefined;
      if (!channels || typeof channels !== "object") return [];

      for (const [name, channelConfig] of Object.entries(channels)) {
        if (!channelConfig || typeof channelConfig !== "object") continue;
        const ch = channelConfig as Record<string, unknown>;
        const groupPolicy = ch.groupPolicy as string | undefined;

        if (groupPolicy && ["open", "any"].includes(groupPolicy)) {
          diagnostics.push({
            severity: "warning",
            category: "runtime",
            rule: this.id,
            file: config.fileName,
            message: `Channel "${name}": Group policy is "${groupPolicy}" — any group can trigger your agent.`,
            fix: 'Set groupPolicy to "allowlist" and define allowed groups.',
          });
        }
      }
      return diagnostics;
    },
  },

  {
    id: "runtime/config-secrets",
    category: "runtime",
    severity: "warning",
    description: "Config should use env var references instead of plaintext secrets",
    check(files) {
      const config = getConfigJSON(files);
      if (!config) return [];
      const diagnostics: Diagnostic[] = [];

      const sensitiveKeys = ["password", "secret", "apikey", "api_key", "privatekey", "private_key", "token"];

      const ruleId = this.id;
      const fileName = config.fileName;

      // Paths where secrets are defined (not referenced) — skip these
      const envDefinitionPrefixes = ["env.vars", "env.secrets"];

      function scanObject(obj: unknown, objPath: string) {
        if (!obj || typeof obj !== "object") return;
        // Skip env var definition sections entirely
        if (envDefinitionPrefixes.some((p) => objPath.startsWith(p))) return;
        for (const [key, value] of Object.entries(obj as Record<string, unknown>)) {
          const currentPath = objPath ? `${objPath}.${key}` : key;
          // Skip env var definition sections
          if (envDefinitionPrefixes.some((p) => currentPath.startsWith(p))) continue;
          if (typeof value === "string" && value.length > 0 && !value.startsWith("$")) {
            if (sensitiveKeys.some((sk) => key.toLowerCase().includes(sk))) {
              // Skip if it looks like a mode value (e.g., "token" for auth.mode)
              if (["token", "password", "off", "none", "pairing", "allowlist", "open"].includes(value)) continue;
              diagnostics.push({
                severity: "warning",
                category: "runtime",
                rule: ruleId,
                file: fileName,
                message: `Plaintext secret at "${currentPath}" — use environment variable reference instead.`,
                fix: `Replace with "\${${key.toUpperCase()}}" and set the env var.`,
              });
            }
          } else if (typeof value === "object") {
            scanObject(value, currentPath);
          }
        }
      }

      scanObject(config.json, "");
      return diagnostics;
    },
  },
];
