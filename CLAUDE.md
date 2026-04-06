# CLAUDE.md — RF Engineering Platform: Session Context

> This file is read automatically at the start of every AI session.
> It provides ground truth about what this repository is, what is built, what is pending, and how to work here.
> Last updated: 2026-04-04 (local hook guardrail overlay and validator hardening synced)

---

## 1. What This Repository Is

**Repository:** `Atomic_cosmic_RFView_Notes` (GitHub: rbr-t/Atomic_cosmic_RFView_Notes)

A multi-component **RF Engineering platform** combining:
- An AI-augmented R/Shiny Power Amplifier (PA) Design Application
- An interactive RF education document (Atomic → Cosmic scale)
- A live PA Design Reference Manual (6 chapters)
- A standalone RF CAD layout tool
- An Infineon (IFX) activity dashboard
- A general-purpose web page knitter utility

**Domain:** RF/microwave engineering — Power Amplifiers, GaN/LDMOS/SiC devices, load-pull, S-parameters, matching networks, Doherty architecture, MCP simulation integration (ADS/AWR).

**Primary language:** R (Shiny, R6, RMarkdown) + JavaScript (Konva.js) + Python (utilities) + SQL (PostgreSQL schema) + YAML (config).

---

## 2. Repository Structure

```
Atomic_cosmic_RFView_Notes/
├── .github/
│   ├── AGENTS.md                   ← Repo-local agent architecture + runtime guardrails
│   ├── hooks/
│   │   ├── 01-session-start.json   ← Session context injection
│   │   ├── 02-pretool-git-safety.json ← Destructive git guardrail
│   │   ├── 03-posttool-customization-validate.json ← Hook/customization validator
│   │   └── scripts/                ← Python hook implementations for local overlay
│   ├── agents/                     ← Repo-local specialist agent definitions
│   ├── instructions/               ← Repo guidance overlays
│   └── skills/                     ← Repo workflow skills and assets
│
├── PA design App/                  ← MAIN APP (R/Shiny, ~85% complete)
│   ├── R/
│   │   ├── app.R                   ← Entry point
│   │   ├── ui.R                    ← Dashboard UI (6 design flow tabs)
│   │   ├── server.R                ← Thin orchestrator
│   │   ├── global.R                ← Libraries, DB init, manager init
│   │   └── modules/
│   │       ├── calculations/       ← PURE functions (no Shiny deps) ← CRITICAL PATTERN
│   │       │   ├── calc_pa_lineup.R
│   │       │   ├── calc_guardrails.R
│   │       │   ├── calc_loss_curves.R
│   │       │   ├── calc_freq_planning.R
│   │       │   ├── calc_link_budget.R
│   │       │   ├── calc_rf_tools.R
│   │       │   └── calc_transistor_sizing.R  ← NEW: Ropt, gate width, Doherty sizing, matching
│   │       ├── server/             ← Shiny reactivity layer (20+ modules)
│   │       └── rf_tools/           ← LP/SP parsers
│   ├── core/
│   │   ├── ai_agents/
│   │   │   ├── base_agent.R        ← R6 base class — ALL agents extend this
│   │   │   └── agent_manager.R     ← Multi-agent coordinator
│   │   ├── project_mgmt/project_manager.R
│   │   ├── data_mgmt/data_manager.R
│   │   ├── security/auth_manager.R ← RBAC (Admin/Designer/Viewer)
│   │   ├── state_config/config_manager.R
│   │   └── tagging_metadata/tag_manager.R
│   ├── plugins/rf_pa_design/agents/
│   │   └── theory_agent.R          ← ✅ ONLY IMPLEMENTED AGENT
│   ├── www/
│   │   ├── js/
│   │   │   ├── pa_lineup_canvas.js  ← 7,941 lines — Konva.js PA topology designer
│   │   │   ├── rf_canvas.js         ← RF CAD 2D layout
│   │   │   └── rf_calc_lib.js       ← Standalone RF calculator
│   │   └── css/
│   │       ├── pa_lineup.css        ← Dark theme, accent #ff7f11
│   │       └── custom.css
│   ├── config/
│   │   ├── app_config.yaml          ← Feature flags, AI config, MCP servers
│   │   └── technology_guardrails.yaml ← GaN/SiC specs
│   ├── database/
│   │   └── init.sql                 ← PostgreSQL schema + demo data
│   ├── data/kb/ampleon/devices.json ← 50+ LDMOS/GaN devices
│   ├── Dockerfile
│   ├── docker-compose.yml           ← 4 services: app, postgres, chroma, pgadmin
│   └── App_ology/                   ← Design philosophy documentation (10 subdirs)
│
├── Atomic_Cosmic_RFView_Project/    ← ✅ 100% COMPLETE — RF education RMarkdown
│   ├── Atomic_Cosmic_RFView.Rmd     ← 80 KB source
│   └── Atomic_Cosmic_RFView.html    ← 4.2 MB rendered output
│
├── PA_Design_Reference_Manual/      ← 🚧 35% — Live manual (Ch.1 done, 2-6 WIP)
│   ├── Chapters/
│   │   ├── Chapter_01_Transistor_Fundamentals.Rmd  ← ✅ COMPLETE
│   │   ├── Chapter_02_Load_Pull.Rmd                ← 🚧
│   │   ├── Chapter_03_Linearization.Rmd            ← 🚧
│   │   ├── Chapter_04_Efficiency.Rmd               ← 🚧
│   │   ├── Chapter_05_Advanced_Techniques.Rmd      ← 🚧
│   │   └── Chapter_06_Lessons_Learned.Rmd          ← 🚧
│   ├── Data_Extraction/Tx_Baseline/ ← IFX project CSV + markdown data
│   └── RF_Engg_books/               ← 30+ reference PDFs (Pozar, Balanis, etc.)
│
├── RF_CAD_Tool/                     ← 🚧 60% — Standalone RF layout tool
├── Web_page_knitter/                ← ✅ 95% — Doc aggregator (multi-format output)
├── IFX_2022_2025/                   ← ✅ 100% — Infineon activity dashboard
├── fix_bom.py                       ← Utility: remove UTF-8 BOM from R files
└── references.bib                   ← Shared bibliography
```

