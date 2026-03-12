# =============================================================================
# lp_parsers.R
# Load Pull file format parsers for the PA Design App.
#
# Supported formats:
#   "spl"       – Generic SPL / Focus Microwaves LP ASCII
#   "focus"     – Focus Microwaves CCMT/LP block format
#   "mdf"       – Maury Microwave MDF (block-structured ASCII)
#   "amcad"     – AMCAD Instruments CSV
#   "anteverta" – Anteverta-mw CSV
#   "mdif"      – Keysight/ADS Microwave Data Interchange Format
#
# All parsers return a named list:
#   $success  logical
#   $error    character (if !success)
#   $format   character – detected/used format tag
#   $filename character
#   $meta     named list – frequency, device, bias, date, ...
#   $points   data.frame – normalised schema (see below)
#   $raw      character vector – original file lines
#
# Normalised column schema for $points:
#   gl_r, gl_i   – load  reflection coeff (Cartesian, dimensionless)
#   gs_r, gs_i   – source reflection coeff (Cartesian)
#   pout_dbm     – output power (dBm)
#   pin_dbm      – input power (dBm)
#   gain_db      – transducer gain (dB)
#   pae_pct      – power-added efficiency (%)
#   de_pct       – drain efficiency (%)
#   idc_a        – drain/collector current (A)
#   vdc_v        – drain/collector voltage (V)
#   pdc_w        – DC power (W)   [computed if absent: vdc_v * idc_a]
#   freq_ghz     – frequency (GHz) [from meta if not per-row]
# =============================================================================

# ── Main dispatcher ───────────────────────────────────────────────────────────

#' Parse a load-pull data file.
#'
#' @param filepath  Path to the file on disk.
#' @param format_override  "auto" (default) or one of: spl, focus, mdf, amcad,
#'                         anteverta, mdif.
#' @return Named list as described in file header.
parse_lp_file <- function(filepath, format_override = "auto") {
  if (!file.exists(filepath))
    return(.lp_err("auto", filepath, paste("File not found:", filepath)))

  lines <- tryCatch(
    readLines(filepath, warn = FALSE, encoding = "UTF-8"),
    error = function(e) readLines(filepath, warn = FALSE)   # latin-1 fallback
  )

  fmt <- if (format_override != "auto") format_override
         else detect_lp_format(lines)

  result <- tryCatch(
    switch(fmt,
      spl       = parse_spl(lines, filepath),
      focus     = parse_focus(lines, filepath),
      mdf       = parse_mdf(lines, filepath),
      amcad     = parse_amcad(lines, filepath),
      anteverta = parse_anteverta(lines, filepath),
      mdif      = parse_mdif(lines, filepath),
      .lp_err(fmt, filepath, paste("Unsupported format:", fmt))
    ),
    error = function(e) .lp_err(fmt, filepath, conditionMessage(e))
  )

  result$format   <- fmt
  result$filename <- basename(filepath)
  result$raw      <- lines
  result
}

# ── Format auto-detection ─────────────────────────────────────────────────────

#' Detect the format of a load-pull file from its first ~25 lines.
detect_lp_format <- function(lines) {
  hd <- paste(
    toupper(trimws(lines[nzchar(trimws(lines))][seq_len(min(25, sum(nzchar(trimws(lines)))))]))
    , collapse = "\n"
  )
  if (grepl("BEGIN MDIF|END MDIF",                  hd)) return("mdif")
  if (grepl("MDF_VERSION|BEGIN SWEEP",               hd)) return("mdf")
  if (grepl("AMCAD",                                 hd)) return("amcad")
  if (grepl("ANTEVERTA",                             hd)) return("anteverta")
  if (grepl("#SOURCE PULL|#LOAD PULL|CCMT|#FORMAT",  hd)) return("focus")
  if (any(grepl("^!", lines[seq_len(min(10, length(lines)))]))) return("spl")
  if (any(grepl(",",   lines[seq_len(min(10, length(lines)))]))) return("amcad")
  "spl"  # safe fallback
}

