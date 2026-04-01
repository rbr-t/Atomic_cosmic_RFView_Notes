# Shiny UI Patterns — TKR Studios

Concrete Shiny R patterns for each UI decision. Copy-paste starting points for module design.

---

## 1. Action Button — Primary CTA

```r
actionButton(
  ns("save"),
  tags$span(icon("save"), "Save Project"),
  class = "btn-primary btn-sm",
  style = "min-width:120px;"
)
```
**CSS minimum:**
```css
.btn-primary {
  background: var(--primary);
  border: none;
  border-radius: var(--r-md);
  font-size: var(--text-md);
  padding: var(--sp-8) var(--sp-16);
  transition: background 0.15s var(--ease-out),
              transform  0.10s var(--ease-out);
}
.btn-primary:hover  { background: var(--primary-hover); }
.btn-primary:active { transform: scale(0.97); }
.btn-primary:focus-visible { outline: 2px solid var(--primary); outline-offset: 3px; }
```

---

## 2. Icon-Only Toolbar Button

```r
tags$button(
  class = "ep-icon-btn",
  title = "Delete selected",     # REQUIRED for accessibility
  `aria-label` = "Delete selected element",
  icon("trash-alt")
)
```
```css
.ep-icon-btn {
  width: 34px; height: 34px;
  display: inline-flex; align-items: center; justify-content: center;
  border-radius: var(--r-sm);
  border: 1px solid var(--border);
  background: transparent;
  color: var(--text-muted);
  transition: background 0.15s, color 0.15s, border-color 0.15s;
  cursor: pointer;
}
.ep-icon-btn:hover  { background: var(--surface-3); color: var(--text); }
.ep-icon-btn.active { background: var(--primary); border-color: var(--primary); color: #fff; }
```

---

## 3. Context-Sensitive Right Panel (properties panel)

Pattern: show/hide based on what's selected in the canvas.

```r
# In UI:
tags$div(
  id = ns("props_panel"),
  class = "props-panel",
  style = "display:none;",        # Hidden by default
  uiOutput(ns("props_content"))   # Rendered dynamically
)

# In Server:
output$props_content <- renderUI({
  req(local_rv$selected_id)
  el <- get_element(local_rv$selected_id)
  # return type-specific property controls
})
observeEvent(local_rv$selected_id, {
  runjs(sprintf(
    "document.getElementById('%s').style.display = '%s';",
    ns("props_panel"),
    if (!is.null(local_rv$selected_id)) "block" else "none"
  ))
})
```

---

## 4. Collapsible Section (accordion)

```r
tags$div(
  class = "tkr-section",
  tags$button(
    class = "tkr-section-header",
    onclick = "this.parentElement.classList.toggle('open')",
    `aria-expanded` = "false",
    tags$span("Section Title"),
    icon("chevron-down", class = "tkr-chevron")
  ),
  tags$div(
    class = "tkr-section-body",
    # content
  )
)
```
```css
.tkr-section-body         { max-height: 0; overflow: hidden; transition: max-height 0.25s var(--ease-out); }
.tkr-section.open .tkr-section-body { max-height: 600px; }
.tkr-chevron              { transition: transform 0.2s; }
.tkr-section.open .tkr-chevron { transform: rotate(180deg); }
```

---

## 5. Status Badge / Chip

```r
tags$span(
  class = "tkr-badge tkr-badge-success",
  icon("check-circle"), " Saved"
)
```
```css
.tkr-badge {
  display: inline-flex; align-items: center; gap: var(--sp-4);
  padding: var(--sp-2) var(--sp-8);
  border-radius: var(--r-sm);
  font-size: var(--text-xs);
  font-weight: 600;
  letter-spacing: 0.4px;
}
.tkr-badge-success { background: rgba(34,197,94,.15); color: #22c55e; }
.tkr-badge-warning { background: rgba(245,158,11,.15); color: #f59e0b; }
.tkr-badge-danger  { background: rgba(239,68,68,.15);  color: #ef4444; }
.tkr-badge-info    { background: rgba(56,189,248,.15); color: #38bdf8; }
.tkr-badge-neutral { background: var(--surface-3);     color: var(--text-muted); }
```

---

## 6. Responsive Two-Column Studio Layout

```r
tags$div(
  class = "studio-layout",
  # Left: controls (~35%)
  tags$div(class = "studio-controls", # ... controls),
  # Right: preview (~65%)
  tags$div(class = "studio-preview",  # ... preview)
)
```
```css
.studio-layout {
  display: flex;
  gap: var(--sp-16);
  height: 100%;
}
.studio-controls { flex: 0 0 320px; overflow-y: auto; }
.studio-preview  { flex: 1; min-width: 0; }

@media (max-width: 768px) {
  .studio-layout   { flex-direction: column; }
  .studio-controls { flex: 0 0 auto; order: 2; }
  .studio-preview  { flex: 0 0 auto; order: 1; min-height: 40svh; }
}
```

---

## 7. Tooltip on Icon Button

```r
library(shinyBS)
bsTooltip(ns("delete_btn"), "Delete selected element", placement = "top", trigger = "hover")
# Or lightweight CSS tooltip:
tags$button(
  class = "ep-icon-btn tkr-tooltip",
  `data-tip` = "Delete selected",
  icon("trash")
)
```
```css
.tkr-tooltip { position: relative; }
.tkr-tooltip::after {
  content: attr(data-tip);
  position: absolute;
  bottom: calc(100% + 6px);
  left: 50%; transform: translateX(-50%);
  background: #1e293b;
  color: #f1f5f9;
  font-size: var(--text-xs);
  white-space: nowrap;
  padding: var(--sp-4) var(--sp-8);
  border-radius: var(--r-sm);
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.15s;
}
.tkr-tooltip:hover::after { opacity: 1; }
```

---

## 8. Notification with Translated String

```r
# Always use t() — never hard-coded English
showNotification(t("save_success"), type = "message", duration = 2)
showNotification(sprintf(t("n_photos_imported"), n), type = "message", duration = 3)
showNotification(t("upload_error"), type = "error")   # No duration — stays until dismissed
```

---

## 9. Empty State (first-run / no data)

```r
uiOutput(ns("empty_state"))

output$empty_state <- renderUI({
  if (length(rv$photos) > 0) return(NULL)
  tags$div(
    class = "tkr-empty-state",
    tags$div(class = "tkr-empty-icon", icon("images", class = "fa-3x")),
    tags$h3(t("no_photos_yet")),
    tags$p(class = "text-muted", t("upload_to_start")),
    actionButton(ns("go_upload"), tags$span(icon("upload"), t("upload")), class = "btn-primary")
  )
})
```
```css
.tkr-empty-state {
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; gap: var(--sp-16);
  padding: var(--sp-24);
  color: var(--text-muted);
  text-align: center;
  min-height: 200px;
}
.tkr-empty-icon { opacity: 0.3; }
```