---

## 3. Completion Status

| Component | Complete | Notes |
|---|---|---|
| PA Design App — Core | 92% | Production-ready, Docker-deployable |
| 4.2 Lineup Calculator | 95% | Physics-correct Ropt, Doherty PAE backoff, topology-aware gain distribution |
| PA Lineup Canvas (Konva.js) | 100% | 7,941 lines, fully functional |
| Spec-Driven Design (System → Stage) | 100% | Phases 1+2 complete: technology selection, gain dist, power cascade |
| Transistor Design Level (Stage → Device) | 70% | calc_transistor_sizing.R + server_transistor_design.R LIVE |
| Calculation Engines | 100% | 7 pure-function files: calc_pa_lineup, guardrails, loss_curves, freq_planning, link_budget, rf_tools, transistor_sizing |
| Theory Agent (AI) | 100% | LLM + KB, mock fallback without API key |
| Architecture/Simulation/Layout/Measurement/Debug/Doc/Strategy Agents | 15% | .agent.md + .R files created; LLM bodies are stubs; not wired to server.R |
| Device Portfolio KB | 100% | 50+ devices in Chroma vector DB |
| Crawl4AI KB Ingestion Pipeline | 35% | Guarded pilot scaffold added (allowlist, robots, provenance, validation gate) |
| Local Hook Guardrail Overlay | 100% | 3 hooks live: session context, git safety, customization validation |
| Hook Validator Hardening | 100% | Naming, ordering, script existence, duplicate coverage, untracked-file detection |
| Load-Pull + S-Param Viewers | 100% | Parsers + Smith chart |
| RF CAD Tool | 60% | Basic layout, no advanced routing |
| PA Reference Manual Ch.1 | 100% | Transistor fundamentals + IFX data |
| PA Reference Manual Ch.2–6 | 10% | Outline + data only |
| Atomic Cosmic RFView | 100% | Rendered HTML, 6 topics |
| IFX Dashboard | 100% | Portable, relative paths |
| Web Page Knitter | 95% | Multi-format doc aggregator |
| Docker Deployment | 100% | 4-service compose ready |
| Unit Tests | 5% | Only 1 stub test file exists — GAP |

---

