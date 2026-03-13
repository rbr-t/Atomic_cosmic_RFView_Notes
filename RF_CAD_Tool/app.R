# =============================================================================
# app.R  –  RF CAD Tool standalone entry point
#
# Run with:  shiny::runApp("RF_CAD_Tool")
# Or:        Rscript -e "shiny::runApp('RF_CAD_Tool', port=6060, launch.browser=TRUE)"
# =============================================================================
library(shiny)

source("R/ui.R")
source("R/server.R")

shinyApp(ui = ui, server = server)
