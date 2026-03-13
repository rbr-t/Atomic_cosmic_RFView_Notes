# =============================================================================
# kb_query.R
# Search, filter and presentation helpers for the device knowledge base.
#
# All functions accept the flat data.frame returned by kb_load_all() and
# return filtered subsets or formatted outputs.
# =============================================================================

# ── Filter ─────────────────────────────────────────────────────────────────────

#' Filter the device table by one or more criteria.
#'
#' All criteria are AND-combined.  Pass NULL to skip a criterion.
#'
#' @param df               data.frame from kb_load_all()
#' @param manufacturer     character vector — exact match(es) (e.g. "Ampleon")
#' @param technology       character vector — e.g. c("LDMOS","GaN-SiC")
#' @param freq_mhz         numeric — device must cover this single frequency
#' @param freq_min_mhz     numeric — device upper edge >= this value
#' @param freq_max_mhz     numeric — device lower edge <= this value
#' @param pout_min_w       numeric — minimum rated output power (CW or pulse)
#' @param pout_max_w       numeric — maximum rated output power
#' @param vdd_v            numeric — supply voltage (±5 V tolerance)
#' @param application      character vector — any of these in application field
#' @param role             character vector — any of these in role field
#' @param status           "active" | "EOL" | "NRND" | "all"
#' @param confidence       character vector — knowledge_confidence levels to include
#' @param tags             character vector — any of these tags present
#' @param exclude_placeholder logical — skip records whose part_number starts with "PLACEHOLDER"
#' @return Filtered data.frame
kb_filter <- function(df,
                      manufacturer        = NULL,
                      technology          = NULL,
                      freq_mhz            = NULL,
                      freq_min_mhz        = NULL,
                      freq_max_mhz        = NULL,
                      pout_min_w          = NULL,
                      pout_max_w          = NULL,
                      vdd_v               = NULL,
                      application         = NULL,
                      role                = NULL,
                      status              = "active",
                      confidence          = NULL,
                      tags                = NULL,
                      exclude_placeholder = TRUE) {

  if (is.null(df) || nrow(df) == 0) return(df)

  mask <- rep(TRUE, nrow(df))

  if (exclude_placeholder)
    mask <- mask & !grepl("^PLACEHOLDER", df$part_number, ignore.case = TRUE)

  if (!is.null(manufacturer) && length(manufacturer) > 0)
    mask <- mask & tolower(df$manufacturer) %in% tolower(manufacturer)

  if (!is.null(technology) && length(technology) > 0)
    mask <- mask & tolower(df$technology) %in% tolower(technology)

  if (!is.null(vdd_v))
    mask <- mask & !is.na(df$vdd_v) & abs(df$vdd_v - vdd_v) <= 5

  # Frequency filters
  if (!is.null(freq_mhz))
    mask <- mask &
      !is.na(df$freq_min_mhz) & !is.na(df$freq_max_mhz) &
      df$freq_min_mhz <= freq_mhz & df$freq_max_mhz >= freq_mhz

  if (!is.null(freq_min_mhz))
    mask <- mask & !is.na(df$freq_max_mhz) & df$freq_max_mhz >= freq_min_mhz

  if (!is.null(freq_max_mhz))
    mask <- mask & !is.na(df$freq_min_mhz) & df$freq_min_mhz <= freq_max_mhz

  # Power filters (check either CW or pulse)
  pout_any <- pmax(df$pout_w_cw %||% NA_real_,
                   df$pout_w_pulse %||% NA_real_,
                   na.rm = TRUE)
  if (!is.null(pout_min_w))
    mask <- mask & !is.na(pout_any) & pout_any >= pout_min_w
  if (!is.null(pout_max_w))
    mask <- mask & !is.na(pout_any) & pout_any <= pout_max_w

  # Status filter
  if (!is.null(status) && status != "all")
    mask <- mask & !is.na(df$status) & tolower(df$status) == tolower(status)

  # Confidence filter
  if (!is.null(confidence) && length(confidence) > 0)
    mask <- mask & tolower(df$knowledge_confidence) %in% tolower(confidence)

  # Array field helpers — check semi-colon-separated values
  .any_match <- function(col_values, query) {
    sapply(col_values, function(v) {
      if (is.na(v)) return(FALSE)
      device_vals <- tolower(trimws(strsplit(v, ";")[[1]]))
      any(tolower(trimws(query)) %in% device_vals)
    })
  }

  if (!is.null(application) && length(application) > 0)
    mask <- mask & .any_match(df$application, application)

  if (!is.null(role) && length(role) > 0)
    mask <- mask & .any_match(df$role, role)

  if (!is.null(tags) && length(tags) > 0)
    mask <- mask & .any_match(df$tags, tags)

  df[mask, , drop = FALSE]
}

# ── Free-text search ──────────────────────────────────────────────────────────

#' Full-text search across part number, family, tags, notes, application etc.
#'
#' @param df     data.frame from kb_load_all()
#' @param query  Character string; case-insensitive substring match
#' @return Filtered data.frame
kb_search <- function(df, query) {
  if (is.null(df) || nrow(df) == 0) return(df)
  query <- trimws(query)
  if (!nzchar(query)) return(df)

  search_cols <- intersect(
    c("part_number", "manufacturer", "family", "series", "technology",
      "package", "tags", "application", "use_case", "role", "notes",
      "knowledge_confidence"),
    names(df)
  )

  mask <- apply(
    df[, search_cols, drop = FALSE], 1,
    function(row) any(grepl(query, row, ignore.case = TRUE, fixed = FALSE))
  )
  df[mask, , drop = FALSE]
}

# ── Display helpers ───────────────────────────────────────────────────────────