# ── Format 1: Generic SPL (Focus Microwaves simple export & generic ASCII) ────

parse_spl <- function(lines, filepath) {
  # Lines starting with ! are comments / metadata.
  # First non-comment, non-empty line is the column header.
  comment_lines <- grepl("^[[:space:]]*!", lines)
  meta_raw      <- lines[comment_lines]
  data_lines    <- lines[!comment_lines & nzchar(trimws(lines))]

  if (length(data_lines) < 2)
    return(.lp_err("spl", filepath, "No data rows found after comments"))

  # Header is first non-empty, non-comment line
  hdr_line  <- data_lines[1]
  data_rows <- data_lines[-1]

  meta <- .parse_comment_meta(meta_raw)
  col_names <- toupper(strsplit(trimws(hdr_line), "[[:space:]]+")[[1]])

  mat <- do.call(rbind, lapply(data_rows, function(r) {
    vals <- strsplit(trimws(r), "[[:space:]]+")[[1]]
    if (length(vals) != length(col_names)) return(NULL)
    suppressWarnings(as.numeric(vals))
  }))
  mat <- mat[!is.na(rowSums(mat)), , drop = FALSE]
  if (nrow(mat) == 0)
    return(.lp_err("spl", filepath, "Could not parse any numeric rows"))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names

  list(success = TRUE, meta = meta, points = .normalise_df(df, meta))
}

# ── Format 2: Focus Microwaves CCMT/LP block format ──────────────────────────

parse_focus <- function(lines, filepath) {
  # Metadata lines start with #, e.g.:
  #   #DEVICE CG2H40010F
  #   #FREQUENCY 2.400 GHz
  # After metadata: blank line, then column header, then data
  meta_raw   <- lines[grepl("^[[:space:]]*#",  lines)]
  data_lines <- lines[!grepl("^[[:space:]]*[#!]", lines) & nzchar(trimws(lines))]

  meta <- .parse_focus_meta(meta_raw)

  if (length(data_lines) < 2)
    return(.lp_err("focus", filepath, "No data rows after header block"))

  hdr_line  <- data_lines[1]
  data_rows <- data_lines[-1]

  col_names <- toupper(strsplit(trimws(hdr_line), "[[:space:]]+")[[1]])

  mat <- do.call(rbind, lapply(data_rows, function(r) {
    vals <- strsplit(trimws(r), "[[:space:]]+")[[1]]
    if (length(vals) < length(col_names)) return(rep(NA_real_, length(col_names)))
    suppressWarnings(as.numeric(vals[seq_len(length(col_names))]))
  }))
  mat <- mat[complete.cases(mat), , drop = FALSE]
  if (nrow(mat) == 0)
    return(.lp_err("focus", filepath, "No complete numeric rows parsed"))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names

  list(success = TRUE, meta = meta, points = .normalise_df(df, meta))
}

# ── Format 3: Maury MDF ───────────────────────────────────────────────────────

