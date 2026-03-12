# =============================================================================
# server_knowledge_base.R
# Knowledge Base Shiny server module for the PA Design App.
#
# Provides:
#   · Searchable, filterable device table (DT)
#   · Device detail panel (specs, app notes, impedance)
#   · "Load Ropt to Smith Chart" button
#   · "Add to Lineup Canvas" button
#   · Utility drawer quick-search (handled via output$kb_drawer_*)
# =============================================================================

serverKnowledgeBase <- function(input, output, session, state) {

  # ── Load all KB data once at session start ─────────────────────────────────
  kb_all <- tryCatch(
    kb_load_all(kb_root = "../data/kb"),
    error = function(e) {
      message("[KB] Failed to load knowledge base: ", e$message)
      data.frame()
    }
  )

  # Reactive: currently filtered/searched dataset
  kb_filtered <- reactive({
    df <- kb_all
    if (nrow(df) == 0) return(df)

    # Search box
    q <- input$kb_search_box
    if (!is.null(q) && nzchar(trimws(q)))
      df <- kb_search(df, q)

    # Manufacturer filter
    mfr <- input$kb_filter_mfr
    if (!is.null(mfr) && length(mfr) > 0 && !"All" %in% mfr)
      df <- kb_filter(df, manufacturer = mfr)

    # Technology filter
    tech <- input$kb_filter_tech
    if (!is.null(tech) && length(tech) > 0 && !"All" %in% tech)
      df <- kb_filter(df, technology = tech)

    # Frequency filter
    freq <- input$kb_filter_freq_mhz
    if (!is.null(freq) && !is.na(freq) && freq > 0)
      df <- kb_filter(df, freq_mhz = as.numeric(freq))

    # Minimum power filter
    pout <- input$kb_filter_pout_w
    if (!is.null(pout) && !is.na(pout) && pout > 0)
      df <- kb_filter(df, pout_min_w = as.numeric(pout))

    # Application filter
    app <- input$kb_filter_app
    if (!is.null(app) && length(app) > 0 && !"All" %in% app)
      df <- kb_filter(df, application = app)

    # Role filter
    role <- input$kb_filter_role
    if (!is.null(role) && length(role) > 0 && !"All" %in% role)
      df <- kb_filter(df, role = role)

    # Show placeholders toggle
    show_ph <- isTRUE(input$kb_show_placeholders)
    if (!show_ph)
      df <- df[!grepl("^PLACEHOLDER", df$part_number, ignore.case = TRUE), ]

    df
  })

  # Reactive: currently selected device_id from DT row click
  selected_device_id <- reactiveVal(NULL)

  # ── Filter sidebar dynamic choices ────────────────────────────────────────
  output$kb_filter_mfr_ui <- renderUI({
    makers <- c("All", sort(unique(kb_all$manufacturer[!is.na(kb_all$manufacturer)])))
    selectInput("kb_filter_mfr", "Manufacturer",
      choices = makers, selected = "All", multiple = TRUE)
  })

  output$kb_filter_tech_ui <- renderUI({
    techs <- c("All", sort(unique(kb_all$technology[!is.na(kb_all$technology)])))
    selectInput("kb_filter_tech", "Technology",
      choices = techs, selected = "All", multiple = TRUE)
  })

  # ── Main device table ──────────────────────────────────────────────────────
  output$kb_device_table <- DT::renderDT({
    df <- kb_filtered()
    if (nrow(df) == 0) {
      return(DT::datatable(data.frame(Message = "No devices match the current filters."),
        options = list(dom = "t"), rownames = FALSE,
        class = "compact cell-border"))
    }

    disp <- kb_display_table(df)
    # Hide the device_id column (last col) — used for row selection lookup
    hidden_col <- which(names(disp) == "device_id") - 1  # 0-indexed for DT

    DT::datatable(
      disp,
      selection  = "single",
      rownames   = FALSE,
      class      = "compact cell-border hover",
      options    = list(
        dom        = "ltip",
        pageLength = 15,
        scrollX    = TRUE,
        columnDefs = list(
          list(targets = hidden_col, visible = FALSE),
          # Confidence column coloring via CSS class
          list(targets = which(names(disp) == "Confidence") - 1,
               className = "dt-center"),
          list(targets = which(names(disp) == "Status") - 1,
               className = "dt-center")
        ),
        language   = list(emptyTable = "No devices match filters")
      )
    ) %>%
      DT::formatStyle(
        "Confidence",
        color            = DT::styleEqual(
          c("high", "medium", "low"),
          c("#2ca02c", "#ff7f11", "#d62728")
        ),
        fontWeight       = "600"
      ) %>%
      DT::formatStyle(
        "Ropt (Ω)",
        color = DT::styleEqual("—", "#555", default = "#ff7f11"),
        fontFamily = "monospace"
      )
  }, server = TRUE)

  # ── Row selection → update device detail ──────────────────────────────────
  observeEvent(input$kb_device_table_rows_selected, {
    row_idx <- input$kb_device_table_rows_selected
    if (is.null(row_idx) || length(row_idx) == 0) {
      selected_device_id(NULL)
      return()
    }
    df      <- kb_filtered()
    disp    <- kb_display_table(df)
    dev_id  <- disp[row_idx, "device_id"]
    selected_device_id(dev_id)
  })

  # ── Device detail panel ────────────────────────────────────────────────────
  output$kb_device_detail <- renderUI({
    dev_id <- selected_device_id()
    if (is.null(dev_id) || !nzchar(dev_id)) {
      return(div(style = "padding:24px; text-align:center; color:#666;",
        icon("hand-pointer"),
        p("Click a row in the table above to see device details.")
      ))
    }
    raw <- tryCatch(
      kb_get_raw_device(dev_id, kb_root = "../data/kb"),
      error = function(e) NULL
    )
    kb_device_card(raw)
  })

  # ── Smith Chart integration — single representative Ropt ──────────────────
  observeEvent(input$kb_send_to_smith, {
    dev_id <- selected_device_id()
    req(dev_id)
    raw <- kb_get_raw_device(dev_id, kb_root = "../data/kb")
    req(raw)

    r_opt <- raw$ropt_ohm
    x_opt <- raw$xopt_ohm
    req(!is.null(r_opt) && !is.na(r_opt))

    updateNumericInput(session, "smith_z_real",  value = as.numeric(r_opt))
    updateNumericInput(session, "smith_z_imag",  value = as.numeric(x_opt %||% 0))
    updateTextInput(  session, "smith_label",    value = raw$part_number %||% dev_id)

    updateTabItems(session, "sidebar_menu", "smith_chart")

    showNotification(
      paste0("Ropt for ", raw$part_number, " loaded into Smith Chart."),
      type = "message", duration = 4
    )
  })

  # ── Smith Chart integration — LP table row (multi-frequency) ──────────────
  # Fired by JavaScript onclick in .render_lp_table() via Shiny.setInputValue
  observeEvent(input$kb_lp_row_click, {
    payload <- input$kb_lp_row_click
    req(payload)

    zl_r <- as.numeric(payload$zl_r)
    zl_x <- as.numeric(payload$zl_x)
    freq  <- payload$freq
    cond  <- payload$condition %||% ""

    if (is.na(zl_r)) return()

    # Get current device part number for the label
    dev_id <- selected_device_id()
    label_str <- if (!is.null(dev_id) && nzchar(dev_id)) {
      raw <- tryCatch(kb_get_raw_device(dev_id, kb_root = "../data/kb"), error = function(e) NULL)
      pn  <- if (!is.null(raw)) raw$part_number %||% dev_id else dev_id
      paste0(pn, " @ ", freq, "MHz (", cond, ")")
    } else {
      paste0("ZL @ ", freq, "MHz")
    }

    updateNumericInput(session, "smith_z_real",  value = zl_r)
    updateNumericInput(session, "smith_z_imag",  value = zl_x)
    updateTextInput(  session, "smith_label",    value = label_str)
    updateTabItems(   session, "sidebar_menu",   "smith_chart")

    showNotification(
      paste0("ZL = ", zl_r, if (zl_x >= 0) "+" else "", zl_x,
             "j Ω at ", freq, " MHz loaded into Smith Chart."),
      type = "message", duration = 4
    )
  })

  # ── Lineup Canvas integration — write KB device to device_portfolio/ ──────
  observeEvent(input$kb_copy_to_lineup, {
    dev_id <- selected_device_id()
    req(dev_id)
    raw <- kb_get_raw_device(dev_id, kb_root = "../data/kb")
    req(raw)

    pn <- raw$part_number %||% dev_id

    # Convert Pout: W → dBm (10·log10(W) + 30)
    pout_w   <- suppressWarnings(as.numeric(raw$pout_w_cw %||% raw$pout_w_pulse %||% NA))
    pout_dbm <- if (!is.null(pout_w) && !is.na(pout_w) && pout_w > 0) {
      round(10 * log10(pout_w * 1000), 1)
    } else {
      suppressWarnings(as.numeric(raw$pout_dbm %||% 43))
    }

    # Convert freq: MHz → GHz (use test freq, else midpoint of band)
    freq_mhz <- suppressWarnings(as.numeric(
      raw$freq_test_mhz %||%
      ((as.numeric(raw$freq_min_mhz %||% 2000) + as.numeric(raw$freq_max_mhz %||% 3000)) / 2)
    ))
    freq_ghz <- round(freq_mhz / 1000, 3)

    # Map KB technology string to guardrails key
    tech_key <- switch(raw$technology %||% "",
      "LDMOS"   = "LDMOS",
      "GaN-SiC" = "GaN_SiC",
      "GaN-Si"  = "GaN_Si",
      "GaAs"    = "GaAs_pHEMT",
      raw$technology %||% "GaN_SiC"
    )

    device <- list(
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
        type      = "transistor",
        label     = pn,
        technology = tech_key,
        gain      = suppressWarnings(as.numeric(raw$gain_db %||% 15)),
        pout      = pout_dbm,
        p1db      = pout_dbm - 2,
        pae       = suppressWarnings(as.numeric(raw$drain_eff_pct %||% raw$pae_pct %||% 30)),
        vdd       = suppressWarnings(as.numeric(raw$vdd_v %||% 28)),
        freq      = freq_ghz,
        biasClass = "AB"
      )
    )

    portfolio_dir <- "device_portfolio"
    if (!dir.exists(portfolio_dir)) dir.create(portfolio_dir, recursive = TRUE)
    jsonlite::write_json(device,
      file.path(portfolio_dir, paste0(device$id, ".json")),
      pretty = TRUE, auto_unbox = TRUE)

    # Push full updated portfolio to canvas palette
    all_devices <- Filter(Negate(is.null),
      lapply(list.files(portfolio_dir, pattern = "\\.json$", full.names = TRUE), function(f) {
        tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
      })
    )
    session$sendCustomMessage("updateDevicePortfolio", all_devices)

    # Signal device_lib module to refresh its unified table
    if (!is.null(state$rv_portfolio_refresh))
      state$rv_portfolio_refresh(state$rv_portfolio_refresh() + 1)

    showNotification(
      paste0(pn, " added to Device Library — available in PA Lineup canvas palette and 3.3 Device Library tab."),
      type = "message", duration = 5
    )
  })

  # ── Drawer quick-search output ─────────────────────────────────────────────
  output$kb_drawer_results <- renderUI({
    q <- input$drawer_kb_search
    if (is.null(q) || !nzchar(trimws(q)))
      return(p(style = "color:#888; font-size:12px;",
               "Type a part number or keyword and press Search."))

    hits <- kb_search(kb_all, q)
    hits <- hits[!grepl("^PLACEHOLDER", hits$part_number, ignore.case = TRUE), ]

    if (nrow(hits) == 0)
      return(p(style = "color:#888; font-size:12px;", "No devices found."))

    # Show top 5 hits
    n    <- min(nrow(hits), 5)
    hits <- hits[seq_len(n), ]

    tagList(
      p(style = "color:#888; font-size:11px; margin:4px 0 8px;",
        nrow(hits), " result(s) — open full view for more."),
      lapply(seq_len(n), function(i) {
        d    <- hits[i, ]
        conf <- d$knowledge_confidence %||% "low"
        ccol <- switch(conf, high="#2ca02c", medium="#ff7f11", low="#d62728", "#888")
        div(class = "drawer-link-row",
          style = "flex-direction:column; align-items:flex-start; padding:6px 0;",
          div(style = "display:flex; align-items:center; gap:6px; width:100%;",
            div(style = paste0("width:6px; height:6px; border-radius:50%;",
                               " background:", ccol, "; flex-shrink:0;")),
            tags$strong(style = "color:#ddd; font-size:12px;",
                        d$part_number %||% "?"),
            div(style = "margin-left:auto; color:#888; font-size:10px;",
                d$technology %||% "")
          ),
          div(style = "color:#888; font-size:11px; margin-left:12px;",
            d$freq_min_mhz %||% "?", "–", d$freq_max_mhz %||% "?", " MHz  \u00b7  ",
            ifelse(!is.na(d$pout_w_cw), paste0(d$pout_w_cw, " W CW"),
                   ifelse(!is.na(d$pout_w_pulse), paste0(d$pout_w_pulse, " W pulse"), ""))
          )
        )
      })
    )
  })

  # Trigger search from drawer when button clicked
  observeEvent(input$drawer_kb_go, {
    req(input$drawer_kb_search)
    # Output is reactive on input$drawer_kb_search — just update reactive chain
  })

  # ── KB stats for dashboard / status bar ───────────────────────────────────
  output$kb_stats_text <- renderText({
    n_total <- nrow(kb_all)
    n_high  <- sum(kb_all$knowledge_confidence == "high",  na.rm = TRUE)
    n_mfr   <- length(unique(kb_all$manufacturer[!is.na(kb_all$manufacturer)]))
    paste0(n_total, " devices  |  ", n_mfr, " manufacturers  |  ",
           n_high, " high-confidence records")
  })
}
