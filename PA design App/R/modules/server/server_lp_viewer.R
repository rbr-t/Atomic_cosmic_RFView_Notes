# =============================================================================
# server_lp_viewer.R
# Load Pull Viewer — server module for the PA Design App.
#
# Handles:
#   · Parsing LP files (delegates to lp_parsers.R)
#   · Smith Chart with Pout/PAE/Gain/DE contour overlays
#   · XY performance plots
#   · Nose plot (PAE vs Pout)
#   · Tabular Ppeak / Pavg summary (DT)
#   · Multi-device comparison plot
#   · HTML and CSV report download handlers
# =============================================================================

# ── Module-level helper: Smith Chart grid ────────────────────────────────────
# Defined at module file scope so it is available as a plain function
# in the shared R session (sourced by server.R before server() is called).
build_smith_grid <- function() {
  GRID   <- "rgba(60,100,70,0.50)"
  GRID_H <- "rgba(100,170,110,0.80)"   # r=0,1 / x=±1 highlighted
  n      <- 300
  theta  <- seq(0, 2 * pi, length.out = n)
  traces <- list()

  # Unit circle
  traces[[length(traces) + 1]] <- list(
    x    = cos(theta),
    y    = sin(theta),
    line = list(color = "rgba(190,200,190,0.75)", width = 1.6),
    name = "|Γ|=1"
  )
  # Real axis
  traces[[length(traces) + 1]] <- list(
    x    = c(-1, 1), y = c(0, 0),
    line = list(color = "rgba(140,140,140,0.40)", width = 0.8),
    name = "real_ax"
  )
  # Constant-R circles
  for (r in c(0, 0.2, 0.5, 1, 2, 5, 10)) {
    cx  <- r / (1 + r)
    rad <- 1 / (1 + r)
    col <- if (r %in% c(0, 1)) GRID_H else GRID
    lw  <- if (r %in% c(0, 1)) 1.0    else 0.60
    traces[[length(traces) + 1]] <- list(
      x    = cx + rad * cos(theta),
      y    =      rad * sin(theta),
      line = list(color = col, width = lw),
      name = paste0("R=", r)
    )
  }
  # Constant-X arcs (clipped to |Γ| ≤ 1)
  for (xv in c(0.2, 0.5, 1, 2, 5, 10,
               -0.2, -0.5, -1, -2, -5, -10)) {
    cx  <- 1; cy <- 1 / xv; rad <- 1 / abs(xv)
    px  <- cx + rad * cos(theta)
    py  <- cy + rad * sin(theta)
    out <- (px^2 + py^2) > 1.0005
    px[out] <- NA; py[out] <- NA
    col <- if (abs(xv) == 1) GRID_H else GRID
    lw  <- if (abs(xv) == 1) 1.0    else 0.60
    traces[[length(traces) + 1]] <- list(
      x = px, y = py,
      line = list(color = col, width = lw),
      name = paste0("X=", xv)
    )
  }
  traces
}

