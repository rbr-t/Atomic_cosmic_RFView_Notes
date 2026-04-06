# TKR Studios — Sub-Agent Architecture

This document describes the VS Code Copilot agent framework for the TKR Studios photo album creator.

## Architecture Overview

```
User Request
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│  t-ikia-t                                                   │  ◄── Intelligence synthesis, root-cause, truth validation
│  Transform → Information → Knowledge → Intelligence →       │
│  Action → Truth                                             │
└──────┬──────────────────────────────────────────────────────┘
       │  validates & escalates to
       ▼
┌─────────────────────────────────────────────────────────────┐
│  mission-compass                                            │  ◄── Goal integrity, three-horizon impact, POV shifts
│  Big-picture tracking · drift detection · realism-check     │
└──────┬──────────────────────────────────────────────────────┘
       │  course-corrects & directs
       ▼
┌─────────────────────────────────────────────────────────────┐
│  deep-specialist                                            │  ◄── Domain authority, anomaly detection, feedback loop
│  Engineering rigour · deep research · POV · PASS/REJECT     │
└──────┬──────────────────────────────────────────────────────┘
       │  validates & feeds back to all layers
       ▼
┌─────────────────────┐
│  orchestrator       │  ◄── Start here for multi-domain tasks
│  .agent.md          │
└──────┬──────────────┘
       │  delegates to
       ▼
┌──────────────────────────────────────────────────────────────┐
│                     Specialist Sub-Agents                     │
├──────────────────┬───────────────────────────────────────────┤
│ layout-composer  │  Canvas, templates, page layouts          │
│ ai-studio        │  AI generation, effects, image quality    │
│ import-pipeline  │  PDF/HTML import, confidence scoring      │
│ export-preflight │  PDF export, DPI checks, print costs      │
│ mobile-responsive│  Touch UI, CSS breakpoints, phone layout  │
│ state-snapshot   │  Auto-save, undo/redo, snapshots          │
│ security-guardian│  OWASP audits, hardening, threat fixes    │
│ legal-guardian   │  Copyright, T&C, privacy law compliance   │
│ pricing-architect│  Pricing, revenue, tax, payment gateways  │
│ localisation-guardian│ Translations, i18n, native UX, RTL    │
└──────────────────┴───────────────────────────────────────────┘

Legal Sub-Agents (invoked by legal-guardian only):
┌──────────────────┬───────────────────────────────────────────┐
│ copyright-scanner│  IP scanning, AI licence, DMCA            │
│ terms-drafter    │  T&C, Privacy Policy, EULA drafting       │
│ compliance-checker│ GDPR, CCPA, India DPDP audit matrix      │
└──────────────────┴───────────────────────────────────────────┘
Orbital Agent (observes all layers, not in the vertical chain):
┌──────────────────┬───────────────────────────────────────────┤
│ rubix            │  Cube mapping, shortest-path solving,     │
│                  │  F/M/L path proposals, POV influence,     │
│                  │  self-tracking solve log                  │
└──────────────────┴───────────────────────────────────────────┘```

## Agent → App Domain Map

