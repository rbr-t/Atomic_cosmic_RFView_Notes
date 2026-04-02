# =============================================================================
# sp_parsers.R
# S-Parameter file format parsers for the PA Design App.
#
# Supported formats:
#   "touchstone"  – Touchstone 1.0 (.s1p, .s2p, .s3p, .s4p, .snp)
#   "touchstone2" – Touchstone 2.0 (.ts, .s2p with [Version] 2.0)
#
# All parsers return a named list:
#   $success      logical
#   $error        character (if !success)
#   $format       character – "touchstone"
#   $filename     character
#   $nports       integer   – number of ports (1, 2, …)
#   $freq_ghz     numeric vector – frequencies in GHz
#   $freq_unit    character – "hz"|"khz"|"mhz"|"ghz" (from file)
#   $data_format  character – "ma"|"db"|"ri"
#   $param_type   character – "s"|"y"|"z"|"h"|"g" (from option line)
#   $z0           numeric   – reference impedance (Ω, default 50)
#   $sp_list      list of length n_freqs, each = nports×nports complex matrix
#   $points       data.frame – long-format: freq_ghz, dataset_tag,
#                              param (e.g. "S11"), real, imag,
#                              mag_linear, mag_db, phase_deg
#   $meta         named list – summary info for display
#   $raw          character vector – original file lines
# =============================================================================

# ── Main dispatcher ───────────────────────────────────────────────────────────
#' Parse a Touchstone S-parameter file.
#'
#' @param filepath  Absolute path to the file.
#' @param format_override  "auto" (default) or "touchstone".
#' @param dataset_tag  Optional tag string; uses filename if NULL.
#' @return Named list as described in the file header.
parse_sp_file <- function(filepath,
                          format_override = "auto",
                          dataset_tag     = NULL) {
  if (!file.exists(filepath))
    return(.sp_err("auto", filepath, paste("File not found:", filepath)))

  lines <- tryCatch(
    readLines(filepath, warn = FALSE, encoding = "UTF-8"),
    error = function(e) readLines(filepath, warn = FALSE)
  )

  fmt <- if (format_override != "auto") format_override
         else detect_sp_format(lines, filepath)

  result <- tryCatch(
    switch(fmt,
      touchstone  = parse_touchstone(lines, filepath),
      touchstone2 = parse_touchstone(lines, filepath),  # same parser handles both
      .sp_err(fmt, filepath, paste("Unsupported format:", fmt))
    ),
    error = function(e) .sp_err(fmt, filepath, conditionMessage(e))
  )

  if (isTRUE(result$success)) {
    result$format   <- fmt
    result$filename <- basename(filepath)
    result$raw      <- lines
    tag <- if (!is.null(dataset_tag) && nzchar(dataset_tag)) dataset_tag
           else .sp_auto_tag(basename(filepath))
    result$dataset_tag <- tag
    if ("points" %in% names(result))
      result$points$dataset_tag <- tag
  }
  result
}

# ── Format auto-detection ─────────────────────────────────────────────────────
detect_sp_format <- function(lines, filepath = NULL) {
  if (!is.null(filepath)) {
    ext <- tolower(sub("^.*\\.([^.]+)$", "\\1", basename(filepath)))
    if (grepl("^s[0-9]+p$", ext) || ext %in% c("ts", "snp")) {
      # Check for Touchstone 2.0 Version marker
      nz <- trimws(lines[nzchar(trimws(lines))])
      if (any(grepl("^\\[Version\\]\\s*2", nz[seq_len(min(5, length(nz)))],
                    ignore.case = TRUE)))
        return("touchstone2")
      return("touchstone")
    }
  }
  # Fallback: look for # option line
  nz <- trimws(lines[nzchar(trimws(lines))])
  for (l in nz[seq_len(min(20, length(nz)))]) {
    if (grepl("^#", l)) return("touchstone")
  }
  "touchstone"
}