#' Return a clean display table for DT rendering in the app.
#'
#' Selects and renames key columns, rounds numerics, replaces NA with "—".
kb_display_table <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(data.frame())

  display <- data.frame(
    `Part #`      = df$part_number      %||% "—",
    `Maker`       = df$manufacturer     %||% "—",
    `Tech`        = df$technology       %||% "—",
    `Gen`         = df$generation       %||% "—",
    `Package`     = df$package          %||% "—",
    `Vdd (V)`     = .fmt_num(df$vdd_v),
    `Fmin (MHz)`  = .fmt_num(df$freq_min_mhz),
    `Fmax (MHz)`  = .fmt_num(df$freq_max_mhz),
    `Pout/CW (W)` = .fmt_num(df$pout_w_cw),
    `Pout/P (W)`  = .fmt_num(df$pout_w_pulse),
    `Gain (dB)`   = .fmt_num(df$gain_db),
    `DE (%)`      = .fmt_num(df$drain_eff_pct),
    `Ropt (Ω)`    = .fmt_num(df$ropt_ohm),
    `Xopt (Ω)`    = .fmt_num(df$xopt_ohm),
    `Status`      = df$status           %||% "—",
    `Confidence`  = df$knowledge_confidence %||% "—",
    `device_id`   = df$device_id        %||% "",   # hidden key column
    stringsAsFactors = FALSE, check.names = FALSE
  )
  display
}

.fmt_num <- function(x, digits = 1) {
  ifelse(is.na(x), "—", as.character(round(x, digits)))
}

# ── Device detail card ────────────────────────────────────────────────────────

#' Build an HTML detail card for a single device record.
#'
#' @param dev   Named list (from kb_get_raw_device) or one-row data.frame
#' @return shiny tagList with formatted device information
kb_device_card <- function(dev) {
  if (is.null(dev)) {
    return(div(p(style = "color:#888;",
      "Select a device in the table to see details.")))
  }

  # Accept both raw list (from JSON) and data.frame row
  if (is.data.frame(dev)) dev <- as.list(dev[1, ])

  .v  <- function(x) {
    v <- dev[[x]]
    if (is.null(v) || length(v) == 0) return("—")
    if (length(v) == 1 && (identical(v, "NA") || isTRUE(is.na(v)))) return("—")
    paste(as.character(v), collapse = "; ")
  }
  .nv <- function(x, unit = "") {
    v <- dev[[x]]
    if (is.null(v) || length(v) == 0) return("—")
    if (length(v) != 1 || isTRUE(is.na(v)) || identical(as.character(v), "NA")) return("—")
    paste0(round(as.numeric(v), 2), if (nzchar(unit)) paste0(" ", unit) else "")
  }

  conf <- .v("knowledge_confidence")
  conf_col <- switch(conf,
    "high"   = "#2ca02c",
    "medium" = "#ff7f11",
    "low"    = "#d62728",
    "#888"
  )
  conf_icon <- switch(conf,
    "high"   = "\u2713\u2713",
    "medium" = "\u2713",
    "low"    = "\u26a0",
    "?"
  )

  ds_url <- .v("datasheet_url")
  ds_link <- if (ds_url != "—" && nzchar(ds_url)) {
    tags$a(href = ds_url, target = "_blank",
           style = "color:#ff7f11;", icon("external-link-alt"), " Open datasheet")
  } else {
    tags$span(style = "color:#666;", "— no URL on file")
  }

  freq_str <- paste0(.nv("freq_min_mhz", ""), "–", .nv("freq_max_mhz", "MHz"))
  pout_str <- {
    cw  <- dev[["pout_w_cw"]]
    pls <- dev[["pout_w_pulse"]]
    parts <- character(0)
    if (!is.null(cw)  && !is.na(cw)  && cw  != "NA") parts <- c(parts, paste0(round(as.numeric(cw),  0), " W CW"))
    if (!is.null(pls) && !is.na(pls) && pls != "NA") parts <- c(parts, paste0(round(as.numeric(pls), 0), " W pulse"))
    if (length(parts) == 0) "—" else paste(parts, collapse = " / ")
  }

  imp_str <- {
    r <- dev[["ropt_ohm"]]; x <- dev[["xopt_ohm"]]
    r_ok <- !is.null(r) && !is.na(r) && r != "NA"
    x_ok <- !is.null(x) && !is.na(x) && x != "NA"
    if (r_ok && x_ok) {
      xv <- as.numeric(x)
      paste0(round(as.numeric(r), 2), if (xv >= 0) "+" else "", round(xv, 2), "j Ω")
    } else "— (see datasheet)"
  }

  # ── Build tab contents ────────────────────────────────────────────────────
  imp_disabled <- if (imp_str == "— (see datasheet)") "disabled" else NULL

  tab_overview <- tabPanel("Overview",
    div(style = "padding:8px 0 4px 0;",
      div(class = "kb-detail-section",
        tags$b("Optimum Load Impedance (Ropt)"), br(),
        span(style = "font-size:15px; color:#ff7f11; font-family:monospace;", imp_str), br(),
        tags$small(style = "color:#666;", "Ref plane: ", .v("impedance_ref_plane"))
      ),
      div(class = "kb-detail-section",
        tags$b("Supply / Bias"), br(),
        span(style = "color:#aaa; font-size:12px;",
          "Vdd = ", .nv("vdd_v", "V"),
          {
            vr <- dev[["vdd_range_v"]]
            if (!is.null(vr) && length(vr) == 2)
              span(style = "color:#666; font-size:11px;",
                   paste0(" (", vr[[1]], "\u2013", vr[[2]], " V)"))
            else NULL
          },
          "  |  Idq = ", .nv("idd_q_ma", "mA"))
      ),
      if (.v("topology") != "\u2014") div(class = "kb-detail-section",
        tags$b("Topology"), br(),
        span(style = "color:#aaa; font-size:12px;",
             gsub(";", "  \u00b7  ", .v("topology")))),
      div(class = "kb-detail-section",
        tags$b("Applications"), br(),
        span(style = "color:#aaa; font-size:12px;",
          gsub(";", "  \u00b7  ", .v("application")))
      ),
      div(class = "kb-detail-section",
        tags$b("Typical role in PA chain"), br(),
        span(style = "color:#aaa; font-size:12px;",
          gsub(";", "  \u00b7  ", .v("role")))
      ),
      if (.v("notes") != "\u2014") div(class = "kb-detail-section",
        tags$b("Engineering notes"),
        p(style = "color:#aaa; font-size:12px; margin-top:4px;", .v("notes"))),
      div(class = "kb-detail-section",
        tags$b("Datasheet"), br(), ds_link,
        {
          an <- dev[["app_notes"]]
          if (!is.null(an) && length(an) > 0)
            div(style = "margin-top:6px;",
              tags$b(style = "font-size:12px;", "Application Notes"),
              tags$ul(style = "padding-left:16px; margin:4px 0 0 0;",
                lapply(an, function(a)
                  tags$li(style = "font-size:11px;",
                    tags$a(href = a$url %||% "#", target = "_blank",
                           style = "color:#5bc0de;", a$title %||% "App Note"))
                )
              )
            )
        }
      ),
      div(style = "display:flex; gap:8px; margin-top:16px;",
        actionButton("kb_send_to_smith", "Load Ropt \u2192 Smith Chart",
          icon = icon("bullseye"), class = "btn-primary btn-sm",
          disabled = imp_disabled),
        actionButton("kb_copy_to_lineup", "Add to Lineup Canvas",
          icon = icon("plus"), class = "btn-default btn-sm")
      )
    )
  )

  # ── Assemble tabset card ──────────────────────────────────────────────────
  tagList(
    div(style = "padding:10px 0 0 0;",

      # ── Persistent header (always visible above tabs) ───────────────────
      div(style = "display:flex; align-items:flex-start; gap:10px; margin-bottom:12px;",
        div(style = "flex:1;",
          h4(style = "margin:0; color:#f0f0f0; font-size:18px;", .v("part_number")),
          p(style  = "margin:2px 0 0 0; color:#aaa; font-size:13px;",
            .v("manufacturer"), " \u00b7 ", .v("technology"), " ", .v("generation"),
            " \u00b7 ", .v("package"))
        ),
        div(style = paste0("background:rgba(0,0,0,0.3); border:1px solid ", conf_col,
                           "; border-radius:4px; padding:4px 10px; font-size:11px;",
                           " color:", conf_col, "; white-space:nowrap;"),
          conf_icon, " ", toupper(conf), " confidence"
        )
      ),

      # ── Key metrics strip (always visible) ─────────────────────────────
      div(style = "display:grid; grid-template-columns:repeat(4,1fr); gap:8px; margin-bottom:14px;",
        .stat_box("Frequency", freq_str),
        .stat_box("Output Power", pout_str),
        .stat_box("Gain", paste0(.nv("gain_db"), " dB")),
        .stat_box("DE / PAE", paste0(.nv("drain_eff_pct"), " / ", .nv("pae_pct"), " %"))
      ),

      # ── Tabset ──────────────────────────────────────────────────────────
      tabsetPanel(
        type = "tabs",
        id   = "kb_dev_card_tabs",
        tab_overview,
        tabPanel("DC Specs",        .render_dc_table(dev)),
        tabPanel("RF Performance",  .render_rf_tab(dev)),
        tabPanel("Impedance / LP",  .render_lp_section(dev)),
        tabPanel("Test PCBs / BOM", .render_bom_tab(dev)),
        tabPanel("Package & ESD",   .render_package_tab(dev))
      )
    )
  )
}

