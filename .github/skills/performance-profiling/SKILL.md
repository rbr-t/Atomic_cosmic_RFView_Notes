---
name: performance-profiling
description: "Diagnose and fix Shiny app performance issues in TKR Studios. Use when: the app feels sluggish, a module is slow to render, reactive chains re-fire too often, the canvas editor lags during drag/resize, image processing is blocking the UI, memory usage is growing, or Railway deployment is timing out. Produces a prioritised list of bottlenecks and concrete fixes with before/after reactive graphs."
argument-hint: "Describe the symptom: which module is slow, what action triggers it, and any error or timeout messages (e.g. 'canvas editor lags on drag', 'photo upload hangs at 20 photos')"
---

# Performance Profiling — TKR Studios

Diagnoses reactivity overhead, rendering bottlenecks, memory leaks, and blocking I/O in the TKR Studios Shiny app.

## The Three Shiny Performance Killers

| Killer | Symptom | Root Cause |
|---|---|---|
| **Over-invalidation** | Module re-renders on every tiny change | `reactive()` / `observe()` reads more values than it needs |
| **Blocking render** | UI freezes during image processing | Synchronous `magick` / Python calls on the main thread |
| **Memory leak** | App slows down progressively | Growing `reactiveValues` lists, un-removed observers |

---

## Step 1 — Locate the bottleneck

### A. Use `profvis` for CPU/time profiling
```r
# In R console with the app loaded:
library(profvis)
profvis({
  # reproduce the slow action here, e.g.:
  source("app_modular.R")
  Sys.sleep(5)  # time the startup
})
```
Look for: wide bars in `get_translations()`, `render_tree_canvas_svg()`, `renderUI()` calls.

### B. Use `reactlog` for reactive graph inspection
```r
options(shiny.reactlog = TRUE)
# Run app, reproduce the slow interaction
# Press Ctrl+F3 in browser to open reactive log
```
Look for: nodes that light up far more than expected on a single user action.

### C. Quick manual timing
```r
# Wrap suspicious observer bodies:
observeEvent(input$something, {
  t0 <- proc.time()
  # ... existing code ...
  cat("elapsed:", (proc.time() - t0)[["elapsed"]], "s\n")
})
```

---

## Step 2 — Fix Over-Invalidation

### Isolate reads that don't need to trigger re-render
```r
# BAD: re-renders whenever ANY rv field changes
output$canvas <- renderUI({
  pages <- rv$pages          # needed
  lang  <- rv$lang           # NOT needed for canvas render
  render_canvas(pages)
})

# GOOD: only invalidates when rv$pages changes
output$canvas <- renderUI({
  pages <- rv$pages
  isolate(render_canvas(pages))   # lang read inside isolate
})
```

### Use `bindEvent()` instead of `observeEvent` for expensive renders
```r
# BAD: observe fires on every rv$photos change during bulk upload
observe({
  render_heavy_thing(rv$photos)
}) |> bindEvent(rv$photos)   # correct — fires once per change, not during list building

# BETTER for expensive ops: debounce
photos_debounced <- debounce(reactive(rv$photos), 400)
observe({ render_heavy_thing(photos_debounced()) })
```

### `eventReactive` > `reactive` for user-triggered renders
```r
# BAD: re-runs on every dependency change
canvas_svg <- reactive({ render_tree_canvas_svg(local_rv$tag_hierarchy, ...) })

# GOOD: only re-runs when template_loaded timestamp changes
canvas_svg <- eventReactive(local_rv$template_loaded, {
  render_tree_canvas_svg(local_rv$tag_hierarchy, ...)
}, ignoreInit = FALSE)
```

---

## Step 3 — Fix Blocking Renders

