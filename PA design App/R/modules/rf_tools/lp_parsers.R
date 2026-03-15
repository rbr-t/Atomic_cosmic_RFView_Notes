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
      lpcwave   = parse_lpcwave(lines, filepath),
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
  n_lines <- length(lines)
  head10  <- lines[seq_len(min(10, n_lines))]
  nz_lines <- lines[nzchar(trimws(lines))]
  hd <- paste(
    toupper(trimws(nz_lines[seq_len(min(50, length(nz_lines)))])),
    collapse = "\n"
  )
  # Focus LPCWAVE: has "# NNN" point-block markers AND column header in !-comment
  if (any(grepl("^#[[:space:]]*[0-9]+", head10)) ||
      grepl("POINT[[:space:]]+GAMMA[[:space:]]+PHASE", hd))
    return("lpcwave")
  if (grepl("BEGIN MDIF|END MDIF",                   hd)) return("mdif")
  # ALPS / Maury MDF: BEGIN Sweep (case-insensitive) or VAR with (real)/(string) types
  if (grepl("MDF_VERSION|BEGIN SWEEP|BEGIN SWEEP",    hd) ||
      grepl("VAR.*\\(REAL\\)|\\(STRING\\)",           hd, ignore.case = TRUE))
    return("mdf")
  if (grepl("AMCAD",                                  hd)) return("amcad")
  if (grepl("ANTEVERTA",                              hd)) return("anteverta")
  if (grepl("#SOURCE PULL|#LOAD PULL|CCMT|#FORMAT",   hd)) return("focus")
  if (any(grepl("^!", head10))) return("spl")
  if (any(grepl(",",  head10))) return("amcad")
  "spl"  # safe fallback
}

# ── Format 1: Generic SPL (Focus Microwaves simple export & generic ASCII) ────

