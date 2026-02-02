#!/usr/bin/env Rscript

# Remove duplicate content in Chapter 1
cat("Cleaning up duplicate Chapter 1 content...\n\n")

combined_file <- "PA_Design_Manual_Combined.html"
lines <- readLines(combined_file, warn = FALSE)

# Find the two "End of Chapter 1" markers
end_markers <- grep('<p><strong>End of Chapter 1</strong></p>', lines, fixed = TRUE)
cat("Found", length(end_markers), "End of Chapter 1 markers at lines:", paste(end_markers, collapse = ", "), "\n")

if (length(end_markers) == 2) {
  # Remove everything from first marker (including the closing divs) up to just before the second marker
  # The second marker is the correct one with proper closing tags
  lines_to_remove_start <- end_markers[1] - 1  # Start from the <hr /> before
  lines_to_remove_end <- end_markers[2] - 1    # Up to just before the second marker
  
  cat("\nRemoving lines", lines_to_remove_start, "to", lines_to_remove_end, "\n")
  cat("That's", lines_to_remove_end - lines_to_remove_start + 1, "lines to remove\n")
  
  # Build new content
  updated_lines <- c(
    lines[1:(lines_to_remove_start - 1)],
    lines[(lines_to_remove_end + 1):length(lines)]
  )
  
  # Backup
  backup_file <- paste0("PA_Design_Manual_Combined_backup_cleanup_", 
                        format(Sys.time(), "%Y%m%d_%H%M%S"), ".html")
  writeLines(lines, backup_file)
  cat("\n✓ Backup saved:", backup_file, "\n")
  
  # Write updated file
  writeLines(updated_lines, combined_file)
  
  cat("\n✅ Successfully removed duplicate content!\n")
  cat("Original lines:", length(lines), "\n")
  cat("New lines:", length(updated_lines), "\n")
  cat("Removed:", length(lines) - length(updated_lines), "lines\n")
} else {
  cat("\n⚠️  Expected 2 'End of Chapter 1' markers, found", length(end_markers), "\n")
  cat("Manual inspection needed.\n")
}