| Agent File | Primary App Files | Shiny Modules |
|-----------|------------------|---------------|
| `orchestrator.agent.md` | `app_modular.R`, `R/config.R`, `R/state_management.R` | All |
| `layout-composer.agent.md` | `R/layout_composer.R`, `R/layout_templates.R`, `R/layer_utils.R` | `module_editor`, `module_template`, `module_studio` |
| `ai-studio.agent.md` | `R/ai_services.R`, `R/advanced_ai.R`, `R/bg_removal.R`, `R/image_effects.R` | `module_ai_editor`, `module_generate`, `module_ai_config` |
| `import-pipeline.agent.md` | `R/import_*.R` (8 files) | `module_import` |
| `export-preflight.agent.md` | `R/print_effects.R`, `R/print_service_api.R`, `R/export_metadata.R` | `module_export`, `module_print_service`, `module_payment` |
| `mobile-responsive.agent.md` | `R/mobile_responsive_new.R`, `R/mobile_responsive.R`, `www/` | `module_editor`, `module_photolibrary`, `module_landing` |
| `state-snapshot.agent.md` | `R/state_management.R`, `R/persistence.R`, `R/project_snapshots.R` | `module_snapshots`, `module_project` |
| `security-guardian.agent.md` | `R/agents/security_agent.R`, `R/validation.R`, `R/modules/module_auth.R`, `R/cloud_storage_api.R`, `R/api.R` | `module_auth` |
| `legal-guardian.agent.md` | `R/cloud_storage_api.R`, `R/ai_services.R`, `.github/skills/legal-document/` | — |
| `copyright-scanner.agent.md` *(sub-agent)* | All `R/`, `www/`, `python/`, `docs/` | — |
| `terms-drafter.agent.md` *(sub-agent)* | `.github/skills/legal-document/assets/` | — |
| `compliance-checker.agent.md` *(sub-agent)* | `R/agents/compliance_agent.R`, `logs/compliance_violations.jsonl` | — |
| `pricing-architect.agent.md` | `R/pricing_config.R`, `R/print_service_api.R`, `R/modules/module_payment.R`, `R/config.R`, `R/i18n.R` | `module_payment`, `module_print_service` |
| `localisation-guardian.agent.md` | `R/i18n.R`, `R/modules/module_language.R`, all modules with `data-i18n` | all modules |
| `t-ikia-t.agent.md` | `logs/`, `R/agents/`, any file fed to it | all — read-only |
| `mission-compass.agent.md` | all agent outputs, `agent_state.json`, `logs/` | all — read-only |
| `deep-specialist.agent.md` | any file, function, algorithm, or agent output fed to it | all — read-only |
| `rubix.agent.md` *(orbital)* | all agent outputs, `agent_state.json` (`rubix_solve_log` key) | all — read-only |

## Background Agent Infrastructure (R/agents/)

These R6 agents run autonomously at runtime (not VS Code agents):

| R File | Purpose | Log |
|--------|---------|-----|
| `agent_manager.R` | Orchestrates all runtime agents | — |
| `event_bus.R` | Pub/sub messaging | `logs/event_bus.jsonl` |
| `state_store.R` | JSON key-value persistence | `agent_state.json` |
| `security_agent.R` | XSS/injection/upload threat detection | `logs/security_threats.jsonl` |
| `compliance_agent.R` | GDPR/CCPA/COPPA checks | `logs/compliance_violations.jsonl` |
| `app_diagnostics_agent.R` | Memory/disk/session health monitoring | — |
| `mcp_client.R` | LLM bridge for agents via MCP protocol | — |

**These files should NOT be edited by specialist sub-agents.** Changes require a dedicated security review.

## Runtime Guardrails

Hooks provide a deterministic guardrail layer under the agent, instruction, and skill system.

- `.github/hooks/01-session-start.json` injects current repo role, branch, and clean/dirty state at session start.
- `.github/hooks/02-pretool-git-safety.json` blocks destructive git commands and asks before higher-risk git operations.
- `.github/hooks/03-posttool-customization-validate.json` validates changed customization files after tool use.

Use hooks for enforcement and automation, not for reasoning or architectural judgement.

## Skills

| Skill | Trigger |
|-------|---------|
| `.github/skills/mobile-responsive/SKILL.md` | Mobile UI implementation or audit |
| `.github/skills/rich-document/SKILL.md` | HTML/PDF document, TOC, tabs, day/night toggle, colour-blind safe, bibliography |
| `.github/skills/legal-document/SKILL.md` | Terms & Conditions, Privacy Policy, EULA, legal HTML/PDF, GDPR/CCPA/DPDP clauses |
| `R/pricing_config.R` | Pricing config skeleton — tier definitions, regional prices, tax rates, gateway map, disclaimers |

## How to Use

### Single-domain task
Use the specialist agent directly in the VS Code agent picker:
- "Fix the canvas drag handle on iPad" → `mobile-responsive`
- "Add a new 3-photo template" → `layout-composer`
- "Debug low-confidence import scores" → `import-pipeline`
- "Add full Hindi translation" → `localisation-guardian`
- "Why is this error happening?" → `t-ikia-t`
- "Synthesise these logs into a root cause" → `t-ikia-t`

### Multi-domain task  
Use `orchestrator` and describe the full feature; it will delegate to the right specialists:
- "Add AI-powered layout suggestions that also work on mobile"
- "Implement auto-save that snapshots before each AI effect"

### Background runtime agents
Start via: `source("scripts/start_agents.R")`  
Stop via: `agent_manager$stop()`  
Status: `agent_manager$status()`

