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
source("modules/server/server_device_lib.R")
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

      # ── RF Tools: full Smith Chart (was a mini-stub; now the complete tool) ──
      "smith_chart" = tagList(
        div(style = "padding:4px 0 10px 0;",
          fluidRow(
            # ── Left control panel ─────────────────────────────────────────
            column(3,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5(icon("crosshairs"), " Impedance Entry", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("smith_z0",    "Reference Z\u2080 (\u03a9)",   value = 50, min = 0.1, max = 1000, step = 1),
                numericInput("smith_z_real","Z Real (\u03a9)",              value = 50, min = -2000, max = 2000),
                numericInput("smith_z_imag","Z Imaginary (\u03a9)",         value = 25, min = -2000, max = 2000),
                textInput("smith_label", "Point Label", value = "", placeholder = "e.g. Zin @ 2.4 GHz"),
                fluidRow(
                  column(6, actionButton("smith_add_point", "Add",
                    icon = icon("plus"),  class = "btn-primary btn-block btn-sm")),
                  column(6, actionButton("smith_clear", "Clear",
                    icon = icon("trash"), class = "btn-warning btn-block btn-sm"))
                ),
                hr(),
                h5(icon("sliders-h"), " Chart options", style = "color:#f0f0f0;"),
                selectInput("smith_mode", "Display Mode",
                  choices  = c("Impedance (Z)" = "Z", "Admittance (Y)" = "Y", "Both (Z+Y)" = "ZY"),
                  selected = "Z"),
                hr(),
                h5(icon("calculator"), " Matching Network", style = "color:#f0f0f0;"),
                selectInput("smith_match_type", "Network Type",
                  choices = c("L-Section", "Pi-Network", "T-Network", "Single Stub", "Double Stub")),
                actionButton("smith_design_match", "Synthesise",
                  icon = icon("calculator"), class = "btn-success btn-block btn-sm"),
                p(class = "text-muted", style = "font-size:11px; margin-top:8px;",
                  "Select 2 points then click Synthesise to compute element values.")
              )
            ),
            # ── Smith Chart plot ────────────────────────────────────────────
            column(9,
              div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5(icon("chart-bar"), " Smith Chart (interactive \u2014 hover/click points)",
                   style = "color:#f0f0f0; margin-top:0;"),
                plotlyOutput("smith_chart_plot", height = "520px"),
                hr(),
                h5("Point Summary & Matching Network", style = "color:#f0f0f0;"),
                verbatimTextOutput("smith_components")
              )
            )
          )
        )
      ),

      # ── Load Pull Viewer: full tool (was a quick-upload stub) ─────────────
      "lp_viewer" = tagList(
        div(style = "padding:4px 0 10px 0;",
          p(style = "color:#aaa; font-size:12px; margin:0 0 10px 0;",
            icon("chart-area"),
            " Import and visualise load-pull / source-pull measurement files.",
            " Formats: SPL, Focus Microwaves, Maury MDF, AMCAD, Anteverta-mw, ADS MDIF."),
          tabsetPanel(id = "lp_tabs",

            # ── Tab 1: Upload & Parse ────────────────────────────────────
            tabPanel("Upload & Parse",
              br(),
              fluidRow(
                column(4,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("File Import", style = "color:#f0f0f0; margin-top:0;"),
                    fileInput("lp_upload", NULL,
                      multiple    = TRUE,
                      accept      = c(".spl",".lpt",".txt",".dat",".mdf",".csv",".ant",".mdif",".s2p"),
                      buttonLabel = icon("upload"),
                      placeholder = "No file selected"),
                    selectInput("lp_format_override", "Format override",
                      choices  = c("Auto-detect" = "auto", "SPL / Generic ASCII" = "spl",
                                   "Focus Microwaves" = "focus", "Maury MDF" = "mdf",
                                   "AMCAD" = "amcad", "Anteverta-mw" = "anteverta", "ADS MDIF" = "mdif"),
                      selected = "auto"),
                    actionButton("lp_parse_btn", "Parse file(s)",
                      icon = icon("cog"), class = "btn-primary btn-block"),
                    hr(),
                    h5("Loaded datasets", style = "color:#f0f0f0;"),
                    uiOutput("lp_dataset_list")
                  )
                ),
                column(8,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Parse Log", style = "color:#f0f0f0; margin-top:0;"),
                    verbatimTextOutput("lp_parse_log"),
                    hr(),
                    h5("Parsed metadata", style = "color:#f0f0f0;"),
                    verbatimTextOutput("lp_meta_preview")
                  )
                )
              )
            ),

            # ── Tab 2: Smith Chart + Contours ────────────────────────────
            tabPanel("Smith Chart",
              br(),
              fluidRow(
                column(3,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Contour controls", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("lp_dataset_selector"),
                    hr(),
                    checkboxGroupInput("lp_contour_vars", "Overlay contours",
                      choices  = c("Pout (dBm)"="pout","PAE (%)"="pae","DE (%)"="de","Gain (dB)"="gain","Power (W)"="pdc"),
                      selected = c("pout","pae")),
                    sliderInput("lp_contour_levels", "No. of contour levels", min = 3, max = 12, value = 6, step = 1),
                    hr(),
                    selectInput("lp_pull_type", "Pull plane",
                      choices = c("Load Pull"="load","Source Pull"="source"), selected = "load"),
                    hr(),
                    checkboxInput("lp_show_max_pae",   "Mark max-PAE point",    value = TRUE),
                    checkboxInput("lp_show_max_pout",  "Mark max-Pout point",   value = TRUE),
                    checkboxInput("lp_show_stability", "Show stability circles", value = FALSE)
                  )
                ),
                column(9,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Smith Chart \u2014 Load Pull Contours", style = "color:#f0f0f0; margin-top:0;"),
                    plotlyOutput("lp_smith_plot", height = "500px")
                  )
                )
              )
            ),

            # ── Tab 3: XY Performance ────────────────────────────────────
            tabPanel("XY Performance",
              br(),
              fluidRow(
                column(3,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Plot controls", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("lp_xy_dataset_selector"),
                    selectInput("lp_xy_x_var", "X axis",
                      choices = c("Pout (dBm)"="pout_dbm","Pin (dBm)"="pin_dbm","Pavs (dBm)"="pavs_dbm")),
                    checkboxGroupInput("lp_xy_y_vars", "Y axis traces",
                      choices  = c("PAE (%)"="pae_pct","DE (%)"="de_pct","Gain (dB)"="gain_db","Pout (dBm)"="pout_dbm"),
                      selected = c("pae_pct","gain_db")),
                    hr(),
                    sliderInput("lp_xy_pin_range", "Pin range (dBm)", min = -20, max = 50, value = c(-5, 35))
                  )
                ),
                column(9,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Gain / PAE / DE vs Power", style = "color:#f0f0f0; margin-top:0;"),
                    plotlyOutput("lp_xy_plot", height = "460px")
                  )
                )
              )
            ),

            # ── Tab 4: Nose Plot ────────────────────────────────────────
            tabPanel("Nose Plot",
              br(),
              fluidRow(
                column(3,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Nose plot controls", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("lp_nose_dataset_selector"),
                    checkboxInput("lp_nose_mark_opt", "Mark optimal point", value = TRUE),
                    hr(),
                    sliderInput("lp_backoff_db", "Back-off reference (dB)", min = 0, max = 12, value = 6, step = 0.5)
                  )
                ),
                column(9,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("PAE vs Pout \u2014 Nose Plot / Trade-off", style = "color:#f0f0f0; margin-top:0;"),
                    plotlyOutput("lp_nose_plot", height = "460px"),
                    hr(),
                    p(class = "text-muted", style = "font-size:11px;",
                      "The optimal operating point balances maximum PAE against required output power.")
                  )
                )
              )
            ),

            # ── Tab 5: Tabular Summary ───────────────────────────────────
            tabPanel("Tabular",
              br(),
              div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Performance summary", style = "color:#f0f0f0; margin-top:0;"),
                fluidRow(
                  column(4, uiOutput("lp_table_dataset_selector")),
                  column(4, sliderInput("lp_ppeak_backoff", "Ppeak back-off (dB)", min=0, max=12, value=6, step=0.5)),
                  column(4, downloadButton("lp_table_csv", "Download CSV", class = "btn-default"))
                ),
                hr(),
                h5("Performance at Ppeak (max Pout)", style = "color:#f0f0f0;"),
                DT::DTOutput("lp_table_ppeak"),
                hr(),
                h5("Performance at Pavg (Ppeak \u2212 X dB back-off)", style = "color:#f0f0f0;"),
                DT::DTOutput("lp_table_pavg")
              )
            ),

            # ── Tab 6: Compare Devices ──────────────────────────────────
            tabPanel("Compare",
              br(),
              fluidRow(
                column(3,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Comparison controls", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("lp_compare_selector"),
                    hr(),
                    selectInput("lp_compare_metric", "Contour metric",
                      choices  = c("PAE (%)"="pae_pct","Pout (dBm)"="pout_dbm","Gain (dB)"="gain_db"),
                      selected = "pae_pct"),
                    checkboxInput("lp_compare_optimum", "Show optimal points", value = TRUE)
                  )
                ),
                column(9,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Multi-device Overlay", style = "color:#f0f0f0; margin-top:0;"),
                    plotlyOutput("lp_compare_plot", height = "520px")
                  )
                )
              )
            ),

            # ── Tab 7: LP Report ────────────────────────────────────────
            tabPanel("LP Report",
              br(),
              fluidRow(
                column(4,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Report options", style = "color:#f0f0f0; margin-top:0;"),
                    textInput("lp_rpt_title",    "Report title",     value = "Load Pull Report"),
                    textInput("lp_rpt_engineer", "Engineer / Author", value = ""),
                    textInput("lp_rpt_project",  "Project ref",       value = ""),
                    hr(),
                    checkboxGroupInput("lp_rpt_sections", "Include sections",
                      choices  = c("Smith Chart contours"="smith","XY performance plots"="xy",
                                   "Nose plot"="nose","Summary table"="table","Parsed metadata"="meta"),
                      selected = c("smith","xy","nose","table")),
                    hr(),
                    downloadButton("lp_rpt_html",    "Download HTML Report",    class = "btn-success btn-block"),
                    br(),
                    downloadButton("lp_rpt_csv_all", "Download All Data (CSV)", class = "btn-default btn-block")
                  )
                ),
                column(8,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Report preview", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("lp_rpt_preview")
                  )
                )
              )
            )
          )
        )
      ),

      # ── Knowledge Base: full tool (was a search-stub) ─────────────────────
      "util_knowledge" = tagList(
        div(style = "padding:4px 0 10px 0;",
          p(style = "color:#aaa; font-size:12px; margin:0 0 8px 0;",
            icon("book"),
            " Searchable library of RF power transistors: specifications, impedance data, app notes and design references.",
            " Confidence: ",
            tags$span(style="color:#2ca02c;font-weight:600;", "\u2713\u2713 high"),
            " = datasheet verified \u00b7 ",
            tags$span(style="color:#ff7f11;font-weight:600;", "\u2713 medium"),
            " = training knowledge \u00b7 ",
            tags$span(style="color:#d62728;font-weight:600;", "\u26a0 low"),
            " = placeholder."
          ),
          verbatimTextOutput("kb_stats_text"),
          fluidRow(
            # ── Filter panel ───────────────────────────────────────────
            column(3,
              div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5(icon("filter"), " Filters", style = "color:#f0f0f0; margin-top:0;"),
                textInput("kb_search_box", "Search",
                  placeholder = "Part number, technology, tag\u2026"),
                hr(),
                uiOutput("kb_filter_mfr_ui"),
                uiOutput("kb_filter_tech_ui"),
                numericInput("kb_filter_freq_mhz", "Covers frequency (MHz)",
                  value = NULL, min = 0.01, max = 50000, step = 1),
                numericInput("kb_filter_pout_w", "Min Pout (W)",
                  value = NULL, min = 0, max = 10000, step = 5),
                selectInput("kb_filter_app", "Application",
                  choices  = c("All", "cellular", "avionics", "ism", "broadcast",
                               "defense", "medical", "radar", "5G", "4G"),
                  selected = "All", multiple = TRUE),
                selectInput("kb_filter_role", "Role in PA chain",
                  choices  = c("All", "driver", "main", "peak", "combined"),
                  selected = "All", multiple = TRUE),
                hr(),
                checkboxInput("kb_show_placeholders", "Show placeholder entries", value = FALSE),
                actionButton("kb_clear_filters", "Clear all filters",
                  icon = icon("times"), class = "btn-default btn-block btn-sm")
              )
            ),
            # ── Devices + Detail ────────────────────────────────────────
            column(9,
              div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px; margin-bottom:10px;",
                h5(icon("list"), " Devices", style = "color:#f0f0f0; margin-top:0;"),
                DT::DTOutput("kb_device_table", height = "340px")
              ),
              div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5(icon("info-circle"), " Device Detail", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("kb_device_detail")
              )
            )
          )
        )
      ),

      # ── Agents ───────────────────────────────────────────────────────────
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
  serverDeviceLib(input, output, session, state)

  # ── Session cleanup ──────────────────────────────────────────────────────
  onStop(function() {
    if (!is.null(db_pool)) poolClose(db_pool)
  })
}