## 4. Architecture Principles (DO NOT VIOLATE)

### 4.1 Calculation engines are PURE functions
Files under `R/modules/calculations/` must have **zero Shiny dependencies** (`input$`, `output$`, `reactive()` etc.). They are called by server modules but are independently testable. This is the most important architectural rule.

### 4.2 Agent pattern — extend base_agent.R
All AI agents are R6 classes extending `core/ai_agents/base_agent.R`. The **only complete example** is `plugins/rf_pa_design/agents/theory_agent.R` (203 lines). When creating new agents, mirror this pattern exactly.

### 4.3 Database with graceful demo-mode fallback
The app runs without PostgreSQL via `DEMO_MODE` flag in `app_config.yaml`. Never assume the DB is always available.

### 4.4 Canvas JS ↔ Shiny protocol
`pa_lineup_canvas.js` and Shiny communicate via `Shiny.setInputValue()` / `session$sendCustomMessage()`. Do not bypass this protocol.

### 4.5 MCP integration is DISABLED by default
`config/app_config.yaml` has `feature_flags.mcp_integration: false`. ADS/AWR/VNA server configs exist but are not activated. Do not assume simulation tools are available.

---

## 5. Key Configuration

**`PA design App/config/app_config.yaml`** (critical values):
```yaml
app:
  name: "RF PA Design"
  domain: rf_pa_design
  theme: dark
  accent_color: "#ff7f11"

ai_agents:
  model: gpt-4
  confidence_threshold: 0.7
  mock_without_key: true        # ← app works without OpenAI key

feature_flags:
  ml_predictions: true
  mcp_integration: false        # ← ADS/AWR disabled
  chatbot: true
  real_time_collaboration: false

security:
  auth_enabled: false           # ← dev mode; enable for production
  session_timeout: 3600
```

---

## 6. What Needs to Be Done (Ordered by Priority)

### Priority 1 — Implement remaining 6 AI agents
Each follows `theory_agent.R` pattern. Agents needed:
1. **architecture-agent** — topology selection (Doherty/balanced/push-pull/Chireix)
2. **simulation-agent** — ADS/AWR MCP bridge + result parsing
3. **layout-agent** — PCB DRC, substrate constraints, via planning
4. **measurement-agent** — lab instrument interface, Touchstone import
5. **debug-agent** — sim vs. measurement anomaly detection
6. **documentation-agent** — auto-generate design reports from project state
7. **strategy-agent** — multi-agent orchestration (last, depends on all above)

### Priority 2 — PA Reference Manual Chapters 2–6
Data is available in `Data_Extraction/Tx_Baseline/`. Use `shared_resources/templates/chapter_template.Rmd`. Topics:
- Ch.2: Load-Pull contours and optimization
- Ch.3: Linearization (DPD, predistortion)
- Ch.4: Efficiency (Doherty, ET/EER)
- Ch.5: Advanced techniques
- Ch.6: Lessons learned from IFX projects

### Priority 3 — Unit tests for calculation engines
Zero tests exist for: `calc_pa_lineup.R`, `calc_guardrails.R`, `calc_loss_curves.R`, `calc_freq_planning.R`, `calc_link_budget.R`, `calc_rf_tools.R`. This is the highest-risk gap.

### Priority 4 — RF CAD Tool advanced features
- Auto-routing
- EM constraint warnings
- Bidirectional link with PA lineup canvas

### Priority 5 — Production hardening
- Enable `auth_enabled: true` + set API keys via environment variables
- Performance profiling for large LP file batches
- Load testing for concurrent users
- Enable `mcp_integration: true` + verify ADS/AWR access

### Priority 6 — Crawl4AI ingestion hardening (new)
- Extend extraction beyond seeded values into robust structured scraping (CSS/XPath + PDF metadata)
- Add unit tests for parser and validation steps in `tools/crawl4ai_kb_ingestion/`
- Add CI guard to block unsafe domains or missing provenance fields
- Add manual approval workflow before `--apply` merges into `data/kb/*/devices.json`

---

## 7. Database Schema (PostgreSQL)