# ── Touchstone 1.0 / 2.0 parser ──────────────────────────────────────────────
parse_touchstone <- function(lines, filepath) {

  # ── Determine number of ports from file extension ─────────────────────
  ext <- tolower(sub("^.*\\.([^.]+)$", "\\1", basename(filepath)))
  nports <- if (grepl("^s([0-9]+)p$", ext)) {
    as.integer(sub("^s([0-9]+)p$", "\\1", ext))
  } else {
    # Infer from first data line value count
    2L
  }

  # ── Collect comment lines for metadata ───────────────────────────────
  comment_lines <- lines[grepl("^\\s*!", lines)]

  # ── Parse option line (#) ─────────────────────────────────────────────
  opt_idx   <- which(grepl("^\\s*#", lines))[1]
  freq_unit  <- "ghz"
  param_type <- "s"
  data_format <- "ma"
  z0 <- 50.0

  if (!is.na(opt_idx)) {
    opt <- toupper(trimws(lines[opt_idx]))
    if (grepl("\\bHZ\\b",  opt)) freq_unit <- "hz"
    if (grepl("\\bKHZ\\b", opt)) freq_unit <- "khz"
    if (grepl("\\bMHZ\\b", opt)) freq_unit <- "mhz"
    if (grepl("\\bGHZ\\b", opt)) freq_unit <- "ghz"
    if (grepl("\\bY\\b",   opt)) param_type <- "y"
    if (grepl("\\bZ\\b",   opt)) param_type <- "z"
    if (grepl("\\bH\\b",   opt)) param_type <- "h"
    if (grepl("\\bG\\b",   opt)) param_type <- "g"
    if (grepl("\\bRI\\b",  opt)) data_format <- "ri"
    if (grepl("\\bDB\\b",  opt)) data_format <- "db"
    if (grepl("\\bMA\\b",  opt)) data_format <- "ma"
    m_z0 <- regmatches(opt, regexpr("\\bR\\s+([0-9.]+)", opt))
    if (length(m_z0) > 0)
      z0 <- as.numeric(sub("[Rr]\\s+", "", m_z0))
  }

  # ── Strip comment, option and bracket lines, keep data ───────────────
  data_lines <- lines[
    !grepl("^\\s*[!#\\[]", lines) &
    nzchar(trimws(lines))
  ]

  # ── Tokenise: strip inline comments, split on whitespace ─────────────
  nums_list <- lapply(data_lines, function(l) {
    l <- sub("!.*$", "", l)   # strip trailing inline comment
    toks <- unlist(strsplit(trimws(l), "[[:space:]]+"))
    toks <- toks[nzchar(toks)]
    v <- suppressWarnings(as.numeric(toks))
    v[!is.na(v)]
  })
  nums_list <- nums_list[lengths(nums_list) > 0]

  if (length(nums_list) == 0)
    return(.sp_err("touchstone", filepath, "No parseable numeric data found."))

  # ── Concatenate all numbers (handles multi-line records for N>2 ports) ─
  all_nums <- unlist(nums_list)

  # Values per row: frequency (1) + nports^2 params × 2 (re/im or mag/phase)
  vals_per_row <- 1L + 2L * nports^2L

  if (length(all_nums) < vals_per_row)
    return(.sp_err("touchstone", filepath,
                   sprintf("Insufficient data: need %d values per row, got %d total.",
                           vals_per_row, length(all_nums))))

  nrows <- length(all_nums) %/% vals_per_row
  if (nrows == 0)
    return(.sp_err("touchstone", filepath, "Could not extract any complete data rows."))

  mat <- matrix(all_nums[seq_len(nrows * vals_per_row)],
                nrow = nrows, ncol = vals_per_row, byrow = TRUE)

  # ── Extract frequencies ───────────────────────────────────────────────
  freq_scale <- switch(freq_unit,
    "hz"  = 1e-9,
    "khz" = 1e-6,
    "mhz" = 1e-3,
    "ghz" = 1.0, 1.0)
  freq_ghz <- mat[, 1] * freq_scale

  # ── Convert paired (v1, v2) → complex ────────────────────────────────
  .to_complex <- function(v1, v2) {
    switch(data_format,
      "ri" = complex(real      = v1, imaginary = v2),
      "ma" = complex(modulus   = v1, argument  = v2 * pi / 180),
      "db" = complex(modulus   = 10^(v1 / 20), argument = v2 * pi / 180),
      complex(real = v1, imaginary = v2)   # fallback = RI
    )
  }

  # ── Build list of nports×nports S-param matrices ──────────────────────
  # Touchstone column ordering: S[row,col] = S_rc
  # For 2-port: S11, S21, S12, S22  → col-major fill
  sp_list <- vector("list", nrows)
  for (i in seq_len(nrows)) {
    raw <- mat[i, -1]   # drop frequency column
    v1  <- raw[seq(1L, length(raw), 2L)]
    v2  <- raw[seq(2L, length(raw), 2L)]
    cv  <- .to_complex(v1, v2)
    # matrix() with byrow=FALSE fills column-by-column:
    # cv[1]=S11, cv[2]=S21, cv[3]=S12, cv[4]=S22
    sp_list[[i]] <- matrix(cv, nrow = nports, ncol = nports,
                           byrow = FALSE)
  }

  # ── Build long-format points data.frame ──────────────────────────────
  df_rows <- vector("list", nrows * nports^2)
  k <- 0L
  for (i in seq_len(nrows)) {
    for (ci in seq_len(nports)) {
      for (ri in seq_len(nports)) {
        cv <- sp_list[[i]][ri, ci]
        k  <- k + 1L
        df_rows[[k]] <- list(
          freq_ghz   = freq_ghz[i],
          param      = sprintf("%s%d%d", toupper(param_type), ri, ci),
          real       = Re(cv),
          imag       = Im(cv),
          mag_linear = Mod(cv),
          mag_db     = 20 * log10(max(Mod(cv), 1e-15)),
          phase_deg  = Arg(cv) * 180 / pi
        )
      }
    }
  }
  points <- do.call(rbind, lapply(df_rows, as.data.frame, stringsAsFactors = FALSE))

  list(
    success     = TRUE,
    format      = "touchstone",
    filename    = basename(filepath),
    nports      = nports,
    freq_ghz    = freq_ghz,
    freq_unit   = freq_unit,
    data_format = data_format,
    param_type  = param_type,
    z0          = z0,
    sp_list     = sp_list,
    points      = points,
    meta        = list(
      filename    = basename(filepath),
      nports      = nports,
      z0          = sprintf("%.4g Ω", z0),
      param_type  = toupper(param_type),
      data_format = toupper(data_format),
      freq_unit   = toupper(freq_unit),
      n_freqs     = nrows,
      freq_range  = sprintf("%.4g – %.4g GHz",
                            min(freq_ghz), max(freq_ghz)),
      comments    = paste(comment_lines, collapse = "\n")
    ),
    raw = lines
  )
}

