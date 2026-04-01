# ═══════════════════════════════════════════════════════════════════════════
# calc_transistor_sizing.R
# Pure-R transistor design functions for PA stage synthesis.
#
# All functions are pure: no Shiny, no reactives, no side-effects.
# Called by server_transistor_design.R.
# ═══════════════════════════════════════════════════════════════════════════


# ── 1. Optimum load resistance ───────────────────────────────────────────────

#' Calculate optimum load resistance for Class-AB/B PA
#'
#' Ropt = (Vdd − Vknee)² / (2 × Pout)
#'
#' @param Vdd_V    Supply voltage [V]
#' @param Vknee_V  Knee voltage [V]  (typically 2 V for GaN, 0.3 V for GaAs)
#' @param Pout_W   Desired output power [W]
#' @return Named list: Ropt_ohm, formula_str, Vdd_V, Vknee_V, Pout_W
calc_ropt <- function(Vdd_V, Vknee_V, Pout_W) {

  if (!is.numeric(Pout_W) || Pout_W <= 0) {
    return(list(
      Ropt_ohm    = NA_real_,
      formula_str = NA_character_,
      Vdd_V       = Vdd_V,
      Vknee_V     = Vknee_V,
      Pout_W      = Pout_W,
      warning     = "Pout_W must be > 0"
    ))
  }

  Ropt <- (Vdd_V - Vknee_V)^2 / (2 * Pout_W)

  formula_str <- sprintf(
    "(%.1fV - %.1fV)\u00b2 / (2 \u00d7 %.3fW)",
    Vdd_V, Vknee_V, Pout_W
  )

  list(
    Ropt_ohm    = Ropt,
    formula_str = formula_str,
    Vdd_V       = Vdd_V,
    Vknee_V     = Vknee_V,
    Pout_W      = Pout_W
  )
}


# ── 2. Gate periphery (total gate width) ────────────────────────────────────

#' Calculate required transistor gate width
#'
#' W_mm = Pout_W / (power_density_W_per_mm × PAE_fraction)
#'
#' @param Pout_W                Desired output power [W]
#' @param power_density_W_per_mm  Technology power density [W/mm]
#'                               (e.g. 2.5 W/mm for standard GaN-on-SiC)
#' @param pae_frac              Power-Added Efficiency as fraction (0–1)
#' @return Named list: gate_width_mm, formula_str, Pout_W, power_density, pae_pct
calc_gate_width <- function(Pout_W, power_density_W_per_mm, pae_frac) {

  if (!is.numeric(power_density_W_per_mm) || power_density_W_per_mm <= 0 ||
      !is.numeric(pae_frac) || pae_frac <= 0) {
    return(list(
      gate_width_mm  = NA_real_,
      formula_str    = NA_character_,
      Pout_W         = Pout_W,
      power_density  = power_density_W_per_mm,
      pae_pct        = if (is.numeric(pae_frac)) pae_frac * 100 else NA_real_,
      warning        = "power_density and pae_frac must be > 0"
    ))
  }

  pae_pct      <- pae_frac * 100
  gate_width   <- Pout_W / (power_density_W_per_mm * pae_frac)

  formula_str <- sprintf(
    "%.3fW / (%.2fW/mm \u00d7 %.0f%%)",
    Pout_W, power_density_W_per_mm, pae_pct
  )

  list(
    gate_width_mm  = gate_width,
    formula_str    = formula_str,
    Pout_W         = Pout_W,
    power_density  = power_density_W_per_mm,
    pae_pct        = pae_pct
  )
}


# ── 3. Quiescent bias current – Class AB ────────────────────────────────────

