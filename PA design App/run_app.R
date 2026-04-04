#!/usr/bin/env Rscript

# PA Design App Launcher
# Run this script to start the Shiny application

# Set working directory to the script location so the launcher works on Windows and Linux.
args <- commandArgs(trailingOnly = FALSE)
script_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(script_arg) > 0) {
  sub("^--file=", "", script_arg[1])
} else {
  normalizePath("run_app.R", winslash = "/", mustWork = FALSE)
}
setwd(dirname(normalizePath(script_path, winslash = "/", mustWork = FALSE)))

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
  shiny::runApp("src/app.R", host = "0.0.0.0", port = 3838, launch.browser = FALSE)
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