parse_mdf <- function(lines, filepath) {
  # Key-value header until BEGIN SWEEP, then column names, then data, END SWEEP
  in_data  <- FALSE
  hdr_done <- FALSE
  col_names <- NULL
  data_rows_raw <- character(0)
  meta_kv   <- list()

  for (ln in lines) {
    ln_up <- toupper(trimws(ln))
    if (grepl("^BEGIN[[:space:]]+SWEEP|^BEGIN[[:space:]]+DATA", ln_up)) {
      in_data <- TRUE; next
    }
    if (grepl("^END[[:space:]]+SWEEP|^END[[:space:]]+DATA", ln_up)) {
      in_data <- FALSE; next
    }
    if (!in_data) {
      # Key-value pairs: KEY VALUE or KEY = VALUE
      kv <- regmatches(ln, regexpr("^([A-Za-z_][A-Za-z0-9_]*)\\s*=?\\s*(.+)$", ln, perl = TRUE))
      if (length(kv) == 1) {
        parts <- strsplit(trimws(gsub("=", " ", kv)), "[[:space:]]+")[[1]]
        if (length(parts) >= 2) meta_kv[[tolower(parts[1])]] <- paste(parts[-1], collapse = " ")
      }
      next
    }
    # Inside data block
    if (!hdr_done && grepl("[A-Za-z]", ln) && !grepl("^[[:space:]]*[!#]", ln)) {
      col_names <- toupper(strsplit(trimws(ln), "[[:space:]]+")[[1]])
      hdr_done  <- TRUE
      next
    }
    if (hdr_done && nzchar(trimws(ln)))
      data_rows_raw <- c(data_rows_raw, ln)
  }

  if (is.null(col_names) || length(data_rows_raw) == 0)
    return(.lp_err("mdf", filepath, "Could not find data block or column headers"))

  mat <- do.call(rbind, lapply(data_rows_raw, function(r) {
    vals <- strsplit(trimws(r), "[[:space:]]+")[[1]]
    suppressWarnings(as.numeric(vals[seq_len(min(length(vals), length(col_names)))]))
  }))
  mat <- mat[complete.cases(mat), , drop = FALSE]
  if (nrow(mat) == 0)
    return(.lp_err("mdf", filepath, "No numeric rows in data block"))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names[seq_len(ncol(df))]

  meta <- c(meta_kv, .kv_to_meta(meta_kv))
  list(success = TRUE, meta = meta, points = .normalise_df(df, meta))
}

# ── Format 4: AMCAD Instruments CSV ──────────────────────────────────────────

parse_amcad <- function(lines, filepath) {
  # First non-comment, non-empty line that contains commas = header row
  skip_re <- "^[[:space:]]*(AMCAD|!|#|%)"
  data_lines <- lines[!grepl(skip_re, lines, ignore.case = TRUE) & nzchar(trimws(lines))]

  # Find the header: first line with >= 4 comma-separated tokens containing letters
  hdr_idx <- which(sapply(data_lines, function(l) {
    toks <- strsplit(trimws(l), ",")[[1]]
    length(toks) >= 4 && any(grepl("[A-Za-z]", toks))
  }))[1]

  if (is.na(hdr_idx))
    return(.lp_err("amcad", filepath, "Could not locate column header row"))

  meta_raw  <- data_lines[seq_len(hdr_idx - 1)]
  hdr_line  <- data_lines[hdr_idx]
  data_rows <- data_lines[(hdr_idx + 1):length(data_lines)]
  data_rows <- data_rows[nzchar(trimws(data_rows))]

  col_names <- toupper(trimws(strsplit(hdr_line, ",")[[1]]))
  meta <- .parse_comment_meta(meta_raw)

  mat <- do.call(rbind, lapply(data_rows, function(r) {
    vals <- strsplit(trimws(r), ",")[[1]]
    suppressWarnings(as.numeric(trimws(vals[seq_len(min(length(vals), length(col_names)))])))
  }))
  mat <- mat[complete.cases(mat), , drop = FALSE]
  if (nrow(mat) == 0)
    return(.lp_err("amcad", filepath, "No numeric rows found"))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names[seq_len(ncol(df))]

  list(success = TRUE, meta = meta, points = .normalise_df(df, meta))
}

# ── Format 5: Anteverta-mw CSV ───────────────────────────────────────────────

parse_anteverta <- function(lines, filepath) {
  # Very similar to AMCAD — reuse AMCAD parser with slight column re-mapping
  result <- parse_amcad(lines, filepath)
  result$format <- "anteverta"
  # Anteverta column names differ slightly — handled in .normalise_df via alias table
  result
}

# ── Format 6: Keysight/ADS MDIF ──────────────────────────────────────────────

