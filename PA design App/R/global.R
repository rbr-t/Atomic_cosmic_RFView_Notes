# ============================================================
# PA Design App - Global Setup
# Libraries, configuration, database initialisation, and manager init
# Sourced once at startup before ui/server are built.
# ============================================================

# Allow uploads up to 2 GB — required for large LP file batches
options(shiny.maxRequestSize = 2048 * 1024^2)

library(shiny)
library(shinydashboard)
library(shinyjs)
library(plotly)
library(DT)
library(R6)
library(yaml)
library(DBI)
library(pool)
library(duckdb)

# Source core systems
source("../core/project_mgmt/project_manager.R")
source("../core/data_mgmt/data_manager.R")
source("../core/security/auth_manager.R")
source("../core/state_config/config_manager.R")
source("../core/tagging_metadata/tag_manager.R")
source("../core/ai_agents/base_agent.R")
source("../core/ai_agents/agent_manager.R")

# Source RF PA Design plugin
source("../plugins/rf_pa_design/plugin_init.R")

# ── Configuration ─────────────────────────────────────────────
config     <- ConfigManager$new("../config/app_config.yaml")
app_config <- config$get_config()

# ── Database (with fallback to demo mode) ─────────────────────
db_pool   <- NULL
demo_mode <- FALSE

tryCatch({
  db_pool <- dbPool(
    drv      = RPostgres::Postgres(),
    host     = Sys.getenv("DB_HOST",     "localhost"),
    port     = Sys.getenv("DB_PORT",     "5432"),
    dbname   = Sys.getenv("DB_NAME",     "pa_design"),
    user     = Sys.getenv("DB_USER",     "admin"),
    password = Sys.getenv("DB_PASSWORD", "secret"),
    minSize  = 1,
    maxSize  = 2
  )
  con <- poolCheckout(db_pool)
  poolReturn(con)
  cat("✓ Database connection established\n")
}, error = function(e) {
  cat("⚠ Database not available - running in DEMO MODE\n")
  cat("  (Theoretical calculations will work, but project data won't persist)\n\n")
  demo_mode <<- TRUE
})

# ── Manager initialisation ────────────────────────────────────
if (!demo_mode) {
  project_mgr <- ProjectManager$new(db_pool)
  data_mgr    <- DataManager$new(db_pool)
  tag_mgr     <- TagManager$new(db_pool)
} else {
  project_mgr <- NULL
  data_mgr    <- NULL
  tag_mgr     <- NULL
}

agent_mgr <- AgentManager$new(config = app_config$ai_agents)
