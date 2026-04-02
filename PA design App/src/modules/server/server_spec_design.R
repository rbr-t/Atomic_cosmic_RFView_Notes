# ============================================================
# server_spec_design.R
# ============================================================

serverSpecDesign <- function(input, output, session, state) {
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
  # SPECIFICATION-DRIVEN DESIGN
  # ============================================================
  
  # Apply Specs to Global Parameters Only
  observeEvent(input$apply_specs_to_global, {
    req(input$spec_frequency, input$spec_p3db, input$spec_gain)
    
    # Convert MHz to GHz for global frequency
    freq_ghz <- input$spec_frequency / 1000
    
    # Update global parameters
    updateNumericInput(session, "global_frequency", value = freq_ghz)
    
    cat(sprintf("[Spec→Global] Updated frequency: %.3f GHz\n", freq_ghz))
    
    showNotification(
      sprintf("Global parameters updated: %.2f GHz", freq_ghz),
      type = "message",
      duration = 3
    )
  })
  
  # Apply Specs to Lineup (Full adaptation)
  observeEvent(input$apply_specs_to_lineup, {
    req(input$spec_frequency, input$spec_p3db, input$spec_gain)
    
    # Collect all specification data
    specs <- list(
      # Primary specifications
      frequency_mhz = input$spec_frequency,
      frequency_ghz = input$spec_frequency / 1000,
      p3db = input$spec_p3db,
      p5db = if(!is.null(input$spec_p5db)) input$spec_p5db else (input$spec_p3db + 2),
      par = if(!is.null(input$spec_par)) input$spec_par else 8.0,  # Peak-to-Average Ratio
      pavg = input$spec_p3db - (if(!is.null(input$spec_par)) input$spec_par else 8.0),  # Average/backoff power
      gain = input$spec_gain,
      
      # Secondary specifications
      supply_voltage = input$spec_supply_voltage,
      efficiency_target = input$spec_efficiency,
      am_pm_p3db = input$spec_am_pm_p3db,
      am_pm_dispersion = input$spec_am_pm_dispersion,
      group_delay = input$spec_group_delay,
      acp = input$spec_acp,
      gain_ripple_inband = input$spec_gain_ripple_inband,
      gain_ripple_3xband = input$spec_gain_ripple_3xband,
      input_return_loss = input$spec_input_return_loss,
      vbw = input$spec_vbw,
      test_conditions = input$spec_test_conditions,
      
      # Calculate derived values
      p1db = input$spec_p3db - 2,  # Typical for solid state
      pin_required = input$spec_p3db - input$spec_gain
    )
    
    cat("[Spec→Lineup] Applying specifications:\n")
    cat(sprintf("  Frequency: %.3f GHz (%.0f MHz)\n", specs$frequency_ghz, specs$frequency_mhz))
    cat(sprintf("  P3dB (Peak): %.1f dBm\n", specs$p3db))
    cat(sprintf("  PAR/BO: %.1f dB\n", specs$par))
    cat(sprintf("  Pavg (Backoff): %.1f dBm\n", specs$pavg))
    cat(sprintf("  Gain: %.1f dB\n", specs$gain))
    cat(sprintf("  Pin required: %.1f dBm\n", specs$pin_required))
    cat(sprintf("  Efficiency target: %.0f%%\n", specs$efficiency_target))
    cat(sprintf("  Supply voltage: %.0f V\n", specs$supply_voltage))
    
    # Update global parameters
    updateNumericInput(session, "global_frequency", value = specs$frequency_ghz)
    updateNumericInput(session, "global_pout_p3db", value = specs$p3db)
    
    # Send specifications to JavaScript for component adaptation
    session$sendCustomMessage("applySpecsToLineup", specs)
    
    showNotification(
      sprintf("Applying specs: %.2f GHz, %.1f dBm, %.1f dB gain",
              specs$frequency_ghz, specs$p3db, specs$gain),
      type = "message",
      duration = 5
    )
  })
  

}