# ── Error helper ──────────────────────────────────────────────────────────────
.sp_err <- function(fmt, filepath, msg) {
  list(
    success  = FALSE,
    format   = fmt,
    filename = basename(filepath),
    error    = msg
  )
}

# ── Auto-tag from filename ────────────────────────────────────────────────────
.sp_auto_tag <- function(fname) {
  base <- tools::file_path_sans_ext(fname)
  # Attempt to shorten: remove common suffix tokens
  if (nchar(base) > 32) {
    tokens <- unlist(strsplit(base, "[_\\-\\s]+"))
    tag    <- paste(tokens[seq_len(min(4, length(tokens)))], collapse = "_")
    if (nchar(tag) < nchar(base)) return(tag)
  }
  base
}

# =============================================================================
# Parameter conversion functions (2-port, operate on complex matrices)
# =============================================================================

#' Convert 2-port S-matrix to Z-parameters.
sp_s_to_z <- function(S, z0 = 50) {
  D <- (1 - S[1,1]) * (1 - S[2,2]) - S[1,2] * S[2,1]
  if (Mod(D) < 1e-15) return(matrix(NA_complex_, 2, 2))
  Z <- matrix(0 + 0i, 2, 2)
  Z[1,1] <- z0 * ((1 + S[1,1]) * (1 - S[2,2]) + S[1,2] * S[2,1]) / D
  Z[1,2] <- z0 *   2 * S[1,2]                                       / D
  Z[2,1] <- z0 *   2 * S[2,1]                                       / D
  Z[2,2] <- z0 * ((1 - S[1,1]) * (1 + S[2,2]) + S[1,2] * S[2,1]) / D
  Z
}

