---
name: accessibility-audit
description: "WCAG 2.1 AA accessibility audit and fix for TKR Studios Shiny app. Use when: running a full accessibility audit, fixing screen reader issues, improving keyboard navigation, checking colour contrast ratios, adding ARIA labels to icon buttons, fixing form accessibility, ensuring the app is usable without a mouse, validating focus management in modals and drawers, meeting ADA / EN 301 549 / EAA compliance requirements."
argument-hint: "Scope of audit: 'full app', a specific module name, or a specific issue type (e.g. 'contrast', 'keyboard nav', 'screen reader', 'forms')"
---

# Accessibility Audit — TKR Studios (WCAG 2.1 AA)

Audits and fixes accessibility issues so the app meets **WCAG 2.1 Level AA** — the baseline required by ADA (US), EAA (EU), AODA (Canada), and DDA (Australia).

---

## WCAG 2.1 AA — What Applies to This App

| Criterion | Level | What It Means |
|---|---|---|
| 1.1.1 Non-text Content | A | Every image/icon/graphic needs an `alt` or `aria-label` |
| 1.4.1 Use of Colour | A | Colour alone must not convey info (add icon/text) |
| 1.4.3 Contrast (Minimum) | AA | Body text: 4.5:1 min. Large text (≥18pt): 3:1 min |
| 1.4.4 Resize Text | AA | Text must scale to 200% without horizontal scroll |
| 1.4.10 Reflow | AA | No horizontal scroll at 320px wide |
| 1.4.11 Non-text Contrast | AA | UI components (inputs, buttons) must have 3:1 contrast |
| 2.1.1 Keyboard | A | All functionality operable via keyboard |
| 2.1.2 No Keyboard Trap | A | Focus must not get stuck anywhere |
| 2.4.3 Focus Order | A | Tab order must be logical (matches visual order) |
| 2.4.7 Focus Visible | AA | Keyboard focus must be visible at all times |
| 3.1.1 Language of Page | A | `<html lang="...">` set to active language |
| 3.3.1 Error Identification | A | Form errors identified in text, not just red border |
| 3.3.2 Labels / Instructions | A | All inputs have visible label or `aria-label` |
| 4.1.2 Name, Role, Value | A | All UI components have accessible name + role |
| 4.1.3 Status Messages | AA | Success/error notifications announced to screen readers |

---

## Step-by-Step Audit Procedure

### Step 1 — Colour Contrast

Check all text/background pairs against WCAG ratios.

#### TKR Studios known pairs to verify:

| Text colour | Background | Required ratio | Tool |
|---|---|---|---|
| `--text` (`#f1f5f9`) on `--surface` (`#1e2130`) | 4.5:1 | ✅ ~12:1 |
| `--text-muted` (`#94a3b8`) on `--surface` | 4.5:1 | ⚠️ verify (~4.7:1) |
| White on `--primary` (`#5b6af0`) | 4.5:1 | ✅ verify (~5.0:1) |
| White on `--warning` (`#f59e0b`) | 4.5:1 | ❌ fails — use dark text on warning |
| White on `--success` (`#22c55e`) | 4.5:1 | ❌ use dark text on success bg |

```css
/* Fix: dark text on light semantic colours */
.tkr-badge-success { background: rgba(34,197,94,.15); color: #15803d; }  /* dark green on tint */
.tkr-badge-warning { background: rgba(245,158,11,.15); color: #b45309; }  /* dark amber */
```

**Tool:** https://webaim.org/resources/contrastchecker/ or browser DevTools accessibility panel.

### Step 2 — Icon-Only Buttons

Grep the codebase for icon-only buttons without labels:

```r
# Search for:
grep_search: icon("...") without aria-label or title
```

Every icon-only interactive element MUST have **both**:
```r
tags$button(
  `aria-label` = "Delete selected element",  # for screen readers
  title = "Delete selected",                  # for sighted mouse users (tooltip)
  icon("trash")
)
```

### Step 3 — Form Inputs

Every `textInput`, `selectInput`, `fileInput`, `numericInput` MUST have a visible `<label>`.

```r
# BAD: label inside placeholder only
textInput(ns("name"), label = NULL, placeholder = "Project name")

# GOOD:
textInput(ns("name"), label = tags$span("Project name", `data-i18n` = "project_name"))
```

