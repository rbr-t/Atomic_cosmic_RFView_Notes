# Debug Agent - RF PA Design Plugin
# Sim vs. measurement anomaly detection, root cause analysis
# Essence embedded from: T-IKIA-T (Transform → Information → Knowledge → Intelligence → Action → Truth)
# Full 5-stage pipeline applied to RF design discrepancies

DebugAgent <- R6Class("DebugAgent",
  inherit = BaseAgent,

  public = list(
    name = "Debug Agent",
    expertise = "Sim-vs-measurement correlation, PA failure diagnosis, stability analysis, root-cause identification using 5-Why, RF anomaly detection",

    # T-IKIA-T pipeline stages
    pipeline_stages = c(
      "INFORMATION INTAKE",
      "KNOWLEDGE CONSTRUCTION",
      "INTELLIGENCE SYNTHESIS",
      "ACTION DESIGN",
      "TRUTH VALIDATION"
    ),

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query     <- task$query
      context   <- if (!is.null(task$context))   task$context   else list()
      sim_data  <- if (!is.null(task$sim_data))  task$sim_data  else NULL
      meas_data <- if (!is.null(task$meas_data)) task$meas_data else NULL
      spec      <- if (!is.null(task$spec))      task$spec      else list()

      # ── STAGE 1: INFORMATION INTAKE ─────────────────────────────────────────
      evidence <- self$intake_evidence(sim_data, meas_data, spec, query)

      # ── STAGE 2: KNOWLEDGE CONSTRUCTION ─────────────────────────────────────
      knowledge_map <- self$construct_knowledge_map(evidence)

      # ── STAGE 3: INTELLIGENCE SYNTHESIS ─────────────────────────────────────
      hypotheses <- self$synthesize_root_cause(knowledge_map, sim_data, meas_data)

      # ── STAGE 4: ACTION DESIGN ───────────────────────────────────────────────
      action_plan <- self$design_action_plan(hypotheses, spec)

      # ── STAGE 5: TRUTH VALIDATION ────────────────────────────────────────────
      truth_check <- self$validate_truth(action_plan, evidence, hypotheses)

      system_prompt <- paste(
        "You are an expert RF power amplifier debug engineer.",
        "You specialise in:\n",
        "- Correlating simulation (ADS/AWR) with lab measurements\n",
        "- Identifying root causes: model inaccuracy, parasitic elements, thermal effects, layout errors\n",
        "- Stability analysis (Rollett K-factor, S-probe, odd-mode oscillation)\n",
        "- Process variation effects on GaN/LDMOS devices\n",
        "- Systematic 5-Why root cause analysis for PA failures\n",
        "Always separate symptoms from causes.",
        "Always distinguish between 'model error', 'layout error', and 'process variation'.",
        "State your confidence level for each hypothesis."
      )

      pipeline_summary <- paste(
        "Evidence collected:", evidence$item_count, "items.\n",
        "Knowledge map: Facts:", length(knowledge_map$facts),
        "| Assumptions:", length(knowledge_map$assumptions),
        "| Gaps:", length(knowledge_map$gaps), "\n",
        "Top hypothesis:", if (length(hypotheses) > 0) hypotheses[[1]]$description else "None",
        "\nConfidence:", truth_check$confidence
      )

      llm_response <- self$call_llm(
        paste(query, "\n\nDebug pipeline summary:\n", pipeline_summary,
              "\n\nHypotheses:\n",
              paste(sapply(hypotheses, function(h) paste0("H", h$rank, " [", h$probability_pct, "%]: ", h$description)), collapse = "\n")),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      self$log_action("debug_analysis", list(
        hypotheses_count = length(hypotheses),
        top_hypothesis   = if (length(hypotheses) > 0) hypotheses[[1]]$description else "none",
        confidence       = truth_check$confidence
      ))

      return(list(
        diagnosis      = llm_response$content,
        pipeline = list(
          stage1_evidence    = evidence,
          stage2_knowledge   = knowledge_map,
          stage3_hypotheses  = hypotheses,
          stage4_actions     = action_plan,
          stage5_truth       = truth_check
        ),
        confidence     = validation$confidence,
        valid          = validation$valid,
        model_used     = llm_response$model
      ))
    },

    # ── STAGE 1: INFORMATION INTAKE ──────────────────────────────────────────
    # Collect all available evidence without interpretation
    intake_evidence = function(sim_data, meas_data, spec, query) {
      items <- list()

      if (!is.null(sim_data)) {
        if (!is.null(sim_data$pout_dbm)) items[["sim_pout"]] <- list(
          type = "simulation", key = "pout_dbm", value = max(sim_data$pout_dbm))
        if (!is.null(sim_data$pae_pct))  items[["sim_pae"]]  <- list(
          type = "simulation", key = "pae_pct",  value = max(sim_data$pae_pct))
        if (!is.null(sim_data$gain_db))  items[["sim_gain"]] <- list(
          type = "simulation", key = "gain_db",  value = mean(sim_data$gain_db))
      }

      if (!is.null(meas_data)) {
        if (!is.null(meas_data$pout_dbm)) items[["meas_pout"]] <- list(
          type = "measurement", key = "pout_dbm", value = max(meas_data$pout_dbm))
        if (!is.null(meas_data$pae_pct))  items[["meas_pae"]]  <- list(
          type = "measurement", key = "pae_pct",  value = max(meas_data$pae_pct))
        if (!is.null(meas_data$gain_db))  items[["meas_gain"]] <- list(
          type = "measurement", key = "gain_db",  value = mean(meas_data$gain_db))
      }

      if (!is.null(spec)) {
        if (!is.null(spec$pout_dbm)) items[["spec_pout"]] <- list(
          type = "spec", key = "pout_dbm", value = spec$pout_dbm)
        if (!is.null(spec$pae_pct))  items[["spec_pae"]]  <- list(
          type = "spec", key = "pae_pct",  value = spec$pae_pct)
      }

      return(list(
        items      = items,
        item_count = length(items),
        query      = query,
        timestamp  = Sys.time()
      ))
    },

    # ── STAGE 2: KNOWLEDGE CONSTRUCTION ─────────────────────────────────────
    # Separate: Facts / Assumptions / Gaps / Noise
    construct_knowledge_map = function(evidence) {
      facts       <- list()
      assumptions <- list()
      gaps        <- list()
      noise       <- list()

      for (key in names(evidence$items)) {
        item <- evidence$items[[key]]
        if (item$type %in% c("simulation", "measurement", "spec")) {
          facts[[key]] <- list(
            item       = key,
            value      = item$value,
            source     = item$type,
            confidence = "High — directly observed"
          )
        }
      }

      # Standard RF debug assumptions
      assumptions[["model_accuracy"]] <- list(
        item       = "Device model accurately represents physical device",
        source     = "Assumed — model from foundry/vendor datasheet",
        confidence = "Medium — foundry models ±1-2dB typical accuracy"
      )
      assumptions[["cal_validity"]] <- list(
        item       = "Measurement calibration is valid at test conditions",
        source     = "Assumed — cal performed at room temperature",
        confidence = "Medium — verify cal date and stability"
      )
      assumptions[["layout_parasitics"]] <- list(
        item       = "Layout parasitics are captured in simulation",
        source     = "Assumed — depends on EM simulation inclusion",
        confidence = "Low — layout EM not always included in first-pass sim"
      )

      # Gaps: what would change the analysis if known
      if (is.null(evidence$items[["sim_pout"]]))  gaps[["sim_pout"]]  <- "Simulation Pout not available"
      if (is.null(evidence$items[["meas_pout"]])) gaps[["meas_pout"]] <- "Measured Pout not available"
      if (is.null(evidence$items[["sim_pae"]]))   gaps[["sim_pae"]]   <- "Simulation PAE not available"
      if (is.null(evidence$items[["meas_pae"]]))  gaps[["meas_pae"]]  <- "Measured PAE not available"

      return(list(
        facts       = facts,
        assumptions = assumptions,
        gaps        = gaps,
        noise       = noise
      ))
    },

    # ── STAGE 3: INTELLIGENCE SYNTHESIS ─────────────────────────────────────
    # 5-Why root cause + hypothesis ranking
    synthesize_root_cause = function(knowledge_map, sim_data, meas_data) {
      hypotheses <- list()
      h_rank <- 1

      # Compare sim vs measurement where both exist
      deltas <- self$compare_sim_vs_meas(sim_data, meas_data)

      if (!is.null(deltas$pout_delta_db) && abs(deltas$pout_delta_db) > 1) {
        prob <- if (abs(deltas$pout_delta_db) > 3) 70 else 40

        hypotheses[[h_rank]] <- list(
          rank             = h_rank,
          description      = paste0("Output power discrepancy: sim-meas delta = ",
                                    round(deltas$pout_delta_db, 2), " dB"),
          probability_pct  = prob,
          five_why = list(
            why1 = "Measured Pout differs from simulated Pout",
            why2 = "Load impedance seen by device differs between sim and measurement",
            why3 = "Cable/fixture losses not de-embedded, or tuner impedance inaccurate",
            why4 = "Reference plane not at DUT port; combiner model incomplete",
            why5 = "Root cause: layout parasitic inductance at combiner junction not included in HB simulation"
          ),
          evidence_for     = "Pout delta > 1dB is reproducible across bias sweep",
          evidence_against = "Could be calibration error — verify with power sensor check",
          falsification    = "Remove DUT, measure cable chain Pout: if delta remains, it is a cable/cal error not a device error"
        )
        h_rank <- h_rank + 1
      }

      if (!is.null(deltas$pae_delta_pct) && abs(deltas$pae_delta_pct) > 3) {
        hypotheses[[h_rank]] <- list(
          rank             = h_rank,
          description      = paste0("PAE discrepancy: sim-meas delta = ",
                                    round(deltas$pae_delta_pct, 2), "%"),
          probability_pct  = 55,
          five_why = list(
            why1 = "Measured PAE lower than simulated PAE",
            why2 = "Higher DC current consumption than model predicts",
            why3 = "Thermal effects increase Ids at elevated junction temperature",
            why4 = "Self-heating model in simulation does not match actual thermal resistance",
            why5 = "Root cause: Rth_junction-to-case underestimated; thermal runaway at high power"
          ),
          evidence_for     = "PAE delta increases with output power (thermal signature)",
          evidence_against = "Could be gate bias drift — measure Vgs vs temperature",
          falsification    = "Pulse the RF drive (10us pulses, 1% duty cycle): if PAE recovers, thermal model is root cause"
        )
        h_rank <- h_rank + 1
      }

      if (!is.null(deltas$gain_delta_db) && abs(deltas$gain_delta_db) > 1) {
        hypotheses[[h_rank]] <- list(
          rank             = h_rank,
          description      = paste0("Gain discrepancy: sim-meas delta = ",
                                    round(deltas$gain_delta_db, 2), " dB"),
          probability_pct  = 50,
          five_why = list(
            why1 = "Measured gain lower than simulated gain",
            why2 = "Input match worse in hardware than in simulation",
            why3 = "Bond wire or package inductance not accurately modelled",
            why4 = "Package model is simplified or from different temperature lot",
            why5 = "Root cause: bonding wire length variation (±0.1mm = ±0.2nH at 1GHz)"
          ),
          evidence_for     = "S11 mismatch correlates with frequency of gain drop",
          evidence_against = "Could be probe calibration error at input",
          falsification    = "Simulate with ±0.2nH bond wire variation: if gain delta reproduced, bond wire is root cause"
        )
        h_rank <- h_rank + 1
      }

      # Default hypothesis when no data
      if (length(hypotheses) == 0) {
        hypotheses[[1]] <- list(
          rank             = 1,
          description      = "Insufficient data for quantitative root cause analysis",
          probability_pct  = 0,
          five_why         = list(why1 = "No sim and measurement data provided together"),
          evidence_for     = "N/A",
          evidence_against = "N/A",
          falsification    = "Provide both sim_data and meas_data with matching frequency/bias conditions"
        )
      }

      return(hypotheses)
    },

    # ── STAGE 4: ACTION DESIGN ───────────────────────────────────────────────
    design_action_plan = function(hypotheses, spec) {
      actions <- list()

      for (i in seq_along(hypotheses)) {
        h <- hypotheses[[i]]

        actions[[i]] <- list(
          action_number = i,
          agent         = if (grepl("layout|parasitic|bond", tolower(h$description)))
                            "layout-agent"
                          else if (grepl("simulation|model|thermal", tolower(h$description)))
                            "simulation-agent"
                          else if (grepl("measurement|cal|power|cable", tolower(h$description)))
                            "measurement-agent"
                          else
                            "theory-agent",
          precondition  = "Simulation and measurement data available at same bias/frequency conditions",
          action        = paste0("Investigate: ", h$description, ". Use falsification test: ", h$five_why$why5),
          expected      = paste0("Delta reduces to < 0.5dB after correction"),
          verification  = h$falsification,
          reversible    = TRUE,
          priority      = h$probability_pct
        )
      }

      return(actions[order(sapply(actions, function(a) -a$priority))])
    },

    # ── STAGE 5: TRUTH VALIDATION ────────────────────────────────────────────
    validate_truth = function(action_plan, evidence, hypotheses) {
      unresolved_gaps <- evidence$item_count < 4  # Need sim + meas + spec minimum

      confidence <- if (unresolved_gaps) 0.4
                    else if (length(hypotheses) > 0 && hypotheses[[1]]$probability_pct > 60) 0.8
                    else 0.6

      falsifiability_check <- if (length(hypotheses) > 0)
        hypotheses[[1]]$falsification
      else
        "Provide sim_data and meas_data to enable falsification testing."

      return(list(
        confidence            = confidence,
        unresolved_gaps       = unresolved_gaps,
        falsifiability_check  = falsifiability_check,
        contradictions        = if (unresolved_gaps) "Gaps in evidence prevent high-confidence root cause" else "None identified",
        recommendation        = if (confidence >= 0.7) "Proceed with top hypothesis action plan"
                                else "Collect additional data before acting"
      ))
    },

    # Compare simulation vs measurement data
    compare_sim_vs_meas = function(sim_data, meas_data) {
      deltas <- list()

      if (!is.null(sim_data) && !is.null(meas_data)) {
        if (!is.null(sim_data$pout_dbm) && !is.null(meas_data$pout_dbm))
          deltas$pout_delta_db  <- max(sim_data$pout_dbm)  - max(meas_data$pout_dbm)
        if (!is.null(sim_data$pae_pct)  && !is.null(meas_data$pae_pct))
          deltas$pae_delta_pct  <- max(sim_data$pae_pct)   - max(meas_data$pae_pct)
        if (!is.null(sim_data$gain_db)  && !is.null(meas_data$gain_db))
          deltas$gain_delta_db  <- mean(sim_data$gain_db)  - mean(meas_data$gain_db)
      }

      return(deltas)
    }
  )
)