#' Convert 2-port S-matrix to Y-parameters.
sp_s_to_y <- function(S, z0 = 50) {
  D <- (1 + S[1,1]) * (1 + S[2,2]) - S[1,2] * S[2,1]
  if (Mod(D) < 1e-15) return(matrix(NA_complex_, 2, 2))
  y0 <- 1 / z0
  Y  <- matrix(0 + 0i, 2, 2)
  Y[1,1] <- y0 * ((1 - S[1,1]) * (1 + S[2,2]) + S[1,2] * S[2,1]) / D
  Y[1,2] <- y0 *  -2 * S[1,2]                                       / D
  Y[2,1] <- y0 *  -2 * S[2,1]                                       / D
  Y[2,2] <- y0 * ((1 + S[1,1]) * (1 - S[2,2]) + S[1,2] * S[2,1]) / D
  Y
}

#' Convert 2-port S-matrix to h-parameters (via Z).
sp_s_to_h <- function(S, z0 = 50) {
  Z <- sp_s_to_z(S, z0)
  if (any(is.na(Z))) return(matrix(NA_complex_, 2, 2))
  if (Mod(Z[2,2]) < 1e-15) return(matrix(NA_complex_, 2, 2))
  H <- matrix(0 + 0i, 2, 2)
  det_Z <- Z[1,1] * Z[2,2] - Z[1,2] * Z[2,1]
  H[1,1] <- det_Z  / Z[2,2]
  H[1,2] <-  Z[1,2] / Z[2,2]
  H[2,1] <- -Z[2,1] / Z[2,2]
  H[2,2] <-  1      / Z[2,2]
  H
}

#' Convert 2-port S-matrix to ABCD (T) parameters.
sp_s_to_abcd <- function(S, z0 = 50) {
  denom <- 2 * S[2,1]
  if (Mod(denom) < 1e-15) return(matrix(NA_complex_, 2, 2))
  ABCD <- matrix(0 + 0i, 2, 2)
  ABCD[1,1] <- ((1 + S[1,1]) * (1 - S[2,2]) + S[1,2] * S[2,1]) / denom          # A
  ABCD[1,2] <- z0 * ((1 + S[1,1]) * (1 + S[2,2]) - S[1,2] * S[2,1]) / denom     # B
  ABCD[2,1] <- (1 / z0) * ((1 - S[1,1]) * (1 - S[2,2]) - S[1,2] * S[2,1]) / denom  # C
  ABCD[2,2] <- ((1 - S[1,1]) * (1 + S[2,2]) + S[1,2] * S[2,1]) / denom          # D
  ABCD
}

#' Convert 2-port S-matrix to T (scattering transfer) parameters.
sp_s_to_t <- function(S) {
  if (Mod(S[2,1]) < 1e-15) return(matrix(NA_complex_, 2, 2))
  T <- matrix(0 + 0i, 2, 2)
  T[1,1] <- -(S[1,1] * S[2,2] - S[1,2] * S[2,1]) / S[2,1]
  T[1,2] <-   S[1,1] / S[2,1]
  T[2,1] <-  -S[2,2] / S[2,1]
  T[2,2] <-   1      / S[2,1]
  T
}

