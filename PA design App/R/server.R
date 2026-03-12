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
# Null-coalescing operator (base R >= 4.4; define for 4.3 compatibility)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

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

# ── Load Pull subsystem ───────────────────────────────────────────────────
source("modules/rf_tools/lp_parsers.R")
source("modules/server/server_lp_viewer.R")

# ── Knowledge Base subsystem ─────────────────────────────────────────────
source("knowledge_base/kb_loader.R")
source("knowledge_base/kb_query.R")
source("modules/server/server_knowledge_base.R")
source("modules/server/server_settings.R")
source("modules/server/server_reporting.R")

# ── Server function ───────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Initialise shared reactive state (rv, lineup reactives, helpers) ──
  state <- initServerState(input, output, session)

  # ── Utility Bar: top-header nav links → update sidebar tab ───────────────
  observeEvent(input$goto_utility_tab, {
    req(input$goto_utility_tab)
    updateTabItems(session, "sidebar_menu", input$goto_utility_tab)
  }, ignoreInit = TRUE)

  # ── Auto-navigate when opened via ?panel= query param (new-window pop-outs) ─
  observe({
    query <- parseQueryString(session$clientData$url_search)
    if (!is.null(query$panel) && nzchar(query$panel)) {
      updateTabItems(session, "sidebar_menu", query$panel)
    }
  })

  # ── Utility Drawer: render compact panel content on demand ────────────────
  output$utility_drawer_content <- renderUI({
    req(input$utility_drawer_tab)
    switch(input$utility_drawer_tab,

      # ── Data Manager ──────────────────────────────────────────────────────
      "util_data" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "Manage project files, import external data and browse the session database."),
        tags$div(class = "drawer-section-label", "Quick Actions"),
        fluidRow(
          column(6,
            actionButton("drawer_data_import", "Import CSV",
              icon = icon("file-csv"), class = "btn-default btn-block btn-sm")
          ),
          column(6,
            actionButton("drawer_data_export", "Export Session",
              icon = icon("download"), class = "btn-default btn-block btn-sm")
          )
        ),
        tags$div(class = "drawer-section-label", "Recent Files"),
        uiOutput("drawer_recent_files"),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("external-link-alt"), " Open Data Manager — Full View"
        )
      ),

      # ── RF Tools (Smith Chart + converters) ───────────────────────────────
      "smith_chart" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "Quick RF unit converters. Open Full View for the interactive Smith Chart."),
        tags$div(class = "drawer-section-label", "dBm \u2194 mW"),
        tags$div(class = "drawer-converter-card",
          fluidRow(
            column(6,
              tags$label("dBm"),
              numericInput("drawer_dbm_in", NULL, value = 20, step = 1)
            ),
            column(6,
              tags$label("mW"),
              numericInput("drawer_mw_in",  NULL, value = 100, step = 1)
            )
          ),
          uiOutput("drawer_rf_conv_result")
        ),
        tags$div(class = "drawer-section-label", "Frequency \u2194 Wavelength"),
        tags$div(class = "drawer-converter-card",
          fluidRow(
            column(6,
              tags$label("GHz"),
              numericInput("drawer_freq_in", NULL, value = 2.4, step = 0.1, min = 0.001)
            ),
            column(6,
              tags$label("Wavelength (mm)"),
              uiOutput("drawer_wl_result")
            )
          )
        ),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("chart-bar"), " Open Smith Chart — Full View"
        )
      ),

      # ── Load Pull Viewer ──────────────────────────────────────────────────
      "lp_viewer" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "Load-pull / source-pull data viewer.",
          " Upload SPL, MDF, AMCAD, Focus, Anteverta or MDIF files."),
        tags$div(class = "drawer-section-label", "Quick upload"),
        fileInput("drawer_lp_quick_upload", NULL,
          multiple    = TRUE,
          accept      = c(".spl",".lpt",".txt",".dat",
                          ".mdf",".csv",".ant",".mdif"),
          buttonLabel = icon("upload"),
          placeholder = "Choose LP file\u2026"),
        p(style = "color:#888; font-size:11px; margin-top:4px;",
          "After uploading, open the full view to parse and visualise."),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("chart-area"), " Open Load Pull Viewer — Full View"
        )
      ),

      # ── AI Agents ─────────────────────────────────────────────────────────
      "util_agents" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "AI agent manager, prompt store and knowledge-augmented design assistant."),
        tags$div(class = "drawer-section-label", "Agent Status"),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("robot")),
          tags$span("PA Design Agent"), tags$span(style = "margin-left:auto;",
            span(class = "label label-default", "Idle"))
        ),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("search")),
          tags$span("Literature Search Agent"), tags$span(style = "margin-left:auto;",
            span(class = "label label-default", "Idle"))
        ),
        tags$div(class = "drawer-section-label", "Quick Prompt"),
        textAreaInput("drawer_agent_prompt", NULL,
          placeholder = "Ask the PA design agent\u2026",
          rows = 3),
        actionButton("drawer_agent_send", "Send",
          icon = icon("paper-plane"), class = "btn-primary btn-sm btn-block"),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("robot"), " Open AI Agents — Full View"
        )
      ),

      # ── Knowledge Base ────────────────────────────────────────────────────
      "util_knowledge" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "Internal references, datasheets, application notes and IFX knowledge library."),
        tags$div(class = "drawer-section-label", "Search"),
        div(style = "display:flex; gap:6px; margin-bottom:12px;",
          textInput("drawer_kb_search", NULL,
            placeholder = "Search documents, notes\u2026"),
          actionButton("drawer_kb_go", icon("search"), class = "btn-default btn-sm")
        ),
        tags$div(class = "drawer-section-label", "Categories"),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("microchip")),
          tags$span("GaN / GaAs Technology")
        ),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("chart-line")),
          tags$span("PA Topologies & Classes")
        ),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("thermometer-half")),
          tags$span("Thermal Management")
        ),
        tags$div(class = "drawer-link-row",
          tags$span(class = "drawer-link-icon", icon("book")),
          tags$span("IFX Internal Notes")
        ),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("book"), " Open Knowledge Base — Full View"
        )
      ),

      # ── Settings ──────────────────────────────────────────────────────────
      "settings" = tagList(
        p(style = "color:#aaa; font-size:12px; margin:0 0 12px 0;",
          "Quick appearance settings. More options in the full settings view."),
        tags$div(class = "drawer-section-label", "Theme"),
        selectInput("drawer_theme_select", NULL,
          choices = c(
            "Dark Mode (default)" = "dark",
            "Light Mode"          = "light",
            "Colorblind-Friendly" = "colorblind"
          ),
          selected = isolate(input$theme_select) %||% "dark"
        ),
        tags$div(class = "drawer-section-label", "Accent Colour"),
        selectInput("drawer_accent_color", NULL,
          choices = c(
            "Orange (default)" = "#ff7f11",
            "Blue"             = "#1f77b4",
            "Green"            = "#2ca02c"
          ),
          selected = isolate(input$accent_color) %||% "#ff7f11"
        ),
        uiOutput("drawer_settings_preview"),
        tags$a(class = "drawer-fullview-link",
          onclick = "utilityDrawerFullView()",
          icon("cog"), " Open Settings — Full View"
        )
      ),

      # Fallback
      div(p("Panel not found."))
    )
  })

  # Sync drawer quick-settings back to the main settings inputs
  observeEvent(input$drawer_theme_select, {
    req(input$drawer_theme_select)
    updateSelectInput(session, "theme_select", selected = input$drawer_theme_select)
  }, ignoreInit = TRUE)
  observeEvent(input$drawer_accent_color, {
    req(input$drawer_accent_color)
    updateSelectInput(session, "accent_color", selected = input$drawer_accent_color)
  }, ignoreInit = TRUE)

  # RF converter results
  output$drawer_rf_conv_result <- renderUI({
    dbm <- input$drawer_dbm_in %||% 20
    mw  <- input$drawer_mw_in  %||% 100
    dbm_from_mw <- if (!is.null(input$drawer_mw_in))  round(10 * log10(max(mw,  1e-9)), 2) else NA
    mw_from_dbm <- if (!is.null(input$drawer_dbm_in)) round(10^(dbm / 10), 3) else NA
    tagList(
      div(class = "drawer-result-badge", paste0(mw_from_dbm, " mW  \u2190  ", dbm, " dBm")),
      div(style = "height:4px;"),
      div(class = "drawer-result-badge", paste0(dbm_from_mw, " dBm  \u2190  ", mw, " mW"))
    )
  })
  output$drawer_wl_result <- renderUI({
    freq_ghz <- input$drawer_freq_in %||% 2.4
    wl_mm <- if (!is.null(freq_ghz) && freq_ghz > 0)
      round(299.792458 / freq_ghz, 2) else NA
    div(style = "margin-top:22px;",
      div(class = "drawer-result-badge", paste0(wl_mm, " mm"))
    )
  })
  output$drawer_recent_files <- renderUI({
    tagList(
      tags$div(class = "drawer-link-row",
        tags$span(class = "drawer-link-icon", icon("file")),
        tags$span("No recent files in this session.", style = "color:#666; font-style:italic; font-size:11px;")
      )
    )
  })
  output$drawer_settings_preview <- renderUI({
    acc <- input$drawer_accent_color %||% "#ff7f11"
    div(style = paste0("margin-top:10px; padding:8px; border-radius:5px; border: 1px solid ", acc, "; color:", acc, "; font-size:11px; text-align:center;"),
      icon("palette"), " Accent preview"
    )
  })

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
  serverReporting(input, output, session, state)
  serverLpViewer(input, output, session, state)
  serverKnowledgeBase(input, output, session, state)

  # ── Session cleanup ──────────────────────────────────────────────────────
  onStop(function() {
    if (!is.null(db_pool)) poolClose(db_pool)
  })
}