#' Calculate quiescent drain current for Class AB/B biasing
#'
#' Idq_mA = Ids_max_mA × (conduction_angle_deg − 180) / 360 × 0.5
#'
#' Class B  = 180°  (Idq ≈ 0)
#' Class AB = 180°–360°  (Idq is a fraction of Imax)
#' Class A  = 360°  (Idq = Imax/2)
#'
#' @param Ids_max_mA          Maximum drain current [mA]
#' @param conduction_angle_deg Conduction angle [°], default 240° (Class AB)
#' @return Named list: Idq_mA, formula_str, conduction_angle_deg, Ids_max_mA, class_label
calc_idq_class_ab <- function(Ids_max_mA, conduction_angle_deg = 240) {

  # Classify operating class
  class_label <- if (conduction_angle_deg == 180) {
    "Class B"
  } else if (conduction_angle_deg > 180 && conduction_angle_deg < 360) {
    "Class AB"
  } else if (conduction_angle_deg == 360) {
    "Class A"
  } else {
    "Class AB"   # clamp out-of-range inputs to AB label
  }

  # Standard approximation: Idq fraction scales linearly between 0 (Class B)
  # and Imax/2 (Class A) as the conduction angle spans 180°→360°.
  Idq_mA <- Ids_max_mA * (conduction_angle_deg - 180) / 360 * 0.5

  formula_str <- sprintf(
    "%.0fmA \u00d7 (%.0f\u00b0 \u2212 180\u00b0) / 360\u00b0 \u00d7 0.5",
    Ids_max_mA, conduction_angle_deg
  )

  list(
    Idq_mA              = Idq_mA,
    formula_str         = formula_str,
    conduction_angle_deg = conduction_angle_deg,
    Ids_max_mA          = Ids_max_mA,
    class_label         = class_label
  )
}


# ── 4. Doherty amplifier sizing ──────────────────────────────────────────────

#' Calculate Doherty amplifier transistor sizing
#'
#' Supported topologies:
#'   "symmetric"      – equal main/peak devices, 6 dB back-off OBO
#'   "asymmetric_6dB" – n=2, peak device 2× larger
#'   "asymmetric_9dB" – n=3, peak device 3× larger, 9 dB OBO
#'
#' Quarter-wave combiner impedance: Zt = sqrt(Ropt_main × 50)
#'
#' @param Ropt_main_ohm  Optimum load resistance of the main transistor [Ω]
#' @param topology       One of "symmetric", "asymmetric_6dB", "asymmetric_9dB"
#' @return Named list: Ropt_main_ohm, Ropt_peak_ohm, Zt_ohm, gate_ratio,
#'         n_factor, topology, formula_Zt
calc_doherty_sizing <- function(Ropt_main_ohm, topology = "symmetric") {

  n_factor <- switch(topology,
    "symmetric"      = 2,
    "asymmetric_6dB" = 2,
    "asymmetric_9dB" = 3,
    2   # default: symmetric
  )

  gate_ratio    <- if (topology == "symmetric") 1.0 else as.numeric(n_factor)
  Ropt_peak     <- n_factor * Ropt_main_ohm

  # Quarter-wave combiner: Zt matches Ropt_main into 50 Ω system
  Zt            <- sqrt(Ropt_main_ohm * 50)

  formula_Zt    <- sprintf(
    "\u221a(%.1f\u03a9 \u00d7 50\u03a9) = %.1f\u03a9",
    Ropt_main_ohm, Zt
  )

  list(
    Ropt_main_ohm  = Ropt_main_ohm,
    Ropt_peak_ohm  = Ropt_peak,
    Zt_ohm         = Zt,
    gate_ratio     = gate_ratio,
    n_factor       = n_factor,
    topology       = topology,
    formula_Zt     = formula_Zt
  )
}


# ── 5. L-match impedance transformation ─────────────────────────────────────

