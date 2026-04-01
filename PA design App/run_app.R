#!/usr/bin/env Rscript

# PA Design App Launcher
# Run this script to start the Shiny application

# Set working directory to app root
setwd("/workspaces/Atomic_cosmic_RFView_Notes/PA design App")

# Print startup message
cat("\n")
cat("========================================\n")
cat("  PA Design App - Starting...\n")
cat("========================================\n")
cat("Working directory:", getwd(), "\n")
cat("\n")

# Check if required packages are installed
required_packages <- c(
  'shiny', 'shinydashboard', 'shinyjs', 'plotly', 'DT',
  'R6', 'yaml', 'DBI', 'RPostgres', 'pool', 'httr', 'jsonlite', 'uuid'
)

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("Installing missing packages:", paste(missing_packages, collapse = ", "), "\n\n")
  install.packages(missing_packages, repos = 'https://cloud.r-project.org/')
}

# Load the app
cat("Loading application...\n\n")

# Run the app
tryCatch({
  shiny::runApp("R/app.R", host = "0.0.0.0", port = 3838, launch.browser = FALSE)
}, error = function(e) {
  cat("\n")
  cat("========================================\n")
  cat("  Error starting application:\n")
  cat("========================================\n")
  cat(conditionMessage(e), "\n")
  cat("\nPlease check:\n")
  cat("1. All required packages are installed\n")
  cat("2. PostgreSQL database is running (optional for demo mode)\n")
  cat("3. Port 3838 is available\n")
})
