# apply_lp_changes.ps1
# Applies all multi-dataset + All/None selector changes to the upstream server_lp_viewer.R
# Input IDs use NO suffix (upstream convention): input$lp_xy_dataset_selector etc.

$file  = "d:\GitHub\PA design App\Atomic_cosmic_RFView_Notes\PA design App\R\modules\server\server_lp_viewer.R"
$lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)

# ── 0-based boundaries ────────────────────────────────────────────────────────
$ms_func_start = 426; $ms_func_end = 442   # .make_selector function body
$ms_calls_start = 443; $ms_calls_end = 450 # blank + 6 .make_selector() call lines + blank
$perf_sel_start = 900; $perf_sel_end = 902 # blank + perf selector comment + call
$xy_start = 820; $xy_end = 898
$gain_start = 914; $gain_end = 988
$eff_start  = 991; $eff_end  = 1066
$ss_start   = 1069; $ss_end   = 1159
$sl_start   = 1162; $sl_end   = 1233
$nm_start   = 1238; $nm_end   = 1319
$nx_start   = 1324; $nx_end   = 1406
# Table csv: single-line replacement at line 1577 (0-based)
$tc_line    = 1576
# Table selector references (0-based lines)
$tbl_sel_lines = @(1449, 1477, 1497, 1520)
$aa_start   = 1583; $aa_end   = 1634
$ap_start   = 1637; $ap_end   = 1674

# ── New .make_selector function ───────────────────────────────────────────────
$newMakeSelector = @'
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
'@

$newMsCalls = @'

  .make_selector("lp_dataset_selector",        "Dataset(s)")
  .make_selector("lp_xy_dataset_selector",     "Dataset(s)")
  .make_selector("lp_ampm_dataset_selector",   "Dataset(s)")
  .make_selector("lp_nose_dataset_selector",   "Dataset(s)")
  .make_selector("lp_table_dataset_selector",  "Dataset(s)")
  .make_selector("lp_compare_selector",        "Dataset(s)")

'@

$newPerfSel = @'

  # ── Performance tab — dataset selector ─────────────────────────────────────
  .make_selector("lp_perf_dataset_selector", "Dataset(s)")

'@

# ── New XY plot (multi-dataset outer loop) ────────────────────────────────────
$newXY = @'
  output$lp_xy_plot <- renderPlotly({
    sel_ids <- input$lp_xy_dataset_selector
    y_vars  <- input$lp_xy_y_vars
    x_var   <- input$lp_xy_x_var %||% "pin_dbm"
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    if (is.null(y_vars) || length(y_vars) == 0) return(ep("Select variables to plot"))
    EFF_VARS <- c("pae_pct", "de_pct")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); i_col <- 1L
    for (di in seq_along(sel_ids)) {
      id   <- sel_ids[di]
      need <- unique(c(x_var, y_vars))
      df   <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) next
      ds_nm <- if (multi_ds) {
        r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 20L)
      } else ""
      ord <- order(df[[x_var]], na.last = NA); df <- df[ord, , drop = FALSE]
      xv  <- df[[x_var]]
      y1_labels <- c(); y2_labels <- c()
      for (v in y_vars) {
        if (!v %in% names(df)) next
        yv    <- df[[v]]; ok <- !is.na(xv) & !is.na(yv)
        col   <- PALETTE[(i_col - 1L) %% length(PALETTE) + 1L]; i_col <- i_col + 1L
        on_y2 <- v %in% EFF_VARS
        lbl   <- switch(v, pae_pct="PAE (%)", de_pct="DE (%)", gain_db="Gain (dB)",
                          pout_dbm="Pout (dBm)", pout_w="Pout (W)", pin_dbm="Pin (dBm)",
                          gsub("_", " ", v))
        leg   <- if (multi_ds) paste0(lbl, " [", ds_nm, "]") else lbl
        if (on_y2) y2_labels <- c(y2_labels, lbl) else y1_labels <- c(y1_labels, lbl)
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], yaxis=if(on_y2)"y2" else "y",
          name=leg, opacity=0.80,
          marker=list(color=col, size=5,
                      symbol=if(on_y2)"circle-open" else "circle", opacity=0.70))
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
'@

