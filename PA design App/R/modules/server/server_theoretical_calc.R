# ============================================================
# server_theoretical_calc.R
# ============================================================

serverTheoreticalCalc <- function(input, output, session, state) {
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
  

}
