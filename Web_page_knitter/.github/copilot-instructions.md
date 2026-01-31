# Copilot Instructions for Web-page-knitter

## Project Overview
- This is an R Shiny app that generates web pages from files in a folder hierarchy, supporting images, Word, PowerPoint, Excel, and PDF files.
- The app has two main tabs: **Individual Reports** (renders a report for a single folder) and **Master Report** (aggregates individual reports into a hierarchical, linkable web page).
- Key files: `app.R` (main app logic and UI), `Report_generator_ShinyApp.Rmd` (individual report template), `Master_html_report_ShinyApp.Rmd` (master report template), `styles.css`, `bootstrapMint.css` (styling), and `logo.png` (default logo).

## Architecture & Patterns
- Uses a modular Shiny approach: UI and server logic for each tab are encapsulated in `reportTabUI` and `reportTabServer` functions.
- Dynamic UI: Users can add/remove input sections for multiple source/destination folders, titles, authors, and logos.
- Reports are rendered via RMarkdown and copied to a `www/` folder for web access. Linked assets (images, etc.) are also copied and their paths rewritten in the HTML.
- The app cleans up the `www/` folder on restart, preserving only essential assets (see `onStart`).
- Uses the `here` package for robust file path handling.

## Developer Workflows
- To run locally: open `app.R` in RStudio or VS Code with R extension, and run the app (ensure R and required packages are installed).
- The app expects `Report_generator_ShinyApp.Rmd` and `Master_html_report_ShinyApp.Rmd` to be present in the root directory.
- For new file type support, update the RMarkdown templates and the file handling logic in `app.R`.
- Use the `copy_report_to_www` helper to ensure all linked files are web-accessible.

## Conventions & Integration
- All user-uploaded or generated assets are placed in the `www/` directory for serving.
- UI inputs are dynamically generated and tracked via `reactiveValues`.
- File paths from Windows are converted for Linux compatibility using a custom `convert_ishare_path()` function (see `app.R`).
- Styling is handled via custom CSS and Bootswatch themes.

## Examples
- See `app.R` for dynamic section UI generation and report rendering logic.
- The `onStart` function in `app.R` shows how the app manages the `www/` directory lifecycle.

## Key Files
- `app.R`: Main app, UI/server modules, file handling, and startup logic.
- `Report_generator_ShinyApp.Rmd`: RMarkdown template for individual reports which iterates thorugh the source folder path specified by the user in app.R and renders a html page embedding files in the respective hierarchcal manner.
- `Master_html_report_ShinyApp.Rmd`: RMarkdown template for master report.
- `www/`: Output directory for rendered reports and assets.
- `styles.css`, `bootstrapMint.css`: Custom styles.

## Local LLM Integration

- The app supports connecting to local language models (e.g., Ollama) for chat-based report Q&A.
- To use a local model, start Ollama and enter `http://localhost:11434` as the API endpoint in the chatbox.
- Model selection is handled via a dropdown; ensure the model name matches what is available in Ollama (e.g., `tinyllama`, `llama2:7b`).
- The chatbox logic sends prompts to the selected model and displays responses in the UI.

## Asset Path Handling

- Asset files (images, CSS, etc.) are located using the `find_project_file()` helper, which searches the project directory recursively.
- Assets are copied to the `www/` folder before rendering reports.
- All HTML references to assets are rewritten to use only the filename, ensuring they are loaded from `www/`.
- See `copy_report_to_www()` in `app.R` for robust path rewriting logic.

## Supported File Types in Reports

- The report templates (`Report_generator_ShinyApp.Rmd`, etc.) support embedding and linking for:
  - Images (jpg, png, gif, svg)
  - Audio (mp3, wav, ogg) via `<audio>` tags
  - Archives (zip, tar, gz) via download links
  - Markdown (`.md`) rendered as HTML
  - R scripts (`.R`, `.Rmd`) shown as formatted code and downloadable
  - JSON/XML rendered as formatted text or tables
- To add support for new file types, update the file handling logic in the RMarkdown templates.

## Error Handling & Resource Management

- All file operations (rendering, copying, reading) should be wrapped in `tryCatch` to prevent app crashes.
- After rendering reports, call `gc()` to clean up memory.
- Directory permissions and existence are checked before file operations.

### Example: Asset Copy and Path Rewrite

```r
logo_path <- find_project_file("logo.png")
file.copy(logo_path, file.path("www", "logo.png"), overwrite = TRUE)
# In HTML: <img src="logo.png" ...>
---
If you add new features or patterns, update this file with concrete examples and rationale.
