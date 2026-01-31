# Chat handlers moved out of app.R to keep UI placement unchanged.
# Expects to be called from inside a module server with the module's input/output/session
# chat_messages: reactiveVal holding chat history
# llm_info: reactiveValues holding model/token/connected
# chat_context: reactive expression returning the selected context

setup_chat_handlers <- function(input, output, session, chat_messages, llm_info, chat_context, context_resolver = NULL) {
  # ensure the null-coalescing helper is available even if not defined elsewhere
  if (!exists("%||%", mode = "function")) {
    `%||%` <- function(a, b) if (!is.null(a)) a else b
  }
  # llm connect logic
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
    # load_chat_history is defined in app.R; be defensive in case it's not available in this scope.
    if (exists("load_chat_history", mode = "function", envir = globalenv())) {
      # call the project's helper from the global environment and guard against errors
      hist <- tryCatch({
        get("load_chat_history", envir = globalenv())(chat_context())
      }, error = function(e) {
        NULL
      })
      if (!is.null(hist) && is.character(hist)) {
        chat_messages(hist)
      } else {
        chat_messages(character())
      }
    } else {
      # fallback to empty history
      chat_messages(character())
    }
    output$chatbox_messages <- renderUI({
      HTML(paste(chat_messages(), collapse = "<br>"))
    })
  })
  
  # Send chat message
  observeEvent(input$chatbox_send, {
    msg <- input$chatbox_input
    if (!is.null(msg) && nzchar(msg)) {
      new_history <- c(chat_messages(), paste0("You: ", msg))
      chat_messages(new_history)
      updateTextInput(session, "chatbox_input", value = "")
      
      # If connected to an LLM endpoint, send prompt and get response.
      # This uses a small helper that tries a few common endpoints/bodies and
      # extracts text from common response shapes. It keeps the Ollama
      # behavior but adds a "deepseek"/generic HTTP option.
      send_llm_prompt <- function(model, token, prompt, timeout_sec = 30) {
        # small helpers
        rtrim <- function(x) sub("/+$", "", x)
        parse_resp_text <- function(txt) {
          if (is.null(txt) || !nzchar(txt)) return(NULL)
          resp <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
          if (is.null(resp)) return(NULL)
          # common shapes
          if (is.list(resp)) {
            # DeepSeek-style: result or data/text or outputs array
            if (!is.null(resp$result)) return(resp$result)
            if (!is.null(resp$data) && !is.null(resp$data$text)) return(resp$data$text)
            if (!is.null(resp$data) && length(resp$data) >= 1 && !is.null(resp$data[[1]]$text)) return(resp$data[[1]]$text)
            # Ollama style: message.content
            if (!is.null(resp$message) && !is.null(resp$message$content)) return(resp$message$content)
            # OpenAI style: choices[[1]]$message$content or choices[[1]]$text
            if (!is.null(resp$choices) && length(resp$choices) >= 1) {
              ch <- resp$choices[[1]]
              if (!is.null(ch$message) && !is.null(ch$message$content)) return(ch$message$content)
              if (!is.null(ch$text)) return(ch$text)
            }
            # some models return outputs/response/text
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
        
        attempts <- list()
        
        # internal helper to record attempt
        record_attempt <- function(endpoint, status = NA, body = NULL) {
          attempts[[length(attempts) + 1]] <<- list(endpoint = endpoint, status = status, body = if (!is.null(body)) substr(body, 1, 200) else NULL)
        }
        
        # Ollama local server convenience: only treat as Ollama when the selected model
        # explicitly indicates Ollama/tinyllama to avoid accidentally matching other endpoints
        if (!is.null(token) && grepl("^http://127.0.0.1:11434", token) && (tolower(model) == "tinyllama" || grepl("ollama", tolower(model)))) {
          endpoint <- paste0(rtrim(token), "/api/chat")
          err_txt <- NULL
          res <- tryCatch(
            httr::POST(
              url = endpoint,
              body = list(model = "tinyllama", messages = list(list(role = "user", content = prompt))),
              encode = "json",
              httr::timeout(timeout_sec)
            ),
            error = function(e) {
              err_txt <<- paste0("ERROR: ", e$message)
              NULL
            }
          )
          st <- if (!is.null(res)) httr::status_code(res) else NA
          txt <- if (!is.null(res)) httr::content(res, as = "text") else err_txt
          record_attempt(endpoint, st, txt)
          if (!is.null(res) && st == 200) {
            return(list(text = parse_resp_text(txt), debug = list(attempts = attempts)))
          }
          return(list(text = NULL, debug = list(attempts = attempts)))
        }
        
        # Dedicated DeepSeek adapter (tries a few common DeepSeek endpoints)
        if (!is.null(model) && tolower(model) == "deepseek-r1:8b") {
          # token may be endpoint or endpoint|auth
          ds_auth <- NULL
          ds_base <- token
          if (!is.null(token) && grepl("\\|", token)) {
            pparts <- strsplit(token, "\\|", fixed = TRUE)[[1]]
            ds_base <- pparts[1]
            if (length(pparts) >= 2) ds_auth <- pparts[2]
          }
          ds_eps <- c()
          if (!is.null(ds_base) && nzchar(ds_base) && grepl("^https?://", ds_base)) {
            ds_eps <- c(ds_eps, ds_base)
            ds_eps <- c(ds_eps, paste0(rtrim(ds_base), "/api/generate"))
            ds_eps <- c(ds_eps, paste0(rtrim(ds_base), "/v1/generate"))
            ds_eps <- c(ds_eps, paste0(rtrim(ds_base), "/v1/outputs"))
          }
          if (length(ds_eps) > 0) {
            ds_bodies <- list(
              list(input = prompt),
              list(prompt = prompt),
              list(text = prompt)
            )
            for (ep in ds_eps) {
              for (b in ds_bodies) {
                headers <- if (!is.null(ds_auth)) list(Authorization = ifelse(grepl("^Bearer ", ds_auth), ds_auth, paste("Bearer", ds_auth))) else NULL
                err_txt <- NULL
                res <- tryCatch({
                  if (!is.null(headers)) {
                    httr::POST(url = ep, body = b, encode = "json", httr::add_headers(.headers = headers), httr::timeout(timeout_sec))
                  } else {
                    httr::POST(url = ep, body = b, encode = "json", httr::timeout(timeout_sec))
                  }
                }, error = function(e) {
                  err_txt <<- paste0("ERROR: ", e$message)
                  NULL
                })
                st <- if (!is.null(res)) httr::status_code(res) else NA
                txt <- if (!is.null(res)) httr::content(res, as = "text") else err_txt
                record_attempt(ep, st, txt)
                if (!is.null(res) && st %in% c(200,201)) {
                  parsed <- parse_resp_text(txt)
                  if (!is.null(parsed)) return(list(text = parsed, debug = list(attempts = attempts)))
                }
              }
            }
          }
          # fallthrough to generic handling if not resolved
        }
        
        # token may include an explicit endpoint and auth separated by '|', e.g.
        # 'https://api.example.com/chat|Bearer XYZ' -> endpoint + auth header value
        auth_header <- NULL
        endpoint_base <- token
        if (!is.null(token) && grepl("\\|", token)) {
          parts <- strsplit(token, "\\|", fixed = TRUE)[[1]]
          endpoint_base <- parts[1]
          if (length(parts) >= 2) auth_header <- parts[2]
        }
        
        # build candidate endpoints
        endpoints <- c()
        if (!is.null(endpoint_base) && nzchar(endpoint_base) && grepl("^https?://", endpoint_base)) {
          endpoints <- c(endpoints, endpoint_base)
          endpoints <- c(endpoints, paste0(rtrim(endpoint_base), "/api/chat"))
          endpoints <- c(endpoints, paste0(rtrim(endpoint_base), "/v1/chat/completions"))
          endpoints <- c(endpoints, paste0(rtrim(endpoint_base), "/v1/completions"))
        }
        # also allow raw model names (no endpoint) to be handled elsewhere; if no endpoints, bail
        if (length(endpoints) == 0) return(NULL)
        
        bodies <- list(
          list(messages = list(list(role = "user", content = prompt))),
          list(input = prompt),
          list(prompt = prompt),
          list(prompt = prompt, model = model)
        )
        
        for (ep in endpoints) {
          for (b in bodies) {
            headers <- if (!is.null(auth_header)) list(Authorization = ifelse(grepl("^Bearer ", auth_header), auth_header, paste("Bearer", auth_header))) else NULL
            err_txt <- NULL
            res <- tryCatch({
              if (!is.null(headers)) {
                httr::POST(url = ep, body = b, encode = "json", httr::add_headers(.headers = headers), httr::timeout(timeout_sec))
              } else {
                httr::POST(url = ep, body = b, encode = "json", httr::timeout(timeout_sec))
              }
            }, error = function(e) {
              err_txt <<- paste0("ERROR: ", e$message)
              NULL
            })
            st <- if (!is.null(res)) httr::status_code(res) else NA
            txt <- if (!is.null(res)) httr::content(res, as = "text") else err_txt
            record_attempt(ep, st, txt)
            if (!is.null(res) && st %in% c(200,201)) {
              parsed <- parse_resp_text(txt)
              if (!is.null(parsed)) return(list(text = parsed, debug = list(attempts = attempts)))
            }
          }
        }
        return(list(text = NULL, debug = list(attempts = attempts)))
      }
      
      if (llm_info$connected) {
        # Resolve context text for the selected chat_context and prepend it to the prompt
        ctx_text <- NULL
        try({
          if (!is.null(context_resolver) && is.function(context_resolver)) {
            ctx_text <- context_resolver(chat_context())
          } else if (exists("extract_section_text", mode = "function", envir = globalenv())) {
            # If a global helper exists, attempt to derive the candidate path from chat_context name
            # The resolver should ideally be provided by the caller (reportTabServer) because it knows the active tab/file
            ctx_text <- tryCatch(get("extract_section_text", envir = globalenv())(NULL, chat_context()), error = function(e) NULL)
          }
        }, silent = TRUE)
        
        # Build final prompt: include small system header + context block if available
        final_prompt <- msg
        if (!is.null(ctx_text) && nzchar(ctx_text)) {
          header <- "Context (from selected report chapter):\n"
          # keep the context reasonably small; truncate to ~4000 chars if large
          if (nchar(ctx_text) > 4000) ctx_text <- substr(ctx_text, 1, 4000)
          final_prompt <- paste0(header, ctx_text, "\n\nUser: ", msg)
        }
        
        reply_res <- send_llm_prompt(llm_info$model, llm_info$token, final_prompt)
        reply_text <- if (is.list(reply_res) && !is.null(reply_res$text)) reply_res$text else if (is.character(reply_res)) reply_res else NULL
        reply_debug <- if (is.list(reply_res) && !is.null(reply_res$debug)) reply_res$debug else NULL
        # friendly model label mapping
        model_labels <- list(
          tinyllama = "TinyLlama",
          `openai-gpt4` = "OpenAI GPT-4",
          `openai-gpt3.5` = "OpenAI GPT-3.5",
          `anthropic-claude3` = "Anthropic Claude 3",
          `google-gemini` = "Google Gemini",
          `deepseek-r1:8b` = "DeepSeek R1:8B"
        )
        md_key <- tolower(as.character(llm_info$model))
        label <- if (!is.null(model_labels[[md_key]])) model_labels[[md_key]] else as.character(llm_info$model)
        if (!is.null(reply_text)) {
          new_history <- c(chat_messages(), paste0(label, ": ", reply_text))
          chat_messages(new_history)
        } else {
          info <- "[No response or error from model]"
          if (!is.null(reply_debug) && !is.null(reply_debug$attempts) && length(reply_debug$attempts) > 0) {
            attempts_summary <- vapply(reply_debug$attempts, function(a) paste0(a$endpoint, " (status=", a$status, ")"), "")
            info <- paste0(info, " Tried: ", paste(attempts_summary, collapse = ", "))
          }
          new_history <- c(chat_messages(), paste0(label, ": ", info))
          chat_messages(new_history)
        }
        # expose debug details for UI
        output$chat_debug <- renderUI({
          if (is.null(reply_debug) || is.null(reply_debug$attempts) || length(reply_debug$attempts) == 0) return(HTML("<div style='color:#666;font-size:0.9em;'>No debug information available</div>"))
          # present attempts with short body snippets
          rows <- lapply(reply_debug$attempts, function(a) {
            ep <- a$endpoint %||% "(unknown)"
            st <- a$status %||% "(no-status)"
            body <- a$body %||% "(no-body)"
            HTML(paste0("<div style='margin-bottom:6px; padding:6px; border-left:3px solid #eee; background:#fafafa;'><b>", ep, "</b> <span style='color:#888'>(status=", st, ")</span><div style='margin-top:4px; color:#222; font-size:0.9em;'>", htmltools::htmlEscape(body), "</div></div>"))
          })
          HTML(paste0("<div style='max-height:180px; overflow:auto; font-family:monospace;'>", paste0(rows, collapse = ""), "</div>"))
        })
      }
      
      output$chatbox_messages <- renderUI({
        HTML(paste(chat_messages(), collapse = "<br>"))
      })
    }
  })
}