# ── New Perf Gain (multi-dataset outer loop, freq inner loop preserved) ───────
$newGain = @'
  output$lp_perf_gain_plot <- renderPlotly({
    sel_ids <- input$lp_perf_dataset_selector
    x_var   <- input$lp_perf_x_var   %||% "pout_dbm"
    y2_v    <- input$lp_perf_gain_y2 %||% "none"
    pt_op   <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    col_off <- 0L   # colour offset across datasets
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c(x_var, "gain_db", "freq_ghz", if (y2_v != "none") y2_v))
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) { col_off <- col_off + 3L; next }
      freqs <- if ("freq_ghz" %in% names(df)) sort(unique(na.omit(df$freq_ghz))) else numeric(0)
      multi_f <- length(freqs) > 1
      if ("gain_db" %in% names(df)) {
        if (multi_f) {
          for (fi in seq_along(freqs)) {
            fq  <- freqs[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
            dff <- df[!is.na(df$freq_ghz) & df$freq_ghz == fq, , drop=FALSE]
            xvf <- dff[[x_var]]; yv <- dff$gain_db; ok  <- !is.na(xvf) & !is.na(yv)
            lbl <- if (multi_ds) .trunc_lbl(sprintf("Gain @ %.4g GHz [%s]", fq, ds_nm))
                   else .trunc_lbl(sprintf("Gain @ %.4g GHz", fq))
            p <- p %>% add_trace(type="scattergl", mode="markers",
              x=xvf[ok], y=yv[ok], yaxis="y", name=lbl,
              marker=list(color=col, size=5, opacity=pt_op))
          }
        } else {
          col <- MPAL[(col_off %% length(MPAL)) + 1L]
          ord <- order(df[[x_var]], na.last=NA); dfo <- df[ord, , drop=FALSE]
          xv <- dfo[[x_var]]; yv <- dfo$gain_db; ok <- !is.na(xv) & !is.na(yv)
          lbl <- if (multi_ds) paste0("Gain [", ds_nm, "]") else "Gain (dB)"
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[ok], y=yv[ok], yaxis="y", name=lbl,
            marker=list(color=col, size=5, opacity=pt_op))
        }
      }
      y2_lbl <- ""
      if (y2_v != "none" && y2_v %in% names(df)) {
        y2_lbl <- switch(y2_v, pae_pct="PAE (%)", de_pct="DE (%)",
                                pout_dbm="Pout (dBm)", pout_w="Pout (W)", y2_v)
        if (multi_f) {
          for (fi in seq_along(freqs)) {
            fq <- freqs[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
            dff <- df[!is.na(df$freq_ghz) & df$freq_ghz == fq, , drop=FALSE]
            xvf <- dff[[x_var]]; yv2 <- dff[[y2_v]]; ok2 <- !is.na(xvf) & !is.na(yv2)
            lbl2 <- if (multi_ds) .trunc_lbl(sprintf("%s @ %.4g GHz [%s]", y2_lbl, fq, ds_nm))
                    else .trunc_lbl(sprintf("%s @ %.4g GHz", y2_lbl, fq))
            p <- p %>% add_trace(type="scattergl", mode="markers",
              x=xvf[ok2], y=yv2[ok2], yaxis="y2", name=lbl2,
              marker=list(color=col, size=5, symbol="circle-open", opacity=pt_op))
          }
        } else {
          col <- MPAL[(col_off %% length(MPAL)) + 1L]
          ord <- order(df[[x_var]], na.last=NA); dfo <- df[ord, , drop=FALSE]
          xv <- dfo[[x_var]]; yv2 <- dfo[[y2_v]]; ok2 <- !is.na(xv) & !is.na(yv2)
          lbl2 <- if (multi_ds) paste0(y2_lbl, " [", ds_nm, "]") else y2_lbl
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[ok2], y=yv2[ok2], yaxis="y2", name=lbl2,
            marker=list(color=col, size=5, symbol="circle-open", opacity=pt_op))
        }
      }
      # Back-off line per dataset (use first dataset only to avoid clutter)
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && !is.null(df$pout_dbm)) {
        pmax <- suppressWarnings(max(df$pout_dbm, na.rm=TRUE))
        if (is.finite(pmax)) shapes_list[[1]] <- list(
          type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(freqs), 1L)
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
'@

# ── New Perf Eff (multi-dataset outer loop) ───────────────────────────────────
$newEff = @'
  output$lp_perf_eff_plot <- renderPlotly({
    sel_ids <- input$lp_perf_dataset_selector
    x_var   <- input$lp_perf_x_var  %||% "pout_dbm"
    y2_v    <- input$lp_perf_eff_y2 %||% "none"
    pt_op   <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
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
      ds_nm <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      need  <- unique(c(x_var, "pae_pct", "de_pct", "freq_ghz", if (y2_v != "none") y2_v))
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !x_var %in% names(df)) { col_off <- col_off + 3L; next }
      freqs  <- if ("freq_ghz" %in% names(df)) sort(unique(na.omit(df$freq_ghz))) else numeric(0)
      multi_f <- length(freqs) > 1
      if (multi_f) {
        for (fi in seq_along(freqs)) {
          fq  <- freqs[fi]; col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          dff <- df[!is.na(df$freq_ghz) & df$freq_ghz == fq, , drop=FALSE]
          xvf <- dff[[x_var]]
          for (ev in EFF_VARS) {
            if (!ev %in% names(dff)) next
            yv <- dff[[ev]]; ok <- !is.na(xvf) & !is.na(yv)
            if (!any(ok)) next
            lbl <- if (multi_ds) .trunc_lbl(sprintf("%s @ %.4g GHz [%s]", EFF_LBLS[ev], fq, ds_nm))
                   else .trunc_lbl(sprintf("%s @ %.4g GHz", EFF_LBLS[ev], fq))
            p <- p %>% add_trace(type="scattergl", mode="markers",
              x=xvf[ok], y=yv[ok], yaxis="y", name=lbl,
              marker=list(color=col, size=5, symbol=EFF_SYMS[ev], opacity=pt_op))
          }
        }
      } else {
        PAL_EFF <- c(MPAL[(col_off %% length(MPAL)) + 1L],
                     MPAL[((col_off + 1L) %% length(MPAL)) + 1L])
        ic <- 1L
        ord <- order(df[[x_var]], na.last=NA); dfo <- df[ord, , drop=FALSE]
        xv  <- dfo[[x_var]]
        for (ev in EFF_VARS) {
          if (!ev %in% names(dfo)) { ic <- ic+1L; next }
          yv <- dfo[[ev]]; ok <- !is.na(xv) & !is.na(yv)
          cl <- PAL_EFF[(ic-1L)%%2L+1L]; ic <- ic+1L
          lbl <- if (multi_ds) paste0(EFF_LBLS[ev], " [", ds_nm, "]") else EFF_LBLS[ev]
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[ok], y=yv[ok], yaxis="y", name=lbl,
            marker=list(color=cl, size=5, symbol=EFF_SYMS[ev], opacity=pt_op))
        }
      }
      if (y2_v != "none" && y2_v %in% names(df) && di == 1L) {
        y2_lbl <- switch(y2_v, gain_db="Gain (dB)", pout_dbm="Pout (dBm)",
                                pout_w="Pout (W)", y2_v)
        ord <- order(df[[x_var]], na.last=NA); dfo <- df[ord, , drop=FALSE]
        xv <- dfo[[x_var]]; yv2 <- dfo[[y2_v]]; ok2 <- !is.na(xv) & !is.na(yv2)
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok2], y=yv2[ok2], yaxis="y2", name=y2_lbl,
          marker=list(color="#ff7f11", size=5, symbol="circle-open", opacity=pt_op))
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && !is.null(df$pout_dbm)) {
        pmax <- suppressWarnings(max(df$pout_dbm, na.rm=TRUE))
        if (is.finite(pmax)) shapes_list[[1]] <- list(
          type="line", x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(freqs), 1L)
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
'@

# ── Smith S multi-dataset (keep show_gin / improved hover from upstream) ──────
$newSmithS = @'
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
        r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 20L)
      } else ""
      df <- .get_df(id, cols = c("gs_r","gs_i","gin_r","gin_i","pout_dbm","gain_db","pae_pct",
                                  if (show_harm) c("gs2_r","gs2_i","gs3_r","gs3_i")))
      if (is.null(df) || !"gs_r" %in% names(df)) next
      if (px_db_p > 0.01 && "gain_db" %in% names(df)) {
        g_lin <- max(df$gain_db[seq_len(min(5L, nrow(df)))], na.rm=TRUE)
        compr <- g_lin - df$gain_db
        df    <- df[!is.na(compr) & abs(compr - px_db_p) <= px_tol_p, , drop=FALSE]
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
'@

# ── Smith L multi-dataset ─────────────────────────────────────────────────────
$newSmithL = @'
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
        r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 20L)
      } else ""
      df <- .get_df(id, cols = c("gl_r","gl_i","pout_dbm","gain_db","pae_pct",
                                  if (show_harm) c("gl2_r","gl2_i","gl3_r","gl3_i")))
      if (is.null(df) || !"gl_r" %in% names(df)) next
      if (px_db_p > 0.01 && "gain_db" %in% names(df)) {
        g_lin <- max(df$gain_db[seq_len(min(5L, nrow(df)))], na.rm=TRUE)
        compr <- g_lin - df$gain_db
        df    <- df[!is.na(compr) & abs(compr - px_db_p) <= px_tol_p, , drop=FALSE]
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
'@

# ── Nose MXE multi-dataset ────────────────────────────────────────────────────
$newNoseMXE = @'
  output$lp_nose_mxe <- renderPlotly({
    sel_ids <- input$lp_nose_dataset_selector
    x_var   <- input$lp_nose_x_pw  %||% "pout_dbm"
    z0      <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    pt_op   <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
               title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#1f77b4","#ff7f11","#2ca02c","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); col_off <- 0L; shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      need  <- c("gl_r","gl_i","pae_pct","de_pct","gain_db","pout_dbm","pin_dbm","pout_w","freq_ghz")
      df    <- .get_df(id, cols = need)
      if (is.null(df)) next
      eff_col <- if ("pae_pct" %in% names(df) && any(!is.na(df$pae_pct))) "pae_pct" else
                 if ("de_pct"  %in% names(df) && any(!is.na(df$de_pct)))  "de_pct"  else NULL
      if (is.null(eff_col)) next
      eff_lbl <- if (eff_col == "pae_pct") "PAE (%)" else "DE (%)"
      pts <- .nose_reduce(df, eff_col)
      if (is.null(pts) || !x_var %in% names(pts)) next
      freqs <- if ("freq_ghz" %in% names(pts)) sort(unique(na.omit(pts$freq_ghz))) else numeric(0)
      multi_f <- length(freqs) > 1
      zl   <- .gamma_to_z(pts$gl_r, pts$gl_i, z0)
      pdbm <- if ("pout_dbm" %in% names(pts)) pts$pout_dbm else rep(NA_real_, nrow(pts))
      gdb  <- if ("gain_db"  %in% names(pts)) pts$gain_db  else rep(NA_real_, nrow(pts))
      htxt <- sprintf(
        "\u0393L = %.3f%+.3fj<br>ZL = %.1f%+.1fj \u03a9<br>Pout = %.1f dBm<br>%s = %.1f%%<br>Gain = %.2f dB",
        pts$gl_r, pts$gl_i, zl$r, zl$x, pdbm, eff_lbl, pts[[eff_col]], gdb)
      xv <- pts[[x_var]]; yv <- pts[[eff_col]]; ok <- !is.na(xv) & !is.na(yv)
      if (multi_f) {
        for (fi in seq_along(freqs)) {
          fq  <- freqs[fi]; sel <- ok & !is.na(pts$freq_ghz) & pts$freq_ghz == fq
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          lbl <- if (multi_ds) .trunc_lbl(sprintf("%.4g GHz [%s]", fq, ds_nm))
                 else .trunc_lbl(sprintf("%.4g GHz", fq))
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[sel], y=yv[sel], name=lbl,
            marker=list(color=col, size=8, opacity=pt_op,
                        line=list(color="rgba(255,255,255,0.4)", width=0.8)),
            hovertext=htxt[sel], hoverinfo="text")
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        lbl <- if (multi_ds) paste0(eff_lbl, " [", ds_nm, "]") else eff_lbl
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], name=lbl,
          marker=list(color=col, size=8, opacity=pt_op,
                      line=list(color="rgba(255,255,255,0.4)", width=0.8)),
          hovertext=htxt[ok], hoverinfo="text")
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && any(!is.na(xv))) {
        pmax <- max(xv, na.rm=TRUE)
        if (is.finite(pmax)) shapes_list[[1]] <- list(type="line",
          x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(freqs), 1L)
    }
    xl <- switch(x_var, pout_dbm="Pout (dBm)", pin_dbm="Pin (dBm)", pout_w="Pout (W)", x_var)
    eff_lbl_axis <- if (all(sapply(sel_ids, function(i) {
      df <- .get_df(i, cols = "de_pct")
      !is.null(df) && "de_pct" %in% names(df) && any(!is.na(df$de_pct))
    }))) "DE (%)" else "PAE (%)"
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      xaxis=list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis=list(title=eff_lbl_axis, color="#1f77b4", showgrid=TRUE,
                 gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#1f77b4")),
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text=paste0("Efficiency Nose \u2014 MXE per load point vs ", xl),
                 font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=20, t=40, b=50))
  })
