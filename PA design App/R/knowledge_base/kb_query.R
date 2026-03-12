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

  .v  <- function(x) { v <- dev[[x]]; if (is.null(v) || identical(v, "NA") || is.na(v)) "—" else as.character(v) }
  .nv <- function(x, unit = "") {
    v <- dev[[x]]
    if (is.null(v) || is.na(v) || v == "NA") return("—")
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

  tagList(
    div(style = "padding:12px 0;",

      # Header
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

      # Performance row
      div(style = "display:grid; grid-template-columns:repeat(4,1fr); gap:8px; margin-bottom:12px;",
        .stat_box("Frequency", freq_str),
        .stat_box("Output Power", pout_str),
        .stat_box("Gain", paste0(.nv("gain_db"), " dB")),
        .stat_box("DE / PAE", paste0(.nv("drain_eff_pct"), " / ", .nv("pae_pct"), " %"))
      ),

      # Impedance
      div(class = "kb-detail-section",
        tags$b("Optimum Load Impedance (Ropt)"), br(),
        span(style = "font-size:15px; color:#ff7f11; font-family:monospace;", imp_str), br(),
        tags$small(style = "color:#666;", "Ref plane: ", .v("impedance_ref_plane"))
      ),

      # Applications & roles
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

      # Supply
      div(class = "kb-detail-section",
        tags$b("Supply / Bias"), br(),
        span(style = "color:#aaa; font-size:12px;",
          "Vdd = ", .nv("vdd_v", "V"), "  |  Idq = ", .nv("idd_q_ma", "mA"))
      ),

      # Notes
      if (.v("notes") != "—") {
        div(class = "kb-detail-section",
          tags$b("Engineering notes"),
          p(style = "color:#aaa; font-size:12px; margin-top:4px;", .v("notes"))
        )
      },

      # Links
      div(class = "kb-detail-section",
        tags$b("Datasheet"), br(), ds_link
      ),

      # Action buttons
      div(style = "display:flex; gap:8px; margin-top:14px;",
        actionButton("kb_send_to_smith", "Load Ropt \u2192 Smith Chart",
          icon = icon("bullseye"), class = "btn-primary btn-sm",
          disabled = if (imp_str == "— (see datasheet)") "disabled" else NULL),
        actionButton("kb_copy_to_lineup", "Add to Lineup Canvas",
          icon = icon("plus"), class = "btn-default btn-sm")
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
