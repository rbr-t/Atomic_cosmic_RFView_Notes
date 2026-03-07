# ============================================================
# calc_guardrails.R
# Technology guardrail calculation engine.
# Pure functions — no Shiny dependencies. Fully testable.
#
# Loads technology_guardrails.yaml and provides:
#   - loadGuardrails()          : load YAML into R list
#   - getTechGuardrail()        : get single technology limits
#   - calcAvailableGain()       : gain vs freq from fT model
#   - calcPAEBackoff()          : PAE vs backoff power model
#   - validateDeviceParams()    : per-component sanity check
#   - buildDesignSpaceData()    : data frame for 4D plot
#   - buildGainBandwidthData()  : data frame for gain-bandwidth plot
#   - buildPAEBackoffData()     : data frame for PAE-backoff curves
# ============================================================

# ── Load guardrail definitions ─────────────────────────────────────────────
loadGuardrails <- function(yaml_path = "../config/technology_guardrails.yaml") {
  if (!file.exists(yaml_path)) {
    # Try relative to R/ directory
    alt_paths <- c(
      "config/technology_guardrails.yaml",
      "../config/technology_guardrails.yaml",
      file.path(dirname(sys.frame(1)$ofile %||% "."), "../config/technology_guardrails.yaml")
    )
    for (p in alt_paths) {
      if (file.exists(p)) { yaml_path <- p; break }
    }
  }
  if (!file.exists(yaml_path)) {
    warning("[Guardrails] YAML not found at: ", yaml_path, " — using embedded fallback")
    return(.guardrail_fallback())
  }
  yaml::read_yaml(yaml_path)
}

# ── Fallback data (in case YAML path not resolved) ─────────────────────────
`%||%` <- function(a, b) if (!is.null(a)) a else b

.guardrail_fallback <- function() {
  list(technologies = list(
    GaN_SiC = list(
      label = "GaN HEMT (SiC)", color = "#70AD47",
      freq_range_ghz = list(min = 0.5, max = 40, sweet_spot_min = 1, sweet_spot_max = 18),
      gain_db = list(ft_ghz_typical = 70, ft_ghz_max = 100),
      pae_pct = list(max_practical_p3db = 72, typical_p3db = 60, at_6db_backoff = 35),
      pout_density_w_per_mm = list(min = 2, typical = 5, max = 12),
      vdd = list(typical = 28, max_abs = 84),
      thermal = list(max_tj_c = 225)
    )
  ))
}


# ── Available Gain model ────────────────────────────────────────────────────
#' Estimate available power gain at a given frequency using the 20dB/decade
#' rolloff from fT.  Includes the effect of Rg*Cgd (for fmax-limited regime).
#'
#' @param freq_ghz    Operating frequency (GHz)
#' @param ft_ghz      Transition frequency fT (GHz)
#' @param fmax_ghz    Maximum oscillation frequency fmax (GHz); NULL = 2*fT
#' @return            Available gain (dB) — clamped to [0, 35] for realism
calcAvailableGain <- function(freq_ghz, ft_ghz, fmax_ghz = NULL) {
  if (is.null(fmax_ghz)) fmax_ghz <- ft_ghz * 2.2
  # MSG (Maximum Stable Gain proxy): 20*log10(fT/f)
  msg_db  <- 20 * log10(pmax(ft_ghz / pmax(freq_ghz, 0.001), 1))
  # MAG (Maximum Available Gain): 20*log10(fmax/f) is slightly optimistic
  # blend the two: G_av = 0.7*MSG + 0.3*MAG
  mag_db  <- 20 * log10(pmax(fmax_ghz / pmax(freq_ghz, 0.001), 1))
  g_av_db <- 0.7 * msg_db + 0.3 * mag_db
  # Clamp: real transistors don't go below 0 dB or above ~35 dB at low freq
  pmin(pmax(g_av_db, 0), 35)
}


