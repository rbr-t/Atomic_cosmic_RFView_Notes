# ============================================================
# calc_pa_lineup.R
# PA Lineup cascade calculation engine.
# Pure function - no Shiny dependencies. Fully unit-testable.
#
# Supports dual operating points (full power + backoff):
#   - Full power: P3dB point
#   - Backoff: Pavg operating point (P3dB - PAR)
# ============================================================

#' PA Lineup Stage-by-Stage Cascade Calculation with Rationale
#'
#' Walks the component chain left-to-right (sorted by x-coordinate) and
#' accumulates gain, DC power, PAE, junction temperature, and compression
#' warnings for both full-power and backoff operating points.
#'
#' @param components  List of component objects (from JavaScript canvas)
#' @param connections List of connection objects (currently unused - spatial sort used)
#' @param input_power_dbm  System input power in dBm (typically P3dB - total_gain)
#' @param backoff_db  Power back-off in dB (typically PAR value)
#' @return Named list with success flag, system metrics, per-stage results, warnings, rationale
lineup_calculate_engine <- function(components,
                                    connections,
                                    input_power_dbm = 0,
                                    backoff_db = 6) {

  if (is.null(components) || length(components) == 0) {
    return(list(
      success  = FALSE,
      message  = "No components in lineup",
      rationale = "Cannot perform calculations without components."
    ))
  }

  # ── Helper: safe property extraction ─────────────────────────
  safeProp <- function(props, name, default) {
    if (is.null(props)) return(default)
    if (is.list(props) && !is.null(props[[name]])) return(props[[name]])
    if (!is.null(names(props)) && name %in% names(props)) return(props[[name]])
    return(default)
  }

  # ── Build rationale log ───────────────────────────────────────
  rationale <- c(
    "═══════════════════════════════════════",
    "  PA LINEUP CALCULATION RATIONALE",
    "═══════════════════════════════════════\n",
    sprintf("Input Power: %.2f dBm (%.4f W)",
            input_power_dbm, 10^(input_power_dbm / 10) / 1000),
    sprintf("Backoff Analysis: %.1f dB below full power\n", backoff_db)
  )

  # ── Sort components by x position (left-to-right signal flow) ─
  tryCatch({
    components <- components[order(sapply(components, function(c) {
      if (is.list(c) && !is.null(c$x)) c$x
      else if ("x" %in% names(c)) c[["x"]]
      else 0
    }))]
  }, error = function(e) invisible(NULL))

  # ── Cascade state variables ───────────────────────────────────
  current_pin    <- input_power_dbm
  current_pin_bo <- input_power_dbm - backoff_db
  total_gain     <- 0
  total_pdc      <- 0
  total_pdc_bo   <- 0
  stage_results  <- list()
  warnings       <- c()

  rationale <- c(rationale,
    "─── Stage-by-Stage Analysis ───",
    "(Full Power | Backoff)\n"
  )

  # ── Process each component ────────────────────────────────────
  for (i in seq_along(components)) {
    comp  <- components[[i]]
    props <- if (is.list(comp) && !is.null(comp$properties))   comp$properties
             else if ("properties" %in% names(comp))            comp[["properties"]]
             else                                                list()

    comp_type  <- if (is.list(comp) && !is.null(comp$type)) comp$type
                  else if ("type" %in% names(comp))         comp[["type"]]
                  else                                       "unknown"

    stage_name <- safeProp(props, "label", paste0("Stage_", i))

    rationale <- c(rationale,
      sprintf("[%d] %s (%s)", i, stage_name, comp_type),
      sprintf("    Input Power: %.2f dBm", current_pin)
    )

    # ── TRANSISTOR ──────────────────────────────────────────────
    if (comp_type == "transistor") {

      gain  <- as.numeric(safeProp(props, "gain",  15))
      p1db  <- as.numeric(safeProp(props, "p1db",  43))
      vdd   <- as.numeric(safeProp(props, "vdd",   28))
      rth   <- as.numeric(safeProp(props, "rth",   2.5))

      # Check if JavaScript already supplied dual operating points
      js_pout_p3db <- safeProp(props, "pout_p3db", NULL)
      js_pout_pavg <- safeProp(props, "pout_pavg", NULL)
      js_pin_p3db  <- safeProp(props, "pin_p3db",  NULL)
      js_pin_pavg  <- safeProp(props, "pin_pavg",  NULL)
      js_pae_p3db  <- safeProp(props, "pae_p3db",  NULL)
      js_pae_pavg  <- safeProp(props, "pae_pavg",  NULL)

      has_dual_op <- !is.null(js_pout_p3db) && !is.null(js_pout_pavg) &&
                     !is.null(js_pin_p3db)  && !is.null(js_pin_pavg)

      cat(sprintf("[%s] dual_op: pout_p3db=%s, pout_pavg=%s, has_dual_op=%s\n",
                  stage_name,
                  if (!is.null(js_pout_p3db)) as.character(js_pout_p3db) else "NULL",
                  if (!is.null(js_pout_pavg)) as.character(js_pout_pavg) else "NULL",
                  has_dual_op))

      if (has_dual_op) {
        # Use JavaScript-calculated dual operating points (applySpecsToComponents)
        pout_dbm    <- as.numeric(js_pout_p3db)
        pout_bo_dbm <- as.numeric(js_pout_pavg)
        pae_full <- if (!is.null(js_pae_p3db)) as.numeric(js_pae_p3db) / 100
                    else as.numeric(safeProp(props, "pae", 50)) / 100
        pae_bo   <- if (!is.null(js_pae_pavg)) as.numeric(js_pae_pavg) / 100
                    else pae_full * 0.7

        rationale <- c(rationale,
          sprintf("    ✓ Using JavaScript dual operating points"),
          sprintf("    Full (P3dB): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%",
                  as.numeric(js_pin_p3db), pout_dbm, pae_full * 100),
          sprintf("    Backoff (Pavg): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%",
                  as.numeric(js_pin_pavg), pout_bo_dbm, pae_bo * 100)
        )
      } else {
        # Fallback: power cascade (not component P3dB)
        pout_dbm    <- current_pin    + gain
        pout_bo_dbm <- current_pin_bo + gain

        pae_full    <- as.numeric(safeProp(props, "pae", 50)) / 100
        pout_ratio  <- 10^((pout_bo_dbm - pout_dbm) / 10)   # linear power ratio
        pae_bo      <- max(pae_full * (pout_ratio ^ 0.8), 0.05)

        rationale <- c(rationale,
          "    [Calculating from power cascade]",
          sprintf("    Full: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm",
                  current_pin, gain, pout_dbm),
          sprintf("    Backoff: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm",
                  current_pin_bo, gain, pout_bo_dbm)
        )
      }

      # Linear power values
      pout_w    <- 10^(pout_dbm    / 10) / 1000
      pout_bo_w <- 10^(pout_bo_dbm / 10) / 1000

      # Compression check - full power
      compressed <- pout_dbm > p1db
      if (compressed) {
        compression_amount <- pout_dbm - p1db
        warnings <- c(warnings,
          sprintf("%s: Compressed by %.1f dB", stage_name, compression_amount))
        rationale <- c(rationale,
          sprintf("    ⚠ WARNING: Output %.2f dBm exceeds P1dB %.2f dBm (compression: %.2f dB)",
                  pout_dbm, p1db, compression_amount))
        pout_dbm <- p1db
        pout_w   <- 10^(pout_dbm / 10) / 1000
      }

      # Compression check - backoff
      compressed_bo <- pout_bo_dbm > p1db
      if (compressed_bo) {
        warnings <- c(warnings,
          sprintf("%s: Compressed at backoff (%.1f dB over P1dB)",
                  stage_name, pout_bo_dbm - p1db))
        rationale <- c(rationale,
          sprintf("    ⚠ WARNING: Backoff output %.2f dBm exceeds P1dB %.2f dBm!",
                  pout_bo_dbm, p1db))
        pout_bo_dbm <- p1db
        pout_bo_w   <- 10^(pout_bo_dbm / 10) / 1000
      }

      # Full power DC / thermal
      ta_c      <- 25
      pdc_w     <- pout_w    / pae_full
      pdiss_w   <- pdc_w     - pout_w
      idc_a     <- pdc_w     / vdd
      tj_c      <- ta_c + pdiss_w   * rth

      # Backoff DC / thermal
      pdc_bo_w  <- pout_bo_w / pae_bo
      pdiss_bo_w <- pdc_bo_w - pout_bo_w
      tj_bo_c   <- ta_c + pdiss_bo_w * rth

      rationale <- c(rationale,
        sprintf("    Full Power: Gain %.2f dB → Pout %.2f dBm (%.4f W)",
                gain, pout_dbm, pout_w),
        sprintf("    Full Power: PAE %.1f%% → PDC = %.3f W, PDiss = %.3f W",
                pae_full * 100, pdc_w, pdiss_w),
        sprintf("    Backoff (%.1f dB): Pout %.2f dBm (%.4f W)",
                backoff_db, pout_bo_dbm, pout_bo_w),
        sprintf("    Backoff: PAE %.1f%% → PDC = %.3f W, PDiss = %.3f W",
                pae_bo * 100, pdc_bo_w, pdiss_bo_w),
        sprintf("    Junction Temp: Full %.1f°C | Backoff %.1f°C", tj_c, tj_bo_c)
      )

      if (tj_c > 150) {
        warnings <- c(warnings,
          sprintf("%s: High junction temp %.0f°C", stage_name, tj_c))
        rationale <- c(rationale,
          sprintf("    ⚠ WARNING: Junction temp %.0f°C exceeds typical limit (150°C)", tj_c))
      }

      stage_results[[length(stage_results) + 1]] <- list(
        stage        = stage_name,
        type         = "transistor",
        pin_dbm      = current_pin,
        pout_dbm     = pout_dbm,
        gain_db      = gain,
        pae_pct      = pae_full * 100,
        pdc_w        = pdc_w,
        pdiss_w      = pdiss_w,
        idc_a        = idc_a,
        tj_c         = tj_c,
        compressed   = compressed,
        technology   = safeProp(props, "technology", "GaN"),
        # Backoff metrics
        pin_bo_dbm   = current_pin_bo,
        pout_bo_dbm  = pout_bo_dbm,
        pae_bo_pct   = pae_bo * 100,
        pdc_bo_w     = pdc_bo_w,
        pdiss_bo_w   = pdiss_bo_w,
        tj_bo_c      = tj_bo_c,
        compressed_bo = compressed_bo
      )

      current_pin    <- pout_dbm
      current_pin_bo <- pout_bo_dbm
      total_gain     <- total_gain + gain
      total_pdc      <- total_pdc  + pdc_w
      total_pdc_bo   <- total_pdc_bo + pdc_bo_w

    # ── MATCHING NETWORK ────────────────────────────────────────
    } else if (comp_type == "matching") {

      loss_db     <- as.numeric(safeProp(props, "loss", 0.5))
      pout_dbm    <- current_pin    - loss_db
      pout_bo_dbm <- current_pin_bo - loss_db

      rationale <- c(rationale,
        sprintf("    Loss: %.2f dB → Full: %.2f dBm | Backoff: %.2f dBm",
                loss_db, pout_dbm, pout_bo_dbm),
        sprintf("    Impedance transformation: %.1f Ω → %.1f Ω",
                as.numeric(safeProp(props, "z_in",  50)),
                as.numeric(safeProp(props, "z_out", 50)))
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage       = stage_name, type  = "matching",
        pin_dbm     = current_pin,  pout_dbm    = pout_dbm,
        loss_db     = loss_db,
        pin_bo_dbm  = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      current_pin    <- pout_dbm
      current_pin_bo <- pout_bo_dbm
      total_gain     <- total_gain - loss_db

    # ── SPLITTER ────────────────────────────────────────────────
    } else if (comp_type == "splitter") {

      loss_db       <- as.numeric(safeProp(props, "loss",        0.3))
      split_ratio   <- as.numeric(safeProp(props, "split_ratio", 0))
      pout_dbm      <- current_pin    - loss_db
      pout_bo_dbm   <- current_pin_bo - loss_db

      rationale <- c(rationale,
        sprintf("    Insertion Loss: %.2f dB, Split Ratio: %.2f dB",
                loss_db, split_ratio),
        sprintf("    Output per path: Full %.2f dBm | Backoff %.2f dBm",
                pout_dbm, pout_bo_dbm)
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage       = stage_name, type  = "splitter",
        pin_dbm     = current_pin,  pout_dbm    = pout_dbm,
        loss_db     = loss_db,      split_ratio = split_ratio,
        pin_bo_dbm  = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      current_pin    <- pout_dbm
      current_pin_bo <- pout_bo_dbm
      total_gain     <- total_gain - loss_db

    # ── COMBINER ────────────────────────────────────────────────
    } else if (comp_type == "combiner") {

      loss_db       <- as.numeric(safeProp(props, "loss", 0.3))
      combiner_type <- safeProp(props, "type", "Wilkinson")

      if (combiner_type == "Doherty" && isTRUE(safeProp(props, "load_modulation", FALSE))) {
        mod_factor <- as.numeric(safeProp(props, "modulation_factor", 2.0))
        rationale <- c(rationale,
          sprintf("    Doherty Combiner with Load Modulation (Factor: %.1f)", mod_factor),
          "    Load modulation improves back-off efficiency"
        )
      }

      # 3 dB combining gain from 2-way combine, minus combiner insertion loss
      pout_dbm    <- current_pin    + 3 - loss_db
      pout_bo_dbm <- current_pin_bo + 3 - loss_db

      rationale <- c(rationale,
        sprintf("    Combining gain: +3 dB (2-way), Loss: %.2f dB", loss_db),
        sprintf("    Output: Full %.2f dBm | Backoff %.2f dBm", pout_dbm, pout_bo_dbm)
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage          = stage_name, type  = "combiner",
        pin_dbm        = current_pin,  pout_dbm    = pout_dbm,
        loss_db        = loss_db,      combining_gain = 3,
        pin_bo_dbm     = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      current_pin    <- pout_dbm
      current_pin_bo <- pout_bo_dbm
      total_gain     <- total_gain + 3 - loss_db
    }

    rationale <- c(rationale, "")
  }

  # ── System summary ────────────────────────────────────────────
  final_pout_dbm  <- current_pin
  final_pout_w    <- 10^(final_pout_dbm  / 10) / 1000
  system_pae      <- if (total_pdc    > 0) (final_pout_w    / total_pdc   ) * 100 else 0

  final_pout_bo_dbm <- current_pin_bo
  final_pout_bo_w   <- 10^(final_pout_bo_dbm / 10) / 1000
  system_pae_bo     <- if (total_pdc_bo > 0) (final_pout_bo_w / total_pdc_bo) * 100 else 0

  rationale <- c(rationale,
    "─── System Summary ───",
    sprintf("Total Gain: %.2f dB", total_gain),
    "\n[FULL POWER]",
    sprintf("  Output Power: %.2f dBm (%.3f W)",    final_pout_dbm, final_pout_w),
    sprintf("  Total DC Power: %.3f W",              total_pdc),
    sprintf("  System PAE: %.1f%%",                  system_pae),
    sprintf("  Heat Dissipation: %.3f W",            total_pdc - final_pout_w),
    sprintf("\n[BACKOFF (%.1f dB)]",                 backoff_db),
    sprintf("  Output Power: %.2f dBm (%.3f W)",    final_pout_bo_dbm, final_pout_bo_w),
    sprintf("  Total DC Power: %.3f W",              total_pdc_bo),
    sprintf("  System PAE: %.1f%%",                  system_pae_bo),
    sprintf("  Heat Dissipation: %.3f W",            total_pdc_bo - final_pout_bo_w)
  )

  if (length(warnings) > 0) {
    rationale <- c(rationale, "\n─── Warnings ───")
    for (w in warnings) rationale <- c(rationale, paste0("⚠ ", w))
  } else {
    rationale <- c(rationale, "\n✓ All stages operating within specifications")
  }

  rationale <- c(rationale, "\n═══════════════════════════════════════")

  list(
    success            = TRUE,
    backoff_db         = backoff_db,
    input_power_dbm    = input_power_dbm,
    final_pout_dbm     = final_pout_dbm,
    final_pout_w       = final_pout_w,
    total_gain         = total_gain,
    total_pdc          = total_pdc,
    system_pae         = system_pae,
    total_pdiss        = total_pdc - final_pout_w,
    # Backoff system metrics
    final_pout_bo_dbm  = final_pout_bo_dbm,
    final_pout_bo_w    = final_pout_bo_w,
    total_pdc_bo       = total_pdc_bo,
    system_pae_bo      = system_pae_bo,
    total_pdiss_bo     = total_pdc_bo - final_pout_bo_w,
    stage_results      = stage_results,
    warnings           = warnings,
    rationale          = paste(rationale, collapse = "\n")
  )
}
