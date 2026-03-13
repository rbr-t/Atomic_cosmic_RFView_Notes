# =============================================================================
# server.R  –  Standalone RF CAD Tool
# =============================================================================
library(shiny)
library(jsonlite)

# Null-coalescing helper (consistent with PA Design App)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

source("../modules/rf_cad_module.R")

server <- function(input, output, session) {

  # ── Register the RF CAD module ─────────────────────────────────────────────
  cad <- rfCadServer("rfcad")

  # ── Export JSON ────────────────────────────────────────────────────────────
  # The toolbar Save button is wired directly in JS; here we handle the
  # header "Export JSON" button which triggers a download.
  output$rfcad_download_json <- downloadHandler(
    filename = function() {
      paste0("rf_cad_design_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json")
    },
    content = function(con) {
      writeLines(cad$get_json(), con)
    },
    contentType = "application/json"
  )

  observeEvent(input$btn_download_json, {
    # Trigger canvas export, then download
    session$sendCustomMessage("rfcad_export_json",
      list(instanceId = "rfcad", trigger = "download"))
  }, ignoreInit = TRUE)

  # ── Import JSON ─────────────────────────────────────────────────────────────
  observeEvent(input$import_confirm, {
    req(input$import_json_file)
    tryCatch({
      design_txt <- readLines(input$import_json_file$datapath, warn = FALSE)
      design_str <- paste(design_txt, collapse = "\n")
      # Validate JSON structure
      parsed <- jsonlite::fromJSON(design_str, simplifyVector = FALSE)
      req(!is.null(parsed$components))

      session$sendCustomMessage("rfcad_load_design",
        list(instanceId = "rfcad", design = design_str))

      # Close modal
      runjs("document.getElementById('rfcad-import-modal').style.display='none';")

      showNotification(
        paste0("Loaded design with ", length(parsed$components), " components."),
        type     = "message",
        duration = 3
      )
    }, error = function(e) {
      showNotification(
        paste0("Import failed: ", e$message),
        type     = "error",
        duration = 5
      )
    })
  }, ignoreInit = TRUE)

  observeEvent(input$import_cancel, {
    runjs("document.getElementById('rfcad-import-modal').style.display='none';")
  }, ignoreInit = TRUE)
}
