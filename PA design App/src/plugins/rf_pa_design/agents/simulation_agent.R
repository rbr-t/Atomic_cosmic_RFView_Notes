# Simulation Agent - RF PA Design Plugin
# ADS/AWR MCP bridge, result parsing, anomaly detection on simulation data
# Essence embedded from: Deep Specialist (anomaly-first scan, engineering report, feedback scores)

SimulationAgent <- R6Class("SimulationAgent",
  inherit = BaseAgent,

  public = list(
    name = "Simulation Agent",
    expertise = "ADS/AWR simulation setup, Touchstone/MDIF parsing, load-pull result analysis, anomaly detection in simulation data",

    # --- DEEP SPECIALIST: Severity taxonomy for simulation anomalies ---
    severity_levels = c("CRITICAL", "HIGH", "MEDIUM", "LOW", "NONE"),

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query   <- task$query
      context <- if (!is.null(task$context))   task$context   else list()
      sim_data <- if (!is.null(task$sim_data)) task$sim_data  else NULL
      spec    <- if (!is.null(task$spec))      task$spec      else list()

      # --- DEEP SPECIALIST: ANOMALY-FIRST SCAN before any analysis ---
      anomaly_report <- self$scan_for_anomalies(sim_data, spec)

      # Do not proceed past CRITICAL without flagging
      if (any(anomaly_report$severities == "CRITICAL")) {
        return(list(
          verdict        = "BLOCKED",
          anomaly_report = anomaly_report,
          message        = "CRITICAL anomaly detected in simulation data. Resolve before proceeding.",
          confidence     = 0,
          valid          = FALSE
        ))
      }

      system_prompt <- paste(
        "You are an expert RF simulation engineer specialising in Keysight ADS and NI AWR Microwave Office.",
        "You can:\n",
        "- Interpret S-parameter, load-pull, harmonic balance, and transient simulation results\n",
        "- Identify convergence failures, stability issues, and mesh errors\n",
        "- Explain discrepancies between simulation and theory\n",
        "- Recommend simulation setup corrections (port impedances, sweep ranges, bias points)\n",
        "Always quote specific simulation result values (Pout, PAE, gain, S11) when commenting on data.",
        "Flag any simulation result that violates physical constraints (e.g., PAE > 100%, negative Pout)."
      )

      if (!is.null(sim_data)) {
        summary_str <- self$summarise_sim_data(sim_data)
        query <- paste(query, "\n\nSimulation data summary:\n", summary_str)
      }

      if (!is.null(spec$pout_dbm))  query <- paste(query, "\nSpec Pout:", spec$pout_dbm, "dBm")
      if (!is.null(spec$pae_pct))   query <- paste(query, "\nSpec PAE:", spec$pae_pct, "%")
      if (!is.null(spec$gain_db))   query <- paste(query, "\nSpec Gain:", spec$gain_db, "dB")

      kb_results   <- self$query_knowledge_base(query, top_k = 3)
      llm_response <- self$call_llm(
        paste(query, "\nKB references:\n",
              paste(sapply(kb_results$results, function(r) r$text), collapse = "\n")),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      # --- DEEP SPECIALIST: Generate structured feedback report ---
      feedback <- self$generate_feedback_report(
        sim_data   = sim_data,
        spec       = spec,
        llm_answer = llm_response$content,
        anomalies  = anomaly_report
      )

      self$log_action("simulation_analysis", list(
        anomalies  = anomaly_report$count,
        verdict    = feedback$verdict,
        confidence = validation$confidence
      ))

      return(list(
        analysis       = llm_response$content,
        anomaly_report = anomaly_report,
        feedback       = feedback,
        confidence     = validation$confidence,
        valid          = validation$valid,
        references     = kb_results$citations,
        model_used     = llm_response$model
      ))
    },

    # --- DEEP SPECIALIST: Anomaly-first scan on simulation data ---
    scan_for_anomalies = function(sim_data, spec = list()) {
      anomalies  <- list()
      severities <- c()

      if (is.null(sim_data)) {
        return(list(
          count      = 0,
          severities = character(0),
          items      = list(),
          summary    = "No simulation data provided — skipping anomaly scan."
        ))
      }

      # Physical impossibility checks
      if (!is.null(sim_data$pae_pct)) {
        if (any(sim_data$pae_pct > 100)) {
          anomalies[["pae_over_100"]] <- list(
            severity     = "CRITICAL",
            what         = "PAE > 100% detected",
            where        = "sim_data$pae_pct",
            consequence  = "Violates energy conservation. Simulation setup error (wrong DC bias, wrong load).",
            fix_direction = "Check DC operating point, verify Vdd/Ids sweep, confirm power reference ports."
          )
          severities <- c(severities, "CRITICAL")
        }

        if (any(sim_data$pae_pct < 0)) {
          anomalies[["pae_negative"]] <- list(
            severity     = "HIGH",
            what         = "Negative PAE values detected",
            where        = "sim_data$pae_pct",
            consequence  = "Device absorbing power. May indicate oscillation or incorrect bias point.",
            fix_direction = "Check stability circles, verify bias sweep range, check for negative resistance."
          )
          severities <- c(severities, "HIGH")
        }
      }

      if (!is.null(sim_data$gain_db)) {
        if (any(sim_data$gain_db > 40)) {
          anomalies[["gain_unrealistic"]] <- list(
            severity     = "HIGH",
            what         = paste("Gain >40dB detected:", max(sim_data$gain_db), "dB"),
            where        = "sim_data$gain_db",
            consequence  = "Likely oscillation or incorrect port normalisation.",
            fix_direction = "Check stability (Rollett K-factor and B1 > 0), verify port impedances."
          )
          severities <- c(severities, "HIGH")
        }
      }

      # Spec margin checks
      if (!is.null(spec$pout_dbm) && !is.null(sim_data$pout_dbm)) {
        margin <- max(sim_data$pout_dbm) - spec$pout_dbm
        if (margin < -1) {
          anomalies[["pout_below_spec"]] <- list(
            severity     = "MEDIUM",
            what         = paste("Simulated Pout below spec by", abs(round(margin, 2)), "dB"),
            where        = "sim_data$pout_dbm vs spec$pout_dbm",
            consequence  = "Design will fail Pout spec. Needs topology or bias optimisation.",
            fix_direction = "Adjust load impedance, increase gate width, or add driver stage."
          )
          severities <- c(severities, "MEDIUM")
        }
      }

      if (!is.null(spec$pae_pct) && !is.null(sim_data$pae_pct)) {
        pae_margin <- max(sim_data$pae_pct) - spec$pae_pct
        if (pae_margin < -3) {
          anomalies[["pae_below_spec"]] <- list(
            severity     = "MEDIUM",
            what         = paste("Simulated PAE below spec by", abs(round(pae_margin, 2)), "%"),
            where        = "sim_data$pae_pct vs spec$pae_pct",
            consequence  = "PAE specification miss. Thermal budget may be exceeded.",
            fix_direction = "Optimise load impedance, reduce output combiner loss, check harmonic terminations."
          )
          severities <- c(severities, "MEDIUM")
        }
      }

      return(list(
        count      = length(anomalies),
        severities = severities,
        items      = anomalies,
        summary    = if (length(anomalies) == 0) "NONE FOUND — simulation data passes anomaly scan."
                     else paste(length(anomalies), "anomalies found:", paste(severities, collapse = ", "))
      ))
    },

    # --- DEEP SPECIALIST: Structured feedback report ---
    generate_feedback_report = function(sim_data, spec, llm_answer, anomalies) {
      correctness  <- if (anomalies$count == 0) 9 else max(1, 9 - anomalies$count * 2)
      completeness <- if (!is.null(sim_data) && !is.null(spec)) 8 else 4
      eng_fit      <- if (anomalies$count == 0) 9 else 6

      verdict <- if (any(anomalies$severities == "CRITICAL")) "REJECT"
      else if (any(anomalies$severities == "HIGH"))          "CONDITIONAL PASS"
      else                                                    "PASS"

      return(list(
        verdict          = verdict,
        correctness      = correctness,
        completeness     = completeness,
        engineering_fit  = eng_fit,
        risk             = if (length(anomalies$severities) > 0) anomalies$severities[1] else "NONE",
        required_fixes   = lapply(anomalies$items, function(a) a$fix_direction),
        llm_summary      = substr(llm_answer, 1, 300)
      ))
    },

    # Parse Touchstone .s2p file into structured list
    parse_touchstone = function(file_path) {
      if (!file.exists(file_path)) stop(paste("Touchstone file not found:", file_path))

      lines <- readLines(file_path)

      # Extract header
      option_line <- lines[grep("^#", lines)[1]]
      data_lines  <- lines[!grepl("^[#!]", lines) & nchar(trimws(lines)) > 0]

      data <- do.call(rbind, lapply(data_lines, function(l) {
        as.numeric(strsplit(trimws(l), "\\s+")[[1]])
      }))

      freq_col <- data[, 1]
      s11_re <- data[, 2]; s11_im <- data[, 3]
      s21_re <- data[, 4]; s21_im <- data[, 5]
      s12_re <- data[, 6]; s12_im <- data[, 7]
      s22_re <- data[, 8]; s22_im <- data[, 9]

      s21_mag_db <- 20 * log10(Mod(complex(real = s21_re, imaginary = s21_im)))

      return(list(
        freq_hz  = freq_col,
        s11      = complex(real = s11_re, imaginary = s11_im),
        s21      = complex(real = s21_re, imaginary = s21_im),
        s12      = complex(real = s12_re, imaginary = s12_im),
        s22      = complex(real = s22_re, imaginary = s22_im),
        gain_db  = s21_mag_db,
        option_line = option_line,
        source   = file_path
      ))
    },

    # Summarise simulation data for LLM prompt
    summarise_sim_data = function(sim_data) {
      parts <- c()
      if (!is.null(sim_data$pout_dbm)) parts <- c(parts, paste("Pout max:", round(max(sim_data$pout_dbm), 2), "dBm"))
      if (!is.null(sim_data$pae_pct))  parts <- c(parts, paste("PAE max:", round(max(sim_data$pae_pct), 2), "%"))
      if (!is.null(sim_data$gain_db))  parts <- c(parts, paste("Gain:", round(mean(sim_data$gain_db), 2), "dB avg"))
      if (!is.null(sim_data$freq_ghz)) parts <- c(parts, paste("Freq range:", round(min(sim_data$freq_ghz), 3), "-",
                                                                 round(max(sim_data$freq_ghz), 3), "GHz"))
      if (length(parts) == 0) return("No numeric simulation data available.")
      paste(parts, collapse = "; ")
    }
  )
)
