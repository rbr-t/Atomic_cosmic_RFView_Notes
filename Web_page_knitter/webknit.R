library(shiny)
library(shinyjs)
library(rmarkdown)
library(here)
library(fs)
library(httr)


`%||%` <- function(a, b) if (!is.null(a)) a else b

# Helper: Copy all files from source to www
copy_source_to_www <- function(source_folder, www_folder = "www") {
  if (!dir.exists(source_folder)) {
    return()
  }
  if (!dir.exists(www_folder)) dir.create(www_folder, recursive = TRUE)
  files <- list.files(source_folder, recursive = TRUE, full.names = TRUE)
  for (f in files) {
    if (file.info(f)$isdir) next
    dest <- file.path(www_folder, basename(f))
    file.copy(f, dest, overwrite = TRUE)
  }
}

# Helper: Copy rendered report to www and rewrite src links
# ...existing code...
copy_report_to_www <- function(report_path, source_folder = NULL, www_folder = "www", verbose = FALSE) {
  dir.create(www_folder, recursive = TRUE, showWarnings = FALSE)

  # locate/rendered report (fallback to newest html in same dir)
  rp <- tryCatch(normalizePath(report_path, winslash = "/", mustWork = FALSE), error = function(e) NA_character_)
  if (is.na(rp) || !file.exists(rp)) {
    possible_dir <- if (!is.na(rp)) dirname(rp) else "."
    if (!dir.exists(possible_dir)) possible_dir <- "."
    html_candidates <- list.files(possible_dir, pattern = "\\.html?$", full.names = TRUE)
    if (length(html_candidates) == 0) {
      if (isTRUE(verbose)) message("copy_report_to_www: no HTML found for ", report_path)
      return(invisible(NA_character_))
    }
    rp <- html_candidates[which.max(file.info(html_candidates)$mtime)]
    if (isTRUE(verbose)) message("copy_report_to_www: using fallback HTML ", rp)
  }
  rp <- normalizePath(rp, winslash = "/", mustWork = TRUE)
  report_dir  <- dirname(rp)
  report_file <- basename(rp)

  # determine source_dir (prefer explicit)
  source_dir <- if (!is.null(source_folder) && nzchar(source_folder) && dir.exists(source_folder)) {
    tryCatch(normalizePath(source_folder, winslash = "/", mustWork = TRUE), error = function(e) report_dir)
  } else {
    report_dir
  }
  src_basename <- basename(source_dir)

  # dest: www/<source_basename>/...
  dest_root <- file.path(www_folder, src_basename)
  if (dir.exists(dest_root)) {
    tryCatch(unlink(dest_root, recursive = TRUE, force = TRUE), error = function(e) {
      if (isTRUE(verbose)) message("copy_report_to_www: removing old dest failed: ", e$message)
    })
  }
  dir.create(dest_root, recursive = TRUE, showWarnings = FALSE)

  # copy entire source_dir tree into dest_root preserving subfolders
  files_src <- list.files(source_dir, all.files = TRUE, recursive = TRUE, full.names = TRUE)
  for (f in files_src) {
    if (identical(normalizePath(f, winslash = "/"), normalizePath(source_dir, winslash = "/"))) next
    if (file.info(f)$isdir) next
    rel <- if (startsWith(f, paste0(source_dir, "/"))) substring(f, nchar(source_dir) + 2) else basename(f)
    destf <- file.path(dest_root, rel)
    dir.create(dirname(destf), recursive = TRUE, showWarnings = FALSE)
    tryCatch(file.copy(f, destf, overwrite = TRUE), error = function(e) {
      if (isTRUE(verbose)) message("copy_report_to_www: failed to copy asset ", f, " -> ", destf, " : ", e$message)
    })
  }

  # copy the rendered HTML into same dest_root
  dest_report <- file.path(dest_root, report_file)
  tryCatch(file.copy(rp, dest_report, overwrite = TRUE), error = function(e) {
    if (isTRUE(verbose)) message("copy_report_to_www: failed to copy HTML to dest: ", e$message)
  })

  # if copied HTML exists, rewrite local links so they point inside dest_root (preserve subfolders)
  if (file.exists(dest_report)) {
    txt <- paste(readLines(dest_report, warn = FALSE), collapse = "\n")
    # unify slashes
    txt <- gsub("\\\\", "/", txt)

    # helper to rewrite attribute matches (href/src/data-src/data-href)
    attr_pat <- '(?i)\\b(href|src|data-src|data-href)\\s*=\\s*([\'"])(.*?)\\2'
    m <- gregexpr(attr_pat, txt, perl = TRUE)[[1]]
    if (m[1] != -1) {
      matches <- regmatches(txt, list(m))[[1]]
      starts <- m
      lens <- attr(m, "match.length")
      for (i in rev(seq_along(matches))) {
        full <- matches[i]
        rex <- regexec(attr_pat, full, perl = TRUE)
        groups <- regmatches(full, rex)[[1]]
        if (length(groups) < 4) next
        key <- groups[2]
        q <- groups[3]
        url_raw <- groups[4]
        url_norm <- gsub("\\\\", "/", url_raw)
        # skip external/protocol-relative/data/mailto/javascript/anchor
        if (grepl("^(?i)([a-z]+:|//|data:|mailto:|javascript:|#)", url_norm, perl = TRUE)) next

        new_url <- url_norm
        # if url starts with source basename (e.g. "Master_report/sub/foo.png") remove the top segment
        if (startsWith(url_norm, paste0(src_basename, "/"))) {
          new_url <- sub(paste0("^", src_basename, "/+"), "", url_norm)
        } else {
          # if url is absolute pointing inside source_dir, make it relative to source_dir
          abs_url_try <- tryCatch(normalizePath(url_norm, winslash = "/", mustWork = FALSE), error = function(e) NA_character_)
          if (!is.na(abs_url_try) && startsWith(abs_url_try, source_dir)) {
            relpath <- substring(abs_url_try, nchar(source_dir) + 2)
            new_url <- relpath
          } else {
            # if it contains the source_dir path segments, strip up to basename
            norm_slashed <- gsub("\\\\", "/", url_norm)
            idx <- regexpr(paste0(src_basename, "/"), norm_slashed, fixed = TRUE)
            if (idx[1] > -1) {
              new_url <- substring(norm_slashed, idx[1] + nchar(src_basename) + 1)
            }
          }
        }
        # ensure no leading "./"
        new_url <- sub("^\\./+", "", new_url)
        # build replacement preserving quotes and attribute key
        replacement <- paste0(key, "=", q, new_url, q)
        substr(txt, starts[i], starts[i] + lens[i] - 1) <- replacement
      }
    }

    # rewrite url(...) occurrences (CSS/background images)
    url_pat <- '(?i)url\\((["\']?)(.*?)\\1\\)'
    m2 <- gregexpr(url_pat, txt, perl = TRUE)[[1]]
    if (m2[1] != -1) {
      matches2 <- regmatches(txt, list(m2))[[1]]
      starts2 <- m2
      lens2 <- attr(m2, "match.length")
      for (i in rev(seq_along(matches2))) {
        full <- matches2[i]
        rex <- regexec(url_pat, full, perl = TRUE)
        groups <- regmatches(full, rex)[[1]]
        if (length(groups) < 3) next
        url_raw <- groups[2]
        if (grepl("^(?i)([a-z]+:|//|data:|#)", url_raw, perl = TRUE)) next
        new_url <- url_raw
        if (startsWith(url_raw, paste0(src_basename, "/"))) {
          new_url <- sub(paste0("^", src_basename, "/+"), "", url_raw)
        } else {
          idx <- regexpr(paste0(src_basename, "/"), url_raw, fixed = TRUE)
          if (idx[1] > -1) new_url <- substring(url_raw, idx[1] + nchar(src_basename) + 1)
        }
        newurl_expr <- paste0("url('", new_url, "')")
        substr(txt, starts2[i], starts2[i] + lens2[i] - 1) <- newurl_expr
      }
    }

    # rewrite srcset entries (keep descriptors)
    srcset_pat <- '(?i)\\bsrcset\\s*=\\s*([\'"])(.*?)\\1'
    if (grepl(srcset_pat, txt, perl = TRUE)) {
      txt <- gsub(srcset_pat, function(m) {
        inner <- sub(srcset_pat, "\\2", m, perl = TRUE)
        parts <- strsplit(inner, ",")[[1]]
        newparts <- vapply(parts, function(p) {
          ptrim <- trimws(p)
          sp <- strsplit(ptrim, "\\s+")[[1]]
          urlp <- sp[1]; rest <- if (length(sp) > 1) paste(sp[-1], collapse = " ") else ""
          if (startsWith(urlp, paste0(src_basename, "/"))) {
            urlp <- sub(paste0("^", src_basename, "/+"), "", urlp)
          } else {
            idx <- regexpr(paste0(src_basename, "/"), urlp, fixed = TRUE)
            if (idx[1] > -1) urlp <- substring(urlp, idx[1] + nchar(src_basename) + 1)
          }
          if (nzchar(rest)) paste(urlp, rest) else urlp
        }, FUN.VALUE = character(1))
        paste0('srcset="', paste(newparts, collapse = ", "), '"')
      }, txt, perl = TRUE)
    }

    # write modified HTML back
    tryCatch(writeLines(txt, con = dest_report), error = function(e) {
      if (isTRUE(verbose)) message("copy_report_to_www: failed to write modified HTML: ", e$message)
    })
  }

  if (isTRUE(verbose)) message("copy_report_to_www: copied HTML+assets to ", dest_root)
  invisible(file.path(src_basename, report_file))
}
# ...existing code...}