Error messages must be text, not just red border:
```r
# GOOD: use validate() for inline errors
validate(
  need(nchar(input$project_name) > 0, t("project_name_required"))
)
```

### Step 4 — Keyboard Navigation

**Tab order** must follow the visual reading order (left→right, top→bottom).

Check for:
- `tabindex="-1"` on focusable elements (removes from tab order — only valid for programmatic focus)
- `tabindex="2"` or positive values (breaks natural tab order — never use)
- Modal dialogs: focus must move INTO the modal on open and RETURN to the trigger on close

```r
# After opening a modal, move focus to first focusable element:
runjs(sprintf(
  "setTimeout(function(){ var el=document.querySelector('#%s input, #%s button'); if(el) el.focus(); }, 100);",
  ns("modal_id"), ns("modal_id")
))
```

### Step 5 — Dynamic Content & Screen Readers

`showNotification()` messages are rendered into the DOM dynamically. Screen readers won't announce them unless there's an `aria-live` region.

Add to `app_modular.R` or via `mobile_viewport_meta()`:
```r
tags$div(
  id = "a11y-live-region",
  `aria-live` = "polite",
  `aria-atomic` = "true",
  style = "position:absolute; width:1px; height:1px; overflow:hidden; clip:rect(0,0,0,0);"
)
```

When using `showNotification`, also push to the live region:
```r
notify <- function(msg, type = "message", duration = 3) {
  showNotification(msg, type = type, duration = duration)
  runjs(sprintf(
    "var r=document.getElementById('a11y-live-region'); if(r) r.textContent='%s';",
    gsub("'", "\u2019", msg)
  ))
}
```

### Step 6 — Language Declaration

When `rv$lang` changes, update the `<html lang>` attribute:

```r
# In module_language.R observeEvent(input$selected):
runjs(sprintf("document.documentElement.setAttribute('lang','%s');", lang))
```

Also set text direction (already implemented for RTL):
```r
runjs(sprintf("document.documentElement.setAttribute('dir','%s');", dir))
```

### Step 7 — Images

All photos in the canvas have functional meaning to the user — they're not decorative.

```r
# In SVG/HTML canvas output, every photo element needs an alt:
tags$img(
  src = photo$src,
  alt = photo$caption %||% sprintf(t("photo_n"), i),   # never empty alt for meaningful images
  class = "canvas-photo"
)
```

For purely decorative SVG icons (border ornaments, background patterns):
```r
# Decorative: empty alt + role=presentation
tags$img(src = "ornament.svg", alt = "", role = "presentation")
# Or on inline SVG:
tags$svg(`aria-hidden` = "true", ...)
```

### Step 8 — Reduced Motion

```css
/* In every CSS file that defines animations: */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

## Audit Output Format

Report findings as:

```
WCAG 2.1 AA Audit — [Module or Scope]
Date: [date]

CRITICAL (must fix before launch):
  [1.4.3] module_export.R line 45: "Download" button text #aaa on #fff — ratio 2.3:1, need 4.5:1
  [2.1.1] module_tagging.R: zoom slider not keyboard-operable

HIGH (fix in next sprint):
  [4.1.2] module_editor.R: 8 icon-only buttons missing aria-label
  [3.3.2] module_payment.R: CVV input has no visible label

MEDIUM (accessibility enhancement):
  [4.1.3] No aria-live region — showNotification not announced to screen readers

PASS:
  [1.4.3] Main text/surface contrast passes AA throughout
  [3.1.1] html lang attribute updated on language change
```

---

## Quick Reference — ARIA Roles for Shiny Patterns

| Pattern | ARIA to add |
|---|---|
| Icon-only button | `aria-label="Description"` |
| Toggle button | `aria-pressed="true/false"` |
| Loading state | `aria-busy="true"` on the container |
| Expanded panel | `aria-expanded="true/false"` on the trigger |
| Tab panel set | `role="tablist"`, `role="tab"`, `role="tabpanel"` |
| Progress bar | `role="progressbar"`, `aria-valuenow`, `aria-valuemin`, `aria-valuemax` |
| Status notification | `role="status"` or `aria-live="polite"` region |
| Error notification | `role="alert"` or `aria-live="assertive"` |
| Dialog/Modal | `role="dialog"`, `aria-modal="true"`, `aria-labelledby` |
