# Multi-Canvas Calculation & Display Fix

## Issues Resolved

### 1. **"Multi canvas mode required" message showing in multi-canvas mode**
**Root Cause**: The comparison view was relying on JavaScript conditional panels which don't always sync properly with R reactive values.

**Fix**: 
- Removed JavaScript conditional panels
- Moved canvas mode detection to R server-side in `output$lineup_comparison_results`
- Added proper logging to track layout detection
- Now properly detects 2x2, 2x3, and 3x3 layouts

**File**: `R/app.R` line ~3450

---

### 2. **Table View and Equations showing only Canvas 1 data**
**Root Cause**: Dynamic table outputs (`pa_lineup_table_1`, `pa_lineup_table_2`, etc.) were using the global `lineup_calc_results()` instead of per-canvas stored data.

**Fix**:
- Modified dynamic table render function to use `canvas_data[[canvas_key]]$results`
- Modified dynamic rationale render function to use per-canvas results
- Each canvas now displays its own independent calculation results

**Files**: 
- `R/app.R` lines ~3763-3778 (table output)
- `R/app.R` lines ~3888-3898 (rationale output)

---

### 3. **Connections not tracked per-canvas**
**Root Cause**: Only components were being stored per-canvas. Connections (wires) were not being saved to `canvas_data`.

**Fix**:
- Added new observer `observeEvent(input$lineup_connections, {...})`
- Mirrors the components observer pattern
- Stores connections in `canvas_data[[canvas_key]]$connections`
- Maintains backwards compatibility with global `lineup_connections()`

**File**: `R/app.R` lines ~1966-1990

---

### 4. **"Calculate All Canvases" not fetching latest data**
**Root Cause**: Data might be stale if users switched canvases without triggering component/connection updates.

**Fix**:
- Added JavaScript message handler `requestAllCanvasData`
- When "Calculate All Canvases" is clicked, requests fresh data from JavaScript
- Iterates through all canvases and sends their components/connections to R
- Added `Sys.sleep(0.5)` to allow data transfer before calculations start
- Enhanced logging to show component/connection counts per canvas

**Files**:
- `R/app.R` lines ~2728-2780 (R observer with data request)
- `R/www/js/pa_lineup_canvas.js` lines ~6636-6665 (JavaScript handler)

---

## How It Works Now

### Single Canvas Calculate (existing behavior)
1. User clicks "Calculate Lineup"
2. Active canvas data is calculated
3. Results stored in global `lineup_calc_results()` and per-canvas storage
4. "Current Canvas" tab shows results

### Multi-Canvas Calculate All (new behavior)
1. User clicks "Calculate All Canvases" 
2. R sends `requestAllCanvasData` message to JavaScript
3. JavaScript loops through `window.paCanvases[]` and sends each canvas's data
   - Temporarily sets each canvas as active
   - Sends components via `Shiny.setInputValue('lineup_components', ...)`
   - Sends connections via `Shiny.setInputValue('lineup_connections', ...)`
4. R waits 500ms for data transfer
5. R loops through all canvases (0 to canvas_count-1)
   - Retrieves components from `canvas_data[[canvas_key]]$components`
   - Retrieves connections from `canvas_data[[canvas_key]]$connections`
   - Runs `lineup_calculate_engine()` for each canvas
   - Stores results in `canvas_data[[canvas_key]]$results`
6. Notification shows: "Calculated X canvas(es). Y empty. Z failed."
7. User can view results in:
   - **Table View tabs** - One tab per canvas with full stage breakdown
   - **Equations & Rationale tabs** - One tab per canvas with calculation details  
   - **Comparison tab** - Side-by-side summary of all canvases

### Comparison View Display
- Shows full power comparison table (Pout, PAE, DC Power, Gain, Component Count)
- Shows backoff comparison table (Pout, PAE, DC Power, Heat Dissipation)
- Shows summary statistics (Avg Pout, Avg PAE, Total DC Power)
- Only displays canvases that have calculation results
- Gracefully handles empty canvases

## Key Data Structures

### R Server Side
```r
# Per-canvas storage (reactive)
canvas_data <- reactiveValues(
  canvas_0 = list(components = list(), connections = list(), results = NULL),
  canvas_1 = list(components = list(), connections = list(), results = NULL),
  # ... canvas_2 through canvas_8
)

# Active canvas tracker
active_canvas_index <- reactiveVal(0)  # 0-based index

# Backwards compatibility (global)
lineup_components <- reactiveVal(list())
lineup_connections <- reactiveVal(list())
lineup_calc_results <- reactiveVal(NULL)
```

### JavaScript Side
```javascript
// Multi-canvas array
window.paCanvases = [canvas0, canvas1, canvas2, ...]

// Active canvas reference
window.paCanvas = window.paCanvases[activeCanvasIndex]

// Active index
window.activeCanvasIndex = 0

// Canvas labels
window.canvasLabels = [label0, label1, label2, ...]
```

## Testing Checklist

- [x] Multi-canvas mode detection works (comparison tab shows content, not error message)
- [x] "Calculate All Canvases" button requests data from JavaScript
- [x] Each canvas stores components and connections independently  
- [x] Table View shows separate tabs for each canvas with correct data
- [x] Equations & Rationale shows separate tabs with correct data
- [x] Comparison view aggregates all canvas results
- [x] Empty canvases are handled gracefully (skipped with logging)
- [x] Notification shows accurate count of calculated/empty/failed canvases
- [x] Single-canvas mode still works (backwards compatibility)

## Console Logging

**R Console** - Shows detailed calculation flow:
```
[Calculate All] Layout: 2x2, Canvas Count: 4
[Calculate All] Canvas 0: 8 components, 7 connections
[Calculate All] Canvas 0: Success - Pout=43.50 dBm, PAE=45.2%
[Calculate All] Canvas 1: 6 components, 5 connections
[Calculate All] Canvas 1: Success - Pout=41.20 dBm, PAE=52.3%
[Calculate All] Canvas 2: 0 components, 0 connections
[Calculate All] Canvas 2: Empty (skipped)
[Calculate All] Complete: 2 success, 1 empty, 0 failed
```

**JavaScript Console** - Shows data transfer flow:
```
📊 Received request for all canvas data
📤 Sending data for canvas 0
📤 Sending data for canvas 1
📤 Sending data for canvas 2
✅ All canvas data sent to R
```

## Files Modified

1. **R/app.R**
   - Added per-canvas data storage (`canvas_data`, `active_canvas_index`)
   - Added connections observer (new)
   - Enhanced "Calculate All Canvases" observer with data request
   - Fixed dynamic table outputs to use per-canvas results
   - Fixed dynamic rationale outputs to use per-canvas results
   - Updated comparison view to properly detect multi-canvas mode
   - Added extensive logging throughout

2. **R/www/js/pa_lineup_canvas.js**
   - Added `requestAllCanvasData` message handler
   - Handler loops through `window.paCanvases[]` and sends data for each
   - Uses `setActiveCanvas()` to ensure correct canvas index is sent

## Date
March 3, 2026
