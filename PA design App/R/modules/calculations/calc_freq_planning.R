# ============================================================
# calc_freq_planning.R
# Pure physical models for RF frequency planning.
# No Shiny dependencies - fully unit-testable.
# ============================================================

#' Atmospheric attenuation model (dB/km)
#'
#' Combines O2 absorption peak (~60 GHz) and H2O absorption peak (~22 GHz)
#' with a baseline linear term.
#' @param fGHz Frequency in GHz
#' @return Attenuation in dB/km
atm_loss_model <- function(fGHz) {
  o2_peak  <- 15 * exp(-((fGHz - 60)^2) / (2 * 5^2))
  h2o_peak <-  8 * exp(-((fGHz - 22)^2) / (2 * 3^2))
  baseline <- 0.01 * fGHz
  baseline + o2_peak + h2o_peak
}

#' LDMOS drain efficiency model (%)
#' Model: max(65 - 0.8*f, 5) %
#' @param f Frequency in GHz
eff_ldmos <- function(f) pmax(65 - 0.8  * f,  5)

#' GaN drain efficiency model (%)
#' Model: max(70 - 0.3*f, 20) %
#' @param f Frequency in GHz
eff_gan   <- function(f) pmax(70 - 0.3  * f, 20)

#' SiGe drain efficiency model (%)
#' Model: max(50 - 0.15*f, 10) %
#' @param f Frequency in GHz
eff_sige  <- function(f) pmax(50 - 0.15 * f, 10)

#' Recommend technology based on operating frequency
#' Rule of thumb: fT > 5 × fop
#' @param freq_ghz Operating frequency in GHz
#' @return Named list: tech, fT_range, expected_gain, color (Bootstrap class)
recommend_technology <- function(freq_ghz) {
  if (freq_ghz < 4) {
    list(tech = "Si LDMOS",           fT_range = "20-40 GHz",   expected_gain = "15-18 dB", color = "primary")
  } else if (freq_ghz < 12) {
    list(tech = "GaAs pHEMT or GaN HEMT", fT_range = "30-100 GHz",  expected_gain = "12-15 dB", color = "success")
  } else if (freq_ghz < 40) {
    list(tech = "GaN HEMT",           fT_range = "50-100 GHz",  expected_gain = "10-12 dB", color = "success")
  } else if (freq_ghz < 100) {
    list(tech = "SiGe HBT or GaN MMIC", fT_range = "200-300 GHz", expected_gain = "8-10 dB",  color = "warning")
  } else {
    list(tech = "InP HEMT or Advanced SiGe", fT_range = "300-600 GHz", expected_gain = "6-8 dB", color = "danger")
  }
}
