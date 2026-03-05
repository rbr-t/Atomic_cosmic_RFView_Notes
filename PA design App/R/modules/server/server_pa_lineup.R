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
          numericInput(paste0("prop_", selected, "_pout"), "Pout (dBm)", 
            value = as.numeric(getProp("pout", 43)), step = 0.5),
          numericInput(paste0("prop_", selected, "_p1db"), "P1dB (dBm)", 
            value = as.numeric(getProp("p1db", 43)), step = 0.5),
          numericInput(paste0("prop_", selected, "_gain"), "Gain (dB)", 
            value = as.numeric(getProp("gain", 15)), step = 0.1),
          numericInput(paste0("prop_", selected, "_pae"), "PAE (%)", 
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
  
  # PA Lineup Calculation Engine with Rationale
  lineup_calculate_engine <- function(components, connections, input_power_dbm = 0, backoff_db = 6) {
    if(is.null(components) || length(components) == 0) {
      return(list(
        success = FALSE,
        message = "No components in lineup",
        rationale = "Cannot perform calculations without components."
      ))
    }
    
    # Helper function to safely extract property values
    safeProp <- function(props, name, default) {
      if(is.null(props)) return(default)
      
      if(is.list(props) && !is.null(props[[name]])) {
        return(props[[name]])
      } else if(!is.null(names(props)) && name %in% names(props)) {
        return(props[[name]])
      } else {
        return(default)
      }
    }
    
    rationale <- c()
    rationale <- c(rationale, "═══════════════════════════════════════")
    rationale <- c(rationale, "  PA LINEUP CALCULATION RATIONALE")
    rationale <- c(rationale, "═══════════════════════════════════════\n")
    rationale <- c(rationale, sprintf("Input Power: %.2f dBm (%.4f W)", 
      input_power_dbm, 10^(input_power_dbm/10)/1000))
    rationale <- c(rationale, sprintf("Backoff Analysis: %.1f dB below full power\n", backoff_db))
    
    # Sort components by x position (left to right flow)
    tryCatch({
      components <- components[order(sapply(components, function(c) {
        if(is.list(c) && !is.null(c$x)) c$x else if("x" %in% names(c)) c[["x"]] else 0
      }))]
    }, error = function(e) {
      # If sorting fails, just use as-is
    })
    
    # Initialize cascade variables
    current_pin <- input_power_dbm
    current_pin_bo <- input_power_dbm - backoff_db  # Backoff input power
    total_gain <- 0
    total_pdc <- 0
    total_pdc_bo <- 0  # Backoff DC power
    stage_results <- list()
    warnings <- c()
    
    rationale <- c(rationale, "─── Stage-by-Stage Analysis ───")
    rationale <- c(rationale, "(Full Power | Backoff)\n")
    
    for(i in seq_along(components)) {
      comp <- components[[i]]
      
      # Safe property extraction
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
      
      stage_name <- safeProp(props, "label", paste0("Stage_", i))
      
      rationale <- c(rationale, sprintf("[%d] %s (%s)", i, stage_name, comp_type))
      rationale <- c(rationale, sprintf("    Input Power: %.2f dBm", current_pin))
      
      if(comp_type == "transistor") {
        # Transistor stage calculations
        gain <- as.numeric(safeProp(props, "gain", 15))
        p1db <- as.numeric(safeProp(props, "p1db", 43))
        vdd <- as.numeric(safeProp(props, "vdd", 28))
        rth <- as.numeric(safeProp(props, "rth", 2.5))
        
        # ═══ CHECK IF JAVASCRIPT ALREADY CALCULATED DUAL OPERATING POINTS ═══
        # JavaScript sends: pout_p3db, pin_p3db, pae_p3db, pout_pavg, pin_pavg, pae_pavg
        js_pout_p3db <- safeProp(props, "pout_p3db", NULL)
        js_pout_pavg <- safeProp(props, "pout_pavg", NULL)
        js_pin_p3db <- safeProp(props, "pin_p3db", NULL)
        js_pin_pavg <- safeProp(props, "pin_pavg", NULL)
        js_pae_p3db <- safeProp(props, "pae_p3db", NULL)
        js_pae_pavg <- safeProp(props, "pae_pavg", NULL)
        
        has_dual_op <- !is.null(js_pout_p3db) && !is.null(js_pout_pavg) && 
                       !is.null(js_pin_p3db) && !is.null(js_pin_pavg)
        
        # Debug logging
        cat(sprintf("[%s] Checking dual_op: pout_p3db=%s, pout_pavg=%s, has_dual_op=%s\n", 
          stage_name, 
          if(!is.null(js_pout_p3db)) as.character(js_pout_p3db) else "NULL",
          if(!is.null(js_pout_pavg)) as.character(js_pout_pavg) else "NULL",
          has_dual_op))
        
        if(has_dual_op) {
          # ✓ Use JavaScript-calculated values (from applySpecsToComponents)
          pout_dbm <- as.numeric(js_pout_p3db)
          pout_bo_dbm <- as.numeric(js_pout_pavg)
          
          # Use JavaScript-calculated PAE if available, else default
          pae_full <- if(!is.null(js_pae_p3db)) as.numeric(js_pae_p3db) / 100 else as.numeric(safeProp(props, "pae", 50)) / 100
          pae_bo <- if(!is.null(js_pae_pavg)) as.numeric(js_pae_pavg) / 100 else pae_full * 0.7
          
          rationale <- c(rationale, sprintf("    ✓ Using JavaScript dual operating points"))
          rationale <- c(rationale, sprintf("    Full (P3dB): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%", 
            as.numeric(js_pin_p3db), pout_dbm, pae_full * 100))
          rationale <- c(rationale, sprintf("    Backoff (Pavg): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%", 
            as.numeric(js_pin_pavg), pout_bo_dbm, pae_bo * 100))
        } else {
          # ═══ FALLBACK: Calculate using power cascade (NOT component p3db!) ═══
          # Both Full and Backoff use CASCADE positions, not component capabilities
          pout_dbm <- current_pin + gain
          pout_bo_dbm <- current_pin_bo + gain  # ← FIX: Use cascade, not component p3db!
          
          # Get default PAE
          pae_full <- as.numeric(safeProp(props, "pae", 50)) / 100
          
          # Estimate PAE at backoff (power-law degradation model)
          # PAE degrades as power reduces: PAE_bo = PAE_full * (Pout_bo/Pout_full)^0.8
          pout_ratio <- 10^((pout_bo_dbm - pout_dbm)/10)  # Power ratio (linear)
          pae_bo <- pae_full * (pout_ratio ^ 0.8)
          pae_bo <- max(pae_bo, 0.05)  # Minimum 5% efficiency
          
          rationale <- c(rationale, sprintf("    [Calculating from power cascade]"))
          rationale <- c(rationale, sprintf("    Full: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm", 
            current_pin, gain, pout_dbm))
          rationale <- c(rationale, sprintf("    Backoff: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm", 
            current_pin_bo, gain, pout_bo_dbm))
        }
        
        # Power calculations
        pout_w <- 10^(pout_dbm/10) / 1000
        pout_bo_w <- 10^(pout_bo_dbm/10) / 1000
        
        # Check compression at full power
        compressed <- pout_dbm > p1db
        if(compressed) {
          compression_amount <- pout_dbm - p1db
          warnings <- c(warnings, sprintf("%s: Compressed by %.1f dB", stage_name, compression_amount))
          rationale <- c(rationale, sprintf("    ⚠ WARNING: Output %.2f dBm exceeds P1dB %.2f dBm (compression: %.2f dB)", 
            pout_dbm, p1db, compression_amount))
          # Limit output to P1dB
          pout_dbm <- p1db
          pout_w <- 10^(pout_dbm/10) / 1000
        }
        
        # Check compression at backoff (should not compress!)
        compressed_bo <- pout_bo_dbm > p1db
        if(compressed_bo) {
          warnings <- c(warnings, sprintf("%s: Compressed at backoff (%.1f dB over P1dB)", 
            stage_name, pout_bo_dbm - p1db))
          rationale <- c(rationale, sprintf("    ⚠ WARNING: Backoff output %.2f dBm exceeds P1dB %.2f dBm!", 
            pout_bo_dbm, p1db))
          pout_bo_dbm <- p1db
          pout_bo_w <- 10^(pout_bo_dbm/10) / 1000
        }
        
        # Full power DC calculations
        pdc_w <- pout_w / pae_full
        pdiss_w <- pdc_w - pout_w
        idc_a <- pdc_w / vdd
        
        # Thermal calculation: Tj = Ta + Pdiss * Rth (assume Ta = 25°C)
        ta_c <- 25
        tj_c <- ta_c + pdiss_w * rth
        
        # === BACKOFF DC CALCULATIONS ===
        
        # Backoff DC power calculations
        pdc_bo_w <- pout_bo_w / pae_bo
        pdiss_bo_w <- pdc_bo_w - pout_bo_w
        tj_bo_c <- ta_c + pdiss_bo_w * rth
        
        rationale <- c(rationale, sprintf("    Full Power: Gain %.2f dB → Pout %.2f dBm (%.4f W)", 
          gain, pout_dbm, pout_w))
        rationale <- c(rationale, sprintf("    Full Power: PAE %.1f%% → PDC = %.3f W, PDiss = %.3f W",
          pae_full * 100, pdc_w, pdiss_w))
        rationale <- c(rationale, sprintf("    Backoff (%.1f dB): Pout %.2f dBm (%.4f W)", 
          backoff_db, pout_bo_dbm, pout_bo_w))
        rationale <- c(rationale, sprintf("    Backoff: PAE %.1f%% → PDC = %.3f W, PDiss = %.3f W",
          pae_bo * 100, pdc_bo_w, pdiss_bo_w))
        rationale <- c(rationale, sprintf("    Junction Temp: Full %.1f°C | Backoff %.1f°C",
          tj_c, tj_bo_c))
        
        if(tj_c > 150) {
          warnings <- c(warnings, sprintf("%s: High junction temp %.0f°C", stage_name, tj_c))
          rationale <- c(rationale, sprintf("    ⚠ WARNING: Junction temperature %.0f°C exceeds typical limit (150°C)", tj_c))
        }
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "transistor",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          gain_db = gain,
          pae_pct = pae_full * 100,  # ← FIX: Use calculated PAE, not component property!
          pdc_w = pdc_w,
          pdiss_w = pdiss_w,
          idc_a = idc_a,
          tj_c = tj_c,
          compressed = compressed,
          technology = safeProp(props, "technology", "GaN"),
          # Backoff metrics
          pin_bo_dbm = current_pin_bo,
          pout_bo_dbm = pout_bo_dbm,
          pae_bo_pct = pae_bo * 100,
          pdc_bo_w = pdc_bo_w,
          pdiss_bo_w = pdiss_bo_w,
          tj_bo_c = tj_bo_c,
          compressed_bo = compressed_bo
        )
        
        current_pin <- pout_dbm
        current_pin_bo <- pout_bo_dbm
        total_gain <- total_gain + gain
        total_pdc <- total_pdc + pdc_w
        total_pdc_bo <- total_pdc_bo + pdc_bo_w
        
      } else if(comp_type == "matching") {
        # Matching network: just loss, no DC power
        loss_db <- as.numeric(safeProp(props, "loss", 0.5))
        pout_dbm <- current_pin - loss_db
        pout_bo_dbm <- current_pin_bo - loss_db  # Backoff output
        
        rationale <- c(rationale, sprintf("    Loss: %.2f dB → Full: %.2f dBm | Backoff: %.2f dBm", 
          loss_db, pout_dbm, pout_bo_dbm))
        rationale <- c(rationale, sprintf("    Impedance transformation: %.1f Ω → %.1f Ω", 
          as.numeric(safeProp(props, "z_in", 50)), as.numeric(safeProp(props, "z_out", 50))))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "matching",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db,
          pin_bo_dbm = current_pin_bo,
          pout_bo_dbm = pout_bo_dbm
        )
        
        current_pin <- pout_dbm
        current_pin_bo <- pout_bo_dbm
        total_gain <- total_gain - loss_db
        
      } else if(comp_type == "splitter") {
        # Splitter: loss + split
        loss_db <- as.numeric(safeProp(props, "loss", 0.3))
        split_ratio_db <- as.numeric(safeProp(props, "split_ratio", 0))
        pout_dbm <- current_pin - loss_db
        pout_bo_dbm <- current_pin_bo - loss_db  # Backoff output
        
        rationale <- c(rationale, sprintf("    Insertion Loss: %.2f dB, Split Ratio: %.2f dB", 
          loss_db, split_ratio_db))
        rationale <- c(rationale, sprintf("    Output per path: Full %.2f dBm | Backoff %.2f dBm", 
          pout_dbm, pout_bo_dbm))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "splitter",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db,
          split_ratio = split_ratio_db,
          pin_bo_dbm = current_pin_bo,
          pout_bo_dbm = pout_bo_dbm
        )
        
        current_pin <- pout_dbm
        current_pin_bo <- pout_bo_dbm
        total_gain <- total_gain - loss_db
        
      } else if(comp_type == "combiner") {
        # Combiner: combine + loss
        loss_db <- as.numeric(safeProp(props, "loss", 0.3))
        combiner_type <- safeProp(props, "type", "Wilkinson")
        
        # If Doherty with load modulation, efficiency boost
        load_modulation <- isTRUE(safeProp(props, "load_modulation", FALSE))
        if(combiner_type == "Doherty" && load_modulation) {
          modulation_factor <- as.numeric(safeProp(props, "modulation_factor", 2.0))
          rationale <- c(rationale, sprintf("    Doherty Combiner with Load Modulation (Factor: %.1f)", 
            modulation_factor))
          rationale <- c(rationale, "    Load modulation improves back-off efficiency")
        }
        
        pout_dbm <- current_pin + 3 - loss_db  # 3dB from combining 2 paths
        pout_bo_dbm <- current_pin_bo + 3 - loss_db  # Backoff combining
        
        rationale <- c(rationale, sprintf("    Combining gain: +3 dB (2-way), Loss: %.2f dB", loss_db))
        rationale <- c(rationale, sprintf("    Output: Full %.2f dBm | Backoff %.2f dBm", 
          pout_dbm, pout_bo_dbm))
        
        stage_results[[length(stage_results) + 1]] <- list(
          stage = stage_name,
          type = "combiner",
          pin_dbm = current_pin,
          pout_dbm = pout_dbm,
          loss_db = loss_db,
          combining_gain = 3,
          pin_bo_dbm = current_pin_bo,
          pout_bo_dbm = pout_bo_dbm
        )
        
        current_pin <- pout_dbm
        current_pin_bo <- pout_bo_dbm
        total_gain <- total_gain + 3 - loss_db
      }
      
      rationale <- c(rationale, "")
    }
    
    # System totals - Full Power
    final_pout_dbm <- current_pin
    final_pout_w <- 10^(final_pout_dbm/10) / 1000
    system_pae <- if(total_pdc > 0) (final_pout_w / total_pdc) * 100 else 0
    
    # System totals - Backoff
    final_pout_bo_dbm <- current_pin_bo
    final_pout_bo_w <- 10^(final_pout_bo_dbm/10) / 1000
    system_pae_bo <- if(total_pdc_bo > 0) (final_pout_bo_w / total_pdc_bo) * 100 else 0
    
    rationale <- c(rationale, "─── System Summary ───")
    rationale <- c(rationale, sprintf("Total Gain: %.2f dB", total_gain))
    rationale <- c(rationale, "\n[FULL POWER]")
    rationale <- c(rationale, sprintf("  Output Power: %.2f dBm (%.3f W)", final_pout_dbm, final_pout_w))
    rationale <- c(rationale, sprintf("  Total DC Power: %.3f W", total_pdc))
    rationale <- c(rationale, sprintf("  System PAE: %.1f%%", system_pae))
    rationale <- c(rationale, sprintf("  Heat Dissipation: %.3f W", total_pdc - final_pout_w))
    rationale <- c(rationale, sprintf("\n[BACKOFF (%.1f dB)]", backoff_db))
    rationale <- c(rationale, sprintf("  Output Power: %.2f dBm (%.3f W)", final_pout_bo_dbm, final_pout_bo_w))
    rationale <- c(rationale, sprintf("  Total DC Power: %.3f W", total_pdc_bo))
    rationale <- c(rationale, sprintf("  System PAE: %.1f%%", system_pae_bo))
    rationale <- c(rationale, sprintf("  Heat Dissipation: %.3f W", total_pdc_bo - final_pout_bo_w))
    
    if(length(warnings) > 0) {
      rationale <- c(rationale, "\n─── Warnings ───")
      for(w in warnings) {
        rationale <- c(rationale, paste0("⚠ ", w))
      }
    } else {
      rationale <- c(rationale, "\n✓ All stages operating within specifications")
    }
    
    rationale <- c(rationale, "\n═══════════════════════════════════════")
    
    list(
      success = TRUE,
      backoff_db = backoff_db,
      input_power_dbm = input_power_dbm,
      final_pout_dbm = final_pout_dbm,
      final_pout_w = final_pout_w,
      total_gain = total_gain,
      total_pdc = total_pdc,
      system_pae = system_pae,
      total_pdiss = total_pdc - final_pout_w,
      # Backoff system metrics
      final_pout_bo_dbm = final_pout_bo_dbm,
      final_pout_bo_w = final_pout_bo_w,
      total_pdc_bo = total_pdc_bo,
      system_pae_bo = system_pae_bo,
      total_pdiss_bo = total_pdc_bo - final_pout_bo_w,
      stage_results = stage_results,
      warnings = warnings,
      rationale = paste(rationale, collapse = "\n")
    )
  }
  
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
  

  # Property apply button observer - uses reactive approach for dynamic buttons
  observeEvent(input$lineup_selected_component, {
    selected <- input$lineup_selected_component
    
    if(is.null(selected) || length(selected) == 0) return()
    
    btn_id <- paste0("apply_props_", selected)
    
    cat(sprintf("[Property Observer] Component %s selected, setting up observer for button: %s\n", 
                selected, btn_id))
    
    # Create a NEW observer for this specific button
    observeEvent(input[[btn_id]], {
      cat(sprintf("[Property Observer] Button %s clicked! Value: %s\n", 
                  btn_id, input[[btn_id]]))
      
      components <- lineup_components()
      
      # Find the component
      comp_idx <- which(sapply(components, function(c) {
        if(is.list(c) && !is.null(c$id)) c$id == selected else FALSE
      }))
      
      if(length(comp_idx) == 0) {
        showNotification("Component not found", type = "error")
        return()
      }
      
      comp <- components[[comp_idx]]
      comp_type <- if(is.list(comp) && !is.null(comp$type)) comp$type else "transistor"
      
      cat(sprintf("[Property Observer] Component type: %s\n", comp_type))
      
      # Collect properties based on component type (NOTE: IDs are prop_{id}_{field})
      properties <- list()
      
      if(comp_type == "transistor") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$technology <- input[[paste0("prop_", selected, "_technology")]]
        properties$biasClass <- input[[paste0("prop_", selected, "_biasClass")]]
        properties$gain <- input[[paste0("prop_", selected, "_gain")]]
        properties$pout <- input[[paste0("prop_", selected, "_pout")]]
        properties$p1db <- input[[paste0("prop_", selected, "_p1db")]]
        properties$pae <- input[[paste0("prop_", selected, "_pae")]]
        properties$vdd <- input[[paste0("prop_", selected, "_vdd")]]
        properties$rth <- input[[paste0("prop_", selected, "_rth")]]
        properties$freq <- input[[paste0("prop_", selected, "_freq")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "matching") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$z_in <- input[[paste0("prop_", selected, "_z_in")]]
        properties$z_out <- input[[paste0("prop_", selected, "_z_out")]]
        properties$bandwidth <- input[[paste0("prop_", selected, "_bandwidth")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "splitter") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$split_ratio <- input[[paste0("prop_", selected, "_split_ratio")]]
        properties$isolation <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "combiner") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$isolation <- input[[paste0("prop_", selected, "_isolation")]]
        properties$loss <- input[[paste0("prop_", selected, "_loss")]]
        properties$load_modulation <- input[[paste0("prop_", selected, "_load_modulation")]]
        properties$modulation_factor <- input[[paste0("prop_", selected, "_modulation_factor")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      } else if(comp_type == "termination") {
        properties$label <- input[[paste0("prop_", selected, "_label")]]
        properties$impedance <- input[[paste0("prop_", selected, "_impedance")]]
        properties$type <- input[[paste0("prop_", selected, "_type")]]
        properties$display <- input[[paste0("prop_", selected, "_display")]]
      }
      
      cat(sprintf("[Property Observer] Collected %d properties\n", length(properties)))
      cat(sprintf("[Property Observer] Sending updateComponent message to JavaScript...\n"))
      
      # Send to JavaScript
      session$sendCustomMessage("updateComponent", list(
        id = selected,
        properties = properties
      ))
      
      showNotification("Component properties updated", type = "message")
    }, ignoreNULL = TRUE, ignoreInit = TRUE)
  }, ignoreNULL = TRUE, ignoreInit = FALSE)
  

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
        data.frame(
          Stage = stage$stage,
          Type = "Transistor",
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = sprintf("%.1f", stage$pae_pct),
          PDC_Full = sprintf("%.3f", stage$pdc_w),
          # Backoff columns
          Pin_BO = sprintf("%.2f", stage$pin_bo_dbm),
          Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
          PAE_BO = sprintf("%.1f", stage$pae_bo_pct),
          PDC_BO = sprintf("%.3f", stage$pdc_bo_w),
          # Common columns
          Gain_dB = sprintf("%.2f", stage$gain_db),
          Status = if(stage$compressed) "⚠ Compressed" else "✓ Linear",
          stringsAsFactors = FALSE
        )
      } else if(stage$type == "matching") {
        data.frame(
          Stage = stage$stage,
          Type = "Matching",
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = "—",
          PDC_Full = "—",
          # Backoff columns
          Pin_BO = sprintf("%.2f", stage$pout_bo_dbm - stage$loss_db),
          Pout_BO = sprintf("%.2f", stage$pout_bo_dbm),
          PAE_BO = "—",
          PDC_BO = "—",
          # Common columns
          Gain_dB = sprintf("%.2f", -stage$loss_db),
          Status = "Passive",
          stringsAsFactors = FALSE
        )
      } else {
        # Splitters and combiners
        loss_val <- if(!is.null(stage$loss_db)) stage$loss_db else 0.3
        gain_val <- if(stage$type == "combiner") 3 - loss_val else -loss_val
        
        data.frame(
          Stage = stage$stage,
          Type = tools::toTitleCase(stage$type),
          # Full power columns
          Pin_Full = sprintf("%.2f", stage$pin_dbm),
          Pout_Full = sprintf("%.2f", stage$pout_dbm),
          PAE_Full = "—",
          PDC_Full = "—",
          # Backoff columns
          Pin_BO = if(!is.null(stage$pin_bo_dbm)) sprintf("%.2f", stage$pin_bo_dbm) else "—",
          Pout_BO = if(!is.null(stage$pout_bo_dbm)) sprintf("%.2f", stage$pout_bo_dbm) else "—",
          PAE_BO = "—",
          PDC_BO = "—",
          # Common columns
          Gain_dB = sprintf("%.2f", gain_val),
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
    summary_row <- data.frame(
      Stage = "SYSTEM TOTAL",
      Type = "—",
      # Full power totals
      Pin_Full = sprintf("%.2f", results$input_power_dbm),
      Pout_Full = sprintf("%.2f", results$final_pout_dbm),
      PAE_Full = sprintf("%.1f", results$system_pae),
      PDC_Full = sprintf("%.3f", results$total_pdc),
      # Backoff totals
      Pin_BO = sprintf("%.2f", results$input_power_dbm - backoff_value),
      Pout_BO = sprintf("%.2f", results$final_pout_bo_dbm),
      PAE_BO = sprintf("%.1f", results$system_pae_bo),
      PDC_BO = sprintf("%.3f", results$total_pdc_bo),
      # Common
      Gain_dB = sprintf("%.2f", results$total_gain),
      Status = if(length(results$warnings) > 0) "⚠ Check" else "✓ OK",
      stringsAsFactors = FALSE
    )
    
    data <- rbind(data, summary_row)
    
    # Create column names with grouped headers
    colnames(data) <- c(
      "Stage", "Type",
      "Pin (dBm)", "Pout (dBm)", "PAE (%)", "PDC (W)",
      "Pin (dBm) ", "Pout (dBm) ", "PAE (%) ", "PDC (W) ",
      "Gain (dB)", "Status"
    )
    
    datatable(data, 
      options = list(
        pageLength = 20, 
        dom = 't',
        columnDefs = list(
          list(className = 'dt-center', targets = 2:11)
        )
      ), 
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
      formatStyle(3:6, backgroundColor = '#f0f8ff') %>%  # Light blue for full power
      formatStyle(7:10, backgroundColor = '#fff8f0')     # Light orange for backoff
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
    layout <- input$canvas_layout
    
    if(is.null(layout) || layout == "1x1") {
      # Single canvas mode - show single equations view
      return(tagList(
        wellPanel(
          h4("PA Lineup Equations"),
          HTML("
            <h5>Power Cascade:</h5>
            <p><b>P<sub>out,i</sub> (dBm)</b> = P<sub>in,i</sub> + G<sub>i</sub></p>
            <p><b>P<sub>in,i+1</sub></b> = P<sub>out,i</sub></p>
            
            <h5>Total Gain:</h5>
            <p><b>G<sub>total</sub> (dB)</b> = Σ G<sub>i</sub></p>
            
            <h5>Power Dissipation (per stage):</h5>
            <p><b>P<sub>diss,i</sub> (W)</b> = P<sub>out,i</sub>(W) · (1/PAE<sub>i</sub> - 1)</p>
            
            <h5>DC Power (per stage):</h5>
            <p><b>P<sub>DC,i</sub> (W)</b> = P<sub>out,i</sub>(W) / PAE<sub>i</sub></p>
            
            <h5>Total System PAE:</h5>
            <p><b>PAE<sub>total</sub></b> = P<sub>out,final</sub> / Σ P<sub>DC,i</sub></p>
            
            <h5>Compression Check:</h5>
            <p>For each stage: <b>P<sub>out,i</sub> ≤ P1dB<sub>i</sub></b></p>
            <p>If P<sub>out,i</sub> > P1dB<sub>i</sub>: <span style='color:red;'>⚠ Compression Warning</span></p>
            
            <h5>For Doherty Architecture:</h5>
            <p><b>Load Modulation:</b> Main PA operates at higher impedance at backoff</p>
            <p><b>Auxiliary Turn-on:</b> Typically at 6dB backoff from P1dB</p>
            <p><b>Combining Efficiency:</b> Accounts for impedance transformation losses</p>
            
            <h5>Thermal Calculations:</h5>
            <p><b>Junction Temp:</b> T<sub>j</sub> = T<sub>a</sub> + P<sub>diss</sub> · R<sub>θja</sub></p>
          ")
        ),
        hr(),
        h4("Calculation Rationale:"),
        verbatimTextOutput("lineup_rationale"),
        hr(),
        textAreaInput("lineup_custom_notes", "Design Notes:", 
          placeholder = "Add your notes, justifications, or remarks here...",
          rows = 4)
      ))
    }
    
    # Multi-canvas mode - create tabs
    canvas_count <- getCanvasCount(layout)
    
    tab_panels <- lapply(1:canvas_count, function(i) {
      tabPanel(
        title = rv$canvas_names[i],
        wellPanel(
          h4(sprintf("%s - PA Lineup Equations", rv$canvas_names[i])),
          HTML("
            <h5>Power Cascade:</h5>
            <p><b>P<sub>out,i</sub> (dBm)</b> = P<sub>in,i</sub> + G<sub>i</sub></p>
            <p><b>P<sub>in,i+1</sub></b> = P<sub>out,i</sub></p>
            
            <h5>Total Gain:</h5>
            <p><b>G<sub>total</sub> (dB)</b> = Σ G<sub>i</sub></p>
            
            <h5>DC Power (per stage):</h5>
            <p><b>P<sub>DC,i</sub> (W)</b> = P<sub>out,i</sub>(W) / PAE<sub>i</sub></p>
            
            <h5>Total System PAE:</h5>
            <p><b>PAE<sub>total</sub></b> = P<sub>out,final</sub> / Σ P<sub>DC,i</sub></p>
          ")
        ),
        hr(),
        h4("Calculation Rationale:"),
        verbatimTextOutput(paste0("lineup_rationale_", i))
      )
    })
    
    do.call(tabsetPanel, c(list(id = "equations_tabs"), tab_panels))
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