'@

# ── Nose XY (Gain Nose) multi-dataset ─────────────────────────────────────────
$newNoseXY = @'
  output$lp_nose_xy <- renderPlotly({
    sel_ids <- input$lp_nose_dataset_selector
    x_var   <- input$lp_nose_x_pw  %||% "pout_dbm"
    z0      <- as.numeric(input$lp_nose_z0_norm %||% 50)
    if (!is.finite(z0) || z0 <= 0) z0 <- 50
    pt_op   <- min(1, max(0.1, as.numeric(input$lp_point_opacity %||% 0.75)))
    bo_db   <- as.numeric(input$lp_backoff_db %||% 6)
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
               title=list(text=m, font=list(color="#aaa")))
    if (is.null(sel_ids) || length(sel_ids) == 0) return(ep("Select a dataset"))
    MPAL     <- c("#2ca02c","#ff7f11","#1f77b4","#d62728","#9467bd",
                  "#8c564b","#e377c2","#17becf","#bcbd22","#7f7f7f")
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly(); col_off <- 0L; shapes_list <- list()
    for (di in seq_along(sel_ids)) {
      id    <- sel_ids[di]
      ds_nm <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      need  <- c("gl_r","gl_i","gain_db","pae_pct","de_pct","pout_dbm","pin_dbm","pout_w","freq_ghz")
      df    <- .get_df(id, cols = need)
      if (is.null(df) || !"gain_db" %in% names(df) || all(is.na(df$gain_db))) next
      pts <- .nose_reduce(df, "gain_db")
      if (is.null(pts) || !x_var %in% names(pts)) next
      eff_col <- if ("pae_pct" %in% names(pts) && any(!is.na(pts$pae_pct))) "pae_pct" else
                 if ("de_pct"  %in% names(pts) && any(!is.na(pts$de_pct)))  "de_pct"  else NULL
      eff_lbl <- if (!is.null(eff_col)) switch(eff_col, pae_pct="PAE (%)", de_pct="DE (%)") else "Eff"
      eff_v   <- if (!is.null(eff_col)) pts[[eff_col]] else rep(NA_real_, nrow(pts))
      freqs   <- if ("freq_ghz" %in% names(pts)) sort(unique(na.omit(pts$freq_ghz))) else numeric(0)
      multi_f <- length(freqs) > 1
      zl   <- .gamma_to_z(pts$gl_r, pts$gl_i, z0)
      pdbm <- if ("pout_dbm" %in% names(pts)) pts$pout_dbm else rep(NA_real_, nrow(pts))
      htxt <- sprintf(
        "\u0393L = %.3f%+.3fj<br>ZL = %.1f%+.1fj \u03a9<br>Pout = %.1f dBm<br>Gain = %.2f dB<br>%s = %.1f%%",
        pts$gl_r, pts$gl_i, zl$r, zl$x, pdbm, pts$gain_db, eff_lbl, eff_v)
      xv <- pts[[x_var]]; yv <- pts$gain_db; ok <- !is.na(xv) & !is.na(yv)
      if (multi_f) {
        for (fi in seq_along(freqs)) {
          fq  <- freqs[fi]; sel <- ok & !is.na(pts$freq_ghz) & pts$freq_ghz == fq
          col <- MPAL[((col_off + fi - 1L) %% length(MPAL)) + 1L]
          lbl <- if (multi_ds) .trunc_lbl(sprintf("%.4g GHz [%s]", fq, ds_nm))
                 else .trunc_lbl(sprintf("%.4g GHz", fq))
          p <- p %>% add_trace(type="scattergl", mode="markers",
            x=xv[sel], y=yv[sel], name=lbl,
            marker=list(color=col, size=8, opacity=pt_op,
                        line=list(color="rgba(255,255,255,0.4)", width=0.8)),
            hovertext=htxt[sel], hoverinfo="text")
        }
      } else {
        col <- MPAL[(col_off %% length(MPAL)) + 1L]
        lbl <- if (multi_ds) paste0("Gain [", ds_nm, "]") else "Gain (dB)"
        p <- p %>% add_trace(type="scattergl", mode="markers",
          x=xv[ok], y=yv[ok], name=lbl,
          marker=list(color=col, size=8, opacity=pt_op,
                      line=list(color="rgba(255,255,255,0.4)", width=0.8)),
          hovertext=htxt[ok], hoverinfo="text")
      }
      if (di == 1L && x_var == "pout_dbm" && is.finite(bo_db) && bo_db >= 0 && any(!is.na(xv))) {
        pmax <- max(xv, na.rm=TRUE)
        if (is.finite(pmax)) shapes_list[[1]] <- list(type="line",
          x0=pmax-bo_db, x1=pmax-bo_db, y0=0, y1=1, yref="paper",
          line=list(color="rgba(200,200,200,0.35)", width=1.5, dash="dash"))
      }
      col_off <- col_off + max(length(freqs), 1L)
    }
    xl <- switch(x_var, pout_dbm="Pout (dBm)", pin_dbm="Pin (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      shapes=if (length(shapes_list) > 0) shapes_list else NULL,
      xaxis=list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis=list(title="Gain (dB)", color="#2ca02c", showgrid=TRUE,
                 gridcolor="rgba(100,100,100,0.25)", tickfont=list(color="#2ca02c")),
      legend=list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title=list(text=paste0("Gain Nose \u2014 MXG per load point vs ", xl),
                 font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=20, t=40, b=50))
  })
