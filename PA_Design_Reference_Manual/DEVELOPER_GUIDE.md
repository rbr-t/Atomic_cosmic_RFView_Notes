# PA Design Reference Manual - Developer Guide

**Version**: 1.1  
**Last Updated**: February 1, 2026  
**Project Status**: Active Development - Week 2  
**Target Audience**: Future developers, maintainers, and contributors

---

## 🎯 Project Overview

### Mission
Create a comprehensive, evidence-based Power Amplifier Design Reference Manual that:
1. Documents real-world PA design experience from IFX projects
2. Serves as an interview preparation and reference resource
3. Enables automated PA design through structured prompting framework

### Core Principles
- **Quality over Quantity**: Accurate, well-researched content
- **Truthfulness**: Evidence-based with proper attribution
- **Rationale**: Clear reasoning for every design decision
- **Simplicity**: Complex concepts explained clearly
- **Professional**: Industry-standard practices and workflows
- **Incremental**: Small, testable, verifiable steps
- **Platform Independent**: Works on any system
- **Reusable**: Modular components for easy extension
- **Scalable**: Architecture supports growth

---

## 📁 Project Structure

```
PA_Design_Reference_Manual/
│
├── README.md                          # Project overview and quick start
├── DEVELOPER_GUIDE.md                 # This file - onboarding for new devs
├── PROJECT_STATUS.Rmd                 # Live tracking document
├── PROJECT_STATUS.html                # Rendered status dashboard
├── PA_Design_Project_Plan.Rmd         # Master plan document
├── PA_Design_Project_Plan.html        # Rendered plan
│
├── data_extraction/                   # Phase 1: Data extraction
│   ├── extraction_scripts/            # Automated extraction tools
│   ├── raw_data/                      # Copied/extracted source data
│   ├── processed_data/                # Cleaned, structured data
│   └── extraction_log.md              # What was extracted and from where
│
├── manual_chapters/                   # Phase 2: Manual development
│   ├── ch01_fundamentals/
│   │   ├── ch01_fundamentals.Rmd      # Main chapter file
│   │   ├── figures/                   # Chapter-specific figures
│   │   ├── data/                      # Chapter-specific data
│   │   └── references.bib             # Chapter-specific references
│   ├── ch02_loadpull/
│   ├── ch03_linearization/
│   ├── ch04_efficiency/
│   ├── ch05_thermal/
│   └── ch06_integration/
│
├── shared_resources/                  # Common resources
│   ├── styles/
│   │   ├── main.css                   # Main stylesheet
│   │   └── print.css                  # Print-friendly styles
│   ├── scripts/
│   │   ├── utils.R                    # Utility functions
│   │   ├── plotting.R                 # Common plotting functions
│   │   └── table_formatting.R         # Table styling functions
│   ├── figures/                       # Shared figures/diagrams
│   └── templates/
│       ├── chapter_template.Rmd       # Template for new chapters
│       └── section_template.Rmd       # Template for sections
│
├── automation_framework/              # Phase 3: Automation system
│   ├── prompt_templates/              # Structured prompts for PA design
│   ├── design_flows/                  # Automated design workflows
│   ├── validation_rules/              # Design rule checks
│   └── automation_manual.md           # How to use automation
│
├── output/                            # Generated output files
│   ├── PA_Design_Manual_v1.0.html     # Final manual (self-contained)
│   ├── PA_Design_Manual_v1.0.pdf      # PDF version (optional)
│   └── chapter_outputs/               # Individual chapter outputs
│
├── tests/                             # Testing and validation
│   ├── unit_tests/                    # Function tests
│   ├── integration_tests/             # End-to-end tests
│   └── validation_data/               # Known-good outputs for comparison
│
└── docs/                              # Additional documentation
    ├── architecture.md                # System architecture
    ├── coding_standards.md            # Style guide
    ├── data_sources.md                # Documentation of data origins
    └── changelog.md                   # Version history
```

---

## 🏗️ Architecture Principles

### 1. Modularity
- Each chapter is self-contained but can be combined
- Shared functions in `shared_resources/scripts/`
- Reusable CSS in `shared_resources/styles/`
- Bibliography can be chapter-specific or global

### 2. Reproducibility
- All code chunks should be reproducible
- Data extraction scripts documented
- Random seeds set where applicable
- Package versions documented

### 3. Platform Independence
- Use relative paths only (within project)
- Avoid OS-specific commands
- Self-contained HTML output (no external dependencies)
- Cross-platform R packages only

### 4. Scalability
- Template-based chapter creation
- Automated numbering systems
- Centralized style management
- Modular automation framework

### 5. Version Control
- Git for all source files
- Meaningful commit messages
- Branch strategy: `main` (stable), `develop` (active), `feature/*` (new work)
- Tag releases: `v1.0`, `v1.1`, etc.

---

## 🛠️ Technology Stack

### Core Technologies
- **R**: Version 4.x+ (primary language)
- **R Markdown**: Document authoring
- **Knitr**: Dynamic report generation
- **Pandoc**: Document conversion (included with RStudio)

