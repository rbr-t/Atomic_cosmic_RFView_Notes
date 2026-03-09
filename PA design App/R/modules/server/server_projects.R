# ============================================================
# server_projects.R
# ============================================================

serverProjects <- function(input, output, session, state) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # Unpack shared state
  rv                  <- state$rv
  lineup_components   <- state$lineup_components
  lineup_connections  <- state$lineup_connections
  lineup_calc_results <- state$lineup_calc_results
  canvas_data         <- state$canvas_data
  active_canvas_index <- state$active_canvas_index
  getUserTemplates    <- state$getUserTemplates
  getCanvasCount      <- state$getCanvasCount
  userTemplates       <- state$userTemplates

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
    
    freq_ghz <- input$new_project_freq %||% 2.4
    tech     <- input$new_project_technology %||% "GaN_SiC"
    vdd      <- input$new_project_vdd %||% 28
    
    if (!demo_mode && !is.null(project_mgr)) {
      new_project <- project_mgr$create_project(
        name = input$new_project_name,
        architecture_type = input$new_project_arch,
        frequency = freq_ghz,
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
    
    # ── Propagate project frequency to all downstream tabs ──────────────────
    # PA Lineup
    updateNumericInput(session, "global_frequency",  value = freq_ghz)
    # Frequency Planning
    updateNumericInput(session, "freq_target_freq",  value = freq_ghz)
    # Performance Guardrails
    updateNumericInput(session, "grd_chk_freq",      value = freq_ghz)
    # Link Budget
    updateNumericInput(session, "link_freq",          value = freq_ghz)
    # Loss Curves
    updateNumericInput(session, "loss_calc_freq",     value = freq_ghz)

    # ── Wire project params to PA Lineup Specifications panel ────────────────
    pout_dbm <- input$new_project_pout %||% 46.0
    par_db   <- input$new_project_par  %||% 8.0
    gain_db  <- input$new_project_gain %||% 40.0
    updateNumericInput(session, "spec_frequency", value = round(freq_ghz * 1000, 1))  # GHz → MHz
    updateNumericInput(session, "spec_p3db",      value = pout_dbm)
    updateNumericInput(session, "spec_par",       value = par_db)
    updateNumericInput(session, "spec_gain",      value = gain_db)
    updateNumericInput(session, "global_pout_p3db", value = pout_dbm)
    updateNumericInput(session, "global_PAR",     value = par_db)
    updateNumericInput(session, "global_backoff", value = par_db)
    
    # Store project defaults in rv so other modules can read them reactively
    rv$project_freq_ghz  <- freq_ghz
    rv$project_technology <- tech
    rv$project_vdd       <- vdd
    
    # Clear name input
    updateTextInput(session, "new_project_name", value = "")
  })
  

}