find_project_file <- function(filename, root = here()) {
  found <- list.files(root, pattern = paste0("^", filename, "$"), recursive = TRUE, full.names = TRUE)
  if (length(found) > 0) {
    return(found[1])
  } else {
    stop(paste("Could not find", filename, "in", root))
  }
}

logo_path <- find_project_file("logo.png")
bootstrap_css_path <- find_project_file("bootstrapMint.css")
styles_css_path <- find_project_file("styles.css")
baya_weaver_path <- find_project_file("baya_weaver1.jpg")

# Utility function to return both original and converted paths
convert_ishare_path <- function(path) {
  if (is.null(path) || path == "") {
    print("Path is NULL or empty.")
    return(list(original_path = path, converted_path = path))
  }

  original_path <- path
  converted_path <- path

  print(paste("Original Path:", original_path))

  if (grepl("^https://sec-ishare\\.infineon\\.com", path)) {
    print("Path matches iShare URL pattern. Converting...")
    # Convert iShare URL to network path
    converted_path <- gsub("^https://sec-ishare\\.infineon\\.com", "//sec-ishare.infineon.com@SSL/DavWWWRoot", path)
    converted_path <- gsub("/", "\\\\", converted_path) # Replace forward slashes with backslashes
    print(paste("Converted Path:", converted_path))
  } else {
    print("Path does not match iShare URL pattern. No conversion performed.")
  }

  print(paste("Returning Original Path:", original_path))
  print(paste("Returning Converted Path:", converted_path))

  return(list(original_path = original_path, converted_path = converted_path))
}

