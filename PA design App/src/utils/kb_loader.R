# =============================================================================
# kb_loader.R
# Knowledge Base data loader for the PA Design App.
#
# Reads all manufacturer JSON device files from data/kb/ and builds a
# unified, queryable data.frame.  Array fields (tags, application, etc.)
# are collapsed to semicolon-separated strings for easy grepl()-based
# filtering while preserving multi-value semantics.
#
# Entry points:
#   kb_load_all(kb_root)         → data.frame of all devices
#   kb_load_manufacturer(mfr)    → data.frame for one manufacturer
#   kb_get_raw_device(device_id) → full JSON list for one device
#   kb_load_taxonomy(kb_root)    → list of tag taxonomy categories
#   kb_load_manufacturer_meta(mfr, kb_root) → list with company info
# =============================================================================

# Scalar fields extracted into data.frame columns
.KB_SCALAR_FIELDS <- c(
  "device_id", "part_number", "manufacturer", "family", "series",
  "technology", "generation", "package", "package_note",
  "vdd_v", "freq_min_mhz", "freq_max_mhz", "freq_test_mhz",
  "pout_w_cw", "pout_w_pulse", "pout_dbm",
  "gain_db", "drain_eff_pct", "pae_pct", "p1db_w",
  "ropt_ohm", "xopt_ohm", "rin_ohm", "xin_ohm",
  "impedance_ref_plane",
  "s_params_available", "spice_model_available", "ads_model_available",
  "status", "datasheet_url",
  "knowledge_source", "knowledge_confidence", "notes"
)

# Numeric fields to coerce from character after rbind
.KB_NUMERIC_FIELDS <- c(
  "vdd_v", "freq_min_mhz", "freq_max_mhz", "freq_test_mhz",
  "pout_w_cw", "pout_w_pulse", "pout_dbm",
  "gain_db", "drain_eff_pct", "pae_pct", "p1db_w",
  "ropt_ohm", "xopt_ohm", "rin_ohm", "xin_ohm"
)

# Array fields to collapse as semicolon-separated strings
.KB_ARRAY_FIELDS <- c("tags", "application", "use_case", "role", "topology")

# ── Internal helpers ──────────────────────────────────────────────────────────

.kb_root_path <- function(kb_root = NULL) {
  if (!is.null(kb_root)) return(kb_root)
  # When sourced from server.R in R/ directory:
  file.path("..", "data", "kb")
}

.parse_device_list <- function(raw_list, source_file = "") {
  rows <- lapply(raw_list, function(d) {
    # Fields starting with "_" are comments/metadata — skip
    if (!is.null(d[["_comment"]])) {
      d[["_comment"]] <- NULL
    }

    # Scalar fields
    row <- lapply(.KB_SCALAR_FIELDS, function(f) {
      v <- d[[f]]
      if (is.null(v) || identical(v, list())) return(NA_character_)
      if (is.logical(v)) return(as.character(v))
      as.character(v)
    })
    names(row) <- .KB_SCALAR_FIELDS

    # Array fields → semicolon-separated strings
    for (af in .KB_ARRAY_FIELDS) {
      v <- d[[af]]
      if (is.null(v) || length(v) == 0) {
        row[[af]] <- NA_character_
      } else {
        row[[af]] <- paste(unlist(v), collapse = ";")
      }
    }

    # App notes → count only (full data retrieved via kb_get_raw_device)
    an <- d[["app_notes"]]
    row[["app_notes_count"]] <- if (is.null(an)) "0" else as.character(length(an))

    # Source file for debugging
    row[["source_file"]] <- source_file

    as.data.frame(row, stringsAsFactors = FALSE)
  })

  if (length(rows) == 0) return(data.frame())

  df <- do.call(rbind, rows)

  # Numeric coercion
  for (f in intersect(.KB_NUMERIC_FIELDS, names(df))) {
    df[[f]] <- suppressWarnings(as.numeric(df[[f]]))
  }
  df$app_notes_count <- suppressWarnings(as.integer(df$app_notes_count))

  # Derive pout_dbm if missing but pout_w_cw or pout_w_pulse present
  needs_dbm <- is.na(df$pout_dbm)
  p_w <- ifelse(!is.na(df$pout_w_cw), df$pout_w_cw, df$pout_w_pulse)
  df$pout_dbm[needs_dbm & !is.na(p_w)] <-
    round(10 * log10(p_w[needs_dbm & !is.na(p_w)] * 1000), 1)

  rownames(df) <- NULL
  df
}

