# dev-tools/megalint/docs/ — Megalint Analysis & Proposals

Documentation for megalint rule management, audits, and proposals.

| Doc | What it is |
|-----|-----------|
| [RULES_AUDIT.md](RULES_AUDIT.md) | Deep dive audit of all ~116 rules — ratings, false positive risk, harm assessment |
| [RULES_AUDIT_COMPLETE.md](RULES_AUDIT_COMPLETE.md) | Extended rules analysis with OpenClaw-specific evaluation |
| [NEW_RULES_PROPOSAL.md](NEW_RULES_PROPOSAL.md) | 25 proposed behavioral rules derived from the system prompt analysis |
| [RULES_GUIDE.md](../RULES_GUIDE.md) | Full check inventory including all Home-Grow and directive import rules |

## Directive import rules (Home-Grow)

These 10 checks enforce the directive import system: agents use `## Imports` in AGENTS.md to pull shared directive files from `shared/directives/` instead of duplicating content inline. Toggle via `CHECK_*=0` in `apps/homegrow/rules.conf`.

| Rule | Flag | Severity | Description |
|------|------|----------|-------------|
| check_imports_section | CHECK_IMPORTS_SECTION | ERROR | AGENTS.md must have ## Imports section |
| check_imports_valid_paths | CHECK_IMPORTS_VALID_PATHS | ERROR | All import paths resolve to directive files |
| check_directives_exist | CHECK_DIRECTIVES_EXIST | ERROR | All 20 directive files present in shared/directives/ |
| check_imports_completeness | CHECK_IMPORTS_COMPLETENESS | WARN | Agent imports match manifest.conf requirements |
| check_imports_no_duplication | CHECK_IMPORTS_NO_DUPLICATION | WARN | No inline content duplicating imported directives |
| check_imports_boot_integration | CHECK_IMPORTS_BOOT_INTEGRATION | WARN | BOOT.md references imports/directives |
| check_imports_tools_dedup | CHECK_IMPORTS_TOOLS_DEDUP | WARN | TOOLS.md doesn't duplicate shared tool content |
| check_imports_user_dedup | CHECK_IMPORTS_USER_DEDUP | WARN | USER.md doesn't duplicate USER_CORE content |
| check_legacy_shared_files | CHECK_LEGACY_SHARED_FILES | WARN | Old monolithic shared files cleaned up |
| check_orphan_directives | CHECK_ORPHAN_DIRECTIVES | INFO | No directive files unused by any agent |

## Related

- Agent evaluation reports: [`reports/`](../../../reports/) (one per agent, with score progression)
- System prompt analysis: [`docs/`](../../../docs/) (Master Summary, AGI Audit, behavioral extractions)
- Prompt Hardener tutorials: [`prompt-hardener/docs/`](../prompt-hardener/docs/)
