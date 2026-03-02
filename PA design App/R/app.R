# PA Design App - Main Application Entry Point
# R Shiny application for end-to-end RF Power Amplifier design

library(shiny)
library(shinydashboard)
library(shinyjs)
library(plotly)
library(DT)
library(R6)
library(yaml)
library(DBI)
library(pool)

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

# Load configuration
config <- ConfigManager$new("../config/app_config.yaml")
app_config <- config$get_config()

# Initialize database connection pool (with fallback to demo mode)
db_pool <- NULL
demo_mode <- FALSE

tryCatch({
  db_pool <- dbPool(
    drv = RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST", "localhost"),
    port = Sys.getenv("DB_PORT", "5432"),
    dbname = Sys.getenv("DB_NAME", "pa_design"),
    user = Sys.getenv("DB_USER", "admin"),
    password = Sys.getenv("DB_PASSWORD", "secret"),
    minSize = 1,
    maxSize = 2
  )
  # Test connection
  con <- poolCheckout(db_pool)
  poolReturn(con)
  cat("✓ Database connection established\n")
}, error = function(e) {
  cat("⚠ Database not available - running in DEMO MODE\n")
  cat("  (Theoretical calculations will work, but project data won't persist)\n\n")
  demo_mode <<- TRUE
})

# Initialize managers
if (!demo_mode) {
  project_mgr <- ProjectManager$new(db_pool)
  data_mgr <- DataManager$new(db_pool)
  tag_mgr <- TagManager$new(db_pool)
} else {
  # Demo mode: use NULL for database connections
  project_mgr <- NULL
  data_mgr <- NULL
  tag_mgr <- NULL
}
agent_mgr <- AgentManager$new(config = app_config$ai_agents)

