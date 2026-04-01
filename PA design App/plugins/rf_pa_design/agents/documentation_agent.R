# Documentation Agent - RF PA Design Plugin
# Auto-report generation, spec drift detection, design goal tracking
# Essence embedded from: Mission Compass (goal lock, three-horizon impact, drift detection, POV function)

DocumentationAgent <- R6Class("DocumentationAgent",
  inherit = BaseAgent,

  public = list(
    name = "Documentation Agent",
    expertise = "Design report generation, spec compliance tracking, design review documentation, milestone reporting, Pout/PAE/gain margin tables",

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query        <- task$query
      context      <- if (!is.null(task$context))     task$context      else list()
      project      <- if (!is.null(task$project))     task$project      else list()
      report_type  <- if (!is.null(task$report_type)) task$report_type  else "design_review"
      spec         <- if (!is.null(task$spec))        task$spec         else list()

      # --- MISSION COMPASS: Lock design goal first ---
      goal_lock <- self$lock_design_goal(project, spec)

      # --- MISSION COMPASS: Detect drift from original spec ---
      drift_signal <- self$detect_spec_drift(project, spec)

      # --- MISSION COMPASS: Three-horizon assessment ---
      horizon_assessment <- self$assess_three_horizon(project, spec)

      system_prompt <- paste(
        "You are a technical documentation engineer for RF power amplifier design.",
        "You generate clear, structured design review documents that include:\n",
        "- Specification compliance table (target vs achieved vs margin)\n",
        "- Key performance metrics at all relevant conditions\n",
        "- Design decisions with rationale\n",
        "- Risk items and open actions\n",
        "- Next steps and gate criteria\n",
        "Use SI units consistently. Quote all results to 1 decimal place.",
        "Always include a specification compliance traffic light (GREEN/AMBER/RED per parameter)."
      )

      # Build document context
      doc_context <- paste(
        "Report type:", report_type,
        "\nProject goal:", goal_lock$locked_goal,
        "\nDrift signal:", drift_signal$status,
        "\nHorizon assessment:", horizon_assessment$summary
      )

      if (!is.null(project$current_results)) {
        doc_context <- paste(doc_context, "\nCurrent results:", jsonlite::toJSON(project$current_results, auto_unbox = TRUE))
      }

      llm_response <- self$call_llm(
        paste(query, "\n\nDocument context:\n", doc_context),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      # Generate structured report
      report <- self$generate_design_report(project, spec, goal_lock, drift_signal, horizon_assessment, llm_response$content)

      self$log_action("documentation_generated", list(
        report_type        = report_type,
        drift_detected     = drift_signal$status != "ON-TRACK",
        horizon_summary    = horizon_assessment$summary,
        confidence         = validation$confidence
      ))

      return(list(
        report         = report,
        goal_lock      = goal_lock,
        drift_signal   = drift_signal,
        horizon        = horizon_assessment,
        llm_content    = llm_response$content,
        confidence     = validation$confidence,
        valid          = validation$valid,
        model_used     = llm_response$model
      ))
    },

    # --- MISSION COMPASS: Lock the design goal from project spec ---
    lock_design_goal = function(project, spec) {
      goal_sentence <- paste0(
        "Design and deliver a PA at ",
        if (!is.null(spec$freq_ghz))    paste0(spec$freq_ghz, " GHz ") else "target frequency ",
        "producing ",
        if (!is.null(spec$pout_dbm))    paste0(spec$pout_dbm, " dBm ") else "target Pout ",
        "with ",
        if (!is.null(spec$pae_pct))     paste0(spec$pae_pct, "% PAE ") else "target PAE ",
        "and ",
        if (!is.null(spec$gain_db))     paste0(spec$gain_db, " dB gain ") else "target gain ",
        "using ",
        if (!is.null(spec$technology))  spec$technology else "target technology",
        "."
      )

      return(list(
        locked_goal = goal_sentence,
        spec        = spec,
        locked_at   = Sys.time(),
        project_id  = if (!is.null(project$id)) project$id else "unknown"
      ))
    },

    # --- MISSION COMPASS: Detect drift between current results and original spec ---
    detect_spec_drift = function(project, spec) {
      drift_items <- list()
      status      <- "ON-TRACK"

      results <- project$current_results
      if (is.null(results)) {
        return(list(status = "NO-DATA", drift_items = list(),
                    summary = "No current results available — cannot assess drift."))
      }

      # Pout drift
      if (!is.null(spec$pout_dbm) && !is.null(results$pout_dbm)) {
        margin <- results$pout_dbm - spec$pout_dbm
        if (margin < -2) {
          drift_items[["pout"]] <- list(
            parameter = "Pout", spec = spec$pout_dbm, current = results$pout_dbm,
            margin_db = round(margin, 2), severity = "CRITICAL",
            note = "Pout >2dB below spec. Design may not meet target without topology change."
          )
          status <- "OFF-COURSE"
        } else if (margin < -0.5) {
          drift_items[["pout_amber"]] <- list(
            parameter = "Pout", spec = spec$pout_dbm, current = results$pout_dbm,
            margin_db = round(margin, 2), severity = "AMBER",
            note = "Pout within 0.5-2dB of spec. Monitor closely."
          )
          if (status == "ON-TRACK") status <- "DRIFTING"
        }
      }

      # PAE drift
      if (!is.null(spec$pae_pct) && !is.null(results$pae_pct)) {
        margin <- results$pae_pct - spec$pae_pct
        if (margin < -5) {
          drift_items[["pae"]] <- list(
            parameter = "PAE", spec = spec$pae_pct, current = results$pae_pct,
            margin_pct = round(margin, 2), severity = "CRITICAL",
            note = "PAE >5% below spec. Fundamental efficiency improvement needed."
          )
          status <- "OFF-COURSE"
        } else if (margin < -2) {
          drift_items[["pae_amber"]] <- list(
            parameter = "PAE", spec = spec$pae_pct, current = results$pae_pct,
            margin_pct = round(margin, 2), severity = "AMBER",
            note = "PAE 2-5% below spec. Optimisation required."
          )
          if (status == "ON-TRACK") status <- "DRIFTING"
        }
      }

      return(list(
        status      = status,
        drift_items = drift_items,
        summary     = paste0("Status: ", status, ". ", length(drift_items), " drift item(s) detected.")
      ))
    },

    # --- MISSION COMPASS: Three-horizon assessment ---
    assess_three_horizon = function(project, spec) {
      # Short: can we unblock the immediate design gate?
      # Mid:   will this compound positively into the next phase?
      # Long:  does this PA design serve the product roadmap?

      short_time <- if (!is.null(project$current_phase) && project$current_phase == "simulation") "✓" else "~"
      short_cost <- if (!is.null(project$on_budget) && project$on_budget) "✓" else "~"
      short_eff  <- if (!is.null(project$current_results)) "✓" else "⚠"

      mid_time   <- "~"  # Depends on layout and measurement iteration count
      mid_cost   <- if (!is.null(spec$technology) && spec$technology == "GaN") "⚠" else "~"  # GaN NRE is high
      mid_eff    <- "✓"

      long_time  <- "✓"
      long_cost  <- "~"
      long_eff   <- if (!is.null(spec$pae_pct) && spec$pae_pct > 60) "✓" else "~"

      summary <- paste0(
        "Short[T:", short_time, " C:", short_cost, " E:", short_eff, "] ",
        "Mid[T:", mid_time, " C:", mid_cost, " E:", mid_eff, "] ",
        "Long[T:", long_time, " C:", long_cost, " E:", long_eff, "]"
      )

      return(list(
        short_term  = list(time = short_time, cost = short_cost, efficiency = short_eff),
        mid_term    = list(time = mid_time,   cost = mid_cost,   efficiency = mid_eff),
        long_term   = list(time = long_time,  cost = long_cost,  efficiency = long_eff),
        summary     = summary
      ))
    },

    # --- MISSION COMPASS: Compass Reading output for design status ---
    generate_compass_reading = function(project, spec) {
      goal_lock  <- self$lock_design_goal(project, spec)
      drift      <- self$detect_spec_drift(project, spec)
      horizon    <- self$assess_three_horizon(project, spec)

      return(list(
        goal       = goal_lock$locked_goal,
        status     = drift$status,
        drift_signal = if (length(drift$drift_items) > 0)
                         paste(sapply(drift$drift_items, function(d) paste(d$parameter, d$severity)), collapse = "; ")
                       else "NONE",
        short_term = horizon$short_term,
        mid_term   = horizon$mid_term,
        long_term  = horizon$long_term,
        correction = if (drift$status == "OFF-COURSE")
                       "Escalate to architecture-agent for topology review. Spec cannot be met with current approach."
                     else if (drift$status == "DRIFTING")
                       "Flag to simulation-agent for parameter optimisation. Schedule interim design review."
                     else
                       "NONE — continue current design flow.",
        confidence = if (drift$status == "ON-TRACK") "HIGH" else "MEDIUM"
      ))
    },

    # Full design report generation
    generate_design_report = function(project, spec, goal_lock, drift_signal, horizon, llm_content) {
      spec_table <- list()
      results    <- project$current_results

      params <- c("pout_dbm", "pae_pct", "gain_db", "freq_ghz")
      for (param in params) {
        if (!is.null(spec[[param]])) {
          current <- if (!is.null(results[[param]])) results[[param]] else NA
          margin  <- if (!is.na(current)) round(current - spec[[param]], 2) else NA
          traffic <- if (is.na(margin))     "GREY"
                     else if (margin >= 0)  "GREEN"
                     else if (margin >= -1) "AMBER"
                     else                   "RED"
          spec_table[[param]] <- list(
            parameter = param, target = spec[[param]],
            achieved = current, margin = margin, status = traffic
          )
        }
      }

      return(list(
        title            = paste("PA Design Report —", if (!is.null(project$name)) project$name else "Unnamed Project"),
        generated_at     = Sys.time(),
        goal             = goal_lock$locked_goal,
        spec_compliance  = spec_table,
        drift_status     = drift_signal$status,
        drift_items      = drift_signal$drift_items,
        horizon          = horizon$summary,
        llm_analysis     = llm_content,
        next_steps       = if (drift_signal$status == "ON-TRACK")
                             "Proceed to next design phase per design plan."
                           else
                             "Address drift items before proceeding. Escalate to strategy-agent if OFF-COURSE."
      ))
    }
  )
)