# ── Public API ────────────────────────────────────────────────────────────────

#' Load all manufacturer device records into a unified data.frame.
#'
#' @param kb_root  Path to the data/kb/ directory (relative to working dir).
#' @return data.frame with one row per device, all scalar fields as columns,
#'         array fields as semicolon-separated strings.
kb_load_all <- function(kb_root = NULL) {
  root   <- .kb_root_path(kb_root)
  if (!dir.exists(root)) {
    warning("KB root not found: ", root)
    return(data.frame())
  }

  subdirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  # Skip "_"-prefixed entries (schema / taxonomy files live at root level)
  subdirs <- subdirs[!grepl("/_", subdirs)]

  all_dfs <- lapply(subdirs, function(d) {
    f <- file.path(d, "devices.json")
    if (!file.exists(f)) return(NULL)
    raw <- tryCatch(
      jsonlite::fromJSON(f, simplifyVector = FALSE),
      error = function(e) {
        warning("Failed to parse KB file: ", f, " — ", e$message)
        list()
      }
    )
    if (length(raw) == 0) return(NULL)
    .parse_device_list(raw, source_file = f)
  })

  all_dfs <- Filter(Negate(is.null), all_dfs)
  if (length(all_dfs) == 0) return(data.frame())

  # Column-safe rbind (fills missing columns with NA)
  all_cols <- Reduce(union, lapply(all_dfs, names))
  combined <- do.call(rbind, lapply(all_dfs, function(df) {
    miss <- setdiff(all_cols, names(df))
    if (length(miss) > 0) df[miss] <- NA
    df[, all_cols, drop = FALSE]
  }))
  rownames(combined) <- NULL
  combined
}

#' Load device records for a single manufacturer.
#'
#' @param manufacturer  Manufacturer folder name (e.g. "ampleon", "nxp").
#' @param kb_root       Path to data/kb/ directory.
kb_load_manufacturer <- function(manufacturer, kb_root = NULL) {
  root <- .kb_root_path(kb_root)
  f    <- file.path(root, tolower(manufacturer), "devices.json")
  if (!file.exists(f)) {
    warning("No devices.json found for manufacturer: ", manufacturer)
    return(data.frame())
  }
  raw <- tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) { warning(e$message); list() }
  )
  .parse_device_list(raw, source_file = f)
}

#' Retrieve the full raw JSON list for a single device (includes app_notes etc.)
#'
#' @param device_id  Unique device_id string (e.g. "ampleon_BLF188XR").
#' @param kb_root    Path to data/kb/ directory.
#' @return Named list (the raw JSON record), or NULL if not found.
kb_get_raw_device <- function(device_id, kb_root = NULL) {
  root    <- .kb_root_path(kb_root)
  subdirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  subdirs <- subdirs[!grepl("/_", subdirs)]

  for (d in subdirs) {
    f <- file.path(d, "devices.json")
    if (!file.exists(f)) next
    raw <- tryCatch(
      jsonlite::fromJSON(f, simplifyVector = FALSE),
      error = function(e) list()
    )
    for (dev in raw) {
      if (!is.null(dev$device_id) && dev$device_id == device_id)
        return(dev)
    }
  }
  NULL
}

#' Load the tag taxonomy.
kb_load_taxonomy <- function(kb_root = NULL) {
  root <- .kb_root_path(kb_root)
  f    <- file.path(root, "_tag_taxonomy.json")
  if (!file.exists(f)) return(list())
  tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) { warning(e$message); list() }
  )
}

#' Load manufacturer metadata (_metadata.json).
kb_load_manufacturer_meta <- function(manufacturer, kb_root = NULL) {
  root <- .kb_root_path(kb_root)
  f    <- file.path(root, tolower(manufacturer), "_metadata.json")
  if (!file.exists(f)) return(list())
  tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) { warning(e$message); list() }
  )
}

#' List all manufacturer IDs with device data available.
kb_list_manufacturers <- function(kb_root = NULL) {
  root    <- .kb_root_path(kb_root)
  subdirs <- list.dirs(root, recursive = FALSE, full.names = FALSE)
  subdirs[!grepl("^_", subdirs) & nzchar(subdirs)]
}
