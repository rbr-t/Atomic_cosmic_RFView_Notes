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
.KONVA_CDN      <- "https://unpkg.com/konva@9.3.14/konva.min.js"
.THREE_CDN      <- "https://cdn.jsdelivr.net/npm/three@0.134.0/build/three.min.js"
.ORBIT_CDN      <- "https://cdn.jsdelivr.net/npm/three@0.134.0/examples/js/controls/OrbitControls.js"

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

# ── R-side RF helpers (used by BOM table) ───────────────────────────────────
.ms_z0 <- function(W, h, er) {
  if (is.null(W) || is.null(h) || is.null(er) || W <= 0 || h <= 0) return(NA_real_)
  u    <- W / h
  eeff <- (er + 1) / 2 + (er - 1) / 2 * (1 + 12 / u)^(-0.5)
  Z0   <- if (u < 1) 60 * log(8 / u + u / 4) / sqrt(eeff)
          else       (120 * pi / (u + 1.393 + 0.667 * log(u + 1.444))) / sqrt(eeff)
  list(Z0 = round(Z0, 1), eeff = round(eeff, 3))
}

.ms_theta <- function(L_mm, freq_GHz, eeff) {
  if (any(sapply(list(L_mm, freq_GHz, eeff), is.null))) return(NA_real_)
  round(L_mm * freq_GHz * sqrt(eeff) * 360 / 299.792, 1)  # degrees
}

