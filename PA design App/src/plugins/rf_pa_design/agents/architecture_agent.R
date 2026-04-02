# Architecture Agent - RF PA Design Plugin
# Topology selection, stage planning, design path generation
# Essence embedded from: Rubix (multi-path cube model) + Mission Compass (spec alignment)

ArchitectureAgent <- R6Class("ArchitectureAgent",
  inherit = BaseAgent,

  public = list(
    name = "Architecture Agent",
    expertise = "PA topology selection, Doherty/balanced/push-pull/Chireix architectures, stage planning, spec-to-topology mapping",

    # --- RUBIX: 6 design faces mapped to PA domain ---
    design_faces = list(
      goal        = "Target spec: Pout, PAE, gain, bandwidth, linearity",
      foundation  = "Technology: GaN/LDMOS/SiC, Vdd, fT, power density",
      front       = "Active implementation: topology, combiner, driver stages",
      context     = "Application: base station, satellite, radar, handset",
      process     = "Design flow: stages → simulation → layout → measurement",
      quality     = "Margins: thermal, stability, reliability, reproducibility"
    ),

    initialize = function(config = list()) {
      super$initialize(config)
    },

    execute = function(task) {
      query   <- task$query
      context <- if (!is.null(task$context)) task$context else list()
      spec    <- if (!is.null(task$spec))    task$spec    else list()

      # --- MISSION COMPASS: lock goal to original spec before any topology work ---
      goal_lock <- self$lock_spec_goal(spec)

      system_prompt <- paste(
        "You are a senior RF power amplifier architect with 20+ years of experience.",
        "You specialise in:\n",
        "- Doherty (2-way, 3-way, asymmetric, wideband Doherty)\n",
        "- Balanced/push-pull (Wilkinson, hybrid combiner, transformer-coupled)\n",
        "- Chireix outphasing / LINC architecture\n",
        "- Envelope tracking and envelope elimination and restoration (ET/EER)\n",
        "- Distributed power amplifiers (DPA)\n",
        "- Stacked/cascode topologies for high-voltage operation\n",
        "Always state: topology rationale, tradeoffs vs alternatives,",
        "technology suitability, and spec margin risk.",
        "If the spec is infeasible with the stated technology, say so explicitly."
      )

      # Enrich query with spec context
      if (!is.null(spec$pout_dbm))    query <- paste(query, "\nTarget Pout:", spec$pout_dbm, "dBm")
      if (!is.null(spec$freq_ghz))    query <- paste(query, "\nFrequency:", spec$freq_ghz, "GHz")
      if (!is.null(spec$pae_pct))     query <- paste(query, "\nTarget PAE:", spec$pae_pct, "%")
      if (!is.null(spec$technology))  query <- paste(query, "\nTechnology:", spec$technology)
      if (!is.null(spec$bandwidth_mhz)) query <- paste(query, "\nBandwidth:", spec$bandwidth_mhz, "MHz")
      if (!is.null(spec$application)) query <- paste(query, "\nApplication:", spec$application)

      # Generate multi-path topology options (Rubix 3-group path structure)
      paths <- self$generate_topology_paths(spec)

      # KB lookup for comparable designs
      kb_results <- self$query_knowledge_base(query, top_k = 3)

      enhanced_query <- paste(
        query,
        "\n\nKnowledge base references:",
        paste(sapply(kb_results$results, function(r) r$text), collapse = "\n"),
        "\n\nTopology options to consider:\n",
        paste(sapply(paths, function(p) paste0("- ", p$topology, ": ", p$rationale)), collapse = "\n")
      )

      llm_response <- self$call_llm(enhanced_query, system_prompt)
      validation   <- self$validate_response(llm_response$content, context)

      self$log_action("topology_selection", list(
        spec       = spec,
        goal_lock  = goal_lock,
        paths      = paths,
        confidence = validation$confidence
      ))

      return(list(
        recommendation  = llm_response$content,
        topology_paths  = paths,
        goal_lock       = goal_lock,
        confidence      = validation$confidence,
        valid           = validation$valid,
        references      = kb_results$citations,
        model_used      = llm_response$model
      ))
    },

    # --- MISSION COMPASS: lock the spec as the immovable goal reference ---
    lock_spec_goal = function(spec) {
      goal_sentence <- paste0(
        "Design a PA delivering ",
        if (!is.null(spec$pout_dbm)) paste0(spec$pout_dbm, " dBm") else "target Pout",
        " at ",
        if (!is.null(spec$freq_ghz)) paste0(spec$freq_ghz, " GHz") else "target frequency",
        " with ",
        if (!is.null(spec$pae_pct))  paste0(spec$pae_pct, "% PAE") else "target PAE",
        " using ",
        if (!is.null(spec$technology)) spec$technology else "target technology",
        "."
      )
      return(list(
        locked_goal = goal_sentence,
        spec_hash   = digest::digest(spec, algo = "md5"),
        timestamp   = Sys.time()
      ))
    },

    # --- RUBIX: Generate 9 topology paths (3 aggressive / 3 balanced / 3 conservative) ---
    generate_topology_paths = function(spec) {
      freq    <- if (!is.null(spec$freq_ghz))   spec$freq_ghz   else 2.0
      pout    <- if (!is.null(spec$pout_dbm))   spec$pout_dbm   else 43
      pae     <- if (!is.null(spec$pae_pct))    spec$pae_pct    else 50
      tech    <- if (!is.null(spec$technology)) spec$technology else "GaN"
      bw      <- if (!is.null(spec$bandwidth_mhz)) spec$bandwidth_mhz else 100

      paths <- list()

      # --- FAST / AGGRESSIVE PATHS (fewest stages, highest risk) ---
      paths[["F1"]] <- list(
        group    = "fast",
        topology = "2-way Doherty",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Highest efficiency at 6dB backoff. Industry standard for base stations. Best PAE vs linearity tradeoff.",
        pae_estimate_pct  = min(pae + 10, 75),
        risk     = "Requires precise output combiner phase balance; bandwidth limited by quarter-wave transformer",
        suitable_for = c("base station", "small cell", "CATV")
      )

      paths[["F2"]] <- list(
        group    = "fast",
        topology = "Balanced (Wilkinson + 90-deg hybrid)",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Excellent return loss and even harmonic suppression. Simple combiner. Less efficiency gain than Doherty.",
        pae_estimate_pct  = min(pae + 2, 60),
        risk     = "6dB power combining loss at full power; combiner loss dominates efficiency at lower power",
        suitable_for = c("wideband", "high linearity", "test instrumentation")
      )

      paths[["F3"]] <- list(
        group    = "fast",
        topology = "Push-Pull (transformer coupled)",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Even harmonics cancel at output. Balanced current drive. Proven at HF–UHF.",
        pae_estimate_pct  = min(pae + 5, 70),
        risk     = "Transformer bandwidth limits operation above 1GHz; common-mode stability must be verified",
        suitable_for = c("HF", "VHF", "UHF", "broadcast")
      )

      # --- BALANCED PATHS ---
      paths[["M1"]] <- list(
        group    = "balanced",
        topology = "3-way Doherty",
        stages   = self$plan_stage_count(pout, freq, tech) + 1,
        rationale = "Efficiency peak at both 9.5dB and 6dB backoff. Better PAPR handling for OFDM signals.",
        pae_estimate_pct  = min(pae + 12, 78),
        risk     = "More complex combiner; 3 devices must be matched. Higher sensitivity to process variation.",
        suitable_for = c("5G NR", "LTE-A", "massive MIMO")
      )

      paths[["M2"]] <- list(
        group    = "balanced",
        topology = "Envelope Tracking (ET)",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Dynamic supply modulation. Efficiency maintained across entire power range.",
        pae_estimate_pct  = min(pae + 15, 80),
        risk     = "Requires ET modulator with bandwidth > signal BW; system complexity increases significantly",
        suitable_for = c("handset", "small cell", "wideband 5G")
      )

      paths[["M3"]] <- list(
        group    = "balanced",
        topology = "Asymmetric Doherty (2:1 ratio)",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Efficiency peak shifted to higher backoff depth. Better match to high PAPR signals.",
        pae_estimate_pct  = min(pae + 8, 72),
        risk     = "Main/peaking device ratio optimisation is iterative; simulation-dependent",
        suitable_for = c("LTE", "5G sub-6GHz", "satellite uplink")
      )

      # --- CONSERVATIVE / SAFE PATHS ---
      paths[["L1"]] <- list(
        group    = "conservative",
        topology = "Single-ended (reference design)",
        stages   = self$plan_stage_count(pout, freq, tech),
        rationale = "Simplest topology. Maximum design confidence. Use as baseline before optimisation.",
        pae_estimate_pct  = min(pae, 55),
        risk     = "No efficiency enhancement. Baseline only.",
        suitable_for = c("prototyping", "reference", "technology evaluation")
      )

      paths[["L2"]] <- list(
        group    = "conservative",
        topology = "Chireix outphasing (LINC)",
        stages   = self$plan_stage_count(pout, freq, tech) + 1,
        rationale = "High peak efficiency. Amplitude and phase modulation via vector sum. No combiner loss at peak.",
        pae_estimate_pct  = min(pae + 18, 82),
        risk     = "Requires precise phase modulation; sensitive to component tolerances; DSP overhead",
        suitable_for = c("highly linear applications", "OFDM with very high PAPR")
      )

      paths[["L3"]] <- list(
        group    = "conservative",
        topology = "Distributed PA (DPA / travelling wave)",
        stages   = 4,
        rationale = "Wideband by design (decade bandwidth possible). Gain and power distributed across multiple devices.",
        pae_estimate_pct  = min(pae - 5, 45),
        risk     = "Lower PAE due to termination losses. Large die area. High complexity.",
        suitable_for = c("broadband electronic warfare", "test instrumentation", "wideband radar")
      )

      return(paths)
    },

    # Stage count estimation based on Pout, frequency, and technology power density
    plan_stage_count = function(pout_dbm, freq_ghz, technology = "GaN") {
      # Technology max single-stage Pout estimates (dBm) at given frequency
      tech_limits <- list(
        "GaN"  = max(10, 50 - 3 * log10(freq_ghz + 0.1)),
        "LDMOS"= max(10, 50 - 4 * log10(freq_ghz + 0.1)),
        "SiC"  = max(10, 48 - 3 * log10(freq_ghz + 0.1)),
        "GaAs" = max(10, 38 - 3 * log10(freq_ghz + 0.1))
      )
      limit_dbm <- tech_limits[[technology]]
      if (is.null(limit_dbm)) limit_dbm <- 40

      if (pout_dbm <= limit_dbm)       return(1)
      else if (pout_dbm <= limit_dbm + 6) return(2)  # 4-way combine at final stage
      else                              return(3)
    },

    # --- RUBIX POV: Check if proposed topology solves ALL 6 design faces ---
    pov_cube_check = function(topology_path, spec) {
      checks <- list(
        goal       = !is.null(spec$pout_dbm) && !is.null(spec$pae_pct),
        foundation = !is.null(spec$technology),
        front      = !is.null(topology_path$topology),
        context    = !is.null(spec$application),
        process    = !is.null(topology_path$stages),
        quality    = !is.null(topology_path$risk)
      )

      unsolved <- names(checks)[!unlist(checks)]

      return(list(
        all_faces_covered = length(unsolved) == 0,
        unsolved_faces    = unsolved,
        solved_faces      = names(checks)[unlist(checks)]
      ))
    }
  )
)