# ── Dark Smith Chart base layout ─────────────────────────────────────────────
.smith_layout <- function(title_txt = "Smith Chart",
                          xl = "Real(\u0393)", yl = "Imag(\u0393)") {
  list(
    paper_bgcolor = "#1b1b2b",
    plot_bgcolor  = "#1b1b2b",
    xaxis = list(
      title       = xl, range = c(-1.25, 1.25),
      zeroline    = FALSE, showgrid = FALSE,
      color       = "#aaa", tickfont = list(color = "#aaa"),
      scaleanchor = "y",    scaleratio = 1
    ),
    yaxis = list(
      title    = yl, range = c(-1.25, 1.25),
      zeroline = FALSE, showgrid = FALSE,
      color    = "#aaa", tickfont = list(color = "#aaa")
    ),
    title  = list(text = title_txt,
                  font = list(color = "#eee", size = 14)),
    font   = list(color = "#aaa"),
    legend = list(font = list(color = "#aaa"),
                  bgcolor = "rgba(0,0,0,0.30)",
                  x = 1.02, y = 1),
    margin = list(l = 50, r = 10, t = 50, b = 50)
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Main module function
# ─────────────────────────────────────────────────────────────────────────────
serverLpViewer <- function(input, output, session, state) {

  # ── Internal state ─────────────────────────────────────────────────────────
  lp_datasets <- reactiveVal(list())   # named list: id → parsed result
  lp_log      <- reactiveVal(character())

  # ── Palette ────────────────────────────────────────────────────────────────
  PALETTE <- c("#ff7f11", "#1f77b4", "#2ca02c", "#d62728",
               "#9467bd", "#8c564b", "#e377c2", "#17becf")

  # ── Parse on button click ──────────────────────────────────────────────────
  observeEvent(input$lp_parse_btn, {
    req(input$lp_upload)
    fmt     <- input$lp_format_override %||% "auto"
    current <- lp_datasets()
    log     <- character()

    for (i in seq_len(nrow(input$lp_upload))) {
      fpath <- input$lp_upload$datapath[i]
      fname <- input$lp_upload$name[i]
      log   <- c(log, paste0("[", i, "] Parsing: ", fname, " ..."))

      result          <- parse_lp_file(fpath, format_override = fmt)
      result$filename <- fname          # preserve user-facing name

      if (isTRUE(result$success)) {
        npts <- nrow(result$points)
        log  <- c(log,
          sprintf("    OK  (%s)  %d measurement points parsed", result$format, npts))
      } else {
        log <- c(log, paste0("    ERROR: ", result$error))
      }

      id            <- make.names(fname, unique = FALSE)
      current[[id]] <- result
    }

    lp_datasets(current)
    lp_log(c(log, "",
             paste0("─── Total datasets in memory: ", length(current), " ───")))
  })

  # ── Parse log output ───────────────────────────────────────────────────────
  output$lp_parse_log <- renderText({
    lg <- lp_log()
    if (length(lg) == 0)
      "No files parsed yet.\nUpload one or more LP files and click 'Parse file(s)'."
    else
      paste(lg, collapse = "\n")
  })

  # ── Metadata preview ───────────────────────────────────────────────────────
  output$lp_meta_preview <- renderText({
    ds <- lp_datasets()
    if (length(ds) == 0) return("(no datasets)")
    lines <- character()
    for (id in names(ds)) {
      r     <- ds[[id]]
      lines <- c(lines, paste0("=== ", r$filename,
                               "  [", r$format, "] ==="))
      if (length(r$meta) > 0) {
        for (nm in names(r$meta))
          lines <- c(lines, sprintf("  %-18s %s", nm, r$meta[[nm]]))
      }
      if (!is.null(r$points) && nrow(r$points) > 0) {
        avail <- names(r$points)[
          sapply(r$points, function(col) !all(is.na(col)))]
        lines <- c(lines, paste0("  Available cols: ",
                                 paste(avail, collapse = ", ")))
      }
      lines <- c(lines, "")
    }
    paste(lines, collapse = "\n")
  })

  # ── Dataset list widget (Upload tab) ──────────────────────────────────────
  output$lp_dataset_list <- renderUI({
    ds <- lp_datasets()
    if (length(ds) == 0)
      return(p(style = "color:#888; font-size:12px;", "No datasets loaded."))

    tagList(lapply(names(ds), function(id) {
      r          <- ds[[id]]
      ok         <- isTRUE(r$success)
      status_col <- if (ok) "#2ca02c" else "#d62728"
      status_txt <- if (ok) paste0("OK \u00b7 ", nrow(r$points), " pts") else "Failed"
      freq_str   <- r$meta[["freq_ghz"]] %||% "?"
      # Escape single-quotes so the JS string literal is safe
      safe_id    <- gsub("'", "\\\\'", id)

      div(style = paste0("padding:5px 0; border-bottom:1px solid #2a2a3a;",
                         " display:flex; align-items:center; gap:6px;"),
        div(style = paste0("width:8px; height:8px; border-radius:50%;",
                           " background:", status_col, "; flex-shrink:0;")),
        div(style = "flex:1 1 auto; overflow:hidden; min-width:0;",
          tags$strong(style = "color:#ddd; font-size:12px;", r$filename),
          br(),
          tags$small(style = "color:#888;",
            r$format, " \u00b7 freq: ", freq_str, " GHz")),
        div(style = paste0("color:", status_col,
                           "; font-size:11px; flex-shrink:0; margin-right:2px;"),
          status_txt),
        tags$button(
          class   = "btn btn-xs",
          style   = paste0("background:transparent; border:1px solid #5a2a2a;",
                           " color:#e77; padding:1px 6px; font-size:12px;",
                           " line-height:1.4; flex-shrink:0; cursor:pointer;"),
          title   = "Remove this dataset",
          onclick = sprintf(
            "Shiny.setInputValue('lp_del_trigger','%s',{priority:'event'});",
            safe_id),
          HTML("&times;")
        )
      )
    }))
  })

  # ── Per-row delete ─────────────────────────────────────────────────────────
  observeEvent(input$lp_del_trigger, {
    del_id  <- input$lp_del_trigger
    current <- lp_datasets()
    if (!del_id %in% names(current)) return()
    fname   <- current[[del_id]]$filename
    current[[del_id]] <- NULL
    lp_datasets(current)
    lp_log(c(lp_log(),
      paste0("Removed dataset: ", fname),
      paste0("\u2500\u2500\u2500 Total datasets in memory: ",
             length(current), " \u2500\u2500\u2500")))
  })

  # ── Clear all datasets ─────────────────────────────────────────────────────
  observeEvent(input$lp_clear_all_btn, {
    lp_datasets(list())
    lp_log(character())
  })

  # ── Dataset selector helper ─────────────────────────────────────────────
  .dataset_choices <- reactive({
    ds <- lp_datasets()
    if (length(ds) == 0) return(character(0))
    setNames(names(ds), sapply(ds, `[[`, "filename"))
  })

  .make_selector <- function(output_id, label = "Dataset",
                             multiple = FALSE) {
    output[[output_id]] <- renderUI({
      ch <- .dataset_choices()
      if (length(ch) == 0)
        return(p(style = "color:#888; font-size:12px;",
                 "Load datasets first."))
      if (multiple)
        checkboxGroupInput(output_id, label, choices = ch, selected = ch[1])
      else
        selectInput(output_id, label, choices = ch, selected = ch[1])
    })
  }

  .make_selector("lp_dataset_selector",        "Dataset(s)", TRUE)
  .make_selector("lp_xy_dataset_selector",     "Dataset",    FALSE)
  .make_selector("lp_nose_dataset_selector",   "Dataset",    FALSE)
  .make_selector("lp_table_dataset_selector",  "Dataset",    FALSE)
  .make_selector("lp_compare_selector",        "Dataset(s)", TRUE)

  # ── Helper: pull normalised data.frame for a dataset id ─────────────────
  .get_df <- function(id) {
    ds <- lp_datasets()
    if (is.null(id) || length(id) == 0 || !id %in% names(ds)) return(NULL)
    r  <- ds[[id]]
    if (!isTRUE(r$success) || is.null(r$points) || nrow(r$points) == 0)
      return(NULL)
    r$points
  }

  # ── Smith Chart with LP contours ──────────────────────────────────────────
  output$lp_smith_plot <- renderPlotly({
    ds       <- lp_datasets()
    sel_ids  <- input$lp_sel_smith
    pull     <- input$lp_pull_type    %||% "load"
    vars     <- input$lp_contour_vars
    n_lev    <- input$lp_contour_levels %||% 6
    show_pae <- isTRUE(input$lp_show_max_pae)
    show_po  <- isTRUE(input$lp_show_max_pout)

    grid <- build_smith_grid()
    p    <- plot_ly()

    for (tr in grid) {
      p <- p %>% add_trace(
        type = "scatter", mode = "lines",
        x = tr$x, y = tr$y, line = tr$line,
        hoverinfo = "none", showlegend = FALSE, name = tr$name
      )
    }

    var_meta <- list(
      pout   = list(col = "pout_dbm", label = "Pout (dBm)", color = "#ff7f11"),
      pae    = list(col = "pae_pct",  label = "PAE (%)",    color = "#1f77b4"),
      de     = list(col = "de_pct",   label = "DE (%)",     color = "#2ca02c"),
      gain   = list(col = "gain_db",  label = "Gain (dB)",  color = "#9467bd"),
      pdc    = list(col = "pdc_w",    label = "Pdc (W)",    color = "#d62728"),
      pout_w = list(col = "pout_w",   label = "Pout (W)",   color = "#ffaa44")
    )

    if (length(sel_ids) > 0 && length(vars) > 0) {
      for (id in sel_ids) {
        df <- .get_df(id)
        if (is.null(df)) next

        xv_all <- if (pull == "load") df$gl_r else df$gs_r
        yv_all <- if (pull == "load") df$gl_i else df$gs_i
        if (is.null(xv_all) || all(is.na(xv_all))) next

        fname <- ds[[id]]$filename

        for (v in vars) {
          vm  <- var_meta[[v]]
          if (is.null(vm) || !vm$col %in% names(df)) next
          zv_all <- df[[vm$col]]

          ok <- !is.na(xv_all) & !is.na(yv_all) & !is.na(zv_all) &
                (xv_all^2 + yv_all^2) <= 1.02
          xv <- xv_all[ok]; yv <- yv_all[ok]; zv <- zv_all[ok]
          if (length(xv) < 4) next

          interp_ok <- FALSE
          if (requireNamespace("akima", quietly = TRUE) && length(xv) >= 6) {
            tryCatch({
              nx <- 50; ny <- 50
              xi <- seq(min(xv) - 0.02, max(xv) + 0.02, length.out = nx)
              yi <- seq(min(yv) - 0.02, max(yv) + 0.02, length.out = ny)

              # akima requires unique-ish (x,y) pairs
              xy_key <- paste(round(xv, 4), round(yv, 4))
              dup    <- duplicated(xy_key)
              res    <- akima::interp(xv[!dup], yv[!dup], zv[!dup],
                                      xo = xi, yo = yi,
                                      linear = TRUE, extrap = FALSE)
              zm    <- res$z
              # Mask outside unit circle
              for (ii in seq_along(xi))
                for (jj in seq_along(yi))
                  if (!is.finite(zm[ii, jj]) ||
                      xi[ii]^2 + yi[jj]^2 > 1.005) zm[ii, jj] <- NA

              p <- p %>% add_contour(
                x          = xi, y = yi, z = t(zm),
                ncontours  = as.integer(n_lev),
                showscale  = FALSE,
                colorscale = list(c(0, vm$color), c(1, vm$color)),
                contours   = list(coloring = "lines",
                                  showlabels = TRUE,
                                  labelfont  = list(color = vm$color,
                                                    size  = 9)),
                line       = list(color = vm$color, width = 1.2),
                name       = paste0(vm$label, " [", fname, "]"),
                showlegend = TRUE
              )
              interp_ok <- TRUE
            }, error = function(e) NULL)
          }

          if (!interp_ok) {
            # Fallback: scatter with coloured size markers
            p <- p %>% add_trace(
              type      = "scatter",
              mode      = "markers",
              x         = xv, y = yv,
              marker    = list(
                color     = zv,
                colorscale = "Viridis",
                size      = 7,
                showscale = TRUE,
                colorbar  = list(title = vm$label,
                                 tickfont = list(color = "#aaa"),
                                 x = 1.15)
              ),
              hovertext = sprintf("%s: %.2f", vm$label, zv),
              hoverinfo = "text",
              name      = paste0(vm$label, " [", fname, "]"),
              showlegend = TRUE
            )
          }

          # Max markers
          if (show_po && v == "pout") {
            best <- which.max(zv)
            p <- p %>% add_trace(type = "scatter", mode = "markers+text",
              x = xv[best], y = yv[best],
              text = sprintf("Pout=%.1f", zv[best]),
              textposition = "top right",
              marker = list(color = "#ff7f11", size = 14, symbol = "star",
                            line = list(color = "white", width = 1.5)),
              name = "Max Pout", showlegend = FALSE)
          }
          if (show_pae && v == "pae") {
            best <- which.max(zv)
            p <- p %>% add_trace(type = "scatter", mode = "markers+text",
              x = xv[best], y = yv[best],
              text = sprintf("PAE=%.1f%%", zv[best]),
              textposition = "top right",
              marker = list(color = "#1f77b4", size = 14, symbol = "diamond",
                            line = list(color = "white", width = 1.5)),
              name = "Max PAE", showlegend = FALSE)
          }
        } # vars loop
      } # dataset loop
    }

    p %>% layout(do.call(.smith_layout, list(
      title_txt = paste0(
        if (pull == "load") "Load Pull" else "Source Pull",
        " \u2014 Smith Chart Contours"),
      xl = paste0("Real(\u0393_", if (pull == "load") "L" else "S", ")"),
      yl = paste0("Imag(\u0393_", if (pull == "load") "L" else "S", ")")
    )))
  })

  # ── XY Performance Plot ────────────────────────────────────────────────────
  output$lp_xy_plot <- renderPlotly({
    id     <- input$lp_sel_xy
    df     <- .get_df(id)
    y_vars <- input$lp_xy_y_vars
    x_var  <- input$lp_xy_x_var %||% "pin_dbm"

    if (is.null(df) || length(y_vars) == 0 || !x_var %in% names(df)) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = "No data — select a dataset",
                     font = list(color = "#aaa"))
      ))
    }

    xv <- df[[x_var]]
    p  <- plot_ly()

    for (i in seq_along(y_vars)) {
      v  <- y_vars[i]
      if (!v %in% names(df)) next
      yv <- df[[v]]
      ok <- !is.na(xv) & !is.na(yv)
      p  <- p %>% add_trace(
        type   = "scatter",
        mode   = "lines+markers",
        x      = xv[ok], y  = yv[ok],
        name   = gsub("_", " ", v),
        line   = list(color = PALETTE[(i - 1) %% length(PALETTE) + 1]),
        marker = list(color = PALETTE[(i - 1) %% length(PALETTE) + 1],
                      size = 5)
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis  = list(title = gsub("_", " ", x_var), color = "#aaa",
                    showgrid = TRUE,
                    gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = "Performance", color = "#aaa",
                    showgrid = TRUE,
                    gridcolor = "rgba(100,100,100,0.25)"),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "XY Performance Plot",
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa")
    )
  })

  # ── Nose Plot (PAE vs Pout) ────────────────────────────────────────────────
  output$lp_nose_plot <- renderPlotly({
    id  <- input$lp_sel_nose
    df  <- .get_df(id)

    use_watts <- isTRUE(input$lp_nose_pout_unit == "w")
    x_col     <- if (use_watts) "pout_w" else "pout_dbm"
    x_label   <- if (use_watts) "Pout (W)" else "Pout (dBm)"
    x_fmt     <- if (use_watts) "%.4f W" else "%.1f dBm"

    if (is.null(df) || !all(c(x_col, "pae_pct") %in% names(df))) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = "No data — select a dataset",
                     font = list(color = "#aaa"))
      ))
    }

    ok   <- !is.na(df[[x_col]]) & !is.na(df$pae_pct)
    pout <- df[[x_col]][ok]
    pae  <- df$pae_pct[ok]

    p <- plot_ly() %>%
      add_trace(
        type      = "scatter", mode = "markers",
        x         = pout, y = pae,
        marker    = list(
          color     = pae, colorscale = "Viridis",
          size      = 7,   showscale = TRUE,
          colorbar  = list(title     = "PAE (%)",
                           tickfont  = list(color = "#aaa"))
        ),
        hovertext = sprintf(paste0("Pout=", x_fmt, ", PAE=%.1f%%"), pout, pae),
        hoverinfo = "text",
        name      = "LP data"
      )

    # Mark optimal PAE point
    if (isTRUE(input$lp_nose_mark_opt) && length(pae) > 0) {
      bi <- which.max(pae)
      p  <- p %>% add_trace(
        type = "scatter", mode = "markers+text",
        x    = pout[bi], y = pae[bi],
        text = sprintf(paste0(x_fmt, " / %.1f%%"), pout[bi], pae[bi]),
        textposition = "top right",
        textfont  = list(color = "#ff7f11", size = 11),
        marker    = list(color = "#ff7f11", size = 14, symbol = "star",
                         line = list(color = "white", width = 1.5)),
        name      = "Max PAE", showlegend = TRUE
      )
    }

    # Back-off reference line (only meaningful on dBm axis)
    bo <- as.numeric(input$lp_backoff_db %||% 6)
    if (length(pout) > 0 && !use_watts) {
      max_po <- max(pout, na.rm = TRUE)
      ymax   <- max(pae,  na.rm = TRUE) * 1.12
      p <- p %>% add_trace(
        type = "scatter", mode = "lines",
        x    = c(max_po - bo, max_po - bo), y = c(0, ymax),
        line = list(color = "#d62728", dash = "dash", width = 1.5),
        name = paste0("-", bo, " dB back-off"),
        showlegend = TRUE
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis  = list(title = x_label, color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = "PAE (%)",    color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "Nose Plot \u2014 PAE vs Pout",
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa")
    )
  })

  # ── Tabular: Ppeak (max Pout) ─────────────────────────────────────────────
  output$lp_table_ppeak <- DT::renderDT({
    id  <- input$lp_sel_table
    df  <- .get_df(id)
    if (is.null(df) || !"pout_dbm" %in% names(df)) return(data.frame())
    bi  <- which.max(df$pout_dbm)
    if (length(bi) == 0) return(data.frame())
    row <- df[bi, , drop = FALSE]
    .clean_dt_row(row)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 1),
     class   = "compact cell-border", rownames = FALSE)

  # ── Tabular: Pavg (Ppeak − N dB) ─────────────────────────────────────────
  output$lp_table_pavg <- DT::renderDT({
    id  <- input$lp_sel_table
    df  <- .get_df(id)
    if (is.null(df) || !"pout_dbm" %in% names(df)) return(data.frame())
    bo      <- as.numeric(input$lp_ppeak_backoff %||% 6)
    max_po  <- max(df$pout_dbm, na.rm = TRUE)
    bi      <- which.min(abs(df$pout_dbm - (max_po - bo)))
    if (length(bi) == 0) return(data.frame())
    row     <- df[bi, , drop = FALSE]
    .clean_dt_row(row)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 1),
     class   = "compact cell-border", rownames = FALSE)

  .clean_dt_row <- function(row) {
    # Keep only non-all-NA columns; round numerics
    non_empty <- names(row)[sapply(row, function(c) !all(is.na(c)))]
    row       <- row[, non_empty, drop = FALSE]
    num_cols  <- names(row)[sapply(row, is.numeric)]
    row[num_cols] <- round(row[num_cols], 3)
    row
  }

  # ── CSV download (single dataset) ─────────────────────────────────────────
  output$lp_table_csv <- downloadHandler(
    filename = function() paste0("lp_data_", Sys.Date(), ".csv"),
    content  = function(file) {
      df <- .get_df(input$lp_sel_table)
      write.csv(if (is.null(df)) data.frame() else df,
                file, row.names = FALSE)
    }
  )

  # ── Comparison plot ────────────────────────────────────────────────────────
  output$lp_compare_plot <- renderPlotly({
    sel    <- input$lp_sel_compare
    ds     <- lp_datasets()
    metric <- input$lp_compare_metric %||% "pae_pct"

    if (length(sel) == 0) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = "Select datasets to compare",
                     font = list(color = "#aaa"))
      ))
    }

    p <- plot_ly()
    for (i in seq_along(sel)) {
      id  <- sel[i]
      df  <- .get_df(id)
      if (is.null(df) || !"pout_dbm" %in% names(df)) next
      if (!metric %in% names(df)) next
      col  <- PALETTE[(i - 1) %% length(PALETTE) + 1]
      xv   <- df$pout_dbm
      yv   <- df[[metric]]
      ok   <- !is.na(xv) & !is.na(yv)
      p    <- p %>% add_trace(
        type   = "scatter", mode = "lines+markers",
        x      = xv[ok], y = yv[ok],
        name   = ds[[id]]$filename,
        line   = list(color = col),
        marker = list(color = col, size = 5)
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis  = list(title = "Pout (dBm)", color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = gsub("_", " ", metric), color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "Multi-device Comparison",
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa")
    )
  })

  # ── Report preview ─────────────────────────────────────────────────────────
  output$lp_rpt_preview <- renderUI({
    ds <- lp_datasets()
    if (length(ds) == 0)
      return(p(style = "color:#888;", "No data loaded. Parse files first."))

    tagList(
      h4("Loaded datasets"),
      lapply(names(ds), function(id) {
        r  <- ds[[id]]
        ok <- isTRUE(r$success)
        div(class = "well",
            style = "background:#1e1e2e; border-color:#3a3a4a; padding:10px;",
          div(style = "display:flex; align-items:center; gap:10px;",
            tags$strong(style = "color:#ddd;", r$filename),
            tags$span(
              style = paste0("color:", if (ok) "#2ca02c" else "#d62728",
                             "; font-size:12px;"),
              if (ok) paste0("\u2713 ", nrow(r$points), " pts") else "\u2717 failed"
            )
          ),
          tags$small(style = "color:#888;",
            "Format: ", r$format,
            " \u00b7 Freq: ", r$meta[["freq_ghz"]] %||% "?", " GHz"),
          if (ok && length(r$meta) > 0) {
            ul_items <- lapply(
              names(r$meta)[seq_len(min(4, length(r$meta)))],
              function(nm) tags$li(nm, ": ", as.character(r$meta[[nm]]))
            )
            tags$ul(style = "font-size:12px; color:#aaa; margin:6px 0 0 0;",
                    ul_items)
          }
        )
      }),
      hr(style = "border-color:#333;"),
      p(style = "color:#888; font-size:12px;",
        "Use the Download buttons to export a full report or combined CSV.")
    )
  })

  # ── HTML Report download ───────────────────────────────────────────────────
  output$lp_rpt_html <- downloadHandler(
    filename = function() paste0("lp_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html"),
    content  = function(file) {
      ds       <- lp_datasets()
      sections <- input$lp_rpt_sections %||% character(0)
      title    <- input$lp_rpt_title    %||% "Load Pull Report"
      engineer <- input$lp_rpt_engineer %||% ""
      project  <- input$lp_rpt_project  %||% ""

      esc <- function(x) gsub("&", "&amp;",
                         gsub("<", "&lt;",
                         gsub(">", "&gt;", as.character(x))))

      hdr <- paste0(
        "<!DOCTYPE html><html lang='en'><head>",
        "<meta charset='UTF-8'>",
        "<title>", esc(title), "</title>",
        "<style>",
        "body{font-family:Arial,sans-serif;line-height:1.6;color:#222;",
        "max-width:960px;margin:24px auto;padding:0 16px;}",
        "h1{color:#333;border-bottom:2px solid #e0e0e0;padding-bottom:8px;}",
        "h2{color:#444;margin-top:28px;}h3{color:#555;}",
        "table{border-collapse:collapse;width:100%;margin:12px 0;}",
        "th,td{border:1px solid #ccc;padding:5px 10px;text-align:left;}",
        "th{background:#f4f4f4;font-weight:600;}",
        ".badge-ok{background:#2ca02c;color:#fff;border-radius:3px;padding:2px 6px;}",
        ".badge-err{background:#d62728;color:#fff;border-radius:3px;padding:2px 6px;}",
        "</style></head><body>",
        "<h1>", esc(title), "</h1>",
        if (nzchar(engineer)) paste0("<p><strong>Engineer:</strong> ", esc(engineer), "</p>") else "",
        if (nzchar(project))  paste0("<p><strong>Project:</strong> ",  esc(project),  "</p>") else "",
        "<p><strong>Generated:</strong> ", as.character(Sys.time()), "</p><hr/>"
      )

      body <- ""

      # Metadata section
      if ("meta" %in% sections) {
        body <- paste0(body, "<h2>Dataset Metadata</h2>")
        for (id in names(ds)) {
          r  <- ds[[id]]
          ok <- isTRUE(r$success)
          body <- paste0(body,
            "<h3>", esc(r$filename),
            " <span class='", if (ok) "badge-ok" else "badge-err", "'>",
            if (ok) "OK" else "failed", "</span></h3>",
            "<table><tr><th>Key</th><th>Value</th></tr>",
            paste0(sapply(names(r$meta), function(nm)
              paste0("<tr><td>", esc(nm), "</td><td>",
                     esc(as.character(r$meta[[nm]])), "</td></tr>")),
              collapse = ""),
            "</table>"
          )
        }
      }

      # Table section
      if ("table" %in% sections) {
        body <- paste0(body, "<h2>Data Tables</h2>")
        for (id in names(ds)) {
          r  <- ds[[id]]
          df <- r$points
          if (is.null(df) || nrow(df) == 0) next
          num_cols <- names(df)[sapply(df, is.numeric)]
          df_show  <- df[, num_cols, drop = FALSE]
          df_show  <- as.data.frame(lapply(df_show, round, digits = 3))

          body <- paste0(body,
            "<h3>", esc(r$filename), " (", nrow(df_show), " rows)</h3>",
            "<table><tr>",
            paste0("<th>", esc(names(df_show)), "</th>", collapse = ""),
            "</tr>",
            paste0(apply(df_show, 1, function(row)
              paste0("<tr>",
                     paste0("<td>", esc(row), "</td>", collapse = ""),
                     "</tr>")),
              collapse = ""),
            "</table>"
          )
        }
      }

      writeLines(paste0(hdr, body, "</body></html>"), file)
    }
  )

  # ── Combined CSV download ──────────────────────────────────────────────────
  output$lp_rpt_csv_all <- downloadHandler(
    filename = function() paste0("lp_all_data_", Sys.Date(), ".csv"),
    content  = function(file) {
      ds  <- lp_datasets()
      dfs <- Filter(Negate(is.null), lapply(names(ds), function(id) {
        r  <- ds[[id]]
        if (!isTRUE(r$success) || nrow(r$points) == 0) return(NULL)
        df             <- r$points
        df$source_file <- r$filename
        df$format      <- r$format
        df
      }))

      if (length(dfs) == 0) {
        write.csv(data.frame(), file, row.names = FALSE)
        return()
      }

      all_cols <- Reduce(union, lapply(dfs, names))
      combined <- do.call(rbind, lapply(dfs, function(d) {
        missing <- setdiff(all_cols, names(d))
        if (length(missing) > 0) d[missing] <- NA
        d[, all_cols, drop = FALSE]
      }))
      write.csv(combined, file, row.names = FALSE)
    }
  )
}
