# ============================================================
# calc_pa_lineup.R
# PA Lineup cascade calculation engine.
# Pure function - no Shiny dependencies. Fully unit-testable.
#
# Topology-aware cascade:
#   - Uses connection graph (pred_map / succ_map) when connections exist
#   - Splitter: subtracts split loss (10*log10(N paths)) + insertion loss
#   - Combiner: sums predecessor powers in watts, then subtracts insertion loss
#   - Falls back to linear x-sort when no connections provided
#
# Supports dual operating points (full power + backoff):
#   - Full power: P3dB point
#   - Backoff: Pavg operating point (P3dB - PAR)
# ============================================================

#' PA Lineup Topology-Aware Cascade Calculation with Rationale
#'
#' When connections are provided, traverses the signal-flow graph in
#' topological order so that splitters correctly split power (-3 dB per 2-way
#' split) and combiners sum the parallel path powers.  Falls back to the
#' original left-to-right x-sort if no connections are available.
#'
#' @param components  List of component objects (from JavaScript canvas)
#' @param connections List of connection objects \{from, to\} (from JavaScript)
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

  # ── dBm helpers ───────────────────────────────────────────────
  dbm2w  <- function(dbm)  10^(dbm / 10) / 1000
  w2dbm  <- function(w)    10 * log10(w * 1000)
  sumdbm <- function(dbm_vec) w2dbm(sum(dbm2w(dbm_vec)))

  # ── Build rationale log ───────────────────────────────────────
  rationale <- c(
    "═══════════════════════════════════════",
    "  PA LINEUP CALCULATION RATIONALE",
    "═══════════════════════════════════════\n",
    "Assumption: port matching (50 Ω) at all interfaces.",
    "  Gain = transducer gain; no mismatch-loss correction applied.\n",
    sprintf("Input Power: %.2f dBm (%.4f W)",
            input_power_dbm, 10^(input_power_dbm / 10) / 1000),
    sprintf("Backoff Analysis: %.1f dB below full power\n", backoff_db)
  )

  # ── Build component lookup by ID ──────────────────────────────
  comp_by_id <- list()
  for (comp in components) {
    cid <- if (!is.null(comp$id)) as.character(comp$id) else NULL
    if (!is.null(cid)) comp_by_id[[cid]] <- comp
  }

  # ── Build predecessor / successor maps from connections ───────
  # pred_map[[id]] = character vector of predecessor IDs
  # succ_map[[id]] = character vector of successor IDs
  has_connections <- !is.null(connections) && length(connections) > 0
  pred_map <- list()
  succ_map <- list()

  if (has_connections) {
    for (conn in connections) {
      from_id <- as.character(conn$from)
      to_id   <- as.character(conn$to)
      if (nchar(from_id) > 0 && nchar(to_id) > 0) {
        pred_map[[to_id]]   <- c(pred_map[[to_id]],   from_id)
        succ_map[[from_id]] <- c(succ_map[[from_id]], to_id)
      }
    }
  }

  # ── Topological sort (Kahn's BFS) or x-sort fallback ─────────
  use_topology <- has_connections && length(comp_by_id) > 0

  if (use_topology) {
    all_ids   <- names(comp_by_id)
    in_degree <- setNames(integer(length(all_ids)), all_ids)
    for (id in all_ids) {
      preds <- pred_map[[id]]
      if (!is.null(preds)) in_degree[id] <- length(preds)
    }
    queue      <- names(in_degree[in_degree == 0])
    topo_order <- character(0)
    while (length(queue) > 0) {
      node   <- queue[1]; queue <- queue[-1]
      topo_order <- c(topo_order, node)
      for (succ_id in succ_map[[node]]) {
        if (!is.na(in_degree[succ_id])) {
          in_degree[succ_id] <- in_degree[succ_id] - 1
          if (in_degree[succ_id] == 0) queue <- c(queue, succ_id)
        }
      }
    }
    # Keep only IDs that exist in comp_by_id
    topo_order   <- topo_order[topo_order %in% names(comp_by_id)]
    ordered_comps <- lapply(topo_order, function(id) comp_by_id[[id]])
    ordered_ids   <- topo_order
    rationale <- c(rationale,
      sprintf("Topology: %d connections, traversing %d nodes in topological order\n",
              length(connections), length(topo_order)))
  } else {
    # Fall back to left-to-right x-sort
    sort_idx      <- order(sapply(components, function(c) {
      if (!is.null(c$x)) c$x else if ("x" %in% names(c)) c[["x"]] else 0
    }))
    ordered_comps <- components[sort_idx]
    ordered_ids   <- sapply(ordered_comps, function(c)
      as.character(if (!is.null(c$id)) c$id else ""))
    rationale <- c(rationale, "Topology: Using x-coordinate sort (no connection graph)\n")
  }

  # ── Per-component output tracking (for topology mode) ─────────
  pout_map    <- list()   # cid -> full-power output (dBm)
  pout_bo_map <- list()   # cid -> backoff output (dBm)

  # ── Cascade totals ────────────────────────────────────────────
  total_gain   <- 0
  total_pdc    <- 0
  total_pdc_bo <- 0
  stage_results <- list()
  warnings      <- c()

  # Track last computed stage output for x-sort linear mode
  linear_pin    <- input_power_dbm
  linear_pin_bo <- input_power_dbm - backoff_db

  rationale <- c(rationale, "─── Stage-by-Stage Analysis ───", "(Full Power | Backoff)\n")

  # ── Process each component ────────────────────────────────────
  for (i in seq_along(ordered_comps)) {
    comp      <- ordered_comps[[i]]
    cid       <- ordered_ids[i]
    props     <- if (!is.null(comp$properties)) comp$properties
                 else if ("properties" %in% names(comp)) comp[["properties"]]
                 else list()

    comp_type  <- if (!is.null(comp$type)) comp$type
                  else if ("type" %in% names(comp)) comp[["type"]]
                  else "unknown"

    stage_name <- safeProp(props, "label", paste0("Stage_", i))

    # ── Determine input power ────────────────────────────────────
    if (use_topology) {
      preds <- pred_map[[cid]]
      if (!is.null(preds) && length(preds) > 0) {
        # Gather all predecessor outputs (fall back to system input if not yet computed)
        p_full <- sapply(preds, function(pid) {
          if (!is.null(pout_map[[pid]])) pout_map[[pid]] else input_power_dbm
        })
        p_bo   <- sapply(preds, function(pid) {
          if (!is.null(pout_bo_map[[pid]])) pout_bo_map[[pid]] else (input_power_dbm - backoff_db)
        })
        # Combiner sums all predecessor powers; everything else takes single predecessor
        if (comp_type == "combiner" && length(p_full) > 1) {
          current_pin    <- sumdbm(p_full)
          current_pin_bo <- sumdbm(p_bo)
        } else {
          current_pin    <- p_full[1]
          current_pin_bo <- p_bo[1]
        }
      } else {
        # No predecessors = source node → use system input
        current_pin    <- input_power_dbm
        current_pin_bo <- input_power_dbm - backoff_db
      }
    } else {
      # Linear fallback: chain stage outputs sequentially
      current_pin    <- linear_pin
      current_pin_bo <- linear_pin_bo
    }

    rationale <- c(rationale,
      sprintf("[%d] %s (%s)", i, stage_name, comp_type),
      sprintf("    Input: %.2f dBm (full) | %.2f dBm (backoff)", current_pin, current_pin_bo)
    )

    # ════════════════════════════════════════════════════════════
    # TRANSISTOR
    # ════════════════════════════════════════════════════════════
    if (comp_type == "transistor") {

      gain <- as.numeric(safeProp(props, "gain",  15))
      p1db <- as.numeric(safeProp(props, "p1db",  43))
      vdd  <- as.numeric(safeProp(props, "vdd",   28))
      rth  <- as.numeric(safeProp(props, "rth",   2.5))

      # Check for JavaScript-supplied dual operating points
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
        pout_dbm    <- as.numeric(js_pout_p3db)
        pout_bo_dbm <- as.numeric(js_pout_pavg)
        pae_full    <- if (!is.null(js_pae_p3db)) as.numeric(js_pae_p3db) / 100
                       else as.numeric(safeProp(props, "pae", 50)) / 100
        pae_bo      <- if (!is.null(js_pae_pavg)) as.numeric(js_pae_pavg) / 100
                       else pae_full * 0.7
        rationale <- c(rationale,
          "    ✓ Using JavaScript dual operating points",
          sprintf("    Full (P3dB): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%",
                  as.numeric(js_pin_p3db), pout_dbm, pae_full * 100),
          sprintf("    Backoff (Pavg): Pin=%.2f, Pout=%.2f dBm, PAE=%.1f%%",
                  as.numeric(js_pin_pavg), pout_bo_dbm, pae_bo * 100)
        )
      } else {
        pout_dbm    <- current_pin    + gain
        pout_bo_dbm <- current_pin_bo + gain
        pae_full    <- as.numeric(safeProp(props, "pae", 50)) / 100
        pout_ratio  <- 10^((pout_bo_dbm - pout_dbm) / 10)
        pae_bo      <- max(pae_full * (pout_ratio ^ 0.8), 0.05)
        rationale <- c(rationale,
          "    [Cascade fallback — no JS dual_op values]",
          sprintf("    Full: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm",
                  current_pin, gain, pout_dbm),
          sprintf("    Backoff: Pin=%.2f + Gain=%.1f → Pout=%.2f dBm",
                  current_pin_bo, gain, pout_bo_dbm)
        )
      }

      pout_w    <- dbm2w(pout_dbm)
      pout_bo_w <- dbm2w(pout_bo_dbm)

      compressed <- pout_dbm > p1db
      if (compressed) {
        warnings <- c(warnings, sprintf("%s: Compressed by %.1f dB", stage_name, pout_dbm - p1db))
        rationale <- c(rationale, sprintf("    ⚠ Compressed: %.2f dBm > P1dB %.2f dBm", pout_dbm, p1db))
        pout_dbm <- p1db; pout_w <- dbm2w(pout_dbm)
      }
      compressed_bo <- pout_bo_dbm > p1db
      if (compressed_bo) {
        warnings <- c(warnings, sprintf("%s: Compressed at backoff", stage_name))
        rationale <- c(rationale, sprintf("    ⚠ Compressed at backoff: %.2f dBm > P1dB %.2f dBm",
                                          pout_bo_dbm, p1db))
        pout_bo_dbm <- p1db; pout_bo_w <- dbm2w(pout_bo_dbm)
      }

      ta_c       <- 25
      pdc_w      <- pout_w    / max(pae_full, 0.01)
      pdiss_w    <- pdc_w     - pout_w
      idc_a      <- pdc_w     / vdd
      tj_c       <- ta_c + pdiss_w * rth
      pdc_bo_w   <- pout_bo_w / max(pae_bo, 0.01)
      pdiss_bo_w <- pdc_bo_w  - pout_bo_w
      tj_bo_c    <- ta_c + pdiss_bo_w * rth

      if (tj_c > 150) {
        warnings <- c(warnings, sprintf("%s: High junction temp %.0f°C", stage_name, tj_c))
        rationale <- c(rationale, sprintf("    ⚠ Tj=%.0f°C exceeds 150°C limit", tj_c))
      }

      rationale <- c(rationale,
        sprintf("    Full: Pout=%.2f dBm, PAE=%.1f%%, PDC=%.3fW, PDiss=%.3fW, Tj=%.1f°C",
                pout_dbm, pae_full*100, pdc_w, pdiss_w, tj_c),
        sprintf("    Backoff: Pout=%.2f dBm, PAE=%.1f%%, PDC=%.3fW, PDiss=%.3fW",
                pout_bo_dbm, pae_bo*100, pdc_bo_w, pdiss_bo_w)
      )

      # Drain Efficiency: DE = Pout / PDC (no Pin subtraction)
      de_full <- if (pdc_w    > 0) (pout_w    / pdc_w   ) * 100 else 0
      de_bo   <- if (pdc_bo_w > 0) (pout_bo_w / pdc_bo_w) * 100 else 0

      stage_results[[length(stage_results) + 1]] <- list(
        stage         = stage_name,  type          = "transistor",  id = cid,
        pin_dbm       = current_pin,  pout_dbm      = pout_dbm,
        gain_db       = gain,         pae_pct       = pae_full * 100,
        de_pct        = de_full,
        gain_full_db  = pout_dbm - current_pin,
        gain_bo_db    = pout_bo_dbm - current_pin_bo,
        pdc_w         = pdc_w,        pdiss_w       = pdiss_w,
        idc_a         = idc_a,        tj_c          = tj_c,
        compressed    = compressed,   technology    = safeProp(props, "technology", "GaN"),
        pin_bo_dbm    = current_pin_bo, pout_bo_dbm = pout_bo_dbm,
        pae_bo_pct    = pae_bo * 100, de_bo_pct     = de_bo,
        pdc_bo_w      = pdc_bo_w,
        pdiss_bo_w    = pdiss_bo_w,   tj_bo_c       = tj_bo_c,
        compressed_bo = compressed_bo
      )

      pout_map[[cid]]    <- pout_dbm
      pout_bo_map[[cid]] <- pout_bo_dbm
      linear_pin    <- pout_dbm
      linear_pin_bo <- pout_bo_dbm
      total_gain    <- total_gain + gain
      total_pdc     <- total_pdc  + pdc_w
      total_pdc_bo  <- total_pdc_bo + pdc_bo_w

    # ════════════════════════════════════════════════════════════
    # MATCHING NETWORK
    # ════════════════════════════════════════════════════════════
    } else if (comp_type == "matching") {

      loss_db     <- as.numeric(safeProp(props, "loss", 0.5))
      pout_dbm    <- current_pin    - loss_db
      pout_bo_dbm <- current_pin_bo - loss_db

      rationale <- c(rationale,
        sprintf("    Loss: %.2f dB → Full: %.2f dBm | Backoff: %.2f dBm",
                loss_db, pout_dbm, pout_bo_dbm),
        sprintf("    Z: %.0f Ω → %.0f Ω",
                as.numeric(safeProp(props, "z_in", 50)),
                as.numeric(safeProp(props, "z_out", 50)))
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage = stage_name, type = "matching",  id = cid,
        pin_dbm = current_pin, pout_dbm = pout_dbm, loss_db = loss_db,
        gain_full_db = -loss_db, gain_bo_db = -loss_db,
        pin_bo_dbm = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      pout_map[[cid]]    <- pout_dbm
      pout_bo_map[[cid]] <- pout_bo_dbm
      linear_pin    <- pout_dbm
      linear_pin_bo <- pout_bo_dbm
      total_gain    <- total_gain - loss_db

    # ════════════════════════════════════════════════════════════
    # SPLITTER  — each output path gets: pin - split_loss - ins_loss
    # For an N-way splitter: split_loss = 10*log10(N) dB
    # We infer N from the connection graph; default 2-way if unknown.
    # ════════════════════════════════════════════════════════════
    } else if (comp_type == "splitter") {

      loss_db     <- as.numeric(safeProp(props, "loss",        0.3))
      split_ratio <- as.numeric(safeProp(props, "split_ratio", 0))

      # Number of output paths from connection graph, default 2
      n_outputs   <- if (use_topology && !is.null(succ_map[[cid]])) {
        max(length(succ_map[[cid]]), 1L)
      } else { 2L }
      split_loss_db <- 10 * log10(n_outputs)   # 3.01 dB for 2-way

      pout_dbm    <- current_pin    - split_loss_db - loss_db
      pout_bo_dbm <- current_pin_bo - split_loss_db - loss_db

      rationale <- c(rationale,
        sprintf("    %d-way split (%.2f dB) + ins. loss %.2f dB",
                n_outputs, split_loss_db, loss_db),
        sprintf("    Per-path output: Full %.2f dBm | Backoff %.2f dBm",
                pout_dbm, pout_bo_dbm)
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage = stage_name, type = "splitter",  id = cid,
        pin_dbm = current_pin, pout_dbm = pout_dbm,
        loss_db = loss_db, split_loss_db = split_loss_db,
        gain_full_db = -(split_loss_db + loss_db),
        gain_bo_db   = -(split_loss_db + loss_db),
        n_outputs = n_outputs, split_ratio = split_ratio,
        pin_bo_dbm = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      pout_map[[cid]]    <- pout_dbm
      pout_bo_map[[cid]] <- pout_bo_dbm
      linear_pin    <- pout_dbm
      linear_pin_bo <- pout_bo_dbm
      total_gain    <- total_gain - split_loss_db - loss_db

    # ════════════════════════════════════════════════════════════
    # COMBINER  — sums predecessor path powers, subtracts ins_loss
    # In topology mode current_pin is already the power sum of
    # all predecessors (computed by sumdbm above).
    # ════════════════════════════════════════════════════════════
    } else if (comp_type == "combiner") {

      loss_db       <- as.numeric(safeProp(props, "loss", 0.3))
      combiner_type <- safeProp(props, "combiner_type", safeProp(props, "type", "Wilkinson"))

      # current_pin is already the summed input (from predecessor pout_map lookups above)
      pout_dbm    <- current_pin    - loss_db
      pout_bo_dbm <- current_pin_bo - loss_db

      # Count number of inputs for rationale
      n_inputs <- if (use_topology && !is.null(pred_map[[cid]])) length(pred_map[[cid]]) else 2L

      rationale <- c(rationale,
        sprintf("    %s combiner, %d inputs summed at %.2f dBm",
                combiner_type, n_inputs, current_pin),
        sprintf("    After combiner loss %.2f dB: Full %.2f dBm | Backoff %.2f dBm",
                loss_db, pout_dbm, pout_bo_dbm)
      )

      stage_results[[length(stage_results) + 1]] <- list(
        stage = stage_name, type = "combiner",  id = cid,
        pin_dbm = current_pin, pout_dbm = pout_dbm,
        loss_db = loss_db, n_inputs = n_inputs,
        gain_full_db = pout_dbm    - current_pin,
        gain_bo_db   = pout_bo_dbm - current_pin_bo,
        pin_bo_dbm = current_pin_bo, pout_bo_dbm = pout_bo_dbm
      )

      pout_map[[cid]]    <- pout_dbm
      pout_bo_map[[cid]] <- pout_bo_dbm
      linear_pin    <- pout_dbm
      linear_pin_bo <- pout_bo_dbm
      # Combining adds 10*log10(n_inputs) in signal power but we track net change
      total_gain    <- total_gain + 10 * log10(n_inputs) - loss_db

    } else if (comp_type == "offset_line") {
      # λ/4 transmission line — contributes insertion loss and 90° phase shift
      loss_db     <- as.numeric(safeProp(props, "loss",           0.2))
      phase_deg   <- as.numeric(safeProp(props, "phase_shift_deg", 90))
      imp_ohm     <- as.numeric(safeProp(props, "impedance",       50))
      role        <- safeProp(props, "offset_role", "phase")
      pout_dbm    <- current_pin    - loss_db
      pout_bo_dbm <- current_pin_bo - loss_db
      stage_name  <- safeProp(props, "label", "λ/4 Line")
      rationale <- c(rationale,
        sprintf("  %s (%s): Z\u2080=%.1f\u03a9, loss=%.2f dB, \u03c6=%d\u00b0",
                stage_name, role, imp_ohm, loss_db, as.integer(phase_deg)),
        sprintf("    Pout=%.2f dBm (full) | %.2f dBm (backoff)", pout_dbm, pout_bo_dbm))
      stage_results[[length(stage_results) + 1]] <- list(
        stage        = stage_name,
        type         = "offset_line",
        id           = cid,
        pin_dbm      = current_pin,
        pout_dbm     = pout_dbm,
        phase_shift_deg = phase_deg,
        impedance    = imp_ohm,
        offset_role  = role,
        loss_db      = loss_db,
        gain_full_db = -loss_db,
        gain_bo_db   = -loss_db,
        pin_bo_dbm   = current_pin_bo,
        pout_bo_dbm  = pout_bo_dbm
      )
      pout_map[[cid]]    <- pout_dbm
      pout_bo_map[[cid]] <- pout_bo_dbm
      linear_pin    <- pout_dbm
      linear_pin_bo <- pout_bo_dbm
      total_gain    <- total_gain - loss_db

    } else {
      # Unknown component type — pass through
      pout_map[[cid]]    <- current_pin
      pout_bo_map[[cid]] <- current_pin_bo
    }

    rationale <- c(rationale, "")
  }

  # ── Final system output: last component(s) with no successors ─
  # In topology mode pick the terminal node (no successors).
  # In linear mode just use the last tracked linear_pin.
  if (use_topology && length(pout_map) > 0) {
    terminal_ids <- names(pout_map)[sapply(names(pout_map), function(id) {
      is.null(succ_map[[id]]) || length(succ_map[[id]]) == 0
    })]
    if (length(terminal_ids) == 1L) {
      final_pout_dbm    <- pout_map[[terminal_ids]]
      final_pout_bo_dbm <- pout_bo_map[[terminal_ids]]
    } else if (length(terminal_ids) > 1L) {
      # Multiple terminal nodes (unusual) – sum them
      final_pout_dbm    <- sumdbm(unlist(pout_map[terminal_ids]))
      final_pout_bo_dbm <- sumdbm(unlist(pout_bo_map[terminal_ids]))
    } else {
      final_pout_dbm    <- linear_pin
      final_pout_bo_dbm <- linear_pin_bo
    }
  } else {
    final_pout_dbm    <- linear_pin
    final_pout_bo_dbm <- linear_pin_bo
  }

  final_pout_w    <- dbm2w(final_pout_dbm)
  final_pout_bo_w <- dbm2w(final_pout_bo_dbm)
  input_power_w   <- dbm2w(input_power_dbm)
  input_power_bo_w <- dbm2w(input_power_dbm - backoff_db)
  # PAE = (Pout - Pin) / PDC * 100  (Power Added Efficiency, not Drain Efficiency)
  system_pae    <- if (total_pdc    > 0) ((final_pout_w    - input_power_w   ) / total_pdc   ) * 100 else 0
  system_pae_bo <- if (total_pdc_bo > 0) ((final_pout_bo_w - input_power_bo_w) / total_pdc_bo) * 100 else 0
  # DE = Pout / PDC * 100  (Drain Efficiency, no Pin)
  system_de     <- if (total_pdc    > 0) (final_pout_w    / total_pdc   ) * 100 else 0
  system_de_bo  <- if (total_pdc_bo > 0) (final_pout_bo_w / total_pdc_bo) * 100 else 0

  rationale <- c(rationale,
    "─── System Summary ───",
    sprintf("Total Gain: %.2f dB", total_gain),
    "\n[FULL POWER]",
    sprintf("  Output Power: %.2f dBm (%.3f W)",  final_pout_dbm, final_pout_w),
    sprintf("  Total DC Power: %.3f W",            total_pdc),
    sprintf("  System PAE: %.1f%%",                system_pae),
    sprintf("  System DE:  %.1f%%",                system_de),
    sprintf("  Heat Dissipation: %.3f W",          total_pdc - final_pout_w),
    sprintf("\n[BACKOFF (%.1f dB)]",               backoff_db),
    sprintf("  Output Power: %.2f dBm (%.3f W)",  final_pout_bo_dbm, final_pout_bo_w),
    sprintf("  Total DC Power: %.3f W",            total_pdc_bo),
    sprintf("  System PAE: %.1f%%",                system_pae_bo),
    sprintf("  System DE:  %.1f%%",                system_de_bo),
    sprintf("  Heat Dissipation: %.3f W",          total_pdc_bo - final_pout_bo_w)
  )

  if (length(warnings) > 0) {
    rationale <- c(rationale, "\n─── Warnings ───")
    for (w in warnings) rationale <- c(rationale, paste0("⚠ ", w))
  } else {
    rationale <- c(rationale, "\n✓ All stages operating within specifications")
  }
  rationale <- c(rationale, "\n═══════════════════════════════════════")

  list(
    success           = TRUE,
    backoff_db        = backoff_db,
    input_power_dbm   = input_power_dbm,
    final_pout_dbm    = final_pout_dbm,
    final_pout_w      = final_pout_w,
    total_gain        = total_gain,
    total_pdc         = total_pdc,
    system_pae        = system_pae,
    system_de         = system_de,
    total_pdiss       = total_pdc - final_pout_w,
    final_pout_bo_dbm = final_pout_bo_dbm,
    final_pout_bo_w   = final_pout_bo_w,
    total_pdc_bo      = total_pdc_bo,
    system_pae_bo     = system_pae_bo,
    system_de_bo      = system_de_bo,
    total_pdiss_bo    = total_pdc_bo - final_pout_bo_w,
    stage_results     = stage_results,
    warnings          = warnings,
    rationale         = paste(rationale, collapse = "\n")
  )
}