# ── Convert a full sp_list to long-format data.frame ─────────────────────────
#' @param sp_list  list of nports×nports complex matrices (one per frequency)
#' @param freq_ghz numeric vector of frequencies
#' @param target   one of "S","Z","Y","h","ABCD","T"
#' @param z0       reference impedance
#' @param dataset_tag optional tag
sp_convert_to_df <- function(sp_list, freq_ghz, target = "S",
                              z0 = 50, dataset_tag = "ds1") {
  nports <- nrow(sp_list[[1]])
  rows   <- vector("list", length(sp_list) * nports^2)
  k      <- 0L
  pref   <- switch(target,
    "S" = "S", "Z" = "Z", "Y" = "Y",
    "h" = "h", "ABCD" = "T", "T" = "T", "S")

  for (i in seq_along(sp_list)) {
    Sm <- sp_list[[i]]
    if (any(is.na(Sm))) next
    M <- if (nports == 2) {
      switch(target,
        "S"    = Sm,
        "Z"    = sp_s_to_z(Sm, z0),
        "Y"    = sp_s_to_y(Sm, z0),
        "h"    = sp_s_to_h(Sm, z0),
        "ABCD" = sp_s_to_abcd(Sm, z0),
        "T"    = sp_s_to_t(Sm),
        Sm)
    } else if (nports == 1) {
      # 1-port: only S, Z, Y
      switch(target,
        "Z"    = matrix(z0 * (1 + Sm[1,1]) / (1 - Sm[1,1]), 1, 1),
        "Y"    = matrix((1/z0) * (1 - Sm[1,1]) / (1 + Sm[1,1]), 1, 1),
        Sm)
    } else {
      Sm   # higher ports: return as-is (S only)
    }
    if (any(is.na(M))) next

    for (ci in seq_len(nports)) {
      for (ri in seq_len(nports)) {
        cv  <- M[ri, ci]
        k   <- k + 1L
        lbl <- if (target == "ABCD") {
          c("A","B","C","D")[[(ri - 1L) * 2L + ci]]
        } else {
          sprintf("%s%d%d", pref, ri, ci)
        }
        rows[[k]] <- list(
          freq_ghz   = freq_ghz[i],
          dataset_tag = dataset_tag,
          param      = lbl,
          real       = Re(cv),
          imag       = Im(cv),
          mag_linear = Mod(cv),
          mag_db     = 20 * log10(max(Mod(cv), 1e-15)),
          phase_deg  = Arg(cv) * 180 / pi
        )
      }
    }
  }
  rows <- rows[seq_len(k)]
  if (length(rows) == 0) return(data.frame())
  do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
}

# =============================================================================
# Stability factor computations (2-port only)
# =============================================================================

