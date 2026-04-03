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

  get_secondary_backoff <- function() {
    if (!is.null(input$backoff_db_secondary) && is.finite(input$backoff_db_secondary) && input$backoff_db_secondary > 0) {
      return(input$backoff_db_secondary)
    }
    if (!is.null(input$spec_par_secondary) && is.finite(input$spec_par_secondary) && input$spec_par_secondary > 0) {
      return(input$spec_par_secondary)
    }
    if (has_three_way_doherty_combiner()) {
      return(get_primary_backoff_for_secondary() * 2)
    }
    NULL
  }

  merge_secondary_backoff_result <- function(primary_result, secondary_result, secondary_backoff) {
    merged <- primary_result
    merged$backoff_db_secondary <- secondary_backoff
    merged$bo_profile <- list(
      primary = primary_result$backoff_db,
      secondary = secondary_backoff,
      has_secondary = TRUE
    )
    merged$final_pout_bo2_dbm <- secondary_result$final_pout_bo_dbm
    merged$final_pout_bo2_w   <- secondary_result$final_pout_bo_w
    merged$system_pae_bo2     <- secondary_result$system_pae_bo
    merged$system_de_bo2      <- secondary_result$system_de_bo
    merged$total_pdc_bo2      <- secondary_result$total_pdc_bo
    merged$total_pdiss_bo2    <- secondary_result$total_pdiss_bo

    secondary_stages <- secondary_result$stage_results %||% list()
    merged$stage_results <- lapply(primary_result$stage_results %||% list(), function(stage) {
      match_idx <- which(vapply(secondary_stages, function(other) {
        same_id <- !is.null(stage$id) && !is.null(other$id) && identical(as.character(stage$id), as.character(other$id))
        same_name <- !is.null(stage$stage) && !is.null(other$stage) && identical(stage$stage, other$stage)
        same_id || same_name
      }, logical(1)))

      if (length(match_idx) == 0) return(stage)

      secondary_stage <- secondary_stages[[match_idx[[1]]]]
      stage$pin_bo2_dbm  <- secondary_stage$pin_bo_dbm
      stage$pout_bo2_dbm <- secondary_stage$pout_bo_dbm
      stage$gain_bo2_db  <- secondary_stage$gain_bo_db
      stage$pdc_bo2_w    <- secondary_stage$pdc_bo_w
      if (!is.null(secondary_stage$pae_bo_pct)) stage$pae_bo2_pct <- secondary_stage$pae_bo_pct
      if (!is.null(secondary_stage$de_bo_pct))  stage$de_bo2_pct  <- secondary_stage$de_bo_pct
      stage
    })

    secondary_warnings <- secondary_result$warnings %||% character(0)
    if (length(secondary_warnings) > 0) {
      merged$warnings <- unique(c(primary_result$warnings %||% character(0), paste0("[BO2] ", secondary_warnings)))
    }

    merged
  }
  
  # ── Push spec changes (PAR / P3dB / frequency) to JavaScript immediately ──
  # This keeps canvas Pavg targets in sync without requiring a button click.
  observe({
    req(input$spec_p3db)
    par_val  <- get_primary_backoff_for_secondary()
    par2_val <- get_secondary_backoff()
    p3db_val <- input$spec_p3db
    freq_val <- if (!is.null(input$spec_frequency))    input$spec_frequency    else 2000
    gain_val <- if (!is.null(input$spec_gain))         input$spec_gain         else 30
    vdd_val  <- if (!is.null(input$spec_supply_voltage)) input$spec_supply_voltage else 28
    comp_pt  <- if (!is.null(input$spec_compression_point))
                  as.integer(input$spec_compression_point) else 3L

    session$sendCustomMessage("syncLineupSpecs", list(
      par              = par_val,
      par_secondary    = par2_val,
      p3db             = p3db_val,
      pavg             = p3db_val - par_val,
      pavg2            = if (!is.null(par2_val)) p3db_val - par2_val else NULL,
      bo_profile       = list(
        primary = par_val,
        secondary = par2_val,
        has_secondary = !is.null(par2_val)
      ),
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
    }
  })
  
  # Update component list when canvas changes
  observeEvent(input$lineup_components, {
    if(!is.null(input$lineup_components)) {
      # Components are sent as a JSON string from JavaScript
      comps_json <- input$lineup_components
      
      # Parse JSON string to R list
      comps <- tryCatch({
        parsed <- jsonlite::fromJSON(comps_json, simplifyVector = FALSE)
        parsed
      }, error = function(e) {
        warning(sprintf("[lineup] Components JSON parse error: %s", e$message))
        list()
      })
      
      # Store the parsed components (global - backwards compatibility)
      lineup_components(comps)
      
      # Also store per-canvas
      canvas_idx <- active_canvas_index()
      canvas_key <- paste0("canvas_", canvas_idx)
      canvas_data[[canvas_key]]$components <- comps
    }
  })
  
  # Update connections when canvas changes
  observeEvent(input$lineup_connections, {
    if(!is.null(input$lineup_connections)) {
      # Connections are sent as a JSON string from JavaScript
      conns_json <- input$lineup_connections
      
      # Parse JSON string to R list
      conns <- tryCatch({
        parsed <- jsonlite::fromJSON(conns_json, simplifyVector = FALSE)
        parsed
      }, error = function(e) {
        warning(sprintf("[lineup] Connections JSON parse error: %s", e$message))
        list()
      })
      
      # Store the parsed connections (global - backwards compatibility)
      lineup_connections(conns)
      
      # Also store per-canvas
      canvas_idx <- active_canvas_index()
      canvas_key <- paste0("canvas_", canvas_idx)
      canvas_data[[canvas_key]]$connections <- conns
    }
  })
  
  # Observer for canvas layout changes
  observeEvent(input$canvas_layout, {
    if(!is.null(input$canvas_layout)) {
      # Send layout update to JavaScript
      session$sendCustomMessage("updateCanvasLayout", list(
        layout = input$canvas_layout
      ))
    }
  }, ignoreInit = TRUE)

  # ── 4.1 ↔ 4.2 Spec sync ─────────────────────────────────────────────────
  # dev_spec_gain (4.1) and spec_gain (4.2 canvas) must stay in sync.
  # Renaming 4.1 input to dev_spec_gain eliminates the duplicate-ID bug.
  # These observers keep both tabs consistent and warn on divergence.

  .spec_syncing <- reactiveVal(FALSE)   # prevents infinite observer loops

  observeEvent(input$dev_spec_gain, {
    if (.spec_syncing()) return()
    if (!is.null(input$spec_gain) && !isTRUE(all.equal(input$dev_spec_gain, input$spec_gain))) {
      .spec_syncing(TRUE)
      updateNumericInput(session, "spec_gain", value = input$dev_spec_gain)
      .spec_syncing(FALSE)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$spec_gain, {
    if (.spec_syncing()) return()
    if (!is.null(input$dev_spec_gain) && !isTRUE(all.equal(input$spec_gain, input$dev_spec_gain))) {
      .spec_syncing(TRUE)
      updateNumericInput(session, "dev_spec_gain", value = input$spec_gain)
      .spec_syncing(FALSE)
      showNotification(
        paste0("\u26a0 Gain spec updated in 4.2 canvas (",
               round(input$spec_gain, 1), " dB). 4.1 updated to match."),
        type = "warning", duration = 5
      )
    }
  }, ignoreInit = TRUE)

  observeEvent(input$dev_spec_pae, {
    if (.spec_syncing()) return()
    if (!is.null(input$spec_pae) && !isTRUE(all.equal(input$dev_spec_pae, input$spec_pae))) {
      .spec_syncing(TRUE)
      updateNumericInput(session, "spec_pae", value = input$dev_spec_pae)
      .spec_syncing(FALSE)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$spec_pae, {
    if (.spec_syncing()) return()
    if (!is.null(input$dev_spec_pae) && !isTRUE(all.equal(input$spec_pae, input$dev_spec_pae))) {
      .spec_syncing(TRUE)
      updateNumericInput(session, "dev_spec_pae", value = input$spec_pae)
      .spec_syncing(FALSE)
      showNotification(
        paste0("\u26a0 PAE spec updated in 4.2 canvas (",
               round(input$spec_pae, 1), "%). 4.1 updated to match."),
        type = "warning", duration = 5
      )
    }
  }, ignoreInit = TRUE)

  # Spec mismatch warning panel (rendered in 4.1 tab)
  output$spec_sync_warning <- renderUI({
    g41 <- input$dev_spec_gain;  g42 <- input$spec_gain
    p41 <- input$dev_spec_pae;   p42 <- input$spec_pae
    if (is.null(g41) || is.null(g42) || is.null(p41) || is.null(p42)) return(NULL)
    mismatches <- character(0)
    if (!isTRUE(all.equal(round(g41, 1), round(g42, 1))))
      mismatches <- c(mismatches, sprintf("Gain: 4.1 = %.1f dB, 4.2 = %.1f dB", g41, g42))
    if (!isTRUE(all.equal(round(p41, 1), round(p42, 1))))
      mismatches <- c(mismatches, sprintf("PAE: 4.1 = %.1f%%, 4.2 = %.1f%%", p41, p42))
    if (length(mismatches) == 0) return(NULL)
    div(style = "margin-top:6px; padding:6px 10px; background:rgba(255,193,7,.15);
                 border-left:3px solid #ffc107; border-radius:3px;",
      icon("exclamation-triangle", style = "color:#ffc107;"),
      tags$strong(" Spec mismatch between 4.1 and 4.2:", style = "color:#ffc107;"),
      tags$ul(lapply(mismatches, tags$li), style = "margin:4px 0 0 12px; padding:0;")
    )
  })

  # ── 4.1 → 4.2 Explicit Sync Button ──────────────────────────────────────
  # Pushes all 4.1 spec fields to the corresponding 4.2 canvas spec inputs.
  observeEvent(input$sync_41_to_42, {
    .spec_syncing(TRUE)
    # Gain and PAE
    if (!is.null(input$dev_spec_gain))
      updateNumericInput(session, "spec_gain", value = input$dev_spec_gain)
    if (!is.null(input$dev_spec_pae))
      updateNumericInput(session, "spec_pae",  value = input$dev_spec_pae)
    # Pout → P3dB
    if (!is.null(input$spec_pout))
      updateNumericInput(session, "spec_p3db", value = input$spec_pout)
    # Back-off → PAR
    if (!is.null(input$spec_backoff))
      updateNumericInput(session, "spec_par",  value = input$spec_backoff)
    # Supply voltage
    if (!is.null(input$spec_vdd))
      updateNumericInput(session, "spec_supply_voltage", value = input$spec_vdd)
    # Frequency: convert GHz centre to MHz for the 4.2 frequency input
    if (!is.null(input$spec_freq_lo) && !is.null(input$spec_freq_hi)) {
      centre_mhz <- ((input$spec_freq_lo + input$spec_freq_hi) / 2) * 1000
      updateNumericInput(session, "spec_frequency", value = round(centre_mhz, 0))
    }
    .spec_syncing(FALSE)
    showNotification(
      "\u2713 4.1 specs synced to 4.2 canvas.",
      type = "message", duration = 4
    )
  }, ignoreInit = TRUE)

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
    
    removeModal()
  })
  
  # Dynamic Property Editor based on selected component
  output$lineup_property_editor <- renderUI({
    selected <- input$lineup_selected_component
    
    if(is.null(selected) || length(selected) == 0) {
      return(tags$div(
        style = "padding: 20px; text-align: center; color: #888;",
        tags$p("Select a component on canvas to edit properties")
      ))
    }
    
    components <- lineup_components()
    if(is.null(components) || length(components) == 0) {
      return(tags$div(style = "padding: 20px;", "No components in lineup"))
    }
    
    # Find the selected component
    comp <- NULL
    tryCatch({
      for(i in seq_along(components)) {
        c <- components[[i]]
        # Handle both list and vector access
        comp_id <- if(is.list(c)) c$id else if(is.vector(c) && "id" %in% names(c)) c["id"] else NULL
        
        if(!is.null(comp_id) && comp_id == selected) {
          comp <- c
          break
        }
      }
    }, error = function(e) {
      warning(sprintf("[lineup] Property editor error: %s", e$message))
    })
    
    if(is.null(comp)) {
      return(tags$div(
        style = "padding: 20px; color: #888;",
        "Component not found. ID: ", selected,
        tags$br(),
        tags$small("Try clicking on a component again")
      ))
    }
    
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
        tagList(
          h4(paste0("Transistor: ", getProp("label", "Transistor"))),
          textInput(paste0("prop_", selected, "_label"), "Label", 
            value = getProp("label", "Transistor")),
          selectInput(paste0("prop_", selected, "_technology"), "Technology",
            choices = c(
              "GaN HEMT (SiC)"  = "GaN_SiC",
              "GaN HEMT (Si)"   = "GaN_Si",
              "Si LDMOS"        = "LDMOS",
              "GaAs pHEMT"      = "GaAs_pHEMT",
              "SiGe HBT"        = "SiGe",
              "InP HEMT"        = "InP",
              "Custom"          = "custom"
            ),
            selected = getProp("technology", "GaN_SiC"),
            selectize = FALSE),
          selectInput(paste0("prop_", selected, "_biasClass"), "Biasing Class",
            choices = c("A", "AB", "B", "C", "D", "E", "F"),
            selected = getProp("biasClass", "AB"),
            selectize = FALSE),
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
      } else if (comp_type == "offset_line") {
        tagList(
          h4(paste0("\u03bb/4 Line: ", getProp("label", "\u03bb/4 Line"))),
          textInput(paste0("prop_", selected, "_label"), "Label",
            value = getProp("label", "\u03bb/4 Line")),
          selectInput(paste0("prop_", selected, "_offset_role"), "Role",
            choices = c(
              "Phase Offset (Input)" = "phase",
              "Impedance Inverter (Output)" = "inverter",
              "Transformer" = "transformer"
            ),
            selected = getProp("offset_role", "phase")),
          numericInput(paste0("prop_", selected, "_phase_shift_deg"), "Phase Shift (\u00b0)",
            value = as.numeric(getProp("phase_shift_deg", 90)),
            min = 0, max = 360, step = 1),
          numericInput(paste0("prop_", selected, "_impedance"), "Z\u2080 (\u03a9)",
            value = as.numeric(getProp("impedance", 50)),
            min = 1, step = 0.5),
          numericInput(paste0("prop_", selected, "_loss"), "Insertion Loss (dB)",
            value = as.numeric(getProp("loss", 0.2)),
            min = 0, step = 0.05),
          hr(),
          h5("Display on Canvas"),
          checkboxGroupInput(paste0("prop_", selected, "_display"), label = NULL,
            choices = c(
              "Label" = "label",
              "Phase (\u00b0)" = "phase",
              "Loss (dB)" = "loss",
              "Z\u2080 (\u03a9)" = "impedance"
            ),
            selected = c("label", "phase"),
            inline = FALSE
          ),
          hr(),
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
    # ── Immediate confirmation the observer fired ────────────────────────
    n_comps <- length(lineup_components())
    showNotification(
      sprintf("\u25cf Calculate fired \u2014 %d component(s) in R", n_comps),
      type = "message", duration = 5, id = "calc_fire_notif"
    )
    message(sprintf("[lineup_calculate] Observer fired. Components in R: %d", n_comps))

    components <- lineup_components()

    if (is.null(components) || length(components) == 0) {
      showNotification("No components to calculate — draw a topology first.", type = "warning")
      return()
    }

    # ── Inputs defined OUTSIDE tryCatch so they remain accessible throughout ──
    input_power   <- if (!is.null(input$spec_p3db) && !is.null(input$spec_gain))
                       input$spec_p3db - input$spec_gain
                     else 0
    backoff_value <- if (!is.null(input$spec_par)) input$spec_par
                     else if (!is.null(input$backoff_db)) input$backoff_db
                     else 6

    # ── Local capture variables ─────────────────────────────────────────
    # DO NOT call reactiveVal setters inside the tryCatch error handler:
    # the reactive context can be lost there, causing a silent failure.
    calc_result <- NULL
    calc_error  <- NULL

    tryCatch({

      message(sprintf("[lineup_calculate] input_power=%.2f dBm, backoff=%.1f dB",
                  input_power, backoff_value))

      result <- lineup_calculate_engine(
        components, lineup_connections(), input_power, backoff_value
      )
      message(sprintf("[lineup_calculate] engine returned success=%s, stages=%d",
                  result$success, length(result$stage_results)))

      secondary_backoff <- get_secondary_backoff()
      if (!is.null(secondary_backoff) && abs(secondary_backoff - backoff_value) > 1e-9) {
        secondary_result <- lineup_calculate_engine(
          components, lineup_connections(), input_power, secondary_backoff
        )
        if (isTRUE(secondary_result$success)) {
          result <- merge_secondary_backoff_result(result, secondary_result, secondary_backoff)
        } else {
          showNotification(
            sprintf("Secondary BO2 calc failed at %.1f dB", secondary_backoff),
            type = "warning", duration = 3
          )
        }
      } else {
        result$bo_profile <- list(
          primary = backoff_value, secondary = NULL, has_secondary = FALSE
        )
      }

      calc_result <- result

    }, error = function(e) {
      # Store message only — do NOT touch reactiveVals inside the error handler
      calc_error <<- conditionMessage(e)
      message(sprintf("[lineup_calculate] ERROR caught: %s", calc_error))
    })

    # ── Set reactive values OUTSIDE the tryCatch ─────────────────────────
    if (!is.null(calc_error)) {
      showNotification(
        paste0("\u26a0 Calculate error: ", calc_error),
        type = "error", duration = 15
      )
      lineup_calc_results(list(
        success       = FALSE,
        message       = calc_error,
        stage_results = list()
      ))
      return()
    }

    if (is.null(calc_result)) {
      showNotification("\u26a0 Calculation returned no result.", type = "error")
      return()
    }

    # ── Store result — invalidates output$pa_lineup_table ────────────────
    message("[lineup_calculate] Storing result in lineup_calc_results")
    lineup_calc_results(calc_result)
    message("[lineup_calculate] Done — reactive set")

    # Trigger DataTables column-width recalculation in the Table View tab.
    session$sendCustomMessage("adjustLineupTable", list())
    # JS validation overlay (visual only — result already stored above)
    session$sendCustomMessage("validateAndCalculate", list(
      components  = components,
      connections = lineup_connections()
    ))

    # Store results per-canvas
    canvas_idx <- active_canvas_index()
    canvas_key <- paste0("canvas_", canvas_idx)
    canvas_data[[canvas_key]]$results <- calc_result

    # ── Push R-computed stage values back to JS canvas ────────────────────
    if (calc_result$success && length(calc_result$stage_results) > 0) {
      comps <- lineup_components()
      for (stage in calc_result$stage_results) {
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
            pin_p3db  = as.numeric(stage$pin_dbm),
            pout_p3db = as.numeric(stage$pout_dbm),
            pin_pavg  = as.numeric(if (!is.null(stage$pin_bo_dbm))  stage$pin_bo_dbm  else stage$pin_dbm  - backoff_value),
            pout_pavg = as.numeric(if (!is.null(stage$pout_bo_dbm)) stage$pout_bo_dbm else stage$pout_dbm - backoff_value),
            pin_pavg2 = as.numeric(stage$pin_bo2_dbm),
            pout_pavg2 = as.numeric(stage$pout_bo2_dbm),
            backoff_db_secondary = as.numeric(calc_result$backoff_db_secondary),
            z_in  = as.numeric(if (!is.null(matched[[1]]$properties$z_in))  matched[[1]]$properties$z_in  else 50),
            z_out = as.numeric(if (!is.null(matched[[1]]$properties$z_out)) matched[[1]]$properties$z_out else 50)
          )
          if (stage$type == "transistor") {
            props_update$pae_p3db     <- as.numeric(stage$pae_pct)
            props_update$pae_pavg     <- as.numeric(stage$pae_bo_pct)
            props_update$pae_pavg2    <- as.numeric(stage$pae_bo2_pct)
            props_update$de_p3db      <- as.numeric(stage$de_pct)
            props_update$de_pavg      <- as.numeric(stage$de_bo_pct)
            props_update$de_pavg2     <- as.numeric(stage$de_bo2_pct)
            props_update$gain_full_db <- as.numeric(stage$gain_full_db)
            props_update$gain_bo_db   <- as.numeric(stage$gain_bo_db)
            props_update$gain_bo2_db  <- as.numeric(stage$gain_bo2_db)
          }
          session$sendCustomMessage("updateComponent", list(id = cid, properties = props_update))
        }
      }
      guardrails_raw <- tryCatch(loadGuardrails(), error = function(e) NULL)
      if (!is.null(guardrails_raw) && !is.null(guardrails_raw$technologies)) {
        limits_map <- lapply(guardrails_raw$technologies, function(t) list(
          pout_max    = as.numeric(t$pout_dbm$max_practical),
          pae_min     = as.numeric(t$pae_pct$min_acceptable),
          pae_typical = as.numeric(t$pae_pct$typical_p3db),
          pae_max     = as.numeric(t$pae_pct$max_practical_p3db),
          freq_max    = as.numeric(t$freq_range_ghz$max),
          vdd_max     = as.numeric(t$vdd$max_abs),
          ft_typical  = as.numeric(t$gain_db$ft_ghz_typical)
        ))
        session$sendCustomMessage("setGuardrailLimits", limits_map)
      }
      session$sendCustomMessage("redrawCanvasDisplay", list())
    }

    showNotification(
      if (calc_result$success) "\u2713 Calculation complete" else "\u26a0 Calculation failed",
      type = if (calc_result$success) "message" else "error"
    )
  })

  # ═══ DEBUG OBSERVER: Trace lineup_calc_results() population ═══
  # Calculate ALL canvases button observer
  observeEvent(input$lineup_calculate_all, {
    layout <- input$canvas_layout
    if(is.null(layout)) layout <- "1x1"
    
    canvas_count <- getCanvasCount(layout)
    
    if(canvas_count == 1) {
      showNotification("Multi-canvas mode required for comparison", type = "warning")
      return()
    }
    
    # First, request fresh data from all canvases in JavaScript
    session$sendCustomMessage("requestAllCanvasData", list())
    
    # Give JavaScript time to send the data
    Sys.sleep(0.5)
    
    # Use spec-based input power — same calculation as single-canvas Calculate
    backoff_value <- if (!is.null(input$spec_par))       input$spec_par
                     else if (!is.null(input$backoff_db)) input$backoff_db
                     else 6
    if (!is.null(input$spec_p3db) && !is.null(input$spec_gain)) {
      input_power <- input$spec_p3db - input$spec_gain
    } else {
      input_power <- 0
    }
    
    calculated_count <- 0
    failed_count <- 0
    empty_count <- 0
    
    for(i in 0:(canvas_count-1)) {
      canvas_key <- paste0("canvas_", i)
      components <- canvas_data[[canvas_key]]$components
      connections <- canvas_data[[canvas_key]]$connections
      
      if(!is.null(components) && length(components) > 0) {
        result <- lineup_calculate_engine(components, connections, input_power, backoff_value)
        canvas_data[[canvas_key]]$results <- result
        
        if(result$success) {
          calculated_count <- calculated_count + 1
        } else {
          failed_count <- failed_count + 1
        }
      } else {
        empty_count <- empty_count + 1
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

      n_updated <- n_updated + 1
    }

    unique_techs <- paste(unique(tech_keys_used), collapse = ", ")
    showNotification(
      sprintf("Optimized %d stage(s) using guardrails. Technology: %s. Old design saved for comparison.", n_updated, unique_techs),
      type = "message", duration = 6
    )
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
        # Validate: gain relationship — linear ≥ BO gain ≥ P3dB gain
        glin  <- suppressWarnings(as.numeric(properties$gain))
        gp3db <- suppressWarnings(as.numeric(properties$gain_p3db))
        gbo   <- suppressWarnings(as.numeric(properties$gain_bo))
        if (!is.na(glin) && !is.na(gp3db) && !is.na(gbo)) {
          if (!(glin >= gbo && gbo >= gp3db)) {
            showNotification(
              "⚠ Gain order incorrect. Expected: Linear \u2265 Gain@BO \u2265 Gain@P3dB (device compresses at higher power).",
              type = "warning", duration = 6
            )
          }
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
      } else if (comp_type == "offset_line") {
        properties$label          <- input[[paste0("prop_", selected, "_label")]]
        properties$offset_role    <- input[[paste0("prop_", selected, "_offset_role")]]
        properties$phase_shift_deg <- input[[paste0("prop_", selected, "_phase_shift_deg")]]
        properties$impedance      <- input[[paste0("prop_", selected, "_impedance")]]
        properties$loss           <- input[[paste0("prop_", selected, "_loss")]]
        properties$display        <- input[[paste0("prop_", selected, "_display")]]
      }

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
      if(!is.null(results$final_pout_bo2_dbm)) {
        tags$tagList(
          tags$h4(sprintf("Backoff Performance 2 (%.1f dB)", results$backoff_db_secondary), style = "color: #FFB74D; margin-bottom: 10px;"),
          tags$div(class = "calc-summary", style = "background-color: #fff4e5; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "Output Power"),
              tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_bo2_dbm)),
              tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_bo2_w))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "System PAE"),
              tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae_bo2))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "DC Power"),
              tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc_bo2))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "Heat Dissipation"),
              tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss_bo2))
            )
          )
        )
      },
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
      if(!is.null(results$final_pout_bo2_dbm)) {
        tags$tagList(
          tags$h4(sprintf("Backoff Performance 2 (%.1f dB)", results$backoff_db_secondary), style = "color: #FFB74D; margin-bottom: 10px;"),
          tags$div(class = "calc-summary", style = "background-color: #fff4e5; padding: 10px; border-radius: 5px; margin-bottom: 15px;",
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "Output Power"),
              tags$span(class = "metric-value", sprintf("%.2f dBm", results$final_pout_bo2_dbm)),
              tags$span(class = "metric-unit", sprintf("(%.3f W)", results$final_pout_bo2_w))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "System PAE"),
              tags$span(class = "metric-value success", sprintf("%.1f%%", results$system_pae_bo2))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "DC Power"),
              tags$span(class = "metric-value", sprintf("%.3f W", results$total_pdc_bo2))
            ),
            tags$div(class = "calc-metric",
              tags$span(class = "metric-label", "Heat Dissipation"),
              tags$span(class = "metric-value warning", sprintf("%.3f W", results$total_pdiss_bo2))
            )
          )
        )
      },
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

    # Show a structured placeholder before first Calculate instead of a bare blank.
    # Context-aware: check whether there are components on the canvas to give a
    # precise message.  We also use destroy = TRUE so DataTables can reinitialise
    # from this 1-column placeholder to the full 16-column table without page reload.
    if (is.null(results) || !isTRUE(results$success)) {
      has_comps <- !is.null(lineup_components()) && length(lineup_components()) > 0
      if (is.null(results)) {
        msg <- if (has_comps)
          "\u25ba Click \u2018Calculate Lineup\u2019 to generate results."
        else
          "Draw a topology on the canvas, then click \u25ba Calculate Lineup."
      } else {
        msg <- paste("\u26a0 Calculation error:", results$message %||% "unknown error",
                     "\u2014 check the canvas for disconnected components.")
      }
      return(datatable(
        data.frame(Status = msg, check.names = FALSE),
        options = list(dom = 't', pageLength = 1, destroy = TRUE),
        rownames = FALSE
      ))
    }

    tryCatch({
    if(!results$success || length(results$stage_results) == 0) {
      msg <- if (!isTRUE(results$success))
               paste("Calculation failed:", results$message %||% "unknown error")
             else "No calculation stages to display. Add components and recalculate."
      return(datatable(
        data.frame(Message = msg),
        options = list(dom = 't', pageLength = 5, destroy = TRUE),
        rownames = FALSE
      ))
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
        destroy = TRUE,      # allows DT to reinitialise when column count changes
        autoWidth = FALSE,   # prevent zero-width cols when init'd in hidden tab
        scrollX = TRUE,      # allow horizontal scroll; forces width recalc on show
        initComplete = JS("function(s){ this.api().columns.adjust(); }"),
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
      formatStyle(3, backgroundColor = 'rgba(156,39,176,0.18)') %>%   # purple tint - Loss
      formatStyle(4:8, backgroundColor = 'rgba(33,150,243,0.15)') %>% # blue tint - full power
      formatStyle(9:13, backgroundColor = 'rgba(255,152,0,0.15)') %>% # orange tint - backoff
      formatStyle(14:15, backgroundColor = 'rgba(76,175,80,0.15)')    # green tint - gain
    }, error = function(e) {
      cat(sprintf("[TABLE ERROR] renderDT failed: %s\n", e$message))
      cat(sprintf("[TABLE ERROR] Call: %s\n", deparse(e$call %||% NULL)))
      datatable(
        data.frame(Error = paste("Table render error — check R console:", e$message)),
        options = list(dom = 't', destroy = TRUE), rownames = FALSE
      )
    })
  }, server = FALSE)

  # Ensure table is rendered even when hidden inside a tab
  outputOptions(output, "pa_lineup_table", suspendWhenHidden = FALSE)
  
  # Dynamic Tables UI - renders tabs for multi-canvas layouts
  output$pa_lineup_tables_dynamic <- renderUI({
    layout <- input$canvas_layout
    
    if(is.null(layout) || layout == "1x1") {
      return(NULL)  # DTOutput lives in the static UI inside a conditionalPanel
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

    # SSOT note: all values here come from the same lineup_calc_results() reactive
    # that feeds the Table View. Canvas overlay values are set by the same R engine
    # via updateComponent messages. All three views (Canvas / Table / Equations) are
    # guaranteed to match after each Calculate run.
    ssot_banner <- if (!is.null(results) && isTRUE(results$success)) {
      div(style = "margin-bottom:8px; padding:4px 10px; background:rgba(76,175,80,.12);
                   border-left:3px solid #4caf50; border-radius:3px; font-size:11px;",
        icon("check-circle", style = "color:#4caf50;"),
        " Values below match the Table View exactly — single source of truth: ",
        tags$code("lineup_calc_results()")
      )
    } else {
      div(style = "margin-bottom:8px; padding:4px 10px; background:rgba(255,193,7,.12);
                   border-left:3px solid #ffc107; border-radius:3px; font-size:11px;",
        icon("info-circle", style = "color:#ffc107;"),
        " No results yet. Click \u25ba Calculate Lineup to populate equations."
      )
    }


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
        ),

        # ── Tab 4: Phase Analysis ──────────────────────────────────────────
        tabPanel(title = tagList(icon("wave-square"), " Phase"),
          br(),
          wellPanel(
            h5(icon("calculator"), " Phase Shift Formulas", style="color:#455a64;"),
            HTML("
              <p><b>\u03bb/4 Transmission Line:</b> introduces exactly 90\u00b0 electrical phase shift at the design frequency.</p>
              <p><b>Impedance Inverter:</b> Z<sub>0</sub> = &radic;(Z<sub>in</sub> &times; Z<sub>out</sub>), phase = 90\u00b0</p>
              <p><b>Doherty combiner path:</b> Main path sees 90\u00b0 inverter; Aux path sees 90\u00b0 offset line &rarr; signals arrive in-phase at combiner.</p>
              <p style='color:#888; font-size:11px;'>Other component types (transistors, matching networks, splitters, combiners) are assigned 0\u00b0 in this simplified model.</p>
            ")
          ),
          if (!is.null(res) && res$success && !is.null(res$phase_results) && length(res$phase_results) > 0) {
            has_phase <- any(sapply(res$phase_results, function(p) p$phase_contrib != 0))
            phase_rows <- lapply(res$phase_results, function(p) {
              is_active <- !is.null(p$phase_contrib) && p$phase_contrib != 0
              tags$tr(
                style = if (is_active) "background-color:#e8f5e9; font-weight:bold;" else "",
                tags$td(p$stage %||% "", style="padding:3px 6px;"),
                tags$td(tools::toTitleCase(gsub("_"," ", p$type %||% "")), style="padding:3px 6px;"),
                tags$td(
                  if (is_active)
                    tags$span(sprintf("+%.0f\u00b0", p$phase_contrib), style="color:#2e7d32;")
                  else tags$span("0\u00b0", style="color:#aaa;"),
                  style="text-align:right;padding:3px 6px;"
                ),
                tags$td(sprintf("%.0f\u00b0", p$cumulative_phase %||% 0),
                        style="text-align:right; font-weight:bold; padding:3px 6px;"),
                tags$td(p$notes %||% "", style="padding:3px 6px; font-size:11px; color:#555;")
              )
            })
            total_contrib <- sum(sapply(res$phase_results, function(p) p$phase_contrib %||% 0))
            last_cum      <- if (length(res$phase_results) > 0)
                                res$phase_results[[length(res$phase_results)]]$cumulative_phase %||% 0
                              else 0
            tagList(
              if (!has_phase) div(class="alert alert-info",
                "\u2139 No \u03bb/4 offset lines in this lineup \u2014 all phase contributions are 0\u00b0."),
              tags$table(style="width:100%; border-collapse:collapse; font-size:12px;",
                tags$thead(tags$tr(
                  lapply(c("Stage","Type","Phase Contrib.","Cumulative Phase","Notes"),
                         function(h) tags$th(h, style="text-align:left; border-bottom:1px solid #ccc; padding:3px 6px;"))
                )),
                tags$tbody(phase_rows),
                tags$tfoot(tags$tr(style="background:#eceff1; font-weight:bold;",
                  tags$td("TOTAL", style="padding:3px 6px;"),
                  tags$td("\u2014", style="padding:3px 6px;"),
                  tags$td(sprintf("%.0f\u00b0", total_contrib), style="text-align:right;padding:3px 6px;"),
                  tags$td(sprintf("%.0f\u00b0", last_cum),      style="text-align:right;padding:3px 6px;"),
                  tags$td("\u03a3 phase from \u03bb/4 lines", style="padding:3px 6px; font-size:11px;")
                ))
              )
            )
          } else tags$em("Run Calculate to see per-stage phase data.", style="color:#888;")
        )
      )
    }

    if (is.null(layout) || layout == "1x1") {
      return(tagList(
        ssot_banner,
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
              formatStyle(3:6, backgroundColor = 'rgba(33,150,243,0.15)') %>%
              formatStyle(7:10, backgroundColor = 'rgba(255,152,0,0.15)')
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


  # ── Respond to PAR change from syncLineupSpecs JS handler ──────────────────
  # JS fires par_changed_trigger when user edits PAR in spec panel,
  # so the R cascade recalculates without requiring a manual button click.
  observeEvent(input$par_changed_trigger, {
    # Only re-run if we have components already calculated
    comps <- lineup_components()
    if (is.null(comps) || length(comps) == 0) return()

    cat("[PAR Trigger] Requesting lineup recalculation from PAR change\n")
    session$sendCustomMessage("triggerLineupCalculate", list(reason = "par_changed"))
  }, ignoreInit = TRUE, ignoreNULL = TRUE)

}
