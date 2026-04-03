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

  is_three_way_doherty_combiner <- function(component) {
    comp_type <- if (is.list(component) && !is.null(component$type)) {
      component$type
    } else if (!is.null(names(component)) && "type" %in% names(component)) {
      component[["type"]]
    } else {
      NULL
    }

    if (is.null(comp_type) || !identical(as.character(comp_type), "combiner")) {
      return(FALSE)
    }

    props <- if (is.list(component) && !is.null(component$properties)) {
      component$properties
    } else if (!is.null(names(component)) && "properties" %in% names(component)) {
      component[["properties"]]
    } else {
      list()
    }

    subtype_raw <- props$subtype %||% props$label %||% ""
    ways_raw <- props$ways %||% props$portCount %||% 0
    subtype <- tolower(as.character(subtype_raw))
    ways <- suppressWarnings(as.numeric(ways_raw))

    isTRUE(is.finite(ways) && ways == 3) || grepl("3-way", subtype, fixed = TRUE)
  }

  has_three_way_doherty_combiner <- function() {
    components <- lineup_components()
    if (is.null(components) || length(components) == 0) {
      return(FALSE)
    }

    any(vapply(components, is_three_way_doherty_combiner, logical(1)))
  }

  get_primary_backoff_for_secondary <- function() {
    if (!is.null(input$spec_par) && is.finite(input$spec_par)) {
      return(input$spec_par)
    }
    if (!is.null(input$backoff_db) && is.finite(input$backoff_db)) {
      return(input$backoff_db)
    }
    6
  }

  get_secondary_backoff_info <- function() {
    if (!is.null(input$backoff_db_secondary) && is.finite(input$backoff_db_secondary) && input$backoff_db_secondary > 0) {
      return(list(value = input$backoff_db_secondary, auto_derived = FALSE))
    }
    if (!is.null(input$spec_par_secondary) && is.finite(input$spec_par_secondary) && input$spec_par_secondary > 0) {
      return(list(value = input$spec_par_secondary, auto_derived = FALSE))
    }
    if (has_three_way_doherty_combiner()) {
      return(list(value = get_primary_backoff_for_secondary() * 2, auto_derived = TRUE))
    }

    list(value = NULL, auto_derived = FALSE)
  }

  get_secondary_backoff <- function() {
    get_secondary_backoff_info()$value
  }

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

  output$calculated_Pavg2 <- renderText({
    p3db <- input$spec_p3db
    par2 <- get_secondary_backoff()

    if (!is.null(p3db) && !is.null(par2) && is.finite(par2) && par2 > 0) {
      return(sprintf("%.1f dBm", p3db - par2))
    }

    return("—")
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

  output$spec_pavg2_display <- renderText({
    p3db <- input$spec_p3db %||% 46
    par2 <- get_secondary_backoff()
    cpt  <- as.integer(input$spec_compression_point %||% 3)

    if (is.null(par2) || !is.finite(par2) || par2 <= 0) {
      return("N/A")
    }

    sprintf("%.1f dBm   [= P%ddB \u2212 PAR2]", p3db - par2, cpt)
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
    list(input$spec_p3db, input$spec_par, input$spec_par_secondary, input$spec_gain, input$spec_frequency,
         input$spec_compression_point),
    {
      req(input$spec_p3db, input$spec_par)
      secondary_info <- get_secondary_backoff_info()
      secondary_value <- secondary_info$value %||% 0

      updateNumericInput(session, "global_pout_p3db", value = input$spec_p3db)
      updateNumericInput(session, "global_PAR",       value = input$spec_par)
      updateNumericInput(session, "global_backoff",   value = input$spec_par)
      updateNumericInput(session, "global_backoff_secondary", value = secondary_value)
      updateNumericInput(session, "backoff_db", value = input$spec_par)
      updateNumericInput(session, "backoff_db_secondary", value = secondary_value)
      if (isTRUE(secondary_info$auto_derived) &&
          (is.null(input$spec_par_secondary) || !is.finite(input$spec_par_secondary) || input$spec_par_secondary <= 0)) {
        updateNumericInput(session, "spec_par_secondary", value = secondary_info$value)
      }
      if (!is.null(input$spec_frequency))
        updateNumericInput(session, "global_frequency",
                           value = round(input$spec_frequency / 1000, 4))
      if (!is.null(input$spec_compression_point))
        updateSelectInput(session, "global_compression_point",
                          selected = input$spec_compression_point)
    },
    ignoreInit = TRUE
  )

  observeEvent(input$lineup_components, {
    secondary_info <- get_secondary_backoff_info()
    secondary_value <- secondary_info$value %||% 0

    updateNumericInput(session, "global_backoff_secondary", value = secondary_value)
    updateNumericInput(session, "backoff_db_secondary", value = secondary_value)

    if (isTRUE(secondary_info$auto_derived) &&
        (is.null(input$spec_par_secondary) || !is.finite(input$spec_par_secondary) || input$spec_par_secondary <= 0)) {
      updateNumericInput(session, "spec_par_secondary", value = secondary_info$value)
    }
  }, ignoreInit = TRUE)

}
