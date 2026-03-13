# =============================================================================
# server_rf_cad.R
# RF CAD Tool — Shiny module (Phase 1: 2D Layout Canvas).
#
# Assets are bundled inside the PA Design App's own www/ folder:
#   www/js/rf_canvas.js
#   www/css/rf_cad.css
#
# Usage:
#   UI  : rfCadUI("rfcad", height = "calc(100vh - 210px)", compact = TRUE)
#   Svr : rfCadServer("rfcad")
# =============================================================================

# ── Konva CDN (version-locked) ───────────────────────────────────────────────
.KONVA_CDN <- "https://unpkg.com/konva@9.3.14/konva.min.js"

# ── Substrate material presets ───────────────────────────────────────────────
.SUBSTRATE_PRESETS <- list(
  "Rogers RO4003C"  = list(er = 3.55,  tanD = 0.0027, h = 0.508, t = 0.035),
  "Rogers RO4350B"  = list(er = 3.66,  tanD = 0.0037, h = 0.762, t = 0.035),
  "Rogers RO3010"   = list(er = 10.2,  tanD = 0.0022, h = 0.635, t = 0.035),
  "Isola I-Tera"    = list(er = 3.45,  tanD = 0.0031, h = 0.508, t = 0.035),
  "FR4"             = list(er = 4.4,   tanD = 0.020,  h = 1.6,   t = 0.035),
  "Alumina 96%"     = list(er = 9.8,   tanD = 0.0001, h = 0.635, t = 0.005),
  "Custom"          = list(er = 4.0,   tanD = 0.002,  h = 0.5,   t = 0.035)
)