parse_spl <- function(lines, filepath) {
  # Focus Power Sweep Plan (and generic SPL) format:
  #
  # - Lines starting with ! are comments / metadata.
  # - Non-comment metadata precedes the actual column header:
  #     "Number of Frequencies = 1", "VAR=<...>", "User params: 3", etc.
  # - The actual column header is the FIRST non-blank, non-comment line whose
  #   every whitespace-delimited token looks like a column name: starts with a
  #   letter or _, may contain letters/digits/_%.(  but NOT '=', ':', or pure
  #   numbers.  E.g. "valid gamma_src1 gamma_ld1 Freq Pin_avail_dBm ..."
  # - After the header, "Freq = X.X GHz" section separators mark new frequency
  #   blocks in multi-frequency files.
  # - Data rows are all-numeric; rows where the VALID column == 0 are skipped.
  # - Single-token rows (zero-padding) are discarded.

  comment_lines <- grepl("^[[:space:]]*!", lines)
  meta_raw      <- lines[comment_lines]
  non_comment   <- lines[!comment_lines]

  # TRUE when every whitespace-split token looks like a column name.
  # Deliberately excludes '.' from allowed chars so filename-like tokens
  # (e.g. "AI1330...spl_1.840GHz.tdp") are not mistaken for column headers.
  .is_col_hdr <- function(ln) {
    toks <- strsplit(trimws(ln), "[[:space:]\t]+")[[1]]
    length(toks) >= 2 &&
      all(grepl("^[A-Za-z_][A-Za-z0-9_%()]*$", toks))
  }

  # Find the first non-blank non-comment line that passes .is_col_hdr
  hdr_idx <- NA_integer_
  for (i in seq_along(non_comment)) {
    if (nzchar(trimws(non_comment[i])) && .is_col_hdr(non_comment[i])) {
      hdr_idx <- i
      break
    }
  }

  if (is.na(hdr_idx))
    return(.lp_err("spl", filepath, "Could not locate column header row"))

  raw_col_names <- strsplit(trimws(non_comment[hdr_idx]), "[[:space:]]+")[[1]]

  # Focus SPL encodes complex gammas as a single column name (e.g. gamma_src1)
  # but stores TWO consecutive numbers (real, imag) per point.  Detect these
  # columns by name pattern and expand: gamma_* → gamma_*_RE + gamma_*_IM
  .expand_gamma_cols <- function(names_vec) {
    out <- character(0)
    for (nm in names_vec) {
      if (grepl("^gamma_", nm, ignore.case = TRUE) &&
          !grepl("_(re|im|real|imag|r|i)$", nm, ignore.case = TRUE)) {
        out <- c(out, paste0(nm, "_re"), paste0(nm, "_im"))
      } else {
        out <- c(out, nm)
      }
    }
    out
  }
  col_names <- toupper(.expand_gamma_cols(raw_col_names))

  # --- Metadata: comment lines + pre-header "Freq = X GHz" lines --------------
  meta <- .parse_comment_meta(meta_raw)

  .parse_freq_line <- function(ln) {
    nums   <- regmatches(ln, gregexpr("[0-9]+\\.?[0-9]*", ln))[[1]]
    unit_m <- regmatches(ln, regexpr("(GHz|MHz|kHz)", ln,
                                     perl = TRUE, ignore.case = TRUE))
    unit <- if (length(unit_m) == 1) tolower(unit_m) else "ghz"
    num  <- suppressWarnings(as.numeric(nums[1]))
    if (is.na(num)) return(NA_real_)
    if (unit == "mhz") num <- num / 1000
    if (unit == "khz") num <- num / 1e6
    num
  }

  pre_hdr <- non_comment[seq_len(hdr_idx - 1)]
  for (ln in pre_hdr) {
    if (grepl("^[[:space:]]*Freq[[:space:]]*=", ln, ignore.case = TRUE)) {
      fq <- .parse_freq_line(ln)
      if (!is.na(fq)) meta$freq_ghz <- fq
    }
  }

  # --- Parse data rows -------------------------------------------------------
  cur_freq  <- suppressWarnings(as.numeric(meta$freq_ghz %||% NA))
  n_cols    <- length(col_names)
  valid_col <- which(col_names == "VALID")   # row-validity flag column
  rows_list <- list()

  after_hdr <- if ((hdr_idx + 1) <= length(non_comment))
                 non_comment[(hdr_idx + 1):length(non_comment)]
               else character(0)

  for (ln in after_hdr) {
    ln <- trimws(ln)
    if (!nzchar(ln)) next

    # Repeated column header (multi-block files) — skip
    if (.is_col_hdr(ln)) next

    # Section separator: "Freq = X.X GHz" — update current frequency context
    if (grepl("^[[:space:]]*Freq[[:space:]]*=", ln, ignore.case = TRUE)) {
      fq <- .parse_freq_line(ln)
      if (!is.na(fq)) cur_freq <- fq
      next
    }

    # Any line containing letters that cannot appear in numeric values
    # (allow e/E for scientific notation like 1.838e+002, but block everything else)
    if (grepl("[A-DF-Za-df-z]", ln)) next

    # Parse numeric tokens
    vals <- suppressWarnings(as.numeric(strsplit(ln, "[[:space:]]+")[[1]]))
    if (any(is.na(vals))) next

    # Skip single-token rows (zero-padding, stray values)
    if (length(vals) < 2) next

    # Skip rows where the VALID flag column == 0
    if (length(valid_col) > 0 &&
        !is.na(vals[valid_col[1]]) && vals[valid_col[1]] == 0) next

    # Truncate or pad to n_cols
    if (length(vals) > n_cols) {
      vals <- vals[seq_len(n_cols)]
    } else if (length(vals) < n_cols) {
      vals <- c(vals, rep(NA_real_, n_cols - length(vals)))
    }

    rows_list <- c(rows_list, list(vals))
  }

  if (length(rows_list) == 0)
    return(.lp_err("spl", filepath, "Could not parse any numeric rows"))

  mat <- do.call(rbind, rows_list)
  df  <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names

  # Drop the VALID column — row-validity flag, not a measurement
  if ("VALID" %in% names(df)) df[["VALID"]] <- NULL

  # Store last observed freq in meta as fallback for .normalise_df
  if (is.null(meta$freq_ghz)) meta$freq_ghz <- cur_freq

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

# ── Format 3: Maury / ALPS MDF (BEGIN Sweep variant) ─────────────────────────

parse_mdf <- function(lines, filepath) {
  # Supports two MDF sub-variants:
  #   a) Classic: MDF_VERSION header, BEGIN SWEEP / END SWEEP block (case-insensitive)
  #   b) ALPS export: VAR GRE(real)=..., BEGIN Sweep, header line starting with %,
  #      data rows end with a quoted string column (stripped before parsing)
  in_data      <- FALSE
  hdr_done     <- FALSE
  col_names    <- NULL
  data_rows_raw <- character(0)
  meta_kv      <- list()

  for (ln in lines) {
    ln_t  <- trimws(ln)
    ln_up <- toupper(ln_t)

    # Skip pure comment lines
    if (grepl("^[!]", ln_t)) next

    if (grepl("^BEGIN[[:space:]]+(SWEEP|DATA)", ln_up)) {
      in_data <- TRUE; next
    }
    if (grepl("^END[[:space:]]+(SWEEP|DATA)", ln_up)) {
      in_data <- FALSE; next
    }

    if (!in_data) {
      # VAR NAME(type) = value  — collect as meta
      if (grepl("^VAR[[:space:]]", ln_up)) {
        m <- regmatches(ln_t,
          regexpr("^VAR[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)\\s*\\([^)]*\\)\\s*=\\s*(.+)$",
                  ln_t, perl = TRUE))
        if (length(m) == 1) {
          pts   <- strsplit(trimws(gsub("VAR[[:space:]]+|\\([^)]*\\)|=", " ", m)),
                            "[[:space:]]+")[[1]]
          pts   <- pts[nzchar(pts)]
          if (length(pts) >= 2)
            meta_kv[[tolower(pts[1])]] <- paste(pts[-1], collapse = " ")
        }
        next
      }
      # KEY = VALUE or KEY VALUE
      kv <- regmatches(ln_t,
        regexpr("^([A-Za-z_][A-Za-z0-9_]*)\\s*=?\\s*(.+)$", ln_t, perl = TRUE))
      if (length(kv) == 1) {
        parts <- strsplit(trimws(gsub("=", " ", kv)), "[[:space:]]+")[[1]]
        if (length(parts) >= 2)
          meta_kv[[tolower(parts[1])]] <- paste(parts[-1], collapse = " ")
      }
      next
    }

    # Inside data block ───────────────────────────────────────────────────
    # Header line: starts with % (ALPS) or is a classic alpha-token header line
    if (!hdr_done && (grepl("^%", ln_t) || (grepl("^[A-Za-z_]", ln_t) &&
                                              !grepl("^[!#]", ln_t)))) {
      # Strip leading % and strip trailing (type) annotations like (real) / (string)
      hdr_clean <- trimws(sub("^%", "", ln_t))
      hdr_clean <- gsub("\\([^)]*\\)", "", hdr_clean)   # remove (real)/(string)
      col_tokens <- strsplit(trimws(hdr_clean), "[[:space:]]+")[[1]]
      col_tokens <- col_tokens[nzchar(col_tokens)]
      if (length(col_tokens) >= 2) {
        col_names <- toupper(col_tokens)
        hdr_done  <- TRUE
        next
      }
    }

    if (hdr_done && nzchar(ln_t)) {
      # Strip trailing quoted-string column (e.g. "filename")
      ln_stripped <- gsub('"[^"]*"', "", ln_t)
      ln_stripped <- trimws(ln_stripped)
      if (nzchar(ln_stripped))
        data_rows_raw <- c(data_rows_raw, ln_stripped)
    }
  }

  if (is.null(col_names) || length(data_rows_raw) == 0)
    return(.lp_err("mdf", filepath, "Could not find data block or column headers"))

  # Strip string-type columns from col_names (ALPS has FNAME at end)
  # Keep only those columns that map to numeric positions
  mat <- do.call(rbind, lapply(data_rows_raw, function(r) {
    vals <- strsplit(trimws(r), "[[:space:]]+")[[1]]
    suppressWarnings(as.numeric(vals[seq_len(min(length(vals), length(col_names)))]))
  }))
  # Drop all-NA columns (non-numeric / string-typed columns, e.g. ALPS FNAME)
  if (!is.null(mat) && nrow(mat) > 0) {
    orig_ncol  <- ncol(mat)
    keep       <- apply(mat, 2, function(col) !all(is.na(col)))
    mat        <- mat[, keep, drop = FALSE]
    col_names_used <- col_names[seq_len(orig_ncol)][keep]
  } else {
    col_names_used <- col_names
  }
  mat <- mat[complete.cases(mat), , drop = FALSE]
  if (is.null(mat) || nrow(mat) == 0)
    return(.lp_err("mdf", filepath, "No numeric rows in data block"))

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  names(df) <- col_names_used

  meta <- c(meta_kv, .kv_to_meta(meta_kv))
  list(success = TRUE, meta = meta, points = .normalise_df(df, meta))
}

# ── Format 3b: Focus Microwaves LPCWAVE ──────────────────────────────────────
# Structure:
#   ! comment block with header line:
#     "Point  Gamma  Phase[deg]  Psource[dBm]  PinWaves[dBm] ..."
#   !---------- separator
#   # NNN  <gamma_mag>  <gamma_phase_deg>   <- load-point descriptor
#       data row 1 (space-separated numerics, same cols as header minus Point/Gamma/Phase)
#       data row 2
#       ...
#   # NNN  ...  <- next load point
#
# The data rows contain: Psource PinWaves PoutWaves GainWavesTrd V2 I2 I1 DE ...
# N/A values are treated as NA.

parse_lpcwave <- function(lines, filepath) {
  # Find the column header: inside !-comments, contains "Point" and "Gamma"
  hdr_line <- NULL
  for (ln in lines) {
    clean <- trimws(sub("^[!]+[[:space:]]*", "", ln))
    if (grepl("^Point[[:space:]]+Gamma", clean, ignore.case = TRUE)) {
      hdr_line <- clean
      break
    }
  }
  if (is.null(hdr_line))
    return(.lp_err("lpcwave", filepath, "Could not find column header in comments"))

  # Parse column names — strip [unit] bracketed suffixes for clean names
  raw_cols  <- strsplit(trimws(hdr_line), "[[:space:]]+")[[1]]
  col_names <- toupper(gsub("\\[[^]]*\\]", "", raw_cols))  # strip [deg], [dBm] etc.
  col_names <- trimws(col_names)
  col_names <- col_names[nzchar(col_names)]

  # Point, Gamma, Phase are load-point descriptors stored in # lines — drop them
  # from the per-row data (they appear as the first 3 cols; rows don't include them)
  data_col_names <- col_names[-(1:3)]   # skip Point, Gamma, Phase
  n_data_cols    <- length(data_col_names)

  # Collect metadata from !-comments
  meta_raw <- lines[grepl("^[[:space:]]*!", lines)]
  meta     <- .parse_comment_meta(meta_raw)

  # Parse data: current load-point gamma (mag, phase_deg)
  cur_gamma_mag  <- NA_real_
  cur_gamma_ang  <- NA_real_
  rows_list      <- list()

  for (ln in lines) {
    ln_t <- trimws(ln)
    if (!nzchar(ln_t) || grepl("^!", ln_t)) next

    # Load-point descriptor: # NNN  gamma_mag  gamma_phase_deg
    # Format: "# 001  0.293  109.2"  => parts = ["#", "001", "0.293", "109.2"]
    if (grepl("^#", ln_t)) {
      parts <- strsplit(ln_t, "[[:space:]]+")[[1]]
      if (length(parts) >= 4) {
        cur_gamma_mag <- suppressWarnings(as.numeric(parts[3]))
        cur_gamma_ang <- suppressWarnings(as.numeric(parts[4]))
      } else if (length(parts) == 3) {
        # Fallback: no point number, just "# mag phase"
        cur_gamma_mag <- suppressWarnings(as.numeric(parts[2]))
        cur_gamma_ang <- suppressWarnings(as.numeric(parts[3]))
      }
      next
    }

    # Data row: replace N/A tokens with NA and parse numerics
    ln_clean <- gsub("N/A", "NA", ln_t, ignore.case = TRUE)
    vals     <- suppressWarnings(
      as.numeric(strsplit(trimws(ln_clean), "[[:space:]]+")[[1]])
    )
    if (length(vals) < 2) next

    # Pad / truncate to expected column count
    if (length(vals) > n_data_cols) vals <- vals[seq_len(n_data_cols)]
    if (length(vals) < n_data_cols) vals <- c(vals, rep(NA_real_, n_data_cols - length(vals)))

    # Prepend Gamma_re and Gamma_im derived from load-point descriptor
    g_ang_rad <- (cur_gamma_ang %||% 0) * pi / 180
    g_re      <- (cur_gamma_mag %||% NA) * cos(g_ang_rad)
    g_im      <- (cur_gamma_mag %||% NA) * sin(g_ang_rad)
    rows_list <- c(rows_list, list(c(g_re, g_im, vals)))
  }

  if (length(rows_list) == 0)
    return(.lp_err("lpcwave", filepath, "No data rows parsed"))

  mat <- do.call(rbind, rows_list)
  df  <- as.data.frame(mat, stringsAsFactors = FALSE)
  # Column layout: GL_R, GL_I, then data_col_names
  names(df) <- c("GL_R", "GL_I", data_col_names)

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
  FREQ = "freq_ghz", `FREQ(GHZ)` = "freq_ghz", FREQUENCY = "freq_ghz",
  FRQ  = "freq_ghz",

  # Focus Power Sweep Plan SPL columns (gamma_src1 / gamma_ld1 expand to _RE/_IM)
  GAMMA_SRC1_RE = "gs_r", GAMMA_SRC1_IM = "gs_i",
  GAMMA_LD1_RE  = "gl_r", GAMMA_LD1_IM  = "gl_i",
  # Legacy single-value aliases (kept for backwards compat if not expanded)
  GAMMA_SRC1 = "gs_r", GAMMA_LD1 = "gl_r",
  # ALPS MDF column names
  GAMMA_SRC1_RE_VAL = "gs_r", GAMMA_SRC1_IM_VAL = "gs_i",
  GAMMA_LD1_RE_VAL  = "gl_r", GAMMA_LD1_IM_VAL  = "gl_i",
  GSRE = "gs_r", GSIM = "gs_i",
  GLRE = "gl_r", GLIM = "gl_i",
  # ALPS additional
  BO = "pin_dbm",
  PIN_AVAIL_DBM = "pin_dbm",
  GT_DB = "gain_db",
  POUT_DBM = "pout_dbm",
  IQ_OUT_MA = "idc_ma", IOUT_MA = "idc_ma",
  VQ_IN_V = "vdc_v",
  `EFF_%` = "de_pct", EFF_COL = "de_pct", EFF_ = "de_pct",
  PDIS = "pdc_w", POUTW = "pout_w",
  # LPCWAVE column names
  PINWAVES = "pin_dbm",
  POUTWAVES = "pout_dbm",
  GAINWAVESTRD = "gain_db",
  GAINWAVESPWR = "gp_db",
  V2 = "vdc_v", I2 = "idc_ma",
  `DE_VNA_PA_SCOPEEQN` = "de_pct",
  PSOURCE = "pavs_dbm",
  # Simple tab-separated export columns (S4_Peak.txt style)
  POUTW_COMPRCON = "pout_w",
  PAE_COMPRCON   = "pae_pct",
  POUT_DBM_COMPRCON = "pout_dbm",
  GT_DB_COMPRCON    = "gain_db"
)

.normalise_df <- function(df, meta) {
  names(df) <- toupper(names(df))

  # Rename columns via alias table
  for (alias in names(.COL_ALIASES)) {
    canon <- .COL_ALIASES[[alias]]
    up_alias <- toupper(alias)
    if (up_alias %in% names(df) && !canon %in% names(df)) {
      names(df)[names(df) == up_alias] <- canon
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

  # LPCWAVE: |GL@F0| and phase in degrees → Cartesian (already done in parse_lpcwave
  # but some Focus formats may also use these patterns)
  if ("GL_R" %in% names(df)) names(df)[names(df) == "GL_R"] <- "gl_r"
  if ("GL_I" %in% names(df)) names(df)[names(df) == "GL_I"] <- "gl_i"

  # mA → A
  if ("idc_ma" %in% names(df) && !"idc_a" %in% names(df))
    df$idc_a <- df$idc_ma / 1000

  # Derive pdc_w if absent
  if (!"pdc_w" %in% names(df) && all(c("idc_a","vdc_v") %in% names(df)))
    df$pdc_w <- df$idc_a * df$vdc_v

  # dBm → Watts conversions
  if (!"pout_w" %in% names(df) && "pout_dbm" %in% names(df))
    df$pout_w <- 10^((df$pout_dbm - 30) / 10)
  if (!"pin_w" %in% names(df) && "pin_dbm" %in% names(df))
    df$pin_w  <- 10^((df$pin_dbm  - 30) / 10)

  # Add freq from meta if missing per-row
  if (!"freq_ghz" %in% names(df)) {
    fq <- suppressWarnings(as.numeric(meta$freq_ghz %||% NA))
    df$freq_ghz <- fq
  }

  # Ensure canonical columns exist (NA if not available)
  canonical <- c("gl_r","gl_i","gs_r","gs_i",
                 "pout_dbm","pout_w","pin_dbm","pin_w",
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
