# Headless test: exercise setup_chat_handlers via shiny::testServer
library(shiny)
library(httr)
library(jsonlite)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Provide minimal helper functions expected by chat_module.R
save_chat_history <- function(messages, context_key, folder = "www") {
  # noop
}
load_chat_history <- function(context_key, folder = "www") {
  character()
}

# Source the chat module
source('chat_module.R')

# Run testServer to simulate a module session and inputs
res <- shiny::testServer(function(input, output, session) {
  # Create reactive containers as expected by the module
  chat_messages <- reactiveVal(character())
  llm_info <- reactiveValues(model = NULL, token = NULL, connected = FALSE)
  chat_context <- reactive({ input$chat_context %||% "Introduction" })
  # Wire handlers
  setup_chat_handlers(input, output, session, chat_messages, llm_info, chat_context)
}, {
  # Simulate user actions
  session$setInputs(llm_model = 'deepseek')
  session$setInputs(llm_token = 'http://127.0.0.1:8001')
  session$setInputs(llm_connect = 1)
  session$setInputs(chat_context = 'Introduction')
  # Allow observers to process
  Sys.sleep(0.2)
  session$setInputs(chatbox_input = 'Hello from headless test')
  session$setInputs(chatbox_send = 1)
  # Wait for the network call and observer
  Sys.sleep(0.5)
  # Inspect the chat_messages reactive in the module environment
  cm <- session$exportReactives()
  # cm may not include the reactiveVal; try reading via getFromNamespace isn't available here
  # Instead, check output$chatbox_messages if available
  if (exists('chat_messages', envir = parent.frame())) {
    tryCatch({
      print(get('chat_messages', envir = parent.frame())())
    }, error = function(e) print('could not read chat_messages') )
  }
})

cat('Headless test completed.\n')
