# Configuration Manager - Core System
# Manages application configuration and user preferences

library(R6)
library(yaml)

ConfigManager <- R6Class("ConfigManager",
  private = list(
    config_file = NULL,
    config_data = NULL
  ),
  
  public = list(
    initialize = function(config_file = "config/app_config.yaml") {
      private$config_file <- config_file
      
      if (file.exists(config_file)) {
        private$config_data <- yaml::read_yaml(config_file)
      } else {
        # Create default configuration
        private$config_data <- self$get_default_config()
        self$save_config()
      }
    },
    
    get_default_config = function() {
      list(
        app = list(
          name = "PA Design Assistant",
          version = "1.0.0",
          domain = "rf_pa_design"
        ),
        theme = list(
          mode = "dark",
          accent_color = "#ff7f11",
          primary_color = "#1b1b1b"
        ),
        units = list(
          frequency = "GHz",
          power = "dBm",
          impedance = "Ohm",
          inductance = "nH",
          capacitance = "pF"
        ),
        ai_agents = list(
          enabled = TRUE,
          model = "gpt-4",
          confidence_threshold = 0.7,
          max_retries = 3
        ),
        database = list(
          host = "localhost",
          port = 5432,
          name = "pa_design",
          pool_size = 10
        ),
        mcp_servers = list(
          list(
            name = "ads_server",
            url = "http://localhost:8081",
            enabled = FALSE
          ),
          list(
            name = "awr_server",
            url = "http://localhost:8082",
            enabled = FALSE
          )
        ),
        security = list(
          auth_enabled = FALSE,
          session_timeout = 3600,
          encryption_enabled = TRUE
        )
      )
    },
    
    get_config = function(path = NULL) {
      if (is.null(path)) {
        return(private$config_data)
      }
      
      # Navigate nested config using path (e.g., "ai_agents.model")
      parts <- strsplit(path, "\\.")[[1]]
      value <- private$config_data
      
      for (part in parts) {
        if (is.list(value) && part %in% names(value)) {
          value <- value[[part]]
        } else {
          return(NULL)
        }
      }
      
      return(value)
    },
    
    set_config = function(path, value) {
      parts <- strsplit(path, "\\.")[[1]]
      
      # Navigate to parent and set value
      config_ref <- private$config_data
      for (i in 1:(length(parts) - 1)) {
        if (!parts[i] %in% names(config_ref)) {
          config_ref[[parts[i]]] <- list()
        }
        config_ref <- config_ref[[parts[i]]]
      }
      
      config_ref[[parts[length(parts)]]] <- value
      
      return(TRUE)
    },
    
    save_config = function() {
      dir.create(dirname(private$config_file), showWarnings = FALSE, recursive = TRUE)
      yaml::write_yaml(private$config_data, private$config_file)
      return(TRUE)
    },
    
    reload_config = function() {
      if (file.exists(private$config_file)) {
        private$config_data <- yaml::read_yaml(private$config_file)
        return(TRUE)
      }
      return(FALSE)
    }
  )
)