.stat_box <- function(label, value) {
  div(style = paste0("background:#1e1e2e; border:1px solid #2a2a3a; border-radius:4px;",
                     " padding:8px 10px; text-align:center;"),
    div(style = "color:#666; font-size:10px; text-transform:uppercase; letter-spacing:0.5px;", label),
    div(style = "color:#f0f0f0; font-size:14px; font-weight:600; margin-top:2px;", value)
  )
}

# Render a single load-pull impedance table.
# lp_data: list of row lists (pass NULL to read dev[["load_pull_table"]]).
# variant_label: text shown in the section header (e.g. "BLP9G0722-20 (flat lead)").
.render_lp_table <- function(dev, lp_data = NULL, variant_label = NULL) {
  lp <- if (!is.null(lp_data)) lp_data else dev[["load_pull_table"]]
  # strip metadata rows (those without numeric freq_mhz)
  lp <- Filter(function(r) !is.null(r$freq_mhz) && !is.na(suppressWarnings(as.numeric(r$freq_mhz))), lp)
  if (is.null(lp) || length(lp) == 0) return(NULL)

  .make_rows <- function(condition_filter, header_label) {
    rows <- Filter(function(r) identical(r$condition, condition_filter), lp)
    if (length(rows) == 0) return(NULL)

    row_tags <- lapply(rows, function(r) {
      freq  <- r$freq_mhz
      zl_r  <- round(r$zl_r, 2)
      zl_x  <- round(r$zl_x, 2)
      zs_r  <- round(r$zs_r, 2)
      zs_x  <- round(r$zs_x, 2)
      pout  <- r$pout_w
      de    <- round(r$drain_eff_pct, 1)
      gp    <- round(r$gain_db, 1)
      zl_str <- paste0(zl_r, if (zl_x >= 0) "+" else "", zl_x, "j")
      zs_str <- paste0(zs_r, if (zs_x >= 0) "+" else "", zs_x, "j")

      js_payload <- sprintf(
        '{\"freq\":%s,\"zl_r\":%s,\"zl_x\":%s,\"zs_r\":%s,\"zs_x\":%s,\"condition\":\"%s\"}',
        freq, zl_r, zl_x, zs_r, zs_x, condition_filter
      )
      send_btn <- tags$td(
        style = "text-align:center; padding:2px 4px;",
        tags$span(
          style  = "cursor:pointer; color:#ff7f11; font-size:13px;",
          title  = "Send ZL to Smith Chart",
          onclick = paste0("Shiny.setInputValue('kb_lp_row_click',", js_payload, ",{priority:'event'});"),
          "\u21d2"
        )
      )
      tags$tr(
        tags$td(style = "padding:2px 6px; color:#f0f0f0;",      freq),
        tags$td(style = "padding:2px 6px; font-family:monospace; font-size:11px; color:#ff7f11;", zl_str),
        tags$td(style = "padding:2px 6px; font-family:monospace; font-size:11px; color:#aaa;",    zs_str),
        tags$td(style = "padding:2px 6px; color:#aaa;", pout),
        tags$td(style = "padding:2px 6px; color:#aaa;", de),
        tags$td(style = "padding:2px 6px; color:#aaa;", gp),
        send_btn
      )
    })
    tagList(
      tags$tr(tags$th(colspan = 7,
        style = "background:#1a1a2a; color:#888; font-size:10px; text-transform:uppercase; padding:3px 6px; letter-spacing:0.5px;",
        header_label)),
      do.call(tagList, row_tags)
    )
  }

  header_text <- if (!is.null(variant_label) && nzchar(variant_label))
    paste("Load-Pull Table \u2014", variant_label)
  else
    "Multi-frequency Load-Pull Table"

  div(class = "kb-detail-section",
    tags$b(header_text),
    tags$small(style = "color:#666; margin-left:8px;",
      " \u2014 ZL / ZS at package lead tips, VDS=28V IDq=180mA, P3dB"),
    div(style = "overflow-x:auto; margin-top:6px;",
      tags$table(
        style = paste0("width:100%; border-collapse:collapse; font-size:12px;",
                       " background:#141420; border-radius:4px; overflow:hidden;"),
        tags$thead(
          tags$tr(
            lapply(c("f (MHz)", "ZL (\u03a9)", "ZS (\u03a9)", "Pout (W)", "\u03b7D (%)", "Gp (dB)", ""),
              function(h) tags$th(style = "padding:4px 6px; background:#1e1e2e; color:#888; font-weight:600; text-align:left;", h)
            )
          )
        ),
        tags$tbody(
          .make_rows("max_power",      "Max Output Power Load"),
          .make_rows("max_efficiency", "Max Drain Efficiency Load")
        )
      )
    ),
    tags$small(style = "color:#555;",
      "\u21d2 Click the arrow to send ZL to the Smith Chart tool.")
  )
}

