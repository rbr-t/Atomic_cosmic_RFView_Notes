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
source("modules/server/server_rf_calculators.R")
source("modules/server/server_guardrails.R")

# ── Load Pull subsystem ───────────────────────────────────────────────────
source("modules/calculations/calc_rf_tools.R")
source("modules/rf_tools/lp_parsers.R")
source("modules/rf_tools/rf_calculators_drawer_ui.R")
source("modules/server/server_lp_viewer.R")

# ── S-Parameter Viewer subsystem ────────────────────────────────────────────
source("modules/rf_tools/sp_parsers.R")
source("modules/server/server_sp_viewer.R")

# ── Knowledge Base subsystem ─────────────────────────────────────────────
source("knowledge_base/kb_loader.R")
source("knowledge_base/kb_query.R")
source("modules/server/server_knowledge_base.R")
source("modules/server/server_device_lib.R")
source("modules/server/server_settings.R")
source("modules/server/server_reporting.R")
source("modules/server/server_rf_cad.R")

# ── Server function ───────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Initialise shared reactive state (rv, lineup reactives, helpers) ──
  state <- initServerState(input, output, session)

  # ── RF CAD Tool module (registered once per session) ─────────────────────
  rfCadServer("rfcad")

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

      # ── RF Calculators: Power · Freq/Wave · MTTF · Thermal ───────────────
      "rf_calc" = rfCalculatorsDrawerUI(),

      # ── RF Tools: Smith Chart + Load Pull ───────────────────────────────────
      "rf_tools" = tagList(
        div(style = "padding:4px 0 10px 0;",
          tabsetPanel(id = "rf_tools_tabs",

            # ── Smith Chart tab ────────────────────────────────────────────
            tabPanel(tagList(icon("crosshairs"), " Smith Chart"),
              div(style = "padding:8px 0 4px 0;",
                fluidRow(
                  # ── Left control panel ─────────────────────────────────
                  column(3,
                    div(class = "well",
                      style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                      h5(icon("crosshairs"), " Impedance Entry",
                        style = "color:#f0f0f0; margin-top:0;"),
                      numericInput("smith_z0",    "Reference Z\u2080 (\u03a9)",
                        value = 50, min = 0.1, max = 1000, step = 1),
                      numericInput("smith_z_real", "Z Real (\u03a9)",
                        value = 50, min = -2000, max = 2000),
                      numericInput("smith_z_imag", "Z Imaginary (\u03a9)",
                        value = 25, min = -2000, max = 2000),
                      textInput("smith_label", "Point Label", value = "",
                        placeholder = "e.g. Zin @ 2.4 GHz"),
                      fluidRow(
                        column(6, actionButton("smith_add_point", "Add",
                          icon  = icon("plus"),
                          class = "btn-primary btn-block btn-sm")),
                        column(6, actionButton("smith_clear", "Clear",
                          icon  = icon("trash"),
                          class = "btn-warning btn-block btn-sm"))
                      ),
                      hr(),
                      h5(icon("sliders-h"), " Chart options", style = "color:#f0f0f0;"),
                      selectInput("smith_mode", "Display Mode",
                        choices  = c("Impedance (Z)" = "Z",
                                     "Admittance (Y)" = "Y",
                                     "Both (Z+Y)"     = "ZY"),
                        selected = "Z"),
                      hr(),
                      h5(icon("calculator"), " Matching Network", style = "color:#f0f0f0;"),
                      selectInput("smith_match_type", "Network Type",
                        choices = c("L-Section", "Pi-Network",
                                    "T-Network", "Single Stub", "Double Stub")),
                      actionButton("smith_design_match", "Synthesise",
                        icon  = icon("calculator"),
                        class = "btn-success btn-block btn-sm"),
                      p(class = "text-muted", style = "font-size:11px; margin-top:8px;",
                        "Select 2 points then click Synthesise to compute element values.")
                    )
                  ),
                  # ── Smith Chart plot ───────────────────────────────────
                  column(9,
                    div(class = "well",
                      style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                      h5(icon("chart-bar"),
                        " Smith Chart (interactive \u2014 hover/click points)",
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

            # ── Load Pull tab ──────────────────────────────────────────────
            tabPanel(tagList(icon("chart-area"), " Load Pull"),
              div(style = "padding:8px 0 4px 0;",
                p(style = "color:#aaa; font-size:12px; margin:0 0 10px 0;",
                  icon("chart-area"),
                  " Import and visualise load-pull / source-pull measurement files.",
                  " Formats: SPL, Focus Microwaves, Maury MDF, AMCAD, Anteverta-mw, ADS MDIF."),

                # ── Global split variable bar ────────────────────────────
                div(
                  style = "background:#181828; border:1px solid #2a2a3a;
                           border-radius:4px; padding:6px 14px;
                           margin-bottom:10px; display:flex;
                           align-items:center; gap:18px;",
                  strong(icon("layer-group"), " Global split / color by:",
                    style = "color:#ccc; font-size:12px; white-space:nowrap;"),
                  div(style = "flex:0 0 190px;",
                    selectInput("lp_global_split_var", NULL,
                      choices  = c(
                        "Frequency (GHz)"  = "freq_ghz",
                        "Dataset Tag"      = "dataset_tag",
                        "Drain Voltage (V)"= "vdc_v"),
                      selected = "freq_ghz",
                      width    = "100%")),
                  p(style = "font-size:11px; color:#666; margin:0;",
                    icon("info-circle"),
                    " Default for all LP plots. Each plot tab can override locally.")
                ),

                tabsetPanel(id = "lp_tabs",

                  # ── Tab 1: Upload & Parse ────────────────────────────
                  tabPanel("Upload & Parse",
                    br(),
                    fluidRow(
                      column(4,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("File Import", style = "color:#f0f0f0; margin-top:0;"),
                          fileInput("lp_upload", NULL,
                            multiple    = TRUE,
                            accept      = c(".spl",".lpt",".txt",".dat",
                                            ".mdf",".csv",".ant",".mdif",".s2p",".cst"),
                            buttonLabel = icon("upload"),
                            placeholder = "No file selected"),
                          selectInput("lp_format_override", "Format override",
                            choices = c(
                              "Auto-detect"         = "auto",
                              "SPL / Generic ASCII" = "spl",
                              "Focus Microwaves"    = "focus",
                              "Maury MDF"           = "mdf",
                              "AMCAD"               = "amcad",
                              "Anteverta-mw"        = "anteverta",
                              "ADS MDIF"            = "mdif",
                              "Mestech/Auriga CST"  = "cst"),
                            selected = "auto"),
                          hr(style = "border-color:#2a2a3a; margin:8px 0;"),
                          strong(icon("tag"), " Dataset tag",
                            style = "color:#ccc; font-size:12px;"),
                          p(style = "font-size:11px; color:#888; margin:2px 0 4px 0;",
                            "Identifies this dataset when comparing multiple files."),
                          checkboxInput("lp_auto_tag",
                            "Auto-tag from filename", value = TRUE),
                          textInput("lp_dataset_tag", NULL,
                            placeholder = "Optional: type a custom tag"),
                          actionButton("lp_parse_btn", "Parse file(s)",
                            icon = icon("cog"), class = "btn-primary btn-block"),
                          hr(),
                          div(
                            style = "display:flex; align-items:baseline;
                                     justify-content:space-between;
                                     margin-bottom:6px;",
                            h5("Loaded datasets",
                               style = "color:#f0f0f0; margin:0;"),
                            actionButton("lp_clear_all_btn", "Clear all",
                              class = "btn btn-danger",
                              style = "padding:2px 10px; font-size:11px;
                                       line-height:1.6; border-radius:3px;")
                          ),
                          uiOutput("lp_dataset_list"),
                          hr(style = "border-color:#2a2a3a; margin:8px 0;"),
                          div(
                            style = "display:flex; align-items:center;
                                     justify-content:space-between; margin-bottom:4px;",
                            h5("Merge datasets",
                               style = "color:#f0f0f0; margin:0; font-size:13px;")
                          ),
                          uiOutput("lp_merge_select_ui"),
                          textInput("lp_merge_label", NULL,
                            placeholder = "Merged dataset name (optional)"),
                          actionButton("lp_merge_btn", "Merge selected",
                            icon  = icon("object-group"),
                            class = "btn-warning btn-block",
                            style = "margin-top:4px;")
                        )
                      ),
                      column(8,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Parse Log", style = "color:#f0f0f0; margin-top:0;"),
                          verbatimTextOutput("lp_parse_log"),
                          hr(),
                          h5("Parsed metadata", style = "color:#f0f0f0;"),
                          verbatimTextOutput("lp_meta_preview")
                        )
                      )
                    )
                  ),

                  # ── Tab 2: Contours ───────────────────────────────────
                  tabPanel(tagList(icon("bullseye"), " Contours"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("sliders-h"), " Contour controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("lp_dataset_selector_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("lp_contour_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Frequency (GHz)</small>"),
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Drain Voltage (V)</small>")),
                            choiceValues = list("global","freq_ghz",
                                                "dataset_tag","vdc_v"),
                            selected = "global"),
                          hr(),
                          checkboxGroupInput("lp_contour_vars", "Overlay contours",
                            choices  = c(
                              "Pout (dBm)" = "pout", "PAE (%)"  = "pae",
                              "DE (%)"     = "de",   "Gain (dB)" = "gain",
                              "Pout (W)"   = "pout_w",
                              "DC Power (W)" = "pdc"),
                            selected = c("pout","pae")),
                          sliderInput("lp_contour_levels", "No. of contour levels",
                            min = 3, max = 12, value = 6, step = 1),
                          hr(),
                          selectInput("lp_pull_type", "Pull plane",
                            choices  = c("Load Pull" = "load", "Source Pull" = "source"),
                            selected = "load"),
                          hr(),
                          strong("Optimal markers", style = "color:#ccc; font-size:12px;"),
                          checkboxInput("lp_show_optima",    "Show MXP/MXE/MXG markers", value = TRUE),
                          checkboxInput("lp_show_max_pae",   "Contour: mark max-PAE",    value = TRUE),
                          checkboxInput("lp_show_max_pout",  "Contour: mark max-Pout",   value = TRUE),
                          hr(),
                          strong("Overlays", style = "color:#ccc; font-size:12px;"),
                          checkboxInput("lp_show_harmonics", "Show 2H/3H \u0393 points",  value = FALSE),
                          checkboxInput("lp_show_stability", "Show stability circles", value = FALSE),
                          checkboxInput("lp_smith_zoom_data", "Zoom to data region",   value = FALSE),
                          hr(),
                          strong(icon("compress-arrows-alt"), " Normalization",
                                 style = "color:#ccc; font-size:12px;"),
                          numericInput("lp_smith_z0_norm",
                            HTML("Reference Z\u2080 (\u03a9) [50 = no change]"),
                            value = 50, min = 1, max = 10000, step = 1),
                          hr(),
                          strong(icon("bolt"), " Compression filter",
                                 style = "color:#ccc; font-size:12px;"),
                          p(style = "font-size:11px; color:#999; margin:4px 0;",
                            "Show only impedances near Px dB compression."),
                          numericInput("lp_smith_px_db",
                            "Px compression (dB)  [0 = all points]",
                            value = 2.2, min = 0, max = 10, step = 0.1),
                          numericInput("lp_smith_px_tol",
                            "Tolerance \u00b1 (dB)",
                            value = 0.3, min = 0.05, max = 2, step = 0.05)
                        )
                      ),
                      column(9,
                        div(style = "text-align:right; margin-bottom:3px;",
                          tags$button(class = "lp-sidebar-toggle-btn",
                            title = "Toggle controls sidebar",
                            tags$i(class = "fa fa-chevron-left"))
                        ),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("chart-pie"), " Contours \u2014 All Datasets on One Smith Chart",
                            style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("lp_smith_plot", height = "560px")
                        )
                      )
                    )
                  ),

                  # ── Tab 3: XY Performance ────────────────────────────
                  tabPanel("XY Performance",
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Plot controls", style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("lp_xy_dataset_selector_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("lp_xy_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Frequency (GHz)</small>"),
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Drain Voltage (V)</small>")),
                            choiceValues = list("global","freq_ghz",
                                                "dataset_tag","vdc_v"),
                            selected = "global"),
                          hr(),
                          selectInput("lp_xy_x_var", "X axis",
                            choices = c(
                              "Pout (dBm)" = "pout_dbm",
                              "Pin (dBm)"  = "pin_dbm",
                              "Pavs (dBm)" = "pavs_dbm",
                              "Pout (W)"   = "pout_w",
                              "Pin (W)"    = "pin_w"),
                            selected = "pout_dbm"),
                          checkboxGroupInput("lp_xy_y_vars", "Y axis traces",
                            choices  = c(
                              "PAE (%)"    = "pae_pct",
                              "DE (%)"     = "de_pct",
                              "Gain (dB)"  = "gain_db",
                              "Pout (dBm)" = "pout_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = c("pae_pct","gain_db")),
                          hr(),
                          sliderInput("lp_xy_pin_range", "Pin range (dBm)",
                            min = -20, max = 50, value = c(-5, 35))
                        )
                      ),
                      column(9,
                        div(style = "text-align:right; margin-bottom:3px;",
                          tags$button(class = "lp-sidebar-toggle-btn",
                            title = "Toggle controls sidebar",
                            tags$i(class = "fa fa-chevron-left"))
                        ),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Gain / PAE / DE vs Power",
                            style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("lp_xy_plot", height = "460px")
                        )
                      )
                    )
                  ),

                  # ── Tab 3b: Performance Overview (4 subplots) ─────────
                  tabPanel(tagList(icon("th"), " Performance"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("sliders-h"), " Controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("lp_perf_dataset_selector_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("lp_perf_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Frequency (GHz)</small>"),
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Drain Voltage (V)</small>")),
                            choiceValues = list("global","freq_ghz",
                                                "dataset_tag","vdc_v"),
                            selected = "global"),
                          hr(),
                          selectInput("lp_perf_x_var", "X axis",
                            choices = c(
                              "Pout (dBm)" = "pout_dbm",
                              "Pin (dBm)"  = "pin_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = "pout_dbm"),
                          hr(),
                          strong("Gain plot: secondary Y", style = "color:#ccc; font-size:12px;"),
                          selectInput("lp_perf_gain_y2", NULL,
                            choices = c(
                              "None"       = "none",
                              "PAE (%)"    = "pae_pct",
                              "DE (%)"     = "de_pct",
                              "Pout (dBm)" = "pout_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = "none"),
                          hr(),
                          strong("Efficiency plot: secondary Y", style = "color:#ccc; font-size:12px;"),
                          selectInput("lp_perf_eff_y2", NULL,
                            choices = c(
                              "None"       = "none",
                              "Gain (dB)"  = "gain_db",
                              "Pout (dBm)" = "pout_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = "none"),
                          hr(),
                          strong(icon("project-diagram"), " Smith chart options",
                                 style = "color:#ccc; font-size:12px;"),
                          numericInput("lp_perf_z0_norm",
                            HTML("Normalize to Z\u2080 (\u03a9)"),
                            value = 50, min = 1, max = 10000, step = 1),
                          checkboxInput("lp_perf_show_harmonics",
                            "Show 2H / 3H \u0393 points", value = FALSE),
                          checkboxInput("lp_perf_show_gin",
                            "Show \u0393in (measured)", value = TRUE),
                          checkboxInput("lp_perf_show_opt",
                            "Mark MXP / MXE / MXG", value = TRUE),
                          hr(),
                          strong(icon("eye"), " Point style",
                                 style = "color:#ccc; font-size:12px;"),
                          sliderInput("lp_point_opacity", "Opacity",
                            min = 0.1, max = 1.0, value = 0.75,
                            step = 0.05, width = "100%"),
                          hr(),
                          strong(icon("bolt"), " Compression filter (Smith)",
                                 style = "color:#ccc; font-size:12px;"),
                          numericInput("lp_perf_px_db",
                            "Px compression (dB)  [0 = all]",
                            value = 2.2, min = 0, max = 10, step = 0.1),
                          numericInput("lp_perf_px_tol", "Tolerance \u00b1 (dB)",
                            value = 0.3, min = 0.05, max = 2, step = 0.05)
                        )
                      ),
                      column(9,
                        div(style = "text-align:right; margin-bottom:3px;",
                          tags$button(class = "lp-sidebar-toggle-btn",
                            title = "Toggle controls sidebar",
                            tags$i(class = "fa fa-chevron-left"))
                        ),
                        fluidRow(
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("chart-line"), " Gain",
                                 style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_perf_gain_plot", height = "310px")
                            )
                          ),
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("tachometer-alt"), " Efficiency (PAE / DE)",
                                 style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_perf_eff_plot",  height = "310px")
                            )
                          )
                        ),
                        fluidRow(
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("crosshairs"), " Source \u0393\u209b",
                                 style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_perf_smith_s",   height = "310px")
                            )
                          ),
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("crosshairs"), " Load \u0393\u2097",
                                 style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_perf_smith_l",   height = "310px")
                            )
                          )
                        )
                      )
                    )
                  ),

                  # ── Tab 4: Nose Plot ─────────────────────────────────
                  tabPanel("Nose / Tradeoff",
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Tradeoff plot controls", style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("lp_nose_dataset_selector_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("lp_nose_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Frequency (GHz)</small>"),
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Drain Voltage (V)</small>")),
                            choiceValues = list("global","freq_ghz",
                                                "dataset_tag","vdc_v"),
                            selected = "global"),
                          hr(),
                          selectInput("lp_nose_x_pw", "X axis (Pout / Pin)",
                            choices = c(
                              "Pout (dBm)" = "pout_dbm",
                              "Pin (dBm)"  = "pin_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = "pout_dbm"),
                          checkboxInput("lp_nose_mark_opt", "Mark MXP/MXE/MXG",
                            value = TRUE),
                          checkboxInput("lp_nose_show_labels", "Show annotation labels",
                            value = TRUE),
                          hr(),
                          strong(icon("compress-arrows-alt"), " Normalization",
                            style = "color:#ccc; font-size:12px;"),
                          numericInput("lp_nose_z0_norm",
                            HTML("Reference Z\u2080 (\u03a9) [50 = no change]"),
                            value = 50, min = 1, max = 10000, step = 1),
                          hr(),
                          strong(icon("bolt"), " Compression filter",
                            style = "color:#ccc; font-size:12px;"),
                          p(style = "font-size:11px; color:#999; margin:4px 0;",
                            "Show only points near Px dB compression. 0 = all."),
                          numericInput("lp_nose_px_db",
                            "Px compression (dB)",
                            value = 2.2, min = 0, max = 10, step = 0.1),
                          numericInput("lp_nose_px_tol", "Tolerance \u00b1 (dB)",
                            value = 0.3, min = 0.05, max = 2, step = 0.05),
                          hr(),
                          sliderInput("lp_backoff_db", "Back-off reference (dB)",
                            min = 0, max = 12, value = 6, step = 0.5)
                        )
                      ),
                      column(9,
                        div(style = "text-align:right; margin-bottom:3px;",
                          tags$button(class = "lp-sidebar-toggle-btn",
                            title = "Toggle controls sidebar",
                            tags$i(class = "fa fa-chevron-left"))
                        ),
                        fluidRow(
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("tachometer-alt"), " Efficiency Nose \u2014 MXE per load point",
                                style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_nose_mxe", height = "420px")
                            )
                          ),
                          column(6,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                              h6(icon("chart-line"), " Gain Nose \u2014 MXG per load point",
                                style = "color:#f0f0f0; margin-top:0; margin-bottom:6px;"),
                              plotlyOutput("lp_nose_xy", height = "420px")
                            )
                          )
                        )
                      )
                    )
                  ),

                  # ── Tab 5: AM-PM / AM-AM ─────────────────────────────
                  tabPanel("AM-PM / AM-AM",
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("AM-PM / AM-AM controls", style = "color:#f0f0f0; margin-top:0;"),
                          # ← own selector ID to avoid DOM duplication with XY tab
                          uiOutput("lp_ampm_dataset_selector_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("lp_ampm_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Frequency (GHz)</small>"),
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Drain Voltage (V)</small>")),
                            choiceValues = list("global","freq_ghz",
                                                "dataset_tag","vdc_v"),
                            selected = "global"),
                          hr(),
                          selectInput("lp_ampm_x_var", "X axis",
                            choices = c(
                              "Pin (dBm)"  = "pin_dbm",
                              "Pout (dBm)" = "pout_dbm",
                              "Pout (W)"   = "pout_w"),
                            selected = "pout_dbm"),
                          hr(),
                          p(style = "font-size:11px; color:#999;",
                            icon("info-circle"),
                            " AM-AM: gain compression vs input power (0 dB = linear; -1 dB = P1dB).",
                            " AM-PM: phase distortion in degrees [\u00b0].")
                        )
                      ),
                      column(9,
                        div(style = "text-align:right; margin-bottom:3px;",
                          tags$button(class = "lp-sidebar-toggle-btn",
                            title = "Toggle controls sidebar",
                            tags$i(class = "fa fa-chevron-left"))
                        ),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("compress-arrows-alt"), " AM-AM Compression (dB)",
                            style = "color:#ff7f11; margin-top:0; margin-bottom:6px;"),
                          plotlyOutput("lp_amam_plot", height = "280px")
                        ),
                        br(),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("wave-square"), " AM-PM Phase distortion (\u00b0)",
                            style = "color:#1f77b4; margin-top:0; margin-bottom:6px;"),
                          plotlyOutput("lp_ampm_plot", height = "280px")
                        )
                      )
                    )
                  ),

                  # ── Tab 6: Tabular Summary ───────────────────────────
                  tabPanel(tagList(icon("table"), " Tabular"),
                    br(),
                    div(class = "well",
                      style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                      h5(icon("table"), " Performance summary",
                         style = "color:#f0f0f0; margin-top:0;"),
                      fluidRow(
                        column(4, uiOutput("lp_table_dataset_selector_ui")),
                        column(4, sliderInput("lp_ppeak_backoff",
                          "Pavg back-off from Ppeak (dB)", min = 0, max = 12, value = 6, step = 0.5)),
                        column(4,
                          br(),
                          downloadButton("lp_table_csv", "Download CSV",
                            class = "btn-default btn-sm"))
                      ),
                      fluidRow(
                        column(12,
                          tags$div(
                            style = "margin-top:4px; display:flex; align-items:center; flex-wrap:wrap; gap:12px;",
                            tags$strong(icon("layer-group"), " Split rows by:"),
                            radioButtons("lp_table_split_local", NULL, inline = TRUE,
                              choiceNames  = list("Global", "Frequency (GHz)", "Dataset Tag", "Drain Voltage (V)"),
                              choiceValues = list("global", "freq_ghz", "dataset_tag", "vdc_v"),
                              selected = "global")
                          )
                        )
                      ),
                      hr(),
                      h5(icon("star"), " Optimal operating points: MXP / MXE / MXG",
                         style = "color:#f0f0f0;"),
                      p(class = "text-muted", style = "font-size:11px;",
                        "MXP = max Pout \u2502 MXE = max PAE \u2502 MXG = max Gain. ",
                        "Results split per frequency. Z = Z\u2080\u00d7(1+\u0393)/(1-\u0393)."),
                      DT::DTOutput("lp_table_optima"),
                      hr(),
                      h5(icon("chart-bar"), " Performance at Ppeak (max Pout) per frequency",
                         style = "color:#f0f0f0;"),
                      DT::DTOutput("lp_table_ppeak"),
                      hr(),
                      h5(icon("battery-half"), " Performance at Pavg (Ppeak \u2212 X\u202fdB back-off) per frequency",
                         style = "color:#f0f0f0;"),
                      DT::DTOutput("lp_table_pavg"),
                      hr(),
                      h5(icon("map-pin"), " Selected design load point (Z\u2097)",
                         style = "color:#f0f0f0;"),
                      p(class = "text-muted", style = "font-size:11px;",
                        "Pick the optimum load from MXP / MXE / MXG or enter custom \u0393_L values."),
                      fluidRow(
                        column(3,
                          selectInput("lp_zl_basis", "Basis",
                            choices = c("MXP (max Pout)" = "MXP",
                                        "MXE (max PAE)"  = "MXE",
                                        "MXG (max Gain)" = "MXG",
                                        "Custom \u0393"  = "custom"),
                            selected = "MXE")
                        ),
                        column(3,
                          numericInput("lp_zl_gamma_r", "Custom Re(\u0393_L)", value = 0, min=-1, max=1, step=0.01)
                        ),
                        column(3,
                          numericInput("lp_zl_gamma_i", "Custom Im(\u0393_L)", value = 0, min=-1, max=1, step=0.01)
                        ),
                        column(3,
                          numericInput("lp_zl_z0", "Z\u2080 (\u03a9)", value = 50, min=1, max=1000, step=1)
                        )
                      ),
                      DT::DTOutput("lp_table_selected_zl")
                    )
                  ),

                  # ── Tab 7: Frequency ──────────────────────────────────
                  tabPanel(tagList(icon("chart-line"), " Freq / split(var)"),
                    br(),
                    tabsetPanel(
                      # Sub-tab: vs Frequency
                      tabPanel("vs Frequency",
                        br(),
                        fluidRow(
                          column(3,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                              h5(icon("sliders-h"), " Frequency sweep controls",
                                 style = "color:#f0f0f0; margin-top:0;"),
                              uiOutput("lp_freq_dataset_selector_ui"),
                              hr(),
                              radioButtons("lp_freq_split_local",
                                tagList(icon("layer-group"), " Split / color by:"),
                                inline = TRUE,
                                choiceNames  = list("Global", "Frequency", "Dataset Tag", "Vdc (V)"),
                                choiceValues = list("global", "freq_ghz", "dataset_tag", "vdc_v"),
                                selected = "global"),
                              hr(),
                              checkboxInput("lp_freq_show_p1db", "Show P1dB", value = TRUE),
                              checkboxInput("lp_freq_show_pavg", "Show Pavg (back-off)", value = TRUE),
                              checkboxInput("lp_freq_show_mxp",  "Show MXP",  value = TRUE),
                              checkboxInput("lp_freq_show_mxe",  "Show MXE",  value = TRUE),
                              checkboxInput("lp_freq_show_mxg",  "Show MXG",  value = TRUE),
                              numericInput("lp_freq_backoff", "Pavg back-off (dB)",
                                           value = 6, min = 0, max = 20, step = 0.5),
                              hr(),
                              p(class = "text-muted", style = "font-size:11px;",
                                "MXP: max Pout │ MXE: max PAE │ MXG: max Gain.")
                            )
                          ),
                          column(9,
                            fluidRow(
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("Power vs Frequency", style = "color:#ff7f11; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_pout_plot", height = "230px"))
                              ),
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("Efficiency vs Frequency", style = "color:#1f77b4; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_eff_plot", height = "230px"))
                              )
                            ),
                            br(),
                            fluidRow(
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("Gain vs Frequency", style = "color:#2ca02c; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_gain_plot", height = "230px"))
                              ),
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("ZL vs Frequency", style = "color:#9467bd; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_zl_plot", height = "230px"))
                              )
                            ),
                            br(),
                            fluidRow(
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("ZS vs Frequency", style = "color:#8c564b; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_zs_plot", height = "230px"))
                              ),
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("AM-AM (Gain) vs Frequency", style = "color:#e377c2; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_amam_plot", height = "230px"))
                              )
                            ),
                            br(),
                            fluidRow(
                              column(6,
                                div(class = "well",
                                  style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                                  h6("AM-PM vs Frequency", style = "color:#9467bd; margin:0 0 6px;"),
                                  plotlyOutput("lp_freq_ampm_plot", height = "230px"))
                              )
                            )
                          )
                        )
                      ),
                      # Sub-tab: Spider
                      tabPanel(tagList(icon("circle-notch"), " Spider"),
                        br(),
                        fluidRow(
                          column(3,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                              h5(icon("circle-notch"), " Spider controls",
                                 style = "color:#f0f0f0; margin-top:0;"),
                              uiOutput("lp_spider_dataset_selector_ui"),
                              hr(),
                              p(class = "text-muted", style = "font-size:11px;",
                                "Spokes = frequency points; traces = metrics.",
                                br(), "Metrics (normalised 0\u2013100 %):",
                                br(), "Pout@MXP/P1dB, PAE@MXE/P1dB,",
                                br(), "Gain@MXG/P1dB, |AM-PM|@MXE.")
                            )
                          ),
                          column(9,
                            div(class = "well",
                              style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                              h5("Spider plot: performance vs frequency",
                                 style = "color:#f0f0f0; margin-top:0;"),
                              tabsetPanel(
                                tabPanel("Peak (MXP/MXE/MXG)",
                                  br(),
                                  plotlyOutput("lp_spider_peak_plot", height = "440px")),
                                tabPanel("Peak (Rev.)",
                                  br(),
                                  plotlyOutput("lp_spider_peak_rev_plot", height = "440px")),
                                tabPanel("P1dB",
                                  br(),
                                  plotlyOutput("lp_spider_p1db_plot", height = "440px")),
                                tabPanel("P1dB (Rev.)",
                                  br(),
                                  plotlyOutput("lp_spider_p1db_rev_plot", height = "440px")),
                                tabPanel("Pavg",
                                  br(),
                                  plotlyOutput("lp_spider_pavg_plot", height = "440px")),
                                tabPanel("Pavg (Rev.)",
                                  br(),
                                  plotlyOutput("lp_spider_pavg_rev_plot", height = "440px"))
                              )
                            )
                          )
                        )
                      )
                    )
                  ),

                  # ── Tab 8: LP Report ───────────────────────────────────
                  tabPanel("LP Report",
                    br(),
                    fluidRow(
                      column(4,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Report options", style = "color:#f0f0f0; margin-top:0;"),
                          textInput("lp_rpt_title",    "Report title",
                            value = "Load Pull Report"),
                          textInput("lp_rpt_engineer", "Engineer / Author", value = ""),
                          textInput("lp_rpt_project",  "Project ref",       value = ""),
                          hr(),
                          tags$label("Datasets to include",
                            style = "color:#ccc; font-weight:600; font-size:13px;"),
                          uiOutput("lp_rpt_dataset_selector"),
                          hr(),
                          checkboxGroupInput("lp_rpt_sections", "Include sections",
                            choices  = c(
                              "Smith Chart contours"  = "smith",
                              "XY performance plots"  = "xy",
                              "Nose plot"             = "nose",
                              "Performance overview"  = "perf",
                              "AM-PM / AM-AM"         = "ampm",
                              "Summary table"         = "table",
                              "Parsed metadata"       = "meta"),
                            selected = c("smith","xy","nose","perf","table")),
                          actionButton("lp_rpt_select_all", "Select All",
                            class = "btn-xs btn-default",
                            style = "margin-bottom:6px; font-size:11px;"),
                          hr(),
                          downloadButton("lp_rpt_html",    "Download HTML Report",
                            class = "btn-success btn-block"),
                          br(),
                          downloadButton("lp_rpt_csv_all", "Download All Data (CSV)",
                            class = "btn-default btn-block")
                        )
                      ),
                      column(8,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Report preview", style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("lp_rpt_preview")
                        )
                      )
                    )
                  )
                )
              )
            ),

            # \u2500\u2500 RF CAD Tool tab \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            # ── S-Parameter Viewer tab ───────────────────────────────────────────────
            tabPanel(tagList(icon("wave-square"), " S-Parameters"),
              div(style = "padding:8px 0 4px 0;",
                p(style = "color:#aaa; font-size:12px; margin:0 0 10px 0;",
                  icon("wave-square"),
                  " Import and visualise S-parameter files (Touchstone .s1p/.s2p/.s3p/.s4p).",
                  " Convert between S, Z, Y, h, ABCD and inspect stability."),

                # ── Global parameter type + split-var bar ───────────────────
                div(
                  style = "background:#181828; border:1px solid #2a2a3a;
                           border-radius:4px; padding:6px 14px;
                           margin-bottom:10px; display:flex;
                           align-items:center; flex-wrap:wrap; gap:18px;",
                  div(style = "flex:0 0 auto;",
                    strong(icon("exchange-alt"), " Parameter type:",
                      style = "color:#ccc; font-size:12px; white-space:nowrap;")
                  ),
                  div(style = "flex:0 0 auto;",
                    radioButtons("sp_param_type", NULL,
                      choices  = c("S" = "S", "Z" = "Z", "Y" = "Y",
                                   "h" = "h", "ABCD" = "ABCD"),
                      selected = "S", inline = TRUE)
                  ),
                  div(style = "flex:0 0 190px;",
                    selectInput("sp_global_split_var", NULL,
                      choices  = c("Dataset Tag"     = "dataset_tag",
                                   "Frequency (GHz)" = "freq_ghz"),
                      selected = "dataset_tag", width = "100%")
                  ),
                  p(style = "font-size:11px; color:#666; margin:0;",
                    icon("info-circle"), " Global split/color by")
                ),

                tabsetPanel(id = "sp_tabs",

                  # ── Tab 1: Upload & Manage ────────────────────────────────
                  tabPanel("Upload & Manage",
                    br(),
                    fluidRow(
                      column(4,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("File Import", style = "color:#f0f0f0; margin-top:0;"),
                          fileInput("sp_upload", NULL,
                            multiple    = TRUE,
                            accept      = c(".s1p",".s2p",".s3p",".s4p",
                                            ".snp",".ts",".txt"),
                            buttonLabel = icon("upload"),
                            placeholder = "No file selected"),
                          hr(style = "border-color:#2a2a3a; margin:8px 0;"),
                          strong(icon("tag"), " Dataset tag",
                            style = "color:#ccc; font-size:12px;"),
                          p(style = "font-size:11px; color:#888; margin:2px 0 4px 0;",
                            "Identifies this dataset when comparing multiple files."),
                          checkboxInput("sp_auto_tag",
                            "Auto-tag from filename", value = TRUE),
                          textInput("sp_dataset_tag", NULL,
                            placeholder = "Optional: custom tag"),
                          actionButton("sp_parse_btn", "Parse file(s)",
                            icon = icon("cog"), class = "btn-primary btn-block"),
                          hr(),
                          div(
                            style = "display:flex; align-items:baseline;
                                     justify-content:space-between;
                                     margin-bottom:6px;",
                            h5("Loaded datasets",
                               style = "color:#f0f0f0; margin:0;"),
                            actionButton("sp_clear_all_btn", "Clear all",
                              class = "btn btn-danger",
                              style = "padding:2px 10px; font-size:11px;
                                       line-height:1.6; border-radius:3px;")
                          ),
                          uiOutput("sp_dataset_list"),
                          hr(style = "border-color:#2a2a3a; margin:8px 0;"),
                          h5("Merge datasets",
                             style = "color:#f0f0f0; margin:0; font-size:13px;"),
                          br(),
                          uiOutput("sp_merge_select_ui"),
                          textInput("sp_merge_label", NULL,
                            placeholder = "Merged dataset name (optional)"),
                          actionButton("sp_merge_btn", "Merge selected",
                            icon  = icon("object-group"),
                            class = "btn-warning btn-block",
                            style = "margin-top:4px;")
                        )
                      ),
                      column(8,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5("Parse Log", style = "color:#f0f0f0; margin-top:0;"),
                          verbatimTextOutput("sp_parse_log"),
                          hr(),
                          h5("Parsed metadata", style = "color:#f0f0f0;"),
                          verbatimTextOutput("sp_meta_preview")
                        )
                      )
                    )
                  ),

                  # ── Tab 2: Mag & Phase ────────────────────────────────────
                  tabPanel(tagList(icon("chart-line"), " Mag & Phase"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("sliders-h"), " Controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("sp_mp_ds_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          uiOutput("sp_mp_param_choices_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("sp_mp_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Frequency (GHz)</small>")),
                            choiceValues = list("global","dataset_tag","freq_ghz"),
                            selected = "global"),
                          hr(),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " Parameter type (S/Z/Y/h/ABCD) is set in the bar above.",
                            " For converted types, a 2-port file with per-freq matrices is required.")
                        )
                      ),
                      column(9,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("chart-bar"), " Magnitude (dB) vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_mag_plot", height = "300px")
                        ),
                        br(),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("wave-square"), " Phase (\u00b0) vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_phase_plot", height = "300px")
                        )
                      )
                    )
                  ),

                  # ── Tab 3: Smith Chart ────────────────────────────────────
                  tabPanel(tagList(icon("crosshairs"), " Smith Chart"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("crosshairs"), " Smith Chart controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("sp_smith_ds_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          uiOutput("sp_smith_param_choices_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("sp_smith_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Frequency (GHz)</small>")),
                            choiceValues = list("global","dataset_tag","freq_ghz"),
                            selected = "global"),
                          hr(),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " S11/S22 are plotted as reflection coefficient \u0393.",
                            " S21/S12 are shown for reference (not \u0393).")
                        )
                      ),
                      column(9,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("crosshairs"),
                             " Smith Chart \u2014 S11/S22/\u0393 frequency sweep",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_smith_plot", height = "560px")
                        )
                      )
                    )
                  ),

                  # ── Tab 4: Stability ──────────────────────────────────────
                  tabPanel(tagList(icon("shield-alt"), " Stability"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("shield-alt"), " Stability controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("sp_stab_ds_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          uiOutput("sp_stab_circ_freq_ui"),
                          hr(),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " K > 1 AND \u03bc > 1 \u2192 unconditionally stable.",
                            br(),
                            " Stability circles: solid = load plane, dashed = source plane.",
                            br(),
                            " |\u0394| = |S11\u00b7S22 \u2212 S12\u00b7S21|")
                        )
                      ),
                      column(9,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("chart-line"),
                             " K (Rollett), \u03bc (input/output), |\u0394| vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_stab_kmu_plot", height = "310px")
                        ),
                        br(),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("crosshairs"), " Stability Circles (Smith Chart)",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_stab_circles_plot", height = "450px")
                        ),
                        br(),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("chart-bar"), " MSG / MAG vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " MSG (dashed orange) shown where K < 1 (potentially unstable).",
                            " MAG (green) shown where K ≥ 1 (unconditionally stable)."),
                          plotlyOutput("sp_stab_msg_plot", height = "260px")
                        ),
                        br(),
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("wave-square"), " Group Delay vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " Computed as \u2212d\u03c6/d\u03c9 from unwrapped S-parameter phase."),
                          plotlyOutput("sp_stab_gd_plot", height = "260px")
                        )
                      )
                    )
                  ),

                  # ── Tab 5: Converted Parameters ───────────────────────────
                  tabPanel(tagList(icon("calculator"), " Parameters"),
                    br(),
                    fluidRow(
                      column(3,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                          h5(icon("calculator"), " Parameter conversion controls",
                             style = "color:#f0f0f0; margin-top:0;"),
                          uiOutput("sp_conv_ds_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          uiOutput("sp_conv_param_choices_ui"),
                          hr(style = "border-color:#2a2a3a; margin:6px 0;"),
                          strong("Split / color by",
                            style = "color:#ccc; font-size:11px;"),
                          radioButtons("sp_conv_split_local", NULL,
                            choiceNames  = list("Use global setting",
                              HTML("<small>Dataset Tag</small>"),
                              HTML("<small>Frequency (GHz)</small>")),
                            choiceValues = list("global","dataset_tag","freq_ghz"),
                            selected = "global"),
                          hr(),
                          p(class = "text-muted", style = "font-size:11px;",
                            icon("info-circle"),
                            " Conversions require 2-port S-matrix data per frequency.",
                            " Not available for merged datasets without sp_list."),
                          tags$ul(style = "color:#999; font-size:11px; padding-left:18px;",
                            tags$li(strong("S:"), " Scattering parameters"),
                            tags$li(strong("Z:"), " Impedance matrix"),
                            tags$li(strong("Y:"), " Admittance matrix"),
                            tags$li(strong("h:"), " Hybrid parameters (h11=Z\u1d35\u2099)"),
                            tags$li(strong("ABCD:"), " Chain/transmission matrix")
                          )
                        )
                      ),
                      column(9,
                        div(class = "well",
                          style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:10px;",
                          h5(icon("chart-bar"), " Converted Parameter Magnitude vs Frequency",
                             style = "color:#f0f0f0; margin-top:0;"),
                          plotlyOutput("sp_conv_plot", height = "460px")
                        )
                      )
                    )
                  ),

                  # ── Tab 6: Tabular ────────────────────────────────────────
                  tabPanel(tagList(icon("table"), " Tabular"),
                    br(),
                    div(class = "well",
                      style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                      h5(icon("table"), " S-Parameter data table",
                         style = "color:#f0f0f0; margin-top:0;"),
                      fluidRow(
                        column(4, uiOutput("sp_tbl_ds_ui")),
                        column(4,
                          br(),
                          p(class = "text-muted", style = "font-size:11px;",
                            "Shows data in the selected parameter type (bar above).")
                        ),
                        column(4,
                          br(),
                          downloadButton("sp_table_csv", "Download CSV",
                            class = "btn-default btn-sm"))
                      ),
                      hr(),
                      DT::DTOutput("sp_table_out", height = "540px")
                    )
                  )

                )  # end sp_tabs
              )
            ),  # end S-Parameters tabPanel

            tabPanel(tagList(icon("drafting-compass"), " RF CAD"),
              div(style = "padding:4px 0 2px 0;",
                rfCadUI("rfcad",
                  height  = "calc(100vh - 210px)",
                  compact = TRUE)
              )
            )
          )
        )
      ),

      # \u2500\u2500 Knowledge Base: full tool (was a search-stub) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
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
  serverRfCalculators(input, output, session, state)
  serverRfTools(input, output, session, state)
  serverGuardrails(input, output, session, state)
  serverSettings(input, output, session, state)
  serverReporting(input, output, session, state)
  serverLpViewer(input, output, session, state)
  serverSpViewer(input, output, session, state)
  serverKnowledgeBase(input, output, session, state)
  serverDeviceLib(input, output, session, state)

  # ── Session cleanup ──────────────────────────────────────────────────────
  onStop(function() {
    if (!is.null(db_pool)) poolClose(db_pool)
  })
}