# UI Definition
ui <- dashboardPage(
  skin = "black",
  
  # Header
  dashboardHeader(
    title = span(
      icon("microchip"),
      "PA Design Assistant"
    ),
    tags$li(class = "dropdown",
      tags$a(href = "#", icon("user"), "Profile")
    )
  ),
  
  # Sidebar
  dashboardSidebar(
    useShinyjs(),
    sidebarMenu(
      id = "sidebar_menu",
      menuItem("Dashboard", tabName = "dashboard", icon = icon("tachometer-alt")),
      menuItem("Projects", tabName = "projects", icon = icon("folder-open")),
      menuItem("Design Flow", tabName = "design", icon = icon("project-diagram"),
        menuSubItem("First Principles", tabName = "first_principles"),
        menuSubItem("Theoretical Calc", tabName = "theoretical_calc"),
        menuSubItem("Architecture", tabName = "architecture"),
        menuSubItem("Simulation", tabName = "simulation"),
        menuSubItem("Layout", tabName = "layout"),
        menuSubItem("Measurement", tabName = "measurement")
      ),
      menuItem("Data Manager", tabName = "data", icon = icon("database")),
      menuItem("RF Tools", tabName = "rf_tools", icon = icon("tools"),
        menuSubItem("Smith Chart", tabName = "smith_chart"),
        menuSubItem("RF Converters", tabName = "rf_converters"),
        menuSubItem("MTTF Calculator", tabName = "mttf_calc"),
        menuSubItem("Thermal Analysis", tabName = "thermal_calc")
      ),
      menuItem("AI Agents", tabName = "agents", icon = icon("robot")),
      menuItem("Knowledge Base", tabName = "knowledge", icon = icon("book")),
      menuItem("Settings", tabName = "settings", icon = icon("cog"))
    )
  ),
  
  # Body
  dashboardBody(
    # Custom CSS and JS
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      tags$link(rel = "stylesheet", type = "text/css", href = "css/pa_lineup.css"),
      tags$script(src = "https://d3js.org/d3.v7.min.js"),
      tags$script(src = "js/pa_lineup_canvas.js"),
      tags$style(HTML("
        .skin-black .main-header .logo { background-color: #1b1b1b; }
        .skin-black .main-header .navbar { background-color: #1b1b1b; }
        .content-wrapper { background-color: #0b0b0b; }
        .box { background-color: #1b1b1b; border-top-color: #ff7f11; }
      "))
    ),
    
    tabItems(
      # Dashboard Tab
      tabItem(tabName = "dashboard",
        fluidRow(
          valueBoxOutput("total_projects", width = 3),
          valueBoxOutput("active_projects", width = 3),
          valueBoxOutput("success_rate", width = 3),
          valueBoxOutput("avg_cycle_time", width = 3)
        ),
        fluidRow(
          box(
            title = "Recent Projects",
            width = 8,
            status = "primary",
            solidHeader = TRUE,
            DTOutput("recent_projects_table")
          ),
          box(
            title = "Design Phase Distribution",
            width = 4,
            status = "info",
            solidHeader = TRUE,
            plotlyOutput("phase_distribution")
          )
        ),
        fluidRow(
          box(
            title = "AI Agent Activity",
            width = 12,
            status = "success",
            solidHeader = TRUE,
            plotlyOutput("agent_activity")
          )
        )
      ),
      
      # Projects Tab
      tabItem(tabName = "projects",
        fluidRow(
          box(
            title = "Create New Project",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            textInput("new_project_name", "Project Name"),
            selectInput("new_project_arch", "Architecture Type",
              choices = c("Class-A", "Class-B", "Class-AB", "Class-C", 
                         "Class-D", "Class-E", "Class-F", "Doherty")),
            numericInput("new_project_freq", "Frequency (GHz)", value = 2.4, min = 0.1, max = 100),
            numericInput("new_project_pout", "Target Pout (dBm)", value = 30, min = 0, max = 60),
            actionButton("create_project_btn", "Create Project", 
                        class = "btn-primary", icon = icon("plus"))
          ),
          box(
            title = "All Projects",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            DTOutput("all_projects_table")
          )
        )
      ),
      
      # Theoretical Calculation Tab
      tabItem(tabName = "theoretical_calc",
        h2("Theoretical Calculation Module"),
        fluidRow(
          box(
            title = "Project Selection",
            width = 12,
            status = "primary",
            solidHeader = TRUE,
            collapsible = TRUE,
            selectInput("calc_project_select", "Select Project", choices = NULL),
            verbatimTextOutput("calc_project_specs")
          )
        ),
        fluidRow(
          tabBox(
            width = 12,
            id = "theoretical_calc_tabs",
            
            # ======================================
            # Tab 1: Frequency Planning Tool
            # ======================================
            tabPanel(
              title = tagList(icon("satellite-dish"), "Frequency Planning"),
              value = "freq_planning",
              
              fluidRow(
                column(3,
                  h4("View Mode:"),
                  radioButtons("freq_view_mode", NULL,
                    choices = c("Canvas" = "canvas", "Table" = "table", "Equations" = "equations"),
                    selected = "canvas", inline = TRUE)
                ),
                column(9,
                  fluidRow(
                    column(4,
                      numericInput("freq_target_freq", "Target Frequency (GHz)", value = 28, min = 0.1, max = 300),
                      numericInput("freq_target_power", "Target Power (W)", value = 20, min = 0.1, max = 1000)
                    ),
                    column(8,
                      checkboxInput("freq_show_eff", "PA Efficiency Curves", TRUE),
                      checkboxInput("freq_show_atm", "Atmospheric Attenuation", TRUE),
                      checkboxInput("freq_show_tech", "Technology Suitability", TRUE),
                      checkboxInput("freq_show_6g", "6G Candidate Band", TRUE)
                    )
                  )
                )
              ),
              hr(),
              
              # Canvas View
              conditionalPanel(
                condition = "input.freq_view_mode == 'canvas'",
                plotlyOutput("freq_planning_canvas", height = "600px")
              ),
              
              # Table View
              conditionalPanel(
                condition = "input.freq_view_mode == 'table'",
                DTOutput("freq_planning_table")
              ),
              
              # Equations View
              conditionalPanel(
                condition = "input.freq_view_mode == 'equations'",
                wellPanel(
                  h4("Frequency Planning Equations"),
                  HTML("
                    <h5>PA Efficiency Models:</h5>
                    <ul>
                      <li><b>LDMOS:</b> η<sub>LDMOS</sub>(f) = max(65 - 0.8f, 5%)</li>
                      <li><b>GaN:</b> η<sub>GaN</sub>(f) = max(70 - 0.3f, 20%)</li>
                      <li><b>SiGe:</b> η<sub>SiGe</sub>(f) = max(50 - 0.15f, 10%)</li>
                    </ul>
                    <h5>Atmospheric Attenuation:</h5>
                    <ul>
                      <li><b>O<sub>2</sub> Absorption:</b> L<sub>O2</sub>(f) = 15·exp(-((f-60)²)/(2·5²)) dB/km</li>
                      <li><b>H<sub>2</sub>O Absorption:</b> L<sub>H2O</sub>(f) = 8·exp(-((f-22)²)/(2·3²)) dB/km</li>
                      <li><b>Total:</b> L<sub>atm</sub>(f) = 0.01f + L<sub>O2</sub>(f) + L<sub>H2O</sub>(f)</li>
                    </ul>
                    <h5>Technology Selection:</h5>
                    <ul>
                      <li><b>LDMOS:</b> 0.01 - 4 GHz (High power, macro base stations)</li>
                      <li><b>GaN:</b> 1 - 100 GHz (Best efficiency/power density tradeoff)</li>
                      <li><b>SiGe:</b> 20 - 300 GHz (Sub-THz, 6G applications)</li>
                    </ul>
                  ")
                )
              ),
              
              hr(),
              htmlOutput("freq_recommendation")
            ),
            
            # ======================================
            # Tab 2: Link Budget Calculator
            # ======================================
            tabPanel(
              title = tagList(icon("link"), "Link Budget"),
              value = "link_budget",
              
              fluidRow(
                column(3,
                  h4("View Mode:"),
                  radioButtons("link_view_mode", NULL,
                    choices = c("Canvas" = "canvas", "Table" = "table", "Equations" = "equations"),
                    selected = "canvas", inline = TRUE)
                ),
                column(9,
                  h4("Link Budget Parameters:"),
                  fluidRow(
                    column(6,
                      numericInput("link_tx_power", "Tx Power (dBm)", value = 43, min = -20, max = 80),
                      numericInput("link_tx_gain", "Tx Antenna Gain (dBi)", value = 15, min = -10, max = 50),
                      numericInput("link_freq", "Frequency (GHz)", value = 28, min = 0.1, max = 100),
                      numericInput("link_distance", "Distance (km)", value = 1, min = 0.001, max = 100)
                    ),
                    column(6,
                      numericInput("link_rx_gain", "Rx Antenna Gain (dBi)", value = 15, min = -10, max = 50),
                      numericInput("link_noise_figure", "Rx Noise Figure (dB)", value = 5, min = 0, max = 20),
                      numericInput("link_bandwidth", "Bandwidth (MHz)", value = 100, min = 0.001, max = 10000),
                      numericInput("link_snr_req", "Required SNR (dB)", value = 20, min = 0, max = 50)
                    )
                  ),
                  actionButton("link_calculate", "Calculate Link Budget", class = "btn-success", icon = icon("calculator"))
                )
              ),
              hr(),
              
              # Canvas View
              conditionalPanel(
                condition = "input.link_view_mode == 'canvas'",
                plotlyOutput("link_budget_canvas", height = "600px")
              ),
              
              # Table View
              conditionalPanel(
                condition = "input.link_view_mode == 'table'",
                DTOutput("link_budget_table")
              ),
              
              # Equations View
              conditionalPanel(
                condition = "input.link_view_mode == 'equations'",
                wellPanel(
                  h4("Link Budget Equations"),
                  HTML("
                    <h5>Free Space Path Loss:</h5>
                    <p><b>FSPL (dB)</b> = 20·log<sub>10</sub>(d) + 20·log<sub>10</sub>(f) + 92.45</p>
                    <p>where: d = distance (km), f = frequency (GHz)</p>
                    
                    <h5>Received Power:</h5>
                    <p><b>P<sub>rx</sub> (dBm)</b> = P<sub>tx</sub> + G<sub>tx</sub> - FSPL + G<sub>rx</sub></p>
                    
                    <h5>Thermal Noise Power:</h5>
                    <p><b>N (dBm)</b> = -174 + 10·log<sub>10</sub>(BW) + NF</p>
                    <p>where: BW = bandwidth (Hz), NF = noise figure (dB)</p>
                    
                    <h5>Signal-to-Noise Ratio:</h5>
                    <p><b>SNR (dB)</b> = P<sub>rx</sub> - N</p>
                    
                    <h5>Link Margin:</h5>
                    <p><b>Margin (dB)</b> = SNR - SNR<sub>required</sub></p>
                    
                    <h5>Additional Losses (typical):</h5>
                    <ul>
                      <li><b>Atmospheric:</b> 0.1 - 2 dB/km (frequency dependent)</li>
                      <li><b>Rain:</b> 0.5 - 20 dB (rain rate dependent)</li>
                      <li><b>Polarization mismatch:</b> 0.5 - 3 dB</li>
                      <li><b>Implementation loss:</b> 1 - 3 dB</li>
                    </ul>
                  ")
                )
              ),
              
              hr(),
              htmlOutput("link_budget_summary")
            ),
            
            # ======================================
            # Tab 3: PA Lineup Calculator (Enhanced Interactive)
            # ======================================
            tabPanel(
              title = tagList(icon("project-diagram"), "PA Lineup"),
              value = "pa_lineup",
              
              fluidRow(
                # Left: Interactive Canvas
                column(8,
                  box(
                    title = tagList(icon("paint-brush"), "Interactive PA Lineup Canvas"),
                    width = 12,
                    status = "info",
                    solidHeader = TRUE,
                    div(
                      id = "pa_lineup_canvas_container", 
                      style = "position: relative;",
                      
                      # Floating top sidebar for architecture templates
                      div(
                        id = "canvas_top_sidebar",
                        class = "canvas-top-sidebar collapsed",
                        
                        # Toggle button
                        tags$button(
                          id = "top_sidebar_toggle",
                          class = "top-sidebar-toggle",
                          onclick = "toggleCanvasTopSidebar()",
                          icon("chevron-down"),
                          " Templates"
                        ),
                        
                        # Top sidebar content
                        div(
                          class = "top-sidebar-content",
                          div(class = "top-sidebar-title", icon("layer-group"), " Architecture Templates"),
                          div(class = "top-sidebar-templates",
                            div(class = "preset-template", `data-preset` = "triple_stage",
                              h5("3-Stage Cascade"),
                              p("Pre-driver → Driver → Final PA")
                            ),
                            div(class = "preset-template", `data-preset` = "single_doherty",
                              h5("Single Driver Doherty"),
                              p("Driver → Splitter → Main/Aux PA")
                            ),
                            div(class = "preset-template", `data-preset` = "dual_doherty",
                              h5("Dual Driver Doherty"),
                              p("Dual drivers → Main/Aux paths")
                            ),
                            div(class = "preset-template", `data-preset` = "blank",
                              h5("Blank Canvas"),
                              p("Start from scratch")
                            )
                          )
                        )
                      ),
                      
                      # Floating right sidebar for canvas actions
                      div(
                        id = "canvas_sidebar",
                        class = "canvas-sidebar collapsed",
                        
                        # Toggle button
                        tags$button(
                          id = "sidebar_toggle",
                          class = "sidebar-toggle",
                          onclick = "toggleCanvasSidebar()",
                          icon("chevron-left"),
                          title = "Canvas Actions"
                        ),
                        
                        # Sidebar content
                        div(
                          class = "sidebar-content",
                          
                          # Zoom Controls Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("search"), " Zoom"),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.zoomIn();",
                              class = "btn btn-default btn-block btn-sm",
                              icon("search-plus"),
                              " Zoom In"
                            ),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.zoomOut();",
                              class = "btn btn-default btn-block btn-sm",
                              icon("search-minus"),
                              " Zoom Out"
                            ),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.resetZoom();",
                              class = "btn btn-default btn-block btn-sm",
                              icon("home"),
                              " Reset View"
                            )
                          ),
                          
                          # Component Actions Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("cogs"), " Actions"),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.deleteSelected();",
                              class = "btn btn-danger btn-block btn-sm",
                              icon("trash"),
                              " Delete"
                            ),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.toggleWireMode();",
                              id = "wire_mode_btn",
                              class = "btn btn-info btn-block btn-sm",
                              icon("project-diagram"),
                              " Wire Mode"
                            ),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.clear();",
                              class = "btn btn-warning btn-block btn-sm",
                              icon("eraser"),
                              " Clear All"
                            )
                          ),
                          
                          # File Actions Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("file"), " File"),
                            actionButton("lineup_save_config", "Save", icon = icon("save"), class = "btn-success btn-block btn-sm"),
                            actionButton("lineup_load_config", "Load", icon = icon("folder-open"), class = "btn-default btn-block btn-sm"),
                            actionButton("lineup_export_diagram", "Export", icon = icon("image"), class = "btn-default btn-block btn-sm"),
                            actionButton("lineup_generate_report", "Report", icon = icon("file-pdf"), class = "btn-default btn-block btn-sm")
                          )
                        )
                      )
                    )
                  )
                ),
                
                # Right: Component Properties & Results
                column(4,
                  # Component Property Editor
                  box(
                    title = "Component Properties",
                    width = 12,
                    collapsible = TRUE,
                    status = "warning",
                    solidHeader = TRUE,
                    uiOutput("lineup_property_editor")
                  ),
                  
                  # Calculation Results
                  box(
                    title = "Calculation Results",
                    width = 12,
                    status = "success",
                    solidHeader = TRUE,
                    actionButton("lineup_calculate", "Calculate Lineup", class = "btn-success btn-block", icon = icon("calculator")),
                    hr(),
                    uiOutput("lineup_calc_results")
                  ),
                  
                  # Version Control
                  box(
                    title = "Version Control",
                    width = 12,
                    status = "primary",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,
                    textInput("lineup_version_name", "Version Name", placeholder = "v1.0"),
                    textAreaInput("lineup_version_notes", "Notes", placeholder = "Description of changes...", rows = 3),
                    actionButton("lineup_save_version", "Save as New Version", class = "btn-primary btn-block", icon = icon("code-branch")),
                    hr(),
                    uiOutput("lineup_version_list")
                  )
                )
              ),
              
              # View Tabs Below Canvas
              fluidRow(
                tabBox(
                  width = 12,
                  
                  # Table View
                  tabPanel(
                    title = tagList(icon("table"), "Table View"),
                    DTOutput("pa_lineup_table")
                  ),
                  
                  # Equations View
                  tabPanel(
                    title = tagList(icon("calculator"), "Equations & Rationale"),
                    wellPanel(
                      h4("PA Lineup Equations"),
                      HTML("
                        <h5>Power Cascade:</h5>
                        <p><b>P<sub>out,i</sub> (dBm)</b> = P<sub>in,i</sub> + G<sub>i</sub></p>
                        <p><b>P<sub>in,i+1</sub></b> = P<sub>out,i</sub></p>
                        
                        <h5>Total Gain:</h5>
                        <p><b>G<sub>total</sub> (dB)</b> = Σ G<sub>i</sub></p>
                        
                        <h5>Power Dissipation (per stage):</h5>
                        <p><b>P<sub>diss,i</sub> (W)</b> = P<sub>out,i</sub>(W) · (1/PAE<sub>i</sub> - 1)</p>
                        
                        <h5>DC Power (per stage):</h5>
                        <p><b>P<sub>DC,i</sub> (W)</b> = P<sub>out,i</sub>(W) / PAE<sub>i</sub></p>
                        
                        <h5>Total System PAE:</h5>
                        <p><b>PAE<sub>total</sub></b> = P<sub>out,final</sub> / Σ P<sub>DC,i</sub></p>
                        
                        <h5>Compression Check:</h5>
                        <p>For each stage: <b>P<sub>out,i</sub> ≤ P1dB<sub>i</sub></b></p>
                        <p>If P<sub>out,i</sub> > P1dB<sub>i</sub>: <span style='color:red;'>⚠ Compression Warning</span></p>
                        
                        <h5>For Doherty Architecture:</h5>
                        <p><b>Load Modulation:</b> Main PA operates at higher impedance at backoff</p>
                        <p><b>Auxiliary Turn-on:</b> Typically at 6dB backoff from P1dB</p>
                        <p><b>Combining Efficiency:</b> Accounts for impedance transformation losses</p>
                        
                        <h5>Thermal Calculations:</h5>
                        <p><b>Junction Temp:</b> T<sub>j</sub> = T<sub>a</sub> + P<sub>diss</sub> · R<sub>θja</sub></p>
                      ")
                    ),
                    hr(),
                    h4("Calculation Rationale:"),
                    verbatimTextOutput("lineup_rationale"),
                    hr(),
                    textAreaInput("lineup_custom_notes", "Design Notes:", 
                      placeholder = "Add your notes, justifications, or remarks here...",
                      rows = 4)
                  )
                )
              )
            )
          )
        )
      ),
      
      # Placeholder tabs (to be implemented)
      tabItem(tabName = "first_principles",
        h2("First Principles Module"),
        p("Module under construction - validates design feasibility based on fundamental RF theory.")
      ),
      
      tabItem(tabName = "architecture",
        h2("Architecture Selection Module"),
        p("Module under construction - recommends PA architecture and topology.")
      ),
      
      tabItem(tabName = "simulation",
        h2("Simulation Module"),
        p("Module under construction - integrates with ADS/AWR via MCP.")
      ),
      
      tabItem(tabName = "layout",
        h2("Layout Module"),
        p("Module under construction - reviews layout for RF best practices.")
      ),
      
      tabItem(tabName = "measurement",
        h2("Measurement Module"),
        p("Module under construction - controls lab equipment and analyzes data.")
      ),
      
      # RF Tools: Smith Chart
      tabItem(tabName = "smith_chart",
        h2("📊 Smith Chart Visualization"),
        fluidRow(
          box(
            title = "Impedance/Admittance Entry",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            selectInput("smith_mode", "Chart Mode",
              choices = c("Impedance", "Admittance", "Combined")),
            numericInput("smith_z_real", "Z Real (Ω)", value = 50, min = -500, max = 500),
            numericInput("smith_z_imag", "Z Imaginary (Ω)", value = 0, min = -500, max = 500),
            numericInput("smith_freq", "Frequency (GHz)", value = 2.4, min = 0.1, max = 100),
            hr(),
            actionButton("smith_add_point", "Add Point", class = "btn-primary", icon = icon("plus")),
            actionButton("smith_clear", "Clear All", class = "btn-warning", icon = icon("trash")),
            hr(),
            h4("Matching Network Design:"),
            selectInput("smith_match_type", "Network Type",
              choices = c("Single Stub", "Double Stub", "L-Section", "Pi-Network", "T-Network")),
            actionButton("smith_design_match", "Design Network", class = "btn-success", icon = icon("calculator"))
          ),
          box(
            title = "Smith Chart",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            p("Interactive Smith Chart with matching network visualization"),
            plotlyOutput("smith_chart_plot", height = "600px"),
            hr(),
            h4("Component Values:"),
            verbatimTextOutput("smith_components")
          )
        )
      ),
      
      # RF Tools: Converters
      tabItem(tabName = "rf_converters",
        h2("🔄 RF Unit Converters"),
        fluidRow(
          box(
            title = "Power Conversions",
            width = 6,
            status = "primary",
            solidHeader = TRUE,
            numericInput("conv_power_watt", "Power (Watt)", value = 1, min = 0),
            verbatimTextOutput("conv_power_results"),
            hr(),
            numericInput("conv_power_dbm", "Power (dBm)", value = 30, min = -100, max = 100),
            verbatimTextOutput("conv_dbm_results")
          ),
          box(
            title = "Voltage/Field Conversions",
            width = 6,
            status = "info",
            solidHeader = TRUE,
            numericInput("conv_voltage", "Voltage (V)", value = 1, min = 0),
            numericInput("conv_impedance", "Impedance (Ω)", value = 50, min = 0.1),
            verbatimTextOutput("conv_voltage_results")
          )
        ),
        fluidRow(
          box(
            title = "Frequency/Wavelength Conversions",
            width = 6,
            status = "warning",
            solidHeader = TRUE,
            numericInput("conv_freq", "Frequency (GHz)", value = 2.4, min = 0.001),
            selectInput("conv_medium", "Medium",
              choices = c("Free Space" = 1, "FR4 (εr=4.4)" = 4.4, "Rogers RO4003 (εr=3.55)" = 3.55, "Custom" = 0)),
            conditionalPanel(
              condition = "input.conv_medium == 0",
              numericInput("conv_er_custom", "Custom εr", value = 1, min = 1, max = 20)
            ),
            verbatimTextOutput("conv_freq_results")
          ),
          box(
            title = "S-Parameters & Reflection Coefficient",
            width = 6,
            status = "success",
            solidHeader = TRUE,
            numericInput("conv_s11_mag", "S11 Magnitude", value = 0.1, min = 0, max = 1, step = 0.01),
            numericInput("conv_s11_phase", "S11 Phase (degrees)", value = 0, min = -180, max = 180),
            verbatimTextOutput("conv_sparams_results")
          )
        )
      ),
      
      # RF Tools: MTTF Calculator
      tabItem(tabName = "mttf_calc",
        h2("⏱️ MTTF (Mean Time To Failure) Calculator"),
        fluidRow(
          box(
            title = "Device Parameters",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            selectInput("mttf_device_type", "Device Type",
              choices = c("LDMOS", "GaN HEMT", "SiGe HBT", "GaAs MESFET", "Custom")),
            numericInput("mttf_tj", "Junction Temperature (°C)", value = 125, min = -55, max = 300),
            numericInput("mttf_ta", "Ambient Temperature (°C)", value = 25, min = -55, max = 150),
            numericInput("mttf_power_diss", "Power Dissipation (W)", value = 10, min = 0.1, max = 1000),
            numericInput("mttf_rth", "Thermal Resistance Rθjc (°C/W)", value = 5, min = 0.1, max = 100),
            hr(),
            h4("Stress Factors:"),
            numericInput("mttf_voltage_stress", "Voltage Stress Factor", value = 1.0, min = 0.5, max = 2, step = 0.1),
            numericInput("mttf_current_stress", "Current Stress Factor", value = 1.0, min = 0.5, max = 2, step = 0.1),
            hr(),
            actionButton("mttf_calculate", "Calculate MTTF", class = "btn-success", icon = icon("calculator"))
          ),
          box(
            title = "Reliability Results",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            h4("MTTF Analysis:"),
            verbatimTextOutput("mttf_results"),
            hr(),
            plotlyOutput("mttf_plot", height = "400px"),
            hr(),
            h4("Reliability Recommendations:"),
            htmlOutput("mttf_recommendations")
          )
        )
      ),
      
      # RF Tools: Thermal Analysis
      tabItem(tabName = "thermal_calc",
        h2("🌡️ Thermal Analysis"),
        fluidRow(
          box(
            title = "Thermal Network Parameters",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            h4("Power Dissipation:"),
            numericInput("therm_pout", "Output Power (W)", value = 20, min = 0.1, max = 1000),
            numericInput("therm_efficiency", "PAE (%)", value = 50, min = 1, max = 90),
            verbatimTextOutput("therm_pdiss"),
            hr(),
            h4("Thermal Resistances:"),
            numericInput("therm_rth_jc", "Rθjc (Junction-to-Case) (°C/W)", value = 2, min = 0.1, max = 50),
            numericInput("therm_rth_cs", "Rθcs (Case-to-Sink) (°C/W)", value = 0.5, min = 0.01, max = 10),
            numericInput("therm_rth_sa", "Rθsa (Sink-to-Ambient) (°C/W)", value = 3, min = 0.1, max = 50),
            hr(),
            numericInput("therm_ta", "Ambient Temperature (°C)", value = 25, min = -55, max = 150),
            numericInput("therm_tj_max", "Max Junction Temp (°C)", value = 150, min = 50, max = 300),
            hr(),
            actionButton("therm_calculate", "Calculate Thermal Profile", class = "btn-success", icon = icon("fire"))
          ),
          box(
            title = "Thermal Analysis Results",
            width = 8,
            status = "danger",
            solidHeader = TRUE,
            h4("Temperature Profile:"),
            verbatimTextOutput("therm_results"),
            hr(),
            plotlyOutput("therm_plot", height = "400px"),
            hr(),
            h4("Heatsink Recommendations:"),
            htmlOutput("therm_recommendations")
          )
        )
      ),
      
      # Settings Tab
      tabItem(tabName = "settings",
        h2("Application Settings"),
        fluidRow(
          box(
            title = "Theme Settings",
            width = 6,
            selectInput("theme_select", "Theme",
              choices = c("Dark Mode" = "dark", "Light Mode" = "light", "Colorblind Mode" = "colorblind")),
            selectInput("accent_color", "Accent Color",
              choices = c("Orange" = "#ff7f11", "Blue" = "#1f77b4", "Green" = "#2ca02c"))
          ),
          box(
            title = "AI Agent Configuration",
            width = 6,
            checkboxInput("agents_enabled", "Enable AI Agents", value = TRUE),
            selectInput("llm_model", "LLM Model",
              choices = c("GPT-4", "GPT-3.5-turbo", "Claude-3-Opus")),
            sliderInput("agent_confidence_threshold", "Confidence Threshold", 
                       min = 0, max = 1, value = 0.7, step = 0.05)
          )
        )
      )
    )
  )
)

