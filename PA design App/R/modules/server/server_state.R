# ============================================================
# server_state.R
# Initialises all shared reactive state for the PA Design App.
# Called once from server.R at app startup.
# Returns a named list of all shared reactives and helpers.
# ============================================================

initServerState <- function(input, output, session) {
  # Reactive values
  rv <- reactiveValues(
    current_project  = NULL,
    projects         = data.frame(),
    project_freq_ghz  = 2.4,
    project_technology = "GaN_SiC",
    project_vdd      = 28,
    canvas_names = c("Canvas 1", "Canvas 2", "Canvas 3", "Canvas 4",
                     "Canvas 5", "Canvas 6", "Canvas 7", "Canvas 8", "Canvas 9")
  )
  
  # Helper function: Get user templates
  getUserTemplates <- function() {
    templates_dir <- file.path("R", "user_templates")
    
    if(!dir.exists(templates_dir)) {
      return(list())
    }
    
    template_files <- list.files(templates_dir, pattern = "\\.json$", full.names = TRUE)
    
    templates <- lapply(template_files, function(filepath) {
      tryCatch({
        template_data <- jsonlite::read_json(filepath, simplifyVector = TRUE)
        list(
          id = paste0("user_", tools::file_path_sans_ext(basename(filepath))),
          name = template_data$name,
          components_count = length(template_data$components),
          filepath = filepath
        )
      }, error = function(e) {
        cat(sprintf("[Template Error] Failed to read %s: %s\n", filepath, e$message))
        NULL
      })
    })
    
    # Remove NULL entries (failed reads)
    Filter(Negate(is.null), templates)
  }
  
  # Helper function: Get canvas count from layout string
  getCanvasCount <- function(layout) {
    if(is.null(layout) || layout == "1x1") {
      return(1)
    }
    
    # Handle special layouts
    if(layout %in% c("2+1", "1+2")) {
      return(3)
    }
    
    # Parse NxM format (e.g., "2x2", "1x3", "4x1", etc.)
    parts <- strsplit(layout, "x")[[1]]
    if(length(parts) == 2) {
      rows <- as.numeric(parts[1])
      cols <- as.numeric(parts[2])
      if(!is.na(rows) && !is.na(cols)) {
        return(rows * cols)
      }
    }
    
    # Fallback to 1 if parsing fails
    return(1)
  }
  
  # Reactive expression for user templates
  userTemplates <- reactive({
    getUserTemplates()
  })
  
  # Send user templates to JavaScript on startup
  observe({
    templates <- userTemplates()
    if(length(templates) > 0) {
      template_info <- lapply(templates, function(t) {
        list(id = t$id, name = t$name, components_count = t$components_count)
      })
      session$sendCustomMessage("updateUserTemplates", template_info)
    }
  })
  
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
  

  # ── PA Lineup reactive values ──────────────────────────────────
  # Reactive values for PA lineup state
  lineup_components <- reactiveVal(list())
  lineup_connections <- reactiveVal(list())
  lineup_calc_results <- reactiveVal(NULL)
  
  # Per-canvas storage for multi-canvas comparison
  canvas_data <- reactiveValues(
    canvas_0 = list(components = list(), connections = list(), results = NULL),
    canvas_1 = list(components = list(), connections = list(), results = NULL),
    canvas_2 = list(components = list(), connections = list(), results = NULL),
    canvas_3 = list(components = list(), connections = list(), results = NULL),
    canvas_4 = list(components = list(), connections = list(), results = NULL),
    canvas_5 = list(components = list(), connections = list(), results = NULL),
    canvas_6 = list(components = list(), connections = list(), results = NULL),
    canvas_7 = list(components = list(), connections = list(), results = NULL),
    canvas_8 = list(components = list(), connections = list(), results = NULL)
  )
  
  active_canvas_index <- reactiveVal(0)
  

  # ── Return shared state list ────────────────────────────────────
  list(
    rv                  = rv,
    lineup_components   = lineup_components,
    lineup_connections  = lineup_connections,
    lineup_calc_results = lineup_calc_results,
    canvas_data         = canvas_data,
    active_canvas_index = active_canvas_index,
    getUserTemplates    = getUserTemplates,
    getCanvasCount      = getCanvasCount,
    userTemplates       = userTemplates
  )
}
