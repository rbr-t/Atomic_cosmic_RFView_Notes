# Install Required R Packages for PA Design Manual Project
# Run this script once during initial setup

cat("Installing required R packages for PA Design Manual...\n\n")

# CRAN mirror
options(repos = c(CRAN = "https://cloud.r-project.org"))

# List of required packages
required_packages <- c(
  # Core R Markdown and documentation
  "rmarkdown",
  "knitr",
  "bookdown",
  "htmltools",
  
  # Data manipulation
  "dplyr",
  "tidyr",
  "readr",
  "readxl",
  "writexl",
  
  # Visualization
  "ggplot2",
  "plotly",
  "patchwork",
  "scales",
  "RColorBrewer",
  
  # Tables
  "kableExtra",
  "DT",
  "gt",
  "formattable",
  
  # Utilities
  "here",
  "glue",
  "stringr",
  "lubridate",
  "jsonlite",
  
  # Scientific computing
  "pracma",
  "signal",
  
  # Testing (optional but recommended)
  "testthat"
)

# Check which packages are not installed
new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]

if(length(new_packages) > 0) {
  cat("Installing the following packages:\n")
  cat(paste("-", new_packages, collapse = "\n"), "\n\n")
  
  install.packages(new_packages, dependencies = TRUE)
  
  cat("\n✅ Installation complete!\n\n")
} else {
  cat("✅ All required packages are already installed.\n\n")
}

# Print summary
cat("Package Summary:\n")
cat("================\n")
for(pkg in required_packages) {
  version <- tryCatch(
    as.character(packageVersion(pkg)),
    error = function(e) "NOT INSTALLED"
  )
  cat(sprintf("%-20s: %s\n", pkg, version))
}

cat("\n✅ Setup complete! Run verify_setup.R to test the installation.\n")
