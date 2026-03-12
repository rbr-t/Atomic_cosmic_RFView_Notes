# =============================================================================
# server_device_lib.R
# Server module: 3.3 Device Library tab.
#
# Shows a unified view of ALL devices from two sources:
#   · Knowledge Base  (manufacturer datasheets / app notes — `source = "knowledge_base"`)
#   · Device Portfolio (user-designed devices saved from 3.2 Guardrails — `source = "user_defined"`)
#
# Features:
#   · Filterable DT with colour-coded Source column (KB = teal, User = green)
#   · Detail panel for any selected device (KB card via kb_device_card(), or summary card)
#   · Side-by-side Compare tab (2–4 devices)
#   · "Add to Canvas" button converts a KB device to a portfolio file and pushes to canvas
# =============================================================================

serverDeviceLib <- function(input, output, session, state) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── Helper: read all saved portfolio devices from device_portfolio/*.json ─
  .load_portfolio <- function(dir = "device_portfolio") {
    if (!dir.exists(dir)) return(list())
    files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
    Filter(Negate(is.null), lapply(files, function(f) {
      tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
    }))
  }

  # ── Helper: convert a KB raw device list to a device_portfolio JSON file ─
  .kb_to_portfolio <- function(raw) {
    pn <- raw$part_number %||% raw$device_id %||% "unknown"

    pout_w   <- suppressWarnings(as.numeric(raw$pout_w_cw %||% raw$pout_w_pulse %||% NA))
    pout_dbm <- if (!is.null(pout_w) && !is.na(pout_w) && pout_w > 0) {
      round(10 * log10(pout_w * 1000), 1)
    } else suppressWarnings(as.numeric(raw$pout_dbm %||% 43))

    freq_mhz <- suppressWarnings(as.numeric(
      raw$freq_test_mhz %||%
      ((as.numeric(raw$freq_min_mhz %||% 2000) + as.numeric(raw$freq_max_mhz %||% 3000)) / 2)
    ))
    freq_ghz <- round(freq_mhz / 1000, 3)

    tech_key <- switch(raw$technology %||% "",
      "LDMOS"   = "LDMOS",  "GaN-SiC" = "GaN_SiC",
      "GaN-Si"  = "GaN_Si", "GaAs"    = "GaAs_pHEMT",
      raw$technology %||% "GaN_SiC"
    )

    list(
      id                    = paste0("kb_", gsub("[^a-zA-Z0-9]", "_", pn), "_",
                                     format(Sys.time(), "%Y%m%d%H%M%S")),
      label                 = pn,
      notes                 = paste0("[KB] ", raw$manufacturer %||% "", " — ",
                                     raw$knowledge_confidence %||% "medium", " confidence"),
      technology            = tech_key,
      tech_label            = trimws(paste(raw$technology %||% "", raw$generation %||% "")),
      freq_ghz              = freq_ghz,
      gain_db               = suppressWarnings(as.numeric(raw$gain_db %||% 15)),
      pae_pct               = suppressWarnings(as.numeric(raw$drain_eff_pct %||% raw$pae_pct %||% 30)),
      pout_dbm              = pout_dbm,
      vdd                   = suppressWarnings(as.numeric(raw$vdd_v %||% 28)),
      p1db_dbm              = pout_dbm - 2,
      pout_density_w_per_mm = 0,
      validation_status     = "ok",
      source                = "knowledge_base",
      kb_confidence         = raw$knowledge_confidence %||% "medium",
      manufacturer          = raw$manufacturer %||% "",
      saved_at              = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      canvas_component = list(
        type = "transistor", label = pn, technology = tech_key,
        gain  = suppressWarnings(as.numeric(raw$gain_db %||% 15)),
        pout  = pout_dbm, p1db = pout_dbm - 2,
        pae   = suppressWarnings(as.numeric(raw$drain_eff_pct %||% raw$pae_pct %||% 30)),
        vdd   = suppressWarnings(as.numeric(raw$vdd_v %||% 28)),
        freq  = freq_ghz, biasClass = "AB"
      )
    )
  }

  # ── Load KB data once at session start ──────────────────────────────────
  kb_all <- tryCatch(
    kb_load_all(kb_root = "../data/kb"),
    error = function(e) {
      message("[DevLib] KB load failed: ", e$message); data.frame()
    }
  )

  # Reactive trigger: bumped when a KB device is written to device_portfolio/
  # (from this module via dl33_add_kb_to_canvas, or from server_knowledge_base
  #  via kb_copy_to_lineup through the shared state$rv_portfolio_refresh signal)
  rv_refresh <- reactiveVal(0)

  observe({
    if (!is.null(state$rv_portfolio_refresh))
      state$rv_portfolio_refresh()   # take dependency
    isolate(rv_refresh(rv_refresh() + 1))
  })

  # ── Unified reactive: combine portfolio + KB devices ─────────────────────
  unified_df <- reactive({
    rv_refresh()   # re-run on portfolio writes

    # --- Portfolio devices → one row each -----------------------------------
    port <- .load_portfolio("device_portfolio")
    port_rows <- lapply(port, function(d) {
      pd <- suppressWarnings(as.numeric(d$pout_dbm %||% NA))
      pout_w <- if (!is.na(pd)) round(10^((pd - 30) / 10), 2) else NA_real_
      data.frame(
        device_id    = d$id %||% "",
        part_number  = d$label %||% "",
        manufacturer = d$manufacturer %||% "—",
        technology   = d$technology %||% "—",
        freq_mhz     = suppressWarnings(as.numeric(d$freq_ghz %||% NA) * 1000),
        pout_w       = pout_w,
        gain_db      = suppressWarnings(as.numeric(d$gain_db %||% NA)),
        pae_pct      = suppressWarnings(as.numeric(d$pae_pct %||% NA)),
        vdd_v        = suppressWarnings(as.numeric(d$vdd %||% NA)),
        confidence   = "user",
        source       = d$source %||% "user_defined",
        saved_at     = d$saved_at %||% "",
        stringsAsFactors = FALSE
      )
    })

    # --- KB devices → one row each (exclude placeholders) -------------------
    kb_filt <- kb_all
    if (nrow(kb_filt) > 0)
      kb_filt <- kb_filt[!grepl("^PLACEHOLDER", kb_filt$part_number, ignore.case = TRUE), ]

    kb_rows <- if (nrow(kb_filt) > 0) {
      lapply(seq_len(nrow(kb_filt)), function(i) {
        d <- kb_filt[i, ]
        fm <- if (!is.na(d$freq_test_mhz)) as.numeric(d$freq_test_mhz)
              else (as.numeric(d$freq_min_mhz %||% NA) + as.numeric(d$freq_max_mhz %||% NA)) / 2
        pw <- if (!is.na(d$pout_w_cw) && d$pout_w_cw > 0) as.numeric(d$pout_w_cw)
              else if (!is.na(d$pout_w_pulse) && d$pout_w_pulse > 0) as.numeric(d$pout_w_pulse)
              else NA_real_
        data.frame(
          device_id    = as.character(d$device_id %||% ""),
          part_number  = as.character(d$part_number %||% ""),
          manufacturer = as.character(d$manufacturer %||% "—"),
          technology   = as.character(d$technology %||% "—"),
          freq_mhz     = fm,
          pout_w       = pw,
          gain_db      = suppressWarnings(as.numeric(d$gain_db)),
          pae_pct      = suppressWarnings(as.numeric(d$drain_eff_pct %||% d$pae_pct)),
          vdd_v        = suppressWarnings(as.numeric(d$vdd_v)),
          confidence   = as.character(d$knowledge_confidence %||% "medium"),
          source       = "knowledge_base",
          saved_at     = "",
          stringsAsFactors = FALSE
        )
      })
    } else list()

    all_rows <- c(port_rows, kb_rows)
    if (length(all_rows) == 0) return(data.frame())
    do.call(rbind, all_rows)
  })

  # ── Filtered reactive (source + technology) ───────────────────────────────
  dl33_filtered <- reactive({
    df <- unified_df()
    if (is.null(df) || nrow(df) == 0) return(df)

    src_sel <- input$dl33_filter_source
    if (!is.null(src_sel) && length(src_sel) > 0 && !"All" %in% src_sel) {
      src_map <- c("Knowledge Base" = "knowledge_base", "User Designed" = "user_defined")
      df <- df[df$source %in% src_map[src_sel], ]
    }

    tech_sel <- input$dl33_filter_tech
    if (!is.null(tech_sel) && length(tech_sel) > 0 && !"All" %in% tech_sel)
      df <- df[df$technology %in% tech_sel, ]

    df
  })

  # ── Selected device IDs (multi-select) ────────────────────────────────────
  dl33_selected_ids <- reactiveVal(character(0))

  # ── Filter UI: technology choices ─────────────────────────────────────────
  output$dl33_tech_filter_ui <- renderUI({
    df <- unified_df()
    techs <- if (!is.null(df) && nrow(df) > 0)
      c("All", sort(unique(df$technology[!is.na(df$technology)])))
    else c("All")
    selectInput("dl33_filter_tech", "Technology",
      choices = techs, selected = "All", multiple = TRUE)
  })

  # ── Main DT ───────────────────────────────────────────────────────────────
  output$dl33_device_table <- DT::renderDT({
    df <- dl33_filtered()
    if (is.null(df) || nrow(df) == 0) {
      return(DT::datatable(
        data.frame(Message = "No devices match the current filters."),
        options = list(dom = "t"), rownames = FALSE,
        class = "compact cell-border"
      ))
    }

    disp <- data.frame(
      Source       = ifelse(df$source == "knowledge_base", "KB", "User"),
      Part         = df$part_number,
      Manufacturer = df$manufacturer,
      Technology   = df$technology,
      `Freq (MHz)` = suppressWarnings(round(as.numeric(df$freq_mhz), 0)),
      `Pout (W)`   = suppressWarnings(round(as.numeric(df$pout_w), 1)),
      `Gain (dB)`  = suppressWarnings(round(as.numeric(df$gain_db), 1)),
      `DE/PAE (%)`  = suppressWarnings(round(as.numeric(df$pae_pct), 1)),
      `Vdd (V)`    = suppressWarnings(round(as.numeric(df$vdd_v), 0)),
      Confidence   = df$confidence,
      device_id    = df$device_id,
      check.names  = FALSE,
      stringsAsFactors = FALSE
    )

    hidden_col <- which(names(disp) == "device_id") - 1L

    DT::datatable(
      disp,
      selection  = "multiple",
      rownames   = FALSE,
      class      = "compact cell-border hover",
      options    = list(
        dom        = "ltip",
        pageLength = 15,
        scrollX    = TRUE,
        columnDefs = list(
          list(targets = hidden_col, visible = FALSE),
          list(targets = 0L,        className = "dt-center")
        ),
        language = list(emptyTable = "No devices match filters.")
      )
    ) %>%
      DT::formatStyle(
        "Source",
        color = DT::styleEqual(c("KB", "User"), c("#5bc0de", "#5cb85c")),
        fontWeight = "bold",
        backgroundColor = DT::styleEqual(
          c("KB", "User"),
          c("rgba(91,192,222,0.12)", "rgba(92,184,92,0.12)")
        )
      ) %>%
      DT::formatStyle(
        "Confidence",
        color = DT::styleEqual(
          c("high", "medium", "low", "user"),
          c("#2ca02c", "#ff7f11", "#d62728", "#5cb85c")
        ),
        fontWeight = "600"
      )
  }, server = TRUE)

  # ── Row selection → update selected IDs ───────────────────────────────────
  observeEvent(input$dl33_device_table_rows_selected, {
    rows <- input$dl33_device_table_rows_selected
    df   <- dl33_filtered()
    if (is.null(rows) || length(rows) == 0 || is.null(df) || nrow(df) == 0) {
      dl33_selected_ids(character(0))
      return()
    }
    valid_rows <- rows[rows <= nrow(df)]
    dl33_selected_ids(df$device_id[valid_rows])
  })

  # ── Device detail panel ────────────────────────────────────────────────────
  output$dl33_device_detail <- renderUI({
    ids <- dl33_selected_ids()
    if (length(ids) == 0) {
      return(div(style = "padding:24px; text-align:center; color:#666;",
        icon("hand-pointer"),
        p("Click a row in the table above to see device details.")
      ))
    }

    dev_id <- ids[1]
    df     <- unified_df()
    row    <- df[df$device_id == dev_id, ]
    if (nrow(row) == 0) return(NULL)

    is_kb <- isTRUE(row$source[1] == "knowledge_base")

    if (is_kb) {
      raw <- tryCatch(
        kb_get_raw_device(dev_id, kb_root = "../data/kb"),
        error = function(e) NULL
      )
      if (!is.null(raw)) {
        tagList(
          kb_device_card(raw),
          div(style = "padding:8px 0;",
            actionButton("dl33_add_kb_to_canvas",
              label = tagList(icon("plus-circle"), " Add to Canvas"),
              class = "btn-primary btn-block"
            )
          )
        )
      } else p(style="color:#888;", "Could not load device details.")
    } else {
      # User-designed portfolio device
      div(class = "kb-device-card",
        h4(icon("microchip"), " ", row$part_number[1]),
        div(style = "background:rgba(255,255,255,0.04); border-radius:4px; padding:10px; margin:8px 0; font-size:12px;",
          tags$table(style = "width:100%;",
            tags$tr(tags$td(tags$strong("Technology:")),  tags$td(row$technology[1])),
            tags$tr(tags$td(tags$strong("Manufacturer:")), tags$td(row$manufacturer[1])),
            tags$tr(tags$td(tags$strong("Freq:")),        tags$td(paste(round(row$freq_mhz[1], 0), "MHz"))),
            tags$tr(tags$td(tags$strong("Pout:")),        tags$td(paste(round(row$pout_w[1], 1), "W"))),
            tags$tr(tags$td(tags$strong("Gain:")),        tags$td(paste(row$gain_db[1], "dB"))),
            tags$tr(tags$td(tags$strong("DE / PAE:")),    tags$td(paste(row$pae_pct[1], "%"))),
            tags$tr(tags$td(tags$strong("Vdd:")),        tags$td(paste(row$vdd_v[1], "V")))
          )
        ),
        div(style = "background:rgba(92,184,92,0.08); border-left:3px solid #5cb85c; padding:6px 10px; border-radius:3px; font-size:12px; color:#5cb85c;",
          icon("check-circle"),
          " User-designed device — already in canvas palette. Drag from the Device Library panel."
        )
      )
    }
  })

  # ── Add KB device to canvas ────────────────────────────────────────────────
  observeEvent(input$dl33_add_kb_to_canvas, {
    ids <- dl33_selected_ids()
    req(length(ids) > 0)
    dev_id <- ids[1]

    df  <- unified_df()
    row <- df[df$device_id == dev_id, ]
    req(nrow(row) > 0, isTRUE(row$source[1] == "knowledge_base"))

    raw <- tryCatch(
      kb_get_raw_device(dev_id, kb_root = "../data/kb"),
      error = function(e) NULL
    )
    req(raw)

    device <- .kb_to_portfolio(raw)

    portfolio_dir <- "device_portfolio"
    if (!dir.exists(portfolio_dir)) dir.create(portfolio_dir, recursive = TRUE)
    jsonlite::write_json(device,
      file.path(portfolio_dir, paste0(device$id, ".json")),
      pretty = TRUE, auto_unbox = TRUE
    )

    rv_refresh(rv_refresh() + 1)

    all_devices <- Filter(Negate(is.null),
      lapply(list.files(portfolio_dir, pattern = "\\.json$", full.names = TRUE), function(f) {
        tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
      })
    )
    session$sendCustomMessage("updateDevicePortfolio", all_devices)

    showNotification(
      paste0(device$label, " added to canvas palette — drag it from the Device Library panel."),
      type = "message", duration = 5
    )
  })

  # ── Compare panel ─────────────────────────────────────────────────────────
  output$dl33_compare_panel <- renderUI({
    ids <- dl33_selected_ids()
    if (length(ids) < 2) {
      return(div(style = "padding:24px; text-align:center; color:#888;",
        icon("info-circle"),
        p("Select 2–4 rows in the Browse tab (hold Ctrl / Cmd for multi-select), then click",
          tags$strong("Compare Selected"), " above."),
        p(style="font-size:11px; color:#666;", "Max 4 devices can be compared at once.")
      ))
    }

    df   <- unified_df()
    rows <- df[df$device_id %in% ids[seq_len(min(length(ids), 4L))], ]
    if (nrow(rows) == 0) return(NULL)

    metrics <- list(
      "Part Number"     = "part_number",
      "Manufacturer"    = "manufacturer",
      "Technology"      = "technology",
      "Freq (MHz)"      = "freq_mhz",
      "Pout (W)"        = "pout_w",
      "Gain (dB)"       = "gain_db",
      "DE / PAE (%)"    = "pae_pct",
      "Vdd (V)"         = "vdd_v",
      "Source"          = "source",
      "Confidence"      = "confidence"
    )

    src_badge <- function(src) {
      if (src == "knowledge_base")
        tags$span(style = "background:#1a3a5c; color:#5bc0de; font-size:9px; padding:1px 4px; border-radius:2px; margin-left:4px;", "KB")
      else
        tags$span(style = "background:#1a3a1a; color:#5cb85c; font-size:9px; padding:1px 4px; border-radius:2px; margin-left:4px;", "User")
    }

    tagList(
      h4(icon("balance-scale"), " Comparing: ",
        paste(rows$part_number, collapse = " vs ")),
      tags$table(
        class = "table table-sm table-striped table-bordered",
        style = "font-size:12px;",
        tags$thead(
          tags$tr(
            tags$th("Metric", style="min-width:110px;"),
            lapply(seq_len(nrow(rows)), function(i) {
              tags$th(rows$part_number[i], src_badge(rows$source[i]))
            })
          )
        ),
        tags$tbody(
          lapply(names(metrics), function(metric) {
            col  <- metrics[[metric]]
            vals <- if (col %in% names(rows)) {
              lapply(seq_len(nrow(rows)), function(i) {
                v <- rows[[col]][i]
                if (col == "source") {
                  if (v == "knowledge_base") "Knowledge Base" else "User Designed"
                } else if (is.numeric(v)) {
                  as.character(round(v, 2))
                } else {
                  as.character(if (is.na(v)) "—" else v)
                }
              })
            } else lapply(seq_len(nrow(rows)), function(i) "—")

            tags$tr(
              tags$td(tags$strong(metric)),
              lapply(vals, tags$td)
            )
          })
        )
      )
    )
  })

  # ── Compare Selected button → switch to Compare tab ───────────────────────
  observeEvent(input$dl33_compare_selected_btn, {
    ids <- dl33_selected_ids()
    if (length(ids) < 2) {
      showNotification("Select 2 or more rows (Ctrl+click) to compare.",
        type = "warning", duration = 4)
      return()
    }
    updateTabsetPanel(session, "dl33_tabs", selected = "dl33_compare")
  })

  # ── Summary stats for header ───────────────────────────────────────────────
  output$dl33_stats_text <- renderText({
    df <- unified_df()
    if (is.null(df) || nrow(df) == 0) return("No devices loaded.")
    n_kb   <- sum(df$source == "knowledge_base",  na.rm = TRUE)
    n_user <- sum(df$source != "knowledge_base",  na.rm = TRUE)
    paste0(n_kb, " KB devices  ·  ", n_user, " user-designed  ·  ", nrow(df), " total")
  })
}