'@

# ── AM-AM multi-dataset ───────────────────────────────────────────────────────
$newAMAM = @'
  output$lp_amam_plot <- renderPlotly({
    sel_ids <- input$lp_ampm_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) sel_ids <- input$lp_xy_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset", font=list(color="#aaa"))))
    x_var <- input$lp_ampm_x_var %||% "pin_dbm"
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_col <- PALETTE[((di - 1L) %% length(PALETTE)) + 1L]
      ds_nm  <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      df <- .get_df(id, cols = c("pin_dbm","pout_dbm","pout_w","gain_db"))
      if (is.null(df) || !"gain_db" %in% names(df)) next
      if (!x_var %in% names(df)) next
      ord <- order(df[[x_var]], na.last=NA); df <- df[ord, , drop=FALSE]
      xv     <- df[[x_var]]; yv_raw <- df$gain_db
      ok     <- !is.na(xv) & !is.na(yv_raw)
      g_lin  <- max(yv_raw[ok][seq_len(min(5L, sum(ok)))], na.rm=TRUE)
      yv     <- yv_raw - g_lin
      ds_aa  <- .lttb(xv[ok], yv[ok], 500L)
      lbl <- if (multi_ds) paste0("AM-AM [", ds_nm, "]") else "AM-AM compression (dB)"
      p <- p %>% add_trace(type="scattergl", mode="markers",
        x=ds_aa$x, y=ds_aa$y, name=lbl, opacity=0.85,
        marker=list(color=ds_col, size=5, opacity=0.75))
      ci <- which(yv[ok] <= -1)
      if (length(ci) > 0) {
        ci1  <- ci[1L]
        plbl <- if (multi_ds) paste0("P1dB [", ds_nm, "]") else "P1dB"
        p    <- p %>% add_trace(type="scatter", mode="markers+text",
          x=xv[ok][ci1], y=yv[ok][ci1],
          text=sprintf("P1dB\n%.1f dBm", xv[ok][ci1]), textposition="top right",
          textfont=list(color=ds_col, size=10),
          marker=list(color=ds_col, size=12, symbol="circle",
                      line=list(color="white", width=2)),
          name=plbl, showlegend=TRUE)
      }
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-AM compression (dB)", color="#aaa",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      legend = list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-AM vs ", xl), font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=30, t=40, b=50))
  })