### Required R Packages
```r
# Core packages
install.packages(c(
  "rmarkdown",      # Document rendering
  "knitr",          # Code execution and reporting
  "bookdown"        # Enhanced R Markdown features
))

# Data manipulation
install.packages(c(
  "dplyr",          # Data wrangling
  "tidyr",          # Data tidying
  "readr",          # Fast data reading
  "readxl"          # Excel file support
))

# Visualization
install.packages(c(
  "ggplot2",        # Grammar of graphics plotting
  "plotly",         # Interactive plots
  "patchwork"       # Combining plots
))

# Tables
install.packages(c(
  "kableExtra",     # Enhanced table formatting
  "DT",             # Interactive DataTables
  "gt"              # Grammar of tables
))

# Utilities
install.packages(c(
  "htmltools",      # HTML manipulation
  "here",           # Project-relative paths
  "glue",           # String interpolation
  "stringr"         # String manipulation
))
```

### Development Environment
- **Recommended**: RStudio 2023.x+ or VS Code with R extension
- **Git**: For version control
- **Pandoc**: Comes with RStudio, or install separately

---

## 🚀 Getting Started

### For New Developers

#### 1. Initial Setup
```bash
# Clone the repository
cd /workspaces/Atomic_cosmic_RFView_Notes/PA_Design_Reference_Manual/

# Install R packages
Rscript -e "source('install_dependencies.R')"

# Verify setup
Rscript -e "source('verify_setup.R')"
```

#### 2. Understand the Project
1. Read `PA_Design_Project_Plan.html` - Overall strategy
2. Read `PROJECT_STATUS.html` - Current state
3. Review this `DEVELOPER_GUIDE.md`
4. Check `data_sources.md` - Where data comes from

#### 3. Run a Test Build
```r
# In R console
setwd("/workspaces/Atomic_cosmic_RFView_Notes/PA_Design_Reference_Manual/")
rmarkdown::render("PROJECT_STATUS.Rmd")
```

#### 4. Review Coding Standards
- Read `docs/coding_standards.md`
- Review existing code in `shared_resources/scripts/`
- Check example chapter structure

---

## 📝 Development Workflow

### Adding a New Chapter

1. **Copy Template**
```bash
cp -r shared_resources/templates/chapter_template.Rmd \
      manual_chapters/chXX_topic/chXX_topic.Rmd
```

2. **Update Chapter Metadata**
```yaml
---
title: "Chapter XX: Topic Name"
author: "PA Design Manual"
date: "`r Sys.Date()`"
---
```

3. **Follow Structure**
   - Introduction & Motivation
   - Theoretical Foundation
   - Design Methodology
   - Practical Examples (from IFX data)
   - Simulation/Measurement Evidence
   - Trends & Current Status
   - Future Directions
   - Lessons Learned
   - Key Takeaways
   - References

4. **Use Shared Resources**
```r
# Source utility functions
source(here::here("shared_resources/scripts/utils.R"))

# Use common plotting functions
source(here::here("shared_resources/scripts/plotting.R"))
```

5. **Test Render**
```r
rmarkdown::render("manual_chapters/chXX_topic/chXX_topic.Rmd")
```

6. **Update Status**
   - Update `PROJECT_STATUS.Rmd` with progress
   - Commit changes with meaningful message

### Working with Data

1. **Extract from Source**
```r
# Use extraction scripts
source("data_extraction/extraction_scripts/extract_loadpull_data.R")
```

2. **Document Source**
   - Log in `data_extraction/extraction_log.md`
   - Include: source file, date, extraction method, any processing

3. **Store Appropriately**
   - Raw data → `data_extraction/raw_data/`
   - Processed data → `data_extraction/processed_data/`
   - Chapter-specific → `manual_chapters/chXX/data/`

4. **Use Reproducibly**
```r
# Load processed data
data <- readr::read_csv(
  here::here("data_extraction/processed_data/loadpull_results.csv")
)
```

### Creating Reusable Functions

1. **Identify Common Patterns**
   - Repeated plotting code?
   - Common data transformations?
   - Frequent table formatting?

2. **Create Function in Appropriate Script**
```r
# shared_resources/scripts/plotting.R

#' Plot Smith Chart with PA Load Data
#' 
#' @param data Data frame with columns: freq, real, imag
#' @param title Plot title
#' @return ggplot object
plot_smith_chart <- function(data, title = "Smith Chart") {
  # Implementation
}
```

3. **Document with Roxygen**
   - Brief description
   - Parameter descriptions
   - Return value
   - Example usage

4. **Test Function**
```r
# tests/unit_tests/test_plotting.R
testthat::test_that("Smith chart plotting works", {
  # Test code
})
```

---

## 🎨 Coding Standards

