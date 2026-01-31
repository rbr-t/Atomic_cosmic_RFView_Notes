# Link Fix Solution for IFX Activity Files

## Problem Analysis

Your master file and individual .Rmd files contain hardcoded Windows paths like:
- `C:/Users/talluribhaga/Documents/My_IFX_activity/00_Master_html_file`
- `C:/Users/talluribhaga/Documents/My_IFX_activity/10_IFX_internal_trainings/`

These paths don't work in the current Linux workspace environment.

## Current Structure

```
IFX_2022_2025/
├── 00_Master_html_file/          # Contains all generated HTML files
├── Report_generator_rmd/         # Contains all .Rmd source files and their HTML outputs
│   ├── Master_html_myActivity_IFX.Rmd  # Master dashboard
│   ├── IFX-Administration-2022_2026.Rmd
│   ├── IFX-Business_Trips-2022_2026.Rmd
│   └── ... (other .Rmd files)
└── 01_Administration/            # Source data folders
    02_Projects/
    03_PRD/
    etc.
```

## Comprehensive Solution

### 1. **Update Master File Path References**

The master file needs to:
- Point to the correct relative location of HTML files
- Use either `00_Master_html_file` folder OR `Report_generator_rmd` folder

**Recommended approach**: Keep HTML files in `00_Master_html_file` and use relative path `../00_Master_html_file/`

### 2. **Update Individual .Rmd Files**

Each individual .Rmd file has two types of paths to fix:
- **Input paths**: Where it reads source data (e.g., `wd <- file.path("C:/Users/...")`)
- **Output paths**: Where it copies generated HTML (e.g., `output_file <- file.path("C:/Users/.../00_Master_html_file")`)

### 3. **Mapping of Old Paths to New Paths**

| Old Windows Path | New Relative Path (from Report_generator_rmd) |
|-----------------|-----------------------------------------------|
| `C:/Users/talluribhaga/Documents/My_IFX_activity/00_Master_html_file` | `../00_Master_html_file` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/01_Administration/` | `../01_Administration/` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/02_Projects/` | `../02_Projects/` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/03_PRD/` | `../03_PRD/` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/06_Business_Trips/` | `../06_Business_Trips/` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/08_Competition/` | `../08_Competition/` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/09_My_presentations` | `../09_My_presentations` |
| `C:/Users/talluribhaga/Documents/My_IFX_activity/10_IFX_internal_trainings/` | `../10_IFX_internal_trainings/` |

### 4. **Files Requiring Updates**

All these .Rmd files need path corrections:
1. `Master_html_myActivity_IFX.Rmd` - Master file
2. `IFX-Administration-2022_2026.Rmd`
3. `IFX-Business_Trips-2022_2026.Rmd`
4. `IFX-Conference_Presentations-2022_2026.Rmd`
5. `IFX-My_presentation-2022_2026.Rmd`
6. `IFX-Personal_review_dialogue-All_STEPS.Rmd`
7. `IFX-Project-Competition_Reports.Rmd`
8. `IFX-Project-PAM_B_2023.Rmd`
9. `IFX-Project-Tx_Baseline_2022.Rmd`
10. `IFX-Technical_Reports-All.Rmd`
11. `IFX-Trainings-Internal.Rmd`
12. `IFX-offboarding-offer.Rmd`
13. `IFX-Organization-chart.Rmd`
14. `IFX-Study_Material-Docs.Rmd`

### 5. **Automated Fix Script**

A Python script `fix_ifx_paths.py` will:
- Scan all .Rmd files in Report_generator_rmd
- Replace hardcoded Windows paths with relative paths
- Create backups before modifying
- Generate a report of all changes

### 6. **How Links Will Work After Fix**

After rendering in R Studio:
1. Open `Master_html_myActivity_IFX.html` in a browser
2. Click on any category/subcategory in the TOC
3. The corresponding HTML will load in the iframe on the right
4. All relative paths will resolve correctly from the current workspace location

### 7. **Best Practices Going Forward**

1. **Use `here` package in R**: Instead of hardcoded paths, use `here::here()` for portable paths
2. **Keep generated HTML in one place**: Either all in `00_Master_html_file` or all in `Report_generator_rmd`
3. **Use relative paths**: Always use relative paths for links between files
4. **Version control**: Keep .Rmd files in version control, not HTML files (they can be regenerated)

### 8. **Alternative: Deploy as Web App**

For even better portability, consider:
- Using R Shiny to create an interactive dashboard
- Deploying to GitHub Pages or similar service
- All files accessible via URLs instead of file paths
