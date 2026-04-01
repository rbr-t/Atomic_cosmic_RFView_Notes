# ============================================================
# server_transistor_design.R
# Shiny server module: Product-Level Transistor Design Synthesis.
# Tab: "prod_transistor"  |  Sidebar section: "5 · Product Level"
#
# Depends on:
#   modules/calculations/calc_transistor_sizing.R  (pure calc functions)
#   state$lineup_calc_results                      (PA lineup reactive)
# ============================================================

serverTransistorDesign <- function(input, output, session, state) {

  # ── Local null-coalescing operator (mirrors server.R definition) ──
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── Unpack shared state ──────────────────────────────────────
  rv          <- state$rv
  calc_results <- state$lineup_calc_results %||% state$calc_results

  # ── CSS constants (dark theme) ────────────────────────────────
  CSS_BG      <- "#1e1e2e"
  CSS_BORDER  <- "#2a2a3a"
  CSS_ACCENT  <- "#ff7f11"
  CSS_TEXT    <- "#e0e0e0"
  CSS_MUTED   <- "#888899"

  # ── Traffic-light helpers ────────────────────────────────────
  dot_green  <- tags$span(style = "color:#28c940; font-size:16px;", "\u25cf")
  dot_amber  <- tags$span(style = "color:#ffaa00; font-size:16px;", "\u25cf")
  dot_red    <- tags$span(style = "color:#ff3b30; font-size:16px;", "\u25cf")

  tl_dot <- function(level) switch(level, GREEN = dot_green, AMBER = dot_amber, dot_red)

  # ── Ropt colour-coding helper ────────────────────────────────
  ropt_color <- function(r) {
    if (is.na(r))             return("color:#888;")
    if (r >= 5  && r <= 100)  return("color:#28c940; font-weight:bold;")
    if ((r >= 3 && r < 5) || (r > 100 && r <= 200)) return("color:#ffaa00; font-weight:bold;")
    "color:#ff3b30; font-weight:bold;"
  }

  # ── Placeholder when no lineup results available ─────────────
  no_results_ui <- function() {
    tags$div(
      style = paste0(
        "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";",
        "border-radius:6px; padding:32px; text-align:center; color:", CSS_MUTED, ";"
      ),
      tags$p(
        style = "font-size:16px; margin:0;",
        icon("info-circle"),
        " Run the PA Lineup Calculator first",
        tags$br(),
        tags$small("(4.2 Architecture & Design Canvas)")
      )
    )
  }

  # ── Transistor-stage guard: TRUE if stage is a transistor ────
  is_transistor_stage <- function(stage) {
    isTRUE(stage$type == "transistor")
  }

  # ── Stage identifier: prefer label, fall back to id ──────────
  stage_label <- function(stage) {
    stage$stage %||% stage$id %||% "Stage"
  }

  # ================================================================
  # 1. TRANSISTOR DESIGN RESULTS  (private reactive)
  # ================================================================
  transistor_design_results <- reactive({
    res <- tryCatch(calc_results(), error = function(e) NULL)
    if (is.null(res) || is.null(res$stage_results) || length(res$stage_results) == 0) {
      return(NULL)
    }

    freq_ghz <- (input$spec_frequency %||% 2000) / 1000

    topology <- input$transistor_topology %||% "doherty_symmetric"

    er   <- input$combiner_er   %||% 3.55
    h_mm <- input$combiner_h_mm %||% 0.508

    per_stage <- lapply(res$stage_results, function(stage) {
      if (!is_transistor_stage(stage)) return(NULL)

      tryCatch(
        calc_transistor_design_suite(
          stage_result = stage,
          freq_ghz     = freq_ghz,
          topology     = topology,
          er           = er,
          h_mm         = h_mm
        ),
        error = function(e) {
          cat(sprintf("[TransistorDesign] calc_transistor_design_suite error for %s: %s\n",
                      stage_label(stage), e$message))
          NULL
        }
      )
    })

    # Name entries by stage label; remove non-transistor NULLs
    transistor_stages <- Filter(function(s) !is.null(s), {
      named <- list()
      for (i in seq_along(res$stage_results)) {
        s <- res$stage_results[[i]]
        if (is_transistor_stage(s) && !is.null(per_stage[[i]])) {
          named[[stage_label(s)]] <- per_stage[[i]]
        }
      }
      named
    })

    if (length(transistor_stages) == 0) return(NULL)

    # Attach raw stage data for compliance checks
    attr(transistor_stages, "stage_results_raw") <- res$stage_results
    transistor_stages
  })

  # ================================================================
  # 2. TRANSISTOR STAGE TABLE  output$transistor_stage_table
  # ================================================================
  output$transistor_stage_table <- renderUI({
    td <- transistor_design_results()
    if (is.null(td)) return(no_results_ui())

    topology   <- input$transistor_topology %||% "doherty_symmetric"
    is_doherty <- grepl("doherty", topology, ignore.case = TRUE)

    header_cells <- tagList(
      tags$th("Stage"),
      tags$th("Technology"),
      tags$th("Pout (dBm)"),
      tags$th("Ropt (\u03a9)"),
      tags$th("Gate Width (mm)"),
      tags$th("Idq (mA)"),
      tags$th("Bias Class")
    )
    if (is_doherty) {
      header_cells <- tagList(
        header_cells,
        tags$th("Ropt\u2098 (\u03a9)"),
        tags$th("Ropt\u209a (\u03a9)"),
        tags$th("Zt (\u03a9)")
      )
    }

    rows <- lapply(names(td), function(nm) {
      d     <- td[[nm]]
      ropt  <- d$ropt$Ropt_ohm  %||% NA
      gw    <- d$gate_width$gate_width_mm %||% NA
      idq   <- d$idq$Idq_mA     %||% NA
      cls   <- d$idq$class_label %||% "Class AB"
      pout  <- d$pout_dbm        %||% NA
      tech  <- attr(d, "technology") %||% "GaN-on-SiC"

      base_cells <- tagList(
        tags$td(nm),
        tags$td(tech),
        tags$td(if (!is.na(pout))  sprintf("%.1f", pout)  else "\u2014"),
        tags$td(style = ropt_color(ropt),
                if (!is.na(ropt))  sprintf("%.1f", ropt)  else "\u2014"),
        tags$td(if (!is.na(gw))    sprintf("%.2f", gw)    else "\u2014"),
        tags$td(if (!is.na(idq))   sprintf("%.1f", idq)   else "\u2014"),
        tags$td(cls)
      )

      if (is_doherty && !is.null(d$doherty)) {
        doh <- d$doherty
        extra <- tagList(
          tags$td(sprintf("%.1f", doh$Ropt_main_ohm %||% NA)),
          tags$td(sprintf("%.1f", doh$Ropt_peak_ohm %||% NA)),
          tags$td(sprintf("%.1f", doh$Zt_ohm        %||% NA))
        )
        tags$tr(base_cells, extra)
      } else if (is_doherty) {
        tags$tr(base_cells,
                tags$td("\u2014"), tags$td("\u2014"), tags$td("\u2014"))
      } else {
        tags$tr(base_cells)
      }
    })

    th_style <- paste0("color:", CSS_ACCENT, "; font-size:12px;",
                       " padding:6px 10px; text-align:left;",
                       " border-bottom:1px solid ", CSS_BORDER, ";")
    td_style <- paste0("color:", CSS_TEXT, "; font-size:12px;",
                       " padding:5px 10px; border-bottom:1px solid ",
                       CSS_BORDER, ";")

    tags$div(
      style = paste0("overflow-x:auto; margin-bottom:12px;"),
      tags$table(
        style = paste0(
          "width:100%; border-collapse:collapse;",
          "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";"
        ),
        tags$thead(
          tags$tr(
            lapply(header_cells$children %||% list(header_cells), function(th) {
              tagAppendAttributes(th, style = th_style)
            })
          )
        ),
        tags$tbody(
          style = td_style,
          rows
        )
      ),
      tags$p(
        style = paste0("font-size:11px; color:", CSS_MUTED, "; margin-top:4px;"),
        tags$span(style = "color:#28c940;", "\u25cf"), " Ropt 5\u2013100\u03a9 \u2003",
        tags$span(style = "color:#ffaa00;", "\u25cf"), " Ropt 3\u20135 or 100\u2013200\u03a9 \u2003",
        tags$span(style = "color:#ff3b30;", "\u25cf"), " Ropt outside range"
      )
    )
  })

  # ================================================================
  # 3. DOHERTY COMBINER PANEL  output$doherty_combiner_panel
  # ================================================================
  output$doherty_combiner_panel <- renderUI({
    topology <- input$transistor_topology %||% "doherty_symmetric"
    if (!grepl("doherty", topology, ignore.case = TRUE)) return(NULL)

    td <- transistor_design_results()
    if (is.null(td)) return(no_results_ui())

    # Use the last (output) transistor stage for combiner calc
    last_stage <- td[[length(td)]]
    cb <- last_stage$combiner

    if (is.null(cb)) {
      return(tags$p(style = paste0("color:", CSS_MUTED, ";"),
                    "Combiner data unavailable \u2014 ensure a transistor stage is in the lineup."))
    }

    box_style <- paste0(
      "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";",
      "border-radius:6px; padding:16px; margin-top:16px;"
    )

    tags$div(
      style = box_style,
      tags$h5(style = paste0("color:", CSS_ACCENT, "; margin-top:0;"),
              icon("wave-square"), " Doherty Quarter-Wave Combiner"),
      tags$div(
        style = "display:grid; grid-template-columns:1fr 1fr 1fr 1fr; gap:10px;",
        tags$div(
          tags$small(style = paste0("color:", CSS_MUTED, ";"), "Zt (\u03a9)"),
          tags$p(style = paste0("color:", CSS_TEXT, "; font-size:16px; margin:0; font-weight:bold;"),
                 sprintf("%.1f", cb$Zt_ohm))
        ),
        tags$div(
          tags$small(style = paste0("color:", CSS_MUTED, ";"), "Length (mm)"),
          tags$p(style = paste0("color:", CSS_TEXT, "; font-size:16px; margin:0; font-weight:bold;"),
                 sprintf("%.2f", cb$len_mm))
        ),
        tags$div(
          tags$small(style = paste0("color:", CSS_MUTED, ";"), "Width (mm)"),
          tags$p(style = paste0("color:", CSS_TEXT, "; font-size:16px; margin:0; font-weight:bold;"),
                 sprintf("%.3f", cb$width_mm))
        ),
        tags$div(
          tags$small(style = paste0("color:", CSS_MUTED, ";"), "\u03bbg/4 (mm)"),
          tags$p(style = paste0("color:", CSS_TEXT, "; font-size:16px; margin:0; font-weight:bold;"),
                 sprintf("%.2f", cb$lambda_g_mm / 4))
        )
      ),
      tags$hr(style = paste0("border-color:", CSS_BORDER, ";")),
      tags$div(
        style = "display:grid; grid-template-columns:1fr 1fr; gap:10px;",
        numericInput("combiner_er",    "\u03b5r (substrate)",
                     value = cb$er, min = 1, max = 20, step = 0.01),
        numericInput("combiner_h_mm", "h (mm)",
                     value = cb$h_mm, min = 0.05, max = 5, step = 0.001)
      ),
      tags$p(
        style = paste0("font-size:11px; color:", CSS_MUTED, "; margin-top:8px; font-style:italic;"),
        "Formula: Zt = \u221a(Ropt\u2098 \u00d7 50\u03a9)  \u2014  ",
        cb$formula_Zt
      ),
      tags$p(
        style = paste0("font-size:11px; color:", CSS_MUTED, "; margin-top:0;"),
        cb$formula_len
      )
    )
  })

  # ================================================================
  # 4. MATCHING NETWORK PANEL  output$matching_network_panel
  # ================================================================
  output$matching_network_panel <- renderUI({
    td <- transistor_design_results()
    if (is.null(td)) return(no_results_ui())

    box_style <- paste0(
      "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";",
      "border-radius:6px; padding:16px; margin-bottom:12px;"
    )

    panels <- lapply(names(td), function(nm) {
      d  <- td[[nm]]
      im <- d$matching_input
      if (is.null(im)) return(NULL)

      topo_label <- switch(im$topology,
        step_down_L = "Step-Down L (series-L + shunt-C)",
        step_up_C   = "Step-Up L (series-C + shunt-L)",
        none        = "Not required",
        im$topology
      )

      tags$div(
        style = box_style,
        tags$h6(style = paste0("color:", CSS_ACCENT, "; margin-top:0;"),
                icon("sliders-h"), " ", nm, " — Input Matching Network"),
        tags$div(
          style = "display:grid; grid-template-columns:repeat(5,1fr); gap:10px;",
          tags$div(
            tags$small(style = paste0("color:", CSS_MUTED, ";"), "Topology"),
            tags$p(style = paste0("color:", CSS_TEXT, "; font-size:13px; margin:0;"), topo_label)
          ),
          tags$div(
            tags$small(style = paste0("color:", CSS_MUTED, ";"), "L (nH)"),
            tags$p(style = paste0("color:", CSS_TEXT, "; font-size:15px; margin:0; font-weight:bold;"),
                   if (!is.na(im$L_nH)) sprintf("%.2f", im$L_nH) else "\u2014")
          ),
          tags$div(
            tags$small(style = paste0("color:", CSS_MUTED, ";"), "C (pF)"),
            tags$p(style = paste0("color:", CSS_TEXT, "; font-size:15px; margin:0; font-weight:bold;"),
                   if (!is.na(im$C_pF)) sprintf("%.2f", im$C_pF) else "\u2014")
          ),
          tags$div(
            tags$small(style = paste0("color:", CSS_MUTED, ";"), "Q"),
            tags$p(style = paste0("color:", CSS_TEXT, "; font-size:15px; margin:0; font-weight:bold;"),
                   sprintf("%.2f", im$Q))
          ),
          tags$div(
            tags$small(style = paste0("color:", CSS_MUTED, ";"), "Est. BW (%)"),
            tags$p(style = paste0("color:", CSS_TEXT, "; font-size:15px; margin:0; font-weight:bold;"),
                   if (is.finite(im$bw_pct)) sprintf("%.0f%%", im$bw_pct) else "\u221e")
          )
        ),
        tags$p(
          style = paste0("font-size:11px; color:", CSS_MUTED, "; margin-top:8px;"),
          im$formula_str
        ),
        tags$p(
          style = paste0("font-size:11px; color:", CSS_MUTED, "; margin-top:0; font-style:italic;"),
          "BW \u2248 100/Q (%)  \u2014  Bode-Fano limit: bandwidth \u00d7 reflection cannot",
          " both be minimised simultaneously for a finite Q network."
        )
      )
    })

    do.call(tagList, Filter(Negate(is.null), panels))
  })

  # ================================================================
  # 5. DESIGN DECISION LOG  output$design_decision_log
  # ================================================================
  output$design_decision_log <- renderUI({
    td <- transistor_design_results()
    if (is.null(td)) return(no_results_ui())

    entries <- lapply(names(td), function(nm) {
      lines <- format_transistor_rationale(td[[nm]])
      header_line <- paste0("=== ", nm, " ===")
      all_lines   <- c(header_line, lines, "")
      paste(all_lines, collapse = "\n")
    })

    log_text <- paste(entries, collapse = "\n")

    tags$div(
      tags$h5(
        style = paste0("color:", CSS_ACCENT, "; margin-bottom:8px;"),
        icon("clipboard-list"),
        " Design Decision Log \u2014 Transistor Level"
      ),
      tags$pre(
        style = paste0(
          "background:#131320; border:1px solid ", CSS_BORDER, ";",
          "border-radius:4px; padding:12px; color:", CSS_TEXT, ";",
          "font-size:12px; font-family:'Fira Code','Consolas',monospace;",
          "white-space:pre-wrap; max-height:500px; overflow-y:auto;"
        ),
        log_text
      )
    )
  })

  # ================================================================
  # 6. SPEC VALIDATION TABLE  output$spec_validation_table
  # ================================================================
  output$spec_validation_table <- renderUI({
    td <- transistor_design_results()
    if (is.null(td)) return(no_results_ui())

    pae_target <- input$spec_efficiency %||% 45
    p3db_spec  <- input$spec_p3db       %||% 47

    # Aggregate across transistor stages
    all_ropt <- sapply(td, function(d) d$ropt$Ropt_ohm      %||% NA)
    all_gw   <- sapply(td, function(d) d$gate_width$gate_width_mm %||% NA)
    all_pae  <- sapply(td, function(d) d$pout_dbm %||% NA)  # pout used for P3dB check

    raw_stages <- attr(td, "stage_results_raw")
    last_transistor_pout <- tryCatch({
      t_stages <- Filter(is_transistor_stage, raw_stages)
      if (length(t_stages) > 0)
        tail(t_stages, 1)[[1]]$pout_dbm %||% NA
      else NA
    }, error = function(e) NA)

    last_transistor_pae <- tryCatch({
      t_stages <- Filter(is_transistor_stage, raw_stages)
      if (length(t_stages) > 0)
        tail(t_stages, 1)[[1]]$pae_pct %||% NA
      else NA
    }, error = function(e) NA)

    # ── Evaluate traffic-light levels ────────────────────────────
    # Ropt
    ropt_val <- mean(all_ropt, na.rm = TRUE)
    ropt_lvl <- if (is.na(ropt_val)) "RED" else if (ropt_val >= 5 && ropt_val <= 100) "GREEN" else if ((ropt_val >= 2 && ropt_val < 5) || (ropt_val > 100 && ropt_val <= 300)) "AMBER" else "RED"

    # Gate width
    gw_val <- mean(all_gw, na.rm = TRUE)
    gw_lvl <- if (is.na(gw_val)) "RED" else if (gw_val >= 0.1 && gw_val <= 10) "GREEN" else if (gw_val > 10 && gw_val <= 20) "AMBER" else "RED"

    # PAE
    pae_diff <- last_transistor_pae - pae_target
    pae_lvl  <- if (is.na(last_transistor_pae)) "RED" else if (abs(pae_diff) <= 5) "GREEN" else if (pae_diff >= -15) "AMBER" else "RED"

    # P3dB
    p3db_diff <- last_transistor_pout - p3db_spec
    p3db_lvl  <- if (is.na(last_transistor_pout)) "RED" else if (abs(p3db_diff) <= 0.5) "GREEN" else if (abs(p3db_diff) <= 1.5) "AMBER" else "RED"

    # Idq
    all_idq <- sapply(td, function(d) d$idq$Idq_mA %||% NA)
    idq_val  <- mean(all_idq, na.rm = TRUE)
    idq_lvl  <- if (is.na(idq_val)) "RED" else if (idq_val >= 10 && idq_val <= 500) "GREEN" else if (idq_val > 500 && idq_val <= 1000) "AMBER" else "RED"

    th_style <- paste0(
      "color:", CSS_ACCENT, "; font-size:12px; padding:6px 12px;",
      "text-align:left; border-bottom:1px solid ", CSS_BORDER, ";"
    )
    td_style <- paste0(
      "color:", CSS_TEXT, "; font-size:12px; padding:5px 12px;",
      "border-bottom:1px solid ", CSS_BORDER, ";"
    )

    make_row <- function(param, value_str, level, note) {
      tags$tr(
        tags$td(style = td_style, tl_dot(level)),
        tags$td(style = td_style, param),
        tags$td(style = td_style, value_str),
        tags$td(style = paste0(td_style, "color:",
                               switch(level, GREEN = "#28c940", AMBER = "#ffaa00", "#ff3b30"), ";"),
                level),
        tags$td(style = paste0(td_style, "color:", CSS_MUTED, "; font-size:11px;"), note)
      )
    }

    tags$div(
      tags$h5(style = paste0("color:", CSS_ACCENT, "; margin-bottom:8px;"),
              icon("traffic-light"), " Specification Compliance"),
      tags$table(
        style = paste0(
          "width:100%; border-collapse:collapse;",
          "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";"
        ),
        tags$thead(
          tags$tr(
            lapply(c("", "Parameter", "Value", "Status", "Note"), function(h) {
              tags$th(style = th_style, h)
            })
          )
        ),
        tags$tbody(
          make_row("Ropt Range",
                   if (!is.na(ropt_val)) sprintf("%.1f \u03a9 (mean)", ropt_val) else "N/A",
                   ropt_lvl,
                   "Target: 5\u2013100 \u03a9"),
          make_row("Gate Width",
                   if (!is.na(gw_val)) sprintf("%.2f mm (mean)", gw_val) else "N/A",
                   gw_lvl,
                   "Target: 0.1\u201310 mm"),
          make_row("PAE vs Target",
                   if (!is.na(last_transistor_pae))
                     sprintf("%.1f%% (target %.0f%%)", last_transistor_pae, pae_target)
                   else "N/A",
                   pae_lvl,
                   if (!is.na(pae_diff)) sprintf("%+.1f%% vs target", pae_diff) else ""),
          make_row("P3dB vs Spec",
                   if (!is.na(last_transistor_pout))
                     sprintf("%.1f dBm (spec %.1f dBm)", last_transistor_pout, p3db_spec)
                   else "N/A",
                   p3db_lvl,
                   if (!is.na(p3db_diff)) sprintf("%+.2f dB vs spec", p3db_diff) else ""),
          make_row("Idq Range",
                   if (!is.na(idq_val)) sprintf("%.1f mA (mean)", idq_val) else "N/A",
                   idq_lvl,
                   "Class AB: 10\u2013500 mA typical")
        )
      )
    )
  })

  # ================================================================
  # 7. EXPORT DOWNLOAD HANDLER  output$export_transistor_design
  # ================================================================
  output$export_transistor_design <- downloadHandler(
    filename = function() {
      paste0("transistor_design_", format(Sys.time(), "%Y%m%d_%H%M"), ".md")
    },
    content = function(file) {
      td  <- tryCatch(transistor_design_results(), error = function(e) NULL)
      res <- tryCatch(calc_results(), error = function(e) NULL)

      freq_mhz   <- input$spec_frequency     %||% NA
      p3db       <- input$spec_p3db          %||% NA
      gain       <- input$spec_gain          %||% NA
      vdd        <- input$spec_supply_voltage %||% NA
      pae_target <- input$spec_efficiency    %||% NA
      par        <- input$spec_par           %||% NA
      topology   <- input$transistor_topology %||% "doherty_symmetric"

      lines <- c(
        "# PA Transistor Design Summary",
        paste0("*Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "*"),
        "",
        "---",
        "",
        "## 1. Specifications",
        "",
        paste0("| Parameter | Value |"),
        paste0("|-----------|-------|"),
        paste0("| Frequency | ", if (!is.na(freq_mhz)) sprintf("%.0f MHz (%.3f GHz)", freq_mhz, freq_mhz/1000) else "N/A", " |"),
        paste0("| P3dB (peak) | ", if (!is.na(p3db)) sprintf("%.1f dBm", p3db) else "N/A", " |"),
        paste0("| Total Gain | ", if (!is.na(gain)) sprintf("%.1f dB", gain) else "N/A", " |"),
        paste0("| Supply Voltage | ", if (!is.na(vdd)) sprintf("%.0f V", vdd) else "N/A", " |"),
        paste0("| PAE Target | ", if (!is.na(pae_target)) sprintf("%.0f%%", pae_target) else "N/A", " |"),
        paste0("| PAR | ", if (!is.na(par)) sprintf("%.1f dB", par) else "N/A", " |"),
        paste0("| Topology | ", topology, " |"),
        "",
        "---",
        "",
        "## 2. Stage Budget"
      )

      if (!is.null(res) && !is.null(res$stage_results)) {
        lines <- c(lines, "",
                   "| Stage | Type | Pin (dBm) | Pout (dBm) | Gain (dB) | PAE (%) |",
                   "|-------|------|-----------|------------|-----------|---------|")
        for (s in res$stage_results) {
          pae_str <- if (!is.null(s$pae_pct) && !is.na(s$pae_pct))
            sprintf("%.1f", s$pae_pct) else "—"
          gain_str <- if (!is.null(s$gain_full_db) && !is.na(s$gain_full_db))
            sprintf("%.1f", s$gain_full_db) else "—"
          lines <- c(lines, sprintf("| %s | %s | %.1f | %.1f | %s | %s |",
                                    stage_label(s), s$type %||% "?",
                                    s$pin_dbm  %||% 0,
                                    s$pout_dbm %||% 0,
                                    gain_str, pae_str))
        }
      } else {
        lines <- c(lines, "", "*No lineup data available.*")
      }

      lines <- c(lines, "", "---", "", "## 3. Transistor Specifications")

      if (!is.null(td)) {
        lines <- c(lines, "",
                   "| Stage | Ropt (\u03a9) | Gate Width (mm) | Idq (mA) | Bias |",
                   "|-------|-----------|----------------|----------|------|")
        for (nm in names(td)) {
          d    <- td[[nm]]
          ropt <- d$ropt$Ropt_ohm          %||% NA
          gw   <- d$gate_width$gate_width_mm %||% NA
          idq  <- d$idq$Idq_mA             %||% NA
          cls  <- d$idq$class_label         %||% "Class AB"
          lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |",
                                    nm,
                                    if (!is.na(ropt)) sprintf("%.1f", ropt) else "\u2014",
                                    if (!is.na(gw))   sprintf("%.2f", gw)   else "\u2014",
                                    if (!is.na(idq))  sprintf("%.1f", idq)  else "\u2014",
                                    cls))
        }
      } else {
        lines <- c(lines, "", "*Run PA Lineup Calculator to populate.*")
      }

      lines <- c(lines, "", "---", "", "## 4. Building Block Designs")

      if (!is.null(td)) {
        for (nm in names(td)) {
          d  <- td[[nm]]
          im <- d$matching_input
          cb <- d$combiner
          lines <- c(lines, "", paste0("### ", nm))
          if (!is.null(im) && im$topology != "none") {
            lines <- c(lines,
                       paste0("**Input Matching (", im$topology, "):** ",
                              sprintf("L = %.2f nH, C = %.2f pF, Q = %.2f, BW \u2248 %.0f%%",
                                      im$L_nH, im$C_pF, im$Q, im$bw_pct)))
          }
          if (!is.null(cb)) {
            lines <- c(lines,
                       paste0("**QW Combiner:** ",
                              sprintf("Zt = %.1f \u03a9, len = %.2f mm, W = %.3f mm",
                                      cb$Zt_ohm, cb$len_mm, cb$width_mm)))
          }
        }
      } else {
        lines <- c(lines, "", "*No transistor data.*")
      }

      lines <- c(lines, "", "---", "", "## 5. Design Decisions")

      if (!is.null(td)) {
        for (nm in names(td)) {
          lines <- c(lines, "", paste0("### ", nm))
          rationale <- format_transistor_rationale(td[[nm]])
          lines <- c(lines, paste0("    ", rationale))
        }
      } else {
        lines <- c(lines, "", "*No data.*")
      }

      lines <- c(lines, "", "---", "", "## 6. Spec Compliance")

      if (!is.null(td)) {
        pae_target_val <- input$spec_efficiency %||% 45
        p3db_spec_val  <- input$spec_p3db       %||% 47

        raw_stages       <- attr(td, "stage_results_raw")
        last_t_pae  <- tryCatch({
          ts <- Filter(is_transistor_stage, raw_stages)
          if (length(ts)) tail(ts,1)[[1]]$pae_pct %||% NA else NA
        }, error = function(e) NA)
        last_t_pout <- tryCatch({
          ts <- Filter(is_transistor_stage, raw_stages)
          if (length(ts)) tail(ts,1)[[1]]$pout_dbm %||% NA else NA
        }, error = function(e) NA)

        all_ropt <- sapply(td, function(d) d$ropt$Ropt_ohm %||% NA)
        ropt_mean <- mean(all_ropt, na.rm = TRUE)
        ropt_status <- if (is.na(ropt_mean)) "FAIL" else if (ropt_mean >= 5 && ropt_mean <= 100) "PASS" else if (ropt_mean >= 2 && ropt_mean <= 300) "WARN" else "FAIL"

        pae_diff   <- if (!is.na(last_t_pae)) last_t_pae - pae_target_val else NA
        pae_status <- if (is.na(pae_diff)) "FAIL" else if (abs(pae_diff) <= 5) "PASS" else if (pae_diff >= -15) "WARN" else "FAIL"

        p3db_diff   <- if (!is.na(last_t_pout)) last_t_pout - p3db_spec_val else NA
        p3db_status <- if (is.na(p3db_diff)) "FAIL" else if (abs(p3db_diff) <= 0.5) "PASS" else if (abs(p3db_diff) <= 1.5) "WARN" else "FAIL"

        lines <- c(lines, "",
                   "| Check | Value | Result |",
                   "|-------|-------|--------|",
                   sprintf("| Ropt range | %.1f \u03a9 mean | %s |",
                           ropt_mean, ropt_status),
                   sprintf("| PAE vs target | %.1f%% (target %.0f%%) | %s |",
                           last_t_pae %||% 0, pae_target_val, pae_status),
                   sprintf("| P3dB vs spec | %.1f dBm (spec %.1f dBm) | %s |",
                           last_t_pout %||% 0, p3db_spec_val, p3db_status))
      } else {
        lines <- c(lines, "", "*No data for compliance check.*")
      }

      writeLines(lines, file)
    }
  )

  # ================================================================
  # 8. MAIN PANEL  output$transistor_design_ui
  # ================================================================
  output$transistor_design_ui <- renderUI({
    td <- tryCatch(transistor_design_results(), error = function(e) NULL)

    # ── Top controls (always shown) ──────────────────────────────
    controls <- tags$div(
      style = paste0(
        "background:", CSS_BG, "; border:1px solid ", CSS_BORDER, ";",
        "border-radius:6px; padding:12px; margin-bottom:16px;",
        "display:flex; gap:16px; align-items:flex-end;"
      ),
      div(
        style = "flex:1;",
        selectInput(
          "transistor_topology",
          label = tags$span(style = paste0("color:", CSS_TEXT, "; font-size:12px;"),
                            "PA Topology"),
          choices = c(
            "Doherty Symmetric (6 dB OBO)"   = "doherty_symmetric",
            "Doherty Asymmetric 6 dB"        = "doherty_asymmetric_6dB",
            "Doherty Asymmetric 9 dB"        = "doherty_asymmetric_9dB",
            "Single-Ended Class AB/B"        = "single_ended"
          ),
          selected = input$transistor_topology %||% "doherty_symmetric",
          width    = "100%"
        )
      ),
      div(
        style = "flex:0 0 auto; padding-bottom:4px;",
        tags$small(
          style = paste0("color:", CSS_MUTED, "; display:block; margin-bottom:4px;"),
          "Freq: ",
          if (!is.null(input$spec_frequency))
            sprintf("%.2f GHz", input$spec_frequency / 1000)
          else "—",
          " | Vdd: ",
          if (!is.null(input$spec_supply_voltage))
            sprintf("%.0f V", input$spec_supply_voltage)
          else "—"
        )
      )
    )

    # ── Main tabset ──────────────────────────────────────────────
    tabset <- tabsetPanel(
      id = "transistor_tabs",

      # ── Tab 1: Transistor Specs ─────────────────────────────
      tabPanel(
        title = tagList(icon("microchip"), " Transistor Specs"),
        value = "tab_specs",
        div(
          style = "padding:16px 0;",
          uiOutput("transistor_stage_table"),
          uiOutput("doherty_combiner_panel")
        )
      ),

      # ── Tab 2: Matching Networks ────────────────────────────
      tabPanel(
        title = tagList(icon("project-diagram"), " Matching Networks"),
        value = "tab_matching",
        div(
          style = "padding:16px 0;",
          uiOutput("matching_network_panel")
        )
      ),

      # ── Tab 3: Decision Log ─────────────────────────────────
      tabPanel(
        title = tagList(icon("clipboard-list"), " Decision Log"),
        value = "tab_log",
        div(
          style = "padding:16px 0;",
          uiOutput("design_decision_log")
        )
      ),

      # ── Tab 4: Spec Compliance ──────────────────────────────
      tabPanel(
        title = tagList(icon("check-circle"), " Spec Compliance"),
        value = "tab_compliance",
        div(
          style = "padding:16px 0;",
          uiOutput("spec_validation_table"),
          div(
            style = "margin-top:20px;",
            downloadButton(
              "export_transistor_design",
              tagList(icon("download"), " Export Design Summary"),
              class = "btn-success"
            )
          )
        )
      )
    )

    tagList(controls, tabset)
  })

}
