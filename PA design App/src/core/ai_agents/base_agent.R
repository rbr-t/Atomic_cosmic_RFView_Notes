# Base Agent - Core AI Agent Framework
# Base class for all AI agents

library(R6)
library(httr)
library(jsonlite)

BaseAgent <- R6Class("BaseAgent",
  public = list(
    name = "BaseAgent",
    expertise = "General AI assistance",
    model = "gpt-4",
    confidence_threshold = 0.7,
    api_key = NULL,
    
    initialize = function(config = list()) {
      if (!is.null(config$model)) self$model <- config$model
      if (!is.null(config$confidence_threshold)) {
        self$confidence_threshold <- config$confidence_threshold
      }
      self$api_key <- Sys.getenv("OPENAI_API_KEY", "")
    },
    
    execute = function(task) {
      # Override this in child classes
      stop("execute() must be implemented in child class")
    },
    
    call_llm = function(prompt, system_prompt = NULL) {
      # Call OpenAI API (or other LLM)
      
      if (self$api_key == "") {
        # Mock response for testing without API key
        return(list(
          content = paste("Mock AI response to:", substr(prompt, 1, 100), "..."),
          model = "mock",
          usage = list(total_tokens = 100)
        ))
      }
      
      messages <- list()
      
      if (!is.null(system_prompt)) {
        messages <- append(messages, list(list(
          role = "system",
          content = system_prompt
        )))
      }
      
      messages <- append(messages, list(list(
        role = "user",
        content = prompt
      )))
      
      response <- tryCatch({
        httr::POST(
          "https://api.openai.com/v1/chat/completions",
          httr::add_headers(
            "Authorization" = paste("Bearer", self$api_key),
            "Content-Type" = "application/json"
          ),
          body = jsonlite::toJSON(list(
            model = self$model,
            messages = messages,
            temperature = 0.7,
            max_tokens = 1000
          ), auto_unbox = TRUE),
          encode = "json"
        )
      }, error = function(e) {
        return(list(status_code = 500, content = list(error = e$message)))
      })
      
      if (response$status_code == 200) {
        content <- httr::content(response, as = "parsed")
        return(list(
          content = content$choices[[1]]$message$content,
          model = content$model,
          usage = content$usage
        ))
      } else {
        return(list(
          content = "Error calling LLM API",
          error = TRUE
        ))
      }
    },
    
    query_knowledge_base = function(query, top_k = 5) {
      # Query vector database (to be implemented with Chroma/Weaviate)
      # For now, return mock results
      
      return(list(
        results = list(
          list(
            text = "Relevant information from knowledge base...",
            source = "RF PA Design Handbook, Chapter 3",
            score = 0.85
          )
        ),
        citations = c("Cripps, S. (2006). RF Power Amplifiers for Wireless Communications")
      ))
    },
    
    validate_response = function(response, context = NULL) {
      # Validate AI response for accuracy and relevance
      # Check for common hallucination patterns
      
      # Basic validation
      if (is.null(response) || response == "") {
        return(list(
          valid = FALSE,
          confidence = 0,
          reason = "Empty response"
        ))
      }
      
      # Check for uncertainty indicators
      uncertainty_words <- c("maybe", "perhaps", "might", "possibly", "unclear")
      text_lower <- tolower(response)
      
      uncertainty_count <- sum(sapply(uncertainty_words, function(w) {
        grepl(w, text_lower, fixed = TRUE)
      }))
      
      confidence <- 1.0 - (uncertainty_count * 0.1)
      confidence <- max(0, min(1, confidence))
      
      return(list(
        valid = confidence >= self$confidence_threshold,
        confidence = confidence,
        reason = if (confidence < self$confidence_threshold) "Low confidence" else "OK"
      ))
    },
    
    log_action = function(action, details) {
      # Log agent action for audit trail
      log_entry <- list(
        timestamp = Sys.time(),
        agent = self$name,
        action = action,
        details = details
      )
      
      # Write to log file
      log_dir <- "logs/agents"
      if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
      
      log_file <- file.path(log_dir, paste0(Sys.Date(), ".json"))
      
      # Append to log
      if (file.exists(log_file)) {
        existing_logs <- jsonlite::fromJSON(log_file)
        all_logs <- c(existing_logs, list(log_entry))
      } else {
        all_logs <- list(log_entry)
      }
      
      write(jsonlite::toJSON(all_logs, pretty = TRUE), log_file)
    }
  )
)
