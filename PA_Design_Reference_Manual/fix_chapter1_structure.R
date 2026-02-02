#!/usr/bin/env Rscript

# Fix Chapter 1 structure in combined HTML to match other chapters
cat("Fixing Chapter 1 structure in PA_Design_Manual_Combined.html...\n\n")

# Read the combined file
combined_file <- "PA_Design_Manual_Combined.html"
combined_full <- readLines(combined_file, warn = FALSE)

# Find Chapter 1 boundaries
ch1_start <- grep("<!-- Chapter 1 Content -->", combined_full, fixed = TRUE)[1]
ch1_end <- grep("<p><strong>End of Chapter 1</strong></p>", combined_full, fixed = TRUE)[1]

cat("Found Chapter 1:\n")
cat("  Start line:", ch1_start, "\n")
cat("  End line:", ch1_end, "\n")

# Read the standalone Chapter 1 file to get the proper content
chapter1_file <- "Chapters/Chapter_01_Transistor_Fundamentals.html"
chapter1_full <- readLines(chapter1_file, warn = FALSE)

# Find where the actual content starts (first section level1)
content_start <- grep('<div id="introduction" class="section level1 tabset"', chapter1_full, fixed = TRUE)[1]
# Find where content ends (before the closing body tag)
content_end_pattern <- "</body>"
content_end <- grep(content_end_pattern, chapter1_full, fixed = TRUE)[1] - 1

cat("\nExtracted content from standalone file:\n")
cat("  Start line:", content_start, "\n")
cat("  End line:", content_end, "\n")

# Extract the content
ch1_content <- chapter1_full[content_start:content_end]

# Create properly structured chapter with wrapper divs
ch1_structured <- c(
  "            <!-- Chapter 1 Content -->",
  "            <div class=\"chapter-content\" id=\"ch1\">",
  "                <body>",
  "<div class=\"container-fluid main-container\">",
  "<!-- setup 3col/9col grid for toc_float and main content  -->",
  "<div class=\"row\">",
  "<div class=\"col-xs-12 col-sm-4 col-md-3\">",
  "",
  "</div>",
  "<div class=\"toc-content col-xs-12 col-sm-8 col-md-9\">",
  "",
  ch1_content,
  "",
  "<p><strong>End of Chapter 1</strong></p>",
  "<hr/>",
  "</div>",
  "</div>",
  "</div>",
  "</body>",
  "            </div>"
)

# Build the updated combined file
updated_combined <- c(
  combined_full[1:(ch1_start - 1)],
  ch1_structured,
  combined_full[(ch1_end + 2):length(combined_full)]  # +2 to skip the </div> after End of Chapter 1
)

# Create backup
backup_file <- paste0("PA_Design_Manual_Combined_backup_structure_fix_", 
                      format(Sys.time(), "%Y%m%d_%H%M%S"), ".html")
writeLines(combined_full, backup_file)
cat("\n✓ Backup saved:", backup_file, "\n")

# Write the updated file
writeLines(updated_combined, combined_file)

cat("\n✅ Successfully fixed Chapter 1 structure!\n\n")
cat("Changes made:\n")
cat("  ✓ Added proper <div class=\"chapter-content\" id=\"ch1\"> wrapper\n")
cat("  ✓ Added Bootstrap grid structure (col-xs-12 col-sm-4 col-md-3 + col-xs-12 col-sm-8 col-md-9)\n")
cat("  ✓ Added toc-content wrapper div\n")
cat("  ✓ Chapter 1 now matches structure of other chapters\n")
cat("  ✓ TOC should now display properly with subsections\n")
cat("  ✓ Content should be properly constrained with left/right TOC visible\n\n")

cat("Original lines:", length(combined_full), "\n")
cat("New lines:", length(updated_combined), "\n")
cat("Difference:", length(updated_combined) - length(combined_full), "lines\n")
