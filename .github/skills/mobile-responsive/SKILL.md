---
name: mobile-responsive
description: "Implement or debug mobile-responsive UI for the TKR Studios Shiny app. Use when: adapting layouts for small screens, fixing touch controls on the canvas editor, making modules stack/collapse correctly on mobile, updating CSS breakpoints, testing the photo album editor on phones/tablets, reviewing R/mobile_responsive.R or R/mobile_responsive_new.R."
argument-hint: "Describe the module or UI area to make mobile-responsive (e.g. 'canvas editor', 'photo library', 'full app audit')"
---

# Mobile-Responsive Implementation — TKR Studios

## When to Use
- User reports layout broken on phone or tablet
- Adding a new Shiny module that needs mobile support
- Full mobile audit of the app
- Adapting the canvas drag-drop editor for touch
- Making panels/sidebars collapse into bottom sheets on small screens

## Key Files

| File | Role |
|------|------|
| `R/mobile_responsive.R` | Original CSS injection helpers (`add_mobile_css()`, `isMobile()`) |
| `R/mobile_responsive_new.R` | Updated helpers — prefer these for new work |
| `R/modules/module_editor.R` | Canvas editor — most complex mobile target |
| `R/modules/module_photolibrary.R` | Photo grid — needs responsive column count |
| `R/modules/module_ai_editor.R` | AI Studio panels — must stack on narrow screens |
| `www/` | Static CSS/JS — place custom responsive overrides here |

## Breakpoints (match existing code)

```css
/* Mobile portrait  */ @media (max-width: 480px)  { ... }
/* Mobile landscape */ @media (max-width: 767px)  { ... }
/* Tablet           */ @media (max-width: 1024px) { ... }
/* Desktop          */ @media (min-width: 1025px) { ... }
```

## Procedure

### 1. Audit — Identify Affected Modules
1. Run `grep_search` for `isMobile` and `mobile_css` to find all existing mobile guards.
2. Identify which modules lack a mobile guard.
3. List affected Shiny inputs (sliders, canvas, drag handles) that need touch equivalents.


### 2. CSS & UI Strategy (2026 update)
- **Tabs**: Make `.nav-tabs` and `.nav-pills` scrollable on mobile (`@media (max-width: 600px)`), enforce tap targets ≥ 44px, and support swipe left/right to change tabs (Hammer.js + custom JS).
- **Bottom navigation**: Convert main sidebar to a bottom nav bar with large icons on mobile. Hide top tab bar if bottom nav is active.
- **Panels / sidebars**: Use `flexDirection: column` + `width: 100%` at mobile breakpoints. Collapse sidebars to overlays or bottom sheets on mobile.
- **Canvas editor** (`module_editor.R`): Inject touch event listeners via `shinyjs::runjs()`. Replace `mousedown/mousemove/mouseup` with `touchstart/touchmove/touchend` equivalents.
- **Photo grid** (`module_photolibrary.R`): Switch from fixed-width thumbnails to `grid-template-columns: repeat(auto-fill, minmax(80px, 1fr))`.
- **Action buttons**: Minimum tap target 44 × 44 px (WCAG 2.5.5).
- **Main area**: Use CSS variables and `clamp()` for fluid margins/paddings.

### 3. Server-Side Detection
```r
# In server — detect mobile via user agent
output$is_mobile <- reactive({
  req(input$clientData)
  isMobile(session)  # from R/mobile_responsive_new.R
})
```

### 4. Conditional UI
```r
# Collapse sidebar to bottom sheet on mobile
conditionalPanel(
  condition = "output.is_mobile",
  mobile_bottom_sheet_ui("controls")
)
```

### 5. Touch-Enabled Canvas
- Use `Hammer.js` (add to `www/`) for pinch-zoom, pan, and tap events.
- Inject via `tags$script(src = "hammer.min.js")` in the UI.
- Map Hammer events → Shiny custom messages via `Shiny.setInputValue()`.


### 6. Test Checklist (2026 update)
- [ ] Tabs are scrollable and accessible on mobile
- [ ] All tab buttons and nav icons ≥ 44 × 44 px
- [ ] Main sidebar is a bottom nav bar on mobile
- [ ] Swipe left/right changes tabs
- [ ] Portrait phone (375 × 812) — no horizontal scroll
- [ ] Landscape phone (812 × 375) — toolbar accessible
- [ ] Tablet (768 × 1024) — sidebars visible or collapsible
- [ ] Canvas drag-drop works via touch
- [ ] Photo upload button reachable with thumb
- [ ] Export button accessible without zooming
- [ ] Bottom navigation bar not obscured by mobile browser chrome

### 7. Validate
1. Run the app: `shiny::runApp("app.R")`
2. Open Chrome DevTools → toggle device toolbar → iPhone 12 Pro
3. Screenshot key interactions
4. Fix any overflow or z-index conflicts

## Common Issues

| Symptom | Fix |
|---------|-----|
| Horizontal scroll on mobile | Add `overflow-x: hidden` to `.container-fluid` |
| Canvas unresponsive to touch | Add touch event bridge in `module_editor.R` |
| Panels overlap on tablet | Check `z-index` stacking in sidebar CSS |
| Font too small on phone | Set `font-size: 16px` on inputs (prevents iOS zoom) |
| Buttons too small | Ensure `min-height: 44px; min-width: 44px` |
