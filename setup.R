#!/usr/bin/env Rscript

# Setup script for RF Engineering Teaching Notes
# This script installs the required R packages

cat("==================================================\n")
cat(" RF Engineering Teaching Notes - Setup Script\n")
cat("==================================================\n\n")

# Function to install if not already installed
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org/", 
                     dependencies = TRUE, quiet = FALSE)
    return(TRUE)
  } else {
    cat(sprintf("✓ %s already installed\n", pkg))
    return(FALSE)
  }
}

# List of required packages
packages <- c(
  "rmarkdown",
  "knitr",
  "ggplot2",
  "flexdashboard"
)

cat("Checking and installing required packages...\n\n")

# Install packages
installed_any <- FALSE
for (pkg in packages) {
  if (install_if_missing(pkg)) {
    installed_any <- TRUE
  }
}

if (!installed_any) {
  cat("\n✓ All required packages are already installed!\n")
} else {
  cat("\n✓ Package installation complete!\n")
}

cat("\n==================================================\n")
cat(" Setup Complete!\n")
cat("==================================================\n")
cat("\nYou can now render the document with:\n")
cat("  Rscript -e \"rmarkdown::render('Atomic_Cosmic_RFView.Rmd')\"\n")
cat("\nOr open Atomic_Cosmic_RFView.Rmd in RStudio and click 'Knit'\n\n")