# Render both load-pull variants (flat-lead Table 9 + gull-wing Table 8)
.render_lp_section <- function(dev) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
  lp_flat    <- dev[["load_pull_table"]]
  lp_gull    <- dev[["load_pull_table_20G"]]
  pn         <- dev[["part_number"]] %||% ""
  pn_g       <- paste0(pn, "G")

  has_flat <- !is.null(lp_flat) && length(Filter(function(r) !is.null(r$freq_mhz), lp_flat)) > 0
  has_gull <- !is.null(lp_gull) && length(Filter(function(r) !is.null(r$freq_mhz), lp_gull)) > 0

  if (!has_flat && !has_gull) {
    return(div(style = "padding:12px; color:#666; font-style:italic; font-size:12px;",
      "Load-pull impedance data not available for this device."))
  }

  div(style = "padding:8px 0;",
    if (has_flat)
      .render_lp_table(dev, lp_data = lp_flat,
        variant_label = paste0(pn, " (SOT1482-1 \u2014 flat lead)")),
    if (has_gull)
      div(style = "margin-top:16px;",
        .render_lp_table(dev, lp_data = lp_gull,
          variant_label = paste0(pn_g, " (SOT1483-1 \u2014 gull-wing)")))
  )
}

# Render DC characteristics table
.render_dc_table <- function(dev) {
  dc <- dev[["dc_characteristics"]]
  if (is.null(dc) || is.null(dc$params) || length(dc$params) == 0) {
    return(div(style = "padding:12px; color:#666; font-style:italic; font-size:12px;",
      "DC characteristic data not available for this device."))
  }
  `%||%` <- function(a, b) if (!is.null(a)) a else b
  cond_str <- dc$test_conditions %||% ""

  .mc <- function(v, style_extra = "") {
    disp <- if (is.null(v) || isTRUE(is.na(v))) "\u2014"
            else as.character(v)
    tags$td(style = paste0("padding:4px 8px; border-bottom:1px solid #1e1e2e;", style_extra), disp)
  }

  rows <- lapply(dc$params, function(p) {
    tags$tr(
      tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; font-family:monospace; font-size:12px; color:#ff7f11; font-weight:600; white-space:nowrap;", p$symbol %||% ""),
      tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#f0f0f0; font-size:12px;", p$parameter %||% ""),
      tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", p$conditions %||% ""),
      .mc(p$min, " color:#5bc0de; font-size:12px; text-align:right;"),
      .mc(p$typ, " color:#f0f0f0; font-size:12px; font-weight:600; text-align:right;"),
      .mc(p$max, " color:#5bc0de; font-size:12px; text-align:right;"),
      tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", p$unit %||% "")
    )
  })

  div(style = "padding:8px 0;",
    if (nzchar(cond_str))
      div(style = "background:#1a1a2a; border-left:3px solid #4472C4; padding:6px 10px; margin-bottom:10px; font-size:11px; color:#888;",
          "\u2139\ufe0f Conditions: ", cond_str),
    div(style = "overflow-x:auto;",
      tags$table(
        style = "width:100%; border-collapse:collapse; font-size:12px; background:#141420; border-radius:4px;",
        tags$thead(tags$tr(lapply(
          c("Symbol", "Parameter", "Conditions", "Min", "Typ", "Max", "Unit"),
          function(h) tags$th(style = "padding:5px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px; text-transform:uppercase; letter-spacing:0.5px;", h)
        ))),
        tags$tbody(do.call(tagList, rows))
      )
    ),
    div(style = "margin-top:8px; font-size:11px; color:#555;",
      "Not tested in production unless noted. Refer to datasheet Table 6.")
  )
}

