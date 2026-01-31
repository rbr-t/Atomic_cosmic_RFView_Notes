library(shiny)
library(shinyjs)
library(rmarkdown)
library(here)
library(fs)
library(httr)


`%||%` <- function(a, b) if (!is.null(a)) a else b

# Load external chat handlers (sourced later after helper functions are defined)
# source("chat_module.R")

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
baya_weaver_path <- find_project_file("baya_weaver_2.png")
chat_module_path <- find_project_file("chat_module.R")

# ============================================================================
# ENHANCED PATH HANDLING FUNCTIONS
# ============================================================================

# Normalize path for cross-platform compatibility and relative path support
normalize_path_for_app <- function(path, base_dir = here::here()) {
  if (is.null(path) || !nzchar(path)) return(path)
  
  # Check if already relative (doesn't start with / or drive letter)
  if (!startsWith(path, "/") && !grepl("^[A-Za-z]:", path)) {
    # Already relative, resolve from base_dir
    resolved <- normalizePath(file.path(base_dir, path), winslash = "/", mustWork = FALSE)
    if (file.exists(resolved) || dir.exists(resolved)) {
      return(resolved)
    }
    # If doesn't exist, still return the constructed path for user to create it
    return(file.path(base_dir, path))
  }
  
  # Try to make absolute paths relative to base_dir for portability
  path_norm <- tryCatch(normalizePath(path, winslash = "/", mustWork = FALSE), error = function(e) path)
  base_norm <- tryCatch(normalizePath(base_dir, winslash = "/", mustWork = TRUE), error = function(e) base_dir)
  
  if (startsWith(path_norm, base_norm)) {
    # Can be made relative
    rel_path <- substring(path_norm, nchar(base_norm) + 2)
    return(rel_path)
  }
  
  return(path_norm)  # Return normalized absolute path
}

# Validate source path with helpful error messages
validate_source_path <- function(path, show_notification = TRUE, session = NULL) {
  if (is.null(path) || !nzchar(path)) {
    if (show_notification) {
      msg <- "Source path is empty. Please specify a folder path."
      if (!is.null(session)) showNotification(msg, type = "error", session = session)
    }
    return(list(valid = FALSE, error = "empty"))
  }
  
  # Normalize the path first
  norm_path <- normalize_path_for_app(path)
  
  if (!dir.exists(norm_path)) {
    if (show_notification && !is.null(session)) {
      show_path_error(path, "not_found", session)
    }
    return(list(valid = FALSE, error = "not_found", normalized = norm_path))
  }
  
  # Check read permissions
  test_file <- tryCatch({
    list.files(norm_path, all.files = FALSE, full.names = FALSE, no.. = TRUE)
    TRUE
  }, error = function(e) FALSE)
  
  if (!test_file) {
    if (show_notification && !is.null(session)) {
      show_path_error(path, "permission", session)
    }
    return(list(valid = FALSE, error = "permission", normalized = norm_path))
  }
  
  return(list(valid = TRUE, normalized = norm_path))
}

# Show context-aware error messages for path problems
show_path_error <- function(path, error_type = "not_found", session = NULL) {
  base_msg <- switch(error_type,
    "not_found" = paste0("📁 Path not found: ", path),
    "empty" = "📁 Path is empty or not specified",
    "permission" = paste0("🔒 Permission denied for: ", path),
    "invalid" = paste0("⚠️ Invalid path format: ", path),
    paste0("❌ Error with path: ", path)
  )
  
  suggestions <- c(
    "",
    "💡 Suggestions:",
    "• Use relative paths (e.g., 'IFX_2022_2025/Report_generator_rmd/')",
    "• Check if the folder exists",
    "• Verify you have read permissions"
  )
  
  # Check if path looks like Windows path on Unix
  if (.Platform$OS.type == "unix" && grepl("^[A-Za-z]:", path)) {
    suggestions <- c(suggestions,
      "• This looks like a Windows path - use forward slashes (/) on Unix/Mac",
      "• Consider using relative paths for cross-platform compatibility")
  }
  
  # Check for common mistakes
  if (grepl("\\\\", path) && .Platform$OS.type == "unix") {
    suggestions <- c(suggestions,
      "• Use forward slashes (/) instead of backslashes (\\) on Unix/Mac")
  }
  
  full_msg <- paste(c(base_msg, suggestions), collapse = "\n")
  
  if (!is.null(session)) {
    showNotification(full_msg, type = "error", duration = 15, session = session)
  } else {
    showNotification(full_msg, type = "error", duration = 15)
  }
}

# Enhanced path conversion supporting iShare and cross-platform paths
normalize_cross_platform_path <- function(path) {
  if (is.null(path) || !nzchar(path)) {
    return(list(original_path = path, converted_path = path))
  }
  
  original_path <- path
  converted_path <- path
  
  # Handle iShare URLs
  if (grepl("^https://sec-ishare\\.infineon\\.com", path)) {
    converted_path <- gsub("^https://sec-ishare\\.infineon\\.com", 
                           "//sec-ishare.infineon.com@SSL/DavWWWRoot", path)
    converted_path <- gsub("/", "\\\\", converted_path)
  }
  
  # Handle Windows paths on Linux/Mac
  if (.Platform$OS.type == "unix" && grepl("^[A-Za-z]:", path)) {
    message(paste("⚠️ Windows path detected on Unix system:", path))
  }
  
  # Normalize slashes for current OS
  converted_path <- normalizePath(converted_path, winslash = "/", mustWork = FALSE)
  
  return(list(original_path = original_path, converted_path = converted_path))
}

# Legacy function for backward compatibility
convert_ishare_path <- function(path) {
  normalize_cross_platform_path(path)
}

# Recent paths management
get_recent_paths <- function(type = "source", max_items = 10) {
  cache_dir <- file.path(path.expand('~'), '.webknit')
  cache_file <- file.path(cache_dir, paste0('recent_', type, '_paths.txt'))
  
  if (file.exists(cache_file)) {
    paths <- readLines(cache_file, warn = FALSE)
    # Filter out paths that no longer exist
    valid_paths <- paths[sapply(paths, dir.exists)]
    return(head(unique(valid_paths), max_items))
  }
  return(character())
}

