#!/usr/bin/env Rscript
library(httr)
library(jsonlite)

rtrim <- function(x) sub("/+$", "", x)

parse_resp_text <- function(txt) {
  if (is.null(txt) || !nzchar(txt)) return(NULL)
  resp <- tryCatch(fromJSON(txt), error = function(e) NULL)
  if (is.null(resp)) return(NULL)
  if (is.list(resp)) {
    if (!is.null(resp$result)) return(resp$result)
    if (!is.null(resp$data) && !is.null(resp$data$text)) return(resp$data$text)
    if (!is.null(resp$data) && length(resp$data) >= 1 && !is.null(resp$data[[1]]$text)) return(resp$data[[1]]$text)
    if (!is.null(resp$message) && !is.null(resp$message$content)) return(resp$message$content)
    if (!is.null(resp$choices) && length(resp$choices) >= 1) {
      ch <- resp$choices[[1]]
      if (!is.null(ch$message) && !is.null(ch$message$content)) return(ch$message$content)
      if (!is.null(ch$text)) return(ch$text)
    }
    if (!is.null(resp$output) && !is.null(resp$output$text)) return(resp$output$text)
    if (!is.null(resp$outputs) && length(resp$outputs) >= 1) {
      out <- resp$outputs[[1]]
      if (!is.null(out$text)) return(out$text)
      if (!is.null(out$content)) return(out$content)
    }
    if (!is.null(resp$response)) return(resp$response)
    if (!is.null(resp$text)) return(resp$text)
  }
  return(NULL)
}

send_llm_prompt <- function(model, token, prompt, timeout_sec = 30) {
  attempts <- list()
  record_attempt <- function(endpoint, status = NA, body = NULL) {
    attempts[[length(attempts) + 1]] <<- list(endpoint = endpoint, status = status, body = if (!is.null(body)) substr(body, 1, 200) else NULL)
  }

  # Ollama (not used for this test unless model asks for it)
  if (!is.null(token) && grepl('^http://127.0.0.1:11434', token) && (tolower(model) == 'tinyllama' || grepl('ollama', tolower(model)))) {
    endpoint <- paste0(rtrim(token), '/api/chat')
    err_txt <- NULL
    res <- tryCatch({
      POST(url = endpoint, body = list(model = 'tinyllama', messages = list(list(role = 'user', content = prompt))), encode = 'json', timeout(timeout_sec))
    }, error = function(e) { err_txt <<- paste0('ERROR: ', e$message); NULL })
    st <- if (!is.null(res)) status_code(res) else NA
    txt <- if (!is.null(res)) content(res, as = 'text') else err_txt
    record_attempt(endpoint, st, txt)
    if (!is.null(res) && st == 200) return(list(text = parse_resp_text(txt), debug = list(attempts = attempts)))
    return(list(text = NULL, debug = list(attempts = attempts)))
  }

  # DeepSeek adapter
  if (!is.null(model) && tolower(model) == 'deepseek-r1:8b') {
    ds_auth <- NULL
    ds_base <- token
    if (!is.null(token) && grepl('\\|', token)) {
      pparts <- strsplit(token, '\\|', fixed = TRUE)[[1]]
      ds_base <- pparts[1]
      if (length(pparts) >= 2) ds_auth <- pparts[2]
    }
    ds_eps <- c()
    if (!is.null(ds_base) && nzchar(ds_base) && grepl('^https?://', ds_base)) {
      ds_eps <- c(ds_eps, ds_base)
      ds_eps <- c(ds_eps, paste0(rtrim(ds_base), '/api/generate'))
      ds_eps <- c(ds_eps, paste0(rtrim(ds_base), '/v1/generate'))
      ds_eps <- c(ds_eps, paste0(rtrim(ds_base), '/v1/outputs'))
    }
    if (length(ds_eps) > 0) {
      ds_bodies <- list(list(input = prompt), list(prompt = prompt), list(text = prompt))
      for (ep in ds_eps) {
        for (b in ds_bodies) {
          headers <- if (!is.null(ds_auth)) add_headers(.headers = list(Authorization = ifelse(grepl('^Bearer ', ds_auth), ds_auth, paste('Bearer', ds_auth)))) else NULL
          err_txt <- NULL
          res <- tryCatch({
            if (!is.null(headers)) POST(url = ep, body = b, encode = 'json', headers, timeout(timeout_sec)) else POST(url = ep, body = b, encode = 'json', timeout(timeout_sec))
          }, error = function(e) { err_txt <<- paste0('ERROR: ', e$message); NULL })
          st <- if (!is.null(res)) status_code(res) else NA
          txt <- if (!is.null(res)) content(res, as = 'text') else err_txt
          record_attempt(ep, st, txt)
          if (!is.null(res) && st %in% c(200, 201)) {
            parsed <- parse_resp_text(txt)
            if (!is.null(parsed)) return(list(text = parsed, debug = list(attempts = attempts)))
          }
        }
      }
    }
  }

  # Generic endpoints
  auth_header <- NULL
  endpoint_base <- token
  if (!is.null(token) && grepl('\\|', token)) {
    parts <- strsplit(token, '\\|', fixed = TRUE)[[1]]
    endpoint_base <- parts[1]
    if (length(parts) >= 2) auth_header <- parts[2]
  }
  endpoints <- c()
  if (!is.null(endpoint_base) && nzchar(endpoint_base) && grepl('^https?://', endpoint_base)) {
    endpoints <- c(endpoints, endpoint_base)
    endpoints <- c(endpoints, paste0(rtrim(endpoint_base), '/api/chat'))
    endpoints <- c(endpoints, paste0(rtrim(endpoint_base), '/v1/chat/completions'))
    endpoints <- c(endpoints, paste0(rtrim(endpoint_base), '/v1/completions'))
  }
  if (length(endpoints) == 0) return(list(text = NULL, debug = list(attempts = attempts)))

  bodies <- list(list(messages = list(list(role = 'user', content = prompt))), list(input = prompt), list(prompt = prompt), list(prompt = prompt, model = model))

  for (ep in endpoints) {
    for (b in bodies) {
      headers <- if (!is.null(auth_header)) add_headers(.headers = list(Authorization = ifelse(grepl('^Bearer ', auth_header), auth_header, paste('Bearer', auth_header)))) else NULL
      err_txt <- NULL
      res <- tryCatch({
        if (!is.null(headers)) POST(url = ep, body = b, encode = 'json', headers, timeout(timeout_sec)) else POST(url = ep, body = b, encode = 'json', timeout(timeout_sec))
      }, error = function(e) { err_txt <<- paste0('ERROR: ', e$message); NULL })
      st <- if (!is.null(res)) status_code(res) else NA
      txt <- if (!is.null(res)) content(res, as = 'text') else err_txt
      record_attempt(ep, st, txt)
      if (!is.null(res) && st %in% c(200,201)) {
        parsed <- parse_resp_text(txt)
        if (!is.null(parsed)) return(list(text = parsed, debug = list(attempts = attempts)))
      }
    }
  }
  return(list(text = NULL, debug = list(attempts = attempts)))
}

# Run the programmatic test against the local dummy server
res <- send_llm_prompt('deepseek', 'http://127.0.0.1:8001', 'Hello from programmatic test', timeout_sec = 5)
cat('--- Parsed Text ---\n')
print(res$text)
cat('\n--- Attempts ---\n')
cat(toJSON(res$debug$attempts, pretty = TRUE, auto_unbox = TRUE))
cat('\n')