### Move image processing off the main thread with `future` + `promises`
```r
library(future); library(promises)
plan(multisession)   # set once at app startup in app_modular.R

# BAD: blocks UI for every uploaded photo
observeEvent(input$upload, {
  result <- process_image_magick(input$upload$datapath)   # blocks 2-3s
  rv$processed <- result
})

# GOOD: async — UI stays responsive
observeEvent(input$upload, {
  showNotification(t("processing"), id = "proc", duration = NULL)
  future({ process_image_magick(input$upload$datapath) }) %...>% {
    rv$processed <- .
    removeNotification("proc")
  }
})
```

### Cache expensive computations
```r
# Cache translated strings (get_translations rebuilds the full list every call)
if (!exists(".i18n_cache")) .i18n_cache <- list()
get_translations_cached <- function(lang) {
  if (is.null(.i18n_cache[[lang]])) {
    .i18n_cache[[lang]] <<- get_translations(lang)
  }
  .i18n_cache[[lang]]
}
```

### Thumbnail generation — limit size early
```r
# Before storing in rv$photos, always downscale to thumbnail:
store_photo <- function(path) {
  img <- image_read(path)
  thumb <- image_resize(img, "300x300>")   # > = only shrink, never enlarge
  list(
    original_path = path,
    thumb_base64  = image_write_base64(thumb, format = "jpeg")
  )
}
```

---

## Step 4 — Fix Memory Leaks

### Remove observers that are no longer needed
```r
# BAD: each module invocation adds another permanent observer
observe({ ... })

# GOOD: store the observer handle and destroy it on session end
obs <- observe({ ... })
session$onSessionEnded(obs$destroy)
```

### Prune growing `reactiveValues` lists
```r
# Check for lists that grow without bound:
observeEvent(rv$photos, {
  # Cap at max_photos from config
  cfg <- get_app_config()
  if (length(rv$photos) > cfg$max_photos) {
    rv$photos <- rv$photos[seq_len(cfg$max_photos)]
    showNotification(sprintf(t("max_photos_reached"), cfg$max_photos), type = "warning")
  }
})
```

---

## Step 5 — CSS / JS Performance

### Avoid layout thrashing in JS
```js
// BAD: read, then write, alternating (forces multiple reflows)
elements.forEach(el => {
  const h = el.offsetHeight;     // read — forces reflow
  el.style.height = h + 10 + 'px'; // write
});

// GOOD: batch reads, then batch writes
const heights = elements.map(el => el.offsetHeight);  // all reads
elements.forEach((el, i) => el.style.height = heights[i] + 10 + 'px');  // all writes
```

### Use `requestAnimationFrame` for canvas updates
```js
// Wrap drag/resize canvas updates:
function updateCanvas() {
  requestAnimationFrame(() => {
    // DOM writes here
  });
}
```

---

## Step 6 — Railway / Docker Deployment Performance

Key constraints on Railway free tier:
- 512MB RAM — watch for `magick` + `python_bg_removal` running simultaneously
- Cold start: `renv::restore()` + package load time

### Reduce cold start
```r
# In app_modular.R: lazy-load heavy packages only when needed
# BAD at top of file:
library(reticulate)   # loads Python bridge immediately

# GOOD: load on first use
load_python_once <- function() {
  if (!exists(".py_loaded")) {
    library(reticulate)
    source("R/config_python.R")
    .py_loaded <<- TRUE
  }
}
```

---

## Profiling Targets — Known Slow Spots in TKR Studios

| Area | Why It's Slow | Quick Fix |
|---|---|---|
| `render_tree_canvas_svg()` | Builds a full SVG string for every hierarchy update | `eventReactive` on `template_loaded` only |
| `get_translations(lang)` | Rebuilds 50+ key list on every module render | Cache per language code (memoize) |
| `module_tagging.R` orbital photos | `renderUI` rebuilds entire sidebar on every photo update | `renderUI` → `renderCachedUI` with cache key `list(rv$photos, local_rv$tag_hierarchy)` |
| `module_editor.R` page canvas | `renderUI` calls too many `observeEvent` on `rv$photos` | Isolate photo list reads; use `throttle()` for rapid input events |
| Python `bg_removal.py` | Blocks main process | Wrap in `future` + `promises` as above |
