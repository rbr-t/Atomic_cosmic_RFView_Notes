#!/usr/bin/env Rscript

# Quick test to render the document with better error reporting

cat("==================================================\n")
cat(" Testing Atomic_Cosmic_RFView.Rmd Rendering\n")
cat("==================================================\n\n")

# Set up library paths
user_lib <- Sys.getenv("R_LIBS_USER")
if (user_lib == "") {
  user_lib <- file.path(Sys.getenv("HOME"), "R", "library")
}
if (dir.exists(user_lib)) {
  .libPaths(c(user_lib, .libPaths()))
  cat(sprintf("Using library path: %s\n\n", user_lib))
}

# Check if file exists
if (!file.exists("Atomic_Cosmic_RFView.Rmd")) {
  stop("ERROR: Atomic_Cosmic_RFView.Rmd not found in current directory!\n")
}

cat("✓ Document file found\n\n")

# Check required packages
required_pkgs <- c("rmarkdown", "knitr", "ggplot2", "flexdashboard")
missing_pkgs <- c()

cat("Checking required packages:\n")
for (pkg in required_pkgs) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("  ✓ %s\n", pkg))
  } else {
    cat(sprintf("  ✗ %s (MISSING)\n", pkg))
    missing_pkgs <- c(missing_pkgs, pkg)
  }
}
cat("\n")

if (length(missing_pkgs) > 0) {
  cat("ERROR: Missing required packages:\n")
  cat(paste("  -", missing_pkgs, collapse = "\n"), "\n\n")
  cat("Please install missing packages using one of these methods:\n\n")
  cat("Method 1: System packages (Ubuntu/Debian)\n")
  cat("  sudo apt-get install r-cran-rmarkdown r-cran-knitr r-cran-ggplot2\n")
  if ("flexdashboard" %in% missing_pkgs) {
    cat("  # flexdashboard not available in apt, install from CRAN or GitHub\n")
  }
  cat("\nMethod 2: From CRAN\n")
  cat(sprintf("  Rscript -e \"install.packages(c('%s'), repos='https://cloud.r-project.org/')\"\n", 
              paste(missing_pkgs, collapse="', '")))
  cat("\nMethod 3: Use the setup.R script\n")
  cat("  Rscript setup.R\n\n")
  stop("Cannot proceed without required packages\n")
}

# Check pandoc
cat("Checking pandoc:\n")
tryCatch({
  pandoc_ver <- rmarkdown::pandoc_version()
  cat(sprintf("  ✓ Pandoc version %s\n\n", pandoc_ver))
}, error = function(e) {
  cat("  ✗ Pandoc not found or not accessible\n\n")
  cat("Please install pandoc:\n")
  cat("  sudo apt-get install pandoc\n\n")
  stop("Pandoc is required for rendering\n")
})

# Try to render
cat("Attempting to render document...\n\n")
tryCatch({
  rmarkdown::render(
    "Atomic_Cosmic_RFView.Rmd",
    output_file = "Atomic_Cosmic_RFView.html",
    quiet = FALSE
  )
  cat("\n")
  cat("==================================================\n")
  cat(" ✓ SUCCESS!\n")
  cat("==================================================\n\n")
  cat("The document has been rendered successfully!\n")
  cat("Output file: Atomic_Cosmic_RFView.html\n\n")
  cat("You can now open it in your web browser:\n")
  cat("  - Double-click the file in your file manager\n")
  cat("  - Or use: xdg-open Atomic_Cosmic_RFView.html (Linux)\n")
  cat("  - Or use: open Atomic_Cosmic_RFView.html (macOS)\n")
  cat("  - Or use: start Atomic_Cosmic_RFView.html (Windows)\n\n")
}, error = function(e) {
  cat("\n")
  cat("==================================================\n")
  cat(" ✗ RENDERING FAILED\n")
  cat("==================================================\n\n")
  cat("Error message:\n")
  cat(conditionMessage(e), "\n\n")
  cat("This error occurred during rendering. Common causes:\n")
  cat("  1. Missing R packages or dependencies\n")
  cat("  2. Syntax errors in the Rmd file\n")
  cat("  3. Missing or invalid references\n")
  cat("  4. Network issues (if fetching remote resources)\n\n")
  cat("Try running the validation script first:\n")
  cat("  Rscript validate_document.R\n\n")
  stop("Rendering failed\n")
})
