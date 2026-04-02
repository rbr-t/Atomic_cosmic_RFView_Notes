# Layout Agent - RF PA Design Plugin
# PCB DRC, substrate constraints, via checks, transmission line validation
# Essence embedded from: Deep Specialist (anomaly-first, engineering domain authority, feedback report)

LayoutAgent <- R6Class("LayoutAgent",
  inherit = BaseAgent,

  public = list(
    name = "Layout Agent",
    expertise = "Microstrip/stripline layout, substrate selection, via design, DRC rule checking, thermal layout, EM constraint validation",

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query   <- task$query
      context <- if (!is.null(task$context)) task$context else list()
      layout  <- if (!is.null(task$layout))  task$layout  else NULL
      substrate <- if (!is.null(task$substrate)) task$substrate else self$default_substrate()
      spec    <- if (!is.null(task$spec))    task$spec    else list()

      # --- DEEP SPECIALIST: Anomaly-first scan before any layout recommendation ---
      anomaly_report <- self$scan_layout_anomalies(layout, substrate, spec)

      if (any(anomaly_report$severities == "CRITICAL")) {
        return(list(
          verdict        = "BLOCKED",
          anomaly_report = anomaly_report,
          message        = "CRITICAL layout anomaly detected. Resolve DRC violations before proceeding.",
          confidence     = 0,
          valid          = FALSE
        ))
      }

      system_prompt <- paste(
        "You are an expert RF PCB and MMIC layout engineer.",
        "You specialise in:\n",
        "- Microstrip and CPW transmission line design\n",
        "- Substrate selection for RF/microwave (Rogers RO4003, RO4350, Taconic, alumina)\n",
        "- Via design for RF grounding (via fences, ground planes, thermal vias)\n",
        "- Component placement for minimum parasitic inductance\n",
        "- EM isolation between signal paths (coupled microstrip, guard traces)\n",
        "- Thermal via arrays and heat spreading for GaN/LDMOS\n",
        "- DRC rules: minimum spacing, minimum width, annular ring\n",
        "Always reference substrate parameters (er, tan_delta, h) when discussing transmission lines.",
        "Quote physical dimensions (mm or mils) with tolerances where relevant."
      )

      # Enrich query with layout/substrate context
      if (!is.null(substrate)) {
        query <- paste(query,
          "\nSubstrate:", substrate$name,
          "| er:", substrate$er,
          "| h:", substrate$h_mm, "mm",
          "| tan_delta:", substrate$tan_delta
        )
      }
      if (!is.null(spec$freq_ghz)) query <- paste(query, "\nFrequency:", spec$freq_ghz, "GHz")

      # Run DRC if layout data available
      drc_result <- if (!is.null(layout)) self$run_drc(layout, substrate, spec) else NULL

      kb_results   <- self$query_knowledge_base(query, top_k = 3)
      llm_response <- self$call_llm(
        paste(query,
              "\nKB references:\n", paste(sapply(kb_results$results, function(r) r$text), collapse = "\n"),
              if (!is.null(drc_result)) paste("\nDRC result:", drc_result$summary) else ""),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      # --- DEEP SPECIALIST: Feedback report ---
      feedback <- self$generate_drc_feedback(drc_result, anomaly_report)

      self$log_action("layout_review", list(
        substrate  = if (!is.null(substrate)) substrate$name else "unknown",
        drc_pass   = if (!is.null(drc_result)) drc_result$pass else NA,
        confidence = validation$confidence
      ))

      return(list(
        guidance       = llm_response$content,
        anomaly_report = anomaly_report,
        drc_result     = drc_result,
        feedback       = feedback,
        confidence     = validation$confidence,
        valid          = validation$valid,
        references     = kb_results$citations,
        model_used     = llm_response$model
      ))
    },

    # --- DEEP SPECIALIST: Anomaly-first scan for layout violations ---
    scan_layout_anomalies = function(layout, substrate, spec = list()) {
      anomalies  <- list()
      severities <- c()

      if (is.null(layout)) {
        return(list(count = 0, severities = character(0), items = list(),
                    summary = "No layout data provided — skipping layout anomaly scan."))
      }

      # Check for via-in-pad (RF signal vias should not be in pad landing zones)
      if (!is.null(layout$vias) && !is.null(layout$pads)) {
        for (via in layout$vias) {
          for (pad in layout$pads) {
            dist <- sqrt((via$x - pad$x)^2 + (via$y - pad$y)^2)
            if (!is.null(pad$clearance) && dist < pad$clearance) {
              anomalies[["via_in_pad"]] <- list(
                severity    = "CRITICAL",
                what        = "Via inside pad clearance zone",
                where       = paste0("Via at (", via$x, ",", via$y, "), pad at (", pad$x, ",", pad$y, ")"),
                consequence = "Solder wicking into via; unreliable solder joint; potential short circuit.",
                fix_direction = "Move via outside pad keepout or use via-in-pad with filled/capped via process."
              )
              severities <- c(severities, "CRITICAL")
            }
          }
        }
      }

      # Check minimum trace width for current carrying capacity
      if (!is.null(layout$traces) && !is.null(spec$pout_dbm)) {
        pout_watts <- 10^((spec$pout_dbm - 30) / 10)
        i_peak     <- sqrt(2 * pout_watts / 50) * 3  # rough estimate
        min_width_mm <- i_peak * 0.35  # ~0.35mm per amp (rough microstrip rule)

        for (trace in layout$traces) {
          if (!is.null(trace$width_mm) && trace$width_mm < min_width_mm && trace$type == "dc_supply") {
            anomalies[[paste0("narrow_dc_trace_", trace$id)]] <- list(
              severity    = "HIGH",
              what        = paste("DC supply trace too narrow:", trace$width_mm, "mm (need >=", round(min_width_mm, 2), "mm)"),
              where       = paste("Trace ID:", trace$id),
              consequence = "Trace overheating at full power; potential open circuit under thermal stress.",
              fix_direction = paste("Widen DC supply trace to >=", round(min_width_mm + 0.1, 2), "mm or use multiple parallel traces.")
            )
            severities <- c(severities, "HIGH")
          }
        }
      }

      # Check substrate loss at frequency
      if (!is.null(substrate) && !is.null(spec$freq_ghz)) {
        if (substrate$tan_delta > 0.01 && spec$freq_ghz > 5) {
          anomalies[["high_loss_substrate"]] <- list(
            severity    = "MEDIUM",
            what        = paste("High loss substrate (tan_delta =", substrate$tan_delta, ") at", spec$freq_ghz, "GHz"),
            where       = paste("Substrate:", substrate$name),
            consequence = paste0("Estimated additional insertion loss: ~",
                                 round(substrate$tan_delta * spec$freq_ghz * 2.5, 2), " dB/cm"),
            fix_direction = "Consider Rogers RO4003C (tan_delta = 0.0027) or RO4350B (tan_delta = 0.0037) for frequencies > 5GHz."
          )
          severities <- c(severities, "MEDIUM")
        }
      }

      return(list(
        count      = length(anomalies),
        severities = severities,
        items      = anomalies,
        summary    = if (length(anomalies) == 0) "NONE FOUND — layout passes anomaly scan."
                     else paste(length(anomalies), "layout anomalies:", paste(severities, collapse = ", "))
      ))
    },

    # DRC: check spacing, width, via rules
    run_drc = function(layout, substrate, spec = list()) {
      violations <- list()

      # Minimum trace clearance check
      if (!is.null(layout$traces)) {
        for (i in seq_along(layout$traces)) {
          for (j in seq_along(layout$traces)) {
            if (i >= j) next
            t1 <- layout$traces[[i]]; t2 <- layout$traces[[j]]
            if (!is.null(t1$x) && !is.null(t2$x)) {
              clearance <- abs(t1$x - t2$x) - (t1$width_mm + t2$width_mm) / 2
              if (!is.na(clearance) && clearance < 0.1) {
                violations[[paste0("spacing_", i, "_", j)]] <- list(
                  rule       = "Minimum clearance 0.1mm",
                  actual_mm  = round(clearance, 4),
                  severity   = "HIGH",
                  trace_ids  = c(t1$id, t2$id)
                )
              }
            }
          }
        }
      }

      pass <- length(violations) == 0
      return(list(
        pass       = pass,
        violations = violations,
        count      = length(violations),
        summary    = if (pass) "DRC PASS — no violations found."
                     else paste("DRC FAIL —", length(violations), "violation(s) found.")
      ))
    },

    # Microstrip line width calculation for target impedance
    calc_microstrip_width = function(z0_ohm, substrate) {
      er   <- substrate$er
      h_mm <- substrate$h_mm

      # Hammerstad approximate formula
      A  <- z0_ohm / 60 * sqrt((er + 1) / 2) + (er - 1) / (er + 1) * (0.23 + 0.11 / er)
      B  <- 377 * pi / (2 * z0_ohm * sqrt(er))

      w_over_h_narrow <- 8 * exp(A) / (exp(2 * A) - 2)
      w_over_h_wide   <- 2 / pi * (B - 1 - log(2 * B - 1) + (er - 1) / (2 * er) * (log(B - 1) + 0.39 - 0.61 / er))

      w_mm <- if (w_over_h_narrow < 2) w_over_h_narrow * h_mm else w_over_h_wide * h_mm

      return(list(
        width_mm    = round(w_mm, 4),
        w_over_h    = round(w_mm / h_mm, 4),
        z0_target   = z0_ohm,
        substrate   = substrate$name
      ))
    },

    # --- DEEP SPECIALIST: Feedback report for DRC results ---
    generate_drc_feedback = function(drc_result, anomaly_report) {
      if (is.null(drc_result)) {
        return(list(verdict = "NO DATA", correctness = 0,
                    completeness = 0, engineering_fit = 0,
                    note = "No layout data provided for DRC."))
      }

      correctness <- if (drc_result$pass) 9 else max(1, 9 - drc_result$count * 2)
      verdict     <- if (any(anomaly_report$severities == "CRITICAL")) "REJECT"
                     else if (!drc_result$pass)                        "CONDITIONAL PASS"
                     else                                               "PASS"

      return(list(
        verdict         = verdict,
        correctness     = correctness,
        completeness    = 8,
        engineering_fit = if (drc_result$pass) 9 else 5,
        risk            = if (length(anomaly_report$severities) > 0) anomaly_report$severities[1] else "NONE",
        drc_violations  = drc_result$count,
        required_fixes  = lapply(drc_result$violations, function(v) v$rule)
      ))
    },

    # Default Rogers RO4003C substrate
    default_substrate = function() {
      list(
        name      = "Rogers RO4003C",
        er        = 3.55,
        h_mm      = 0.508,
        tan_delta = 0.0027,
        cu_oz     = 1,
        note      = "Default. Change to match actual PCB stackup."
      )
    },

    # Check via spacing for RF ground fence
    check_via_spacing = function(layout, freq_ghz) {
      lambda_mm <- 300 / (freq_ghz * sqrt(3.55)) * 1000  # rough guided wavelength in mm
      max_via_pitch_mm <- lambda_mm / 20  # rule of thumb: pitch < lambda/20

      warnings <- list()
      if (!is.null(layout$via_pitch_mm) && layout$via_pitch_mm > max_via_pitch_mm) {
        warnings[["via_pitch"]] <- list(
          what       = paste("Via pitch", layout$via_pitch_mm, "mm exceeds lambda/20 =", round(max_via_pitch_mm, 2), "mm"),
          severity   = "MEDIUM",
          consequence = "Insufficient RF ground return; potential resonance between vias.",
          fix_direction = paste("Reduce via pitch to <=", round(max_via_pitch_mm * 0.8, 2), "mm")
        )
      }

      return(list(
        max_pitch_mm = round(max_via_pitch_mm, 2),
        warnings     = warnings,
        freq_ghz     = freq_ghz
      ))
    }
  )
)
