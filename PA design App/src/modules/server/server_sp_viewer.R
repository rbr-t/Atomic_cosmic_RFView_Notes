# =============================================================================
# server_sp_viewer.R
# S-Parameter Viewer — server module for the PA Design App.
#
# Handles:
#   · Parsing Touchstone files (delegates to sp_parsers.R)
#   · Mag & Phase plots vs frequency
#   · Smith Chart view (any S/Z/Y/h/ABCD combination)
#   · Stability circles, K-factor and Mu factors
#   · Parameter conversion: S → Z, Y, h, ABCD, T
#   · Global / per-tab split variable
#   · Multi-dataset management (upload, tag, merge, remove)
# =============================================================================

serverSpViewer <- function(input, output, session, state) {

  # ── Palette ─────────────────────────────────────────────────────────────────
  SP_PALETTE <- c("#ff7f11", "#1f77b4", "#2ca02c", "#d62728",
                  "#9467bd", "#8c564b", "#e377c2", "#17becf",
                  "#bcbd22", "#aec7e8")

  # ── Internal state ───────────────────────────────────────────────────────────
  sp_datasets <- reactiveVal(list())   # named list: id → parsed result
  sp_log      <- reactiveVal(character())

  .sp_log_add <- function(...) {
    msg <- paste(..., collapse = " ")
    sp_log(c(sp_log(), paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", msg)))
  }

  # ── Generate unique dataset id ────────────────────────────────────────────────
  .new_sp_id <- function() {
    paste0("sp_", format(Sys.time(), "%Y%m%d%H%M%S%OS3"),
           "_", sample.int(9999, 1))
  }

  # ── Helper: truncate legend label ────────────────────────────────────────────
  .trunc <- function(s, n = 28L) {
    s <- as.character(s[1L])
    if (nchar(s) > n) paste0(substr(s, 1L, n), "\u2026") else s
  }

  # ── DATASET LIST UI ──────────────────────────────────────────────────────────
  output$sp_dataset_list <- renderUI({
    ds <- sp_datasets()
    if (length(ds) == 0)
      return(p(style = "color:#666; font-size:11px; margin:4px 0;",
               icon("info-circle"), " No datasets loaded yet."))
    tagList(lapply(seq_along(ds), function(i) {
      id <- names(ds)[i]
      r  <- ds[[id]]
      div(style = "display:flex; align-items:center; gap:6px; margin:3px 0;
                   background:#232333; border-radius:4px; padding:4px 8px;",
        div(style = paste0("width:10px; height:10px; border-radius:50%;
                            background:", SP_PALETTE[((i-1) %% length(SP_PALETTE))+1],
                           "; flex-shrink:0;")),
        div(style = "flex:1; overflow:hidden;",
          tags$small(style = "color:#eee; display:block; white-space:nowrap;
                               overflow:hidden; text-overflow:ellipsis;",
                     .trunc(r$dataset_tag, 30)),
          tags$small(style = "color:#888; display:block;",
                     sprintf("%d-port · %d pts · %s",
                             r$nports %||% "?",
                             nrow(r$points) %||% 0,
                             r$meta$freq_range %||% ""))
        ),
        actionButton(paste0("sp_remove_", id), NULL,
                     icon = icon("times"),
                     class = "btn btn-danger",
                     style = "padding:1px 6px; font-size:10px; line-height:1.4; border-radius:3px;")
      )
    }))
  })

  # ── REMOVE dataset buttons ───────────────────────────────────────────────────
  observe({
    ds <- sp_datasets()
    lapply(names(ds), function(id) {
      btn_id <- paste0("sp_remove_", id)
      observeEvent(input[[btn_id]], {
        cur <- sp_datasets()
        cur[[id]] <- NULL
        sp_datasets(cur)
        .sp_log_add("Removed dataset:", ds[[id]]$dataset_tag)
      }, ignoreInit = TRUE, once = TRUE)
    })
  })

  # ── MERGE SELECT UI ──────────────────────────────────────────────────────────
  output$sp_merge_select_ui <- renderUI({
    ds <- sp_datasets()
    if (length(ds) < 2)
      return(p(style = "color:#888; font-size:11px;",
               "Upload at least 2 datasets to merge."))
    checkboxGroupInput("sp_merge_ids", NULL,
                       choices  = setNames(names(ds),
                                           sapply(ds, `[[`, "dataset_tag")),
                       selected = names(ds))
  })

  # ── CLEAR ALL ────────────────────────────────────────────────────────────────
  observeEvent(input$sp_clear_all_btn, {
    sp_datasets(list())
    sp_log(character())
    .sp_log_add("All datasets cleared.")
  })

  # ── PARSE UPLOADED FILES ─────────────────────────────────────────────────────
  observeEvent(input$sp_parse_btn, {
    req(input$sp_upload)
    files   <- input$sp_upload
    n_files <- nrow(files)
    withProgress(message = "Parsing S-parameter files", value = 0, {
      for (i in seq_len(n_files)) {
        fp  <- files$datapath[i]
        fn  <- files$name[i]
        setProgress(
          value   = (i - 1) / n_files,
          detail  = sprintf("%d / %d: %s", i, n_files,
                            if (nchar(fn) > 30) paste0(substr(fn,1,28),"\u2026") else fn)
        )
        tag <- if (isTRUE(input$sp_auto_tag)) {
          .sp_auto_tag(fn)
        } else if (!is.null(input$sp_dataset_tag) && nzchar(input$sp_dataset_tag)) {
          input$sp_dataset_tag
        } else {
          .sp_auto_tag(fn)
        }
        .sp_log_add("Parsing:", fn)
        r <- tryCatch(
          parse_sp_file(fp, dataset_tag = tag),
          error = function(e) .sp_err("auto", fn, conditionMessage(e))
        )
        if (isTRUE(r$success)) {
          id <- .new_sp_id()
          cur <- sp_datasets()
          cur[[id]] <- r
          sp_datasets(cur)
          .sp_log_add("OK:", fn,
                      sprintf("(%d-port, %d freq pts, Z0=%.4g\u03a9)",
                              r$nports, length(r$freq_ghz), r$z0))
        } else {
          .sp_log_add("ERROR:", fn, "-", r$error)
        }
        setProgress(value = i / n_files,
                    detail = if (i == n_files) "Done" else NULL)
      }
    })
  })

  # ── MERGE DATASETS ───────────────────────────────────────────────────────────
  observeEvent(input$sp_merge_btn, {
    ids <- input$sp_merge_ids
    req(length(ids) >= 2)
    ds <- sp_datasets()
    sel <- ds[ids]
    withProgress(message = "Merging datasets", value = 0, {
    setProgress(0.2, detail = "Combining rows\u2026")
    # Combine points data frames
    merged_pts <- do.call(rbind, lapply(sel, `[[`, "points"))
    lbl <- if (!is.null(input$sp_merge_label) && nzchar(input$sp_merge_label))
      input$sp_merge_label
    else paste(sapply(sel, `[[`, "dataset_tag"), collapse = " + ")
    merged_pts$dataset_tag <- lbl
    n1 <- sel[[1]]
    new_r <- list(
      success     = TRUE,
      format      = "merged",
      filename    = lbl,
      dataset_tag = lbl,
      nports      = n1$nports,
      freq_ghz    = sort(unique(merged_pts$freq_ghz)),
      freq_unit   = n1$freq_unit %||% "ghz",
      data_format = n1$data_format %||% "ri",
      param_type  = n1$param_type %||% "s",
      z0          = n1$z0 %||% 50,
      sp_list     = NULL,    # merged: per-freq list not rebuilt
      points      = merged_pts,
      meta        = list(
        filename   = lbl,
        nports     = n1$nports,
        z0         = n1$meta$z0 %||% "50 Ω",
        param_type = n1$meta$param_type %||% "S",
        n_freqs    = nrow(dplyr::distinct(merged_pts, freq_ghz)),
        freq_range = sprintf("%.4g – %.4g GHz",
                             min(merged_pts$freq_ghz, na.rm = TRUE),
                             max(merged_pts$freq_ghz, na.rm = TRUE))
      ),
      raw = character()
    )
    setProgress(0.8, detail = "Finalising\u2026")
    new_id <- .new_sp_id()
    cur    <- sp_datasets()
    cur[[new_id]] <- new_r
    sp_datasets(cur)
    .sp_log_add("Merged", length(ids), "datasets into:", lbl)
    setProgress(1.0, detail = "Done")
    }) # end withProgress
  })

  # ── PARSE LOG output ─────────────────────────────────────────────────────────
  output$sp_parse_log <- renderText({
    log <- sp_log()
    if (length(log) == 0) "No files parsed yet."
    else paste(tail(log, 40), collapse = "\n")
  })

  # ── METADATA PREVIEW ────────────────────────────────────────────────────────
  output$sp_meta_preview <- renderText({
    ds <- sp_datasets()
    if (length(ds) == 0) return("— load a file to see metadata —")
    lines_out <- character()
    for (id in names(ds)) {
      r <- ds[[id]]
      m <- r$meta
      lines_out <- c(lines_out,
        paste0("=== ", r$dataset_tag, " ==="),
        sprintf("  File     : %s",  m$filename %||% "?"),
        sprintf("  Ports    : %d",  m$nports   %||% "?"),
        sprintf("  Z0       : %s",  m$z0       %||% "50 Ω"),
        sprintf("  Param    : %s",  m$param_type %||% "S"),
        sprintf("  Format   : %s",  m$data_format %||% "MA"),
        sprintf("  Freq pts : %d",  m$n_freqs  %||% 0),
        sprintf("  Freq range: %s", m$freq_range %||% "?"),
        "")
    }
    paste(lines_out, collapse = "\n")
  })

  # ── SHARED DATASET SELECTOR UI ──────────────────────────────────────────────
  .dataset_selector <- function(out_id, label = "Dataset(s)") {
    output[[paste0("sp_", out_id)]] <- renderUI({
      ds <- sp_datasets()
      if (length(ds) == 0) return(NULL)
      choices <- setNames(names(ds), sapply(ds, `[[`, "dataset_tag"))
      selectInput(paste0("sp_sel_", out_id), label,
                  choices = choices, selected = names(ds)[1],
                  multiple = TRUE, width = "100%")
    })
  }
  .dataset_selector("mp_ds_ui",    "Dataset(s)")
  .dataset_selector("smith_ds_ui", "Dataset(s)")
  .dataset_selector("stab_ds_ui",  "Dataset(s)")
  .dataset_selector("conv_ds_ui",  "Dataset(s)")
  .dataset_selector("tbl_ds_ui",   "Dataset(s)")

  # ── HELPER: get combined points for selected ids ──────────────────────────
  .get_points <- function(sel_ids) {
    ds <- sp_datasets()
    ids <- if (is.null(sel_ids) || length(sel_ids) == 0) names(ds) else sel_ids
    ids <- ids[ids %in% names(ds)]
    if (length(ids) == 0) return(NULL)
    do.call(rbind, lapply(ids, function(id) ds[[id]]$points))
  }

  # ── HELPER: get combined sp_list for selected id (single dataset) ─────────
  .get_splist_single <- function(sel_id) {
    ds <- sp_datasets()
    if (is.null(sel_id) || length(sel_id) == 0) return(NULL)
    id <- sel_id[1]
    if (!id %in% names(ds)) return(NULL)
    r <- ds[[id]]
    list(sp_list = r$sp_list, freq_ghz = r$freq_ghz,
         nports = r$nports, z0 = r$z0 %||% 50,
         dataset_tag = r$dataset_tag)
  }

  # ── Effective split variable ─────────────────────────────────────────────────
  .eff_split <- function(local_id) {
    lv <- input[[local_id]] %||% "global"
    if (!is.null(lv) && lv != "global") lv
    else input$sp_global_split_var %||% "dataset_tag"
  }

  # ── Phase / group-delay helpers ───────────────────────────────────────────────
  .phase_unwrap <- function(phase_rad) {
    n <- length(phase_rad)
    if (n <= 1L) return(phase_rad)
    dp <- diff(phase_rad)
    dp_corr <- dp - 2 * pi * round(dp / (2 * pi))
    c(phase_rad[1L], phase_rad[1L] + cumsum(dp_corr))
  }

  # Group delay (ns): -d(phase_rad) / (2π · d(freq_GHz))
  .gd_ns <- function(ph_unwrapped, freq_ghz) {
    n  <- length(freq_ghz)
    gd <- rep(NA_real_, n)
    if (n < 2L) return(gd)
    ph <- ph_unwrapped; fr <- freq_ghz
    gd[1L] <- -(ph[2L]   - ph[1L])     / (fr[2L]   - fr[1L])
    gd[n]  <- -(ph[n]    - ph[n - 1L]) / (fr[n]    - fr[n - 1L])
    if (n >= 3L)
      gd[2L:(n - 1L)] <- -(ph[3L:n] - ph[1L:(n - 2L)]) / (fr[3L:n] - fr[1L:(n - 2L)])
    gd / (2 * pi)   # ns
  }

  # ── PARAM TYPE UI helpers ────────────────────────────────────────────────────
  .param_choices <- function(nports) {
    base <- c("S11" = "S11")
    if (nports >= 2)
      base <- c(base, "S21" = "S21", "S12" = "S12", "S22" = "S22")
    base
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # MAG & PHASE TAB
  # ─────────────────────────────────────────────────────────────────────────────

  # Reactive: build data for Mag/Phase — performs conversion when needed
  sp_mp_data <- reactive({
    sel        <- input$sp_sel_mp_ds_ui
    param_type <- input$sp_param_type %||% "S"
    ds         <- sp_datasets()
    ids <- if (is.null(sel) || length(sel) == 0) names(ds) else sel
    ids <- ids[ids %in% names(ds)]
    if (length(ids) == 0) return(NULL)
    all_dfs <- lapply(ids, function(id) {
      r <- ds[[id]]
      if (param_type == "S" || is.null(r$sp_list)) return(r$points)
      sp_convert_to_df(r$sp_list, r$freq_ghz,
                       target = param_type, z0 = r$z0 %||% 50,
                       dataset_tag = r$dataset_tag)
    })
    all_dfs <- all_dfs[!sapply(all_dfs, is.null)]
    if (length(all_dfs) == 0) return(NULL)
    do.call(rbind, all_dfs)
  })

  output$sp_mag_plot <- renderPlotly({
    pts <- sp_mp_data()
    if (is.null(pts)) {
      return(plotly::plot_ly() %>%
               plotly::layout(
                 paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
                 annotations = list(list(
                   text = "No data — upload a Touchstone file",
                   x = 0.5, y = 0.5, showarrow = FALSE, xref = "paper", yref = "paper",
                   font = list(color = "#888", size = 14)
                 ))
               ))
    }

    sel_params <- input$sp_mp_params %||% unique(pts$param)
    split_col  <- .eff_split("sp_mp_split_local")
    pts <- pts[pts$param %in% sel_params, ]
    if (nrow(pts) == 0) return(plotly::plot_ly())

    split_vals <- sort(unique(pts[[split_col]]))
    fig <- plotly::plot_ly()
    for (si in seq_along(split_vals)) {
      sv  <- split_vals[si]
      sub <- pts[pts[[split_col]] == sv, ]
      for (pi in seq_along(sel_params)) {
        pm  <- sel_params[pi]
        sub2 <- sub[sub$param == pm, ]
        if (nrow(sub2) == 0) next
        col  <- SP_PALETTE[((si - 1) * length(sel_params) + pi - 1) %% length(SP_PALETTE) + 1]
        lbl  <- if (split_col == "dataset_tag") sprintf("%s · %s", pm, sv)
                else sprintf("%s @ %s=%s", pm, split_col, sv)
        fig <- fig %>% plotly::add_trace(
          x = sub2$freq_ghz, y = sub2$mag_db,
          type = "scatter", mode = "lines+markers",
          name = lbl,
          line   = list(color = col, width = 1.8),
          marker = list(color = col, size = 4),
          hovertemplate = paste0(lbl, "<br>Freq: %{x:.4g} GHz<br>",
                                 "|%{meta}|: %{y:.2f} dB<extra></extra>"),
          meta = pm
        )
      }
    }

    ptype <- toupper(input$sp_param_type %||% "S")
    fig %>% plotly::layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor  = "#1b1b2b",
      xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                   gridcolor = "#2a2a3a", tickfont = list(color = "#aaa"),
                   zeroline = FALSE),
      yaxis = list(title = sprintf("|%s| (dB)", ptype),
                   color = "#aaa", gridcolor = "#2a2a3a",
                   tickfont = list(color = "#aaa"), zeroline = FALSE),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.3)", orientation = "v"),
      title  = list(text = sprintf("Magnitude — %s Parameters", ptype),
                    font = list(color = "#eee", size = 14)),
      margin = list(l = 55, r = 10, t = 50, b = 50),
      hovermode = "x unified"
    )
  })

  output$sp_phase_plot <- renderPlotly({
    pts <- sp_mp_data()
    if (is.null(pts)) return(plotly::plot_ly())

    sel_params <- input$sp_mp_params %||% unique(pts$param)
    split_col  <- .eff_split("sp_mp_split_local")
    pts <- pts[pts$param %in% sel_params, ]
    if (nrow(pts) == 0) return(plotly::plot_ly())

    split_vals <- sort(unique(pts[[split_col]]))
    fig <- plotly::plot_ly()
    for (si in seq_along(split_vals)) {
      sv  <- split_vals[si]
      sub <- pts[pts[[split_col]] == sv, ]
      for (pi in seq_along(sel_params)) {
        pm   <- sel_params[pi]
        sub2 <- sub[sub$param == pm, ]
        if (nrow(sub2) == 0) next
        col  <- SP_PALETTE[((si - 1) * length(sel_params) + pi - 1) %% length(SP_PALETTE) + 1]
        lbl  <- if (split_col == "dataset_tag") sprintf("%s · %s", pm, sv)
                else sprintf("%s @ %s=%s", pm, split_col, sv)
        fig <- fig %>% plotly::add_trace(
          x = sub2$freq_ghz, y = sub2$phase_deg,
          type = "scatter", mode = "lines+markers",
          name = lbl,
          line   = list(color = col, width = 1.8),
          marker = list(color = col, size = 4),
          hovertemplate = paste0(lbl, "<br>Freq: %{x:.4g} GHz<br>Phase: %{y:.2f}°<extra></extra>")
        )
      }
    }
    ptype <- toupper(input$sp_param_type %||% "S")
    fig %>% plotly::layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor  = "#1b1b2b",
      xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                   gridcolor = "#2a2a3a", tickfont = list(color = "#aaa"),
                   zeroline = FALSE),
      yaxis = list(title = sprintf("Phase of %s (°)", ptype),
                   color = "#aaa", gridcolor = "#2a2a3a",
                   tickfont = list(color = "#aaa"), zeroline = FALSE),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.3)", orientation = "v"),
      title  = list(text = sprintf("Phase — %s Parameters", ptype),
                    font = list(color = "#eee", size = 14)),
      margin = list(l = 55, r = 10, t = 50, b = 50),
      hovermode = "x unified"
    )
  })

  # Dynamic param checkboxes for Mag/Phase tab
  output$sp_mp_param_choices_ui <- renderUI({
    df <- sp_mp_data()
    if (is.null(df) || nrow(df) == 0) return(NULL)
    all_params <- sort(unique(df$param))
    checkboxGroupInput("sp_mp_params", "Parameters to show",
      choices = all_params, selected = all_params, inline = TRUE)
  })

  # ─────────────────────────────────────────────────────────────────────────────
  # SMITH CHART TAB
  # ─────────────────────────────────────────────────────────────────────────────

  output$sp_smith_plot <- renderPlotly({
    sel  <- input$sp_sel_smith_ds_ui
    pts  <- .get_points(sel)
    if (is.null(pts)) {
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
                               annotations = list(list(
                                 text = "No data — load a dataset",
                                 x = 0.5, y = 0.5, showarrow = FALSE,
                                 xref = "paper", yref = "paper",
                                 font = list(color = "#888", size = 14)))))
    }

    # Which params to show on Smith (only makes sense for |Γ|-type: S11, S22)
    sp_params  <- input$sp_smith_params %||% c("S11", "S22")
    split_col  <- .eff_split("sp_smith_split_local")
    pts_s <- pts[pts$param %in% sp_params, ]
    if (nrow(pts_s) == 0) return(plotly::plot_ly())

    # Build Smith grid
    grid_traces <- build_smith_grid()
    fig <- plotly::plot_ly()
    for (tr in grid_traces) {
      fig <- fig %>% plotly::add_trace(
        x = tr$x, y = tr$y, type = "scatter", mode = "lines",
        line = tr$line, name = tr$name, showlegend = FALSE,
        hoverinfo = "none")
    }

    split_vals <- sort(unique(pts_s[[split_col]]))
    for (si in seq_along(split_vals)) {
      sv  <- split_vals[si]
      sub <- pts_s[pts_s[[split_col]] == sv, ]
      params_here <- unique(sub$param)
      for (pi in seq_along(params_here)) {
        pm   <- params_here[pi]
        sub2 <- sub[sub$param == pm, ]
        if (nrow(sub2) == 0) next
        col  <- SP_PALETTE[((si - 1) * length(params_here) + pi - 1) %% length(SP_PALETTE) + 1]
        lbl  <- sprintf("%s · %s", pm, sv)
        # Convert to Γ via S-param (S11, S22 ARE Γ for single port)
        fig <- fig %>% plotly::add_trace(
          x = sub2$real, y = sub2$imag,
          type = "scatter", mode = "lines+markers",
          name = lbl,
          line   = list(color = col, width = 2),
          marker = list(color = col, size = 5),
          hovertemplate = paste0(
            lbl, "<br>Freq: %{customdata:.4g} GHz",
            "<br>Γ: %{x:.3f}%{y:+.3f}j<extra></extra>"),
          customdata = sub2$freq_ghz
        )
        # Start marker
        fig <- fig %>% plotly::add_trace(
          x = sub2$real[1], y = sub2$imag[1],
          type = "scatter", mode = "markers",
          name = paste("start", lbl),
          marker = list(color = col, size = 9, symbol = "triangle-up"),
          showlegend = FALSE, hoverinfo = "skip"
        )
      }
    }

    fig %>% plotly::layout(
      .smith_layout(
        sprintf("Smith Chart — %s", toupper(input$sp_param_type %||% "S"))
      )
    )
  })

  # Dynamic param selector for Smith chart
  output$sp_smith_param_choices_ui <- renderUI({
    ds  <- sp_datasets()
    sel <- input$sp_sel_smith_ds_ui
    if (length(ds) == 0) return(NULL)
    id  <- if (!is.null(sel) && length(sel) && sel[1] %in% names(ds)) sel[1] else names(ds)[1]
    np  <- ds[[id]]$nports %||% 2
    all_params <- sprintf("S%d%d", rep(1:np, each = np), rep(1:np, times = np))
    # Default: reflection params only (main diagonal)
    def <- sprintf("S%d%d", 1:np, 1:np)
    checkboxGroupInput("sp_smith_params", "Plot on Smith Chart",
      choices = all_params, selected = def, inline = TRUE)
  })

  # ─────────────────────────────────────────────────────────────────────────────
  # STABILITY TAB (K, Mu, Delta + Stability Circles)
  # ─────────────────────────────────────────────────────────────────────────────

  sp_stab_reactive <- reactive({
    sel <- input$sp_sel_stab_ds_ui
    if (is.null(sel) || length(sel) == 0) return(NULL)
    info <- .get_splist_single(sel)
    if (is.null(info) || is.null(info$sp_list)) return(NULL)
    if (info$nports != 2) return(list(error = "Stability only supported for 2-port networks."))
    nf <- length(info$sp_list)
    withProgress(message = "Computing stability", value = 0, {
    setProgress(0.1, detail = sprintf("%d frequency points\u2026", nf))
    stab_df <- sp_stability(info$sp_list, info$freq_ghz)
    setProgress(0.6, detail = "Stability circles\u2026")
    circles  <- sp_stab_circles(info$sp_list, info$freq_ghz)

    # ── Group delay from S-parameter phases ──────────────────────────────────
    port_pairs <- list(S11 = c(1L, 1L), S21 = c(2L, 1L),
                       S12 = c(1L, 2L), S22 = c(2L, 2L))
    gd_df <- tryCatch({
      gd_rows <- lapply(names(port_pairs), function(nm) {
        pp     <- port_pairs[[nm]]
        ph_raw <- sapply(info$sp_list, function(S) Arg(S[pp[1L], pp[2L]]))
        ord    <- order(info$freq_ghz)
        fr_ord <- info$freq_ghz[ord]
        ph_u   <- .phase_unwrap(ph_raw[ord])
        gd     <- .gd_ns(ph_u, fr_ord)
        data.frame(freq_ghz = fr_ord, param = nm, gd_ns = gd,
                   stringsAsFactors = FALSE)
      })
      do.call(rbind, gd_rows)
    }, error = function(e) NULL)

    setProgress(1.0, detail = "Done")
    list(df = stab_df, circles = circles, freq_ghz = info$freq_ghz,
         tag = info$dataset_tag, gd_df = gd_df)
    }) # end withProgress
  })

  output$sp_stab_kmu_plot <- renderPlotly({
    res <- sp_stab_reactive()
    if (is.null(res)) {
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
                               annotations = list(list(text = "No data",
                                 x=0.5,y=0.5,showarrow=FALSE,
                                 xref="paper",yref="paper",
                                 font=list(color="#888",size=14)))))
    }
    if (!is.null(res$error)) {
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                               annotations=list(list(text=res$error,
                                 x=0.5,y=0.5,showarrow=FALSE,
                                 xref="paper",yref="paper",
                                 font=list(color="#ff7f11",size=13)))))
    }
    df  <- res$df
    tag <- res$tag

    fig <- plotly::plot_ly()

    # K factor
    fig <- fig %>% plotly::add_trace(
      x = df$freq_ghz, y = df$K,
      type = "scatter", mode = "lines+markers",
      name = "K (Rollett)",
      line   = list(color = "#ff7f11", width = 2),
      marker = list(color = "#ff7f11", size = 5),
      yaxis  = "y",
      hovertemplate = "K: %{y:.3f}<br>Freq: %{x:.4g} GHz<extra></extra>"
    )
    # Mu_in
    fig <- fig %>% plotly::add_trace(
      x = df$freq_ghz, y = df$mu_in,
      type = "scatter", mode = "lines+markers",
      name = "μ (input)",
      line   = list(color = "#1f77b4", width = 2),
      marker = list(color = "#1f77b4", size = 5),
      hovertemplate = "μ_in: %{y:.3f}<br>Freq: %{x:.4g} GHz<extra></extra>"
    )
    # Mu_out
    fig <- fig %>% plotly::add_trace(
      x = df$freq_ghz, y = df$mu_out,
      type = "scatter", mode = "lines+markers",
      name = "μ' (output)",
      line   = list(color = "#2ca02c", width = 2),
      marker = list(color = "#2ca02c", size = 5),
      hovertemplate = "μ_out: %{y:.3f}<br>Freq: %{x:.4g} GHz<extra></extra>"
    )
    # |Delta|
    fig <- fig %>% plotly::add_trace(
      x = df$freq_ghz, y = df$delta_mag,
      type = "scatter", mode = "lines",
      name = "|Δ|",
      line = list(color = "#9467bd", width = 1.5, dash = "dot"),
      hovertemplate = "|Δ|: %{y:.4f}<br>Freq: %{x:.4g} GHz<extra></extra>"
    )
    # Stability threshold line K=1
    fig <- fig %>% plotly::add_trace(
      x = range(df$freq_ghz, na.rm = TRUE),
      y = c(1, 1),
      type = "scatter", mode = "lines",
      name = "K=1 / μ=1 (threshold)",
      line = list(color = "rgba(255,255,255,0.3)", width = 1, dash = "dash"),
      hoverinfo = "skip", showlegend = TRUE
    )

    fig %>% plotly::layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor  = "#1b1b2b",
      title  = list(text = sprintf("Stability — %s", tag),
                    font = list(color = "#eee", size = 14)),
      xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                   gridcolor = "#2a2a3a", zeroline = FALSE,
                   tickfont = list(color = "#aaa")),
      yaxis = list(title = "K, μ, |Δ|",
                   color = "#aaa", gridcolor = "#2a2a3a",
                   zeroline = FALSE, tickfont = list(color = "#aaa")),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.3)"),
      margin = list(l = 55, r = 10, t = 50, b = 50),
      hovermode = "x unified"
    )
  })

  output$sp_stab_circles_plot <- renderPlotly({
    res <- sp_stab_reactive()
    if (is.null(res) || !is.null(res$error)) return(plotly::plot_ly())

    circles <- res$circles
    freq_ghz <- res$freq_ghz
    tag <- res$tag

    # Which frequencies to draw circles for
    sel_freqs <- if (!is.null(input$sp_stab_circ_freqs) &&
                     length(input$sp_stab_circ_freqs) > 0) {
      as.numeric(input$sp_stab_circ_freqs)
    } else {
      # Default: up to 5 evenly-spaced frequencies
      idx <- unique(round(seq(1, length(freq_ghz), length.out = min(5, length(freq_ghz)))))
      freq_ghz[idx]
    }

    theta <- seq(0, 2 * pi, length.out = 200)
    grid  <- build_smith_grid()
    fig   <- plotly::plot_ly()
    for (tr in grid) {
      fig <- fig %>% plotly::add_trace(
        x = tr$x, y = tr$y, type = "scatter", mode = "lines",
        line = tr$line, name = tr$name, showlegend = FALSE, hoverinfo = "none")
    }

    load_df   <- circles$load
    source_df <- circles$source

    for (i in seq_along(sel_freqs)) {
      fq  <- sel_freqs[i]
      idx <- which.min(abs(freq_ghz - fq))
      col_l <- SP_PALETTE[(i - 1) %% length(SP_PALETTE) + 1]
      col_s <- SP_PALETTE[(i - 1 + 5) %% length(SP_PALETTE) + 1]
      ld <- load_df[idx, ]
      sr <- source_df[idx, ]
      lbl_freq <- sprintf("%.4g GHz", fq)
      if (!is.na(ld$center_r) && !is.na(ld$radius)) {
        fig <- fig %>% plotly::add_trace(
          x    = ld$center_r + ld$radius * cos(theta),
          y    = ld$center_i + ld$radius * sin(theta),
          type = "scatter", mode = "lines",
          name = paste("Load stab. circle", lbl_freq),
          line = list(color = col_l, width = 2),
          hovertemplate = paste0("Load stability circle<br>", lbl_freq, "<extra></extra>")
        )
        fig <- fig %>% plotly::add_trace(
          x = ld$center_r, y = ld$center_i,
          type = "scatter", mode = "markers",
          name = paste("Centre_L", lbl_freq),
          marker = list(color = col_l, size = 8, symbol = "cross"),
          showlegend = FALSE, hoverinfo = "skip"
        )
      }
      if (!is.na(sr$center_r) && !is.na(sr$radius)) {
        fig <- fig %>% plotly::add_trace(
          x    = sr$center_r + sr$radius * cos(theta),
          y    = sr$center_i + sr$radius * sin(theta),
          type = "scatter", mode = "lines",
          name = paste("Source stab. circle", lbl_freq),
          line = list(color = col_s, width = 2, dash = "dash"),
          hovertemplate = paste0("Source stability circle<br>", lbl_freq, "<extra></extra>")
        )
      }
    }

    fig %>% plotly::layout(
      .smith_layout(sprintf("Stability Circles — %s", tag))
    )
  })

  # ── MSG / MAG plot ───────────────────────────────────────────────────────────────────
  output$sp_stab_msg_plot <- renderPlotly({
    res <- sp_stab_reactive()
    if (is.null(res) || !is.null(res$error))
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
                               annotations = list(list(
                                 text = if (!is.null(res$error)) res$error
                                        else "No data — select a 2-port dataset",
                                 x=0.5, y=0.5, showarrow=FALSE,
                                 xref="paper", yref="paper",
                                 font=list(color="#888", size=13)))))
    df  <- res$df
    tag <- res$tag
    fig <- plotly::plot_ly()

    # MSG: plot for rows where K < 1 (conditionally unstable region)
    msg_rows <- df[!is.na(df$msg_db), ]
    if (nrow(msg_rows) > 0) {
      # Show MSG for K<1 points, MAG for K>=1 points as separate styled traces
      ku1 <- msg_rows[!is.na(df$K[!is.na(df$msg_db)]) &
                         df$K[!is.na(df$msg_db)] < 1, ]
      if (nrow(ku1) > 0)
        fig <- fig %>% plotly::add_trace(
          x = ku1$freq_ghz, y = ku1$msg_db,
          type = "scatter", mode = "lines+markers", name = "MSG (K < 1)",
          line   = list(color = "#ff7f11", width = 2, dash = "dot"),
          marker = list(color = "#ff7f11", size = 5, symbol = "circle-open"),
          hovertemplate = "MSG: %{y:.2f} dB<br>Freq: %{x:.4g} GHz<extra></extra>")
    }

    # MAG: plot for rows where K >= 1 (unconditionally stable region)
    mag_rows <- df[!is.na(df$mag_db), ]
    if (nrow(mag_rows) > 0)
      fig <- fig %>% plotly::add_trace(
        x = mag_rows$freq_ghz, y = mag_rows$mag_db,
        type = "scatter", mode = "lines+markers", name = "MAG (K ≥ 1)",
        line   = list(color = "#2ca02c", width = 2),
        marker = list(color = "#2ca02c", size = 5),
        hovertemplate = "MAG: %{y:.2f} dB<br>Freq: %{x:.4g} GHz<extra></extra>")

    # Unilateral gain |S21|^2 reference
    if (!is.null(res$df) && "msg_db" %in% names(res$df)) {
      fig <- fig %>% plotly::layout(
        paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
        title  = list(text = sprintf("MSG / MAG — %s", tag),
                      font = list(color = "#eee", size = 14)),
        xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                     gridcolor = "#2a2a3a", zeroline = FALSE,
                     tickfont = list(color = "#aaa")),
        yaxis = list(title = "Gain (dB)", color = "#aaa",
                     gridcolor = "#2a2a3a", zeroline = FALSE,
                     tickfont = list(color = "#aaa")),
        legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.3)"),
        margin = list(l = 55, r = 10, t = 50, b = 50),
        hovermode = "x unified"
      )
    } else {
      fig <- fig %>% plotly::layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b")
    }
    fig
  })

  # ── Group Delay plot ─────────────────────────────────────────────────────────────────
  output$sp_stab_gd_plot <- renderPlotly({
    res <- sp_stab_reactive()
    if (is.null(res) || !is.null(res$error) || is.null(res$gd_df))
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                               annotations = list(list(
                                 text = "No group delay data — select a 2-port dataset",
                                 x=0.5, y=0.5, showarrow=FALSE,
                                 xref="paper", yref="paper",
                                 font=list(color="#888", size=13)))))
    gd_df <- res$gd_df
    tag   <- res$tag
    gd_colors <- c(S11 = "#ff7f11", S21 = "#1f77b4", S12 = "#2ca02c", S22 = "#d62728")
    fig <- plotly::plot_ly()
    for (pm in unique(gd_df$param)) {
      sub <- gd_df[gd_df$param == pm, ]
      col <- if (pm %in% names(gd_colors)) gd_colors[[pm]] else SP_PALETTE[1]
      fig <- fig %>% plotly::add_trace(
        x = sub$freq_ghz, y = sub$gd_ns,
        type = "scatter", mode = "lines+markers",
        name = sprintf("GD(%s)", pm),
        line   = list(color = col, width = 1.8),
        marker = list(color = col, size = 4),
        hovertemplate = sprintf("GD(%s): %%{y:.3f} ns<br>Freq: %%{x:.4g} GHz<extra></extra>", pm)
      )
    }
    fig %>% plotly::layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
      title  = list(text = sprintf("Group Delay — %s", tag),
                    font = list(color = "#eee", size = 14)),
      xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                   gridcolor = "#2a2a3a", zeroline = FALSE,
                   tickfont = list(color = "#aaa")),
      yaxis = list(title = "Group Delay (ns)", color = "#aaa",
                   gridcolor = "#2a2a3a", zeroline = FALSE,
                   tickfont = list(color = "#aaa")),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.3)"),
      margin = list(l = 55, r = 10, t = 50, b = 50),
      hovermode = "x unified"
    )
  })

  # Dynamic frequency selector for stability circles
  output$sp_stab_circ_freq_ui <- renderUI({
    res <- sp_stab_reactive()
    if (is.null(res) || !is.null(res$error)) return(NULL)
    freqs <- sort(unique(res$freq_ghz))
    def   <- freqs[unique(round(seq(1, length(freqs), length.out = min(5, length(freqs)))))]
    checkboxGroupInput("sp_stab_circ_freqs", "Frequencies for circles",
      choices  = setNames(freqs, sprintf("%.4g GHz", freqs)),
      selected = def, inline = TRUE)
  })

  # ─────────────────────────────────────────────────────────────────────────────
  # CONVERTED PARAMETERS TAB
  # ─────────────────────────────────────────────────────────────────────────────

  sp_conv_reactive <- reactive({
    sel    <- input$sp_sel_conv_ds_ui
    ptype  <- input$sp_param_type %||% "S"
    if (is.null(sel) || length(sel) == 0) return(NULL)
    ds <- sp_datasets()
    withProgress(message = sprintf("Converting to %s-parameters", toupper(ptype)), value = 0, {
    all_dfs <- lapply(seq_along(sel), function(i) {
      id <- sel[i]
      setProgress(
        value  = (i - 1) / length(sel),
        detail = sprintf("%d / %d datasets\u2026", i, length(sel))
      )
      if (!id %in% names(ds)) return(NULL)
      r <- ds[[id]]
      if (is.null(r$sp_list)) {
        pts <- r$points
        pts$param_type <- ptype
        return(pts)
      }
      sp_convert_to_df(r$sp_list, r$freq_ghz,
                       target = ptype, z0 = r$z0 %||% 50,
                       dataset_tag = r$dataset_tag)
    })
    setProgress(1.0, detail = "Done")
    do.call(rbind, all_dfs[!sapply(all_dfs, is.null)])
    }) # end withProgress
  })

  output$sp_conv_plot <- renderPlotly({
    df <- sp_conv_reactive()
    if (is.null(df) || nrow(df) == 0) {
      return(plotly::plot_ly() %>%
               plotly::layout(paper_bgcolor = "#1b1b2b", plot_bgcolor = "#1b1b2b",
                               annotations = list(list(
                                 text = "No data — upload a 2-port Touchstone file",
                                 x=0.5,y=0.5,showarrow=FALSE,xref="paper",yref="paper",
                                 font=list(color="#888",size=14)))))
    }
    ptype      <- toupper(input$sp_param_type %||% "S")
    sel_params <- input$sp_conv_params %||% unique(df$param)
    split_col  <- .eff_split("sp_conv_split_local")
    df <- df[df$param %in% sel_params, ]
    if (nrow(df) == 0) return(plotly::plot_ly())

    split_vals <- sort(unique(df[[split_col]]))
    fig <- plotly::plot_ly()
    for (si in seq_along(split_vals)) {
      sv  <- split_vals[si]
      sub <- df[df[[split_col]] == sv, ]
      params_here <- unique(sub$param)
      for (pi in seq_along(params_here)) {
        pm   <- params_here[pi]
        sub2 <- sub[sub$param == pm, ]
        if (nrow(sub2) == 0) next
        col  <- SP_PALETTE[((si-1)*length(params_here) + pi - 1) %% length(SP_PALETTE) + 1]
        lbl  <- sprintf("%s · %s", pm, sv)
        fig  <- fig %>% plotly::add_trace(
          x = sub2$freq_ghz, y = sub2$mag_db,
          type = "scatter", mode = "lines+markers",
          name = lbl,
          line   = list(color = col, width = 1.8),
          marker = list(color = col, size = 4),
          hovertemplate = paste0(lbl, "<br>Freq: %{x:.4g} GHz<br>|param|: %{y:.2f} dB<extra></extra>")
        )
      }
    }

    fig %>% plotly::layout(
      paper_bgcolor = "#1b1b2b", plot_bgcolor  = "#1b1b2b",
      title  = list(text = sprintf("%s-Parameters (Magnitude)", ptype),
                    font = list(color = "#eee", size = 14)),
      xaxis = list(title = "Frequency (GHz)", color = "#aaa",
                   gridcolor = "#2a2a3a", zeroline = FALSE,
                   tickfont = list(color = "#aaa")),
      yaxis = list(title = sprintf("|%s| (dB)", ptype),
                   color = "#aaa", gridcolor = "#2a2a3a",
                   zeroline = FALSE, tickfont = list(color = "#aaa")),
      legend = list(font = list(color = "#aaa"),
                    bgcolor = "rgba(0,0,0,0.3)"),
      margin = list(l = 55, r = 10, t = 50, b = 50),
      hovermode = "x unified"
    )
  })

  # Dynamic converted-param choices
  output$sp_conv_param_choices_ui <- renderUI({
    df <- sp_conv_reactive()
    if (is.null(df) || nrow(df) == 0) return(NULL)
    all_params <- sort(unique(df$param))
    checkboxGroupInput("sp_conv_params", "Parameters",
      choices = all_params, selected = all_params, inline = TRUE)
  })

  # ─────────────────────────────────────────────────────────────────────────────
  # TABULAR TAB
  # ─────────────────────────────────────────────────────────────────────────────

  output$sp_table_out <- DT::renderDT({
    sel   <- input$sp_sel_tbl_ds_ui
    ptype <- input$sp_param_type %||% "S"
    if (is.null(sel) || length(sel) == 0) return(DT::datatable(data.frame()))
    ds <- sp_datasets()
    withProgress(message = "Building table", value = 0, {
    all_dfs <- lapply(seq_along(sel), function(i) {
      id <- sel[i]
      setProgress(
        value  = (i - 1) / length(sel),
        detail = sprintf("%d / %d datasets\u2026", i, length(sel))
      )
      if (!id %in% names(ds)) return(NULL)
      r <- ds[[id]]
      if (!is.null(r$sp_list)) {
        df <- sp_convert_to_df(r$sp_list, r$freq_ghz,
                               target = ptype, z0 = r$z0 %||% 50,
                               dataset_tag = r$dataset_tag)
      } else {
        df <- r$points
        df$dataset_tag <- r$dataset_tag
      }
      df[, c("freq_ghz","dataset_tag","param","real","imag","mag_db","phase_deg")]
    })
    df <- do.call(rbind, all_dfs[!sapply(all_dfs, is.null)])
    if (is.null(df) || nrow(df) == 0) return(DT::datatable(data.frame()))

    # Round for display
    df$freq_ghz  <- round(df$freq_ghz,  6)
    df$real      <- round(df$real,      5)
    df$imag      <- round(df$imag,      5)
    df$mag_db    <- round(df$mag_db,    3)
    df$phase_deg <- round(df$phase_deg, 3)

    colnames(df) <- c("Freq (GHz)", "Dataset", "Param",
                      "Real", "Imag", "|P| (dB)", "Phase (°)")

    setProgress(1.0, detail = "Rendering\u2026")
    DT::datatable(
      df,
      rownames    = FALSE,
      filter      = "top",
      class       = "table-condensed",
      options = list(
        pageLength  = 20,
        scrollX     = TRUE,
        dom         = "ftip",
        initComplete = DT::JS(
          "function(settings,json){",
          "$(this.api().table().header()).css({'background-color':'#1e1e2e','color':'#ccc'});",
          "}"
        )
      )
    ) %>%
      DT::formatStyle(
        columns    = 1:ncol(df),
        color      = "#ddd",
        background = "#1e1e2e",
        fontSize   = "12px"
      )
    }) # end withProgress
  })

  # CSV download for table
  output$sp_table_csv <- downloadHandler(
    filename = function() paste0("sp_data_", Sys.Date(), ".csv"),
    content  = function(file) {
      sel   <- input$sp_sel_tbl_ds_ui
      ptype <- input$sp_param_type %||% "S"
      ds    <- sp_datasets()
      all_dfs <- lapply(sel, function(id) {
        if (!id %in% names(ds)) return(NULL)
        r <- ds[[id]]
        if (!is.null(r$sp_list)) {
          sp_convert_to_df(r$sp_list, r$freq_ghz,
                           target = ptype, z0 = r$z0 %||% 50,
                           dataset_tag = r$dataset_tag)
        } else {
          pts <- r$points; pts$dataset_tag <- r$dataset_tag; pts
        }
      })
      df <- do.call(rbind, all_dfs[!sapply(all_dfs, is.null)])
      write.csv(df, file, row.names = FALSE)
    }
  )
}