# Render RF Performance tab: production RF test + multi-frequency app performance
.render_rf_tab <- function(dev) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # Section 1: Production RF test
  rf <- dev[["rf_characteristics"]]
  rf_section <- if (!is.null(rf) && !is.null(rf$params) && length(rf$params) > 0) {
    cond <- rf$test_conditions %||% ""
    note <- rf$test_note %||% ""
    rows_rf <- lapply(rf$params, function(p) {
      .td <- function(v, sty = "") {
        disp <- if (is.null(v) || isTRUE(is.na(v))) "\u2014" else as.character(v)
        tags$td(style = paste0("padding:4px 8px; border-bottom:1px solid #1e1e2e; text-align:right;", sty), disp)
      }
      tags$tr(
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; font-family:monospace; color:#ff7f11; font-weight:600; font-size:12px;", p$symbol %||% ""),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#f0f0f0; font-size:12px;", p$parameter %||% ""),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", p$conditions %||% ""),
        .td(p$min, " color:#5bc0de; font-size:12px;"),
        .td(p$typ, " color:#f0f0f0; font-weight:600; font-size:12px;"),
        .td(p$max, " color:#5bc0de; font-size:12px;"),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", p$unit %||% "")
      )
    })
    tagList(
      h5(style = "color:#f0f0f0; margin:0 0 6px 0; font-size:13px; font-weight:600;",
        icon("flask"), " Production RF Test \u2014 Table 7"),
      if (nzchar(cond))
        div(style = "background:#1a1a2a; border-left:3px solid #4472C4; padding:6px 10px; margin-bottom:6px; font-size:11px; color:#888;", cond),
      if (nzchar(note))
        div(style = "font-size:11px; color:#777; margin-bottom:8px; font-style:italic;", note),
      div(style = "overflow-x:auto;",
        tags$table(
          style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
          tags$thead(tags$tr(lapply(
            c("Symbol", "Parameter", "Conditions", "Min", "Typ", "Max", "Unit"),
            function(h) tags$th(style = "padding:5px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px; letter-spacing:0.5px;", h)
          ))),
          tags$tbody(do.call(tagList, rows_rf))
        )
      ),
      div(style = "margin-top:6px; font-size:11px; color:#555;", "Refer to datasheet Table 7.")
    )
  } else {
    tagList(
      h5(style = "color:#f0f0f0; font-size:13px;", "RF Specifications (summary)"),
      div(style = "font-size:12px; color:#aaa; line-height:1.8;",
        tags$table(style = "width:auto;",
          tags$tr(tags$td(style="padding:2px 6px; font-weight:600;", "Gain (typ):"),  tags$td(paste0(dev$gain_db %||% "\u2014", " dB"))),
          tags$tr(tags$td(style="padding:2px 6px; font-weight:600;", "\u03b7D (typ):"), tags$td(paste0(dev$drain_eff_pct %||% "\u2014", " %"))),
          tags$tr(tags$td(style="padding:2px 6px; font-weight:600;", "P1dB (typ):"), tags$td(paste0(dev$p1db_dbm %||% "\u2014", " dBm"))),
          tags$tr(tags$td(style="padding:2px 6px; font-weight:600;", "P3dB (typ):"), tags$td(paste0(dev$p3db_dbm %||% "\u2014", " dBm")))
        )
      )
    )
  }

  # Section 2: Multi-frequency W-CDMA application performance
  ap <- dev[["application_performance"]]
  ap_section <- if (!is.null(ap) && !is.null(ap$rows) && length(ap$rows) > 0) {
    ap_cond <- ap$test_conditions %||% ""
    ap_sig  <- ap$signal %||% "RF"
    ap_rows <- lapply(ap$rows, function(r) {
      freq_s <- paste0(r$freq_min_mhz, "\u2013", r$freq_max_mhz, " MHz")
      acpr   <- if (!is.null(r$acpr5m_dbc) && !is.na(r$acpr5m_dbc)) paste0(r$acpr5m_dbc, " dBc") else "\u2014"
      tags$tr(
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#f0f0f0; font-weight:600;", freq_s),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#aaa;",     r$vds_v %||% "28"),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#aaa;",     r$pl_av_dbm %||% "\u2014"),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#ff7f11; font-weight:600;", paste0(r$gp_db, " dB")),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#ff7f11; font-weight:600;", paste0(r$de_pct, " %")),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#aaa;",     acpr)
      )
    })
    tagList(
      h5(style = "color:#f0f0f0; margin:18px 0 6px 0; font-size:13px; font-weight:600;",
        icon("chart-bar"), " Multi-frequency Application Performance \u2014 Table 1 (", ap_sig, ")"),
      if (nzchar(ap_cond))
        div(style = "background:#1a1a2a; border-left:3px solid #ff7f11; padding:6px 10px; margin-bottom:8px; font-size:11px; color:#888;", ap_cond),
      div(style = "overflow-x:auto;",
        tags$table(
          style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
          tags$thead(tags$tr(lapply(
            c("Freq Band", "Vds (V)", "PL(AV) (dBm)", "Gp (dB)", "\u03b7D (%)", "ACPR5M (dBc)"),
            function(h) tags$th(style = "padding:5px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px;", h)
          ))),
          tags$tbody(do.call(tagList, ap_rows))
        )
      ),
      div(style = "margin-top:6px; font-size:11px; color:#555;",
        "[1] 3GPP TM1; 64 DCHP; PAR=7.2dB at 0.01% CCDF. Typical values at Tcase=25\u00b0C.")
    )
  } else NULL

  div(style = "padding:8px 0;", rf_section, ap_section)
}