# ── PAE vs backoff model ────────────────────────────────────────────────────
#' Estimate PAE at a given output backoff level.
#' Uses a first-principles model based on class of operation.
#'
#' @param pae_p3db_pct  PAE at P3dB (full power), percent
#' @param backoff_db    Output power backoff from P3dB (positive number, dB)
#' @param pa_class      "A", "AB", "B", "E", "F", "Doherty"
#' @return              PAE at backoff (percent)
calcPAEBackoff <- function(pae_p3db_pct, backoff_db, pa_class = "AB") {
  eta_p3db <- pae_p3db_pct / 100
  # Power ratio relative to P3dB
  pout_ratio <- 10^(-backoff_db / 10)   # linear power ratio

  eta_bo <- switch(pa_class,
    # Class A: DC bias is FIXED regardless of output power — PAE collapses linearly
    "A"  = eta_p3db * pout_ratio,
    # Class B: Idc proportional to sqrt(Pout) — PAE ~ eta_p3db * sqrt(pout_ratio)
    "B"  = eta_p3db * sqrt(pout_ratio),
    # Class AB: between A and B — use exponent ~0.6
    "AB" = eta_p3db * (pout_ratio ^ 0.6),
    # Class E/F (switched/harmonic): stays efficient down to ~6 dB BO, then drops
    "E"  = {
      if (backoff_db <= 4) eta_p3db * (pout_ratio ^ 0.3)
      else                 eta_p3db * (pout_ratio ^ 0.55)
    },
    "F"  = {
      if (backoff_db <= 4) eta_p3db * (pout_ratio ^ 0.25)
      else                 eta_p3db * (pout_ratio ^ 0.50)
    },
    # Doherty: flat efficiency in the backoff region (ideal), then drops like Class B
    "Doherty" = {
      doherty_bo <- 6   # ideal Doherty flat region
      if (backoff_db <= doherty_bo) {
        # In the Doherty BO window, PAE stays close to peak
        eta_p3db * (pout_ratio ^ 0.15)
      } else {
        # Beyond the BO window, falls like Class B
        eta_at_bo <- eta_p3db * ((10^(-doherty_bo/10)) ^ 0.15)
        ratio_from_bo <- backoff_db - doherty_bo
        eta_at_bo * ((10^(-ratio_from_bo/10)) ^ 0.55)
      }
    },
    # Default — Class AB
    eta_p3db * (pout_ratio ^ 0.6)
  )

  pmax(eta_bo * 100, 1)   # floor at 1%
}


# ── Device parameter validation ─────────────────────────────────────────────
#' Validate a single device's proposed parameters against technology guardrails.
#'
#' @param tech_key      Technology key string (matches YAML key)
#' @param freq_ghz      Operating frequency (GHz)
#' @param gain_db       Claimed gain (dB)
#' @param pae_pct       Claimed PAE at P3dB (%)
#' @param pout_dbm      Claimed Pout at P3dB (dBm)
#' @param vdd           Supply voltage (V)
#' @param pout_density  Pout density (W/mm) — optional
#' @param guardrails    Loaded guardrail list (from loadGuardrails)
#' @return              List: status ("ok"/"warning"/"error"), messages
validateDeviceParams <- function(tech_key, freq_ghz, gain_db, pae_pct, pout_dbm,
                                  vdd, pout_density = NULL, guardrails = NULL) {
  if (is.null(guardrails)) guardrails <- loadGuardrails()
  tech <- guardrails$technologies[[tech_key]]
  if (is.null(tech)) {
    return(list(status = "error", messages = paste("Unknown technology:", tech_key)))
  }
  rules   <- guardrails$validation_rules
  status  <- "ok"
  msgs    <- character(0)
  warns   <- character(0)
  errors  <- character(0)

  # ── 1. Frequency range ────────────────────────────────────────
  fr <- tech$freq_range_ghz
  if (freq_ghz < fr$min || freq_ghz > fr$max) {
    errors <- c(errors, sprintf(
      "Frequency %.1f GHz is outside %s operating range (%.1f–%.1f GHz)",
      freq_ghz, tech$label, fr$min, fr$max))
  } else if (freq_ghz < fr$sweet_spot_min || freq_ghz > fr$sweet_spot_max) {
    warns <- c(warns, sprintf(
      "%.1f GHz is outside the sweet spot (%.1f–%.1f GHz) for %s",
      freq_ghz, fr$sweet_spot_min, fr$sweet_spot_max, tech$label))
  }

  # ── 2. Gain vs frequency ─────────────────────────────────────
  ft  <- tech$gain_db$ft_ghz_typical
  fmx <- tech$gain_db$fmax_ghz_typical %||% (ft * 2.2)
  max_gain <- calcAvailableGain(freq_ghz, ft, fmx)
  margin   <- rules$gain_vs_freq$margin_db  %||% 3
  hard_err <- rules$gain_vs_freq$error_margin_db %||% 6
  if (gain_db > max_gain + hard_err) {
    errors <- c(errors, sprintf(
      "Gain %.1f dB exceeds physics limit for %s at %.1f GHz (max achievable ≈ %.1f dB from fT/f model)",
      gain_db, tech$label, freq_ghz, max_gain))
  } else if (gain_db > max_gain + margin) {
    warns <- c(warns, sprintf(
      "Gain %.1f dB is aggressive for %s at %.1f GHz — limit ≈ %.1f dB (requires Class-F or optimistic fT)",
      gain_db, tech$label, freq_ghz, max_gain))
  }

  # ── 3. PAE sanity ────────────────────────────────────────────
  pae_max  <- tech$pae_pct$max_practical_p3db %||% 78.5
  pae_warn <- rules$pae_sanity$warning_threshold_pct %||% 70
  pae_hard <- rules$pae_sanity$error_threshold_pct   %||% 80
  if (pae_pct > pae_hard) {
    errors <- c(errors, sprintf(
      "PAE %.1f%% exceeds absolute physical limit (%.1f%% Class-B theoretical maximum)",
      pae_pct, 78.5))
  } else if (pae_pct > pae_max) {
    warns <- c(warns, sprintf(
      "PAE %.1f%% exceeds reported best practice for %s (typical max %.1f%%) — very optimistic",
      pae_pct, tech$label, pae_max))
  }

  # ── 4. Vdd derating ──────────────────────────────────────────
  vdd_max_abs <- tech$vdd$max_abs %||% (tech$vdd$typical * 2)

  if (vdd > vdd_max_abs) {
    errors <- c(errors, sprintf(
      "Vdd %.1f V exceeds absolute maximum %.1f V for %s (Vbr violation risk)",
      vdd, vdd_max_abs, tech$label))
  }

  # ── 5. Pout density ──────────────────────────────────────────
  if (!is.null(pout_density)) {
    pd_max  <- tech$pout_density_w_per_mm$max  %||% 999
    pd_warn <- pd_max * (1 - (rules$pout_density$warning_margin_pct %||% 10) / 100)
    if (pout_density > pd_max) {
      errors <- c(errors, sprintf(
        "Pout density %.2f W/mm exceeds process maximum %.2f W/mm for %s",
        pout_density, pd_max, tech$label))
    } else if (pout_density > pd_warn) {
      warns <- c(warns, sprintf(
        "Pout density %.2f W/mm is near the process limit (%.2f W/mm) for %s",
        pout_density, pd_max, tech$label))
    }
  }

  # ── Compile result ────────────────────────────────────────────
  if (length(errors) > 0) status <- "error"
  else if (length(warns) > 0) status <- "warning"

  list(
    status   = status,
    errors   = errors,
    warnings = warns,
    tech     = tech$label,
    freq_ghz = freq_ghz,
    max_gain_available = round(max_gain, 1),
    pae_max_practical  = pae_max
  )
}


