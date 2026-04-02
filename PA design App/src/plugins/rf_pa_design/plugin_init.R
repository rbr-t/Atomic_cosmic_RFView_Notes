# RF PA Design Plugin Initialization
# Loads plugin-specific components

# Source all agents
agent_files <- list.files("plugins/rf_pa_design/agents", pattern = "\\.R$", full.names = TRUE)
for (agent_file in agent_files) {
  tryCatch({
    source(agent_file)
  }, error = function(e) {
    message(paste("Could not load agent:", agent_file))
  })
}

# Source UI modules
ui_module_files <- list.files("plugins/rf_pa_design/ui_modules", pattern = "\\.R$", full.names = TRUE)
for (ui_file in ui_module_files) {
  tryCatch({
    source(ui_file)
  }, error = function(e) {
    message(paste("Could not load UI module:", ui_file))
  })
}

message("RF PA Design plugin initialized")