# Render Test PCBs / BOM tab
.render_bom_tab <- function(dev) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
  circs <- dev[["test_circuits"]]
  if (is.null(circs) || length(circs) == 0) {
    return(div(style = "padding:12px; color:#666; font-style:italic; font-size:12px;",
      "Reference PCB designs not available for this device."))
  }

  circ_sections <- lapply(circs, function(c) {
    freq_str  <- paste0(c$freq_mhz, " MHz")
    pcb_info  <- paste0(c$pcb_substrate %||% "", ", ", c$pcb_thickness_mm %||% "", " mm thick",
                        if (!is.null(c$pcb_size_mm)) paste0(", ", c$pcb_size_mm, " mm board") else "")
    fig_ref   <- c$figure %||% ""
    bom       <- c$bom %||% list()

    bom_rows <- lapply(bom, function(b) {
      tags$tr(
        tags$td(style = "padding:3px 8px; border-bottom:1px solid #1a1a2a; font-family:monospace; font-size:11px; color:#f0f0f0; white-space:nowrap;", b$ref %||% ""),
        tags$td(style = "padding:3px 8px; border-bottom:1px solid #1a1a2a; color:#aaa; font-size:12px;", b$type %||% ""),
        tags$td(style = "padding:3px 8px; border-bottom:1px solid #1a1a2a; color:#ff7f11; font-size:12px; font-weight:600;", b$value %||% ""),
        tags$td(style = "padding:3px 8px; border-bottom:1px solid #1a1a2a; color:#666; font-size:11px;", b$vendor %||% "")
      )
    })

    div(style = "margin-bottom:20px;",
      h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 4px 0; border-left:3px solid #ff7f11; padding-left:8px;",
        icon("microchip"), " Test Circuit \u2014 ", freq_str),
      div(style = "font-size:11px; color:#888; margin-bottom:8px;",
        icon("server"), " PCB: ", pcb_info,
        if (nzchar(fig_ref)) span(style = "margin-left:10px; color:#666;", "\u2014 ", fig_ref) else NULL
      ),
      div(style = "overflow-x:auto;",
        tags$table(
          style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
          tags$thead(tags$tr(lapply(
            c("Ref Designator", "Type", "Value", "Vendor / Notes"),
            function(h) tags$th(style = "padding:4px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px;", h)
          ))),
          tags$tbody(do.call(tagList, bom_rows))
        )
      )
    )
  })

  div(style = "padding:8px 0;",
    div(style = "background:#1a1a2a; border-left:3px solid #666; padding:6px 10px; margin-bottom:14px; font-size:11px; color:#888;",
      icon("info-circle"), " All three reference designs use Ampleon BLP9G0722-20G (gull-wing). Schematics in datasheet Figs 2\u20134. Default bias: VDS=28V, IDq=180mA, class-AB."),
    do.call(tagList, circ_sections)
  )
}