# Server Logic
server <- function(input, output, session) {
  
  # Reactive values
  rv <- reactiveValues(
    current_project = NULL,
    projects = data.frame()
  )
  
  # Load projects on startup
  observe({
    if (!demo_mode && !is.null(project_mgr)) {
      rv$projects <- project_mgr$get_all_projects()
    } else {
      # Demo mode: use sample data
      rv$projects <- data.frame(
        id = c("demo-1", "demo-2", "demo-3"),
        name = c("5G PA 3.5GHz", "WiFi 6E 6GHz", "Sub-6 GaN"),
        architecture_type = c("Doherty", "Class-AB", "Class-E"),
        frequency = c(3500, 6000, 2600),
        target_pout = c(43, 30, 40),
        status = c("active", "active", "completed"),
        created_at = Sys.time(),
        stringsAsFactors = FALSE
      )
    }
    
    # Update project selection dropdowns
    project_choices <- setNames(rv$projects$id, rv$projects$name)
    updateSelectInput(session, "calc_project_select", choices = project_choices)
  })
  
  # Dashboard: Value Boxes
  output$total_projects <- renderValueBox({
    valueBox(
      nrow(rv$projects),
      "Total Projects",
      icon = icon("folder"),
      color = "blue"
    )
  })
  
  output$active_projects <- renderValueBox({
    active_count <- sum(rv$projects$status == "active", na.rm = TRUE)
    valueBox(
      active_count,
      "Active Projects",
      icon = icon("play-circle"),
      color = "green"
    )
  })
  
  output$success_rate <- renderValueBox({
    valueBox(
      "85%",
      "Success Rate",
      icon = icon("check-circle"),
      color = "yellow"
    )
  })
  
  output$avg_cycle_time <- renderValueBox({
    valueBox(
      "42 days",
      "Avg Cycle Time",
      icon = icon("clock"),
      color = "purple"
    )
  })
  
  # Dashboard: Recent Projects Table
  output$recent_projects_table <- renderDT({
    datatable(
      head(rv$projects, 10),
      options = list(pageLength = 5, dom = 't'),
      selection = 'single'
    )
  })
  
  # Dashboard: Phase Distribution Plot
  output$phase_distribution <- renderPlotly({
    phases <- c("Concept", "Calculation", "Simulation", "Layout", "Measurement")
    counts <- c(3, 5, 8, 2, 1)
    
    plot_ly(labels = phases, values = counts, type = 'pie',
            marker = list(colors = c('#ff7f11', '#ff9f3f', '#ffbf6b', '#ffd89b', '#fff0cc'))) %>%
      layout(showlegend = TRUE, paper_bgcolor = '#0b0b0b', plot_bgcolor = '#0b0b0b',
             font = list(color = '#cfcfcf'))
  })
  
  # Dashboard: Agent Activity
  output$agent_activity <- renderPlotly({
    agents <- c("Theory", "Architecture", "Simulation", "Layout", "Measurement")
    activity <- c(45, 32, 67, 23, 15)
    
    plot_ly(x = agents, y = activity, type = 'bar',
            marker = list(color = '#ff7f11')) %>%
      layout(
        title = "Agent Calls (Last 7 Days)",
        paper_bgcolor = '#0b0b0b',
        plot_bgcolor = '#1b1b1b',
        font = list(color = '#cfcfcf'),
        xaxis = list(title = "Agent", color = '#cfcfcf'),
        yaxis = list(title = "Number of Calls", color = '#cfcfcf')
      )
  })
  
  # Projects: All Projects Table
  output$all_projects_table <- renderDT({
    datatable(
      rv$projects,
      options = list(pageLength = 10),
      selection = 'single'
    )
  })
  
  # Projects: Create New Project
  observeEvent(input$create_project_btn, {
    req(input$new_project_name)
    
    if (!demo_mode && !is.null(project_mgr)) {
      new_project <- project_mgr$create_project(
        name = input$new_project_name,
        architecture_type = input$new_project_arch,
        frequency = input$new_project_freq,
        target_pout = input$new_project_pout
      )
      
      rv$projects <- project_mgr$get_all_projects()
      
      showNotification(
        paste("Project", input$new_project_name, "created successfully!"),
        type = "message",
        duration = 3
      )
    } else {
      # Demo mode: show info message
      showNotification(
        "Demo Mode: Project creation requires database connection. Use theoretical calculations to test features.",
        type = "warning",
        duration = 5
      )
    }
    
    # Clear inputs
    updateTextInput(session, "new_project_name", value = "")
  })
  
  # Theoretical Calc: Display Project Specs
  output$calc_project_specs <- renderPrint({
    req(input$calc_project_select)
    
    project <- rv$projects[rv$projects$id == input$calc_project_select, ]
    
    if (nrow(project) > 0) {
      cat("Project:", project$name, "\n")
      cat("Architecture:", project$architecture_type, "\n")
      cat("Frequency:", project$frequency, "GHz\n")
      cat("Target Pout:", project$target_pout, "dBm\n")
    }
  })
  
  # Theoretical Calc: Load-Pull Calculation
  observeEvent(input$calc_loadpull_btn, {
    req(input$calc_vdd, input$calc_imax)
    
    # Simple load-pull calculation (Class-A approximation)
    pout_watts <- (input$calc_vdd * input$calc_imax) / 2
    pout_dbm <- 10 * log10(pout_watts * 1000)
    z_load <- (input$calc_vdd^2) / (2 * pout_watts)
    
    output$calc_loadpull_results <- renderPrint({
      cat("Optimal Load Impedance (Class-A):\n")
      cat("  Zload =", round(z_load, 2), "Ω\n")
      cat("  Pout (max) =", round(pout_watts, 2), "W (", round(pout_dbm, 1), "dBm)\n")
      cat("  PAE (theoretical max) ≈ 50%\n")
    })
    
    showNotification("Load-pull calculation completed", type = "message")
  })
  
  # Theoretical Calc: Matching Network Synthesis
  observeEvent(input$calc_match_btn, {
    req(input$calc_z_source, input$calc_z_load, input$calc_freq)
    
    z_s <- input$calc_z_source
    z_l <- input$calc_z_load
    freq <- input$calc_freq * 1e9  # Convert to Hz
    
    # Simple L-section matching calculation
    if (z_s > z_l) {
      # Step-down network
      q <- sqrt(z_s / z_l - 1)
      x_series <- q * z_l
      b_parallel <- q / z_s
      
      l_series <- x_series / (2 * pi * freq) * 1e9  # nH
      c_parallel <- b_parallel / (2 * pi * freq) * 1e12  # pF
      
      output$calc_match_results <- renderPrint({
        cat("L-Section Step-Down Network:\n")
        cat("  Series Inductor:", round(l_series, 2), "nH\n")
        cat("  Parallel Capacitor:", round(c_parallel, 2), "pF\n")
        cat("  Q-factor:", round(q, 2), "\n")
      })
    } else {
      # Step-up network
      q <- sqrt(z_l / z_s - 1)
      b_series <- q / z_l
      x_parallel <- q * z_s
      
      c_series <- b_series / (2 * pi * freq) * 1e12  # pF
      l_parallel <- x_parallel / (2 * pi * freq) * 1e9  # nH
      
      output$calc_match_results <- renderPrint({
        cat("L-Section Step-Up Network:\n")
        cat("  Series Capacitor:", round(c_series, 2), "pF\n")
        cat("  Parallel Inductor:", round(l_parallel, 2), "nH\n")
        cat("  Q-factor:", round(q, 2), "\n")
      })
    }
    
    showNotification("Matching network synthesized", type = "message")
  })
  
  # Theoretical Calc: Ask Theory Agent
  observeEvent(input$calc_ask_theory_btn, {
    req(input$calc_theory_query)
    
    showNotification("Theory Agent is processing your query...", type = "message", duration = NULL, id = "theory_notif")
    
    # Call Theory Agent
    tryCatch({
      response <- agent_mgr$call_agent(
        agent_name = "TheoryAgent",
        task = list(
          query = input$calc_theory_query,
          context = list(
            project_id = input$calc_project_select,
            frequency = input$calc_freq
          )
        )
      )
      
      output$calc_theory_response <- renderPrint({
        cat("Theory Agent Response:\n\n")
        cat(response$answer, "\n\n")
        cat("Confidence:", response$confidence, "\n")
        if (!is.null(response$references)) {
          cat("\nReferences:\n")
          cat(paste(response$references, collapse = "\n"))
        }
      })
      
      removeNotification("theory_notif")
      showNotification("Theory Agent response received", type = "message", duration = 3)
      
    }, error = function(e) {
      removeNotification("theory_notif")
      showNotification(paste("Error:", e$message), type = "error", duration = 5)
      
      output$calc_theory_response <- renderPrint({
        cat("Theory Agent is not yet fully implemented.\n")
        cat("Mock response for demo purposes:\n\n")
        cat("Based on your specifications, the fundamental limits are:\n")
        cat("- Bode-Fano limit constrains matching bandwidth\n")
        cat("- Maximum theoretical PAE for Class-A: 50%\n")
        cat("- For higher efficiency, consider Class-E or Class-F\n")
      })
    })
  })
  
  # ============================================================
  # RF Frequency Planning Tool (Integrated)
  # ============================================================
  
  # Physical Models
  atm_loss_model <- function(fGHz) {
    o2_peak <- 15 * exp(-((fGHz - 60)^2) / (2*5^2))
    h2o_peak <- 8 * exp(-((fGHz - 22)^2) / (2*3^2))
    baseline <- 0.01 * fGHz
    baseline + o2_peak + h2o_peak
  }
  
  eff_ldmos <- function(f) pmax(65 - 0.8*f, 5)
  eff_gan   <- function(f) pmax(70 - 0.3*f, 20)
  eff_sige  <- function(f) pmax(50 - 0.15*f, 10)
  
  # Frequency Planning Canvas
  output$freq_planning_canvas <- renderPlotly({
    
    f <- seq(0.1, 300, length.out = 800)
    
    fig <- plot_ly()
    
    # Technology Suitability Map
    if(input$freq_show_tech){
      tech_map <- data.frame(
        tech = c("LDMOS","GaN","SiGe"),
        fmin = c(0.01, 1, 20),
        fmax = c(4, 100, 300),
        color = c("rgba(0,0,255,0.15)",
                  "rgba(0,255,0,0.15)",
                  "rgba(255,0,0,0.15)")
      )
      
      for(i in 1:nrow(tech_map)){
        fig <- fig %>%
          add_trace(
            x = c(tech_map$fmin[i], tech_map$fmax[i],
                  tech_map$fmax[i], tech_map$fmin[i], tech_map$fmin[i]),
            y = c(0, 0, 100, 100, 0),
            type = "scatter",
            mode = "lines",
            fill = "toself",
            fillcolor = tech_map$color[i],
            line = list(width = 0),
            name = tech_map$tech[i],
            hoverinfo = "text",
            text = paste("Technology:", tech_map$tech[i])
          )
      }
    }
    
    # Efficiency curves
    if(input$freq_show_eff){
      fig <- fig %>%
        add_lines(x = f, y = eff_ldmos(f), name = "LDMOS Efficiency (%)") %>%
        add_lines(x = f, y = eff_gan(f), name = "GaN Efficiency (%)") %>%
        add_lines(x = f, y = eff_sige(f), name = "SiGe Efficiency (%)")
    }
    
    # Atmospheric attenuation
    if(input$freq_show_atm){
      fig <- fig %>%
        add_lines(x = f, y = atm_loss_model(f),
                  name = "Atmospheric Loss (dB/km)",
                  yaxis = "y2")
    }
    
    # 6G band
    if(input$freq_show_6g){
      fig <- fig %>%
        add_trace(
          x = c(100, 300, 300, 100, 100),
          y = c(0, 0, 100, 100, 0),
          type = "scatter",
          fill = "toself",
          fillcolor = "rgba(200,0,200,0.2)",
          line = list(width = 0),
          name = "6G Sub-THz",
          hoverinfo = "text",
          text = "6G Candidate Band"
        )
    }
    
    # Target marker
    fig <- fig %>%
      add_markers(x = input$freq_target_freq,
                  y = 60,
                  marker = list(size = 12, color = "red"),
                  name = "Target Frequency")
    
    fig %>%
      layout(
        title = "Interactive Frequency Planning Canvas",
        xaxis = list(title = "Frequency (GHz)", type = "log",
                     range = c(log10(0.1), log10(300))),
        yaxis = list(title = "Efficiency (%)"),
        yaxis2 = list(title = "Atmospheric Loss (dB/km)",
                      overlaying = "y",
                      side = "right"),
        legend = list(orientation = "h"),
        hovermode = "closest"
      )
  })
  
  # Frequency Planning Table
  output$freq_planning_table <- renderDT({
    f_target <- input$freq_target_freq
    
    data <- data.frame(
      Parameter = c("Target Frequency", "LDMOS Efficiency", "GaN Efficiency", "SiGe Efficiency",
                    "Atmospheric Loss", "Wavelength (free space)", "Recommended Technology"),
      Value = c(
        sprintf("%.2f GHz", f_target),
        sprintf("%.1f%%", eff_ldmos(f_target)),
        sprintf("%.1f%%", eff_gan(f_target)),
        sprintf("%.1f%%", eff_sige(f_target)),
        sprintf("%.2f dB/km", atm_loss_model(f_target)),
        sprintf("%.2f mm", 3e8 / (f_target * 1e9) * 1000),
        if(f_target < 4) "LDMOS" else if(f_target < 100) "GaN" else "SiGe"
      )
    )
    
    datatable(data, options = list(pageLength = 10, dom = 't'), rownames = FALSE)
  })
  
  # Technology Recommendation
  output$freq_recommendation <- renderUI({
    
    f <- input$freq_target_freq
    
    tech <- if(f < 4) {
      "LDMOS (High power, macro base stations)"
    } else if(f < 100) {
      "GaN (Best tradeoff efficiency & power density)"
    } else {
      "SiGe / Advanced GaN MMIC (Sub-THz)"
    }
    
    HTML(paste0(
      "<h4>Recommended Technology</h4>",
      "<b>Frequency:</b> ", f, " GHz<br>",
      "<b>Output Power:</b> ", input$freq_target_power, " W<br><br>",
      "<b>Suggested Device:</b> ", tech
    ))
  })
  
  # ============================================================
  # Link Budget Calculator
  # ============================================================
  
  # Reactive values for link budget
  link_budget_data <- reactive({
    input$link_calculate
    
    # Calculate FSPL (Free Space Path Loss)
    fspl <- 20 * log10(input$link_distance) + 20 * log10(input$link_freq) + 92.45
    
    # Calculate received power
    p_rx <- input$link_tx_power + input$link_tx_gain - fspl + input$link_rx_gain
    
    # Calculate noise power
    bw_hz <- input$link_bandwidth * 1e6
    noise_power <- -174 + 10 * log10(bw_hz) + input$link_noise_figure
    
    # Calculate SNR
    snr <- p_rx - noise_power
    
    # Calculate margin
    margin <- snr - input$link_snr_req
    
    list(
      fspl = fspl,
      p_rx = p_rx,
      noise_power = noise_power,
      snr = snr,
      margin = margin,
      status = if(margin > 0) "PASS" else "FAIL"
    )
  })
  
  # Link Budget Canvas
  output$link_budget_canvas <- renderPlotly({
    ld <- link_budget_data()
    
    # Visual representation of link budget stages
    stages <- c("Tx Power", "Tx Gain", "Path Loss", "Rx Gain", "Rx Power", "Noise", "SNR")
    values <- c(
      input$link_tx_power,
      input$link_tx_power + input$link_tx_gain,
      input$link_tx_power + input$link_tx_gain - ld$fspl,
      ld$p_rx,
      ld$p_rx,
      ld$noise_power,
      ld$snr
    )
    
    x_pos <- 1:7
    colors <- c("blue", "green", "red", "green", "orange", "purple", 
                if(ld$margin > 0) "green" else "red")
    
    # Create visual flow diagram
    fig <- plot_ly()
    
    # Add bars showing power levels
    for(i in 1:length(stages)) {
      fig <- fig %>%
        add_trace(
          x = x_pos[i],
          y = values[i],
          type = "bar",
          name = stages[i],
          marker = list(color = colors[i]),
          text = sprintf("%s<br>%.2f dBm", stages[i], values[i]),
          hoverinfo = "text"
        )
    }
    
    # Add connection arrows annotations
    annotations <- list()
    for(i in 1:(length(stages)-1)) {
      annotations[[i]] <- list(
        x = x_pos[i] + 0.5,
        y = max(values) * 0.9,
        text = "→",
        showarrow = FALSE,
        font = list(size = 20)
      )
    }
    
    # Add margin line
    fig <- fig %>%
      add_trace(
        x = x_pos,
        y = rep(input$link_snr_req + ld$noise_power, length(x_pos)),
        type = "scatter",
        mode = "lines",
        name = "Required Power",
        line = list(color = "red", dash = "dash", width = 2)
      )
    
    fig %>%
      layout(
        title = sprintf("Link Budget Canvas - Margin: %.2f dB (%s)", ld$margin, ld$status),
        xaxis = list(title = "Link Budget Stages", tickvals = x_pos, ticktext = stages),
        yaxis = list(title = "Power Level (dBm)"),
        showlegend = TRUE,
        annotations = annotations,
        hovermode = "closest"
      )
  })
  
  # Link Budget Table
  output$link_budget_table <- renderDT({
    ld <- link_budget_data()
    
    data <- data.frame(
      Parameter = c(
        "Tx Power", "Tx Antenna Gain", "EIRP", "Free Space Path Loss",
        "Rx Antenna Gain", "Received Power", "Noise Power", "SNR", 
        "Required SNR", "Link Margin", "Status"
      ),
      Value = c(
        sprintf("%.2f dBm", input$link_tx_power),
        sprintf("%.2f dBi", input$link_tx_gain),
        sprintf("%.2f dBm", input$link_tx_power + input$link_tx_gain),
        sprintf("%.2f dB", ld$fspl),
        sprintf("%.2f dBi", input$link_rx_gain),
        sprintf("%.2f dBm", ld$p_rx),
        sprintf("%.2f dBm", ld$noise_power),
        sprintf("%.2f dB", ld$snr),
        sprintf("%.2f dB", input$link_snr_req),
        sprintf("%.2f dB", ld$margin),
        ld$status
      ),
      Unit = c("dBm", "dBi", "dBm", "dB", "dBi", "dBm", "dBm", "dB", "dB", "dB", "-")
    )
    
    datatable(data, options = list(pageLength = 15, dom = 't'), rownames = FALSE) %>%
      formatStyle('Value', 
        target = 'row',
        backgroundColor = styleEqual(c('FAIL', 'PASS'), c('rgba(255,0,0,0.2)', 'rgba(0,255,0,0.2)'))
      )
  })
  
  # Link Budget Summary
  output$link_budget_summary <- renderUI({
    ld <- link_budget_data()
    
    color <- if(ld$margin > 10) "green" else if(ld$margin > 0) "orange" else "red"
    status_icon <- if(ld$margin > 0) "✓" else "✗"
    
    HTML(paste0(
      "<h4 style='color:", color, ";'>", status_icon, " Link Budget Summary</h4>",
      "<b>Distance:</b> ", input$link_distance, " km<br>",
      "<b>Frequency:</b> ", input$link_freq, " GHz<br>",
      "<b>Path Loss:</b> ", sprintf("%.2f dB", ld$fspl), "<br>",
      "<b>Received Power:</b> ", sprintf("%.2f dBm", ld$p_rx), "<br>",
      "<b>SNR:</b> ", sprintf("%.2f dB", ld$snr), "<br>",
      "<b>Link Margin:</b> <span style='font-size:18px;'><b>", sprintf("%.2f dB", ld$margin), "</b></span><br><br>",
      if(ld$margin > 10) {
        "<p style='color:green;'>✓ Excellent link margin - system is robust against fading</p>"
      } else if(ld$margin > 3) {
        "<p style='color:orange;'>⚠ Adequate margin but consider adding fade margin for reliability</p>"
      } else if(ld$margin > 0) {
        "<p style='color:orange;'>⚠ Marginal - vulnerable to atmospheric effects and multipath</p>"
      } else {
        "<p style='color:red;'>✗ Insufficient margin - link will fail. Increase Tx power, antenna gain, or reduce distance</p>"
      }
    ))
  })
  
  # ============================================================
  # PA Lineup Calculator (Interactive D3.js Canvas Version)
  # ============================================================
  
  # Reactive values for PA lineup state
  lineup_components <- reactiveVal(list())
  lineup_connections <- reactiveVal(list())
  lineup_calc_results <- reactiveVal(NULL)
  
  # Update component list when canvas changes
  observeEvent(input$lineup_components, {
    if(!is.null(input$lineup_components)) {
      # Components are sent as a JSON string from JavaScript
      comps_json <- input$lineup_components
      
      cat(sprintf("[Components Update] Received data from JavaScript\n"))
      cat(sprintf("[Components Update] Data class: %s, length: %d\n", class(comps_json), length(comps_json)))
      cat(sprintf("[Components Update] First 200 chars: %s\n", substr(comps_json, 1, 200)))
      
      # Parse JSON string to R list
      comps <- tryCatch({
        parsed <- jsonlite::fromJSON(comps_json, simplifyVector = FALSE)
        cat(sprintf("[Components Update] Successfully parsed %d components\n", length(parsed)))
        
        if(length(parsed) > 0) {
          cat(sprintf("[Components Update] First component - ID: %s, Type: %s\n", 
                      if(!is.null(parsed[[1]]$id)) parsed[[1]]$id else "NULL",
                      if(!is.null(parsed[[1]]$type)) parsed[[1]]$type else "NULL"))
        }
        
        parsed
      }, error = function(e) {
        cat(sprintf("[Components Update] JSON parse error: %s\n", e$message))
        cat(sprintf("[Components Update] Full JSON string length: %d\n", nchar(comps_json)))
        list()
      })
      
      # Store the parsed components
      lineup_components(comps)
    }
  })
  
  # Dynamic Property Editor based on selected component
  output$lineup_property_editor <- renderUI({
    selected <- input$lineup_selected_component
    
    cat(sprintf("[Property Editor] renderUI called, selected = %s\n", 
                if(is.null(selected)) "NULL" else selected))
    
    if(is.null(selected) || length(selected) == 0) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        tags$p("Select a component on canvas to edit properties")
      ))
    }
    
    components <- lineup_components()
    cat(sprintf("[Property Editor] Components count: %d\n", length(components)))
    
    if(is.null(components) || length(components) == 0) {
      return(tags$div(style = "padding: 20px;", "No components in lineup"))
    }
    
    # Debug: Print component structure
    cat("[Property Editor] Component IDs in list:\n")
    for(i in seq_along(components)) {
      c <- components[[i]]
      comp_id <- if(is.list(c) && !is.null(c$id)) c$id else "NO_ID"
      comp_type <- if(is.list(c) && !is.null(c$type)) c$type else "NO_TYPE"
      cat(sprintf("  [%d] ID=%s, Type=%s\n", i, comp_id, comp_type))
    }
    cat(sprintf("[Property Editor] Looking for component with ID: %s (class: %s)\n", 
                selected, class(selected)))
    
    # Debug: Check component structure
    # print(paste("Selected component ID:", selected))
    # print(paste("Components structure:", str(components)))
    
    # Find the selected component
    comp <- NULL
    tryCatch({
      for(i in seq_along(components)) {
        c <- components[[i]]
        # Handle both list and vector access
        comp_id <- if(is.list(c)) c$id else if(is.vector(c) && "id" %in% names(c)) c["id"] else NULL
        
        cat(sprintf("[Property Editor] Checking component %d: ID=%s (class: %s), selected=%s (class: %s), match=%s\n", 
                    i, comp_id, class(comp_id), selected, class(selected), 
                    if(!is.null(comp_id)) comp_id == selected else "NULL_ID"))
        
        if(!is.null(comp_id) && comp_id == selected) {
          comp <- c
          cat(sprintf("[Property Editor] MATCH FOUND at index %d!\n", i))
          break
        }
      }
    }, error = function(e) {
      cat(sprintf("[Property Editor] ERROR finding component: %s\n", e$message))
      print(e)
    })
    
    if(is.null(comp)) {
      cat(sprintf("[Property Editor] Component %s NOT FOUND!\n", selected))
      return(tags$div(
        style = "padding: 20px; color: #888;",
        "Component not found. ID: ", selected,
        tags$br(),
        tags$small("Try clicking on a component again")
      ))
    }
    
    cat(sprintf("[Property Editor] Component found! Type: %s\n", 
                if(is.list(comp) && !is.null(comp$type)) comp$type else "unknown"))
    
    # Safely extract properties
    tryCatch({
      # Handle both list and vector access
      props <- if(is.list(comp) && !is.null(comp$properties)) {
        comp$properties
      } else if("properties" %in% names(comp)) {
        comp[["properties"]]
      } else {
        list()
      }
      
      comp_type <- if(is.list(comp) && !is.null(comp$type)) {
        comp$type
      } else if("type" %in% names(comp)) {
        comp[["type"]]
      } else {
        "unknown"
      }
      
      # Helper function to safely get property value
      getProp <- function(name, default = "") {
        if(is.list(props) && !is.null(props[[name]])) {
          return(props[[name]])
        } else if(!is.null(names(props)) && name %in% names(props)) {
          return(props[[name]])
        } else {
          return(default)
        }
      }
      
      # Generate property inputs based on component type
      if(comp_type == "transistor") {
        cat(sprintf("[Property Editor] Generating UI for transistor component %s\n", selected))
        tagList(
          h4(paste0("Transistor: ", getProp("label", "Transistor"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Transistor")),
          selectInput(paste0("prop_", selected, "_technology"), "Technology", 
            choices = c("GaN", "LDMOS", "GaAs", "SiC", "Si-LDMOS"),
            selected = getProp("technology", "GaN")),
          hr(),
          h5("Performance Parameters"),
          numericInput(paste0("prop_", selected, "_pout"), "Pout (dBm)", 
            value = as.numeric(getProp("pout", 43)), step = 0.5),
          numericInput(paste0("prop_", selected, "_p1db"), "P1dB (dBm)", 
            value = as.numeric(getProp("p1db", 43)), step = 0.5),
          numericInput(paste0("prop_", selected, "_gain"), "Gain (dB)", 
            value = as.numeric(getProp("gain", 15)), step = 0.1),
          numericInput(paste0("prop_", selected, "_pae"), "PAE (%)", 
            value = as.numeric(getProp("pae", 50)), min = 0, max = 100, step = 1),
          hr(),
          h5("Electrical"),
          numericInput(paste0("prop_", selected, "_vdd"), "VDD (V)", 
            value = as.numeric(getProp("vdd", 28)), step = 0.5),
          numericInput(paste0("prop_", selected, "_rth"), "Rth (°C/W)", 
            value = as.numeric(getProp("rth", 2.5)), step = 0.1),
          numericInput(paste0("prop_", selected, "_freq"), "Frequency (GHz)", 
            value = as.numeric(getProp("freq", 2.6)), step = 0.1),
          hr(),
          h5("Display on Canvas"),
          checkboxGroupInput(paste0("prop_", selected, "_display"),
            label = NULL,
            choices = c("Technology" = "technology", "Gain" = "gain", "PAE" = "pae", "Pout" = "pout"),
            selected = c("technology", "pout"),
            inline = FALSE
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "matching") {
        tagList(
          h4(paste0("Matching Network: ", getProp("label", "Matching"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Matching")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("L-section", "Pi", "T", "Transformer", "TL-stub"),
            selected = getProp("type", "L-section")),
          numericInput(paste0("prop_", selected, "_loss"), "Loss (dB)", 
            value = as.numeric(getProp("loss", 0.5)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_z_in"), "Z_in (Ω)", 
            value = as.numeric(getProp("z_in", 50)), step = 0.5),
          numericInput(paste0("prop_", selected, "_z_out"), "Z_out (Ω)", 
            value = as.numeric(getProp("z_out", 50)), step = 0.5),
          numericInput(paste0("prop_", selected, "_bandwidth"), "Bandwidth (%)", 
            value = as.numeric(getProp("bandwidth", 10)), step = 1),
          hr(),
          h5("Display on Canvas"),
          checkboxGroupInput(paste0("prop_", selected, "_display"),
            label = NULL,
            choices = c("Label" = "label", "Loss" = "loss", "Type" = "type"),
            selected = c("label", "loss"),
            inline = FALSE
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "splitter") {
        tagList(
          h4(paste0("Splitter: ", getProp("label", "Splitter"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Splitter")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("Wilkinson", "Hybrid", "T-junction", "Branchline"),
            selected = getProp("type", "Wilkinson")),
          numericInput(paste0("prop_", selected, "_loss"), "Insertion Loss (dB)", 
            value = as.numeric(getProp("loss", 0.3)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_isolation"), "Isolation (dB)", 
            value = as.numeric(getProp("isolation", 20)), step = 1),
          numericInput(paste0("prop_", selected, "_split_ratio"), "Split Ratio (dB)", 
            value = as.numeric(getProp("split_ratio", 0)), step = 0.5),
          hr(),
          h5("Display on Canvas"),
          checkboxGroupInput(paste0("prop_", selected, "_display"),
            label = NULL,
            choices = c("Label" = "label", "Loss" = "loss", "Type" = "type"),
            selected = c("label", "loss"),
            inline = FALSE
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "combiner") {
        tagList(
          h4(paste0("Combiner: ", getProp("label", "Combiner"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Combiner")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("Wilkinson", "Hybrid", "Doherty", "Chireix", "Outphasing"),
            selected = getProp("type", "Wilkinson")),
          numericInput(paste0("prop_", selected, "_loss"), "Insertion Loss (dB)", 
            value = as.numeric(getProp("loss", 0.3)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_isolation"), "Isolation (dB)", 
            value = as.numeric(getProp("isolation", 20)), step = 1),
          checkboxInput(paste0("prop_", selected, "_load_modulation"), "Load Modulation", 
            value = isTRUE(getProp("load_modulation", FALSE))),
          conditionalPanel(
            condition = sprintf("input['prop_%s_load_modulation'] == true", selected),
            numericInput(paste0("prop_", selected, "_modulation_factor"), "Modulation Factor", 
              value = as.numeric(getProp("modulation_factor", 2.0)), 
              min = 1, max = 4, step = 0.1)
          ),
          hr(),
          h5("Display on Canvas"),
          checkboxGroupInput(paste0("prop_", selected, "_display"),
            label = NULL,
            choices = c("Label" = "label", "Loss" = "loss", "Type" = "type"),
            selected = c("label", "loss"),
            inline = FALSE
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else {
        tagList(
          h4("Unknown Component Type"),
          p(paste0("Type: ", comp_type)),
          p("This component type is not yet supported for editing")
        )
      }
    }, error = function(e) {
      tags$div(
        class = "alert alert-danger",
        tags$h4("Error Loading Properties"),
        tags$p("Could not parse component data:"),
        tags$pre(e$message),
        tags$small("This is a data structure issue. Check browser console for details.")
      )
    })
  })
  
  # PA Lineup Calculation Engine with Rationale
  lineup_calculate_engine <- function(components, connections, input_power_dbm = 0) {
    if(is.null(components) || length(components) == 0) {
      return(list(
        success = FALSE,
        message = "No components in lineup",
        rationale = "Cannot perform calculations without components."
      ))
    }
    
    # Helper function to safely extract property values
    safeProp <- function(props, name, default) {
      if(is.null(props)) return(default)
      
      if(is.list(props) && !is.null(props[[name]])) {
        return(props[[name]])
      } else if(!is.null(names(props)) && name %in% names(props)) {
        return(props[[name]])
      } else {
        return(default)
      }
    }
    
    rationale <- c()
    rationale <- c(rationale, "═══════════════════════════════════════")
    rationale <- c(rationale, "  PA LINEUP CALCULATION RATIONALE")
    rationale <- c(rationale, "═══════════════════════════════════════\n")
    rationale <- c(rationale, sprintf("Input Power: %.2f dBm (%.4f W)\n", 
      input_power_dbm, 10^(input_power_dbm/10)/1000))
    
    # Sort components by x position (left to right flow)
    tryCatch({
      components <- components[order(sapply(components, function(c) {
        if(is.list(c) && !is.null(c$x)) c$x else if("x" %in% names(c)) c[["x"]] else 0
      }))]
    }, error = function(e) {
      # If sorting fails, just use as-is
    })
    
    # Initialize cascade variables
    current_pin <- input_power_dbm
    total_gain <- 0
    total_pdc <- 0
    stage_results <- list()
    warnings <- c()
    
    rationale <- c(rationale, "─── Stage-by-Stage Analysis ───\n")
    
    for(i in seq_along(components)) {
      comp <- components[[i]]
      
      # Safe property extraction
      props <- if(is.list(comp) && !is.null(comp$properties)) {
        comp$properties
      } else if("properties" %in% names(comp)) {
        comp[["properties"]]
      } else {
        list()
      }
      
      comp_type <- if(is.list(comp) && !is.null(comp$type)) {
        comp$type
      } else if("type" %in% names(comp)) {
        comp[["type"]]
      } else {
        "unknown"
      }
      
      stage_name <- safeProp(props, "label", paste0("Stage_", i))
      
      rationale <- c(rationale, sprintf("[%d] %s (%s)", i, stage_name, comp_type))
      rationale <- c(rationale, sprintf("    Input Power: %.2f dBm", current_pin))
      
      if(comp_type == "transistor") {
        # Transistor stage calculations
        gain <- as.numeric(safeProp(props, "gain", 15))
        pout_dbm <- current_pin + gain
        pout_w <- 10^(pout_dbm/10) / 1000
        p1db <- as.numeric(safeProp(props, "p1db", 43))
        pae <- as.numeric(safeProp(props, "pae", 50)) / 100
        vdd <- as.numeric(safeProp(props, "vdd", 28))
        rth <- as.numeric(safeProp(props, "rth", 2.5))
        
        # Check compression
        compressed <- pout_dbm > p1db
        if(compressed) {
          compression_amount <- pout_dbm - p1db
          warnings <- c(warnings, sprintf("%s: Compressed by %.1f dB", stage_name, compression_amount))
          rationale <- c(rationale, sprintf("    ⚠ WARNING: Output %.2f dBm exceeds P1dB %.2f dBm (compression: %.2f dB)", 
            pout_dbm, p1db, compression_amount))
          # Limit output to P1dB
          pout_dbm <- p1db
          pout_w <- 10^(pout_dbm/10) / 1000
        }
        
        # DC power calculation: PDC = Pout / PAE
        pdc_w <- pout_w / pae
        pdiss_w <- pdc_w - pout_w
        idc_a <- pdc_w / vdd
        
        # Thermal calculation: Tj = Ta + Pdiss * Rth (assume Ta = 25°C)
        ta_c <- 25
        tj_c <- ta_c + pdiss_w * rth
        
        rationale <- c(rationale, sprintf("    Gain: %.2f dB → Output: %.2f dBm (%.4f W)", 
          gain, pout_dbm, pout_w))
        rationale <- c(rationale, sprintf("    PAE: %.1f%% → PDC = Pout/PAE = %.4f W / %.3f = %.3f W",
          props$pae, pout_w, pae, pdc_w))
        rationale <- c(rationale, sprintf("    Dissipation: PDiss = PDC - Pout = %.3f W", pdiss_w))
        rationale <- c(rationale, sprintf("    DC Current: IDC = PDC/VDD = %.3f A (VDD = %.1f V)", idc_a, vdd))
        rationale <- c(rationale, sprintf("    Junction Temp: Tj = Ta + PDiss*Rth = %d°C + %.3fW * %.2f°C/W = %.1f°C",
          ta_c, pdiss_w, rth, tj_c))
        
        if(tj_c > 150) {
          warnings <- c(warnings, sprintf("%s: High junction temp %.0f°C", stage_name, tj_c))
          rationale <- c(rationale, sprintf("    ⚠ WARNING: Junction temperature %.0f°C exceeds typical limit (150°C)", tj_c))
        }
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "transistor",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          gain_db = gain,
          pae_pct = as.numeric(safeProp(props, "pae", 50)),
          pdc_w = pdc_w,
          pdiss_w = pdiss_w,
          idc_a = idc_a,
          tj_c = tj_c,
          compressed = compressed,
          technology = safeProp(props, "technology", "GaN")
        )
        
        current_pin <- pout_dbm
        total_gain <- total_gain + gain
        total_pdc <- total_pdc + pdc_w
        
      } else if(comp_type == "matching") {
        # Matching network: just loss, no DC power
        loss_db <- as.numeric(safeProp(props, "loss", 0.5))
        pout_dbm <- current_pin - loss_db
        
        rationale <- c(rationale, sprintf("    Loss: %.2f dB → Output: %.2f dBm", loss_db, pout_dbm))
        rationale <- c(rationale, sprintf("    Impedance transformation: %.1f Ω → %.1f Ω", 
          as.numeric(safeProp(props, "z_in", 50)), as.numeric(safeProp(props, "z_out", 50))))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "matching",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db
        )
        
        current_pin <- pout_dbm
        total_gain <- total_gain - loss_db
        
      } else if(comp_type == "splitter") {
        # Splitter: loss + split
        loss_db <- as.numeric(safeProp(props, "loss", 0.3))
        split_ratio_db <- as.numeric(safeProp(props, "split_ratio", 0))
        pout_dbm <- current_pin - loss_db
        
        rationale <- c(rationale, sprintf("    Insertion Loss: %.2f dB, Split Ratio: %.2f dB", 
          loss_db, split_ratio_db))
        rationale <- c(rationale, sprintf("    Output per path: %.2f dBm (assumes 2-way split)", pout_dbm))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "splitter",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db,
          split_ratio = split_ratio_db
        )
        
        current_pin <- pout_dbm
        total_gain <- total_gain - loss_db
        
      } else if(comp_type == "combiner") {
        # Combiner: combine + loss
        loss_db <- as.numeric(safeProp(props, "loss", 0.3))
        combiner_type <- safeProp(props, "type", "Wilkinson")
        
        # If Doherty with load modulation, efficiency boost
        load_modulation <- isTRUE(safeProp(props, "load_modulation", FALSE))
        if(combiner_type == "Doherty" && load_modulation) {
          modulation_factor <- as.numeric(safeProp(props, "modulation_factor", 2.0))
          rationale <- c(rationale, sprintf("    Doherty Combiner with Load Modulation (Factor: %.1f)", 
            modulation_factor))
          rationale <- c(rationale, "    Load modulation improves back-off efficiency")
        }
        
        pout_dbm <- current_pin + 3 - loss_db  # 3dB from combining 2 paths
        
        rationale <- c(rationale, sprintf("    Combining gain: +3 dB (2-way), Loss: %.2f dB", loss_db))
        rationale <- c(rationale, sprintf("    Output: %.2f dBm", pout_dbm))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "combiner",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db,
          combining_gain = 3
        )
        
        current_pin <- pout_dbm
        total_gain <- total_gain + 3 - loss_db
      }
      
      rationale <- c(rationale, "")
    }
    
    # System totals
    final_pout_dbm <- current_pin
    final_pout_w <- 10^(final_pout_dbm/10) / 1000
    system_pae <- if(total_pdc > 0) (final_pout_w / total_pdc) * 100 else 0
    
    rationale <- c(rationale, "─── System Summary ───")
    rationale <- c(rationale, sprintf("Total Gain: %.2f dB", total_gain))
    rationale <- c(rationale, sprintf("Final Output Power: %.2f dBm (%.3f W)", final_pout_dbm, final_pout_w))
    rationale <- c(rationale, sprintf("Total DC Power: %.3f W", total_pdc))
    rationale <- c(rationale, sprintf("System PAE: (Pout / PDC) * 100 = (%.4f / %.3f) * 100 = %.1f%%",
      final_pout_w, total_pdc, system_pae))
    rationale <- c(rationale, sprintf("Total Heat Dissipation: %.3f W", total_pdc - final_pout_w))
    
    if(length(warnings) > 0) {
      rationale <- c(rationale, "\n─── Warnings ───")
      for(w in warnings) {
        rationale <- c(rationale, paste0("⚠ ", w))
      }
    } else {
      rationale <- c(rationale, "\n✓ All stages operating within specifications")
    }
    
    rationale <- c(rationale, "\n═══════════════════════════════════════")
    
    list(
      success = TRUE,
      input_power_dbm = input_power_dbm,
      final_pout_dbm = final_pout_dbm,
      final_pout_w = final_pout_w,
      total_gain = total_gain,
      total_pdc = total_pdc,
      system_pae = system_pae,
      total_pdiss = total_pdc - final_pout_w,
      stage_results = stage_results,
      warnings = warnings,
      rationale = paste(rationale, collapse = "\n")
    )
  }
  
  # Calculate button observer
  observeEvent(input$lineup_calculate, {
    components <- lineup_components()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No components to calculate", type = "warning")
      return()
    }
    
    # Validate connections via JavaScript (client-side validation)
    session$sendCustomMessage("validateAndCalculate", list(
      components = components,
      connections = lineup_connections()
    ))
    
    # Get input power from first component or use default
    input_power <- 0  # Default 0 dBm
    
    result <- lineup_calculate_engine(components, lineup_connections(), input_power)
    lineup_calc_results(result)
    
    showNotification(
      if(result$success) "Calculation complete" else "Calculation failed",
      type = if(result$success) "message" else "error"
    )
  })
  
  # ============================================================
  # FILE OPERATIONS: Save, Load, Export, Report
  # ============================================================
  
  # Save Configuration
  observeEvent(input$lineup_save_config, {
    components <- lineup_components()
    connections <- lineup_connections()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to save", type = "warning")
      return()
    }
    
    config <- list(
      components = components,
      connections = connections,
      metadata = list(
        timestamp = Sys.time(),
        version = "1.0",
        app = "PA Lineup Designer"
      )
    )
    
    # Create filename with timestamp
    filename <- sprintf("pa_lineup_%s.json", format(Sys.time(), "%Y%m%d_%H%M%S"))
    filepath <- file.path(tempdir(), filename)
    
    tryCatch({
      jsonlite::write_json(config, filepath, auto_unbox = TRUE, pretty = TRUE)
      showNotification(
        sprintf("Configuration saved to: %s", filename),
        type = "message",
        duration = 5
      )
      cat(sprintf("[Save] Configuration saved to: %s\n", filepath))
    }, error = function(e) {
      showNotification(
        sprintf("Save failed: %s", e$message),
        type = "error"
      )
    })
  })
  
  # Load Configuration
  observeEvent(input$lineup_load_config, {
    showModal(modalDialog(
      title = "Load Configuration",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("lineup_load_confirm", "Load", class = "btn-success")
      ),
      fileInput("lineup_config_file", "Select Configuration File (.json)",
                accept = c(".json", "application/json"))
    ))
  })
  
  observeEvent(input$lineup_load_confirm, {
    req(input$lineup_config_file)
    
    file_info <- input$lineup_config_file
    
    tryCatch({
      config <- jsonlite::read_json(file_info$datapath, simplifyVector = TRUE)
      
      # Validate config structure
      if(!is.list(config) || is.null(config$components)) {
        stop("Invalid configuration file format")
      }
      
      # Send to JavaScript
      session$sendCustomMessage("loadConfiguration", config)
      
      showNotification("Configuration loaded successfully", type = "message")
      removeModal()
      
      cat(sprintf("[Load] Configuration loaded from: %s\n", file_info$name))
      cat(sprintf("[Load] Components: %d, Connections: %d\n", 
                  length(config$components), 
                  length(config$connections)))
      
    }, error = function(e) {
      showNotification(
        sprintf("Load failed: %s", e$message),
        type = "error"
      )
    })
  })
  
  # Export Diagram (SVG)
  observeEvent(input$lineup_export_diagram, {
    components <- lineup_components()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to export", type = "warning")
      return()
    }
    
    showNotification(
      "Export feature: Right-click on canvas → 'Save Image As...' to export SVG",
      type = "message",
      duration = 8
    )
    
    # Future enhancement: Trigger JavaScript to export SVG
    # session$sendCustomMessage("exportSVG", list())
  })
  
  # Generate Report (PDF)
  observeEvent(input$lineup_generate_report, {
    components <- lineup_components()
    results <- lineup_calc_results()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to report", type = "warning")
      return()
    }
    
    if(is.null(results) || !results$success) {
      showNotification("Please calculate lineup before generating report", type = "warning")
      return()
    }
    
    showModal(modalDialog(
      title = "Generate Report",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("lineup_report_confirm", "Generate", class = "btn-success")
      ),
      textInput("lineup_report_title", "Report Title", value = "PA Lineup Design Report"),
      textInput("lineup_report_author", "Author", value = ""),
      textAreaInput("lineup_report_notes", "Additional Notes", rows = 3)
    ))
  })
  
  observeEvent(input$lineup_report_confirm, {
    tryCatch({
      # Generate simple text report (PDF generation would require rmarkdown/reportlab)
      report_lines <- c(
        "================================",
        input$lineup_report_title,
        "================================",
        "",
        sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        if(nchar(input$lineup_report_author) > 0) sprintf("Author: %s", input$lineup_report_author) else NULL,
        "",
        "LINEUP CONFIGURATION",
        "--------------------",
        sprintf("Components: %d", length(lineup_components())),
        sprintf("Total Gain: %.2f dB", lineup_calc_results()$total_gain),
        sprintf("Output Power: %.2f dBm (%.3f W)", 
                lineup_calc_results()$final_pout_dbm,
                lineup_calc_results()$final_pout_w),
        sprintf("System PAE: %.1f%%", lineup_calc_results()$system_pae),
        sprintf("DC Power: %.3f W", lineup_calc_results()$total_pdc),
        "",
        "CALCULATION RATIONALE",
        "--------------------",
        lineup_calc_results()$rationale,
        "",
        if(nchar(input$lineup_report_notes) > 0) c("ADDITIONAL NOTES", "----------------", input$lineup_report_notes) else NULL
      )
      
      # Save to temp file
      filename <- sprintf("pa_lineup_report_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S"))
      filepath <- file.path(tempdir(), filename)
      writeLines(report_lines, filepath)
      
      showNotification(
        sprintf("Report saved to: %s", filename),
        type = "message",
        duration = 5
      )
      removeModal()
      
      cat(sprintf("[Report] Generated: %s\n", filepath))
      
    }, error = function(e) {
      showNotification(
        sprintf("Report generation failed: %s", e$message),
        type = "error"
      )
    })
  })
  
  # ============================================================
  # END FILE OPERATIONS
  # ============================================================
  
  # Property apply button observer - uses reactive approach for dynamic buttons
  observeEvent(input$lineup_selected_component, {
    selected <- input$lineup_selected_component
    
    if(is.null(selected) || length(selected) == 0) return()
    
    btn_id <- paste0("apply_props_", selected)
    
    cat(sprintf("[Property Observer] Component %s selected, setting up observer for button: %s\n", 
                selected, btn_id))
    
    # Create a NEW observer for this specific button
    observeEvent(input[[btn_id]], {
      cat(sprintf("[Property Observer] Button %s clicked! Value: %s\n", 
                  btn_id, input[[btn_id]]))
      
      components <- lineup_components()
      
      # Find the component
      comp_idx <- which(sapply(components, function(c) {
        if(is.list(c) && !is.null(c$id)) c$id == selected else FALSE
      }))
      
      if(length(comp_idx) == 0) {
        showNotification("Component not found", type = "error")
        return()
      }
      
      comp <- components[[comp_idx]]
      comp_type <- if(is.list(comp) && !is.null(comp$type)) comp$type else "transistor"
      
      cat(sprintf("[Property Observer] Component type: %s\n", comp_type))
      
      # Collect properties based on component type (NOTE: IDs are prop_{id}_{field})
      properties <- list()
      
      if(comp_type == "transistor") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$technology <- input[[paste0("prop_", selected, "_technology")]]
        properties$gain <- input[[paste0("prop_", selected, "_gain")]]
        properties$pout <- input[[paste0("prop_", selected, "_pout")]]
        properties$p1db <- input[[paste0("prop_", selected, "_p1db")]]
        properties$pae <- input[[paste0("prop_", selected, "_pae")]]
        properties$vdd <- input[[paste0("prop_", selected, "_vdd")]]
        properties$rth <- input[[paste0("prop_", selected, "_rth")]]
        properties$freq <- input[[paste0("prop_", selected, "_freq")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "matching") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$z_in <- input[[paste0("prop_", selected, "_z_in")]]
        properties$z_out <- input[[paste0("prop_", selected, "_z_out")]]
        properties$bandwidth <- input[[paste0("prop_", selected, "_bandwidth")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "splitter") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$split_ratio <- input[[paste0("prop_", selected, "_split_ratio")]]
        properties$isolation <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "combiner") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$isolation <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$load_modulation <- input[[paste0("prop_", selected, "_load_modulation")]]
        properties$modulation_factor <- input[[paste0("prop_", selected, "_modulation_factor")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      }
      
      cat(sprintf("[Property Observer] Collected %d properties\n", length(properties)))
      cat(sprintf("[Property Observer] Sending updateComponent message to JavaScript...\n"))
      
      # Send to JavaScript
      session$sendCustomMessage("updateComponent", list(
        id = selected,
        properties = properties
      ))
      
      showNotification("Component properties updated", type = "message")
    }, ignoreNULL = TRUE, ignoreInit = TRUE)
  }, ignoreNULL = TRUE, ignoreInit = FALSE)
  
  # Calculation results output
  output$lineup_results <- renderUI({
    results <- lineup_calc_results()
    
    if(is.null(results)) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        "Click Calculate to see results"
      ))
    }
    
    if(!results$success) {
      return(tags$div(
        class = "alert alert-warning",
        tags$h4("Calculation Error"),
        tags$p(results$message)
      ))
    }
    
    tagList(
      tags$div(class = "calc-summary",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Output Power"),
          tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_dbm)),
          tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_w))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Total Gain"),
          tags$span(class = "metric-value", sprintf("%.2f dB", results$total_gain))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "System PAE"),
          tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "DC Power"),
          tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Heat Dissipation"),
          tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss))
        )
      ),
      if(length(results$warnings) > 0) {
        tags$div(class = "alert alert-warning",
          tags$strong("⚠ Warnings:"),
          tags$ul(
            lapply(results$warnings, function(w) tags$li(w))
          )
        )
      }
    )
  })
  
  # Rationale output
  output$lineup_rationale <- renderText({
    results <- lineup_calc_results()
    if(is.null(results) || !results$success) {
      return("No calculation results available. Click Calculate to generate rationale.")
    }
    results$rationale
  })
  
  # PA Lineup Table
  output$pa_lineup_table <- renderDT({
    results <- lineup_calc_results()
    
    if(is.null(results) || !results$success || length(results$stage_results) == 0) {
      return(datatable(data.frame(Message = "No calculation data available")))
    }
    
    # Build table from stage results
    rows <- lapply(results$stage_results, function(stage) {
      if(stage$type == "transistor") {
        data.frame(
          Stage = stage$stage,
          Type = "Transistor",
          Pin_dBm = sprintf("%.2f", stage$pin_dbm),
          Pout_dBm = sprintf("%.2f", stage$pout_dbm),
          Gain_dB = sprintf("%.2f", stage$gain_db),
          PAE_pct = sprintf("%.1f", stage$pae_pct),
          PDC_W = sprintf("%.3f", stage$pdc_w),
          Pdiss_W = sprintf("%.3f", stage$pdiss_w),
          Tj_C = sprintf("%.1f", stage$tj_c),
          Status = if(stage$compressed) "⚠ Compressed" else "✓ Linear",
          stringsAsFactors = FALSE
        )
      } else if(stage$type == "matching") {
        data.frame(
          Stage = stage$stage,
          Type = "Matching",
          Pin_dBm = sprintf("%.2f", stage$pin_dbm),
          Pout_dBm = sprintf("%.2f", stage$pout_dbm),
          Gain_dB = sprintf("%.2f", -stage$loss_db),
          PAE_pct = "—",
          PDC_W = "—",
          Pdiss_W = "—",
          Tj_C = "—",
          Status = "Passive",
          stringsAsFactors = FALSE
        )
      } else {
        data.frame(
          Stage = stage$stage,
          Type = tools::toTitleCase(stage$type),
          Pin_dBm = sprintf("%.2f", stage$pin_dbm),
          Pout_dBm = sprintf("%.2f", stage$pout_dbm),
          Gain_dB = "—",
          PAE_pct = "—",
          PDC_W = "—",
          Pdiss_W = "—",
          Tj_C = "—",
          Status = "Passive",
          stringsAsFactors = FALSE
        )
      }
    })
    
    data <- do.call(rbind, rows)
    
    # Add summary row
    summary_row <- data.frame(
      Stage = "SYSTEM TOTAL",
      Type = "—",
      Pin_dBm = sprintf("%.2f", results$input_power_dbm),
      Pout_dBm = sprintf("%.2f", results$final_pout_dbm),
      Gain_dB = sprintf("%.2f", results$total_gain),
      PAE_pct = sprintf("%.1f", results$system_pae),
      PDC_W = sprintf("%.3f", results$total_pdc),
      Pdiss_W = sprintf("%.3f", results$total_pdiss),
      Tj_C = "—",
      Status = if(length(results$warnings) > 0) "⚠ Check" else "✓ OK",
      stringsAsFactors = FALSE
    )
    
    data <- rbind(data, summary_row)
    
    datatable(data, options = list(pageLength = 20, dom = 't'), rownames = FALSE) %>%
      formatStyle('Status',
        backgroundColor = styleEqual(
          c('✓ Linear', '⚠ Compressed', '✓ OK', '⚠ Check', 'Passive'),
          c('rgba(0,255,0,0.2)', 'rgba(255,165,0,0.3)', 'rgba(0,255,0,0.2)', 
            'rgba(255,165,0,0.3)', 'rgba(200,200,200,0.2)')
        )
      )
  })
  
  # ============================================================
  # RF Tools: Converters (Placeholder Implementation)
  # ============================================================
  
  output$conv_power_results <- renderPrint({
    watt <- input$conv_power_watt
    dbm <- 10 * log10(watt * 1000)
    dbw <- 10 * log10(watt)
    cat("Power Conversions:\n")
    cat("================\n")
    cat(sprintf("%.4f W = %.2f dBm = %.2f dBW\n", watt, dbm, dbw))
  })
  
  output$conv_dbm_results <- renderPrint({
    dbm <- input$conv_power_dbm
    watt <- 10^(dbm/10) / 1000
    dbw <- dbm - 30
    cat("Power Conversions:\n")
    cat("================\n")
    cat(sprintf("%.2f dBm = %.6f W = %.2f dBW\n", dbm, watt, dbw))
  })
  
  output$conv_voltage_results <- renderPrint({
    v <- input$conv_voltage
    z <- input$conv_impedance
    power_w <- v^2 / z
    power_dbm <- 10 * log10(power_w * 1000)
    current_a <- v / z
    cat("Voltage/Power Conversions:\n")
    cat("=========================\n")
    cat(sprintf("Voltage: %.4f V\n", v))
    cat(sprintf("Impedance: %.2f Ω\n", z))
    cat(sprintf("Power: %.4f W (%.2f dBm)\n", power_w, power_dbm))
    cat(sprintf("Current: %.4f A\n", current_a))
  })
  
  output$conv_freq_results <- renderPrint({
    freq_ghz <- input$conv_freq
    freq_hz <- freq_ghz * 1e9
    
    er <- if(input$conv_medium == "0") input$conv_er_custom else as.numeric(input$conv_medium)
    
    lambda_m <- 3e8 / freq_hz
    lambda_eff_m <- lambda_m / sqrt(er)
    lambda_mm <- lambda_m * 1000
    lambda_eff_mm <- lambda_eff_m * 1000
    
    cat("Frequency/Wavelength Conversions:\n")
    cat("=================================\n")
    cat(sprintf("Frequency: %.4f GHz = %.2f MHz\n", freq_ghz, freq_ghz * 1000))
    cat(sprintf("Free Space Wavelength: %.2f mm\n", lambda_mm))
    cat(sprintf("Effective Wavelength (εr=%.2f): %.2f mm\n", er, lambda_eff_mm))
    cat(sprintf("Quarter-wave: %.2f mm\n", lambda_eff_mm / 4))
    cat(sprintf("Half-wave: %.2f mm\n", lambda_eff_mm / 2))
  })
  
  output$conv_sparams_results <- renderPrint({
    s11_mag <- input$conv_s11_mag
    s11_phase <- input$conv_s11_phase
    
    # Convert to reflection coefficient
    gamma_real <- s11_mag * cos(s11_phase * pi/180)
    gamma_imag <- s11_mag * sin(s11_phase * pi/180)
    
    # Calculate return loss and VSWR
    return_loss_db <- -20 * log10(s11_mag)
    vswr <- (1 + s11_mag) / (1 - s11_mag)
    
    cat("S-Parameter Conversions:\n")
    cat("=======================\n")
    cat(sprintf("S11: %.4f ∠ %.2f°\n", s11_mag, s11_phase))
    cat(sprintf("Γ: %.4f %+.4fj\n", gamma_real, gamma_imag))
    cat(sprintf("Return Loss: %.2f dB\n", return_loss_db))
    cat(sprintf("VSWR: %.2f:1\n", vswr))
  })
  
  # ============================================================
  # RF Tools: Smith Chart (Placeholder)
  # ============================================================
  
  output$smith_chart_plot <- renderPlotly({
    plot_ly() %>%
      add_trace(
        type = "scatter",
        mode = "lines",
        x = cos(seq(0, 2*pi, length.out = 100)),
        y = sin(seq(0, 2*pi, length.out = 100)),
        line = list(color = "white"),
        showlegend = FALSE
      ) %>%
      layout(
        xaxis = list(range = c(-1.2, 1.2), title = "Real(Γ)"),
        yaxis = list(range = c(-1.2, 1.2), title = "Imag(Γ)"),
        title = "Smith Chart (Placeholder - Full implementation pending)"
      )
  })
  
  output$smith_components <- renderPrint({
    cat("Smith Chart matching network synthesis:\n")
    cat("========================================\n")
    cat("Placeholder - Full implementation pending\n\n")
    cat("Will support:\n")
    cat("- Single/double stub matching\n")
    cat("- L/Pi/T network synthesis\n")
    cat("- Interactive impedance plotting\n")
    cat("- S-parameter trajectory visualization\n")
  })
  
  # ============================================================
  # RF Tools: MTTF Calculator (Placeholder)
  # ============================================================
  
  observeEvent(input$mttf_calculate, {
    output$mttf_results <- renderPrint({
      tj <- input$mttf_tj
      ta <- input$mttf_ta
      pdiss <- input$mttf_power_diss
      rth <- input$mttf_rth
      
      # Simplified Arrhenius model
      Ea <- 0.7  # Activation energy (eV)
      k <- 8.617e-5  # Boltzmann constant (eV/K)
      T_ref <- 398  # Reference temp (125°C in Kelvin)
      T_op <- tj + 273  # Operating temp in Kelvin
      
      # Acceleration factor
      AF <- exp((Ea/k) * (1/T_ref - 1/T_op))
      
      # Base MTTF at reference conditions (hours)
      MTTF_base <- 1e6
      
      # Adjusted MTTF
      voltage_factor <- input$mttf_voltage_stress^2
      current_factor <- input$mttf_current_stress^2
      MTTF_adj <- MTTF_base * AF / (voltage_factor * current_factor)
      
      MTTF_years <- MTTF_adj / 8760
      
      cat("MTTF Analysis Results:\n")
      cat("=====================\n\n")
      cat(sprintf("Device Type: %s\n", input$mttf_device_type))
      cat(sprintf("Junction Temperature: %.1f°C\n", tj))
      cat(sprintf("Ambient Temperature: %.1f°C\n", ta))
      cat(sprintf("Power Dissipation: %.2f W\n", pdiss))
      cat(sprintf("Temperature Rise: %.1f°C\n", pdiss * rth))
      cat("\n")
      cat(sprintf("Acceleration Factor: %.2f\n", AF))
      cat(sprintf("Voltage Stress Factor: %.2f\n", voltage_factor))
      cat(sprintf("Current Stress Factor: %.2f\n", current_factor))
      cat("\n")
      cat(sprintf("MTTF: %.0f hours (%.1f years)\n", MTTF_adj, MTTF_years))
      cat(sprintf("Failure Rate (λ): %.2e failures/hour\n", 1/MTTF_adj))
    })
    
    output$mttf_plot <- renderPlotly({
      # Placeholder reliability curve
      time <- seq(0, 200000, length.out = 100)
      reliability <- exp(-time / 1e6)
      
      plot_ly(x = time, y = reliability * 100, type = "scatter", mode = "lines",
              line = list(color = "green", width = 2)) %>%
        layout(
          title = "Reliability vs Time",
          xaxis = list(title = "Time (hours)"),
          yaxis = list(title = "Reliability (%)")
        )
    })
    
    output$mttf_recommendations <- renderUI({
      HTML(paste0(
        "<ul>",
        "<li>Reduce junction temperature by improving thermal management</li>",
        "<li>Operate at lower voltage/current for extended lifetime</li>",
        "<li>Consider derating factors for mission-critical applications</li>",
        "<li>Implement temperature monitoring and protection</li>",
        "</ul>"
      ))
    })
  })
  
  # ============================================================
  # RF Tools: Thermal Analysis (Placeholder)
  # ============================================================
  
  output$therm_pdiss <- renderPrint({
    pout <- input$therm_pout
    pae <- input$therm_efficiency / 100
    pdc <- pout / pae
    pdiss <- pdc - pout
    
    cat(sprintf("DC Power: %.2f W\n", pdc))
    cat(sprintf("Output Power: %.2f W\n", pout))
    cat(sprintf("Dissipated Power: %.2f W\n", pdiss))
  })
  
  observeEvent(input$therm_calculate, {
    output$therm_results <- renderPrint({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdc <- pout / pae
      pdiss <- pdc - pout
      
      rth_jc <- input$therm_rth_jc
      rth_cs <- input$therm_rth_cs
      rth_sa <- input$therm_rth_sa
      rth_total <- rth_jc + rth_cs + rth_sa
      
      ta <- input$therm_ta
      tj_max <- input$therm_tj_max
      
      tj <- ta + pdiss * rth_total
      tc <- ta + pdiss * (rth_cs + rth_sa)
      ts <- ta + pdiss * rth_sa
      
      margin <- tj_max - tj
      
      cat("Thermal Analysis Results:\n")
      cat("========================\n\n")
      cat(sprintf("Power Dissipation: %.2f W\n\n", pdiss))
      cat("Thermal Resistances:\n")
      cat(sprintf("  Rθjc: %.2f °C/W\n", rth_jc))
      cat(sprintf("  Rθcs: %.2f °C/W\n", rth_cs))
      cat(sprintf("  Rθsa: %.2f °C/W\n", rth_sa))
      cat(sprintf("  Rθja (total): %.2f °C/W\n\n", rth_total))
      cat("Temperature Profile:\n")
      cat(sprintf("  Ambient (Ta): %.1f °C\n", ta))
      cat(sprintf("  Heatsink (Ts): %.1f °C\n", ts))
      cat(sprintf("  Case (Tc): %.1f °C\n", tc))
      cat(sprintf("  Junction (Tj): %.1f °C\n", tj))
      cat(sprintf("  Max Junction: %.1f °C\n\n", tj_max))
      
      if (margin > 0) {
        cat(sprintf("✓ Thermal margin: %.1f °C (SAFE)\n", margin))
      } else {
        cat(sprintf("✗ THERMAL VIOLATION: %.1f °C over limit!\n", -margin))
      }
    })
    
    output$therm_plot <- renderPlotly({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdiss <- (pout / pae) - pout
      
      rth_jc <- input$therm_rth_jc
      rth_cs <- input$therm_rth_cs
      rth_sa <- input$therm_rth_sa
      
      ta <- input$therm_ta
      
      ts <- ta + pdiss * rth_sa
      tc <- ta + pdiss * (rth_cs + rth_sa)
      tj <- ta + pdiss * (rth_jc + rth_cs + rth_sa)
      
      nodes <- c("Ambient", "Heatsink", "Case", "Junction")
      temps <- c(ta, ts, tc, tj)
      colors <- c("blue", "green", "orange", "red")
      
      plot_ly(x = nodes, y = temps, type = "bar",
              marker = list(color = colors)) %>%
        layout(
          title = "Thermal Profile",
          xaxis = list(title = "Location"),
          yaxis = list(title = "Temperature (°C)")
        ) %>%
        add_trace(
          x = nodes,
          y = rep(input$therm_tj_max, length(nodes)),
          type = "scatter",
          mode = "lines",
          line = list(color = "red", dash = "dash"),
          name = "Max Tj Limit"
        )
    })
    
    output$therm_recommendations <- renderUI({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdiss <- (pout / pae) - pout
      
      rth_total <- input$therm_rth_jc + input$therm_rth_cs + input$therm_rth_sa
      tj <- input$therm_ta + pdiss * rth_total
      margin <- input$therm_tj_max - tj
      
      if (margin > 20) {
        HTML("<p style='color:green;'><b>✓ Thermal design is adequate</b></p>
             <ul>
             <li>Current heatsink solution is sufficient</li>
             <li>Consider monitoring for reliability</li>
             </ul>")
      } else if (margin > 0) {
        HTML("<p style='color:orange;'><b>⚠ Marginal thermal design</b></p>
             <ul>
             <li>Improve heatsink or add forced air cooling</li>
             <li>Reduce thermal interface resistance (better TIM)</li>
             <li>Consider active cooling solutions</li>
             </ul>")
      } else {
        HTML("<p style='color:red;'><b>✗ Thermal violation - MUST ADDRESS</b></p>
             <ul>
             <li><b>Critical:</b> Reduce Rθsa or increase heatsink area</li>
             <li>Add forced air or liquid cooling</li>
             <li>Reduce power dissipation (improve PAE or lower output power)</li>
             <li>Split power across multiple devices</li>
             </ul>")
      }
    })
  })
  
  # Cleanup on session end
  onStop(function() {
    if (!is.null(db_pool)) {
      poolClose(db_pool)
    }
  })
}

# Run the application
shinyApp(ui = ui, server = server)