# =============================================================================
# rfCadUI(id, height, compact)
# =============================================================================
rfCadUI <- function(id, height = "600px", compact = FALSE) {

  ns <- NS(id)

  # Assets served from the app's own www/ (standard Shiny path)
  js_path  <- "js/rf_canvas.js"
  css_path <- "css/rf_cad.css"

  # ── Component palette buttons ───────────────────────────────────────────
  palette_items <- list(
    list(type = "ms",         label = "Microstrip",   icon = "\u2500"),
    list(type = "bend90",     label = "Bend 90\u00b0",icon = "\u231d"),
    list(type = "tee",        label = "T-Junction",   icon = "\u22a5"),
    list(type = "coupled",    label = "Coupled",      icon = "\u2016"),
    list(type = "via",        label = "GND Via",      icon = "\u25cf"),
    list(type = "port",       label = "RF Port",      icon = "\u25c6"),
    list(type = "open_stub",  label = "Open Stub",    icon = "\u2a10"),
    list(type = "short_stub", label = "Short Stub",   icon = "\u23da")
  )

  palette_btns <- lapply(palette_items, function(item) {
    tags$button(
      class       = "rfcad-palette-btn",
      `data-type` = item$type,
      title       = item$label,
      onclick     = sprintf(
        "var c=RFCAD.getCanvas('%s');if(c)c.setTool('%s');", id, item$type
      ),
      tags$span(class = "rfcad-palette-icon", item$icon),
      tags$span(class = "rfcad-palette-label", item$label)
    )
  })

  # ── Toolbar ─────────────────────────────────────────────────────────────
  toolbar_left <- tagList(
    tags$button(
      class = "rfcad-tool-btn", id = ns("btn_select"), title = "Select (V)",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.setTool('select');", id),
      "\u25b6 Select"
    ),
    tags$span(class = "rfcad-toolbar-sep"),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Delete selected (Del)",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.deleteSelected();", id),
      "\ud83d\uddd1 Del"
    ),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Rotate 45\u00b0 (R)",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.rotateSelected(45);", id),
      "\u21bb Rot"
    ),
    tags$span(class = "rfcad-toolbar-sep"),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Zoom In",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.zoomBy(1.25);", id),
      "+ Zoom"
    ),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Zoom Out",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.zoomBy(0.8);", id),
      "\u2212 Zoom"
    ),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Fit to content (F)",
      onclick = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.fitToContent();", id),
      "\u26f6 Fit"
    )
  )

  toolbar_right <- tagList(
    tags$span(style = "color:#aaa; font-size:11px; margin-right:4px;", "Grid:"),
    tags$select(
      id       = ns("grid_size"),
      class    = "rfcad-select-sm",
      onchange = sprintf(
        "var c=RFCAD.getCanvas('%s');if(c)c.setGrid(parseFloat(this.value));", id
      ),
      tags$option(value = "0.1",  "0.1 mm"),
      tags$option(value = "0.25", "0.25 mm"),
      tags$option(value = "0.5",  selected = "selected", "0.5 mm"),
      tags$option(value = "1.0",  "1.0 mm"),
      tags$option(value = "2.0",  "2.0 mm")
    ),
    tags$label(
      class = "rfcad-snap-label",
      title = "Snap to grid",
      tags$input(
        type     = "checkbox",
        id       = ns("snap_grid"),
        checked  = "checked",
        onchange = sprintf(
          "var c=RFCAD.getCanvas('%s');if(c)c.setSnap(this.checked);", id
        )
      ),
      "Snap"
    ),
    tags$span(class = "rfcad-toolbar-sep"),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Save design",
      onclick = sprintf(
        "var c=RFCAD.getCanvas('%s');if(c){var d=c.exportJSON();Shiny.setInputValue('%s',d,{priority:'event'});}",
        id, ns("save_trigger")
      ),
      "\ud83d\udcbe Save"
    ),
    tags$button(
      class = "rfcad-ctrl-btn", title = "Clear canvas",
      onclick = sprintf(
        "if(confirm('Clear all components?')){var c=RFCAD.getCanvas('%s');if(c)c.clearAll();}",
        id
      ),
      "\u2715 Clear"
    )
  )

  # ── Properties panel ─────────────────────────────────────────────────────
  props_panel <- div(
    class = "rfcad-properties",
    div(class = "rfcad-panel-header", "Properties"),

    div(class = "rfcad-panel-header rfcad-panel-subheader", "Substrate"),
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "Preset"),
      selectInput(ns("sub_preset"), NULL,
        choices  = c("Select preset\u2026" = "", names(.SUBSTRATE_PRESETS)),
        selected = "")
    ),
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "\u03b5r"),
      numericInput(ns("sub_er"),   NULL, value = 3.55,  min = 1,    max = 100, step = 0.01)
    ),
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "tan\u03b4"),
      numericInput(ns("sub_tanD"), NULL, value = 0.0027, min = 0,    max = 1,   step = 0.0001)
    ),
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "h"),
      numericInput(ns("sub_h"),    NULL, value = 0.508, min = 0.01, max = 10,  step = 0.01),
      tags$span(class = "rfcad-prop-unit", "mm")
    ),
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "t (Cu)"),
      numericInput(ns("sub_t"),    NULL, value = 0.035, min = 0,    max = 1,   step = 0.001),
      tags$span(class = "rfcad-prop-unit", "mm")
    ),

    tags$hr(style = "border-color:#2a2a3a; margin:8px 0;"),
    div(class = "rfcad-panel-header rfcad-panel-subheader", "Selected Component"),
    uiOutput(ns("rfcad_props")),

    tags$hr(style = "border-color:#2a2a3a; margin:8px 0;"),
    div(class = "rfcad-panel-header rfcad-panel-subheader", "Design"),
    uiOutput(ns("design_summary"))
  )

  # ── Full layout ──────────────────────────────────────────────────────────
  tagList(
    singleton(tags$head(
      tags$script(src = .KONVA_CDN),
      tags$script(src = js_path),
      tags$link(rel = "stylesheet", href = css_path)
    )),

    div(
      class = if (compact) "rfcad-app-wrapper rfcad-compact" else "rfcad-app-wrapper",
      style = sprintf("height:%s;", height),

      div(class = "rfcad-toolbar",
        div(class = "rfcad-toolbar-left",  toolbar_left),
        div(class = "rfcad-toolbar-right", toolbar_right)
      ),

      div(class = "rfcad-body",
        div(class = "rfcad-palette",
          div(class = "rfcad-panel-header", "Components"),
          palette_btns
        ),
        div(class = "rfcad-canvas-wrapper",
          div(id = ns("rfcad_canvas"), class = "rfcad-canvas-container")
        ),
        props_panel
      ),

      div(id = paste0("rfcad_status_", id), class = "rfcad-statusbar",
        "Loading canvas\u2026")
    ),

    tags$script(HTML(sprintf(
      "(function(){
        function initCanvas(){
          if(typeof RFCAD==='undefined'||typeof Konva==='undefined'){
            setTimeout(initCanvas,100); return;
          }
          RFCAD.createCanvas('%s','%s','%s');
        }
        if(document.readyState==='loading'){
          document.addEventListener('DOMContentLoaded',initCanvas);
        } else { initCanvas(); }
      })();",
      ns("rfcad_canvas"), id, id
    )))
  )
}


