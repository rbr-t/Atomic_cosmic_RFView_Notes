# Development Guide

## Setup

### Local Environment

1. **Clone & Install R dependencies**
   ```bash
   git clone https://github.com/rbr-t/Atomic_cosmic_RFView_Notes.git
   cd "PA design App"
   cp .env.example .env.local

   # Install R packages
   Rscript -e "renv::restore()"
   ```

2. **Database Setup** (optional for demo mode)
   ```bash
   # Create database
   createdb pa_design_app

   # Initialize schema
   psql -U postgres -d pa_design_app -f database/01_schema.sql
   psql -U postgres -d pa_design_app -f database/seeds/01_init.sql
   ```

3. **Start Development Server**
   ```bash
   cd src
   Rscript -e "shiny::runApp('app.R', port=3838)"
   ```

   Access at http://localhost:3838

### Docker Development

```bash
docker-compose -f infra/docker/docker-compose.yml up -d

# View logs
docker-compose logs -f app

# Run shell in container
docker-compose exec app bash

# Database admin UI
# http://localhost:5050 (pgadmin)
```

---

## Code Patterns

### Calculation Engines (Pure Functions)

**Location**: `src/modules/calculations/`

All functions here must be **pure** — no Shiny dependencies (`input$`, `reactive()`, etc.).

```r
# ✅ CORRECT
calc_ropt <- function(vdd, vknee, pout) {
  (vdd - vknee)^2 / (2 * pout)
}

# ❌ WRONG — uses Shiny!
calc_ropt <- function(vdd, pout) {
  vdd_val <- input$vdd  # ← NO!
  (vdd_val)^2 / (2 * pout)
}
```

**Testing**:
```r
# tests/testthat/test_calc_pa_lineup.R
test_that("Ropt calculation is correct", {
  result <- calc_ropt(vdd=28, vknee=2, pout=10)
  expect_close(result, 3.38, tolerance=0.01)
})
```

### Server Modules (Shiny Reactivity)

**Location**: `src/modules/server/`

These orchestrate UI inputs → calculations → outputs.

```r
# server_transistor_design.R
mod_transistor_design_server <- function(id, project_data) {
  moduleServer(id, function(input, output, session) {

    # Reactive: call pure calc function
    transistor_result <- reactive({
      calc_transistor_sizing(
        topology = input$topology,
        pout = input$power_out,
        vdd = input$vdd
      )
    })

    # Output: display results
    output$gate_width <- renderText({
      transistor_result()$gate_width
    })
  })
}
```

### AI Agents

**Location**: `src/plugins/rf_pa_design/agents/`

**Pattern**: Extend `base_agent.R` (R6 class).

```r
# theory_agent.R (reference implementation)
TheoryAgent <- R6::R6Class(
  "TheoryAgent",
  inherit = BaseAgent,
  public = list(
    initialize = function() {
      super$initialize(
        name = "theory_agent",
        description = "Physics consultation and device selection"
      )
    },

    execute = function(input_data) {
      # Validate input
      if (!private$validate_input(input_data)) {
        return(list(status = "error", message = "Invalid input"))
      }

      # Call LLM or fallback
      result <- private$query_llm(input_data)

      # Log execution
      self$log_execution(input_data, result)

      return(result)
    }
  )
)
```

### Database Models

**Location**: `src/core/data_mgmt/`

Use `DBI` + `RPostgres` for type-safe queries.

```r
# data_manager.R
DataManager <- R6::R6Class(
  "DataManager",
  public = list(
    get_project = function(project_id) {
      query <- "SELECT * FROM projects WHERE id = $1"
      DBI::dbGetQuery(self$conn, query, list(project_id))
    },

    create_project = function(name, architecture_type) {
      query <- "
        INSERT INTO projects (name, architecture_type, created_at)
        VALUES ($1, $2, NOW())
        RETURNING *
      "
      DBI::dbGetQuery(self$conn, query, list(name, architecture_type))
    }
  )
)
```

---

## Testing

