# PA Design App — RF Power Amplifier Design Platform

Professional-grade R/Shiny application for RF Power Amplifier (PA) design, equipped with AI-augmented calculation engines, interactive visualization tools, and MCP integration for circuit simulation.

---

## Quick Start

### Prerequisites
- **Docker & Docker Compose** (recommended)
- OR: **R 4.3+**, **PostgreSQL 14+**, **Node.js 16+**

### Run with Docker (Recommended)

```bash
cd "PA design App"
cp .env.example .env.local
docker-compose -f infra/docker/docker-compose.yml up -d
```

Access the app at **http://localhost:3838**

### Manual Setup

```bash
# 1. Install R dependencies
cd "PA design App"
Rscript -e "renv::restore()"

# 2. Initialize database
psql -U postgres -d pa_design_app -f database/01_schema.sql
psql -U postgres -d pa_design_app -f database/seeds/01_init.sql

# 3. Start application
Rscript -e "shiny::runApp('src/app.R', port=3838)"
```

---

## Features

### Core Capabilities
- **4.2 Lineup Calculator** — Physics-correct PA topology design with Ropt, Doherty PAE, gain distribution
- **Interactive Canvas** — Konva.js-powered PA topology editor with real-time visualization
- **Spec-Driven Design** — System → Stage → Device flow (Rubix M1: Transistor design level complete)
- **Load-Pull & S-Parameter Viewers** — Touchstone format support with Smith chart
- **Knowledge Base** — Searchable device portfolio (50+ LDMOS/GaN devices)

### AI Assistance
- **Theory Agent** — Physics consultation + device recommendations
- **6 Additional Agents** (Stub implementations ready for completion)
  - Architecture, Simulation, Layout, Measurement, Debug, Documentation, Strategy

### Production Ready
- ✅ Docker deployment (4 services: app, postgres, chroma, pgadmin)
- ✅ RBAC authentication framework (disabled by default)
- ✅ Comprehensive configuration management
- ✅ Graceful demo-mode fallback (no DB required)

---

## Project Structure

```
PA design App/
├── src/                          # Application source code
│   ├── app.R                     # Entry point
│   ├── ui.R                      # Dashboard UI (6 design tabs)
│   ├── server.R                  # Thin orchestrator
│   ├── global.R                  # Initialization & managers
│   ├── modules/
│   │   ├── calculations/         # PURE functions (no Shiny deps) ⭐
│   │   ├── server/               # Shiny reactivity layer
│   │   └── rf_tools/             # Parsers & utilities
│   ├── core/                     # Core managers (R6 classes)
│   ├── plugins/                  # Agent implementations
│   └── utils/                    # Helpers, KB loaders
├── assets/                       # Frontend assets
│   ├── js/                       # JavaScript modules
│   └── css/                      # Stylesheets
├── config/                       # Configuration files
│   ├── app_config.yaml           # Main config (env-variable based)
│   └── technology_guardrails.yaml # GaN/SiC specifications
├── database/                     # Database assets
│   ├── 01_schema.sql             # PostgreSQL schema
│   ├── seeds/                    # Initial data
│   └── migrations/               # (future)
├── data/                         # Application data
│   ├── kb/                       # Knowledge base (vector DB)
│   ├── sample-files/             # Load-pull sample data
│   ├── projects/                 # User projects (persistent)
│   ├── uploads/                  # Temporary uploads
│   └── cache/                    # Query results cache
├── tests/                        # Unit tests & fixtures
├── docs/                         # Documentation
│   ├── architecture/             # Design philosophy
│   ├── api-patterns/             # Code patterns
│   ├── decisions/                # ADR (Architecture Decision Records)
│   └── changelog/                # Historical session notes
├── infra/                        # Deployment & infrastructure
│   ├── docker/                   # Docker configuration
│   ├── k8s/                      # (future) Kubernetes manifests
│   └── scripts/                  # Maintenance scripts
├── .github/                      # GitHub Actions CI/CD
│   └── workflows/                # Automated tests & deployment
└── config files
    ├── .env.example              # Environment variables template
    ├── app_config.yaml           # Application configuration
    └── .gitignore                # Git exclusions
```