parse_mdif <- function(lines, filepath) {
  # Structure:
  # BEGIN MDIF "name"
  #   VAR  <name>  <type>  <value>   (swept variable at this block)
  #   [ACDATA / DATA block]
  #   BEGIN DATA  or  BEGIN ACDATA
  #     ! header (optional)
  #     col1 col2 ...
  #     val  val  ...
  #   END DATA
  # END MDIF  [repeats for each sweep point]

  blocks     <- list()
  cur_vars   <- list()
  in_mdif    <- FALSE
  in_data    <- FALSE
  hdr_done   <- FALSE
  col_names  <- NULL
  cur_rows   <- character(0)

  for (ln in lines) {
    ln_t  <- trimws(ln)
    ln_up <- toupper(ln_t)

    if (grepl("^BEGIN[[:space:]]+MDIF", ln_up)) {
      in_mdif <- TRUE; cur_vars <- list(); next
    }
    if (grepl("^END[[:space:]]+MDIF", ln_up)) {
      in_mdif <- FALSE; next
    }
    if (!in_mdif) next

    if (grepl("^VAR[[:space:]]", ln_up)) {
      parts <- strsplit(ln_t, "[[:space:]]+")[[1]]
      if (length(parts) >= 4) cur_vars[[parts[2]]] <- suppressWarnings(as.numeric(parts[4]))
      next
    }
    if (grepl("^BEGIN[[:space:]]+(DATA|ACDATA)", ln_up)) {
      in_data  <- TRUE
      hdr_done <- FALSE
      col_names <- NULL
      cur_rows <- character(0)
      next
    }
    if (grepl("^END[[:space:]]+(DATA|ACDATA)", ln_up)) {
      in_data <- FALSE
      if (!is.null(col_names) && length(cur_rows) > 0) {
        mat <- do.call(rbind, lapply(cur_rows, function(r) {
          vals <- strsplit(trimws(r), "[[:space:]]+")[[1]]
          suppressWarnings(as.numeric(vals[seq_len(min(length(vals), length(col_names)))]))
        }))
        mat <- mat[complete.cases(mat), , drop = FALSE]
        if (nrow(mat) > 0) {
          df <- as.data.frame(mat, stringsAsFactors = FALSE)
          names(df) <- col_names[seq_len(ncol(df))]
          for (vn in names(cur_vars)) df[[vn]] <- cur_vars[[vn]]
          blocks <- c(blocks, list(df))
        }
      }
      next
    }
    if (!in_data) next

    # Skip ! comments
    if (grepl("^!", ln_t)) next

    if (!hdr_done && grepl("[A-Za-z]", ln_t)) {
      col_names <- toupper(strsplit(ln_t, "[[:space:]]+")[[1]])
      hdr_done  <- TRUE
      next
    }
    if (hdr_done && nzchar(ln_t)) cur_rows <- c(cur_rows, ln_t)
  }

  if (length(blocks) == 0)
    return(.lp_err("mdif", filepath, "No data blocks found in MDIF file"))

  # Combine all blocks (column union)
  all_cols <- unique(unlist(lapply(blocks, names)))
  combined <- do.call(rbind, lapply(blocks, function(b) {
    missing <- setdiff(all_cols, names(b))
    for (m in missing) b[[m]] <- NA_real_
    b[, all_cols, drop = FALSE]
  }))

  meta <- list()
  list(success = TRUE, meta = meta, points = .normalise_df(combined, meta))
}

# ── Column name normalisation ─────────────────────────────────────────────────
# Maps every known variant to the canonical schema column name.