# Chat history helpers
save_chat_history <- function(messages, context_key, folder = "www") {
  file_path <- file.path(folder, paste0("chat_history_", context_key, ".txt"))
  writeLines(messages, file_path)
}
load_chat_history <- function(context_key, folder = "www") {
  file_path <- file.path(folder, paste0("chat_history_", context_key, ".txt"))
  if (file.exists(file_path)) {
    readLines(file_path)
  } else {
    character()
  }
}

# Clean up www folder on app start, keep essential assets
onStart <- function() {
  www_folder <- here("Web-page-knitter", "www")
  if (!dir.exists(www_folder)) {
    return()
  }
  keep_files <- c("logo.png", "styles.css", "bootstrapMint.css", "baya_weaver1.jpg")
  all_files <- list.files(www_folder, full.names = TRUE)
  for (f in all_files) {
    if (!basename(f) %in% keep_files) file.remove(f)
  }
}

# UI Module
reportTabUI <- function(id, toc_choices = NULL) {
  ns <- NS(id)
  fluidPage(
    tags$head(     
      tags$link(rel = "stylesheet", type = "text/css", href = "styles.css"),
      tags$link(rel = "stylesheet", type = "text/css", href = "bootstrapMint.css"),
      tags$style(HTML("
        .sidebar-toggle-float {
          position: fixed;
          top: 80px;
          left: 10px;
          z-index: 2000;
          background: #2196F3;
          color: #fff;
          border: none;
          border-radius: 50%;
          width: 40px;
          height: 40px;
          box-shadow: 0 2px 6px rgba(0,0,0,0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
        }
        .sidebar-toggle-float:hover {
          background: #1769aa;
        }
        .right-sidebar-toggle-float {
          position: fixed;
          top: 80px;
          right: 10px;
          z-index: 2000;
          background: #2196F3;
          color: #fff;
          border: none;
          border-radius: 50%;
          width: 40px;
          height: 40px;
          box-shadow: 0 2px 6px rgba(0,0,0,0.2);
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
        }
        .right-sidebar-toggle-float:hover {
          background: #1769aa;
        }
        .sidebar-hidden {
          display: none !important;
        }
        .main-panel-expanded {
          width: 100% !important;
          max-width: 100% !important;
        }
        .right-sidebar {
          position: fixed;
          top: 70px;
          right: 0;
          width: 350px;
          height: calc(100% - 70px);
          background: #f8f9fa;
          border-left: 1px solid #ddd;
          z-index: 1500;
          padding: 20px;
          overflow-y: auto;
          box-shadow: -2px 0 6px rgba(0,0,0,0.1);
        }
        .right-sidebar-hidden {
          display: none !important;
        }
        #sidebar_panel {
  transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
          }
          .sidebar-hidden {
            max-width: 0 !important;
            min-width: 0 !important;
            width: 0 !important;
            opacity: 0;
            overflow: hidden !important;
            transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
          }
          .right-sidebar {
            transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
          }
          .right-sidebar-hidden {
            right: -350px !important;
            opacity: 0;
            transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
          }
        .chatbox-messages {
          height: 300px;
          overflow-y: auto;
          background: #fff;
          border: 1px solid #ccc;
          padding: 10px;
          margin-bottom: 10px;
        }
      "))
    ),
    actionButton(ns("toggle_sidebar"), label = NULL, icon = icon("bars"), class = "sidebar-toggle-float"),
    actionButton(ns("toggle_right_sidebar"), label = NULL, icon = icon("comments"), class = "right-sidebar-toggle-float"),
    fluidRow(
      useShinyjs(),
      sidebarLayout(
        sidebarPanel(
          div(
            class = "sticky-buttons",
            div(
              class = "button-row",
              actionButton(ns("add_section"), "Add Section +", class = "btn btn-success"),
              actionButton(ns("render_all_reports"), "Render Reports", class = "btn btn-primary")
            )
          ),
          br(),
          div(id = ns("dynamic_sections")),
          width = 4,
          id = ns("sidebar_panel")
        ),
        mainPanel(
          navbarPage(
            id = ns("dynamic_navbar"),
            title = "Report previews",
            tabPanel("Welcome", h6("Rendered reports will appear here!"))
          ),
          width = 8,
          id = ns("main_panel")
        )
      ),
      # Right sidebar (chatbox), hidden by default
      div(
        id = ns("right_sidebar"),
        class = "right-sidebar right-sidebar-hidden",
        h4("Chat with LLM"),
        selectInput(
          ns("llm_model"),
          "Choose Language Model:",
          choices = c("Local tinyllama (Ollama)", "OpenAI GPT-4", "OpenAI GPT-3.5", "Anthropic Claude 3", "Google Gemini"),
          selected = "Local tinyllama (Ollama)"
        ),
        passwordInput(
          ns("llm_token"),
          "Paste your API token:",
          placeholder = "Paste your API token here"
        ),
        actionButton(ns("llm_connect"), "Connect", class = "btn btn-info"),
        tags$hr(),
        selectInput(
          ns("chat_context"),
          "Select Chapter/File for Context:",
          choices = toc_choices %||% c("Introduction", "Methods", "Results"),
          selected = toc_choices[[1]] %||% "Introduction"
        ),
        uiOutput(ns("chatbox_messages"), class = "chatbox-messages"),
        textInput(ns("chatbox_input"), "Type your message:"),
        actionButton(ns("chatbox_send"), "Send", class = "btn btn-primary")
      )
    )
  )
}

# Server Module
reportTabServer <- function(id, rmd_file, report_type = "individual", toc_choices = NULL) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    report_type <- match.arg(report_type, choices = c("individual", "master"))
    rv <- reactiveValues(section_count = 0, sections = list())
    # Chat state
    chat_messages <- reactiveVal(character())
    llm_info <- reactiveValues(model = NULL, token = NULL, connected = FALSE)
    chat_context <- reactive({
      input$chat_context %||% "Introduction"
    })

    observeEvent(input$close_tab, {
  tab_name <- input$close_tab
  print(paste("Trying to close tab:", tab_name))
  removeTab(session$ns("dynamic_navbar"), target = tab_name)
  file_to_delete <- file.path("www", paste0(tab_name, ".html"))
  if (file.exists(file_to_delete)) file.remove(file_to_delete)
  showNotification(paste("Closed and deleted:", tab_name), type = "message")
}, ignoreInit = TRUE)

    # Sidebar toggle logic
    observeEvent(input$toggle_sidebar, {
      shinyjs::toggleClass(selector = paste0("#", ns("sidebar_panel")), class = "sidebar-hidden")
      shinyjs::toggleClass(selector = paste0("#", ns("main_panel")), class = "main-panel-expanded")
    })
    # Right sidebar toggle logic
    observeEvent(input$toggle_right_sidebar, {
      shinyjs::toggleClass(selector = paste0("#", ns("right_sidebar")), class = "right-sidebar-hidden")
    })

    # LLM connect logic
    observeEvent(input$llm_connect, {
      llm_info$model <- input$llm_model
      llm_info$token <- input$llm_token
      llm_info$connected <- !is.null(llm_info$token) && nzchar(llm_info$token)
      if (llm_info$connected) {
        showNotification(paste("Connected to", llm_info$model), type = "message")
      } else {
        showNotification("Please enter a valid API token.", type = "error")
      }
    })

    # Load chat history when context changes
    observeEvent(chat_context(), {
      chat_messages(load_chat_history(chat_context()))
      output$chatbox_messages <- renderUI({
        HTML(paste(chat_messages(), collapse = "<br>"))
      })
    })

    # Save chat message on send
    observeEvent(input$chatbox_send, {
      msg <- input$chatbox_input
      if (!is.null(msg) && nzchar(msg)) {
        new_history <- c(chat_messages(), paste0("You: ", msg))
        chat_messages(new_history)
        updateTextInput(session, "chatbox_input", value = "")

        # If connected to Ollama, send prompt and get response
        if (llm_info$connected && grepl("^http://127.0.0.1:11434", llm_info$token)) {
          res <- tryCatch(
            {
              httr::POST(
                url = paste0(llm_info$token, "/api/chat"),
                body = list(
                  model = "tinyllama",
                  messages = list(list(role = "user", content = msg))
                ),
                encode = "json",
                timeout(30)
              )
            },
            error = function(e) NULL
          )
          if (!is.null(res) && httr::status_code(res) == 200) {
            # resp <- httr::content(res) # Default is parsed
            resp <- jsonlite::fromJSON(httr::content(res, as = "text"))
            print(resp) # Debug: See the parsed response
            if (is.list(resp) && !is.null(resp$message) && !is.null(resp$message$content)) {
              reply <- resp$message$content
              new_history <- c(chat_messages(), paste0("TinyLlama: ", reply))
              chat_messages(new_history)
            } else {
              new_history <- c(chat_messages(), "TinyLlama: [Unexpected response format from Ollama]")
              chat_messages(new_history)
            }
          } else {
            new_history <- c(chat_messages(), "TinyLlama: [No response or error from Ollama]")
            chat_messages(new_history)
          }
        }
        output$chatbox_messages <- renderUI({
          HTML(paste(chat_messages(), collapse = "<br>"))
        })
      }
    })
    # Dynamic section logic (same as your previous implementation)
    observeEvent(input$add_section, {
      rv$section_count <- rv$section_count + 1
      section_id <- paste0("section_", rv$section_count)
      insertUI(
        selector = paste0("#", ns("dynamic_sections")),
        ui = div(
          id = ns(section_id),
          checkboxInput(ns(paste0(section_id, "_checkbox")), "Include this section", value = TRUE),
          textInput(ns(paste0(section_id, "_source")), "Source Folder", placeholder = "Paste Source path"),
          textInput(ns(paste0(section_id, "_destination")), "Destination Folder", placeholder = "Paste Destination path"),
          textInput(ns(paste0(section_id, "_title")), "Report Title", placeholder = "Enter in format (Title-Subtitle-addition)"),
          textInput(ns(paste0(section_id, "_author")), "Author", placeholder = "Enter Author"),
          div(
            style = "display: flex; align-items: center; gap: 10px;",
            div(style = "flex: 2;", fileInput(ns(paste0(section_id, "_logo")), "Logo (optional):",
              accept = c("image/png", "image/jpeg", "image/jpg")
            )),
            div(style = "flex: 1;", numericInput(ns(paste0(section_id, "_logo_width")), "Width:", value = 75, min = 10)),
            div(style = "flex: 1;", numericInput(ns(paste0(section_id, "_logo_height")), "Height:", value = 35, min = 10))
          ),
          selectInput(
            ns(paste0(section_id, "_format")),
            "Choose Report Format:",
            choices = c(
              "HTML Document" = "rmarkdown::html_document",
              "Flex Dashboard" = "flexdashboard::flex_dashboard",
              "Reveal.js Presentation" = "revealjs::revealjs_presentation",
              "Slidy Presentation" = "rmarkdown::slidy_presentation",
              "ioslides Presentation" = "rmarkdown::ioslides_presentation"
            ),
            selected = "rmarkdown::html_document"
          ),
          actionButton(ns(paste0(section_id, "_remove")), "Remove Section -", class = "btn btn-danger"),
          hr()
        )
      )
      observeEvent(input[[paste0(section_id, "_remove")]], {
        removeUI(selector = paste0("#", ns(section_id)))
        rv$sections[[section_id]] <- NULL
      })
      rv$sections[[section_id]] <- list(
        source_path = NULL,
        destination_path = NULL,
        title = NULL,
        author = NULL,
        logo = logo_path,
        logo_width = 75,
        logo_height = 35,
        format = NULL,
        checkbox = TRUE
      )
    })

    # Synchronize inputs with reactiveValues
    observe({
      for (section_id in names(rv$sections)) {
        if (!is.null(rv$sections[[section_id]])) {
          # Get the current inputs
          source_path <- input[[paste0(section_id, "_source")]]
          destination_path <- input[[paste0(section_id, "_destination")]]

          print(paste0("This is source path:", source_path))
          print(paste0("This is destination path:", destination_path))

          # Convert paths using the updated convert_ishare_path() function
          paths_source <- convert_ishare_path(source_path)
          paths_destination <- convert_ishare_path(destination_path)

          # Store both original and converted paths in rv$sections
          rv$sections[[section_id]]$original_source <- paths_source$original_path
          rv$sections[[section_id]]$converted_source <- paths_source$converted_path
          rv$sections[[section_id]]$original_destination <- paths_destination$original_path
          rv$sections[[section_id]]$converted_destination <- paths_destination$converted_path

          # Debugging: Print stored paths
          print(paste("Original Source Path:", rv$sections[[section_id]]$original_source))
          print(paste("Converted Source Path:", rv$sections[[section_id]]$converted_source))
          print(paste("Original Destination Path:", rv$sections[[section_id]]$original_destination))
          print(paste("Converted Destination Path:", rv$sections[[section_id]]$converted_destination))


          # Update reactiveValues with converted paths
          if (!identical(rv$sections[[section_id]]$source_path, paths_source$converted_path)) {
            rv$sections[[section_id]]$source_path <- paths_source$converted_path
            print(paste("Converted Source Path:", paths_source$converted_path)) # Debugging
          }

          if (!identical(rv$sections[[section_id]]$destination_path, paths_destination$converted_path)) {
            rv$sections[[section_id]]$destination_path <- paths_destination$converted_path
            print(paste("Converted Destination Path:", paths_destination$converted_path)) # Debugging
          }

          # Update other inputs
          rv$sections[[section_id]]$title <- input[[paste0(section_id, "_title")]]
          rv$sections[[section_id]]$author <- input[[paste0(section_id, "_author")]]
          rv$sections[[section_id]]$logo <- if (!is.null(input[[paste0(section_id, "_logo")]])) {
            input[[paste0(section_id, "_logo")]]$datapath
          } else {
            logo_path # Default logo path if no file is uploaded
          }
          rv$sections[[section_id]]$logo_width <- input[[paste0(section_id, "_logo_width")]]
          rv$sections[[section_id]]$logo_height <- input[[paste0(section_id, "_logo_height")]]
          rv$sections[[section_id]]$format <- input[[paste0(section_id, "_format")]]
          rv$sections[[section_id]]$checkbox <- input[[paste0(section_id, "_checkbox")]]

          # print("Debug: Contents of rv$sections before rendering:")
          # print(rv$sections)
        }
      }
    })

    # Render all reports when "Render Reports" button is clicked (same as before)
    observeEvent(input$render_all_reports, {
      withProgress(message = "Rendering reports...", value = 0, {
        num_sections <- length(names(rv$sections))
        progress_step <- 1 / max(num_sections, 1) # Avoid division by zero

        for (section_id in names(rv$sections)) {
          section <- rv$sections[[section_id]]
          if (!is.null(section) && section$checkbox) {
            # Debugging: Print paths before validation
            print(paste("Debug: Section Source Path =", section$source_path))
            print(paste("Debug: Section Destination Path =", section$destination_path))

            # Validate inputs
            if ((is.null(section$original_source) || section$original_source == "") ||
              (is.null(section$converted_destination) || section$converted_destination == "") ||
              (is.null(section$title) || section$title == "") ||
              (is.null(section$author) || section$author == "")) {
              showNotification("Error: Missing inputs in section", type = "error")
              next
            }

            # Dynamically set output options
            output_options <- switch(section$format,
              "rmarkdown::html_document" = if (report_type == "individual") {
                list(
                  toc = TRUE,
                  toc_float = TRUE,
                  number_sections = TRUE,
                  theme = "yeti",
                  css = c(styles_css_path, bootstrap_css_path)
                )
              } else {
                list(
                  number_sections = TRUE,
                  theme = "yeti",
                  css = c(styles_css_path, bootstrap_css_path)
                )
              },
              "flexdashboard::flex_dashboard" = list(orientation = "rows"),
              "revealjs::revealjs_presentation" = list(slide_level = 3),
              "rmarkdown::slidy_presentation" = list(slide_level = 3),
              "rmarkdown::ioslides_presentation" = list(widescreen = TRUE, incremental = TRUE, smaller = TRUE),
              NULL
            )

            # Update progress message
            incProgress(progress_step, detail = paste("Rendering:", section$title))

            # Log the rendering process for debugging
            print(paste("Rendering report for section:", section_id))

            # Use pre-computed paths instead of re-converting
            original_src_path <- section$original_source
            converted_src_path <- section$converted_source
            original_dstn_path <- section$original_destination
            converted_dstn_path <- section$converted_destination

            # Render the report
            report_filename <- paste0(gsub("[^a-zA-Z0-9\\s]", "_", section$title), ".html")
            report_filepath <- file.path(section$destination, report_filename)

            # ...existing code...
            tryCatch(
              {
                # local verbose flag for debug printing (avoid undefined variable errors)
                verbose <- FALSE
                # --- prepare safe filenames/paths ---
                sanitized_title <- gsub("[^a-zA-Z0-9\\s]", " ", section$title)
                sanitized_title <- gsub("\\s+", "-", trimws(sanitized_title))
                report_filename <- paste0(sanitized_title, ".html")
                report_filepath <- file.path(section$destination_path, report_filename)

                # ensure destination exists
                dir_create(section$destination_path)
                dir_create("www")

                # Debug prints
                if (isTRUE(verbose)) {
                  message("Rendering to: ", report_filepath)
                  message("Source folder (assets): ", section$source_path)
                }

                # Render using the exact report_filename into destination_path
                rmarkdown::render(
                  input = rmd_file,
                  output_file = report_filename,          # exact filename
                  output_dir  = section$destination_path, # exact folder
                  params = list(
                    original_src_path = as.character(original_src_path),
                    converted_src_path = as.character(converted_src_path),
                    original_dstn_path = as.character(original_dstn_path),
                    converted_dstn_path = as.character(converted_dstn_path),
                    title = as.character(section$title),
                    author = as.character(section$author),
                    logo = section$logo,
                    logo_width = section$logo_width,
                    logo_height = section$logo_height
                  ),
                  output_format  = section$format,
                  output_options = output_options
                )

                # confirm rendered file exists
                if (!file.exists(report_filepath)) {
                  stop("Rendered HTML not found at: ", report_filepath, ". Files in destination: ",
                       paste(list.files(section$destination_path, pattern = "\\.html?$", full.names = TRUE), collapse = ", "))
                }

                # Copy rendered report + assets -> www; pass source folder explicitly
                iframe_src <- copy_report_to_www(
                  report_path   = report_filepath,
                  source_folder = section$source_path,
                  www_folder    = "www",
                  verbose       = TRUE
                )

                if (is.na(iframe_src) || !nzchar(iframe_src)) {
                  stop("copy_report_to_www failed to prepare preview for: ", report_filepath)
                }

                showNotification(paste0("Report successfully rendered: ", section$title), type = "message")

                # Only append the preview tab after successful copy; use returned path
                appendTab(
                  inputId = "dynamic_navbar",
                  tabPanel(
                    title = tagList(
                      section$title,
                      tags$button(
                        class = "tab-close-btn btn btn-link btn-sm",
                        style = "padding:0;margin-left:8px;",
                        `data-tabname` = ns(section$title),
                        icon("times")
                      )
                    ),
                    tags$iframe(
                      src = iframe_src, # use path returned by copy_report_to_www (e.g. "Folder/report.html")
                      width = "100%",
                      height = "750px",
                      frameborder = "0"
                    )
                  ),
                  select = TRUE
                )
              },
              error = function(e) {
                showNotification(paste0("Error rendering report: ", e$message), type = "error")
              }
            )
            gc() # Clean up memory
          }
        }
      })
    })
  })
}

