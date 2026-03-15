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

  # ── Helpers ────────────────────────────────────────────────────────────────
  # Truncate long filenames for legend labels (max n visible chars)
  .short_name <- function(s, n = 24) {
    if (nchar(s) > n) paste0(substr(s, 1, n), "\u2026") else s
  }

  # Gamma-grid cache: stored as result$interp_cache[[var_key]][[pull_key]]
  # each element: list(xi, yi, zm) — computed once on parse
  .precompute_interp <- function(df, nx = 40, ny = 40) {
    var_map <- list(
      pout   = "pout_dbm", pae  = "pae_pct",  de    = "de_pct",
      gain   = "gain_db",  pdc  = "pdc_w",    pout_w = "pout_w"
    )
    cache <- list()
    for (pull_key in c("load", "source")) {
      xv_all <- if (pull_key == "load") df$gl_r else df$gs_r
      yv_all <- if (pull_key == "load") df$gl_i else df$gs_i
      if (is.null(xv_all) || all(is.na(xv_all))) next
      for (vname in names(var_map)) {
        col <- var_map[[vname]]
        if (!col %in% names(df)) next
        zv_all <- df[[col]]
        ok     <- !is.na(xv_all) & !is.na(yv_all) & !is.na(zv_all) &
                  (xv_all^2 + yv_all^2) <= 1.02
        xv <- xv_all[ok]; yv <- yv_all[ok]; zv <- zv_all[ok]
        if (length(xv) < 6) next
        key <- paste0(pull_key, ":", vname)
        tryCatch({
          xi <- seq(min(xv) - 0.01, max(xv) + 0.01, length.out = nx)
          yi <- seq(min(yv) - 0.01, max(yv) + 0.01, length.out = ny)
          xy_key <- paste(round(xv, 4), round(yv, 4))
          dup    <- duplicated(xy_key)
          res    <- akima::interp(xv[!dup], yv[!dup], zv[!dup],
                                  xo = xi, yo = yi, linear = TRUE, extrap = FALSE)
          zm <- res$z
          for (ii in seq_along(xi))
            for (jj in seq_along(yi))
              if (!is.finite(zm[ii, jj]) ||
                  xi[ii]^2 + yi[jj]^2 > 1.005) zm[ii, jj] <- NA
          cache[[key]] <- list(xi = xi, yi = yi, zm = zm)
        }, error = function(e) NULL)
      }
    }
    cache
  }

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
      result$filename <- fname

      if (isTRUE(result$success)) {
        npts <- nrow(result$points)
        log  <- c(log,
          sprintf("    OK  (%s)  %d measurement points parsed", result$format, npts))
        # Pre-compute interpolation cache for instant Smith chart rendering
        if (requireNamespace("akima", quietly = TRUE) && npts >= 6) {
          log <- c(log, "    Pre-computing contour grids...")
          result$interp_cache <- .precompute_interp(result$points)
          log <- c(log, paste0("    Cached ", length(result$interp_cache), " grids."))
        }
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
    ds        <- lp_datasets()
    sel_ids   <- input$lp_dataset_selector
    pull      <- input$lp_pull_type    %||% "load"
    vars      <- input$lp_contour_vars
    n_lev     <- input$lp_contour_levels %||% 6
    show_pae  <- isTRUE(input$lp_show_max_pae)
    show_po   <- isTRUE(input$lp_show_max_pout)
    zoom_data <- isTRUE(input$lp_smith_zoom_data)

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
      pout   = list(col = "pout_dbm", label = "Pout(dBm)", color = "#ff7f11"),
      pae    = list(col = "pae_pct",  label = "PAE(%)",    color = "#1f77b4"),
      de     = list(col = "de_pct",   label = "DE(%)",     color = "#2ca02c"),
      gain   = list(col = "gain_db",  label = "Gain(dB)",  color = "#9467bd"),
      pdc    = list(col = "pdc_w",    label = "Pdc(W)",    color = "#d62728"),
      pout_w = list(col = "pout_w",   label = "Pout(W)",   color = "#ffaa44")
    )

    # Collect data bounds for zoom-to-data feature
    all_xv <- c(); all_yv <- c()
    colorbar_x <- 1.02   # start position; shift right per colorbar

    if (length(sel_ids) > 0 && length(vars) > 0) {
      for (id in sel_ids) {
        df    <- .get_df(id)
        if (is.null(df)) next
        r     <- ds[[id]]
        fname <- .short_name(r$filename)

        xv_all <- if (pull == "load") df$gl_r else df$gs_r
        yv_all <- if (pull == "load") df$gl_i else df$gs_i
        if (is.null(xv_all) || all(is.na(xv_all))) next

        for (v in vars) {
          vm  <- var_meta[[v]]
          if (is.null(vm) || !vm$col %in% names(df)) next
          zv_all <- df[[vm$col]]

          ok <- !is.na(xv_all) & !is.na(yv_all) & !is.na(zv_all) &
                (xv_all^2 + yv_all^2) <= 1.02
          xv <- xv_all[ok]; yv <- yv_all[ok]; zv <- zv_all[ok]
          if (length(xv) < 4) next
          all_xv <- c(all_xv, xv); all_yv <- c(all_yv, yv)

          # Short legend: "Gain(dB) [short_filename]"
          leg_name <- paste0(vm$label, " [", fname, "]")

          # Try cache first, then on-the-fly interpolation
          cache_key  <- paste0(pull, ":", v)
          cached     <- r$interp_cache[[cache_key]]
          interp_ok  <- FALSE

          if (!is.null(cached)) {
            xi <- cached$xi; yi <- cached$yi; zm <- cached$zm
            interp_ok <- TRUE
          } else if (requireNamespace("akima", quietly = TRUE) && length(xv) >= 6) {
            tryCatch({
              nx <- 40; ny <- 40
              xi <- seq(min(xv) - 0.01, max(xv) + 0.01, length.out = nx)
              yi <- seq(min(yv) - 0.01, max(yv) + 0.01, length.out = ny)
              xy_key <- paste(round(xv, 4), round(yv, 4))
              dup    <- duplicated(xy_key)
              res    <- akima::interp(xv[!dup], yv[!dup], zv[!dup],
                                      xo = xi, yo = yi,
                                      linear = TRUE, extrap = FALSE)
              zm <- res$z
              for (ii in seq_along(xi))
                for (jj in seq_along(yi))
                  if (!is.finite(zm[ii, jj]) ||
                      xi[ii]^2 + yi[jj]^2 > 1.005) zm[ii, jj] <- NA
              interp_ok <- TRUE
            }, error = function(e) NULL)
          }

          if (interp_ok) {
            p <- p %>% add_contour(
              x          = xi, y = yi, z = t(zm),
              ncontours  = as.integer(n_lev),
              showscale  = TRUE,
              colorscale = list(c(0, "#111"), c(1, vm$color)),
              colorbar   = list(
                title    = vm$label,
                x        = colorbar_x,
                len      = 0.6,
                tickfont = list(color = "#aaa", size = 9),
                titlefont = list(color = vm$color, size = 10)
              ),
              contours   = list(coloring   = "lines",
                                showlabels = TRUE,
                                labelfont  = list(color = vm$color, size = 9)),
              line       = list(color = vm$color, width = 1.2),
              name       = leg_name,
              showlegend = TRUE
            )
            colorbar_x <- colorbar_x + 0.13
          } else {
            p <- p %>% add_trace(
              type   = "scatter", mode = "markers",
              x      = xv, y = yv,
              marker = list(color = zv, colorscale = "Viridis", size = 7,
                            showscale  = TRUE,
                            colorbar   = list(title = vm$label, x = colorbar_x,
                                             tickfont = list(color = "#aaa"))),
              hovertext = sprintf("%s: %.2f", vm$label, zv),
              hoverinfo = "text",
              name = leg_name, showlegend = TRUE
            )
            colorbar_x <- colorbar_x + 0.13
          }

          # Max markers
          if (show_po && v == "pout") {
            best <- which.max(zv)
            p <- p %>% add_trace(type = "scatter", mode = "markers+text",
              x = xv[best], y = yv[best],
              text = sprintf("%.1f dBm", zv[best]),
              textposition = "top right",
              marker = list(color = "#ff7f11", size = 14, symbol = "star",
                            line = list(color = "white", width = 1.5)),
              name = "Max Pout", showlegend = FALSE)
          }
          if (show_pae && v == "pae") {
            best <- which.max(zv)
            p <- p %>% add_trace(type = "scatter", mode = "markers+text",
              x = xv[best], y = yv[best],
              text = sprintf("%.1f%%", zv[best]),
              textposition = "top right",
              marker = list(color = "#1f77b4", size = 14, symbol = "diamond",
                            line = list(color = "white", width = 1.5)),
              name = "Max PAE", showlegend = FALSE)
          }
        } # vars loop
      } # dataset loop
    }

    # Axis range: zoom to data or full chart
    ax_range <- if (zoom_data && length(all_xv) > 0) {
      pad <- 0.08
      list(c(min(all_xv) - pad, max(all_xv) + pad),
           c(min(all_yv) - pad, max(all_yv) + pad))
    } else {
      list(c(-1.25, 1.25), c(-1.25, 1.25))
    }

    base_layout <- do.call(.smith_layout, list(
      title_txt = paste0(
        if (pull == "load") "Load Pull" else "Source Pull",
        " \u2014 Smith Chart Contours"),
      xl = paste0("Re(\u0393_", if (pull == "load") "L" else "S", ")"),
      yl = paste0("Im(\u0393_", if (pull == "load") "L" else "S", ")")
    ))
    base_layout$xaxis$range <- ax_range[[1]]
    base_layout$yaxis$range <- ax_range[[2]]
    base_layout$margin <- list(l = 50, r = max(80, 80 + (colorbar_x - 1.02) / 0.13 * 60),
                               t = 50, b = 50)

    p %>% layout(base_layout)
  })

  # ── XY Performance Plot (dual Y-axis: power/gain on Y1, PAE/DE on Y2) ─────
  output$lp_xy_plot <- renderPlotly({
    id     <- input$lp_xy_dataset_selector
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

    # Efficiency variables go on Y2 (right axis)
    EFF_VARS <- c("pae_pct", "de_pct")

    xv <- df[[x_var]]
    p  <- plot_ly()
    y1_labels <- c(); y2_labels <- c(); i_col <- 1L

    for (v in y_vars) {
      if (!v %in% names(df)) next
      yv    <- df[[v]]
      ok    <- !is.na(xv) & !is.na(yv)
      col   <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]
      i_col <- i_col + 1L
      on_y2 <- v %in% EFF_VARS
      lbl   <- switch(v,
        pae_pct  = "PAE (%)",  de_pct  = "DE (%)",
        gain_db  = "Gain (dB)", pout_dbm = "Pout (dBm)",
        pout_w   = "Pout (W)",  pin_dbm  = "Pin (dBm)",
        gsub("_", " ", v))
      if (on_y2) y2_labels <- c(y2_labels, lbl)
      else       y1_labels <- c(y1_labels, lbl)
      p <- p %>% add_trace(
        type   = "scatter", mode = "lines+markers",
        x      = xv[ok], y = yv[ok],
        yaxis  = if (on_y2) "y2" else "y",
        name   = lbl,
        line   = list(color = col, dash = if (on_y2) "dot" else "solid"),
        marker = list(color = col, size = 5,
                      symbol = if (on_y2) "circle-open" else "circle")
      )
    }

    y1_title <- if (length(y1_labels) > 0) paste(y1_labels, collapse = " / ") else "Value"
    y2_title <- if (length(y2_labels) > 0) paste(y2_labels, collapse = " / ") else "Efficiency (%)"

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis  = list(title = gsub("_", " ", x_var), color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = y1_title, color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis2 = list(title = y2_title, color = "#aaa",
                    overlaying = "y", side = "right", showgrid = FALSE,
                    zeroline = FALSE),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "XY Performance", font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa"),
      margin = list(l = 60, r = 70, t = 50, b = 60)
    )
  })

  # ── Tradeoff / Nose Plot — configurable dual-axis ─────────────────────────
  # Shows all LP measurement points. Y1 and Y2 are user-selectable.
  # Default: X = Pout(dBm), Y1 = Gain(dB), Y2 = PAE(%)
  output$lp_nose_plot <- renderPlotly({
    id     <- input$lp_nose_dataset_selector
    df     <- .get_df(id)
    x_var  <- input$lp_nose_x_var  %||% "pout_dbm"
    y1_var <- input$lp_nose_y1_var %||% "gain_db"
    y2_var <- input$lp_nose_y2_var %||% "pae_pct"

    # Human-readable axis labels
    .ax_lbl <- function(v) switch(v,
      pout_dbm = "Pout (dBm)", pout_w  = "Pout (W)",  pin_dbm = "Pin (dBm)",
      gain_db  = "Gain (dB)",  pae_pct = "PAE (%)",   de_pct  = "DE (%)",
      gsub("_", " ", v))

    if (is.null(df)) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = "No data — select a dataset",
                     font = list(color = "#aaa"))
      ))
    }

    # Sort by X for a clean line
    if (x_var %in% names(df)) {
      ord <- order(df[[x_var]], na.last = NA)
      df  <- df[ord, , drop = FALSE]
    }

    xv  <- if (x_var %in% names(df)) df[[x_var]] else NULL
    y1v <- if (y1_var %in% names(df)) df[[y1_var]] else NULL
    y2v <- if (y2_var %in% names(df)) df[[y2_var]] else NULL

    if (is.null(xv)) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = paste0("Column '", x_var, "' not found in dataset"),
                     font = list(color = "#aaa"))))
    }

    p <- plot_ly()

    # Y1 trace (left axis)
    if (!is.null(y1v)) {
      ok1 <- !is.na(xv) & !is.na(y1v)
      p <- p %>% add_trace(
        type   = "scatter", mode = "lines+markers",
        x      = xv[ok1], y = y1v[ok1],
        yaxis  = "y",
        name   = .ax_lbl(y1_var),
        line   = list(color = "#ff7f11", width = 2),
        marker = list(color = "#ff7f11", size = 5)
      )
      # Mark max-PAE / max-Gain point
      if (isTRUE(input$lp_nose_mark_opt) && sum(ok1) > 0) {
        bi <- which.max(y1v[ok1])
        p  <- p %>% add_trace(
          type = "scatter", mode = "markers+text",
          x = xv[ok1][bi], y = y1v[ok1][bi],
          text = sprintf("%.2f", y1v[ok1][bi]),
          textposition = "top right",
          textfont = list(color = "#ffcc80", size = 11),
          marker   = list(color = "#ff7f11", size = 13, symbol = "star",
                          line = list(color = "white", width = 1.5)),
          yaxis = "y", name = paste0("Max ", .ax_lbl(y1_var)), showlegend = TRUE
        )
      }
    }

    # Y2 trace (right axis)
    if (!is.null(y2v)) {
      ok2 <- !is.na(xv) & !is.na(y2v)
      p <- p %>% add_trace(
        type   = "scatter", mode = "lines+markers",
        x      = xv[ok2], y = y2v[ok2],
        yaxis  = "y2",
        name   = .ax_lbl(y2_var),
        line   = list(color = "#1f77b4", width = 2, dash = "dot"),
        marker = list(color = "#1f77b4", size = 5, symbol = "circle-open")
      )
      # Mark optimal Y2 point
      if (isTRUE(input$lp_nose_mark_opt) && sum(ok2) > 0) {
        bi <- which.max(y2v[ok2])
        p  <- p %>% add_trace(
          type = "scatter", mode = "markers+text",
          x = xv[ok2][bi], y = y2v[ok2][bi],
          text = sprintf("%.2f", y2v[ok2][bi]),
          textposition = "top left",
          textfont = list(color = "#7ec8e3", size = 11),
          marker   = list(color = "#1f77b4", size = 13, symbol = "diamond",
                          line = list(color = "white", width = 1.5)),
          yaxis = "y2", name = paste0("Max ", .ax_lbl(y2_var)), showlegend = TRUE
        )
      }
    }

    # Back-off reference line on X axis (when X is dBm-type)
    bo <- as.numeric(input$lp_backoff_db %||% 6)
    if (!is.null(xv) && x_var %in% c("pout_dbm", "pin_dbm") && bo > 0) {
      max_x <- max(xv, na.rm = TRUE)
      p <- p %>% add_trace(
        type = "scatter", mode = "lines",
        x    = c(max_x - bo, max_x - bo), y = c(0, 1),
        yaxis = "y", xaxis = "x",
        line = list(color = "#d62728", dash = "dash", width = 1.5),
        visible = "legendonly",
        name = paste0("-", bo, " dB back-off")
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis  = list(title = .ax_lbl(x_var), color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = if (!is.null(y1v)) .ax_lbl(y1_var) else "",
                    color = "#ff7f11",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                    tickfont = list(color = "#ff7f11")),
      yaxis2 = list(title = if (!is.null(y2v)) .ax_lbl(y2_var) else "",
                    color = "#1f77b4",
                    overlaying = "y", side = "right",
                    showgrid = FALSE, zeroline = FALSE,
                    tickfont = list(color = "#1f77b4")),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "Tradeoff Plot",
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa"),
      margin = list(l = 65, r = 70, t = 50, b = 60)
    )
  })

  # ── Tabular: Ppeak (max Pout) ─────────────────────────────────────────────
  output$lp_table_ppeak <- DT::renderDT({
    id  <- input$lp_table_dataset_selector
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
    id  <- input$lp_table_dataset_selector
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
      df <- .get_df(input$lp_table_dataset_selector)
      write.csv(if (is.null(df)) data.frame() else df,
                file, row.names = FALSE)
    }
  )

  # ── Comparison plot ────────────────────────────────────────────────────────
  output$lp_compare_plot <- renderPlotly({
    sel    <- input$lp_compare_selector
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
