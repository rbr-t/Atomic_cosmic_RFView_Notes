# IFX Integration Module for Web-page-knitter
# Provides pre-configured templates for IFX-style hierarchical reports

ifx_integration_ui <- function(id) {
  ns <- NS(id)
  
  wellPanel(
    style = "background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border-radius: 10px;",
    h3(icon("briefcase"), "IFX Activity Dashboard Integration", style = "margin-top: 0;"),
    p("Quick setup for IFX-style hierarchical reports with pre-configured templates"),
    
    fluidRow(
      column(6,
        selectInput(ns("ifx_template"), "Report Type:",
                    choices = list(
                      "🏢 IFX Templates" = c(
                        "Administration Documents" = "01_Administration",
                        "Projects" = "02_Projects",
                        "Personal Review Dialogue (PRD)" = "03_PRD",
                        "Conferences" = "04_Conferences",
                        "Study Materials" = "05_Study_Material",
                        "Business Trips" = "06_Business_Trips",
                        "Technical Reports" = "07_Technical_reports",
                        "Competition Analysis" = "08_Competition",
                        "My Presentations" = "09_My_presentations",
                        "Internal Trainings" = "10_IFX_internal_trainings"
                      ),
                      "📚 Generic Templates" = c(
                        "Meeting Notes" = "generic_meetings",
                        "Personal Projects" = "generic_projects",
                        "Research Papers" = "generic_research",
                        "Course Materials" = "generic_courses",
                        "Documentation" = "generic_docs",
                        "Portfolio" = "generic_portfolio",
                        "Lab Notebooks" = "generic_lab",
                        "Book Notes" = "generic_books",
                        "Code Repository" = "generic_code",
                        "Client Work" = "generic_clients"
                      )
                    ),
                    selected = "01_Administration",
                    width = "100%")
      ),
      column(6,
        textInput(ns("ifx_base_path"), "IFX Base Folder:",
                  value = "IFX_2022_2025",
                  placeholder = "e.g., IFX_2022_2025",
                  width = "100%")
      )
    ),
    
    fluidRow(
      column(6,
        textInput(ns("ifx_author"), "Author:",
                  value = "BT",
                  placeholder = "Your initials or name",
                  width = "100%")
      ),
      column(6,
        selectInput(ns("ifx_format"), "Output Format:",
                    choices = c(
                      "HTML Document" = "html_document",
                      "HTML with TOC Float" = "html_document_toc"
                    ),
                    selected = "html_document",
                    width = "100%")
      )
    ),
    
    fluidRow(
      column(12,
        actionButton(ns("apply_ifx_template"), 
                     "Apply IFX Template to New Section", 
                     icon = icon("check-circle"),
                     class = "btn-success btn-block",
                     style = "margin-top: 10px; font-weight: bold;")
      )
    ),
    
    hr(style = "border-color: rgba(255,255,255,0.3);"),
    
    fluidRow(
      column(12,
        h4(icon("info-circle"), "IFX Folder Structure", style = "margin-top: 0;"),
        tags$pre(
          style = "background: rgba(0,0,0,0.2); padding: 10px; border-radius: 5px; color: white; font-size: 11px;",
          "IFX_2022_2025/
├── 01_Administration/      # Contracts, HR, salary
├── 02_Projects/            # Project documentation
├── 03_PRD/                 # Performance reviews
├── 04_Conferences/         # Conference materials
├── 05_Study_Material/      # Learning resources
├── 06_Business_Trips/      # Travel docs
├── 07_Technical_reports/   # Technical papers
├── 08_Competition/         # Competitive analysis
├── 09_My_presentations/    # Your presentations
├── 10_IFX_internal_trainings/ # Training materials
└── 00_Master_html_file/    # Output destination"
        )
      )
    ),
    
    div(
      style = "background: rgba(255,255,255,0.1); padding: 10px; border-radius: 5px; margin-top: 10px;",
      p(icon("lightbulb"), strong("Tips:"), style = "margin: 0 0 5px 0;"),
      tags$ul(
        style = "margin: 0; padding-left: 20px;",
        tags$li("Template auto-fills: title, source path, destination path"),
        tags$li("You can modify any field after applying the template"),
        tags$li("Works with relative paths for portability"),
        tags$li("Compatible with the IFX_2022_2025 folder structure")
      )
    )
  )
}

