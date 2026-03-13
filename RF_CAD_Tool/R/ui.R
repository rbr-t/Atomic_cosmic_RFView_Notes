# =============================================================================
# ui.R  –  Standalone RF CAD Tool
# =============================================================================
library(shiny)
library(shinydashboard)
library(shinyjs)

source("../modules/rf_cad_module.R")

ui <- fluidPage(
  title = "RF CAD Tool",
  useShinyjs(),

  tags$head(
    tags$meta(charset = "UTF-8"),
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1.0"),
    tags$style(HTML("
      html, body { margin:0; padding:0; height:100vh; overflow:hidden;
                   background:#0f0f1a; color:#e0e0e0; font-family:'Segoe UI',sans-serif; }
      .rfcad-page-header {
        background:#12121e; border-bottom:1px solid #2a2a3a;
        padding:8px 16px; display:flex; align-items:center; gap:12px;
        height:44px; box-sizing:border-box;
      }
      .rfcad-page-title {
        color:#c8a84b; font-size:16px; font-weight:600; letter-spacing:.5px;
      }
      .rfcad-page-subtitle { color:#666; font-size:12px; }
      .rfcad-page-actions  { margin-left:auto; display:flex; gap:8px; }
      .rfcad-body-wrap     { height:calc(100vh - 44px); }
    "))
  ),

  # ── Page header ─────────────────────────────────────────────────────────────
  div(class = "rfcad-page-header",
    tags$span(class = "rfcad-page-title",
      icon("drafting-compass"), " RF CAD Tool"),
    tags$span(class = "rfcad-page-subtitle", "Phase 1 — 2D Layout Canvas"),
    div(class = "rfcad-page-actions",
      actionButton("btn_download_json", "Export JSON",
        class = "btn-default btn-sm", icon = icon("download")),
      actionButton("btn_load_json", "Import JSON",
        class = "btn-default btn-sm", icon = icon("upload")),
      tags$a(
        href   = "https://github.com/yourusername/rf-cad-tool",
        target = "_blank",
        class  = "btn btn-default btn-sm",
        icon("github"), " Docs"
      )
    )
  ),

  # ── Main canvas module ───────────────────────────────────────────────────────
  div(class = "rfcad-body-wrap",
    rfCadUI("rfcad",
      height     = "calc(100vh - 44px)",
      standalone = TRUE)
  ),

  # ── Import modal (file picker for loading saved JSON) ───────────────────────
  tags$div(
    id    = "rfcad-import-modal",
    style = "display:none; position:fixed; inset:0; background:rgba(0,0,0,.7);
             z-index:9999; align-items:center; justify-content:center;",
    tags$div(
      style = "background:#1a1a2e; border:1px solid #2a2a3a; border-radius:8px;
               padding:24px; min-width:340px; max-width:500px;",
      tags$h4(style = "color:#c8a84b; margin-top:0;", "Import Design JSON"),
      fileInput("import_json_file", NULL,
        accept = ".json",
        placeholder = "Choose design .json file"),
      div(style = "display:flex; gap:8px; justify-content:flex-end; margin-top:12px;",
        actionButton("import_cancel", "Cancel", class = "btn-default btn-sm"),
        actionButton("import_confirm", "Load",  class = "btn-primary btn-sm")
      )
    )
  ),

  # ── Wire modal open/close ────────────────────────────────────────────────────
  tags$script(HTML("
    document.getElementById('btn_load_json').addEventListener('click', function() {
      var m = document.getElementById('rfcad-import-modal');
      m.style.display = 'flex';
    });
    document.getElementById('import_cancel').addEventListener('click', function() {
      document.getElementById('rfcad-import-modal').style.display = 'none';
    });
  "))
)
