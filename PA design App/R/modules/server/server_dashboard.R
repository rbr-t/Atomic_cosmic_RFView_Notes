# ============================================================
# server_dashboard.R
# ============================================================

serverDashboard <- function(input, output, session, state) {
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
  

}
