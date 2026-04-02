# ============================================================
# calc_link_budget.R
# RF link budget calculations.
# Uses standard Friis / thermal-noise formulas.
# No Shiny dependencies - fully unit-testable.
# ============================================================

#' Calculate a complete RF link budget.
#'
#' @param tx_power_dbm  Transmitter output power (dBm)
#' @param tx_gain_dbi   Transmit antenna gain (dBi)
#' @param rx_gain_dbi   Receive antenna gain (dBi)
#' @param distance_km   Link distance (km)
#' @param freq_ghz      Carrier frequency (GHz)
#' @param bw_mhz        Receiver noise bandwidth (MHz)
#' @param noise_figure_db  Receiver noise figure (dB)
#' @param snr_req_db    Required SNR at detector (dB)
#' @return Named list with all budget components
calc_link_budget <- function(tx_power_dbm,
                             tx_gain_dbi,
                             rx_gain_dbi,
                             distance_km,
                             freq_ghz,
                             bw_mhz,
                             noise_figure_db,
                             snr_req_db) {

  # Free-Space Path Loss:  FSPL = 20·log10(d) + 20·log10(f) + 92.45  [dB]
  # (valid for d in km, f in GHz)
  fspl <- 20 * log10(distance_km) + 20 * log10(freq_ghz) + 92.45

  # Received power
  p_rx <- tx_power_dbm + tx_gain_dbi - fspl + rx_gain_dbi

  # Thermal noise power: N = kTB + NF  (kT0 = -174 dBm/Hz at 290 K)
  bw_hz       <- bw_mhz * 1e6
  noise_power <- -174 + 10 * log10(bw_hz) + noise_figure_db

  # Signal-to-noise ratio achieved
  snr <- p_rx - noise_power

  # Link margin over required SNR
  margin <- snr - snr_req_db

  list(
    fspl        = fspl,
    p_rx        = p_rx,
    noise_power = noise_power,
    snr         = snr,
    margin      = margin,
    status      = if (margin > 0) "PASS" else "FAIL"
  )
}