.COL_ALIASES <- c(
  # Load reflection coefficient
  GL_R = "gl_r", GL_REAL = "gl_r", GAMMA_L_R = "gl_r", GAMMAL_R = "gl_r",
  GAMMAL_REAL = "gl_r", GL_RE = "gl_r", LOAD_R = "gl_r",
  "GAMMA_L_MAG" = "gl_mag", "GL_MAG" = "gl_mag", GAMMAL_MAG = "gl_mag",

  GL_I = "gl_i", GL_IMAG = "gl_i", GAMMA_L_I = "gl_i", GAMMAL_I = "gl_i",
  GAMMAL_IMAG = "gl_i", GL_IM = "gl_i", LOAD_I = "gl_i",
  "GAMMA_L_ANG" = "gl_ang", "GL_ANG" = "gl_ang", GAMMAL_ANG = "gl_ang",
  "GAMMA_L_PHASE" = "gl_ang", GL_PHASE = "gl_ang",

  # Source reflection coefficient
  GS_R = "gs_r", GS_REAL = "gs_r", GAMMA_S_R = "gs_r", GAMMAS_R = "gs_r",
  "GAMMA_S_MAG" = "gs_mag", GS_MAG = "gs_mag",

  GS_I = "gs_i", GS_IMAG = "gs_i", GAMMA_S_I = "gs_i", GAMMAS_I = "gs_i",
  "GAMMA_S_ANG" = "gs_ang", GS_ANG = "gs_ang",
  "GAMMA_S_PHASE" = "gs_ang",

  # Power
  POUT = "pout_dbm", `POUT(DBM)` = "pout_dbm", POUT_DBM = "pout_dbm",
  OUTPUTPOWER = "pout_dbm",
  PIN  = "pin_dbm",  `PIN(DBM)`  = "pin_dbm",  PIN_DBM  = "pin_dbm",
  PAV  = "pin_dbm",  PAVS = "pin_dbm", AVAIL_POWER = "pin_dbm",

  # Gain
  GAIN = "gain_db", `GAIN(DB)` = "gain_db", GAIN_DB = "gain_db",
  GT   = "gain_db", TRANSDUCER_GAIN = "gain_db",
  GP   = "gp_db",   POWERGAIN = "gp_db",

  # Efficiency
  PAE  = "pae_pct", `PAE(%)` = "pae_pct", PAE_PCT = "pae_pct",
  `PAE(PERCENT)` = "pae_pct",
  DE   = "de_pct",  `DE(%)`  = "de_pct",  DE_PCT  = "de_pct",
  EFF  = "de_pct",  DRAIN_EFF = "de_pct",

  # Bias
  IDC = "idc_a", `IDC(A)` = "idc_a", IDC_A = "idc_a",
  `IDC(MA)` = "idc_ma",
  IDS = "idc_a", IDRAIN = "idc_a",
  VDC = "vdc_v", `VDC(V)` = "vdc_v", VDC_V = "vdc_v",
  VDS = "vdc_v", VDRAIN = "vdc_v",
  PDC = "pdc_w", `PDC(W)` = "pdc_w", PDC_W = "pdc_w",

  # Frequency
  FREQ = "freq_ghz", `FREQ(GHZ)` = "freq_ghz", FREQUENCY = "freq_ghz"
)

.normalise_df <- function(df, meta) {
  names(df) <- toupper(names(df))

  # Rename columns via alias table
  for (alias in names(.COL_ALIASES)) {
    canon <- .COL_ALIASES[[alias]]
    if (alias %in% names(df) && !canon %in% names(df)) {
      names(df)[names(df) == alias] <- canon
    }
  }

  # Convert magnitude+angle → Cartesian if needed
  if ("gl_mag" %in% names(df) && "gl_ang" %in% names(df) &&
      !all(c("gl_r","gl_i") %in% names(df))) {
    ang_rad  <- df$gl_ang * pi / 180
    df$gl_r  <- df$gl_mag * cos(ang_rad)
    df$gl_i  <- df$gl_mag * sin(ang_rad)
  }
  if ("gs_mag" %in% names(df) && "gs_ang" %in% names(df) &&
      !all(c("gs_r","gs_i") %in% names(df))) {
    ang_rad  <- df$gs_ang * pi / 180
    df$gs_r  <- df$gs_mag * cos(ang_rad)
    df$gs_i  <- df$gs_mag * sin(ang_rad)
  }

  # mA → A
  if ("idc_ma" %in% names(df) && !"idc_a" %in% names(df))
    df$idc_a <- df$idc_ma / 1000

  # Derive pdc_w if absent
  if (!"pdc_w" %in% names(df) && all(c("idc_a","vdc_v") %in% names(df)))
    df$pdc_w <- df$idc_a * df$vdc_v

  # Add freq from meta if missing per-row
  if (!"freq_ghz" %in% names(df)) {
    fq <- suppressWarnings(as.numeric(meta$freq_ghz %||% NA))
    df$freq_ghz <- fq
  }

  # Ensure canonical columns exist (NA if not available)
  canonical <- c("gl_r","gl_i","gs_r","gs_i","pout_dbm","pin_dbm",
                 "gain_db","pae_pct","de_pct","idc_a","vdc_v","pdc_w","freq_ghz")
  for (cn in canonical) if (!cn %in% names(df)) df[[cn]] <- NA_real_

  df[, canonical, drop = FALSE]
}

