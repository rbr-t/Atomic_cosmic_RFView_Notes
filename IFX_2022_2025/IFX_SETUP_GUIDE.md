# IFX Activity Files - Complete Setup Guide

## Overview

This guide will help you set up and use your IFX activity dashboard with properly working links.

## What Was the Problem?

Your `.Rmd` files contained hardcoded Windows paths like:
- `C:/Users/talluribhaga/Documents/My_IFX_activity/...`

These paths don't work now that the files are in a different location (Linux workspace in VS Code).

## The Solution

Replace all hardcoded paths with **relative paths** that work from anywhere.

## Step-by-Step Instructions

### Step 1: Apply the Path Fixes

Run the automated path fixer script:

```bash
cd /workspaces/Atomic_cosmic_RFView_Notes/IFX_2022_2025
python fix_ifx_paths.py
```

This will:
- ✓ Update all 14 `.Rmd` files
- ✓ Replace Windows paths with relative paths
- ✓ Create backup files (`.Rmd.backup`) for safety
- ✓ Show a summary of all changes

If you want to preview changes first without modifying files:
```bash
python fix_ifx_paths.py --dry-run
```

### Step 2: Verify the Changes

After running the script, check one of the files to verify:

```bash
cd Report_generator_rmd
grep -n "../00_Master_html_file" Master_html_myActivity_IFX.Rmd
```

You should see the relative paths instead of the old Windows paths.

### Step 3: Re-render the HTML Files

You have two options:

#### Option A: Render in VS Code Dev Container (if R is installed)

```bash
cd Report_generator_rmd
Rscript -e "rmarkdown::render('Master_html_myActivity_IFX.Rmd')"
```

#### Option B: Copy files back to your Windows PC and render there

1. Copy the entire `IFX_2022_2025` folder back to your Windows machine
2. Open R Studio
3. Open `Master_html_myActivity_IFX.Rmd`
4. Click "Knit" or run:
   ```r
   rmarkdown::render('Master_html_myActivity_IFX.Rmd')
   ```

### Step 4: View Your Dashboard

1. Navigate to the generated HTML:
   ```
   IFX_2022_2025/Report_generator_rmd/Master_html_myActivity_IFX.html
   ```

2. Open it in a browser:
   - **In VS Code**: Right-click the HTML file → "Open with Live Server" (if installed)
   - **Or**: Double-click the file to open in your default browser

3. Click on categories in the left sidebar (TOC) to load individual reports

## File Structure Explained

```
IFX_2022_2025/
├── Report_generator_rmd/              # Main working directory
│   ├── Master_html_myActivity_IFX.Rmd  # Master dashboard (UPDATED ✓)
│   ├── Master_html_myActivity_IFX.html # Generated dashboard
│   ├── IFX-*.Rmd                       # Individual reports (ALL UPDATED ✓)
│   ├── IFX-*.html                      # Generated reports
│   └── *.Rmd.backup                    # Backup files (safe to delete after verification)
│
├── 00_Master_html_file/               # Copies of generated HTML files
│   └── IFX-*.html
│
├── 01_Administration/                 # Source data folders
├── 02_Projects/
├── 03_PRD/
└── ... (other numbered folders)
```

## How the Links Work Now

### Before (Broken):
```r
dir_path <- "C:/Users/talluribhaga/Documents/My_IFX_activity/00_Master_html_file"
```

### After (Working):
```r
dir_path <- "../00_Master_html_file"
```

The `..` means "go up one directory", so from `Report_generator_rmd/` it goes to `IFX_2022_2025/00_Master_html_file/`.

## Workflow for Future Updates

When you need to update your reports:

1. **Edit the .Rmd files** in `Report_generator_rmd/`
2. **Render individual reports** in R Studio:
   ```r
   rmarkdown::render('IFX-Administration-2022_2026.Rmd')
   ```
3. **Render the master file**:
   ```r
   rmarkdown::render('Master_html_myActivity_IFX.Rmd')
   ```
4. **View the updated dashboard** in your browser

## Advanced: Setting Up R Environment (Optional)

If you want to render directly in VS Code's dev container:

```bash
# Install R (if not already installed)
sudo apt-get update
sudo apt-get install -y r-base

# Install required R packages
Rscript -e "install.packages(c('rmarkdown', 'htmltools', 'knitr', 'here'), repos='https://cran.rstudio.com/')"
```

## Troubleshooting

### Problem: "File not found" errors when viewing HTML

**Solution**: Make sure all HTML files are in the same location structure. The master file expects to find them in:
- `../00_Master_html_file/` OR
- Same directory as the master file

### Problem: CSS/Images not loading

**Solution**: Check that these files exist in `Report_generator_rmd/`:
- `styles.css`
- `bootstrapMint.css`
- `logo.png`

### Problem: Individual report shows broken links to source files

**Solution**: This is expected if source files (PDFs, images, etc.) are not in the workspace. The `.Rmd` files reference local folders that may not be synced.

### Problem: Want to restore original files

**Solution**: The backup files are still there:
```bash
cd Report_generator_rmd
# Restore a single file
cp Master_html_myActivity_IFX.Rmd.backup Master_html_myActivity_IFX.Rmd

# Or restore all files
for f in *.Rmd.backup; do cp "$f" "${f%.backup}"; done
```

## Cleaning Up

Once you've verified everything works, you can delete the backup files:

```bash
cd Report_generator_rmd
rm *.Rmd.backup
```

## Next Steps & Recommendations

1. **Version Control**: Keep the `.Rmd` files in Git, not the HTML files (they can be regenerated)
   
2. **Portable Paths**: The path fix makes your files work anywhere. You can now:
   - Share the folder with colleagues
   - Move it to different computers
   - Keep it in cloud storage (Dropbox, OneDrive, etc.)

3. **Consider Using `here` Package**: For even more robustness, use R's `here` package:
   ```r
   library(here)
   dir_path <- here("00_Master_html_file")
   ```

4. **Web Deployment** (optional): For the best experience, consider:
   - GitHub Pages: Host the HTML files as a website
   - R Shiny: Create an interactive dashboard
   - Quarto: Modern R Markdown alternative with better web support

## Files Created by This Setup

- `LINK_FIX_SOLUTION.md` - Detailed technical explanation
- `IFX_SETUP_GUIDE.md` - This file (user-friendly guide)
- `fix_ifx_paths.py` - Automated path fixing script
- `Report_generator_rmd/*.Rmd.backup` - Backup copies of original files

## Questions or Issues?

If you encounter any problems:

1. Check the backup files are intact
2. Review the LINK_FIX_SOLUTION.md for technical details
3. Run the script again with `--dry-run` to see what would change
4. Make sure you're running R commands from the correct directory

---

**Last Updated**: January 31, 2026
**Status**: ✓ All path fixes applied and ready to use
