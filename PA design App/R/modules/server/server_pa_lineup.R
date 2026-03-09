# ============================================================
# server_pa_lineup.R
# Handles all PA Lineup canvas, property editor,
# calculation engine, results display, and multi-canvas.
# ============================================================

serverPaLineup <- function(input, output, session, state) {
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
  # PA Lineup Calculator (Interactive D3.js Canvas Version)
  # ============================================================
  
  # ── Push spec changes (PAR / P3dB / frequency) to JavaScript immediately ──
  # This keeps canvas Pavg targets in sync without requiring a button click.
  observe({
    req(input$spec_p3db)
    par_val  <- if (!is.null(input$spec_par))          input$spec_par          else 8.0
    p3db_val <- input$spec_p3db
    freq_val <- if (!is.null(input$spec_frequency))    input$spec_frequency    else 2000
    gain_val <- if (!is.null(input$spec_gain))         input$spec_gain         else 30
    vdd_val  <- if (!is.null(input$spec_supply_voltage)) input$spec_supply_voltage else 28
    comp_pt  <- if (!is.null(input$spec_compression_point))
                  as.integer(input$spec_compression_point) else 3L

    session$sendCustomMessage("syncLineupSpecs", list(
      par              = par_val,
      p3db             = p3db_val,
      pavg             = p3db_val - par_val,
      frequency_ghz    = freq_val / 1000,
      gain             = gain_val,
      supply_voltage   = vdd_val,
      compression_point = comp_pt   # P(X)dB compression definition
    ))
  })

  # Track active canvas changes
  observeEvent(input$active_canvas, {
    if(!is.null(input$active_canvas)) {
      active_canvas_index(input$active_canvas)
      cat(sprintf("[Active Canvas] Changed to: %d\n", input$active_canvas))
    }
  })
  
  # Update component list when canvas changes
  observeEvent(input$lineup_components, {
    if(!is.null(input$lineup_components)) {
      # Components are sent as a JSON string from JavaScript
      comps_json <- input$lineup_components
      
      cat(sprintf("[Components Update] Received data from JavaScript\n"))
      cat(sprintf("[Components Update] Data class: %s, length: %d\n", class(comps_json), length(comps_json)))
      cat(sprintf("[Components Update] First 200 chars: %s\n", substr(comps_json, 1, 200)))
      
      # Parse JSON string to R list
      comps <- tryCatch({
        parsed <- jsonlite::fromJSON(comps_json, simplifyVector = FALSE)
        cat(sprintf("[Components Update] Successfully parsed %d components\n", length(parsed)))
        
        if(length(parsed) > 0) {
          cat(sprintf("[Components Update] First component - ID: %s, Type: %s\n", 
                      if(!is.null(parsed[[1]]$id)) parsed[[1]]$id else "NULL",
                      if(!is.null(parsed[[1]]$type)) parsed[[1]]$type else "NULL"))
        }
        
        parsed
      }, error = function(e) {
        cat(sprintf("[Components Update] JSON parse error: %s\n", e$message))
        cat(sprintf("[Components Update] Full JSON string length: %d\n", nchar(comps_json)))
        list()
      })
      
      # Store the parsed components (global - backwards compatibility)
      lineup_components(comps)
      
      # Also store per-canvas
      canvas_idx <- active_canvas_index()
      canvas_key <- paste0("canvas_", canvas_idx)
      canvas_data[[canvas_key]]$components <- comps
      cat(sprintf("[Components Update] Stored %d components for canvas %d\n", length(comps), canvas_idx))
    }
  })
  
  # Update connections when canvas changes
  observeEvent(input$lineup_connections, {
    if(!is.null(input$lineup_connections)) {
      # Connections are sent as a JSON string from JavaScript
      conns_json <- input$lineup_connections
      
      cat(sprintf("[Connections Update] Received data from JavaScript\n"))
      
      # Parse JSON string to R list
      conns <- tryCatch({
        parsed <- jsonlite::fromJSON(conns_json, simplifyVector = FALSE)
        cat(sprintf("[Connections Update] Successfully parsed %d connections\n", length(parsed)))
        parsed
      }, error = function(e) {
        cat(sprintf("[Connections Update] JSON parse error: %s\n", e$message))
        list()
      })
      
      # Store the parsed connections (global - backwards compatibility)
      lineup_connections(conns)
      
      # Also store per-canvas
      canvas_idx <- active_canvas_index()
      canvas_key <- paste0("canvas_", canvas_idx)
      canvas_data[[canvas_key]]$connections <- conns
      cat(sprintf("[Connections Update] Stored %d connections for canvas %d\n", length(conns), canvas_idx))
    }
  })
  
  # Observer for canvas layout changes
  observeEvent(input$canvas_layout, {
    if(!is.null(input$canvas_layout)) {
      cat(sprintf("[Canvas Layout] Changed to: %s\n", input$canvas_layout))
      
      # Send layout update to JavaScript
      session$sendCustomMessage("updateCanvasLayout", list(
        layout = input$canvas_layout
      ))
    }
  }, ignoreInit = TRUE)
  
  # Observer for editing canvas names
  observeEvent(input$edit_canvas_names, {
    layout <- input$canvas_layout
    canvas_count <- getCanvasCount(layout)
    
    showModal(modalDialog(
      title = "Edit Canvas Names",
      size = "m",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("save_canvas_names", "Save", class = "btn-primary")
      ),
      div(
        style = "max-height: 500px; overflow-y: auto;",
        lapply(1:canvas_count, function(i) {
          textInput(
            paste0("canvas_name_", i),
            label = sprintf("Canvas %d Name:", i),
            value = rv$canvas_names[i],
            placeholder = sprintf("Canvas %d", i)
          )
        })
      )
    ))
  })
  
  # Observer for saving canvas names
  observeEvent(input$save_canvas_names, {
    layout <- input$canvas_layout
    canvas_count <- getCanvasCount(layout)
    
    # Update canvas names from inputs
    for(i in 1:canvas_count) {
      input_id <- paste0("canvas_name_", i)
      if(!is.null(input[[input_id]]) && nchar(trimws(input[[input_id]])) > 0) {
        rv$canvas_names[i] <- trimws(input[[input_id]])
      } else {
        rv$canvas_names[i] <- sprintf("Canvas %d", i)
      }
    }
    
    # Send updated names to JavaScript
    session$sendCustomMessage("updateCanvasNames", list(
      names = rv$canvas_names[1:canvas_count]
    ))
    
    cat(sprintf("[Canvas Names] Updated: %s\n", paste(rv$canvas_names[1:canvas_count], collapse = ", ")))
    
    removeModal()
  })
  
  # Dynamic Property Editor based on selected component
  output$lineup_property_editor <- renderUI({
    selected <- input$lineup_selected_component
    
    cat(sprintf("[Property Editor] renderUI called, selected = %s\n", 
                if(is.null(selected)) "NULL" else selected))
    
    if(is.null(selected) || length(selected) == 0) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        tags$p("Select a component on canvas to edit properties")
      ))
    }
    
    components <- lineup_components()
    cat(sprintf("[Property Editor] Components count: %d\n", length(components)))
    
    if(is.null(components) || length(components) == 0) {
      return(tags$div(style = "padding: 20px;", "No components in lineup"))
    }
    
    # Debug: Print component structure
    cat("[Property Editor] Component IDs in list:\n")
    for(i in seq_along(components)) {
      c <- components[[i]]
      comp_id <- if(is.list(c) && !is.null(c$id)) c$id else "NO_ID"
      comp_type <- if(is.list(c) && !is.null(c$type)) c$type else "NO_TYPE"
      cat(sprintf("  [%d] ID=%s, Type=%s\n", i, comp_id, comp_type))
    }
    cat(sprintf("[Property Editor] Looking for component with ID: %s (class: %s)\n", 
                selected, class(selected)))
    
    # Debug: Check component structure
    # print(paste("Selected component ID:", selected))
    # print(paste("Components structure:", str(components)))
    
    # Find the selected component
    comp <- NULL
    tryCatch({
      for(i in seq_along(components)) {
        c <- components[[i]]
        # Handle both list and vector access
        comp_id <- if(is.list(c)) c$id else if(is.vector(c) && "id" %in% names(c)) c["id"] else NULL
        
        cat(sprintf("[Property Editor] Checking component %d: ID=%s (class: %s), selected=%s (class: %s), match=%s\n", 
                    i, comp_id, class(comp_id), selected, class(selected), 
                    if(!is.null(comp_id)) comp_id == selected else "NULL_ID"))
        
        if(!is.null(comp_id) && comp_id == selected) {
          comp <- c
          cat(sprintf("[Property Editor] MATCH FOUND at index %d!\n", i))
          break
        }
      }
    }, error = function(e) {
      cat(sprintf("[Property Editor] ERROR finding component: %s\n", e$message))
      print(e)
    })
    
    if(is.null(comp)) {
      cat(sprintf("[Property Editor] Component %s NOT FOUND!\n", selected))
      return(tags$div(
        style = "padding: 20px; color: #888;",
        "Component not found. ID: ", selected,
        tags$br(),
        tags$small("Try clicking on a component again")
      ))
    }
    
    cat(sprintf("[Property Editor] Component found! Type: %s\n", 
                if(is.list(comp) && !is.null(comp$type)) comp$type else "unknown"))
    
    # Safely extract properties
    tryCatch({
      # Handle both list and vector access
      props <- if(is.list(comp) && !is.null(comp$properties)) {
        comp$properties
      } else if("properties" %in% names(comp)) {
        comp[["properties"]]
      } else {
        list()
      }
      
      comp_type <- if(is.list(comp) && !is.null(comp$type)) {
        comp$type
      } else if("type" %in% names(comp)) {
        comp[["type"]]
      } else {
        "unknown"
      }
      
      # Helper function to safely get property value
      getProp <- function(name, default = "") {
        if(is.list(props) && !is.null(props[[name]])) {
          return(props[[name]])
        } else if(!is.null(names(props)) && name %in% names(props)) {
          return(props[[name]])
        } else {
          return(default)
        }
      }
      
      # Generate property inputs based on component type
      if(comp_type == "transistor") {
        cat(sprintf("[Property Editor] Generating UI for transistor component %s\n", selected))
        tagList(
          h4(paste0("Transistor: ", getProp("label", "Transistor"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Transistor")),
          selectizeInput(paste0("prop_", selected, "_technology"), "Technology", 
            choices = c("GaN", "GaN_Si", "GaN_SiC", "LDMOS", "GaAs", "SiC", "Si-LDMOS", "InP", "GaN-HEMT"),
            selected = getProp("technology", "GaN"),
            options = list(
              create = TRUE,
              placeholder = 'Select or type custom technology'
            )),
          selectInput(paste0("prop_", selected, "_biasClass"), "Biasing Class",
            choices = c("A", "AB", "B", "C", "D", "E", "F"),
            selected = getProp("biasClass", "AB")),
          hr(),
          h5("Performance Parameters"),
          numericInput(paste0("prop_", selected, "_pout"), "Pout @ P3dB (dBm)", 
            value = as.numeric(getProp("pout", 43)), step = 0.5),
          numericInput(paste0("prop_", selected, "_p1db"), "P1dB (dBm) — must be ≤ Pout (compression point always below operating output)", 
            value = as.numeric(getProp("p1db", 45)), step = 0.5),
          fluidRow(
            column(6,
              numericInput(paste0("prop_", selected, "_gain_p3db"), "Gain @ P3dB (dB)", 
                value = as.numeric(getProp("gain_p3db", getProp("gain", 15))), step = 0.1)
            ),
            column(6,
              numericInput(paste0("prop_", selected, "_gain_bo"), "Gain @ BO (dB)", 
                value = as.numeric(getProp("gain_bo", getProp("gain", 15))), step = 0.1)
            )
          ),
          numericInput(paste0("prop_", selected, "_gain"), "Gain (dB) — linear region", 
            value = as.numeric(getProp("gain", 15)), step = 0.1),
          numericInput(paste0("prop_", selected, "_pae"), "PAE @ P3dB (%)", 
            value = as.numeric(getProp("pae", 50)), min = 0, max = 100, step = 1),
          hr(),
          h5("Electrical"),
          numericInput(paste0("prop_", selected, "_vdd"), "VDD (V)", 
            value = as.numeric(getProp("vdd", 28)), step = 0.5),
          numericInput(paste0("prop_", selected, "_rth"), "Rth (°C/W)", 
            value = as.numeric(getProp("rth", 2.5)), step = 0.1),
          numericInput(paste0("prop_", selected, "_freq"), "Frequency (GHz)", 
            value = as.numeric(getProp("freq", 2.6)), step = 0.1),
          hr(),
          h5("Display on Canvas"),
          div(style="display: grid; grid-template-columns: 1fr 1fr; gap: 5px;",
            checkboxGroupInput(paste0("prop_", selected, "_display"),
              label = NULL,
              choices = c(
                "Label" = "label",
                "Technology" = "technology",
                "Bias Class" = "biasClass",
                "Gain (dB)" = "gain",
                "Gain@P3dB" = "gain_p3db",
                "Gain@BO" = "gain_bo",
                "PAE (%)" = "pae",
                "Pout (dBm)" = "pout",
                "P1dB (dBm)" = "p1db",
                "VDD (V)" = "vdd",
                "Freq (GHz)" = "freq"
              ),
              selected = c("technology", "pout"),
              inline = FALSE
            )
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "matching") {
        tagList(
          h4(paste0("Matching Network: ", getProp("label", "Matching"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Matching")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("L-section", "Pi", "T", "Transformer", "TL-stub"),
            selected = getProp("type", "L-section")),
          numericInput(paste0("prop_", selected, "_loss"), "Loss (dB)", 
            value = as.numeric(getProp("loss", 0.5)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_z_in"), "Z_in (Ω)", 
            value = as.numeric(getProp("z_in", 50)), step = 0.5),
          numericInput(paste0("prop_", selected, "_z_out"), "Z_out (Ω)", 
            value = as.numeric(getProp("z_out", 50)), step = 0.5),
          numericInput(paste0("prop_", selected, "_bandwidth"), "Bandwidth (%)", 
            value = as.numeric(getProp("bandwidth", 10)), step = 1),
          hr(),
          h5("Display on Canvas"),
          div(style="display: grid; grid-template-columns: 1fr 1fr; gap: 5px;",
            checkboxGroupInput(paste0("prop_", selected, "_display"),
              label = NULL,
              choices = c(
                "Label" = "label",
                "Type" = "type",
                "Loss (dB)" = "loss",
                "Z_in (\u03A9)" = "z_in",
                "Z_out (\u03A9)" = "z_out",
                "Bandwidth (%)" = "bandwidth"
              ),
              selected = c("label", "loss"),
              inline = FALSE
            )
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "splitter") {
        tagList(
          h4(paste0("Splitter: ", getProp("label", "Splitter"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Splitter")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("Wilkinson", "Hybrid", "T-junction", "Branchline"),
            selected = getProp("type", "Wilkinson")),
          numericInput(paste0("prop_", selected, "_loss"), "Insertion Loss (dB)", 
            value = as.numeric(getProp("loss", 0.3)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_isolation"), "Isolation (dB)", 
            value = as.numeric(getProp("isolation", 20)), step = 1),
          numericInput(paste0("prop_", selected, "_split_ratio"), "Split Ratio (dB)", 
            value = as.numeric(getProp("split_ratio", 0)), step = 0.5),
          hr(),
          h5("Display on Canvas"),
          div(style="display: grid; grid-template-columns: 1fr 1fr; gap: 5px;",
            checkboxGroupInput(paste0("prop_", selected, "_display"),
              label = NULL,
              choices = c(
                "Label" = "label",
                "Type" = "type",
                "Loss (dB)" = "loss",
                "Isolation (dB)" = "isolation",
                "Split Ratio (dB)" = "split_ratio"
              ),
              selected = c("label", "loss"),
              inline = FALSE
            )
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "combiner") {
        tagList(
          h4(paste0("Combiner: ", getProp("label", "Combiner"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Combiner")),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("Wilkinson", "Hybrid", "Doherty", "Chireix", "Outphasing"),
            selected = getProp("type", "Wilkinson")),
          numericInput(paste0("prop_", selected, "_loss"), "Insertion Loss (dB)", 
            value = as.numeric(getProp("loss", 0.3)), min = 0, step = 0.05),
          numericInput(paste0("prop_", selected, "_isolation"), "Isolation (dB)", 
            value = as.numeric(getProp("isolation", 20)), step = 1),
          checkboxInput(paste0("prop_", selected, "_load_modulation"), "Load Modulation", 
            value = isTRUE(getProp("load_modulation", FALSE))),
          conditionalPanel(
            condition = sprintf("input['prop_%s_load_modulation'] == true", selected),
            numericInput(paste0("prop_", selected, "_modulation_factor"), "Modulation Factor", 
              value = as.numeric(getProp("modulation_factor", 2.0)), 
              min = 1, max = 4, step = 0.1)
          ),
          hr(),
          h5("Display on Canvas"),
          div(style="display: grid; grid-template-columns: 1fr 1fr; gap: 5px;",
            checkboxGroupInput(paste0("prop_", selected, "_display"),
              label = NULL,
              choices = c(
                "Label" = "label",
                "Type" = "type",
                "Loss (dB)" = "loss",
                "Isolation (dB)" = "isolation",
                "Load Mod" = "load_modulation"
              ),
              selected = c("label", "loss"),
              inline = FALSE
            )
          ),
          hr(),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else if(comp_type == "termination") {
        tagList(
          h4(paste0("Termination: ", getProp("label", "Term"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Term")),
          numericInput(paste0("prop_", selected, "_impedance"), "Impedance (Ω)", 
            value = as.numeric(getProp("impedance", 50)), 
            min = 1, max = 1000, step = 1),
          selectInput(paste0("prop_", selected, "_type"), "Type", 
            choices = c("Matched Load" = "matched", 
                       "Open Circuit" = "open", 
                       "Short Circuit" = "short",
                       "Custom" = "custom"),
            selected = getProp("type", "matched")),
          hr(),
          h5("Display on Canvas"),
          div(style="display: grid; grid-template-columns: 1fr 1fr; gap: 5px;",
            checkboxGroupInput(paste0("prop_", selected, "_display"),
              label = NULL,
              choices = c(
                "Label" = "label",
                "Impedance (Ω)" = "impedance"
              ),
              selected = c("label", "impedance"),
              inline = FALSE
            )
          ),
          hr(),
          p(class = "text-muted", style = "font-size: 11px;",
            icon("info-circle"), " Termination loads absorb power. ",
            "Connect signal (positive end) via wire-snap to circuit."
          ),
          actionButton(paste0("apply_props_", selected), "Apply Changes", 
            class = "btn-primary btn-block",
            onclick = paste0("console.log('Apply button clicked: apply_props_", selected, "');"))
        )
      } else {
        tagList(
          h4("Unknown Component Type"),
          p(paste0("Type: ", comp_type)),
          p("This component type is not yet supported for editing")
        )
      }
    }, error = function(e) {
      tags$div(
        class = "alert alert-danger",
        tags$h4("Error Loading Properties"),
        tags$p("Could not parse component data:"),
        tags$pre(e$message),
        tags$small("This is a data structure issue. Check browser console for details.")
      )
    })
  })
  
  # PA Lineup Calculation Engine is defined in modules/calculations/calc_pa_lineup.R
  # (Loads as global function via app.R sourcing at startup)
  # REMOVED: inline local definition that shadowed the modular version

  # Calculate button observer
  observeEvent(input$lineup_calculate, {
    components <- lineup_components()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No components to calculate", type = "warning")
      return()
    }
    
    # Validate connections via JavaScript (client-side validation)
    session$sendCustomMessage("validateAndCalculate", list(
      components = components,
      connections = lineup_connections()
    ))
    
    # ═══ CRITICAL FIX: Calculate required input power from specifications ═══
    # If specs available: Pin_required = P3dB - Total_Gain
    # This ensures the cascade reaches the target P3dB output power
    if(!is.null(input$spec_p3db) && !is.null(input$spec_gain)) {
      input_power <- input$spec_p3db - input$spec_gain
      cat(sprintf("[Calculate] Using specs: P3dB=%.1f dBm, Gain=%.1f dB → Pin=%.2f dBm\n", 
        input$spec_p3db, input$spec_gain, input_power))
    } else {
      # Fallback: use default input power
      input_power <- 0  # dBm
      cat("[Calculate] Warning: No specs available, using default Pin=0 dBm\n")
    }
    
    # ═══ CRITICAL FIX: Use PAR from specs if available, else backoff_db ═══
    # Priority: 1) spec_par (correct), 2) backoff_db (legacy)
    if(!is.null(input$spec_par) && !is.null(input$spec_p3db)) {
      # Use PAR from specifications (P3dB-based approach)
      backoff_value <- input$spec_par
      showNotification(sprintf("Calculating with PAR = %.1f dB from specifications", backoff_value), 
        type = "message", duration = 3)
    } else {
      # Fall back to generic backoff_db input
      backoff_value <- if(!is.null(input$backoff_db)) input$backoff_db else 6
      showNotification(sprintf("Calculating with generic backoff = %.1f dB", backoff_value), 
        type = "warning", duration = 3)
    }
    
    result <- lineup_calculate_engine(components, lineup_connections(), input_power, backoff_value)
    
    # Store results globally (backwards compatibility)
    lineup_calc_results(result)
    
    # Store results per-canvas
    canvas_idx <- active_canvas_index()
    canvas_key <- paste0("canvas_", canvas_idx)
    canvas_data[[canvas_key]]$results <- result
    cat(sprintf("[Calculate] Stored results for canvas %d\n", canvas_idx))

    # ── Push R-computed stage values back to JS canvas (single source of truth) ──
    # After this, canvas display reads R-computed pin/pout/pae/gain rather than
    # re-computing from gain cascade which depends on a linear chain assumption.
    if (result$success && length(result$stage_results) > 0) {
      comps <- lineup_components()
      for (stage in result$stage_results) {
        # Match by component ID (reliable) — fall back to label for legacy
        if (!is.null(stage$id)) {
          cid     <- as.character(stage$id)
          matched <- Filter(function(c) !is.null(c$id) && as.character(c$id) == cid, comps)
        } else {
          matched <- Filter(function(c) {
            lbl <- if (!is.null(c$properties$label)) c$properties$label else ""
            lbl == stage$stage
          }, comps)
          if (length(matched) > 0) cid <- as.character(matched[[1]]$id)
        }
        if (length(matched) > 0) {
          props_update <- list(
            pin_p3db  = stage$pin_dbm,
            pout_p3db = stage$pout_dbm,
            pin_pavg  = if (!is.null(stage$pin_bo_dbm))  stage$pin_bo_dbm  else stage$pin_dbm  - backoff_value,
            pout_pavg = if (!is.null(stage$pout_bo_dbm)) stage$pout_bo_dbm else stage$pout_dbm - backoff_value,
            # Point 12: Assume matched impedance (50 Ω) at all ports.
            # z_in / z_out default to 50 unless the user has explicitly overridden them.
            z_in      = if (!is.null(matched[[1]]$properties$z_in))  matched[[1]]$properties$z_in  else 50,
            z_out     = if (!is.null(matched[[1]]$properties$z_out)) matched[[1]]$properties$z_out else 50
          )
          if (stage$type == "transistor") {
            props_update$pae_p3db     <- stage$pae_pct
            props_update$pae_pavg     <- stage$pae_bo_pct
            props_update$de_p3db      <- stage$de_pct
            props_update$de_pavg      <- stage$de_bo_pct
            props_update$gain_full_db <- stage$gain_full_db
            props_update$gain_bo_db   <- stage$gain_bo_db
          }
          session$sendCustomMessage("updateComponent", list(id = cid, properties = props_update))
        }
      }
      # Signal JS to redraw all display overlays with fresh data
      session$sendCustomMessage("redrawCanvasDisplay", list())
    }

    showNotification(
      if(result$success) "Calculation complete" else "Calculation failed",
      type = if(result$success) "message" else "error"
    )
  })
  
  # Calculate ALL canvases button observer
  observeEvent(input$lineup_calculate_all, {
    layout <- input$canvas_layout
    if(is.null(layout)) layout <- "1x1"
    
    canvas_count <- getCanvasCount(layout)
    
    cat(sprintf("[Calculate All] Layout: %s, Canvas Count: %d\n", layout, canvas_count))
    
    if(canvas_count == 1) {
      showNotification("Multi-canvas mode required for comparison", type = "warning")
      return()
    }
    
    # First, request fresh data from all canvases in JavaScript
    session$sendCustomMessage("requestAllCanvasData", list())
    
    # Give JavaScript time to send the data
    Sys.sleep(0.5)
    
    # Get backoff value from input (with fallback)
    backoff_value <- if(!is.null(input$backoff_db)) input$backoff_db else 6
    input_power <- 0  # Default 0 dBm
    
    calculated_count <- 0
    failed_count <- 0
    empty_count <- 0
    
    for(i in 0:(canvas_count-1)) {
      canvas_key <- paste0("canvas_", i)
      components <- canvas_data[[canvas_key]]$components
      connections <- canvas_data[[canvas_key]]$connections
      
      cat(sprintf("[Calculate All] Canvas %d: %d components, %d connections\n", 
                  i, length(components), length(connections)))
      
      if(!is.null(components) && length(components) > 0) {
        result <- lineup_calculate_engine(components, connections, input_power, backoff_value)
        canvas_data[[canvas_key]]$results <- result
        
        if(result$success) {
          calculated_count <- calculated_count + 1
          cat(sprintf("[Calculate All] Canvas %d: Success - Pout=%.2f dBm, PAE=%.1f%%\n", 
                      i, result$final_pout_dbm, result$system_pae))
        } else {
          failed_count <- failed_count + 1
          cat(sprintf("[Calculate All] Canvas %d: Failed - %s\n", i, result$message))
        }
      } else {
        empty_count <- empty_count + 1
        cat(sprintf("[Calculate All] Canvas %d: Empty (skipped)\n", i))
      }
    }
    
    msg <- sprintf("Calculated %d canvas(es).", calculated_count)
    if(empty_count > 0) msg <- paste0(msg, sprintf(" %d empty.", empty_count))
    if(failed_count > 0) msg <- paste0(msg, sprintf(" %d failed.", failed_count))
    
    showNotification(
      msg,
      type = if(failed_count == 0 && calculated_count > 0) "message" else "warning",
      duration = 5
    )
    
    cat(sprintf("[Calculate All] Complete: %d success, %d empty, %d failed\n", 
                calculated_count, empty_count, failed_count))
  })


  # ── Optimize Lineup button (REMOVED from UI — observer kept for compatibility) ──────
  # Button removed from PA Lineup tab UI.
  # observeEvent(input$lineup_optimize, {  # DISABLED
  if (FALSE) { observeEvent(input$lineup_optimize, {
    components <- lineup_components()

    if (is.null(components) || length(components) == 0) {
      showNotification("No components on canvas to optimize.", type = "warning")
      return()
    }

    transistors <- Filter(function(c) !is.null(c$type) && c$type == "transistor", components)
    if (length(transistors) == 0) {
      showNotification("No transistor stages found — add components first.", type = "warning")
      return()
    }

    # ── Save pre-optimization snapshot for version control ─────────────────
    rv$pre_optimize_snapshot <- components
    cat(sprintf("[Optimize] Saved pre-optimize snapshot (%d components)\n", length(components)))

    # Collect active specs
    freq_ghz <- if (!is.null(input$spec_frequency)) input$spec_frequency / 1000 else 2.0
    p3db_dbm <- if (!is.null(input$spec_p3db))      input$spec_p3db     else 46.0
    par_db   <- if (!is.null(input$spec_par))        input$spec_par      else 8.0
    vdd_spec <- if (!is.null(input$spec_supply_voltage)) input$spec_supply_voltage else 28.0

    guardrails <- tryCatch(loadGuardrails(), error = function(e) NULL)
    if (is.null(guardrails)) {
      showNotification("Could not load technology guardrails.", type = "error")
      return()
    }
    techs <- guardrails$technologies

    # Pick best technology for a given frequency and required Pout
    selectOptimalTech <- function(freq, pout_req) {
      viable <- lapply(names(techs), function(k) {
        t <- techs[[k]]
        in_freq  <- freq >= t$freq_range_ghz$min && freq <= t$freq_range_ghz$max
        in_pout  <- pout_req >= t$pout_dbm$min_practical && pout_req <= t$pout_dbm$max_practical
        if (in_freq && in_pout) {
          list(key = k, label = t$label,
               pae      = as.numeric(t$pae_pct$typical_p3db),
               ft       = as.numeric(t$gain_db$ft_ghz_typical),
               vdd      = as.numeric(t$vdd$typical),
               pout_max = as.numeric(t$pout_dbm$max_practical))
        } else NULL
      })
      viable <- Filter(Negate(is.null), viable)
      if (length(viable) == 0) {
        # Fallback: GaN_SiC covers most use-cases
        t <- techs$GaN_SiC
        return(list(key = "GaN_SiC", label = "GaN HEMT (SiC)",
                    pae = as.numeric(t$pae_pct$typical_p3db),
                    ft  = as.numeric(t$gain_db$ft_ghz_typical),
                    vdd = as.numeric(t$vdd$typical),
                    pout_max = 56))
      }
      # Prefer highest typical PAE (most efficient) among viable options
      viable[[which.max(sapply(viable, `[[`, "pae"))]]
    }

    # Count PA stages (main + aux) vs driver stages
    n_pa_stages <- sum(sapply(transistors, function(t) {
      lbl <- tolower(if (!is.null(t$properties$label)) t$properties$label else "")
      grepl("main|aux|\\bpa\\b|power amp", lbl)
    }))
    n_driver_stages <- length(transistors) - n_pa_stages
    if (n_pa_stages == 0) n_pa_stages <- 1  # treat all as PA if not labelled

    # Power budget: system P3dB = sum of PA outputs through combiner
    # Each PA needs: p3db - 10*log10(n_pa_stages) + combiner_loss
    combiner_loss <- 0.3
    pa_pout_req    <- p3db_dbm - 10 * log10(n_pa_stages) + combiner_loss
    # Pavg target for each PA at backoff
    pa_pavg_req    <- p3db_dbm - par_db + combiner_loss   # main only at backoff

    # Drivers need ~10-15 dB less than PA output (to drive through splitter)
    split_loss     <- 0.3
    driver_pout_req <- pa_pout_req - 12.0 + split_loss

    tech_keys_used <- c()
    n_updated      <- 0

    for (tx in transistors) {
      cid   <- as.character(tx$id)
      props <- if (!is.null(tx$properties)) tx$properties else list()
      label <- tolower(if (!is.null(props$label)) props$label else "")

      is_pa_stage <- grepl("main|aux|\\bpa\\b|power amp", label)
      pout_req    <- if (is_pa_stage) pa_pout_req else driver_pout_req

      best <- selectOptimalTech(freq_ghz, pout_req)
      tech_keys_used <- c(tech_keys_used, best$key)

      # Realistic gain: 80% of guardrail-modelled available gain,
      # clamped per stage type (PAs ~10-14 dB, drivers ~14-18 dB)
      avail_gain   <- calcAvailableGain(freq_ghz, best$ft)
      prac_gain    <- min(avail_gain * 0.80, if (is_pa_stage) 14 else 18)
      prac_gain    <- max(prac_gain, if (is_pa_stage) 8 else 12)   # floor

      # P1dB ≤ Pout: 1dB compression point is typically 2-3 dB below operating Pout (P3dB)
      p1db_val <- round(pout_req - 2.0, 1)

      # Pavg PAE estimate (typically 5-10% better than P3dB for Doherty)
      pae_bo_val <- round(best$pae * 1.08, 0)

      # Respect supplied Vdd where possible
      use_vdd <- if (!is.null(vdd_spec) && vdd_spec > 0) vdd_spec else best$vdd

      updated_props <- c(props, list(
        technology    = best$key,
        gain          = round(prac_gain, 1),
        gain_p3db     = round(prac_gain, 1),
        gain_bo       = round(prac_gain - 0.5, 1),  # typical ~0.5 dB less at BO
        pae           = best$pae,
        pae_p3db      = best$pae,
        pae_pavg      = pae_bo_val,
        vdd           = use_vdd,
        pout          = round(pout_req, 1),
        pout_p3db     = round(pout_req, 1),
        pout_pavg     = round(pa_pavg_req, 1),
        p1db          = p1db_val
      ))

      session$sendCustomMessage("updateComponent", list(
        id         = cid,
        properties = updated_props
      ))

      cat(sprintf("[Optimize] %s → tech=%s, Gain=%.1fdB, PAE=%d%%, Vdd=%.0fV, Pout=%.1f dBm, P1dB=%.1f dBm\n",
                  label, best$key, prac_gain, best$pae, use_vdd, pout_req, p1db_val))
      n_updated <- n_updated + 1
    }

    unique_techs <- paste(unique(tech_keys_used), collapse = ", ")
    showNotification(
      sprintf("Optimized %d stage(s) using guardrails. Technology: %s. Old design saved for comparison.", n_updated, unique_techs),
      type = "message", duration = 6
    )
    cat(sprintf("[Optimize] Complete: %d transistor(s) updated (%s)\n", n_updated, unique_techs))

    # Redraw canvas overlays and re-trigger calculation with optimized values
    session$sendCustomMessage("redrawCanvasDisplay", list())
  }) } # end disabled optimize observer


  # Property apply — single stable observer (avoids accumulating observers on
  # repeated component selection). Depends on: current selection + apply button.
  observe({
    selected <- input$lineup_selected_component
    if (is.null(selected) || length(selected) == 0) return()

    btn_id <- paste0("apply_props_", selected)
    clicks  <- input[[btn_id]]
    # Only fire on real button clicks (value > 0), NOT on initialization (0/NULL)
    if (is.null(clicks) || clicks == 0) return()

    cat(sprintf("[Property Observer] Apply clicked for %s (clicks=%s)\n",
                selected, clicks))

    isolate({
      components <- lineup_components()

      comp_idx <- which(sapply(components, function(c) {
        if (is.list(c) && !is.null(c$id)) c$id == selected else FALSE
      }))

      if (length(comp_idx) == 0) {
        showNotification("Component not found", type = "error")
        return()
      }

      comp      <- components[[comp_idx]]
      comp_type <- if (is.list(comp) && !is.null(comp$type)) comp$type else "transistor"

      cat(sprintf("[Property Observer] Component type: %s\n", comp_type))

      properties <- list()

      if (comp_type == "transistor") {
        properties$label      <- input[[paste0("prop_", selected, "_label")]]
        properties$technology <- input[[paste0("prop_", selected, "_technology")]]
        properties$biasClass  <- input[[paste0("prop_", selected, "_biasClass")]]
        properties$gain       <- input[[paste0("prop_", selected, "_gain")]]
        properties$gain_p3db  <- input[[paste0("prop_", selected, "_gain_p3db")]]
        properties$gain_bo    <- input[[paste0("prop_", selected, "_gain_bo")]]
        properties$pout       <- input[[paste0("prop_", selected, "_pout")]]
        properties$p1db       <- input[[paste0("prop_", selected, "_p1db")]]
        properties$pae        <- input[[paste0("prop_", selected, "_pae")]]
        properties$vdd        <- input[[paste0("prop_", selected, "_vdd")]]
        properties$rth        <- input[[paste0("prop_", selected, "_rth")]]
        properties$freq       <- input[[paste0("prop_", selected, "_freq")]]
        properties$z_in       <- input[[paste0("prop_", selected, "_z_in")]]
        properties$z_out      <- input[[paste0("prop_", selected, "_z_out")]]
        properties$display    <- input[[paste0("prop_", selected, "_display")]]
        # Validate: P1dB must be <= Pout
        if (!is.null(properties$p1db) && !is.null(properties$pout) &&
            as.numeric(properties$p1db) > as.numeric(properties$pout)) {
          showNotification(
            sprintf("⚠ P1dB (%.1f dBm) must be \u2264 Pout (%.1f dBm). Setting P1dB = Pout \u2212 2 dB.",
                    as.numeric(properties$p1db), as.numeric(properties$pout)),
            type = "warning", duration = 5
          )
          properties$p1db <- as.numeric(properties$pout) - 2
        }
      } else if (comp_type == "matching") {
        properties$label     <- input[[paste0("prop_", selected, "_label")]]
        properties$type      <- input[[paste0("prop_", selected, "_type")]]
        properties$loss      <- input[[paste0("prop_", selected, "_loss")]]
        properties$z_in      <- input[[paste0("prop_", selected, "_z_in")]]
        properties$z_out     <- input[[paste0("prop_", selected, "_z_out")]]
        properties$bandwidth <- input[[paste0("prop_", selected, "_bandwidth")]]
        properties$display   <- input[[paste0("prop_", selected, "_display")]]
      } else if (comp_type == "splitter") {
        properties$label       <- input[[paste0("prop_", selected, "_label")]]
        properties$type        <- input[[paste0("prop_", selected, "_type")]]
        properties$split_ratio <- input[[paste0("prop_", selected, "_split_ratio")]]
        properties$isolation   <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss        <- input[[paste0("prop_", selected, "_loss")]]
        properties$display     <- input[[paste0("prop_", selected, "_display")]]
      } else if (comp_type == "combiner") {
        properties$label            <- input[[paste0("prop_", selected, "_label")]]
        properties$type             <- input[[paste0("prop_", selected, "_type")]]
        properties$isolation        <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss             <- input[[paste0("prop_", selected, "_loss")]]
        properties$load_modulation  <- input[[paste0("prop_", selected, "_load_modulation")]]
        properties$modulation_factor <- input[[paste0("prop_", selected, "_modulation_factor")]]
        properties$display          <- input[[paste0("prop_", selected, "_display")]]
      } else if (comp_type == "termination") {
        properties$label     <- input[[paste0("prop_", selected, "_label")]]
        properties$impedance <- input[[paste0("prop_", selected, "_impedance")]]
        properties$type      <- input[[paste0("prop_", selected, "_type")]]
        properties$display   <- input[[paste0("prop_", selected, "_display")]]
      }

      cat(sprintf("[Property Observer] Sending %d properties to JS\n", length(properties)))
      session$sendCustomMessage("updateComponent", list(id = selected, properties = properties))
      showNotification("Component properties updated", type = "message")
    })
  })
  

  # Calculation results output
  # Current canvas calculation results (fix: this was lineup_results before)
  output$lineup_calc_results <- renderUI({
    results <- lineup_calc_results()
    
    if(is.null(results)) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        "Click Calculate to see results"
      ))
    }
    
    if(!results$success) {
      return(tags$div(
        class = "alert alert-warning",
        tags$h4("Calculation Error"),
        tags$p(results$message)
      ))
    }
    
    backoff_value <- if(!is.null(results$backoff_db)) results$backoff_db else 6
    
    tagList(
      tags$h4("Full Power Performance", style = "color: #2196F3; margin-bottom: 10px;"),
      tags$div(class = "calc-summary", style = "background-color: #f0f8ff; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Output Power"),
          tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_dbm)),
          tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_w))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "System PAE"),
          tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "DC Power"),
          tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Heat Dissipation"),
          tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss))
        )
      ),
      tags$h4(sprintf("Backoff Performance (%.1f dB)", backoff_value), style = "color: #FF9800; margin-bottom: 10px;"),
      tags$div(class = "calc-summary", style = "background-color: #fff8f0; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Output Power"),
          tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_bo_dbm)),
          tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_bo_w))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "System PAE"),
          tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae_bo))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "DC Power"),
          tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc_bo))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Heat Dissipation"),
          tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss_bo))
        )
      ),
      tags$div(class = "calc-summary", style = "background-color: #f5f5f5; padding: 10px; border-radius: 5px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Total Gain"),
          tags$span(class = "metric-value", sprintf("%.2f dB", results$total_gain))
        )
      ),
      if(length(results$warnings) > 0) {
        tags$div(class = "alert alert-warning",
          tags$strong("⚠ Warnings:"),
          tags$ul(
            lapply(results$warnings, function(w) tags$li(w))
          )
        )
      }
    )
  })
  
  # Legacy output name (keep for backwards compatibility)
  output$lineup_results <- renderUI({
    results <- lineup_calc_results()
    
    if(is.null(results)) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        "Click Calculate to see results"
      ))
    }
    
    if(!results$success) {
      return(tags$div(
        class = "alert alert-warning",
        tags$h4("Calculation Error"),
        tags$p(results$message)
      ))
    }
    
    backoff_value <- if(!is.null(results$backoff_db)) results$backoff_db else 6
    
    tagList(
      tags$h4("Full Power Performance", style = "color: #2196F3; margin-bottom: 10px;"),
      tags$div(class = "calc-summary", style = "background-color: #f0f8ff; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Output Power"),
          tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_dbm)),
          tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_w))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "System PAE"),
          tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "DC Power"),
          tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Heat Dissipation"),
          tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss))
        )
      ),
      tags$h4(sprintf("Backoff Performance (%.1f dB)", backoff_value), style = "color: #FF9800; margin-bottom: 10px;"),
      tags$div(class = "calc-summary", style = "background-color: #fff8f0; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Output Power"),
          tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_bo_dbm)),
          tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_bo_w))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "System PAE"),
          tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae_bo))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "DC Power"),
          tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc_bo))
        ),
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Heat Dissipation"),
          tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss_bo))
        )
      ),
      tags$div(class = "calc-summary", style = "background-color: #f5f5f5; padding: 10px; border-radius: 5px;",
        tags$div(class = "calc-metric",
          tags$span(class = "metric-label", "Total Gain"),
          tags$span(class = "metric-value", sprintf("%.2f dB", results$total_gain))
        )
      ),
      if(length(results$warnings) > 0) {
        tags$div(class = "alert alert-warning",
          tags$strong("⚠ Warnings:"),
          tags$ul(
            lapply(results$warnings, function(w) tags$li(w))
          )
        )
      }
    )
  })
  
  # Rationale output
  output$lineup_rationale <- renderText({
    results <- lineup_calc_results()
    if(is.null(results) || !results$success) {
      return("No calculation results available. Click Calculate to generate rationale.")
    }
    results$rationale
  })
  
  # Multi-canvas comparison output
  output$lineup_comparison_results <- renderUI({
    layout <- input$canvas_layout
    if(is.null(layout)) layout <- "1x1"
    
    canvas_count <- getCanvasCount(layout)
    
    cat(sprintf("[Comparison View] Layout: %s, Canvas Count: %d\n", layout, canvas_count))
    
    if(canvas_count == 1) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        icon("info-circle", style = "font-size: 36px; margin-bottom: 10px;"),
        tags$h4("Multi-Canvas Comparison Unavailable"),
        tags$p("Switch to any multi-canvas layout (2x1, 1x2, 2x2, 2x3, etc.) to compare multiple canvases")
      ))
    }
    
    # Collect results from all canvases
    comparison_data <- list()
    has_results <- FALSE
    
    for(i in 0:(canvas_count-1)) {
      canvas_key <- paste0("canvas_", i)
      canvas_name <- if(!is.null(rv$canvas_names) && length(rv$canvas_names) > i) {
        rv$canvas_names[i+1]
      } else {
        paste("Canvas", i+1)
      }
      
      result <- canvas_data[[canvas_key]]$results
      if(!is.null(result) && result$success) {
        has_results <- TRUE
        comparison_data[[as.character(i)]] <- list(
          name = canvas_name,
          result = result
        )
      }
    }
    
    if(!has_results) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        icon("info-circle", style = "font-size: 36px; margin-bottom: 10px;"),
        tags$p("No calculation results available"),
        tags$p(style = "font-size: 14px;", "Click 'Calculate All Canvases' to generate comparison data")
      ))
    }
    
    # Create comparison table
    tagList(
      tags$h4("Canvas Comparison", style = "color: #2196F3; margin-bottom: 15px;"),
      tags$div(
        style = "overflow-x: auto;",
        tags$table(
          class = "table table-striped table-hover",
          style = "margin-bottom: 20px;",
          tags$thead(
            tags$tr(
              tags$th("Canvas", style = "background-color: #34495e; color: white; font-weight: bold;"),
              tags$th("Output Power", style = "background-color: #34495e; color: white;"),
              tags$th("PAE (%)", style = "background-color: #34495e; color: white;"),
              tags$th("DC Power (W)", style = "background-color: #34495e; color: white;"),
              tags$th("Total Gain (dB)", style = "background-color: #34495e; color: white;"),
              tags$th("Components", style = "background-color: #34495e; color: white;")
            )
          ),
          tags$tbody(
            lapply(names(comparison_data), function(idx) {
              data <- comparison_data[[idx]]
              result <- data$result
              
              # Determine best performers for highlighting
              pae_style <- ""
              pout_style <- ""
              
              tags$tr(
                tags$td(tags$strong(data$name)),
                tags$td(
                  sprintf("%.2f dBm (%.3f W)", result$final_pout_dbm, result$final_pout_w),
                  style = pout_style
                ),
                tags$td(
                  sprintf("%.1f%%", result$system_pae),
                  style = pae_style
                ),
                tags$td(sprintf("%.3f", result$total_pdc)),
                tags$td(sprintf("%.2f", result$total_gain)),
                tags$td(sprintf("%d", length(canvas_data[[paste0("canvas_", idx)]]$components)))
              )
            })
          )
        )
      ),
      
      # Backoff comparison
      if(all(sapply(comparison_data, function(d) !is.null(d$result$final_pout_bo_dbm)))) {
        backoff_value <- comparison_data[[1]]$result$backoff_db
        if(is.null(backoff_value)) backoff_value <- 6
        
        tagList(
          tags$h4(sprintf("Backoff Comparison (%.1f dB)", backoff_value), 
                  style = "color: #FF9800; margin-bottom: 15px; margin-top: 25px;"),
          tags$div(
            style = "overflow-x: auto;",
            tags$table(
              class = "table table-striped table-hover",
              tags$thead(
                tags$tr(
                  tags$th("Canvas", style = "background-color: #FF9800; color: white; font-weight: bold;"),
                  tags$th("Output Power", style = "background-color: #FF9800; color: white;"),
                  tags$th("PAE (%)", style = "background-color: #FF9800; color: white;"),
                  tags$th("DC Power (W)", style = "background-color: #FF9800; color: white;"),
                  tags$th("Heat Dissipation (W)", style = "background-color: #FF9800; color: white;")
                )
              ),
              tags$tbody(
                lapply(names(comparison_data), function(idx) {
                  data <- comparison_data[[idx]]
                  result <- data$result
                  
                  tags$tr(
                    tags$td(tags$strong(data$name)),
                    tags$td(sprintf("%.2f dBm (%.3f W)", result$final_pout_bo_dbm, result$final_pout_bo_w)),
                    tags$td(sprintf("%.1f%%", result$system_pae_bo)),
                    tags$td(sprintf("%.3f", result$total_pdc_bo)),
                    tags$td(sprintf("%.3f", result$total_pdiss_bo))
                  )
                })
              )
            )
          )
        )
      },
      
      # Summary statistics
      tags$div(
        class = "alert alert-info",
        style = "margin-top: 20px;",
        tags$strong(icon("chart-bar"), " Summary Statistics:"),
        tags$ul(
          style = "margin-top: 10px; margin-bottom: 0;",
          tags$li(sprintf("Canvases with results: %d / %d", length(comparison_data), canvas_count)),
          tags$li(sprintf("Avg Output Power: %.2f dBm", 
                         mean(sapply(comparison_data, function(d) d$result$final_pout_dbm)))),
          tags$li(sprintf("Avg PAE: %.1f%%", 
                         mean(sapply(comparison_data, function(d) d$result$system_pae)))),
          tags$li(sprintf("Total DC Power (all canvases): %.3f W", 
                         sum(sapply(comparison_data, function(d) d$result$total_pdc))))
        )
      )
    )
  })
  
  # PA Lineup Table
  output$pa_lineup_table <- renderDT({
    results <- lineup_calc_results()
    
    if(is.null(results) || !results$success || length(results$stage_results) == 0) {
      return(datatable(data.frame(Message = "No calculation data available")))
    }
    
    backoff_value <- if(!is.null(results$backoff_db)) results$backoff_db else 6
    
    # Build table from stage results with backoff columns
    rows <- lapply(results$stage_results, function(stage) {
      if(stage$type == "transistor") {
        de_full <- if (!is.null(stage$de_pct)) sprintf("%.1f", stage$de_pct) else "—"
        de_bo   <- if (!is.null(stage$de_bo_pct)) sprintf("%.1f", stage$de_bo_pct) else "—"
        data.frame(
          Stage = stage$stage,
          Type = "Transistor",
          Loss_dB = "—",
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = sprintf("%.1f", stage$pae_pct),
          DE_Full  = de_full,
          PDC_Full = sprintf("%.3f", stage$pdc_w),
          # Backoff columns
          Pin_BO = sprintf("%.2f", stage$pin_bo_dbm),
          Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
          PAE_BO = sprintf("%.1f", stage$pae_bo_pct),
          DE_BO  = de_bo,
          PDC_BO = sprintf("%.3f", stage$pdc_bo_w),
          # Separate gain columns (actual computed, not device property)
          Gain_P3dB = sprintf("%.2f", stage$gain_full_db),
          Gain_BO   = sprintf("%.2f", stage$gain_bo_db),
          Status = if(stage$compressed) "⚠ Compressed" else "✓ Linear",
          stringsAsFactors = FALSE
        )
      } else if(stage$type == "matching") {
        data.frame(
          Stage = stage$stage,
          Type = "Matching",
          Loss_dB = sprintf("%.2f", if(!is.null(stage$loss_db)) stage$loss_db else 0.5),
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = "—", DE_Full = "—",
          PDC_Full = "—",
          # Backoff columns (pin_bo_dbm stored directly in engine)
          Pin_BO = sprintf("%.2f", stage$pin_bo_dbm),
          Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
          PAE_BO = "—", DE_BO = "—",
          PDC_BO = "—",
          # Gain columns
          Gain_P3dB = sprintf("%.2f", stage$gain_full_db),
          Gain_BO   = sprintf("%.2f", stage$gain_bo_db),
          Status = "Passive",
          stringsAsFactors = FALSE
        )
      } else {
        # Splitters and combiners — use actual computed gains from engine
        loss_val <- if(!is.null(stage$loss_db)) stage$loss_db else 0.3
        data.frame(
          Stage = stage$stage,
          Type = tools::toTitleCase(stage$type),
          Loss_dB = sprintf("%.2f", loss_val),
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = "—", DE_Full = "—",
          PDC_Full = "—",
          # Backoff columns
          Pin_BO = if(!is.null(stage$pin_bo_dbm)) sprintf("%.2f", stage$pin_bo_dbm) else "—",
          Pout_BO = if(!is.null(stage$pout_bo_dbm)) sprintf("%.2f", stage$pout_bo_dbm) else "—",
          PAE_BO = "—", DE_BO = "—",
          PDC_BO = "—",
          # Gain columns: combiner gain at BO will reflect Doherty physics (≈−loss at BO)
          Gain_P3dB = if(!is.null(stage$gain_full_db)) sprintf("%.2f", stage$gain_full_db) else "—",
          Gain_BO   = if(!is.null(stage$gain_bo_db))   sprintf("%.2f", stage$gain_bo_db)   else "—",
          Status = "Passive",
          stringsAsFactors = FALSE
        )
      }
    })
    
    data <- do.call(rbind, rows)
    
    # Calculate totals for summary row
    total_loss <- sum(sapply(results$stage_results, function(stage) {
      if(stage$type == "matching" && !is.null(stage$loss_db)) {
        stage$loss_db
      } else if(stage$type %in% c("splitter", "combiner") && !is.null(stage$loss_db)) {
        stage$loss_db
      } else if(stage$type %in% c("splitter", "combiner")) {
        0.3
      } else {
        0
      }
    }))
    
    # Summary row with backoff data
    system_gain_full <- results$final_pout_dbm - results$input_power_dbm
    system_gain_bo   <- results$final_pout_bo_dbm - (results$input_power_dbm - backoff_value)
    sys_de    <- if (!is.null(results$system_de))    sprintf("%.1f", results$system_de)    else "—"
    sys_de_bo <- if (!is.null(results$system_de_bo)) sprintf("%.1f", results$system_de_bo) else "—"
    summary_row <- data.frame(
      Stage = "SYSTEM TOTAL",
      Type = "—",
      Loss_dB = "—",
      # Full power totals
      Pin_Full = sprintf("%.2f", results$input_power_dbm),
      Pout_Full = sprintf("%.2f", results$final_pout_dbm),
      PAE_Full = sprintf("%.1f", results$system_pae),
      DE_Full  = sys_de,
      PDC_Full = sprintf("%.3f", results$total_pdc),
      # Backoff totals
      Pin_BO = sprintf("%.2f", results$input_power_dbm - backoff_value),
      Pout_BO = sprintf("%.2f", results$final_pout_bo_dbm),
      PAE_BO = sprintf("%.1f", results$system_pae_bo),
      DE_BO  = sys_de_bo,
      PDC_BO = sprintf("%.3f", results$total_pdc_bo),
      # Gain totals (actual end-to-end computed)
      Gain_P3dB = sprintf("%.2f", system_gain_full),
      Gain_BO   = sprintf("%.2f", system_gain_bo),
      Status = if(length(results$warnings) > 0) "⚠ Check" else "✓ OK",
      stringsAsFactors = FALSE
    )
    
    data <- rbind(data, summary_row)
    
    # Create column names with grouped headers
    colnames(data) <- c(
      "Stage", "Type", "Loss(dB)",
      "Pin (dBm)", "Pout (dBm)", "PAE (%)", "DE (%)", "PDC (W)",
      "Pin (dBm) ", "Pout (dBm) ", "PAE (%) ", "DE (%) ", "PDC (W) ",
      "Gain@P3dB", "Gain@BO", "Status"
    )
    
    # ── Spec values for red-highlight comparison ──────────────────────────────
    spec_pout <- if (!is.null(input$spec_p3db)) as.numeric(input$spec_p3db) else NA_real_
    spec_gain <- if (!is.null(input$spec_gain)) as.numeric(input$spec_gain)  else NA_real_
    spec_pae  <- if (!is.null(input$spec_pae))  as.numeric(input$spec_pae)   else NA_real_

    # rowCallback: colour SYSTEM TOTAL cells red when they fall below spec
    row_cb <- JS(paste0(
      "function(row,data){",
      "  if(data[0]!=='SYSTEM TOTAL')return;",
      "  var sp=", if (!is.na(spec_pout)) spec_pout else "null", ";",
      "  var sg=", if (!is.na(spec_gain)) spec_gain else "null", ";",
      "  var se=", if (!is.na(spec_pae))  spec_pae  else "null", ";",
      "  var r='rgba(220,53,69,0.35)',t='#ffaaaa',b='bold';",
      "  if(sp!==null&&parseFloat(data[4])<sp)$('td:eq(4)',row).css({'background-color':r,'color':t,'font-weight':b});",
      "  if(se!==null&&parseFloat(data[5])<se)$('td:eq(5)',row).css({'background-color':r,'color':t,'font-weight':b});",
      "  if(sg!==null&&parseFloat(data[13])<sg)$('td:eq(13)',row).css({'background-color':r,'color':t,'font-weight':b});",
      "}"
    ))

    datatable(data, 
      options = list(
        pageLength = 20, 
        dom = 't',
        rowCallback = row_cb,
        columnDefs = list(
          list(className = 'dt-center', targets = 2:15)
        )
      ), 
      rownames = FALSE,
      container = htmltools::withTags(table(
        class = 'display',
        thead(
          tr(
            th(rowspan = 2, 'Stage'),
            th(rowspan = 2, 'Type'),
            th(rowspan = 2, 'Loss (dB)', style = 'background-color:#f8f0ff; border-bottom: 2px solid #9c27b0;'),
            th(colspan = 5, style = 'text-align:center; background-color:#e8f4f8; border-bottom: 2px solid #2196F3;', 'Full Power (P3dB)'),
            th(colspan = 5, style = 'text-align:center; background-color:#fff3e0; border-bottom: 2px solid #FF9800;', sprintf('Backoff / Pavg (%.1f dB)', backoff_value)),
            th(colspan = 2, style = 'text-align:center; background-color:#f0ffe0; border-bottom: 2px solid #4CAF50;', 'Stage Gain (dB)'),
            th(rowspan = 2, 'Status')
          ),
          tr(
            lapply(c('Pin (dBm)', 'Pout (dBm)', 'PAE (%)', 'DE (%)', 'PDC (W)'), th),
            lapply(c('Pin (dBm)', 'Pout (dBm)', 'PAE (%)', 'DE (%)', 'PDC (W)'), th),
            lapply(c('@P3dB', '@Pavg'), th)
          )
        )
      ))
    ) %>%
      formatStyle('Status',
        backgroundColor = styleEqual(
          c('✓ Linear', '⚠ Compressed', '✓ OK', '⚠ Check', 'Passive'),
          c('rgba(0,255,0,0.2)', 'rgba(255,165,0,0.3)', 'rgba(0,255,0,0.2)', 
            'rgba(255,165,0,0.3)', 'rgba(200,200,200,0.2)')
        )
      ) %>%
      formatStyle(3, backgroundColor = '#f8f0ff') %>%        # purple for Loss
      formatStyle(4:8, backgroundColor = '#f0f8ff') %>%      # Light blue for full power
      formatStyle(9:13, backgroundColor = '#fff8f0') %>%     # Light orange for backoff
      formatStyle(14:15, backgroundColor = '#f0fff0')        # Light green for gain columns
  })
  
  # Dynamic Tables UI - renders tabs for multi-canvas layouts
  output$pa_lineup_tables_dynamic <- renderUI({
    layout <- input$canvas_layout
    
    if(is.null(layout) || layout == "1x1") {
      # Single canvas mode - show single table
      return(DTOutput("pa_lineup_table"))
    }
    
    # Multi-canvas mode - create tabs
    canvas_count <- getCanvasCount(layout)
    
    tab_panels <- lapply(1:canvas_count, function(i) {
      tabPanel(
        title = rv$canvas_names[i],
        DTOutput(paste0("pa_lineup_table_", i))
      )
    })
    
    do.call(tabsetPanel, c(list(id = "table_tabs"), tab_panels))
  })
  
  # Dynamic Equations UI - renders tabs for multi-canvas layouts  
  output$pa_lineup_equations_dynamic <- renderUI({
    layout  <- input$canvas_layout
    results <- lineup_calc_results()
    cpt     <- as.integer(input$spec_compression_point %||% 3)
    cpt_lbl <- paste0("P", cpt, "dB")

    # ── Helper: build per-stage table rows ──────────────────────────────────
    make_power_rows <- function(res) {
      if (is.null(res) || !res$success || length(res$stage_results) == 0) return(NULL)
      rows <- lapply(res$stage_results, function(s) {
        tags$tr(
          tags$td(s$stage %||% s$type, style="padding:3px 6px;"),
          tags$td(sprintf("%.1f", s$pin_dbm  %||% NA), style="text-align:right;padding:3px 6px;"),
          tags$td(sprintf("%.1f", s$pout_dbm %||% NA), style="text-align:right;padding:3px 6px;"),
          tags$td(sprintf("%.1f", (s$pout_dbm %||% 0) - (s$pin_dbm %||% 0)),
                  style="text-align:right;padding:3px 6px;"),
          tags$td(if (!is.null(s$compressed) && isTRUE(s$compressed))
                    tags$span("⚠ compressed", style="color:red;") else "\u2713",
                  style="text-align:center;padding:3px 6px;")
        )
      })
      tags$table(style="width:100%; border-collapse:collapse; font-size:12px;",
        tags$thead(tags$tr(
          lapply(c("Stage","Pin (dBm)","Pout (dBm)","Stage G (dB)","Status"),
                 function(h) tags$th(h, style="text-align:left; border-bottom:1px solid #ccc; padding:3px 6px;"))
        )),
        tags$tbody(rows)
      )
    }

    make_gain_rows <- function(res) {
      if (is.null(res) || !res$success || length(res$stage_results) == 0) return(NULL)
      xstrs <- lapply(res$stage_results, function(s) {
        if (!is.null(s$type) && s$type == "transistor")
          tags$tr(
            tags$td(s$stage %||% "Stage", style="padding:3px 6px;"),
            tags$td(sprintf("%.2f dB", s$gain_db %||% 0), style="text-align:right;padding:3px 6px;"),
            tags$td(sprintf("%.1f dBm", s$pin_dbm  %||% 0), style="text-align:right;padding:3px 6px;"),
            tags$td(sprintf("%.1f dBm", s$pout_dbm %||% 0), style="text-align:right;padding:3px 6px;")
          )
      })
      tags$table(style="width:100%; border-collapse:collapse; font-size:12px;",
        tags$thead(tags$tr(
          lapply(c("Stage","Gain","Pin","Pout"),
                 function(h) tags$th(h, style="text-align:left; border-bottom:1px solid #ccc; padding:3px 6px;"))
        )),
        tags$tbody(xstrs)
      )
    }

    make_pae_rows <- function(res) {
      if (is.null(res) || !res$success || length(res$stage_results) == 0) return(NULL)
      rows <- lapply(res$stage_results, function(s) {
        if (!is.null(s$type) && s$type == "transistor") {
          pout_w <- if (!is.null(s$pout_w)) s$pout_w else
                    tryCatch(10^((s$pout_dbm - 30)/10), error=function(e) NA)
          tags$tr(
            tags$td(s$stage %||% "Stage", style="padding:3px 6px;"),
            tags$td(sprintf("%.1f%%", s$pae_pct %||% 0), style="text-align:right;padding:3px 6px;color:#27ae60;"),
            tags$td(sprintf("%.3f W", s$pdc_w   %||% 0), style="text-align:right;padding:3px 6px;"),
            tags$td(sprintf("%.3f W", s$pdiss_w %||% 0), style="text-align:right;padding:3px 6px;color:#e74c3c;")
          )
        }
      })
      tags$table(style="width:100%; border-collapse:collapse; font-size:12px;",
        tags$thead(tags$tr(
          lapply(c("Stage","PAE","P_DC (W)","P_diss (W)"),
                 function(h) tags$th(h, style="text-align:left; border-bottom:1px solid #ccc; padding:3px 6px;"))
        )),
        tags$tbody(rows)
      )
    }

    # ── Build 3-tab rationale panel ─────────────────────────────────────────
    build_rationale_tabs <- function(res) {
      tabsetPanel(
        id = "eq_rationale_tabs",

        # ── Tab 1: Power Cascade ──────────────────────────────────────────
        tabPanel(title = tagList(icon("bolt"), " Power"),
          br(),
          wellPanel(
            h5(icon("calculator"), " Power Cascade Formulas", style="color:#2196F3;"),
            HTML(paste0("
              <p><b>Operating Point:</b> Pout = ", cpt_lbl, " (user-selected compression reference)</p>
              <p><b>Pavg</b> = ", cpt_lbl, " &minus; PAR</p>
              <p><b>P<sub>out,i</sub></b> (dBm) = P<sub>in,i</sub> + G<sub>i</sub></p>
              <p><b>Backoff power:</b> P<sub>backoff</sub> = ", cpt_lbl, " &minus; BO (dB)</p>
              <p><b>Z<sub>opt</sub></b> = V<sub>dd</sub>&sup2; / (2 &times; P<sub>out</sub>)</p>
              <p style='color:#888; font-size:11px;'>dBm &rarr; W : P(W) = 10<sup>((dBm&minus;30)/10)</sup></p>
            "))
          ),
          if (!is.null(res) && res$success) {
            tagList(
              h5(icon("table"), " Per-Stage Power Results", style="color:#2196F3; margin-top:10px;"),
              make_power_rows(res)
            )
          } else tags$em("Run Calculate to see per-stage results.", style="color:#888;")
        ),

        # ── Tab 2: Gain ───────────────────────────────────────────────────
        tabPanel(title = tagList(icon("signal"), " Gain"),
          br(),
          wellPanel(
            h5(icon("calculator"), " Gain Calculation Formulas", style="color:#27ae60;"),
            HTML("
              <p><b>Stage Gain:</b> G<sub>i</sub> (dB) = P<sub>out,i</sub> &minus; P<sub>in,i</sub></p>
              <p><b>Cascaded Gain:</b> G<sub>total</sub> = &sum; G<sub>i</sub> (all stages in dB)</p>
              <p><b>Friis formula (noise figure):</b> NF<sub>total</sub> = NF<sub>1</sub> + (NF<sub>2</sub>&minus;1)/G<sub>1</sub> + ...</p>
              <p><b>Available Gain:</b> G<sub>A</sub> = |S<sub>21</sub>|&sup2; when conjugate-matched</p>
              <p style='color:#888; font-size:11px;'>Note: Gain rolls off ~20 dB/decade of frequency (fT limit).</p>
            ")
          ),
          if (!is.null(res) && res$success) {
            tagList(
              div(style="background:#f5fff5; padding:8px 12px; border-radius:4px; margin-bottom:8px;",
                strong("System Total Gain: "),
                span(sprintf("%.2f dB", res$total_gain), style="color:#27ae60; font-size:15px; font-weight:bold;")
              ),
              h5(icon("table"), " Per-Stage Gain", style="color:#27ae60; margin-top:10px;"),
              make_gain_rows(res)
            )
          } else tags$em("Run Calculate to see per-stage results.", style="color:#888;")
        ),

        # ── Tab 3: PAE ────────────────────────────────────────────────────
        tabPanel(title = tagList(icon("leaf"), " PAE / Efficiency"),
          br(),
          wellPanel(
            h5(icon("calculator"), " PAE & Efficiency Formulas", style="color:#e67e22;"),
            HTML("
              <p><b>PAE (per stage):</b> PAE<sub>i</sub> = (P<sub>out,i</sub> &minus; P<sub>in,i</sub>) / P<sub>DC,i</sub> &times; 100%</p>
              <p><b>Drain efficiency:</b> &eta;<sub>D</sub> = P<sub>out</sub> / P<sub>DC</sub></p>
              <p><b>DC Power:</b> P<sub>DC,i</sub> = P<sub>out,i</sub>(W) / PAE<sub>i</sub></p>
              <p><b>Dissipated Power:</b> P<sub>diss,i</sub> = P<sub>DC,i</sub> &minus; P<sub>out,i</sub>(W)</p>
              <p><b>System PAE:</b> PAE<sub>sys</sub> = P<sub>out,final</sub>(W) / &sum; P<sub>DC,i</sub>(W)</p>
              <p><b>Backoff PAE approx.:</b> PAE<sub>BO</sub> &asymp; PAE<sub>P3dB</sub> &times; (P<sub>out</sub>/P<sub>3dB</sub>)<sup>0.6</sup></p>
              <p style='color:#888; font-size:11px;'>Class-B ceiling: &eta;<sub>D</sub> = 78.5% &times; &radic;(P<sub>out</sub>/P<sub>sat</sub>).</p>
            ")
          ),
          if (!is.null(res) && res$success) {
            tagList(
              fluidRow(
                column(4, div(style="background:#f5fff5; padding:6px 10px; border-radius:4px;",
                  strong("System PAE @ P3dB: "),
                  span(sprintf("%.1f%%", res$system_pae), style="color:#27ae60; font-weight:bold;")
                )),
                column(4, div(style="background:#fff8f0; padding:6px 10px; border-radius:4px;",
                  strong("System PAE @ Pavg: "),
                  span(sprintf("%.1f%%", res$system_pae_bo), style="color:#e67e22; font-weight:bold;")
                )),
                column(4, div(style="background:#fff0f0; padding:6px 10px; border-radius:4px;",
                  strong("Total P_diss: "),
                  span(sprintf("%.2f W", res$total_pdiss), style="color:#e74c3c; font-weight:bold;")
                ))
              ),
              br(),
              h5(icon("table"), " Per-Stage PAE", style="color:#e67e22; margin-top:6px;"),
              make_pae_rows(res)
            )
          } else tags$em("Run Calculate to see per-stage results.", style="color:#888;")
        )
      )
    }

    if (is.null(layout) || layout == "1x1") {
      return(tagList(
        build_rationale_tabs(results),
        hr(),
        textAreaInput("lineup_custom_notes", "Design Notes:", 
          placeholder = "Add your notes, justifications, or remarks here...",
          rows = 4)
      ))
    }

    # Multi-canvas mode
    canvas_count <- getCanvasCount(layout)
    tab_panels <- lapply(1:canvas_count, function(i) {
      canvas_key <- paste0("canvas_", i - 1)
      cv_res     <- canvas_data[[canvas_key]]$results
      tabPanel(title = rv$canvas_names[i],
        build_rationale_tabs(cv_res)
      )
    })
    do.call(tabsetPanel, c(list(id = "equations_canvas_tabs"), tab_panels))
  })
  
  # Dynamic render outputs for multi-canvas tables and rationale
  observe({
    layout <- input$canvas_layout
    
    if(!is.null(layout) && layout != "1x1") {
      canvas_count <- getCanvasCount(layout)
      
      # Create render functions for each canvas
      lapply(1:canvas_count, function(i) {
        local({
          canvas_index <- i
          
          # Table output
          output_name_table <- paste0("pa_lineup_table_", canvas_index)
          output[[output_name_table]] <- renderDT({
            # Get results from per-canvas storage
            canvas_key <- paste0("canvas_", canvas_index - 1)
            results <- canvas_data[[canvas_key]]$results
            
            if(is.null(results) || !results$success || length(results$stage_results) == 0) {
              return(datatable(data.frame(Message = sprintf("No calculation data for Canvas %d. Click 'Calculate All Canvases'.", canvas_index))))
            }
            
            backoff_value <- if(!is.null(results$backoff_db)) results$backoff_db else 6
            
            # Build table from stage results with backoff columns
            rows <- lapply(results$stage_results, function(stage) {
              if(stage$type == "transistor") {
                data.frame(
                  Stage = stage$stage,
                  Type = "Transistor",
                  Pin_Full = sprintf("%.2f", stage$pin_dbm),
                  Pout_Full = sprintf("%.2f", stage$pout_dbm),
                  PAE_Full = sprintf("%.1f", stage$pae_pct),
                  PDC_Full = sprintf("%.3f", stage$pdc_w),
                  Pin_BO = sprintf("%.2f", stage$pin_bo_dbm),
                  Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
                  PAE_BO = sprintf("%.1f", stage$pae_bo_pct),
                  PDC_BO = sprintf("%.3f", stage$pdc_bo_w),
                  Gain_dB = sprintf("%.2f", stage$gain_db),
                  Status = if(stage$compressed) "⚠ Compressed" else "✓ Linear",
                  stringsAsFactors = FALSE
                )
              } else if(stage$type == "matching") {
                data.frame(
                  Stage = stage$stage,
                  Type = "Matching",
                  Pin_Full = sprintf("%.2f", stage$pin_dbm),
                  Pout_Full = sprintf("%.2f", stage$pout_dbm),
                  PAE_Full = "—",
                  PDC_Full = "—",
                  Pin_BO = sprintf("%.2f", stage$pout_bo_dbm - stage$loss_db),
                  Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
                  PAE_BO = "—",
                  PDC_BO = "—",
                  Gain_dB = sprintf("%.2f", -stage$loss_db),
                  Status = "Passive",
                  stringsAsFactors = FALSE
                )
              } else {
                loss_val <- if(!is.null(stage$loss_db)) stage$loss_db else 0.3
                gain_val <- if(stage$type == "combiner") 3 - loss_val else -loss_val
                
                data.frame(
                  Stage = stage$stage,
                  Type = tools::toTitleCase(stage$type),
                  Pin_Full = sprintf("%.2f", stage$pin_dbm),
                  Pout_Full = sprintf("%.2f", stage$pout_dbm),
                  PAE_Full = "—",
                  PDC_Full = "—",
                  Pin_BO = if(!is.null(stage$pin_bo_dbm)) sprintf("%.2f", stage$pin_bo_dbm) else "—",
                  Pout_BO = if(!is.null(stage$pout_bo_dbm)) sprintf("%.2f", stage$pout_bo_dbm) else "—",
                  PAE_BO = "—",
                  PDC_BO = "—",
                  Gain_dB = sprintf("%.2f", gain_val),
                  Status = "Passive",
                  stringsAsFactors = FALSE
                )
              }
            })
            
            data <- do.call(rbind, rows)
            
            # Summary row
            summary_row <- data.frame(
              Stage = "SYSTEM TOTAL",
              Type = "—",
              Pin_Full = sprintf("%.2f", results$input_power_dbm),
              Pout_Full = sprintf("%.2f", results$final_pout_dbm),
              PAE_Full = sprintf("%.1f", results$system_pae),
              PDC_Full = sprintf("%.3f", results$total_pdc),
              Pin_BO = sprintf("%.2f", results$input_power_dbm - backoff_value),
              Pout_BO = sprintf("%.2f", results$final_pout_bo_dbm),
              PAE_BO = sprintf("%.1f", results$system_pae_bo),
              PDC_BO = sprintf("%.3f", results$total_pdc_bo),
              Gain_dB = sprintf("%.2f", results$total_gain),
              Status = if(length(results$warnings) > 0) "⚠ Check" else "✓ OK",
              stringsAsFactors = FALSE
            )
            
            data <- rbind(data, summary_row)
            
            colnames(data) <- c(
              "Stage", "Type",
              "Pin (dBm)", "Pout (dBm)", "PAE (%)", "PDC (W)",
              "Pin (dBm) ", "Pout (dBm) ", "PAE (%) ", "PDC (W) ",
              "Gain (dB)", "Status"
            )
            
            datatable(data, 
              options = list(pageLength = 20, dom = 't', columnDefs = list(list(className = 'dt-center', targets = 2:11))), 
              rownames = FALSE,
              container = htmltools::withTags(table(
                class = 'display',
                thead(
                  tr(
                    th(rowspan = 2, 'Stage'),
                    th(rowspan = 2, 'Type'),
                    th(colspan = 4, style = 'text-align:center; background-color:#e8f4f8; border-bottom: 2px solid #2196F3;', 'Full Power'),
                    th(colspan = 4, style = 'text-align:center; background-color:#fff3e0; border-bottom: 2px solid #FF9800;', sprintf('Backoff (%.1f dB)', backoff_value)),
                    th(rowspan = 2, 'Gain (dB)'),
                    th(rowspan = 2, 'Status')
                  ),
                  tr(
                    lapply(c('Pin (dBm)', 'Pout (dBm)', 'PAE (%)', 'PDC (W)'), th),
                    lapply(c('Pin (dBm)', 'Pout (dBm)', 'PAE (%)', 'PDC (W)'), th)
                  )
                )
              ))
            ) %>%
              formatStyle('Status',
                backgroundColor = styleEqual(
                  c('✓ Linear', '⚠ Compressed', '✓ OK', '⚠ Check', 'Passive'),
                  c('rgba(0,255,0,0.2)', 'rgba(255,165,0,0.3)', 'rgba(0,255,0,0.2)', 
                    'rgba(255,165,0,0.3)', 'rgba(200,200,200,0.2)')
                )
              ) %>%
              formatStyle(3:6, backgroundColor = '#f0f8ff') %>%
              formatStyle(7:10, backgroundColor = '#fff8f0')
          })
          
          # Rationale output
          output_name_rationale <- paste0("lineup_rationale_", canvas_index)
          output[[output_name_rationale]] <- renderText({
            # Get results from per-canvas storage
            canvas_key <- paste0("canvas_", canvas_index - 1)
            results <- canvas_data[[canvas_key]]$results
            if(is.null(results) || !results$success) {
              return(sprintf("No calculation results for Canvas %d. Click 'Calculate All Canvases'.", canvas_index))
            }
            results$rationale
          })
        })
      })
    }
  })
  


}
