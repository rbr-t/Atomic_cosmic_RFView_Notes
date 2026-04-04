# =============================================================================
# server_knowledge_base.R
# Knowledge Base Shiny server module for the PA Design App.
#
# Provides:
#   · Searchable, filterable device table (DT)
#   · Device detail panel (specs, app notes, impedance)
#   · "Load Ropt to Smith Chart" button
#   · "Add to Lineup Canvas" button
#   · Utility drawer quick-search (handled via output$kb_drawer_*)
# =============================================================================

serverKnowledgeBase <- function(input, output, session, state) {

  # ── Load all KB data and allow refresh after ingestion apply ──────────────
  load_kb_all <- function() {
    tryCatch(
      kb_load_all(kb_root = "../data/kb"),
      error = function(e) {
        message("[KB] Failed to load knowledge base: ", e$message)
        data.frame()
      }
    )
  }
  kb_all_rv <- reactiveVal(load_kb_all())

  reload_kb_all <- function() {
    kb_all_rv(load_kb_all())
  }

  ingest_state <- reactiveValues(
    last_vendor = NULL,
    last_artifact = NULL,
    last_log = "Ready. Fill fields and click Fetch Preview.",
    last_technology = ""
  )

  protected_state <- reactiveValues(
    loaded_device_id = NULL,
    status = "Protected mode disabled."
  )

  crawl_root <- normalizePath("../tools/crawl4ai_kb_ingestion", winslash = "/", mustWork = FALSE)
  seed_catalog_path <- file.path(crawl_root, "configs", "vendor_seed_catalog.yaml")
  pipeline_script <- file.path(crawl_root, "crawl_kb_pipeline.py")
  validator_script <- file.path(crawl_root, "validate_kb_pipeline.py")

  get_python_exe <- function() {
    venv_py <- normalizePath(file.path(crawl_root, ".venv", "Scripts", "python.exe"), winslash = "/", mustWork = FALSE)
    if (file.exists(venv_py)) return(venv_py)

    py <- Sys.which("python")
    if (nzchar(py)) return(py)

    ""
  }

  normalize_vendor_key <- function(x) {
    x <- tolower(trimws(x %||% ""))
    x <- gsub("[^a-z0-9]+", "_", x)
    x <- gsub("(^_+|_+$)", "", x)
    x
  }

  normalize_external_url <- function(x) {
    x <- trimws(x %||% "")
    if (!nzchar(x)) return("")
    # Chrome PDF viewer wrapper: chrome-extension://.../https://host/file.pdf
    embedded <- regmatches(x, regexpr("https?://.*$", x, ignore.case = TRUE))
    if (length(embedded) == 1 && nzchar(embedded)) {
      x <- embedded
    }
    x
  }

  infer_vendor_key_from_url <- function(url) {
    url <- normalize_external_url(url)
    if (!nzchar(url)) return("")
    host <- tryCatch(tolower(httr::parse_url(url)$hostname %||% ""), error = function(e) "")
    if (grepl("ampleon", host, fixed = TRUE)) return("ampleon")
    if (grepl("nxp", host, fixed = TRUE)) return("nxp")
    if (grepl("qorvo", host, fixed = TRUE)) return("qorvo")
    if (grepl("guerrilla-rf", host, fixed = TRUE) || grepl("guerrilla_rf", host, fixed = TRUE)) return("guerrilla_rf")
    host <- gsub("^www\\.", "", host)
    sub("\\..*$", "", host)
  }

  infer_part_number_from_url <- function(url) {
    url <- normalize_external_url(url)
    if (!nzchar(url)) return("")
    path <- tryCatch(httr::parse_url(url)$path %||% "", error = function(e) "")
    tail <- basename(path)
    tail <- gsub("\\.(html?|pdf)$", "", tail, ignore.case = TRUE)
    tail <- gsub("^part[/_-]*", "", tail, ignore.case = TRUE)
    trimws(tail)
  }

  infer_manufacturer_from_vendor <- function(vendor_key) {
    switch(normalize_vendor_key(vendor_key),
      ampleon = "Ampleon",
      nxp = "NXP",
      qorvo = "Qorvo",
      guerrilla_rf = "Guerrilla RF",
      if (nzchar(vendor_key)) tools::toTitleCase(vendor_key) else ""
    )
  }

  default_extraction <- function(vendor_key, title_selector = NULL, datasheet_selector = NULL, summary_selector = NULL) {
    datasheet_selector_clean <- trimws(datasheet_selector %||% "")
    datasheet_pdf_url <- if (nzchar(datasheet_selector_clean) && grepl("^https?://", datasheet_selector_clean, ignore.case = TRUE)) {
      datasheet_selector_clean
    } else {
      NULL
    }
    list(
      selector_version = "pilot-v1",
      title_selector = if (!is.null(title_selector) && nzchar(trimws(title_selector))) trimws(title_selector) else "h1",
      datasheet_link_selector = if (!is.null(datasheet_selector) && nzchar(trimws(datasheet_selector)) && is.null(datasheet_pdf_url)) trimws(datasheet_selector) else "a[href*='data-sheet'], a[href*='datasheet'], a[href*='/docs/']",
      datasheet_pdf_url = datasheet_pdf_url,
      product_summary_selector = if (!is.null(summary_selector) && nzchar(trimws(summary_selector))) trimws(summary_selector) else "main, .product-details, .product-page"
    )
  }

  upsert_seed_product <- function(vendor_key, part_number, product_url, manufacturer, technology, freq_min_mhz, freq_max_mhz,
                                  title_selector = NULL, datasheet_selector = NULL, summary_selector = NULL) {
    if (!file.exists(seed_catalog_path)) {
      stop("Seed catalog not found: ", seed_catalog_path)
    }

    cfg <- yaml::read_yaml(seed_catalog_path)
    if (is.null(cfg$vendors)) cfg$vendors <- list()

    vendor_cfg <- cfg$vendors[[vendor_key]]
    if (is.null(vendor_cfg)) {
      vendor_cfg <- list(
        discovery_url = product_url,
        extraction_defaults = list(
          selector_version = "pilot-v1",
          title_selectors = list("h1", "title"),
          datasheet_link_patterns = list("/documents/data-sheet/", "/documents/datasheet/", "/docs/"),
          frequency_patterns = list("GHz", "MHz")
        ),
        products = list()
      )
    }

    existing <- vendor_cfg$products %||% list()
    existing <- Filter(function(p) {
      !identical(tolower(p$part_number %||% ""), tolower(part_number))
    }, existing)

    expected_block <- list()
    if (nzchar(trimws(manufacturer %||% "")))
      expected_block$manufacturer <- trimws(manufacturer)
    if (nzchar(trimws(technology %||% "")))
      expected_block$technology <- trimws(technology)
    if (!is.na(freq_min_mhz) && is.finite(freq_min_mhz) && as.numeric(freq_min_mhz) > 0)
      expected_block$freq_min_mhz <- as.numeric(freq_min_mhz)
    if (!is.na(freq_max_mhz) && is.finite(freq_max_mhz) && as.numeric(freq_max_mhz) > 0)
      expected_block$freq_max_mhz <- as.numeric(freq_max_mhz)

    new_product <- list(
      part_number = part_number,
      product_url = product_url,
      expected = expected_block,
      extraction = default_extraction(vendor_key, title_selector, datasheet_selector, summary_selector)
    )

    vendor_cfg$products <- c(list(new_product), existing)
    cfg$vendors[[vendor_key]] <- vendor_cfg

    yaml::write_yaml(cfg, seed_catalog_path)
  }

  run_crawl_cmd <- function(args) {
    py <- get_python_exe()
    if (!nzchar(py)) {
      return(list(ok = FALSE, out = c("Python executable not found. Configure crawl4ai venv first."), status = 127L))
    }
    if (length(args) == 0 || !file.exists(args[[1]])) {
      return(list(ok = FALSE, out = c("Crawler script not found:", args[[1]] %||% "<missing>"), status = 127L))
    }
    safe_args <- vapply(args, shQuote, character(1), type = "cmd")

    old_utf8 <- Sys.getenv("PYTHONUTF8", unset = "")
    old_ioenc <- Sys.getenv("PYTHONIOENCODING", unset = "")
    Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")
    on.exit({
      Sys.setenv(PYTHONUTF8 = old_utf8, PYTHONIOENCODING = old_ioenc)
    }, add = TRUE)

    out <- tryCatch(
      suppressWarnings(system2(py, args = safe_args, stdout = TRUE, stderr = TRUE)),
      error = function(e) c("Command failed:", e$message)
    )
    status <- attr(out, "status") %||% 0L
    debug_line <- paste("[DEBUG] cmd=", py, " ", paste(safe_args, collapse = " "))
    list(ok = identical(status, 0L), out = c(debug_line, out), status = status)
  }

  extract_artifact_path <- function(log_lines) {
    if (is.null(log_lines) || length(log_lines) == 0) return(NULL)
    hit <- grep("Wrote verification artifact:", log_lines, value = TRUE)
    if (length(hit) == 0) return(NULL)
    sub("^.*Wrote verification artifact:\\s*", "", tail(hit, 1))
  }

  extract_discovery_artifact_path <- function(log_lines) {
    if (is.null(log_lines) || length(log_lines) == 0) return(NULL)
    hit <- grep("Wrote discovery artifact:", log_lines, value = TRUE)
    if (length(hit) == 0) return(NULL)
    sub("^.*Wrote discovery artifact:\\s*", "", tail(hit, 1))
  }

  vendor_from_device_id <- function(device_id) {
    if (is.null(device_id) || !nzchar(device_id)) return(NA_character_)
    sub("_.*$", "", device_id)
  }

  vendor_devices_file <- function(device_id) {
    vendor <- vendor_from_device_id(device_id)
    if (is.na(vendor) || !nzchar(vendor)) return(NA_character_)
    file.path("..", "data", "kb", vendor, "devices.json")
  }

  load_vendor_devices <- function(path) {
    if (!file.exists(path)) return(list())
    jsonlite::read_json(path, simplifyVector = FALSE)
  }

  save_vendor_devices <- function(path, records) {
    if (!dir.exists(dirname(path))) dir.create(dirname(path), recursive = TRUE)
    jsonlite::write_json(records, path, pretty = TRUE, auto_unbox = TRUE)
  }

  get_record_index <- function(records, device_id) {
    which(vapply(records, function(x) identical(x$device_id %||% "", device_id), logical(1)))
  }

  validate_ingest_form <- function(vendor_key, part_number, product_url, manufacturer, freq_min, freq_max) {
    errs <- c()
    if (!nzchar(product_url)) errs <- c(errs, "Product URL is required")
    if (nzchar(product_url) && !grepl("^https?://", product_url, ignore.case = TRUE))
      errs <- c(errs, "Product URL must start with http:// or https://")
    if (!is.na(freq_min) && !is.na(freq_max) && freq_max < freq_min)
      errs <- c(errs, "Frequency max must be greater than or equal to frequency min")
    # Plausibility: RF PA frequencies are never < 20 MHz — values < 20 are likely GHz entered in wrong unit
    if (!is.na(freq_min) && freq_min > 0 && freq_min < 20)
      errs <- c(errs, sprintf(
        "Freq min = %.3g MHz looks like a GHz value (< 20\u202fMHz). Did you mean %.0f\u202fMHz?",
        freq_min, freq_min * 1000))
    if (!is.na(freq_max) && freq_max > 0 && freq_max < 20)
      errs <- c(errs, sprintf(
        "Freq max = %.3g MHz looks like a GHz value (< 20\u202fMHz). Did you mean %.0f\u202fMHz?",
        freq_max, freq_max * 1000))
    errs
  }

  render_artifact_summary <- function(artifact_path) {
    if (is.null(artifact_path) || !nzchar(artifact_path) || !file.exists(artifact_path)) {
      return(div(style = "margin-top:8px; font-size:11px; color:#8b8b96;",
        icon("file-alt"), " No artifact yet."
      ))
    }

    payload <- tryCatch(jsonlite::read_json(artifact_path, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(payload) || is.null(payload$records)) {
      return(div(style = "margin-top:8px; font-size:11px; color:#d9534f;",
        icon("exclamation-triangle"), " Could not read artifact summary."
      ))
    }

    recs <- payload$records
    n_records <- if (is.data.frame(recs)) nrow(recs) else length(recs)
    blocked <- isTRUE(payload$blocked_for_auto_merge)
    block_color <- if (blocked) "#d9534f" else "#5cb85c"
    block_text <- if (blocked) "BLOCKED" else "PASS"

    div(style = "margin-top:8px; padding:8px; border:1px solid #2a2a3a; border-radius:4px; background:#161622;",
      div(style = "font-size:11px; color:#ddd; font-weight:600;", icon("file-code"), " Last Artifact"),
      div(style = "font-size:11px; color:#aaa; margin-top:4px;", basename(artifact_path)),
      div(style = "font-size:11px; color:#aaa;", paste0("Records: ", n_records)),
      div(style = paste0("font-size:11px; color:", block_color, "; font-weight:700;"), paste0("Validation: ", block_text))
    )
  }

  split_filter_values <- function(values) {
    values <- values[!is.na(values)]
    values <- trimws(as.character(values))
    values <- values[nzchar(values)]
    if (length(values) == 0) return(character(0))
    pieces <- trimws(unlist(strsplit(values, ";", fixed = TRUE), use.names = FALSE))
    pieces[nzchar(pieces)]
  }

  count_filter_values <- function(values, split_multi = FALSE) {
    raw_values <- if (isTRUE(split_multi)) split_filter_values(values) else trimws(as.character(values[!is.na(values)]))
    raw_values <- raw_values[nzchar(raw_values)]
    if (length(raw_values) == 0) return(integer(0))
    sort(table(raw_values), decreasing = TRUE)
  }

  build_filter_choices <- function(values, split_multi = FALSE) {
    counts <- count_filter_values(values, split_multi = split_multi)
    if (length(counts) == 0) return(character(0))
    labels <- paste0(names(counts), " (", as.integer(counts), ")")
    stats::setNames(names(counts), labels)
  }

  kb_filter_taxonomy <- reactive({
    kb_all <- kb_all_rv()
    if (nrow(kb_all) == 0) {
      return(list(
        manufacturer = integer(0),
        technology = integer(0),
        application = integer(0),
        role = integer(0)
      ))
    }

    list(
      manufacturer = count_filter_values(kb_all$manufacturer),
      technology = count_filter_values(kb_all$technology),
      application = count_filter_values(kb_all$application, split_multi = TRUE),
      role = count_filter_values(kb_all$role, split_multi = TRUE)
    )
  })

  current_workspace_spec <- reactive({
    freq_min_mhz <- suppressWarnings(as.numeric(input$spec_freq_lo %||% NA_real_)) * 1000
    freq_max_mhz <- suppressWarnings(as.numeric(input$spec_freq_hi %||% NA_real_)) * 1000
    centre_freq <- suppressWarnings(as.numeric(input$spec_frequency %||% NA_real_))

    if (is.na(freq_min_mhz) && !is.na(centre_freq)) freq_min_mhz <- centre_freq
    if (is.na(freq_max_mhz) && !is.na(centre_freq)) freq_max_mhz <- centre_freq

    target_pout_dbm <- suppressWarnings(as.numeric(input$spec_p3db %||% input$spec_pout %||% NA_real_))
    current_app <- input$kb_filter_app
    current_app <- if (!is.null(current_app) && length(current_app) > 0) current_app[[1]] else ""

    list(
      freq_min_mhz = freq_min_mhz,
      freq_max_mhz = freq_max_mhz,
      freq_mhz = centre_freq,
      target_pout_dbm = target_pout_dbm,
      application = current_app
    )
  })

  kb_agent_state <- reactiveVal(list(
    status = "idle",
    snapshot = NULL,
    anomaly = NULL,
    requirements = character(0),
    target_vendor = "",
    refresh_plan = list(),
    workspace_spec = list()
  ))

  catalog_scan_state <- reactiveValues(
    last_log = "No vendor catalog scan yet.",
    results = list()
  )

  build_kb_agent_query <- function() {
    vendor_targets <- unique(Filter(nzchar, c(
      normalize_vendor_key(input$kb_ingest_vendor %||% ""),
      normalize_vendor_key(input$kb_batch_vendor %||% ""),
      infer_vendor_key_from_url(input$kb_ingest_product_url %||% "")
    )))
    query_bits <- c("Review KB coverage, filter suggestions, and ingestion readiness")
    if (length(vendor_targets) > 0) {
      query_bits <- c(query_bits, paste0("Target vendors: ", paste(vendor_targets, collapse = ", ")))
    }
    if (nzchar(trimws(input$kb_search_box %||% ""))) {
      query_bits <- c(query_bits, paste0("Current KB search: ", trimws(input$kb_search_box)))
    }
    paste(query_bits, collapse = ". ")
  }

  run_kb_agent_scan <- function() {
    manager <- tryCatch(get("agent_mgr", envir = .GlobalEnv), error = function(e) NULL)
    if (is.null(manager)) {
      return(list(
        status = "unavailable",
        snapshot = NULL,
        anomaly = list(severity = "high", findings = "Agent manager not available."),
        requirements = character(0),
        target_vendor = ""
      ))
    }

    agent <- tryCatch(manager$get_agent("KBAgent"), error = function(e) NULL)
    if (is.null(agent)) {
      return(list(
        status = "unavailable",
        snapshot = NULL,
        anomaly = list(severity = "high", findings = "KB agent could not be initialised."),
        requirements = character(0),
        target_vendor = ""
      ))
    }

    query <- build_kb_agent_query()
    snapshot <- tryCatch(agent$refresh_state(), error = function(e) NULL)
    anomaly <- if (!is.null(snapshot)) {
      tryCatch(
        agent$anomaly_scan(query, context = list(approved_for_apply = FALSE), snapshot = snapshot),
        error = function(e) list(severity = "high", findings = paste0("KB scan failed: ", e$message))
      )
    } else {
      list(severity = "high", findings = "KB snapshot refresh failed.")
    }
    requirements <- if (!is.null(snapshot)) {
      tryCatch(agent$recommended_requirements(snapshot, query), error = function(e) character(0))
    } else {
      character(0)
    }
    refresh_plan <- if (!is.null(snapshot) && is.function(agent$build_catalog_refresh_plan)) {
      tryCatch(agent$build_catalog_refresh_plan(current_workspace_spec(), snapshot), error = function(e) list())
    } else {
      list()
    }

    target_vendor <- unique(Filter(nzchar, c(
      normalize_vendor_key(input$kb_ingest_vendor %||% ""),
      normalize_vendor_key(input$kb_batch_vendor %||% ""),
      infer_vendor_key_from_url(input$kb_ingest_product_url %||% "")
    )))

    list(
      status = "ready",
      snapshot = snapshot,
      anomaly = anomaly,
      requirements = requirements,
      target_vendor = paste(target_vendor, collapse = ", "),
      refresh_plan = refresh_plan,
      workspace_spec = current_workspace_spec()
    )
  }

  # Reactive: currently filtered/searched dataset
  kb_filtered <- reactive({
    df <- kb_all_rv()
    if (nrow(df) == 0) return(df)

    # Search box
    q <- input$kb_search_box
    if (!is.null(q) && nzchar(trimws(q)))
      df <- kb_search(df, q)

    # Manufacturer filter
    mfr <- input$kb_filter_mfr
    if (!is.null(mfr) && length(mfr) > 0)
      df <- kb_filter(df, manufacturer = mfr)

    # Technology filter
    tech <- input$kb_filter_tech
    if (!is.null(tech) && length(tech) > 0)
      df <- kb_filter(df, technology = tech)

    # Frequency filter
    freq <- input$kb_filter_freq_mhz
    if (!is.null(freq) && !is.na(freq) && freq > 0)
      df <- kb_filter(df, freq_mhz = as.numeric(freq))

    # Minimum power filter
    pout <- input$kb_filter_pout_w
    if (!is.null(pout) && !is.na(pout) && pout > 0)
      df <- kb_filter(df, pout_min_w = as.numeric(pout))

    # Application filter
    app <- input$kb_filter_app
    if (!is.null(app) && length(app) > 0)
      df <- kb_filter(df, application = app)

    # Role filter
    role <- input$kb_filter_role
    if (!is.null(role) && length(role) > 0)
      df <- kb_filter(df, role = role)

    # Show placeholders toggle
    show_ph <- isTRUE(input$kb_show_placeholders)
    if (!show_ph)
      df <- df[!grepl("^PLACEHOLDER", df$part_number, ignore.case = TRUE), ]

    df
  })

  # Reactive: currently selected device_id from DT row click
  selected_device_id <- reactiveVal(NULL)

  # ── Filter sidebar dynamic choices ────────────────────────────────────────
  output$kb_filter_mfr_ui <- renderUI({
    makers <- build_filter_choices(kb_all_rv()$manufacturer)
    selectizeInput("kb_filter_mfr", "Manufacturer",
      choices = makers, selected = isolate(input$kb_filter_mfr), multiple = TRUE,
      options = list(placeholder = "All manufacturers", plugins = list("remove_button")))
  })

  output$kb_filter_tech_ui <- renderUI({
    techs <- build_filter_choices(kb_all_rv()$technology)
    selectizeInput("kb_filter_tech", "Technology",
      choices = techs, selected = isolate(input$kb_filter_tech), multiple = TRUE,
      options = list(placeholder = "All technologies", plugins = list("remove_button")))
  })

  output$kb_filter_app_ui <- renderUI({
    apps <- build_filter_choices(kb_all_rv()$application, split_multi = TRUE)
    selectizeInput("kb_filter_app", "Target Market / Application",
      choices = apps, selected = isolate(input$kb_filter_app), multiple = TRUE,
      options = list(placeholder = "Suggest from KB records", plugins = list("remove_button")))
  })

  output$kb_filter_role_ui <- renderUI({
    roles <- build_filter_choices(kb_all_rv()$role, split_multi = TRUE)
    selectizeInput("kb_filter_role", "Role in PA chain",
      choices = roles, selected = isolate(input$kb_filter_role), multiple = TRUE,
      options = list(placeholder = "Suggest from KB records", plugins = list("remove_button")))
  })

  output$kb_filter_suggestions_ui <- renderUI({
    taxonomy <- kb_filter_taxonomy()

    render_group <- function(title, counts) {
      if (length(counts) == 0) return(NULL)
      tags$div(
        style = "margin-bottom:8px;",
        tags$div(style = "font-size:10px; text-transform:uppercase; letter-spacing:0.08em; color:#9aa0aa; margin-bottom:4px;", title),
        tags$div(
          lapply(utils::head(seq_along(counts), 6), function(idx) {
            label <- names(counts)[idx]
            count <- as.integer(counts[[idx]])
            tags$span(
              style = paste(
                "display:inline-block; margin:0 6px 6px 0; padding:3px 8px; border-radius:999px;",
                "background:#222235; border:1px solid #34344a; color:#d9d9e2; font-size:10px;"
              ),
              paste0(label, " ", count)
            )
          })
        )
      )
    }

    tagList(
      render_group("Manufacturers", taxonomy$manufacturer),
      render_group("Technologies", taxonomy$technology),
      render_group("Target Markets", taxonomy$application),
      render_group("Roles", taxonomy$role)
    )
  })

  observe({
    req(isTRUE(input$utility_drawer_tab == "util_knowledge"))
    kb_all_rv()
    input$kb_agent_refresh
    input$kb_agent_scan_catalogs
    input$kb_agent_load_primary_catalog
    input$kb_ingest_vendor
    input$kb_batch_vendor
    input$kb_ingest_product_url
    input$kb_search_box
    kb_agent_state(run_kb_agent_scan())
  })

  observeEvent(input$kb_agent_load_primary_catalog, {
    plan <- kb_agent_state()$refresh_plan %||% list()
    if (length(plan) == 0) return()
    top <- plan[[1]]
    if (!nzchar(top$catalog_url %||% "")) return()
    updateTextInput(session, "kb_batch_vendor", value = top$vendor %||% "")
    updateTextInput(session, "kb_batch_catalog_url", value = top$catalog_url %||% "")
    if (nzchar(top$url_pattern %||% "")) {
      updateTextInput(session, "kb_batch_url_pattern", value = top$url_pattern)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$kb_agent_scan_catalogs, {
    plan <- kb_agent_state()$refresh_plan %||% list()
    if (length(plan) == 0) {
      catalog_scan_state$last_log <- "No vendor catalogs available for automatic scanning."
      return()
    }

    scan_plan <- Filter(function(item) nzchar(item$catalog_url %||% ""), utils::head(plan, 4))
    if (length(scan_plan) == 0) {
      catalog_scan_state$last_log <- "Catalog refresh plan has no usable URLs."
      return()
    }

    results <- list()
    discovered_sets <- list()
    log_lines <- c()
    withProgress(message = "Scanning vendor catalogs", value = 0, {
      for (idx in seq_along(scan_plan)) {
        item <- scan_plan[[idx]]
        args <- c(
          discovery_script,
          "--catalog-url", item$catalog_url,
          "--config", seed_catalog_path,
          "--max-links", "25"
        )
        if (nzchar(item$url_pattern %||% "")) {
          args <- c(args, "--url-pattern", item$url_pattern)
        }
        res <- run_crawl_cmd(args)
        artifact <- extract_discovery_artifact_path(res$out)
        payload <- if (!is.null(artifact) && file.exists(artifact)) {
          tryCatch(jsonlite::read_json(artifact, simplifyVector = TRUE), error = function(e) NULL)
        } else {
          NULL
        }
        total_found <- payload$total_found %||% 0
        products <- payload$products %||% list()
        results[[item$vendor]] <- list(
          vendor = item$vendor,
          catalog_url = item$catalog_url,
          url_pattern = item$url_pattern %||% "",
          total_found = total_found,
          artifact = artifact,
          ok = isTRUE(res$ok)
        )
        discovered_sets[[length(discovered_sets) + 1]] <- list(vendor = item$vendor, products = products)
        log_lines <- c(log_lines, paste0(item$vendor, ": ", total_found, " product links"))
        incProgress(1 / length(scan_plan), detail = item$vendor)
      }
    })

    catalog_scan_state$results <- results
    catalog_scan_state$last_log <- paste(log_lines, collapse = "\n")
    batch_state$discovered_products <- merge_discovered_products(discovered_sets)
    batch_state$artifact_paths <- lapply(results, function(item) item$artifact)
    batch_state$artifact_path <- if (length(batch_state$artifact_paths) > 0) batch_state$artifact_paths[[1]] else NULL

    top_success <- Filter(function(item) isTRUE(item$ok) && nzchar(item$catalog_url %||% ""), results)
    if (length(top_success) > 0) {
      first_hit <- top_success[[1]]
      updateTextInput(session, "kb_batch_vendor", value = first_hit$vendor %||% "")
      updateTextInput(session, "kb_batch_catalog_url", value = first_hit$catalog_url %||% "")
      if (nzchar(first_hit$url_pattern %||% "")) {
        updateTextInput(session, "kb_batch_url_pattern", value = first_hit$url_pattern)
      }
    }
  }, ignoreInit = TRUE)

  output$kb_agent_brief_ui <- renderUI({
    agent_state <- kb_agent_state()
    anomaly <- agent_state$anomaly %||% list(severity = "none", findings = "No KB findings.")
    snapshot <- agent_state$snapshot
    severity <- tolower(anomaly$severity %||% "none")
    severity_color <- switch(severity,
      critical = "#d9534f",
      high = "#ff7f11",
      medium = "#f0ad4e",
      none = "#2ca02c",
      "#7f8c8d"
    )

    findings <- anomaly$findings
    if (is.character(findings)) findings <- as.list(findings)
    findings <- Filter(Negate(is.null), findings)
    requirements <- utils::head(agent_state$requirements %||% character(0), 3)
    workspace_spec <- agent_state$workspace_spec %||% list()
    refresh_plan <- agent_state$refresh_plan %||% list()
    scan_summary <- catalog_scan_state$last_log %||% ""
    top_plan <- utils::head(refresh_plan, 3)
    workspace_freq <- if (!is.na(workspace_spec$freq_min_mhz %||% NA_real_) && !is.na(workspace_spec$freq_max_mhz %||% NA_real_)) {
      paste0(round(workspace_spec$freq_min_mhz / 1000, 2), "-", round(workspace_spec$freq_max_mhz / 1000, 2), " GHz")
    } else if (!is.na(workspace_spec$freq_mhz %||% NA_real_)) {
      paste0(round(workspace_spec$freq_mhz / 1000, 2), " GHz")
    } else {
      "not set"
    }
    workspace_pout <- if (!is.na(workspace_spec$target_pout_dbm %||% NA_real_)) {
      paste0(round(workspace_spec$target_pout_dbm, 1), " dBm")
    } else {
      "not set"
    }

    tags$div(
      style = paste0(
        "margin:8px 0 10px; padding:10px 12px; border-radius:8px; ",
        "border:1px solid #2a2a3a; background:linear-gradient(180deg, rgba(34,34,53,0.98), rgba(22,22,34,0.98));"
      ),
      tags$div(
        style = "display:flex; align-items:flex-start; gap:10px; justify-content:space-between;",
        tags$div(
          tags$div(style = "font-size:12px; font-weight:700; color:#f0f0f0;", icon("robot"), " KB Agent"),
          tags$div(style = "font-size:11px; color:#9aa0aa; margin-top:2px;",
            paste0(
              length(snapshot$configured_vendors %||% character(0)), " configured vendors, ",
              length(snapshot$kb_vendors %||% character(0)), " live KB folders"
            )
          )
        ),
        tags$div(style = "display:flex; align-items:center; gap:8px;",
          tags$span(
            style = paste0(
              "display:inline-block; padding:3px 8px; border-radius:999px; font-size:10px; font-weight:700; ",
              "background:", severity_color, "; color:#101014; text-transform:uppercase;"
            ),
            severity
          ),
          actionButton("kb_agent_refresh", NULL, icon = icon("sync-alt"), class = "btn-default btn-xs")
        )
      ),
      if (nzchar(agent_state$target_vendor %||% "")) {
        tags$div(style = "font-size:11px; color:#d6d6e0; margin-top:8px;", paste0("Target vendor: ", agent_state$target_vendor))
      },
      tags$div(style = "font-size:11px; color:#c9ced6; margin-top:8px;",
        paste0("Workspace target: ", workspace_freq, " | ", workspace_pout,
          if (nzchar(workspace_spec$application %||% "")) paste0(" | ", workspace_spec$application) else ""))
      ,
      if (length(findings) > 0) {
        tags$ul(
          style = "margin:8px 0 0 16px; padding:0; color:#d6d6e0; font-size:11px;",
          lapply(utils::head(findings, 2), tags$li)
        )
      },
      if (length(top_plan) > 0) {
        tags$div(
          style = "margin-top:8px; color:#d6d6e0; font-size:11px;",
          tags$div(style = "font-size:10px; text-transform:uppercase; letter-spacing:0.08em; color:#9aa0aa; margin-bottom:4px;", "Catalog priority"),
          tags$ul(
            style = "margin:0 0 0 16px; padding:0;",
            lapply(top_plan, function(item) {
              tags$li(paste0(item$display_name %||% item$vendor, " | score ", item$score %||% 0, " | ", paste(item$reasons %||% character(0), collapse = "; ")))
            })
          )
        )
      },
      tags$div(style = "display:flex; gap:8px; margin-top:8px; flex-wrap:wrap;",
        actionButton("kb_agent_load_primary_catalog", "Load Top Catalog", icon = icon("crosshairs"), class = "btn-default btn-sm"),
        actionButton("kb_agent_scan_catalogs", "Scan Vendor Catalogs", icon = icon("satellite-dish"), class = "btn-info btn-sm")
      ),
      if (nzchar(scan_summary)) {
        tags$div(style = "margin-top:8px; font-size:10px; color:#9aa0aa; white-space:pre-line;", scan_summary)
      },
      if (length(requirements) > 0) {
        tags$div(
          style = "margin-top:8px; font-size:10px; color:#9aa0aa;",
          paste("Next checks:", paste(requirements, collapse = " | "))
        )
      }
    )
  })

  output$kb_ingest_technology_ui <- renderUI({
    selectInput("kb_ingest_technology", "Technology",
      choices  = c("Auto-detect" = "", "LDMOS", "GaN-SiC", "GaN-Si", "GaAs", "SiC", "Other"),
      selected = ingest_state$last_technology,
      selectize = FALSE)
  })

  # ── Main device table ──────────────────────────────────────────────────────
  output$kb_device_table <- DT::renderDT({
    df <- kb_filtered()
    if (nrow(df) == 0) {
      return(DT::datatable(data.frame(Message = "No devices match the current filters."),
        options = list(dom = "t"), rownames = FALSE,
        class = "compact cell-border"))
    }

    disp <- kb_display_table(df)
    # Hide the device_id column (last col) — used for row selection lookup
    hidden_col <- which(names(disp) == "device_id") - 1  # 0-indexed for DT

    DT::datatable(
      disp,
      selection  = "single",
      rownames   = FALSE,
      class      = "compact cell-border hover kb-device-table",
      options    = list(
        dom        = "ltip",
        autoWidth  = FALSE,
        pageLength = 25,
        lengthMenu = list(c(8, 12, 15, 25, 50), c(8, 12, 15, 25, 50)),
        scrollY    = "360px",
        scrollCollapse = TRUE,
        scrollX    = TRUE,
        columnDefs = list(
          list(targets = hidden_col, visible = FALSE),
          list(targets = which(names(disp) == "Target Market/Application") - 1,
               className = "kb-wrap-col"),
          list(targets = which(names(disp) == "Package") - 1,
               className = "kb-wrap-col"),
          # Confidence column coloring via CSS class
          list(targets = which(names(disp) == "Confidence") - 1,
               className = "dt-center"),
          list(targets = which(names(disp) == "Status") - 1,
               className = "dt-center")
        ),
        language   = list(emptyTable = "No devices match filters")
      )
    ) %>%
      DT::formatStyle(
        "Confidence",
        color            = DT::styleEqual(
          c("high", "medium", "low"),
          c("#2ca02c", "#ff7f11", "#d62728")
        ),
        fontWeight       = "600"
      ) %>%
      DT::formatStyle(
        "Ropt (Ω)",
        color = DT::styleEqual("—", "#555", default = "#ff7f11"),
        fontFamily = "monospace"
      )
  }, server = TRUE)

  # ── Row selection → update device detail ──────────────────────────────────
  observeEvent(input$kb_device_table_rows_selected, {
    row_idx <- input$kb_device_table_rows_selected
    if (is.null(row_idx) || length(row_idx) == 0) {
      selected_device_id(NULL)
      return()
    }
    df      <- kb_filtered()
    disp    <- kb_display_table(df)
    dev_id  <- disp[row_idx, "device_id"]
    selected_device_id(dev_id)
  })

  # ── Device detail panel ────────────────────────────────────────────────────
  output$kb_device_detail <- renderUI({
    dev_id <- selected_device_id()
    if (is.null(dev_id) || !nzchar(dev_id)) {
      return(div(style = "padding:24px; text-align:center; color:#666;",
        icon("hand-pointer"),
        p("Click a row in the table above to see device details.")
      ))
    }
    raw <- tryCatch(
      kb_get_raw_device(dev_id, kb_root = "../data/kb"),
      error = function(e) NULL
    )
    kb_device_card(raw)
  })

  output$kb_protected_editor_ui <- renderUI({
    disabled <- !isTRUE(input$kb_protected_mode)
    div(
      style = "margin-top:8px; border:1px solid #2a2a3a; border-radius:4px; padding:8px; background:#161622;",
      fluidRow(
        column(4, textInput("kb_edit_device_id", "Device ID", value = "", placeholder = "Load selected device", width = "100%")),
        column(4, textInput("kb_edit_part_number", "Part Number", value = "", width = "100%")),
        column(4, textInput("kb_edit_manufacturer", "Manufacturer", value = "", width = "100%"))
      ),
      fluidRow(
        column(3, selectInput("kb_edit_technology", "Technology",
          choices = c("LDMOS", "GaN-SiC", "GaN-Si", "GaAs", "SiC", "Other"),
          selected = "LDMOS", width = "100%")),
        column(3, selectInput("kb_edit_status", "Status",
          choices = c("active", "NRND", "EOL"), selected = "active", width = "100%")),
        column(3, selectInput("kb_edit_confidence", "Confidence",
          choices = c("high", "medium", "low"), selected = "medium", width = "100%")),
        column(3, textInput("kb_edit_datasheet_url", "Datasheet URL", value = "", width = "100%"))
      ),
      fluidRow(
        column(6, numericInput("kb_edit_freq_min_mhz", "Freq min (MHz)", value = NA, min = 0, step = 0.1, width = "100%")),
        column(6, numericInput("kb_edit_freq_max_mhz", "Freq max (MHz)", value = NA, min = 0, step = 0.1, width = "100%"))
      ),
      textAreaInput("kb_edit_notes", "Notes", value = "", rows = 2, width = "100%"),
      if (disabled)
        div(style = "font-size:11px; color:#d9a441;", icon("lock"), " Enable protected mode to edit or delete.")
    )
  })

  # ── Smith Chart integration — single representative Ropt ──────────────────
  observeEvent(input$kb_send_to_smith, {
    dev_id <- selected_device_id()
    req(dev_id)
    raw <- kb_get_raw_device(dev_id, kb_root = "../data/kb")
    req(raw)

    r_opt <- raw$ropt_ohm
    x_opt <- raw$xopt_ohm
    req(!is.null(r_opt) && !is.na(r_opt))

    updateNumericInput(session, "smith_z_real",  value = as.numeric(r_opt))
    updateNumericInput(session, "smith_z_imag",  value = as.numeric(x_opt %||% 0))
    updateTextInput(  session, "smith_label",    value = raw$part_number %||% dev_id)

    shinyjs::runjs('utilityDrawerOpen("rf_tools")')

    showNotification(
      paste0("Ropt for ", raw$part_number, " loaded into Smith Chart."),
      type = "message", duration = 4
    )
  })

  # ── Smith Chart integration — LP table row (multi-frequency) ──────────────
  # Fired by JavaScript onclick in .render_lp_table() via Shiny.setInputValue
  observeEvent(input$kb_lp_row_click, {
    payload <- input$kb_lp_row_click
    req(payload)

    zl_r <- as.numeric(payload$zl_r)
    zl_x <- as.numeric(payload$zl_x)
    freq  <- payload$freq
    cond  <- payload$condition %||% ""

    if (is.na(zl_r)) return()

    # Get current device part number for the label
    dev_id <- selected_device_id()
    label_str <- if (!is.null(dev_id) && nzchar(dev_id)) {
      raw <- tryCatch(kb_get_raw_device(dev_id, kb_root = "../data/kb"), error = function(e) NULL)
      pn  <- if (!is.null(raw)) raw$part_number %||% dev_id else dev_id
      paste0(pn, " @ ", freq, "MHz (", cond, ")")
    } else {
      paste0("ZL @ ", freq, "MHz")
    }

    updateNumericInput(session, "smith_z_real",  value = zl_r)
    updateNumericInput(session, "smith_z_imag",  value = zl_x)
    updateTextInput(  session, "smith_label",    value = label_str)
    shinyjs::runjs('utilityDrawerOpen("rf_tools")')

    showNotification(
      paste0("ZL = ", zl_r, if (zl_x >= 0) "+" else "", zl_x,
             "j Ω at ", freq, " MHz loaded into Smith Chart."),
      type = "message", duration = 4
    )
  })

  # ── Lineup Canvas integration — write KB device to device_portfolio/ ──────
  observeEvent(input$kb_copy_to_lineup, {
    dev_id <- selected_device_id()
    req(dev_id)
    raw <- kb_get_raw_device(dev_id, kb_root = "../data/kb")
    req(raw)

    pn <- raw$part_number %||% dev_id

    # Convert Pout: W → dBm (10·log10(W) + 30)
    pout_w   <- suppressWarnings(as.numeric(raw$pout_w_cw %||% raw$pout_w_pulse %||% NA))
    pout_dbm <- if (!is.null(pout_w) && !is.na(pout_w) && pout_w > 0) {
      round(10 * log10(pout_w * 1000), 1)
    } else {
      suppressWarnings(as.numeric(raw$pout_dbm %||% 43))
    }

    # Convert freq: MHz → GHz (use test freq, else midpoint of band)
    freq_mhz <- suppressWarnings(as.numeric(
      raw$freq_test_mhz %||%
      ((as.numeric(raw$freq_min_mhz %||% 2000) + as.numeric(raw$freq_max_mhz %||% 3000)) / 2)
    ))
    freq_ghz <- round(freq_mhz / 1000, 3)

    # Map KB technology string to guardrails key
    tech_key <- switch(raw$technology %||% "",
      "LDMOS"   = "LDMOS",
      "GaN-SiC" = "GaN_SiC",
      "GaN-Si"  = "GaN_Si",
      "GaAs"    = "GaAs_pHEMT",
      raw$technology %||% "GaN_SiC"
    )

    device <- list(
      id                    = paste0("kb_", gsub("[^a-zA-Z0-9]", "_", pn), "_",
                                     format(Sys.time(), "%Y%m%d%H%M%S")),
      label                 = pn,
      notes                 = paste0("[KB] ", raw$manufacturer %||% "", " — ",
                                     raw$knowledge_confidence %||% "medium", " confidence"),
      technology            = tech_key,
      tech_label            = trimws(paste(raw$technology %||% "", raw$generation %||% "")),
      freq_ghz              = freq_ghz,
      gain_db               = suppressWarnings(as.numeric(raw$gain_db %||% 15)),
      pae_pct               = suppressWarnings(as.numeric(raw$drain_eff_pct %||% raw$pae_pct %||% 30)),
      pout_dbm              = pout_dbm,
      vdd                   = suppressWarnings(as.numeric(raw$vdd_v %||% 28)),
      p1db_dbm              = pout_dbm - 2,
      pout_density_w_per_mm = 0,
      validation_status     = "ok",
      source                = "knowledge_base",
      kb_confidence         = raw$knowledge_confidence %||% "medium",
      manufacturer          = raw$manufacturer %||% "",
      saved_at              = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      canvas_component = list(
        type      = "transistor",
        label     = pn,
        technology = tech_key,
        gain      = suppressWarnings(as.numeric(raw$gain_db %||% 15)),
        pout      = pout_dbm,
        p1db      = pout_dbm - 2,
        pae       = suppressWarnings(as.numeric(raw$drain_eff_pct %||% raw$pae_pct %||% 30)),
        vdd       = suppressWarnings(as.numeric(raw$vdd_v %||% 28)),
        freq      = freq_ghz,
        biasClass = "AB"
      )
    )

    portfolio_dir <- "device_portfolio"
    if (!dir.exists(portfolio_dir)) dir.create(portfolio_dir, recursive = TRUE)
    jsonlite::write_json(device,
      file.path(portfolio_dir, paste0(device$id, ".json")),
      pretty = TRUE, auto_unbox = TRUE)

    # Bump shared signal → server_device_lib's merged-push observer sends the
    # full harmonised palette (portfolio + KB catalogue) to the canvas
    if (!is.null(state$rv_lib_refresh))
      isolate(state$rv_lib_refresh(state$rv_lib_refresh() + 1L))

    # Also refresh the device-lib table
    if (!is.null(state$rv_portfolio_refresh))
      state$rv_portfolio_refresh(state$rv_portfolio_refresh() + 1)

    showNotification(
      paste0(pn, " permanently saved to portfolio — visible in PA Lineup canvas palette and 3.3 Device Library."),
      type = "message", duration = 5
    )
  })

  observeEvent(input$kb_protected_load, {
    dev_id <- selected_device_id()
    if (is.null(dev_id) || !nzchar(dev_id)) {
      protected_state$status <- "No selected record in table."
      showNotification("Select a device row first.", type = "warning", duration = 4)
      return()
    }

    raw <- tryCatch(kb_get_raw_device(dev_id, kb_root = "../data/kb"), error = function(e) NULL)
    if (is.null(raw)) {
      protected_state$status <- paste0("Failed to load record: ", dev_id)
      showNotification("Failed to load selected record.", type = "error", duration = 4)
      return()
    }

    protected_state$loaded_device_id <- dev_id
    updateTextInput(session, "kb_edit_device_id", value = raw$device_id %||% "")
    updateTextInput(session, "kb_edit_part_number", value = raw$part_number %||% "")
    updateTextInput(session, "kb_edit_manufacturer", value = raw$manufacturer %||% "")
    updateSelectInput(session, "kb_edit_technology", selected = raw$technology %||% "Other")
    updateSelectInput(session, "kb_edit_status", selected = raw$status %||% "active")
    updateSelectInput(session, "kb_edit_confidence", selected = raw$knowledge_confidence %||% "medium")
    updateTextInput(session, "kb_edit_datasheet_url", value = raw$datasheet_url %||% "")
    updateNumericInput(session, "kb_edit_freq_min_mhz", value = suppressWarnings(as.numeric(raw$freq_min_mhz %||% NA)))
    updateNumericInput(session, "kb_edit_freq_max_mhz", value = suppressWarnings(as.numeric(raw$freq_max_mhz %||% NA)))
    updateTextAreaInput(session, "kb_edit_notes", value = raw$notes %||% "")

    protected_state$status <- paste0("Loaded: ", raw$device_id %||% dev_id)
    showNotification("Record loaded into protected editor.", type = "message", duration = 3)
  })

  observeEvent(input$kb_protected_save, {
    if (!isTRUE(input$kb_protected_mode)) {
      protected_state$status <- "Blocked: protected mode is disabled."
      showNotification("Enable protected mode first.", type = "error", duration = 4)
      return()
    }
    if (!identical(trimws(input$kb_protected_confirm %||% ""), "UPDATE")) {
      protected_state$status <- "Blocked: confirm token must be UPDATE for save."
      showNotification("Type UPDATE in confirm token to save changes.", type = "error", duration = 5)
      return()
    }

    dev_id <- trimws(input$kb_edit_device_id %||% "")
    if (!nzchar(dev_id)) {
      protected_state$status <- "Blocked: Device ID is required."
      showNotification("Load a record first.", type = "error", duration = 4)
      return()
    }

    vfile <- vendor_devices_file(dev_id)
    if (is.na(vfile) || !file.exists(vfile)) {
      protected_state$status <- paste0("Blocked: vendor file not found for ", dev_id)
      showNotification("Vendor file not found for selected record.", type = "error", duration = 5)
      return()
    }

    records <- load_vendor_devices(vfile)
    idx <- get_record_index(records, dev_id)
    if (length(idx) != 1) {
      protected_state$status <- paste0("Blocked: record not found in vendor file for ", dev_id)
      showNotification("Record not found in vendor file.", type = "error", duration = 5)
      return()
    }

    rec <- records[[idx]]
    rec$part_number <- trimws(input$kb_edit_part_number %||% rec$part_number %||% "")
    rec$manufacturer <- trimws(input$kb_edit_manufacturer %||% rec$manufacturer %||% "")
    rec$technology <- trimws(input$kb_edit_technology %||% rec$technology %||% "Other")
    rec$status <- trimws(input$kb_edit_status %||% rec$status %||% "active")
    rec$knowledge_confidence <- trimws(input$kb_edit_confidence %||% rec$knowledge_confidence %||% "medium")
    rec$datasheet_url <- trimws(input$kb_edit_datasheet_url %||% rec$datasheet_url %||% "")
    rec$notes <- trimws(input$kb_edit_notes %||% rec$notes %||% "")

    fmin <- suppressWarnings(as.numeric(input$kb_edit_freq_min_mhz %||% NA))
    fmax <- suppressWarnings(as.numeric(input$kb_edit_freq_max_mhz %||% NA))
    if (!is.na(fmin)) rec$freq_min_mhz <- fmin
    if (!is.na(fmax)) rec$freq_max_mhz <- fmax

    records[[idx]] <- rec
    save_vendor_devices(vfile, records)
    reload_kb_all()
    updateTextInput(session, "kb_protected_confirm", value = "")

    protected_state$status <- paste0("Updated: ", dev_id)
    showNotification("KB record updated in protected mode.", type = "message", duration = 4)
  })

  observeEvent(input$kb_protected_delete, {
    if (!isTRUE(input$kb_protected_mode)) {
      protected_state$status <- "Blocked: protected mode is disabled."
      showNotification("Enable protected mode first.", type = "error", duration = 4)
      return()
    }
    if (!identical(trimws(input$kb_protected_confirm %||% ""), "DELETE")) {
      protected_state$status <- "Blocked: confirm token must be DELETE for removal."
      showNotification("Type DELETE in confirm token to remove record.", type = "error", duration = 5)
      return()
    }

    dev_id <- trimws(input$kb_edit_device_id %||% "")
    if (!nzchar(dev_id)) {
      protected_state$status <- "Blocked: Device ID is required."
      showNotification("Load a record first.", type = "error", duration = 4)
      return()
    }

    vfile <- vendor_devices_file(dev_id)
    if (is.na(vfile) || !file.exists(vfile)) {
      protected_state$status <- paste0("Blocked: vendor file not found for ", dev_id)
      showNotification("Vendor file not found for selected record.", type = "error", duration = 5)
      return()
    }

    records <- load_vendor_devices(vfile)
    idx <- get_record_index(records, dev_id)
    if (length(idx) != 1) {
      protected_state$status <- paste0("Blocked: record not found in vendor file for ", dev_id)
      showNotification("Record not found in vendor file.", type = "error", duration = 5)
      return()
    }

    records <- records[-idx]
    save_vendor_devices(vfile, records)
    reload_kb_all()
    updateTextInput(session, "kb_protected_confirm", value = "")
    updateTextInput(session, "kb_edit_device_id", value = "")

    protected_state$status <- paste0("Deleted: ", dev_id)
    showNotification("KB record deleted in protected mode.", type = "warning", duration = 5)
  })

  output$kb_protected_status <- renderText({
    protected_state$status %||% "Protected mode disabled."
  })

  # ── Drawer quick-search output ─────────────────────────────────────────────
  output$kb_drawer_results <- renderUI({
    q <- input$drawer_kb_search
    if (is.null(q) || !nzchar(trimws(q)))
      return(p(style = "color:#888; font-size:12px;",
               "Type a part number or keyword and press Search."))

    hits <- kb_search(kb_all_rv(), q)
    hits <- hits[!grepl("^PLACEHOLDER", hits$part_number, ignore.case = TRUE), ]

    if (nrow(hits) == 0)
      return(p(style = "color:#888; font-size:12px;", "No devices found."))

    # Show top 5 hits
    n    <- min(nrow(hits), 5)
    hits <- hits[seq_len(n), ]

    tagList(
      p(style = "color:#888; font-size:11px; margin:4px 0 8px;",
        nrow(hits), " result(s) — open full view for more."),
      lapply(seq_len(n), function(i) {
        d    <- hits[i, ]
        conf <- d$knowledge_confidence %||% "low"
        ccol <- switch(conf, high="#2ca02c", medium="#ff7f11", low="#d62728", "#888")
        div(class = "drawer-link-row",
          style = "flex-direction:column; align-items:flex-start; padding:6px 0;",
          div(style = "display:flex; align-items:center; gap:6px; width:100%;",
            div(style = paste0("width:6px; height:6px; border-radius:50%;",
                               " background:", ccol, "; flex-shrink:0;")),
            tags$strong(style = "color:#ddd; font-size:12px;",
                        d$part_number %||% "?"),
            div(style = "margin-left:auto; color:#888; font-size:10px;",
                d$technology %||% "")
          ),
          div(style = "color:#888; font-size:11px; margin-left:12px;",
            d$freq_min_mhz %||% "?", "–", d$freq_max_mhz %||% "?", " MHz  \u00b7  ",
            ifelse(!is.na(d$pout_w_cw), paste0(d$pout_w_cw, " W CW"),
                   ifelse(!is.na(d$pout_w_pulse), paste0(d$pout_w_pulse, " W pulse"), ""))
          )
        )
      })
    )
  })

  # Trigger search from drawer when button clicked
  observeEvent(input$drawer_kb_go, {
    req(input$drawer_kb_search)
    # Output is reactive on input$drawer_kb_search — just update reactive chain
  })

  observeEvent(input$kb_clear_filters, {
    updateTextInput(session, "kb_search_box", value = "")
    updateSelectizeInput(session, "kb_filter_mfr", selected = character(0))
    updateSelectizeInput(session, "kb_filter_tech", selected = character(0))
    updateNumericInput(session, "kb_filter_freq_mhz", value = NA)
    updateNumericInput(session, "kb_filter_pout_w", value = NA)
    updateSelectizeInput(session, "kb_filter_app", selected = character(0))
    updateSelectizeInput(session, "kb_filter_role", selected = character(0))
    updateCheckboxInput(session, "kb_show_placeholders", value = FALSE)
  })

  # ── Technology field: track last selection & restore across drawer tab switches ─
  observeEvent(input$kb_ingest_technology, {
    ingest_state$last_technology <- input$kb_ingest_technology
  }, ignoreInit = TRUE)

  observeEvent(input$utility_drawer_tab, {
    if (isTRUE(input$utility_drawer_tab == "util_knowledge")) {
      shinyjs::delay(150, {
        tech <- ingest_state$last_technology
        if (!is.null(tech) && nzchar(tech))
          updateSelectInput(session, "kb_ingest_technology", selected = tech)
        if (!nzchar(trimws(input$kb_ingest_vendor %||% "")))
          updateTextInput(session, "kb_ingest_vendor", value = "ampleon")
        if (!nzchar(trimws(input$kb_batch_vendor %||% "")))
          updateTextInput(session, "kb_batch_vendor", value = "ampleon")
      })
    }
  }, ignoreInit = TRUE)

  observeEvent(input$kb_ingest_fetch_preview, {
    product_url <- normalize_external_url(input$kb_ingest_product_url)
    vendor_key <- normalize_vendor_key(input$kb_ingest_vendor)
    if (!nzchar(vendor_key)) vendor_key <- infer_vendor_key_from_url(product_url)

    part_number <- trimws(input$kb_ingest_part_number %||% "")
    if (!nzchar(part_number)) part_number <- infer_part_number_from_url(product_url)

    manufacturer <- trimws(input$kb_ingest_manufacturer %||% "")
    if (!nzchar(manufacturer)) manufacturer <- infer_manufacturer_from_vendor(vendor_key)

    technology <- trimws(input$kb_ingest_technology %||% "")
    if (identical(technology, "Auto-detect")) technology <- ""

    freq_min <- suppressWarnings(as.numeric(input$kb_ingest_freq_min_mhz %||% NA_real_))
    freq_max <- suppressWarnings(as.numeric(input$kb_ingest_freq_max_mhz %||% NA_real_))
    selector_title <- trimws(input$kb_ingest_selector_title %||% "")
    selector_datasheet <- normalize_external_url(input$kb_ingest_selector_datasheet)
    selector_summary <- trimws(input$kb_ingest_selector_summary %||% "")

    updateTextInput(session, "kb_ingest_vendor", value = vendor_key)
    updateTextInput(session, "kb_ingest_part_number", value = part_number)
    updateTextInput(session, "kb_ingest_product_url", value = product_url)
    updateTextInput(session, "kb_ingest_manufacturer", value = manufacturer)
    if (nzchar(selector_datasheet)) updateTextInput(session, "kb_ingest_selector_datasheet", value = selector_datasheet)

    form_errors <- validate_ingest_form(vendor_key, part_number, product_url, manufacturer, freq_min, freq_max)
    if (length(form_errors) > 0) {
      ingest_state$last_log <- paste(c("Form validation failed:", paste0(" - ", form_errors)), collapse = "\n")
      showNotification(form_errors[[1]], type = "error", duration = 6)
      return()
    }

    withProgress(message = "Fetching preview", detail = paste0(vendor_key, " / ", part_number), value = 0.2, {
      upsert_seed_product(
        vendor_key, part_number, product_url, manufacturer, technology, freq_min, freq_max,
        title_selector = selector_title,
        datasheet_selector = selector_datasheet,
        summary_selector = selector_summary
      )
      incProgress(0.3)

      res <- run_crawl_cmd(c(pipeline_script, "--vendor", vendor_key, "--max-products", "1"))
      artifact <- extract_artifact_path(res$out)
      ingest_state$last_vendor <- vendor_key
      ingest_state$last_artifact <- artifact
      ingest_state$last_log <- paste(res$out, collapse = "\n")
      incProgress(1)

      if (!res$ok) {
        showNotification("Fetch Preview failed. Check log output.", type = "error", duration = 6)
      } else {
        showNotification("Fetch Preview completed. Run Validate next.", type = "message", duration = 4)
      }
    })
  })

  observeEvent(input$kb_ingest_validate, {
    withProgress(message = "Validating artifacts", value = 0.5, {
      vendor_key <- normalize_vendor_key(input$kb_ingest_vendor)
      args <- if (nzchar(vendor_key)) c(validator_script, "--vendor", vendor_key) else c(validator_script)
      res <- run_crawl_cmd(args)
      ingest_state$last_log <- paste(res$out, collapse = "\n")
      incProgress(1)
      if (!res$ok) {
        showNotification("Validation failed. Review log details.", type = "warning", duration = 6)
      } else {
        showNotification("Validation passed.", type = "message", duration = 4)
      }
    })
  })

  observeEvent(input$kb_ingest_apply, {
    vendor_key <- normalize_vendor_key(input$kb_ingest_vendor)
    if (!nzchar(vendor_key)) {
      showNotification("Vendor key is required for Apply.", type = "error", duration = 5)
      return()
    }

    withProgress(message = "Applying to KB", detail = paste0("Vendor: ", vendor_key), value = 0.5, {
      res <- run_crawl_cmd(c(pipeline_script, "--vendor", vendor_key, "--max-products", "1", "--apply"))
      ingest_state$last_log <- paste(res$out, collapse = "\n")
      incProgress(1)
      if (!res$ok) {
        showNotification("Apply failed or was blocked by validation.", type = "error", duration = 6)
      } else {
        reload_kb_all()
        if (!is.null(state$rv_portfolio_refresh))
          state$rv_portfolio_refresh(state$rv_portfolio_refresh() + 1)
        showNotification("Apply completed and KB reloaded.", type = "message", duration = 5)
      }
    })
  })

  output$kb_ingest_status <- renderText({
    ingest_state$last_log %||% "Ready. Fill fields and click Fetch Preview."
  })

  output$kb_ingest_artifact_summary <- renderUI({
    render_artifact_summary(ingest_state$last_artifact)
  })

  # ── Batch Catalog Import ───────────────────────────────────────────────────
  discovery_script <- file.path(crawl_root, "discover_catalog_links.py")

  batch_state <- reactiveValues(
    discovered_products = NULL,   # list of list(part_number, product_url)
    last_log = "Fill Vendor key + Catalog URL, then click Discover Products.",
    artifact_path = NULL,
    artifact_paths = list()
  )

  merge_discovered_products <- function(product_sets) {
    merged <- list()
    seen <- character(0)
    for (item in product_sets) {
      products <- item$products %||% list()
      vendor_key <- normalize_vendor_key(item$vendor %||% "")
      for (prod in products) {
        product_url <- prod$product_url %||% ""
        key <- paste(vendor_key, product_url, sep = "::")
        if (!nzchar(product_url) || key %in% seen) next
        prod$vendor <- vendor_key
        merged[[length(merged) + 1]] <- prod
        seen <- c(seen, key)
      }
    }
    merged
  }

  group_selected_batch_products <- function(products) {
    if (length(products) == 0) return(list())
    vendor_keys <- vapply(products, function(item) normalize_vendor_key(item$vendor %||% input$kb_batch_vendor %||% ""), character(1))
    split(products, vendor_keys)
  }

  observeEvent(input$kb_batch_discover, {
    vendor_key <- normalize_vendor_key(input$kb_batch_vendor)
    catalog_url <- trimws(input$kb_batch_catalog_url %||% "")
    url_pattern <- trimws(input$kb_batch_url_pattern %||% "")
    max_links   <- suppressWarnings(as.integer(input$kb_batch_max_links %||% 50L))

    if (!nzchar(vendor_key)) {
      batch_state$last_log <- "Error: Vendor key is required."
      showNotification("Vendor key is required for batch discovery.", type = "error", duration = 5)
      return()
    }
    if (!nzchar(catalog_url) || !grepl("^https?://", catalog_url, ignore.case = TRUE)) {
      batch_state$last_log <- "Error: Valid Catalog URL (https://...) is required."
      showNotification("Valid catalog URL is required.", type = "error", duration = 5)
      return()
    }
    if (is.na(max_links) || max_links < 1) max_links <- 50L

    withProgress(message = "Discovering products", detail = catalog_url, value = 0.3, {
      disc_args <- c(discovery_script,
        "--catalog-url", catalog_url,
        "--config",      seed_catalog_path,
        "--max-links",   as.character(max_links))
      if (nzchar(url_pattern))
        disc_args <- c(disc_args, "--url-pattern", url_pattern)

      res <- run_crawl_cmd(disc_args)
      incProgress(0.8)

      batch_state$last_log <- paste(res$out, collapse = "\n")
      batch_state$discovered_products <- NULL

      if (!res$ok) {
        showNotification("Discovery failed — check log.", type = "error", duration = 6)
        return()
      }

      # Parse the discovery artifact from the output log
      artifact_line <- grep("Wrote discovery artifact:", res$out, value = TRUE)
      if (length(artifact_line) == 0) {
        batch_state$last_log <- paste(c("Discovery returned ok but no artifact found:", res$out), collapse = "\n")
        showNotification("No discovery artifact found.", type = "warning", duration = 5)
        return()
      }

      artifact_file <- sub("^.*Wrote discovery artifact:\\s*", "", tail(artifact_line, 1))
      batch_state$artifact_path <- artifact_file

      if (!file.exists(artifact_file)) {
        batch_state$last_log <- paste0("Artifact file not found: ", artifact_file)
        return()
      }

      payload <- tryCatch(jsonlite::read_json(artifact_file, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(payload) || is.null(payload$products)) {
        batch_state$last_log <- "Could not parse discovery artifact."
        return()
      }

      products <- payload$products
      for (i in seq_along(products)) {
        products[[i]]$vendor <- vendor_key
      }
      batch_state$discovered_products <- products
      batch_state$artifact_paths <- stats::setNames(list(artifact_file), vendor_key)

      n <- length(products)
      batch_state$last_log <- paste(c(
        paste0("[OK] Discovered ", n, " product link(s) from ", catalog_url),
        paste0("     Select items below, then click Batch Fetch Preview."),
        res$out
      ), collapse = "\n")

      incProgress(1)
      showNotification(paste0("Discovered ", n, " product links."), type = "message", duration = 4)
    })
  })

  output$kb_batch_product_list_ui <- renderUI({
    prods <- batch_state$discovered_products
    if (is.null(prods) || length(prods) == 0) return(NULL)

    checkboxes <- lapply(seq_along(prods), function(i) {
      p <- prods[[i]]
      chk_id <- paste0("kb_batch_sel_", i)
      div(style = "margin-bottom:3px;",
        checkboxInput(chk_id, label = div(
          tags$strong(style = "color:#ddd; font-size:11px;",
            p$part_number %||% paste0("product_", i)),
          if (nzchar(p$vendor %||% "")) {
            div(style = "font-size:10px; color:#ffb36a;", paste0("Vendor: ", p$vendor))
          },
          div(style = "font-size:10px; color:#888; word-break:break-all;",
            p$product_url %||% "")
        ), value = TRUE)
      )
    })

    div(style = "margin-top:8px; max-height:200px; overflow-y:auto; border:1px solid #2a2a3a; border-radius:4px; padding:8px; background:#161622;",
      div(style = "display:flex; gap:8px; margin-bottom:6px;",
        actionButton("kb_batch_select_all",   "All",  class = "btn-default btn-xs"),
        actionButton("kb_batch_deselect_all", "None", class = "btn-default btn-xs"),
        tags$span(style = "color:#888; font-size:11px; align-self:center;",
          paste0(length(prods), " products queued"))
      ),
      tagList(checkboxes)
    )
  })

  output$kb_batch_action_buttons_ui <- renderUI({
    if (is.null(batch_state$discovered_products) || length(batch_state$discovered_products) == 0)
      return(NULL)
    div(style = "margin-top:6px;",
      actionButton("kb_batch_fetch_preview", "Batch Fetch Preview",
        icon = icon("download"), class = "btn-primary btn-block btn-sm"),
      actionButton("kb_batch_validate", "Batch Validate",
        icon = icon("check-circle"), class = "btn-info btn-block btn-sm"),
      actionButton("kb_batch_apply", "Batch Apply to KB",
        icon = icon("save"), class = "btn-success btn-block btn-sm"),
      tags$small(style = "display:block; color:#8b8b96; margin-top:4px;",
        "Flow: Discover or Scan \u2192 Select links \u2192 Fetch Preview \u2192 Validate \u2192 Apply")
    )
  })

  # Helper: get selected product indices
  get_selected_batch_products <- function() {
    prods <- batch_state$discovered_products
    if (is.null(prods) || length(prods) == 0) return(list())
    selected <- Filter(function(i) {
      isTRUE(input[[paste0("kb_batch_sel_", i)]])
    }, seq_along(prods))
    prods[selected]
  }

  # Select / deselect all
  observeEvent(input$kb_batch_select_all, {
    prods <- batch_state$discovered_products
    if (is.null(prods)) return()
    for (i in seq_along(prods))
      updateCheckboxInput(session, paste0("kb_batch_sel_", i), value = TRUE)
  })

  observeEvent(input$kb_batch_deselect_all, {
    prods <- batch_state$discovered_products
    if (is.null(prods)) return()
    for (i in seq_along(prods))
      updateCheckboxInput(session, paste0("kb_batch_sel_", i), value = FALSE)
  })

  # Batch Fetch Preview: upsert selected products into seed catalog, then run crawl
  observeEvent(input$kb_batch_fetch_preview, {
    sel_prods <- get_selected_batch_products()
    if (length(sel_prods) == 0) {
      batch_state$last_log <- "No products selected. Check at least one item."
      showNotification("No products selected.", type = "warning", duration = 4)
      return()
    }

    grouped <- group_selected_batch_products(sel_prods)
    if (length(grouped) == 0) {
      batch_state$last_log <- "Error: no vendor could be inferred from selected products."
      showNotification("Selected links are missing vendor context.", type = "error", duration = 4)
      return()
    }

    logs <- c()
    artifacts <- list()
    vendor_names <- names(grouped)
    withProgress(message = "Batch Fetch Preview", detail = paste0(length(sel_prods), " selected products"), value = 0.05, {
      for (idx in seq_along(vendor_names)) {
        vendor_key <- vendor_names[[idx]]
        vendor_products <- grouped[[vendor_key]]
        for (p in vendor_products) {
          tryCatch(
            upsert_seed_product(vendor_key, p$part_number %||% "unknown", p$product_url %||% "",
                                infer_manufacturer_from_vendor(vendor_key), "Other", NA_real_, NA_real_),
            error = function(e) message("[Batch] upsert_seed_product error: ", e$message)
          )
        }

        res <- run_crawl_cmd(c(pipeline_script, "--vendor", vendor_key,
                                "--max-products", as.character(length(vendor_products))))
        artifacts[[vendor_key]] <- extract_artifact_path(res$out)
        logs <- c(logs, paste0("[", vendor_key, "]"), res$out)
        incProgress(1 / length(vendor_names), detail = vendor_key)
      }

      batch_state$artifact_paths <- artifacts
      batch_state$artifact_path <- if (length(artifacts) > 0) artifacts[[1]] else NULL
      batch_state$last_log <- paste(logs, collapse = "\n")

      if (length(Filter(Negate(is.null), artifacts)) == 0) {
        showNotification("Batch Fetch Preview failed. Check log.", type = "error", duration = 6)
      } else {
        showNotification("Batch Fetch Preview done. Run Batch Validate next.", type = "message", duration = 4)
      }
    })
  })

  # Batch Validate
  observeEvent(input$kb_batch_validate, {
    grouped <- group_selected_batch_products(get_selected_batch_products())
    vendor_names <- names(grouped)
    if (length(vendor_names) == 0) vendor_names <- names(batch_state$artifact_paths %||% list())
    if (length(vendor_names) == 0) {
      batch_state$last_log <- "No vendor artifacts available to validate."
      return()
    }

    logs <- c()
    withProgress(message = "Validating batch artifacts", value = 0.05, {
      for (idx in seq_along(vendor_names)) {
        vendor_key <- vendor_names[[idx]]
        res <- run_crawl_cmd(c(validator_script, "--vendor", vendor_key))
        logs <- c(logs, paste0("[", vendor_key, "]"), res$out)
        incProgress(1 / length(vendor_names), detail = vendor_key)
      }
      batch_state$last_log <- paste(logs, collapse = "\n")
      showNotification("Batch Validation completed. Review log for vendor-level results.", type = "message", duration = 4)
    })
  })

  # Batch Apply
  observeEvent(input$kb_batch_apply, {
    sel_prods <- get_selected_batch_products()
    if (length(sel_prods) == 0) {
      batch_state$last_log <- "No products selected."
      showNotification("No products selected.", type = "warning", duration = 4)
      return()
    }

    grouped <- group_selected_batch_products(sel_prods)
    if (length(grouped) == 0) {
      batch_state$last_log <- "Error: no vendor could be inferred from selected products."
      return()
    }

    logs <- c()
    vendor_names <- names(grouped)
    withProgress(message = "Batch Apply to KB", detail = paste0(length(sel_prods), " selected products"), value = 0.05, {
      for (idx in seq_along(vendor_names)) {
        vendor_key <- vendor_names[[idx]]
        vendor_products <- grouped[[vendor_key]]
        res <- run_crawl_cmd(c(pipeline_script, "--vendor", vendor_key,
                                "--max-products", as.character(length(vendor_products)), "--apply"))
        logs <- c(logs, paste0("[", vendor_key, "]"), res$out)
        incProgress(1 / length(vendor_names), detail = vendor_key)
      }
      batch_state$last_log <- paste(logs, collapse = "\n")
      reload_kb_all()
      if (!is.null(state$rv_portfolio_refresh))
        state$rv_portfolio_refresh(state$rv_portfolio_refresh() + 1)
      showNotification("Batch Apply completed and KB reloaded.", type = "message", duration = 5)
    })
  })

  output$kb_batch_status <- renderText({
    batch_state$last_log %||% "Ready."
  })

  # ── KB stats for dashboard / status bar ───────────────────────────────────
  output$kb_stats_text <- renderText({
    kb_all <- kb_all_rv()
    n_total <- nrow(kb_all)
    n_high  <- sum(kb_all$knowledge_confidence == "high",  na.rm = TRUE)
    n_mfr   <- length(unique(kb_all$manufacturer[!is.na(kb_all$manufacturer)]))
    paste0(n_total, " devices  |  ", n_mfr, " manufacturers  |  ",
           n_high, " high-confidence records")
  })
}
