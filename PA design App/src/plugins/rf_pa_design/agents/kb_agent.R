# KB Agent - RF PA Design Plugin
# Knowledge base ingestion, vendor adaptation, extraction integrity, and KB governance

library(R6)
library(jsonlite)

KBAgent <- R6Class("KBAgent",
  inherit = BaseAgent,

  private = list(
    resolve_existing_path = function(candidates) {
      for (candidate in candidates) {
        if (file.exists(candidate) || dir.exists(candidate)) {
          return(candidate)
        }
      }
      NULL
    },

    as_lines = function(items) {
      if (length(items) == 0) return("none")
      paste(paste0("- ", items), collapse = "\n")
    },

    detect_vendor_mentions = function(query, known_vendors) {
      query_lc <- tolower(if (!is.null(query)) query else "")
      vendors <- Filter(function(vendor) {
        vendor_hyphen <- gsub("_", "-", vendor)
        grepl(vendor, query_lc, fixed = TRUE) || grepl(vendor_hyphen, query_lc, fixed = TRUE)
      }, known_vendors)
      unique(vendors)
    }
  ),

  public = list(
    name = "KB Agent",
    expertise = paste(
      "RF device knowledge-base ingestion, datasheet extraction workflows,",
      "vendor adaptation, figure/table normalization, provenance enforcement,",
      "and cross-agent KB governance"
    ),
    solve_log = list(),

    initialize = function(config = list()) {
      super$initialize(config)
      self$load_solve_log()
    },

    execute = function(task) {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      query <- task$query %||% "Assess the current KB ingestion request"
      context <- task$context %||% list()

      snapshot <- self$refresh_state()
      anomaly_check <- self$anomaly_scan(query, context, snapshot)
      requirements <- self$recommended_requirements(snapshot, query)
      collaboration <- self$collaboration_plan(query, snapshot)
      pov <- self$pov_check(query, snapshot, anomaly_check)

      system_prompt <- paste(
        "You are the KB Agent for the RF PA Design App.",
        "You specialise in guarded knowledge-base ingestion for RF device libraries.",
        "Your job is to critique extraction requests before implementation,",
        "respect provenance and review gates, adapt workflows to vendor-specific datasheet structure,",
        "and coordinate with other specialist agents when the request crosses domains.",
        "Always lead with anomaly findings, then a concrete extraction strategy, then collaboration handoffs.",
        "Never claim a vendor parser is production-ready unless the current repo state supports it."
      )

      prompt <- paste(
        query,
        "\n\nKB snapshot:",
        "\nConfigured vendors:", paste(snapshot$configured_vendors, collapse = ", "),
        "\nKB vendor folders:", paste(snapshot$kb_vendors, collapse = ", "),
        "\nVendor coverage:",
        paste(vapply(snapshot$vendor_inventory, function(item) {
          paste0(item$vendor, ": ", item$device_count, " device records, ", item$extracted_artifact_count, " extracted artifact folders")
        }, character(1)), collapse = " | "),
        "\nAnomaly check:\n", private$as_lines(anomaly_check$findings),
        "\nRequirements:\n", private$as_lines(requirements),
        "\nCollaboration plan:\n", private$as_lines(collaboration$handoffs),
        "\nPOV notes:\n", private$as_lines(unname(unlist(pov)))
      )

      llm_response <- self$call_llm(prompt, system_prompt)
      validation <- self$validate_response(llm_response$content, context)
      confidence <- min(validation$confidence, anomaly_check$confidence_ceiling)

      self$record_solve_log(list(
        timestamp = Sys.time(),
        query = query,
        anomalies = anomaly_check$severity,
        vendor_count = length(snapshot$configured_vendors),
        handoff_count = length(collaboration$handoffs)
      ))

      self$log_action("kb_request", list(
        query = query,
        severity = anomaly_check$severity,
        confidence = confidence,
        valid = validation$valid
      ))

      list(
        answer = llm_response$content,
        anomaly_check = anomaly_check,
        kb_snapshot = snapshot,
        requirements = requirements,
        collaboration = collaboration,
        pov = pov,
        confidence = confidence,
        valid = validation$valid && anomaly_check$severity != "critical",
        model_used = llm_response$model
      )
    },

    refresh_state = function() {
      catalog <- self$load_vendor_catalog()
      inventory <- self$load_kb_inventory()

      list(
        catalog_path = catalog$path,
        kb_root = inventory$kb_root,
        configured_vendors = catalog$vendors,
        vendor_products = catalog$product_counts,
        discovery_urls = catalog$discovery_urls,
        kb_vendors = inventory$vendors,
        vendor_inventory = inventory$vendor_inventory,
        vendor_metadata = inventory$vendor_metadata,
        primary_vendor = "ampleon",
        last_refreshed = as.character(Sys.time())
      )
    },

    load_vendor_catalog = function() {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      candidates <- c(
        "../tools/crawl4ai_kb_ingestion/configs/vendor_seed_catalog.yaml",
        "tools/crawl4ai_kb_ingestion/configs/vendor_seed_catalog.yaml",
        "PA design App/tools/crawl4ai_kb_ingestion/configs/vendor_seed_catalog.yaml"
      )
      catalog_path <- private$resolve_existing_path(candidates)
      if (is.null(catalog_path) || !requireNamespace("yaml", quietly = TRUE)) {
        return(list(path = catalog_path, vendors = character(0), product_counts = list(), discovery_urls = list()))
      }

      cfg <- tryCatch(yaml::read_yaml(catalog_path), error = function(...) NULL)
      if (is.null(cfg)) {
        return(list(path = catalog_path, vendors = character(0), product_counts = list(), discovery_urls = list()))
      }
      vendors <- names(cfg$vendors %||% list())
      product_counts <- lapply(cfg$vendors %||% list(), function(item) length(item$products %||% list()))
      discovery_urls <- lapply(cfg$vendors %||% list(), function(item) item$discovery_url %||% NULL)
      list(path = catalog_path, vendors = vendors, product_counts = product_counts, discovery_urls = discovery_urls)
    },

    load_kb_inventory = function() {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      candidates <- c("../data/kb", "data/kb", "PA design App/data/kb")
      kb_root <- private$resolve_existing_path(candidates)
      if (is.null(kb_root)) {
        return(list(kb_root = NULL, vendors = character(0), vendor_inventory = list()))
      }

      vendor_dirs <- list.dirs(kb_root, full.names = FALSE, recursive = FALSE)
      vendor_dirs <- vendor_dirs[!grepl("^_", vendor_dirs)]

      vendor_inventory <- lapply(vendor_dirs, function(vendor) {
        vendor_dir <- file.path(kb_root, vendor)
        devices_file <- file.path(vendor_dir, "devices.json")
        metadata_file <- file.path(vendor_dir, "_metadata.json")
        metadata <- if (file.exists(metadata_file)) {
          tryCatch(jsonlite::fromJSON(metadata_file, simplifyVector = FALSE), error = function(...) list())
        } else {
          list()
        }
        device_count <- 0
        if (file.exists(devices_file)) {
          device_count <- tryCatch(length(jsonlite::fromJSON(devices_file, simplifyVector = FALSE)), error = function(...) 0)
        }
        extracted_dir <- file.path(vendor_dir, "_extracted")
        extracted_count <- if (dir.exists(extracted_dir)) length(list.dirs(extracted_dir, recursive = FALSE)) else 0
        list(
          vendor = vendor,
          device_count = device_count,
          extracted_artifact_count = extracted_count,
          devices_file = if (file.exists(devices_file)) devices_file else NULL,
          metadata_file = if (file.exists(metadata_file)) metadata_file else NULL,
          metadata = metadata
        )
      })

      vendor_metadata <- stats::setNames(lapply(vendor_inventory, function(item) item$metadata %||% list()), vendor_dirs)

      list(kb_root = kb_root, vendors = vendor_dirs, vendor_inventory = vendor_inventory, vendor_metadata = vendor_metadata)
    },

    build_catalog_refresh_plan = function(workspace_spec = list(), snapshot = NULL) {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      snapshot <- snapshot %||% self$refresh_state()

      spec_freq_min <- suppressWarnings(as.numeric(workspace_spec$freq_min_mhz %||% NA_real_))
      spec_freq_max <- suppressWarnings(as.numeric(workspace_spec$freq_max_mhz %||% NA_real_))
      spec_freq_mid <- if (!is.na(spec_freq_min) && !is.na(spec_freq_max)) {
        (spec_freq_min + spec_freq_max) / 2
      } else if (!is.na(spec_freq_min)) {
        spec_freq_min
      } else {
        suppressWarnings(as.numeric(workspace_spec$freq_mhz %||% NA_real_))
      }
      spec_pout_dbm <- suppressWarnings(as.numeric(workspace_spec$target_pout_dbm %||% NA_real_))
      spec_pout_w <- if (!is.na(spec_pout_dbm)) 10^((spec_pout_dbm - 30) / 10) else NA_real_
      spec_application <- tolower(trimws(workspace_spec$application %||% ""))

      plan <- lapply(snapshot$configured_vendors %||% character(0), function(vendor) {
        metadata <- snapshot$vendor_metadata[[vendor]] %||% list()
        catalog_url <- metadata$catalog_url %||% metadata$products_url %||% snapshot$discovery_urls[[vendor]] %||% ""
        url_pattern <- metadata$catalog_url_pattern %||% ""
        product_families <- metadata$product_families %||% list()
        key_markets <- tolower(unlist(metadata$key_markets %||% list(), use.names = FALSE))
        score <- if (identical(vendor, "ampleon")) 100 else 60
        reasons <- c()

        if (identical(vendor, "ampleon")) {
          reasons <- c(reasons, "Primary extraction target")
        }

        if (nzchar(catalog_url)) {
          score <- score + 10
          reasons <- c(reasons, "Catalog URL available")
        } else {
          score <- score - 40
          reasons <- c(reasons, "Catalog URL missing")
        }

        if (!is.na(spec_freq_mid) && length(product_families) > 0) {
          freq_hits <- Filter(function(item) {
            rng <- suppressWarnings(as.numeric(unlist(item$freq_range_mhz %||% list(), use.names = FALSE)))
            length(rng) >= 2 && is.finite(rng[[1]]) && is.finite(rng[[2]]) && spec_freq_mid >= rng[[1]] && spec_freq_mid <= rng[[2]]
          }, product_families)
          if (length(freq_hits) > 0) {
            score <- score + 18
            reasons <- c(reasons, paste0("Frequency overlap with ", length(freq_hits), " family"))
          }
        }

        if (!is.na(spec_pout_w) && length(product_families) > 0) {
          power_hits <- Filter(function(item) {
            rng <- suppressWarnings(as.numeric(unlist(item$power_range_w %||% list(), use.names = FALSE)))
            length(rng) >= 2 && is.finite(rng[[1]]) && is.finite(rng[[2]]) && spec_pout_w >= rng[[1]] && spec_pout_w <= rng[[2]]
          }, product_families)
          if (length(power_hits) > 0) {
            score <- score + 12
            reasons <- c(reasons, paste0("Power overlap with ", length(power_hits), " family"))
          }
        }

        if (nzchar(spec_application) && length(key_markets) > 0) {
          market_hits <- Filter(function(item) grepl(item, spec_application, fixed = TRUE) || grepl(spec_application, item, fixed = TRUE), key_markets)
          if (length(market_hits) > 0) {
            score <- score + 10
            reasons <- c(reasons, paste0("Application match: ", market_hits[[1]]))
          }
        }

        list(
          vendor = vendor,
          display_name = metadata$manufacturer %||% metadata$full_name %||% vendor,
          catalog_url = catalog_url,
          url_pattern = url_pattern,
          score = score,
          reasons = unique(reasons)
        )
      })

      plan[order(vapply(plan, function(item) item$score %||% 0, numeric(1)), decreasing = TRUE)]
    },

    anomaly_scan = function(query, context = list(), snapshot = NULL) {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      snapshot <- snapshot %||% self$refresh_state()
      findings <- character(0)
      severity <- "none"
      confidence_ceiling <- 0.95

      if (length(snapshot$configured_vendors) == 0) {
        findings <- c(findings, "CRITICAL: vendor seed catalog is missing or unreadable, so KB extension work would be blind.")
        severity <- "critical"
        confidence_ceiling <- 0.35
      }

      missing_vendor_files <- vapply(snapshot$configured_vendors, function(vendor) {
        !vendor %in% snapshot$kb_vendors
      }, logical(1))
      if (any(missing_vendor_files)) {
        findings <- c(
          findings,
          paste0("HIGH: configured vendors without KB folders: ", paste(snapshot$configured_vendors[missing_vendor_files], collapse = ", "), ".")
        )
        if (severity == "none") severity <- "high"
        confidence_ceiling <- min(confidence_ceiling, 0.6)
      }

      missing_catalog_meta <- vapply(snapshot$configured_vendors, function(vendor) {
        metadata <- snapshot$vendor_metadata[[vendor]] %||% list()
        !nzchar(metadata$catalog_url %||% metadata$products_url %||% snapshot$discovery_urls[[vendor]] %||% "")
      }, logical(1))
      if (any(missing_catalog_meta)) {
        findings <- c(
          findings,
          paste0("MEDIUM: vendors without catalog metadata: ", paste(snapshot$configured_vendors[missing_catalog_meta], collapse = ", "), ".")
        )
        if (severity == "none") severity <- "medium"
        confidence_ceiling <- min(confidence_ceiling, 0.8)
      }

      mentioned_vendors <- private$detect_vendor_mentions(query, snapshot$configured_vendors)
      unknown_vendor_pattern <- regmatches(query, gregexpr("[A-Za-z]+", query, perl = TRUE))[[1]]
      unknown_vendor_pattern <- unique(tolower(unknown_vendor_pattern))
      unknown_vendor_pattern <- setdiff(unknown_vendor_pattern, c(tolower(snapshot$configured_vendors), "vendor", "vendors", "kb", "agent", "pdf", "figure", "figures", "table", "tables"))
      if (length(mentioned_vendors) == 0 && grepl("vendor", tolower(query), fixed = TRUE)) {
        findings <- c(findings, "MEDIUM: request asks for vendor handling without naming a target vendor, so the parser strategy should stay generic-first.")
        if (severity == "none") severity <- "medium"
        confidence_ceiling <- min(confidence_ceiling, 0.75)
      }

      if (grepl("apply|merge|production", tolower(query)) && !isTRUE(context$approved_for_apply)) {
        findings <- c(findings, "HIGH: request implies production merge/apply, but no approval flag was provided for guarded KB ingestion.")
        if (severity %in% c("none", "medium")) severity <- "high"
        confidence_ceiling <- min(confidence_ceiling, 0.55)
      }

      if (length(findings) == 0) {
        findings <- "NONE FOUND - current KB state supports incremental extension work."
      }

      list(
        severity = severity,
        findings = findings,
        confidence_ceiling = confidence_ceiling,
        mentioned_vendors = mentioned_vendors,
        lexical_outliers = head(unknown_vendor_pattern, 8)
      )
    },

    recommended_requirements = function(snapshot, query) {
      requirements <- c(
        "Python packages: crawl4ai, pdfplumber, requests, pyyaml",
        "R packages: jsonlite, yaml",
        "Per-record provenance: URL, crawl timestamp, HTTP status, content SHA-256",
        "Artifact-first workflow before any KB apply/merge",
        "Vendor profile boundary between generic parsing and vendor-specific table/figure logic"
      )

      if (grepl("figure|thumbnail|hover|plot|pcb", tolower(query))) {
        requirements <- c(requirements, "Extracted figure pages or thumbnails must resolve to local KB artifact paths for Shiny preview rendering")
      }

      if (length(snapshot$configured_vendors) > 0) {
        requirements <- c(requirements, paste0("Current configured vendors: ", paste(snapshot$configured_vendors, collapse = ", ")))
      }
      if (length(snapshot$vendor_metadata %||% list()) > 0) {
        requirements <- c(requirements, "Per-vendor catalog metadata should expose products_url or catalog_url for automated refresh planning")
      }

      unique(requirements)
    },

    collaboration_plan = function(query, snapshot) {
      query_lc <- tolower(query)
      handoffs <- c("StrategyAgent for multi-step rollout sequencing")
      if (grepl("report|document|review|summary", query_lc)) {
        handoffs <- c(handoffs, "DocumentationAgent for KB change reporting and review-ready summaries")
      }
      if (grepl("import|ingest|parse|pdf|datasheet|touchstone", query_lc)) {
        handoffs <- c(handoffs, "Import Pipeline Agent for file-format handling and parser troubleshooting")
      }
      if (grepl("sim|measurement|spec", query_lc)) {
        handoffs <- c(handoffs, "MeasurementAgent and SimulationAgent when datasheet claims need validation against lab or model data")
      }
      if (length(snapshot$configured_vendors) > 2) {
        handoffs <- c(handoffs, "Mission Compass if vendor expansion starts drifting from the original guarded-ingestion goal")
      }

      list(
        primary_agent = "KBAgent",
        handoffs = unique(handoffs)
      )
    },

    pov_check = function(query, snapshot, anomaly_check) {
      list(
        mission_compass = if (grepl("agent", tolower(query)) && anomaly_check$severity == "none") {
          "Goal remains aligned: KB work still serves guarded ingestion and structured device retrieval."
        } else {
          "Watch for drift: KB changes should improve extraction fidelity, not expand scope into uncontrolled crawling."
        },
        self = if (length(snapshot$configured_vendors) >= 1) {
          "Within domain: live vendor catalog and KB inventory were refreshed before answering."
        } else {
          "Domain risk: vendor catalog could not be confirmed, so recommendations should stay provisional."
        },
        downstream = "Outputs stay actionable only if they preserve the artifact-first review gate and keep vendor-specific parsing isolated behind explicit profiles."
      )
    },

    pov_influence = function(target_agent_name, snapshot = NULL) {
      `%||%` <- function(a, b) if (!is.null(a)) a else b
      snapshot <- snapshot %||% self$refresh_state()
      blind_spots <- list(
        StrategyAgent = "May sequence KB expansion work without checking whether vendor-specific parser coverage actually exists.",
        DocumentationAgent = "May summarize KB state without surfacing provenance gaps or parser limitations.",
        MeasurementAgent = "May trust datasheet claims without distinguishing measured tables from marketing summary text.",
        SimulationAgent = "May consume extracted RF values without checking whether they came from structured tables or text fallback."
      )

      list(
        target_agent = target_agent_name,
        blind_spot = blind_spots[[target_agent_name]] %||% "Target agent has no KB-specific POV entry yet.",
        suggested_tune = paste(
          "Pass the current KB vendor inventory (",
          paste(snapshot$configured_vendors, collapse = ", "),
          ") into", target_agent_name,
          "before making decisions that depend on datasheet structure or parser coverage."
        )
      )
    },

    record_solve_log = function(entry) {
      self$solve_log <- c(self$solve_log, list(entry))
      dir.create("logs", showWarnings = FALSE, recursive = TRUE)
      tryCatch(
        write(jsonlite::toJSON(self$solve_log, pretty = TRUE, auto_unbox = TRUE), "logs/kb_agent_state.json"),
        error = function(e) message("KB Agent: could not write solve log - ", e$message)
      )
    },

    load_solve_log = function() {
      log_file <- "logs/kb_agent_state.json"
      if (file.exists(log_file)) {
        tryCatch({
          self$solve_log <- jsonlite::fromJSON(log_file, simplifyVector = FALSE)
        }, error = function(...) {
          self$solve_log <- list()
        })
      }
    }
  )
)