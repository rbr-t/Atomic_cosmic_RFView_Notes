# ============================================================
# server_guardrails.R
# Server module: Performance Guardrails tab.
#
# Renders:
#   - 4D Design Space bubble plot  (dual axes: PAE right Y, Gain top X)
#   - Gain vs Frequency plot       (click-to-reposition ★ marker)
#   - PAE vs Backoff curves        (click-to-reposition ★)
#   - Reference table              (guardrail summary DT)
#   - Validation result card       (per-device sanity check)
#   - Save to Device Library       (JSON portfolio → canvas palette)
#
# All heavy calculation delegated to calc_guardrails.R
# ============================================================

serverGuardrails <- function(input, output, session, state) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── Helper: load saved device portfolio ─────────────────────
  loadDevicePortfolio <- function(dir = "device_portfolio") {
    if (!dir.exists(dir)) return(list())
    files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
    devices <- lapply(files, function(f) {
      tryCatch(jsonlite::read_json(f, simplifyVector = FALSE), error = function(e) NULL)
    })
    Filter(Negate(is.null), devices)
  }

  # ── Reactive triggers for device library operations ─────────
  rv_lib_refresh <- reactiveVal(0)   # bumped on save, delete, edit
  rv_edit_id     <- reactiveVal(NULL) # stores id of device being edited

  # ── On startup: signal device_lib to push the merged (portfolio + KB) palette ─
  # server_device_lib.R observes state$rv_lib_refresh and pushes the full
  # harmonised list (user portfolio + all KB catalogue devices) to the canvas.
  observe({
    isolate(state$rv_lib_refresh(state$rv_lib_refresh() + 1L))
  })

  # ── Reactive: all saved devices (re-fetched on save/delete/edit) ─
  all_lib_devices <- reactive({
    input$grd_save_device; rv_lib_refresh()  # invalidate on save OR refresh
    loadDevicePortfolio("device_portfolio")
  })

  # ── Device names vector ─────────────────────────────────────────
  lib_device_names <- reactive({
    devs <- all_lib_devices()
    sapply(devs, function(d) d$name %||% d$label %||% "Saved")
  })

  # ── Render the multi-select dropdown ──────────────────────────────
  output$grd_device_lib_select_ui <- renderUI({
    nms <- lib_device_names()
    if (length(nms) == 0) {
      return(tags$p(style = "font-size:11px; color:#888; font-style:italic;",
                    "No saved devices yet."))
    }
    choices <- setNames(seq_along(nms), nms)
    selectInput("grd_lib_overlay_sel",
      label    = NULL,
      choices  = choices,
      selected = NULL,      # none selected by default
      multiple = TRUE,
      selectize = TRUE,
      width    = "100%"
    )
  })

  # Select-all / clear observers
  observeEvent(input$grd_lib_select_all, {
    nms <- lib_device_names()
    if (length(nms) == 0) return()
    updateSelectInput(session, "grd_lib_overlay_sel",
                      selected = as.character(seq_along(nms)))
  })
  observeEvent(input$grd_lib_select_none, {
    updateSelectInput(session, "grd_lib_overlay_sel", selected = character(0))
  })

  # ── Helper: return only selected devices ─────────────────────────
  selected_lib_devices <- reactive({
    devs <- all_lib_devices()
    sel  <- input$grd_lib_overlay_sel
    if (is.null(sel) || length(sel) == 0) return(list())
    idx  <- as.integer(sel)
    idx  <- idx[idx >= 1 & idx <= length(devs)]
    devs[idx]
  })

  # ── Load guardrails once at module init ──────────────────────
  guardrails <- tryCatch(
    loadGuardrails("../config/technology_guardrails.yaml"),
    error = function(e) {
      tryCatch(
        loadGuardrails("config/technology_guardrails.yaml"),
        error = function(e2) { cat("[Guardrails] using embedded fallback\n"); loadGuardrails() }
      )
    }
  )

  # ── Cached data frames (re-computed on tech overlay filter change) ──
  design_space_df <- reactive({
    df  <- buildDesignSpaceData(guardrails)
    sel <- input$grd_tech_overlay
    if (!is.null(sel) && length(sel) > 0) df[df$tech %in% sel, ] else df
  })

  gain_bw_df <- reactive({
    df  <- buildGainBandwidthData(guardrails)
    sel <- input$grd_tech_overlay
    if (!is.null(sel) && length(sel) > 0) df[df$tech %in% sel, ] else df
  })

  pae_bo_df <- reactive({ buildPAEBackoffData(guardrails) })

  # ── User device value helpers ────────────────────────────────
  user_freq  <- reactive({ input$grd_chk_freq    %||% 3.5  })
  user_gain  <- reactive({ input$grd_chk_gain    %||% 15   })
  user_pae   <- reactive({ input$grd_chk_pae     %||% 60   })
  user_pout  <- reactive({ input$grd_chk_pout    %||% 43   })
  user_vdd   <- reactive({ input$grd_chk_vdd     %||% 28   })
  user_tech  <- reactive({ input$grd_tech_select %||% "GaN_SiC" })
  user_pd    <- reactive({
    pd <- input$grd_chk_pdensity %||% 0
    if (pd > 0) return(pd)
    # Fallback: selected technology's typical Pout density (W/mm)
    # Avoids the misleading dBm→W conflation that was used before
    tech <- guardrails$technologies[[user_tech() %||% "GaN_SiC"]]
    tech$pout_density_w_per_mm$typical %||% 5.0
  })

  # ═══════════════════════════════════════════════════════════════
  # PLOT 1 — Technology Design Space (bubble chart)
  # X : Frequency (GHz) — log scale
  # Y : Pout density (W/mm) or Pout (dBm)
  # Bubble size : PAE or Gain
  # Colour : technology
  # Click → repositions ★ marker & updates freq / pout_density inputs
  # ═══════════════════════════════════════════════════════════════
  output$grd_design_space_plot <- renderPlotly({
    df       <- design_space_df()
    req(nrow(df) > 0)

    y_mode   <- input$grd_yaxis_mode  %||% "density"
    sz_mode  <- input$grd_bubble_size %||% "pae"
    tech_sel <- user_tech()

    y_lab  <- if (y_mode == "density") "Pout density (W/mm)" else "Pout (dBm est.)"
    y_title <- if (y_mode == "density") "Pout Density (W/mm)" else "Pout (dBm est.)"
    sz_label <- if (sz_mode == "pae") "Bubble size = PAE (%)" else "Bubble size = Gain (dB)"

    fig <- plot_ly(source = "grd_ds")

    for (tk in unique(df$tech)) {
      sub <- df[df$tech == tk, ]
      idx   <- round(seq(1, nrow(sub), length.out = min(nrow(sub), 15)))
      sub_s <- sub[idx, ]
      col   <- sub_s$color[1]

      y_vals    <- if (y_mode == "density") sub_s$pout_density_typ
                   else 10 * log10(sub_s$pout_density_typ * 1e3)
      sz_vals   <- if (sz_mode == "pae") sub_s$pae_typ_pct else sub_s$gain_db
      opacities <- ifelse(sub_s$in_sweet_spot, 0.85, 0.30)

      # Sweet-spot fill band
      sweet_s <- sub_s[sub_s$in_sweet_spot, ]
      if (nrow(sweet_s) > 2) {
        yhi <- if (y_mode == "density") sweet_s$pout_density_max
               else 10 * log10(sweet_s$pout_density_max * 1e3)
        ylo <- if (y_mode == "density") sweet_s$pout_density_typ * 0.7
               else 10 * log10(sweet_s$pout_density_typ * 0.7 * 1e3)
        fig <- fig %>% add_trace(
          type = "scatter", mode = "lines",
          x = c(sweet_s$freq_ghz, rev(sweet_s$freq_ghz)),
          y = c(yhi, rev(ylo)),
          fill = "toself", fillcolor = paste0(col, "20"),
          line = list(color = "transparent"),
          hoverinfo = "skip", showlegend = FALSE
        )
      }

      # Bubbles
      fig <- fig %>% add_trace(
        type = "scatter", mode = "markers",
        x = sub_s$freq_ghz, y = y_vals,
        name = sub_s$label[1],
        text = paste0(
          "<b>", sub_s$label[1], "</b><br>",
          "f = ", round(sub_s$freq_ghz, 2), " GHz<br>",
          y_lab, ": ", round(y_vals, 2), "<br>",
          "PAE typ: ", round(sub_s$pae_typ_pct, 1), "%<br>",
          "Gain: ", round(sub_s$gain_db, 1), " dB<br>",
          ifelse(sub_s$in_sweet_spot, "<b style='color:#7f7;'>★ Sweet spot</b>",
                 "<span style='color:#888;'>(peripheral)</span>")
        ),
        hoverinfo = "text",
        marker = list(color = col, opacity = opacities,
                      size = pmax(pmin(sz_vals * 0.65, 40), 7),
                      line = list(color = "white", width = 0.8)),
        legendgroup = tk
      )
    }

    # ★ User device marker
    u_freq <- user_freq()
    u_y    <- if (y_mode == "density") user_pd() else user_pout()
    ti     <- guardrails$technologies[[tech_sel]]
    y_unit <- if (y_mode == "density") "W/mm" else "dBm"

    fig <- fig %>% add_trace(
      type = "scatter", mode = "markers+text",
      x = u_freq, y = u_y, name = "Your Device",
      text = "★", textfont = list(size = 14, color = "#ff7f11"),
      textposition = "top right",
      hovertext = paste0(
        "<b>★ Your Device</b><br>Tech: ", ti$label, "<br>",
        "f = ", u_freq, " GHz<br>Y = ", round(u_y, 2), " ", y_unit, "<br>",
        "PAE = ", user_pae(), "%  Gain = ", user_gain(), " dB"
      ),
      hoverinfo = "text",
      marker = list(symbol = "star", size = 22, color = "#ff7f11",
                    line = list(color = "white", width = 1.5))
    )

    # ── Device Library overlay (only selected devices shown as ◆ markers) ───
    lib_devices <- selected_lib_devices()
    for (dev in lib_devices) {
      d_freq  <- dev$frequency_ghz %||% dev$frequency %||% dev$freq_ghz %||% 3.5
      d_pout  <- dev$pout_dbm  %||% dev$pout   %||% 43
      d_pd    <- dev$pout_density_w_per_mm %||% dev$pout_density %||% dev$pd_w_mm %||%
                   (if (d_pout > 20) round(10^((as.numeric(d_pout) - 30) / 10) / 2, 2) else 5)
      d_pae   <- dev$pae_pct   %||% dev$pae    %||% 50
      d_gain  <- dev$gain_db   %||% dev$gain   %||% 15
      d_label <- dev$name      %||% dev$label  %||% "Saved"
      d_y     <- if (y_mode == "density") as.numeric(d_pd) else as.numeric(d_pout)
      fig <- fig %>% add_trace(
        type = "scatter", mode = "markers+text",
        x = as.numeric(d_freq), y = d_y,
        name = paste0("◆ ", d_label),
        text = "◆", textfont = list(size = 11, color = "#00ccff"),
        textposition = "top center",
        hovertext = paste0(
          "<b>◆ ", d_label, "</b> [Library]<br>",
          "f = ", d_freq, " GHz<br>",
          if (y_mode == "density") paste0("Pd = ", round(d_pd, 2), " W/mm<br>")
          else paste0("Pout = ", d_pout, " dBm<br>"),
          "PAE = ", d_pae, "%   Gain = ", d_gain, " dB"
        ),
        hoverinfo = "text",
        marker = list(symbol = "diamond", size = 14, color = "#00ccff",
                      line = list(color = "white", width = 1.5))
      )
    }

    fig %>%
      layout(
        title = list(
          text = paste0("<b>Technology Design Space</b>  —  ", sz_label,
                        "   <span style='font-size:12px;color:#aaa;'>(click to reposition ★)</span>"),
          font = list(color = "#fff", size = 15)
        ),
        paper_bgcolor = "#0b0b0b",
        plot_bgcolor  = "#141414",
        clickmode     = "event",
        xaxis = list(
          title = "Frequency (GHz)",
          type = "log", range = c(-1, 2.48),
          tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"
        ),
        yaxis = list(
          title = y_title,
          tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"
        ),
        legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.5)",
                      x = 0.01, y = 0.99),
        font   = list(color = "#ccc"),
        annotations = list(list(
          x = 0.01, y = -0.12, xref = "paper", yref = "paper",
          text = "<span style='color:#7f7;'>■</span> Solid = sweet spot  <span style='color:#555;'>■</span> Faded = peripheral",
          showarrow = FALSE, font = list(size = 11, color = "#888"), align = "left"
        ))
      ) %>%
      plotly::config(displayModeBar = TRUE) %>%
      event_register("plotly_click")
  })

  # Click on Design Space → reposition ★ + sync input fields
  observeEvent({
    req(isTRUE(input$sidebar_menu == "tech_guardrails"))
    event_data("plotly_click", source = "grd_ds")
  }, {
    click <- event_data("plotly_click", source = "grd_ds")
    if (is.null(click)) return()
    f <- click$x;  y_v <- click$y
    if (!is.null(f) && is.numeric(f) && f > 0)
      updateNumericInput(session, "grd_chk_freq", value = round(f, 2))
    if (!is.null(y_v) && is.numeric(y_v) && y_v > 0) {
      if (isTRUE((input$grd_yaxis_mode %||% "density") == "density"))
        updateNumericInput(session, "grd_chk_pdensity", value = round(y_v, 2))
      else
        updateNumericInput(session, "grd_chk_pout", value = round(y_v, 1))
    }
    showNotification(sprintf("★ moved to %.2f GHz", f %||% 0), type = "message", duration = 2)
  })


  # ═══════════════════════════════════════════════════════════════
  # PLOT 2 — Gain vs Frequency  (click → update freq + gain inputs)
  # ═══════════════════════════════════════════════════════════════
  output$grd_gain_bw_plot <- renderPlotly({
    df  <- gain_bw_df()
    req(nrow(df) > 0)

    show_ft_rule <- isTRUE(input$grd_gain_show_ft_rule)
    fig <- plot_ly(source = "grd_gn")

    for (tk in unique(df$tech)) {
      sub <- df[df$tech == tk & df$in_range, ]
      if (nrow(sub) == 0) next
      col <- sub$color[1]; lbl <- sub$label[1]

      fig <- fig %>%
        add_trace(type = "scatter", mode = "lines",
                  x = c(sub$freq_ghz, rev(sub$freq_ghz)),
                  y = c(sub$gain_max, rev(sub$gain_typ)),
                  fill = "toself", fillcolor = paste0(col, "33"),
                  line = list(color = "transparent"), hoverinfo = "skip", showlegend = FALSE) %>%
        add_trace(type = "scatter", mode = "lines",
                  x = sub$freq_ghz, y = sub$gain_typ, name = lbl,
                  line = list(color = col, width = 2.5),
                  text = paste0("<b>", lbl, "</b><br>f=", round(sub$freq_ghz, 2),
                                " GHz<br>G_typ=", round(sub$gain_typ, 1), " dB"),
                  hoverinfo = "text")
    }

    if (show_ft_rule) {
      f_ref <- exp(seq(log(0.1), log(300), length.out = 200))
      for (ft_v in c(35, 70, 300)) {
        fig <- fig %>% add_trace(
          type = "scatter", mode = "lines", x = f_ref,
          y = pmax(20 * log10(ft_v / f_ref), 0),
          name = paste0("20dB/dec (fT=", ft_v, "GHz)"),
          line = list(color = "#555", width = 1, dash = "dot"), hoverinfo = "skip")
      }
    }

    u_freq <- user_freq(); u_gain <- user_gain()
    fig <- fig %>% add_trace(
      type = "scatter", mode = "markers+text",
      x = u_freq, y = u_gain, name = "Your Device",
      text = "★", textfont = list(size = 14, color = "#ff7f11"),
      textposition = "top right",
      marker = list(symbol = "star", size = 20, color = "#ff7f11",
                    line = list(color = "white", width = 1.5)),
      hovertext = paste0("★ f=", u_freq, " GHz, G=", u_gain, " dB"),
      hoverinfo = "text")

    # ── Device Library overlay ───────────────────────────────────────────────
    lib_devices <- selected_lib_devices()
    for (dev in lib_devices) {
      d_freq  <- dev$frequency_ghz %||% dev$frequency %||% dev$freq_ghz %||% 3.5
      d_gain  <- dev$gain_db  %||% dev$gain  %||% 15
      d_label <- dev$name     %||% dev$label %||% "Saved"
      fig <- fig %>% add_trace(
        type = "scatter", mode = "markers+text",
        x = as.numeric(d_freq), y = as.numeric(d_gain),
        name = paste0("◆ ", d_label),
        text = "◆", textfont = list(size = 11, color = "#00ccff"),
        textposition = "top center",
        hovertext = paste0(
          "<b>◆ ", d_label, "</b> [Library]<br>",
          "f = ", d_freq, " GHz<br>Gain = ", d_gain, " dB"
        ),
        hoverinfo = "text",
        marker = list(symbol = "diamond", size = 14, color = "#00ccff",
                      line = list(color = "white", width = 1.5))
      )
    }

    fig %>% layout(
      title = list(
        text = "<b>Available Gain vs Frequency</b>   <span style='font-size:12px;color:#aaa;'>(click to reposition ★)</span>",
        font = list(color = "#fff", size = 15)),
      paper_bgcolor = "#0b0b0b", plot_bgcolor = "#141414",
      clickmode = "event",
      xaxis = list(title = "Frequency (GHz)", type = "log",
                   tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"),
      yaxis = list(title = "Available Gain (dB)", range = c(0, 38),
                   tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"),
      legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.5)"),
      font = list(color = "#ccc")
    ) %>%
      plotly::config(displayModeBar = TRUE) %>%
      event_register("plotly_click")
  })

  observeEvent({
    req(isTRUE(input$sidebar_menu == "tech_guardrails"))
    event_data("plotly_click", source = "grd_gn")
  }, {
    click <- event_data("plotly_click", source = "grd_gn")
    if (is.null(click)) return()
    f <- click$x; g <- click$y
    if (!is.null(f) && is.numeric(f) && f > 0)
      updateNumericInput(session, "grd_chk_freq", value = round(f, 2))
    if (!is.null(g) && is.numeric(g) && g > 0)
      updateNumericInput(session, "grd_chk_gain", value = round(g, 1))
    showNotification(sprintf("★ f=%.2f GHz, G=%.1f dB", f %||% 0, g %||% 0),
                     type = "message", duration = 2)
  })


  # ═══════════════════════════════════════════════════════════════
  # PLOT 3 — PAE vs Backoff  (click → update backoff + PAE inputs)
  # ═══════════════════════════════════════════════════════════════
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

    fig <- plot_ly(source = "grd_pae")

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

    # ── Device Library overlay ───────────────────────────────────────────────
    lib_devices <- selected_lib_devices()
    for (dev in lib_devices) {
      d_pae   <- dev$pae_pct    %||% dev$pae      %||% 50
      d_bo    <- dev$backoff_db %||% dev$bo_db     %||% dev$par_db %||% 8
      d_label <- dev$name       %||% dev$label     %||% "Saved"
      fig <- fig %>% add_trace(
        type = "scatter", mode = "markers+text",
        x = as.numeric(d_bo), y = as.numeric(d_pae),
        name = paste0("◆ ", d_label),
        text = "◆", textfont = list(size = 11, color = "#00ccff"),
        textposition = "top center",
        hovertext = paste0(
          "<b>◆ ", d_label, "</b> [Library]<br>",
          "BO = ", d_bo, " dB<br>PAE = ", d_pae, "%"
        ),
        hoverinfo = "text",
        marker = list(symbol = "diamond", size = 14, color = "#00ccff",
                      line = list(color = "white", width = 1.5))
      )
    }

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
      title = list(
        text = paste0("<b>PAE vs Output Backoff</b>  — ", tech_info$label,
                      "   <span style='font-size:12px;color:#aaa;'>(click to set ★)</span>"),
        font = list(color = "#fff", size = 15)),
      paper_bgcolor = "#0b0b0b",
      plot_bgcolor  = "#141414",
      clickmode = "event",
      xaxis = list(title = "Output Backoff from P3dB (dB)", autorange = "reversed",
                   tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"),
      yaxis = list(title = "PAE (%)", range = c(0, 85),
                   tickfont = list(color = "#ccc"), gridcolor = "#2a2a2a", color = "#ccc"),
      legend = list(font = list(color = "#ccc"), bgcolor = "rgba(0,0,0,0.5)"),
      font   = list(color = "#ccc"),
      annotations = list(list(
        x = 0.99, y = 0.97, xref = "paper", yref = "paper",
        text = paste0("Base PAE @ P3dB: ", tech_info$pae_pct$typical_p3db, "%  (typ for ", tech_info$label, ")"),
        showarrow = FALSE, font = list(size = 11, color = "#aaa"),
        xanchor = "right"
      ))
    ) %>%
      event_register("plotly_click")
  })

  # Click on PAE plot → update backoff + PAE inputs
  observeEvent({
    req(isTRUE(input$sidebar_menu == "tech_guardrails"))
    event_data("plotly_click", source = "grd_pae")
  }, {
    click <- event_data("plotly_click", source = "grd_pae")
    if (is.null(click)) return()
    bo_v <- click$x;  pae_v <- click$y
    if (!is.null(bo_v)  && is.numeric(bo_v))
      updateNumericInput(session, "grd_pae_pavg_bo", value = round(bo_v, 1))
    if (!is.null(pae_v) && is.numeric(pae_v) && pae_v > 0)
      updateNumericInput(session, "grd_chk_pae", value = round(pae_v, 0))
    showNotification(sprintf("★ PAE=%.0f%% @ BO=%.1f dB", pae_v %||% 0, bo_v %||% 0),
                     type = "message", duration = 2)
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
    # When pd=0 (not explicitly set), use the same density the ★ marker shows
    # so the validation result is always consistent with the design space plot
    if (is.null(pd) || pd == 0) pd <- user_pd()

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
        "ok"      = "var(--c-ok-bg)",
        "warning" = "var(--c-warn-bg)",
        "error"   = "var(--c-err-bg)",
        "var(--s-raised)"
      )
      brd_col <- switch(result$status,
        "ok"      = "var(--c-ok)",
        "warning" = "var(--c-warn)",
        "error"   = "var(--c-err)",
        "var(--bdr-norm)"
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
          div(style = "font-size:12px; color:var(--tx-med);",
            sprintf("Max gain available at %.1f GHz (%s): %.1f dB",
                    result$freq_ghz, result$tech, result$max_gain_available)
          ),
          div(style = "font-size:12px; color:var(--tx-med); margin-top:3px;",
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


  # ═══════════════════════════════════════════════════════════════
  # SAVE TO DEVICE LIBRARY
  # Validates current params, persists JSON, notifies canvas palette
  # ═══════════════════════════════════════════════════════════════
  observeEvent(input$grd_save_device, {
    req(input$grd_save_label)
    safe_label <- trimws(input$grd_save_label)
    if (nchar(safe_label) == 0) {
      showNotification("Please enter a device label.", type = "warning")
      return()
    }

    pd <- input$grd_chk_pdensity %||% 0
    if (pd == 0) pd <- NULL

    validation <- validateDeviceParams(
      tech_key     = input$grd_tech_select,
      freq_ghz     = input$grd_chk_freq,
      gain_db      = input$grd_chk_gain,
      pae_pct      = input$grd_chk_pae,
      pout_dbm     = input$grd_chk_pout,
      vdd          = input$grd_chk_vdd,
      pout_density = pd,
      guardrails   = guardrails
    )

    device <- list(
      id          = paste0("dev_", gsub("[^a-zA-Z0-9]", "_", safe_label), "_",
                           format(Sys.time(), "%Y%m%d%H%M%S")),
      label       = safe_label,
      notes       = trimws(input$grd_save_notes %||% ""),
      technology  = input$grd_tech_select,
      tech_label  = guardrails$technologies[[input$grd_tech_select]]$label,
      freq_ghz    = input$grd_chk_freq,
      gain_db     = input$grd_chk_gain,
      pae_pct     = input$grd_chk_pae,
      pout_dbm    = input$grd_chk_pout,
      vdd         = input$grd_chk_vdd,
      p1db_dbm    = input$grd_chk_pout - 2,
      pout_density_w_per_mm = input$grd_chk_pdensity %||% 0,
      validation_status     = validation$status,
      saved_at    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      canvas_component = list(
        type       = "transistor",
        label      = safe_label,
        technology = input$grd_tech_select,
        gain       = input$grd_chk_gain,
        pout       = input$grd_chk_pout,
        p1db       = input$grd_chk_pout - 2,
        pae        = input$grd_chk_pae,
        vdd        = input$grd_chk_vdd,
        freq       = input$grd_chk_freq,
        biasClass  = "AB"
      )
    )

    portfolio_dir <- "device_portfolio"
    if (!dir.exists(portfolio_dir)) dir.create(portfolio_dir, recursive = TRUE)
    fname <- file.path(portfolio_dir, paste0(device$id, ".json"))
    jsonlite::write_json(device, fname, pretty = TRUE, auto_unbox = TRUE)

    # Signal device_lib to push the merged (portfolio + KB) palette
    isolate(state$rv_lib_refresh(state$rv_lib_refresh() + 1L))

    status_colors <- c(ok = "#27ae60", warning = "#f39c12", error = "#e74c3c")
    sc <- status_colors[[device$validation_status]] %||% "#888"

    output$grd_save_result <- renderUI({
      div(style = "background:var(--c-ok-bg); border-left:4px solid var(--c-ok); padding:8px 10px; border-radius:3px; margin-top:8px;",
          div(style = "color:var(--c-ok); font-size:13px; font-weight:bold;",
              icon("check-circle"), " Saved: ", device$label),
          div(style = paste0("color:", sc, "; font-size:12px; margin-top:3px;"),
              "Guardrails: ", toupper(device$validation_status)),
          div(style = "color:var(--tx-med); font-size:11px; margin-top:4px;",
              "Available in PA Lineup palette under 'Device Library'.")
      )
    })

    showNotification(paste0("Saved '", device$label, "' to Device Library"),
                     type = "message", duration = 4)
  })

  # Render list of saved devices (refreshes on save, delete, or edit)
  output$grd_saved_devices_list <- renderUI({
    input$grd_save_device; rv_lib_refresh()  # dual reactive dependency
    devices <- loadDevicePortfolio("device_portfolio")
    if (length(devices) == 0) {
      return(div(style = "color:var(--tx-med); font-size:12px; padding:6px;",
                 "No devices saved yet."))
    }
    status_colors <- c(ok = "#27ae60", warning = "#f39c12", error = "#e74c3c")
    tags$ul(
      style = "padding-left:0; list-style:none; margin:0;",
      lapply(devices, function(d) {
        sc     <- status_colors[[d$validation_status %||% "ok"]] %||% "#888"
        dev_id <- d$id %||% ""
        safe_label <- gsub("'", "\\\\'", d$label %||% "device")
        tags$li(
          style = paste0("padding:5px 6px; margin-bottom:4px; background:var(--s-raised);",
                         " border-radius:3px; border-left:3px solid ", sc, ";"),
          div(style = "display:flex; align-items:center; justify-content:space-between; gap:6px;",
            div(style = "min-width:0; flex:1;",
              div(style = "color:var(--tx-hi); font-size:12px; font-weight:bold;
                           white-space:nowrap; overflow:hidden; text-overflow:ellipsis;",
                  d$label),
              div(style = "color:var(--tx-med); font-size:11px;",
                  d$tech_label, " · ", d$freq_ghz, " GHz · G=", d$gain_db,
                  " dB · PAE=", d$pae_pct, "% · Pout=", d$pout_dbm, " dBm")
            ),
            div(style = "display:flex; gap:3px; flex-shrink:0;",
              tags$button(
                class = "btn btn-xs btn-default",
                style = "padding:2px 5px; color:var(--tx-med);",
                title = "Edit label / notes",
                onclick = paste0(
                  "Shiny.setInputValue('grd_edit_device','", dev_id,
                  "',{priority:'event'})"),
                HTML('<i class="fa fa-pencil"></i>')
              ),
              tags$button(
                class = "btn btn-xs btn-danger",
                style = "padding:2px 5px;",
                title = "Delete device",
                onclick = paste0(
                  "if(confirm('Delete \\u2018", safe_label,
                  "\\u2019 from the device library?')){",
                  "Shiny.setInputValue('grd_delete_device','", dev_id,
                  "',{priority:'event'});}"),
                HTML('<i class="fa fa-trash"></i>')
              )
            )
          )
        )
      })
    )
  })

  # ── Delete device ────────────────────────────────────────────────
  observeEvent(input$grd_delete_device, {
    req(input$grd_delete_device)
    dev_id <- input$grd_delete_device
    fpath  <- file.path("device_portfolio", paste0(dev_id, ".json"))
    if (file.exists(fpath)) {
      file.remove(fpath)
      rv_lib_refresh(rv_lib_refresh() + 1L)
      isolate(state$rv_lib_refresh(state$rv_lib_refresh() + 1L))
      showNotification("Device removed from library.", type = "warning", duration = 3)
    }
  })

  # ── Open edit modal ──────────────────────────────────────────────
  observeEvent(input$grd_edit_device, {
    req(input$grd_edit_device)
    dev_id <- input$grd_edit_device
    fpath  <- file.path("device_portfolio", paste0(dev_id, ".json"))
    if (!file.exists(fpath)) {
      showNotification("Device file not found.", type = "error"); return()
    }
    d <- jsonlite::read_json(fpath, simplifyVector = FALSE)
    rv_edit_id(dev_id)
    showModal(modalDialog(
      title = tagList(icon("pencil"), " Edit Device"),
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("grd_edit_device_save", "Save Changes",
                     class = "btn-success", icon = icon("save"))
      ),
      textInput("grd_edit_device_label", "Device Label",
                value = d$label %||% "",
                placeholder = "e.g. GaN_3p5G_43dBm"),
      textInput("grd_edit_device_notes", "Notes (optional)",
                value = d$notes %||% "",
                placeholder = "e.g. 3.5 GHz driver stage")
    ))
  })

  # ── Save edits from modal ────────────────────────────────────────
  observeEvent(input$grd_edit_device_save, {
    dev_id <- rv_edit_id()
    req(dev_id, nchar(trimws(input$grd_edit_device_label %||% "")) > 0)
    fpath <- file.path("device_portfolio", paste0(dev_id, ".json"))
    if (!file.exists(fpath)) {
      showNotification("Device file not found.", type = "error"); return()
    }
    d       <- jsonlite::read_json(fpath, simplifyVector = FALSE)
    d$label <- trimws(input$grd_edit_device_label)
    d$notes <- trimws(input$grd_edit_device_notes %||% "")
    jsonlite::write_json(d, fpath, auto_unbox = TRUE, pretty = TRUE)
    removeModal()
    rv_edit_id(NULL)
    rv_lib_refresh(rv_lib_refresh() + 1L)
    isolate(state$rv_lib_refresh(state$rv_lib_refresh() + 1L))
    showNotification(paste0("'", d$label, "' updated."), type = "message", duration = 3)
  })

}