#' Calculate L-match network element values
#'
#' Q = sqrt(Zmax/Zmin − 1)
#' Step-down (Zs > Zl):  series-L + shunt-C
#' Step-up   (Zs < Zl):  series-C + shunt-L
#'
#' @param Zs_ohm   Source impedance [Ω]
#' @param Zl_ohm   Load impedance [Ω]
#' @param freq_ghz Frequency [GHz]
#' @return Named list: Q, L_nH, C_pF, bw_pct, topology, Zs_ohm, Zl_ohm,
#'         freq_ghz, formula_str
calc_matching_lmatch <- function(Zs_ohm, Zl_ohm, freq_ghz) {

  # Trivial case: no transformation needed
  if (isTRUE(all.equal(Zs_ohm, Zl_ohm))) {
    return(list(
      Q           = 0,
      L_nH        = NA_real_,
      C_pF        = NA_real_,
      bw_pct      = Inf,
      topology    = "none",
      Zs_ohm      = Zs_ohm,
      Zl_ohm      = Zl_ohm,
      freq_ghz    = freq_ghz,
      formula_str = "Zs = Zl — no matching required"
    ))
  }

  Zmax <- max(Zs_ohm, Zl_ohm)
  Zmin <- min(Zs_ohm, Zl_ohm)
  Q    <- sqrt(Zmax / Zmin - 1)
  omega <- 2 * pi * freq_ghz * 1e9   # angular frequency [rad/s]

  if (Zs_ohm > Zl_ohm) {
    # ── Step-down: series-L into shunt-C ──────────────────────────────────
    topology <- "step_down_L"
    L_nH     <- Q * Zmin / omega * 1e9
    C_pF     <- Q / (omega * Zmax) * 1e12
  } else {
    # ── Step-up: series-C into shunt-L ────────────────────────────────────
    topology <- "step_up_C"
    L_nH     <- Zmax / (Q * omega) * 1e9
    C_pF     <- 1 / (Q * omega * Zmin) * 1e12
  }

  bw_pct <- 100 / Q   # approximate fractional bandwidth [%]

  formula_str <- sprintf(
    "Q = \u221a(%.1f\u03a9 / %.1f\u03a9 \u2212 1) = %.2f",
    Zmax, Zmin, Q
  )

  list(
    Q           = Q,
    L_nH        = L_nH,
    C_pF        = C_pF,
    bw_pct      = bw_pct,
    topology    = topology,
    Zs_ohm      = Zs_ohm,
    Zl_ohm      = Zl_ohm,
    freq_ghz    = freq_ghz,
    formula_str = formula_str
  )
}


# ── 6. Doherty quarter-wave combiner (microstrip) ───────────────────────────

#' Calculate Doherty quarter-wave combiner physical dimensions
#'
#' Uses the standard closed-form approximation for microstrip line width
#' (Wheeler 1977, corrected by Hammerstad & Jensen 1980).
#'
#' For narrow strips (W/h < 2): W/h = 8·exp(A) / (exp(2A) − 2)
#' where A = (Zt/60)·sqrt((εr+1)/2) + (εr−1)/(εr+1)·(0.23 + 0.11/εr)
#'
#' @param Ropt_main_ohm Optimum load resistance of main transistor [Ω]
#' @param freq_ghz      Centre frequency [GHz]
#' @param er            Substrate relative permittivity (default 3.55 – Rogers 4003C)
#' @param h_mm          Substrate thickness [mm] (default 0.508 mm – 20 mil)
#' @return Named list: Zt_ohm, len_mm, width_mm, lambda_g_mm, er, h_mm,
#'         freq_ghz, formula_Zt, formula_len
calc_doherty_combiner <- function(Ropt_main_ohm, freq_ghz,
                                  er = 3.55, h_mm = 0.508) {

  Zt <- sqrt(Ropt_main_ohm * 50)

  # Guided wavelength: λg = c / (f × sqrt(εr))  [mm]
  # c = 299792.458 mm/μs  →  use c in mm/s: 299792458000 mm/s
  # Simplified: λg [mm] = 299792.458 / (freq_ghz × 1000 × sqrt(er))
  lambda_g_mm <- 299792.458 / (freq_ghz * 1000 * sqrt(er))
  len_mm      <- lambda_g_mm / 4

  # ── Wheeler / Hammerstad microstrip width calculation ──────────────────
  # Parameter A (equation valid for both wide and narrow lines)
  A        <- (Zt / 60) * sqrt((er + 1) / 2) +
              (er - 1) / (er + 1) * (0.23 + 0.11 / er)
  exp_A    <- exp(A)
  exp_2A   <- exp(2 * A)
  W_over_h <- 8 * exp_A / (exp_2A - 2)   # narrow-strip formula (W/h < 2)

  # Wide-strip correction (W/h ≥ 2): apply Hammerstad approximation
  # B = 377π / (2 × Zt × sqrt(er))
  B_param   <- 377 * pi / (2 * Zt * sqrt(er))
  W_over_h_wide <- (2 / pi) * (B_param - 1 -
                    log(2 * B_param - 1) +
                    (er - 1) / (2 * er) *
                    (log(B_param - 1) + 0.39 - 0.61 / er))

  # Select formula based on which branch gives the physically correct result
  # (both converge near W/h = 2; choose the branch consistent with narrow vs wide)
  W_over_h_final <- if (W_over_h < 2) W_over_h else W_over_h_wide
  width_mm <- W_over_h_final * h_mm

  formula_Zt  <- sprintf(
    "\u221a(%.1f\u03a9 \u00d7 50\u03a9) = %.1f\u03a9",
    Ropt_main_ohm, Zt
  )
  formula_len <- sprintf(
    "\u03bbg/4 = %.1f mm at %.2f GHz (\u03b5r=%.2f)",
    len_mm, freq_ghz, er
  )

  list(
    Zt_ohm      = Zt,
    len_mm      = len_mm,
    width_mm    = width_mm,
    lambda_g_mm = lambda_g_mm,
    er          = er,
    h_mm        = h_mm,
    freq_ghz    = freq_ghz,
    formula_Zt  = formula_Zt,
    formula_len = formula_len
  )
}