'@

# ── AM-PM multi-dataset ───────────────────────────────────────────────────────
$newAMPM = @'
  output$lp_ampm_plot <- renderPlotly({
    sel_ids <- input$lp_ampm_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) sel_ids <- input$lp_xy_dataset_selector
    if (is.null(sel_ids) || length(sel_ids) == 0) return(
      plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
        title=list(text="Select a dataset", font=list(color="#aaa"))))
    x_var <- input$lp_ampm_x_var %||% "pin_dbm"
    ep <- function(m) plot_ly() %>% layout(paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
                        title=list(text=m, font=list(color="#aaa")))
    multi_ds <- length(sel_ids) > 1L
    p <- plot_ly()
    for (di in seq_along(sel_ids)) {
      id     <- sel_ids[di]
      ds_col <- PALETTE[((di - 1L) %% length(PALETTE)) + 1L]
      ds_nm  <- if (multi_ds) { r <- lp_datasets()[[id]]; .short_name(r$filename %||% id, 18L) } else ""
      df <- .get_df(id, cols = c("pin_dbm","pout_dbm","pout_w","am_pm"))
      if (is.null(df) || !"am_pm" %in% names(df) || all(is.na(df$am_pm))) next
      if (!x_var %in% names(df)) next
      ord <- order(df[[x_var]], na.last=NA); df <- df[ord, , drop=FALSE]
      xv <- df[[x_var]]; yv <- df$am_pm; ok <- !is.na(xv) & !is.na(yv)
      ds_pm <- .lttb(xv[ok], yv[ok], 500L)
      lbl <- if (multi_ds) paste0("AM-PM [", ds_nm, "]") else "AM-PM (\u00b0)"
      p <- p %>% add_trace(type="scattergl", mode="lines+markers",
        x=ds_pm$x, y=ds_pm$y, name=lbl, opacity=0.85,
        line=list(color=ds_col, width=2),
        marker=list(color=ds_col, size=5, opacity=0.60))
    }
    xl <- switch(x_var, pin_dbm="Pin (dBm)", pout_dbm="Pout (dBm)", pout_w="Pout (W)", x_var)
    p %>% layout(
      paper_bgcolor="#1b1b2b", plot_bgcolor="#1b1b2b",
      xaxis  = list(title=xl, color="#aaa", showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)"),
      yaxis  = list(title="AM-PM (\u00b0)", color="#1f77b4",
                    showgrid=TRUE, gridcolor="rgba(100,100,100,0.25)",
                    tickfont=list(color="#1f77b4")),
      legend = list(font=list(color="#aaa"), bgcolor="rgba(0,0,0,0.3)"),
      title  = list(text=paste0("AM-PM vs ", xl), font=list(color="#eee", size=13)),
      font=list(color="#aaa"), margin=list(l=65, r=30, t=40, b=50))
  })