---

## Architecture Principles

### 1. **Pure Functions for Calculations** ⭐
- All files in `src/modules/calculations/` are **zero Shiny-dependency**
- Independently testable; called by server modules
- Example: `calc_pa_lineup.R`, `calc_transistor_sizing.R`

### 2. **R6-Based Agent Pattern**
All AI agents extend `core/ai_agents/base_agent.R`. Reference implementation: `theory_agent.R` (203 lines).

### 3. **Database Graceful Fallback**
App runs in **demo mode** without PostgreSQL via `DEMO_MODE` flag in app_config.yaml.

### 4. **Canvas ↔ Shiny Protocol**
JavaScript (Konva.js) communicates with Shiny via `Shiny.setInputValue()` / `session$sendCustomMessage()`.

### 5. **Configuration Hierarchy**
- `.env.local` (environment variables)
- `config/app_config.yaml` (runtime config with env variable substitution)
- Application defaults (in code)

---

## Configuration

### Environment Variables (`.env.local`)
```bash
APP_ENV=production
AUTH_ENABLED=true
DB_HOST=postgres.example.com
CHROMA_HOST=chroma.example.com
API_KEY_OPENAI=sk-...
```

### Feature Flags (`config/app_config.yaml`)
```yaml
feature_flags:
  enable_ml_predictions: true
  enable_mcp_integration: false      # ADS/AWR disabled by default
  enable_chatbot: true
  enable_real_time_collaboration: false
```

See `.env.example` and `config/app_config.yaml` for complete reference.

---

## Development

### Running Tests
```bash
cd "PA design App"
Rscript -e "testthat::test_dir('tests/testthat')"
```

### Code Quality
```bash
# Lint R code
Rscript -e "lintr::lint_dir('src')"

# Code coverage
Rscript -e "covr::package_coverage('src')"
```

### Local Development with Docker
```bash
docker-compose -f infra/docker/docker-compose.yml up -d
# Make code changes in src/ (hot reload enabled)
# View logs: docker-compose logs -f app
```

---

## Production Deployment

### Prerequisites
- CI/CD secrets configured (GitHub Actions)
  - `DOCKER_USERNAME`, `DOCKER_PASSWORD`
  - `DEPLOY_KEY`, `DEPLOY_HOST`, `DEPLOY_USER`

### Deploy
```bash
# On main branch push or tag
git push origin main
# Automated workflow: test → build → deploy
```

### Health Checks
```bash
curl http://your-host:3838
docker-compose exec app curl http://localhost:3838
```

---

## Known Gaps & Next Steps

| Priority | Item | Status |
|---|---|---|
| **P1** | Implement 6 remaining AI agents | 15% (stubs created) |
| **P2** | Unit tests for calculation engines | 5% (critical gap) |
| **P3** | PA Reference Manual Chapters 2–6 | 35% |
| **P4** | Enable MCP integration (ADS/AWR) | Disabled by default |
| **P5** | Production hardening (auth, secrets) | Ready to enable |

See `docs/decisions/IMPLEMENTATION_ROADMAP.md` for details.

---

## References

- **Architecture Philosophy**: `docs/architecture/01_App_philosophy`
- **Knowledge Base**: `data/kb/ampleon/devices.json` (50+ devices)
- **RF Books**: `docs/architecture/RF_Engg_books/` (30+ PDFs)
- **IFX Data**: `PA_Design_Reference_Manual/Data_Extraction/`

---

## Support & Contributing

- **Issues**: GitHub Issues (use `[bug]`, `[feature]`, `[docs]` labels)
- **Code Review**: Pull requests to develop branch
- **Questions**: See `docs/` directory for architecture, API patterns, decisions

---

## License

[Your License Here]

---

**Last Updated**: 2026-04-02
**Version**: 1.1.0
**Maintained By**: RF Engineering Team
