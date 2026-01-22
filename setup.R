#!/usr/bin/env Rscript

# Setup script for RF Engineering Teaching Notes
# This script installs the required R packages

cat("==================================================\n")
cat(" RF Engineering Teaching Notes - Setup Script\n")
cat("==================================================\n\n")

# Create user library directory if it doesn't exist
user_lib <- Sys.getenv("R_LIBS_USER")
if (user_lib == "") {
  user_lib <- file.path(Sys.getenv("HOME"), "R", "library")
}
if (!dir.exists(user_lib)) {
  dir.create(user_lib, recursive = TRUE)
  cat(sprintf("Created user library directory: %s\n\n", user_lib))
}

# Add user library to library paths
.libPaths(c(user_lib, .libPaths()))
cat(sprintf("Using library path: %s\n\n", user_lib))

# Function to install if not already installed
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    tryCatch({
      install.packages(pkg, repos = "https://cloud.r-project.org/", 
                       lib = user_lib, dependencies = TRUE, quiet = FALSE)
      return(TRUE)
    }, error = function(e) {
      cat(sprintf("  Warning: Could not install %s from CRAN\n", pkg))
      cat(sprintf("  Error: %s\n", conditionMessage(e)))
      return(FALSE)
    })
  } else {
    cat(sprintf("✓ %s already installed\n", pkg))
    return(FALSE)
  }
}

# List of required packages
packages <- c(
  "rmarkdown",
  "knitr",
  "ggplot2"
)

cat("Checking and installing required packages...\n\n")

# Install packages
installed_any <- FALSE
for (pkg in packages) {
  if (install_if_missing(pkg)) {
    installed_any <- TRUE
  }
}

# Special handling for flexdashboard (may not be in CRAN)
cat("\nChecking flexdashboard (special package)...\n")
if (!requireNamespace("flexdashboard", quietly = TRUE)) {
  cat("flexdashboard not found. Attempting to install from GitHub...\n")
  
  # Check if remotes/devtools is available
  if (!requireNamespace("remotes", quietly = TRUE) && !requireNamespace("devtools", quietly = TRUE)) {
    cat("Installing remotes package first...\n")
    tryCatch({
      install.packages("remotes", repos = "https://cloud.r-project.org/", 
                       lib = user_lib, quiet = FALSE)
    }, error = function(e) {
      cat("Could not install remotes. Please install it manually:\n")
      cat("  sudo apt-get install r-cran-remotes\n")
      cat("Or try: install.packages('remotes')\n")
    })
  }
  
  # Try to install flexdashboard from GitHub
  if (requireNamespace("remotes", quietly = TRUE)) {
    cat("Installing flexdashboard from GitHub...\n")
    tryCatch({
      remotes::install_github("rstudio/flexdashboard", lib = user_lib, upgrade = "never")
      cat("✓ flexdashboard installed from GitHub\n")
      installed_any <- TRUE
    }, error = function(e) {
      cat("\n✗ Could not install flexdashboard from GitHub\n")
      cat("Error:", conditionMessage(e), "\n\n")
      cat("Alternative installation methods:\n")
      cat("1. Download from: https://github.com/rstudio/flexdashboard/archive/refs/heads/main.zip\n")
      cat("2. Extract and run: R CMD INSTALL flexdashboard-main\n")
      cat("3. Or see TROUBLESHOOTING.md for more options\n\n")
    })
  } else {
    cat("\n✗ Cannot install flexdashboard without remotes/devtools\n")
    cat("Please install manually. See TROUBLESHOOTING.md for instructions\n\n")
  }
} else {
  cat("✓ flexdashboard already installed\n")
}

if (!installed_any) {
  cat("\n✓ All required packages are already installed!\n")
} else {
  cat("\n✓ Package installation process complete!\n")
}

# Verify all packages
cat("\n==================================================\n")
cat(" Verification\n")
cat("==================================================\n\n")

all_ok <- TRUE
for (pkg in c(packages, "flexdashboard")) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("✓ %s\n", pkg))
  } else {
    cat(sprintf("✗ %s (MISSING)\n", pkg))
    all_ok <- FALSE
  }
}

cat("\n==================================================\n")
if (all_ok) {
  cat(" ✓ Setup Complete - All packages installed!\n")
  cat("==================================================\n")
  cat("\nYou can now render the document with:\n")
  cat("  Rscript render_document.R\n")
  cat("\nOr directly:\n")
  cat("  Rscript -e \".libPaths(c('", user_lib, "', .libPaths())); rmarkdown::render('Atomic_Cosmic_RFView.Rmd')\"\n")
  cat("\nOr open Atomic_Cosmic_RFView.Rmd in RStudio and click 'Knit'\n\n")
} else {
  cat(" ⚠ Setup Incomplete - Some packages missing\n")
  cat("==================================================\n")
  cat("\nSome packages could not be installed automatically.\n")
  cat("Please see TROUBLESHOOTING.md for manual installation instructions.\n\n")
  cat("You can also try:\n")
  cat("  sudo apt-get install r-cran-rmarkdown r-cran-knitr r-cran-ggplot2 r-cran-remotes\n\n")
}

