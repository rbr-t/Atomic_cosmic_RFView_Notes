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

  # Gamma (Cartesian) → impedance (Z = Z0*(1+Γ)/(1-Γ))
  .gamma_to_z <- function(gr, gi, z0 = 50) {
    denom <- (1 - gr)^2 + gi^2
    r     <- z0 * (1 - gr^2 - gi^2) / denom
    x     <- z0 * 2 * gi            / denom
    list(r = r, x = x)
  }

  # Find MXP (max Pout), MXE (max PAE/DE), MXG (max Gain) row indices.
  # Returns named list of scalar row indices (or NA).
  .find_optima <- function(df) {
    idx <- function(col) {
      if (!col %in% names(df)) return(NA_integer_)
      v <- df[[col]]
      if (all(is.na(v))) return(NA_integer_)
      which.max(v)
    }
    list(
      MXP = idx("pout_dbm"),
      MXE = if (!is.na(idx("pae_pct"))) idx("pae_pct") else idx("de_pct"),
      MXG = idx("gain_db")
    )
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

  # ── Parse on button click (with progress bar) ──────────────────────────────
  observeEvent(input$lp_parse_btn, {
    req(input$lp_upload)
    fmt     <- input$lp_format_override %||% "auto"
    current <- lp_datasets()
    log     <- character()
    n_files <- nrow(input$lp_upload)
    has_akima <- requireNamespace("akima", quietly = TRUE)

    # Each file: 2 steps (parse + cache), total steps = n_files * 2
    n_steps <- n_files * 2L
    step    <- 0L

    withProgress(message = "Loading LP files", value = 0, {
      for (i in seq_len(n_files)) {
        fpath <- input$lp_upload$datapath[i]
        fname <- input$lp_upload$name[i]
        log   <- c(log, paste0("[", i, "] Parsing: ", fname, " ..."))

        step <- step + 1L
        setProgress(step / n_steps,
                    detail = paste0("Parsing ", i, "/", n_files, ": ",
                                    .short_name(fname, 30)))

        result          <- parse_lp_file(fpath, format_override = fmt)
        result$filename <- fname

        if (isTRUE(result$success)) {
          npts <- nrow(result$points)
          log  <- c(log,
            sprintf("    OK  (%s)  %d measurement points parsed", result$format, npts))

          step <- step + 1L
          setProgress(step / n_steps,
                      detail = paste0("Caching grids ", i, "/", n_files))

          if (has_akima && npts >= 6) {
            log <- c(log, "    Pre-computing contour grids...")
            result$interp_cache <- .precompute_interp(result$points)
            log <- c(log, paste0("    Cached ", length(result$interp_cache), " grids."))
          }
        } else {
          step <- step + 1L   # skip cache step
          log  <- c(log, paste0("    ERROR: ", result$error))
        }

        id            <- make.names(fname, unique = FALSE)
        current[[id]] <- result
      }
    })

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
    # Truncate display labels so they fit in the sidebar column without
    # overflowing into the adjacent plot area
    ids    <- names(ds)
    labels <- vapply(ds, function(r) .short_name(r$filename, 26L), character(1))
    setNames(ids, labels)
  })

  .make_selector <- function(output_id, label = "Dataset",
                             multiple = FALSE) {
    output[[output_id]] <- renderUI({
      ch <- .dataset_choices()
      if (length(ch) == 0)
        return(p(style = "color:#888; font-size:12px;",
                 "Load datasets first."))
      # Wrap in a container that enforces overflow:hidden on the element
      div(style = "max-width:100%; overflow:hidden;",
        if (multiple)
          checkboxGroupInput(output_id, label, choices = ch, selected = ch[1])
        else
          selectInput(output_id, label, choices = ch, selected = ch[1],
                      width = "100%")
      )
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

    # Optimum marker config
    OPT_CFG <- list(
      MXP = list(col = "pout_dbm", sym = "star",    color = "#ff7f11", label = "MXP"),
      MXE = list(col = "pae_pct",  sym = "diamond",  color = "#1f77b4", label = "MXE"),
      MXG = list(col = "gain_db",  sym = "triangle-up", color = "#2ca02c", label = "MXG")
    )
    show_opt <- isTRUE(input$lp_show_optima %||% TRUE)
    show_h2  <- isTRUE(input$lp_show_harmonics)

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
              colorscale = list(list(0, "#111111"), list(1, vm$color)),
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

        # ── Optimum points: MXP, MXE, MXG (always shown by default) ──────────
        if (show_opt) {
          opt <- .find_optima(df)
          for (oname in names(OPT_CFG)) {
            bi <- opt[[oname]]
            if (is.na(bi)) next
            cfg <- OPT_CFG[[oname]]
            if (!cfg$col %in% names(df)) next
            ox <- xv_all[bi]; oy <- yv_all[bi]; oz <- df[[cfg$col]][bi]
            if (any(is.na(c(ox, oy)))) next
            p <- p %>% add_trace(
              type = "scatter", mode = "markers+text",
              x = ox, y = oy,
              text = sprintf("%s\n%.1f", oname, oz),
              textposition = "top center",
              textfont = list(color = cfg$color, size = 10),
              marker = list(color = cfg$color, size = 16,
                            symbol = cfg$sym,
                            line = list(color = "white", width = 1.5)),
              name = paste0(oname, " [", fname, "]"), showlegend = TRUE
            )
          }
        }

        # ── 2nd / 3rd harmonic impedance clusters ─────────────────────────────
        if (show_h2) {
          for (harm in list(
              list(r = "gl2_r", i = "gl2_i", label = "2H", color = "#e377c2"),
              list(r = "gl3_r", i = "gl3_i", label = "3H", color = "#17becf")
          )) {
            if (!all(c(harm$r, harm$i) %in% names(df))) next
            hx <- df[[harm$r]]; hy <- df[[harm$i]]
            ok_h <- !is.na(hx) & !is.na(hy)
            if (sum(ok_h) == 0) next
            p <- p %>% add_trace(
              type = "scatter", mode = "markers",
              x = hx[ok_h], y = hy[ok_h],
              marker = list(color = harm$color, size = 5,
                            symbol = "x", opacity = 0.7),
              name = paste0(harm$label, "Γ_L [", fname, "]"),
              showlegend = TRUE, hoverinfo = "none"
            )
          }
        }
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

  # ── Tradeoff / Nose Plot — all measured impedances coloured by metric ───
  # Each LP measurement point is plotted as a scatter on the Smith chart plane
  # with colour = selected metric, giving the classic "scatter cloud" nose/tradeoff view.
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

    # ─ Layout mode: Smith-scatter vs XY dual-axis ──────────────────────────────
    # "Smith-scatter" mode: X=Re(Γ_L), Y=Im(Γ_L), colour = x_var metric
    # This is the standard trade-off / nose chart display
    use_smith <- isTRUE(input$lp_nose_smith_mode %||% TRUE)
    pull      <- input$lp_pull_type %||% "load"

    if (use_smith) {
      # Retrieve Gamma columns
      xv_all <- if (pull == "load") df$gl_r else df$gs_r
      yv_all <- if (pull == "load") df$gl_i else df$gs_i

      if (is.null(xv_all) || all(is.na(xv_all))) {
        return(plot_ly() %>% layout(
          paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
          title = list(text = "No Γ data — check Pull plane setting",
                       font = list(color = "#aaa"))))
      }

      # Colour the scatter by x_var (metric)
      col_var   <- x_var
      col_label <- .ax_lbl(col_var)
      cv <- if (col_var %in% names(df)) df[[col_var]] else rep(NA_real_, nrow(df))

      ok <- !is.na(xv_all) & !is.na(yv_all) & !is.na(cv) &
            (xv_all^2 + yv_all^2) <= 1.02
      xv <- xv_all[ok]; yv <- yv_all[ok]; cv_ok <- cv[ok]

      # Build Smith grid background
      grid <- build_smith_grid()
      p    <- plot_ly()
      for (tr in grid) {
        p <- p %>% add_trace(
          type = "scatter", mode = "lines",
          x = tr$x, y = tr$y, line = tr$line,
          hoverinfo = "none", showlegend = FALSE, name = tr$name
        )
      }

      hover_txt <- sprintf(
        paste0(col_label, ": %.2f<br>Re(Γ): %.3f<br>Im(Γ): %.3f"),
        cv_ok, xv, yv
      )

      p <- p %>% add_trace(
        type      = "scatter", mode = "markers",
        x         = xv, y = yv,
        marker    = list(
          color     = cv_ok,
          colorscale = "Jet",
          size      = 8,
          showscale = TRUE,
          colorbar  = list(title = col_label,
                           tickfont = list(color = "#aaa"),
                           titlefont = list(color = "#aaa"))
        ),
        hovertext = hover_txt,
        hoverinfo = "text",
        name      = col_label
      )

      # Optimum markers: MXP, MXE, MXG
      if (isTRUE(input$lp_nose_mark_opt)) {
        opt <- .find_optima(df)
        OPT_CFG_N <- list(
          MXP = list(col = "pout_dbm", sym = "star",       color = "#ff7f11"),
          MXE = list(col = "pae_pct",  sym = "diamond",    color = "#1f77b4"),
          MXG = list(col = "gain_db",  sym = "triangle-up",color = "#2ca02c")
        )
        for (oname in names(OPT_CFG_N)) {
          bi <- opt[[oname]]
          if (is.na(bi)) next
          cfg <- OPT_CFG_N[[oname]]
          if (!cfg$col %in% names(df)) next
          odf <- df[bi, ]
          ox  <- if (pull == "load") odf$gl_r else odf$gs_r
          oy  <- if (pull == "load") odf$gl_i else odf$gs_i
          ov  <- odf[[cfg$col]]
          if (any(is.na(c(ox, oy)))) next
          p <- p %>% add_trace(
            type = "scatter", mode = "markers+text",
            x = ox, y = oy,
            text = sprintf("%s\n%.2f", oname, ov),
            textposition = "top center",
            textfont = list(color = cfg$color, size = 11),
            marker = list(color = cfg$color, size = 16, symbol = cfg$sym,
                          line = list(color = "white", width = 2)),
            name = oname, showlegend = TRUE
          )
        }
      }

      # Harmonic impedance scatter (2H, 3H)
      for (harm in list(
          list(r = "gl2_r", i = "gl2_i", label = "\u0393_L 2H", color = "#e377c2"),
          list(r = "gl3_r", i = "gl3_i", label = "\u0393_L 3H", color = "#17becf")
      )) {
        if (!all(c(harm$r, harm$i) %in% names(df))) next
        hx <- df[[harm$r]]; hy <- df[[harm$i]]
        ok_h <- !is.na(hx) & !is.na(hy)
        if (sum(ok_h) == 0) next
        p <- p %>% add_trace(
          type = "scatter", mode = "markers",
          x = hx[ok_h], y = hy[ok_h],
          marker = list(color = harm$color, size = 6, symbol = "x", opacity = 0.8),
          name = harm$label, showlegend = TRUE, hoverinfo = "none"
        )
      }

      ax_r <- if (isTRUE(input$lp_smith_zoom_data) && length(xv) > 0) {
        pad <- 0.08
        list(c(min(xv) - pad, max(xv) + pad), c(min(yv) - pad, max(yv) + pad))
      } else {
        list(c(-1.25, 1.25), c(-1.25, 1.25))
      }

      return(p %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor  = "#1b1b2b",
        xaxis  = list(title = paste0("Re(\u0393", if (pull=="load") "_L" else "_S", ")"),
                      range = ax_r[[1]], zeroline = FALSE, showgrid = FALSE,
                      color = "#aaa", scaleanchor = "y", scaleratio = 1),
        yaxis  = list(title = paste0("Im(\u0393", if (pull=="load") "_L" else "_S", ")"),
                      range = ax_r[[2]], zeroline = FALSE, showgrid = FALSE,
                      color = "#aaa"),
        legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
        title  = list(text = paste0("Tradeoff / Nose Plot — coloured by ", col_label),
                      font = list(color = "#eee", size = 14)),
        font   = list(color = "#aaa"),
        margin = list(l = 50, r = 110, t = 50, b = 50)
      ))
    } # end Smith-scatter mode

    # ─ XY dual-axis fallback (when Smith mode is unchecked) ───────────────────
    if (x_var %in% names(df)) {
      ord <- order(df[[x_var]], na.last = NA)
      df  <- df[ord, , drop = FALSE]
    }
    xv  <- if (x_var  %in% names(df)) df[[x_var]]  else NULL
    y1v <- if (y1_var %in% names(df)) df[[y1_var]] else NULL
    y2v <- if (y2_var %in% names(df)) df[[y2_var]] else NULL

    if (is.null(xv)) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = paste0("Column '", x_var, "' not found in dataset"),
                     font = list(color = "#aaa"))))
    }

    p <- plot_ly()
    if (!is.null(y1v)) {
      ok1 <- !is.na(xv) & !is.na(y1v)
      p   <- p %>% add_trace(
        type = "scatter", mode = "lines+markers",
        x = xv[ok1], y = y1v[ok1], yaxis = "y",
        name = .ax_lbl(y1_var),
        line = list(color = "#ff7f11", width = 2),
        marker = list(color = "#ff7f11", size = 5)
      )
      if (isTRUE(input$lp_nose_mark_opt) && sum(ok1) > 0) {
        bi <- which.max(y1v[ok1])
        p  <- p %>% add_trace(
          type = "scatter", mode = "markers+text",
          x = xv[ok1][bi], y = y1v[ok1][bi],
          text = sprintf("%.2f", y1v[ok1][bi]),
          textposition = "top right",
          textfont = list(color = "#ffcc80", size = 11),
          marker = list(color = "#ff7f11", size = 13, symbol = "star",
                        line = list(color = "white", width = 1.5)),
          yaxis = "y", name = paste0("Max ", .ax_lbl(y1_var)), showlegend = TRUE
        )
      }
    }
    if (!is.null(y2v)) {
      ok2 <- !is.na(xv) & !is.na(y2v)
      p   <- p %>% add_trace(
        type = "scatter", mode = "lines+markers",
        x = xv[ok2], y = y2v[ok2], yaxis = "y2",
        name = .ax_lbl(y2_var),
        line = list(color = "#1f77b4", width = 2, dash = "dot"),
        marker = list(color = "#1f77b4", size = 5, symbol = "circle-open")
      )
      if (isTRUE(input$lp_nose_mark_opt) && sum(ok2) > 0) {
        bi <- which.max(y2v[ok2])
        p  <- p %>% add_trace(
          type = "scatter", mode = "markers+text",
          x = xv[ok2][bi], y = y2v[ok2][bi],
          text = sprintf("%.2f", y2v[ok2][bi]),
          textposition = "top left",
          textfont = list(color = "#7ec8e3", size = 11),
          marker = list(color = "#1f77b4", size = 13, symbol = "diamond",
                        line = list(color = "white", width = 1.5)),
          yaxis = "y2", name = paste0("Max ", .ax_lbl(y2_var)), showlegend = TRUE
        )
      }
    }
    bo <- as.numeric(input$lp_backoff_db %||% 6)
    if (!is.null(xv) && x_var %in% c("pout_dbm","pin_dbm") && bo > 0) {
      max_x <- max(xv, na.rm = TRUE)
      p <- p %>% add_trace(
        type = "scatter", mode = "lines",
        x = c(max_x - bo, max_x - bo), y = c(0, 1),
        yaxis = "y",
        line = list(color = "#d62728", dash = "dash", width = 1.5),
        visible = "legendonly",
        name = paste0("-", bo, " dB back-off")
      )
    }
    p %>% layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
      xaxis  = list(title = .ax_lbl(x_var),  color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = if (!is.null(y1v)) .ax_lbl(y1_var) else "",
                    color = "#ff7f11",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                    tickfont = list(color = "#ff7f11")),
      yaxis2 = list(title = if (!is.null(y2v)) .ax_lbl(y2_var) else "",
                    color = "#1f77b4", overlaying = "y", side = "right",
                    showgrid = FALSE, zeroline = FALSE,
                    tickfont = list(color = "#1f77b4")),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = "Tradeoff Plot", font = list(color = "#eee", size = 14)),
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

  # ── Tabular: Optimum operating points (MXP / MXE / MXG) with impedances ──
  output$lp_table_optima <- DT::renderDT({
    id <- input$lp_table_dataset_selector
    df <- .get_df(id)
    if (is.null(df)) return(data.frame())

    opt  <- .find_optima(df)
    rows <- list()

    for (oname in c("MXP", "MXE", "MXG")) {
      bi <- opt[[oname]]
      if (is.na(bi)) next
      row  <- df[bi, , drop = FALSE]

      gl_r <- if ("gl_r" %in% names(row)) row$gl_r else NA_real_
      gl_i <- if ("gl_i" %in% names(row)) row$gl_i else NA_real_
      gs_r <- if ("gs_r" %in% names(row)) row$gs_r else NA_real_
      gs_i <- if ("gs_i" %in% names(row)) row$gs_i else NA_real_
      zl   <- .gamma_to_z(gl_r, gl_i)
      zs   <- .gamma_to_z(gs_r, gs_i)

      rec <- data.frame(
        Point    = oname,
        Pout_dBm = round(if ("pout_dbm" %in% names(row)) row$pout_dbm else NA_real_, 2),
        Gain_dB  = round(if ("gain_db"  %in% names(row)) row$gain_db  else NA_real_, 2),
        PAE_pct  = round(if ("pae_pct"  %in% names(row)) row$pae_pct  else NA_real_, 2),
        DE_pct   = round(if ("de_pct"   %in% names(row)) row$de_pct   else NA_real_, 2),
        Freq_GHz = round(if ("freq_ghz" %in% names(row)) row$freq_ghz else NA_real_, 4),
        Gamma_L  = sprintf("%.3f %+.3fj", gl_r, gl_i),
        ZL_Ohm   = sprintf("%.2f %+.2fj", round(zl$r, 2), round(zl$x, 2)),
        Gamma_S  = sprintf("%.3f %+.3fj", gs_r, gs_i),
        ZS_Ohm   = sprintf("%.2f %+.2fj", round(zs$r, 2), round(zs$x, 2)),
        stringsAsFactors = FALSE
      )
      rows[[oname]] <- rec
    }

    if (length(rows) == 0) return(data.frame())
    do.call(rbind, rows)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 5),
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

  # ── AM-PM / AM-AM vs Pout ───────────────────────────────────────────────────
  output$lp_ampm_plot <- renderPlotly({
    id    <- input$lp_xy_dataset_selector   # reuse XY selector
    df    <- .get_df(id)
    x_var <- input$lp_ampm_x_var %||% "pin_dbm"

    .ax_lbl2 <- function(v) switch(v,
      pout_dbm = "Pout (dBm)", pin_dbm = "Pin (dBm)", pout_w = "Pout (W)",
      gsub("_", " ", v))

    empty_plot <- function(msg)
      plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = msg, font = list(color = "#aaa")))

    if (is.null(df)) return(empty_plot("No data — select a dataset"))

    has_ampm <- "am_pm" %in% names(df) && !all(is.na(df$am_pm))
    has_gain <- "gain_db" %in% names(df) && !all(is.na(df$gain_db))

    if (!has_ampm && !has_gain) {
      return(empty_plot("No AM-PM or Gain data found in this dataset"))
    }

    # Sort by X
    if (x_var %in% names(df)) {
      ord <- order(df[[x_var]], na.last = NA)
      df  <- df[ord, , drop = FALSE]
    }
    xv <- df[[x_var]]
    p  <- plot_ly()

    # AM-AM: Gain (dB) vs Pout — left Y axis (linear gain compression)
    if (has_gain) {
      yv <- df$gain_db
      ok <- !is.na(xv) & !is.na(yv)
      p  <- p %>% add_trace(
        type = "scatter", mode = "lines+markers",
        x = xv[ok], y = yv[ok], yaxis = "y",
        name = "AM-AM (dB)",
        line   = list(color = "#ff7f11", width = 2),
        marker = list(color = "#ff7f11", size = 5)
      )
      # Mark 1dB compression point
      if (sum(ok) > 2) {
        g_lin  <- max(yv[ok][seq_len(min(3, sum(ok)))], na.rm = TRUE)
        g_comp <- g_lin - 1
        ci     <- which(yv[ok] <= g_comp)
        if (length(ci) > 0) {
          ci1 <- ci[1]
          p   <- p %>% add_trace(
            type = "scatter", mode = "markers+text",
            x = xv[ok][ci1], y = yv[ok][ci1],
            text = sprintf("P1dB\n%.1f dBm", xv[ok][ci1]),
            textposition = "top right",
            textfont = list(color = "#ff7f11", size = 10),
            marker = list(color = "#ff7f11", size = 12, symbol = "circle",
                          line = list(color = "white", width = 2)),
            yaxis = "y", name = "P1dB", showlegend = TRUE
          )
        }
      }
    }

    # AM-PM: phase distortion vs Pout — right Y axis
    if (has_ampm) {
      yv2 <- df$am_pm
      ok2 <- !is.na(xv) & !is.na(yv2)
      p   <- p %>% add_trace(
        type = "scatter", mode = "lines+markers",
        x = xv[ok2], y = yv2[ok2], yaxis = "y2",
        name = "AM-PM (°)",
        line   = list(color = "#1f77b4", width = 2, dash = "dot"),
        marker = list(color = "#1f77b4", size = 5, symbol = "circle-open")
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
      xaxis  = list(title = .ax_lbl2(x_var), color = "#aaa",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
      yaxis  = list(title = "AM-AM (dB)", color = "#ff7f11",
                    showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                    tickfont = list(color = "#ff7f11")),
      yaxis2 = list(title = "AM-PM (°)", color = "#1f77b4",
                    overlaying = "y", side = "right",
                    showgrid = FALSE, zeroline = FALSE,
                    tickfont = list(color = "#1f77b4")),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
      title  = list(text = paste0("AM-AM / AM-PM vs ", .ax_lbl2(x_var)),
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa"),
      margin = list(l = 65, r = 70, t = 50, b = 60)
    )
  })

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

      fmt1 <- function(x) ifelse(is.na(x), "\u2014", sprintf("%.2f", x))

      # ── Serialize a plotly figure to a self-contained <div>+<script> block ──
      div_count <- 0L
      plot_div <- function(p, height = "460px") {
        div_count <<- div_count + 1L
        did  <- paste0("lp_fig_", div_count)
        b    <- plotly::plotly_build(p)
        jd   <- jsonlite::toJSON(b$x$data,   auto_unbox = TRUE,
                                 null = "null", na = "null", force = TRUE)
        jl   <- jsonlite::toJSON(b$x$layout, auto_unbox = TRUE,
                                 null = "null", na = "null", force = TRUE)
        paste0(
          "<div id='", did, "' style='width:100%;height:", height,
          ";margin-bottom:20px;'></div>\n",
          "<script>(function(){\n",
          "  Plotly.newPlot('", did, "',", jd, ",", jl,
          ",{responsive:true,displayModeBar:true});\n",
          "})();</script>\n"
        )
      }

      # ── MXP/MXE/MXG summary HTML table ────────────────────────────────────
      optima_html <- function(df) {
        opt     <- .find_optima(df)
        has_gl  <- all(c("gl_r", "gl_i") %in% names(df))
        has_gs  <- all(c("gs_r", "gs_i") %in% names(df))
        rows    <- ""
        for (oname in c("MXP", "MXE", "MXG")) {
          bi <- opt[[oname]]
          if (is.na(bi)) next
          row <- df[bi, , drop = FALSE]
          zl  <- if (has_gl) {
            zz <- .gamma_to_z(row$gl_r, row$gl_i)
            sprintf("%.1f%+.1fj\u03a9", zz$r, zz$x)
          } else "\u2014"
          zs  <- if (has_gs) {
            zz <- .gamma_to_z(row$gs_r, row$gs_i)
            sprintf("%.1f%+.1fj\u03a9", zz$r, zz$x)
          } else "\u2014"
          bg  <- switch(oname,
            MXP = "#fff3e0", MXE = "#e3f2fd", MXG = "#e8f5e9", "#fff")
          rows <- paste0(rows,
            "<tr style='background:", bg, ";'>",
            "<td style='font-weight:700;padding:5px 10px;'>", oname, "</td>",
            "<td style='padding:5px 10px;'>", fmt1(row$pout_dbm), " dBm</td>",
            "<td style='padding:5px 10px;'>", fmt1(row$gain_db),  " dB</td>",
            "<td style='padding:5px 10px;'>", fmt1(row$pae_pct),  " %</td>",
            "<td style='padding:5px 10px;'>", fmt1(row$de_pct),   " %</td>",
            "<td style='padding:5px 10px;'>", fmt1(row$pin_dbm),  " dBm</td>",
            "<td style='padding:5px 10px;'>", zl, "</td>",
            "<td style='padding:5px 10px;'>", zs, "</td>",
            "</tr>"
          )
        }
        paste0(
          "<table style='border-collapse:collapse;width:100%;margin:10px 0;'>",
          "<thead><tr style='background:#e0e0e0;'>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Optimum</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Pout</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Gain</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>PAE</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>DE</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Pin</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Z_L</th>",
          "<th style='padding:5px 10px;border:1px solid #bbb;'>Z_S</th>",
          "</tr></thead>",
          "<tbody>", rows, "</tbody></table>"
        )
      }

      # ── Build Smith chart plotly figure ────────────────────────────────────
      build_smith_fig <- function(r, df) {
        grid <- build_smith_grid()
        p    <- plot_ly()
        for (tr in grid)
          p <- p %>% add_trace(type = "scatter", mode = "lines",
            x = tr$x, y = tr$y, line = tr$line,
            hoverinfo = "none", showlegend = FALSE, name = tr$name)

        vm_list <- list(
          pout = list(col = "pout_dbm", label = "Pout (dBm)", color = "#ff7f11"),
          pae  = list(col = "pae_pct",  label = "PAE (%)",    color = "#1f77b4")
        )
        xv_gl <- df$gl_r;  yv_gl <- df$gl_i
        ok_xy <- !is.na(xv_gl) & !is.na(yv_gl)
        cbx   <- 1.02

        for (v in names(vm_list)) {
          vm  <- vm_list[[v]]
          if (!vm$col %in% names(df)) next
          zv  <- df[[vm$col]]
          ok  <- ok_xy & !is.na(zv) & (xv_gl^2 + yv_gl^2) <= 1.02
          xv  <- xv_gl[ok]; yv <- yv_gl[ok]; zv <- zv[ok]
          if (length(xv) < 4) next

          cached <- r$interp_cache[[paste0("load:", v)]]
          if (!is.null(cached)) {
            p <- p %>% add_contour(
              x = cached$xi, y = cached$yi, z = t(cached$zm),
              ncontours = 6L, showscale = TRUE,
              colorscale = list(list(0, "#111111"), list(1, vm$color)),
              colorbar   = list(title = vm$label, x = cbx, len = 0.6,
                                tickfont  = list(color = "#aaa", size = 9),
                                titlefont = list(color = vm$color, size = 10)),
              contours   = list(coloring = "lines", showlabels = TRUE,
                                labelfont = list(color = vm$color, size = 9)),
              line       = list(color = vm$color, width = 1.2),
              name = vm$label, showlegend = TRUE)
          } else {
            p <- p %>% add_trace(type = "scatter", mode = "markers",
              x = xv, y = yv,
              marker = list(color = zv, colorscale = "Viridis", size = 7,
                            showscale = TRUE,
                            colorbar = list(title = vm$label, x = cbx,
                                            tickfont = list(color = "#aaa"))),
              name = vm$label, showlegend = TRUE)
          }
          cbx <- cbx + 0.13
        }

        # MXP / MXE / MXG markers
        opt      <- .find_optima(df)
        OPT_CFG  <- list(
          MXP = list(col="pout_dbm", sym="star",       color="#ff7f11", label="MXP"),
          MXE = list(col="pae_pct",  sym="diamond",    color="#1f77b4", label="MXE"),
          MXG = list(col="gain_db",  sym="triangle-up",color="#2ca02c", label="MXG"))
        for (oname in names(OPT_CFG)) {
          bi  <- opt[[oname]]
          if (is.na(bi)) next
          cfg <- OPT_CFG[[oname]]
          if (!cfg$col %in% names(df)) next
          ox <- xv_gl[bi]; oy <- yv_gl[bi]; oz <- df[[cfg$col]][bi]
          if (any(is.na(c(ox, oy)))) next
          p <- p %>% add_trace(type = "scatter", mode = "markers+text",
            x = ox, y = oy,
            text = sprintf("%s\n%.1f", oname, oz),
            textposition = "top center",
            textfont = list(color = cfg$color, size = 10),
            marker   = list(color = cfg$color, size = 16, symbol = cfg$sym,
                            line = list(color = "white", width = 1.5)),
            name = cfg$label, showlegend = TRUE)
        }

        sl <- .smith_layout(
          title_txt = paste0("Load Pull \u2014 Smith Chart (", .short_name(r$filename, 30L), ")"),
          xl = "Re(\u0393_L)", yl = "Im(\u0393_L)")
        sl$margin <- list(l = 55, r = max(80, 80 + (cbx - 1.02) / 0.13 * 60), t = 50, b = 50)
        p %>% layout(sl)
      }

      # ── Build XY performance figure ────────────────────────────────────────
      build_xy_fig <- function(r, df) {
        xv   <- df$pin_dbm %||% seq_len(nrow(df))
        EFF  <- c("pae_pct", "de_pct")
        VARS <- intersect(c("gain_db", "pae_pct", "de_pct", "pout_dbm"), names(df))
        PAL  <- c("#ff7f11", "#1f77b4", "#2ca02c", "#9467bd")
        p    <- plot_ly(); y1_lbl <- c(); y2_lbl <- c(); icol <- 1L
        for (v in VARS) {
          yv  <- df[[v]]; ok <- !is.na(xv) & !is.na(yv)
          cl  <- PAL[(icol - 1L) %% length(PAL) + 1L]; icol <- icol + 1L
          on2 <- v %in% EFF
          lbl <- switch(v, gain_db="Gain (dB)", pae_pct="PAE (%)",
                         de_pct="DE (%)", pout_dbm="Pout (dBm)", gsub("_"," ",v))
          if (on2) y2_lbl <- c(y2_lbl, lbl) else y1_lbl <- c(y1_lbl, lbl)
          p <- p %>% add_trace(type = "scatter", mode = "lines+markers",
            x = xv[ok], y = yv[ok],
            yaxis = if (on2) "y2" else "y", name = lbl,
            line   = list(color = cl, dash = if (on2) "dot" else "solid"),
            marker = list(color = cl, size = 5))
        }
        p %>% layout(
          paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
          xaxis  = list(title = "Pin (dBm)", color = "#aaa",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
          yaxis  = list(title = paste(y1_lbl, collapse = " / ") %||% "Value",
                        color = "#aaa",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
          yaxis2 = list(title = paste(y2_lbl, collapse = " / ") %||% "Efficiency (%)",
                        color = "#aaa", overlaying = "y", side = "right",
                        showgrid = FALSE, zeroline = FALSE),
          legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
          title  = list(text = paste0("XY Performance \u2014 ", .short_name(r$filename, 30L)),
                        font = list(color = "#eee", size = 14)),
          font   = list(color = "#aaa"),
          margin = list(l = 65, r = 75, t = 50, b = 60))
      }

      # ── Build Nose/Tradeoff scatter figure ─────────────────────────────────
      build_nose_fig <- function(r, df) {
        has_gl <- !is.null(df$gl_r) && !all(is.na(df$gl_r))
        if (has_gl) {
          grid <- build_smith_grid(); p <- plot_ly()
          for (tr in grid)
            p <- p %>% add_trace(type = "scatter", mode = "lines",
              x = tr$x, y = tr$y, line = tr$line,
              hoverinfo = "none", showlegend = FALSE, name = tr$name)
          cv  <- df$pout_dbm %||% rep(NA_real_, nrow(df))
          ok  <- !is.na(df$gl_r) & !is.na(df$gl_i) & !is.na(cv) &
                 (df$gl_r^2 + df$gl_i^2) <= 1.02
          p   <- p %>% add_trace(type = "scatter", mode = "markers",
            x = df$gl_r[ok], y = df$gl_i[ok],
            marker = list(color = cv[ok], colorscale = "Jet", size = 8,
                          showscale = TRUE,
                          colorbar = list(title = "Pout (dBm)",
                                          tickfont  = list(color = "#aaa"),
                                          titlefont = list(color = "#aaa"))),
            name = "Pout (dBm)")
          sl <- .smith_layout(
            title_txt = paste0("Tradeoff \u2014 Pout vs \u0393_L (", .short_name(r$filename,28L),")"),
            xl = "Re(\u0393_L)", yl = "Im(\u0393_L)")
          p %>% layout(sl)
        } else if (!is.null(df$pout_dbm)) {
          # XY fallback: Gain + PAE vs Pout
          p    <- plot_ly()
          VARS <- list(list(v="gain_db", l="Gain (dB)", c="#ff7f11", y2=FALSE),
                       list(v="pae_pct", l="PAE (%)",   c="#1f77b4", y2=TRUE))
          for (vv in VARS) {
            if (!vv$v %in% names(df)) next
            yv <- df[[vv$v]]; ok <- !is.na(df$pout_dbm) & !is.na(yv)
            p <- p %>% add_trace(type = "scatter", mode = "lines+markers",
              x = df$pout_dbm[ok], y = yv[ok],
              yaxis = if (vv$y2) "y2" else "y",
              name = vv$l, line = list(color = vv$c, dash = if (vv$y2) "dot" else "solid"),
              marker = list(color = vv$c, size = 5))
          }
          p %>% layout(
            paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
            xaxis  = list(title = "Pout (dBm)", color = "#aaa",
                          showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
            yaxis  = list(title = "Gain (dB)", color = "#aaa",
                          showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
            yaxis2 = list(title = "PAE (%)", color = "#aaa",
                          overlaying = "y", side = "right", showgrid = FALSE),
            legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
            title  = list(text = paste0("Tradeoff \u2014 ", .short_name(r$filename, 28L)),
                          font = list(color = "#eee", size = 14)),
            font   = list(color = "#aaa"),
            margin = list(l = 65, r = 75, t = 50, b = 60))
        } else NULL
      }

      # ── Build AM-AM / AM-PM figure ─────────────────────────────────────────
      build_ampm_fig <- function(r, df) {
        xv       <- df$pin_dbm %||% df$pout_dbm
        has_gain <- "gain_db" %in% names(df) && !all(is.na(df$gain_db))
        has_ampm <- "am_pm"   %in% names(df) && !all(is.na(df$am_pm))
        if (is.null(xv) || (!has_gain && !has_ampm)) return(NULL)
        p <- plot_ly()
        if (has_gain) {
          yv <- df$gain_db; ok <- !is.na(xv) & !is.na(yv)
          p  <- p %>% add_trace(type = "scatter", mode = "lines+markers",
            x = xv[ok], y = yv[ok], yaxis = "y", name = "AM-AM (dB)",
            line = list(color = "#ff7f11", width = 2), marker = list(color = "#ff7f11", size = 5))
        }
        if (has_ampm) {
          yv2 <- df$am_pm; ok2 <- !is.na(xv) & !is.na(yv2)
          p   <- p %>% add_trace(type = "scatter", mode = "lines+markers",
            x = xv[ok2], y = yv2[ok2], yaxis = "y2", name = "AM-PM (\u00b0)",
            line   = list(color = "#1f77b4", width = 2, dash = "dot"),
            marker = list(color = "#1f77b4", size = 5, symbol = "circle-open"))
        }
        x_lbl <- if (!is.null(df$pin_dbm)) "Pin (dBm)" else "Pout (dBm)"
        p %>% layout(
          paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
          xaxis  = list(title = x_lbl, color = "#aaa",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
          yaxis  = list(title = "AM-AM (dB)", color = "#ff7f11",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                        tickfont = list(color = "#ff7f11")),
          yaxis2 = list(title = "AM-PM (\u00b0)", color = "#1f77b4",
                        overlaying = "y", side = "right", showgrid = FALSE,
                        tickfont = list(color = "#1f77b4")),
          legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
          title  = list(text = paste0("AM-AM / AM-PM \u2014 ", .short_name(r$filename, 28L)),
                        font = list(color = "#eee", size = 14)),
          font   = list(color = "#aaa"),
          margin = list(l = 65, r = 75, t = 50, b = 60))
      }

      # ── Assemble report body ──────────────────────────────────────────────
      body <- ""
      for (id in names(ds)) {
        r  <- ds[[id]]
        ok <- isTRUE(r$success)
        df <- if (ok) r$points else NULL

        body <- paste0(body,
          "<hr style='margin:28px 0; border-color:#ccc;'/>",
          "<h2>", esc(r$filename),
          "  <span class='", if (ok) "badge-ok" else "badge-err", "'>",
          if (ok) "OK" else "failed", "</span></h2>")
        if (!ok) next

        # Summary table
        if ("table" %in% sections)
          body <- paste0(body, "<h3>Optimum Points Summary</h3>", optima_html(df))

        # Parsed metadata
        if ("meta" %in% sections && length(r$meta) > 0) {
          rows <- paste0(
            "<tr><td style='font-weight:600;padding:4px 12px 4px 6px;'>",
            esc(names(r$meta)), "</td><td style='padding:4px 6px;'>",
            esc(as.character(unlist(r$meta))), "</td></tr>", collapse = "")
          body <- paste0(body,
            "<h3>Metadata</h3>",
            "<table style='border-collapse:collapse;width:auto;margin:8px 0;'>",
            "<thead><tr><th style='padding:4px 12px 4px 6px;border-bottom:2px solid #ccc;",
            "text-align:left;'>Key</th>",
            "<th style='padding:4px 6px;border-bottom:2px solid #ccc;",
            "text-align:left;'>Value</th></tr></thead><tbody>",
            rows, "</tbody></table>")
        }

        has_gl <- !is.null(df$gl_r) && !all(is.na(df$gl_r))

        # Smith chart
        if ("smith" %in% sections && has_gl)
          body <- paste0(body, "<h3>Smith Chart \u2014 Pout &amp; PAE Contours</h3>",
                         plot_div(build_smith_fig(r, df)))

        # XY performance
        if ("xy" %in% sections)
          body <- paste0(body, "<h3>XY Performance</h3>",
                         plot_div(build_xy_fig(r, df)))

        # Nose / Tradeoff
        if ("nose" %in% sections) {
          p_nose <- build_nose_fig(r, df)
          if (!is.null(p_nose))
            body <- paste0(body, "<h3>Tradeoff / Nose Chart</h3>",
                           plot_div(p_nose))
        }

        # AM-AM / AM-PM (always included when data is present)
        p_am <- build_ampm_fig(r, df)
        if (!is.null(p_am))
          body <- paste0(body, "<h3>AM-AM / AM-PM</h3>", plot_div(p_am))
      }

      # ── Page header + CDN script ──────────────────────────────────────────
      hdr <- paste0(
        "<!DOCTYPE html><html lang='en'><head>",
        "<meta charset='UTF-8'>",
        "<meta name='viewport' content='width=device-width,initial-scale=1'>",
        "<title>", esc(title), "</title>",
        "<script src='https://cdn.plot.ly/plotly-2.35.2.min.js' charset='utf-8'></script>",
        "<style>",
        "body{font-family:Arial,sans-serif;line-height:1.6;color:#222;",
        "max-width:1100px;margin:24px auto;padding:0 20px;background:#fafafa;}",
        "h1{color:#333;border-bottom:2px solid #555;padding-bottom:10px;}",
        "h2{color:#333;margin-top:32px;border-left:4px solid #ff7f11;padding-left:10px;}",
        "h3{color:#555;margin-top:20px;}",
        "table{border-collapse:collapse;width:100%;margin:10px 0;}",
        "th,td{border:1px solid #ddd;padding:5px 10px;text-align:left;font-size:13px;}",
        "th{background:#ececec;font-weight:600;}",
        "tr:hover{background:#f5f5f5;}",
        ".badge-ok{background:#2ca02c;color:#fff;border-radius:3px;",
        "padding:2px 8px;font-size:12px;font-weight:600;}",
        ".badge-err{background:#d62728;color:#fff;border-radius:3px;",
        "padding:2px 8px;font-size:12px;font-weight:600;}",
        ".meta-info{color:#666;font-size:14px;margin:4px 0;}",
        "</style></head><body>",
        "<h1>", esc(title), "</h1>",
        if (nzchar(engineer)) paste0("<p class='meta-info'><strong>Engineer:</strong> ",
                                     esc(engineer), "</p>") else "",
        if (nzchar(project))  paste0("<p class='meta-info'><strong>Project:</strong> ",
                                     esc(project),  "</p>") else "",
        "<p class='meta-info'><strong>Generated:</strong> ",
        esc(as.character(Sys.time())), "</p>",
        "<p class='meta-info'><strong>Datasets:</strong> ", length(ds), "</p>"
      )

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