save_recent_path <- function(path, type = "source") {
  if (is.null(path) || !nzchar(path)) return(invisible(NULL))
  
  cache_dir <- file.path(path.expand('~'), '.webknit')
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  
  cache_file <- file.path(cache_dir, paste0('recent_', type, '_paths.txt'))
  existing <- if (file.exists(cache_file)) readLines(cache_file, warn = FALSE) else character()
  
  # Add new path at the beginning
  updated <- unique(c(path, existing))
  writeLines(head(updated, 20), cache_file)  # Keep last 20
  invisible(NULL)
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

# Helper: extract TOC choices from a rendered HTML file.
# Preference order:
# 1) Look for an element with class/id 'toc' or role='navigation' containing anchor links.
# 2) Fall back to scanning for headings (h1-h3) and use their text and ids/anchors.
# Returns a named character vector where names are labels shown to user and values are anchors/ids
# (anchor without leading '#'), or NULL if nothing found.
extract_toc_from_html <- function(html_path, max_items = 200, max_depth = 3) {
  if (is.null(html_path) || !file.exists(html_path)) return(NULL)
  txt <- tryCatch(paste(readLines(html_path, warn = FALSE), collapse = "\n"), error = function(e) return(NULL))
  if (is.null(txt) || !nzchar(txt)) return(NULL)
  
  # prefer an explicit TOC container: common classes/ids
  toc_patterns <- c("\\bclass=[\'\"]?toc[\'\"]?", "\\bid=[\'\"]?toc[\'\"]?", "role=[\'\"]?navigation[\'\"]?")
  toc_area <- NULL
  for (pat in toc_patterns) {
    m <- regexpr(pat, txt, perl = TRUE, ignore.case = TRUE)
    if (m[1] > -1) {
      # try to extract the nearest <nav> or <div> block around match
      start_idx <- max(1, m[1] - 200)
      tail <- substring(txt, start_idx)
      # crude extraction: find first <a ... href="#...">label</a> occurrences after pat
      a_pat <- "<a[^>]+href\\s*=\\s*([\'\"])(#?)([^\'\"]+)\\1[^>]*>(.*?)</a>"
      am <- gregexpr(a_pat, tail, perl = TRUE, ignore.case = TRUE)[[1]]
      if (am[1] != -1) {
        matches <- regmatches(tail, list(am))[[1]]
        labels <- character()
        hrefs <- character()
        for (i in seq_along(matches)) {
          full <- matches[i]
          g <- regmatches(full, regexec(a_pat, full, perl = TRUE, ignore.case = TRUE))[[1]]
          if (length(g) >= 5) {
            hrefs <- c(hrefs, g[3])
            # strip tags from label
            lab <- gsub("<[^>]+>", "", g[4])
            lab <- trimws(gsub("\\s+", " ", lab))
            labels <- c(labels, ifelse(nzchar(lab), lab, g[3]))
          }
          if (length(labels) >= max_items) break
        }
        if (length(labels) > 0) {
          names(hrefs) <- labels
          return(hrefs)
        }
      }
    }
  }
  
  # fallback: scan headings h1..h3 and capture id or create anchor from text
  # Use non-greedy match for inner content and ensure we capture the full heading tag
  heading_pat <- "<h([1-3])([^>]*)>(.*?)</h\\1>"
  hm <- gregexpr(heading_pat, txt, perl = TRUE, ignore.case = TRUE)[[1]]
  if (hm[1] == -1) return(NULL)
  matches <- regmatches(txt, list(hm))[[1]]
  labels <- character()
  hrefs <- character()
  for (i in seq_along(matches)) {
    full <- matches[i]
    g <- regmatches(full, regexec(heading_pat, full, perl = TRUE, ignore.case = TRUE))[[1]]
    if (length(g) >= 4) {
      # g[1] full match, g[2] level, g[3] attrs, g[4] inner HTML
      inner <- g[4]
      # try to find id attribute inside the opening tag (g[3])
      idm <- regexec("id=\\s*([\\'\"])([^\\'\"]+)\\1", g[3], perl = TRUE, ignore.case = TRUE)
      idg <- regmatches(g[3], idm)[[1]]
      hid <- if (length(idg) >= 3) idg[3] else NULL
      # strip any tags inside heading to get label text
      lab <- gsub("<[^>]+>", "", inner)
      lab <- trimws(gsub("\\s+", " ", lab))
      if (nzchar(lab)) {
        labels <- c(labels, lab)
        if (!is.null(hid) && nzchar(hid)) {
          hrefs <- c(hrefs, hid)
        } else {
          # generate safe anchor by slugifying label (lowercase first so uppercase letters are preserved)
          lab_low <- tolower(lab)
          slug <- gsub("[^a-z0-9]+", "-", lab_low)
          slug <- gsub("(^-|-$)", "", slug)
          hrefs <- c(hrefs, slug)
        }
      }
    }
    if (length(labels) >= max_items) break
  }
  if (length(labels) == 0) return(NULL)
  names(hrefs) <- labels
  return(hrefs)
}

# Extract plain-text content for a particular anchor (id or anchor name) from an HTML file.
# Returns a trimmed plain-text string or NULL if not found. Truncates to max_chars.
extract_section_text <- function(html_path, anchor = NULL, max_chars = 6000) {
  if (is.null(html_path) || !file.exists(html_path)) return(NULL)
  txt <- tryCatch(paste(readLines(html_path, warn = FALSE), collapse = "\n"), error = function(e) return(NULL))
  if (is.null(txt) || !nzchar(txt)) return(NULL)
  
  # If no anchor provided, return first body text up to max_chars
  if (is.null(anchor) || !nzchar(anchor)) {
    # crude strip of tags
    body <- sub("(?s).*<body[^>]*>(.*)</body>.*", "\\1", txt, perl = TRUE)
    if (!nzchar(body)) body <- txt
    plain <- gsub("<[^>]+>", "", body)
    plain <- gsub("\\s+", " ", plain)
    plain <- trimws(plain)
    if (nchar(plain) > max_chars) plain <- substr(plain, 1, max_chars)
    return(plain)
  }
  
  # find element with id or name matching anchor
  # look for id="anchor" or name="anchor" or href="#anchor"
  # find the heading or element that contains the anchor and then grab subsequent sibling content until next heading of same or higher level
  # crude approach: locate the heading tag that contains id/name or an <a name=> link
  pat_id <- paste0("(<h[1-6][^>]*id=\\\"", anchor, "\\\"[^>]*>.*?</h[1-6]>)|(<h[1-6][^>]*name=\\\'", anchor, "\\\'[^>]*>.*?</h[1-6]>)|(<a[^>]+name=\\\"", anchor, "\\\"[^>]*>\\s*</a>)|(<a[^>]+id=\\\"", anchor, "\\\"[^>]*>\\s*</a>)")
  m <- regexpr(pat_id, txt, perl = TRUE, ignore.case = TRUE)
  start_pos <- if (m[1] > 0) m[1] + attr(m, "match.length") else -1
  
  if (start_pos > 0) {
    # take following chunk up to next <h1|h2|h3 or up to max_chars worth of text
    tail_txt <- substring(txt, start_pos)
    # stop at next heading of level 1-3
    stop_pat <- "(?s)<h([1-3])[^>]*>"
    s <- regexpr(stop_pat, tail_txt, perl = TRUE, ignore.case = TRUE)
    snippet <- if (s[1] > 0) substring(tail_txt, 1, s[1]-1) else tail_txt
    plain <- gsub("<[^>]+>", "", snippet)
    plain <- gsub("\\s+", " ", plain)
    plain <- trimws(plain)
    if (nchar(plain) > max_chars) plain <- substr(plain, 1, max_chars)
    return(plain)
  }
  
  # as a last resort, try to find an anchor by href="#anchor" and extract surrounding text
  href_pat <- paste0("<a[^>]+href=([\'\"])#", anchor, "\\1[^>]*>(.*?)</a>")
  hm <- regexpr(href_pat, txt, perl = TRUE, ignore.case = TRUE)
  if (hm[1] > 0) {
    full <- regmatches(txt, list(hm))[[1]][1]
    lab <- gsub("<[^>]+>", "", full)
    lab <- trimws(lab)
    if (nchar(lab) > 0) return(substr(lab, 1, max_chars))
  }
  
  # If no id/name/href matched, try to locate a heading whose slugified text equals the anchor
  heading_pat_all <- "<h([1-6])([^>]*)>(.*?)</h\\1>"
  hm2 <- gregexpr(heading_pat_all, txt, perl = TRUE, ignore.case = TRUE)[[1]]
  if (hm2[1] != -1) {
    matches2 <- regmatches(txt, list(hm2))[[1]]
    for (full in matches2) {
      g <- regmatches(full, regexec(heading_pat_all, full, perl = TRUE, ignore.case = TRUE))[[1]]
      if (length(g) >= 4) {
        inner <- g[4]
        lab <- gsub("<[^>]+>", "", inner)
        lab <- trimws(gsub("\\s+", " ", lab))
        lab_low <- tolower(lab)
        slug <- gsub("[^a-z0-9]+", "-", lab_low)
        slug <- gsub("(^-|-$)", "", slug)
        if (identical(slug, anchor)) {
          # find this heading's position in the full text and extract following content
          pos <- regexpr(full, txt, fixed = TRUE)[1]
          if (pos > 0) {
            start_pos2 <- pos + nchar(full)
            tail_txt <- substring(txt, start_pos2)
            stop_pat <- "(?s)<h([1-3])[^>]*>"
            s <- regexpr(stop_pat, tail_txt, perl = TRUE, ignore.case = TRUE)
            snippet <- if (s[1] > 0) substring(tail_txt, 1, s[1]-1) else tail_txt
            plain <- gsub("<[^>]+>", "", snippet)
            plain <- gsub("\\s+", " ", plain)
            plain <- trimws(plain)
            if (nchar(plain) > max_chars) plain <- substr(plain, 1, max_chars)
            return(plain)
          }
        }
      }
    }
  }
  
  return(NULL)
}

# Now that helper functions are defined, load the external chat handlers
#source("chat_module.R")
source(chat_module_path)

# Load IFX integration module
ifx_module_path <- here("Web_page_knitter", "Modules", "ifx_integration.R")
if (file.exists(ifx_module_path)) {
  source(ifx_module_path)
  message("IFX integration module loaded successfully")
} else {
  warning("IFX integration module not found at: ", ifx_module_path)
}


# Clean up www folder on app start, keep essential assets
onStart <- function() {
  www_folder <- here("Web_page_knitter", "www")
  if (!dir.exists(www_folder)) {
    dir.create(www_folder, recursive = TRUE)
  }  
  
  keep_files <- c(basename(logo_path), basename(styles_css_path), basename(bootstrap_css_path), basename(baya_weaver_path))
  
  # only examine top-level entries (files and folders) inside www
  entries <- list.files(www_folder, full.names = TRUE, recursive = FALSE)
  for (entry in entries) {
    bn <- basename(entry)
    if (dir.exists(entry)) {
      # remove entire subfolder (recursive)
      tryCatch({
        unlink(entry, recursive = TRUE, force = TRUE)
      }, error = function(e) {
        message("onStart: failed to remove directory ", entry, ": ", e$message)
      })
    } else {
      # file: remove unless it's one of the keep files
      if (!bn %in% keep_files) {
        tryCatch({
          file.remove(entry)
        }, error = function(e) {
          message("onStart: failed to remove file ", entry, ": ", e$message)
        })
      }
    }
  }
}

# UI Module
reportTabUI <- function(id, toc_choices = NULL) {
  ns <- NS(id)
  fluidPage(
    tags$head(       
      tags$link(rel = "stylesheet", type = "text/css", href = paste0(basename(styles_css_path), "?v=", as.integer(file.info(basename(styles_css_path))$mtime))),
      tags$link(rel = "stylesheet", type = "text/css", href = paste0(basename(bootstrap_css_path), "?v=", as.integer(file.info(basename(bootstrap_css_path))$mtime))),
      # Debug helper: allow server to request the browser to print the module nav/tab HTML
      tags$script(HTML("Shiny.addCustomMessageHandler('debug-nav', function(msg){ try{ console.group('debug-nav'); console.log('selector nav:', msg.nav); var nav = document.querySelector(msg.nav); console.log('nav element:', nav ? nav.outerHTML : 'NOT FOUND'); console.log('selector content:', msg.content); var cont = document.querySelector(msg.content); console.log('content element:', cont ? cont.outerHTML : 'NOT FOUND'); console.groupEnd(); } catch(e){ console.warn('debug-nav error', e); } });")),
      # small debug button (hidden) to request a DOM dump from the browser
      tags$script(HTML("$(document).on('click', '#debug_nav_dump', function(){ Shiny.setInputValue('debug_request_nav', Math.random(), {priority: 'event'}); });")),
      # minimal inline CSS only for floating toggles; other styles are in www/styles.css
      #tags$style(HTML('.sidebar-toggle-float{position:fixed;top:200px;left:10px;z-index:2000;background:#2196F3;color:#fff;border:none;border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center}.right-sidebar-toggle-float{position:fixed;top:650px;right:10px;z-index:2000;background:#2196F3;color:#fff;border:none;border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center}.sidebar-hidden{display:none!important}.main-panel-expanded{width:100%!important;max-width:100%!important}.right-sidebar{position:fixed;top:70px;right:0;width:350px;height:calc(100% - 70px);background:#f8f9fa;border-left:1px solid #ddd;z-index=1500;padding:20px;overflow-y:auto;box-shadow:-2px 0 6px rgba(0,0,0,0.1)}'))
      tags$style(HTML('
    .sidebar-toggle-float{position:fixed;top:200px;left:10px;z-index:2000;background:#2196F3;color:#fff;border:none;border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center}
    .right-sidebar-toggle-float{position:fixed;top:650px;right:10px;z-index:2000;background:#2196F3;color:#fff;border:none;border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center}
    .sidebar-hidden{display:none!important}
    .main-panel-expanded{width:100%!important;max-width:100%!important}
        .right-sidebar{position:fixed;top:70px;right:0;width:350px;height:calc(100% - 70px);background:#f8f9fa;border-left:1px solid #ddd;z-index=1500;padding:20px;overflow-y:auto;box-shadow:-2px 0 6px rgba(0,0,0,0.1)}
    /* smooth slide in/out for right sidebar */
    .right-sidebar { transition: transform 220ms ease, visibility 220ms; will-change: transform; }
    .right-sidebar-hidden { transform: translateX(calc(100% + 16px)); visibility: hidden; }

    /* global safety, avoid any element expanding past viewport width */
    html, body, .container-fluid { max-width: 100%; overflow-x: hidden; box-sizing: border-box; }
    /* Ensure brand area is flexible and title text trims if necessary */
    .navbar .navbar-brand { display: flex; align-items: center; gap: 12px; min-width: 0; }
    .navbar .navbar-brand img { max-height: 56px; width: auto; display: block; }
    /* Title text inside brand - constrain and ellipsize (use % not vw to avoid scrollbar issues) */
    .navbar .navbar-brand .title-text {
      display: inline-block;
      max-width: calc(100% - 360px); /* reserve space for controls / toggles */
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      vertical-align: middle;
    }

    /* Sticky buttons panel: place at beginning of sidebar, small top offset */
    .sticky-buttons {
      position: -webkit-sticky;
      position: sticky;
      top: 12px; /* sit close to top of sidebar */
      z-index: 900; /* keep below config area so config can overlay when opened */
      background: linear-gradient(180deg, #ffffff, #f7fbff);
      border: 1px solid rgba(0,0,0,0.06);
      border-radius: 8px;
      padding: 10px;
      box-shadow: 0 6px 18px rgba(15, 45, 80, 0.06);
      margin-bottom: 12px;
      display: block;
      width: 100%;
      box-sizing: border-box;
    }
    .sticky-buttons .button-row { display:flex; gap:8px; align-items:center; justify-content:flex-start; flex-wrap:nowrap; white-space:nowrap; }
    .sticky-buttons .sticky-btn { min-width: 140px; flex: 0 0 auto; }

    /* make sure there is always clearing space below sticky block so later content is not covered */
    .sticky-buttons + hr { margin-top: 10px; border: 0; border-top: 1px solid rgba(0,0,0,0.06); }

  /* config toggle and area: higher stacking and clear spacing so it cannot be overlapped */
  .config-toggle { position: relative; z-index: 1600; display: block; margin-bottom: 6px; margin-top: 8px; }
  /* special styling for the configuration settings area */
  .config-area { display: none; position: relative; z-index: 1700; margin-top: 8px; background: linear-gradient(180deg, #f8fbff, #ffffff); border: 1px solid rgba(3, 102, 214, 0.08); padding: 10px; border-radius: 8px; box-shadow: 0 4px 14px rgba(16,24,40,0.04); }
  .config-area.config-open { display: block !important; z-index: 1700; }

    /* small safety: ensure sidebar panel allows visible overflow so sticky works */
    .sidebar .well, .sidebar { overflow: visible !important; }
  /* dynamic sections hidden by default until user adds a section */
  .dynamic-sections-hidden { display: none !important; }
  ')
                 
      )
      # insert small inline CSS that references the actual namespaced IDs so overflow/z-index rules apply
      ,
      tags$style(HTML(paste0(
        "#", ns("sidebar_panel"), ".sidebar-hidden { display: none !important; width: 0 !important; margin: 0 !important; padding: 0 !important; visibility: hidden !important; }",
        "#", ns("sidebar_panel"), " { transition: width 220ms ease, margin 220ms ease, visibility 220ms; }",
        "#", ns("main_panel"), ".main-panel-expanded { width: 100% !important; max-width: 100% !important; margin-left: 0 !important; padding-left: 12px !important; padding-right: 12px !important; flex: 1 1 auto !important; }",
        "#", ns("main_panel"), ".main-panel-expanded .tab-content, #", ns("main_panel"), ".main-panel-expanded iframe { width: 100% !important; max-width: 100% !important; }",
        "#", ns("main_panel"), ".main-panel-expanded .col-sm-8, #", ns("main_panel"), ".main-panel-expanded .col-md-8, #", ns("main_panel"), ".main-panel-expanded .col-lg-8 { width: 100% !important; flex: 0 0 100% !important; max-width: 100% !important; }",
        "#", ns("right_sidebar"), " { z-index: 1600; }",
        ":root{ --sticky-top: 78px; --sticky-top-mobile: 70px; }",
        "#", ns("sidebar_panel"), " { overflow: visible !important; }",
        "#", ns("sidebar_panel"), " .sticky-buttons { position: -webkit-sticky; position: sticky; top: var(--sticky-top); z-index: 1800; background: linear-gradient(180deg, #ffffff, #f7fbff); box-shadow: 0 6px 18px rgba(15,45,80,0.06); border-radius: 8px; padding: 10px; will-change: transform, top; -webkit-backface-visibility: hidden; backface-visibility: hidden; }",
        "#", ns("sidebar_panel"), " .sticky-buttons .sticky-btn { min-width: 140px; flex: 0 0 auto; display: inline-block; }",
        "@media (max-width: 768px) { ", "#", ns("sidebar_panel"), " .sticky-buttons { position: fixed; top: var(--sticky-top-mobile); right: 12px; width: auto; border-radius: 10px; } }"
      )))
    ),
    # JS fallback: keep sticky-buttons visible by switching to fixed positioning when needed
    tags$script(HTML(paste0("(function(){ var sidebarSel='#", ns("sidebar_panel"), "'; var stickySel = sidebarSel + ' .sticky-buttons'; var ticking=false; function doUpdate(){ var side = document.querySelector(sidebarSel); var s = document.querySelector(stickySel); if(!side || !s) return; var sideRect = side.getBoundingClientRect(); var sRect = s.getBoundingClientRect(); var topOffset = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--sticky-top')) || 78; if(sRect.top < topOffset){ var style = window.getComputedStyle(side); var padLeft = parseFloat(style.paddingLeft) || 0; var padRight = parseFloat(style.paddingRight) || 0; var innerWidth = Math.max(0, sideRect.width - padLeft - padRight); s.style.transition = 'none'; if(!s.classList.contains('sticky-fixed-js')){ s.style.width = innerWidth + 'px'; s.style.boxSizing = 'border-box'; s.style.position = 'fixed'; s.style.zIndex = 1900; s.classList.add('sticky-fixed-js'); } s.style.top = topOffset + 'px'; var left = Math.max(8, sideRect.left + padLeft + 6); s.style.left = left + 'px'; } else { if(s.classList.contains('sticky-fixed-js')){ s.style.position = ''; s.style.top = ''; s.style.left = ''; s.style.zIndex = ''; s.style.width = ''; s.style.boxSizing = ''; s.style.transition = ''; s.classList.remove('sticky-fixed-js'); } } } function requestUpdate(){ if(!ticking){ ticking=true; requestAnimationFrame(function(){ doUpdate(); ticking=false; }); } } window.addEventListener('scroll', requestUpdate, {passive:true}); window.addEventListener('resize', requestUpdate); document.addEventListener('DOMContentLoaded', function(){ setTimeout(requestUpdate,200); }); setTimeout(requestUpdate,400); })();")))
    ,
    tags$script(HTML(paste0("(function(){ var root = document.getElementById(\"", ns('dynamic_navbar'), "\"); if(!root) return; var obs = new MutationObserver(function(m){ try{ var active = root.querySelector('.nav .nav-link.active'); if(active){ var val = active.getAttribute('data-value') || active.getAttribute('data-tabname') || active.getAttribute('data-value'); if(val) Shiny.setInputValue('\"", ns('active_tab'), "\', val, {priority:'event'}); } }catch(e){} }); obs.observe(root, {attributes:true, childList:true, subtree:true}); /* also initialize */ setTimeout(function(){ try{ var a = root.querySelector('.nav .nav-link.active'); if(a){ var v = a.getAttribute('data-value') || a.getAttribute('data-tabname') || a.getAttribute('data-value'); if(v) Shiny.setInputValue('\"", ns('active_tab'), "\', v, {priority:'event'}); } }catch(e){} },300); })();")))
    ,
    actionButton(ns("toggle_sidebar"), label = NULL, icon = icon("bars"), class = "sidebar-toggle-float"),
    actionButton(ns("toggle_right_sidebar"), label = NULL, icon = icon("comments"), class = "right-sidebar-toggle-float"),
    # close buttons use inline onclick to notify the module namespaced input
    fluidRow(
      useShinyjs(),
      sidebarLayout(
        sidebarPanel(
          # Move configuration to the top of the sidebar for better visibility
          div(style = "margin-bottom:12px;",
              actionLink(ns("config_toggle"),
                         label = tagList(icon("cog"), tags$strong(" Configuration settings ")),
                         class = "config-toggle",
                         style = "display:block; margin-bottom:6px; position:relative; z-index:2100;"),
              div(id = ns("config_area"), class = "config-area",
                  downloadButton(ns("save_settings"), "Export settings (.json)", class = "btn btn-secondary"),
                  br(), br(),
                  fileInput(ns("load_settings"), "Import settings (.json)", accept = c(".json")),
                  tags$hr(),
                  selectInput(ns("profiles"), "Saved profiles:", choices = c("(none)"), selected = NULL),
                  textInput(ns("profile_name"), "Profile name (for save):", placeholder = "my-work-profile"),
                  div(style = "display:flex; gap:8px;",
                      actionButton(ns("save_profile"), "Save profile", class = "btn btn-info"),
                      actionButton(ns("load_profile"), "Load profile", class = "btn btn-primary"),
                      actionButton(ns("delete_profile"), "Delete profile", class = "btn btn-danger")                
                  )
              )
          ),
          # Spacer + Sticky action buttons below the configuration area
          hr(style = "margin-top:12px; margin-bottom:10px;"),
          br(),
          div(style = "margin-top:8px; margin-bottom:18px;",
              div(class = "sticky-buttons",
                  div(class = "button-row",
                      actionButton(ns("add_section"), "Add Section +", class = "btn btn-success sticky-btn"),
                      actionButton(ns("render_all_reports"), "Render Reports", class = "btn btn-primary sticky-btn")
                  ),
                  div(class = "button-row", style = "margin-top:8px;",
                      actionButton(ns("test_paths"), "Test All Paths", icon = icon("check-circle"), 
                                   class = "btn btn-info btn-sm sticky-btn"),
                      actionButton(ns("show_examples"), "Show Examples", icon = icon("lightbulb"), 
                                   class = "btn btn-warning btn-sm sticky-btn")
                  ),
                  div(class = "button-row", style = "margin-top:8px;",
                      actionButton(ns("select_all"), "Select All", icon = icon("check-square"), 
                                   class = "btn btn-secondary btn-sm sticky-btn"),
                      actionButton(ns("deselect_all"), "Deselect All", icon = icon("square"), 
                                   class = "btn btn-secondary btn-sm sticky-btn")
                  ),
                  tags$div(style = "height:8px;")
              )
          ),
          hr(),
          
          # IFX Integration Panel
          conditionalPanel(
            condition = sprintf("input['%s'] == true", ns("show_ifx_integration")),
            div(id = ns("ifx_integration_panel"),
                ifx_integration_ui(ns("ifx_module"))
            )
          ),
          
          # Toggle for IFX integration
          div(style = "margin-bottom:12px;",
              checkboxInput(ns("show_ifx_integration"), 
                            label = tagList(icon("briefcase"), strong(" Show IFX Integration")),
                            value = FALSE)
          ),
          
          br(),
          div(id = ns("dynamic_sections"), class = "dynamic-sections-hidden"),
          width = 4,
          id = ns("sidebar_panel")
        ),
        mainPanel(
          navbarPage(
            id = ns("dynamic_navbar"),
            title = "Report previews",
            tabPanel("Welcome", h6("Rendered reports will appear here!"))
          ),
          actionButton(ns('debug_nav_dump'), 'DEBUG: Dump nav DOM', style = 'display:none;'),
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
          choices = c(
            "Local tinyllama (Ollama)" = "tinyllama",
            "OpenAI GPT-4" = "openai-gpt4",
            "OpenAI GPT-3.5" = "openai-gpt3.5",
            "Anthropic Claude 3" = "anthropic-claude3",
            "Google Gemini" = "google-gemini",
            "DeepSeek: R1:8B" = "deepseek-r1:8b"
          ),
          selected = "tinyllama"
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
        uiOutput(ns("chat_debug"), class = "chatbox-debug"),
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
    # track open preview tabs: map uid -> list(title, file)
    rv$open_tabs <- list()
    # Non-reactive snapshot used for safe access outside reactive consumers
    last_sections_snapshot <- list()
    # Chat state
    chat_messages <- reactiveVal(character())
    llm_info <- reactiveValues(model = NULL, token = NULL, connected = FALSE)
    chat_context <- reactive({
      input$chat_context %||% "Introduction"
    })
    
    # deterministic uid generator based on section inputs (fallback simple hash if digest not available)
    make_tab_uid <- function(section) {
      key <- paste0(section$source_path %||% "", "|", section$destination_path %||% "", "|", section$title %||% "", "|", section$author %||% "", "|", section$logo %||% "", "|", section$format %||% "")
      if (requireNamespace("digest", quietly = TRUE)) {
        return(digest::digest(key, algo = "sha1"))
      }
      # simple deterministic fallback
      raw <- charToRaw(key)
      h <- 0L
      for (i in seq_along(raw)) h <- (h * 31L + as.integer(raw[i])) %% 2^31
      sprintf("%08x", h)
    }
    
    observeEvent(input$close_tab, {
      uid <- input$close_tab
      if (is.null(uid) || !nzchar(uid)) return()
      # lookup title for user-friendly notification
      info <- rv$open_tabs[[uid]] %||% list(title = uid, file = file.path("www", paste0(uid, ".html")))
      # remove only the specific tab by uid in this module's navbar
      removeTab("dynamic_navbar", target = uid)
      # delete the corresponding copied file inside www if present
      if (!is.null(info$file)) {
        # info$file is returned by copy_report_to_www (e.g. "Output/report.html") or may be an absolute path
        candidate <- info$file
        if (!startsWith(candidate, "/") && !grepl("^[A-Za-z]:\\\\", candidate)) {
          candidate <- file.path("www", candidate)
        }
        if (file.exists(candidate)) {
          tryCatch(file.remove(candidate), error = function(e) NULL)
        }
      }
      # drop from open_tabs map
      rv$open_tabs[[uid]] <- NULL
      showNotification(paste("Closed and deleted:", info$title), type = "message")
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
    
    # Wire external chat handlers (in chat_module.R)
    # Provide a context_resolver closure so the chat handlers can fetch the selected
    # chapter text from the currently active preview's copied HTML in www/.
    context_resolver <- function(context_key) {
      # context_key corresponds to the selected label/anchor from the dropdown
      sel <- context_key %||% ""
      # determine active preview file from rv$open_tabs
      ots <- rv$open_tabs
      if (length(ots) == 0) return(NULL)
      # prefer the most recently opened tab if no deterministic active input
      uids <- names(ots)
      uid <- tail(uids, 1)
      info <- ots[[uid]]
      if (is.null(info) || is.null(info$file) || !nzchar(info$file)) return(NULL)
      candidate <- info$file
      if (!startsWith(candidate, "/") && !grepl("^[A-Za-z]:\\\\", candidate)) candidate_path <- file.path("www", candidate) else candidate_path <- candidate
      if (dir.exists(candidate_path)) {
        htmls <- list.files(candidate_path, pattern = "\\.html?$", full.names = TRUE)
        if (length(htmls) > 0) candidate_path <- htmls[1]
      }
      if (!file.exists(candidate_path)) return(NULL)
      tryCatch({ extract_section_text(candidate_path, anchor = sel, max_chars = 6000) }, error = function(e) NULL)
    }
    setup_chat_handlers(input, output, session, chat_messages, llm_info, chat_context, context_resolver)
    # Ensure chat (right sidebar) is minimized/hidden on initial load
    session$onFlushed(function() {
      try({
        shinyjs::addClass(selector = paste0("#", ns("right_sidebar")), class = "right-sidebar-hidden")
      }, silent = TRUE)
    }, once = TRUE)
    
    # Update chat_context choices when a preview tab is opened or the active tab changes.
    # rv$open_tabs maps uid -> list(title, file)
    observe({
      # reactive dependency on open_tabs content
      ots <- rv$open_tabs
      # find currently active tab in this module's navbar
      # use a safe JS bridge to ask the browser for active tab id if available
      # Prefer the JS-provided active tab input when available
      active_uid <- NULL
      try({ if (!is.null(input$active_tab) && nzchar(input$active_tab)) active_uid <- input$active_tab }, silent = TRUE)
      # legacy fallback: dynamic_navbar input or last-opened tab
      if (is.null(active_uid) || !nzchar(active_uid)) {
        try({ if (!is.null(input$dynamic_navbar) && nzchar(input$dynamic_navbar)) active_uid <- input$dynamic_navbar }, silent = TRUE)
      }
      if (is.null(active_uid) || !nzchar(active_uid)) {
        if (length(ots) > 0) {
          uids <- names(ots)
          if (length(uids) > 0) active_uid <- tail(uids, 1)
        }
      }
      
      # If still no active tab, clear choices to default set
      if (is.null(active_uid) || !nzchar(active_uid) || is.null(ots[[active_uid]])) {
        # default choices
        default_choices <- c("Introduction", "Methods", "Results")
        try({ updateSelectInput(session, "chat_context", choices = default_choices, selected = default_choices[1]) }, silent = TRUE)
        return(invisible(NULL))
      }
      
      info <- ots[[active_uid]]
      # info$file may be relative like 'Master_report/report.html' or an absolute path
      candidate <- info$file %||% ""
      if (!nzchar(candidate)) {
        try({ updateSelectInput(session, "chat_context", choices = c("Introduction"), selected = "Introduction") }, silent = TRUE)
        return(invisible(NULL))
      }
      # construct path inside app www folder if needed
      if (!startsWith(candidate, "/") && !grepl("^[A-Za-z]:\\\\", candidate)) {
        candidate_path <- file.path("www", candidate)
      } else {
        candidate_path <- candidate
      }
      
      # If the candidate is a directory, look for an index.html or an html file
      if (dir.exists(candidate_path)) {
        htmls <- list.files(candidate_path, pattern = "\\.html?$", full.names = TRUE)
        if (length(htmls) > 0) candidate_path <- htmls[1]
      }
      
      if (!file.exists(candidate_path)) {
        try({ updateSelectInput(session, "chat_context", choices = c("Introduction"), selected = "Introduction") }, silent = TRUE)
        return(invisible(NULL))
      }
      
      # extract TOC choices from the copied html
      toc <- tryCatch(extract_toc_from_html(candidate_path), error = function(e) NULL)
      if (is.null(toc) || length(toc) == 0) {
        # fallback to a minimal set
        fallback <- c("Introduction", "Methods", "Results")
        try({ updateSelectInput(session, "chat_context", choices = fallback, selected = fallback[1]) }, silent = TRUE)
        return(invisible(NULL))
      }
      
      # 'toc' is named vector: values are anchors (without #), names are labels
      # present them to the user as labels and set values to anchors
      choices <- as.character(toc)
      names(choices) <- names(toc)
      try({ updateSelectInput(session, "chat_context", choices = choices, selected = choices[1]) }, silent = TRUE)
    })
    # Dynamic section logic (same as your previous implementation)
    observeEvent(input$add_section, {
      message('DEBUG: add_section clicked')
      # ensure the dynamic sections container is visible when adding a section
      try({ shinyjs::removeClass(selector = paste0('#', ns('dynamic_sections')), class = 'dynamic-sections-hidden') }, silent = TRUE)
      rv$section_count <- rv$section_count + 1
      section_id <- paste0("section_", rv$section_count)
      insertUI(
        selector = paste0("#", ns("dynamic_sections")),
        ui = div(
          id = ns(section_id),
          checkboxInput(ns(paste0(section_id, "_checkbox")), "Include this section", value = TRUE),
          div(
            selectInput(ns(paste0(section_id, "_source_recent")), "Recent Source Paths:",
                       choices = c("(Type or select...)" = "", get_recent_paths("source")),
                       selected = "",
                       width = "100%"),
            textInput(ns(paste0(section_id, "_source")), "Source Folder", 
                     placeholder = "e.g., IFX_2022_2025/01_Administration/",
                     width = "100%")
          ),
          div(
            selectInput(ns(paste0(section_id, "_dest_recent")), "Recent Destination Paths:",
                       choices = c("(Type or select...)" = "", get_recent_paths("destination")),
                       selected = "",
                       width = "100%"),
            textInput(ns(paste0(section_id, "_destination")), "Destination Folder", 
                     placeholder = "e.g., IFX_2022_2025/00_Master_html_file/",
                     width = "100%")
          ),
          textInput(ns(paste0(section_id, "_title")), "Report Title", 
                   placeholder = "e.g., IFX Administration 2022-2026"),
          textInput(ns(paste0(section_id, "_author")), "Author", 
                   placeholder = "Enter Author"),
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
      
      # Add observers for recent path selection
      local({
        sid <- section_id
        observeEvent(input[[paste0(sid, "_source_recent")]], {
          sel <- input[[paste0(sid, "_source_recent")]]
          if (!is.null(sel) && nzchar(sel) && sel != "(Type or select...)") {
            updateTextInput(session, paste0(sid, "_source"), value = sel)
          }
        }, ignoreInit = TRUE)
        
        observeEvent(input[[paste0(sid, "_dest_recent")]], {
          sel <- input[[paste0(sid, "_dest_recent")]]
          if (!is.null(sel) && nzchar(sel) && sel != "(Type or select...)") {
            updateTextInput(session, paste0(sid, "_destination"), value = sel)
          }
        }, ignoreInit = TRUE)
      })
      
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
    
    # IFX Integration Module
    source(file.path("Modules", "ifx_integration.R"), local = TRUE)
    ifx_integration_server("ifx_module", parent_rv = rv, parent_session = session, parent_ns = ns)
    
    # Test All Paths Button
    observeEvent(input$test_paths, {
      sections <- rv$sections
      if (length(sections) == 0) {
        showNotification("No sections configured to test", type = "warning")
        return()
      }
      
      results <- list()
      for (i in seq_along(sections)) {
        section <- sections[[i]]
        section_name <- names(sections)[i]
        
        # Validate source path
        src_validation <- validate_source_path(section$source_path, show_notification = FALSE)
        
        # Validate destination path (just check parent directory exists or can be created)
        dst_ok <- TRUE
        dst_path <- section$destination_path
        if (!is.null(dst_path) && nzchar(dst_path)) {
          dst_parent <- dirname(normalize_path_for_app(dst_path))
          if (!dir.exists(dst_parent)) {
            # Try to create it
            dst_ok <- tryCatch({
              dir.create(dst_parent, recursive = TRUE, showWarnings = FALSE)
              TRUE
            }, error = function(e) FALSE)
          }
        }
        
        # Check logo file
        logo_ok <- TRUE
        if (!is.null(section$logo) && nzchar(section$logo)) {
          logo_ok <- file.exists(section$logo)
        }
        
        results[[i]] <- list(
          section = section_name,
          title = section$title %||% "(No title)",
          source_ok = src_validation$valid,
          source_path = section$source_path %||% "(empty)",
          dest_ok = dst_ok,
          dest_path = dst_path %||% "(empty)",
          logo_ok = logo_ok,
          logo_path = section$logo %||% "(default)",
          all_ok = src_validation$valid && dst_ok && logo_ok
        )
      }
      
      # Show results in modal
      html_results <- lapply(results, function(r) {
        status_icon <- if (r$all_ok) "✅" else "❌"
        paste0(
          "<div style='margin-bottom:15px; padding:10px; border-left:3px solid ", 
          if(r$all_ok) "#28a745" else "#dc3545", ";'>",
          "<strong>", status_icon, " ", r$title, "</strong><br>",
          "<small style='color:#666;'>Section: ", r$section, "</small><br>",
          "<div style='margin-top:5px;'>",
          if (r$source_ok) "✓" else "✗", " Source: <code>", r$source_path, "</code><br>",
          if (r$dest_ok) "✓" else "✗", " Destination: <code>", r$dest_path, "</code><br>",
          if (r$logo_ok) "✓" else "✗", " Logo: <code>", basename(r$logo_path), "</code>",
          "</div>",
          "</div>"
        )
      })
      
      all_passed <- all(sapply(results, function(r) r$all_ok))
      summary_msg <- if (all_passed) {
        "<div style='background:#d4edda; padding:10px; border-radius:5px; margin-bottom:15px;'><strong>✓ All paths are valid!</strong> You can proceed with rendering.</div>"
      } else {
        "<div style='background:#f8d7da; padding:10px; border-radius:5px; margin-bottom:15px;'><strong>⚠ Some paths have issues</strong> - please fix them before rendering.</div>"
      }
      
      showModal(modalDialog(
        title = "Path Test Results",
        size = "l",
        HTML(paste0(summary_msg, paste(html_results, collapse = ""))),
        easyClose = TRUE,
        footer = modalButton("Close")
      ))
    })
    
    # Show Examples Button
    observeEvent(input$show_examples, {
      examples <- get_ifx_example_configs()
      
      example_html <- lapply(examples, function(ex) {
        paste0(
          "<div style='border:1px solid #ddd; padding:15px; margin-bottom:15px; border-radius:8px; background:#f8f9fa;'>",
          "<h5 style='margin-top:0; color:#0366d6;'>", ex$name, "</h5>",
          "<p style='margin:5px 0; color:#666;'>", ex$description, "</p>",
          "<pre style='background:#fff; padding:10px; border-radius:5px; margin-top:10px;'>",
          "Source: ", ex$source, "\n",
          "Destination: ", ex$destination, "\n",
          "Title: ", ex$title, "\n",
          "Author: ", ex$author,
          "</pre>",
          "</div>"
        )
      })
      
      showModal(modalDialog(
        title = HTML("<h3><i class='fa fa-lightbulb'></i> Example Configurations</h3>"),
        size = "l",
        HTML(paste0(
          "<div style='margin-bottom:20px;'>",
          "<p>Here are some real-world examples based on the IFX_2022_2025 folder structure:</p>",
          "</div>",
          paste(example_html, collapse = ""),
          "<hr>",
          "<div style='background:#e7f3ff; padding:15px; border-radius:8px; border-left:4px solid #0366d6;'>",
          "<h5><i class='fa fa-info-circle'></i> General Tips:</h5>",
          "<ul style='margin:10px 0;'>",
          "<li>Use <strong>relative paths</strong> (e.g., 'IFX_2022_2025/01_Administration/') for portability</li>",
          "<li>Use <strong>numbered prefixes</strong> (01_, 02_) for automatic ordering</li>",
          "<li>Keep source files <strong>organized hierarchically</strong></li>",
          "<li><strong>Save profiles</strong> for repeated workflows</li>",
          "<li>Use the <strong>IFX Integration</strong> panel for quick setup</li>",
          "</ul>",
          "</div>"
        )),
        easyClose = TRUE,
        footer = modalButton("Close")
      ))
    })
    
    # Select All Sections
    observeEvent(input$select_all, {
      sections <- rv$sections
      if (length(sections) == 0) {
        showNotification("No sections to select", type = "warning")
        return()
      }
      
      count <- 0
      for (section_id in names(sections)) {
        checkbox_id <- paste0(section_id, "_checkbox")
        if (!is.null(input[[checkbox_id]])) {
          updateCheckboxInput(session, checkbox_id, value = TRUE)
          count <- count + 1
        }
      }
      
      showNotification(
        sprintf("✓ Selected %d section(s)", count),
        type = "message",
        duration = 2
      )
    })
    
    # Deselect All Sections
    observeEvent(input$deselect_all, {
      sections <- rv$sections
      if (length(sections) == 0) {
        showNotification("No sections to deselect", type = "warning")
        return()
      }
      
      count <- 0
      for (section_id in names(sections)) {
        checkbox_id <- paste0(section_id, "_checkbox")
        if (!is.null(input[[checkbox_id]])) {
          updateCheckboxInput(session, checkbox_id, value = FALSE)
          count <- count + 1
        }
      }
      
      showNotification(
        sprintf("✗ Deselected %d section(s)", count),
        type = "warning",
        duration = 2
      )
    })
    
    # Debug: log when Render Reports button clicked (the heavy render logic is in another observer)
    observeEvent(input$render_all_reports, {
      message('DEBUG: render_all_reports clicked')
    }, ignoreInit = TRUE)
    
    # Save / Load settings: create download handler and load uploaded JSON
    output$save_settings <- downloadHandler(
      filename = function() paste0("webknit_settings_", Sys.Date(), ".json"),
      content = function(file) {
        # build config using non-reactive snapshot (safe outside reactive consumer)
        llm_vals <- tryCatch(reactiveValuesToList(llm_info), error = function(e) list())
        cfg <- list(
          llm = list(model = llm_vals$model %||% NULL, token = llm_vals$token %||% NULL),
          sections = last_sections_snapshot %||% list()
        )
        jsonlite::write_json(cfg, path = file, pretty = TRUE, auto_unbox = TRUE)
      }
    )
    
    # Helper: reconstruct dynamic sections UI from a saved sections list
    reconstruct_sections <- function(sections_list) {
      # Remove any existing children under the dynamic container without reading rv$sections
      tryCatch({
        # remove all child nodes inside the dynamic_sections container (safer than reading rv)
        removeUI(selector = paste0("#", ns("dynamic_sections"), " > *"), multiple = TRUE)
      }, error = function(e) {
        # best-effort fallback: try to remove known section ids if present
        #        tryCatch({
        #          if (exists("rv", inherits = FALSE)) {
        #            for (sid in names(rv$sections)) {
        #              tryCatch(removeUI(selector = paste0("#", ns(sid))), error = function(e) NULL)
        #            }
        #          }
        #        }, error = function(e) NULL)
        # avoid reading rv$sections here to prevent reactive-value access outside reactive consumer
        NULL
      })
      
      # reset reactive storage
      rv$sections <- list()
      last_sections_snapshot <<- list()
      rv$section_count <- 0
      
      if (is.null(sections_list) || length(sections_list) == 0) return(invisible(NULL))
      
      # Use a local counter and local_sections list so we don't read rv$sections (reactive) here
      local_count <- 0
      local_sections <- list()
      
      for (saved in sections_list) {
        local_count <- local_count + 1
        section_id <- paste0("section_", local_count)
        
        insertUI(
          selector = paste0("#", ns("dynamic_sections")),
          ui = div(
            id = ns(section_id),
            checkboxInput(ns(paste0(section_id, "_checkbox")), "Include this section", value = !isFALSE(saved$checkbox)),
            div(style = "display:flex; gap:8px; align-items:center;",
                div(style = "flex: 3;", textInput(ns(paste0(section_id, "_source")), "Source Folder", value = saved$original_source %||% saved$source_path, placeholder = "Paste Source path")),
                div(style = "flex: 1;", shinyFiles::shinyDirButton(ns(paste0(section_id, "_source_browse")), "Browse...", "Select source folder"))
            ),
            div(style = "display:flex; gap:8px; align-items:center;",
                div(style = "flex: 3;", textInput(ns(paste0(section_id, "_destination")), "Destination Folder", value = saved$original_destination %||% saved$destination_path, placeholder = "Paste Destination path")),
                div(style = "flex: 1;", shinyFiles::shinyDirButton(ns(paste0(section_id, "_destination_browse")), "Browse...", "Select destination folder"))
            ),
            textInput(ns(paste0(section_id, "_title")), "Report Title", value = saved$title, placeholder = "Enter in format (Title-Subtitle-addition)"),
            textInput(ns(paste0(section_id, "_author")), "Author", value = saved$author, placeholder = "Enter Author"),
            div(
              style = "display: flex; align-items: center; gap: 10px;",
              div(style = "flex: 2;", fileInput(ns(paste0(section_id, "_logo")), "Logo (optional):", accept = c("image/png", "image/jpeg", "image/jpg"))),
              div(style = "flex: 1;", numericInput(ns(paste0(section_id, "_logo_width")), "Width:", value = saved$logo_width %||% 75, min = 10)),
              div(style = "flex: 1;", numericInput(ns(paste0(section_id, "_logo_height")), "Height:", value = saved$logo_height %||% 35, min = 10))
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
              selected = saved$format %||% "rmarkdown::html_document"
            ),
            actionButton(ns(paste0(section_id, "_remove")), "Remove Section -", class = "btn btn-danger"),
            hr()
          )
        )
        
        # attach remove observer for this dynamically created section
        local({
          sid <- section_id
          observeEvent(input[[paste0(sid, "_remove")]], {
            removeUI(selector = paste0("#", ns(sid)))
            rv$sections[[sid]] <- NULL
          }, ignoreInit = TRUE)
        })
        
        # setup shinyFiles directory choosers and observers for restored section
        local({
          sid <- section_id
          tryCatch({
            shinyFiles::shinyDirChoose(input, id = paste0(sid, "_source_browse"), roots = dir_roots, session = session)
          }, error = function(e) NULL)
          tryCatch({
            shinyFiles::shinyDirChoose(input, id = paste0(sid, "_destination_browse"), roots = dir_roots, session = session)
          }, error = function(e) NULL)
          
          observeEvent(input[[paste0(sid, "_source_browse")]], {
            sel <- input[[paste0(sid, "_source_browse")]]
            if (is.null(sel)) return()
            p <- tryCatch(shinyFiles::parseDirPath(dir_roots, sel), error = function(e) NULL)
            if (!is.null(p) && length(p) > 0) updateTextInput(session, paste0(sid, "_source"), value = as.character(p[[1]]))
          }, ignoreInit = TRUE)
          
          observeEvent(input[[paste0(sid, "_destination_browse")]], {
            sel <- input[[paste0(sid, "_destination_browse")]]
            if (is.null(sel)) return()
            p <- tryCatch(shinyFiles::parseDirPath(dir_roots, sel), error = function(e) NULL)
            if (!is.null(p) && length(p) > 0) updateTextInput(session, paste0(sid, "_destination"), value = as.character(p[[1]]))
          }, ignoreInit = TRUE)
        })
        
        # populate a plain list entry for this section (logo file can't be pre-populated into fileInput)
        local_sections[[section_id]] <- list(
          source_path = saved$source_path %||% saved$original_source,
          destination_path = saved$destination_path %||% saved$original_destination,
          title = saved$title,
          author = saved$author,
          logo = saved$logo %||% logo_path,
          logo_width = saved$logo_width %||% 75,
          logo_height = saved$logo_height %||% 35,
          format = saved$format %||% "rmarkdown::html_document",
          checkbox = !isFALSE(saved$checkbox)
        )
      }
      
      # commit local count and assign reactive storage from the plain local list
      rv$section_count <- local_count
      rv$sections <- local_sections
      # update non-reactive snapshot for safe external access
      last_sections_snapshot <<- local_sections
      # ensure the dynamic sections UI is visible when reconstructing from a profile
      try({ shinyjs::removeClass(selector = paste0('#', ns('dynamic_sections')), class = 'dynamic-sections-hidden') }, silent = TRUE)
    }
    
    observeEvent(input$load_settings, {
      f <- input$load_settings
      if (is.null(f) || length(f$datapath) == 0) return()
      cfg <- tryCatch(jsonlite::read_json(f$datapath, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(cfg)) {
        showNotification("Failed to read settings file (invalid JSON)", type = "error")
        return()
      }
      
      # restore llm settings (if present)
      if (!is.null(cfg$llm)) {
        if (!is.null(cfg$llm$model)) {
          updateSelectInput(session, "llm_model", selected = cfg$llm$model)
          llm_info$model <- cfg$llm$model
        }
        if (!is.null(cfg$llm$token)) {
          updateTextInput(session, "llm_token", value = cfg$llm$token)
          llm_info$token <- cfg$llm$token
        }
      }
      
      # Reconstruct dynamic sections immediately from loaded config
      reconstruct_sections(cfg$sections %||% list())
      showNotification("Settings loaded and sections reconstructed", type = "message")
    })
    
    # Profile directory helpers
    profile_dir <- file.path(path.expand('~'), '.webknit')
    if (!dir.exists(profile_dir)) dir.create(profile_dir, recursive = TRUE, showWarnings = FALSE)
    last_settings_file <- file.path(profile_dir, 'last_settings.json')
    
    list_profiles <- function() {
      js <- list.files(profile_dir, pattern = '\\.(json)$', full.names = TRUE)
      names(js) <- basename(js)
      js
    }
    
    # populate profiles select on start
    observe({
      profs <- list_profiles()
      choices <- c('(none)', basename(profs))
      updateSelectInput(session, "profiles", choices = choices, selected = ifelse(length(choices) > 1, choices[2], '(none)'))
    })
    
    # Save profile button writes to ~/.webknit/<name>.json
    observeEvent(input$save_profile, {
      name <- input$profile_name
      if (is.null(name) || !nzchar(name)) {
        showNotification('Enter a profile name first', type = 'error')
        return()
      }
      target <- file.path(profile_dir, paste0(name, '.json'))
      # use non-reactive snapshot for saving outside reactive consumer
      cfg <- list(llm = list(model = llm_info$model, token = llm_info$token), sections = last_sections_snapshot %||% list())
      tryCatch({
        jsonlite::write_json(cfg, path = target, pretty = TRUE, auto_unbox = TRUE)
        showNotification(paste('Profile saved to', target), type = 'message')
        # refresh list
        profs <- list_profiles()
        choices <- c('(none)', basename(profs))
        updateSelectInput(session, "profiles", choices = choices, selected = basename(target))
      }, error = function(e) showNotification(paste('Failed to save profile:', e$message), type = 'error'))
    })
    
    # Load profile
    observeEvent(input$load_profile, {
      sel <- input$profiles
      if (is.null(sel) || sel == '(none)') {
        showNotification('Select a profile to load', type = 'error')
        return()
      }
      path <- file.path(profile_dir, sel)
      if (!file.exists(path)) { showNotification('Profile file missing', type = 'error'); return() }
      cfg <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE), error = function(e) NULL)
      if (is.null(cfg)) { showNotification('Failed to read profile', type = 'error'); return() }
      # restore llm/settings
      if (!is.null(cfg$llm)) {
        if (!is.null(cfg$llm$model)) { updateSelectInput(session, 'llm_model', selected = cfg$llm$model); llm_info$model <- cfg$llm$model }
        if (!is.null(cfg$llm$token)) { updateTextInput(session, 'llm_token', value = cfg$llm$token); llm_info$token <- cfg$llm$token }
      }
      # Ensure dynamic sections UI is visible, then reconstruct sections immediately
      try({ shinyjs::removeClass(selector = paste0('#', ns('dynamic_sections')), class = 'dynamic-sections-hidden') }, silent = TRUE)
      reconstruct_sections(cfg$sections %||% list())
      showNotification('Profile loaded and sections reconstructed', type = 'message')
    })
    
    # Delete profile
    observeEvent(input$delete_profile, {
      sel <- input$profiles
      if (is.null(sel) || sel == '(none)') { showNotification('Select a profile to delete', type = 'error'); return() }
      path <- file.path(profile_dir, sel)
      if (!file.exists(path)) { showNotification('Profile file missing', type = 'error'); return() }
      ok <- tryCatch({ file.remove(path); TRUE }, error = function(e) FALSE)
      if (isTRUE(ok)) {
        showNotification('Profile deleted', type = 'message')
        profs <- list_profiles(); choices <- c('(none)', basename(profs)); updateSelectInput(session, 'profiles', choices = choices, selected = '(none)')
      } else showNotification('Failed to delete profile', type = 'error')
    })
    
    # Autosave on session end: persist last settings
    session$onSessionEnded(function() {
      # persist llm and last_sections_snapshot (avoid reactive access here)
      llm_vals <- tryCatch(reactiveValuesToList(llm_info), error = function(e) list())
      cfg <- list(
        llm = list(
          model = llm_vals$model %||% NULL,
          token = llm_vals$token %||% NULL
        ),
        sections = last_sections_snapshot %||% list()
      )
      tryCatch(jsonlite::write_json(cfg, path = last_settings_file, pretty = TRUE, auto_unbox = TRUE), error = function(e) NULL)
    })
    
    # Autoload last settings if present -- read saved config but DO NOT apply sections automatically.
    session$onFlushed(function() {
      if (file.exists(last_settings_file)) {
        cfg <- tryCatch(jsonlite::read_json(last_settings_file, simplifyVector = TRUE), error = function(e) NULL)
        if (!is.null(cfg) && !is.null(cfg$llm)) {
          if (!is.null(cfg$llm$model)) { llm_info$model <- cfg$llm$model }
          if (!is.null(cfg$llm$token)) { llm_info$token <- cfg$llm$token }
        }
        # Store saved sections into last_sections_snapshot so user can load them explicitly
        if (!is.null(cfg$sections) && length(cfg$sections) > 0) {
          last_sections_snapshot <<- cfg$sections
        }
        # Do not modify rv$sections or reconstruct UI here; leave input UI minimized until user acts
        rv$sections <- list()
      }
    }, once = TRUE)
    
    # Restore UI button: reconstruct dynamic UI from what's currently in rv$sections
    
    
    # Toggle configuration area visibility
    observeEvent(input$config_toggle, {
      # toggle the config-open class on the namespaced element so CSS controls visibility/z-index
      shinyjs::toggleClass(selector = paste0("#", ns("config_area")), class = "config-open")
    }, ignoreInit = TRUE)
    
    # Synchronize inputs with reactiveValues
    observe({
      # React to changes in rv$sections so newly inserted UI elements are discovered.
      # We deliberately do NOT isolate here because we want this observer to rerun when
      # a new section is added (rv$sections changes) so it can register dependencies on
      # the newly created input elements. To avoid a tight reactive loop we only assign
      # back to rv$sections when the content actually differs.
      sections <- rv$sections
      for (section_id in names(sections)) {
        if (!is.null(sections[[section_id]])) {
          # Get the current inputs
          source_path <- input[[paste0(section_id, "_source")]]
          destination_path <- input[[paste0(section_id, "_destination")]]
          
          print(paste0("This is source path:", source_path))
          print(paste0("This is destination path:", destination_path))
          
          # Convert paths using the updated convert_ishare_path() function
          paths_source <- convert_ishare_path(source_path)
          paths_destination <- convert_ishare_path(destination_path)
          
          # Store both original and converted paths in the local sections copy
          sections[[section_id]]$original_source <- paths_source$original_path
          sections[[section_id]]$converted_source <- paths_source$converted_path
          sections[[section_id]]$original_destination <- paths_destination$original_path
          sections[[section_id]]$converted_destination <- paths_destination$converted_path
          
          # Debugging: Print stored paths
          print(paste("Original Source Path:", sections[[section_id]]$original_source))
          print(paste("Converted Source Path:", sections[[section_id]]$converted_source))
          print(paste("Original Destination Path:", sections[[section_id]]$original_destination))
          print(paste("Converted Destination Path:", sections[[section_id]]$converted_destination))
          
          # Update local sections with converted paths
          sections[[section_id]]$source_path <- paths_source$converted_path
          sections[[section_id]]$destination_path <- paths_destination$converted_path
          
          # Update other inputs in local sections
          sections[[section_id]]$title <- input[[paste0(section_id, "_title")]]
          sections[[section_id]]$author <- input[[paste0(section_id, "_author")]]
          sections[[section_id]]$logo <- if (!is.null(input[[paste0(section_id, "_logo")]])) {
            input[[paste0(section_id, "_logo")]]$datapath
          } else {
            logo_path # Default logo path if no file is uploaded
          }
          sections[[section_id]]$logo_width <- input[[paste0(section_id, "_logo_width")]]
          sections[[section_id]]$logo_height <- input[[paste0(section_id, "_logo_height")]]
          sections[[section_id]]$format <- input[[paste0(section_id, "_format")]]
          sections[[section_id]]$checkbox <- input[[paste0(section_id, "_checkbox")]]
          
          # print("Debug: Contents of local sections before updating rv$sections:")
          # print(sections)
        }
      }
      # Update rv$sections only if the 'sections' content actually changed to avoid
      # retriggering this observer unnecessarily.
      if (!identical(rv$sections, sections)) {
        rv$sections <- sections
      }
      # also update non-reactive snapshot so external handlers can read it safely
      last_sections_snapshot <<- sections
    })
    
    # Render all reports when "Render Reports" button is clicked (same as before)
    observeEvent(input$render_all_reports, {
      # Read current inputs at render time to ensure we use the latest user edits
      sections_for_render <- rv$sections
      for (section_id in names(sections_for_render)) {
        if (!is.null(sections_for_render[[section_id]])) {
          # pull live inputs for this section (ensures recent changes are used)
          src <- input[[paste0(section_id, "_source")]]
          dst <- input[[paste0(section_id, "_destination")]]
          sections_for_render[[section_id]]$original_source <- convert_ishare_path(src)$original_path
          sections_for_render[[section_id]]$converted_source <- convert_ishare_path(src)$converted_path
          sections_for_render[[section_id]]$original_destination <- convert_ishare_path(dst)$original_path
          sections_for_render[[section_id]]$converted_destination <- convert_ishare_path(dst)$converted_path
          sections_for_render[[section_id]]$source_path <- sections_for_render[[section_id]]$converted_source
          sections_for_render[[section_id]]$destination_path <- sections_for_render[[section_id]]$converted_destination
          sections_for_render[[section_id]]$title <- input[[paste0(section_id, "_title")]]
          sections_for_render[[section_id]]$author <- input[[paste0(section_id, "_author")]]
          sections_for_render[[section_id]]$logo <- if (!is.null(input[[paste0(section_id, "_logo")]])) input[[paste0(section_id, "_logo")]]$datapath else sections_for_render[[section_id]]$logo %||% logo_path
          sections_for_render[[section_id]]$logo_width <- input[[paste0(section_id, "_logo_width")]]
          sections_for_render[[section_id]]$logo_height <- input[[paste0(section_id, "_logo_height")]]
          sections_for_render[[section_id]]$format <- input[[paste0(section_id, "_format")]]
          sections_for_render[[section_id]]$checkbox <- input[[paste0(section_id, "_checkbox")]]
        }
      }
      
      withProgress(message = "Rendering reports...", value = 0, {
        num_sections <- length(names(sections_for_render))
        sections_to_render <- sum(sapply(sections_for_render, function(s) isTRUE(s$checkbox)))
        progress_step <- 1 / max(sections_to_render, 1) # Avoid division by zero
        current_section <- 0
        
        for (section_id in names(sections_for_render)) {
          section <- sections_for_render[[section_id]]
          if (!is.null(section) && isTRUE(section$checkbox)) {
            
            # Build tolerant local path/title/author vars from multiple possible keys
            original_src <- (
              section$original_source %||% section$source_path %||% section$converted_source %||% ""
            )
            converted_dst <- (
              section$converted_destination %||% section$destination_path %||% section$original_destination %||% ""
            )
            title_val <- section$title %||% ""
            author_val <- section$author %||% ""
            
            # Debugging: Print resolved values
            print(paste("Resolved original_src:", original_src))
            print(paste("Resolved converted_dst:", converted_dst))
            print(paste("Resolved title:", title_val))
            print(paste("Resolved author:", author_val))
            
            # Validate inputs using the resolved local variables
            if (!nzchar(trimws(as.character(original_src))) ||
                !nzchar(trimws(as.character(converted_dst))) ||
                !nzchar(trimws(as.character(title_val))) ||
                !nzchar(trimws(as.character(author_val)))) {
              showNotification(paste0("Error: Missing inputs in section '", section_id, "'. Please ensure Source, Destination, Title and Author are filled."), type = "error")
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
            current_section <- current_section + 1
            incProgress(progress_step, 
                       detail = sprintf("[%d/%d] Rendering: %s", 
                                      current_section, sections_to_render, title_val))
            
            # Log the rendering process for debugging
            print(paste("Rendering report for section:", section_id))
            
            # Use the resolved local path variables for rendering
            original_src_path <- as.character(original_src)
            converted_src_path <- as.character(section$converted_source %||% section$source_path %||% "")
            original_dstn_path <- as.character(section$original_destination %||% section$destination_path %||% "")
            converted_dstn_path <- as.character(converted_dst %||% "")
            
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
                # create uid based on section inputs so identical titles with different inputs get unique tab values
                uid <- make_tab_uid(section)
                # keep the rendered HTML filename identical to the sanitized title (no UID suffix)
                report_filename <- paste0(sanitized_title, ".html")
                report_filepath <- file.path(section$destination_path, report_filename)
                
                # ensure destination exists
                dir_create(section$destination_path)
                dir_create("www")
                
                # copy the shared css files into the report output folder so the Rmd will find them by basename
                tryCatch({
                  file.copy(styles_css_path, file.path(section$destination_path, styles_css_path), overwrite = TRUE)
                }, error = function(e) message("Failed to copy styles.css to output dir: ", e$message))
                tryCatch({
                  file.copy(bootstrap_css_path, file.path(section$destination_path, bootstrap_css_path), overwrite = TRUE)
                }, error = function(e) message("Failed to copy bootstrapMint.css to output dir: ", e$message))
                
                # Debug prints
                if (isTRUE(verbose)) {
                  message("Rendering to: ", report_filepath)
                  message("Source folder (assets): ", section$source_path)
                }
                
                # Validate source path before rendering
                source_validation <- validate_source_path(section$source_path)
                if (!source_validation$valid) {
                  stop(sprintf(
                    "Invalid source path for '%s':\n%s\n\nSuggestion: %s",
                    section$title,
                    source_validation$error,
                    source_validation$suggestion
                  ))
                }
                
                # Normalize destination path
                normalized_dest <- normalize_path_for_app(section$destination_path)
                if (is.null(normalized_dest)) {
                  stop(sprintf(
                    "Invalid destination path for '%s': %s",
                    section$title,
                    section$destination_path
                  ))
                }
                
                # Render using the exact report_filename into destination_path
                rmarkdown::render(
                  input = rmd_file,
                  output_file = report_filename,          # exact filename
                  output_dir  = section$destination_path, # exact folder
                  params = list(
                    original_src_path = as.character(original_src),
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
                
                # Save successful paths to recent history
                save_recent_path(section$source_path, "source")
                save_recent_path(section$destination_path, "destination")
                
                # confirm rendered file exists
                if (!file.exists(report_filepath)) {
                  stop("Rendered HTML not found at: ", report_filepath, ". Files in destination: ",
                       paste(list.files(section$destination_path, pattern = "\\.html?$", full.names = TRUE), collapse = ", "))
                }
                
                # Determine which source folder to copy: prefer converted_source (usable path) if it exists,
                # otherwise fall back to original_source, and finally the report output dir.
                src_to_copy <- NULL
                if (!is.null(section$converted_source) && nzchar(section$converted_source) && dir.exists(section$converted_source)) {
                  src_to_copy <- section$converted_source
                } else if (!is.null(section$original_source) && nzchar(section$original_source) && dir.exists(section$original_source)) {
                  src_to_copy <- section$original_source
                } else if (!is.null(section$source_path) && nzchar(section$source_path) && dir.exists(section$source_path)) {
                  src_to_copy <- section$source_path
                } else {
                  src_to_copy <- dirname(report_filepath)
                }
                
                # Copy rendered report + assets -> www; pass the chosen source folder so original assets are preserved
                iframe_src <- copy_report_to_www(
                  report_path   = report_filepath,
                  source_folder = src_to_copy,
                  www_folder    = "www",
                  verbose       = TRUE
                )
                
                if (is.na(iframe_src) || !nzchar(iframe_src)) {
                  stop("copy_report_to_www failed to prepare preview for: ", report_filepath)
                }
                
                # Only append the preview tab after successful copy; use returned path
                # generate uid for this report and use it for the tab value (do not change filename)
                # iframe_src already contains the copied path relative to www
                iframe_src_final <- iframe_src
                # show human title with a short UID suffix so users can distinguish duplicates
                short_uid <- substr(uid, 1, 8)
                # Build the tab title including a close button that directly notifies this module's namespaced close input
                close_onclick <- sprintf("Shiny.setInputValue('%s', '%s', {priority:'event'}); return false;", ns("close_tab"), uid)
                # Use uid as the tab value to ensure uniqueness (avoids cross-tab collisions)
                tab_value <- uid
                # Close button keeps uid in data attribute; onclick will notify the module's namespaced input
                display_title <- tagList(
                  section$title,
                  tags$span(style = "color:#666;margin-left:6px;font-size:0.9em;", paste0("(", short_uid, ")")),
                  tags$a(href = '#', `data-tabname` = uid, title = 'Close preview', style = 'margin-left:8px; text-decoration:none; color:inherit;', onclick = close_onclick, icon('times'))
                )
                
                message(sprintf("Appending tab uid=%s title=%s", uid, section$title))
                appendTab(
                  inputId = "dynamic_navbar",
                  tabPanel(
                    title = display_title,
                    value = tab_value,
                    tags$iframe(
                      src = iframe_src_final,
                      width = "100%",
                      height = "750px",
                      frameborder = "0"
                    )
                  ),
                  select = TRUE
                )
                # ask the browser to dump the nav/tab DOM so we can see if the tab was created client-side
                tryCatch({ session$sendCustomMessage('debug-nav', list(nav = paste0('#', ns('dynamic_navbar'), ' .nav'), content = paste0('#', ns('dynamic_navbar'), ' .tab-content'), uid = uid)) }, error = function(e) NULL)
                # ensure the newly appended tab is selected
                tryCatch({
                  message(sprintf("Attempting to select tab uid=%s", uid))
                  updateTabsetPanel(session, inputId = "dynamic_navbar", selected = uid)
                  message(sprintf("Selected tab uid=%s", uid))
                }, error = function(e) {
                  message(sprintf("updateTabsetPanel error for uid=%s: %s", uid, e$message))
                  showNotification(paste("Tab selection failed:", e$message), type = "error")
                })
                # record mapping for cleanup and notifications
                # record the actual file path used for the iframe (returned by copy_report_to_www)
                rv$open_tabs[[uid]] <- list(title = section$title, file = iframe_src_final)
                # only notify success after tab appended and selected
                showNotification(paste0("Report successfully rendered: ", section$title), type = "message")
              },
              error = function(e) {
                showNotification(paste0("Error rendering report: ", e$message), type = "error")
              }
            )
            gc() # Clean up memory
          }
        }
      })
      
      # update reactive storage and snapshot with the final values used for rendering
      if (!identical(rv$sections, sections_for_render)) rv$sections <- sections_for_render
      last_sections_snapshot <<- sections_for_render
    })
  })
}


# Main UI
ui <- navbarPage(
  tags$head(
    useShinyjs(),
    # existing tab-close handler plus toggle / night-mode styles
    # global close handler removed; module-scoped handlers are registered inside reportTabUI
    tags$style(HTML("
      /* Toggle switch */
      .toggle-switch { position: relative; display: inline-block; width: 56px; height: 30px; margin: 10px 12px; vertical-align: middle; }
      .toggle-switch input { opacity: 0; width: 0; height: 0; }
      .toggle-switch .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background: #d9ead3; transition: .25s; border-radius: 20px; }
      .toggle-switch .slider:before { position: absolute; content: \"\"; height: 24px; width: 24px; left: 3px; bottom: 3px; background: white; transition: .25s; border-radius: 50%; box-shadow: 0 1px 3px rgba(0,0,0,0.3); }
      .toggle-switch input:checked + .slider { background: #999999; }
      .toggle-switch input:focus + .slider { box-shadow: 0 0 2px rgba(33,150,243,0.6); }
      .toggle-switch input:checked + .slider:before { transform: translateX(26px); }

      /* Night mode */
      body.night-mode { background: #444444 !important; color: #e6eef8 !important; }
      .navbar.night-mode, .navbar { background-color: #444444 !important; border-color: #0b1220 !important; }
      .navbar .navbar-brand, .navbar .nav, .navbar a { color: #e6eef8 !important; }
      .main, .container, .content { color: inherit; background: transparent; }
      /* Make iframe previews match dark background when night-mode is active (basic) */
      body.night-mode iframe { background: #444444; color: #e6eef8; }

      /* Small adjustments to ensure toggle aligns nicely with header */
      .navbar .toggle-switch { margin-top: 12px; margin-bottom: 12px; }
    "))
  ),
  title = tagList(
    div(style = "display:flex; flex-direction:column; align-items:flex-start; gap:8px;",
        div(style = "display:flex; align-items:center; gap:10px;",
            img(src = basename(baya_weaver_path), height = "80px", style = "margin-right: 20px;"),
            span(style = "font-size:20px; font-weight:600;", "Web-page knitter")
        ),
        # toggle placed directly under the title
        div(class = "toggle-switch", style = "margin-left:0; margin-right: 20px;margin-top: 0px;",
            tags$input(id = "toggle_night_view", type = "checkbox"),
            tags$label(class = "slider", `for` = "toggle_night_view")
        )
    ),
  ),
  theme = bslib::bs_theme(version = 5, bootswatch = "minty"),
  tabPanel(
    "Individual Reports",
    fluidPage(
      #actionButton("toggle_sidebar", label = NULL, icon = icon("bars"), class = "sidebar-toggle-float"),
      #actionButton("toggle_right_sidebar", label = NULL, icon = icon("bars"), class = "right-sidebar-toggle-float"),
      useShinyjs(),
      #tags$head(
      #  tags$link(rel = "stylesheet", type = "text/css", href = basename(styles_css_path)),
      #  tags$link(rel = "stylesheet", type = "text/css", href = basename(bootstrap_css_path))
      # sticky style moved to www/styles.css (externalized for caching and easier overrides)
      #),
      reportTabUI("individual")
    )
  ),
  tabPanel(
    "Master Report",
    fluidPage(
      useShinyjs(),
      #tags$head(
      #  tags$link(rel = "stylesheet", type = "text/css", href = basename(styles_css_path)),
      # tags$link(rel = "stylesheet", type = "text/css", href = basename(bootstrap_css_path))
      #),
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
  # debug helper: when the hidden debug button is pressed, ask the browser to dump the dynamic_navbar DOM
  observeEvent(input$debug_request_nav, {
    try({
      session$sendCustomMessage('debug-nav', list(nav = paste0('#', NS('individual')('dynamic_navbar'), ' .nav'), content = paste0('#', NS('individual')('dynamic_navbar'), ' .tab-content')))
    }, silent = TRUE)
  })
}

options(shiny.port = 4846)
shinyApp(ui = ui, server = server, onStart = onStart)
