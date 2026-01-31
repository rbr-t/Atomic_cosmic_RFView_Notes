# IFX Activity Dashboard (2022-2025)

A collection of R Markdown reports documenting your Infineon (IFX) activities from 2022-2025, including administration, projects, conferences, and technical work.

## 📁 What's Inside

```
IFX_2022_2025/
├── Report_generator_rmd/      # 📝 Main working directory
│   ├── Master_html_myActivity_IFX.Rmd    # Dashboard master file
│   └── IFX-*.Rmd                         # Individual report files
│
├── 00_Master_html_file/       # 🌐 Generated HTML copies
├── 01_Administration/         # 📋 Administrative documents
├── 02_Projects/               # 🎯 Project files
├── 03_PRD/                    # 👤 Personal review dialogue
├── 04_Conferences/            # 🎤 Conference materials
├── 05_Study_Material/         # 📚 Learning resources
├── 06_Business_Trips/         # ✈️ Travel documentation
├── 07_Technical_reports/      # 📊 Technical reports
├── 08_Competition/            # 🏆 Competitive analysis
├── 09_My_presentations/       # 🎯 Your presentations
└── 10_IFX_internal_trainings/ # 🎓 Training materials
```

## 🚀 Quick Start

### View the Dashboard

1. Navigate to: `Report_generator_rmd/`
2. Open: `Master_html_myActivity_IFX.html` in a web browser
3. Click categories in the left sidebar to view individual reports

### Update/Regenerate Reports

1. Open R Studio
2. Navigate to `Report_generator_rmd/`
3. Open `Master_html_myActivity_IFX.Rmd`
4. Click "Knit" to regenerate the dashboard

## ✅ Recent Updates (Jan 31, 2026)

All hardcoded Windows paths have been replaced with relative paths:
- ✅ Works on any operating system
- ✅ Portable and shareable
- ✅ No reconfiguration needed
- ✅ Version control friendly

**See documentation files for details:**
- 📖 **IFX_SETUP_GUIDE.md** - Complete setup instructions
- 📋 **IFX_QUICK_REFERENCE.md** - Quick command reference
- 🔧 **LINK_FIX_SOLUTION.md** - Technical details
- 🐍 **fix_ifx_paths.py** - Path fixing script

## 📊 Dashboard Features

The master dashboard (`Master_html_myActivity_IFX.html`) provides:
- **Hierarchical navigation** - Organized by IFX, category, and topic
- **Iframe viewer** - Preview reports without opening files
- **Collapsible TOC** - Toggle sidebar for more viewing space
- **Responsive layout** - Works on different screen sizes

## 📝 Report Categories

| Category | File Prefix | Content |
|----------|------------|---------|
| Administration | IFX-Administration | Contracts, HR, salary, courses |
| Business Trips | IFX-Business_Trips | Travel bookings and expenses |
| Conferences | IFX-Conference_Presentations | Conference attendance and talks |
| Presentations | IFX-My_presentation | Your presentations and talks |
| Projects | IFX-Project-* | Project documentation (Tx, PAM, Competition) |
| PRD | IFX-Personal_review_dialogue | Performance review materials |
| Technical Reports | IFX-Technical_Reports | Technical documentation |
| Training | IFX-Trainings-Internal | Internal training materials |
| Study Materials | IFX-Study_Material-Docs | Learning resources |
| Organization | IFX-Organization-chart | Org charts and structure |
| Offboarding | IFX-offboarding-offer | Exit documentation |

## 🛠️ Technology Stack

- **R Markdown** - Document authoring
- **htmltools** - HTML generation
- **knitr** - Dynamic report generation
- **yeti theme** - Bootstrap-based styling
- **Custom CSS** - styles.css, bootstrapMint.css

## 🔄 Workflow

### Adding New Content

1. Add source files to appropriate numbered folder
2. Update or create corresponding `.Rmd` file in `Report_generator_rmd/`
3. Render the individual report in R Studio
4. Re-render the master dashboard to include it

### Maintaining Reports

- **Edit**: Modify `.Rmd` files, not `.html` files
- **Render**: Use R Studio's "Knit" button or `rmarkdown::render()`
- **Backup**: `.Rmd.backup` files available for safety
- **Version Control**: Commit `.Rmd` files, not `.html` (can regenerate)

## 📦 Requirements

### To View
- Any modern web browser (Chrome, Firefox, Safari, Edge)
- No special software needed

### To Edit/Regenerate
- R (>= 4.0.0)
- R Studio (recommended)
- R packages:
  - rmarkdown
  - htmltools
  - knitr
  - here
  - gt, gtExtras (for tables)
  - readxl, xlsx (for Excel files)
  - pdftools (for PDF processing)

Install packages in R:
```r
install.packages(c("rmarkdown", "htmltools", "knitr", "here", 
                   "gt", "gtExtras", "readxl", "xlsx", "pdftools"))
```

## 🔐 Privacy Note

This folder may contain personal and confidential work information. Keep appropriate access controls when:
- Sharing with colleagues
- Uploading to cloud storage
- Committing to version control

Consider:
- Using private repositories
- Encrypting sensitive files
- Removing personal paths/names before sharing
- Following company data policies

## 📞 Support

If you encounter issues:
1. Check **IFX_SETUP_GUIDE.md** for troubleshooting
2. Review **LINK_FIX_SOLUTION.md** for technical details
3. Verify `.Rmd.backup` files exist for recovery
4. Run `python fix_ifx_paths.py --dry-run` to check paths

## 📜 Change Log

### 2026-01-31
- Fixed all hardcoded Windows paths → relative paths
- Created comprehensive documentation
- Added automated path fixing script
- Created backup copies of all .Rmd files

### Original Creation
- Created master dashboard structure
- Organized reports by category
- Implemented iframe-based viewer
- Added custom styling

---

**Maintained by**: BT  
**Period**: 2022-2025  
**Last Updated**: January 31, 2026  
**Status**: ✅ Active and ready to use
