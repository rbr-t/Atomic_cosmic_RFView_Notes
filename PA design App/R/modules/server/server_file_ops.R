# ============================================================
# server_file_ops.R
# ============================================================

serverFileOps <- function(input, output, session, state) {
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
  # FILE OPERATIONS: Save, Load, Export, Report
  # ============================================================
  
  # Save Configuration
  observeEvent(input$lineup_save_config, {
    components <- lineup_components()
    connections <- lineup_connections()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to save", type = "warning")
      return()
    }
    
    config <- list(
      components = components,
      connections = connections,
      metadata = list(
        timestamp = Sys.time(),
        version = "1.0",
        app = "PA Lineup Designer"
      )
    )
    
    # Create filename with timestamp
    filename <- sprintf("pa_lineup_%s.json", format(Sys.time(), "%Y%m%d_%H%M%S"))
    filepath <- file.path(tempdir(), filename)
    
    tryCatch({
      jsonlite::write_json(config, filepath, auto_unbox = TRUE, pretty = TRUE)
      showNotification(
        sprintf("Configuration saved to: %s", filename),
        type = "message",
        duration = 5
      )
      cat(sprintf("[Save] Configuration saved to: %s\n", filepath))
    }, error = function(e) {
      showNotification(
        sprintf("Save failed: %s", e$message),
        type = "error"
      )
    })
  })
  
  # Load Configuration
  observeEvent(input$lineup_load_config, {
    showModal(modalDialog(
      title = "Load Configuration",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("lineup_load_confirm", "Load", class = "btn-success")
      ),
      fileInput("lineup_config_file", "Select Configuration File (.json)",
                accept = c(".json", "application/json")),
      helpText(icon("info-circle"), " Saved configurations are in your Downloads folder or the directory where you saved them.",
               style = "color: #888; font-size: 12px; margin-top: -10px;")
    ))
  })
  
  observeEvent(input$lineup_load_confirm, {
    req(input$lineup_config_file)
    
    file_info <- input$lineup_config_file
    
    tryCatch({
      config <- jsonlite::read_json(file_info$datapath, simplifyVector = TRUE)
      
      # Validate config structure
      if(!is.list(config) || is.null(config$components)) {
        stop("Invalid configuration file format")
      }
      
      # Send to JavaScript
      session$sendCustomMessage("loadConfiguration", config)
      
      showNotification("Configuration loaded successfully", type = "message")
      removeModal()
      
      cat(sprintf("[Load] Configuration loaded from: %s\n", file_info$name))
      cat(sprintf("[Load] Components: %d, Connections: %d\n", 
                  length(config$components), 
                  length(config$connections)))
      
    }, error = function(e) {
      showNotification(
        sprintf("Load failed: %s", e$message),
        type = "error"
      )
    })
  })
  
  # Export Diagram (SVG)
  observeEvent(input$lineup_export_diagram, {
    components <- lineup_components()
  
  # Save as User Template
  observeEvent(input$save_template_data, {
    req(input$save_template_data)
    
    template_data <- input$save_template_data
    template_name <- template_data$name
    
    if(is.null(template_name) || template_name == "") {
      showNotification("Template name is required", type = "error")
      return()
    }
    
    # Create user_templates directory if it doesn't exist
    templates_dir <- file.path("R", "user_templates")
    if(!dir.exists(templates_dir)) {
      dir.create(templates_dir, recursive = TRUE)
      cat(sprintf("[Template] Created directory: %s\n", templates_dir))
    }
    
    # Sanitize filename (remove special characters)
    safe_name <- gsub("[^a-zA-Z0-9_-]", "_", template_name)
    filename <- sprintf("%s.json", safe_name)
    filepath <- file.path(templates_dir, filename)
    
    # Add metadata
    template_data$metadata <- list(
      created = as.character(Sys.time()),
      version = "1.0",
      type = "user_template"
    )
    
    tryCatch({
      jsonlite::write_json(template_data, filepath, auto_unbox = TRUE, pretty = TRUE)
      showNotification(
        sprintf("Template '%s' saved successfully!", template_name),
        type = "message",
        duration = 3
      )
      cat(sprintf("[Template] Saved: %s (%d components, %d wires)\n", 
                  template_name, 
                  length(template_data$components), 
                  length(template_data$wires)))
      
      # Reload and send updated user templates list
      updated_templates <- getUserTemplates()
      if(length(updated_templates) > 0) {
        template_info <- lapply(updated_templates, function(t) {
          list(id = t$id, name = t$name, components_count = t$components_count)
        })
        session$sendCustomMessage("updateUserTemplates", template_info)
      }
      
    }, error = function(e) {
      showNotification(
        sprintf("Failed to save template: %s", e$message),
        type = "error"
      )
      cat(sprintf("[Template Error] %s\n", e$message))
    })
  })
  
  # Load User Template
  observeEvent(input$load_user_template, {
    req(input$load_user_template)
    
    template_id <- input$load_user_template
    
    # Remove "user_" prefix to get filename
    filename <- sub("^user_", "", template_id)
    filepath <- file.path("R", "user_templates", paste0(filename, ".json"))
    
    if(!file.exists(filepath)) {
      showNotification(
        "Template file not found",
        type = "error"
      )
      cat(sprintf("[Template Error] File not found: %s\n", filepath))
      return()
    }
    
    tryCatch({
      template_data <- jsonlite::read_json(filepath, simplifyVector = TRUE)
      
      # Send to JavaScript to load
      session$sendCustomMessage("loadUserTemplateData", template_data)
      
      cat(sprintf("[Template] Loaded: %s (%d components, %d wires)\n",
                  template_data$name,
                  length(template_data$components),
                  length(template_data$wires)))
      
    }, error = function(e) {
      showNotification(
        sprintf("Failed to load template: %s", e$message),
        type = "error"
      )
      cat(sprintf("[Template Error] %s\n", e$message))
    })
  })
  
  # Render user templates manager UI
  output$user_templates_manager <- renderUI({
    templates <- getUserTemplates()
    
    if(length(templates) == 0) {
      return(tags$p(
        style = "text-align: center; color: #999; font-size: 11px; padding: 10px;",
        "No saved templates"
      ))
    }
    
    lapply(templates, function(tmpl) {
      template_id <- tmpl$id
      template_name <- tmpl$name
      filename <- sub("^user_", "", template_id)
      
      tags$div(
        style = "margin-bottom: 8px; padding: 8px; background: rgba(255,255,255,0.05); border-radius: 4px;",
        tags$div(
          style = "display: flex; justify-content: space-between; align-items: center;",
          tags$div(
            style = "flex: 1;",
            tags$strong(style = "color: #fff; font-size: 11px;", template_name),
            tags$br(),
            tags$small(style = "color: #999;", sprintf("%d components", tmpl$components_count))
          ),
          tags$div(
            style = "display: flex; gap: 4px;",
            actionButton(
              paste0("edit_template_", filename),
              icon("edit"),
              class = "btn btn-warning btn-xs",
              style = "padding: 2px 6px;",
              title = "Edit template name",
              onclick = sprintf("console.log('Edit clicked: %s'); if(typeof editTemplate === 'function') { editTemplate('%s', '%s'); } else { alert('editTemplate function not found!'); }", filename, filename, template_name)
            ),
            actionButton(
              paste0("delete_template_", filename),
              icon("trash"),
              class = "btn btn-danger btn-xs",
              style = "padding: 2px 6px;",
              title = "Delete template"
            )
          )
        )
      )
    })
  })
  
  # Render user templates in top sidebar (Architecture Templates section)
  output$user_templates_top_display <- renderUI({
    templates <- getUserTemplates()
    
    if(length(templates) == 0) {
      return(tags$div(
        style = "text-align: center; color: #777; font-size: 11px; padding: 10px; font-style: italic;",
        "No saved templates yet"
      ))
    }
    
    lapply(templates, function(tmpl) {
      template_filename <- sub("^user_", "", tmpl$id)
      
      tags$div(
        class = "preset-template user-template",
        `data-preset` = paste0("user_", template_filename),
        `data-user-template` = "true",
        onclick = sprintf("loadUserTemplate('%s');", template_filename),
        tags$h5(style = "margin: 0; color: #FF7F11;", icon("star"), " ", tmpl$name),
        tags$p(style = "margin: 2px 0 0 0; font-size: 10px;", sprintf("%d components", tmpl$components_count))
      )
    })
  })
  
  # Observe changes that require updating both template displays
  observe({
    # Trigger re-render of both template UIs when files change
    list.files(file.path("R", "user_templates"), pattern = "\\.json$")
  }) %>% debounce(500)  # Debounce to avoid too frequent updates
  
  # Template delete/edit observers remain the same
  observe({
    templates <- getUserTemplates()
    
    lapply(templates, function(tmpl) {
      filename <- sub("^user_", "", tmpl$id)
      btn_id <- paste0("delete_template_", filename)
      
      observeEvent(input[[btn_id]], {
        filepath <- file.path("R", "user_templates", paste0(filename, ".json"))
        
        if(file.exists(filepath)) {
          tryCatch({
            file.remove(filepath)
            showNotification(
              sprintf("Template '%s' deleted", tmpl$name),
              type = "message",
              duration = 3
            )
            cat(sprintf("[Template] Deleted: %s\n", tmpl$name))
            
            # Reload templates
            updated_templates <- getUserTemplates()
            if(length(updated_templates) > 0) {
              template_info <- lapply(updated_templates, function(t) {
                list(id = t$id, name = t$name, components_count = t$components_count)
              })
              session$sendCustomMessage("updateUserTemplates", template_info)
            } else {
              session$sendCustomMessage("updateUserTemplates", list())
            }
            
          }, error = function(e) {
            showNotification(
              sprintf("Failed to delete template: %s", e$message),
              type = "error"
            )
          })
        }
      }, ignoreNULL = TRUE, ignoreInit = TRUE)
    })
  })
  
  # Edit template (rename) observer
  observeEvent(input$edit_template_submit, {
    req(input$edit_template_filename, input$edit_template_newname)
    
    filename <- input$edit_template_filename
    new_name <- trimws(input$edit_template_newname)
    
    if(new_name == "") {
      showNotification("Template name cannot be empty", type = "error")
      return()
    }
    
    filepath <- file.path("R", "user_templates", paste0(filename, ".json"))
    
    if(!file.exists(filepath)) {
      showNotification("Template file not found", type = "error")
      return()
    }
    
    tryCatch({
      # Read existing template
      template_data <- jsonlite::read_json(filepath, simplifyVector = FALSE)
      
      # Update name
      old_name <- template_data$name
      template_data$name <- new_name
      
      # If user wants to rename file too, create new file and delete old
      safe_new_name <- gsub("[^a-zA-Z0-9_-]", "_", new_name)
      new_filepath <- file.path("R", "user_templates", paste0(safe_new_name, ".json"))
      
      # Write to new file
      jsonlite::write_json(template_data, new_filepath, auto_unbox = TRUE, pretty = TRUE)
      
      # Delete old file if different
      if(filepath != new_filepath && file.exists(filepath)) {
        file.remove(filepath)
      }
      
      showNotification(
        sprintf("Template renamed from '%s' to '%s'", old_name, new_name),
        type = "message",
        duration = 3
      )
      cat(sprintf("[Template] Renamed: %s -> %s\n", old_name, new_name))
      
      # Reload templates
      updated_templates <- getUserTemplates()
      if(length(updated_templates) > 0) {
        template_info <- lapply(updated_templates, function(t) {
          list(id = t$id, name = t$name, components_count = t$components_count)
        })
        session$sendCustomMessage("updateUserTemplates", template_info)
      }
      
    }, error = function(e) {
      showNotification(
        sprintf("Failed to edit template: %s", e$message),
        type = "error"
      )
      cat(sprintf("[Template Error] %s\n", e$message))
    })
  })
  
  # Load user template observer (from top sidebar Architecture Templates)
  observeEvent(input$load_user_template_filename, {
    req(input$load_user_template_filename)
    
    filename <- input$load_user_template_filename
    filepath <- file.path("R", "user_templates", paste0(filename, ".json"))
    
    if(!file.exists(filepath)) {
      showNotification("Template file not found", type = "error")
      return()
    }
    
    tryCatch({
      template_data <- jsonlite::read_json(filepath, simplifyVector = TRUE)
      
      # Send template data to JavaScript  
      session$sendCustomMessage("loadTemplateData", template_data)
      
      showNotification(
        sprintf("Loaded template: %s", template_data$name),
        type = "message",
        duration = 3
      )
      
      cat(sprintf("[Template] Loaded: %s\n", template_data$name))
      
    }, error = function(e) {
      showNotification(
        sprintf("Failed to load template: %s", e$message),
        type = "error"
      )
      cat(sprintf("[Template Error] Failed to load %s: %s\n", filename, e$message))
    })
  })
  
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to export", type = "warning")
      return()
    }
    
    showNotification(
      "Export feature: Right-click on canvas → 'Save Image As...' to export SVG",
      type = "message",
      duration = 8
    )
    
    # Future enhancement: Trigger JavaScript to export SVG
    # session$sendCustomMessage("exportSVG", list())
  })
  
  # Generate Report (PDF)
  observeEvent(input$lineup_generate_report, {
    components <- lineup_components()
    results <- lineup_calc_results()
    
    if(is.null(components) || length(components) == 0) {
      showNotification("No lineup to report", type = "warning")
      return()
    }
    
    if(is.null(results) || !results$success) {
      showNotification("Please calculate lineup before generating report", type = "warning")
      return()
    }
    
    showModal(modalDialog(
      title = "Generate Report",
      footer = tagList(
        modalButton("Cancel"),
        actionButton("lineup_report_confirm", "Generate", class = "btn-success")
      ),
      textInput("lineup_report_title", "Report Title", value = "PA Lineup Design Report"),
      textInput("lineup_report_author", "Author", value = ""),
      textAreaInput("lineup_report_notes", "Additional Notes", rows = 3)
    ))
  })
  
  observeEvent(input$lineup_report_confirm, {
    tryCatch({
      # Generate simple text report (PDF generation would require rmarkdown/reportlab)
      report_lines <- c(
        "================================",
        input$lineup_report_title,
        "================================",
        "",
        sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
        if(nchar(input$lineup_report_author) > 0) sprintf("Author: %s", input$lineup_report_author) else NULL,
        "",
        "LINEUP CONFIGURATION",
        "--------------------",
        sprintf("Components: %d", length(lineup_components())),
        sprintf("Total Gain: %.2f dB", lineup_calc_results()$total_gain),
        sprintf("Output Power: %.2f dBm (%.3f W)", 
                lineup_calc_results()$final_pout_dbm,
                lineup_calc_results()$final_pout_w),
        sprintf("System PAE: %.1f%%", lineup_calc_results()$system_pae),
        sprintf("DC Power: %.3f W", lineup_calc_results()$total_pdc),
        "",
        "CALCULATION RATIONALE",
        "--------------------",
        lineup_calc_results()$rationale,
        "",
        if(nchar(input$lineup_report_notes) > 0) c("ADDITIONAL NOTES", "----------------", input$lineup_report_notes) else NULL
      )
      
      # Save to temp file
      filename <- sprintf("pa_lineup_report_%s.txt", format(Sys.time(), "%Y%m%d_%H%M%S"))
      filepath <- file.path(tempdir(), filename)
      writeLines(report_lines, filepath)
      
      showNotification(
        sprintf("Report saved to: %s", filename),
        type = "message",
        duration = 5
      )
      removeModal()
      
      cat(sprintf("[Report] Generated: %s\n", filepath))
      
    }, error = function(e) {
      showNotification(
        sprintf("Report generation failed: %s", e$message),
        type = "error"
      )
    })
  })
  

}
