---
name: rich-document
description: "Create rich, elegant, modern, intuitive HTML/PDF documents with TOC, tab panels, day/night toggle, color-blind-safe palettes, bibliography/citations, and print-ready PDF. Use when: writing reports, documentation, R Markdown, Quarto docs, analysis outputs, exporting album summaries to PDF or HTML. Generates structured Quarto .qmd or R Markdown .Rmd files with full theming."
argument-hint: "Describe the document: title, content sections, whether bibliography is needed, output format (html/pdf/both)"
---

# Rich Document Skill

Produces polished, accessible, multi-format documents (HTML + PDF) from Quarto (`.qmd`) or R Markdown (`.Rmd`).

## Feature Checklist

| Feature | Implementation |
|---------|---------------|
| Table of Contents | Floating sidebar TOC with smooth scroll |
| Tabs | Quarto `tabset` / `{.tabset}` panels |
| Day / Night toggle | Built-in Quarto `theme: [light, dark]` + custom SCSS |
| Color-blind safe | Okabe-Ito palette (8-color, deuteranopia/protanopia safe) |
| Bibliography | BibTeX `.bib` + CSL citation style |
| PDF output | `format: pdf` via TinyTeX or Chrome/Puppeteer |
| Accessible | WCAG 2.1 AA contrast, ARIA labels, semantic headings |

---

## Step-by-Step Procedure

### Step 1 — Scaffold the document

Create a `.qmd` file (preferred) or `.Rmd`. Use [the template](./assets/document-template.qmd) as the starting point.

Copy [assets/document-template.qmd](./assets/document-template.qmd) to your target location and rename it.

**Minimum viable YAML frontmatter:**
```yaml
---
title: "Your Title"
subtitle: "Optional subtitle"
author: "Author Name"
date: today
format:
  html:
    theme:
      light: [flatly, assets/theme-light.scss]
      dark:  [darkly, assets/theme-dark.scss]
    toc: true
    toc-depth: 3
    toc-location: left
    toc-title: "Contents"
    number-sections: true
    smooth-scroll: true
    code-fold: true
    code-tools: true
    fig-align: center
    fig-cap-location: bottom
    link-external-newwindow: true
  pdf:
    documentclass: article
    geometry: margin=2.5cm
    toc: true
    number-sections: true
    colorlinks: true
    fig-pos: "H"
bibliography: references.bib
csl: https://www.zotero.org/styles/apa-7th-edition
---
```

---

### Step 2 — Add tab panels

Use Quarto's native tabset for logical grouping. Always add `{.tabset}` to the parent header:

````markdown
## Results {.tabset}

### Overview
Content here...

### Detailed Analysis
Content here...

### Raw Data
```{r}
head(data)
```
````

For R Markdown:
````markdown
## Results {.tabset .tabset-fade .tabset-pills}
````

---

### Step 3 — Apply color-blind-safe palette

Use the **Okabe-Ito palette** for all charts and color-coded elements. See [references/color-blind.md](./references/color-blind.md) for full palette.

**In R (ggplot2):**
```r
okabe_ito <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442",
               "#0072B2", "#D55E00", "#CC79A7", "#000000")

# Apply globally:
options(ggplot2.discrete.colour = okabe_ito,
        ggplot2.discrete.fill   = okabe_ito)

# Or per plot:
scale_colour_manual(values = okabe_ito)
```

**In CSS (for custom HTML callouts/badges):**
```scss
// In assets/theme-light.scss or theme-dark.scss
$color-accent-1:  #E69F00;  // Orange — safe lead colour
$color-accent-2:  #56B4E9;  // Sky blue
$color-accent-3:  #009E73;  // Bluish green
$color-accent-4:  #0072B2;  // Blue
$color-accent-5:  #D55E00;  // Vermillion
$color-accent-6:  #CC79A7;  // Reddish purple
```

---

### Step 4 — Configure bibliography

1. Create `references.bib` in the same directory:
```bibtex
@article{key2024,
  author  = {Last, First},
  title   = {Article Title},
  journal = {Journal Name},
  year    = {2024},
  volume  = {1},
  pages   = {1--10},
  doi     = {10.xxxx/xxxxx}
}
```

2. Cite inline:
```markdown
This result was confirmed in prior work [@key2024].
Multiple citations: [@key2024; @another2023].
Page-specific: [@key2024, p. 45].
```

3. A `## References` section is generated automatically at document end.

