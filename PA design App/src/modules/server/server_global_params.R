# ============================================================
# server_global_params.R
# ============================================================

serverGlobalParams <- function(input, output, session, state) {
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
  # Global Lineup Parameters - Pavg Calculation
  # ============================================================
  
  output$calculated_Pavg <- renderText({
    # CRITICAL FIX: Calculate Pavg from SPECIFICATIONS (P3dB - PAR), not from components!
    # The specification defines the system operating points, not the component calculations.
    
    # Get specification values
    p3db <- input$spec_p3db
    par <- input$spec_par
    
    # Validate inputs
    if(is.null(p3db) || is.null(par)) {
      # Fallback: try to get from components if specs not available
      components <- lineup_components()
      if(is.null(components) || length(components) == 0) {
        return("N/A")
      }
      
      # Find final output power (last transistor in chain)
      final_pout <- 43  # default
      for(comp in components) {
        if(!is.null(comp$type) && comp$type == "transistor") {
          if(!is.null(comp$properties) && !is.null(comp$properties$pout)) {
            final_pout <- comp$properties$pout
          }
        }
      }
      
      backoff <- input$global_backoff
      if(is.null(backoff)) backoff <- 6
      pavg <- final_pout - backoff
    } else {
      # ✓ CORRECT: Pavg = P3dB - PAR (from specifications)
      pavg <- p3db - par
    }
    
    return(sprintf("%.1f dBm", pavg))
  })
  
  # Calculated Pin from Global Parameters (based on specs)
  output$calculated_Pin_global <- renderText({
    req(input$global_pout_p3db, input$spec_gain)
    
    pin_calc <- input$global_pout_p3db - input$spec_gain
    
    return(sprintf("%.1f dBm", pin_calc))
  })
  
  # Bandwidth Display in Specifications
  output$spec_bandwidth_display <- renderText({
    req(input$spec_frequency, input$spec_bw_lower, input$spec_bw_upper)
    
    freq_mhz <- input$spec_frequency
    bw_lower_pct <- input$spec_bw_lower / 100
    bw_upper_pct <- input$spec_bw_upper / 100
    
    bw_total <- freq_mhz * (bw_lower_pct + bw_upper_pct)
    
    return(sprintf("%.0f", bw_total))
  })

  # ── Spec panel derived displays ──────────────────────────────────────────────
  # Pavg display inside Lineup Specifications panel
  output$spec_pavg_display <- renderText({
    p3db <- input$spec_p3db %||% 46
    par  <- input$spec_par  %||% 8
    cpt  <- as.integer(input$spec_compression_point %||% 3)
    sprintf("%.1f dBm   [= P%ddB \u2212 PAR]", p3db - par, cpt)
  })

  # Pin display inside Lineup Specifications panel
  output$spec_pin_display <- renderText({
    p3db <- input$spec_p3db  %||% 46
    gain <- input$spec_gain  %||% 40
    cpt  <- as.integer(input$spec_compression_point %||% 3)
    sprintf("%.1f dBm   [= P%ddB \u2212 Gain]", p3db - gain, cpt)
  })

  # ── Keep Global Lineup Parameters in sync with Lineup Specifications ─────────
  # When spec_p3db / spec_par / spec_gain / spec_frequency change, mirror the
  # values into the Global Lineup Parameters panel so both panels are consistent.
  observeEvent(
    list(input$spec_p3db, input$spec_par, input$spec_gain, input$spec_frequency,
         input$spec_compression_point),
    {
      req(input$spec_p3db, input$spec_par)
      updateNumericInput(session, "global_pout_p3db", value = input$spec_p3db)
      updateNumericInput(session, "global_PAR",       value = input$spec_par)
      updateNumericInput(session, "global_backoff",   value = input$spec_par)
      if (!is.null(input$spec_frequency))
        updateNumericInput(session, "global_frequency",
                           value = round(input$spec_frequency / 1000, 4))
      if (!is.null(input$spec_compression_point))
        updateSelectInput(session, "global_compression_point",
                          selected = input$spec_compression_point)
    },
    ignoreInit = TRUE
  )

}