'@

# ── Helper: split here-string into lines, handle PS here-string leading/trailing newline
function Get-Lines([string]$body) { $body -split '\r?\n' }

$msLines    = Get-Lines $newMakeSelector
$msCalls    = Get-Lines $newMsCalls
$perfSel    = Get-Lines $newPerfSel
$xyLines    = Get-Lines $newXY
$gainLines  = Get-Lines $newGain
$effLines   = Get-Lines $newEff
$ssLines    = Get-Lines $newSmithS
$slLines    = Get-Lines $newSmithL
$nmLines    = Get-Lines $newNoseMXE
$nxLines    = Get-Lines $newNoseXY
$aaLines    = Get-Lines $newAMAM
$apLines    = Get-Lines $newAMPM

# ── Build the new file ────────────────────────────────────────────────────────
$out = [System.Collections.Generic.List[string]]::new()

# 1) Before .make_selector function (lines 0..ms_func_start-1)
$out.AddRange([string[]]$lines[0..($ms_func_start - 1)])

# 2) New .make_selector function
$out.AddRange([string[]]$msLines)

# 3) Between end of function and .make_selector calls (ms_func_end+1..ms_calls_start-1)
#    ms_func_end=442 (closing '}'), ms_calls_start=443 (blank line before calls)
#    We skip that range entirely since new calls are in $msCalls
$out.AddRange([string[]]$msCalls)