### Run All Tests
```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

### Create New Test File
```r
# tests/testthat/test_calc_transistor_sizing.R
library(testthat)
source("src/modules/calculations/calc_transistor_sizing.R")

test_that("gate_width_calc returns positive value", {
  result <- calc_gate_width(pout = 10, power_density = 4, pae = 0.75)
  expect_gt(result, 0)
})
```

### Test Coverage
```bash
Rscript -e "
  library(covr)
  cov <- package_coverage('src/modules/calculations')
  report(cov)
"
```

---

## Debugging

### Enable Debug Logging
```bash
# .env.local
LOG_LEVEL=debug
APP_DEBUG=true
```

### Inspect Reactive State
```r
# In server.R
observe({
  cat("\n=== REACTIVE STATE ===\n")
  cat("Project ID:", input$project_id, "\n")
  cat("Topology:", input$topology, "\n")
  cat("Power Out:", input$power_out, "\n")
})
```

### Database Debugging
```bash
# Connect to running DB
docker-compose exec postgres psql -U postgres pa_design_app

# List tables
\dt

# Check data
SELECT * FROM projects LIMIT 5;
```

---

## Building & Releasing

### Local Build
```bash
docker build -f infra/docker/Dockerfile -t pa-design-app:dev .
docker run -p 3838:3838 pa-design-app:dev
```

### Push to Docker Hub
```bash
docker tag pa-design-app:dev username/pa-design-app:v1.1.0
docker push username/pa-design-app:v1.1.0
```

### Git Workflow
```bash
# Feature branch
git checkout -b feature/my-feature
# ... make changes ...
git commit -m "feat: add new feature"
git push origin feature/my-feature

# Create PR
# → Automated tests run
# → Code review
# → Merge to develop
# → Staging deployment
# → Manual promotion to main
# → Production deployment
```

---

## Common Tasks

### Add a New Calculation Module
```r
# 1. Create pure function file
# src/modules/calculations/calc_my_calc.R

calc_my_measurement <- function(input_a, input_b) {
  # Pure logic here
  result <- input_a * input_b
  return(result)
}

# 2. Add server module
# src/modules/server/server_my_calc.R

mod_my_calc_server <- function(id, data) {
  moduleServer(id, function(input, output, session) {
    result <- reactive({
      calc_my_measurement(
        input$param_a,
        input$param_b
      )
    })

    output$result_display <- renderText(result())
  })
}

# 3. Add tests
# tests/testthat/test_calc_my_calc.R

test_that("my_measurement works", {
  result <- calc_my_measurement(2, 3)
  expect_equal(result, 6)
})

# 4. Link in global.R or ui.R
```

### Add a New Database Table
```sql
-- database/migrations/002_add_new_table.sql
CREATE TABLE new_entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Then apply:
psql -U postgres -d pa_design_app -f database/migrations/002_add_new_table.sql
```

### Enable Production Features
```yaml
# config/app_config.yaml
security:
  auth_enabled: true              # Enable authentication
  encryption_enabled: true        # Enable data encryption

feature_flags:
  enable_mcp_integration: true     # Enable ADS/AWR bridge
```

---

## Performance Tips

1. **Memoize expensive calculations**
   ```r
   library(memoise)
   calc_expensive <- memoise::memoise(function(x) { ... })
   ```

2. **Use reactive conditions to avoid re-runs**
   ```r
   observeEvent(input$calculate_button, {
     result <- calc_complex()  # Only runs on button click
   })
   ```

3. **Database connection pooling**
   ```r
   # Configured in config_manager.R
   pool_size: 10  # Adjust based on concurrent users
   ```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| App won't start | Check `logs/app.log`; verify DB connection in `.env.local` |
| Database connection fails | Ensure PostgreSQL is running; check credentials in `.env.local` |
| Slow performance | Check calculation complexity; enable database query logging |
| Docker build fails | Run `docker-compose down -v` to clean volumes; rebuild |

---

**Last Updated**: 2026-04-02
