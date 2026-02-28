#!/bin/bash

# Script to render Chapter 01 with proper library paths
# This will work once all R packages finish installing

echo "Checking for required packages..."

# Set R library path
export R_LIBS_USER=~/R/library

# Check if rmarkdown is available
if Rscript -e "library(rmarkdown)" 2>&1 | grep -q "Error"; then
    echo "ERROR: rmarkdown package not yet installed"
    echo "The package installation is still ongoing. Please wait and try again."
    exit 1
fi

# Check if plotly is available  
if Rscript -e "library(plotly)" 2>&1 | grep -q "Error"; then
    echo "ERROR: plotly package not yet installed"
    echo "The package installation is still ongoing. Please wait and try again."
    exit 1
fi

# Check if ggplot2 is available
if Rscript -e "library(ggplot2)" 2>&1 | grep -q "Error"; then
    echo "ERROR: ggplot2 package not yet installed"
    echo "The package installation is still ongoing. Please wait and try again."
    exit 1
fi

echo "All required packages found! Starting render..."

# Change to the chapter directory
cd /workspaces/Atomic_cosmic_RFView_Notes/PA_Design_Reference_Manual/Chapters

# Render the document
Rscript -e ".libPaths('~/R/library'); rmarkdown::render('Chapter_01_Transistor_Fundamentals.Rmd', output_file='Chapter_01_Transistor_Fundamentals.html')"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SUCCESS! HTML document generated:"
    echo "   /workspaces/Atomic_cosmic_RFView_Notes/PA_Design_Reference_Manual/Chapters/Chapter_01_Transistor_Fundamentals.html"
    echo ""
    echo "Opening in browser..."
    "$BROWSER" Chapter_01_Transistor_Fundamentals.html
else
    echo "❌ ERROR: Rendering failed. Check the output above for details."
    exit 1
fi
