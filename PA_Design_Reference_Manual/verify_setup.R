# Verify Setup for PA Design Manual Project
# Run this to check if environment is properly configured

cat("🔍 Verifying PA Design Manual setup...\n\n")

# Required packages
required_packages <- c(
  "rmarkdown", "knitr", "bookdown", "htmltools",
  "dplyr", "tidyr", "readr", "ggplot2", "plotly",
  "kableExtra", "DT", "here", "glue", "stringr"
)

# Check R version
cat("📊 R Version:\n")
cat(paste("  ", R.version.string, "\n\n"))

if(getRversion() < "4.0.0") {
  cat("⚠️  Warning: R version 4.0.0 or higher recommended\n\n")
}

# Check packages
cat("📦 Package Check:\n")
all_installed <- TRUE
for(pkg in required_packages) {
  installed <- pkg %in% installed.packages()[,"Package"]
  status <- if(installed) "✅" else "❌"
  version <- if(installed) as.character(packageVersion(pkg)) else "NOT INSTALLED"
  cat(sprintf("  %s %-20s: %s\n", status, pkg, version))
  if(!installed) all_installed <- FALSE
}
cat("\n")

# Check Pandoc
cat("📝 Pandoc:\n")
pandoc_available <- rmarkdown::pandoc_available()
if(pandoc_available) {
  cat(sprintf("  ✅ Pandoc %s found\n\n", rmarkdown::pandoc_version()))
} else {
  cat("  ❌ Pandoc not found (required for rendering)\n\n")
}

# Check project structure
cat("📁 Project Structure:\n")
expected_dirs <- c(
  "data_extraction",
  "manual_chapters",
  "shared_resources",
  "automation_framework",
  "output",
  "tests",
  "docs"
)

all_dirs_exist <- TRUE
for(dir in expected_dirs) {
  exists <- dir.exists(dir)
  status <- if(exists) "✅" else "❌"
  cat(sprintf("  %s %s/\n", status, dir))
  if(!exists) all_dirs_exist <- FALSE
}
cat("\n")

# Check key files
cat("📄 Key Files:\n")
expected_files <- c(
  "README.md",
  "DEVELOPER_GUIDE.md",
  "PROJECT_STATUS.Rmd",
  "PA_Design_Project_Plan.Rmd"
)

all_files_exist <- TRUE
for(file in expected_files) {
  exists <- file.exists(file)
  status <- if(exists) "✅" else "❌"
  cat(sprintf("  %s %s\n", status, file))
  if(!exists) all_files_exist <- FALSE
}
cat("\n")

# Test simple rendering
cat("🧪 Test Rendering:\n")
test_passed <- tryCatch({
  # Create minimal test file
  test_rmd <- "---
title: Test
output: html_document
---

# Test
This is a test.
"
  writeLines(test_rmd, "test_render.Rmd")
  rmarkdown::render("test_render.Rmd", quiet = TRUE)
  file.remove("test_render.Rmd", "test_render.html")
  cat("  ✅ Test rendering successful\n\n")
  TRUE
}, error = function(e) {
  cat(paste("  ❌ Test rendering failed:", e$message, "\n\n"))
  FALSE
})

# Final summary
cat(paste(rep("=", 50), collapse = ""), "\n")
cat("📋 VERIFICATION SUMMARY\n")
cat(paste(rep("=", 50), collapse = ""), "\n")

if(all_installed && pandoc_available && all_dirs_exist && all_files_exist && test_passed) {
  cat("✅ All checks passed!\n")
  cat("✅ Your environment is ready for development.\n\n")
  cat("Next steps:\n")
  cat("  1. Review PROJECT_STATUS.html for current state\n")
  cat("  2. Read DEVELOPER_GUIDE.md for workflow\n")
  cat("  3. Start with data extraction phase\n")
} else {
  cat("❌ Some checks failed. Please address the issues above.\n\n")
  if(!all_installed) cat("  - Install missing packages: Rscript install_dependencies.R\n")
  if(!pandoc_available) cat("  - Install Pandoc or use RStudio\n")
  if(!all_dirs_exist || !all_files_exist) cat("  - Re-run project setup\n")
}

cat("\n")