# Render Package & ESD tab: variants, dimensions, pinning, ESD, ruggedness, graphical data
.render_package_tab <- function(dev) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  .kv_row <- function(k, v, vc = "#aaa") tags$tr(
    tags$td(style = "padding:3px 8px; border-bottom:1px solid #1a1a2a; color:#888; font-size:12px; font-weight:600; width:45%;", k),
    tags$td(style = paste0("padding:3px 8px; border-bottom:1px solid #1a1a2a; font-size:12px; color:", vc, ";"), v)
  )
  .section_table <- function(...) {
    tags$table(style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px; margin-bottom:4px;",
               tags$tbody(...))
  }

  # ── Variants ──────────────────────────────────────────────────────────────
  variants_section <- {
    vars <- dev[["variants"]] %||% list()
    if (length(vars) == 0) NULL else {
      vrows <- lapply(vars, function(v)
        tags$tr(
          tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; font-family:monospace; color:#ff7f11; font-weight:600; font-size:12px;", v$type_number %||% ""),
          tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#aaa; font-size:12px;", v$package %||% ""),
          tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", v$description %||% "")
        )
      )
      div(style = "margin-bottom:14px;",
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 6px 0;",
           icon("box"), " Ordering Variants"),
        div(style = "overflow-x:auto;",
          tags$table(
            style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
            tags$thead(tags$tr(lapply(c("Type Number", "Package", "Description"), function(h)
              tags$th(style = "padding:5px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px;", h)))),
            tags$tbody(do.call(tagList, vrows))
          )
        )
      )
    }
  }

  # ── Pinning ────────────────────────────────────────────────────────────────
  pins_section <- {
    pin <- dev[["pinning"]] %||% list()
    if (length(pin) == 0 && !is.null(dev[["package_note"]])) NULL else {
      div(style = "margin-bottom:14px;",
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 6px 0;",
           icon("project-diagram"), " Pinning (SOT1482-1 / SOT1483-1)"),
        div(style = "font-family:monospace; font-size:12px; background:#141420; border-radius:4px; padding:10px 14px; line-height:1.9;",
          if (!is.null(pin$pin1)) div(span(style = "color:#ff7f11; font-weight:600;", "Pin 1: "), span(style = "color:#f0f0f0;", pin$pin1)) else NULL,
          if (!is.null(pin$pin2)) div(span(style = "color:#ff7f11; font-weight:600;", "Pin 2: "), span(style = "color:#f0f0f0;", pin$pin2)) else NULL,
          if (!is.null(pin$pin3)) div(span(style = "color:#ff7f11; font-weight:600;", "Pin 3: "), span(style = "color:#f0f0f0;", pin$pin3)) else NULL,
          div(style = "margin-top:6px; font-size:11px; color:#555;",
              "sym112 \u2014 refer to datasheet pinning diagram (Table 2)."),
          div(style = "margin-top:4px; font-size:11px; color:#888;",
              dev[["package_note"]] %||% "")
        )
      )
    }
  }

  # ── Package dimensions ────────────────────────────────────────────────────
  dims_section <- {
    pd <- dev[["package_dimensions"]] %||% list()
    if (length(pd) == 0) NULL else {
      pkg_tables <- lapply(names(pd), function(pkg_name) {
        d <- pd[[pkg_name]]
        rows <- list(
          if (!is.null(d$body_length_mm))   .kv_row("Body length",           paste0(d$body_length_mm, " mm")),
          if (!is.null(d$overall_width_mm)) .kv_row("Overall width",         paste0(d$overall_width_mm, " mm")),
          if (!is.null(d$body_height_mm))   .kv_row("Body height",           paste0(d$body_height_mm, " mm")),
          if (!is.null(d$lead_span_mm))     .kv_row("Lead pitch/span",       paste0(d$lead_span_mm, " mm")),
          if (!is.null(d$lead_width_mm))    .kv_row("Lead width",            paste0(d$lead_width_mm, " mm")),
          if (!is.null(d$exposed_heatsink_mm)) .kv_row("Exposed heatsink",   paste0(d$exposed_heatsink_mm, " mm")),
          if (!is.null(d$standoff_min_mm))  .kv_row("Stand-off (min/max)",   paste0(d$standoff_min_mm, "\u2013", d$standoff_max_mm, " mm")),
          if (!is.null(d$coplanarity_leads_mm)) .kv_row("Lead coplanarity \u2264", paste0(d$coplanarity_leads_mm, " mm")),
          if (!is.null(d$mold_protrusion_max_mm)) .kv_row("Mold protrusion \u2264", paste0(d$mold_protrusion_max_mm, " mm/side")),
          if (!is.null(d$lead_plating))     .kv_row("Lead plating",          d$lead_plating)
        )
        rows <- Filter(Negate(is.null), rows)
        div(style = "margin-bottom:12px; flex:1; min-width:220px;",
          h6(style = "color:#5bc0de; font-size:11px; font-weight:600; text-transform:uppercase; letter-spacing:0.5px; margin:0 0 4px 0;", pkg_name),
          .section_table(do.call(tagList, rows))
        )
      })
      div(style = "margin-bottom:14px;",
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 8px 0;",
           icon("ruler"), " Package Dimensions"),
        div(style = "display:flex; gap:12px; flex-wrap:wrap;",
          do.call(tagList, pkg_tables))
      )
    }
  }

  # ── ESD ───────────────────────────────────────────────────────────────────
  esd_section <- {
    esd <- dev[["esd"]] %||% list()
    lv  <- dev[["limiting_values"]] %||% list()
    th  <- dev[["thermal"]] %||% list()
    rug <- dev[["ruggedness"]] %||% list()

    esd_rows <- list()
    if (!is.null(esd$cdm_class)) esd_rows <- c(esd_rows, list(
      tags$tr(
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#f0f0f0; font-size:12px;", "CDM (Charged Device Model)"),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#ff7f11; font-weight:600; font-size:12px;", paste0("Class ", esd$cdm_class)),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", paste0(esd$cdm_standard %||% "", " \u2014 ", esd$cdm_note %||% ""))
      )
    ))
    if (!is.null(esd$hbm_class)) esd_rows <- c(esd_rows, list(
      tags$tr(
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#f0f0f0; font-size:12px;", "HBM (Human Body Model)"),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#ff7f11; font-weight:600; font-size:12px;", paste0("Class ", esd$hbm_class)),
        tags$td(style = "padding:4px 8px; border-bottom:1px solid #1e1e2e; color:#888; font-size:11px;", paste0(esd$hbm_standard %||% "", " \u2014 ", esd$hbm_note %||% ""))
      )
    ))

    lv_table <- if (!is.null(lv$vds_max_v)) {
      .section_table(
        .kv_row("VDS max",           paste0(lv$vds_max_v, " V"),     "#f0f0f0"),
        .kv_row("VGS range",         paste0(lv$vgs_min_v %||% "\u2014", " to +", lv$vgs_max_v %||% "\u2014", " V"), "#f0f0f0"),
        .kv_row("Storage temp (Tstg)", paste0(lv$tstg_min_c %||% "\u2014", " to ", lv$tstg_max_c %||% "\u2014", " \u00b0C"), "#f0f0f0"),
        .kv_row("Junction temp (Tj max)", paste0(lv$tj_max_c %||% "\u2014", " \u00b0C"), "#f44"),
        if (!is.null(lv$standard)) .kv_row("Standard", lv$standard, "#666") else NULL
      )
    } else NULL

    th_kv <- if (!is.null(th$rth_jc_k_per_w))
      .kv_row(paste0("Rth(j-c) \u2014 ", th$conditions %||% ""), paste0(th$rth_jc_k_per_w, " K/W"), "#ff7f11")
    else NULL

    rug_note <- if (!is.null(rug$vswr))
      div(style = "background:#1a1a2a; border-left:3px solid #27ae60; padding:6px 10px; font-size:11px; color:#aaa; margin-top:8px;",
        icon("shield-alt"), " Ruggedness: VSWR ", rug$vswr, ":1 through all phases at ",
        "VDS=", rug$vds_v %||% "28", "V, Pout=", rug$pout_cw_w %||% "20", "W CW, tested at ",
        paste(rug$test_freq_mhz %||% list(), collapse=" and "), " MHz on ", rug$board %||% "demo board"
      )
    else NULL

    div(style = "margin-bottom:14px;",
      if (length(esd_rows) > 0) tagList(
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 6px 0;",
           icon("shield-alt"), " ESD Sensitivity (Table 13)"),
        div(style = "background:#1d0808; border:1px solid #e74c3c; border-radius:3px; padding:6px 10px; margin-bottom:8px; font-size:11px; color:#e74c3c;",
          icon("exclamation-triangle"), " This device is sensitive to ElectroStatic Discharge (ESD). Handle with ESD precautions per ANSI/ESD S20.20, IEC/ST 61340-5, or JESD625-A."),
        div(style = "overflow-x:auto;",
          tags$table(
            style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
            tags$thead(tags$tr(lapply(c("ESD Model", "Class", "Standard / Note"), function(h)
              tags$th(style = "padding:5px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px;", h)))),
            tags$tbody(do.call(tagList, esd_rows))
          )
        )
      ) else NULL,
      if (!is.null(lv_table)) tagList(
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:14px 0 6px 0;",
           icon("exclamation-triangle"), " Absolute Maximum Ratings (Table 4)"),
        lv_table
      ) else NULL,
      if (!is.null(th_kv)) tagList(
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:14px 0 6px 0;",
           icon("thermometer-half"), " Thermal Characteristics (Table 5)"),
        .section_table(th_kv)
      ) else NULL,
      rug_note
    )
  }

  # ── Graphical data index ──────────────────────────────────────────────────
  gd_section <- {
    gd <- dev[["graphical_data"]] %||% list()
    if (is.null(gd$note) && is.null(gd$cw_curves)) NULL else {
      all_curves <- c(gd$cw_curves %||% list(),
                      gd$pulsed_cw_curves %||% list(),
                      gd$wcdma_curves %||% list())
      curve_rows <- if (length(all_curves) > 0) {
        lapply(all_curves, function(cv) tags$tr(
          tags$td(style = "padding:2px 8px; border-bottom:1px solid #1a1a2a; color:#ff7f11; font-size:11px; font-weight:600;", cv$fig %||% ""),
          tags$td(style = "padding:2px 8px; border-bottom:1px solid #1a1a2a; color:#aaa; font-size:11px;", cv$signal %||% ""),
          tags$td(style = "padding:2px 8px; border-bottom:1px solid #1a1a2a; color:#888; font-size:11px;",
            paste(unlist(cv$freqs_mhz), collapse=" / "), " MHz"),
          tags$td(style = "padding:2px 8px; border-bottom:1px solid #1a1a2a; color:#666; font-size:11px;", cv$axes %||% "")
        ))
      } else list()

      div(style = "margin-top:14px;",
        h5(style = "color:#f0f0f0; font-size:13px; font-weight:600; margin:0 0 6px 0;",
           icon("chart-line"), " Available Performance Curves (DS figures)"),
        if (nchar(gd$note %||% "") > 0)
          div(style = "font-size:11px; color:#888; margin-bottom:8px; font-style:italic;", gd$note),
        if (length(curve_rows) > 0)
          div(style = "overflow-x:auto;",
            tags$table(
              style = "width:100%; border-collapse:collapse; background:#141420; border-radius:4px;",
              tags$thead(tags$tr(lapply(c("Figure", "Signal", "Frequencies", "Axes"), function(h)
                tags$th(style = "padding:4px 8px; background:#1e1e2e; color:#888; font-weight:600; text-align:left; font-size:11px;", h)))),
              tags$tbody(do.call(tagList, curve_rows))
            )
          )
        else NULL
      )
    }
  }

  div(style = "padding:8px 0;", variants_section, pins_section, dims_section, esd_section, gd_section)
}