# =============================================================================
# rfCadServer(id)
# =============================================================================
rfCadServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    rv <- reactiveValues(
      components = list(),
      selected   = NULL,
      substrate  = list(er = 3.55, tanD = 0.0027, h = 0.508, t = 0.035)
    )

    # Substrate preset
    observeEvent(input$sub_preset, {
      req(nzchar(input$sub_preset))
      p <- .SUBSTRATE_PRESETS[[input$sub_preset]]
      if (!is.null(p)) {
        updateNumericInput(session, "sub_er",   value = p$er)
        updateNumericInput(session, "sub_tanD", value = p$tanD)
        updateNumericInput(session, "sub_h",    value = p$h)
        updateNumericInput(session, "sub_t",    value = p$t)
      }
    }, ignoreInit = TRUE)

    # Push substrate to canvas
    observe({
      req(!is.null(input$sub_er), !is.null(input$sub_h))
      sub <- list(
        er   = input$sub_er   %||% 3.55,
        tanD = input$sub_tanD %||% 0.0027,
        h    = input$sub_h    %||% 0.508,
        t    = input$sub_t    %||% 0.035
      )
      rv$substrate <- sub
      session$sendCustomMessage("rfcad_update_substrate",
        list(instanceId = id, substrate = sub))
    })

    # Receive components from JS
    observeEvent(input$rfcad_components, {
      raw <- input$rfcad_components
      if (!is.null(raw) && nzchar(raw)) {
        tryCatch(
          rv$components <- jsonlite::fromJSON(raw, simplifyVector = FALSE),
          error = function(e) warning("[rfCadServer] components parse error: ", e$message)
        )
      }
    })

    # Receive selected from JS
    observeEvent(input$rfcad_selected, {
      raw <- input$rfcad_selected
      if (is.null(raw) || !nzchar(raw) || raw == "null") {
        rv$selected <- NULL
      } else {
        tryCatch(
          rv$selected <- jsonlite::fromJSON(raw, simplifyVector = FALSE),
          error = function(e) rv$selected <- NULL
        )
      }
    })

    # Properties panel for selected component
    output$rfcad_props <- renderUI({
      comp <- rv$selected
      if (is.null(comp)) {
        return(div(style = "color:#666; font-size:11px; padding:4px 8px;",
          "Click a component to edit its properties."))
      }

      params <- comp$params %||% list()
      type   <- comp$type   %||% "ms"

      fields <- list(
        div(class = "rfcad-prop-row",
          tags$label(class = "rfcad-prop-label", "Name"),
          textInput(ns("prop_name"), NULL, value = comp$name %||% "")
        ),
        div(class = "rfcad-prop-row",
          tags$label(class = "rfcad-prop-label", "Rotation"),
          numericInput(ns("prop_rotation"), NULL, value = comp$rotation %||% 0, step = 45),
          tags$span(class = "rfcad-prop-unit", "\u00b0")
        )
      )

      if (type %in% c("ms", "bend90", "open_stub", "short_stub", "tee")) {
        fields <- c(fields, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "W"),
            numericInput(ns("prop_W"), NULL, value = params$W %||% 0.5, min = 0.001, step = 0.01),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type %in% c("ms", "bend90", "open_stub", "short_stub", "tee", "coupled")) {
        fields <- c(fields, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "L"),
            numericInput(ns("prop_L"), NULL, value = params$L %||% 5.0, min = 0.01, step = 0.1),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type == "coupled") {
        fields <- c(fields, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Gap"),
            numericInput(ns("prop_gap"), NULL, value = params$gap %||% 0.2, min = 0.001, step = 0.01),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type == "via") {
        fields <- c(fields, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Drill"),
            numericInput(ns("prop_drill"), NULL, value = params$drill %||% 0.3, min = 0.05, step = 0.05),
            tags$span(class = "rfcad-prop-unit", "mm")
          ),
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Pad"),
            numericInput(ns("prop_pad"), NULL, value = params$pad %||% 0.6, min = 0.1, step = 0.05),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type == "port") {
        fields <- c(fields, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Port #"),
            numericInput(ns("prop_portNum"), NULL, value = params$portNum %||% 1, min = 1, step = 1)
          )
        ))
      }

      fields <- c(fields, list(
        div(style = "margin-top:8px;",
          actionButton(ns("prop_apply"), "Apply",
            class = "btn-primary btn-sm btn-block", icon = icon("check")))
      ))

      tagList(fields)
    })

    # Apply property changes
    observeEvent(input$prop_apply, {
      req(!is.null(rv$selected))
      updated_params <- Filter(Negate(is.null), list(
        W       = input$prop_W,
        L       = input$prop_L,
        gap     = input$prop_gap,
        drill   = input$prop_drill,
        pad     = input$prop_pad,
        portNum = input$prop_portNum
      ))
      session$sendCustomMessage("rfcad_update_param", list(
        instanceId  = id,
        componentId = rv$selected$id,
        name        = input$prop_name %||% rv$selected$name,
        rotation    = input$prop_rotation %||% rv$selected$rotation,
        params      = updated_params
      ))
    }, ignoreInit = TRUE)

    # Design summary
    output$design_summary <- renderUI({
      comps <- rv$components
      n <- length(comps)
      if (n == 0) return(div(style = "color:#666; font-size:11px; padding:4px 8px;",
        "No components placed."))
      types <- table(vapply(comps, function(c) c$type %||% "?", character(1)))
      tagList(
        div(style = "color:#c8a84b; font-weight:600; font-size:11px; margin:4px 8px;",
          sprintf("Total: %d component%s", n, if (n == 1) "" else "s")),
        lapply(names(types), function(tp) {
          div(class = "rfcad-prop-row", style = "padding:0 8px;",
            tags$span(class = "rfcad-prop-label", tp),
            tags$span(style = "color:#c8a84b;", types[[tp]]))
        })
      )
    })

    # Save trigger (toolbar Save button)
    observeEvent(input$save_trigger, {
      req(!is.null(input$save_trigger), nzchar(input$save_trigger))
      rv$last_save <- input$save_trigger
    }, ignoreInit = TRUE)

    # Public interface
    list(
      components = reactive(rv$components),
      selected   = reactive(rv$selected),
      substrate  = reactive(rv$substrate),
      get_json   = function() {
        jsonlite::toJSON(
          list(version = "1.0", substrate = rv$substrate, components = rv$components),
          auto_unbox = TRUE, pretty = TRUE
        )
      }
    )
  })
}