```sql
projects    (uuid, name, architecture_type, topology, frequency, targets, phase, status, tags, metadata)
datasets    (project_id, name, type, format, file_path, metadata)
tags        (entity_type, entity_id, tag_name, tag_value)
users       (username, email, password_hash, role: admin|designer|viewer)
agent_logs  (agent_name, project_id, action, input_data, output_data, confidence, execution_time_ms)
simulations (project_id, name, tool, parameters, results, status)
```

Demo data: 3 sample projects (5G PA, WiFi 6E, Sub-6 GaN).

---

## 8. Docker Services

```yaml
app:      port 3838  ← Shiny application
postgres: port 5432  ← PostgreSQL
chroma:   port 8000  ← Vector DB for knowledge base
pgadmin:  port 5050  ← DB admin UI
```

Run: `docker-compose up -d` from `PA design App/`

---

## 9. Technology Reference

| Technology | Where Used |
|---|---|
| R / Shiny | App framework, all modules |
| R6 | AI agent classes |
| Konva.js | PA lineup canvas (7,941 lines), RF CAD canvas |
| Plotly | Interactive charts |
| PostgreSQL + DBI/pool | Project data persistence |
| Chroma (vector DB) | Knowledge base semantic search |
| OpenAI GPT-4 | AI agents (mock fallback available) |
| Docker Compose | Deployment |
| YAML | App config, technology guardrails |
| Touchstone (.s2p/.s3p) | S-parameter import |
| .lpcwave / .cst / .spl | Load-pull data import |

---

## 10. Working Guidelines for AI Sessions

1. **Read `app_config.yaml` before touching config** — feature flags control what's live
2. **Check `base_agent.R` before writing any agent code** — do not reinvent the base class
3. **Never add Shiny deps to `calculations/`** — pure functions only
4. **Run `fix_bom.py` if R files fail to parse on Windows** — BOM issue documented
5. **Demo mode is on by default** — app works without DB or API keys
6. **7 ZIP archives in root** — historical backups, do not unzip unless debugging a specific regression
7. **`App_ology/` directory** — read before making architectural decisions; documents design philosophy, boundary conditions, component library
8. **`PA_Design_Reference_Manual/RF_Engg_books/`** — 30+ reference PDFs; cite from these when writing technical content
9. **Crawl4AI runs must stay allowlist-only** — never crawl outside approved domains in seed catalog
10. **KB ingestion defaults to review mode** — generate artifacts first, apply only after human sign-off
11. **Local hooks are active under `.github/hooks/`** — use them as deterministic guardrails, not as a replacement for agent reasoning
12. **Atomic carries a local hook overlay, not the full global hook toolchain** — validator/test innovations originate in `Global_Agentic_Operating_System` and are propagated here selectively

---

## 11. Key Known Gaps (as of 2026-04-01 audit)

| Gap | Risk | Mitigation |
|---|---|---|
| No unit tests for calculation engines | HIGH — silent numeric errors possible | Write `tests/testthat/test_calc_transistor_sizing.R` first (has most risk) |
| 6 of 8 AI agents are LLM stubs | HIGH — core product functionality | Follow theory_agent.R pattern; `.agent.md` POV influence sections added |
| Transistor design → topology feedback loop | MEDIUM — Ropt<5Ω signals wrong topology | server_transistor_design.R emits topology_recheck_needed; architecture_agent needs listener |
| MCP simulation integration unverified | MEDIUM — ADS/AWR access not confirmed | Verify tool access before enabling flag |
| Auth disabled in dev config | MEDIUM — must enable before production | Set `auth_enabled: true` + env var secrets |
| Building block synthesis incomplete | MEDIUM — Phase 3+4 of spec-driven POC | Multi-stage support (3+ stages), other topologies, auto-fix on spec mismatch |
| Large LP file performance untested | LOW-MEDIUM | Profile before user testing |

---

## 11b. Open Issues / Known Gaps — Lineup Calculator Physics (Rubix M1)

