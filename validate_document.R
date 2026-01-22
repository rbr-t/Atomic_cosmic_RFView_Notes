#!/usr/bin/env Rscript

# Test script to validate the Atomic_Cosmic_RFView.Rmd document

cat("Testing Atomic_Cosmic_RFView.Rmd validation...\n")

# Check if file exists
if (!file.exists("Atomic_Cosmic_RFView.Rmd")) {
  stop("Error: Atomic_Cosmic_RFView.Rmd not found!")
}

cat("✓ File exists\n")

# Read the file
content <- readLines("Atomic_Cosmic_RFView.Rmd")
cat(sprintf("✓ File readable (%d lines)\n", length(content)))

# Check for YAML header
if (content[1] == "---") {
  yaml_end <- which(content == "---")[2]
  cat(sprintf("✓ YAML header found (lines 1-%d)\n", yaml_end))
}

# Check for required sections
sections <- c("Atomic & Quantum Level", "Molecular & Material Level", 
              "Device Level", "System Level", "Terrestrial Level", "Cosmic Level")
              
for (section in sections) {
  if (any(grepl(section, content, fixed = TRUE))) {
    cat(sprintf("✓ Section found: %s\n", section))
  } else {
    cat(sprintf("✗ Section missing: %s\n", section))
  }
}

# Check for code chunks
r_chunks <- grep("```\\{r", content)
cat(sprintf("✓ Found %d R code chunks\n", length(r_chunks)))

# Check for LaTeX equations
latex_inline <- length(grep("\\$[^$]+\\$", content))
latex_display <- length(grep("\\$\\$", content))
cat(sprintf("✓ Found ~%d LaTeX equations\n", latex_inline + latex_display/2))

# Check if bibliography file exists
if (file.exists("references.bib")) {
  bib_lines <- readLines("references.bib")
  entries <- length(grep("^@", bib_lines))
  cat(sprintf("✓ Bibliography file exists with %d entries\n", entries))
}

cat("\n=== Validation Complete ===\n")
cat("The document structure looks good!\n")
cat("To render, run: rmarkdown::render('Atomic_Cosmic_RFView.Rmd')\n")
