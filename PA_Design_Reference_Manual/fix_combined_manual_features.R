#!/usr/bin/env Rscript

# Fix Combined Manual Features
# 1. Add glossary CSS and JavaScript
# 2. Add Plotly library 
# 3. Ensure Plotly plots are properly embedded

combined_file <- "PA_Design_Manual_Combined.html"

# Read the combined file
cat("Reading combined HTML file...\n")
lines <- readLines(combined_file, warn = FALSE)

# Create backup
backup_file <- paste0("PA_Design_Manual_Combined_backup_features_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html")
writeLines(lines, backup_file)
cat(sprintf("✓ Backup saved: %s\n\n", backup_file))

# Find the head section end
head_end <- grep("</head>", lines)[1]

if (!is.na(head_end)) {
  # Add glossary CSS
  glossary_css <- c(
    "",
    "<!-- Glossary Styles -->",
    "<style>",
    ".glossary-term {",
    "  position: relative;",
    "  color: #0066cc;",
    "  font-weight: 600;",
    "  cursor: help;",
    "  border-bottom: 1px dotted #0066cc;",
    "  padding-bottom: 1px;",
    "}",
    "",
    ".glossary-term:hover {",
    "  color: #004499;",
    "  border-bottom-color: #004499;",
    "}",
    "",
    ".glossary-content {",
    "  display: none;",
    "  position: absolute;",
    "  z-index: 1000;",
    "  background-color: #f9f9f9;",
    "  border: 2px solid #0066cc;",
    "  border-radius: 8px;",
    "  padding: 15px;",
    "  box-shadow: 0 4px 6px rgba(0,0,0,0.2);",
    "  min-width: 300px;",
    "  max-width: 500px;",
    "  left: 0;",
    "  top: 100%;",
    "  margin-top: 5px;",
    "}",
    "",
    ".glossary-content.show {",
    "  display: block;",
    "}",
    "",
    ".glossary-icon {",
    "  margin-left: 3px;",
    "  font-size: 0.85em;",
    "  vertical-align: super;",
    "}",
    "",
    "/* Mobile responsive */",
    "@media screen and (max-width: 768px) {",
    "  .glossary-content {",
    "    position: fixed;",
    "    left: 5% !important;",
    "    right: 5%;",
    "    top: auto !important;",
    "    bottom: 10%;",
    "    max-width: 90%;",
    "    min-width: auto;",
    "  }",
    "}",
    "</style>",
    ""
  )
  
  # Add glossary JavaScript
  glossary_js <- c(
    "<!-- Glossary JavaScript -->",
    "<script>",
    "document.addEventListener('DOMContentLoaded', function() {",
    "  // Add click handlers to glossary terms",
    "  const glossaryTerms = document.querySelectorAll('.glossary-term');",
    "  ",
    "  glossaryTerms.forEach(term => {",
    "    term.addEventListener('click', function(e) {",
    "      e.preventDefault();",
    "      e.stopPropagation();",
    "      ",
    "      // Get the target glossary content",
    "      const targetId = this.getAttribute('data-term');",
    "      const glossaryContent = document.getElementById(targetId);",
    "      ",
    "      if (glossaryContent) {",
    "        // Close all other glossaries",
    "        document.querySelectorAll('.glossary-content.show').forEach(content => {",
    "          if (content !== glossaryContent) {",
    "            content.classList.remove('show');",
    "          }",
    "        });",
    "        ",
    "        // Toggle this glossary",
    "        glossaryContent.classList.toggle('show');",
    "      }",
    "    });",
    "  });",
    "  ",
    "  // Close glossaries when clicking outside",
    "  document.addEventListener('click', function(e) {",
    "    if (!e.target.closest('.glossary-term')) {",
    "      document.querySelectorAll('.glossary-content.show').forEach(content => {",
    "        content.classList.remove('show');",
    "      });",
    "    }",
    "  });",
    "});",
    "</script>",
    ""
  )
  
  # Check if Plotly is already loaded
  has_plotly <- any(grepl("plotly.*\\.js", lines))
  
  plotly_script <- character(0)
  if (!has_plotly) {
    cat("Adding Plotly library...\n")
    plotly_script <- c(
      "<!-- Plotly Library -->",
      "<script src=\"https://cdn.plot.ly/plotly-2.27.0.min.js\" charset=\"utf-8\"></script>",
      ""
    )
  } else {
    cat("Plotly library already present\n")
  }
  
  # Insert all additions before </head>
  updated_lines <- c(
    lines[1:(head_end-1)],
    glossary_css,
    glossary_js,
    plotly_script,
    lines[head_end:length(lines)]
  )
  
  # Write the updated file
  writeLines(updated_lines, combined_file)
  
  cat("\n✅ Successfully added features to combined manual!\n\n")
  cat("Changes made:\n")
  cat("  ✓ Added glossary CSS styles\n")
  cat("  ✓ Added glossary JavaScript for click interactions\n")
  if (!has_plotly) {
    cat("  ✓ Added Plotly library\n")
  }
  cat("\nOriginal lines:", length(lines), "\n")
  cat("New lines:", length(updated_lines), "\n")
  cat("Added:", length(updated_lines) - length(lines), "lines\n")
  
} else {
  cat("Error: Could not find </head> tag\n")
}