| ID | Description | Status |
|---|---|---|
| FM-01 | Ropt formula used `(Vdd)²/(2P)` — missing Vknee, causing 15–23% error for GaN | **FIXED** — `(Vdd−Vknee)²/(2P)` + `_getVkneeFromTech()` in pa_lineup_canvas.js:4961 |
| FM-02 | Doherty PAE backoff used generic `η^0.8` degradation — not topology-aware | **FIXED** — Doherty: `η_bo = η_peak × (0.5 + 0.5×√ratio)`; conventional model retained |
| FM-03 | `recommend_technology()` returned display strings not YAML keys (`'Si LDMOS'` vs `'LDMOS'`) | **FIXED** — keys normalised: `LDMOS`, `GaN_SiC`, `InP`; guardrails lookup now resolves correctly |
| FM-04 | `distributeGain()` placed Doherty main/peak stages in series — wrong topology | **FIXED** — explicit parallel main/peak branch rendering with correct signal-flow |
| FM-05 | `spec_supply_voltage` default was 30 V — inconsistent with 28 V GaN standard | **FIXED** — ui.R default and JS `selectTechnology` vdd both corrected to 28 V |

---

## 12. Transistor Design Level— Implementation Notes (added 2026-04-01)

### What was added (Rubix M1 — 7 moves)

| File | Role |
|---|---|
| `R/modules/calculations/calc_transistor_sizing.R` | Pure-R transistor sizing: Ropt, gate width, Idq, Doherty sizing, L-match, combiner dimensions |
| `R/modules/server/server_transistor_design.R` | Shiny server: drives tab 5.1, decision log, spec compliance, markdown export |
| `R/ui.R` prod_transistor tab | Real UI replacing placeholder: topology selector, substrate inputs, device assumptions |
| `.github/agents/theory-agent.agent.md` | Created; POV influence: expose Ropt methods to server layer |
| `.github/agents/documentation-agent.agent.md` | POV influence: living decision journal via EventBus |
| `.github/agents/architecture-agent.agent.md` | POV influence: topology re-evaluation when Ropt < 5Ω |

### Key formulas implemented

```r
Ropt     = (Vdd − Vknee)² / (2 × Pout)          # Cripps optimum load
W_gate   = Pout / (power_density × PAE)           # Gate width sizing
Zt       = √(Ropt_main × 50Ω)                     # Doherty combiner impedance
len_mm   = λg/4 = c / (4 × f × √εr)              # Quarter-wave combiner length
Q        = √(Rmax/Rmin − 1)                        # L-match Q factor
L, C     = Standard L-match synthesis formulas     # Element values
```

### What the transistor design tab does NOT yet do (next steps)

1. **3+ stage support** — currently processes only transistor components from 2-stage Doherty
2. **Auto-fix on spec mismatch** — validation panel shows AMBER/RED but does not propose fixes
3. **topology re-evaluation listener** — architecture_agent does not yet respond to `topology_recheck_needed` event
4. **theory_agent delegation** — calc_transistor_sizing.R duplicates formulas from theory_agent.R; should delegate
5. **Unit tests** — `tests/testthat/test_calc_transistor_sizing.R` not yet written

---

## 13. Crawl4AI Guarded KB Ingestion Pilot (added 2026-04-03)

### Objective
Provide a compliant, auditable ingestion path to refresh vendor device libraries from public product pages and datasheet sources.

### Files added
- `PA design App/tools/crawl4ai_kb_ingestion/crawl_kb_pipeline.py`
- `PA design App/tools/crawl4ai_kb_ingestion/validate_kb_pipeline.py`
- `PA design App/tools/crawl4ai_kb_ingestion/configs/vendor_seed_catalog.yaml`
- `PA design App/tools/crawl4ai_kb_ingestion/requirements.txt`
- `PA design App/tools/crawl4ai_kb_ingestion/README.md`
- `PA design App/docs/guides/CRAWL4AI_KB_INGESTION_GUARDRAILS.md`
- `PA design App/THIRD_PARTY_NOTICES.md`
- `PA design App/.github/workflows/crawl4ai-kb-guard.yml`
- `PA design App/data/kb/nxp/devices.json`

### Safeguards implemented
1. Domain allowlist enforcement (`ampleon.com`, `nxp.com`)
2. robots.txt check enabled by default in crawler run config
3. Low crawl rate defaults (conservative delay + concurrency)
4. Per-record provenance (`url`, UTC time, HTTP status, SHA-256 hash)
5. Minimum schema validation gate before merge
6. Artifact-first workflow (`--apply` required for KB write)
7. Duplicate prevention by `device_id` at merge time
8. CI validator for allowlist, provenance fields, and latest artifact safety

