# ============================================================
# server_guardrails.R
# Server module: Performance Guardrails tab.
#
# Renders:
#   - 4D Design Space bubble plot  (grd_design_space_plot)
#   - Gain vs Frequency plot       (grd_gain_bw_plot)
#   - PAE vs Backoff curves        (grd_pae_bo_plot)
#   - Reference table              (grd_ref_table_dt)
#   - Validation result card       (grd_validation_result)
#
# All heavy calculation is delegated to calc_guardrails.R
# ============================================================

serverGuardrails <- function(input, output, session, state) {

  # ── Load guardrails once at module init ──────────────────────
  guardrails <- tryCatch(
    loadGuardrails("../config/technology_guardrails.yaml"),
    error = function(e) {
      cat("[Guardrails] YAML load error:", e$message, "\n")
      loadGuardrails("config/technology_guardrails.yaml")
    }
  )

  # ── Cached data frames (reactive, but only re-computed on tech filter) ──
  design_space_df <- reactive({
    df <- buildDesignSpaceData(guardrails)
    # Filter to selected technologies
    sel <- input$grd_tech_overlay
    if (!is.null(sel) && length(sel) > 0) df[df$tech %in% sel, ]
    else df
  })

  gain_bw_df <- reactive({
    df <- buildGainBandwidthData(guardrails)
    sel <- input$grd_tech_overlay
    if (!is.null(sel) && length(sel) > 0) df[df$tech %in% sel, ]
    else df
  })

  pae_bo_df <- reactive({
    buildPAEBackoffData(guardrails)
  })

  # ── Helper: user device marker values ───────────────────────
  user_freq  <- reactive({ req(input$grd_chk_freq);  input$grd_chk_freq  })
  user_gain  <- reactive({ req(input$grd_chk_gain);  input$grd_chk_gain  })
  user_pae   <- reactive({ req(input$grd_chk_pae);   input$grd_chk_pae   })
  user_pout  <- reactive({ req(input$grd_chk_pout);  input$grd_chk_pout  })
  user_vdd   <- reactive({ req(input$grd_chk_vdd);   input$grd_chk_vdd   })
  user_tech  <- reactive({ req(input$grd_tech_select); input$grd_tech_select })

  # ── Helper: pout density from pout_dbm (assume single mm gate width) ──
  # We display it as pout_dbm directly on the density plot if density = 0
  user_pout_density <- reactive({
    pd <- input$grd_chk_pdensity
    if (is.null(pd) || pd == 0) {
      # Estimate from pout dBm using typical Ropt for selected tech
      tech <- guardrails$technologies[[user_tech()]]
      vdd_v <- user_vdd()
      # Pout(W) / Pgatewidth(mm).  Assume 1mm gate for estimation.
      pout_w <- 10^(user_pout() / 10) / 1000
      pout_w   # store as W — will be interpreted as W/mm for a 1mm gate
    } else {
      pd
    }
  })

  # ══════════════════════════════════════════════════════════════
  # PLOT 1 — Technology Design Space (4D Bubble)
  # X: Frequency (GHz), Y: Pout density (W/mm) or Pout (dBm)
  # Size: PAE or Gain, Colour: Technology
  # ══════════════════════════════════════════════════════════════
  output$grd_design_space_plot <- renderPlotly({
    df  <- design_space_df()
    req(nrow(df) > 0)

    y_mode   <- input$grd_yaxis_mode    %||% "density"
    sz_mode  <- input$grd_bubble_size   %||% "pae"
    tech_sel <- user_tech()

    # Build one trace per technology
    techs_in_plot <- unique(df$tech)
    fig <- plot_ly()

    marker_size_range <- c(6, 40)   # px for bubble size

    for (tk in techs_in_plot) {
      sub <- df[df$tech == tk, ]
      # Sample to ~15 representative points spread across freq range
      idx   <- round(seq(1, nrow(sub), length.out = min(nrow(sub), 15)))
      sub_s <- sub[idx, ]

      y_vals  <- if (y_mode == "density") sub_s$pout_density_typ else {
        10 * log10(sub_s$pout_density_typ * 1e3)  # rough dBm estimate
      }
      sz_vals <- if (sz_mode == "pae") sub_s$pae_typ_pct else sub_s$gain_db
      sz_lab  <- if (sz_mode == "pae") "PAE (%)" else "Gain (dB)"
      y_lab   <- if (y_mode == "density") "Pout density (W/mm)" else "Pout (dBm)"

      # Sweet spot highlight: use opacity
      opacities <- ifelse(sub_s$in_sweet_spot, 0.85, 0.35)
      col <- sub_s$color[1]

      fig <- fig %>% add_trace(
        type       = "scatter",
        mode       = "markers",
        x          = sub_s$freq_ghz,
        y          = y_vals,
        name       = sub_s$label[1],
        text       = paste0(
          "<b>", sub_s$label[1], "</b><br>",
          "Freq: ", round(sub_s$freq_ghz, 2), " GHz<br>",
          y_lab, ": ", round(y_vals, 2), "<br>",
          "PAE typ: ", round(sub_s$pae_typ_pct, 1), "%<br>",
          "Gain: ", round(sub_s$gain_db, 1), " dB<br>",
          if (sub_s$in_sweet_spot[1]) "<b>★ Sweet spot</b>" else "(outside sweet spot)"
        ),
        hoverinfo  = "text",
        marker     = list(
          color   = col,
          opacity = opacities,
          size    = pmax(pmin(sz_vals * 0.65, 40), 6),  # scale PAE% → px
          line    = list(color = "white", width = 0.8),
          symbol  = "circle"
        )
      )
    }

    # ── User device marker ──────────────────────────────────────
    u_freq  <- user_freq()
    u_pae   <- user_pae()
    u_gain  <- user_gain()
    u_pd    <- user_pout_density()
    tech_info <- guardrails$technologies[[tech_sel]]

    u_y <- if (y_mode == "density") u_pd else user_pout()
    u_sz <- if (sz_mode == "pae") u_pae else u_gain

    fig <- fig %>% add_trace(
      type      = "scatter",
      mode      = "markers+text",
      x         = u_freq,
      y         = u_y,
      name      = "Your Device",
      text      = "★",
      textposition = "middle center",
      hovertext = paste0(
        "<b>★ Your Device</b><br>",
        "Tech: ", tech_info$label, "<br>",
        "Freq: ", u_freq, " GHz<br>",
        y_lab, ": ", round(u_y, 2), "<br>",
        "PAE: ", u_pae, "%<br>",
        "Gain: ", u_gain, " dB"
      ),
      hoverinfo = "text",
      marker    = list(
        symbol = "star",
        size   = 24,
        color  = "white",
        line   = list(color = "#ff7f11", width = 2)
      )
    )

    y_lab_full <- if (y_mode == "density") "Pout Density (W/mm)" else "Pout (dBm)"
    sz_lab_full <- if (sz_mode == "pae") "Bubble size = PAE (%)" else "Bubble size = Gain (dB)"

    fig %>% layout(
      title     = list(text = paste0("<b>Technology Design Space</b>  —  ", sz_lab_full),
                       font = list(color = "#fff")),
      paper_bgcolor = "#0b0b0b",
      plot_bgcolor  = "#141414",
      xaxis = list(
        title      = "Frequency (GHz)",
        type       = "log",
        tickfont   = list(color = "#ccc"),
        gridcolor  = "#333",
        color      = "#ccc"
      ),
      yaxis = list(
        title    = y_lab_full,
        tickfont = list(color = "#ccc"),
        gridcolor = "#333",
        color    = "#ccc"
      ),
      legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.4)"),
      font   = list(color = "#ccc"),
      annotations = list(list(
        x = 0.01, y = -0.12, xref = "paper", yref = "paper",
        text = "Solid opacity = sweet spot  |  Faded = peripheral operating range  |  ★ = your device",
        showarrow = FALSE, font = list(size = 11, color = "#888")
      ))
    )
  })


  # ══════════════════════════════════════════════════════════════
  # PLOT 2 — Gain vs Frequency (bandwidth envelope)
  # ══════════════════════════════════════════════════════════════
  output$grd_gain_bw_plot <- renderPlotly({
    df  <- gain_bw_df()
    req(nrow(df) > 0)

    show_ft_rule <- isTRUE(input$grd_gain_show_ft_rule)
    fig <- plot_ly()

    techs_in_plot <- unique(df$tech)

    for (tk in techs_in_plot) {
      sub <- df[df$tech == tk & df$in_range, ]
      if (nrow(sub) == 0) next
      col <- sub$color[1]
      lbl <- sub$label[1]

      # Shaded region between gain_typ and gain_max
      fig <- fig %>% add_trace(
        type = "scatter", mode = "lines",
        x    = c(sub$freq_ghz, rev(sub$freq_ghz)),
        y    = c(sub$gain_max, rev(sub$gain_typ)),
        name = paste(lbl, "range"),
        fill = "toself",
        fillcolor = paste0(col, "33"),   # ~20% opacity hex
        line      = list(color = "transparent"),
        hoverinfo = "skip",
        showlegend = FALSE
      )

      # Typical gain line
      fig <- fig %>% add_trace(
        type = "scatter", mode = "lines",
        x    = sub$freq_ghz,
        y    = sub$gain_typ,
        name = lbl,
        line = list(color = col, width = 2.5),
        text = paste0("<b>", lbl, "</b><br>",
                      "f=", round(sub$freq_ghz, 2), " GHz<br>",
                      "G_typ=", round(sub$gain_typ, 1), " dB"),
        hoverinfo = "text"
      )
    }

    # 20 dB/decade reference
    if (show_ft_rule) {
      f_ref <- exp(seq(log(0.1), log(300), length.out = 200))
      for (ft_val in c(35, 70, 300)) {
        fig <- fig %>% add_trace(
          type = "scatter", mode = "lines",
          x    = f_ref,
          y    = pmax(20 * log10(ft_val / f_ref), 0),
          name = paste0("20dB/dec (fT=", ft_val, "GHz)"),
          line = list(color = "#555", width = 1, dash = "dot"),
          hoverinfo = "skip"
        )
      }
    }

    # User design point
    u_freq <- user_freq()
    u_gain <- user_gain()
    fig <- fig %>% add_trace(
      type = "scatter", mode = "markers+text",
      x    = u_freq, y = u_gain,
      name = "Your Device",
      text = "★",
      textposition = "top center",
      marker   = list(symbol = "star", size = 20, color = "white",
                      line = list(color = "#ff7f11", width = 2)),
      hovertext = paste0("★ Your Device<br>f=", u_freq, " GHz, G=", u_gain, " dB"),
      hoverinfo = "text"
    )

    fig %>% layout(
      title  = list(text = "<b>Available Gain vs Frequency</b>  (fT/f model + shaded range)",
                    font = list(color = "#fff")),
      paper_bgcolor = "#0b0b0b",
      plot_bgcolor  = "#141414",
      xaxis  = list(title = "Frequency (GHz)", type = "log",
                    tickfont = list(color = "#ccc"), gridcolor = "#333", color = "#ccc"),
      yaxis  = list(title = "Available Gain (dB)", range = c(0, 38),
                    tickfont = list(color = "#ccc"), gridcolor = "#333", color = "#ccc"),
      legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.4)"),
      font   = list(color = "#ccc")
    )
  })


  # ══════════════════════════════════════════════════════════════
  # PLOT 3 — PAE vs Backoff
  # ══════════════════════════════════════════════════════════════
  output$grd_pae_bo_plot <- renderPlotly({
    df_all   <- pae_bo_df()
    req(nrow(df_all) > 0)

    tech_sel <- user_tech()
    classes  <- input$grd_pae_classes %||% c("AB", "Doherty", "B")
    op_bo    <- input$grd_pae_pavg_bo %||% 8

    # Filter to selected tech and classes
    df <- df_all[df_all$tech == tech_sel & df_all$pa_class %in% classes, ]
    if (nrow(df) == 0) {
      df <- df_all[df_all$tech == tech_sel, ]
    }

    tech_info <- guardrails$technologies[[tech_sel]]
    base_color <- tech_info$color %||% "#70AD47"

    # Colour palette per class (diverging from tech base colour)
    class_colors <- c(
      "A"       = "#e74c3c",
      "AB"      = "#f39c12",
      "B"       = "#27ae60",
      "Doherty" = "#3498db",
      "F"       = "#9b59b6"
    )

    fig <- plot_ly()

    for (cls in classes) {
      sub <- df[df$pa_class == cls, ]
      if (nrow(sub) == 0) next
      col <- class_colors[[cls]] %||% base_color

      fig <- fig %>% add_trace(
        type = "scatter", mode = "lines",
        x    = sub$backoff_db,
        y    = sub$pae_pct,
        name = paste0("Class ", cls),
        line = list(color = col, width = 2.5),
        text = paste0("<b>Class ", cls, "</b><br>",
                      "BO: ", round(sub$backoff_db, 1), " dB<br>",
                      "PAE: ", round(sub$pae_pct, 1), "%"),
        hoverinfo = "text"
      )
    }

    # Vertical line at user's operating backoff
    u_pae <- user_pae()
    fig <- fig %>%
      add_trace(
        type = "scatter", mode = "lines",
        x = c(op_bo, op_bo), y = c(0, 85),
        name = paste0("Your BO (", op_bo, " dB)"),
        line = list(color = "#ff7f11", width = 1.5, dash = "dashdot"),
        hoverinfo = "skip"
      ) %>%
      add_trace(
        type = "scatter", mode = "markers+text",
        x    = op_bo, y = u_pae,
        name = "Your PAE",
        text = paste0("★ ", u_pae, "%"),
        textposition = "top right",
        marker = list(symbol = "star", size = 20, color = "white",
                      line = list(color = "#ff7f11", width = 2)),
        hovertext = paste0("★ Your Device<br>BO=", op_bo, " dB, PAE=", u_pae, "%"),
        hoverinfo = "text"
      )

    # Theoretical Class-B ceiling line
    bo_seq <- seq(0, 16, by = 0.25)
    pae_b_ceil <- 78.5 * sqrt(10^(-bo_seq / 10))
    fig <- fig %>% add_trace(
      type = "scatter", mode = "lines",
      x = bo_seq, y = pae_b_ceil,
      name = "Class-B ceiling (78.5%·√BO)",
      line = list(color = "#555", width = 1, dash = "dot"),
      hoverinfo = "skip"
    )

    fig %>% layout(
      title  = list(
        text = paste0("<b>PAE vs Output Backoff</b>  — ", tech_info$label),
        font = list(color = "#fff")),
      paper_bgcolor = "#0b0b0b",
      plot_bgcolor  = "#141414",
      xaxis = list(title = "Output Backoff from P3dB (dB)", autorange = "reversed",
                   tickfont = list(color = "#ccc"), gridcolor = "#333", color = "#ccc"),
      yaxis = list(title = "PAE (%)", range = c(0, 85),
                   tickfont = list(color = "#ccc"), gridcolor = "#333", color = "#ccc"),
      legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.4)"),
      font   = list(color = "#ccc"),
      annotations = list(list(
        x = 0.99, y = 0.97, xref = "paper", yref = "paper",
        text = paste0("Base PAE @ P3dB: ", tech_info$pae_pct$typical_p3db, "%  (typ for ", tech_info$label, ")"),
        showarrow = FALSE, font = list(size = 11, color = "#aaa"),
        xanchor = "right"
      ))
    )
  })


  # ══════════════════════════════════════════════════════════════
  # TABLE — Guardrail reference summary
  # ══════════════════════════════════════════════════════════════
  output$grd_ref_table_dt <- renderDT({
    df <- buildGuardrailSummaryTable(guardrails)
    datatable(
      df,
      rownames   = FALSE,
      options    = list(
        pageLength = 10,
        dom        = "t",
        scrollX    = TRUE,
        columnDefs = list(list(className = "dt-center", targets = "_all"))
      ),
      class = "table table-striped table-bordered table-sm"
    ) %>%
      formatStyle(
        "Technology",
        fontWeight = "bold"
      ) %>%
      formatStyle(
        "PAE P3dB max (%)",
        background = styleColorBar(c(0, 80), "#70AD47"),
        backgroundSize = "98% 60%",
        backgroundRepeat = "no-repeat",
        backgroundPosition = "center"
      )
  })


  # ══════════════════════════════════════════════════════════════
  # VALIDATION RESULT CARD
  # ══════════════════════════════════════════════════════════════
  observeEvent(input$grd_run_check, {
    req(input$grd_tech_select, input$grd_chk_freq, input$grd_chk_gain,
        input$grd_chk_pae, input$grd_chk_pout, input$grd_chk_vdd)

    pd <- input$grd_chk_pdensity
    if (is.null(pd) || pd == 0) pd <- NULL

    result <- validateDeviceParams(
      tech_key    = input$grd_tech_select,
      freq_ghz    = input$grd_chk_freq,
      gain_db     = input$grd_chk_gain,
      pae_pct     = input$grd_chk_pae,
      pout_dbm    = input$grd_chk_pout,
      vdd         = input$grd_chk_vdd,
      pout_density = pd,
      guardrails  = guardrails
    )

    output$grd_validation_result <- renderUI({
      icon_sym   <- switch(result$status,
        "ok"      = icon("check-circle"),
        "warning" = icon("exclamation-triangle"),
        "error"   = icon("times-circle"),
        icon("question-circle")
      )
      bg_col <- switch(result$status,
        "ok"      = "#1a3a1a",
        "warning" = "#3a300a",
        "error"   = "#3a0a0a",
        "#1e1e2e"
      )
      brd_col <- switch(result$status,
        "ok"      = "#27ae60",
        "warning" = "#f39c12",
        "error"   = "#e74c3c",
        "#555"
      )
      status_lbl <- switch(result$status,
        "ok"      = "PASS — Within Guardrails",
        "warning" = "WARNING — Stretching the Limits",
        "error"   = "FAIL — Violates Physics",
        "UNKNOWN"
      )

      tagList(
        div(
          style = paste0("background:", bg_col, "; border-left:4px solid ", brd_col,
                         "; padding:10px 12px; border-radius:3px; margin-top:10px;"),
          div(style = paste0("color:", brd_col, "; font-weight:bold; font-size:13px; margin-bottom:6px;"),
            icon_sym, " ", status_lbl
          ),
          div(style = "font-size:12px; color:#bbb;",
            sprintf("Max gain available at %.1f GHz (%s): %.1f dB",
                    result$freq_ghz, result$tech, result$max_gain_available)
          ),
          div(style = "font-size:12px; color:#bbb; margin-top:3px;",
            sprintf("Best-practice PAE limit (%s): %.1f%%",
                    result$tech, result$pae_max_practical)
          ),
          if (length(result$errors) > 0)
            div(style = "margin-top:8px;",
              lapply(result$errors, function(e)
                div(style = "color:#e74c3c; font-size:12px; margin-top:3px;",
                    icon("times"), " ", e)
              )
            ),
          if (length(result$warnings) > 0)
            div(style = "margin-top:8px;",
              lapply(result$warnings, function(w)
                div(style = "color:#f39c12; font-size:12px; margin-top:3px;",
                    icon("exclamation-triangle"), " ", w)
              )
            )
        )
      )
    })
  })

}
