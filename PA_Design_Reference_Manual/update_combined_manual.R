#!/usr/bin/env Rscript
# Script to update the combined manual with latest Chapter 1

cat("Updating PA_Design_Manual_Combined.html with enhanced Chapter 1...\n\n")

# Get Chapter 1 content between section markers
chapter1_full <- readLines("Chapters/Chapter_01_Transistor_Fundamentals.html", warn = FALSE)
combined_full <- readLines("PA_Design_Manual_Combined.html", warn = FALSE)

# Find Chapter 1 boundaries in combined file  
ch1_start_markers <- grep("Chapter 1 Content", combined_full, fixed = FALSE)
ch1_end_markers <- grep("End of Chapter 1|Chapter 2", combined_full, fixed = FALSE)

if (length(ch1_start_markers) == 0) {
  cat("ERROR: Could not find Chapter 1 start marker\n")
  quit(status = 1)
}

# Get the actual content boundaries
ch1_start <- ch1_start_markers[1] + 1  # Start after comment
ch1_end <- min(ch1_end_markers[ch1_end_markers > ch1_start]) - 1  # End before next marker

cat("Found Chapter 1 in combined manual:\n")
cat("  Start line:", ch1_start, "\n")
cat("  End line:", ch1_end, "\n")
cat("  Total lines to replace:", ch1_end - ch1_start + 1, "\n\n")

# Extract Chapter 1 main content from standalone file
# Find the actual content start (after TOC and header)
content_start_patterns <- c(
  '<div id="introduction-why-gan-for-rf-power-amplifiers"',
  '<div class="section level1"',
  '<h1 class="title toc-ignore"'
)

ch1_content_start <- NULL
for (pattern in content_start_patterns) {
  idx <- grep(pattern, chapter1_full, fixed = TRUE)
  if (length(idx) > 0) {
    ch1_content_start <- idx[1]
    break
  }
}

# Find content end (before footer/script tags)
ch1_content_end_candidates <- c(
  grep('<div id="refs"', chapter1_full, fixed = TRUE),
  grep('</body>', chapter1_full, fixed = TRUE),
  grep('<script type="application/json"', chapter1_full, fixed = TRUE)
)

ch1_content_end <- min(unlist(ch1_content_end_candidates)) - 5  # Stop a few lines before

# Extract the content
ch1_new_content <- chapter1_full[ch1_content_start:ch1_content_end]

cat("Extracted new Chapter 1 content:\n")
cat("  Start line in source:", ch1_content_start, "\n")
cat("  End line in source:", ch1_content_end, "\n")
cat("  Total lines extracted:", length(ch1_new_content), "\n\n")

# Create updated combined manual
updated_combined <- c(
  combined_full[1:(ch1_start - 1)],              # Everything before Chapter 1
  ch1_new_content,                                 # New Chapter 1 content  
  combined_full[(ch1_end + 1):length(combined_full)]  # Everything after Chapter 1
)

cat("Creating updated combined manual:\n")
cat("  Original lines:", length(combined_full), "\n")
cat("  New lines:", length(updated_combined), "\n")
cat("  Difference:", length(updated_combined) - length(combined_full), "lines\n\n")

# Write backup first
backup_file <- paste0("PA_Design_Manual_Combined_backup_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html")
writeLines(combined_full, backup_file)
cat("✓ Backup saved:", backup_file, "\n")

# Write updated file
writeLines(updated_combined, "PA_Design_Manual_Combined.html")

cat("\n✅ Successfully updated PA_Design_Manual_Combined.html\n")
cat("\nChapter 1 now includes all latest enhancements:\n")
cat("  ✓ Enhanced Figure 1.1 (4-panel: band diagram, cross-section, top view, schematic)\n")
cat("  ✓ Interactive Plotly Figure 1.3 with log-scale X-axis\n")
cat("  ✓ PA Class load lines (A, AB, B, C, D, E, F) - toggleable\n")
cat("  ✓ Interactive Plotly Figure 1.4 with bias region overlays\n")
cat("  ✓ Fixed text rendering issue after Figure 1.4\n")
cat("  ✓ LDMOS & GaAs technology comparison\n")
cat("  ✓ Comprehensive trapping mechanisms section\n")
cat("  ✓ 5 interactive glossary terms\n")