### Pilot seed scope (verification)
- Ampleon: 2 products
- NXP: 2 products
- Discovery anchors:
  - `https://www.ampleon.com/products/mobile-broadband/1.4-2.2-ghz-transistors/#/`
  - `https://www.nxp.com/products/product-selector:PRODUCT-SELECTOR?category=c250_c65&page=1`

### Known limitations
- Dynamic vendor pages may return partial text without additional wait/selectors.
- Pilot currently focuses on safe scaffolding and verification artifacts, not full datasheet table extraction.
- Engineering review remains mandatory before production merges.
- Real Crawl4AI runs need Python 3.12/3.13 today; Python 3.14 is still blocked by dependency build compatibility on this Windows workstation.

---

## 13b. Local Hook Guardrail Overlay (added 2026-04-04)

### Objective
Protect repo-local Copilot customization files and git operations in Atomic without over-importing every global-only hook utility.

### Files added or updated
- `.github/AGENTS.md`
- `.github/hooks/README.md`
- `.github/hooks/01-session-start.json`
- `.github/hooks/02-pretool-git-safety.json`
- `.github/hooks/03-posttool-customization-validate.json`
- `.github/hooks/scripts/session_start_context.py`
- `.github/hooks/scripts/pretool_git_safety.py`
- `.github/hooks/scripts/posttool_customization_validate.py`

### Current local hook scope
1. Session-start repo context injection
2. Destructive-git blocking and higher-risk git confirmation requests
3. Post-tool customization validation for hook/config shape and wiring

### Validator hardening now present locally
1. Hook filename pattern enforcement (`NN-kebab-case.json`)
2. Supported event validation (`SessionStart`, `PreToolUse`, `PostToolUse`)
3. Referenced script existence checks under `.github/hooks/scripts/`
4. Duplicate event-script coverage detection across the hook suite
5. Unique and strictly increasing numeric hook prefix validation
6. Correct untracked-file detection via `git status --porcelain --untracked-files=all`

### Deliberate boundary
- Atomic does **not** currently carry the global-only propagation reminder hook.
- Atomic does **not** currently carry the global fixture runner or hook inventory helper.
- Global hook experiments and self-tests should land first in `Global_Agentic_Operating_System`, then be back-ported here only when they are useful locally.

---

## 14. Propagation Log

### 2026-04-06 — Cross-repo propagation from Atomic

| Item | Type | Propagated to | Notes |
|------|------|---------------|-------|
| `skills/legal-document/` | Skill (full folder + assets) | Global, Digital_twin, House | Richer replacement for `accessible-legal-documents`; includes HTML templates, GDPR/DPDP/CCPA references |
| `skills/mobile-responsive/` | Skill (adapted) | Global, Digital_twin, House | Domain-adapted per repo: generic Shiny (Global), ag-field canvas (Digital_twin), BOQ/budget tracker (House) |
| `agents/localisation-guardian.agent.md` | Agent (adapted) | Global, Digital_twin, House | Generalised for Global; ag measurement units for Digital_twin; construction cost/area units for House |
| `agents/legal-guardian.agent.md` | Agent (generalised) | Global | RF/ITAR-specific content stripped; universal legal risk framework retained |
| Hook validator `script_file` path bug | Bug fix (back-ported from Global) | Atomic | `path.parent.parent / relative_to(...)` → `repo_root = path.parents[2]; repo_root / script_path` |

### Non-propagated (deliberate)
| Item | Reason |
|------|--------|
| `instructions/locale-aware-formatting.instructions.md` | References `rv$lang` / `t()` / `R/i18n.R` — specific to album-editor app; not applicable to RF/ag/house apps without that i18n infrastructure |
| Hook `04-posttool-global-propagation-reminder.json` | Deliberately absent from Atomic per CLAUDE.md §13b boundary; originates in Global and back-ported selectively |
| RF-specific agents (theory, architecture, simulation, layout, measurement, debug, strategy, kb, etc.) | RF PA domain-specific; not applicable to other repos |

---

*This document was generated from a full T-IKIA-T codebase audit conducted on 2026-04-01. Update this file when major milestones are completed.*
