# ============================================================
# server_loss_curves.R
# ============================================================

serverLossCurves <- function(input, output, session, state) {
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

  # ============================================================
  # Loss Curves Tab - Plotting and Calculations
  # ============================================================
  
  # Loss estimation function (matching JavaScript implementation)
  estimatePassiveLoss_R <- function(type, freq_ghz) {
    loss_db <- 0
    
    if (type == "transmission_line") {
      # Microstrip on FR4, 10cm length
      loss_db <- (0.05 + 0.15 * sqrt(freq_ghz) + 0.02 * freq_ghz) * 1.0  # per 10cm
    } else if (type == "wilkinson_splitter") {
      # 2-way Wilkinson with quarter-wave transformer
      loss_db <- 3.0 + 0.1 + 0.05 * freq_ghz
    } else if (type == "wilkinson_combiner") {
      loss_db <- 3.0 + 0.1 + 0.05 * freq_ghz
    } else if (type == "quadrature_hybrid") {
      # 90-degree coupler
      loss_db <- 0.3 + 0.08 * freq_ghz + 0.02 * freq_ghz^1.5
    } else if (type == "t_junction") {
      loss_db <- 0.05 + 0.03 * freq_ghz
    } else if (type == "doherty_combiner") {
      # Lower loss than Wilkinson
      loss_db <- 0.2 + 0.02 * freq_ghz + 0.01 * freq_ghz^1.3
    } else if (type == "transformer") {
      # 1:1 transformer
      if (freq_ghz < 0.5) {
        loss_db <- 0.3 + 0.05 * freq_ghz
      } else if (freq_ghz < 3) {
        loss_db <- 0.2 + 0.03 * (freq_ghz - 0.5)
      } else {
        loss_db <- 0.4 + 0.1 * (freq_ghz - 3)
      }
    }
    
    return(loss_db)
  }
  
  # Loss Curves Plot
  output$loss_curves_plot <- renderPlotly({
    req(input$loss_curve_components)
    
    # Generate frequency range
    freq_range <- seq(0.5, 30, by = 0.1)
    
    # Component names for legend
    component_names <- list(
      "wilkinson_splitter" = "Wilkinson Splitter (2-way)",
      "wilkinson_combiner" = "Wilkinson Combiner (2-way)",
      "quadrature_hybrid" = "Quadrature Hybrid (90°)",
      "t_junction" = "T-Junction Splitter",
      "transmission_line" = "Transmission Line (10cm)",
      "doherty_combiner" = "Doherty Combiner",
      "transformer" = "Transformer (1:1)"
    )
    
    # Component colors
    component_colors <- list(
      "wilkinson_splitter" = "#e74c3c",
      "wilkinson_combiner" = "#3498db",
      "quadrature_hybrid" = "#2ecc71",
      "t_junction" = "#f39c12",
      "transmission_line" = "#9b59b6",
      "doherty_combiner" = "#1abc9c",
      "transformer" = "#e67e22"
    )
    
    # Create empty plot
    p <- plot_ly()
    
    # Add trace for each selected component
    for (comp_type in input$loss_curve_components) {
      loss_values <- sapply(freq_range, function(f) estimatePassiveLoss_R(comp_type, f))
      
      p <- p %>% add_trace(
        x = freq_range,
        y = loss_values,
        type = 'scatter',
        mode = 'lines',
        name = component_names[[comp_type]],
        line = list(color = component_colors[[comp_type]], width = 2.5),
        hovertemplate = paste0(
          '<b>', component_names[[comp_type]], '</b><br>',
          'Frequency: %{x:.2f} GHz<br>',
          'Loss: %{y:.2f} dB<br>',
          '<extra></extra>'
        )
      )
    }
    
    # Layout
    p <- p %>% layout(
      title = list(
        text = "<b>Passive Component Loss vs Frequency</b>",
        font = list(size = 16)
      ),
      xaxis = list(
        title = "Frequency (GHz)",
        gridcolor = '#e0e0e0',
        zeroline = FALSE
      ),
      yaxis = list(
        title = "Insertion Loss (dB)",
        gridcolor = '#e0e0e0',
        zeroline = FALSE
      ),
      hovermode = 'closest',
      legend = list(
        x = 0.02,
        y = 0.98,
        bgcolor = 'rgba(255, 255, 255, 0.9)',
        bordercolor = '#999',
        borderwidth = 1
      ),
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
    
    return(p)
  })
  
  # Loss Calculator Result
  output$loss_calc_result <- renderText({
    req(input$loss_calc_freq, input$loss_calc_type)
    
    loss_db <- estimatePassiveLoss_R(input$loss_calc_type, input$loss_calc_freq)
    
    return(sprintf("%.2f", loss_db))
  })
  

}
