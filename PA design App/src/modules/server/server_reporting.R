# ============================================================
# server_reporting.R
# Reporting (section 7) and App Download (section 8) handlers.
#
# Provides:
#   serverReporting(input, output, session, state)
# ============================================================

serverReporting <- function(input, output, session, state) {

  # ── Stage completion status (static for now; wire to real state later) ───
  stage_info <- list(
    list(id = "first_principles", label = "1 · First Principles",    done = FALSE),
    list(id = "system_level",     label = "2 · System Level",        done = FALSE),
    list(id = "tech_level",       label = "3 · Technology Level",    done = FALSE),
    list(id = "device_level",     label = "4 · Device Level",        done = FALSE),
    list(id = "product_level",    label = "5 · Product Level",       done = FALSE),
    list(id = "lessons_learnt",   label = "6 · Lessons Learnt",      done = FALSE)
  )

  # ── Stage status cards ────────────────────────────────────────────────────
  output$reporting_stage_cards <- renderUI({
    cards <- lapply(stage_info, function(s) {
      status_col  <- if (s$done) "#2ca02c" else "#888"
      status_text <- if (s$done) "Complete" else "Stub — no data yet"
      status_icon <- if (s$done) icon("check-circle") else icon("clock")
      div(class = "report-stage-card",
        div(class = "stage-label",
          tags$span(style = paste0("color:", status_col), status_icon), " ", s$label
        ),
        div(class = "stage-status", status_text),
        if (s$id %in% input$report_include_stages) {
          tags$span(class = "badge", style = "background:#ff7f11", "Included")
        } else {
          tags$span(style = "color:#555; font-size:11px", "Excluded")
        }
      )
    })
    do.call(tagList, cards)
  })

  # ── Report preview (HTML fragment) ────────────────────────────────────────
  output$report_preview_html <- renderUI({
    req(input$report_preview_btn)
    isolate({
      title   <- if (nzchar(input$report_title))  input$report_title  else "PA Design Report"
      author  <- if (nzchar(input$report_author)) input$report_author else "—"
      rev_str <- if (nzchar(input$report_revision)) input$report_revision else "1.0"
      HTML(paste0(
        "<div style='font-family:sans-serif; color:#eee;'>",
        "<h3 style='color:#ff7f11;'>", htmltools::htmlEscape(title), "</h3>",
        "<p style='color:#aaa; font-size:12px;'>",
          "Author: ", htmltools::htmlEscape(author), " &nbsp;|&nbsp; ",
          "Rev: ",    htmltools::htmlEscape(rev_str), " &nbsp;|&nbsp; ",
          "Format: ", htmltools::htmlEscape(input$report_format %||% "html_self"),
        "</p>",
        "<hr style='border-color:#444;'>",
        "<p style='font-size:12px; color:#ccc;'>",
          htmltools::htmlEscape(
            if (nzchar(input$report_abstract)) input$report_abstract
            else "(No abstract entered)"
          ),
        "</p>",
        "<p style='color:#888; font-size:11px;'>",
          "Sections: ", paste(input$report_include_stages %||% "(none)", collapse=", "),
        "</p>",
        "</div>"
      ))
    })
  })

  # ── Download: stage reports (HTML) ────────────────────────────────────────
  output$report_download_stages <- downloadHandler(
    filename = function() {
      paste0("PA_Stage_Reports_", format(Sys.Date(), "%Y%m%d"), ".html")
    },
    content = function(file) {
      stages  <- input$report_include_stages %||% character(0)
      detail  <- input$report_detail_level   %||% "standard"
      html_parts <- c(
        "<html><head><meta charset='UTF-8'>",
        "<style>body{font-family:sans-serif;background:#1a1a1a;color:#eee;padding:30px}",
        "h1{color:#ff7f11} h2{color:#ccc} table{border-collapse:collapse;width:100%}",
        "th,td{border:1px solid #444;padding:6px 10px;font-size:13px}",
        "th{background:#2a2a2a}</style></head><body>",
        paste0("<h1>PA Design — Stage Reports</h1>"),
        paste0("<p><em>Generated: ", Sys.time(), " &nbsp;|&nbsp; Detail: ", detail, "</em></p><hr>")
      )
      for (s in stage_info) {
        if (s$id %in% stages) {
          html_parts <- c(html_parts,
            paste0("<h2>", s$label, "</h2>"),
            paste0("<p style='color:#888;'>This stage report is a placeholder. ",
                   "Real content will be pulled from stage-specific reactive outputs ",
                   "when full stage data entry is implemented.</p><hr>")
          )
        }
      }
      html_parts <- c(html_parts, "</body></html>")
      writeLines(paste(html_parts, collapse="\n"), file)
    },
    contentType = "text/html"
  )

  # ── Download: master report (HTML) ────────────────────────────────────────
  output$report_download_master <- downloadHandler(
    filename = function() {
      tag    <- gsub("[^A-Za-z0-9_-]", "_", input$report_title %||% "PA_Report")
      rev    <- gsub("[^A-Za-z0-9._-]", "_", input$report_revision %||% "1.0")
      ext    <- if (identical(input$report_format, "pdf")) "pdf" else "html"
      paste0(tag, "_rev", rev, "_", format(Sys.Date(), "%Y%m%d"), ".", ext)
    },
    content = function(file) {
      toc_html <- if (isTRUE(input$report_include_toc)) {
        paste0("<nav><h3>Table of Contents</h3><ol>",
               paste(sapply(stage_info, function(s) {
                 if (s$id %in% (input$report_include_stages %||% character(0)))
                   paste0("<li><a href='#", s$id, "'>" , s$label, "</a></li>")
                 else ""
               }), collapse=""),
               "</ol></nav><hr>")
      } else ""

      title   <- htmltools::htmlEscape(input$report_title   %||% "PA Design Report")
      author  <- htmltools::htmlEscape(input$report_author  %||% "")
      rev_str <- htmltools::htmlEscape(input$report_revision %||% "1.0")
      abstract_txt <- htmltools::htmlEscape(input$report_abstract %||% "")
      conf_banner <- if (isTRUE(input$report_confidential)) {
        "<div style='background:#7a0000;color:#fff;padding:6px 14px;border-radius:4px;font-size:13px;font-weight:700;'>CONFIDENTIAL</div><br>"
      } else ""
      custom_css <- input$report_custom_css %||% ""

      html <- paste0(
        "<!DOCTYPE html><html><head><meta charset='UTF-8'>",
        "<title>", title, "</title>",
        "<style>",
        "body{font-family:sans-serif;background:#fff;color:#222;padding:40px;max-width:900px;margin:auto}",
        "h1{color:#cc5500} h2{color:#333;border-bottom:1px solid #ddd;padding-bottom:4px}",
        "table{border-collapse:collapse;width:100%;margin:12px 0}",
        "th,td{border:1px solid #ccc;padding:6px 10px;font-size:13px}",
        "th{background:#f0f0f0} .confidential{background:#7a0000;color:#fff;padding:6px 14px;",
        "border-radius:4px;font-size:13px;font-weight:700}",
        custom_css,
        "</style></head><body>",
        conf_banner,
        "<h1>", title, "</h1>",
        "<p><strong>Author:</strong> ", author,
        " &nbsp;|&nbsp; <strong>Revision:</strong> ", rev_str,
        " &nbsp;|&nbsp; <strong>Date:</strong> ", format(Sys.Date()), "</p>",
        if (nzchar(abstract_txt)) paste0("<blockquote>", abstract_txt, "</blockquote><hr>") else "",
        toc_html,
        paste(sapply(stage_info, function(s) {
          if (s$id %in% (input$report_include_stages %||% character(0))) {
            paste0("<h2 id='", s$id, "'>", s$label, "</h2>",
                   "<p style='color:#666;font-size:13px;'>Stage data will be populated here ",
                   "when the corresponding design sections are completed.</p>")
          } else ""
        }), collapse=""),
        "</body></html>"
      )
      writeLines(html, file)
    },
    contentType = "text/html"
  )

  # ── Download: dataset snapshot (RDS) ──────────────────────────────────────
  output$snap_download_rds <- downloadHandler(
    filename = function() {
      tag <- gsub("[^A-Za-z0-9_-]", "_", input$snap_project_tag %||% "snapshot")
      if (!nzchar(tag)) tag <- "snapshot"
      paste0("PA_snapshot_", tag, "_", format(Sys.Date(), "%Y%m%d"), ".rds")
    },
    content = function(file) {
      snap <- list(
        meta = list(
          date        = Sys.time(),
          project_tag = input$snap_project_tag %||% "",
          app_version = "Phase5"
        ),
        # Pull live reactive values from state
        rv    = reactiveValuesToList(state$rv),
        stage_info = stage_info
      )
      saveRDS(snap, file)
    }
  )

  # ── Download: CSV zip ──────────────────────────────────────────────────────
  output$snap_download_csv <- downloadHandler(
    filename = function() {
      tag <- gsub("[^A-Za-z0-9_-]", "_", input$snap_project_tag %||% "csv")
      paste0("PA_data_", tag, "_", format(Sys.Date(), "%Y%m%d"), ".zip")
    },
    content = function(file) {
      tmp_dir <- tempfile()
      dir.create(tmp_dir)
      # Placeholder — write a manifest CSV; real tables from state$rv go here
      write.csv(
        data.frame(
          stage  = sapply(stage_info, `[[`, "label"),
          status = sapply(stage_info, function(s) if (s$done) "complete" else "stub")
        ),
        file.path(tmp_dir, "stage_manifest.csv"),
        row.names = FALSE
      )
      zip(file, files = list.files(tmp_dir, full.names = TRUE), flags = "-j")
    },
    contentType = "application/zip"
  )

  # ── Sub-app manifest preview ──────────────────────────────────────────────
  output$subapp_manifest_preview <- renderUI({
    req(input$subapp_preview_manifest)
    isolate({
      secs <- input$subapp_sections %||% character(0)
      if (length(secs) == 0) return(p(class="text-muted", "No sections selected."))
      wellPanel(
        h6("Manifest preview"),
        tags$ul(
          lapply(c(
            "app.R", "R/ui.R (filtered)", "R/server.R (filtered)",
            "www/custom.css", "www/js/",
            paste0("R/modules/server/server_", secs, ".R")
          ), tags$li)
        )
      )
    })
  })

  # ── Download: sub-app ZIP (placeholder) ────────────────────────────────────
  output$subapp_download_zip <- downloadHandler(
    filename = function() {
      name <- gsub("[^A-Za-z0-9_-]", "_", input$subapp_name %||% "PA_SubApp")
      paste0(name, "_v", gsub("[^0-9.]", "", input$subapp_version %||% "1.0"), ".zip")
    },
    content = function(file) {
      # Placeholder: produce a minimal sub-app structure as a ZIP
      tmp_dir <- tempfile()
      dir.create(tmp_dir)
      readme <- c(
        paste0("# ", input$subapp_name %||% "PA Sub-App"),
        paste0("Author: ", input$subapp_author %||% ""),
        paste0("Version: ", input$subapp_version %||% "1.0"),
        paste0("Generated: ", Sys.time()),
        "",
        "Sections included:",
        paste0("  - ", input$subapp_sections %||% "(none)")
      )
      writeLines(readme, file.path(tmp_dir, "README.md"))
      writeLines("# Placeholder app.R — full sub-app export coming in next phase.",
                 file.path(tmp_dir, "app.R"))
      zip(file, files = list.files(tmp_dir, full.names = TRUE), flags = "-j")
    },
    contentType = "application/zip"
  )

  # ── Template: save / list ──────────────────────────────────────────────────
  tmpl_path <- file.path("data", "templates.json")

  templates_rv <- reactiveVal({
    if (file.exists(tmpl_path)) {
      tryCatch(jsonlite::fromJSON(tmpl_path, simplifyVector = FALSE), error = function(e) list())
    } else {
      list()
    }
  })

  observeEvent(input$tmpl_save_btn, {
    req(nzchar(trimws(input$tmpl_name)))
    new_tmpl <- list(
      name        = input$tmpl_name,
      description = input$tmpl_description %||% "",
      tech        = input$tmpl_tech        %||% "",
      band        = input$tmpl_band        %||% "",
      saved_at    = format(Sys.time())
    )
    current <- templates_rv()
    # Remove old entry with same name if it exists
    current <- Filter(function(t) t$name != new_tmpl$name, current)
    current <- c(current, list(new_tmpl))
    dir.create(dirname(tmpl_path), showWarnings = FALSE, recursive = TRUE)
    jsonlite::write_json(current, tmpl_path, auto_unbox = TRUE, pretty = TRUE)
    templates_rv(current)
    showNotification(paste("Template saved:", new_tmpl$name), type = "message")
  })

  output$tmpl_list_ui <- renderUI({
    tmpls <- templates_rv()
    if (length(tmpls) == 0)
      return(p(class = "text-muted", "No templates saved yet."))
    rows <- lapply(tmpls, function(t) {
      tags$div(class = "report-stage-card",
        tags$span(class = "stage-label", icon("file-alt"), " ", t$name),
        tags$span(class = "stage-status",
          paste0(t$tech, " | ", t$band, " — ", t$saved_at))
      )
    })
    do.call(tagList, rows)
  })
}

# ── Utility: null-coalescing operator ────────────────────────────────────────
`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0 && !identical(x, "")) x else y
