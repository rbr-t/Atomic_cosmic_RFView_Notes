# Strategy Agent - RF PA Design Plugin
# Multi-agent orchestration, design flow management, cube-based path planning
# Essence embedded from: Rubix (cube model, 9-path generation, solve log, POV influence)

StrategyAgent <- R6Class("StrategyAgent",
  inherit = BaseAgent,

  public = list(
    name = "Strategy Agent",
    expertise = "RF PA design flow orchestration, multi-agent collaboration, topology-to-tape-out path planning, design risk mitigation, Rubix cube-model problem solving for RF engineering",

    # --- RUBIX: 6 design cube faces mapped to PA design domain ---
    cube_faces = list(
      goal        = list(colour = "White", represents = "Target spec: Pout, PAE, gain, bandwidth, linearity, technology"),
      foundation  = list(colour = "Yellow", represents = "Known reality: available devices, fab process, tools, prior art"),
      front       = list(colour = "Red",   represents = "Active work: current design phase, simulation state, layout progress"),
      context     = list(colour = "Orange", represents = "Constraints: schedule, budget, NRE, application requirements"),
      process     = list(colour = "Blue",  represents = "Agents and workflow: who is doing what, handoffs, dependencies"),
      quality     = list(colour = "Green", represents = "Integrity: margins, thermal, stability, reliability, testability")
    ),

    solve_log = list(),  # Rubix self-improvement log

    initialize = function(config = list()) {
      super$initialize(config)
      self$load_solve_log()
    },

    execute = function(task) {
      query      <- task$query
      context    <- if (!is.null(task$context)) task$context else list()
      project    <- if (!is.null(task$project)) task$project else list()
      spec       <- if (!is.null(task$spec))    task$spec    else list()
      agent_mgr  <- task$agent_manager  # Optional: AgentManager instance

      # --- RUBIX STEP 1: Map the design cube ---
      cube_map <- self$map_design_cube(project, spec)

      # --- RUBIX STEP 2: Generate 9 candidate paths ---
      paths <- self$generate_paths(cube_map, spec)

      # --- RUBIX STEP 3: Recommend one path ---
      recommendation <- self$recommend_path(paths, cube_map)

      # --- RUBIX STEP 4: Expand recommended path into move sequence ---
      move_sequence <- self$expand_move_sequence(recommendation, project, spec)

      system_prompt <- paste(
        "You are a senior RF PA design strategist and project architect.",
        "You coordinate the full design flow from spec to silicon/PCB:\n",
        "- Topology selection through architecture-agent\n",
        "- Simulation setup and validation through simulation-agent\n",
        "- Layout review through layout-agent\n",
        "- Lab measurement planning through measurement-agent\n",
        "- Failure diagnosis through debug-agent\n",
        "- Report generation through documentation-agent\n",
        "You define which agents to engage in which order, what inputs they need,",
        "and how to interpret their outputs to keep the design on course.",
        "Always state the risk of each design path and why the recommended path was chosen."
      )

      cube_summary <- paste(
        "Design cube state:\n",
        "  Goal face:", cube_map$face_status$goal, "\n",
        "  Foundation:", cube_map$face_status$foundation, "\n",
        "  Front (active work):", cube_map$face_status$front, "\n",
        "  Context:", cube_map$face_status$context, "\n",
        "  Process:", cube_map$face_status$process, "\n",
        "  Quality:", cube_map$face_status$quality, "\n",
        "Solved faces:", paste(cube_map$solved_faces, collapse = ", "), "\n",
        "Unsolved:", paste(cube_map$unsolved_faces, collapse = ", ")
      )

      llm_response <- self$call_llm(
        paste(query, "\n\n", cube_summary,
              "\n\nRecommended path:", recommendation$path_id,
              "\nMove sequence:\n",
              paste(sapply(move_sequence, function(m) paste0("  Move ", m$move, ": ", m$action)), collapse = "\n")),
        system_prompt
      )
      validation <- self$validate_response(llm_response$content, context)

      # --- RUBIX STEP 4: Record solve log ---
      self$record_solve_log(list(
        date          = Sys.Date(),
        cube_size     = cube_map$cube_size,
        problem_tag   = substr(query, 1, 60),
        path_chosen   = recommendation$path_id,
        total_moves   = length(move_sequence),
        outcome       = "IN_PROGRESS",
        reuse_pattern = recommendation$rationale
      ))

      self$log_action("strategy_plan", list(
        cube_size       = cube_map$cube_size,
        path_chosen     = recommendation$path_id,
        solved_faces    = length(cube_map$solved_faces),
        confidence      = validation$confidence
      ))

      return(list(
        strategy       = llm_response$content,
        cube_map       = cube_map,
        paths          = paths,
        recommendation = recommendation,
        move_sequence  = move_sequence,
        confidence     = validation$confidence,
        valid          = validation$valid,
        model_used     = llm_response$model
      ))
    },

    # --- RUBIX STEP 1: Map the PA design cube ---
    map_design_cube = function(project, spec) {
      face_status <- list(
        goal       = if (!is.null(spec$pout_dbm) && !is.null(spec$pae_pct) &&
                        !is.null(spec$freq_ghz))                         "SOLVED"
                     else if (!is.null(spec$pout_dbm))                  "PARTIAL"
                     else                                                "UNSOLVED",
        foundation = if (!is.null(spec$technology))                     "SOLVED"
                     else                                                "UNSOLVED",
        front      = if (!is.null(project$topology))                    "SOLVED"
                     else if (!is.null(project$current_phase))          "PARTIAL"
                     else                                                "UNSOLVED",
        context    = if (!is.null(spec$application) && !is.null(project$schedule)) "SOLVED"
                     else if (!is.null(spec$application))               "PARTIAL"
                     else                                                "UNSOLVED",
        process    = if (!is.null(project$current_phase))               "PARTIAL"
                     else                                                "UNSOLVED",
        quality    = if (!is.null(project$stability_verified) && project$stability_verified) "SOLVED"
                     else if (!is.null(project$current_results))        "PARTIAL"
                     else                                                "UNSOLVED"
      )

      solved   <- names(face_status)[unlist(face_status) == "SOLVED"]
      partial  <- names(face_status)[unlist(face_status) == "PARTIAL"]
      unsolved <- names(face_status)[unlist(face_status) == "UNSOLVED"]

      cube_size <- if (length(unsolved) == 0)     "2x2"
                   else if (length(unsolved) <= 2) "3x3"
                   else if (length(unsolved) <= 4) "4x4"
                   else                            "NxN"

      return(list(
        cube_size      = cube_size,
        face_status    = face_status,
        solved_faces   = solved,
        partial_faces  = partial,
        unsolved_faces = unsolved,
        solved_cubies  = list(spec = spec, project = project)
      ))
    },

    # --- RUBIX STEP 2: Generate 9 design flow paths ---
    generate_paths = function(cube_map, spec) {
      tech <- if (!is.null(spec$technology)) spec$technology else "GaN"
      freq <- if (!is.null(spec$freq_ghz))  spec$freq_ghz  else 2.0

      paths <- list(
        # FAST paths
        F1 = list(path_id = "F1", group = "fast",
          sequence   = c("architecture-agent", "simulation-agent", "layout-agent", "measurement-agent"),
          description = "Standard topology → HB simulation → layout → single measurement iteration",
          moves      = 4, risk = "HIGH",
          integrity  = "80%",
          rationale  = "Fastest path to first-pass hardware. High risk of multiple respins."),
        F2 = list(path_id = "F2", group = "fast",
          sequence   = c("architecture-agent", "layout-agent", "measurement-agent"),
          description = "Skip detailed simulation — use existing load-pull data for topology, go to layout directly",
          moves      = 3, risk = "HIGH",
          integrity  = "70%",
          rationale  = "Only valid if technology and topology are well-characterised from prior designs."),
        F3 = list(path_id = "F3", group = "fast",
          sequence   = c("theory-agent", "simulation-agent", "measurement-agent"),
          description = "Theory-first small-signal design → simulation → measure (skip dedicated layout agent)",
          moves      = 3, risk = "MEDIUM",
          integrity  = "75%",
          rationale  = "Good for well-known topologies where layout parasitics are low-impact."),

        # BALANCED paths
        M1 = list(path_id = "M1", group = "balanced",
          sequence   = c("architecture-agent", "simulation-agent", "debug-agent", "layout-agent", "measurement-agent"),
          description = "Architecture → HB sim → sim sanity check → layout → measurement",
          moves      = 5, risk = "MEDIUM",
          integrity  = "88%",
          rationale  = "Recommended for first GaN/LDMOS designs. Debug-agent catches sim anomalies before layout."),
        M2 = list(path_id = "M2", group = "balanced",
          sequence   = c("theory-agent", "architecture-agent", "simulation-agent", "layout-agent", "measurement-agent", "documentation-agent"),
          description = "Full design flow with documentation gate before tapeout",
          moves      = 6, risk = "MEDIUM",
          integrity  = "92%",
          rationale  = "Best for product development where design review gates are required."),
        M3 = list(path_id = "M3", group = "balanced",
          sequence   = c("architecture-agent", "simulation-agent", "layout-agent", "debug-agent", "measurement-agent"),
          description = "Architecture → sim → layout → debug correlation → measurement",
          moves      = 5, risk = "MEDIUM",
          integrity  = "85%",
          rationale  = "Debug-agent used post-layout for EM/sim correlation before hardware is ordered."),

        # CONSERVATIVE paths
        L1 = list(path_id = "L1", group = "conservative",
          sequence   = c("theory-agent", "architecture-agent", "simulation-agent", "debug-agent", "layout-agent", "debug-agent", "measurement-agent", "documentation-agent"),
          description = "Full rigorous flow: theory → architecture → sim → debug × 2 → layout → measurement → documentation",
          moves      = 8, risk = "LOW",
          integrity  = "97%",
          rationale  = "For safety-critical or high-NRE designs where respins are very costly."),
        L2 = list(path_id = "L2", group = "conservative",
          sequence   = c("architecture-agent", "simulation-agent", "simulation-agent", "layout-agent", "measurement-agent", "debug-agent", "documentation-agent"),
          description = "Two simulation passes (schematic + EM co-simulation) before layout",
          moves      = 7, risk = "LOW",
          integrity  = "95%",
          rationale  = "Recommended for frequencies > 6GHz where EM effects dominate."),
        L3 = list(path_id = "L3", group = "conservative",
          sequence   = c("theory-agent", "architecture-agent", "simulation-agent", "layout-agent", "simulation-agent", "measurement-agent", "debug-agent", "documentation-agent"),
          description = "Theory anchoring → post-layout EM re-simulation → measurement correlation",
          moves      = 8, risk = "LOW",
          integrity  = "96%",
          rationale  = paste0("Recommended for ", tech, " at ", freq, " GHz with tight PAE spec."))
      )

      return(paths)
    },

    # --- RUBIX STEP 3: Recommend one path ---
    recommend_path = function(paths, cube_map) {
      n_unsolved <- length(cube_map$unsolved_faces)

      # Selection logic based on cube state
      recommended_id <- if (n_unsolved >= 4)       "M1"  # Many unknowns: balanced fast
                        else if (n_unsolved >= 2)   "M2"  # Some unknowns: balanced full
                        else                        "L1"  # Almost solved: conservative finish

      path <- paths[[recommended_id]]

      return(list(
        path_id    = recommended_id,
        path       = path,
        rationale  = paste0("Cube has ", n_unsolved, " unsolved face(s). ",
                            path$rationale, " Integrity: ", path$integrity, "."),
        confidence = if (n_unsolved == 0) "HIGH" else if (n_unsolved <= 2) "MEDIUM" else "LOW"
      ))
    },

    # Expand recommended path into ordered move sequence
    expand_move_sequence = function(recommendation, project, spec) {
      moves <- list()
      for (i in seq_along(recommendation$path$sequence)) {
        agent_name <- recommendation$path$sequence[[i]]
        moves[[i]] <- list(
          move       = i,
          agent      = agent_name,
          action     = paste0("Engage ", agent_name, " — ",
                              switch(agent_name,
                                "theory-agent"         = "derive load impedance and matching topology",
                                "architecture-agent"   = "select topology and generate 9 design paths",
                                "simulation-agent"     = "run harmonic balance + anomaly scan",
                                "layout-agent"         = "DRC check + substrate constraint audit",
                                "measurement-agent"    = "calibration audit + data import + integrity check",
                                "debug-agent"          = "run T-IKIA-T pipeline: sim-vs-meas correlation",
                                "documentation-agent"  = "generate compass reading + spec compliance report",
                                "unknown action"
                              )),
          face_affected = switch(agent_name,
            "theory-agent"        = "goal",
            "architecture-agent"  = "front",
            "simulation-agent"    = "front",
            "layout-agent"        = "quality",
            "measurement-agent"   = "quality",
            "debug-agent"         = "foundation",
            "documentation-agent" = "context",
            "unknown"
          )
        )
      }
      return(moves)
    },

    # --- RUBIX: POV Influence — advise another agent on its blind spot ---
    pov_influence = function(target_agent_name, cube_map) {
      blind_spots <- list(
        "theory-agent"        = "Cannot see layout parasitics or measurement calibration state. May over-idealise device performance.",
        "architecture-agent"  = "Cannot see simulation convergence or measurement floor. May select topology that is theoretically optimal but practically difficult.",
        "simulation-agent"    = "Cannot see actual lab cal state or process variation. Simulation results are model-limited.",
        "layout-agent"        = "Cannot see bias supply current waveforms or thermal runaway conditions. Focuses on geometric rules only.",
        "measurement-agent"   = "Cannot see simulation reference planes or model assumptions. May not correlate correctly without sim data.",
        "debug-agent"         = "Needs both sim and meas data to be useful. Without both, hypotheses are speculative.",
        "documentation-agent" = "Reflects past state — cannot predict future drift. Must be re-run at each design gate."
      )

      return(list(
        target_agent = target_agent_name,
        current_scope = paste("Handles", target_agent_name, "domain tasks"),
        blind_spot    = blind_spots[[target_agent_name]],
        suggested_tune = paste("Pass cube_map$face_status to", target_agent_name,
                               "so it can see what faces are solved and calibrate confidence accordingly."),
        long_term_aim  = "All agents should emit confidence levels relative to unsolved cube faces, not absolute."
      ))
    },

    # Rubix solve log management
    record_solve_log = function(entry) {
      self$solve_log <- c(self$solve_log, list(entry))

      log_file <- "logs/strategy_solve_log.json"
      dir.create("logs", showWarnings = FALSE, recursive = TRUE)
      tryCatch(
        write(jsonlite::toJSON(self$solve_log, pretty = TRUE, auto_unbox = TRUE), log_file),
        error = function(e) message("Could not write solve log: ", e$message)
      )
    },

    load_solve_log = function() {
      log_file <- "logs/strategy_solve_log.json"
      if (file.exists(log_file)) {
        tryCatch({
          self$solve_log <- jsonlite::fromJSON(log_file, simplifyVector = FALSE)
          message("Strategy Agent: loaded ", length(self$solve_log), " solve log entries.")
        }, error = function(e) {
          message("Strategy Agent: could not load solve log — starting fresh.")
        })
      }
    }
  )
)
