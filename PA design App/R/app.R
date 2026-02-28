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
source("core/project_mgmt/project_manager.R")
source("core/data_mgmt/data_manager.R")
source("core/security/auth_manager.R")
source("core/state_config/config_manager.R")
source("core/tagging_metadata/tag_manager.R")
source("core/ai_agents/base_agent.R")
source("core/ai_agents/agent_manager.R")

# Source RF PA Design plugin
source("plugins/rf_pa_design/plugin_init.R")

# Load configuration
config <- ConfigManager$new("config/app_config.yaml")
app_config <- config$get_config()

# Initialize database connection pool
db_pool <- dbPool(
  drv = RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST", "localhost"),
  port = Sys.getenv("DB_PORT", "5432"),
  dbname = Sys.getenv("DB_NAME", "pa_design"),
  user = Sys.getenv("DB_USER", "admin"),
  password = Sys.getenv("DB_PASSWORD", "secret")
)

# Initialize managers
project_mgr <- ProjectManager$new(db_pool)
data_mgr <- DataManager$new(db_pool)
tag_mgr <- TagManager$new(db_pool)
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
      menuItem("AI Agents", tabName = "agents", icon = icon("robot")),
      menuItem("Knowledge Base", tabName = "knowledge", icon = icon("book")),
      menuItem("Settings", tabName = "settings", icon = icon("cog"))
    )
  ),
  
  # Body
  dashboardBody(
    # Custom CSS
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
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
            selectInput("calc_project_select", "Select Project", choices = NULL),
            hr(),
            h4("Current Project Specs:"),
            verbatimTextOutput("calc_project_specs")
          )
        ),
        fluidRow(
          box(
            title = "Load-Pull Calculations",
            width = 6,
            status = "info",
            solidHeader = TRUE,
            numericInput("calc_vdd", "Supply Voltage Vdd (V)", value = 28, min = 1, max = 100),
            numericInput("calc_imax", "Max Current Imax (A)", value = 2, min = 0.1, max = 20),
            numericInput("calc_freq", "Operating Frequency (GHz)", value = 2.4, min = 0.1, max = 100),
            actionButton("calc_loadpull_btn", "Calculate Load Impedance", 
                        class = "btn-success", icon = icon("calculator")),
            hr(),
            h4("Results:"),
            verbatimTextOutput("calc_loadpull_results")
          ),
          box(
            title = "Matching Network Synthesis",
            width = 6,
            status = "warning",
            solidHeader = TRUE,
            numericInput("calc_z_source", "Source Impedance (Ω)", value = 50, min = 1, max = 500),
            numericInput("calc_z_load", "Load Impedance (Ω)", value = 10, min = 1, max = 500),
            selectInput("calc_match_type", "Matching Network Type",
              choices = c("L-Section", "Pi-Network", "T-Network", "Stub")),
            actionButton("calc_match_btn", "Synthesize Matching Network",
                        class = "btn-success", icon = icon("network-wired")),
            hr(),
            h4("Component Values:"),
            verbatimTextOutput("calc_match_results")
          )
        ),
        fluidRow(
          box(
            title = "AI Agent: Theory Agent",
            width = 12,
            status = "success",
            solidHeader = TRUE,
            textAreaInput("calc_theory_query", "Ask Theory Agent", 
                         placeholder = "e.g., What are the fundamental limits for this design?",
                         rows = 3),
            actionButton("calc_ask_theory_btn", "Ask Theory Agent",
                        class = "btn-primary", icon = icon("robot")),
            hr(),
            h4("Theory Agent Response:"),
            verbatimTextOutput("calc_theory_response")
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
    rv$projects <- project_mgr$get_all_projects()
    
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
  
  # Cleanup on session end
  onStop(function() {
    poolClose(db_pool)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