# ── 7. Orchestrator: full transistor design suite ───────────────────────────

#' Run the complete transistor sizing design suite for one PA stage
#'
#' @param stage_result  List / data-frame row containing at minimum:
#'                        pout_dbm  – output power [dBm]
#'                        pae_pct   – PAE [%]
#'                        vdd_v     – supply voltage [V]  (optional, default 28 V)
#' @param freq_ghz      Design frequency [GHz]
#' @param topology      "doherty_symmetric" | "doherty_asymmetric_6dB" |
#'                      "doherty_asymmetric_9dB" | "single_ended"
#' @param er            Substrate εr (default 3.55)
#' @param h_mm          Substrate thickness [mm] (default 0.508)
#' @return Named list with elements: ropt, gate_width, idq, doherty, matching_input,
#'         combiner, pout_w, pout_dbm, freq_ghz, topology
calc_transistor_design_suite <- function(stage_result,
                                         freq_ghz,
                                         topology = "doherty_symmetric",
                                         er       = 3.55,
                                         h_mm     = 0.508) {

  # ── Extract stage parameters ──────────────────────────────────────────
  pout_dbm <- if (!is.null(stage_result$pout_dbm)) stage_result$pout_dbm else 47.0
  pae_pct  <- if (!is.null(stage_result$pae_pct))  stage_result$pae_pct  else 45.0
  vdd_v    <- if (!is.null(stage_result$vdd_v))    stage_result$vdd_v    else 28.0

  # ── GaN technology defaults ───────────────────────────────────────────
  vknee_v             <- 2.0    # GaN knee voltage [V]
  power_density_w_mm  <- 2.5    # GaN-on-SiC typical [W/mm]

  # ── Convert dBm → W ──────────────────────────────────────────────────
  pout_w <- 10^(pout_dbm / 10) / 1000

  # ── 1. Optimum load resistance ────────────────────────────────────────
  ropt_res <- calc_ropt(
    Vdd_V   = vdd_v,
    Vknee_V = vknee_v,
    Pout_W  = pout_w
  )

  # ── 2. Gate width ─────────────────────────────────────────────────────
  gate_width_res <- calc_gate_width(
    Pout_W               = pout_w,
    power_density_W_per_mm = power_density_w_mm,
    pae_frac             = pae_pct / 100
  )

  # ── 3. Quiescent current  (Ids_max ≈ 800 mA/mm × gate_width_mm) ──────
  ids_max_ma <- 800 * if (!is.na(gate_width_res$gate_width_mm))
                        gate_width_res$gate_width_mm else 1.0
  idq_res    <- calc_idq_class_ab(
    Ids_max_mA          = ids_max_ma,
    conduction_angle_deg = 240   # Class AB default
  )

  # ── 4 & 6. Doherty-specific calculations ─────────────────────────────
  is_doherty <- grepl("doherty", topology, ignore.case = TRUE)

  if (is_doherty) {
    doh_topo <- sub("doherty_", "", topology)   # strip prefix for inner function
    doherty_res <- calc_doherty_sizing(
      Ropt_main_ohm = ropt_res$Ropt_ohm,
      topology      = doh_topo
    )
    combiner_res <- calc_doherty_combiner(
      Ropt_main_ohm = ropt_res$Ropt_ohm,
      freq_ghz      = freq_ghz,
      er            = er,
      h_mm          = h_mm
    )
    # Use Doherty main-device Ropt as the input matching source impedance
    zs_input <- ropt_res$Ropt_ohm
  } else {
    doherty_res  <- NULL
    combiner_res <- NULL
    zs_input     <- ropt_res$Ropt_ohm
  }

  # ── 5. Input matching (device input → 50 Ω driver) ───────────────────
  # Gate input impedance approximated as Ropt/5 (typical for GaN HEMT)
  zin_approx <- zs_input / 5
  matching_input_res <- calc_matching_lmatch(
    Zs_ohm   = 50,        # source: driver output / system impedance
    Zl_ohm   = max(zin_approx, 1),   # load: transistor gate (guard against 0)
    freq_ghz = freq_ghz
  )

  # ── Assemble and return ───────────────────────────────────────────────
  list(
    ropt          = ropt_res,
    gate_width    = gate_width_res,
    idq           = idq_res,
    doherty       = doherty_res,
    matching_input = matching_input_res,
    combiner      = combiner_res,
    pout_w        = pout_w,
    pout_dbm      = pout_dbm,
    freq_ghz      = freq_ghz,
    topology      = topology
  )
}


