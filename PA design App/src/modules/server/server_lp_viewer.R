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

  # ── Split-variable helpers ─────────────────────────────────────────────────

  # Parse filename tokens to build a compact auto-tag
  .parse_filename_tag <- function(fname) {
    tokens <- character(0)
    m_idq <- regmatches(fname, regexpr(
      "Idq_?([0-9]+(?:\\.[0-9]+)?)\\s*m[Aa]", fname, perl = TRUE))
    if (length(m_idq) > 0)
      tokens <- c(tokens, paste0("Idq=", sub("(?i)Idq_?", "", m_idq, perl = TRUE)))
    m_vdd <- regmatches(fname, regexpr(
      "V(?:dd|cc|ds|dc)_?([0-9]+(?:p[0-9]+)?)\\s*V", fname, perl = TRUE,
      ignore.case = TRUE))
    if (length(m_vdd) > 0)
      tokens <- c(tokens, gsub("_", "=", m_vdd))
    m_fq <- regmatches(fname, regexpr(
      "[0-9]+[p_][0-9]*[Gg][Hh][Zz]", fname, perl = TRUE))
    if (length(m_fq) > 0)
      tokens <- c(tokens, paste0(gsub("[p_]", ".", m_fq)))
    if (length(tokens) > 0) paste(tokens, collapse = " / ")
    else tools::file_path_sans_ext(basename(fname))
  }

  # Resolve effective split variable for a tab (tab_prefix: "contour","xy","perf","nose","ampm")
  .eff_split <- function(tab_prefix) {
    local_id  <- paste0("lp_", tab_prefix, "_split_local")
    local_val <- input[[local_id]] %||% "global"
    if (!is.null(local_val) && local_val != "global") local_val
    else input$lp_global_split_var %||% "freq_ghz"
  }

  # Get sorted unique split values from a dataframe column (always character for uniformity)
  .split_vals <- function(df, split_col) {
    if (!split_col %in% names(df)) return(character(0))
    vals <- unique(df[[split_col]])
    sort(as.character(vals[!is.na(vals)]))
  }

  # Format a split value as a legend/label string
  .split_lbl <- function(val, split_col) {
    switch(split_col,
      freq_ghz    = sprintf("%.4g GHz", suppressWarnings(as.numeric(val))),
      vdc_v       = sprintf("Vdc=%.4g V", suppressWarnings(as.numeric(val))),
      dataset_tag = as.character(val),
      as.character(val)
    )
  }

  # ── Helpers ────────────────────────────────────────────────────────────────
  # Truncate long filenames for legend labels (max n visible chars)
  .short_name <- function(s, n = 24) {
    s <- s[1L]   # guard: ensure scalar (prevents 'condition has length > 1')
    if (nchar(s) > n) paste0(substr(s, 1, n), "\u2026") else s
  }

  # Truncate a legend label to at most n chars (with ellipsis)
  .trunc_lbl <- function(s, n = 30L) {
    s <- s[1L]
    if (nchar(s) > n) paste0(substr(s, 1L, n), "\u2026") else s
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

  # Reduce a full load-pull sweep → one row per (freq, unique ZL) at the given metric's max.
  # metric: "pae_pct" for MXE nose, "gain_db" for MXG nose.
  .nose_reduce <- function(df, metric) {
    if (!metric %in% names(df) || all(is.na(df[[metric]]))) return(NULL)
    if (!all(c("gl_r","gl_i") %in% names(df)))              return(NULL)
    freq_key <- if ("freq_ghz" %in% names(df) && any(!is.na(df$freq_ghz)))
                  as.character(round(df$freq_ghz, 4)) else rep("0", nrow(df))
    gl_key  <- paste(round(df$gl_r, 4), round(df$gl_i, 4), sep = "_")
    grp_key <- paste(freq_key, gl_key, sep = ":")
    out <- do.call(rbind, lapply(split(seq_len(nrow(df)), grp_key), function(idx) {
      grp <- df[idx, , drop = FALSE]
      bi  <- which.max(grp[[metric]])
      if (length(bi) == 0L) return(NULL)
      grp[bi, , drop = FALSE]
    }))
    if (is.null(out) || nrow(out) == 0L) return(NULL)
    out
  }

  # Like .nose_reduce() but selects the point nearest Px dB compression per sweep.
  # When px_db == 0 falls back to max-metric selection.
  .nose_px_reduce <- function(df, metric, px_db = 0, px_tol = 0.3) {
    if (px_db <= 0) return(.nose_reduce(df, metric))
    if (!"gain_db" %in% names(df) || all(is.na(df$gain_db)))
      return(.nose_reduce(df, metric))
    if (!all(c("gl_r","gl_i") %in% names(df))) return(NULL)
    freq_key <- if ("freq_ghz" %in% names(df) && any(!is.na(df$freq_ghz)))
                  as.character(round(df$freq_ghz, 4)) else rep("0", nrow(df))
    gl_key  <- paste(round(df$gl_r, 4), round(df$gl_i, 4), sep = "_")
    grp_key <- paste(freq_key, gl_key, sep = ":")
    x_col   <- if ("pin_dbm"  %in% names(df)) "pin_dbm"  else
               if ("pout_dbm" %in% names(df)) "pout_dbm" else NULL
    out <- do.call(rbind, lapply(split(seq_len(nrow(df)), grp_key), function(idx) {
      grp <- df[idx, , drop = FALSE]
      if (!is.null(x_col)) grp <- grp[order(grp[[x_col]], na.last = NA), , drop = FALSE]
      g     <- grp$gain_db
      g_lin <- suppressWarnings(max(g[seq_len(min(5L, length(g)))], na.rm = TRUE))
      if (!is.finite(g_lin)) return(NULL)
      compr <- g_lin - g
      ci    <- which(!is.na(compr) & abs(compr - px_db) <= px_tol)
      if (length(ci) == 0) return(NULL)
      sub <- grp[ci, , drop = FALSE]
      if (!metric %in% names(sub) || all(is.na(sub[[metric]]))) return(NULL)
      bi  <- which.max(sub[[metric]])
      if (length(bi) == 0L) return(NULL)
      sub[bi, , drop = FALSE]
    }))
    if (is.null(out) || nrow(out) == 0L) return(NULL)
    out
  }

  # Place annotation text boxes with arrows so they do not overlap.
  # Returns a list of Plotly annotation objects ready for layout(annotations=...).
  .anno_nonoverlap <- function(xs, ys, labels, fg_colors,
                               arrow_colors = NULL, plot_w = 380, plot_h = 260) {
    n <- length(xs)
    if (n == 0) return(list())
    if (is.null(arrow_colors)) arrow_colors <- fg_colors
    # 12 candidate pixel offsets (ax, ay) — covers 8 compass + 4 wider positions
    cands <- list(
      c(  0, -44), c( 40, -30), c( 52,   0), c( 40,  30),
      c(  0,  46), c(-40,  30), c(-52,   0), c(-40, -30),
      c(  0, -62), c( 58, -44), c( 72,   0), c( 58,  44)
    )
    xr <- range(xs, na.rm = TRUE); yr <- range(ys, na.rm = TRUE)
    dx <- max(diff(xr), 1e-9);     dy <- max(diff(yr), 1e-9)
    px <- (xs - xr[1]) / dx * plot_w
    py <- (ys - yr[1]) / dy * plot_h
    placed <- vector("list", n)
    bw <- 46; bh <- 24     # approx half-extents of a text box in pixels
    for (i in seq_len(n)) {
      chosen <- cands[[1]]
      for (cand in cands) {
        ax <- cand[1]; ay <- cand[2]
        tx_i <- px[i] + ax; ty_i <- py[i] + ay
        ok <- TRUE
        for (j in seq_len(i - 1)) {
          if (is.null(placed[[j]])) next
          tx_j <- px[j] + placed[[j]][1]; ty_j <- py[j] + placed[[j]][2]
          if (abs(tx_i - tx_j) < bw * 2 && abs(ty_i - ty_j) < bh * 2) {
            ok <- FALSE; break
          }
        }
        if (ok) { chosen <- cand; break }
      }
      placed[[i]] <- chosen
    }
    lapply(seq_len(n), function(i) {
      list(
        x = xs[i], y = ys[i], xref = "x", yref = "y",
        text       = labels[i],
        ax         = placed[[i]][1], ay = placed[[i]][2],
        axref      = "pixel",        ayref = "pixel",
        font       = list(color = fg_colors[i], size = 9),
        arrowcolor = arrow_colors[i], arrowwidth = 1.3,
        arrowsize  = 0.7,             arrowhead  = 2,
        bgcolor    = "rgba(18,18,30,0.82)",
        bordercolor = fg_colors[i],  borderwidth = 1, borderpad = 3,
        showarrow  = TRUE
      )
    })
  }

  # Per-sweep Px compression filter.
  # For each (freq × swept-impedance) group keeps the single row where |compression - px_db|
  # is minimised.  z_r_col / z_i_col name the swept-impedance Gamma columns.
  .px_filter_df <- function(df, px_db, px_tol,
                             z_r_col = "gl_r", z_i_col = "gl_i") {
    if (!"gain_db" %in% names(df) || all(is.na(df$gain_db))) return(df)
    if (!all(c(z_r_col, z_i_col) %in% names(df)))            return(df)
    freq_key <- if ("freq_ghz" %in% names(df) && any(!is.na(df$freq_ghz)))
                  as.character(round(df$freq_ghz, 4)) else rep("0", nrow(df))
    gl_key   <- paste(round(df[[z_r_col]], 4), round(df[[z_i_col]], 4))
    grp_key  <- paste(freq_key, gl_key)
    x_col    <- if ("pin_dbm"  %in% names(df)) "pin_dbm" else
                if ("pout_dbm" %in% names(df)) "pout_dbm" else NULL
    keep <- logical(nrow(df))
    for (gk in unique(grp_key)) {
      idx   <- which(grp_key == gk)
      sg    <- df[idx, , drop = FALSE]
      ord_w <- if (!is.null(x_col)) order(sg[[x_col]], na.last = NA) else seq_len(nrow(sg))
      idx_s <- idx[ord_w]
      g     <- sg$gain_db[ord_w]
      g_l   <- suppressWarnings(max(g[seq_len(min(5L, length(g)))], na.rm = TRUE))
      if (!is.finite(g_l)) next
      compr <- g_l - g
      ci    <- which(!is.na(compr) & compr >= (px_db - px_tol) & compr <= (px_db + px_tol))
      if (length(ci) > 0) {
        ci_best     <- ci[which.min(abs(compr[ci] - px_db))]
        keep[idx_s[ci_best]] <- TRUE
      }
    }
    df[keep, , drop = FALSE]
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

        result          <- parse_lp_file(fpath, format_override = fmt, filename_hint = fname)
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
          # Stamp dataset_tag column (used by split-by-tag feature)
          manual_tag <- trimws(input$lp_dataset_tag %||% "")
          use_auto   <- isTRUE(input$lp_auto_tag %||% TRUE)
          tag_val    <- if (nzchar(manual_tag)) manual_tag
                        else if (use_auto) .parse_filename_tag(fname)
                        else .short_name(fname, 40L)
          result$points$dataset_tag <- tag_val
          log <- c(log, paste0("    Tag: \u201c", tag_val, "\u201d"))

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

  # ── Merge datasets UI ────────────────────────────────────────────────────
  output$lp_merge_select_ui <- renderUI({
    ds <- lp_datasets()
    ok_ids <- names(ds)[vapply(ds, function(r) isTRUE(r$success), logical(1))]
    if (length(ok_ids) < 2)
      return(p(style = "color:#888; font-size:12px;",
               "Load \u22652 datasets to enable merge."))
    ch <- setNames(ok_ids, vapply(ok_ids, function(i) .short_name(ds[[i]]$filename, 26L), character(1)))
    checkboxGroupInput("lp_merge_ids", NULL, choices = ch, selected = ok_ids,
                       width = "100%")
  })

  observeEvent(input$lp_merge_btn, {
    ids <- input$lp_merge_ids
    if (is.null(ids) || length(ids) < 2) {
      lp_log(c(lp_log(), "Merge: select at least 2 datasets.")); return()
    }
    ds <- lp_datasets()
    valid_ids <- ids[ids %in% names(ds) & vapply(ids, function(i) isTRUE(ds[[i]]$success), logical(1))]
    if (length(valid_ids) < 2) {
      lp_log(c(lp_log(), "Merge: fewer than 2 valid datasets selected.")); return()
    }
    # Read and rbind data from DuckDB, aligning columns
    merged_df <- tryCatch({
      dfs <- lapply(valid_ids, function(i) {
        tbl <- ds[[i]]$tbl_name
        if (is.null(tbl) || !DBI::dbExistsTable(lp_con, tbl)) return(NULL)
        DBI::dbReadTable(lp_con, tbl)
      })
      dfs <- Filter(Negate(is.null), dfs)
      if (length(dfs) == 0) stop("No data found in selected datasets")
      all_cols <- Reduce(union, lapply(dfs, names))
      dfs_aligned <- lapply(dfs, function(df) {
        missing <- setdiff(all_cols, names(df))
        for (col in missing) df[[col]] <- NA_real_
        df[all_cols]
      })
      do.call(rbind, dfs_aligned)
    }, error = function(e) {
      lp_log(c(lp_log(), paste0("Merge error: ", e$message))); NULL
    })
    if (is.null(merged_df)) return()

    # Write merged table to DuckDB
    new_id   <- paste0("merged_", format(Sys.time(), "%H%M%S"))
    tbl_name <- paste0("lp_", gsub("[^A-Za-z0-9_]", "_", new_id))
    success  <- tryCatch({
      DBI::dbWriteTable(lp_con, tbl_name, merged_df, overwrite = TRUE); TRUE
    }, error = function(e) {
      lp_log(c(lp_log(), paste0("Merge DuckDB write error: ", e$message))); FALSE
    })
    if (!success) return()

    # Build merged record
    lbl <- trimws(input$lp_merge_label %||% "")
    fname <- if (nchar(lbl) > 0) lbl else
      paste(vapply(valid_ids, function(i) .short_name(ds[[i]]$filename, 10L), character(1)),
            collapse = "+")
    new_result <- list(
      success   = TRUE,
      filename  = fname,
      format    = paste0("merged(", length(valid_ids), ")"),
      nrows     = nrow(merged_df),
      tbl_name  = tbl_name,
      col_names = names(merged_df),
      meta      = ds[[valid_ids[1L]]]$meta,
      points    = NULL
    )
    current <- lp_datasets()
    current[[new_id]] <- new_result
    lp_datasets(current)
    lp_log(c(lp_log(),
      sprintf("Merged %d datasets \u2192 '%s' (%d pts, %d cols)",
              length(valid_ids), fname, nrow(merged_df), ncol(merged_df)),
      paste0("\u2500\u2500\u2500 Total datasets: ", length(current), " \u2500\u2500\u2500")))
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

  .make_selector <- function(output_id, label = "Dataset(s)") {
    btn_all  <- paste0(output_id, "_selall")
    btn_none <- paste0(output_id, "_selnone")
    output[[paste0(output_id, "_ui")]] <- renderUI({
      ch <- .dataset_choices()
      if (length(ch) == 0)
        return(p(style = "color:#888; font-size:12px;", "Load datasets first."))
      div(style = "max-width:100%;",
        tags$label(label, style = "color:#ccc; font-size:12px; font-weight:600; display:block; margin-bottom:4px;"),
        div(style = "display:flex; gap:5px; margin-bottom:6px;",
          actionButton(btn_all,  "All",  class = "btn btn-xs btn-default",
                       style = "padding:2px 8px; font-size:11px;"),
          actionButton(btn_none, "None", class = "btn btn-xs btn-default",
                       style = "padding:2px 8px; font-size:11px;")
        ),
        checkboxGroupInput(output_id, label = NULL, choices = ch, selected = ch,
                           width = "100%")
      )
    })
    observeEvent(input[[btn_all]], {
      ch <- .dataset_choices()
      updateCheckboxGroupInput(session, output_id, choices = ch, selected = ch)
    }, ignoreInit = TRUE)
    observeEvent(input[[btn_none]], {
      ch <- .dataset_choices()
      updateCheckboxGroupInput(session, output_id, choices = ch, selected = character(0))
    }, ignoreInit = TRUE)
  }

  .make_selector("lp_dataset_selector",        "Dataset(s)")
  .make_selector("lp_xy_dataset_selector",     "Dataset(s)")
  .make_selector("lp_ampm_dataset_selector",   "Dataset(s)")
  .make_selector("lp_nose_dataset_selector",   "Dataset(s)")
  .make_selector("lp_table_dataset_selector",  "Dataset(s)")

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
    do_norm   <- abs(z0_norm - 50) > 0.1
    px_db     <- as.numeric(input$lp_smith_px_db  %||% 0)
    px_tol    <- as.numeric(input$lp_smith_px_tol %||% 0.3)
    do_px     <- is.finite(px_db) && px_db > 0.01
    sv        <- .eff_split("contour")
    ep <- function(m) plot_ly() %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      title=list(text=m, font=list(color="#aaa")))

    if (is.null(sel_ids) || length(sel_ids) == 0)
      return(ep("Select a dataset"))
    if (is.null(vars) || length(vars) == 0)
      return(ep("Select at least one contour variable"))

    # Gamma re-normalisation helper
    .renorm_gamma <- function(gr, gi) {
      z_r <- 50 * (1 - gr^2 - gi^2) / ((1 - gr)^2 + gi^2)
      z_x <- 50 * 2 * gi            / ((1 - gr)^2 + gi^2)
      d   <- (z_r + z0_norm)^2 + z_x^2
      list(r = ((z_r - z0_norm) * (z_r + z0_norm) + z_x^2) / d,
           i = 2 * z_x * z0_norm / d)
    }

    grid <- build_smith_grid()

    var_meta <- list(
      pout   = list(col = "pout_dbm", label = "Pout(dBm)", color = "#ff7f11"),
      pae    = list(col = "pae_pct",  label = "PAE(%)",    color = "#1f77b4"),
      de     = list(col = "de_pct",   label = "DE(%)",     color = "#2ca02c"),
      gain   = list(col = "gain_db",  label = "Gain(dB)",  color = "#9467bd"),
      pdc    = list(col = "pdc_w",    label = "Pdc(W)",    color = "#d62728"),
      pout_w = list(col = "pout_w",   label = "Pout(W)",   color = "#ffaa44")
    )

    OPT_CFG <- list(
      MXP = list(col = "pout_dbm", sym = "star",       color = "#ff7f11", label = "MXP"),
      MXE = list(col = "pae_pct",  sym = "diamond",     color = "#1f77b4", label = "MXE"),
      MXG = list(col = "gain_db",  sym = "triangle-up", color = "#2ca02c", label = "MXG")
    )
    show_opt  <- isTRUE(input$lp_show_optima %||% TRUE)
    show_h2   <- isTRUE(input$lp_show_harmonics)
    show_stab <- isTRUE(input$lp_show_stability)

    # ── Determine if side-by-side mode (dataset_tag split) ────────────────
    tag_vals <- character(0)
    if (sv == "dataset_tag") {
      for (id in sel_ids) {
        df_t <- .get_df(id, cols = "dataset_tag")
        if (!is.null(df_t) && "dataset_tag" %in% names(df_t))
          tag_vals <- unique(c(tag_vals, as.character(na.omit(df_t$dataset_tag))))
      }
      tag_vals <- sort(tag_vals)
    }
    do_side_by_side <- length(tag_vals) > 1

    # ── Panel builder ─────────────────────────────────────────────────────
    # panel_tag_filter: keep only rows where dataset_tag == this value (NULL = all rows)
    # inner_split_col: column used for within-panel color grouping (freq_ghz or vdc_v)
    build_panel <- function(panel_tag_filter = NULL, inner_split_col = "freq_ghz",
                            panel_title = NULL) {
      p          <- plot_ly()
      all_xv     <- c(); all_yv <- c()
      colorbar_x <- 1.02

      for (tr in grid) {
        p <- p %>% add_trace(
          type = "scatter", mode = "lines",
          x = tr$x, y = tr$y, line = tr$line,
          hoverinfo = "none", showlegend = FALSE, name = tr$name
        )
      }

      if (length(sel_ids) > 0 && length(vars) > 0) {
        for (id in sel_ids) {
          metric_cols <- vapply(vars, function(v) {
            vm <- var_meta[[v]]; if (is.null(vm)) NA_character_ else vm$col
          }, character(1))
          gamma_cols <- c("gl_r","gl_i","gs_r","gs_i","gl2_r","gl2_i","gl3_r","gl3_i")
          need_cols  <- unique(c(gamma_cols, na.omit(metric_cols), "freq_ghz",
                                 inner_split_col, "dataset_tag",
                                 if (do_px) c("gain_db", "pin_dbm") else NULL))
          df    <- .get_df(id, cols = need_cols)
          if (is.null(df)) next

          # ── Dataset tag filter (side-by-side mode) ────────────────────────
          if (!is.null(panel_tag_filter) && "dataset_tag" %in% names(df))
            df <- df[!is.na(df$dataset_tag) & df$dataset_tag == panel_tag_filter,
                     , drop = FALSE]
          if (is.null(df) || nrow(df) == 0) next

          r     <- ds[[id]]
          fname <- .short_name(r$filename)

          # ── Px compression filter ─────────────────────────────────────────
          if (do_px) {
            df <- .px_filter_df(df, px_db, px_tol, "gl_r", "gl_i")
            if (nrow(df) == 0) next
          }

          xv_all <- if (pull == "load") df$gl_r else df$gs_r
          yv_all <- if (pull == "load") df$gl_i else df$gs_i
          if (is.null(xv_all) || all(is.na(xv_all))) next

          # ── Γ re-normalisation ────────────────────────────────────────────
          if (do_norm) {
            nr <- .renorm_gamma(xv_all, yv_all)
            xv_all <- nr$r; yv_all <- nr$i
            if (!is.null(df$gs_r)) {
              nrs <- .renorm_gamma(df$gs_r, df$gs_i)
              df$gs_r <- nrs$r; df$gs_i <- nrs$i
            }
            for (hcol in c("gl2_r","gl2_i","gl3_r","gl3_i")) {
              if (hcol %in% names(df)) {
                pfx   <- sub("_[ri]$", "", hcol)
                r_col <- paste0(pfx, "_r"); i_col <- paste0(pfx, "_i")
                if (all(c(r_col, i_col) %in% names(df))) {
                  nh <- .renorm_gamma(df[[r_col]], df[[i_col]])
                  df[[r_col]] <- nh$r; df[[i_col]] <- nh$i
                }
              }
            }
          }

          # ── Within-panel split (inner_split_col) ─────────────────────────
          splits  <- .split_vals(df, inner_split_col)
          multi_f <- length(splits) > 1

          for (v in vars) {
            vm <- var_meta[[v]]
            if (is.null(vm) || !vm$col %in% names(df)) next
            zv_all <- df[[vm$col]]

          slices <- if (multi_f) {
            lapply(splits, function(sv_val) {
              fsel <- !is.na(df[[inner_split_col]]) &
                      as.character(df[[inner_split_col]]) == sv_val
              xf <- xv_all[fsel]; yf <- yv_all[fsel]; zf <- zv_all[fsel]
              ok_f <- !is.na(xf) & !is.na(yf) & !is.na(zf) & (xf^2 + yf^2) <= 1.02
              list(xv = xf[ok_f], yv = yf[ok_f], zv = zf[ok_f],
                   leg = sprintf("%s @ %s [%s]", vm$label,
                                 .split_lbl(sv_val, inner_split_col), fname),
                   ckey = NULL)
            })
          } else {
            ok_s <- !is.na(xv_all) & !is.na(yv_all) & !is.na(zv_all) &
                    (xv_all^2 + yv_all^2) <= 1.02
            list(list(xv = xv_all[ok_s], yv = yv_all[ok_s], zv = zv_all[ok_s],
                      leg = paste0(vm$label, " [", fname, "]"),
                      ckey = paste0(pull, ":", v)))
          }

          for (sl in slices) {
          xv <- sl$xv; yv <- sl$yv; zv <- sl$zv
          if (length(xv) < 4) next
          all_xv <- c(all_xv, xv); all_yv <- c(all_yv, yv)
          leg_name  <- sl$leg
          cache_key <- sl$ckey
          cached    <- if (!is.null(cache_key) && !do_norm && !do_px) r$interp_cache[[cache_key]] else NULL
          interp_ok <- FALSE
          # Colorbar range from actual data extent (not interpolation grid)
          zmin_cb <- min(zv, na.rm = TRUE)
          zmax_cb <- max(zv, na.rm = TRUE)
          if (!is.null(cached)) {
            xi <- cached$xi; yi <- cached$yi; zm <- cached$zm
            interp_ok <- TRUE
          } else if (requireNamespace("akima", quietly = TRUE) && length(xv) >= 6) {
            tryCatch({
              nx <- 40; ny <- 40
              xi <- seq(min(xv) - 0.01, max(xv) + 0.01, length.out = nx)
              yi <- seq(min(yv) - 0.01, max(yv) + 0.01, length.out = ny)
              # Deduplicate by keeping the row with max metric at each impedance
              xy_key <- paste(round(xv, 4), round(yv, 4))
              if (anyDuplicated(xy_key)) {
                grps_d <- split(seq_along(xv), xy_key)
                kd     <- vapply(grps_d, function(i) i[which.max(zv[i])], integer(1L))
                xv_d <- xv[kd]; yv_d <- yv[kd]; zv_d <- zv[kd]
              } else { xv_d <- xv; yv_d <- yv; zv_d <- zv }
              res    <- akima::interp(xv_d, yv_d, zv_d,
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
              zmin       = zmin_cb,  zmax = zmax_cb,
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
          } # slices loop
        } # vars loop

        # ── Optimum points: MXP, MXE, MXG per split slice ────────────────
        if (show_opt) {
          opt_splits <- if (multi_f) splits else list(NA_character_)
          for (sv_o in opt_splits) {
            if (multi_f) {
              fsel_o <- !is.na(df[[inner_split_col]]) &
                        as.character(df[[inner_split_col]]) == sv_o
              df_o  <- df[fsel_o, , drop = FALSE]
              xv_o  <- xv_all[fsel_o]; yv_o <- yv_all[fsel_o]
            } else {
              df_o <- df; xv_o <- xv_all; yv_o <- yv_all
            }
            opt <- .find_optima(df_o)
            for (oname in names(OPT_CFG)) {
              bi <- opt[[oname]]
              if (is.na(bi)) next
              cfg <- OPT_CFG[[oname]]
              if (!cfg$col %in% names(df_o)) next
              ox <- xv_o[bi]; oy <- yv_o[bi]; oz <- df_o[[cfg$col]][bi]
              if (any(is.na(c(ox, oy)))) next
              oleg <- if (multi_f)
                        sprintf("%s @ %s [%s]", oname,
                                .split_lbl(sv_o, inner_split_col), fname)
                      else paste0(oname, " [", fname, "]")
              p <- p %>% add_trace(
                type = "scatter", mode = "markers+text",
                x = ox, y = oy,
                text = sprintf("%s\n%.1f", oname, oz),
                textposition = "top center",
                textfont = list(color = cfg$color, size = 10),
                marker = list(color = cfg$color, size = 16,
                              symbol = cfg$sym,
                              line = list(color = "white", width = 1.5)),
                name = oleg, showlegend = TRUE
              )
            }
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
      } # if sel_ids + vars

      # ── Stability circles ──────────────────────────────────────────────
      if (show_stab && length(sel_ids) > 0) {
        STAB_COLS <- c("s11_mag","s11_ang","s12_mag","s12_ang",
                       "s21_mag","s21_ang","s22_mag","s22_ang")
        n_sc <- 0L
        for (id in sel_ids) {
          r  <- isolate(lp_datasets()[[id]])
          if (is.null(r) || !isTRUE(r$success)) next
          avail <- r$col_names %||% character(0)
          if (!all(STAB_COLS %in% avail)) next
          df_s <- .get_df(id, cols = c(STAB_COLS, "freq_ghz"))
          if (is.null(df_s) || nrow(df_s) == 0) next
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
          theta_sc <- seq(0, 2*pi, length.out = 200)
          cx <- Re(C_out); cy <- Im(C_out)
          sc_x <- cx + r_out * cos(theta_sc)
          sc_y <- cy + r_out * sin(theta_sc)
          sc_col <- c("#e377c2","#17becf","#bcbd22","#8c564b")[n_sc %% 4L + 1L]
          n_sc   <- n_sc + 1L
          fname_s <- .short_name(r$filename, 20L)
          p <- p %>% add_trace(type="scatter", mode="lines",
            x=sc_x, y=sc_y,
            line=list(color=sc_col, width=1.8, dash="dash"),
            name=paste0("Stab-out [",fname_s,"]"),
            hovertext=sprintf("Output stability circle<br>%s<br>C=(%.3f%+.3fj) r=%.3f",
                              fname_s, cx, cy, r_out),
            hoverinfo="text", showlegend=TRUE)
        }
        if (n_sc == 0L)
          p <- p %>% add_trace(type="scatter", mode="text", x=0, y=0,
            text="S-params needed for stability circles",
            textfont=list(color="#e8a000",size=11),
            hoverinfo="none", showlegend=FALSE, name="stab_note")
      }

      # ── Layout ─────────────────────────────────────────────────────────
      ax_range <- if (zoom_data && length(all_xv) > 0) {
        pad <- 0.08
        list(c(min(all_xv) - pad, max(all_xv) + pad),
             c(min(all_yv) - pad, max(all_yv) + pad))
      } else {
        list(c(-1.25, 1.25), c(-1.25, 1.25))
      }
      title_txt <- paste0(
        if (pull == "load") "Load Pull" else "Source Pull",
        " \u2014 Smith Chart",
        if (!is.null(panel_title)) paste0(" [", panel_title, "]") else " Contours")
      base_layout <- do.call(.smith_layout, list(
        title_txt = title_txt,
        xl = paste0("Re(\u0393_", if (pull == "load") "L" else "S", ")"),
        yl = paste0("Im(\u0393_", if (pull == "load") "L" else "S", ")")
      ))
      base_layout$xaxis$range <- ax_range[[1]]
      base_layout$yaxis$range <- ax_range[[2]]
      base_layout$margin <- list(l = 50,
                                 r = max(80, 80 + (colorbar_x - 1.02) / 0.13 * 60),
                                 t = 50, b = 50)
      p %>% layout(base_layout)
    } # end build_panel

    # ── Dispatch: side-by-side or single chart ────────────────────────────
    if (do_side_by_side) {
      inner_col <- "freq_ghz"    # within each tag panel, still split by freq
      panels <- lapply(tag_vals, function(tag) {
        build_panel(panel_tag_filter = tag, inner_split_col = inner_col,
                    panel_title = tag)
      })
      n_panels <- length(panels)
      plotly::subplot(panels, nrows = 1, shareX = FALSE, shareY = FALSE,
                      titleX = TRUE, titleY = TRUE,
                      widths = rep(1 / n_panels, n_panels)) %>%
        layout(paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
               font = list(color = "#aaa"))
    } else {
      build_panel(panel_tag_filter = NULL, inner_split_col = sv)
    }
  })

  output$lp_xy_plot <- renderPlotly({
    sel_ids <- input$lp_xy_dataset_selector
    y_vars  <- input$lp_xy_y_vars
    x_var   <- input$lp_xy_x_var %||% "pin_dbm"
    sv      <- .eff_split("xy")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    if (is.null(y_vars) || length(y_vars) == 0) return(ep("Select variables to plot"))
    EFF_VARS <- c("pae_pct", "de_pct")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); i_col <- 1L
    for (di in seq_along(sel_ids)) {
      id   <- sel_ids[di]
      need <- unique(c(x_var, y_vars, "gl_r", "gl_i", sv))
      df   <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) next
      ds_nm <- if (multi_ds) {
        r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 20L)
      } else ""
      ord <- order(df[[x_var]], na.last = NA); df <- df[ord, , drop = FALSE]
      xv     <- df[[x_var]]
      y1_labels <- c(); y2_labels <- c()
      splits  <- .split_vals(df, sv)
      multi_f <- length(splits) > 1
      for (v in y_vars) {
        if (!v %in% names(df)) next
        on_y2 <- v %in% EFF_VARS
        lbl   <- switch(v, pae_pct="PAE (%)", de_pct="DE (%)", gain_db="Gain (dB)",
                          pout_dbm="Pout (dBm)", pout_w="Pout (W)", pin_dbm="Pin (dBm)",
                          gsub("_", " ", v))
        if (on_y2) y2_labels <- c(y2_labels, lbl) else y1_labels <- c(y1_labels, lbl)
        if (multi_f) {
          for (fi in seq_along(splits)) {
            sv_val <- splits[fi]
            col <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]; i_col <- i_col + 1L
            dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
            lns <- .lp_lines_by_load(dff, x_var, v)
            lbl_s <- .split_lbl(sv_val, sv)
            leg <- if (multi_ds) .trunc_lbl(sprintf("%s@%s[%s]", lbl, lbl_s, ds_nm)) else
                   .trunc_lbl(sprintf("%s @ %s", lbl, lbl_s))
            p <- p %>% add_trace(type="scattergl", mode="lines+markers",
              x=lns$x, y=lns$y, yaxis=if(on_y2)"y2" else "y",
              name=leg, opacity=0.80,
              line=list(color=col, width=1.2),
              marker=list(color=col, size=4,
                          symbol=if(on_y2)"circle-open" else "circle", opacity=0.70))
          }
        } else {
          col <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]; i_col <- i_col + 1L
          lns <- .lp_lines_by_load(df, x_var, v)
          leg <- if (multi_ds) paste0(lbl, " [", ds_nm, "]") else lbl
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns$x, y=lns$y, yaxis=if(on_y2)"y2" else "y",
            name=leg, opacity=0.80,
            line=list(color=col, width=1.2),
            marker=list(color=col, size=4,
                        symbol=if(on_y2)"circle-open" else "circle", opacity=0.70))
        }
      }
    }
    y1_title <- if (length(y1_labels) > 0) paste(unique(y1_labels), collapse=" / ") else "Value"
    y2_title <- if (length(y2_labels) > 0) paste(unique(y2_labels), collapse=" / ") else "Efficiency (%)"
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=gsub("_"," ",x_var), color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title=y1_title, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis2 = list(title=y2_title, color="#aaa", overlaying="y", side="right", showgrid=FALSE, zeroline=FALSE),
      legend = list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.30)"),
      title  = list(text="XY Performance", font=list(color="#eee", size=14)),
      font=list(color="#aaa"), margin=list(l=60, r=70, t=50, b=60))
  })


  # â”€â”€ Performance tab â€” dataset selector â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  .make_selector("lp_perf_dataset_selector", "Dataset(s)")

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
  # ── Helper: build NA-separated x/y vectors grouped by load point ─────────
  .lp_lines_by_load <- function(dff, x_var, y_var) {
    has_gl <- all(c("gl_r","gl_i") %in% names(dff))
    if (!has_gl || !x_var %in% names(dff) || !y_var %in% names(dff))
      return(list(x=dff[[x_var]], y=dff[[y_var]]))
    gl_key <- paste(round(dff$gl_r, 5), round(dff$gl_i, 5))
    grps <- unique(gl_key)
    xo <- c(); yo <- c()
    for (gk in grps) {
      m  <- gl_key == gk
      dg <- dff[m, , drop=FALSE]
      dg <- dg[order(dg[[x_var]], na.last=NA), , drop=FALSE]
      xo <- c(xo, dg[[x_var]], NA_real_)
      yo <- c(yo, dg[[y_var]], NA_real_)
    }
    list(x=head(xo,-1), y=head(yo,-1))  # drop trailing NA
  }

  output$lp_perf_gain_plot <- renderPlotly({
    sel_ids <- input$lp_perf_dataset_selector
    x_var   <- input$lp_perf_x_var   %||% "pout_dbm"
    y2_v    <- input$lp_perf_gain_y2 %||% "none"
    pt_op   <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    sv      <- .eff_split("perf")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    col_off <- 0L
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c(x_var, "gain_db", sv, "gl_r", "gl_i", if (y2_v != "none") y2_v))
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) { col_off <- col_off + 3L; next }
      splits  <- .split_vals(df, sv)
      multi_f <- length(splits) > 1
      if ("gain_db" %in% names(df)) {
        if (multi_f) {
          for (fi in seq_along(splits)) {
            sv_val <- splits[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
            dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
            lns <- .lp_lines_by_load(dff, x_var, "gain_db")
            lbl_s <- .split_lbl(sv_val, sv)
            lbl <- if (multi_ds) .trunc_lbl(sprintf("Gain @ %s [%s]", lbl_s, ds_nm))
                   else .trunc_lbl(sprintf("Gain @ %s", lbl_s))
            p <- p %>% add_trace(type="scattergl", mode="lines+markers",
              x=lns$x, y=lns$y, yaxis="y", name=lbl,
              line=list(color=col, width=1.2),
              marker=list(color=col, size=4, opacity=pt_op))
          }
        } else {
          col <- MPAL[(col_off %% length(MPAL)) + 1L]
          lns <- .lp_lines_by_load(df, x_var, "gain_db")
          lbl <- if (multi_ds) paste0("Gain [", ds_nm, "]") else "Gain (dB)"
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns$x, y=lns$y, yaxis="y", name=lbl,
            line=list(color=col, width=1.2),
            marker=list(color=col, size=4, opacity=pt_op))
        }
      }
      y2_lbl <- ""
      if (y2_v != "none" && y2_v %in% names(df)) {
        y2_lbl <- switch(y2_v, pae_pct="PAE (%)", de_pct="DE (%)",
                                pout_dbm="Pout (dBm)", pout_w="Pout (W)", y2_v)
        if (multi_f) {
          for (fi in seq_along(splits)) {
            sv_val <- splits[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
            dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
            lns2 <- .lp_lines_by_load(dff, x_var, y2_v)
            lbl_s <- .split_lbl(sv_val, sv)
            lbl2 <- if (multi_ds) .trunc_lbl(sprintf("%s @ %s [%s]", y2_lbl, lbl_s, ds_nm))
                    else .trunc_lbl(sprintf("%s @ %s", y2_lbl, lbl_s))
            p <- p %>% add_trace(type="scattergl", mode="lines+markers",
              x=lns2$x, y=lns2$y, yaxis="y2", name=lbl2,
              line=list(color=col, width=1.2, dash="dot"),
              marker=list(color=col, size=4, symbol="circle-open", opacity=pt_op))
          }
        } else {
          col <- MPAL[(col_off %% length(MPAL)) + 1L]
          lns2 <- .lp_lines_by_load(df, x_var, y2_v)
          lbl2 <- if (multi_ds) paste0(y2_lbl, " [", ds_nm, "]") else y2_lbl
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns2$x, y=lns2$y, yaxis="y2", name=lbl2,
            line=list(color=col, width=1.2, dash="dot"),
            marker=list(color=col, size=4, symbol="circle-open", opacity=pt_op))
        }
      }
      # Back-off line per dataset (use first dataset only to avoid clutter)
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && !is.null(df$pout_dbm)) {
        pmax <- suppressWarnings(max(df$pout_dbm, na.rm=TRUE))
        if (is.finite(pmax)) shapes_list[[1]] <- list(
          type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="Gain (dB)", color="#ff7f11", showgrid=TRUE,
                    gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#ff7f11")),
      yaxis2 = list(title=if(nchar(y2_lbl)>0)y2_lbl else "",
                    color="#1f77b4", overlaying="y", side="right", showgrid=FALSE,
                    zeroline=FALSE, tickfont=list(color="#1f77b4")),
      shapes=shapes_list,
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text="Gain", font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=60, r=60, t=35, b=50))
  })

  # ── Performance: Efficiency subplot ───────────────────────────────────────
  output$lp_perf_eff_plot <- renderPlotly({
    sel_ids  <- input$lp_perf_dataset_selector
    x_var    <- input$lp_perf_x_var  %||% "pout_dbm"
    y2_v     <- input$lp_perf_eff_y2 %||% "none"
    pt_op    <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    sv       <- .eff_split("perf")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL    <- c("#1f77b4","#2ca02c","#d62728","#9467bd","#8c564b",
                 "#e377c2","#17becf","#bcbd22","#7f7f7f","#ff7f11")
    EFF_VARS <- c("pae_pct","de_pct")
    EFF_SYMS <- c(pae_pct="circle", de_pct="circle-open")
    EFF_LBLS <- c(pae_pct="PAE (%)", de_pct="DE (%)")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    col_off <- 0L
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    shapes_list <- list(); y2_lbl <- ""
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c(x_var, "pae_pct", "de_pct", "gain_db", sv, "gl_r", "gl_i",
                        if (y2_v != "none") y2_v))
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) { col_off <- col_off + 3L; next }
      splits  <- .split_vals(df, sv)
      multi_f <- length(splits) > 1
      if (multi_f) {
        for (fi in seq_along(splits)) {
          sv_val <- splits[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
          lbl_s <- .split_lbl(sv_val, sv)
          for (ev in EFF_VARS) {
            if (!ev %in% names(dff)) next
            lns <- .lp_lines_by_load(dff, x_var, ev)
            if (all(is.na(lns$y))) next
            lbl <- if (multi_ds) .trunc_lbl(sprintf("%s @ %s [%s]", EFF_LBLS[ev], lbl_s, ds_nm))
                   else .trunc_lbl(sprintf("%s @ %s", EFF_LBLS[ev], lbl_s))
            p <- p %>% add_trace(type="scattergl", mode="lines+markers",
              x=lns$x, y=lns$y, yaxis="y", name=lbl,
              line=list(color=col, width=1.2,
                        dash=if(ev=="de_pct") "dot" else "solid"),
              marker=list(color=col, size=4, symbol=EFF_SYMS[ev], opacity=pt_op))
          }
        }
      } else {
        PAL_EFF <- c(MPAL[(col_off %% length(MPAL)) + 1L],
                     MPAL[((col_off + 1L) %% length(MPAL)) + 1L])
        ic <- 1L
        for (ev in EFF_VARS) {
          if (!ev %in% names(df)) { ic <- ic+1L; next }
          cl <- PAL_EFF[(ic-1L)%%2L+1L]; ic <- ic+1L
          lns <- .lp_lines_by_load(df, x_var, ev)
          if (all(is.na(lns$y))) next
          lbl <- if (multi_ds) paste0(EFF_LBLS[ev], " [", ds_nm, "]") else EFF_LBLS[ev]
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns$x, y=lns$y, yaxis="y", name=lbl,
            line=list(color=cl, width=1.2,
                      dash=if(ev=="de_pct") "dot" else "solid"),
            marker=list(color=cl, size=4, symbol=EFF_SYMS[ev], opacity=pt_op))
        }
      }
      if (y2_v != "none" && y2_v %in% names(df) && di == 1L) {
        y2_lbl <- switch(y2_v, gain_db="Gain (dB)", pout_dbm="Pout (dBm)",
                                pout_w="Pout (W)", y2_v)
        if (multi_f) {
          for (fi in seq_along(splits)) {
            sv_val <- splits[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
            dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
            lns2 <- .lp_lines_by_load(dff, x_var, y2_v)
            lbl2 <- .trunc_lbl(sprintf("%s @ %s", y2_lbl, .split_lbl(sv_val, sv)))
            p <- p %>% add_trace(type="scattergl", mode="lines+markers",
              x=lns2$x, y=lns2$y, yaxis="y2", name=lbl2,
              line=list(color="#ff7f11", width=1.2, dash="dash"),
              marker=list(color="#ff7f11", size=4, symbol="circle-open", opacity=pt_op))
          }
        } else {
          lns2 <- .lp_lines_by_load(df, x_var, y2_v)
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns2$x, y=lns2$y, yaxis="y2", name=y2_lbl,
            line=list(color="#ff7f11", width=1.2, dash="dash"),
            marker=list(color="#ff7f11", size=4, symbol="circle-open", opacity=pt_op))
        }
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && !is.null(df$pout_dbm)) {
        pmax <- suppressWarnings(max(df$pout_dbm, na.rm=TRUE))
        if (is.finite(pmax)) shapes_list[[1]] <- list(
          type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="Efficiency (%)", color="#1f77b4", showgrid=TRUE,
                    gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#1f77b4")),
      yaxis2 = list(title=y2_lbl, color="#ff7f11", overlaying="y", side="right",
                    showgrid=FALSE, zeroline=FALSE, tickfont=list(color="#ff7f11")),
      shapes=shapes_list,
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text="Efficiency", font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=60, r=60, t=35, b=50))
  })

  # ── Performance: Smith Source (Γ_S) ───────────────────────────────────────
  output$lp_perf_smith_s <- renderPlotly({
    sel_ids   <- input$lp_perf_dataset_selector
    z0        <- as.numeric(input$lp_perf_z0_norm %||% 50)
    px_db_p   <- as.numeric(input$lp_perf_px_db   %||% 0)
    px_tol_p  <- as.numeric(input$lp_perf_px_tol  %||% 0.3)
    show_harm <- isTRUE(input$lp_perf_show_harmonics)
    show_opt  <- isTRUE(input$lp_perf_show_opt %||% TRUE)
    show_gin  <- isTRUE(input$lp_perf_show_gin %||% TRUE)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    multi <- length(sel_ids) > 1L
    grid  <- build_smith_grid()
    p     <- plot_ly()
    for (tr in grid) p <- p %>% add_trace(type="scatter", mode="lines",
      x=tr$x, y=tr$y, line=tr$line, hoverinfo="none", showlegend=FALSE, name=tr$name)
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_col <- PALETTE[((di - 1L) %% length(PALETTE)) + 1L]
      ds_lbl <- if (multi) {
        r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 20L)
      } else ""
      df <- .get_df(id, cols = c("gs_r","gs_i","gin_r","gin_i","pout_dbm","gain_db","pae_pct",
                                  "freq_ghz", "pin_dbm",
                                  if (show_harm) c("gs2_r","gs2_i","gs3_r","gs3_i")))
      if (is.null(df) || !"gs_r" %in% names(df)) next
      if (px_db_p > 0.01) {
        df <- .px_filter_df(df, px_db_p, px_tol_p, "gs_r", "gs_i")
        if (nrow(df) == 0) next
      }
      ng <- .renorm_g(df$gs_r, df$gs_i, z0)
      xv <- ng$r; yv <- ng$i
      ok <- !is.na(xv) & !is.na(yv) & (xv^2 + yv^2) <= 1.02
      lbl <- if (multi) paste0("\u0393_S [", ds_lbl, "]") else "\u0393_S"
      if (!multi) {
        cv <- df$pout_dbm %||% rep(NA_real_, nrow(df))
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], opacity=0.65,
          marker=list(color=cv[ok], colorscale="Jet", size=7, showscale=TRUE,
                      opacity=0.60,
                      colorbar=list(title="Pout(dBm)", len=0.6,
                                   tickfont=list(color="#aaa", size=9),
                                   titlefont=list(color="#aaa", size=10))),
          name=lbl, hoverinfo="text",
          hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
            "Re(\u0393_S): %.4f<br>Im(\u0393_S): %.4f<br>R_S: %.2f \u03a9<br>X_S: %.2f \u03a9<br>Pout: %.1f dBm",
            xv[ok],yv[ok],zz$r,zz$x,cv[ok])})
      } else {
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], opacity=0.65,
          marker=list(color=ds_col, size=7, opacity=0.60),
          name=lbl, hoverinfo="text",
          hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
            "Re(\u0393_S): %.4f<br>Im(\u0393_S): %.4f<br>R_S: %.2f \u03a9<br>X_S: %.2f \u03a9",
            xv[ok],yv[ok],zz$r,zz$x)})
      }
      if (show_harm) {
        for (h in list(list(r="gs2_r", i="gs2_i", ord="2H"),
                       list(r="gs3_r", i="gs3_i", ord="3H"))) {
          if (!all(c(h$r, h$i) %in% names(df))) next
          ngh  <- .renorm_g(df[[h$r]], df[[h$i]], z0)
          ok_h <- !is.na(ngh$r) & !is.na(ngh$i)
          if (sum(ok_h) == 0) next
          hlbl <- if (multi) paste0(h$ord, " \u0393_S [", ds_lbl, "]")
                  else paste0(h$ord, " \u0393_S")
          p <- p %>% add_trace(type="scatter", mode="markers",
            x=ngh$r[ok_h], y=ngh$i[ok_h],
            marker=list(color=ds_col, size=6, symbol="x", opacity=0.8),
            name=hlbl, showlegend=TRUE, hoverinfo="none")
        }
      }
      if (show_gin && all(c("gin_r","gin_i") %in% names(df)) &&
          !all(is.na(df$gin_r))) {
        ng_in <- .renorm_g(df$gin_r, df$gin_i, z0)
        ok_in <- !is.na(ng_in$r) & !is.na(ng_in$i)
        if (sum(ok_in) > 0) {
          gin_lbl <- if (multi) paste0("\u0393_in [", ds_lbl, "]") else "\u0393_in (meas.)"
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=ng_in$r[ok_in], y=ng_in$i[ok_in], opacity=0.70,
            marker=list(color="#e6550d", size=5, symbol="square-open", opacity=0.65),
            name=gin_lbl, showlegend=TRUE, hoverinfo="none")
        }
      }
      if (show_opt) {
        opt <- .find_optima(df)
        OC  <- list(MXP=list(col="pout_dbm", sym="star",       color="#ff7f11"),
                    MXE=list(col="pae_pct",  sym="diamond",    color="#1f77b4"),
                    MXG=list(col="gain_db",  sym="triangle-up", color="#2ca02c"))
        for (nm in names(OC)) {
          bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
          if (!cfg$col %in% names(df)) next
          ng_o <- .renorm_g(df$gs_r[bi], df$gs_i[bi], z0)
          olbl <- if (multi) paste0(nm, " [", ds_lbl, "]") else nm
          p <- p %>% add_trace(type="scatter", mode="markers+text",
            x=ng_o$r, y=ng_o$i,
            text=sprintf("%s\n%.1f", nm, df[[cfg$col]][bi]),
            textposition="top center", textfont=list(color=cfg$color, size=10),
            marker=list(color=cfg$color, size=14, symbol=cfg$sym,
                        line=list(color="white", width=1.5)),
            name=olbl, showlegend=TRUE)
        }
      }
    }
    z_lbl <- if (abs(z0 - 50) < 0.1) "50\u03a9" else sprintf("%.0f\u03a9", z0)
    sl <- .smith_layout(title_txt=paste0("Source \u0393_S  (Z\u2080=", z_lbl, ")"),
                        xl="Re(\u0393_S)", yl="Im(\u0393_S)")
    p %>% layout(sl)
  })

  # ── Performance: Smith Load (Γ_L) ─────────────────────────────────────────
  output$lp_perf_smith_l <- renderPlotly({
    sel_ids   <- input$lp_perf_dataset_selector
    z0        <- as.numeric(input$lp_perf_z0_norm %||% 50)
    px_db_p   <- as.numeric(input$lp_perf_px_db   %||% 0)
    px_tol_p  <- as.numeric(input$lp_perf_px_tol  %||% 0.3)
    show_harm <- isTRUE(input$lp_perf_show_harmonics)
    show_opt  <- isTRUE(input$lp_perf_show_opt %||% TRUE)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    multi <- length(sel_ids) > 1L
    grid  <- build_smith_grid()
    p     <- plot_ly()
    for (tr in grid) p <- p %>% add_trace(type="scatter", mode="lines",
      x=tr$x, y=tr$y, line=tr$line, hoverinfo="none", showlegend=FALSE, name=tr$name)
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_col <- PALETTE[((di - 1L) %% length(PALETTE)) + 1L]
      ds_lbl <- if (multi) {
        r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 20L)
      } else ""
      df <- .get_df(id, cols = c("gl_r","gl_i","pout_dbm","gain_db","pae_pct",
                                  "freq_ghz", "pin_dbm",
                                  if (show_harm) c("gl2_r","gl2_i","gl3_r","gl3_i")))
      if (is.null(df) || !"gl_r" %in% names(df)) next
      if (px_db_p > 0.01) {
        df <- .px_filter_df(df, px_db_p, px_tol_p, "gl_r", "gl_i")
        if (nrow(df) == 0) next
      }
      ng <- .renorm_g(df$gl_r, df$gl_i, z0)
      xv <- ng$r; yv <- ng$i
      ok <- !is.na(xv) & !is.na(yv) & (xv^2 + yv^2) <= 1.02
      lbl <- if (multi) paste0("\u0393_L [", ds_lbl, "]") else "\u0393_L"
      if (!multi) {
        cv <- df$pout_dbm %||% rep(NA_real_, nrow(df))
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], opacity=0.65,
          marker=list(color=cv[ok], colorscale="Jet", size=7, showscale=TRUE,
                      opacity=0.60,
                      colorbar=list(title="Pout(dBm)", len=0.6,
                                   tickfont=list(color="#aaa", size=9),
                                   titlefont=list(color="#aaa", size=10))),
          name=lbl, hoverinfo="text",
          hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
            "Re(\u0393_L): %.4f<br>Im(\u0393_L): %.4f<br>R_L: %.2f \u03a9<br>X_L: %.2f \u03a9<br>Pout: %.1f dBm",
            xv[ok],yv[ok],zz$r,zz$x,cv[ok])})
      } else {
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], opacity=0.65,
          marker=list(color=ds_col, size=7, opacity=0.60),
          name=lbl, hoverinfo="text",
          hovertext={zz<-.gamma_to_z(xv[ok],yv[ok],z0); sprintf(
            "Re(\u0393_L): %.4f<br>Im(\u0393_L): %.4f<br>R_L: %.2f \u03a9<br>X_L: %.2f \u03a9",
            xv[ok],yv[ok],zz$r,zz$x)})
      }
      if (show_harm) {
        for (h in list(list(r="gl2_r", i="gl2_i", ord="2H"),
                       list(r="gl3_r", i="gl3_i", ord="3H"))) {
          if (!all(c(h$r, h$i) %in% names(df))) next
          ngh  <- .renorm_g(df[[h$r]], df[[h$i]], z0)
          ok_h <- !is.na(ngh$r) & !is.na(ngh$i)
          if (sum(ok_h) == 0) next
          hlbl <- if (multi) paste0(h$ord, " \u0393_L [", ds_lbl, "]")
                  else paste0(h$ord, " \u0393_L")
          p <- p %>% add_trace(type="scatter", mode="markers",
            x=ngh$r[ok_h], y=ngh$i[ok_h],
            marker=list(color=ds_col, size=6, symbol="x", opacity=0.8),
            name=hlbl, showlegend=TRUE, hoverinfo="none")
        }
      }
      if (show_opt) {
        opt <- .find_optima(df)
        OC  <- list(MXP=list(col="pout_dbm", sym="star",       color="#ff7f11"),
                    MXE=list(col="pae_pct",  sym="diamond",    color="#1f77b4"),
                    MXG=list(col="gain_db",  sym="triangle-up", color="#2ca02c"))
        for (nm in names(OC)) {
          bi <- opt[[nm]]; if (is.na(bi)) next; cfg <- OC[[nm]]
          if (!cfg$col %in% names(df)) next
          ng_o <- .renorm_g(df$gl_r[bi], df$gl_i[bi], z0)
          olbl <- if (multi) paste0(nm, " [", ds_lbl, "]") else nm
          p <- p %>% add_trace(type="scatter", mode="markers+text",
            x=ng_o$r, y=ng_o$i,
            text=sprintf("%s\n%.1f", nm, df[[cfg$col]][bi]),
            textposition="top center", textfont=list(color=cfg$color, size=10),
            marker=list(color=cfg$color, size=14, symbol=cfg$sym,
                        line=list(color="white", width=1.5)),
            name=olbl, showlegend=TRUE)
        }
      }
    }
    z_lbl <- if (abs(z0 - 50) < 0.1) "50\u03a9" else sprintf("%.0f\u03a9", z0)
    sl <- .smith_layout(title_txt=paste0("Load \u0393_L  (Z\u2080=", z_lbl, ")"),
                        xl="Re(\u0393_L)", yl="Im(\u0393_L)")
    p %>% layout(sl)
  })

  # ── Nose Plot 1: Efficiency Nose — MXE per load point ────────────────────
  # For each unique ZL in the sweep, pick the row with max PAE (or DE).
  # Scatter: X = Pout at that max, Y = PAE at that max.
  output$lp_nose_mxe <- renderPlotly({
    sel_ids  <- input$lp_nose_dataset_selector
    x_var    <- input$lp_nose_x_pw  %||% "pout_dbm"
    z0       <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    pt_op    <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    bo_db    <- as.numeric(input$lp_backoff_db %||% 6)
    px_db    <- as.numeric(input$lp_nose_px_db  %||% 0)
    px_tol   <- as.numeric(input$lp_nose_px_tol %||% 0.3)
    mark_opt    <- isTRUE(input$lp_nose_mark_opt   %||% TRUE)
    show_labels <- isTRUE(input$lp_nose_show_labels %||% TRUE)
    if (!is.finite(px_db)  || px_db  < 0) px_db  <- 0
    if (!is.finite(px_tol) || px_tol <= 0) px_tol <- 0.3
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
               title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#1f77b4","#ff7f11","#2ca02c","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv       <- .eff_split("nose")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); col_off <- 0L; shapes_list <- list()
    annot_xs <- c(); annot_ys <- c(); annot_lbl <- c()
    annot_col <- c(); annot_arr <- c()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c("gl_r","gl_i","pae_pct","de_pct","gain_db","pout_dbm","pin_dbm","pout_w", sv))
      df    <- .get_df(id, cols = need)
      if (is.null(df)) next
      eff_col <- if ("pae_pct" %in% names(df) && any(!is.na(df$pae_pct))) "pae_pct" else
                 if ("de_pct"  %in% names(df) && any(!is.na(df$de_pct)))  "de_pct"  else NULL
      if (is.null(eff_col)) next
      eff_lbl <- if (eff_col == "pae_pct") "PAE (%)" else "DE (%)"
      pts <- .nose_px_reduce(df, eff_col, px_db, px_tol)
      if (is.null(pts) || !x_var %in% names(pts)) next
      splits  <- .split_vals(pts, sv)
      multi_f <- length(splits) > 1
      zl   <- .gamma_to_z(pts$gl_r, pts$gl_i, z0)
      pdbm <- if ("pout_dbm" %in% names(pts)) pts$pout_dbm else rep(NA_real_, nrow(pts))
      gdb  <- if ("gain_db"  %in% names(pts)) pts$gain_db  else rep(NA_real_, nrow(pts))
      htxt <- sprintf(
        "\u0393L = %.3f%+.3fj<br>ZL = %.1f%+.1fj \u03a9<br>Pout = %.1f dBm<br>%s = %.1f%%<br>Gain = %.2f dB",
        pts$gl_r, pts$gl_i, zl$r, zl$x, pdbm, eff_lbl, pts[[eff_col]], gdb)
      xv <- pts[[x_var]]; yv <- pts[[eff_col]]; ok <- !is.na(xv) & !is.na(yv)
      if (multi_f) {
        for (fi in seq_along(splits)) {
          sv_val <- splits[fi]; sel <- ok & !is.na(pts[[sv]]) & as.character(pts[[sv]]) == sv_val
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          lbl <- if (multi_ds) .trunc_lbl(sprintf("%s [%s]", .split_lbl(sv_val, sv), ds_nm))
                 else .trunc_lbl(.split_lbl(sv_val, sv))
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[sel], y=yv[sel], name=lbl,
            marker=list(color=col, size=8, opacity=pt_op,
                        line=list(color="rgba(255,255,255,0.4)", width=0.8)),
            hovertext=htxt[sel], hoverinfo="text")
          if (mark_opt && any(sel)) {
            pts_f <- pts[sel, , drop=FALSE]
            xvf <- xv[sel]; yvf <- yv[sel]
            # MXE: max efficiency at this split value
            bi_e <- which.max(pts_f[[eff_col]])
            if (length(bi_e) > 0 && is.finite(xvf[bi_e]) && is.finite(yvf[bi_e])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvf[bi_e], y=yvf[bi_e],
                name=if(multi_ds) sprintf("MXE %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXE %s",.split_lbl(sv_val,sv)),
                marker=list(color=col, size=14, symbol="star",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvf[bi_e])
              annot_ys  <- c(annot_ys,  yvf[bi_e])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXE</b><br>%.1f%%<br>%s", yvf[bi_e], .split_lbl(sv_val, sv)))
              annot_col <- c(annot_col, col);       annot_arr <- c(annot_arr, col)
            }
            # MXP: max Pout at this split value
            if ("pout_dbm" %in% names(pts_f)) {
              bi_p <- which.max(pts_f$pout_dbm)
              if (length(bi_p) > 0 && is.finite(xvf[bi_p]) && is.finite(yvf[bi_p])) {
                p <- p %>% add_trace(type="scatter", mode="markers",
                  x=xvf[bi_p], y=yvf[bi_p],
                  name=if(multi_ds) sprintf("MXP %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXP %s",.split_lbl(sv_val,sv)),
                  marker=list(color="#ff7f11", size=12, symbol="diamond",
                              line=list(color="white", width=1.5)),
                  showlegend=FALSE, hoverinfo="skip")
                annot_xs  <- c(annot_xs,  xvf[bi_p])
                annot_ys  <- c(annot_ys,  yvf[bi_p])
                annot_lbl <- c(annot_lbl, sprintf("<b>MXP</b><br>%.1f dBm<br>%s",
                                                   pts_f$pout_dbm[bi_p], .split_lbl(sv_val, sv)))
                annot_col <- c(annot_col, "#ff7f11"); annot_arr <- c(annot_arr, "#ff7f11")
              }
            }
            # MXG: max Gain at this split value
            if ("gain_db" %in% names(pts_f)) {
              bi_g <- which.max(pts_f$gain_db)
              if (length(bi_g) > 0 && is.finite(xvf[bi_g]) && is.finite(yvf[bi_g])) {
                p <- p %>% add_trace(type="scatter", mode="markers",
                  x=xvf[bi_g], y=yvf[bi_g],
                  name=if(multi_ds) sprintf("MXG %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXG %s",.split_lbl(sv_val,sv)),
                  marker=list(color="#2ca02c", size=12, symbol="triangle-up",
                              line=list(color="white", width=1.5)),
                  showlegend=FALSE, hoverinfo="skip")
                annot_xs  <- c(annot_xs,  xvf[bi_g])
                annot_ys  <- c(annot_ys,  yvf[bi_g])
                annot_lbl <- c(annot_lbl, sprintf("<b>MXG</b><br>%.1f dB<br>%s",
                                                   pts_f$gain_db[bi_g], .split_lbl(sv_val, sv)))
                annot_col <- c(annot_col, "#2ca02c"); annot_arr <- c(annot_arr, "#2ca02c")
              }
            }
          }
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        lbl <- if (multi_ds) paste0(eff_lbl, " [", ds_nm, "]") else eff_lbl
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], name=lbl,
          marker=list(color=col, size=8, opacity=pt_op,
                      line=list(color="rgba(255,255,255,0.4)", width=0.8)),
          hovertext=htxt[ok], hoverinfo="text")
        if (mark_opt && any(ok)) {
          pts_ok <- pts[ok, , drop=FALSE]; xvok <- xv[ok]; yvok <- yv[ok]
          bi_e <- which.max(pts_ok[[eff_col]])
          if (length(bi_e) > 0 && is.finite(xvok[bi_e]) && is.finite(yvok[bi_e])) {
            p <- p %>% add_trace(type="scatter", mode="markers",
              x=xvok[bi_e], y=yvok[bi_e],
              name=if(multi_ds) paste0("MXE [",ds_nm,"]") else "MXE",
              marker=list(color=col, size=14, symbol="star",
                          line=list(color="white", width=1.5)),
              showlegend=FALSE, hoverinfo="skip")
            annot_xs  <- c(annot_xs,  xvok[bi_e])
            annot_ys  <- c(annot_ys,  yvok[bi_e])
            annot_lbl <- c(annot_lbl, sprintf("<b>MXE</b><br>%.1f%%", yvok[bi_e]))
            annot_col <- c(annot_col, col); annot_arr <- c(annot_arr, col)
          }
          if ("pout_dbm" %in% names(pts_ok)) {
            bi_p <- which.max(pts_ok$pout_dbm)
            if (length(bi_p) > 0 && is.finite(xvok[bi_p]) && is.finite(yvok[bi_p])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvok[bi_p], y=yvok[bi_p],
                name=if(multi_ds) paste0("MXP [",ds_nm,"]") else "MXP",
                marker=list(color="#ff7f11", size=12, symbol="diamond",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvok[bi_p])
              annot_ys  <- c(annot_ys,  yvok[bi_p])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXP</b><br>%.1f dBm", pts_ok$pout_dbm[bi_p]))
              annot_col <- c(annot_col, "#ff7f11"); annot_arr <- c(annot_arr, "#ff7f11")
            }
          }
          if ("gain_db" %in% names(pts_ok)) {
            bi_g <- which.max(pts_ok$gain_db)
            if (length(bi_g) > 0 && is.finite(xvok[bi_g]) && is.finite(yvok[bi_g])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvok[bi_g], y=yvok[bi_g],
                name=if(multi_ds) paste0("MXG [",ds_nm,"]") else "MXG",
                marker=list(color="#2ca02c", size=12, symbol="triangle-up",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvok[bi_g])
              annot_ys  <- c(annot_ys,  yvok[bi_g])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXG</b><br>%.1f dB", pts_ok$gain_db[bi_g]))
              annot_col <- c(annot_col, "#2ca02c"); annot_arr <- c(annot_arr, "#2ca02c")
            }
          }
        }
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && any(!is.na(xv))) {
        pmax <- max(xv, na.rm=TRUE)
        if (is.finite(pmax)) shapes_list[[1]] <- list(type="line",
          x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    annots <- if (mark_opt && show_labels && length(annot_xs) > 0)
                .anno_nonoverlap(annot_xs, annot_ys, annot_lbl, annot_col, annot_arr)
              else list()
    xl <- switch(x_var, pout_dbm="Pout (dBm)", pin_dbm="Pin (dBm)", pout_w="Pout (W)", x_var)
    eff_lbl_axis <- if (all(sapply(sel_ids, function(i) {
      d2 <- .get_df(i, cols = "de_pct")
      !is.null(d2) && "de_pct" %in% names(d2) && any(!is.na(d2$de_pct))
    }))) "DE (%)" else "PAE (%)"
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      annotations=annots,
      xaxis=list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis=list(title=eff_lbl_axis, color="#1f77b4", showgrid=TRUE,
                 gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#1f77b4")),
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text=paste0("Efficiency Nose \u2014 MXE per load point vs ", xl),
                 font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=20, t=40, b=50)) %>%
    plotly::config(editable = TRUE, edits = list(annotationPosition = TRUE))
  })

  # ── Nose Plot 2: Gain Nose — MXG per load point ────────────────────────────
  # For each unique ZL in the sweep, pick the row with max Gain.
  # Scatter: X = Pout at that max, Y = Gain at that max.
  output$lp_nose_xy <- renderPlotly({
    sel_ids  <- input$lp_nose_dataset_selector
    x_var    <- input$lp_nose_x_pw  %||% "pout_dbm"
    z0       <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    pt_op    <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    bo_db    <- as.numeric(input$lp_backoff_db %||% 6)
    px_db    <- as.numeric(input$lp_nose_px_db  %||% 0)
    px_tol   <- as.numeric(input$lp_nose_px_tol %||% 0.3)
    mark_opt    <- isTRUE(input$lp_nose_mark_opt   %||% TRUE)
    show_labels <- isTRUE(input$lp_nose_show_labels %||% TRUE)
    if (!is.finite(px_db)  || px_db  < 0) px_db  <- 0
    if (!is.finite(px_tol) || px_tol <= 0) px_tol <- 0.3
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
               title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#2ca02c","#ff7f11","#1f77b4","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv       <- .eff_split("nose")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); col_off <- 0L; shapes_list <- list()
    annot_xs <- c(); annot_ys <- c(); annot_lbl <- c()
    annot_col <- c(); annot_arr <- c()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c("gl_r","gl_i","gain_db","pae_pct","de_pct","pout_dbm","pin_dbm","pout_w", sv))
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !"gain_db" %in% names(df) || all(is.na(df$gain_db))) next
      pts <- .nose_px_reduce(df, "gain_db", px_db, px_tol)
      if (is.null(pts) || !x_var %in% names(pts)) next
      eff_col <- if ("pae_pct" %in% names(pts) && any(!is.na(pts$pae_pct))) "pae_pct" else
                 if ("de_pct"  %in% names(pts) && any(!is.na(pts$de_pct)))  "de_pct"  else NULL
      eff_lbl <- if (!is.null(eff_col)) switch(eff_col, pae_pct="PAE (%)", de_pct="DE (%)") else "Eff"
      eff_v   <- if (!is.null(eff_col)) pts[[eff_col]] else rep(NA_real_, nrow(pts))
      splits  <- .split_vals(pts, sv)
      multi_f <- length(splits) > 1
      zl   <- .gamma_to_z(pts$gl_r, pts$gl_i, z0)
      pdbm <- if ("pout_dbm" %in% names(pts)) pts$pout_dbm else rep(NA_real_, nrow(pts))
      htxt <- sprintf(
        "\u0393L = %.3f%+.3fj<br>ZL = %.1f%+.1fj \u03a9<br>Pout = %.1f dBm<br>Gain = %.2f dB<br>%s = %.1f%%",
        pts$gl_r, pts$gl_i, zl$r, zl$x, pdbm, pts$gain_db, eff_lbl, eff_v)
      xv <- pts[[x_var]]; yv <- pts$gain_db; ok <- !is.na(xv) & !is.na(yv)
      if (multi_f) {
        for (fi in seq_along(splits)) {
          sv_val <- splits[fi]; sel <- ok & !is.na(pts[[sv]]) & as.character(pts[[sv]]) == sv_val
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          lbl <- if (multi_ds) .trunc_lbl(sprintf("%s [%s]", .split_lbl(sv_val, sv), ds_nm))
                 else .trunc_lbl(.split_lbl(sv_val, sv))
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[sel], y=yv[sel], name=lbl,
            marker=list(color=col, size=8, opacity=pt_op,
                        line=list(color="rgba(255,255,255,0.4)", width=0.8)),
            hovertext=htxt[sel], hoverinfo="text")
          if (mark_opt && any(sel)) {
            pts_f <- pts[sel, , drop=FALSE]
            xvf <- xv[sel]; yvf <- yv[sel]
            # MXG: max gain at this split value
            bi_g <- which.max(pts_f$gain_db)
            if (length(bi_g) > 0 && is.finite(xvf[bi_g]) && is.finite(yvf[bi_g])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvf[bi_g], y=yvf[bi_g],
                name=if(multi_ds) sprintf("MXG %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXG %s",.split_lbl(sv_val,sv)),
                marker=list(color=col, size=14, symbol="star",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvf[bi_g])
              annot_ys  <- c(annot_ys,  yvf[bi_g])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXG</b><br>%.1f dB<br>%s", yvf[bi_g], .split_lbl(sv_val, sv)))
              annot_col <- c(annot_col, col);       annot_arr <- c(annot_arr, col)
            }
            # MXP: max Pout at this split value
            if ("pout_dbm" %in% names(pts_f)) {
              bi_p <- which.max(pts_f$pout_dbm)
              if (length(bi_p) > 0 && is.finite(xvf[bi_p]) && is.finite(yvf[bi_p])) {
                p <- p %>% add_trace(type="scatter", mode="markers",
                  x=xvf[bi_p], y=yvf[bi_p],
                  name=if(multi_ds) sprintf("MXP %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXP %s",.split_lbl(sv_val,sv)),
                  marker=list(color="#ff7f11", size=12, symbol="diamond",
                              line=list(color="white", width=1.5)),
                  showlegend=FALSE, hoverinfo="skip")
                annot_xs  <- c(annot_xs,  xvf[bi_p])
                annot_ys  <- c(annot_ys,  yvf[bi_p])
                annot_lbl <- c(annot_lbl, sprintf("<b>MXP</b><br>%.1f dBm<br>%s",
                                                   pts_f$pout_dbm[bi_p], .split_lbl(sv_val, sv)))
                annot_col <- c(annot_col, "#ff7f11"); annot_arr <- c(annot_arr, "#ff7f11")
              }
            }
            # MXE: max efficiency at this split value
            if (!is.null(eff_col) && eff_col %in% names(pts_f)) {
              bi_e <- which.max(pts_f[[eff_col]])
              if (length(bi_e) > 0 && is.finite(xvf[bi_e]) && is.finite(yvf[bi_e])) {
                p <- p %>% add_trace(type="scatter", mode="markers",
                  x=xvf[bi_e], y=yvf[bi_e],
                  name=if(multi_ds) sprintf("MXE %s [%s]",.split_lbl(sv_val,sv),ds_nm) else sprintf("MXE %s",.split_lbl(sv_val,sv)),
                  marker=list(color="#1f77b4", size=12, symbol="triangle-up",
                              line=list(color="white", width=1.5)),
                  showlegend=FALSE, hoverinfo="skip")
                annot_xs  <- c(annot_xs,  xvf[bi_e])
                annot_ys  <- c(annot_ys,  yvf[bi_e])
                annot_lbl <- c(annot_lbl, sprintf("<b>MXE</b><br>%.1f%%<br>%s",
                                                   pts_f[[eff_col]][bi_e], .split_lbl(sv_val, sv)))
                annot_col <- c(annot_col, "#1f77b4"); annot_arr <- c(annot_arr, "#1f77b4")
              }
            }
          }
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        lbl <- if (multi_ds) paste0("Gain [", ds_nm, "]") else "Gain (dB)"
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], name=lbl,
          marker=list(color=col, size=8, opacity=pt_op,
                      line=list(color="rgba(255,255,255,0.4)", width=0.8)),
          hovertext=htxt[ok], hoverinfo="text")
        if (mark_opt && any(ok)) {
          pts_ok <- pts[ok, , drop=FALSE]; xvok <- xv[ok]; yvok <- yv[ok]
          bi_g <- which.max(pts_ok$gain_db)
          if (length(bi_g) > 0 && is.finite(xvok[bi_g]) && is.finite(yvok[bi_g])) {
            p <- p %>% add_trace(type="scatter", mode="markers",
              x=xvok[bi_g], y=yvok[bi_g],
              name=if(multi_ds) paste0("MXG [",ds_nm,"]") else "MXG",
              marker=list(color=col, size=14, symbol="star",
                          line=list(color="white", width=1.5)),
              showlegend=FALSE, hoverinfo="skip")
            annot_xs  <- c(annot_xs,  xvok[bi_g])
            annot_ys  <- c(annot_ys,  yvok[bi_g])
            annot_lbl <- c(annot_lbl, sprintf("<b>MXG</b><br>%.1f dB", yvok[bi_g]))
            annot_col <- c(annot_col, col); annot_arr <- c(annot_arr, col)
          }
          if ("pout_dbm" %in% names(pts_ok)) {
            bi_p <- which.max(pts_ok$pout_dbm)
            if (length(bi_p) > 0 && is.finite(xvok[bi_p]) && is.finite(yvok[bi_p])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvok[bi_p], y=yvok[bi_p],
                name=if(multi_ds) paste0("MXP [",ds_nm,"]") else "MXP",
                marker=list(color="#ff7f11", size=12, symbol="diamond",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvok[bi_p])
              annot_ys  <- c(annot_ys,  yvok[bi_p])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXP</b><br>%.1f dBm", pts_ok$pout_dbm[bi_p]))
              annot_col <- c(annot_col, "#ff7f11"); annot_arr <- c(annot_arr, "#ff7f11")
            }
          }
          if (!is.null(eff_col) && eff_col %in% names(pts_ok)) {
            bi_e <- which.max(pts_ok[[eff_col]])
            if (length(bi_e) > 0 && is.finite(xvok[bi_e]) && is.finite(yvok[bi_e])) {
              p <- p %>% add_trace(type="scatter", mode="markers",
                x=xvok[bi_e], y=yvok[bi_e],
                name=if(multi_ds) paste0("MXE [",ds_nm,"]") else "MXE",
                marker=list(color="#1f77b4", size=12, symbol="triangle-up",
                            line=list(color="white", width=1.5)),
                showlegend=FALSE, hoverinfo="skip")
              annot_xs  <- c(annot_xs,  xvok[bi_e])
              annot_ys  <- c(annot_ys,  yvok[bi_e])
              annot_lbl <- c(annot_lbl, sprintf("<b>MXE</b><br>%.1f%%", pts_ok[[eff_col]][bi_e]))
              annot_col <- c(annot_col, "#1f77b4"); annot_arr <- c(annot_arr, "#1f77b4")
            }
          }
        }
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && any(!is.na(xv))) {
        pmax <- max(xv, na.rm=TRUE)
        if (is.finite(pmax)) shapes_list[[1]] <- list(type="line",
          x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    annots <- if (mark_opt && show_labels && length(annot_xs) > 0)
                .anno_nonoverlap(annot_xs, annot_ys, annot_lbl, annot_col, annot_arr)
              else list()
    xl <- switch(x_var, pout_dbm="Pout (dBm)", pin_dbm="Pin (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      annotations=annots,
      xaxis=list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis=list(title="Gain (dB)", color="#2ca02c", showgrid=TRUE,
                 gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#2ca02c")),
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text=paste0("Gain Nose \u2014 MXG per load point vs ", xl),
                 font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=20, t=40, b=50)) %>%
    plotly::config(editable = TRUE, edits = list(annotationPosition = TRUE))
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

  # Compute per-split-value freq_optima for Freq tab / Spider / Tables.
  # Returns list of list(sv_lbl, fo) — sv_lbl is NULL when no secondary split.
  # When sv = "freq_ghz" / "dataset_tag" / absent from df, treats df as one slice.
  .freq_optima_sv <- function(df, sv, bo_db = 6) {
    .single <- function(lbl = NULL) {
      fo <- .freq_optima(df, bo_db)
      if (is.null(fo) || nrow(fo) == 0L) NULL else list(list(sv_lbl = lbl, fo = fo))
    }
    if (sv %in% c("freq_ghz", "dataset_tag") || !sv %in% names(df)) return(.single())
    sv_vals <- .split_vals(df, sv)
    if (length(sv_vals) <= 1L)
      return(.single(if (length(sv_vals) == 1L) .split_lbl(sv_vals, sv) else NULL))
    result <- Filter(Negate(is.null), lapply(sv_vals, function(v) {
      sl <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == v, , drop = FALSE]
      if (nrow(sl) == 0L) return(NULL)
      fo <- .freq_optima(sl, bo_db)
      if (is.null(fo) || nrow(fo) == 0L) return(NULL)
      list(sv_lbl = .split_lbl(v, sv), fo = fo)
    }))
    if (length(result) == 0L) NULL else result
  }

  # ── Tabular: Reference format — one row per (dataset, freq) ─────────────
  output$lp_table_optima <- DT::renderDT({
    sel_ids <- input$lp_table_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(DT::datatable(data.frame()))
    bo_db   <- as.numeric(input$lp_ppeak_backoff %||% 6)
    sv      <- .eff_split("table")
    fmt1 <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.1f", x))
    fmt2 <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.2f", x))
    all_rows <- list()
    for (id in sel_ids) {
      df <- .get_df(id)
      if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm   <- .short_name(r$filename %||% id, 22L)
      sv_list <- .freq_optima_sv(df, sv, bo_db = bo_db)
      if (is.null(sv_list) || length(sv_list) == 0) next
      fmt_z   <- function(r, x) ifelse(is.na(r)|is.na(x), NA_character_, sprintf("%.1f%+.1fj", r, x))
      for (si in seq_along(sv_list)) {
        fo     <- sv_list[[si]]$fo
        sv_lbl <- sv_list[[si]]$sv_lbl
        nm     <- if (!is.null(sv_lbl)) paste0(ds_nm, " [", sv_lbl, "]") else ds_nm
        fo     <- fo[order(fo$freq_ghz, na.last = NA), ]
        for (i in seq_len(nrow(fo))) {
          row <- fo[i, ]
          all_rows[[length(all_rows) + 1L]] <- data.frame(
            Dataset  = nm,
          Freq_GHz = round(row$freq_ghz, 4),
          # @ Peak Pout (MXP)
          MXP.Pout = fmt1(row$mxp_dbm),
          MXP.Gain = fmt2(row$gain_mxp),
          MXP.PAE  = fmt1(row$pae_mxp),
          MXP.DE   = fmt1(row$de_mxp),
          MXP.ZL   = fmt_z(row$zl_r_mxp, row$zl_x_mxp),
          MXP.ZS   = fmt_z(row$zs_r_mxp, row$zs_x_mxp),
          # @ Peak Eff (MXE)
          MXE.Pout = fmt1(row$pout_mxe),
          MXE.Gain = fmt2(row$gain_mxe),
          MXE.PAE  = fmt1(row$mxe_pae),
          MXE.DE   = fmt1(row$mxe_de),
          MXE.ZL   = fmt_z(row$zl_r_mxe, row$zl_x_mxe),
          MXE.ZS   = fmt_z(row$zs_r_mxe, row$zs_x_mxe),
          # @ P1dB
          P1dB.Pout = fmt1(row$pout_p1db),
          P1dB.Gain = fmt2(row$gain_p1db),
          P1dB.PAE  = fmt1(row$pae_p1db),
          P1dB.DE   = fmt1(row$de_p1db),
          P1dB.ZL   = fmt_z(row$zl_r_p1db, row$zl_x_p1db),
          P1dB.ZS   = fmt_z(row$zs_r_p1db, row$zs_x_p1db),
          # @ Pavg
          Pavg.Pout = fmt1(row$pout_pavg),
          Pavg.Gain = fmt2(row$gain_pavg),
          Pavg.PAE  = fmt1(row$pae_pavg),
          Pavg.DE   = fmt1(row$de_pavg),
          Pavg.ZL   = fmt_z(row$zl_r_pavg, row$zl_x_pavg),
          Pavg.ZS   = fmt_z(row$zs_r_pavg, row$zs_x_pavg),
          stringsAsFactors = FALSE
          )
        }
      }
    }
    if (length(all_rows) == 0) return(DT::datatable(data.frame()))
    out <- do.call(rbind, all_rows)
    # Grouped header using DT container — 6 cols per operating point
    bsep <- "border-left:2px solid #444; text-align:center;"
    sub_h <- c("Pout","Gain","PAE%","DE%","ZL(\u03a9)","ZS(\u03a9)")
    sketch <- htmltools::withTags(table(
      class = "display",
      thead(
        tr(
          th(rowspan = 2, "Dataset"),
          th(rowspan = 2, "Freq\n(GHz)"),
          th(colspan = 6, style = bsep, "@\u202fPeak Pout (MXP)"),
          th(colspan = 6, style = bsep, "@\u202fPeak Eff (MXE)"),
          th(colspan = 6, style = bsep, "@\u202fP1dB"),
          th(colspan = 6, style = bsep, paste0("@\u202fPavg (\u2212", bo_db, "\u202fdB)"))
        ),
        tr(lapply(rep(sub_h, 4), th))
      )
    ))
    DT::datatable(out, container = sketch, rownames = FALSE,
      options = list(dom = "lftip", scrollX = TRUE, pageLength = 20,
        columnDefs = list(
          list(className = "dt-right", targets = seq(1L, ncol(out) - 1L)),
          list(className = "dt-left",  targets = c(6L,7L, 12L,13L, 18L,19L, 24L,25L)))),
      class = "compact cell-border")
  }, server = FALSE)

  # ── Tabular: Ppeak (max Pout) per frequency ───────────────────────────────
  output$lp_table_ppeak <- DT::renderDT({
    sel_ids <- input$lp_table_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(data.frame())
    sv      <- .eff_split("table")
    all_rows <- list()
    for (id in sel_ids) {
      df <- .get_df(id)
      if (is.null(df) || !"pout_dbm" %in% names(df)) next
      ds_nm <- { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 25L) }
      rows <- list()
      if (sv == "freq_ghz" || !sv %in% names(df)) {
        for (grp in .by_freq(df)) {
          gdf <- grp$df
          bi  <- which.max(gdf$pout_dbm)
          if (length(bi) == 0) next
          rec <- .perf_row_at(gdf, bi)
          if (is.null(rec)) next
          rec$Freq_GHz <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
          rec$Dataset  <- ds_nm
          rows[[length(rows) + 1]] <- rec
        }
      } else {
        for (v in .split_vals(df, sv)) {
          sv_df <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == v, , drop=FALSE]
          if (nrow(sv_df) == 0) next
          row_nm <- paste0(ds_nm, " [", .split_lbl(v, sv), "]")
          for (grp in .by_freq(sv_df)) {
            gdf <- grp$df
            bi  <- which.max(gdf$pout_dbm)
            if (length(bi) == 0) next
            rec <- .perf_row_at(gdf, bi)
            if (is.null(rec)) next
            rec$Freq_GHz <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
            rec$Dataset  <- row_nm
            rows[[length(rows) + 1]] <- rec
          }
        }
      }
      if (length(rows) > 0) all_rows <- c(all_rows, rows)
    }
    if (length(all_rows) == 0) return(data.frame())
    do.call(rbind, all_rows)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 20),
     class = "compact cell-border", rownames = FALSE)

  # ── Tabular: Pavg (Ppeak − N dB back-off) per frequency ──────────────────
  output$lp_table_pavg <- DT::renderDT({
    sel_ids <- input$lp_table_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(data.frame())
    bo      <- as.numeric(input$lp_ppeak_backoff %||% 6)
    sv      <- .eff_split("table")
    all_rows <- list()
    for (id in sel_ids) {
      df <- .get_df(id)
      if (is.null(df) || !"pout_dbm" %in% names(df)) next
      ds_nm <- { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 25L) }
      rows <- list()
      if (sv == "freq_ghz" || !sv %in% names(df)) {
        for (grp in .by_freq(df)) {
          gdf    <- grp$df
          max_po <- max(gdf$pout_dbm, na.rm = TRUE)
          bi     <- which.min(abs(gdf$pout_dbm - (max_po - bo)))
          if (length(bi) == 0) next
          rec <- .perf_row_at(gdf, bi)
          if (is.null(rec)) next
          rec$Freq_GHz   <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
          rec$Backoff_dB <- round(bo, 1)
          rec$Dataset    <- ds_nm
          rows[[length(rows) + 1]] <- rec
        }
      } else {
        for (v in .split_vals(df, sv)) {
          sv_df <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == v, , drop=FALSE]
          if (nrow(sv_df) == 0) next
          row_nm <- paste0(ds_nm, " [", .split_lbl(v, sv), "]")
          for (grp in .by_freq(sv_df)) {
            gdf    <- grp$df
            max_po <- max(gdf$pout_dbm, na.rm = TRUE)
            bi     <- which.min(abs(gdf$pout_dbm - (max_po - bo)))
            if (length(bi) == 0) next
            rec <- .perf_row_at(gdf, bi)
            if (is.null(rec)) next
            rec$Freq_GHz   <- if (is.na(grp$freq)) NA_real_ else round(grp$freq, 4)
            rec$Backoff_dB <- round(bo, 1)
            rec$Dataset    <- row_nm
            rows[[length(rows) + 1]] <- rec
          }
        }
      }
      if (length(rows) > 0) all_rows <- c(all_rows, rows)
    }
    if (length(all_rows) == 0) return(data.frame())
    do.call(rbind, all_rows)
  }, options = list(dom = "t", scrollX = TRUE, pageLength = 20),
     class = "compact cell-border", rownames = FALSE)

  # ── Tabular: Selected design load point ───────────────────────────────────
  output$lp_table_selected_zl <- DT::renderDT({
    sel_ids <- input$lp_table_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(data.frame())
    basis   <- input$lp_zl_basis %||% "MXE"
    z0      <- as.numeric(input$lp_zl_z0 %||% 50)
    sv      <- .eff_split("table")
    all_rows <- list()
    for (id in sel_ids) {
      df <- .get_df(id)
      if (is.null(df)) next
      ds_nm <- { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 25L) }
      rows <- list()
      if (sv == "freq_ghz" || !sv %in% names(df)) {
        for (grp in .by_freq(df)) {
          gdf  <- grp$df
          freq <- grp$freq
          if (basis == "custom") {
            gr_c <- as.numeric(input$lp_zl_gamma_r %||% 0)
            gi_c <- as.numeric(input$lp_zl_gamma_i %||% 0)
            zl   <- .gamma_to_z(gr_c, gi_c, z0)
            rec  <- data.frame(
              Dataset  = ds_nm,
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
            rec$Dataset  <- ds_nm
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
      } else {
        for (v in .split_vals(df, sv)) {
          sv_df <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == v, , drop=FALSE]
          if (nrow(sv_df) == 0) next
          row_nm <- paste0(ds_nm, " [", .split_lbl(v, sv), "]")
          for (grp in .by_freq(sv_df)) {
            gdf  <- grp$df
            freq <- grp$freq
            if (basis == "custom") {
              gr_c <- as.numeric(input$lp_zl_gamma_r %||% 0)
              gi_c <- as.numeric(input$lp_zl_gamma_i %||% 0)
              zl   <- .gamma_to_z(gr_c, gi_c, z0)
              rec  <- data.frame(
                Dataset  = row_nm,
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
              rec$Dataset  <- row_nm
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
        }
      }
      if (length(rows) > 0) all_rows <- c(all_rows, rows)
    }
    if (length(all_rows) == 0) return(data.frame())
    out  <- do.call(rbind, all_rows)
    keep <- intersect(c("Dataset","Freq_GHz","Basis","Pout_dBm","Gain_dB","PAE_pct","DE_pct",
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
      df <- .get_df(input$lp_table_dataset_selector[1L])
      write.csv(if (is.null(df)) data.frame() else df,
                file, row.names = FALSE)
    }
  )

  # ── AM-AM (gain compression) ───────────────────────────────────────────────
  output$lp_amam_plot <- renderPlotly({
    sel_ids <- input$lp_ampm_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) sel_ids <- input$lp_xy_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset", font=list(color="#aaa"))))
    x_var   <- input$lp_ampm_x_var %||% "pout_dbm"
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    MPAL <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv       <- .eff_split("ampm")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    col_off <- 0L
    shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_nm  <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      df <- .get_df(id, cols = unique(c("pin_dbm","pout_dbm","pout_w","gain_db","gl_r","gl_i", sv)))
      if (is.null(df) || !"gain_db" %in% names(df)) { col_off <- col_off + 3L; next }
      if (!x_var %in% names(df)) { col_off <- col_off + 3L; next }
      splits  <- .split_vals(df, sv)
      multi_f <- length(splits) > 1L
      if (multi_f) {
        for (fi in seq_along(splits)) {
          sv_val <- splits[fi]
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
          if (!x_var %in% names(dff)) next
          xv_all <- dff[[x_var]]; yv_raw <- dff$gain_db
          ok_all <- !is.na(xv_all) & !is.na(yv_raw)
          if (!any(ok_all)) next
          g_lin  <- max(yv_raw[ok_all][seq_len(min(5L, sum(ok_all)))], na.rm=TRUE)
          dff$gain_compr <- dff$gain_db - g_lin
          lns <- .lp_lines_by_load(dff, x_var, "gain_compr")
          sv_sfx <- sprintf(" %s", .split_lbl(sv_val, sv))
          lbl    <- if (multi_ds) .trunc_lbl(sprintf("AM-AM%s [%s]", sv_sfx, ds_nm))
                    else .trunc_lbl(sprintf("AM-AM%s", sv_sfx))
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns$x, y=lns$y, name=lbl, opacity=0.85,
            line=list(color=col, width=1.5),
            marker=list(color=col, size=4, opacity=0.65))
          # P1dB: use sorted-full data for detection
          xv <- xv_all[ok_all]; yv <- yv_raw[ok_all] - g_lin
          ci <- which(yv <= -1)
          if (length(ci) > 0) {
            ci1  <- ci[1L]
            plbl <- if (multi_ds) .trunc_lbl(sprintf("P1dB%s [%s]", sv_sfx, ds_nm))
                    else .trunc_lbl(sprintf("P1dB%s", sv_sfx))
            p <- p %>% add_trace(type="scatter", mode="markers+text",
              x=xv[ci1], y=yv[ci1],
              text=sprintf("P1dB\n%.1f dBm", xv[ci1]), textposition="top right",
              textfont=list(color=col, size=9),
              marker=list(color=col, size=12, symbol="circle",
                          line=list(color="white", width=2)),
              name=plbl, showlegend=TRUE)
          }
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        xv_all <- df[[x_var]]; yv_raw <- df$gain_db
        ok_all <- !is.na(xv_all) & !is.na(yv_raw)
        g_lin  <- max(yv_raw[ok_all][seq_len(min(5L, sum(ok_all)))], na.rm=TRUE)
        df$gain_compr <- df$gain_db - g_lin
        lns <- .lp_lines_by_load(df, x_var, "gain_compr")
        lbl <- if (multi_ds) paste0("AM-AM [", ds_nm, "]") else "AM-AM compression (dB)"
        p <- p %>% add_trace(type="scattergl", mode="lines+markers",
          x=lns$x, y=lns$y, name=lbl, opacity=0.85,
          line=list(color=col, width=1.5),
          marker=list(color=col, size=4, opacity=0.65))
        xv <- xv_all[ok_all]; yv <- yv_raw[ok_all] - g_lin
        ci <- which(yv <= -1)
        if (length(ci) > 0) {
          ci1  <- ci[1L]
          plbl <- if (multi_ds) paste0("P1dB [", ds_nm, "]") else "P1dB"
          p    <- p %>% add_trace(type="scatter", mode="markers+text",
            x=xv[ci1], y=yv[ci1],
            text=sprintf("P1dB\n%.1f dBm", xv[ci1]), textposition="top right",
            textfont=list(color=col, size=10),
            marker=list(color=col, size=12, symbol="circle",
                        line=list(color="white", width=2)),
            name=plbl, showlegend=TRUE)
        }
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    # ── Pavg back-off reference line ─────────────────────────────────────────
    if (x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && length(sel_ids) > 0) {
      df0 <- .get_df(sel_ids[1L], cols = "pout_dbm")
      if (!is.null(df0) && "pout_dbm" %in% names(df0)) {
        pmax <- max(df0$pout_dbm, na.rm = TRUE)
        if (is.finite(pmax)) {
          shapes_list <- c(shapes_list, list(list(
            type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
            line=list(color="rgba(255,255,255,0.4)", width=1.5, dash="dot"))))
        }
      }
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-AM compression (dB)", color="#aaa",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      legend = list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-AM vs ", xl), font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=30, t=40, b=50))
  })

  # ── AM-PM (phase distortion in degrees) ──────────────────────────────────
  output$lp_ampm_plot <- renderPlotly({
    sel_ids <- input$lp_ampm_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) sel_ids <- input$lp_xy_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset", font=list(color="#aaa"))))
    x_var   <- input$lp_ampm_x_var %||% "pout_dbm"
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    MPAL <- c("#1f77b4","#2ca02c","#d62728","#9467bd","#8c564b",
              "#e377c2","#17becf","#bcbd22","#7f7f7f","#ff7f11")
    sv       <- .eff_split("ampm")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    col_off <- 0L
    shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_nm  <- if (multi_ds) { r <- isolate(lp_datasets()[[id]]); .short_name(r$filename %||% id, 18L) } else ""
      df <- .get_df(id, cols = unique(c("pin_dbm","pout_dbm","pout_w","am_pm","gain_db","gl_r","gl_i", sv)))
      if (is.null(df) || !"am_pm" %in% names(df) || all(is.na(df$am_pm))) { col_off <- col_off + 3L; next }
      if (!x_var %in% names(df)) { col_off <- col_off + 3L; next }
      splits  <- .split_vals(df, sv)
      multi_f <- length(splits) > 1L
      if (multi_f) {
        for (fi in seq_along(splits)) {
          sv_val <- splits[fi]
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          dff <- df[!is.na(df[[sv]]) & as.character(df[[sv]]) == sv_val, , drop=FALSE]
          if (!x_var %in% names(dff) || !"am_pm" %in% names(dff)) next
          lns <- .lp_lines_by_load(dff, x_var, "am_pm")
          if (all(is.na(lns$y))) next
          sv_sfx <- sprintf(" %s", .split_lbl(sv_val, sv))
          lbl   <- if (multi_ds) .trunc_lbl(sprintf("AM-PM%s [%s]", sv_sfx, ds_nm))
                   else .trunc_lbl(sprintf("AM-PM%s", sv_sfx))
          p <- p %>% add_trace(type="scattergl", mode="lines+markers",
            x=lns$x, y=lns$y, name=lbl, opacity=0.85,
            line=list(color=col, width=1.5),
            marker=list(color=col, size=4, opacity=0.60))
          # P1dB marker from gain compression (use sorted data for detection)
          if ("gain_db" %in% names(dff)) {
            ord_det <- order(dff[[x_var]], na.last=NA)
            xv_det  <- dff[[x_var]][ord_det]
            gv_raw  <- dff$gain_db[ord_det]
            yv_det  <- dff$am_pm[ord_det]
            gok <- !is.na(xv_det) & !is.na(gv_raw) & !is.na(yv_det)
            if (any(gok)) {
              g_lin <- max(gv_raw[gok][seq_len(min(5L, sum(gok)))], na.rm=TRUE)
              ci <- which((gv_raw[gok] - g_lin) <= -1)
              if (length(ci) > 0) {
                ci1 <- ci[1L]
                plbl <- if (multi_ds) .trunc_lbl(sprintf("P1dB%s [%s]", sv_sfx, ds_nm))
                        else .trunc_lbl(sprintf("P1dB%s", sv_sfx))
                xv_gok <- xv_det[gok]; yv_gok <- yv_det[gok]
                p <- p %>% add_trace(type="scatter", mode="markers+text",
                  x=xv_gok[ci1], y=yv_gok[ci1],
                  text=sprintf("P1dB\n%.1f dBm", xv_gok[ci1]), textposition="top right",
                  textfont=list(color=col, size=9),
                  marker=list(color=col, size=12, symbol="circle",
                              line=list(color="white", width=2)),
                  name=plbl, showlegend=TRUE)
              }
            }
          }
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        lns <- .lp_lines_by_load(df, x_var, "am_pm")
        lbl <- if (multi_ds) paste0("AM-PM [", ds_nm, "]") else "AM-PM (\u00b0)"
        p <- p %>% add_trace(type="scattergl", mode="lines+markers",
          x=lns$x, y=lns$y, name=lbl, opacity=0.85,
          line=list(color=col, width=1.5),
          marker=list(color=col, size=4, opacity=0.60))
        # P1dB marker from gain compression (use sorted data for detection)
        if ("gain_db" %in% names(df)) {
          ord_det <- order(df[[x_var]], na.last=NA)
          xv_det  <- df[[x_var]][ord_det]
          gv_raw  <- df$gain_db[ord_det]
          yv_det  <- df$am_pm[ord_det]
          gok <- !is.na(xv_det) & !is.na(gv_raw) & !is.na(yv_det)
          if (any(gok)) {
            g_lin <- max(gv_raw[gok][seq_len(min(5L, sum(gok)))], na.rm=TRUE)
            ci <- which((gv_raw[gok] - g_lin) <= -1)
            if (length(ci) > 0) {
              ci1 <- ci[1L]
              plbl <- if (multi_ds) paste0("P1dB [", ds_nm, "]") else "P1dB"
              xv_gok <- xv_det[gok]; yv_gok <- yv_det[gok]
              p <- p %>% add_trace(type="scatter", mode="markers+text",
                x=xv_gok[ci1], y=yv_gok[ci1],
                text=sprintf("P1dB\n%.1f dBm", xv_gok[ci1]), textposition="top right",
                textfont=list(color=col, size=10),
                marker=list(color=col, size=12, symbol="circle",
                            line=list(color="white", width=2)),
                name=plbl, showlegend=TRUE)
            }
          }
        }
      }
      col_off <- col_off + max(length(splits), 1L)
    }
    # ── Pavg back-off reference line ─────────────────────────────────────────
    if (x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && length(sel_ids) > 0) {
      df0 <- .get_df(sel_ids[1L], cols = "pout_dbm")
      if (!is.null(df0) && "pout_dbm" %in% names(df0)) {
        pmax <- max(df0$pout_dbm, na.rm = TRUE)
        if (is.finite(pmax)) {
          shapes_list <- c(shapes_list, list(list(
            type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
            line=list(color="rgba(255,255,255,0.4)", width=1.5, dash="dot"))))
        }
      }
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-PM (\u00b0)", color="#1f77b4",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color="#1f77b4")),
      legend = list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-PM vs ", xl), font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=30, t=40, b=50))
  })

  # ── Report: Select All sections ────────────────────────────────────────────
  observeEvent(input$lp_rpt_select_all, {
    all_choices <- c("smith","xy","nose","perf","ampm","table","meta")
    updateCheckboxGroupInput(session, "lp_rpt_sections", selected = all_choices)
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

  # ═══════════════════════════════════════════════════════════════════════════
  # FREQUENCY TAB – performance metrics vs frequency
  # ═══════════════════════════════════════════════════════════════════════════

  .make_selector("lp_freq_dataset_selector",   "Dataset(s)")
  .make_selector("lp_spider_dataset_selector", "Dataset(s)")

  # Helper: aggregate per-frequency optima for one dataset df
  # bo_db: back-off in dB from MXP to define Pavg operating point
  .freq_optima <- function(df, bo_db = 6) {
    rows <- list()
    for (grp in .by_freq(df)) {
      freq <- grp$freq; gdf <- grp$df
      opt  <- .find_optima(gdf)
      bi_p <- opt$MXP; bi_e <- opt$MXE; bi_g <- opt$MXG
      # P1dB: first row where gain has compressed >= 1 dB
      bi_p1 <- NA_integer_
      if ("gain_db" %in% names(gdf)) {
        x_col <- if ("pin_dbm" %in% names(gdf)) "pin_dbm" else NULL
        ord_g <- if (!is.null(x_col)) order(gdf[[x_col]], na.last=NA) else seq_len(nrow(gdf))
        g_s   <- gdf$gain_db[ord_g]
        g_lin <- suppressWarnings(max(g_s[seq_len(min(5L,length(g_s)))], na.rm=TRUE))
        ci    <- which((g_lin - g_s) >= 1)
        if (length(ci) > 0) bi_p1 <- ord_g[ci[1L]]
      }
      # Pavg point: row closest to Pout = Pout_MXP - bo_db
      bi_pav <- NA_integer_
      if (!is.na(bi_p) && "pout_dbm" %in% names(gdf) && is.finite(bo_db) && bo_db > 0) {
        pav_tgt <- gdf$pout_dbm[bi_p] - bo_db
        diffs   <- abs(gdf$pout_dbm - pav_tgt)
        idx     <- which.min(diffs)
        if (length(idx) > 0 && is.finite(diffs[idx])) bi_pav <- idx
      }
      rows[[length(rows)+1L]] <- list(
        freq_ghz   = if (is.na(freq)) NA_real_ else freq,
        # MXP / MXE / MXG metrics
        mxp_dbm    = if (!is.na(bi_p)   && "pout_dbm"%in%names(gdf)) gdf$pout_dbm[bi_p]  else NA_real_,
        mxe_pae    = if (!is.na(bi_e)   && "pae_pct" %in%names(gdf)) gdf$pae_pct[bi_e]   else NA_real_,
        mxe_de     = if (!is.na(bi_e)   && "de_pct"  %in%names(gdf)) gdf$de_pct[bi_e]    else NA_real_,
        mxg_gain   = if (!is.na(bi_g)   && "gain_db" %in%names(gdf)) gdf$gain_db[bi_g]   else NA_real_,
        gain_mxe   = if (!is.na(bi_e)   && "gain_db" %in%names(gdf)) gdf$gain_db[bi_e]   else NA_real_,
        ampm_mxp   = if (!is.na(bi_p)   && "am_pm"   %in%names(gdf)) gdf$am_pm[bi_p]     else NA_real_,
        ampm_mxe   = if (!is.na(bi_e)   && "am_pm"   %in%names(gdf)) gdf$am_pm[bi_e]     else NA_real_,
        # Additional per-operating-point metrics (MXP/MXE/MXG cross-columns)
        gain_mxp   = if (!is.na(bi_p)   && "gain_db" %in%names(gdf)) gdf$gain_db[bi_p]   else NA_real_,
        pae_mxp    = if (!is.na(bi_p)   && "pae_pct" %in%names(gdf)) gdf$pae_pct[bi_p]   else NA_real_,
        de_mxp     = if (!is.na(bi_p)   && "de_pct"  %in%names(gdf)) gdf$de_pct[bi_p]    else NA_real_,
        pout_mxe   = if (!is.na(bi_e)   && "pout_dbm"%in%names(gdf)) gdf$pout_dbm[bi_e]  else NA_real_,
        pout_mxg   = if (!is.na(bi_g)   && "pout_dbm"%in%names(gdf)) gdf$pout_dbm[bi_g]  else NA_real_,
        pae_mxg    = if (!is.na(bi_g)   && "pae_pct" %in%names(gdf)) gdf$pae_pct[bi_g]   else NA_real_,
        de_mxg     = if (!is.na(bi_g)   && "de_pct"  %in%names(gdf)) gdf$de_pct[bi_g]    else NA_real_,
        ampm_mxg   = if (!is.na(bi_g)   && "am_pm"   %in%names(gdf)) gdf$am_pm[bi_g]     else NA_real_,
        # P1dB metrics (input-referred index)
        p1db_dbm   = if (!is.na(bi_p1)  && "pin_dbm" %in%names(gdf)) gdf$pin_dbm[bi_p1]  else NA_real_,
        pout_p1db  = if (!is.na(bi_p1)  && "pout_dbm"%in%names(gdf)) gdf$pout_dbm[bi_p1] else NA_real_,
        gain_p1db  = if (!is.na(bi_p1)  && "gain_db" %in%names(gdf)) gdf$gain_db[bi_p1]  else NA_real_,
        pae_p1db   = if (!is.na(bi_p1)  && "pae_pct" %in%names(gdf)) gdf$pae_pct[bi_p1]  else NA_real_,
        de_p1db    = if (!is.na(bi_p1)  && "de_pct"  %in%names(gdf)) gdf$de_pct[bi_p1]   else NA_real_,
        ampm_p1db  = if (!is.na(bi_p1)  && "am_pm"   %in%names(gdf)) gdf$am_pm[bi_p1]    else NA_real_,
        # Pavg (back-off) metrics
        pout_pavg  = if (!is.na(bi_pav) && "pout_dbm"%in%names(gdf)) gdf$pout_dbm[bi_pav] else NA_real_,
        gain_pavg  = if (!is.na(bi_pav) && "gain_db" %in%names(gdf)) gdf$gain_db[bi_pav] else NA_real_,
        pae_pavg   = if (!is.na(bi_pav) && "pae_pct" %in%names(gdf)) gdf$pae_pct[bi_pav] else NA_real_,
        de_pavg    = if (!is.na(bi_pav) && "de_pct"  %in%names(gdf)) gdf$de_pct[bi_pav]  else NA_real_,
        ampm_pavg  = if (!is.na(bi_pav) && "am_pm"   %in%names(gdf)) gdf$am_pm[bi_pav]   else NA_real_,
        # Impedances at MXE
        zl_r_mxe   = if (!is.na(bi_e) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_e], gdf$gl_i[bi_e]); z$r } else NA_real_,
        zl_x_mxe   = if (!is.na(bi_e) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_e], gdf$gl_i[bi_e]); z$x } else NA_real_,
        zs_r_mxe   = if (!is.na(bi_e) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_e], gdf$gs_i[bi_e]); z$r } else NA_real_,
        zs_x_mxe   = if (!is.na(bi_e) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_e], gdf$gs_i[bi_e]); z$x } else NA_real_,
        # Impedances at MXP
        zl_r_mxp   = if (!is.na(bi_p) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_p], gdf$gl_i[bi_p]); z$r } else NA_real_,
        zl_x_mxp   = if (!is.na(bi_p) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_p], gdf$gl_i[bi_p]); z$x } else NA_real_,
        zs_r_mxp   = if (!is.na(bi_p) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_p], gdf$gs_i[bi_p]); z$r } else NA_real_,
        zs_x_mxp   = if (!is.na(bi_p) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_p], gdf$gs_i[bi_p]); z$x } else NA_real_,
        # Impedances at MXG
        zl_r_mxg   = if (!is.na(bi_g) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_g], gdf$gl_i[bi_g]); z$r } else NA_real_,
        zl_x_mxg   = if (!is.na(bi_g) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_g], gdf$gl_i[bi_g]); z$x } else NA_real_,
        zs_r_mxg   = if (!is.na(bi_g) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_g], gdf$gs_i[bi_g]); z$r } else NA_real_,
        zs_x_mxg   = if (!is.na(bi_g) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_g], gdf$gs_i[bi_g]); z$x } else NA_real_,
        # Impedances at P1dB
        zl_r_p1db  = if (!is.na(bi_p1) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_p1], gdf$gl_i[bi_p1]); z$r } else NA_real_,
        zl_x_p1db  = if (!is.na(bi_p1) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_p1], gdf$gl_i[bi_p1]); z$x } else NA_real_,
        zs_r_p1db  = if (!is.na(bi_p1) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_p1], gdf$gs_i[bi_p1]); z$r } else NA_real_,
        zs_x_p1db  = if (!is.na(bi_p1) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_p1], gdf$gs_i[bi_p1]); z$x } else NA_real_,
        # Impedances at Pavg
        zl_r_pavg  = if (!is.na(bi_pav) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_pav], gdf$gl_i[bi_pav]); z$r } else NA_real_,
        zl_x_pavg  = if (!is.na(bi_pav) && all(c("gl_r","gl_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gl_r[bi_pav], gdf$gl_i[bi_pav]); z$x } else NA_real_,
        zs_r_pavg  = if (!is.na(bi_pav) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_pav], gdf$gs_i[bi_pav]); z$r } else NA_real_,
        zs_x_pavg  = if (!is.na(bi_pav) && all(c("gs_r","gs_i")%in%names(gdf))) {
                       z <- .gamma_to_z(gdf$gs_r[bi_pav], gdf$gs_i[bi_pav]); z$x } else NA_real_
      )
    }
    if (length(rows) == 0) return(NULL)
    do.call(rbind, lapply(rows, as.data.frame))
  }

  # Dark-theme helper used repeatedly in frequency plots
  .freq_layout <- function(p, title_txt, xl, y1l, y2l=NULL, pal="#ff7f11") {
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      title  = list(text=title_txt, font=list(color="#eee", size=13)),
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title=y1l, color=pal,  showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color=pal)),
      yaxis2 = if (!is.null(y2l)) list(title=y2l, color="#1f77b4", overlaying="y",
                    side="right", showgrid=FALSE, zeroline=FALSE,
                    tickfont=list(color="#1f77b4")) else NULL,
      legend = list(orientation="h", x=0.5, xanchor="center", y=-0.28,
                    font=list(color="#aaa", size=10), bgcolor="rgba(0,0,0,0.15)"),
      font   = list(color="#aaa"),
      margin = list(l=60, r=if(!is.null(y2l)) 65 else 20, t=40, b=95))
  }

  # ── Frequency: Power vs frequency plot ────────────────────────────────────
  output$lp_freq_pout_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp) || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe) || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg) || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        col   <- MPAL[(col_off%%length(MPAL))+1L]; col_off <- col_off+1L
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        ok_p  <- !is.na(xv) & !is.na(fo$mxp_dbm)
        if (show_mxp && any(ok_p)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
          x=xv[ok_p], y=fo$mxp_dbm[ok_p], name=paste0("Pout@MXP [",sfx,"]"),
          line=list(color=col,width=2), marker=list(color=col,size=7))
        if (show_mxe) {
          ok_e <- !is.na(xv) & !is.na(fo$pout_mxe)
          if (any(ok_e)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_e], y=fo$pout_mxe[ok_e], name=paste0("Pout@MXE [",sfx,"]"),
            line=list(color=col,width=2,dash="dash"),
            marker=list(color=col,size=7,symbol="diamond"))
        }
        if (show_mxg) {
          ok_g_p <- !is.na(xv) & !is.na(fo$pout_mxg)
          if (any(ok_g_p)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g_p], y=fo$pout_mxg[ok_g_p], name=paste0("Pout@MXG [",sfx,"]"),
            line=list(color=col,width=2,dash="dot"),
            marker=list(color=col,size=7,symbol="square"))
        }
        if (show_p1db) {
          ok1 <- !is.na(xv) & !is.na(fo$p1db_dbm)
          if (any(ok1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok1], y=fo$p1db_dbm[ok1], name=paste0("Pin@P1dB [",sfx,"]"),
            line=list(color=col,width=1.5,dash="dashdot"),
            marker=list(color=col,size=6,symbol="diamond-open"))
        }
        if (show_pavg && any(ok_p)) {
          pav <- fo$mxp_dbm - bo_db
          p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_p], y=pav[ok_p], name=paste0("Pavg [",sfx,"]"),
            line=list(color=col,width=1.5,dash="longdash"),
            marker=list(color=col,size=5,symbol="circle-open"))
        }
      }
    }
    .freq_layout(p, "Power vs Frequency", "Frequency (GHz)", "Power (dBm)", pal="#ff7f11")
  })

  # ── Frequency: Efficiency vs frequency plot ────────────────────────────────
  output$lp_freq_eff_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp) || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe) || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg) || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#1f77b4","#2ca02c","#d62728","#9467bd","#8c564b",
              "#e377c2","#17becf","#bcbd22","#7f7f7f","#ff7f11")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        col1  <- MPAL[(col_off    %%length(MPAL))+1L]
        col2  <- MPAL[((col_off+1)%%length(MPAL))+1L]
        col_off <- col_off + 2L
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        # PAE/DE at MXE (peak efficiency) — solid lines
        if (show_mxe) {
          ok_e <- !is.na(xv) & !is.na(fo$mxe_pae)
          ok_d <- !is.na(xv) & !is.na(fo$mxe_de)
          if (any(ok_e)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_e], y=fo$mxe_pae[ok_e], name=paste0("PAE@MXE [",sfx,"]"),
            line=list(color=col1,width=2), marker=list(color=col1,size=7))
          if (any(ok_d)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_d], y=fo$mxe_de[ok_d], name=paste0("DE@MXE [",sfx,"]"),
            line=list(color=col2,width=1.5), marker=list(color=col2,size=6,symbol="circle-open"))
        }
        # PAE/DE at MXP (peak power) — dash lines
        if (show_mxp) {
          ok_ep <- !is.na(xv) & !is.na(fo$pae_mxp)
          ok_dp <- !is.na(xv) & !is.na(fo$de_mxp)
          if (any(ok_ep)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_ep], y=fo$pae_mxp[ok_ep], name=paste0("PAE@MXP [",sfx,"]"),
            line=list(color=col1,width=2,dash="dash"),
            marker=list(color=col1,size=7,symbol="triangle-up"))
          if (any(ok_dp)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_dp], y=fo$de_mxp[ok_dp], name=paste0("DE@MXP [",sfx,"]"),
            line=list(color=col2,width=1.5,dash="dash"),
            marker=list(color=col2,size=6,symbol="triangle-up-open"))
        }
        # PAE/DE at MXG (max gain) — dot lines
        if (show_mxg) {
          ok_eg <- !is.na(xv) & !is.na(fo$pae_mxg)
          ok_dg <- !is.na(xv) & !is.na(fo$de_mxg)
          if (any(ok_eg)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_eg], y=fo$pae_mxg[ok_eg], name=paste0("PAE@MXG [",sfx,"]"),
            line=list(color=col1,width=2,dash="dot"),
            marker=list(color=col1,size=7,symbol="square"))
          if (any(ok_dg)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_dg], y=fo$de_mxg[ok_dg], name=paste0("DE@MXG [",sfx,"]"),
            line=list(color=col2,width=1.5,dash="dot"),
            marker=list(color=col2,size=6,symbol="square-open"))
        }
        if (show_p1db) {
          ok_ep1 <- !is.na(xv) & !is.na(fo$pae_p1db)
          ok_dp1 <- !is.na(xv) & !is.na(fo$de_p1db)
          if (any(ok_ep1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_ep1], y=fo$pae_p1db[ok_ep1], name=paste0("PAE@P1dB [",sfx,"]"),
            line=list(color=col1,width=1.5,dash="dashdot"),
            marker=list(color=col1,size=6,symbol="diamond"))
          if (any(ok_dp1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_dp1], y=fo$de_p1db[ok_dp1], name=paste0("DE@P1dB [",sfx,"]"),
            line=list(color=col2,width=1.5,dash="dashdot"),
            marker=list(color=col2,size=5,symbol="diamond-open"))
        }
        if (show_pavg) {
          ok_ev <- !is.na(xv) & !is.na(fo$pae_pavg)
          ok_dv <- !is.na(xv) & !is.na(fo$de_pavg)
          if (any(ok_ev)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_ev], y=fo$pae_pavg[ok_ev], name=paste0("PAE@Pavg [",sfx,"]"),
            line=list(color=col1,width=1.5,dash="longdash"),
            marker=list(color=col1,size=5,symbol="circle-open"))
          if (any(ok_dv)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_dv], y=fo$de_pavg[ok_dv], name=paste0("DE@Pavg [",sfx,"]"),
            line=list(color=col2,width=1.5,dash="longdash"),
            marker=list(color=col2,size=4,symbol="square-open"))
        }
      }
    }
    .freq_layout(p, "Efficiency vs Frequency", "Frequency (GHz)", "Efficiency (%)", pal="#1f77b4")
  })

  # ── Frequency: Gain vs frequency plot ─────────────────────────────────────
  output$lp_freq_gain_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp) || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe) || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg) || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#2ca02c","#ff7f11","#1f77b4","#d62728","#9467bd",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        col   <- MPAL[(col_off%%length(MPAL))+1L]; col_off <- col_off+1L
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        # Gain at MXG — solid
        if (show_mxg) {
          ok_g <- !is.na(xv) & !is.na(fo$mxg_gain)
          if (any(ok_g)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g], y=fo$mxg_gain[ok_g], name=paste0("Gain@MXG [",sfx,"]"),
            line=list(color=col,width=2), marker=list(color=col,size=7,symbol="square"))
        }
        # Gain at MXE — dash
        if (show_mxe) {
          ok_ge <- !is.na(xv) & !is.na(fo$gain_mxe)
          if (any(ok_ge)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_ge], y=fo$gain_mxe[ok_ge], name=paste0("Gain@MXE [",sfx,"]"),
            line=list(color=col,width=2,dash="dash"),
            marker=list(color=col,size=7,symbol="diamond"))
        }
        # Gain at MXP — dot
        if (show_mxp) {
          ok_gp <- !is.na(xv) & !is.na(fo$gain_mxp)
          if (any(ok_gp)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_gp], y=fo$gain_mxp[ok_gp], name=paste0("Gain@MXP [",sfx,"]"),
            line=list(color=col,width=2,dash="dot"),
            marker=list(color=col,size=7,symbol="circle"))
        }
        if (show_p1db) {
          ok_g1 <- !is.na(xv) & !is.na(fo$gain_p1db)
          if (any(ok_g1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g1], y=fo$gain_p1db[ok_g1], name=paste0("Gain@P1dB [",sfx,"]"),
            line=list(color=col,width=1.5,dash="dashdot"),
            marker=list(color=col,size=6,symbol="diamond-open"))
        }
        if (show_pavg) {
          ok_gv <- !is.na(xv) & !is.na(fo$gain_pavg)
          if (any(ok_gv)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_gv], y=fo$gain_pavg[ok_gv], name=paste0("Gain@Pavg [",sfx,"]"),
            line=list(color=col,width=1.5,dash="longdash"),
            marker=list(color=col,size=5,symbol="circle-open"))
        }
      }
    }
    .freq_layout(p, "Gain vs Frequency", "Frequency (GHz)", "Gain (dB)", pal="#2ca02c")
  })

  # ── Frequency: AM-AM (gain @ operating points) vs frequency ───────────────
  output$lp_freq_amam_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp) || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe) || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg) || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#e377c2","#ff7f11","#1f77b4","#2ca02c","#d62728",
              "#9467bd","#8c564b","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        col   <- MPAL[(col_off%%length(MPAL))+1L]; col_off <- col_off+1L
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        # Gain at MXE — solid, star
        if (show_mxe) {
          ok_e <- !is.na(xv) & !is.na(fo$gain_mxe)
          if (any(ok_e)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_e], y=fo$gain_mxe[ok_e], name=paste0("Gain@MXE [",sfx,"]"),
            line=list(color=col,width=2), marker=list(color=col,size=7,symbol="star"))
        }
        # Gain at MXP — dash, circle
        if (show_mxp) {
          ok_p <- !is.na(xv) & !is.na(fo$gain_mxp)
          if (any(ok_p)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_p], y=fo$gain_mxp[ok_p], name=paste0("Gain@MXP [",sfx,"]"),
            line=list(color=col,width=2,dash="dash"),
            marker=list(color=col,size=7,symbol="circle"))
        }
        # Gain at MXG — dot, square
        if (show_mxg) {
          ok_g <- !is.na(xv) & !is.na(fo$mxg_gain)
          if (any(ok_g)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g], y=fo$mxg_gain[ok_g], name=paste0("Gain@MXG [",sfx,"]"),
            line=list(color=col,width=2,dash="dot"),
            marker=list(color=col,size=7,symbol="square"))
        }
        if (show_p1db) {
          ok_g1 <- !is.na(xv) & !is.na(fo$gain_p1db)
          if (any(ok_g1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g1], y=fo$gain_p1db[ok_g1], name=paste0("Gain@P1dB [",sfx,"]"),
            line=list(color=col,width=1.5,dash="dashdot"),
            marker=list(color=col,size=6,symbol="diamond"))
        }
        if (show_pavg) {
          ok_gv <- !is.na(xv) & !is.na(fo$gain_pavg)
          if (any(ok_gv)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_gv], y=fo$gain_pavg[ok_gv], name=paste0("Gain@Pavg [",sfx,"]"),
            line=list(color=col,width=1.5,dash="longdash"),
            marker=list(color=col,size=5,symbol="circle-open"))
        }
      }
    }
    .freq_layout(p, "Gain (AM-AM) vs Frequency", "Frequency (GHz)", "Gain (dB)", pal="#e377c2")
  })

  # ── Frequency: AM-PM vs frequency plot ────────────────────────────────────
  output$lp_freq_ampm_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp) || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe) || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg) || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#9467bd","#ff7f11","#1f77b4","#2ca02c","#d62728",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        col   <- MPAL[(col_off%%length(MPAL))+1L]; col_off <- col_off+1L
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        # AM-PM at MXE — solid, star
        if (show_mxe) {
          ok_e <- !is.na(xv) & !is.na(fo$ampm_mxe)
          if (any(ok_e)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_e], y=fo$ampm_mxe[ok_e], name=paste0("AM-PM@MXE [",sfx,"]"),
            line=list(color=col,width=2), marker=list(color=col,size=7,symbol="star"))
        }
        # AM-PM at MXP — dash, circle
        if (show_mxp) {
          ok_p <- !is.na(xv) & !is.na(fo$ampm_mxp)
          if (any(ok_p)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_p], y=fo$ampm_mxp[ok_p], name=paste0("AM-PM@MXP [",sfx,"]"),
            line=list(color=col,width=2,dash="dash"),
            marker=list(color=col,size=7,symbol="circle"))
        }
        # AM-PM at MXG — dot, square
        if (show_mxg) {
          ok_g <- !is.na(xv) & !is.na(fo$ampm_mxg)
          if (any(ok_g)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_g], y=fo$ampm_mxg[ok_g], name=paste0("AM-PM@MXG [",sfx,"]"),
            line=list(color=col,width=2,dash="dot"),
            marker=list(color=col,size=7,symbol="square"))
        }
        if (show_p1db) {
          ok_p1 <- !is.na(xv) & !is.na(fo$ampm_p1db)
          if (any(ok_p1)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_p1], y=fo$ampm_p1db[ok_p1], name=paste0("AM-PM@P1dB [",sfx,"]"),
            line=list(color=col,width=1.5,dash="dashdot"),
            marker=list(color=col,size=6,symbol="diamond"))
        }
        if (show_pavg) {
          ok_pv <- !is.na(xv) & !is.na(fo$ampm_pavg)
          if (any(ok_pv)) p <- p %>% add_trace(type="scatter", mode="lines+markers",
            x=xv[ok_pv], y=fo$ampm_pavg[ok_pv], name=paste0("AM-PM@Pavg [",sfx,"]"),
            line=list(color=col,width=1.5,dash="longdash"),
            marker=list(color=col,size=5,symbol="circle-open"))
        }
      }
    }
    .freq_layout(p, "AM-PM vs Frequency", "Frequency (GHz)", "AM-PM (\u00b0)", pal="#9467bd")
  })

  # ── Frequency: ZL vs frequency plot ───────────────────────────────────────
  .imp_traces <- function(p, fo, xv, pfx, r_col, x_col, ds_nm,
                          show_p1db, show_pavg, show_mxp, show_mxe, show_mxg,
                          MPAL, col_idx) {
    col_mxe  <- MPAL[(col_idx      %% length(MPAL)) + 1L]
    col_mxp  <- MPAL[((col_idx+1L) %% length(MPAL)) + 1L]
    col_mxg  <- MPAL[((col_idx+2L) %% length(MPAL)) + 1L]
    col_p1db <- MPAL[((col_idx+3L) %% length(MPAL)) + 1L]
    .tr <- function(rv, xv2, nm, col, dash="solid", sym="circle") {
      ok <- !is.na(xv2) & !is.na(rv)
      if (!any(ok)) return(p)
      p <<- p %>% add_trace(type="scatter", mode="lines+markers",
        x=xv2[ok], y=rv[ok], name=nm,
        line=list(color=col, width=1.5, dash=dash),
        marker=list(color=col, size=5, symbol=sym, opacity=0.8))
    }
    if (show_mxe) {
      .tr(fo[[paste0(pfx,"r_mxe")]], xv, paste0("MXE Re [",ds_nm,"]"), col_mxe)
      .tr(fo[[paste0(pfx,"x_mxe")]], xv, paste0("MXE Im [",ds_nm,"]"), col_mxe, "dot","circle-open")
    }
    if (show_mxp) {
      .tr(fo[[paste0(pfx,"r_mxp")]], xv, paste0("MXP Re [",ds_nm,"]"), col_mxp)
      .tr(fo[[paste0(pfx,"x_mxp")]], xv, paste0("MXP Im [",ds_nm,"]"), col_mxp, "dot","circle-open")
    }
    if (show_mxg) {
      .tr(fo[[paste0(pfx,"r_mxg")]], xv, paste0("MXG Re [",ds_nm,"]"), col_mxg)
      .tr(fo[[paste0(pfx,"x_mxg")]], xv, paste0("MXG Im [",ds_nm,"]"), col_mxg, "dot","circle-open")
    }
    if (show_p1db) {
      .tr(fo[[paste0(pfx,"r_p1db")]], xv, paste0("P1dB Re [",ds_nm,"]"), col_p1db, "dash","diamond")
      .tr(fo[[paste0(pfx,"x_p1db")]], xv, paste0("P1dB Im [",ds_nm,"]"), col_p1db, "dashdot","diamond-open")
    }
    if (show_pavg) {
      .tr(fo[[paste0(pfx,"r_pavg")]], xv, paste0("Pavg Re [",ds_nm,"]"), col_mxe, "longdash","square")
      .tr(fo[[paste0(pfx,"x_pavg")]], xv, paste0("Pavg Im [",ds_nm,"]"), col_mxe, "longdashdot","square-open")
    }
    p
  }

  output$lp_freq_zl_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp)  || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe)  || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg)  || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#9467bd","#ff7f11","#2ca02c","#d62728","#1f77b4",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        p     <- .imp_traces(p, fo, xv, "zl_", "zl_", "zl_", sfx,
                             show_p1db, show_pavg, show_mxp, show_mxe, show_mxg,
                             MPAL, col_off)
        col_off <- col_off + 4L
      }
    }
    .freq_layout(p, "ZL vs Frequency", "Frequency (GHz)", "ZL (\u03a9)", pal="#9467bd")
  })

  output$lp_freq_zs_plot <- renderPlotly({
    sel_ids   <- input$lp_freq_dataset_selector
    show_p1db <- isTRUE(input$lp_freq_show_p1db)
    show_pavg <- isTRUE(input$lp_freq_show_pavg)
    show_mxp  <- isTRUE(input$lp_freq_show_mxp)  || is.null(input$lp_freq_show_mxp)
    show_mxe  <- isTRUE(input$lp_freq_show_mxe)  || is.null(input$lp_freq_show_mxe)
    show_mxg  <- isTRUE(input$lp_freq_show_mxg)  || is.null(input$lp_freq_show_mxg)
    bo_db     <- as.numeric(input$lp_freq_backoff %||% 6)
    MPAL <- c("#8c564b","#ff7f11","#2ca02c","#d62728","#9467bd",
              "#1f77b4","#e377c2","#17becf","#bcbd22","#7f7f7f")
    sv   <- .eff_split("freq")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                          title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids)||length(sel_ids)==0) return(ep("Select datasets"))
    p <- plot_ly(); col_off <- 0L
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      df    <- .get_df(id); if (is.null(df)) next
      r     <- isolate(lp_datasets()[[id]])
      ds_nm <- .short_name(r$filename %||% id, 15L)
      sv_list <- .freq_optima_sv(df, sv, bo_db=bo_db); if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        fo    <- sv_list[[si]]$fo
        sfx   <- { slbl <- sv_list[[si]]$sv_lbl; if (!is.null(slbl)) paste0(slbl," [",ds_nm,"]") else ds_nm }
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]; xv <- fo$freq_ghz
        p     <- .imp_traces(p, fo, xv, "zs_", "zs_", "zs_", sfx,
                             show_p1db, show_pavg, show_mxp, show_mxe, show_mxg,
                             MPAL, col_off)
        col_off <- col_off + 4L
      }
    }
    .freq_layout(p, "ZS vs Frequency", "Frequency (GHz)", "ZS (\u03a9)", pal="#8c564b")
  })

  # ── Frequency: Spider plot (shared helper) ────────────────────────────────
  # METS = list of list(col, lbl, clr, abs=FALSE)
  .make_spider <- function(sel_ids, bo_db, sv, title_txt, METS) {
    DASHES <- c("solid","dot","dash","dashdot","longdash")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                            title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select datasets"))
    ds_list <- list()
    ds_idx  <- 0L
    for (i in seq_along(sel_ids)) {
      id  <- sel_ids[i]
      df  <- .get_df(id); if (is.null(df)) next
      r   <- isolate(lp_datasets()[[id]])
      base_nm <- .short_name(r$filename %||% id, 14L)
      sv_list <- .freq_optima_sv(df, sv, bo_db)
      if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        fo    <- sv_list[[si]]$fo
        sv_lbl <- sv_list[[si]]$sv_lbl
        nm    <- if (!is.null(sv_lbl)) paste0(sv_lbl, " [", base_nm, "]") else base_nm
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]
        ds_idx <- ds_idx + 1L
        ds_list[[length(ds_list)+1L]] <- list(
          fo   = fo,
          name = nm,
          dash = DASHES[((ds_idx-1L) %% length(DASHES)) + 1L])
      }
    }
    if (length(ds_list) == 0) return(ep("No frequency data available"))
    all_freqs <- sort(unique(unlist(lapply(ds_list, function(d) d$fo$freq_ghz))))
    all_freqs <- all_freqs[is.finite(all_freqs)]
    if (length(all_freqs) == 0) return(ep("No valid frequencies found"))
    spoke_lbls <- sprintf("%.4g GHz", all_freqs)
    all_fo <- do.call(rbind, lapply(ds_list, `[[`, "fo"))
    safe_norm <- function(x, mn, mx) {
      rng <- mx - mn
      if (!is.finite(rng) || rng < 1e-10) return(rep(50, length(x)))
      pmax(0, pmin(100, (x - mn) / rng * 100))
    }
    g_range <- lapply(METS, function(m) {
      col <- m$col
      if (!col %in% names(all_fo)) return(list(mn=0, mx=1))
      vals <- if (isTRUE(m$abs)) abs(all_fo[[col]]) else all_fo[[col]]
      mn <- suppressWarnings(min(vals, na.rm=TRUE))
      mx <- suppressWarnings(max(vals, na.rm=TRUE))
      if (!is.finite(mn) || !is.finite(mx)) list(mn=0, mx=1) else list(mn=mn, mx=mx)
    })
    p <- plot_ly(); multi_ds <- length(ds_list) > 1L
    for (di in seq_along(ds_list)) {
      ds <- ds_list[[di]]
      fo <- ds$fo; ds_nm <- ds$name; dsh <- ds$dash
      fo_freqs <- fo$freq_ghz
      for (mi in seq_along(METS)) {
        met <- METS[[mi]]
        if (!met$col %in% names(fo)) next
        raw_vals <- if (isTRUE(met$abs)) abs(fo[[met$col]]) else fo[[met$col]]
        if (all(is.na(raw_vals))) next
        norm_vals <- safe_norm(raw_vals, g_range[[mi]]$mn, g_range[[mi]]$mx)
        r_vec <- rep(NA_real_, length(all_freqs))
        for (fi in seq_along(fo_freqs)) {
          idx <- which(abs(all_freqs - fo_freqs[fi]) < 1e-6)
          if (length(idx) > 0) r_vec[idx[1]] <- norm_vals[fi]
        }
        ok <- which(!is.na(r_vec))
        if (length(ok) == 0) next
        r_cl <- c(r_vec[ok], r_vec[ok[1]]); t_cl <- c(spoke_lbls[ok], spoke_lbls[ok[1]])
        lbl  <- if (multi_ds) paste0(met$lbl, " [", ds_nm, "]") else met$lbl
        p <- p %>% add_trace(type="scatterpolar", mode="lines+markers",
          r=r_cl, theta=t_cl, fill="toself",
          fillcolor=paste0(met$clr, "22"),
          line=list(color=met$clr, width=1.8, dash=dsh),
          marker=list(color=met$clr, size=5),
          name=lbl, showlegend=TRUE, opacity=0.85)
      }
    }
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      polar = list(bgcolor="#1b1b2b",
        radialaxis  = list(visible=TRUE, range=c(0,100), color="#aaa",
                           gridcolor="rgba(150,150,150,0.3)",
                           tickfont=list(color="#aaa"), ticksuffix="%"),
        angularaxis = list(color="#aaa", tickfont=list(color="#ddd"), direction="clockwise")),
      legend = list(orientation="h", x=0.5, xanchor="center", y=-0.12,
                    font=list(color="#aaa", size=10), bgcolor="rgba(0,0,0,0.20)"),
      title  = list(text=title_txt, font=list(color="#eee", size=13)),
      font   = list(color="#aaa"),
      margin = list(l=40, r=40, t=55, b=110))
  }

  # ── Spider (reverse): spokes = metrics, traces = frequencies ─────────────
  .make_spider_rev <- function(sel_ids, bo_db, sv, title_txt, METS) {
    FPAL <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd",
              "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                            title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select datasets"))
    ds_list <- list()
    for (i in seq_along(sel_ids)) {
      id  <- sel_ids[i]
      df  <- .get_df(id); if (is.null(df)) next
      r   <- isolate(lp_datasets()[[id]])
      base_nm <- .short_name(r$filename %||% id, 14L)
      sv_list <- .freq_optima_sv(df, sv, bo_db)
      if (is.null(sv_list)) next
      for (si in seq_along(sv_list)) {
        fo    <- sv_list[[si]]$fo
        sv_lbl <- sv_list[[si]]$sv_lbl
        nm    <- if (!is.null(sv_lbl)) paste0(sv_lbl, " [", base_nm, "]") else base_nm
        fo    <- fo[order(fo$freq_ghz, na.last=NA),]
        ds_list[[length(ds_list)+1L]] <- list(fo = fo, name = nm)
      }
    }
    if (length(ds_list) == 0) return(ep("No frequency data available"))
    spoke_lbls <- sapply(METS, `[[`, "lbl")
    n_spokes   <- length(METS)
    all_fo <- do.call(rbind, lapply(ds_list, `[[`, "fo"))
    safe_norm <- function(x, mn, mx) {
      rng <- mx - mn
      if (!is.finite(rng) || rng < 1e-10) return(rep(50, length(x)))
      pmax(0, pmin(100, (x - mn) / rng * 100))
    }
    g_range <- lapply(METS, function(m) {
      col <- m$col
      if (!col %in% names(all_fo)) return(list(mn=0, mx=1))
      vals <- if (isTRUE(m$abs)) abs(all_fo[[col]]) else all_fo[[col]]
      mn <- suppressWarnings(min(vals, na.rm=TRUE))
      mx <- suppressWarnings(max(vals, na.rm=TRUE))
      if (!is.finite(mn) || !is.finite(mx)) list(mn=0, mx=1) else list(mn=mn, mx=mx)
    })
    multi_ds <- length(ds_list) > 1L
    p <- plot_ly(); col_idx <- 0L
    for (di in seq_along(ds_list)) {
      ds <- ds_list[[di]]
      fo <- ds$fo; ds_nm <- ds$name
      for (fi in seq_along(fo$freq_ghz)) {
        fq  <- fo$freq_ghz[fi]
        row <- fo[fi, , drop=FALSE]
        r_vec <- rep(NA_real_, n_spokes)
        for (mi in seq_along(METS)) {
          met <- METS[[mi]]
          if (!met$col %in% names(row)) next
          val <- if (isTRUE(met$abs)) abs(row[[met$col]]) else row[[met$col]]
          if (length(val) == 0 || is.na(val)) next
          r_vec[mi] <- safe_norm(val, g_range[[mi]]$mn, g_range[[mi]]$mx)
        }
        ok <- which(!is.na(r_vec))
        if (length(ok) < 2L) next
        r_cl <- c(r_vec[ok], r_vec[ok[1L]]); t_cl <- c(spoke_lbls[ok], spoke_lbls[ok[1L]])
        col_idx <- col_idx + 1L
        clr <- FPAL[((col_idx - 1L) %% length(FPAL)) + 1L]
        lbl <- if (multi_ds) sprintf("%.4g GHz [%s]", fq, ds_nm) else sprintf("%.4g GHz", fq)
        p <- p %>% add_trace(type="scatterpolar", mode="lines+markers",
          r=r_cl, theta=t_cl, fill="toself",
          fillcolor=paste0(clr, "22"),
          line=list(color=clr, width=1.8),
          marker=list(color=clr, size=5),
          name=lbl, showlegend=TRUE, opacity=0.85)
      }
    }
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      polar = list(bgcolor="#1b1b2b",
        radialaxis  = list(visible=TRUE, range=c(0,100), color="#aaa",
                           gridcolor="rgba(150,150,150,0.3)",
                           tickfont=list(color="#aaa"), ticksuffix="%"),
        angularaxis = list(color="#aaa", tickfont=list(color="#ddd"), direction="clockwise")),
      legend = list(orientation="h", x=0.5, xanchor="center", y=-0.12,
                    font=list(color="#aaa", size=10), bgcolor="rgba(0,0,0,0.20)"),
      title  = list(text=title_txt, font=list(color="#eee", size=13)),
      font   = list(color="#aaa"),
      margin = list(l=40, r=40, t=55, b=110))
  }

  output$lp_spider_peak_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider(input$lp_spider_dataset_selector, bo_db, sv,
      "Spider: Peak Performance (MXP / MXE / MXG)",
      list(
        list(col="mxp_dbm",  lbl="Pout@MXP",      clr="#ff7f11", abs=FALSE),
        list(col="mxe_pae",  lbl="PAE@MXE",        clr="#1f77b4", abs=FALSE),
        list(col="mxe_de",   lbl="DE@MXE",         clr="#17becf", abs=FALSE),
        list(col="mxg_gain", lbl="Gain@MXG",       clr="#2ca02c", abs=FALSE),
        list(col="ampm_mxe", lbl="|AM-PM|\u00b0@MXE", clr="#e377c2", abs=TRUE)))
  })

  output$lp_spider_p1db_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider(input$lp_spider_dataset_selector, bo_db, sv,
      "Spider: P1dB Operating Point",
      list(
        list(col="pout_p1db", lbl="Pout@P1dB",      clr="#ff7f11", abs=FALSE),
        list(col="pae_p1db",  lbl="PAE@P1dB",        clr="#1f77b4", abs=FALSE),
        list(col="de_p1db",   lbl="DE@P1dB",         clr="#17becf", abs=FALSE),
        list(col="gain_p1db", lbl="Gain@P1dB",       clr="#2ca02c", abs=FALSE),
        list(col="ampm_p1db", lbl="|AM-PM|\u00b0@P1dB", clr="#e377c2", abs=TRUE)))
  })

  output$lp_spider_pavg_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider(input$lp_spider_dataset_selector, bo_db, sv,
      paste0("Spider: Pavg (", bo_db, " dB back-off)"),
      list(
        list(col="pout_pavg", lbl="Pout@Pavg",       clr="#ff7f11", abs=FALSE),
        list(col="pae_pavg",  lbl="PAE@Pavg",         clr="#1f77b4", abs=FALSE),
        list(col="de_pavg",   lbl="DE@Pavg",          clr="#17becf", abs=FALSE),
        list(col="gain_pavg", lbl="Gain@Pavg",        clr="#2ca02c", abs=FALSE),
        list(col="ampm_pavg", lbl="|AM-PM|\u00b0@Pavg",  clr="#e377c2", abs=TRUE)))
  })

  output$lp_spider_peak_rev_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider_rev(input$lp_spider_dataset_selector, bo_db, sv,
      "Spider (Rev): Peak \u2014 Spokes=Metrics, Traces=Frequencies",
      list(
        list(col="mxp_dbm",  lbl="Pout@MXP",         clr="#ff7f11", abs=FALSE),
        list(col="mxe_pae",  lbl="PAE@MXE",           clr="#1f77b4", abs=FALSE),
        list(col="mxe_de",   lbl="DE@MXE",            clr="#17becf", abs=FALSE),
        list(col="mxg_gain", lbl="Gain@MXG",          clr="#2ca02c", abs=FALSE),
        list(col="ampm_mxe", lbl="|AM-PM|\u00b0@MXE", clr="#e377c2", abs=TRUE)))
  })

  output$lp_spider_p1db_rev_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider_rev(input$lp_spider_dataset_selector, bo_db, sv,
      "Spider (Rev): P1dB \u2014 Spokes=Metrics, Traces=Frequencies",
      list(
        list(col="pout_p1db", lbl="Pout@P1dB",          clr="#ff7f11", abs=FALSE),
        list(col="pae_p1db",  lbl="PAE@P1dB",            clr="#1f77b4", abs=FALSE),
        list(col="de_p1db",   lbl="DE@P1dB",             clr="#17becf", abs=FALSE),
        list(col="gain_p1db", lbl="Gain@P1dB",           clr="#2ca02c", abs=FALSE),
        list(col="ampm_p1db", lbl="|AM-PM|\u00b0@P1dB",  clr="#e377c2", abs=TRUE)))
  })

  output$lp_spider_pavg_rev_plot <- renderPlotly({
    bo_db <- as.numeric(input$lp_freq_backoff %||% 6)
    sv    <- .eff_split("freq")
    .make_spider_rev(input$lp_spider_dataset_selector, bo_db, sv,
      paste0("Spider (Rev): Pavg (", bo_db, " dB back-off) \u2014 Spokes=Metrics, Traces=Frequencies"),
      list(
        list(col="pout_pavg", lbl="Pout@Pavg",          clr="#ff7f11", abs=FALSE),
        list(col="pae_pavg",  lbl="PAE@Pavg",            clr="#1f77b4", abs=FALSE),
        list(col="de_pavg",   lbl="DE@Pavg",             clr="#17becf", abs=FALSE),
        list(col="gain_pavg", lbl="Gain@Pavg",           clr="#2ca02c", abs=FALSE),
        list(col="ampm_pavg", lbl="|AM-PM|\u00b0@Pavg",  clr="#e377c2", abs=TRUE)))
  })


}