# Main UI
ui <- navbarPage(
  tags$head(
    tags$script(HTML("
    $(document).on('click', '.tab-close-btn', function(e) {
      var tabName = $(this).data('tabname');
      Shiny.setInputValue('close_tab', tabName, {priority: 'event'});
      e.stopPropagation();
    });
  "))
  ),
  theme = bslib::bs_theme(version = 5, bootswatch = "minty"),
  title = div(
    img(src = "baya_weaver1.jpg", height = "60px", style = "margin-right: 10px;"),
    "Web-page knitter"
  ),  
  header = div(
    class = "toggle-switch",
    tags$input(id = "toggle_night_view", type = "checkbox"),
    tags$label(class = "slider", `for` = "toggle_night_view")
  ),
  tabPanel(
    "Individual Reports",
    fluidPage(
      actionButton("toggle_sidebar", label = NULL, icon = icon("bars"), class = "sidebar-toggle-float"),
      actionButton("toggle_right_sidebar", label = NULL, icon = icon("bars"), class = "right-sidebar-toggle-float"),
      useShinyjs(),
      tags$head(
        tags$link(rel = "stylesheet", type = "text/css", href = styles_css_path),
        tags$link(rel = "stylesheet", type = "text/css", href = bootstrap_css_path)
      ),
      reportTabUI("individual")
    )
  ),
  tabPanel(
    "Master Report",
    fluidPage(
      useShinyjs(),
      tags$head(
        tags$link(rel = "stylesheet", type = "text/css", href = styles_css_path),
        tags$link(rel = "stylesheet", type = "text/css", href = bootstrap_css_path)
      ),
      reportTabUI("master")
    )
  )
)

# Main server
server <- function(input, output, session) {
  useShinyjs()
  observe({
    if (input$toggle_night_view) {
      shinyjs::addClass(selector = "body", class = "night-mode")
      shinyjs::addClass(selector = ".navbar", class = "night-mode")
    } else {
      shinyjs::removeClass(selector = "body", class = "night-mode")
      shinyjs::removeClass(selector = ".navbar", class = "night-mode")
    }
  })

  individual_rmd_file <- find_project_file("Report_generator_ShinyApp.Rmd")
  master_rmd_file <- find_project_file("Master_html_report_ShinyApp.Rmd")
  # Example TOC choices, you can populate dynamically
  toc_choices <- c("Introduction", "Methods", "Results")
  reportTabServer("individual", rmd_file = individual_rmd_file, report_type = "individual", toc_choices = toc_choices)
  reportTabServer("master", rmd_file = master_rmd_file, report_type = "master", toc_choices = toc_choices)
}

options(shiny.port = 4846)
shinyApp(ui = ui, server = server, onStart = onStart)