# ── 8. Human-readable design rationale ──────────────────────────────────────

#' Format transistor design rationale as labelled decision strings
#'
#' @param design_suite  Output of calc_transistor_design_suite()
#' @return Character vector; one string per design parameter
format_transistor_rationale <- function(design_suite) {

  lines <- character(0)

  # ── Ropt ──────────────────────────────────────────────────────────────
  r <- design_suite$ropt
  if (!is.null(r) && !is.na(r$Ropt_ohm)) {
    lines <- c(lines, sprintf(
      "\u25b8 Ropt: %.1f \u03a9 \u2190 %s",
      r$Ropt_ohm, r$formula_str
    ))
  }

  # ── Gate width ────────────────────────────────────────────────────────
  gw <- design_suite$gate_width
  if (!is.null(gw) && !is.na(gw$gate_width_mm)) {
    lines <- c(lines, sprintf(
      "\u25b8 Gate width: %.2f mm \u2190 %s",
      gw$gate_width_mm, gw$formula_str
    ))
  }

  # ── Quiescent current ─────────────────────────────────────────────────
  idq <- design_suite$idq
  if (!is.null(idq) && !is.na(idq$Idq_mA)) {
    lines <- c(lines, sprintf(
      "\u25b8 Idq (%s): %.1f mA \u2190 %s",
      idq$class_label, idq$Idq_mA, idq$formula_str
    ))
  }

  # ── Doherty topology ──────────────────────────────────────────────────
  doh <- design_suite$doherty
  if (!is.null(doh)) {
    lines <- c(lines, sprintf(
      "\u25b8 Doherty Zt: %.1f \u03a9 \u2190 %s  [topology: %s, n=%d]",
      doh$Zt_ohm, doh$formula_Zt, doh$topology, doh$n_factor
    ))
    lines <- c(lines, sprintf(
      "\u25b8 Peak Ropt: %.1f \u03a9 \u2190 %d \u00d7 %.1f \u03a9 (main)",
      doh$Ropt_peak_ohm, doh$n_factor, doh$Ropt_main_ohm
    ))
  }

  # ── Input matching ────────────────────────────────────────────────────
  im <- design_suite$matching_input
  if (!is.null(im)) {
    if (im$topology == "none") {
      lines <- c(lines, "\u25b8 Input match: not required (Zs = Zl)")
    } else {
      lines <- c(lines, sprintf(
        "\u25b8 Input match (%s): L=%.2f nH, C=%.2f pF, BW\u224890/Q=%.0f%% \u2190 %s",
        im$topology, im$L_nH, im$C_pF, im$bw_pct, im$formula_str
      ))
    }
  }

  # ── Combiner ─────────────────────────────────────────────────────────
  cb <- design_suite$combiner
  if (!is.null(cb)) {
    lines <- c(lines, sprintf(
      "\u25b8 QW combiner: Zt=%.1f \u03a9, len=%.2f mm, W=%.3f mm \u2190 %s",
      cb$Zt_ohm, cb$len_mm, cb$width_mm, cb$formula_len
    ))
  }

  # ── Power summary ─────────────────────────────────────────────────────
  lines <- c(lines, sprintf(
    "\u25b8 Pout: %.1f dBm (%.3f W) @ %.2f GHz  [%s]",
    design_suite$pout_dbm, design_suite$pout_w,
    design_suite$freq_ghz, design_suite$topology
  ))

  lines
}