ifx_integration_server <- function(id, parent_rv, parent_session, parent_ns) {
  moduleServer(id, function(input, output, session) {
    
    observeEvent(input$apply_ifx_template, {
      template_folder <- input$ifx_template
      base_path <- input$ifx_base_path
      author <- input$ifx_author
      format_choice <- input$ifx_format
      
      # Validate base path exists
      if (!nzchar(base_path)) {
        showNotification("Please specify the base folder path", type = "error")
        return()
      }
      
      # Check if this is a generic template
      is_generic <- grepl("^generic_", template_folder)
      
      if (is_generic) {
        # Generic template handling
        template_type <- gsub("^generic_", "", template_folder)
        display_name <- switch(template_type,
          "meetings" = "Meeting Notes",
          "projects" = "Personal Projects",
          "research" = "Research Papers",
          "courses" = "Course Materials",
          "docs" = "Documentation",
          "portfolio" = "Portfolio",
          "lab" = "Lab Notebooks",
          "books" = "Book Notes",
          "code" = "Code Repository",
          "clients" = "Client Work",
          tools::toTitleCase(gsub("_", " ", template_type))
        )
        
        # Suggest generic paths
        source_path <- file.path(base_path, display_name)
        destination_path <- file.path(base_path, "Reports")
        title <- paste(display_name, format(Sys.Date(), "%Y"))
        
      } else {
        # IFX template handling (original logic)
        display_name <- gsub("^[0-9]+_", "", template_folder)
        display_name <- gsub("_", " ", display_name)
        source_path <- file.path(base_path, template_folder)
        destination_path <- file.path(base_path, "00_Master_html_file")
        title <- paste("IFX", display_name, "2022-2026")
      }
      
      # Add a new section to parent
      new_section_id <- parent_rv$section_count + 1
      parent_rv$section_count <- new_section_id
      
      # Prepare section configuration
      section_config <- list(
        source_path = source_path,
        destination_path = destination_path,
        title = title,
        author = author,
        logo = find_project_file("logo.png"),
        logo_width = 75,
        logo_height = 35,
        format = if (format_choice == "html_document_toc") {
          "rmarkdown::html_document(toc = TRUE, toc_float = TRUE)"
        } else {
          "rmarkdown::html_document"
        },
        checkbox = TRUE
      )
      
      # Store in parent reactive values
      parent_rv$sections[[as.character(new_section_id)]] <- section_config
      
      # Update UI in parent - we need to trigger UI refresh
      # This will be handled by observing rv$sections in the parent server
      
      showNotification(
        paste0("✓ Template Applied: ", title, 
               "\nSource: ", source_path,
               "\nCheck the new section below and click 'Render Report' when ready."),
        type = "message",
        duration = 8
      )
      
      # Try to make the dynamic sections visible
      tryCatch({
        shinyjs::removeClass(selector = paste0('#', parent_ns('dynamic_sections')), 
                           class = 'dynamic-sections-hidden')
      }, error = function(e) {
        message("Could not toggle dynamic sections visibility: ", e$message)
      })
    })
  })
}

# Example configurations helper
get_ifx_example_configs <- function() {
  list(
    list(
      name = "IFX Administration Report",
      source = "IFX_2022_2025/01_Administration/",
      destination = "IFX_2022_2025/00_Master_html_file/",
      title = "IFX Administration Documents 2022-2026",
      author = "BT",
      description = "Contracts, HR documents, salary info, internal course certificates"
    ),
    list(
      name = "IFX Master Dashboard",
      source = "IFX_2022_2025/00_Master_html_file/",
      destination = "IFX_2022_2025/00_Master_html_file/",
      title = "My IFX Activity Dashboard",
      author = "BT",
      description = "Master report linking all individual IFX reports"
    ),
    list(
      name = "Project Documentation",
      source = "IFX_2022_2025/02_Projects/01_Tx_Baseline/",
      destination = "IFX_2022_2025/00_Master_html_file/",
      title = "IFX Project - Tx Baseline 2022",
      author = "BT",
      description = "Project files and documentation for Tx Baseline project"
    )
  )
}