# ── Convenience wrappers ──────────────────────────────────────────────────────

#' Find devices that cover a specific band and role — quick lookup for PA design.
#'
#' @param df       Full device data.frame
#' @param freq_mhz Frequency to cover (MHz)
#' @param pout_w   Minimum output power required (W)
#' @param role     "driver", "main", or "peak"
#' @return Filtered, sorted data.frame
kb_find_devices <- function(df, freq_mhz, pout_w = 1, role = NULL) {
  result <- kb_filter(df,
    freq_mhz   = freq_mhz,
    pout_min_w = pout_w,
    role       = role,
    status     = "active",
    exclude_placeholder = TRUE
  )
  if (nrow(result) == 0) return(result)

  # Sort: high-confidence first, then by Pout ascending (closest fit)
  conf_rank <- c(high = 1, medium = 2, low = 3)
  result$._conf_rank <- conf_rank[result$knowledge_confidence]
  result$._conf_rank[is.na(result$._conf_rank)] <- 4
  p_any <- pmax(result$pout_w_cw, result$pout_w_pulse, na.rm = TRUE)
  result$._pout <- p_any
  result <- result[order(result$._conf_rank, result$._pout), ]
  result[, !names(result) %in% c("._conf_rank", "._pout"), drop = FALSE]
}

#' Return a named list suitable for selectInput choices.
kb_choices <- function(df, label_col = "part_number", value_col = "device_id") {
  if (nrow(df) == 0) return(character(0))
  vals   <- df[[value_col]]
  labels <- paste0(df[[label_col]], " (", df$manufacturer, ")")
  setNames(vals, labels)
}
