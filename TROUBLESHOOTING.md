# 🚨 TROUBLESHOOTING: Cannot Render the Document

## Quick Diagnosis

If you're unable to run the app and view the HTML output, follow these steps:

### Step 1: Run the Diagnostic Script

```bash
cd /path/to/Atomic_cosmic_RFView_Notes
Rscript render_document.R
```

This will tell you exactly what's missing.

### Step 2: Install Missing Packages

The most common issue is the **flexdashboard** package not being installed.

#### Option A: Install from CRAN (Recommended)

```bash
# If you have internet access to CRAN
Rscript -e "install.packages('flexdashboard', repos='https://cloud.r-project.org/', dependencies=TRUE)"
```

#### Option B: Install from GitHub

```bash
# If CRAN is not accessible
Rscript -e "remotes::install_github('rstudio/flexdashboard')"
```

#### Option C: Use System Packages (Linux/Ubuntu)

```bash
# First install the main packages
sudo apt-get update
sudo apt-get install r-cran-rmarkdown r-cran-knitr r-cran-ggplot2 r-cran-devtools

# Then install flexdashboard from GitHub
Rscript -e "remotes::install_github('rstudio/flexdashboard')"
```

#### Option D: Manual Installation

If you have persistent network issues:

1. Download flexdashboard from: https://github.com/rstudio/flexdashboard/archive/refs/heads/main.zip
2. Extract the ZIP file
3. Install from local directory:
```R
install.packages("/path/to/flexdashboard-main", repos = NULL, type = "source")
```

### Step 3: Verify Installation

```bash
Rscript -e "library(flexdashboard); cat('✓ flexdashboard installed successfully\n')"
```

### Step 4: Render the Document

Once all packages are installed:

```bash
# Method 1: Use the render script (with better error messages)
Rscript render_document.R

# Method 2: Direct rendering
Rscript -e "rmarkdown::render('Atomic_Cosmic_RFView.Rmd')"

# Method 3: In RStudio
# Open Atomic_Cosmic_RFView.Rmd and click "Knit"
```

## Common Issues and Solutions

### Issue 1: "package 'flexdashboard' is not available"

**Cause**: CRAN mirror not accessible or package not in repository

**Solutions**:
- Try a different CRAN mirror: `options(repos = c(CRAN = 'https://cran.rstudio.com/'))`
- Install from GitHub (see Option B above)
- Check your internet connection

### Issue 2: "unable to install packages" or permission errors

**Cause**: Trying to install to system library without permissions

**Solution**: Create and use a user library
```R
user_lib <- file.path(Sys.getenv("HOME"), "R", "library")
dir.create(user_lib, recursive = TRUE)
.libPaths(c(user_lib, .libPaths()))
install.packages("flexdashboard", lib = user_lib)
```

### Issue 3: "pandoc not found"

**Cause**: Pandoc not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install pandoc

# macOS
brew install pandoc

# Windows: Download from https://pandoc.org/installing.html
```

### Issue 4: Network/Proxy Issues

**Cause**: Firewall or proxy blocking CRAN access

**Solutions**:
1. Configure proxy in R:
```R
Sys.setenv(http_proxy = "http://proxy.example.com:port")
Sys.setenv(https_proxy = "http://proxy.example.com:port")
```

2. Download packages manually and install offline

3. Use a different network

### Issue 5: Old R Version

**Cause**: R version too old for recent packages

**Solution**: Update R to at least version 4.0
```bash
# Check R version
R --version

# Update R (Ubuntu/Debian)
sudo apt-get update
sudo apt-get upgrade r-base r-base-dev
```

## Alternative: Use RStudio

RStudio includes many R packages by default and makes installation easier:

1. Install RStudio Desktop: https://posit.co/download/rstudio-desktop/
2. Open RStudio
3. Go to Tools → Install Packages
4. Type: `flexdashboard` and click Install
5. Open `Atomic_Cosmic_RFView.Rmd`
6. Click the "Knit" button

## Testing Your Setup

Run this comprehensive test:

```R
# Test script
cat("=== R Environment Test ===\n")
cat("R version:", as.character(getRversion()), "\n")
cat("Platform:", R.version$platform, "\n\n")

packages <- c("rmarkdown", "knitr", "ggplot2", "flexdashboard")
for (pkg in packages) {
  status <- if (requireNamespace(pkg, quietly = TRUE)) "✓" else "✗"
  cat(sprintf("%s %s\n", status, pkg))
}

cat("\nPandoc:", as.character(rmarkdown::pandoc_version()), "\n")
cat("\nLibrary paths:\n")
cat(paste(.libPaths(), collapse = "\n"), "\n")
```

Save as `test_setup.R` and run:
```bash
Rscript test_setup.R
```

## Getting Help

If you're still having issues:

1. Run `Rscript render_document.R` and copy the full error message
2. Check the R session info: `Rscript -e "sessionInfo()"`
3. Report the issue with:
   - Your operating system
   - R version
   - Error messages
   - Output of render_document.R

## Quick Fix: Simplified Version

If you absolutely cannot install flexdashboard, I can provide a simplified HTML version that works with just rmarkdown. Let me know if you need this alternative.

---

**Most Common Solution**: Just run this one command:

```bash
Rscript -e "install.packages('flexdashboard', repos='https://cloud.r-project.org/')"
```

Then try rendering again!
