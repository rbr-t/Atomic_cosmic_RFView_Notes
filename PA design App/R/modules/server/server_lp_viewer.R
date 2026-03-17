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

  # ── DuckDB in-memory backend ──────────────────────────────────────────────
  # Each dataset's points data.frame is written here immediately after parse;
  # r$points is then set to NULL so large files never accumulate in R memory.
  lp_con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  session$onSessionEnded(function() {
    tryCatch(duckdb::dbDisconnect(lp_con, shutdown = TRUE),
             error = function(e) NULL)
  })

  # ── Pure-R LTTB downsampler ───────────────────────────────────────────────
  # Largest-Triangle-Three-Buckets: reduces n points to at most max_pts while
  # preserving the visual shape.  No package dependency required.
  .lttb <- function(x, y, max_pts = 500L) {
    n <- length(x)
    if (n <= max_pts || max_pts < 3L) return(list(x = x, y = y))
    bucket_size <- (n - 2) / (max_pts - 2)
    out_x <- x[1]; out_y <- y[1]
    a <- 1L
    for (i in seq_len(max_pts - 2L)) {
      rng_s <- floor((i + 1) * bucket_size) + 1L
      rng_e <- min(floor((i + 2) * bucket_size) + 1L, n)
      avg_x <- mean(x[rng_s:rng_e], na.rm = TRUE)
      avg_y <- mean(y[rng_s:rng_e], na.rm = TRUE)
      b_s   <- floor(i * bucket_size) + 1L
      b_e   <- min(floor((i + 1) * bucket_size), n)
      areas <- abs((x[a] - avg_x) * (y[b_s:b_e] - y[a]) -
                   (x[a] - x[b_s:b_e]) * (avg_y - y[a])) * 0.5
      bi    <- b_s + which.max(areas) - 1L
      out_x <- c(out_x, x[bi]); out_y <- c(out_y, y[bi])
      a     <- bi
    }
    list(x = c(out_x, x[n]), y = c(out_y, y[n]))
  }

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

        id  <- make.names(fname, unique = FALSE)

        # Write points to DuckDB and drop from R memory
        if (isTRUE(result$success) && !is.null(result$points)) {
          tbl <- paste0("lp_", gsub("[^A-Za-z0-9_]", "_", id))
          tryCatch({
            if (DBI::dbExistsTable(lp_con, tbl))
              DBI::dbRemoveTable(lp_con, tbl)
            DBI::dbWriteTable(lp_con, tbl, result$points)
            result$nrows     <- nrow(result$points)
            result$tbl_name  <- tbl
            result$col_names <- names(result$points)
            result$points    <- NULL   # free R memory
            log <- c(log, sprintf("    \u2192 DuckDB: %d rows \u00d7 %d cols stored in '%s'",
                                  result$nrows, length(result$col_names), tbl))
          }, error = function(e) {
            log <<- c(log, paste0("    WARNING: DuckDB write failed: ", e$message,
                                  " \u2014 keeping data.frame in memory"))
            result$nrows     <<- nrow(result$points)
            result$col_names <<- names(result$points)
          })
        }

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
      if (!is.null(r$col_names) && length(r$col_names) > 0) {
        avail <- r$col_names
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
      status_txt <- if (ok) paste0("OK \u00b7 ", r$nrows %||% 0L, " pts") else "Failed"
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
    r <- current[[del_id]]
    # Clean up DuckDB table to free in-memory storage
    if (!is.null(r$tbl_name) && DBI::dbExistsTable(lp_con, r$tbl_name))
      tryCatch(DBI::dbRemoveTable(lp_con, r$tbl_name), error = function(e) NULL)
    fname   <- r$filename
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
    output[[paste0(output_id, "_ui")]] <- renderUI({
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
  .make_selector("lp_ampm_dataset_selector",   "Dataset",    FALSE)
  .make_selector("lp_nose_dataset_selector",   "Dataset",    FALSE)
  .make_selector("lp_table_dataset_selector",  "Dataset",    FALSE)
  .make_selector("lp_compare_selector",        "Dataset(s)", TRUE)

  # ── Helper: pull normalised data.frame for a dataset id ─────────────────
  # cols: optional character vector of column names to SELECT (saves I/O)
  .get_df <- function(id, cols = NULL) {
    ds <- lp_datasets()
    if (is.null(id) || length(id) == 0 || !id %in% names(ds)) return(NULL)
    r  <- ds[[id]]
    if (!isTRUE(r$success)) return(NULL)

    # DuckDB path (normal case — points were offloaded)
    if (!is.null(r$tbl_name) && DBI::dbExistsTable(lp_con, r$tbl_name)) {
      sel <- if (!is.null(cols)) {
        valid <- intersect(cols, r$col_names)
        if (length(valid) == 0) return(NULL)
        paste(paste0('"', valid, '"'), collapse = ", ")
      } else "*"
      tryCatch(
        DBI::dbGetQuery(lp_con,
          paste0("SELECT ", sel, " FROM \"", r$tbl_name, "\"")),
        error = function(e) NULL
      )
    # Fallback: data.frame still in memory (DuckDB write failed or legacy)
    } else if (!is.null(r$points) && nrow(r$points) > 0) {
      if (!is.null(cols)) {
        valid <- intersect(cols, names(r$points))
        if (length(valid) == 0) return(NULL)
        r$points[, valid, drop = FALSE]
      } else {
        r$points
      }
    } else NULL
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
    z0_norm   <- as.numeric(input$lp_smith_z0_norm %||% 50)
    if (!is.finite(z0_norm) || z0_norm <= 0) z0_norm <- 50
    do_norm   <- abs(z0_norm - 50) > 0.1          # only transform if ≠ 50 Ω
    px_db     <- as.numeric(input$lp_smith_px_db  %||% 0)
    px_tol    <- as.numeric(input$lp_smith_px_tol %||% 0.3)
    do_px     <- is.finite(px_db) && px_db > 0.01

    # Helper: re-normalise Gamma from Z0=50 to z0_norm
    .renorm_gamma <- function(gr, gi) {
      z_r <- 50 * (1 - gr^2 - gi^2) / ((1 - gr)^2 + gi^2)
      z_x <- 50 * 2 * gi            / ((1 - gr)^2 + gi^2)
      d   <- (z_r + z0_norm)^2 + z_x^2
      list(r = ((z_r - z0_norm) * (z_r + z0_norm) + z_x^2) / d,
           i = 2 * z_x * z0_norm / d)
    }

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
    show_stab <- isTRUE(input$lp_show_stability)

    if (length(sel_ids) > 0 && length(vars) > 0) {
      for (id in sel_ids) {
        # Column-targeted query: only fetch Γ columns + requested metric columns
        # Also fetch gain_db when Px compression filter is active.
        metric_cols <- vapply(vars, function(v) {
          vm <- var_meta[[v]]; if (is.null(vm)) NA_character_ else vm$col
        }, character(1))
        gamma_cols <- c("gl_r","gl_i","gs_r","gs_i","gl2_r","gl2_i","gl3_r","gl3_i")
        need_cols  <- unique(c(gamma_cols, na.omit(metric_cols),
                               if (do_px) "gain_db" else NULL))
        df    <- .get_df(id, cols = need_cols)
        if (is.null(df)) next
        r     <- ds[[id]]
        fname <- .short_name(r$filename)

        # ── Px compression filter ───────────────────────────────────────────
        if (do_px && "gain_db" %in% names(df) && !all(is.na(df$gain_db))) {
          g_lin <- max(df$gain_db[seq_len(min(5L, nrow(df)))], na.rm = TRUE)
          compr <- g_lin - df$gain_db           # 0 at small signal, + at compression
          df    <- df[!is.na(compr) & abs(compr - px_db) <= px_tol, , drop = FALSE]
          if (nrow(df) == 0) next
        }

        xv_all <- if (pull == "load") df$gl_r else df$gs_r
        yv_all <- if (pull == "load") df$gl_i else df$gs_i
        if (is.null(xv_all) || all(is.na(xv_all))) next

        # ── Γ re-normalisation ──────────────────────────────────────────────
        if (do_norm) {
          nr <- .renorm_gamma(xv_all, yv_all)
          xv_all <- nr$r; yv_all <- nr$i
          if (!is.null(df$gs_r)) {
            nrs <- .renorm_gamma(df$gs_r, df$gs_i)
            df$gs_r <- nrs$r; df$gs_i <- nrs$i
          }
          for (hcol in c("gl2_r","gl2_i","gl3_r","gl3_i")) {
            if (hcol %in% names(df)) {
              tag <- if (grepl("_r$", hcol)) "_r" else "_i"
              pfx <- sub("_[ri]$", "", hcol)
              r_col <- paste0(pfx, "_r"); i_col <- paste0(pfx, "_i")
              if (all(c(r_col, i_col) %in% names(df))) {
                nh <- .renorm_gamma(df[[r_col]], df[[i_col]])
                df[[r_col]] <- nh$r; df[[i_col]] <- nh$i
              }
            }
          }
        }

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

          # Try cache first (only valid for 50-Ω reference; skip when re-normalised)
          cache_key  <- paste0(pull, ":", v)
          cached     <- if (!do_norm) r$interp_cache[[cache_key]] else NULL
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
              opacity = 0.60,
              marker = list(color = zv, colorscale = "Viridis", size = 7,
                            opacity = 0.55,
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

    # ── Stability circles (output plane) ────────────────────────────────────
    # Computed from S-parameters if present in a dataset; one circle per dataset.
    if (show_stab && length(sel_ids) > 0) {
      STAB_COLS <- c("s11_mag","s11_ang","s12_mag","s12_ang",
                     "s21_mag","s21_ang","s22_mag","s22_ang")
      n_sc <- 0L
      for (id in sel_ids) {
        r  <- lp_datasets()[[id]]
        if (is.null(r) || !isTRUE(r$success)) next
        avail <- r$col_names %||% character(0)
        if (!all(STAB_COLS %in% avail)) next

        df_s <- .get_df(id, cols = c(STAB_COLS, "freq_ghz"))
        if (is.null(df_s) || nrow(df_s) == 0) next

        # Use first (or most common) row as representative S-parameter set
        df_s <- df_s[1L, , drop = FALSE]
        s11 <- df_s$s11_mag * exp(1i * df_s$s11_ang * pi / 180)
        s12 <- df_s$s12_mag * exp(1i * df_s$s12_ang * pi / 180)
        s21 <- df_s$s21_mag * exp(1i * df_s$s21_ang * pi / 180)
        s22 <- df_s$s22_mag * exp(1i * df_s$s22_ang * pi / 180)
        det_s <- s11 * s22 - s12 * s21

        denom_out <- Mod(s11)^2 - Mod(det_s)^2
        if (abs(denom_out) < 1e-12) next

        C_out <- Conj(s11 - det_s * Conj(s22)) / denom_out
        r_out <- abs(Mod(s12 * s21) / abs(denom_out))

        # Draw circle on Smith chart
        theta_sc <- seq(0, 2*pi, length.out = 200)
        cx <- Re(C_out); cy <- Im(C_out)
        sc_x <- cx + r_out * cos(theta_sc)
        sc_y <- cy + r_out * sin(theta_sc)
        sc_col <- c("#e377c2","#17becf","#bcbd22","#8c564b")[n_sc %% 4L + 1L]
        n_sc   <- n_sc + 1L
        fname  <- .short_name(r$filename, 20L)
        p <- p %>% add_trace(type="scatter", mode="lines",
          x=sc_x, y=sc_y,
          line=list(color=sc_col, width=1.8, dash="dash"),
          name=paste0("Stab-out [",fname,"]"),
          hovertext=sprintf("Output stability circle<br>%s<br>C=(%.3f%+.3fj) r=%.3f",
                            fname, cx, cy, r_out),
          hoverinfo="text", showlegend=TRUE)
      }
      if (n_sc == 0L) {
        # No S-params available — add a placeholder text trace
        p <- p %>% add_trace(type="scatter", mode="text",
          x=0, y=0,
          text="S-params needed for stability circles",
          textfont=list(color="#e8a000",size=11),
          hoverinfo="none", showlegend=FALSE, name="stab_note")
      }
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
    if (is.null(id) || length(id) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset",font=list(color="#aaa"))))
    id     <- id[1L]   # guard against duplicate-ID vector artefact
    y_vars <- input$lp_xy_y_vars
    x_var  <- input$lp_xy_x_var %||% "pin_dbm"

    # Column-targeted query — only fetch the columns this plot actually needs
    need   <- unique(c(x_var, y_vars))
    df     <- .get_df(id, cols = need)

    if (is.null(df) || length(y_vars) == 0 || !x_var %in% names(df)) {
      return(plot_ly() %>% layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title = list(text = "No data — select a dataset",
                     font = list(color = "#aaa"))
      ))
    }

# Efficiency variables go on Y2 (right axis)
      EFF_VARS <- c("pae_pct", "de_pct")

      # Sort by X so the scatter follows the power sweep direction
      ord <- order(df[[x_var]], na.last = NA)
      df  <- df[ord, , drop = FALSE]

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
        # Pure scatter — LP data has one point per (impedance, power) combination;
        # connecting points with lines produces misleading vertical jumps.
        p <- p %>% add_trace(
          type   = "scattergl", mode = "markers",
          x      = xv[ok], y = yv[ok],
          yaxis  = if (on_y2) "y2" else "y",
          name   = lbl,
          opacity = 0.80,
          marker = list(color = col, size = 5,
                        symbol = if (on_y2) "circle-open" else "circle",
                        opacity = 0.70)
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

  # ── Performance tab — dataset selector ────────────────────────────────────
  .make_selector("lp_perf_dataset_selector", "Dataset", FALSE)

  # ── Helper: re-normalise Gamma assuming original Z0=50 ────────────────────
  .renorm_g <- function(gr, gi, z0) {
    if (abs(z0 - 50) < 0.1) return(list(r = gr, i = gi))
    z_r <- 50 * (1 - gr^2 - gi^2) / ((1 - gr)^2 + gi^2)
    z_x <- 50 * 2 * gi            / ((1 - gr)^2 + gi^2)
    d   <- (z_r + z0)^2 + z_x^2
    list(r = ((z_r - z0) * (z_r + z0) + z_x^2) / d,
         i = 2 * z_x * z0 / d)
  }

  # ── Performance: Gain subplot ──────────────────────────────────────────────
  output$lp_perf_gain_plot <- renderPlotly({
    id    <- input$lp_perf_dataset_selector
    x_var <- input$lp_perf_x_var   %||% "pin_dbm"
    y2_v  <- input$lp_perf_gain_y2 %||% "none"
    need  <- unique(c(x_var, "gain_db", if (y2_v != "none") y2_v))
    df    <- .get_df(id, cols = need)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title = list(text=m, font=list(color="#aaa")))
    if (is.null(df) || !x_var %in% names(df)) return(ep("No data"))
    ord <- order(df[[x_var]], na.last = NA); df <- df[ord, , drop=FALSE]
    xv  <- df[[x_var]]; p <- plot_ly()
    if ("gain_db" %in% names(df)) {
      yv <- df$gain_db; ok <- !is.na(xv) & !is.na(yv)
      p  <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok], y=yv[ok], yaxis="y", name="Gain (dB)",
               marker=list(color="#ff7f11",size=5,opacity=0.75))
    }
    y2_lbl <- ""
    if (y2_v != "none" && y2_v %in% names(df)) {
      yv2 <- df[[y2_v]]; ok2 <- !is.na(xv) & !is.na(yv2)
      y2_lbl <- switch(y2_v, pae_pct="PAE (%)", de_pct="DE (%)",
                              pout_dbm="Pout (dBm)", pout_w="Pout (W)", y2_v)
      p <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok2], y=yv2[ok2], yaxis="y2", name=y2_lbl,
               marker=list(color="#1f77b4",size=5,symbol="circle-open",opacity=0.75))
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl,         color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="Gain (dB)", color="#ff7f11", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#ff7f11")),
      yaxis2 = list(title=y2_lbl, color="#1f77b4", overlaying="y", side="right", showgrid=FALSE, zeroline=FALSE, tickfont=list(color="#1f77b4")),
      legend=list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.3)"),
      title=list(text="Gain", font=list(color="#eee",size=13)),
      font=list(color="#aaa"), margin=list(l=60,r=60,t=35,b=50))
  })

  # ── Performance: Efficiency subplot ───────────────────────────────────────
  output$lp_perf_eff_plot <- renderPlotly({
    id    <- input$lp_perf_dataset_selector
    x_var <- input$lp_perf_x_var  %||% "pin_dbm"
    y2_v  <- input$lp_perf_eff_y2 %||% "none"
    need  <- unique(c(x_var, "pae_pct", "de_pct", if (y2_v != "none") y2_v))
    df    <- .get_df(id, cols = need)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(df) || !x_var %in% names(df)) return(ep("No data"))
    ord <- order(df[[x_var]], na.last=NA); df <- df[ord, , drop=FALSE]
    xv <- df[[x_var]]; p <- plot_ly()
    PAL_EFF <- c("#1f77b4","#2ca02c")
    ic <- 1L
    for (ev in c("pae_pct","de_pct")) {
      if (!ev %in% names(df)) { ic <- ic + 1L; next }
      yv <- df[[ev]]; ok <- !is.na(xv) & !is.na(yv)
      cl <- PAL_EFF[(ic-1L) %% 2L + 1L]; ic <- ic + 1L
      lbl <- if (ev=="pae_pct") "PAE (%)" else "DE (%)"
      p <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok], y=yv[ok], yaxis="y", name=lbl,
               marker=list(color=cl,size=5,opacity=0.75))
    }
    y2_lbl <- ""
    if (y2_v != "none" && y2_v %in% names(df)) {
      yv2 <- df[[y2_v]]; ok2 <- !is.na(xv) & !is.na(yv2)
      y2_lbl <- switch(y2_v, gain_db="Gain (dB)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", y2_v)
      p <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok2], y=yv2[ok2], yaxis="y2", name=y2_lbl,
               marker=list(color="#ff7f11",size=5,symbol="circle-open",opacity=0.75))
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl,          color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="Efficiency (%)", color="#1f77b4", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#1f77b4")),
      yaxis2 = list(title=y2_lbl, color="#ff7f11", overlaying="y", side="right", showgrid=FALSE, zeroline=FALSE, tickfont=list(color="#ff7f11")),
      legend=list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.3)"),
      title=list(text="Efficiency", font=list(color="#eee",size=13)),
      font=list(color="#aaa"), margin=list(l=60,r=60,t=35,b=50))
  })

  # ── Performance: Smith Source (Γ_S) ───────────────────────────────────────
  output$lp_perf_smith_s <- renderPlotly({
    id        <- input$lp_perf_dataset_selector
    z0        <- as.numeric(input$lp_perf_z0_norm %||% 50)
    px_db_p   <- as.numeric(input$lp_perf_px_db   %||% 0)
    px_tol_p  <- as.numeric(input$lp_perf_px_tol  %||% 0.3)
    show_harm <- isTRUE(input$lp_perf_show_harmonics)
    show_opt  <- isTRUE(input$lp_perf_show_opt %||% TRUE)
    df        <- .get_df(id, cols = c("gs_r","gs_i","pout_dbm","gain_db","pae_pct",
                                       if (show_harm) c("gs2_r","gs2_i","gs3_r","gs3_i")))
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(df) || !"gs_r" %in% names(df)) return(ep("No source-pull \u0393_S data"))
    # Px filter
    if (px_db_p > 0.01 && "gain_db" %in% names(df)) {
      g_lin <- max(df$gain_db[seq_len(min(5L,nrow(df)))], na.rm=TRUE)
      compr <- g_lin - df$gain_db
      df    <- df[!is.na(compr) & abs(compr - px_db_p) <= px_tol_p, , drop=FALSE]
    }
    # Γ normalization
    ng <- .renorm_g(df$gs_r, df$gs_i, z0)
    xv <- ng$r; yv <- ng$i
    cv <- df$pout_dbm %||% rep(NA_real_, nrow(df))
    ok <- !is.na(xv) & !is.na(yv) & (xv^2 + yv^2) <= 1.02
    grid <- build_smith_grid(); p <- plot_ly()
    for (tr in grid) p <- p %>% add_trace(type="scatter",mode="lines",
      x=tr$x,y=tr$y,line=tr$line,hoverinfo="none",showlegend=FALSE,name=tr$name)
    p <- p %>% add_trace(type="scattergl",mode="markers",
      x=xv[ok],y=yv[ok],
      opacity=0.65,
      marker=list(color=cv[ok],colorscale="Jet",size=7,showscale=TRUE,
                  opacity=0.60,
                  colorbar=list(title="Pout(dBm)",len=0.6,
                               tickfont=list(color="#aaa",size=9),
                               titlefont=list(color="#aaa",size=10))),
      name="Γ_S", hoverinfo="text",
      hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
        "Re(Γ_S): %.4f<br>Im(Γ_S): %.4f<br>R_S: %.2f Ω<br>X_S: %.2f Ω<br>Pout: %.1f dBm",
        xv[ok],yv[ok],zz$r,zz$x,cv[ok])})
    if (show_harm) {
      for (h in list(list(r="gs2_r",i="gs2_i",lbl="2H Γ_S",col="#e377c2"),
                     list(r="gs3_r",i="gs3_i",lbl="3H Γ_S",col="#17becf"))) {
        if (!all(c(h$r,h$i) %in% names(df))) next
        ngh <- .renorm_g(df[[h$r]], df[[h$i]], z0)
        ok_h <- !is.na(ngh$r) & !is.na(ngh$i)
        if (sum(ok_h)==0) next
        p <- p %>% add_trace(type="scatter",mode="markers",
          x=ngh$r[ok_h],y=ngh$i[ok_h],
          marker=list(color=h$col,size=6,symbol="x",opacity=0.8),
          name=h$lbl,showlegend=TRUE,hoverinfo="none")
      }
    }
    if (show_opt) {
      opt <- .find_optima(df)
      OC  <- list(MXP=list(col="pout_dbm",sym="star",color="#ff7f11"),
                  MXE=list(col="pae_pct", sym="diamond",color="#1f77b4"),
                  MXG=list(col="gain_db", sym="triangle-up",color="#2ca02c"))
      for (nm in names(OC)) {
        bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
        if (!cfg$col %in% names(df)) next
        ng_o <- .renorm_g(df$gs_r[bi], df$gs_i[bi], z0)
        p <- p %>% add_trace(type="scatter",mode="markers+text",
          x=ng_o$r,y=ng_o$i,
          text=sprintf("%s\n%.1f",nm,df[[cfg$col]][bi]),textposition="top center",
          textfont=list(color=cfg$color,size=10),
          marker=list(color=cfg$color,size=14,symbol=cfg$sym,
                      line=list(color="white",width=1.5)),
          name=nm,showlegend=TRUE)
      }
    }
    z_lbl <- if (abs(z0-50)<0.1) "50\u03a9" else sprintf("%.0f\u03a9",z0)
    sl <- .smith_layout(title_txt=paste0("Source \u0393_S  (Z\u2080=",z_lbl,")"),
                        xl="Re(\u0393_S)", yl="Im(\u0393_S)")
    p %>% layout(sl)
  })

  # ── Performance: Smith Load (Γ_L) ─────────────────────────────────────────
  output$lp_perf_smith_l <- renderPlotly({
    id        <- input$lp_perf_dataset_selector
    z0        <- as.numeric(input$lp_perf_z0_norm %||% 50)
    px_db_p   <- as.numeric(input$lp_perf_px_db   %||% 0)
    px_tol_p  <- as.numeric(input$lp_perf_px_tol  %||% 0.3)
    show_harm <- isTRUE(input$lp_perf_show_harmonics)
    show_opt  <- isTRUE(input$lp_perf_show_opt %||% TRUE)
    df        <- .get_df(id, cols = c("gl_r","gl_i","pout_dbm","gain_db","pae_pct",
                                       if (show_harm) c("gl2_r","gl2_i","gl3_r","gl3_i")))
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(df) || !"gl_r" %in% names(df)) return(ep("No load-pull \u0393_L data"))
    if (px_db_p > 0.01 && "gain_db" %in% names(df)) {
      g_lin <- max(df$gain_db[seq_len(min(5L,nrow(df)))], na.rm=TRUE)
      compr <- g_lin - df$gain_db
      df    <- df[!is.na(compr) & abs(compr - px_db_p) <= px_tol_p, , drop=FALSE]
    }
    ng <- .renorm_g(df$gl_r, df$gl_i, z0)
    xv <- ng$r; yv <- ng$i
    cv <- df$pout_dbm %||% rep(NA_real_, nrow(df))
    ok <- !is.na(xv) & !is.na(yv) & (xv^2 + yv^2) <= 1.02
    grid <- build_smith_grid(); p <- plot_ly()
    for (tr in grid) p <- p %>% add_trace(type="scatter",mode="lines",
      x=tr$x,y=tr$y,line=tr$line,hoverinfo="none",showlegend=FALSE,name=tr$name)
    p <- p %>% add_trace(type="scattergl",mode="markers",
      x=xv[ok],y=yv[ok],
      opacity=0.65,
      marker=list(color=cv[ok],colorscale="Jet",size=7,showscale=TRUE,
                  opacity=0.60,
                  colorbar=list(title="Pout(dBm)",len=0.6,
                               tickfont=list(color="#aaa",size=9),
                               titlefont=list(color="#aaa",size=10))),
      name="Γ_L", hoverinfo="text",
      hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
        "Re(Γ_L): %.4f<br>Im(Γ_L): %.4f<br>R_L: %.2f Ω<br>X_L: %.2f Ω<br>Pout: %.1f dBm",
        xv[ok],yv[ok],zz$r,zz$x,cv[ok])})
    if (show_harm) {
      for (h in list(list(r="gl2_r",i="gl2_i",lbl="2H Γ_L",col="#e377c2"),
                     list(r="gl3_r",i="gl3_i",lbl="3H Γ_L",col="#17becf"))) {
        if (!all(c(h$r,h$i) %in% names(df))) next
        ngh <- .renorm_g(df[[h$r]], df[[h$i]], z0)
        ok_h <- !is.na(ngh$r) & !is.na(ngh$i)
        if (sum(ok_h)==0) next
        p <- p %>% add_trace(type="scatter",mode="markers",
          x=ngh$r[ok_h],y=ngh$i[ok_h],
          marker=list(color=h$col,size=6,symbol="x",opacity=0.8),
          name=h$lbl,showlegend=TRUE,hoverinfo="none")
      }
    }
    if (show_opt) {
      opt <- .find_optima(df)
      OC  <- list(MXP=list(col="pout_dbm",sym="star",color="#ff7f11"),
                  MXE=list(col="pae_pct", sym="diamond",color="#1f77b4"),
                  MXG=list(col="gain_db", sym="triangle-up",color="#2ca02c"))
      for (nm in names(OC)) {
        bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
        if (!cfg$col %in% names(df)) next
        ng_o <- .renorm_g(df$gl_r[bi], df$gl_i[bi], z0)
        p <- p %>% add_trace(type="scatter",mode="markers+text",
          x=ng_o$r,y=ng_o$i,
          text=sprintf("%s\n%.1f",nm,df[[cfg$col]][bi]),textposition="top center",
          textfont=list(color=cfg$color,size=10),
          marker=list(color=cfg$color,size=14,symbol=cfg$sym,
                      line=list(color="white",width=1.5)),
          name=nm,showlegend=TRUE)
      }
    }
    z_lbl <- if (abs(z0-50)<0.1) "50\u03a9" else sprintf("%.0f\u03a9",z0)
    sl <- .smith_layout(title_txt=paste0("Load \u0393_L  (Z\u2080=",z_lbl,")"),
                        xl="Re(\u0393_L)", yl="Im(\u0393_L)")
    p %>% layout(sl)
  })

  # ── Nose/Tradeoff — Plot 1: Smith chart coloured by metric ───────────────
  output$lp_nose_smith <- renderPlotly({
    id       <- input$lp_nose_dataset_selector
    if (is.null(id) || length(id) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset",font=list(color="#aaa"))))
    id       <- id[1L]
    col_var  <- input$lp_nose_x_var    %||% "pout_dbm"
    z0       <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    px_db    <- as.numeric(input$lp_nose_px_db  %||% 0)
    px_tol   <- as.numeric(input$lp_nose_px_tol %||% 0.3)
    do_px    <- is.finite(px_db) && px_db > 0.01
    mark_opt <- isTRUE(input$lp_nose_mark_opt)
    pull     <- input$lp_pull_type %||% "load"

    need <- unique(c("gl_r","gl_i","gs_r","gs_i","gain_db","pout_dbm","pae_pct","de_pct",col_var))
    df   <- .get_df(id, cols = need)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
                        title=list(text=m,font=list(color="#aaa")))
    if (is.null(df)) return(ep("No data"))

    # Px filter
    if (do_px && "gain_db" %in% names(df) && !all(is.na(df$gain_db))) {
      g_lin <- max(df$gain_db[seq_len(min(5L,nrow(df)))], na.rm=TRUE)
      compr <- g_lin - df$gain_db
      df    <- df[!is.na(compr) & abs(compr - px_db) <= px_tol, , drop=FALSE]
      if (nrow(df) == 0) return(ep("No data after Px filter — adjust tolerance"))
    }

    xv_all <- if (pull == "load") df$gl_r else df$gs_r
    yv_all <- if (pull == "load") df$gl_i else df$gs_i
    if (is.null(xv_all) || all(is.na(xv_all)))
      return(ep(paste0("No \u0393","_",if(pull=="load")"L" else "S"," data")))

    # Re-normalise Gamma
    ng <- .renorm_g(xv_all, yv_all, z0)
    xv <- ng$r; yv <- ng$i

    cv  <- if (col_var %in% names(df)) df[[col_var]] else rep(NA_real_, nrow(df))
    ok  <- !is.na(xv) & !is.na(yv) & !is.na(cv) & (xv^2 + yv^2) <= 1.02
    col_lbl <- switch(col_var, pout_dbm="Pout (dBm)", pae_pct="PAE (%)",
                      gain_db="Gain (dB)", de_pct="DE (%)", pin_dbm="Pin (dBm)", col_var)

    grid <- build_smith_grid(); p <- plot_ly()
    for (tr in grid) p <- p %>% add_trace(type="scatter",mode="lines",
      x=tr$x,y=tr$y,line=tr$line,hoverinfo="none",showlegend=FALSE,name=tr$name)

    p <- p %>% add_trace(type="scattergl", mode="markers",
      x=xv[ok], y=yv[ok],
      opacity = 0.70,
      marker = list(color=cv[ok], colorscale="Jet", size=7, showscale=TRUE,
                    opacity=0.65,
                    colorbar=list(title=col_lbl, tickfont=list(color="#aaa",size=9),
                                  titlefont=list(color="#aaa",size=10))),
      hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
        "%s: %.2f<br>Re(\u0393): %.4f<br>Im(\u0393): %.4f<br>R: %.2f \u03a9<br>X: %.2f \u03a9",
        col_lbl,cv[ok],xv[ok],yv[ok],zz$r,zz$x)},
      hoverinfo="text", name=col_lbl)

    if (mark_opt) {
      opt <- .find_optima(df)
      OC  <- list(MXP=list(col="pout_dbm",sym="star",      color="#ff7f11"),
                  MXE=list(col="pae_pct", sym="diamond",   color="#1f77b4"),
                  MXG=list(col="gain_db", sym="triangle-up",color="#2ca02c"))
      for (nm in names(OC)) {
        bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
        if (!cfg$col %in% names(df)) next
        ox_raw <- if(pull=="load") df$gl_r[bi] else df$gs_r[bi]
        oy_raw <- if(pull=="load") df$gl_i[bi] else df$gs_i[bi]
        if (any(is.na(c(ox_raw,oy_raw)))) next
        ng_o <- .renorm_g(ox_raw, oy_raw, z0)
        p <- p %>% add_trace(type="scatter",mode="markers+text",
          x=ng_o$r, y=ng_o$i,
          text=sprintf("%s\n%.2f",nm,df[[cfg$col]][bi]), textposition="top center",
          textfont=list(color=cfg$color,size=10),
          marker=list(color=cfg$color,size=14,symbol=cfg$sym,
                      line=list(color="white",width=1.5)),
          name=nm, showlegend=TRUE)
      }
    }

    z_lbl <- if (abs(z0-50)<0.1) "50\u03a9" else sprintf("%.0f\u03a9",z0)
    sl <- .smith_layout(
      title_txt=paste0("Tradeoff \u2014 coloured by ",col_lbl," (Z\u2080=",z_lbl,")"),
      xl=paste0("Re(\u0393_",if(pull=="load")"L" else "S",")"),
      yl=paste0("Im(\u0393_",if(pull=="load")"L" else "S",")"))
    p %>% layout(sl)
  })

  # ── Nose/Tradeoff — Plot 2: Gain (Y1) and Efficiency (Y2) vs Pout/Pin ─────
  # Classic PA "nose plot": Gain scatter on primary Y-axis,
  # PAE / DE on secondary Y-axis, X = Pout (dBm) by default.
  output$lp_nose_xy <- renderPlotly({
    id     <- input$lp_nose_dataset_selector
    if (is.null(id) || length(id) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset",font=list(color="#aaa"))))
    id     <- id[1L]
    x_var  <- input$lp_nose_x_pw  %||% "pout_dbm"
    z0     <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    px_db  <- as.numeric(input$lp_nose_px_db  %||% 2.2)
    px_tol <- as.numeric(input$lp_nose_px_tol %||% 0.3)
    do_px  <- is.finite(px_db) && px_db > 0.01
    mark_opt <- isTRUE(input$lp_nose_mark_opt)

    need <- unique(c("gain_db","pae_pct","de_pct",x_var))
    df   <- .get_df(id, cols = need)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
                        title=list(text=m,font=list(color="#aaa")))
    if (is.null(df)) return(ep("No data"))
    if (!x_var %in% names(df)) return(ep(paste0("Column '",x_var,"' not found")))

    # Px compression filter (uses gain_db already in need)
    if (do_px && "gain_db" %in% names(df) && !all(is.na(df$gain_db))) {
      g_lin <- max(df$gain_db[seq_len(min(5L,nrow(df)))], na.rm=TRUE)
      compr <- g_lin - df$gain_db
      df    <- df[!is.na(compr) & abs(compr - px_db) <= px_tol, , drop=FALSE]
      if (nrow(df) == 0) return(ep("No data after Px filter \u2014 adjust tolerance"))
    }

    xv <- df[[x_var]]
    p  <- plot_ly()

    # Gain on primary Y
    if ("gain_db" %in% names(df)) {
      yv <- df$gain_db; ok <- !is.na(xv) & !is.na(yv)
      p  <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok], y=yv[ok], yaxis="y", name="Gain (dB)",
               opacity=0.80,
               marker=list(color="#ff7f11", size=6, opacity=0.75))
    }

    # PAE on secondary Y (preferred); DE as fallback if PAE not available
    eff_col <- if ("pae_pct" %in% names(df) && any(!is.na(df$pae_pct))) "pae_pct" else
               if ("de_pct"  %in% names(df) && any(!is.na(df$de_pct)))  "de_pct"  else NULL
    eff_lbl <- if (!is.null(eff_col)) switch(eff_col, pae_pct="PAE (%)", de_pct="DE (%)") else ""
    if (!is.null(eff_col)) {
      yv2 <- df[[eff_col]]; ok2 <- !is.na(xv) & !is.na(yv2)
      p   <- p %>% add_trace(type="scattergl", mode="markers",
               x=xv[ok2], y=yv2[ok2], yaxis="y2", name=eff_lbl,
               opacity=0.80,
               marker=list(color="#1f77b4", size=6, symbol="circle-open", opacity=0.75))
    }

    # Mark MXP / MXE / MXG
    if (mark_opt) {
      opt <- .find_optima(df)
      OC  <- list(MXP=list(col="pout_dbm",sym="star",      color="#ff7f11", y2=FALSE),
                  MXE=list(col="pae_pct", sym="diamond",   color="#1f77b4", y2=TRUE),
                  MXG=list(col="gain_db", sym="triangle-up",color="#2ca02c", y2=FALSE))
      for (nm in names(OC)) {
        bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
        yv_opt <- if (cfg$y2 && !is.null(eff_col)) df[[eff_col]][bi] else {
          if ("gain_db" %in% names(df)) df$gain_db[bi] else next
        }
        xv_opt <- if (x_var %in% names(df)) df[[x_var]][bi] else next
        if (is.na(xv_opt) || is.na(yv_opt)) next
        p <- p %>% add_trace(type="scatter", mode="markers+text",
          x=xv_opt, y=yv_opt,
          yaxis=if(cfg$y2)"y2" else "y",
          text=sprintf("%s\n%.2f",nm,yv_opt), textposition="top center",
          textfont=list(color=cfg$color,size=9),
          marker=list(color=cfg$color,size=12,symbol=cfg$sym,
                      line=list(color="white",width=1.5)),
          name=nm, showlegend=TRUE)
      }
    }

    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)",
                         pout_w="Pout (W)", gsub("_"," ",x_var))
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE,
                    gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="Gain (dB)", color="#ff7f11",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color="#ff7f11")),
      yaxis2 = list(title=eff_lbl, color="#1f77b4",
                    overlaying="y", side="right", showgrid=FALSE,
                    zeroline=FALSE, tickfont=list(color="#1f77b4")),
      legend=list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.3)"),
      title=list(text=paste0("Nose Plot \u2014 Gain & Efficiency vs ",xl),
                 font=list(color="#eee",size=13)),
      font=list(color="#aaa"), margin=list(l=65,r=70,t=40,b=50))
  })

  # ── Table helpers ──────────────────────────────────────────────────────────
  .perf_row_at <- function(df, bi) {
    if (length(bi) == 0 || is.na(bi[1])) return(NULL)
    row <- df[bi[1], , drop = FALSE]
    gl_r <- if ("gl_r" %in% names(row)) row$gl_r else NA_real_
    gl_i <- if ("gl_i" %in% names(row)) row$gl_i else NA_real_
    gs_r <- if ("gs_r" %in% names(row)) row$gs_r else NA_real_
    gs_i <- if ("gs_i" %in% names(row)) row$gs_i else NA_real_
    zl   <- .gamma_to_z(gl_r, gl_i)
    zs   <- .gamma_to_z(gs_r, gs_i)
    data.frame(
      Pout_dBm = round(if ("pout_dbm" %in% names(row)) row$pout_dbm else NA_real_, 2),
      Gain_dB  = round(if ("gain_db"  %in% names(row)) row$gain_db  else NA_real_, 2),
      PAE_pct  = round(if ("pae_pct"  %in% names(row)) row$pae_pct  else NA_real_, 2),
      DE_pct   = round(if ("de_pct"   %in% names(row)) row$de_pct   else NA_real_, 2),
      Pin_dBm  = round(if ("pin_dbm"  %in% names(row)) row$pin_dbm  else NA_real_, 2),
      Freq_GHz = round(if ("freq_ghz" %in% names(row)) row$freq_ghz else NA_real_, 4),
      Gamma_L  = sprintf("%.3f %+.3fj", gl_r, gl_i),
      ZL_Ohm   = sprintf("%.2f %+.2fj", round(zl$r, 2), round(zl$x, 2)),
      Gamma_S  = sprintf("%.3f %+.3fj", gs_r, gs_i),
      ZS_Ohm   = sprintf("%.2f %+.2fj", round(zs$r, 2), round(zs$x, 2)),
      stringsAsFactors = FALSE
    )
  }

  # Split dataframe into per-frequency sub-frames
  .by_freq <- function(df) {
    if ("freq_ghz" %in% names(df) && length(unique(na.omit(df$freq_ghz))) > 1) {
      freqs <- sort(unique(na.omit(df$freq_ghz)))
      lapply(freqs, function(f)
        list(freq = f, df = df[!is.na(df$freq_ghz) & df$freq_ghz == f, , drop = FALSE]))
    } else {
      list(list(freq = NA_real_, df = df))
    }
  }

  # ── Tabular: Optimum operating points (MXP / MXE / MXG) per frequency ─────
  output$lp_table_optima <- DT::renderDT({
    id <- input$lp_table_dataset_selector
    df <- .get_df(id)
    if (is.null(df)) return(data.frame())
    rows <- list()
    for (grp in .by_freq(df)) {
      gdf  <- grp$df
      freq <- grp$freq
      f_lbl <- if (is.na(freq)) "" else sprintf("%.4g GHz", freq)
      opt  <- .find_optima(gdf)
      for (oname in c("MXP", "MXE", "MXG")) {
        bi <- opt[[oname]]
        if (is.na(bi)) next
        rec <- .perf_row_at(gdf, bi)
        if (is.null(rec)) next
        rec$Point   <- oname
        rec$Freq_GHz <- if (is.na(freq)) NA_real_ else round(freq, 4)
        rows[[length(rows) + 1]] <- rec[, c("Point","Freq_GHz",
          intersect(c("Pout_dBm","Gain_dB","PAE_pct","DE_pct","Pin_dBm",
                      "Gamma_L","ZL_Ohm","Gamma_S","ZS_Ohm"), names(rec)))]
      }
    }
    if (length(rows) == 0) return(data.frame())
    do.call(rbind, rows)
  }, options = list(dom = "lftip", scrollX = TRUE, pageLength = 10),
     class = "compact cell-border", rownames = FALSE)

  # ── Tabular: Ppeak (max Pout) per frequency ───────────────────────────────
  output$lp_table_ppeak <- DT::renderDT({
    id  <- input$lp_table_dataset_selector
    df  <- .get_df(id)
    if (is.null(df) || !"pout_dbm" %in% names(df)) return(data.frame())
    rows <- list()
    for (grp in .by_freq(df)) {
      gdf <- grp$df
      bi  <- which.max(gdf$pout_dbm)
      if (length(bi) == 0) next
      rec <- .perf_row_at(gdf, bi)
      if (is.null(rec)) next
      rec$Freq_GHz <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
      rows[[length(rows) + 1]] <- rec
    }
    if (length(rows) == 0) return(data.frame())
    do.call(rbind, rows)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 20),
     class = "compact cell-border", rownames = FALSE)

  # ── Tabular: Pavg (Ppeak − N dB back-off) per frequency ──────────────────
  output$lp_table_pavg <- DT::renderDT({
    id  <- input$lp_table_dataset_selector
    df  <- .get_df(id)
    if (is.null(df) || !"pout_dbm" %in% names(df)) return(data.frame())
    bo   <- as.numeric(input$lp_ppeak_backoff %||% 6)
    rows <- list()
    for (grp in .by_freq(df)) {
      gdf    <- grp$df
      max_po <- max(gdf$pout_dbm, na.rm = TRUE)
      bi     <- which.min(abs(gdf$pout_dbm - (max_po - bo)))
      if (length(bi) == 0) next
      rec <- .perf_row_at(gdf, bi)
      if (is.null(rec)) next
      rec$Freq_GHz <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
      rec$Backoff_dB <- round(bo, 1)
      rows[[length(rows) + 1]] <- rec
    }
    if (length(rows) == 0) return(data.frame())
    do.call(rbind, rows)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 20),
     class = "compact cell-border", rownames = FALSE)

  # ── Tabular: Selected design load point ───────────────────────────────────
  output$lp_table_selected_zl <- DT::renderDT({
    id    <- input$lp_table_dataset_selector
    basis <- input$lp_zl_basis %||% "MXE"
    z0    <- as.numeric(input$lp_zl_z0 %||% 50)
    df    <- .get_df(id)
    if (is.null(df)) return(data.frame())
    rows <- list()
    for (grp in .by_freq(df)) {
      gdf  <- grp$df
      freq <- grp$freq
      if (basis == "custom") {
        gr_c <- as.numeric(input$lp_zl_gamma_r %||% 0)
        gi_c <- as.numeric(input$lp_zl_gamma_i %||% 0)
        zl   <- .gamma_to_z(gr_c, gi_c, z0)
        rec  <- data.frame(
          Freq_GHz = if (is.na(freq)) NA_real_ else round(freq, 4),
          Basis    = "Custom",
          Gamma_L  = sprintf("%.3f %+.3fj", gr_c, gi_c),
          ZL_Ohm   = sprintf("%.2f %+.2fj", round(zl$r, 2), round(zl$x, 2)),
          Pout_dBm = NA_real_, Gain_dB = NA_real_,
          PAE_pct  = NA_real_, stringsAsFactors = FALSE)
      } else {
        opt <- .find_optima(gdf)
        bi  <- opt[[basis]]
        if (is.na(bi)) next
        rec  <- .perf_row_at(gdf, bi)
        if (is.null(rec)) next
        rec$Basis    <- basis
        rec$Freq_GHz <- if (is.na(freq)) NA_real_ else round(freq, 4)
        # Convert to requested Z0
        if (abs(z0 - 50) > 0.1 && "Gamma_L" %in% names(rec)) {
          gparts   <- as.numeric(strsplit(gsub("[ij]","",rec$Gamma_L),"[ ]+")[[1]])
          ng       <- .renorm_g(gparts[1], gparts[2], z0)
          zl2      <- .gamma_to_z(ng$r, ng$i, z0)
          rec$Gamma_L <- sprintf("%.3f %+.3fj", ng$r, ng$i)
          rec$ZL_Ohm  <- sprintf("%.2f %+.2fj", round(zl2$r, 2), round(zl2$x, 2))
        }
      }
      rows[[length(rows) + 1]] <- rec
    }
    if (length(rows) == 0) return(data.frame())
    out <- do.call(rbind, rows)
    keep <- intersect(c("Freq_GHz","Basis","Pout_dBm","Gain_dB","PAE_pct","DE_pct",
                        "Gamma_L","ZL_Ohm","Gamma_S","ZS_Ohm"), names(out))
    out[, keep, drop = FALSE]
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 20),
     class = "compact cell-border", rownames = FALSE)

  .clean_dt_row <- function(row) {
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

  # ── AM-AM (gain compression) ───────────────────────────────────────────────
  output$lp_amam_plot <- renderPlotly({
    id    <- input$lp_ampm_dataset_selector
    if (is.null(id) || length(id) == 0) id <- input$lp_xy_dataset_selector
    if (is.null(id) || length(id) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset",font=list(color="#aaa"))))
    id    <- id[1L]
    x_var <- input$lp_ampm_x_var %||% "pin_dbm"
    df    <- .get_df(id, cols = c("pin_dbm","pout_dbm","pout_w","gain_db"))
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
                        title=list(text=m,font=list(color="#aaa")))
    if (is.null(df) || !"gain_db" %in% names(df)) return(ep("No Gain data found"))
    if (!x_var %in% names(df)) return(ep(paste0("Column '",x_var,"' not found")))
    ord <- order(df[[x_var]], na.last=NA); df <- df[ord,,drop=FALSE]
    xv      <- df[[x_var]]
    yv_raw  <- df$gain_db
    ok      <- !is.na(xv) & !is.na(yv_raw)
    g_lin   <- max(yv_raw[ok][seq_len(min(5L,sum(ok)))], na.rm=TRUE)
    yv      <- yv_raw - g_lin      # 0 at small signal, -1 at P1dB
    ds_aa   <- .lttb(xv[ok], yv[ok], 500L)
    p <- plot_ly() %>% add_trace(
      type="scattergl", mode="lines+markers",
      x=ds_aa$x, y=ds_aa$y,
      name="AM-AM compression (dB)",
      opacity=0.85,
      line=list(color="#ff7f11",width=2),
      marker=list(color="#ff7f11",size=5,opacity=0.60)
    )
    # P1dB marker
    ci <- which(yv[ok] <= -1)
    if (length(ci) > 0) {
      ci1 <- ci[1L]
      p   <- p %>% add_trace(
        type="scatter", mode="markers+text",
        x=xv[ok][ci1], y=yv[ok][ci1],
        text=sprintf("P1dB\n%.1f dBm", xv[ok][ci1]),
        textposition="top right",
        textfont=list(color="#ff7f11",size=10),
        marker=list(color="#ff7f11",size=12,symbol="circle",
                    line=list(color="white",width=2)),
        name="P1dB", showlegend=TRUE)
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-AM compression (dB)", color="#ff7f11",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color="#ff7f11")),
      legend = list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-AM vs ",xl), font=list(color="#eee",size=13)),
      font=list(color="#aaa"), margin=list(l=65,r=30,t=40,b=50))
  })

  # ── AM-PM (phase distortion in degrees) ──────────────────────────────────
  output$lp_ampm_plot <- renderPlotly({
    id    <- input$lp_ampm_dataset_selector
    if (is.null(id) || length(id) == 0) id <- input$lp_xy_dataset_selector
    if (is.null(id) || length(id) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset",font=list(color="#aaa"))))
    id    <- id[1L]
    x_var <- input$lp_ampm_x_var %||% "pin_dbm"
    df    <- .get_df(id, cols = c("pin_dbm","pout_dbm","pout_w","am_pm"))
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b",plot_bgcolor="#1b1b2b",
                        title=list(text=m,font=list(color="#aaa")))
    if (is.null(df)) return(ep("No data"))
    if (!"am_pm" %in% names(df) || all(is.na(df$am_pm)))
      return(ep("No AM-PM column found in this dataset"))
    if (!x_var %in% names(df)) return(ep(paste0("Column '",x_var,"' not found")))
    ord <- order(df[[x_var]], na.last=NA); df <- df[ord,,drop=FALSE]
    xv  <- df[[x_var]]; yv <- df$am_pm
    ok  <- !is.na(xv) & !is.na(yv)
    ds_pm <- .lttb(xv[ok], yv[ok], 500L)
    p <- plot_ly() %>% add_trace(
      type="scattergl", mode="lines+markers",
      x=ds_pm$x, y=ds_pm$y,
      name="AM-PM (\u00b0)",
      opacity=0.85,
      line=list(color="#1f77b4",width=2),
      marker=list(color="#1f77b4",size=5,opacity=0.60)
    )
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-PM (\u00b0)", color="#1f77b4",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color="#1f77b4")),
      legend = list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-PM vs ",xl), font=list(color="#eee",size=13)),
      font=list(color="#aaa"), margin=list(l=65,r=30,t=40,b=50))
  })

  # ── Comparison plot ────────────────────────────────────────────────────────
  output$lp_compare_plot <- renderPlotly({
    sel     <- input$lp_compare_selector
    ds      <- lp_datasets()
    x_var   <- input$lp_compare_x_var   %||% "pin_dbm"
    y_vars  <- input$lp_compare_y_vars
    if (is.null(y_vars) || length(y_vars) == 0) y_vars <- "pae_pct"
    per_freq <- isTRUE(input$lp_compare_per_freq)
    lttb_n   <- as.integer(input$lp_compare_lttb %||% 500L)
    mark_opt <- isTRUE(input$lp_compare_optimum)

    ep <- function(m) plot_ly() %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      title=list(text=m, font=list(color="#aaa")))

    if (is.null(sel) || length(sel) == 0)
      return(ep("Select datasets to compare"))

    EFF_VARS <- c("pae_pct","de_pct")
    .lbl <- function(v) switch(v, pae_pct="PAE (%)", de_pct="DE (%)",
      gain_db="Gain (dB)", pout_dbm="Pout (dBm)", pout_w="Pout (W)",
      pin_dbm="Pin (dBm)", gsub("_"," ",v))

    p <- plot_ly(); i_col <- 1L

    for (id in sel) {
      df <- .get_df(id, cols = unique(c(x_var, y_vars, "gain_db",
                         if (per_freq) "freq_ghz")))
      if (is.null(df) || !x_var %in% names(df)) next
      r     <- ds[[id]]
      fname <- .short_name(r$filename, 22L)

      groups <- if (per_freq) .by_freq(df) else list(list(freq=NA_real_, df=df))

      for (grp in groups) {
        gdf  <- grp$df
        f_sfx <- if (!is.na(grp$freq)) sprintf(" %.4g GHz", grp$freq) else ""
        # Sort by X
        ord  <- order(gdf[[x_var]], na.last=NA); gdf <- gdf[ord,,drop=FALSE]
        xv   <- gdf[[x_var]]

        for (v in y_vars) {
          if (!v %in% names(gdf)) next
          yv  <- gdf[[v]]
          ok  <- !is.na(xv) & !is.na(yv)
          col <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]; i_col <- i_col + 1L
          ds_c <- .lttb(xv[ok], yv[ok], lttb_n)
          on_y2 <- v %in% EFF_VARS
          col <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]; i_col <- i_col + 1L
          p <- p %>% add_trace(
            type="scattergl", mode="markers",
            x=ds_c$x, y=ds_c$y,
            yaxis = if (on_y2) "y2" else "y",
            name=paste0(fname, f_sfx, " \u2014 ", .lbl(v)),
            opacity=0.80,
            marker=list(color=col, size=5, opacity=0.65,
                        symbol=if(on_y2)"circle-open" else "circle"))
        }

        # Mark MXP/MXE/MXG
        if (mark_opt) {
          opt <- .find_optima(gdf)
          OC  <- list(MXP=list(col="pout_dbm",sym="star",      c="#ff7f11"),
                      MXE=list(col="pae_pct", sym="diamond",   c="#1f77b4"),
                      MXG=list(col="gain_db", sym="triangle-up",c="#2ca02c"))
          for (nm in names(OC)) {
            bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
            if (!cfg$col %in% names(gdf)) next
            on_y2 <- cfg$col %in% EFF_VARS
            p <- p %>% add_trace(type="scatter", mode="markers+text",
              x=gdf[[x_var]][bi], y=gdf[[cfg$col]][bi],
              yaxis=if(on_y2)"y2" else "y",
              text=sprintf("%s\n%.2f",nm,gdf[[cfg$col]][bi]), textposition="top center",
              textfont=list(color=cfg$c,size=9),
              marker=list(color=cfg$c,size=12,symbol=cfg$sym,
                          line=list(color="white",width=1.5)),
              name=paste0(nm," ",fname,f_sfx), showlegend=TRUE)
          }
        }
      }
    }

    xl <- .lbl(x_var)
    y1_lbls <- vapply(setdiff(y_vars, EFF_VARS), .lbl, character(1))
    y2_lbls <- vapply(intersect(y_vars, EFF_VARS), .lbl, character(1))

    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title=if(length(y1_lbls)>0) paste(y1_lbls,collapse=" / ") else "",
                    color="#aaa",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis2 = list(title=if(length(y2_lbls)>0) paste(y2_lbls,collapse=" / ") else "",
                    color="#aaa", overlaying="y", side="right",
                    showgrid=FALSE, zeroline=FALSE),
      legend=list(font=list(color="#aaa"),bgcolor="rgba(0,0,0,0.30)"),
      title=list(text="Multi-device Comparison", font=list(color="#eee",size=14)),
      font=list(color="#aaa"), margin=list(l=60,r=70,t=50,b=60))
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
              if (ok) paste0("\u2713 ", r$nrows %||% 0L, " pts") else "\u2717 failed"
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

  # ── Report dataset selector (multi-select, all selected by default) ────────
  output$lp_rpt_dataset_selector <- renderUI({
    ds <- lp_datasets()
    if (length(ds) == 0)
      return(tags$p(style = "color:#888; font-size:12px;",
                    "No datasets loaded yet."))
    nms <- stats::setNames(names(ds), vapply(ds, function(r) r$filename, character(1)))
    checkboxGroupInput("lp_rpt_datasets",
      label   = NULL,
      choices = nms, selected = names(ds),
      width   = "100%")
  })

  # ── HTML Report download ───────────────────────────────────────────────────
  output$lp_rpt_html <- downloadHandler(
    filename = function() paste0("lp_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html"),
    content  = function(file) {
      ds_all   <- lp_datasets()
      sel_ids  <- input$lp_rpt_datasets %||% names(ds_all)
      # Filter to only user-selected datasets (fallback: all)
      ds       <- ds_all[intersect(sel_ids, names(ds_all))]
      if (length(ds) == 0) ds <- ds_all   # safety: never generate empty report
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
        x_lbl <- if (!is.null(df$pin_dbm)) "Pin (dBm)" else "Pout (dBm)"
        title_str <- paste0("AM-AM / AM-PM \u2014 ", .short_name(r$filename, 28L))

        # ---- AM-AM: gain compression relative to small-signal gain ----
        p_amam <- plot_ly()
        if (has_gain) {
          yv_raw <- df$gain_db; ok <- !is.na(xv) & !is.na(yv_raw)
          ord    <- order(xv[ok]); xv_s <- xv[ok][ord]; yv_s <- yv_raw[ok][ord]
          g_lin  <- mean(head(yv_s, min(5L, length(yv_s))), na.rm = TRUE)
          yv_c   <- yv_s - g_lin
          p_amam <- p_amam %>% add_trace(type = "scatter", mode = "lines+markers",
            x = xv_s, y = yv_c, name = "AM-AM compression",
            opacity = 0.85,
            line   = list(color = "#ff7f11", width = 2),
            marker = list(color = "#ff7f11", size = 5, opacity = 0.60))
          # P1dB marker
          p1_idx <- which(yv_c <= -1)
          if (length(p1_idx) > 0) {
            bi <- p1_idx[1L]
            p_amam <- p_amam %>% add_trace(type = "scatter", mode = "markers+text",
              x = xv_s[bi], y = yv_c[bi],
              text = sprintf("P1dB\n%.1f dBm", xv_s[bi]), textposition = "top right",
              textfont = list(color = "#ffdd57", size = 9),
              marker = list(symbol = "diamond", color = "#ffdd57", size = 12,
                            line = list(color = "white", width = 1.5)),
              name = "P1dB", showlegend = FALSE)
          }
        }
        p_amam <- p_amam %>% layout(
          paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
          title  = list(text = title_str, font = list(color = "#eee", size = 14)),
          xaxis  = list(title = x_lbl, color = "#aaa",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
          yaxis  = list(title = "AM-AM compression (dB)", color = "#ff7f11",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                        tickfont = list(color = "#ff7f11")),
          legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
          font   = list(color = "#aaa"),
          margin = list(l = 65, r = 40, t = 50, b = 60))

        # ---- AM-PM: phase distortion in degrees ----
        p_ampm <- plot_ly()
        if (has_ampm) {
          yv2 <- df$am_pm; ok2 <- !is.na(xv) & !is.na(yv2)
          ord2 <- order(xv[ok2]); xv2 <- xv[ok2][ord2]; yv2s <- yv2[ok2][ord2]
          p_ampm <- p_ampm %>% add_trace(type = "scatter", mode = "lines+markers",
            x = xv2, y = yv2s, name = "AM-PM (\u00b0)",
            opacity = 0.85,
            line   = list(color = "#1f77b4", width = 2, dash = "dot"),
            marker = list(color = "#1f77b4", size = 5, symbol = "circle-open", opacity = 0.60))
        }
        p_ampm <- p_ampm %>% layout(
          paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
          xaxis  = list(title = x_lbl, color = "#aaa",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)"),
          yaxis  = list(title = "AM-PM (\u00b0)", color = "#1f77b4",
                        showgrid = TRUE, gridcolor = "rgba(100,100,100,0.25)",
                        tickfont = list(color = "#1f77b4")),
          legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.30)"),
          font   = list(color = "#aaa"),
          margin = list(l = 65, r = 40, t = 20, b = 60))

        list(amam = p_amam, ampm = p_ampm)
      }

      # ── Helper: build per-dataset optima HTML table ──────────────────────
      optima_tbl_html <- function(df) {
        rows2 <- list()
        for (grp in .by_freq(df)) {
          gdf <- grp$df; freq <- grp$freq
          opt <- .find_optima(gdf)
          for (oname in c("MXP","MXE","MXG")) {
            bi <- opt[[oname]]; if (is.na(bi)) next
            row <- gdf[bi, , drop=FALSE]
            gl_r <- if ("gl_r"%in%names(row)) row$gl_r else NA_real_
            gl_i <- if ("gl_i"%in%names(row)) row$gl_i else NA_real_
            gs_r <- if ("gs_r"%in%names(row)) row$gs_r else NA_real_
            gs_i <- if ("gs_i"%in%names(row)) row$gs_i else NA_real_
            zl   <- .gamma_to_z(gl_r, gl_i); zs <- .gamma_to_z(gs_r, gs_i)
            rows2[[length(rows2)+1]] <- sprintf(
              "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
              oname,
              if (is.na(freq)) "&mdash;" else sprintf("%.4g",freq),
              if ("pout_dbm"%in%names(row)) sprintf("%.2f",row$pout_dbm) else "&mdash;",
              if ("gain_db" %in%names(row)) sprintf("%.2f",row$gain_db)  else "&mdash;",
              if ("pae_pct" %in%names(row)) sprintf("%.2f",row$pae_pct)  else "&mdash;",
              if ("de_pct"  %in%names(row)) sprintf("%.2f",row$de_pct)   else "&mdash;",
              if (any(!is.na(c(gl_r,gl_i)))) sprintf("%.3f%+.3fj",gl_r,gl_i) else "&mdash;",
              if (any(!is.na(c(gl_r,gl_i)))) sprintf("%.2f%+.2fj\u03a9",round(zl$r,2),round(zl$x,2)) else "&mdash;",
              if (any(!is.na(c(gs_r,gs_i)))) sprintf("%.3f%+.3fj",gs_r,gs_i) else "&mdash;")
          }
          # Ppeak row
          bi_pk <- which.max(gdf$pout_dbm)
          if (length(bi_pk)>0) {
            row <- gdf[bi_pk,,drop=FALSE]
            gl_r<-if("gl_r"%in%names(row))row$gl_r else NA_real_
            gl_i<-if("gl_i"%in%names(row))row$gl_i else NA_real_
            zl<-.gamma_to_z(gl_r,gl_i)
            rows2[[length(rows2)+1]] <- sprintf(
              "<tr style='background:#fff8ee'><td>Ppeak</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>&mdash;</td></tr>",
              if(is.na(freq)) "&mdash;" else sprintf("%.4g",freq),
              if("pout_dbm"%in%names(row))sprintf("%.2f",row$pout_dbm) else "&mdash;",
              if("gain_db" %in%names(row))sprintf("%.2f",row$gain_db)  else "&mdash;",
              if("pae_pct" %in%names(row))sprintf("%.2f",row$pae_pct)  else "&mdash;",
              if("de_pct"  %in%names(row))sprintf("%.2f",row$de_pct)   else "&mdash;",
              if(any(!is.na(c(gl_r,gl_i))))sprintf("%.3f%+.3fj",gl_r,gl_i) else "&mdash;",
              if(any(!is.na(c(gl_r,gl_i))))sprintf("%.2f%+.2fj\u03a9",round(zl$r,2),round(zl$x,2)) else "&mdash;")
          }
        }
        if (length(rows2)==0) return("<p><em>No performance data available.</em></p>")
        paste0(
          "<table><thead><tr><th>Point</th><th>Freq (GHz)</th>",
          "<th>Pout (dBm)</th><th>Gain (dB)</th><th>PAE (%)</th><th>DE (%)</th>",
          "<th>&Gamma;_L</th><th>Z_L (&Omega;)</th><th>&Gamma;_S</th></tr></thead><tbody>",
          paste(rows2, collapse=""), "</tbody></table>")
      }

      # ── Assemble report body ──────────────────────────────────────────────
      body   <- ""
      toc_li <- ""
      sec_id <- 0L
      for (id in names(ds)) {
        sec_id <- sec_id + 1L
        r      <- ds[[id]]
        ok     <- isTRUE(r$success)
        df     <- if (ok) .get_df(id) else NULL
        did    <- paste0("ds", sec_id)
        fname  <- esc(r$filename)

        # TOC entry
        toc_li <- paste0(toc_li,
          "<li><a href='#", did, "'>", fname, "</a>",
          "<ul style='padding-left:12px;font-size:11px;list-style:disc;'>",
          if (ok) paste0(
            "<li><a href='#", did, "_summary'>&#128202; Summary</a></li>",
            "<li><a href='#", did, "_smith'>&#9678; Contours</a></li>",
            "<li><a href='#", did, "_xy'>&#128200; XY Performance</a></li>",
            "<li><a href='#", did, "_imp'>&#127919; Impedances</a></li>",
            "<li><a href='#", did, "_ampm'>&#128201; AM-AM/AM-PM</a></li>",
            if ("meta" %in% sections) paste0("<li><a href='#", did, "_meta'>&#128196; Metadata</a></li>") else ""
          ) else "",
          "</ul></li>")

        body <- paste0(body,
          "<section id='", did, "'>",
          "<hr style='margin:32px 0 20px; border-color:#ccc;'/>",
          "<h2 id='", did, "'>",
          "&#128065; ", fname,
          "  <span class='", if (ok) "badge-ok" else "badge-err", "'>",
          if (ok) "OK" else "failed", "</span></h2>")
        if (!ok) { body <- paste0(body, "</section>"); next }

        # 1. Summary table
        body <- paste0(body,
          "<h3 id='", did, "_summary'>&#128202; Performance Summary</h3>",
          optima_tbl_html(df))

        # 2. Smith chart contours
        has_gl <- !is.null(df$gl_r) && !all(is.na(df$gl_r))
        if ("smith" %in% sections && has_gl)
          body <- paste0(body,
            "<h3 id='", did, "_smith'>&#9678; Smith Chart &mdash; Contours</h3>",
            plot_div(build_smith_fig(r, df)))

        # 3. XY performance
        if ("xy" %in% sections)
          body <- paste0(body,
            "<h3 id='", did, "_xy'>&#128200; XY Performance (Gain / PAE / DE)</h3>",
            plot_div(build_xy_fig(r, df)))

        # 4. Source & Load impedances
        body <- paste0(body,
          "<h3 id='", did, "_imp'>&#127919; Source &amp; Load Impedances (&Gamma;)</h3>")
        if ("nose" %in% sections) {
          p_nose <- build_nose_fig(r, df)
          if (!is.null(p_nose)) body <- paste0(body, plot_div(p_nose))
        } else {
          body <- paste0(body, "<p class='text-muted'>Enable &ldquo;Nose plot&rdquo; section to include impedance scatter.</p>")
        }

        # 5. AM-AM / AM-PM
        p_am <- build_ampm_fig(r, df)
        if (!is.null(p_am))
          body <- paste0(body,
            "<h3 id='", did, "_ampm'>&#128201; AM-AM (compression) / AM-PM (&deg;)</h3>",
            plot_div(p_am$amam), plot_div(p_am$ampm))

        # 6. Metadata
        if ("meta" %in% sections && length(r$meta) > 0) {
          meta_rows <- paste0(
            "<tr><td style='font-weight:600;padding:4px 12px 4px 6px;'>",
            esc(names(r$meta)), "</td><td style='padding:4px 6px;'>",
            esc(as.character(unlist(r$meta))), "</td></tr>", collapse = "")
          body <- paste0(body,
            "<h3 id='", did, "_meta'>&#128196; Measurement Metadata</h3>",
            "<table style='border-collapse:collapse;width:auto;margin:8px 0;'>",
            "<thead><tr><th style='padding:4px 12px 4px 6px;border-bottom:2px solid #ccc;text-align:left;'>Key</th>",
            "<th style='padding:4px 6px;border-bottom:2px solid #ccc;text-align:left;'>Value</th></tr></thead>",
            "<tbody>", meta_rows, "</tbody></table>")
        }

        body <- paste0(body, "</section>")
      }

      # ── Page header + CDN script + floating TOC ───────────────────────────
      hdr <- paste0(
        "<!DOCTYPE html><html lang='en'><head>",
        "<meta charset='UTF-8'>",
        "<meta name='viewport' content='width=device-width,initial-scale=1'>",
        "<title>", esc(title), "</title>",
        "<script src='https://cdn.plot.ly/plotly-2.35.2.min.js' charset='utf-8'></script>",
        "<style>",
        ":root{--accent:#ff7f11;--bg:#fafafa;--text:#222;--border:#ddd;}",
        "body{font-family:Arial,sans-serif;line-height:1.6;color:var(--text);",
        "  background:var(--bg);margin:0;padding:0;}",
        "#content{max-width:1060px;margin:24px auto 24px 280px;padding:0 24px;}",
        "#toc{position:fixed;top:0;left:0;width:260px;height:100vh;",
        "  background:#1e1e2e;color:#ccc;overflow-y:auto;padding:16px 12px;",
        "  box-sizing:border-box;font-size:12px;border-right:1px solid #333;}",
        "#toc h4{color:#ff7f11;margin:0 0 10px;font-size:13px;letter-spacing:.5px;}",
        "#toc ul{list-style:none;padding:0;margin:0;}",
        "#toc li{margin:3px 0;}",
        "#toc a{color:#bbb;text-decoration:none;display:block;padding:2px 4px;border-radius:3px;}",
        "#toc a:hover{color:#fff;background:rgba(255,127,17,0.25);}",
        "h1{color:#333;border-bottom:3px solid var(--accent);padding-bottom:10px;margin-top:0;}",
        "h2{color:#333;margin-top:36px;border-left:4px solid var(--accent);padding-left:10px;}",
        "h3{color:#555;margin-top:22px;border-left:2px solid #ddd;padding-left:8px;}",
        "section{margin-bottom:24px;}",
        "table{border-collapse:collapse;width:100%;margin:10px 0;font-size:13px;}",
        "th,td{border:1px solid var(--border);padding:5px 10px;text-align:left;}",
        "th{background:#ececec;font-weight:600;}",
        "tr:hover{background:#f5f5f5;}",
        ".badge-ok{background:#2ca02c;color:#fff;border-radius:3px;",
        "  padding:2px 8px;font-size:12px;font-weight:600;}",
        ".badge-err{background:#d62728;color:#fff;border-radius:3px;",
        "  padding:2px 8px;font-size:12px;font-weight:600;}",
        ".meta-info{color:#666;font-size:14px;margin:4px 0;}",
        "@media(max-width:800px){#toc{display:none;}#content{margin-left:24px;}}",
        "</style></head><body>",
        "<nav id='toc'>",
        "<h4>&#128196; Load Pull Report</h4>",
        "<ul>",
        "<li><a href='#rpt-header'>&#127968; Cover</a></li>",
        toc_li,
        "</ul></nav>",
        "<div id='content'>",
        "<h1 id='rpt-header'>", esc(title), "</h1>",
        "<div style='border:1px solid #ddd;border-radius:4px;padding:12px;",
        "background:#fff;margin-bottom:20px;display:inline-block;min-width:300px;'>",
        if (nzchar(engineer)) paste0("<p class='meta-info'>&#128100; <strong>Engineer:</strong> ", esc(engineer), "</p>") else "",
        if (nzchar(project))  paste0("<p class='meta-info'>&#128196; <strong>Project:</strong> ",  esc(project),  "</p>") else "",
        "<p class='meta-info'>&#128336; <strong>Generated:</strong> ", esc(as.character(Sys.time())), "</p>",
        "<p class='meta-info'>&#128230; <strong>Datasets:</strong> ", length(ds), "</p>",
        "</div>"
      )

      writeLines(paste0(hdr, body, "</div></body></html>"), file)
    }
  )

  # ── Combined CSV download ──────────────────────────────────────────────────
  output$lp_rpt_csv_all <- downloadHandler(
    filename = function() paste0("lp_all_data_", Sys.Date(), ".csv"),
    content  = function(file) {
      ds  <- lp_datasets()
      dfs <- Filter(Negate(is.null), lapply(names(ds), function(id) {
        r  <- ds[[id]]
        if (!isTRUE(r$success) || (r$nrows %||% 0L) == 0L) return(NULL)
        df             <- .get_df(id)
        if (is.null(df)) return(NULL)
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
