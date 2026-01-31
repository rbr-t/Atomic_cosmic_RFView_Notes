# Test script to exercise send_llm_prompt from chat_module.R
# It sources app.R to ensure helper functions are available and chat_module is loaded.

source('app.R')

# construct a minimal environment to call send_llm_prompt defined inside setup_chat_handlers
# Since send_llm_prompt is local to observeEvent in setup_chat_handlers, we can't call it directly.
# Instead, we will mimic the same helper logic here by copying the function body.

send_llm_prompt_local <- function(model, token, prompt, timeout_sec = 10) {
  rtrim <- function(x) sub("/+$", "", x)
  parse_resp_text <- function(txt) {
    if (is.null(txt) || !nzchar(txt)) return(NULL)
    resp <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
    if (is.null(resp)) return(NULL)
    if (is.list(resp)) {
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

  # Try dummy endpoint
  endpoints <- c(token, paste0(rtrim(token), '/api/chat'))
  for (ep in endpoints) {
    res <- tryCatch(httr::POST(ep, body = list(prompt = prompt), encode = 'json', httr::timeout(timeout_sec)), error = function(e) NULL)
    if (!is.null(res) && httr::status_code(res) %in% c(200,201)) {
      txt <- httr::content(res, as = 'text')
      parsed <- parse_resp_text(txt)
      if (!is.null(parsed)) return(parsed)
    }
  }
  return(NULL)
}

cat('Testing send_llm_prompt_local against http://127.0.0.1:8001\n')
resp <- send_llm_prompt_local('deepseek', 'http://127.0.0.1:8001', 'Hello from test')
cat('Response:', resp, '\n')