## Pricing Domain Trigger Examples

| User Request | Agent | Action |
|---|---|---|
| "Add INR pricing for Indian users" | `pricing-architect` | Add IN region config, GST display logic |
| "Set up subscription tiers" | `pricing-architect` | Define Free/Starter/Creator/Pro in `pricing_config.R` |
| "Integrate Razorpay for India" | `pricing-architect` + `security-guardian` | Add gateway config + credential handling |
| "Show VAT-inclusive prices in EU" | `pricing-architect` | Wire `price_includes_tax` flag in checkout UI |
| "What's our margin on the Creator plan?" | `pricing-architect` | AI cost margin worksheet |
| "Add pricing disclaimers to checkout" | `pricing-architect` | Inject `get_checkout_disclaimer()` into UI |
| "Draft a refund policy" | `pricing-architect` → `legal-guardian` | Pricing policy HTML with regional terms |
| "Validate DALL·E 3 is safe for free tier" | `pricing-architect` | API cost vs. plan revenue analysis |

## Legal Domain Trigger Examples

| User Request | Agent | Action |
|---|---|---|
| "Review the app for copyright issues" | `legal-guardian` → `copyright-scanner` | Scan codebase + AI licences |
| "Draft terms and conditions for the app" | `legal-guardian` → `terms-drafter` | Generate T&C HTML using clause library |
| "Check GDPR compliance" | `legal-guardian` → `compliance-checker` | Produce compliance matrix |
| "Are we CCPA compliant?" | `legal-guardian` → `compliance-checker` | Produce California rights gap analysis |
| "What copyright applies to AI-generated images?" | `legal-guardian` | AI copyright law reference lookup |
| "We're launching in India — what do we need?" | `legal-guardian` → `compliance-checker` | DPDP Act checklist |
| "The Stability AI terms changed — what's impacted?" | `legal-guardian` → `copyright-scanner` | AI provider licence diff |

## Suggested Future Agents

Based on identified gaps in the current app:

| Future Agent | Trigger | App Gap |
|-------------|---------|---------|
| `layout-suggestion` | "suggest layout for photos" | No auto-layout recommendation |
| `image-quality` | "check photo quality before export" | No quality gate on upload |
| `prompt-coach` | "enhance my generation prompt" | Prompts not enriched before Stability AI |
| `print-cost-estimator` | "estimate print cost" | Print costs not reactively updated |

## Known Security Issues (tracked by `security-guardian`)

| Severity | OWASP | File | Issue |
|----------|-------|------|-------|
| ~~Critical~~ | ~~A01~~ | ~~`module_auth.R`~~ | ~~`AUTH_BYPASS=TRUE` allows unauthenticated admin access~~ — **Fixed** (startup guard in `app_modular.R` blocks bypass outside `SHINY_ENV=development`) |
| ~~High~~ | ~~A02~~ | ~~`cloud_storage_api.R`~~ | ~~OAuth tokens stored in plaintext `.cloud_tokens.json`~~ — **Fixed** (`.cloud_tokens.json` added to `.gitignore`; `save_tokens()`/`load_tokens()` encrypt with `openssl` when `TOKEN_ENCRYPTION_KEY` is set) |
| ~~High~~ | ~~A07~~ | ~~`module_auth.R`~~ | ~~Firebase REST token verification background-only; admin role granted before verification~~ — **Fixed** (role defaults to `"user"`; admin role granted only after REST verification confirms admin email) |
| ~~Medium~~ | ~~A03~~ | ~~`api.R`~~ | ~~`add_photo()` and `load_project()` accept raw file paths without sanitisation~~ — **Fixed** (`load_project()` whitelists `[a-zA-Z0-9_-]` names; `add_photo()` validates extension + `normalizePath()`) |
| ~~Medium~~ | ~~A05~~ | ~~`module_auth.R`~~ | ~~`message()` calls expose raw Firebase API error bodies~~ — **Fixed** (all three `message()` calls replaced with fixed generic strings) |
| ~~Medium~~ | ~~A10~~ | ~~`ai_services.R`~~ | ~~SSRF via API-response URL downloads and HuggingFace model URL~~ — **Fixed** (`.validate_download_url()`, `.validate_hf_model_id()`, `.validate_upload_path()`, `timeout()`) |