.rfcad_designs_dir <- function() {
  # Relative to the app root (one level up from R/)
  d <- tryCatch(
    normalizePath(file.path(getwd(), "..", "www", "designs"), mustWork = FALSE),
    error = function(e) tempdir()
  )
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# =============================================================================
# rfCadUI(id, height, compact)
# =============================================================================
rfCadUI <- function(id, height = "600px", compact = FALSE) {

  ns <- NS(id)

  # Assets served from the app's own www/ (standard Shiny path)
  # Version suffix forces browser to bypass cache after file updates.
  js_path  <- "js/rf_canvas.js?v=20260317"
  css_path <- "css/rf_cad.css"

  # ── Shared JS helper: set active tool button ────────────────────────────
  # Called by every tool button so only one is highlighted at a time
  .tool_js <- function(toolName) sprintf(
    "(function(){
      var c=RFCAD.getCanvas('%s');if(!c)return;
      c.setTool('%s');
      document.querySelectorAll('#%s_tb [data-tool]').forEach(function(b){
        b.classList.toggle('active', b.dataset.tool==='%s');
      });
    })();",
    id, toolName, id, toolName
  )

  # ── Helper: make a toolbar button ───────────────────────────────────────
  .tb_btn <- function(icon, label, title, onclick, extra_class = "", tool = NULL, btn_id = NULL) {
    args <- list(
      class   = paste("rfcad-tb-btn", extra_class),
      title   = title,
      onclick = onclick
    )
    if (!is.null(tool))   args[["data-tool"]] <- tool
    if (!is.null(btn_id)) args[["id"]]        <- btn_id
    do.call(tags$button, c(args, list(
      tags$span(class = "rfcad-tb-icon", icon),
      tags$span(class = "rfcad-tb-label", label)
    )))
  }

  .tb_sep <- function() tags$span(class = "rfcad-tb-sep")

  # ═══════════════════════════════════════════════════════════════════════
  # TOOLBAR ROWS
  # ═══════════════════════════════════════════════════════════════════════

  # ── Row 1: Drafting / Drawing Tools ─────────────────────────────────────
  tb_row1 <- div(class = "rfcad-tb-row",
    div(class = "rfcad-tb-group-label", "Drafting"),
    .tb_btn("\u25b6", "Select",   "Select / Move (V)",          .tool_js("select"),    tool = "select"),
    .tb_btn("\u270b", "Pan",      "Pan canvas (Space+drag)",    .tool_js("pan"),       tool = "pan"),
    .tb_sep(),
    .tb_btn("\u2500", "Line",     "Draw single line segment",   .tool_js("line"),      tool = "line"),
    .tb_btn("\u299a", "Polyline", "Draw polyline (dbl-click end)", .tool_js("polyline"),  tool = "polyline"),
    .tb_btn("\u25e0", "Arc",      "3-point arc",                .tool_js("arc"),       tool = "arc"),
    .tb_btn("\u25ad", "Rect",     "Draw rectangle",             .tool_js("rect"),      tool = "rect"),
    .tb_btn("\u25cb", "Circle",   "Draw circle",                .tool_js("circle"),    tool = "circle"),
    .tb_btn("\u2b21", "Polygon",  "Draw polygon",               .tool_js("polygon"),   tool = "polygon"),
    .tb_sep(),
    .tb_btn("\U0001f4cf", "Ruler", "Measure distance + angle",
      sprintf(
        "(function(){
          var c=RFCAD.getCanvas('%s');if(!c)return;
          var btns=document.querySelectorAll('#%s_tb [data-tool]');
          btns.forEach(function(b){b.classList.remove('active');});
          var me=document.querySelector('#%s_tb [data-tool=ruler]');
          var wasActive=me&&me.classList.contains('active');
          if(!wasActive){if(me)me.classList.add('active');c.setTool('ruler');}
          else{c.clearMeasure();c.setTool('select');}
        })();",
        id, id, id
      ),
      tool = "ruler"
    ),
    .tb_btn("\u2220", "AngleDim", "Angle dimension annotation", .tool_js("angle_dim"), tool = "angle_dim"),
    .tb_btn("\U0001f4dd", "Text",  "Place text annotation",      .tool_js("text"),      tool = "text")
  )

  # ── Row 2: RF Components ─────────────────────────────────────────────────
  rf_comp_items <- list(
    list(type="ms",         icon="\u2500", label="MS",      title="Microstrip line (2-click draw)"),
    list(type="bend90",     icon="\u231d", label="Bend",    title="90\u00b0 bend / miter"),
    list(type="tee",        icon="\u22a5", label="T-Jct",   title="T-Junction"),
    list(type="coupled",    icon="\u2016", label="Coupled", title="Edge-coupled lines"),
    list(type="via",        icon="\u25cf", label="Via",     title="GND via (drill+pad)"),
    list(type="port",       icon="\u25c6", label="Port",    title="RF Port (numbered)"),
    list(type="open_stub",  icon="\u2a10", label="OStub",   title="Open-ended stub"),
    list(type="short_stub", icon="\u23da", label="SStub",   title="Short/GND stub")
  )
  tb_row2 <- div(class = "rfcad-tb-row",
    div(class = "rfcad-tb-group-label", "RF Components"),
    lapply(rf_comp_items, function(it)
      .tb_btn(it$icon, it$label, it$title, .tool_js(it$type), tool = it$type)
    )
  )

  # ── Row 3: Modification Tools ────────────────────────────────────────────
  tb_row3 <- div(class = "rfcad-tb-row",
    div(class = "rfcad-tb-group-label", "Modify"),
    .tb_btn("\u21a9", "Undo", "Undo last action (Ctrl+Z)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.undo();", id),
      tool = "undo"),
    .tb_btn("\u21aa", "Redo", "Redo (Ctrl+Y)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.redo();", id),
      tool = "redo"),
    .tb_sep(),
    .tb_btn("\u2715",     "Delete",   "Delete selected (Del)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.deleteSelected();", id)),
    .tb_btn("\u21bb",     "Rot+45",   "Rotate +45\u00b0 (R)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.rotateSelected(45);", id)),
    .tb_btn("\u21ba",     "Rot-45",   "Rotate -45\u00b0",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.rotateSelected(-45);", id)),
    .tb_btn("\u2194",     "MirrorH",  "Mirror horizontal",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.mirrorSelected('h');", id)),
    .tb_btn("\u2195",     "MirrorV",  "Mirror vertical",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.mirrorSelected('v');", id)),
    .tb_sep(),
    .tb_btn("\U0001f4cb", "Copy",     "Copy selected (Ctrl+C)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.copySelected();", id)),
    .tb_btn("\u2397",     "Array",    "Rectangular array of selected",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.arraySelected();", id)),
    .tb_btn("\u25a1",     "Offset",   "Offset selected shape outward",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.offsetSelected();", id)),
    .tb_sep(),
    .tb_btn("\u2692",     "Chamfer",  "Chamfer selected corner",
      .tool_js("chamfer"), tool = "chamfer"),
    .tb_btn("\u25dc",     "Fillet",   "Fillet (round) selected corner",
      .tool_js("fillet"),  tool = "fillet")
  )

  # ── Row 4: Annotation Tools ───────────────────────────────────────────────
  tb_row4 <- div(class = "rfcad-tb-row",
    div(class = "rfcad-tb-group-label", "Annotation"),
    .tb_btn("\u21a6",     "DimH",     "Horizontal dimension",    .tool_js("dim_h"),    tool = "dim_h"),
    .tb_btn("\u21a7",     "DimV",     "Vertical dimension",      .tool_js("dim_v"),    tool = "dim_v"),
    .tb_btn("\u21d7",     "DimAngld", "Aligned dimension",       .tool_js("dim_align"),tool = "dim_align"),
    .tb_btn("\u2934",     "Leader",   "Leader with annotation",  .tool_js("leader"),   tool = "leader"),
    .tb_btn("\u25a6",     "Label",    "Place component label",   .tool_js("label"),    tool = "label"),
    .tb_sep(),
    .tb_btn("\U0001f4cb", "BOM",      "Bill of Materials & Revisions",
      sprintf("Shiny.setInputValue('%s', Math.random(), {priority:'event'});",
              paste0(id, "-show_bom_rev")))
  )

  # ── Row 5: View / Layer / File Controls ──────────────────────────────────
  tb_row5 <- div(class = "rfcad-tb-row rfcad-tb-row-view",
    div(class = "rfcad-tb-group-label", "View"),
    .tb_btn("+",          "ZoomIn",  "Zoom in (scroll)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.zoomBy(1.25);", id)),
    .tb_btn("\u2212",      "ZoomOut", "Zoom out",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.zoomBy(0.8);", id)),
    .tb_btn("\u26f6",      "Fit",     "Fit content to view (F)",
      sprintf("var c=RFCAD.getCanvas('%s');if(c)c.fitToContent();", id)),
    .tb_sep(),
    # 3D toggle
    .tb_btn("\U0001f9ca", "3D", "Toggle 3D view",
      sprintf(
        "(function(){
          var w2=document.getElementById('%s_2d_wrap'),w3=document.getElementById('%s_3d_wrap');
          var is3d=w3.style.display!=='none';
          if(is3d){w2.style.display='';w3.style.display='none';}
          else{w2.style.display='none';w3.style.display='';
            var c=RFCAD.getCanvas('%s');var j=c?c.exportJSON():'{}';
            if(typeof RF3D!=='undefined'){(function(json,cid){setTimeout(function(){RF3D.render(json,cid);},120);})(j,'%s_3d_canvas');}}
          document.querySelector('#%s_tb [data-tool=\'3d\']').classList.toggle('active',!is3d);
        })();",
        id, id, id, id, id
      ),
      tool = "3d"
    ),
    .tb_sep(),
    # Layer panel toggle
    .tb_btn("\u25a3", "Layers", "Toggle layer panel",
      sprintf(
        "(function(){
          var lp=document.getElementById('%s_layer_panel');
          if(!lp)return;
          var vis=lp.style.display==='block';
          lp.style.display=vis?'none':'block';
          document.querySelector('#%s_tb [data-tool=\'layers\']').classList.toggle('active',!vis);
        })();",
        id, id
      ),
      tool = "layers"
    ),
    .tb_sep(),
    # Schematic / Symbol mode toggle
    .tb_btn("\u25a1\u2082", "Schematic", "Toggle schematic symbol mode",
      sprintf(
        "(function(){var c=RFCAD.getCanvas('%s');if(c)c.toggleSymbolMode();})();",
        id
      ),
      tool = "schematic"
    ),
    .tb_sep(),
    tags$span(class = "rfcad-tb-inline-label", "Grid:"),
    tags$select(
      id       = ns("grid_size"),
      class    = "rfcad-tb-select",
      onchange = sprintf("var c=RFCAD.getCanvas('%s');if(c)c.setGrid(parseFloat(this.value));", id),
      tags$option(value="0.1",  "0.1mm"),
      tags$option(value="0.25", "0.25mm"),
      tags$option(value="0.5",  selected="selected", "0.5mm"),
      tags$option(value="1.0",  "1mm"),
      tags$option(value="2.0",  "2mm")
    ),
    tags$label(
      class = "rfcad-tb-snap-label",
      title = "Snap to grid",
      tags$input(
        type="checkbox", id=ns("snap_grid"), checked="checked",
        onchange=sprintf("var c=RFCAD.getCanvas('%s');if(c)c.setSnap(this.checked);", id)
      ),
      "Snap"
    ),
    .tb_sep(),
    # Save
    .tb_btn("\U0001f4be", "Save", "Save design to JSON",
      sprintf(
        "var c=RFCAD.getCanvas('%s');if(c){var d=c.exportJSON();Shiny.setInputValue('%s',d,{priority:'event'});}",
        id, ns("save_trigger")
      )
    ),
    # Clear
    .tb_btn("\u2717", "Clear", "Clear all components",
      sprintf("if(confirm('Clear all components?')){var c=RFCAD.getCanvas('%s');if(c)c.clearAll();}", id)
    ),
    # New Session
    .tb_btn("\u2b1c", "New", "Start a new blank session (clears saved state)",
      sprintf(
        "if(confirm('Start new session? Current design will be lost.')){var c=RFCAD.getCanvas('%s');if(c)c.clearSession();}",
        id
      )
    ),
    .tb_sep(),
    # Export dropdown
    div(class = "rfcad-export-wrap",
      tags$button(
        class   = "rfcad-tb-btn rfcad-export-btn",
        onclick = sprintf(
          "(function(){var m=document.getElementById('%s_export_menu');m.style.display=m.style.display==='block'?'none':'block';})();",
          id
        ),
        tags$span(class="rfcad-tb-icon", "\U0001f4e4"),
        tags$span(class="rfcad-tb-label", "Export\u25be")
      ),
      div(id = paste0(id, "_export_menu"), class = "rfcad-export-menu",
        tags$a(class="rfcad-export-item", href="#",
          onclick=sprintf(
            "(function(){var c=RFCAD.getCanvas('%s');if(!c){alert('No canvas');return false;}var url=c.exportSVG();if(!url){alert('SVG not available');return false;}var a=document.createElement('a');a.href=url;a.download='%s_design.svg';a.click();document.getElementById('%s_export_menu').style.display='none';return false;})();",
            id,id,id),
          "\U0001f5bc SVG"
        ),
        tags$a(class="rfcad-export-item", href="#",
          onclick=sprintf(
            "(function(){var c=RFCAD.getCanvas('%s');if(!c){alert('No canvas');return false;}var j=c.exportJSON();Shiny.setInputValue('%s',{json:j,fmt:'dxf',ts:Date.now()},{priority:'event'});document.getElementById('%s_export_menu').style.display='none';return false;})();",
            id,paste0(id,"-export_trigger"),id),
          "\U0001f4d0 DXF"
        ),
        tags$a(class="rfcad-export-item", href="#",
          onclick=sprintf(
            "(function(){var c=RFCAD.getCanvas('%s');if(!c){alert('No canvas');return false;}var j=c.exportJSON();Shiny.setInputValue('%s',{json:j,fmt:'gerber',ts:Date.now()},{priority:'event'});document.getElementById('%s_export_menu').style.display='none';return false;})();",
            id,paste0(id,"-export_trigger"),id),
          "\U0001f9ff Gerber"
        )
      )
    ),
    .tb_sep(),
    # Expand toggle
    .tb_btn("\u26f6", "Expand", "Expand RF CAD to 95% of screen (hides sidebar)",
      sprintf(
        "(function(){
          var wrap=document.getElementById('%s_outer');
          if(!wrap)return;
          var expanded=wrap.classList.toggle('rfcad-expanded');
          document.querySelector('#%s_tb [data-tool=\'expand\']').classList.toggle('active',expanded);
          var c=RFCAD.getCanvas('%s');
          setTimeout(function(){
            var el=document.getElementById('%s');
            if(el&&c&&c.stage){c.stage.width(el.offsetWidth);c.stage.height(el.offsetHeight);c.drawGrid();}
          },320);
        })();",
        id, id, id, ns("rfcad_canvas")
      ),
      tool = "expand"
    ),
    # Pop-out in a standalone window (no sidebar/header)
    .tb_btn("\u29c9", "New Tab", "Open RF CAD in a standalone window",
      "window.open(location.href.split('?')[0]+'?panel=rf_tools&rfcad=1&standalone=1','_blank','width=1400,height=860,menubar=no,toolbar=no,location=no,status=no,resizable=yes');"
    )
  )

  # ── Component palette (left sidebar) ─────────────────────────────────────
  palette_btns <- lapply(rf_comp_items, function(item) {
    tags$button(
      class       = "rfcad-palette-btn",
      `data-type` = item$type,
      title       = item$title,
      onclick     = .tool_js(item$type),
      tags$span(class = "rfcad-palette-icon", item$icon),
      tags$span(class = "rfcad-palette-label", item$label)
    )
  })

  palette_grid <- div(class = "rfcad-palette-grid", palette_btns)

  # ── Layer Panel (floating, toggled by Layers button) ─────────────────────
  layer_defs <- list(
    list(id="metal_top",     color="#c8a84b", label="Metal Top",   locked=FALSE),
    list(id="metal_bot",     color="#7b9fc7", label="Metal Bot",   locked=FALSE),
    list(id="metal_inner_1", color="#8fcf70", label="Inner 1",     locked=FALSE),
    list(id="metal_inner_2", color="#c878c8", label="Inner 2",     locked=FALSE),
    list(id="substrate",     color="#4a8a4a", label="Substrate",   locked=TRUE),
    list(id="silkscreen",    color="#ffffff", label="Silkscreen",  locked=FALSE),
    list(id="drc",           color="#ff4444", label="DRC / Errors",locked=TRUE)
  )
  layer_rows <- lapply(layer_defs, function(ly) {
    div(class = "rfcad-layer-row",
      # Eye (visibility) toggle
      tags$button(
        class   = "rfcad-layer-eye active",
        id      = sprintf("%s_lyr_eye_%s", id, ly$id),
        title   = "Toggle layer visibility",
        `data-layer` = ly$id,
        onclick = sprintf(
          "(function(){
            var btn=this; btn.classList.toggle('active');
            var vis=btn.classList.contains('active');
            var c=RFCAD.getCanvas('%s');
            if(c) c.setLayerVisible('%s', vis);
          }).call(this);",
          id, ly$id
        ),
        "\U0001f441"
      ),
      # Lock toggle
      tags$button(
        class   = if(ly$locked) "rfcad-layer-lock active" else "rfcad-layer-lock",
        id      = sprintf("%s_lyr_lock_%s", id, ly$id),
        title   = "Toggle layer lock",
        `data-layer` = ly$id,
        onclick = sprintf(
          "(function(){
            var btn=this; btn.classList.toggle('active');
            var locked=btn.classList.contains('active');
            var c=RFCAD.getCanvas('%s');
            if(c) c.setLayerLocked('%s', locked);
          }).call(this);",
          id, ly$id
        ),
        if(ly$locked) "\U0001f512" else "\U0001f513"
      ),
      # Color swatch
      tags$span(
        class = "rfcad-layer-swatch",
        style = sprintf("background:%s;", ly$color)
      ),
      # Layer name (click to set as active draw layer)
      tags$button(
        class   = if(ly$id == "metal_top") "rfcad-layer-name active" else "rfcad-layer-name",
        id      = sprintf("%s_lyr_name_%s", id, ly$id),
        title   = "Set as active draw layer",
        onclick = sprintf(
          "(function(){
            document.querySelectorAll('#%s_layer_panel .rfcad-layer-name').forEach(function(b){
              b.classList.remove('active');
            });
            this.classList.add('active');
            var c=RFCAD.getCanvas('%s');
            if(c) c.setActiveLayer('%s');
          }).call(this);",
          id, id, ly$id
        ),
        ly$label
      )
    )
  })

  layer_panel <- div(
    id    = paste0(id, "_layer_panel"),
    class = "rfcad-layer-panel",
    style = "display:none;",
    div(class = "rfcad-layer-panel-header",
      "\u25a3 Layers",
      tags$button(
        class   = "rfcad-layer-panel-close",
        onclick = sprintf(
          "document.getElementById('%s_layer_panel').style.display='none';
           document.querySelector('#%s_tb [data-tool=layers]').classList.remove('active');",
          id, id
        ),
        "\u00d7"
      )
    ),
    do.call(div, c(list(class = "rfcad-layer-list"), layer_rows))
  )

  # ── Properties panel ─────────────────────────────────────────────────────
  props_panel <- div(
    class = "rfcad-properties",
    div(class = "rfcad-panel-header", "Properties",
      # Mini layer active-layer indicator
      tags$span(id = paste0(id, "_active_layer_badge"),
        class = "rfcad-active-layer-badge",
        style = "background:#c8a84b; color:#111;",
        "Metal Top"
      )
    ),

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
    div(class = "rfcad-prop-row",
      tags$label(class = "rfcad-prop-label", "Freq"),
      numericInput(ns("freq_ghz"), NULL, value = 2.4,  min = 0.1,  max = 100, step = 0.1),
      tags$span(class = "rfcad-prop-unit", "GHz")
    ),

    tags$hr(style = "border-color:#2a2a3a; margin:8px 0;"),
    div(class = "rfcad-panel-header rfcad-panel-subheader", "Selected Component"),
    uiOutput(ns("rfcad_props")),
    div(id = paste0("rfcad_rf_params_", id), class = "rfcad-rf-params-wrapper"),

    tags$hr(style = "border-color:#2a2a3a; margin:8px 0;"),
    div(class = "rfcad-panel-header rfcad-panel-subheader", "Design"),
    uiOutput(ns("design_summary"))
  )

  # ── Full layout ──────────────────────────────────────────────────────────
  tagList(
    singleton(tags$head(
      tags$script(src = .KONVA_CDN),
      tags$script(src = .THREE_CDN),
      tags$script(src = .ORBIT_CDN),
      tags$script(src = js_path),
      tags$script(src = "js/rf_calc_lib.js"),
      tags$script(src = "js/rf_3d_viewer.js?v=20260317"),
      tags$link(rel = "stylesheet", href = css_path)
    )),

    # Outer wrapper carries the rfcad-expanded class for 95% expand mode
    div(
      id    = paste0(id, "_outer"),
      class = if (compact) "rfcad-outer rfcad-compact" else "rfcad-outer",

      div(
        class = "rfcad-app-wrapper",
        style = sprintf("height:%s;", height),

        # ── Multi-row toolbar band ──────────────────────────────────────
        div(id = paste0(id, "_tb"), class = "rfcad-tb-band",
          tb_row1,
          tb_row2,
          tb_row3,
          tb_row4,
          tb_row5
        ),

        div(class = "rfcad-body",
          # Left palette sidebar (quick-access RF components)
          div(class = "rfcad-palette",
            div(class = "rfcad-panel-header", "Components"),
            palette_grid
          ),

          # Canvas area — layer panel floats inside this
          div(class = "rfcad-canvas-wrapper",
            layer_panel,
            # 2D canvas
            div(id = paste0(id, "_2d_wrap"), style = "width:100%;height:100%;",
              div(id = ns("rfcad_canvas"), class = "rfcad-canvas-container")
            ),
            # 3D canvas (hidden by default, absolutely fills wrapper)
            div(id = paste0(id, "_3d_wrap"), style = "position:absolute;inset:0;display:none;",
              div(id = paste0(id, "_3d_canvas"), class = "rfcad-3d-container")
            )
          ),

          props_panel
        ),

        div(id = paste0("rfcad_status_", id), class = "rfcad-statusbar",
          tags$span(id = paste0(id, "_status_tool"),  class = "rfcad-statusbar-tool",  "Select"),
          tags$span(class = "rfcad-statusbar-sep", "|"),
          tags$span(id = paste0(id, "_status_layer"), class = "rfcad-statusbar-layer", "Metal Top"),
          tags$span(class = "rfcad-statusbar-sep", "|"),
          tags$span(id = paste0(id, "_status_coords"), class = "rfcad-statusbar-coords", "(0.000, 0.000) mm"),
          tags$span(class = "rfcad-statusbar-sep", "|"),
          tags$span(id = paste0(id, "_status_info"),  class = "rfcad-statusbar-info",  "Ready")
        )
      )
    ),

    tags$script(HTML(sprintf(
      "(function(){
        /* ---- initial bootstrap (also works when tab is hidden) ---- */
        function initCanvas(){
          if(typeof RFCAD==='undefined'||typeof Konva==='undefined'){
            setTimeout(initCanvas,100); return;
          }
          var el=document.getElementById('%s');
          if(!el){ setTimeout(initCanvas,150); return; }
          if(el.offsetWidth===0){ setTimeout(initCanvas,150); return; }
          if(!RFCAD.canvases['%s']) {
            RFCAD.canvases['%s'] = RFCAD.createCanvas('%s','%s','%s');
          }
        }
        if(document.readyState==='loading'){
          document.addEventListener('DOMContentLoaded',initCanvas);
        } else { initCanvas(); }

        /* ---- Shiny message handler (re-init after tab reveal) ---- */
        Shiny.addCustomMessageHandler('rfcad_init', function(msg){
          var el=document.getElementById(msg.containerId);
          if(!el) return;
          function tryInit(){
            if(typeof RFCAD==='undefined'||typeof Konva==='undefined'){
              setTimeout(tryInit,100); return;
            }
            if(el.offsetWidth===0){ setTimeout(tryInit,150); return; }
            if(!RFCAD.canvases[msg.instanceId]) {
              RFCAD.canvases[msg.instanceId] =
                RFCAD.createCanvas(msg.containerId, msg.nsPrefix, msg.instanceId);
            } else {
              /* already exists but may have 0-size stage from hidden tab */
              var c = RFCAD.canvases[msg.instanceId];
              if(c && c.stage && c.stage.width()===0){
                c.stage.width(el.offsetWidth);
                c.stage.height(el.offsetHeight||500);
                if(c.drawGrid) c.drawGrid();
              }
            }
          }
          tryInit();
        });
      })();",
      ns("rfcad_canvas"),
      id, id, ns("rfcad_canvas"), id, id
    )))
  )
}