# ── Build Design Space data frame (for 4D bubble plot) ─────────────────────
#' Generate the technology design space data frame.
#' Each row = one (technology, frequency) sample point.
#' Columns: tech, label, color, freq_ghz, pout_density_typ, pae_p3db, gain_db
#' This populates the background "envelope" regions.
#'
#' @param guardrails  Loaded guardrail list
#' @param freq_points Number of frequency points per technology
#' @return data.frame
buildDesignSpaceData <- function(guardrails = NULL, freq_points = 60) {
  if (is.null(guardrails)) guardrails <- loadGuardrails()
  techs <- guardrails$technologies

  rows <- list()
  for (tech_key in names(techs)) {
    tech <- techs[[tech_key]]
    fr   <- tech$freq_range_ghz

    # Generate log-spaced freqs within tech range
    freqs <- exp(seq(log(fr$min), log(fr$max), length.out = freq_points))
    ft    <- tech$gain_db$ft_ghz_typical     %||% 50
    fmx   <- tech$gain_db$fmax_ghz_typical   %||% (ft * 2.2)
    pd    <- tech$pout_density_w_per_mm
    pae_p <- tech$pae_pct

    # PAE decreases slightly with frequency (empirical rule: ~0.5%/GHz for most techs)
    pae_base <- pae_p$typical_p3db %||% 45
    pae_max  <- pae_p$max_practical_p3db %||% 65

    in_sweet <- freqs >= fr$sweet_spot_min & freqs <= fr$sweet_spot_max

    for (j in seq_along(freqs)) {
      f  <- freqs[j]
      g  <- calcAvailableGain(f, ft, fmx)
      # PAE degrades at high freq: scale by (fT/f)^0.15 capped at 1
      pae_scale <- pmin((ft / f) ^ 0.08, 1)
      rows[[length(rows) + 1]] <- data.frame(
        tech            = tech_key,
        label           = tech$label,
        color           = tech$color,
        freq_ghz        = f,
        gain_db         = g,
        pout_density_typ= pd$typical %||% 1,
        pout_density_max= pd$max     %||% 2,
        pae_typ_pct     = pae_base * pae_scale,
        pae_max_pct     = pae_max  * pae_scale,
        vdd_typ         = tech$vdd$typical %||% 28,
        in_sweet_spot   = in_sweet[j],
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}


# ── Build Gain-Bandwidth envelope data ─────────────────────────────────────
#' Per-technology gain vs frequency envelope (for overlay on bubble chart).
#' @return data.frame with cols: tech, label, color, freq_ghz, gain_max, gain_typ
buildGainBandwidthData <- function(guardrails = NULL) {
  if (is.null(guardrails)) guardrails <- loadGuardrails()
  techs <- guardrails$technologies

  rows <- list()
  freqs <- exp(seq(log(0.1), log(300), length.out = 200))

  for (tech_key in names(techs)) {
    tech <- techs[[tech_key]]
    fr   <- tech$freq_range_ghz
    ft   <- tech$gain_db$ft_ghz_typical   %||% 50
    fmx  <- tech$gain_db$fmax_ghz_typical %||% (ft * 2.2)
    ftx  <- tech$gain_db$ft_ghz_max       %||% (ft * 1.3)
    fmxx <- tech$gain_db$fmax_ghz_max     %||% (fmx * 1.3)

    for (f in freqs) {
      if (f < fr$min * 0.5 || f > fr$max * 2) next
      rows[[length(rows) + 1]] <- data.frame(
        tech      = tech_key,
        label     = tech$label,
        color     = tech$color,
        freq_ghz  = f,
        gain_typ  = calcAvailableGain(f, ft,  fmx),
        gain_max  = calcAvailableGain(f, ftx, fmxx),
        in_range  = (f >= fr$min & f <= fr$max),
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}


# ── Build PAE vs Backoff curves ─────────────────────────────────────────────
#' @return data.frame: tech, label, color, backoff_db, pae_pct, pa_class
buildPAEBackoffData <- function(guardrails = NULL) {
  if (is.null(guardrails)) guardrails <- loadGuardrails()
  techs <- guardrails$technologies
  classes <- c("A", "AB", "B", "Doherty", "F")
  backoffs <- seq(0, 16, by = 0.25)

  rows <- list()
  for (tech_key in names(techs)) {
    tech     <- techs[[tech_key]]
    pae_p3db <- tech$pae_pct$typical_p3db %||% 45

    for (cls in classes) {
      for (bo in backoffs) {
        rows[[length(rows) + 1]] <- data.frame(
          tech       = tech_key,
          label      = paste(tech$label, "-", cls),
          tech_label = tech$label,
          color      = tech$color,
          pa_class   = cls,
          backoff_db = bo,
          pae_pct    = calcPAEBackoff(pae_p3db, bo, cls),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, rows)
}


# ── Build summary table for UI display ──────────────────────────────────────
#' Flat summary table of all key guardrail parameters per technology.
#' @return data.frame suitable for DT rendering
buildGuardrailSummaryTable <- function(guardrails = NULL) {
  if (is.null(guardrails)) guardrails <- loadGuardrails()
  techs <- guardrails$technologies

  rows <- lapply(names(techs), function(tk) {
    t  <- techs[[tk]]
    fr <- t$freq_range_ghz
    gd <- t$gain_db
    pae<- t$pae_pct
    pd <- t$pout_density_w_per_mm
    data.frame(
      Technology        = t$label,
      `Freq Range (GHz)`= sprintf("%.1f – %.1f", fr$min, fr$max),
      `Sweet Spot (GHz)`= sprintf("%.1f – %.1f", fr$sweet_spot_min, fr$sweet_spot_max),
      `fT typ (GHz)`    = gd$ft_ghz_typical  %||% NA,
      `fmax typ (GHz)`  = gd$fmax_ghz_typical %||% NA,
      `Vdd typ (V)`     = t$vdd$typical       %||% NA,
      `Vdd max (V)`     = t$vdd$max_abs        %||% NA,
      `Pout density W/mm`= sprintf("%.1f – %.1f", pd$min %||% 0, pd$max %||% 0),
      `PAE P3dB typ (%)`= pae$typical_p3db    %||% NA,
      `PAE P3dB max (%)`= pae$max_practical_p3db %||% NA,
      `Max Tj (°C)`     = t$thermal$max_tj_c  %||% NA,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