# 4) After calls (ms_calls_end+1=451) up to XY plot comment (xy_start-1 = 819)
#    We need to check if there's a perf selector call around line 900-902 to replace
$out.AddRange([string[]]$lines[451..($xy_start - 2)])  # up to one line before output$lp_xy_plot

# 5) New XY plot
$out.AddRange([string[]]$xyLines)

# 6) Between xy_end+1 and the Performance tab selector comment (perf_sel_start=900, 0-based)
#    xy_end=898, so gap = lines 899..(perf_sel_start-1 = 899) = just line 899 (blank)
$out.AddRange([string[]]$lines[($xy_end + 1)..($perf_sel_start - 1)])

# 7) Replace perf selector comment+call with new version (perf_sel_start..perf_sel_end = 900..902)
$out.AddRange([string[]]$perfSel)

# 8) Between perf selector end (903) and gain plot start (914)
$out.AddRange([string[]]$lines[($perf_sel_end + 1)..($gain_start - 1)])

# 9) New Gain plot
$out.AddRange([string[]]$gainLines)

# 10) Gap between gain end (988) and eff start (991)
$out.AddRange([string[]]$lines[($gain_end + 1)..($eff_start - 1)])

# 11) New Eff plot
$out.AddRange([string[]]$effLines)

# 12) Gap between eff end (1066) and Smith S start (1069)
$out.AddRange([string[]]$lines[($eff_end + 1)..($ss_start - 1)])

