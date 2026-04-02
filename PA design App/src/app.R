# ============================================================
# app.R — PA Design App entry point
#
# This file is the ONLY file Shiny needs to run the app.
# All logic lives in the sourced modules below.
#
# Architecture:
#   global.R           – libraries, config, DB, manager init
#   ui.R               – full dashboardPage() UI definition
#   server.R           – server function + sources all modules
#   modules/
#     calculations/    – pure (non-Shiny) calculation functions
#     server/          – serverXxx() module functions
# ============================================================

# ── Global setup (libraries, config, DB, managers) ───────────
source("global.R")

# ── Calculation modules (pure functions, no Shiny deps) ──────
source("modules/calculations/calc_freq_planning.R")
source("modules/calculations/calc_loss_curves.R")
source("modules/calculations/calc_link_budget.R")
source("modules/calculations/calc_pa_lineup.R")
source("modules/calculations/calc_rf_tools.R")
source("modules/calculations/calc_guardrails.R")

# ── UI definition ─────────────────────────────────────────────
source("ui.R")

# ── Server function + all server modules ─────────────────────
source("server.R")

# ── Launch ────────────────────────────────────────────────────
shinyApp(ui = ui, server = server)

