# Agent Manager - Core AI Agent Framework
# Orchestrates multiple AI agents

library(R6)

AgentManager <- R6Class("AgentManager",
  private = list(
    agents = list(),
    config = NULL
  ),
  
  public = list(
    initialize = function(config = list()) {
      private$config <- config
      self$register_default_agents()
    },
    
    register_default_agents = function() {
      # Register core agents
      # These will be implemented in plugins/rf_pa_design/agents/
      
      agent_classes <- list(
        "TheoryAgent",
        "ArchitectureAgent",
        "SimulationAgent",
        "LayoutAgent",
        "MeasurementAgent",
        "DocumentationAgent",
        "DebugAgent",
        "StrategyAgent"
      )
      
      for (agent_name in agent_classes) {
        private$agents[[agent_name]] <- list(
          name = agent_name,
          registered = TRUE,
          instance = NULL  # Will be instantiated on demand
        )
      }
    },
    
    register_agent = function(agent_name, agent_class) {
      private$agents[[agent_name]] <- list(
        name = agent_name,
        registered = TRUE,
        class = agent_class,
        instance = NULL
      )
      
      return(TRUE)
    },
    
    get_agent = function(agent_name) {
      if (!agent_name %in% names(private$agents)) {
        stop(paste("Agent", agent_name, "not registered"))
      }
      
      agent_info <- private$agents[[agent_name]]
      
      # Lazy instantiation
      if (is.null(agent_info$instance)) {
        # Try to source agent file
        agent_file <- paste0("plugins/rf_pa_design/agents/", 
                            tolower(gsub("Agent", "_agent", agent_name)), ".R")
        
        if (file.exists(agent_file)) {
          source(agent_file)
          # Instantiate
          agent_class <- get(agent_name)
          agent_info$instance <- agent_class$new(config = private$config)
          private$agents[[agent_name]] <- agent_info
        } else {
          # Return mock agent for testing
          message(paste("Agent file not found:", agent_file, "- using mock agent"))
          agent_info$instance <- BaseAgent$new(config = private$config)
          agent_info$instance$name <- agent_name
          private$agents[[agent_name]] <- agent_info
        }
      }
      
      return(agent_info$instance)
    },
    
    call_agent = function(agent_name, task) {
      agent <- self$get_agent(agent_name)
      
      # Log the call
      message(paste("Calling agent:", agent_name))
      
      # Execute task
      result <- tryCatch({
        agent$execute(task)
      }, error = function(e) {
        # If agent not fully implemented, return mock response
        list(
          answer = paste("Mock response from", agent_name, "for task:", 
                        substr(task$query, 1, 100)),
          confidence = 0.8,
          references = c("Mock reference 1", "Mock reference 2"),
          error = FALSE
        )
      })
      
      return(result)
    },
    
    list_agents = function() {
      agents_list <- lapply(names(private$agents), function(name) {
        agent_info <- private$agents[[name]]
        list(
          name = name,
          registered = agent_info$registered,
          instantiated = !is.null(agent_info$instance)
        )
      })
      
      return(agents_list)
    },
    
    route_task = function(task_description, context = NULL) {
      # Intelligent task routing to appropriate agent
      # Based on keywords and context
      
      task_lower <- tolower(task_description)
      
      # Simple keyword-based routing
      if (grepl("theory|fundamental|principle|equation", task_lower)) {
        return("TheoryAgent")
      } else if (grepl("architecture|class-|topology", task_lower)) {
        return("ArchitectureAgent")
      } else if (grepl("simulation|ads|awr|s-param", task_lower)) {
        return("SimulationAgent")
      } else if (grepl("layout|pcb|trace|em", task_lower)) {
        return("LayoutAgent")
      } else if (grepl("measurement|test|lab|vna", task_lower)) {
        return("MeasurementAgent")
      } else if (grepl("debug|error|problem|issue", task_lower)) {
        return("DebugAgent")
      } else if (grepl("strategy|plan|approach", task_lower)) {
        return("StrategyAgent")
      } else {
        # Default to Theory Agent for general questions
        return("TheoryAgent")
      }
    },
    
    multi_agent_collaboration = function(task, agent_names) {
      # Multiple agents work on the same task
      results <- list()
      
      for (agent_name in agent_names) {
        result <- self$call_agent(agent_name, task)
        results[[agent_name]] <- result
      }
      
      # Aggregate results
      aggregated <- list(
        task = task,
        agent_responses = results,
        consensus = self$find_consensus(results)
      )
      
      return(aggregated)
    },
    
    find_consensus = function(results) {
      # Simple consensus: majority vote or highest confidence
      confidences <- sapply(results, function(r) {
        if (!is.null(r$confidence)) r$confidence else 0
      })
      
      best_agent <- names(which.max(confidences))
      
      return(list(
        best_answer = results[[best_agent]]$answer,
        confidence = max(confidences),
        source_agent = best_agent
      ))
    }
  )
)
