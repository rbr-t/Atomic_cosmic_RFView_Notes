# ============================================================
# server_projects.R
# ============================================================

serverProjects <- function(input, output, session, state) {
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
  

}
