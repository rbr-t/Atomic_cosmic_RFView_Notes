# ============================================================
# calc_loss_curves.R
# Passive component insertion-loss models vs frequency.
# Models mirror the JavaScript implementation in pa_lineup_canvas.js
# so R calculations stay consistent with the canvas display.
# No Shiny dependencies - fully unit-testable.
# ============================================================

#' Estimate insertion loss of a passive RF component at a given frequency.
#'
#' Models are empirically derived (see UI reference tab for citations).
#' @param type  Component type string (see choices below)
#' @param freq_ghz Frequency in GHz
#' @return  Insertion loss in dB (scalar)
#'
#' Supported types:
#'   "transmission_line"  – Microstrip on FR4, 10 cm length
#'   "wilkinson_splitter" – 2-way Wilkinson splitter
#'   "wilkinson_combiner" – 2-way Wilkinson combiner
#'   "quadrature_hybrid"  – 90° coupler
#'   "t_junction"         – Simple T-junction splitter
#'   "doherty_combiner"   – Doherty impedance-inverter combiner
#'   "transformer"        – 1:1 RF transformer
estimatePassiveLoss_R <- function(type, freq_ghz) {

  switch(type,

    transmission_line = {
      # Microstrip FR4, 10 cm: skin-effect (√f) + dielectric loss (f)
      (0.05 + 0.15 * sqrt(freq_ghz) + 0.02 * freq_ghz) * 1.0
    },

    wilkinson_splitter = ,
    wilkinson_combiner = {
      # 3 dB ideal split + 0.1 dB transformer IL + freq-dependent loss
      3.0 + 0.1 + 0.05 * freq_ghz
    },

    quadrature_hybrid = {
      # 90° coupler: directivity degrades with f
      0.3 + 0.08 * freq_ghz + 0.02 * freq_ghz^1.5
    },

    t_junction = {
      # Simple junction – no resistor, very low loss, poor isolation
      0.05 + 0.03 * freq_ghz
    },

    doherty_combiner = {
      # Quarter-wave impedance inverter – much lower loss than Wilkinson
      0.2 + 0.02 * freq_ghz + 0.01 * freq_ghz^1.3
    },

    transformer = {
      # 1:1 transformer: three loss regions
      if      (freq_ghz < 0.5) 0.3  + 0.05 * freq_ghz
      else if (freq_ghz < 3.0) 0.2  + 0.03 * (freq_ghz - 0.5)
      else                     0.4  + 0.1  * (freq_ghz - 3.0)
    },

    # Default – unknown component type
    {
      warning(sprintf("estimatePassiveLoss_R: unknown type '%s', returning 0 dB", type))
      0
    }
  )
}