# ── Metadata helpers ──────────────────────────────────────────────────────────

.parse_comment_meta <- function(comment_lines) {
  meta <- list()
  for (ln in comment_lines) {
    clean <- trimws(sub("^[!#%]+[[:space:]]*", "", ln))
    if (!nzchar(clean)) next
    # KEY: VALUE  or  KEY VALUE
    m <- regmatches(clean, regexpr("^([A-Za-z][A-Za-z0-9_ \\-\\.]*)[:\\s]+(.+)$",
                                   clean, perl = TRUE))
    if (length(m) == 1) {
      pairs <- strsplit(m, "[:\\s]+", perl = TRUE)[[1]]
      key   <- tolower(trimws(gsub("[^A-Za-z0-9_]", "_", pairs[1])))
      val   <- trimws(paste(pairs[-1], collapse = " "))
      meta[[key]] <- val
    }
  }
  meta
}

.parse_focus_meta <- function(meta_lines) {
  meta <- list()
  for (ln in meta_lines) {
    clean <- trimws(sub("^#+[[:space:]]*", "", ln))
    if (!nzchar(clean)) next
    parts <- strsplit(clean, "[[:space:]]+")[[1]]
    if (length(parts) >= 2) {
      key        <- tolower(parts[1])
      meta[[key]] <- paste(parts[-1], collapse = " ")
    }
  }
  .kv_to_meta(meta)
}

# Standardise key names from arbitrary key-value pairs
.kv_to_meta <- function(kv) {
  out <- kv
  for (k in names(kv)) {
    ku <- toupper(k)
    if (ku %in% c("FREQ","FREQUENCY","FREQ(GHZ)")) {
      # Parse "2.4 GHz" or "2.4"
      num <- suppressWarnings(as.numeric(gsub("[^0-9\\.]", "", kv[[k]])))
      if (!is.na(num)) out$freq_ghz <- num
    }
    if (ku %in% c("DEVICE","DUT","DEVICENAME")) out$device <- kv[[k]]
    if (ku %in% c("DATE","MEAS_DATE"))           out$date   <- kv[[k]]
    if (ku %in% c("VD","VDS","VDRAIN","VDC"))    out$vd     <- suppressWarnings(as.numeric(gsub("[^0-9\\.-]","",kv[[k]])))
    if (ku %in% c("ID","IDS","IDRAIN","IDC"))    out$id_ma  <- suppressWarnings(as.numeric(gsub("[^0-9\\.-]","",kv[[k]])))
  }
  out
}

# ── Error result constructor ──────────────────────────────────────────────────

.lp_err <- function(fmt, filepath, msg) {
  list(
    success  = FALSE,
    error    = msg,
    format   = fmt,
    filename = basename(filepath),
    meta     = list(),
    points   = data.frame(
      gl_r=numeric(), gl_i=numeric(), gs_r=numeric(), gs_i=numeric(),
      pout_dbm=numeric(), pin_dbm=numeric(), gain_db=numeric(),
      pae_pct=numeric(), de_pct=numeric(), idc_a=numeric(),
      vdc_v=numeric(), pdc_w=numeric(), freq_ghz=numeric()
    ),
    raw = character()
  )
}

# ── Null-coalescing (safe re-definition in case not in scope) ─────────────────
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b