### R Code Style
- Follow [Tidyverse Style Guide](https://style.tidyverse.org/)
- Use `<-` for assignment, not `=`
- Maximum line length: 80 characters
- Use snake_case for function and variable names
- Add comments for non-obvious code

### R Markdown Structure
```r
# Good chunk naming
```{r load-data, include=FALSE}
data <- read_csv("data.csv")
```

# Clear chunk options
```{r plot-results, fig.width=8, fig.height=6, fig.cap="Load-Pull Results"}
plot(data)
```
```

### File Naming
- Chapters: `ch01_fundamentals.Rmd`
- Scripts: `utils.R`, `plotting_functions.R`
- Data: `loadpull_data_2023.csv`
- Figures: `fig_01_smith_chart.png`

### Git Commit Messages
```
feat: Add Chapter 2 Load-Pull Analysis
fix: Correct Smith chart scaling issue
docs: Update DEVELOPER_GUIDE with testing info
refactor: Modularize plotting functions
```

---

## 🧪 Testing & Validation

### Manual Testing
1. Render each chapter individually
2. Check figure quality and numbering
3. Verify all references resolve
4. Test on different browsers (for HTML)

### Automated Checks
```r
# Run validation script
source("tests/validate_manual.R")

# Checks performed:
# - All figures exist
# - All references valid
# - No broken links
# - Chapter numbering correct
# - Code chunks execute without error
```

### Quality Checklist
- [ ] All facts verified against source data
- [ ] Figures are clear and properly labeled
- [ ] Equations are correctly formatted (LaTeX)
- [ ] References properly cited
- [ ] Code is reproducible
- [ ] Cross-references work
- [ ] HTML output is self-contained

---

## 📚 Key Resources & References

### Internal Documentation
- `PA_Design_Project_Plan.html` - Master plan
- `PROJECT_STATUS.html` - Live status
- `data_sources.md` - Data provenance
- `architecture.md` - System design

### External References
- [R Markdown Cookbook](https://bookdown.org/yihui/rmarkdown-cookbook/)
- [R Markdown Guide](https://bookdown.org/yihui/rmarkdown/)
- [Bookdown Documentation](https://bookdown.org/yihui/bookdown/)
- [Tidyverse Style Guide](https://style.tidyverse.org/)

### Example Projects
- `Atomic_Cosmic_RFView.Rmd` - Proven template structure
- IFX project files - Source data and evidence

---

## 🐛 Troubleshooting

### Common Issues

#### Rendering Fails
```r
# Check package versions
sessionInfo()

# Update packages
update.packages(ask = FALSE)

# Clear cache
knitr::clean_cache()
```

#### Figures Not Appearing
- Check file paths (use `here::here()`)
- Verify figure files exist
- Check chunk options: `fig.path`, `fig.width`, etc.

#### References Not Resolving
- Verify BibTeX syntax
- Check bibliography file path in YAML
- Ensure citation keys match

#### Out of Memory
- Process data in chunks
- Use `rm()` to clean up large objects
- Increase R memory limit if needed

---

## 🔄 Maintenance & Updates

### Regular Tasks
- **Weekly**: Update PROJECT_STATUS.Rmd
- **Per Chapter**: Update extraction_log.md
- **Per Milestone**: Git tag and backup
- **Monthly**: Review and refactor code

### Updating This Guide
When project evolves:
1. Update relevant sections
2. Add examples for new patterns
3. Document new dependencies
4. Update architecture diagrams

---

## 📞 Handover Checklist

When transitioning to a new developer:

- [ ] Walk through project structure
- [ ] Explain data sources and extraction process
- [ ] Review current PROJECT_STATUS.html
- [ ] Demonstrate rendering workflow
- [ ] Show how to run tests
- [ ] Grant repository access
- [ ] Share credentials (if any)
- [ ] Schedule follow-up questions session

---

## 🎯 Quick Reference Commands

```r
# Render status document
rmarkdown::render("PROJECT_STATUS.Rmd")

# Render a chapter
rmarkdown::render("manual_chapters/ch01_fundamentals/ch01_fundamentals.Rmd")

# Render entire manual (when combined)
rmarkdown::render("PA_Design_Manual.Rmd")

# Run tests
source("tests/validate_manual.R")

# Check dependencies
source("verify_setup.R")

# Clean outputs
unlink("output/*", recursive = TRUE)
```

---

## 📈 Success Metrics

A successful handover means the new developer can:
1. ✅ Understand the project goals and architecture
2. ✅ Navigate the folder structure confidently
3. ✅ Add a new chapter following the template
4. ✅ Extract and integrate new data
5. ✅ Run tests and validation
6. ✅ Update documentation
7. ✅ Commit changes with proper messages
8. ✅ Continue development with minimal support

---

## 🙏 Contributing

### How to Contribute
1. Check PROJECT_STATUS.html for current priorities
2. Pick a task or suggest improvements
3. Create a feature branch
4. Follow coding standards
5. Test your changes
6. Update documentation
7. Submit for review

### Questions?
- Check this guide first
- Review PROJECT_STATUS.html
- Check existing code for examples
- Document questions for next check-in

---

*This guide is a living document. Update it as the project evolves.*

**Last Updated**: February 1, 2026  
**Version**: 1.0  
**Maintained By**: Project Team