4. Change citation style by swapping the `csl:` URL. Common styles:
   - APA 7th: `https://www.zotero.org/styles/apa-7th-edition`
   - Vancouver: `https://www.zotero.org/styles/vancouver`
   - Chicago: `https://www.zotero.org/styles/chicago-author-date`
   - IEEE: `https://www.zotero.org/styles/ieee`

---

### Step 5 — Day / Night toggle

Day/night is automatic with Quarto's dual-theme system. The toggle button appears top-right.

Fine-tune with SCSS overrides. Use [assets/theme-light.scss](./assets/theme-light.scss) and [assets/theme-dark.scss](./assets/theme-dark.scss).

**Key SCSS variables to override:**
```scss
// theme-light.scss
$body-bg:    #ffffff;
$body-color: #1a1a2e;
$link-color: #0072B2;

// theme-dark.scss  
$body-bg:    #1a1a2e;
$body-color: #e8e8f0;
$link-color: #56B4E9;
```

**Custom day/night aware callout blocks:**
```markdown
::: {.callout-note}
This renders correctly in both themes.
:::

::: {.callout-warning}
Warning block — orange in both themes (Okabe-Ito color).
:::
```

---

### Step 6 — Render

**HTML only:**
```bash
quarto render document.qmd --to html
```

**PDF only:**
```bash
quarto render document.qmd --to pdf
```

**Both formats at once:**
```bash
quarto render document.qmd
```

**From R:**
```r
quarto::quarto_render("document.qmd")
# or for R Markdown:
rmarkdown::render("document.Rmd", output_format = "all")
```

**Install TinyTeX for PDF rendering (one-time):**
```r
install.packages("tinytex")
tinytex::install_tinytex()
```

---

### Step 7 — Quality checks

Before finalising, verify:

- [ ] TOC links work (especially after renaming sections)
- [ ] All tab panels have content (empty tabs cause render warnings)
- [ ] Every chart uses Okabe-Ito palette (no default red/green)
- [ ] Contrast ratio ≥ 4.5:1 for body text (check with browser DevTools → Accessibility)
- [ ] Bibliography section appears and all `[@key]` citations resolve
- [ ] Day/night toggle tested manually in browser
- [ ] PDF: check page breaks aren't splitting tables mid-row (`keep_together: true`)
- [ ] PDF: figures have captions (`fig-cap:`)

---

## Asset Locations

| File | Format | Purpose |
|------|--------|---------|
| [assets/document-template.qmd](./assets/document-template.qmd) | Quarto | Full-featured `.qmd` starter |
| [assets/document-template.Rmd](./assets/document-template.Rmd) | R Markdown | Full-featured `.Rmd` starter (tabset, kable, all features) |
| [assets/theme-light.scss](./assets/theme-light.scss) | SCSS | Light mode overrides for Quarto |
| [assets/theme-dark.scss](./assets/theme-dark.scss) | SCSS | Dark mode overrides for Quarto |
| [assets/rmd-header.html](./assets/rmd-header.html) | HTML | Google Fonts + day/night JS toggle for `.Rmd` |
| [assets/rmd-custom.css](./assets/rmd-custom.css) | CSS | Full light/dark CSS for `.Rmd` (CSS variables, Okabe-Ito) |
| [assets/rmd-latex-header.tex](./assets/rmd-latex-header.tex) | LaTeX | PDF preamble: fontspec, booktabs, hyperref, Inter font |
| [references/color-blind.md](./references/color-blind.md) | Reference | Okabe-Ito palette, WCAG contrast table, R code |

### Quarto vs R Markdown — quick decision

| Need | Use |
|------|-----|
| New document, full features | `document-template.qmd` — native day/night toggle, cleaner syntax |
| Existing `.Rmd` project | `document-template.Rmd` — JS-powered toggle, CSS variables |
| PDF only | Either — both have LaTeX/xelatex support |
| Shiny integration | `.Rmd` with `runtime: shiny` |

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Dark theme ignores SCSS | Must list `.scss` file in `theme: [base, custom.scss]` array order |
| PDF missing fonts | Run `tinytex::tlmgr_install("collection-fontsrecommended")` |
| Tabs not rendering | Quarto needs `toc: true` and `tabset` only works in HTML output |
| Bibliography not found | `references.bib` must be in same directory as `.qmd`, or use absolute path |
| Color-blind contrast fails | Never use red (#FF0000) vs. green (#00FF00) — use Okabe-Ito pair instead |
| Page numbers in HTML | `page-layout: article` disables; use `page-layout: full` for dashboards |