#' Compute stability metrics for a 2-port S-param dataset.
#'
#' @param sp_list  list of 2×2 complex matrices
#' @param freq_ghz numeric vector (same length)
#' @return data.frame with columns:
#'   freq_ghz, delta_mag, K, mu_in, mu_out, B1, stable (logical)
sp_stability <- function(sp_list, freq_ghz) {
  nf   <- length(sp_list)
  rows <- vector("list", nf)
  for (i in seq_len(nf)) {
    S  <- sp_list[[i]]
    if (nrow(S) != 2 || any(is.na(S))) {
      rows[[i]] <- list(freq_ghz = freq_ghz[i],
                        delta_mag = NA_real_, K = NA_real_,
                        mu_in = NA_real_, mu_out = NA_real_,
                        B1 = NA_real_, msg_db = NA_real_, mag_db = NA_real_,
                        stable = NA)
      next
    }
    s11  <- S[1,1]; s22  <- S[2,2]
    s12  <- S[1,2]; s21  <- S[2,1]
    Delta <- s11 * s22 - s12 * s21
    dM    <- Mod(Delta)
    s11m  <- Mod(s11); s22m <- Mod(s22)
    s12s21 <- Mod(s12 * s21)

    K <- if (s12s21 > 1e-15)
      (1 - s11m^2 - s22m^2 + dM^2) / (2 * s12s21)
    else Inf

    mu_in <- if ((Mod(s22 - Delta * Conj(s11)) + s12s21) > 1e-15)
      (1 - s11m^2) / (Mod(s22 - Delta * Conj(s11)) + s12s21)
    else NA_real_

    mu_out <- if ((Mod(s11 - Delta * Conj(s22)) + s12s21) > 1e-15)
      (1 - s22m^2) / (Mod(s11 - Delta * Conj(s22)) + s12s21)
    else NA_real_

    B1 <- 1 + s11m^2 - s22m^2 - dM^2

    # MSG (Maximum Stable Gain, valid K < 1) and MAG (Maximum Available Gain, K >= 1)
    s21_mag <- Mod(s21)
    s12_mag <- Mod(s12)
    gain_r_db <- if (s12_mag > 1e-15)
      20 * log10(max(s21_mag, 1e-15) / s12_mag)
    else NA_real_
    msg_db_v <- gain_r_db   # MSG = |S21/S12| dB
    mag_db_v <- if (!is.na(K) && K >= 1 && !is.na(gain_r_db))
      gain_r_db + 20 * log10(max(K - sqrt(K^2 - 1), 1e-15))
    else NA_real_

    rows[[i]] <- list(
      freq_ghz  = freq_ghz[i],
      delta_mag = dM,
      K         = K,
      mu_in     = mu_in,
      mu_out    = mu_out,
      B1        = B1,
      msg_db    = msg_db_v,
      mag_db    = mag_db_v,
      stable    = (!is.na(K) && K > 1 && !is.na(mu_in) && mu_in > 1)
    )
  }
  do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
}

#' Compute input and output stability circles for a 2-port.
#'
#' @return list(load = list(center_r, center_i, radius),
#'              source = list(center_r, center_i, radius))
#'   each per frequency as data.frame
sp_stab_circles <- function(sp_list, freq_ghz) {
  nf   <- length(sp_list)
  load_rows   <- vector("list", nf)
  source_rows <- vector("list", nf)

  for (i in seq_len(nf)) {
    S  <- sp_list[[i]]
    if (nrow(S) != 2 || any(is.na(S))) {
      load_rows[[i]] <- source_rows[[i]] <- list(
        freq_ghz = freq_ghz[i], center_r = NA, center_i = NA, radius = NA)
      next
    }
    s11 <- S[1,1]; s22 <- S[2,2]
    s12 <- S[1,2]; s21 <- S[2,1]
    Delta <- s11 * s22 - s12 * s21
    dM2   <- Mod(Delta)^2

    # Load (output) stability circle
    dL <- Mod(s22)^2 - dM2
    if (abs(dL) > 1e-15) {
      CL <- Conj(s22 - Delta * Conj(s11)) / dL
      RL <- Mod(s12 * s21) / abs(dL)
    } else {
      CL <- NA_complex_; RL <- NA_real_
    }
    load_rows[[i]] <- list(
      freq_ghz = freq_ghz[i],
      center_r = Re(CL), center_i = Im(CL), radius = RL)

    # Source (input) stability circle
    dS <- Mod(s11)^2 - dM2
    if (abs(dS) > 1e-15) {
      CS <- Conj(s11 - Delta * Conj(s22)) / dS
      RS <- Mod(s12 * s21) / abs(dS)
    } else {
      CS <- NA_complex_; RS <- NA_real_
    }
    source_rows[[i]] <- list(
      freq_ghz = freq_ghz[i],
      center_r = Re(CS), center_i = Im(CS), radius = RS)
  }

  list(
    load   = do.call(rbind, lapply(load_rows,   as.data.frame, stringsAsFactors = FALSE)),
    source = do.call(rbind, lapply(source_rows, as.data.frame, stringsAsFactors = FALSE))
  )
}
