# Quick Reference

## Key Files & Directories

```
PA design App/
├── README.md                      ← Start here
├── DEVELOPMENT.md                 ← Dev setup & patterns
├── DEPLOYMENT.md                  ← Ops guide
├── .env.example                   ← Environment template
├── config/app_config.yaml         ← Main config (env-based)
│
├── src/                           ← Application source
│   ├── app.R                      ← Entry point
│   ├── ui.R                       ← Dashboard UI
│   ├── server.R                   ← Orchestrator
│   ├── global.R                   ← Init & managers
│   ├── modules/
│   │   ├── calculations/          ← PURE functions (no Shiny)
│   │   ├── server/                ← Shiny reactivity
│   │   └── rf_tools/              ← Parsers & utilities
│   ├── core/                      ← Core managers (R6)
│   ├── plugins/                   ← AI agents
│   └── utils/                     ← KB loaders, helpers
│
├── assets/                        ← Frontend (JS, CSS)
│   ├── js/konva/                  ← Canvas libraries
│   ├── js/rf-tools/               ← Measurement tools
│   ├── js/common/                 ← Shared scripts
│   └── css/                       ← Stylesheets
│
├── config/                        ← Configuration
│   ├── app_config.yaml            ← Runtime config
│   └── technology_guardrails.yaml ← Device specs
│
├── database/                      ← SQL schema & migrations
│   ├── 01_schema.sql              ← PostgreSQL schema
│   ├── seeds/                     ← Initial data
│   └── migrations/                ← Versioned SQL updates
│
├── data/                          ← Application data
│   ├── kb/                        ← Knowledge base (vector DB)
│   ├── sample-files/              ← Load-pull samples
│   ├── projects/                  ← User projects
│   ├── uploads/                   ← Temp uploads
│   └── cache/                     ← Query cache
│
├── tests/                         ← Unit tests
│   ├── testthat/                  ← R test files
│   ├── fixtures/                  ← Test data
│   └── mocks/                     ← Mock objects
│
├── docs/                          ← Documentation
│   ├── README.md                  ← Architecture overview
│   ├── DEVELOPMENT.md             ← Dev guide
│   ├── DEPLOYMENT.md              ← Ops guide
│   ├── architecture/              ← Design philosophy & components
│   ├── api-patterns/              ← Code patterns
│   ├── decisions/                 ← Architecture Decision Records
│   ├── changelog/                 ← Session notes & history
│   └── archive/                   ← Historical docs
│
├── infra/                         ← Infrastructure
│   ├── docker/                    ← Docker configs
│   │   ├── Dockerfile             ← Container image
│   │   └── docker-compose.yml     ← Services orchestration
│   ├── k8s/                       ← Kubernetes (future)
│   └── scripts/                   ← Admin scripts
│
└── .github/                       ← GitHub integrations
    └── workflows/                 ← CI/CD pipelines
        ├── test-build.yml         ← Test & build
        └── deploy.yml             ← Deployment automation
```

---

## Common Commands

### Local Development

```bash
# Install & start (Docker) — RECOMMENDED
docker-compose -f infra/docker/docker-compose.yml up -d
# http://localhost:3838

# Install & start (manual)
Rscript -e "renv::restore()"
psql -U postgres -d pa_design_app -f database/01_schema.sql
Rscript -e "shiny::runApp('src/app.R', port=3838)"

# Stop all services
docker-compose down

# View logs
docker-compose logs -f app
```

### Testing

```bash
# Run all tests
Rscript -e "testthat::test_dir('tests/testthat')"

# Run single test file
Rscript -e "testthat::test_file('tests/testthat/test_calc_pa_lineup.R')"

# Code coverage
Rscript -e "covr::package_coverage('src/modules/calculations')"

# Lint code
Rscript -e "lintr::lint_dir('src')"
```

### Database

```bash
# Connect
psql -U postgres pa_design_app

# Backup
pg_dump -U postgres pa_design_app > backup.sql

# Restore
psql -U postgres pa_design_app < backup.sql

# With Docker
docker-compose exec postgres psql -U postgres pa_design_app
```

### Git & Releases

```bash
# Create feature branch
git checkout -b feature/my-feature

# Commit changes
git add src/
git commit -m "feat: add new feature"
git push origin feature/my-feature

# Create release
git tag -a v1.1.0 -m "Release 1.1.0"
git push origin main v1.1.0
```