# 13) New Smith S
$out.AddRange([string[]]$ssLines)

# 14) Gap between Smith S end (1159) and Smith L start (1162)
$out.AddRange([string[]]$lines[($ss_end + 1)..($sl_start - 1)])

# 15) New Smith L
$out.AddRange([string[]]$slLines)

# 16) Gap between Smith L end (1233) and Nose MXE start (1238)
$out.AddRange([string[]]$lines[($sl_end + 1)..($nm_start - 1)])

# 17) New Nose MXE
$out.AddRange([string[]]$nmLines)

# 18) Gap between Nose MXE end (1319) and Nose XY start (1324)
$out.AddRange([string[]]$lines[($nm_end + 1)..($nx_start - 1)])

# 19) New Nose XY
$out.AddRange([string[]]$nxLines)

# 20) Table helpers section (nx_end+1=1407 up to tc_line=1573)
$out.AddRange([string[]]$lines[($nx_end + 1)..($tc_line - 1)])

# 21) Patched CSV line (replacing: .get_df(input$lp_table_dataset_selector))
$tcLine = $lines[$tc_line] -replace [regex]::Escape('.get_df(input$lp_table_dataset_selector)'),
                                   '.get_df(input$lp_table_dataset_selector[1L])'
$out.Add($tcLine)

# 22) Lines after csv up to AM-AM start
$out.AddRange([string[]]$lines[($tc_line + 1)..($aa_start - 1)])

# 23) New AM-AM
$out.AddRange([string[]]$aaLines)

# 24) Gap between AM-AM end (1634) and AM-PM start (1637)
$out.AddRange([string[]]$lines[($aa_end + 1)..($ap_start - 1)])

# 25) New AM-PM
$out.AddRange([string[]]$apLines)

# 26) Everything after AM-PM
$out.AddRange([string[]]$lines[($ap_end + 1)..($lines.Count - 1)])

# ── Apply table selector [1L] patches ────────────────────────────────────────
$finalArr = $out.ToArray()
foreach ($li in $tbl_sel_lines) {
  # Adjust line index for the offset caused by replacements
  # Note: tbl_sel_lines are 0-based in the ORIGINAL file;
  # we patch them inline in the output array after building it.
  # However since table section is AFTER all replacements above (line 1409+),
  # the offsets have shifted. Let's patch by content match instead.
}
# Simpler: do a global regex replace on the output array for the pattern
for ($i = 0; $i -lt $finalArr.Count; $i++) {
  if ($finalArr[$i] -match 'id\s*<-\s*input\$lp_table_dataset_selector\b' -and
      $finalArr[$i] -notmatch '\[1L\]') {
    $finalArr[$i] = $finalArr[$i] -replace 'input\$lp_table_dataset_selector\b',
                                           'input$lp_table_dataset_selector[1L]'
  }
}

[System.IO.File]::WriteAllLines($file, $finalArr, [System.Text.Encoding]::UTF8)
Write-Host "Done. Lines: $($finalArr.Count) (was $($lines.Count))"
