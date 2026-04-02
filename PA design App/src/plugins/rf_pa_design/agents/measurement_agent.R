# Measurement Agent - RF PA Design Plugin
# Lab instrument interface, VNA data import, calibration audit, measurement integrity
# Essence embedded from: Security Guardian (systematic audit, severity classification, traceable integrity)

MeasurementAgent <- R6Class("MeasurementAgent",
  inherit = BaseAgent,

  public = list(
    name = "Measurement Agent",
    expertise = "VNA measurements, load-pull test systems, power meter calibration, spectrum analyser setup, Touchstone import, measurement traceability, cal kit verification",

    # --- SECURITY GUARDIAN ANALOGY: Measurement threats (same systematic approach) ---
    # Broken calibration  → Broken Access Control (wrong data gets through)
    # Uncorrected port mismatch → Cryptographic failures (data integrity compromised)
    # Wrong reference plane → Injection (bad data injected into analysis)
    # Drift without re-cal  → Insecure design (system degrades silently)
    # Unchecked cable flex → Security misconfiguration (environmental factors uncontrolled)

    # Measurement integrity checklist (analogous to OWASP Top 10)
    integrity_checklist = list(
      list(id = "M01", area = "Calibration validity",       risk = "CRITICAL", description = "Cal date within drift spec; cal kit characterised at temperature"),
      list(id = "M02", area = "Port match correction",      risk = "HIGH",     description = "SOLT/TRL/LRM applied; residual errors < -40dB return loss"),
      list(id = "M03", area = "Reference plane definition", risk = "HIGH",     description = "Reference plane at DUT ports; correct de-embedding applied"),
      list(id = "M04", area = "Power level accuracy",       risk = "HIGH",     description = "Power meter calibrated to NIST-traceable standard within 12 months"),
      list(id = "M05", area = "Cable phase stability",      risk = "MEDIUM",   description = "Phase-stable cables used; flex cables < 0.1deg/bend at test frequency"),
      list(id = "M06", area = "Temperature stabilisation",  risk = "MEDIUM",   description = "DUT at thermal equilibrium (>15 min soak); ambient ±2°C"),
      list(id = "M07", area = "Harmonics and spurious",     risk = "MEDIUM",   description = "Spectrum analyser resolution bandwidth, RBW/VBW settings verified"),
      list(id = "M08", area = "Bias sequencing",            risk = "MEDIUM",   description = "Gate bias before drain bias; correct sweep order for safety"),
      list(id = "M09", area = "Load impedance accuracy",    risk = "LOW",      description = "Tuner cal, impedance pull range verified vs spec targets"),
      list(id = "M10", area = "Data logging / export",      risk = "LOW",      description = "Raw data exported in lossless format; cal state saved with data file")
    ),

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query   <- task$query
      context <- if (!is.null(task$context))    task$context    else list()
      meas_data <- if (!is.null(task$meas_data)) task$meas_data else NULL
      cal_state <- if (!is.null(task$cal_state)) task$cal_state else NULL
      spec    <- if (!is.null(task$spec))       task$spec       else list()

      # --- SECURITY GUARDIAN: Audit calibration chain FIRST ---
      cal_audit <- self$audit_calibration_chain(cal_state)

      system_prompt <- paste(
        "You are an expert RF measurement engineer with deep experience in:",
        "- VNA (Keysight/Rohde&Schwarz) S-parameter measurements and calibration\n",
        "- Load-pull test systems (Maury, Focus, ATN)\n",
        "- Power measurement (Keysight EPM, Rohde&Schwarz NRP)\n",
        "- Spectrum analyser and signal analyser measurements\n",
        "- Harmonic balance correlation between simulation and measurement\n",
        "Always state calibration assumptions when interpreting results.",
        "Flag any measurement result that could be corrupted by calibration errors.",
        "Recommend re-measurement conditions when data integrity is in question."
      )

      if (!is.null(meas_data)) {
        summary_str <- self$summarise_meas_data(meas_data)
        query <- paste(query, "\n\nMeasurement summary:\n", summary_str)
      }

      if (!is.null(spec$pout_dbm)) query <- paste(query, "\nSpec Pout:", spec$pout_dbm, "dBm")
      if (!is.null(spec$freq_ghz)) query <- paste(query, "\nFrequency:", spec$freq_ghz, "GHz")

      kb_results   <- self$query_knowledge_base(query, top_k = 3)
      llm_response <- self$call_llm(
        paste(query,
              "\nCalibration audit:", cal_audit$summary,
              "\nKB references:\n", paste(sapply(kb_results$results, function(r) r$text), collapse = "\n")),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      integrity_report <- self$check_measurement_integrity(meas_data, spec)

      self$log_action("measurement_analysis", list(
        cal_audit_pass     = cal_audit$pass,
        integrity_risk     = integrity_report$overall_risk,
        confidence         = validation$confidence
      ))

      return(list(
        analysis          = llm_response$content,
        cal_audit         = cal_audit,
        integrity_report  = integrity_report,
        confidence        = validation$confidence,
        valid             = validation$valid,
        references        = kb_results$citations,
        model_used        = llm_response$model
      ))
    },

    # --- SECURITY GUARDIAN pattern: Systematic calibration audit ---
    audit_calibration_chain = function(cal_state = NULL) {
      findings <- list()

      if (is.null(cal_state)) {
        return(list(
          pass    = FALSE,
          summary = "No calibration state provided. Cannot verify measurement integrity.",
          findings = list(list(
            id = "M01", severity = "CRITICAL",
            note = "Calibration state unknown. All measurement results are untrustworthy until cal is verified."
          ))
        ))
      }

      # Check cal date
      if (!is.null(cal_state$cal_date)) {
        days_old <- as.numeric(Sys.Date() - as.Date(cal_state$cal_date))
        if (days_old > 365) {
          findings[["M01_expired"]] <- list(
            id       = "M01", severity = "CRITICAL",
            note     = paste("Calibration expired:", days_old, "days old (max 365 days)"),
            fix      = "Recalibrate instrument and cal kit. Check NIST traceability certificate."
          )
        } else if (days_old > 180) {
          findings[["M01_aging"]] <- list(
            id       = "M01", severity = "MEDIUM",
            note     = paste("Calibration aging:", days_old, "days (recommend <180 days for critical measurements)"),
            fix      = "Schedule recalibration. Verify cal kit characterisation at operating temperature."
          )
        }
      }

      # Check port match correction
      if (!is.null(cal_state$port_correction) && !cal_state$port_correction) {
        findings[["M02_no_correction"]] <- list(
          id       = "M02", severity = "HIGH",
          note     = "Port match correction not applied. Raw data only.",
          fix      = "Apply SOLT, TRL, or LRM calibration. Residual return loss should be < -40dB."
        )
      }

      # Check reference plane
      if (!is.null(cal_state$reference_plane) && cal_state$reference_plane == "connector") {
        findings[["M03_wrong_ref"]] <- list(
          id       = "M03", severity = "HIGH",
          note     = "Reference plane at connector, not DUT port.",
          fix      = "Apply de-embedding for cable/adapter losses to move reference plane to DUT ports."
        )
      }

      pass <- !any(sapply(findings, function(f) f$severity == "CRITICAL"))
      return(list(
        pass     = pass,
        findings = findings,
        summary  = if (pass && length(findings) == 0)
                     "Calibration chain PASS — all checks clear."
                   else paste(length(findings), "calibration issue(s) found.")
      ))
    },

    # --- SECURITY GUARDIAN: Measurement integrity classification ---
    check_measurement_integrity = function(meas_data, spec = list()) {
      risks <- c()

      if (is.null(meas_data)) {
        return(list(overall_risk = "UNKNOWN", risks = c("No measurement data"),
                    summary = "No measurement data available for integrity check."))
      }

      # Pout sanity check
      if (!is.null(meas_data$pout_dbm)) {
        if (any(meas_data$pout_dbm > 70)) risks <- c(risks, "CRITICAL: Pout > 70dBm (1kW+) — verify power meter range and attenuator setting")
        if (any(meas_data$pout_dbm < -30)) risks <- c(risks, "HIGH: Pout very low — device may not be biased or is oscillating")
      }

      # PAE sanity
      if (!is.null(meas_data$pae_pct)) {
        if (any(meas_data$pae_pct > 100)) risks <- c(risks, "CRITICAL: PAE > 100% — power meter error or wrong DC current reading")
        if (any(meas_data$pae_pct < 0))   risks <- c(risks, "HIGH: Negative PAE — device in small-signal regime or wrong bias")
      }

      # S21 phase discontinuity
      if (!is.null(meas_data$s21_phase_deg)) {
        phase_jumps <- diff(meas_data$s21_phase_deg)
        if (any(abs(phase_jumps) > 90)) risks <- c(risks, "MEDIUM: Phase discontinuity > 90deg — likely cable phase wrap or resonance")
      }

      overall_risk <- if      (any(grepl("CRITICAL", risks))) "CRITICAL"
                      else if (any(grepl("HIGH",     risks))) "HIGH"
                      else if (any(grepl("MEDIUM",   risks))) "MEDIUM"
                      else                                     "LOW"

      return(list(
        overall_risk = overall_risk,
        risks        = risks,
        summary      = if (length(risks) == 0) "Measurement data passes integrity checks."
                       else paste(length(risks), "integrity issue(s) detected.")
      ))
    },

    # Parse Touchstone .s2p file (shared with SimulationAgent but with cal state awareness)
    parse_touchstone = function(file_path, cal_state = NULL) {
      if (!file.exists(file_path)) stop(paste("Touchstone file not found:", file_path))

      # --- SECURITY GUARDIAN: flag uncalibrated data on import ---
      cal_warning <- if (is.null(cal_state))
        "WARNING: No calibration state provided with this Touchstone import. Treat data as uncalibrated."
      else NULL

      lines      <- readLines(file_path)
      data_lines <- lines[!grepl("^[#!]", lines) & nchar(trimws(lines)) > 0]
      data       <- do.call(rbind, lapply(data_lines, function(l) as.numeric(strsplit(trimws(l), "\\s+")[[1]])))

      result <- list(
        freq_hz    = data[, 1],
        s11        = complex(real = data[, 2], imaginary = data[, 3]),
        s21        = complex(real = data[, 4], imaginary = data[, 5]),
        s12        = complex(real = data[, 6], imaginary = data[, 7]),
        s22        = complex(real = data[, 8], imaginary = data[, 9]),
        gain_db    = 20 * log10(Mod(complex(real = data[, 4], imaginary = data[, 5]))),
        source     = file_path,
        cal_state  = cal_state,
        cal_warning = cal_warning
      )

      return(result)
    },

    summarise_meas_data = function(meas_data) {
      parts <- c()
      if (!is.null(meas_data$pout_dbm)) parts <- c(parts, paste("Pout max:", round(max(meas_data$pout_dbm), 2), "dBm"))
      if (!is.null(meas_data$pae_pct))  parts <- c(parts, paste("PAE max:", round(max(meas_data$pae_pct), 2), "%"))
      if (!is.null(meas_data$gain_db))  parts <- c(parts, paste("Gain:", round(mean(meas_data$gain_db), 2), "dB avg"))
      if (length(parts) == 0) return("No numeric measurement data available.")
      paste(parts, collapse = "; ")
    }
  )
)