### Docker Operations

```bash
# Build image
docker build -f infra/docker/Dockerfile -t pa-design-app:dev .

# Run container
docker run -p 3838:3838 -e DB_HOST=localhost pa-design-app:dev

# Push to Docker Hub
docker tag pa-design-app:dev username/pa-design-app:v1.1.0
docker push username/pa-design-app:v1.1.0

# Clean up
docker system prune -a
```

---

## Architecture Patterns

### Calculation Engines

**Location**: `src/modules/calculations/`

Pure R functions — NO Shiny dependencies.

```r
# ✅ CORRECT
calc_ropt <- function(vdd, vknee, pout) {
  (vdd - vknee)^2 / (2 * pout)
}

# Called by server module
result <- calc_ropt(input$vdd, input$vknee, input$pout)
```

### Server Modules

**Location**: `src/modules/server/`

Orchestrate UI ↔ Calc ↔ Output.

```r
mod_calc_server <- function(id, data) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({ calc_ropt(...) })
    output$result <- renderText({ result() })
  })
}
```

### AI Agents

**Location**: `src/plugins/rf_pa_design/agents/`

Extend `BaseAgent` (R6 class).

```r
MyAgent <- R6::R6Class("MyAgent", inherit = BaseAgent, public = list(
  execute = function(input_data) {
    # Validate, process, log, return
    # Reference: theory_agent.R (203 lines)
  }
))
```

### Database Access

**Location**: `src/core/data_mgmt/`

Use `DBI` + `RPostgres` for type-safe queries.

```r
DataManager$get_project(project_id)
DataManager$create_project(name, architecture_type)
```

---

## Configuration

### Environment Variables (`.env.local`)

```bash
APP_ENV=development
AUTH_ENABLED=false
DB_HOST=localhost
DB_PORT=5432
LOG_LEVEL=info
CHROMA_HOST=localhost
CHROMA_PORT=8000
```

### Feature Flags

```yaml
# config/app_config.yaml
feature_flags:
  enable_ml_predictions: true
  enable_mcp_integration: false      # ← Disabled by default
  enable_chatbot: true
  enable_real_time_collaboration: false
```

---

## Key Decisions

### 1. Pure Calculations
All business logic in `src/modules/calculations/` is **pure**—independently testable, no framework dependencies.

### 2. R6 Agents
All AI agents extend `BaseAgent`. Reference: `theory_agent.R` (203 lines, fully functional).

### 3. Graceful Fallback
App works **without** PostgreSQL (demo mode). DB connection optional via `DEMO_MODE` flag.

### 4. Canvas Protocol
Shiny ↔ Konva.js communication via `Shiny.setInputValue()` / `session$sendCustomMessage()`.

### 5. Configuration Hierarchy
`.env.local` → `app_config.yaml` (env substitution) → code defaults

---

## Troubleshooting

| Problem | Check |
|---|---|
| App won't start | Logs: `docker-compose logs app` or `logs/app.log` |
| DB connection fails | `.env.local` credentials; PostgreSQL service running |
| Slow calculations | Check `calc_*.R` for inefficiency; profile with `profvis` |
| JavaScript errors | Browser console (`F12`); check `assets/js/` paths |
| Docker build fails | `docker-compose down -v` (clean volumes); rebuild |

---

## What's Next

**Priority 1**: Unit tests for calculation engines (GAP-001 — CRITICAL)

```bash
cd "PA design App"
tests/testthat/test_calc_transistor_sizing.R  # Create this
```

**Priority 2**: Architecture Agent implementation (Weeks 1-4)

**Priority 3**: Remaining 5 agents (Phases 4+5)

See `docs/decisions/IMPLEMENTATION_ROADMAP.md` for full roadmap.

---

## Resources

- **Docs**: `docs/DEVELOPMENT.md`, `docs/DEPLOYMENT.md`
- **Patterns**: `docs/api-patterns/`
- **Decisions**: `docs/decisions/IMPLEMENTATION_ROADMAP.md`
- **Architecture**: `docs/architecture/`
- **References**: `docs/architecture/RF_Engg_books/`

---

**Last Updated**: 2026-04-02
