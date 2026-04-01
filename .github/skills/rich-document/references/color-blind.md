# Color-Blind Safe Design Reference

## The Okabe-Ito Palette (Recommended)

The gold standard for accessible scientific figures. Safe for **deuteranopia** (red-green, most common), **protanopia** (red weak), and **tritanopia** (blue-yellow). Named after Masataka Okabe and Kei Ito (2002).

| Name | Hex | RGB | Use for |
|------|-----|-----|---------|
| Orange | `#E69F00` | 230, 159, 0 | Primary accent, warnings |
| Sky Blue | `#56B4E9` | 86, 180, 233 | Links, notes, second series |
| Bluish Green | `#009E73` | 0, 158, 115 | Success, third series |
| Yellow | `#F0E442` | 240, 228, 66 | Highlights (use sparingly on white) |
| Blue | `#0072B2` | 0, 114, 178 | Headers, primary data series |
| Vermillion | `#D55E00` | 213, 94, 0 | Errors, cautions, alerts |
| Reddish Purple | `#CC79A7` | 204, 121, 167 | Secondary accent |
| Black | `#000000` | 0, 0, 0 | Text, neutral reference series |

**Swatch order for sequential use:**
```
■ Orange  ■ Sky Blue  ■ Bluish Green  ■ Blue  ■ Vermillion  ■ Reddish Purple  ■ Yellow  ■ Black
```

---

## R Quick Integration

```r
okabe_ito <- c(
  "#E69F00", "#56B4E9", "#009E73", "#F0E442",
  "#0072B2", "#D55E00", "#CC79A7", "#000000"
)

# ggplot2 — global (set in setup chunk)
options(
  ggplot2.discrete.colour = okabe_ito,
  ggplot2.discrete.fill   = okabe_ito
)

# ggplot2 — per-scale
scale_colour_manual(values = okabe_ito)
scale_fill_manual(values = okabe_ito)

# ggplot2 — continuous (orange → blue diverging)
scale_colour_gradient2(low = "#D55E00", mid = "#F0E442", high = "#0072B2")

# base R
palette(okabe_ito)
barplot(values, col = okabe_ito[1:length(values)])
```

---

## WCAG 2.1 Contrast Ratios

Minimum: **4.5:1** body text, **3:1** large text (≥18pt or ≥14pt bold).

| Foreground | Background | Ratio | Passes AA |
|------------|------------|-------|-----------|
| `#0072B2` (blue) | `#ffffff` | 5.23:1 | ✓ AA |
| `#D55E00` (vermillion) | `#ffffff` | 4.74:1 | ✓ AA |
| `#009E73` (bluish green) | `#ffffff` | 3.78:1 | ✓ large text |
| `#E69F00` (orange) | `#ffffff` | 2.85:1 | ✗ (use for icons/borders only) |
| `#56B4E9` (sky blue) | `#ffffff` | 2.91:1 | ✗ (use on dark bg only) |
| `#56B4E9` (sky blue) | `#1a1a2e` (dark bg) | 7.14:1 | ✓ AA |
| `#E69F00` (orange) | `#1a1a2e` (dark bg) | 6.42:1 | ✓ AA |

> **Rule**: Never rely on colour alone to convey meaning — always pair with shape, pattern, or label.

---

## Colorblindness Simulation

Test your figures before publishing:
- **Browser**: install the [Colorblinding](https://chrome.google.com/webstore/detail/colorblinding/dgbgleaofjainknadoffbjkclicbbgaa) Chrome extension
- **R**: `colorblindr::cvd_grid(your_plot)` — simulates all four types side by side
- **Figma/Pencil**: use the built-in accessibility simulator

```r
# Install colorblindr
install.packages("colorblindr", repos = "https://cloud.r-project.org")
# or from GitHub:
# remotes::install_github("clauswilke/colorblindr")

library(colorblindr)
colorblindr::cvd_grid(p)    # p = your ggplot object
```

---

## Patterns as a Supplement to Color

When using small multiples or prints that may be black-and-white:

```r
# ggpattern for filled bars with texture
library(ggpattern)
ggplot(data, aes(x, y, fill = group, pattern = group)) +
  geom_col_pattern(pattern_density = 0.3) +
  scale_pattern_manual(values = c("stripe", "crosshatch", "dot", "none"))
```

For line charts, vary both colour AND line type:
```r
scale_linetype_manual(values = c("solid", "dashed", "dotted", "dotdash"))
```

---

## Further Reading

- Okabe & Ito (2002): *Color Universal Design*. https://jfly.uni-koeln.de/color/
- Wilke, C. (2019): *Fundamentals of Data Visualization*, Ch. 19. https://clauswilke.com/dataviz/color-pitfalls.html
- WCAG 2.1 Contrast Guidelines: https://www.w3.org/TR/WCAG21/#contrast-minimum
- Tableau Color Blind 10 (alternative): https://www.tableau.com/about/blog/2016/7/colors-upgrade-tableau-10-56782