# =============================================================================
# rfCadServer(id)
# =============================================================================
rfCadServer <- function(id) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Robust canvas initialization (works inside hidden tabs) ──────────────
    # The rfcad_init JS handler waits until offsetWidth > 0 before creating
    # the Konva stage, making it safe when the RF CAD tab is initially hidden.
    session$onFlushed(function() {
      session$sendCustomMessage("rfcad_init", list(
        instanceId  = id,
        containerId = ns("rfcad_canvas"),
        nsPrefix    = id
      ))
    }, once = TRUE)

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
        list(instanceId = id, h = sub$h, er = sub$er, tand = sub$tanD, t = sub$t))
    })

    # Push frequency to canvas (Phase 2)
    observe({
      req(!is.null(input$freq_ghz))
      session$sendCustomMessage("rfcad_set_freq",
        list(instanceId = id, freq_GHz = input$freq_ghz %||% 2.4))
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

    # Properties panel — Phase 4: Geometry + Material tabs
    output$rfcad_props <- renderUI({
      comp <- rv$selected
      if (is.null(comp)) {
        return(div(style = "color:#666; font-size:11px; padding:4px 8px;",
          "Click a component to edit its properties."))
      }

      params <- comp$params %||% list()
      mat    <- comp$mat    %||% list()
      type   <- comp$type   %||% "ms"

      # ── Geometry tab ─────────────────────────────────────────────────
      geo <- list(
        div(class = "rfcad-prop-row",
          tags$label(class = "rfcad-prop-label", "Name"),
          textInput(ns("prop_name"), NULL, value = comp$name %||% "")
        ),
        div(class = "rfcad-prop-row",
          tags$label(class = "rfcad-prop-label", "Layer"),
          selectInput(ns("prop_layer"), NULL,
            choices  = c("\u25a0 Metal Top" = "metal_top",
                         "\u25a0 Metal Bot" = "metal_bot",
                         "\u25a0 Inner 1"   = "metal_inner_1",
                         "\u25a0 Inner 2"   = "metal_inner_2"),
            selected = comp$layer %||% "metal_top")
        ),
        div(class = "rfcad-prop-row",
          tags$label(class = "rfcad-prop-label", "Rotation"),
          numericInput(ns("prop_rotation"), NULL, value = comp$rotation %||% 0, step = 45),
          tags$span(class = "rfcad-prop-unit", "\u00b0")
        )
      )

      if (type %in% c("ms", "bend90", "open_stub", "short_stub", "tee")) {
        geo <- c(geo, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "W"),
            numericInput(ns("prop_W"), NULL, value = params$W %||% 0.5, min = 0.001, step = 0.01),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type %in% c("ms", "bend90", "open_stub", "short_stub", "tee", "coupled")) {
        geo <- c(geo, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "L"),
            numericInput(ns("prop_L"), NULL, value = params$L %||% 5.0, min = 0.01, step = 0.1),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type == "bend90") {
        geo <- c(geo, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Miter"),
            div(style = "padding-top:3px;",
              checkboxInput(ns("prop_miter"), "Mitered corner",
                value = !isFALSE(params$miter)))
          )
        ))
      }

      if (type == "coupled") {
        geo <- c(geo, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Gap"),
            numericInput(ns("prop_gap"), NULL, value = params$gap %||% 0.2, min = 0.001, step = 0.01),
            tags$span(class = "rfcad-prop-unit", "mm")
          )
        ))
      }

      if (type == "via") {
        geo <- c(geo, list(
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
        geo <- c(geo, list(
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "Port #"),
            numericInput(ns("prop_portNum"), NULL, value = params$portNum %||% 1, min = 1, step = 1)
          )
        ))
      }

      # ── Material override tab ─────────────────────────────────────────
      mat_has_override <- length(mat) > 0 && !is.null(mat$er)
      mat_tab <- tagList(
        div(class = "rfcad-prop-row", style = "padding-top:4px;",
          checkboxInput(ns("mat_override"), "Override substrate",
            value = mat_has_override)
        ),
        conditionalPanel(
          condition = paste0("input['", ns("mat_override"), "'] === true"),
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "\u03b5r"),
            numericInput(ns("mat_er"), NULL,
              value = mat$er %||% rv$substrate$er %||% 3.55,
              min = 1, max = 100, step = 0.01)
          ),
          div(class = "rfcad-prop-row",
            tags$label(class = "rfcad-prop-label", "tan\u03b4"),
            numericInput(ns("mat_tanD"), NULL,
              value = mat$tanD %||% rv$substrate$tanD %||% 0.0027,
              min = 0, max = 1, step = 0.0001)
          )
        )
      )

      tagList(
        tabsetPanel(type = "pills", id = ns("prop_tabs"),
          tabPanel("Geometry", tagList(geo)),
          tabPanel("Material", mat_tab)
        ),
        div(style = "margin-top:6px; padding:0 4px;",
          actionButton(ns("prop_apply"), "Apply",
            class = "btn-primary btn-sm btn-block", icon = icon("check")))
      )
    })

    # Apply property changes (Phase 4 — structured send with layer + mat)
    observeEvent(input$prop_apply, {
      req(!is.null(rv$selected))
      updated_params <- Filter(Negate(is.null), list(
        W       = input$prop_W,
        L       = input$prop_L,
        gap     = input$prop_gap,
        drill   = input$prop_drill,
        pad     = input$prop_pad,
        portNum = input$prop_portNum,
        miter   = if (!is.null(input$prop_miter)) input$prop_miter else NULL
      ))
      mat_data <- if (isTRUE(input$mat_override)) {
        Filter(Negate(is.null), list(
          er   = input$mat_er,
          tanD = input$mat_tanD
        ))
      } else {
        list()  # empty = use substrate defaults
      }
      session$sendCustomMessage("rfcad_update_param", list(
        instanceId  = id,
        componentId = rv$selected$id,
        name        = input$prop_name     %||% rv$selected$name,
        rotation    = input$prop_rotation %||% rv$selected$rotation,
        layer       = input$prop_layer    %||% rv$selected$layer %||% "metal_top",
        params      = updated_params,
        mat         = mat_data
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

    # ── BOM / Revision modal ──────────────────────────────────────────────
    observeEvent(input$show_bom_rev, {
      showModal(modalDialog(
        title = tagList(
          tags$span(style = "color:#c8a84b;", "\U0001f4cb"),
          " Design BOM & Revisions"
        ),
        size  = "l",
        easyClose = TRUE,
        footer = modalButton("Close"),

        tabsetPanel(
          tabPanel("Bill of Materials",
            div(style = "margin-top:8px;",
              DT::dataTableOutput(ns("bom_dt"))
            )
          ),
          tabPanel("Save / Revisions",
            div(style = "padding:12px;",
              div(style = "margin-bottom:8px;",
                textInput(ns("commit_msg"), "Commit message",
                  value  = paste0("Design snapshot ", format(Sys.time(), "%Y-%m-%d %H:%M")),
                  width  = "100%"),
                div(style = "display:flex; gap:8px; margin-top:6px;",
                  actionButton(ns("design_save"),   "Save JSON",
                    class = "btn-default btn-sm", icon = icon("download")),
                  actionButton(ns("design_commit"), "Save + Git Commit",
                    class = "btn-primary btn-sm", icon = icon("code-branch"))
                )
              ),
              tags$hr(style = "border-color:#333;"),
              div(style = "margin-top:6px;",
                strong(style = "color:#c8a84b; font-size:12px;", "Recent commits"),
                uiOutput(ns("revision_list"))
              )
            )
          )
        )
      ))
    }, ignoreInit = TRUE)

    # BOM table
    output$bom_dt <- DT::renderDataTable({
      comps <- rv$components
      sub   <- rv$substrate
      freq  <- input$freq_ghz %||% 2.4
      if (length(comps) == 0) {
        return(data.frame(Message = "No components placed."))
      }
      rows <- lapply(seq_along(comps), function(i) {
        comp    <- comps[[i]]
        p       <- comp$params %||% list()
        mat     <- comp$mat    %||% list()
        er_use  <- mat$er   %||% sub$er   %||% 3.55
        h_use   <- sub$h    %||% 0.508
        W       <- p$W      %||% NA_real_
        L       <- p$L      %||% NA_real_
        rf      <- if (!is.na(W)) .ms_z0(W, h_use, er_use) else list(Z0 = NA_real_, eeff = NA_real_)
        theta   <- if (!is.na(L) && !is.na(rf$eeff)) .ms_theta(L, freq, rf$eeff) else NA_real_
        data.frame(
          `#`    = i,
          Type   = comp$type   %||% "",
          Name   = comp$name   %||% "",
          Layer  = comp$layer  %||% "metal_top",
          `W(mm)`= if (!is.na(W)) round(W, 4) else NA_real_,
          `L(mm)`= if (!is.na(L)) round(L, 4) else NA_real_,
          "Z0(Ohm)"  = rf$Z0,
          "Theta(deg)" = theta,
          check.names = FALSE, stringsAsFactors = FALSE
        )
      })
      do.call(rbind, rows)
    }, options = list(
      pageLength = 20, dom = 'tip', scrollX = TRUE,
      columnDefs = list(list(className = 'dt-center', targets = '_all'))
    ), rownames = FALSE)

    # Save JSON to www/designs/
    observeEvent(input$design_save, {
      json_str <- jsonlite::toJSON(
        list(version = "1.0", substrate = rv$substrate, components = rv$components),
        auto_unbox = TRUE, pretty = TRUE
      )
      dest <- file.path(.rfcad_designs_dir(),
        paste0(id, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json"))
      tryCatch({
        writeLines(json_str, dest)
        showNotification(paste0("Saved: ", basename(dest)),
          type = "message", duration = 4)
      }, error = function(e) {
        showNotification(paste0("Save failed: ", e$message), type = "error")
      })
    }, ignoreInit = TRUE)

    # Save JSON + git commit
    observeEvent(input$design_commit, {
      req(nzchar(input$commit_msg %||% ""))
      json_str <- jsonlite::toJSON(
        list(version = "1.0", substrate = rv$substrate, components = rv$components),
        auto_unbox = TRUE, pretty = TRUE
      )
      fname <- paste0(id, "_design.json")
      dest  <- file.path(.rfcad_designs_dir(), fname)
      tryCatch({
        writeLines(json_str, dest)
        # Try git add + commit via system (git2r has env issues in some docker envs)
        repo_root <- tryCatch(
          system2("git", c("rev-parse", "--show-toplevel"),
            stdout = TRUE, stderr = FALSE),
          error = function(e) character(0)
        )
        if (length(repo_root) > 0 && nzchar(repo_root)) {
          system2("git", c("add", dest))
          system2("git", c("commit", "-m",
            paste0("[rf-cad] ", input$commit_msg %||% "Design snapshot")))
          showNotification("Committed to git.", type = "message", duration = 4)
        } else {
          showNotification("JSON saved (no git repo found).",
            type = "warning", duration = 4)
        }
        output$revision_list <- renderUI({ .revision_ui() })
      }, error = function(e) {
        showNotification(paste0("Commit failed: ", e$message), type = "error")
      })
    }, ignoreInit = TRUE)

    # Revision log helper
    .revision_ui <- function() {
      commits <- tryCatch(
        system2("git", c("log", "--oneline", "-8",
          file.path(.rfcad_designs_dir(), paste0(id, "_design.json"))),
          stdout = TRUE, stderr = FALSE),
        error = function(e) character(0)
      )
      if (length(commits) == 0 || all(!nzchar(commits))) {
        return(div(style = "color:#666; font-size:11px;", "No commits yet."))
      }
      tagList(lapply(commits, function(line) {
        parts <- strsplit(line, " ", fixed = TRUE)[[1]]
        sha   <- parts[1]
        msg   <- paste(parts[-1], collapse = " ")
        div(style = "font-size:11px; padding:2px 0; border-bottom:1px solid #222;",
          tags$span(style = "color:#7b9fc7; font-family:monospace;", sha),
          tags$span(style = "color:#c8c8d8; margin-left:6px;", msg)
        )
      }))
    }
    output$revision_list <- renderUI({ .revision_ui() })

    # ── Export trigger ────────────────────────────────────────────────────────
    rv_export <- reactiveValues(pending = NULL)

    observeEvent(input$export_trigger, {
      req(input$export_trigger)
      trig <- input$export_trigger
      fmt  <- trig$fmt
      json <- trig$json
      rv_export$pending <- list(fmt = fmt, json = json)

      if (fmt == "dxf") {
        showNotification("Generating DXF\u2026", id = "rfcad_export_notif",
                         type = "message", duration = NULL)
        # Write temp JSON, run Python script
        tmp_json <- tempfile(fileext = ".json")
        tmp_dxf  <- tempfile(fileext = ".dxf")
        writeLines(json, tmp_json)
        script   <- system.file("scripts/rf_to_dxf.py",
                                package = "",
                                mustWork = FALSE)
        if (!nzchar(script)) {
          # Resolve relative to www
          script <- file.path(getwd(), "..", "www", "scripts", "rf_to_dxf.py")
        }
        ret <- system2("python3",
                       args   = c(shQuote(normalizePath(tmp_json, mustWork = FALSE)),
                                  shQuote(normalizePath(tmp_dxf,  mustWork = FALSE))),
                       stdout = TRUE, stderr = TRUE,
                       env    = character(0),
                       wait   = TRUE)
        removeNotification("rfcad_export_notif")
        if (file.exists(tmp_dxf) && file.size(tmp_dxf) > 0) {
          rv_export$pending <- list(fmt = "dxf", path = tmp_dxf)
          showNotification("DXF ready — click DXF again to download.",
                           type = "message", duration = 4)
          session$sendCustomMessage("rfcad_trigger_download",
            list(url     = paste0("export_dxf_", id),
                 filename = paste0(id, "_design.dxf")))
        } else {
          showNotification(paste("DXF failed:", paste(ret, collapse = " ")),
                           type = "error", duration = 6)
        }

      } else if (fmt == "gerber") {
        # Basic Gerber: write RS-274X GTL from component rectangles
        tmp_json <- tempfile(fileext = ".json")
        writeLines(json, tmp_json)
        design   <- jsonlite::fromJSON(json, simplifyVector = FALSE)
        comps    <- design$components
        gbr_lines <- c(
          "%FSLAX46Y46*%",
          "%MOMM*%",
          "%LPD*%",
          "G04 RF CAD Gerber Export - Top Copper*"
        )
        # Aperture: D10 = rectangle, D11 = circle
        gbr_lines <- c(gbr_lines,
          "%ADD10R,0.001X0.001*%",  # placeholder rect
          "%ADD11C,0.001*%"
        )
        for (comp in comps) {
          ctype  <- comp$type
          params <- comp$params
          if (is.null(params)) next
          W <- as.numeric(params$W %||% 1) * 1e6   # mm -> Gerber units (1e-6 mm)
          L <- as.numeric(params$L %||% 10) * 1e6
          cx <- as.numeric(comp$x %||% 0) * 1e6
          cy <- as.numeric(comp$y %||% 0) * 1e6
          gbr_lines <- c(gbr_lines,
            sprintf("%%ADD10R,%.6fX%.6f*%%", W / 1e6, L / 1e6),
            "D10*",
            sprintf("X%dY%dD03*", as.integer(cx), as.integer(cy))
          )
        }
        gbr_lines <- c(gbr_lines, "M02*")
        tmp_gbr <- tempfile(fileext = ".gbr")
        writeLines(gbr_lines, tmp_gbr)
        rv_export$pending <- list(fmt = "gerber", path = tmp_gbr)
        session$sendCustomMessage("rfcad_trigger_download",
          list(url      = paste0("export_gbr_", id),
               filename  = paste0(id, "_top_copper.gbr")))
        showNotification("Gerber ready.", type = "message", duration = 4)
      }
    }, ignoreInit = TRUE)

    # DXF download handler
    output[[paste0("export_dxf_", id)]] <- downloadHandler(
      filename = function() paste0(id, "_design.dxf"),
      content  = function(file) {
        req(rv_export$pending)
        src <- rv_export$pending$path
        req(file.exists(src))
        file.copy(src, file, overwrite = TRUE)
      },
      contentType = "application/dxf"
    )

    # Gerber download handler
    output[[paste0("export_gbr_", id)]] <- downloadHandler(
      filename = function() paste0(id, "_top_copper.gbr"),
      content  = function(file) {
        req(rv_export$pending)
        src <- rv_export$pending$path
        req(file.exists(src))
        file.copy(src, file, overwrite = TRUE)
      },
      contentType = "application/octet-stream"
    )

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
