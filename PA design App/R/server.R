# ============================================================
# server.R
# Thin server orchestrator for the PA Design App.
#
# Sources all server module functions and wires them together
# into the Shiny server function.  Each module is a pure
# function serverXxx(input, output, session, state) that
# registers its own reactive handlers and returns nothing.
#
# Shared reactive state is created by initServerState() and
# passed as a named list to every module.
# ============================================================

# ── Source calculation engines (needed by server modules) ────────────────
source("modules/calculations/calc_pa_lineup.R")
source("modules/calculations/calc_guardrails.R")

# ── Source server modules ─────────────────────────────────────────────────
source("modules/server/server_state.R")
source("modules/server/server_dashboard.R")
source("modules/server/server_projects.R")
source("modules/server/server_theoretical_calc.R")
source("modules/server/server_freq_planning.R")
source("modules/server/server_global_params.R")
source("modules/server/server_loss_curves.R")
source("modules/server/server_link_budget.R")
source("modules/server/server_pa_lineup.R")
source("modules/server/server_spec_design.R")
source("modules/server/server_file_ops.R")
source("modules/server/server_rf_tools.R")
source("modules/server/server_guardrails.R")
source("modules/server/server_settings.R")

# ── Server function ───────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Initialise shared reactive state (rv, lineup reactives, helpers) ──
  state <- initServerState(input, output, session)

  # ── Utility Bar: top-header nav links → update sidebar tab ───────────────
  observeEvent(input$goto_utility_tab, {
    req(input$goto_utility_tab)
    updateTabItems(session, "sidebar_menu", input$goto_utility_tab)
  }, ignoreInit = TRUE)

  # ── Register all feature modules ────────────────────────────────────────
  serverDashboard(input, output, session, state)
  serverProjects(input, output, session, state)
  serverTheoreticalCalc(input, output, session, state)
  serverFreqPlanning(input, output, session, state)
  serverGlobalParams(input, output, session, state)
  serverLossCurves(input, output, session, state)
  serverLinkBudget(input, output, session, state)
  serverPaLineup(input, output, session, state)
  serverSpecDesign(input, output, session, state)
  serverFileOps(input, output, session, state)
  serverRfTools(input, output, session, state)
  serverGuardrails(input, output, session, state)
  serverSettings(input, output, session, state)

  # ── Session cleanup ──────────────────────────────────────────────────────
  onStop(function() {
    if (!is.null(db_pool)) poolClose(db_pool)
  })
}
