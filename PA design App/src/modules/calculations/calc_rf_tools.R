# ============================================================
# calc_rf_tools.R
# Pure RF calculation functions for the RF Tools tab.
# No Shiny dependencies — fully unit-testable.
#
# Covers:
#   - Power / voltage / frequency converter math
#   - S-parameter conversions
#   - MTTF Arrhenius reliability model
#   - Thermal network analysis
# ============================================================


# ── Power Conversions ─────────────────────────────────────────

#' Convert Watts to dBm and dBW
calc_power_from_watts <- function(watt) {
  list(
    watt = watt,
    dbm  = 10 * log10(watt * 1000),
    dbw  = 10 * log10(watt)
  )
}

#' Convert dBm to Watts and dBW
calc_power_from_dbm <- function(dbm) {
  list(
    dbm  = dbm,
    watt = 10^(dbm / 10) / 1000,
    dbw  = dbm - 30
  )
}


# ── Voltage / Impedance ───────────────────────────────────────

#' Convert voltage + impedance to power
calc_power_from_voltage <- function(v, z = 50) {
  power_w   <- v^2 / z
  list(
    voltage_v   = v,
    impedance_ohm = z,
    power_w     = power_w,
    power_dbm   = 10 * log10(power_w * 1000),
    current_a   = v / z
  )
}


# ── Frequency / Wavelength ───────────────────────────────────

#' Compute free-space and effective wavelengths from frequency
#' @param freq_ghz  Frequency in GHz
#' @param er        Relative permittivity of medium (1.0 = free space)
calc_wavelengths <- function(freq_ghz, er = 1.0) {
  freq_hz     <- freq_ghz * 1e9
  lambda_m    <- 3e8 / freq_hz
  lambda_eff_m <- lambda_m / sqrt(er)
  list(
    freq_ghz        = freq_ghz,
    freq_mhz        = freq_ghz * 1000,
    er              = er,
    lambda_mm       = lambda_m    * 1000,
    lambda_eff_mm   = lambda_eff_m * 1000,
    quarter_wave_mm = lambda_eff_m * 1000 / 4,
    half_wave_mm    = lambda_eff_m * 1000 / 2
  )
}


# ── S-Parameter Conversions ───────────────────────────────────

#' S11 (magnitude + phase) → Γ, return loss, VSWR
#' @param s11_mag   S11 linear magnitude (0–1)
#' @param s11_phase S11 phase in degrees
calc_sparams <- function(s11_mag, s11_phase) {
  gamma_real      <- s11_mag * cos(s11_phase * pi / 180)
  gamma_imag      <- s11_mag * sin(s11_phase * pi / 180)
  return_loss_db  <- -20 * log10(s11_mag)
  vswr            <- (1 + s11_mag) / (1 - s11_mag)
  list(
    s11_mag         = s11_mag,
    s11_phase_deg   = s11_phase,
    gamma_real      = gamma_real,
    gamma_imag      = gamma_imag,
    return_loss_db  = return_loss_db,
    vswr            = vswr
  )
}


# ── MTTF — Arrhenius Reliability Model ───────────────────────

#' Calculate MTTF using a simplified Arrhenius model
#'
#' @param tj_c             Junction temperature (°C)
#' @param voltage_stress   Voltage stress factor (normalised, 1.0 = nominal)
#' @param current_stress   Current stress factor (normalised, 1.0 = nominal)
#' @param mttf_base_hours  Base MTTF at reference conditions (default 1 M hours)
#' @param Ea               Activation energy in eV (default 0.7 eV, typical GaAs/GaN)
#' @param T_ref_c          Reference temperature in °C (default 125 °C)
calc_mttf <- function(tj_c,
                      voltage_stress   = 1.0,
                      current_stress   = 1.0,
                      mttf_base_hours  = 1e6,
                      Ea               = 0.7,
                      T_ref_c          = 125) {

  k       <- 8.617e-5          # Boltzmann constant (eV/K)
  T_ref   <- T_ref_c + 273.15  # Reference temp in Kelvin
  T_op    <- tj_c   + 273.15   # Operating temp in Kelvin

  AF             <- exp((Ea / k) * (1 / T_ref - 1 / T_op))
  voltage_factor <- voltage_stress^2
  current_factor <- current_stress^2
  mttf_adj       <- mttf_base_hours * AF / (voltage_factor * current_factor)
  failure_rate   <- 1 / mttf_adj

  list(
    tj_c           = tj_c,
    T_ref_c        = T_ref_c,
    activation_energy_eV = Ea,
    acceleration_factor  = AF,
    voltage_factor = voltage_factor,
    current_factor = current_factor,
    mttf_hours     = mttf_adj,
    mttf_years     = mttf_adj / 8760,
    failure_rate   = failure_rate
  )
}

#' Reliability function R(t) = exp(-λt) using MTTF from calc_mttf()
#' @param time_hours  Vector of time points in hours
#' @param mttf_hours  MTTF in hours
calc_reliability_curve <- function(time_hours, mttf_hours) {
  lambda      <- 1 / mttf_hours
  reliability <- exp(-lambda * time_hours)
  data.frame(time_hours = time_hours, reliability_pct = reliability * 100)
}


# ── Thermal Network Analysis ──────────────────────────────────

#' Full thermal stack-up: junction → case → heatsink → ambient
#'
#' @param pout_w         Output power in Watts
#' @param pae_pct        Power-added efficiency in percent  
#' @param rth_jc         Rθjc — junction-to-case thermal resistance (°C/W)
#' @param rth_cs         Rθcs — case-to-heatsink thermal resistance (°C/W)
#' @param rth_sa         Rθsa — heatsink-to-ambient thermal resistance (°C/W)
#' @param ta_c           Ambient temperature in °C
#' @param tj_max_c       Maximum allowable junction temperature in °C
calc_thermal <- function(pout_w,
                         pae_pct,
                         rth_jc   = 1.5,
                         rth_cs   = 0.5,
                         rth_sa   = 2.0,
                         ta_c     = 25,
                         tj_max_c = 200) {

  pae       <- pae_pct / 100
  pdc_w     <- pout_w / pae
  pdiss_w   <- pdc_w - pout_w
  rth_total <- rth_jc + rth_cs + rth_sa

  ts_c  <- ta_c + pdiss_w * rth_sa
  tc_c  <- ta_c + pdiss_w * (rth_cs + rth_sa)
  tj_c  <- ta_c + pdiss_w * rth_total
  margin_c <- tj_max_c - tj_c

  status <- if (margin_c > 20) "SAFE"
            else if (margin_c > 0) "MARGINAL"
            else "VIOLATION"

  list(
    pout_w      = pout_w,
    pae_pct     = pae_pct,
    pdc_w       = pdc_w,
    pdiss_w     = pdiss_w,
    rth_jc      = rth_jc,
    rth_cs      = rth_cs,
    rth_sa      = rth_sa,
    rth_total   = rth_total,
    ta_c        = ta_c,
    ts_c        = ts_c,
    tc_c        = tc_c,
    tj_c        = tj_c,
    tj_max_c    = tj_max_c,
    margin_c    = margin_c,
    status      = status
  )
}
