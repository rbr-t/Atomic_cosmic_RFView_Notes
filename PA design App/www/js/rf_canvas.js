/*!
 * RF CAD Canvas Engine — Phase 1
 * Konva.js-based 2D layout tool for RF microstrip design.
 *
 * Plugin architecture: can run standalone or embedded in the PA Design App.
 * Each canvas instance is identified by an instanceId so multiple canvases
 * can coexist on the same page.
 *
 * Shiny ↔ JS protocol
 *  JS → Shiny (via Shiny.setInputValue):
 *    <nsPrefix>-rfcad_components       JSON array of all components
 *    <nsPrefix>-rfcad_selected         JSON of selected component (or null)
 *    <nsPrefix>-rfcad_tool             current tool name
 *    <nsPrefix>-rfcad_zoom             current zoom %
 *
 *  Shiny → JS (via custom message handlers — all globally named):
 *    rfcad_init            { instanceId, containerId, nsPrefix }
 *    rfcad_set_tool        { instanceId, tool }
 *    rfcad_update_param    { instanceId, id, param, value }
 *    rfcad_update_name     { instanceId, id, name }
 *    rfcad_update_layer    { instanceId, id, layer }
 *    rfcad_update_rotation { instanceId, id, angle }
 *    rfcad_load_design     { instanceId, json }
 *    rfcad_clear           { instanceId }
 *    rfcad_set_grid        { instanceId, gridSizeMm, snapEnabled, gridVisible }
 *    rfcad_update_substrate{ instanceId, h, er, tand, t }
 *    rfcad_fit_view        { instanceId }
 *    rfcad_zoom_in         { instanceId }
 *    rfcad_zoom_out        { instanceId }
 *    rfcad_delete_selected { instanceId }
 *    rfcad_rotate_selected { instanceId, angle }
 *    rfcad_export_json     { instanceId }
 */

(function (global) {
  'use strict';

  // ── Global canvas registry ─────────────────────────────────────────────
  const canvases = {};

  // ── Visual constants ───────────────────────────────────────────────────
  const BASE_SCALE     = 20;      // pixels per mm at zoom 1×
  const PORT_R_PX      = 4;       // port circle radius (in world-px, not screen-px)
  const SEL_COLOR      = '#f5c518';
  const LABEL_COLOR    = '#e0e0e0';
  const ORIGIN_COLOR   = '#3a4a6a';
  const GRID_MAJOR_CLR = '#2e3a5a';   // visible blue-gray
  const GRID_MINOR_CLR = '#1e2840';   // dimmer sub-grid
  const COMP_COLORS    = {
    metal_top     : '#c8a84b',
    metal_bot     : '#7b9fc7',
    metal_inner_1 : '#8fcf70',
    metal_inner_2 : '#c878c8',
    via           : '#d4d4d4',
    port          : '#ff6b6b',
    default       : '#c8a84b'
  };

  // ── Factory: create one canvas instance ───────────────────────────────
  function createCanvas(containerId, nsPrefix, instanceId) {
    const container = document.getElementById(containerId);
    if (!container) {
      console.warn('[RFCAD] container not found:', containerId);
      return null;
    }

    // ── Per-instance state ─────────────────────────────────────────────
    const state = {
      instanceId   : instanceId || 'default',
      nsPrefix     : nsPrefix   || '',
      tool         : 'select',
      zoom         : 1.0,
      gridSizeMm   : 0.5,
      snapEnabled  : true,
      gridVisible  : true,
      components   : [],
      nextId       : 1,
      selectedId   : null,
      isPanning    : false,
      isDrawing    : false,
      drawStart    : null,
      drawPreview  : null,
      measurePts   : [],   // [{x,y}] ruler tool points (max 2)
      polyPts      : [],   // in-progress vertices for polyline / polygon
      arcPts       : [],   // in-progress [start, mid-pt, end] for arc
      shiftDown    : false,
      symbolMode   : false,
      substrate    : { h: 0.254, er: 4.3, tand: 0.0027, t: 0.035 },
      freqGHz      : 2.4,
      defaults     : { W: 0.5, L: 5.0, gap: 0.2, layer: 'metal_top', strokeW: 0.1 },
      layerVisibility: {},
      layerLocked  : {}
    };

    // ── Konva primitives ───────────────────────────────────────────────
    const w = container.offsetWidth  || 900;
    const h = container.offsetHeight || 600;

    const stage  = new Konva.Stage({ container: containerId, width: w, height: h });
    const layers = {
      grid : new Konva.Layer({ listening: false }),
      comp : new Konva.Layer(),
      ui   : new Konva.Layer()
    };
    stage.add(layers.grid, layers.comp, layers.ui);

    // Center origin
    stage.position({ x: w / 2, y: h / 2 });
    stage.scale({ x: BASE_SCALE, y: BASE_SCALE });

    // ── Utility: coordinate transforms ────────────────────────────────
    function mmToPx(mm)  { return mm * BASE_SCALE; }
    function pxToMm(px)  { return px / BASE_SCALE; }

    function snapMm(mm) {
      if (!state.snapEnabled) return mm;
      return Math.round(mm / state.gridSizeMm) * state.gridSizeMm;
    }

    // Snap direction to nearest 45° multiple when Shift is held
    function snapAngle45(dx, dy) {
      if (!state.shiftDown) return { dx, dy };
      const angle = Math.atan2(dy, dx);
      const snapped = Math.round(angle / (Math.PI / 4)) * (Math.PI / 4);
      const len = Math.sqrt(dx * dx + dy * dy);
      return { dx: len * Math.cos(snapped), dy: len * Math.sin(snapped) };
    }

    function pointerMm() {
      const pos = stage.getPointerPosition();
      if (!pos) return { x: 0, y: 0 };
      const inv = layers.comp.getAbsoluteTransform().copy().invert();
      const lp  = inv.point(pos);
      return { x: pxToMm(lp.x), y: pxToMm(lp.y) };
    }

    function uid() {
      const n = state.nextId++;
      return 'cmp_' + n;
    }

    // ── Shiny communication helpers ────────────────────────────────────
    const NS = state.nsPrefix ? state.nsPrefix + '-' : '';

    function shinySend(key, value) {
      if (typeof Shiny !== 'undefined') {
        Shiny.setInputValue(NS + key, value, { priority: 'event' });
      }
    }

    // ── Session persistence (localStorage) ────────────────────────────
    const SESSION_KEY = 'rfcad_session_' + (instanceId || 'default');

    function sessionSave() {
      try {
        localStorage.setItem(SESSION_KEY, JSON.stringify({
          components : state.components,
          substrate  : state.substrate,
          freqGHz    : state.freqGHz,
          nextId     : state.nextId,
          defaults   : state.defaults,
          stageX     : stage.x(),
          stageY     : stage.y(),
          stageScale : stage.scaleX()
        }));
      } catch(e) { /* storage quota exceeded — silently ignore */ }
    }

    function sessionLoad() {
      try {
        const raw = localStorage.getItem(SESSION_KEY);
        if (!raw) return false;
        const data = JSON.parse(raw);
        state.components = data.components  || [];
        state.nextId     = data.nextId      || 1;
        if (data.substrate) Object.assign(state.substrate, data.substrate);
        if (data.freqGHz)   state.freqGHz = data.freqGHz;
        if (data.defaults)  Object.assign(state.defaults, data.defaults);
        if (data.stageScale) {
          stage.scale({ x: data.stageScale, y: data.stageScale });
          state.zoom = data.stageScale / BASE_SCALE;
        }
        if (data.stageX !== undefined) stage.position({ x: data.stageX, y: data.stageY });
        reRenderAll();
        drawGrid();
        updateStatus();
        // Notify Shiny — non-blocking
        setTimeout(() => syncComponents(), 400);
        return true;
      } catch(e) {
        console.error('[RFCAD] sessionLoad error:', e);
        return false;
      }
    }

    function syncComponents() {
      shinySend('rfcad_components', JSON.stringify(state.components));
      sessionSave();
    }

    function syncSelected(comp) {
      shinySend('rfcad_selected', comp ? JSON.stringify(comp) : null);
    }

    function syncTool() {
      shinySend('rfcad_tool', state.tool);
    }

    function syncZoom() {
      shinySend('rfcad_zoom', Math.round(state.zoom * 100));
    }

    // ── Grid drawing ───────────────────────────────────────────────────
    function drawGrid() {
      const gl = layers.grid;
      gl.destroyChildren();
      if (!state.gridVisible) { gl.batchDraw(); return; }

      const sw = stage.width();
      const sh = stage.height();
      const inv = layers.grid.getAbsoluteTransform().copy().invert();
      const tl  = inv.point({ x: 0,  y: 0  });
      const br  = inv.point({ x: sw, y: sh });

      const gs  = state.gridSizeMm;
      const x0  = Math.floor(pxToMm(tl.x) / gs) * gs;
      const x1  = Math.ceil(pxToMm(br.x)  / gs) * gs;
      const y0  = Math.floor(pxToMm(tl.y) / gs) * gs;
      const y1  = Math.ceil(pxToMm(br.y)  / gs) * gs;

      const curScale    = stage.scaleX();
      const strokeMajor = 1.0 / curScale;
      const strokeMinor = 0.5 / curScale;
      const minorGs     = gs / 5;

      // minor — only when zoomed in enough
      if (curScale > BASE_SCALE * 0.4) {
        for (let x = x0; x <= x1 + 1e-9; x += minorGs) {
          gl.add(new Konva.Line({
            points: [mmToPx(x), mmToPx(y0), mmToPx(x), mmToPx(y1)],
            stroke: GRID_MINOR_CLR, strokeWidth: strokeMinor, listening: false
          }));
        }
        for (let y = y0; y <= y1 + 1e-9; y += minorGs) {
          gl.add(new Konva.Line({
            points: [mmToPx(x0), mmToPx(y), mmToPx(x1), mmToPx(y)],
            stroke: GRID_MINOR_CLR, strokeWidth: strokeMinor, listening: false
          }));
        }
      }

      // major
      for (let x = x0; x <= x1 + 1e-9; x += gs) {
        gl.add(new Konva.Line({
          points: [mmToPx(x), mmToPx(y0), mmToPx(x), mmToPx(y1)],
          stroke: GRID_MAJOR_CLR, strokeWidth: strokeMajor, listening: false
        }));
      }
      for (let y = y0; y <= y1 + 1e-9; y += gs) {
        gl.add(new Konva.Line({
          points: [mmToPx(x0), mmToPx(y), mmToPx(x1), mmToPx(y)],
          stroke: GRID_MAJOR_CLR, strokeWidth: strokeMajor, listening: false
        }));
      }

      // origin cross
      const xl = Math.max(Math.abs(x0), Math.abs(x1)) + gs;
      const yl = Math.max(Math.abs(y0), Math.abs(y1)) + gs;
      gl.add(new Konva.Line({ points: [mmToPx(-xl), 0, mmToPx(xl), 0], stroke: ORIGIN_COLOR, strokeWidth: strokeMajor * 2, listening: false }));
      gl.add(new Konva.Line({ points: [0, mmToPx(-yl), 0, mmToPx(yl)], stroke: ORIGIN_COLOR, strokeWidth: strokeMajor * 2, listening: false }));

      gl.batchDraw();
    }

    // ── Component rendering ────────────────────────────────────────────
    function buildMicrostrip(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W);
      const L  = mmToPx(comp.params.L);
      const sw = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      g.add(new Konva.Rect({
        x: 0, y: -W / 2, width: L, height: W,
        fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)',
        strokeWidth: sw, cornerRadius: mmToPx(0.05)
      }));
      addPortMarker(g, 0, 0);
      addPortMarker(g, L, 0);
    }

    function buildBend90(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W);
      const L  = mmToPx(comp.params.L);
      const sw  = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      const miter = comp.params.miter !== false;
      // Horizontal arm
      g.add(new Konva.Rect({ x: 0, y: -W / 2, width: L - W / 2, height: W, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw }));
      // Vertical arm (going up)
      g.add(new Konva.Rect({ x: L - W, y: -L + W / 2, width: W, height: L - W / 2, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw }));
      // Corner fill
      g.add(new Konva.Rect({ x: L - W, y: -W / 2, width: W / 2, height: W / 2, fill: color, strokeWidth: 0 }));
      // Miter cut (45° line)
      if (miter) {
        g.add(new Konva.Line({
          points: [L - W + W * 0.35, -W / 2, L - W / 2, -W / 2 + W * 0.35],
          stroke: '#1a1a2e', strokeWidth: W * 0.5, closed: false, listening: false
        }));
      }
      addPortMarker(g, 0,     0);
      addPortMarker(g, L - W / 2, -(L - W / 2));
    }

    function buildTee(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W);
      const L  = mmToPx(comp.params.L);
      const sw  = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      // Horizontal through
      g.add(new Konva.Rect({ x: 0, y: -W / 2, width: L, height: W, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw, cornerRadius: mmToPx(0.05) }));
      // Vertical stub (up from center)
      g.add(new Konva.Rect({ x: L / 2 - W / 2, y: -W / 2 - L / 2, width: W, height: L / 2, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw }));
      addPortMarker(g, 0,     0);
      addPortMarker(g, L,     0);
      addPortMarker(g, L / 2, -(W / 2 + L / 2));
    }

    function buildCoupled(g, comp, color, sel) {
      const W   = mmToPx(comp.params.W);
      const L   = mmToPx(comp.params.L);
      const gap = mmToPx(comp.params.gap || state.defaults.gap);
      const sw  = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      const c2  = COMP_COLORS.metal_bot;
      // Top trace
      g.add(new Konva.Rect({ x: 0, y: -(gap / 2 + W), width: L, height: W, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw, cornerRadius: mmToPx(0.05) }));
      // Bottom trace
      g.add(new Konva.Rect({ x: 0, y:  gap / 2,       width: L, height: W, fill: c2,    stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw, cornerRadius: mmToPx(0.05) }));
      // Gap indicator (dashed line)
      g.add(new Konva.Line({
        points: [mmToPx(-0.3), 0, mmToPx(comp.params.L + 0.3), 0],
        stroke: '#555', strokeWidth: 0.5 / stage.scaleX(), dash: [mmToPx(0.3), mmToPx(0.2)], listening: false
      }));
      addPortMarker(g, 0, -(gap / 2 + W / 2));
      addPortMarker(g, L, -(gap / 2 + W / 2));
      addPortMarker(g, 0,  gap / 2 + W / 2);
      addPortMarker(g, L,  gap / 2 + W / 2);
    }

    function buildVia(g, comp, sel) {
      const rDrill = mmToPx((comp.params.drill || 0.2) / 2);
      const rPad   = mmToPx((comp.params.pad   || 0.5) / 2);
      const sw     = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      g.add(new Konva.Circle({ x: 0, y: 0, radius: rPad, fill: COMP_COLORS.metal_top, stroke: sel ? SEL_COLOR : '#888', strokeWidth: sw }));
      g.add(new Konva.Circle({ x: 0, y: 0, radius: rPad * 0.65, fill: COMP_COLORS.via, strokeWidth: 0 }));
      g.add(new Konva.Circle({ x: 0, y: 0, radius: rDrill, fill: '#111', stroke: '#444', strokeWidth: 0.5 / stage.scaleX() }));
    }

    function buildPort(g, comp, sel) {
      const W   = mmToPx(comp.params.W || state.defaults.W);
      const pW  = mmToPx(0.8);
      const sw  = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      // Arrow/triangle pointing left
      g.add(new Konva.Arrow({
        points: [pW, 0, 0, 0],
        pointerLength: pW * 0.5, pointerWidth: W,
        fill: COMP_COLORS.port, stroke: sel ? SEL_COLOR : COMP_COLORS.port.replace('ff', '99'),
        strokeWidth: 0.5 / stage.scaleX()
      }));
      // Trace stub
      g.add(new Konva.Rect({ x: pW, y: -W / 2, width: mmToPx(0.5), height: W, fill: COMP_COLORS.metal_top, strokeWidth: 0 }));
      addPortMarker(g, pW + mmToPx(0.5), 0);
      // Port number
      const pn = comp.params.portNum || '';
      g.add(new Konva.Text({
        x: 0, y: W / 2 + 3 / stage.scaleX(),
        text: 'P' + pn, fontSize: 10 / stage.scaleX(),
        fill: COMP_COLORS.port, listening: false
      }));
    }

    function buildOpenStub(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W);
      const L  = mmToPx(comp.params.L);
      const sw = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      g.add(new Konva.Rect({ x: 0, y: -W / 2, width: L, height: W, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw }));
      // Open end marker
      g.add(new Konva.Line({ points: [L, -W, L, W], stroke: sel ? SEL_COLOR : color, strokeWidth: sw * 2, listening: false }));
      addPortMarker(g, 0, 0);
    }

    function buildShortStub(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W);
      const L  = mmToPx(comp.params.L);
      const sw = sel ? 2 / stage.scaleX() : 0.5 / stage.scaleX();
      g.add(new Konva.Rect({ x: 0, y: -W / 2, width: L, height: W, fill: color, stroke: sel ? SEL_COLOR : 'rgba(0,0,0,0.5)', strokeWidth: sw }));
      // Short/ground end marker (hatch)
      g.add(new Konva.Rect({ x: L, y: -W, width: W * 0.4, height: W * 2, fill: '#666', strokeWidth: 0 }));
      addPortMarker(g, 0, 0);
    }

    function addPortMarker(g, x, y) {
      const r = PORT_R_PX / stage.scaleX();
      g.add(new Konva.Circle({
        x, y, radius: r,
        fill: '#12121e', stroke: COMP_COLORS.port,
        strokeWidth: Math.max(0.8, 1.5 / stage.scaleX()),
        listening: false
      }));
    }

    // ══════════════════════════════════════════════════════════════════
    // SHAPE RENDERERS (Commit 2 — drawn geometry types)
    // ══════════════════════════════════════════════════════════════════

    function buildLine(g, comp, color, sel) {
      const pts = comp.pts || [{ x: 0, y: 0 }, { x: comp.params.L || 5, y: 0 }];
      const sw  = (comp.params.strokeW || state.defaults.strokeW || 0.1);
      const swPx = sel ? Math.max(sw * 1.8, 2 / stage.scaleX()) : Math.max(sw, 0.5 / stage.scaleX());
      g.add(new Konva.Line({
        points: pts.flatMap(p => [mmToPx(p.x - comp.x), mmToPx(p.y - comp.y)]),
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: mmToPx(swPx),
        lineCap: 'round', lineJoin: 'round',
        listening: false
      }));
    }

    function buildPolyline(g, comp, color, sel) {
      const pts = comp.pts || [];
      if (pts.length < 2) return;
      const sw   = comp.params.strokeW || state.defaults.strokeW || 0.1;
      const swPx = sel ? Math.max(sw * 1.8, 2 / stage.scaleX()) : Math.max(sw, 0.5 / stage.scaleX());
      g.add(new Konva.Line({
        points: pts.flatMap(p => [mmToPx(p.x - comp.x), mmToPx(p.y - comp.y)]),
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: mmToPx(swPx),
        closed: comp.closed || false,
        fill: (comp.closed && comp.filled) ? color + '55' : 'transparent',
        lineCap: 'round', lineJoin: 'round',
        listening: false
      }));
      // vertex handles when selected
      if (sel) {
        pts.forEach(p => {
          g.add(new Konva.Circle({
            x: mmToPx(p.x - comp.x), y: mmToPx(p.y - comp.y),
            radius: 3 / stage.scaleX(),
            fill: SEL_COLOR, strokeWidth: 0, listening: false
          }));
        });
      }
    }

    function buildArcShape(g, comp, color, sel) {
      // Store: {cx, cy, radius, startAngle, endAngle} — angles in degrees
      const sw   = comp.params.strokeW || state.defaults.strokeW || 0.1;
      const swPx = sel ? Math.max(sw * 1.8, 2 / stage.scaleX()) : Math.max(sw, 0.5 / stage.scaleX());
      g.add(new Konva.Arc({
        x: mmToPx(comp.cx - comp.x), y: mmToPx(comp.cy - comp.y),
        innerRadius: mmToPx(comp.radius),
        outerRadius: mmToPx(comp.radius),
        angle: comp.arcAngle || 180,
        rotation: comp.startAngle || 0,
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: mmToPx(swPx),
        listening: false
      }));
    }

    function buildRectShape(g, comp, color, sel) {
      const W  = mmToPx(comp.params.W || 1);
      const L  = mmToPx(comp.params.L || 5);
      const sw = sel ? 2 / stage.scaleX() : Math.max(mmToPx(comp.params.strokeW || 0.05), 0.5 / stage.scaleX());
      g.add(new Konva.Rect({
        x: 0, y: -W / 2, width: L, height: W,
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: sw,
        fill: comp.filled ? color + '44' : 'transparent',
        cornerRadius: 0
      }));
    }

    function buildCircleShape(g, comp, color, sel) {
      const r  = mmToPx(comp.params.radius || 1);
      const sw = sel ? 2 / stage.scaleX() : Math.max(mmToPx(comp.params.strokeW || 0.05), 0.5 / stage.scaleX());
      g.add(new Konva.Circle({
        x: 0, y: 0, radius: r,
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: sw,
        fill: comp.filled ? color + '33' : 'transparent'
      }));
    }

    function buildPolygonShape(g, comp, color, sel) {
      // stored as pts[]  (same as polyline), always closed
      buildPolyline(g, { ...comp, closed: true }, color, sel);
    }

    function buildTextAnn(g, comp, sel) {
      const fs  = Math.max(6, (comp.params.fontSize || 0.5) * BASE_SCALE / stage.scaleX());
      g.add(new Konva.Text({
        x: 0, y: 0,
        text: comp.params.text || '',
        fontSize: fs,
        fill: sel ? SEL_COLOR : (comp.params.color || '#e0e0e0'),
        fontFamily: comp.params.fontFamily || 'Roboto Mono, monospace',
        listening: false
      }));
    }

    function buildDimension(g, comp, color, sel) {
      // comp.pts = [{x,y},{x,y}], comp.params.dimType = 'h'|'v'|'align'
      const pts = comp.pts || [];
      if (pts.length < 2) return;
      const p1  = pts[0], p2 = pts[1];
      const sc  = stage.scaleX();
      const sw  = 0.8 / sc;
      const ext = 1.5 / sc;   // extension line overhang in px
      const dimType = comp.params.dimType || 'align';

      let dx = mmToPx(p2.x - p1.x), dy = mmToPx(p2.y - p1.y);
      let dim;

      if (dimType === 'h') {
        dx = mmToPx(p2.x - p1.x); dy = 0;
        dim = Math.abs(p2.x - p1.x);
      } else if (dimType === 'v') {
        dx = 0; dy = mmToPx(p2.y - p1.y);
        dim = Math.abs(p2.y - p1.y);
      } else {
        dim = Math.sqrt((p2.x - p1.x) ** 2 + (p2.y - p1.y) ** 2);
      }

      const ox = mmToPx(p1.x - comp.x), oy = mmToPx(p1.y - comp.y);
      const lineColor = sel ? SEL_COLOR : color;
      const offset = -10 / sc;  // dim line offset above geometry

      // Dimension line
      g.add(new Konva.Line({ points: [ox, oy + offset, ox + dx, oy + dy + offset], stroke: lineColor, strokeWidth: sw, listening: false }));
      // Extension lines
      g.add(new Konva.Line({ points: [ox, oy - ext, ox, oy + offset + ext], stroke: lineColor, strokeWidth: sw, listening: false }));
      g.add(new Konva.Line({ points: [ox + dx, oy + dy - ext, ox + dx, oy + dy + offset + ext], stroke: lineColor, strokeWidth: sw, listening: false }));
      // Arrowheads
      const aLen = 3 / sc;
      const textX = ox + dx / 2, textY = oy + dy / 2 + offset;
      g.add(new Konva.Arrow({ points: [ox + aLen * 2, oy + offset, ox, oy + offset], pointerLength: aLen, pointerWidth: aLen, fill: lineColor, stroke: lineColor, strokeWidth: sw / 2, listening: false }));
      g.add(new Konva.Arrow({ points: [ox + dx - aLen * 2, oy + dy + offset, ox + dx, oy + dy + offset], pointerLength: aLen, pointerWidth: aLen, fill: lineColor, stroke: lineColor, strokeWidth: sw / 2, listening: false }));
      // Label
      const lbl  = dim.toFixed(3) + ' mm';
      const fs   = Math.max(6, 9 / sc);
      g.add(new Konva.Rect({ x: textX - lbl.length * fs * 0.29, y: textY - fs * 1.1, width: lbl.length * fs * 0.58, height: fs * 1.2, fill: 'rgba(0,0,20,0.75)', cornerRadius: 2, listening: false }));
      g.add(new Konva.Text({ x: textX - lbl.length * fs * 0.29, y: textY - fs * 1.1, text: lbl, fontSize: fs, fill: lineColor, listening: false }));
    }

    function buildLeader(g, comp, color, sel) {
      const pts = comp.pts || [];
      if (pts.length < 2) return;
      const sc  = stage.scaleX();
      const ptsPx = pts.flatMap(p => [mmToPx(p.x - comp.x), mmToPx(p.y - comp.y)]);
      g.add(new Konva.Arrow({
        points: ptsPx,
        pointerLength: 4 / sc, pointerWidth: 3 / sc,
        fill: sel ? SEL_COLOR : color,
        stroke: sel ? SEL_COLOR : color,
        strokeWidth: 0.8 / sc,
        listening: false
      }));
      if (comp.params.text) {
        const lp = pts[pts.length - 1];
        const fs = Math.max(6, 9 / sc);
        g.add(new Konva.Text({ x: mmToPx(lp.x - comp.x) + 4 / sc, y: mmToPx(lp.y - comp.y) - fs * 0.6, text: comp.params.text, fontSize: fs, fill: sel ? SEL_COLOR : '#e0e0e0', listening: false }));
      }
    }

    // ══════════════════════════════════════════════════════════════════
    // SCHEMATIC SYMBOL BUILDERS  (symbol mode)
    // ══════════════════════════════════════════════════════════════════

    function buildSymbolMS(g, comp, color, sel) {
      // Standard schematic: rectangle box with Z₀ / θ annotation
      const W  = mmToPx(0.8);   // fixed schematic width
      const L  = mmToPx(2.5);   // fixed schematic length
      const sc = stage.scaleX();
      const sw = sel ? 2 / sc : 1 / sc;
      g.add(new Konva.Rect({ x: 0, y: -W / 2, width: L, height: W, stroke: sel ? SEL_COLOR : color, strokeWidth: sw, fill: 'rgba(0,0,0,0.3)', cornerRadius: 2 }));
      addPortMarker(g, 0, 0);
      addPortMarker(g, L, 0);
      // Z₀/θ label inside box
      const sub  = state.substrate;
      const z0   = comp._z0  || '?';
      const theta = comp._theta || '?';
      g.add(new Konva.Text({ x: 3 / sc, y: -W / 2 + 1 / sc, text: `Z₀=${z0}Ω\nθ=${theta}°`, fontSize: Math.max(4, 6 / sc), fill: color, listening: false }));
    }

    function buildSymbolVia(g, comp, sel) {
      const sc = stage.scaleX();
      const r1 = 4 / sc, r2 = 2 / sc;
      g.add(new Konva.Circle({ x: 0, y: 0, radius: r1, stroke: sel ? SEL_COLOR : '#d4d4d4', strokeWidth: 1 / sc, fill:'transparent' }));
      g.add(new Konva.Line({ points: [-r1, 0, r1, 0], stroke: '#888', strokeWidth: 1 / sc, listening: false }));
      g.add(new Konva.Line({ points: [0, -r1, 0, r1], stroke: '#888', strokeWidth: 1 / sc, listening: false }));
      // gnd symbol
      const y0 = r1;
      const gndW = r1 * 1.8;
      [0, 2, 4].forEach((d, i) => {
        const w = gndW * (1 - i * 0.2);
        g.add(new Konva.Line({ points: [-w / 2, (y0 + d / sc), w / 2, (y0 + d / sc)], stroke: '#aaa', strokeWidth: Math.max(0.5, (1.5 - i * 0.4) / sc), listening: false }));
      });
    }

    function buildSymbolPort(g, comp, sel) {
      const sc  = stage.scaleX();
      const pn  = comp.params.portNum || 1;
      const r   = 5 / sc;
      g.add(new Konva.Circle({ x: 0, y: 0, radius: r, stroke: sel ? SEL_COLOR : COMP_COLORS.port, strokeWidth: 1 / sc, fill: 'transparent' }));
      g.add(new Konva.Text({ x: -r * 0.6, y: -r * 0.6, text: String(pn), fontSize: Math.max(5, 8 / sc), fill: COMP_COLORS.port, listening: false }));
    }

    function buildSymbolCoupled(g, comp, color, sel) {
      // Two parallel lines with coupling arrows
      const L  = mmToPx(2.5);
      const sc = stage.scaleX();
      const sw = sel ? 2 / sc : 1 / sc;
      const y  = 3 / sc;
      g.add(new Konva.Line({ points: [0, -y, L, -y], stroke: sel ? SEL_COLOR : color, strokeWidth: sw, listening: false }));
      g.add(new Konva.Line({ points: [0, y, L, y], stroke: sel ? SEL_COLOR : COMP_COLORS.metal_bot, strokeWidth: sw, listening: false }));
      // coupling arrows
      const mx = L / 2;
      g.add(new Konva.Arrow({ points: [mx, -y * 0.3, mx, y * 0.3], pointerLength: 2 / sc, pointerWidth: 2 / sc, stroke: '#aaa', fill: '#aaa', strokeWidth: 0.5 / sc, listening: false }));
      addPortMarker(g, 0, -y); addPortMarker(g, L, -y);
      addPortMarker(g, 0,  y); addPortMarker(g, L,  y);
    }

    function buildSymbolGeneric(g, comp, color, sel) {
      // Fallback: simple labeled square
      const s  = mmToPx(1);
      const sc = stage.scaleX();
      const sw = sel ? 2 / sc : 1 / sc;
      g.add(new Konva.Rect({ x: -s / 2, y: -s / 2, width: s, height: s, stroke: sel ? SEL_COLOR : color, strokeWidth: sw, fill: 'rgba(0,0,0,0.2)' }));
      const abbrMap = { bend90:'B', tee:'T', open_stub:'OS', short_stub:'SS' };
      g.add(new Konva.Text({ x: -s / 2 + 1 / sc, y: -s / 4, text: abbrMap[comp.type] || comp.type.slice(0, 2).toUpperCase(), fontSize: Math.max(5, 8 / sc), fill: color, listening: false }));
    }

    // ══════════════════════════════════════════════════════════════════════
    // renderComponent  — layout mode + symbol mode + Commit-2 shape types
    // ══════════════════════════════════════════════════════════════════════
    function renderComponent(comp) {
      const isSel    = comp.id === state.selectedId;
      const color    = COMP_COLORS[comp.layer] || COMP_COLORS.default;
      const curScale = stage.scaleX();

      const group = new Konva.Group({
        id       : comp.id,
        x        : mmToPx(comp.x),
        y        : mmToPx(comp.y),
        rotation : comp.rotation || 0,
        scaleX   : comp.scaleX   || 1,
        scaleY   : comp.scaleY   || 1,
        draggable: true
      });

      // ── Symbol mode vs Layout mode dispatch ──────────────────────────
      if (state.symbolMode) {
        switch (comp.type) {
          case 'ms': case 'microstrip': buildSymbolMS(group, comp, color, isSel); break;
          case 'via':                   buildSymbolVia(group, comp, isSel);        break;
          case 'port':                  buildSymbolPort(group, comp, isSel);       break;
          case 'coupled':               buildSymbolCoupled(group, comp, color, isSel); break;
          default:                      buildSymbolGeneric(group, comp, color, isSel); break;
        }
      } else {
        switch (comp.type) {
          case 'ms':
          case 'microstrip'   : buildMicrostrip(group, comp, color, isSel); break;
          case 'bend90'       : buildBend90(group, comp, color, isSel); break;
          case 'tee'          : buildTee(group, comp, color, isSel); break;
          case 'coupled'      : buildCoupled(group, comp, color, isSel); break;
          case 'via'          : buildVia(group, comp, isSel); break;
          case 'port'         : buildPort(group, comp, isSel); break;
          case 'open_stub'    : buildOpenStub(group, comp, color, isSel); break;
          case 'short_stub'   : buildShortStub(group, comp, color, isSel); break;
          // ── Commit 2 drawn shapes ─────────────────────────────────
          case 'line'         : buildLine(group, comp, color, isSel); break;
          case 'polyline'     : buildPolyline(group, comp, color, isSel); break;
          case 'arc_shape'    : buildArcShape(group, comp, color, isSel); break;
          case 'rect_shape'   : buildRectShape(group, comp, color, isSel); break;
          case 'circle_shape' : buildCircleShape(group, comp, color, isSel); break;
          case 'polygon_shape': buildPolygonShape(group, comp, color, isSel); break;
          case 'text_ann'     : buildTextAnn(group, comp, isSel); break;
          case 'dim_h'        :
          case 'dim_v'        :
          case 'dim_align'    : buildDimension(group, comp, color, isSel); break;
          case 'leader'       : buildLeader(group, comp, color, isSel); break;
          default             : buildMicrostrip(group, comp, color, isSel);
        }
      }

      // Component name label
      const hideLabel = ['text_ann','dim_h','dim_v','dim_align','leader'].includes(comp.type);
      if (comp.name && !hideLabel) {
        const fs = Math.max(7, 11 / curScale);
        group.add(new Konva.Text({
          x: 2, y: -(fs + 3) / curScale,
          text: comp.name, fontSize: fs, fill: LABEL_COLOR, listening: false
        }));
      }

      // Selection outline ring
      if (isSel) {
        const bb  = group.getClientRect({ relativeTo: layers.comp });
        const pad = 4 / curScale;
        layers.ui.destroyChildren();
        layers.ui.add(new Konva.Rect({
          x: bb.x - pad, y: bb.y - pad,
          width:  (bb.width  / curScale) + pad * 2,
          height: (bb.height / curScale) + pad * 2,
          strokeWidth: 2 / curScale, stroke: SEL_COLOR,
          dash: [4 / curScale, 4 / curScale],
          fill: 'transparent', listening: false,
          transformsEnabled: 'position'
        }));
        layers.ui.batchDraw();
      }

      // Drag events
      const isPtsBased = ['line','polyline','arc_shape','polygon_shape',
                          'dim_h','dim_v','dim_align','leader'].includes(comp.type);
      group.on('click tap', () => selectComponent(comp.id));
      group.on('dragstart', () => selectComponent(comp.id));
      group.on('dragmove',  () => updateStatus());
      group.on('dragend', () => {
        const sx = snapMm(pxToMm(group.x()));
        const sy = snapMm(pxToMm(group.y()));
        group.x(mmToPx(sx)); group.y(mmToPx(sy));
        const c = state.components.find(cc => cc.id === comp.id);
        if (c) {
          const dx = sx - c.x, dy = sy - c.y;
          c.x = sx; c.y = sy;
          if (c.pts && isPtsBased) {
            c.pts = c.pts.map(p => ({ x: p.x + dx, y: p.y + dy }));
          }
        }
        syncComponents();
        layers.comp.batchDraw();
      });

      layers.comp.add(group);
    }

    function reRenderAll() {
      layers.comp.destroyChildren();
      layers.ui.destroyChildren();
      state.components.forEach(c => {
        // Skip components on hidden layers
        const vis = state.layerVisibility;
        if (vis && c.layer && vis[c.layer] === false) return;
        renderComponent(c);
      });
      layers.comp.batchDraw();
      drawResizeHandles();   // add L/W handles for selected component
      layers.ui.batchDraw();
    }

    // ── Resize handles for selected component ─────────────────────────
    function drawResizeHandles() {
      if (!state.selectedId) return;
      const comp = state.components.find(c => c.id === state.selectedId);
      if (!comp) return;

      const hasLW = ['microstrip','ms','bend90','tee','coupled',
                     'open_stub','short_stub','rect_shape'].includes(comp.type);
      const hasR  = ['circle_shape','via'].includes(comp.type);
      if (!hasLW && !hasR) return;

      const group = layers.comp.findOne('#' + comp.id);
      if (!group) return;

      const sc = stage.scaleX();
      const hr = 6 / sc;

      function makeHandle(x, y, fill, cursor, onDragMove, onDragEnd) {
        const absPos = group.getAbsoluteTransform().point({ x, y });
        const h = new Konva.Circle({
          x: absPos.x, y: absPos.y, radius: hr,
          fill: fill, stroke: '#111', strokeWidth: 1 / sc,
          draggable: true, hitStrokeWidth: 10 / sc, listening: true
        });
        h.on('mouseenter', () => { stage.container().style.cursor = cursor; });
        h.on('mouseleave', () => {
          stage.container().style.cursor = state.tool === 'select' ? 'default' : 'crosshair';
        });
        h.on('dragmove',  onDragMove);
        h.on('dragend',   onDragEnd);
        layers.ui.add(h);
        return h;
      }

      const finishResize = () => { reRenderAll(); syncComponents(); };

      if (hasLW) {
        const L = mmToPx(comp.params.L || 5);
        const W = mmToPx(comp.params.W || 0.5);

        // Yellow: right-end handle → changes L
        makeHandle(L, 0, SEL_COLOR, 'ew-resize', function() {
          const c = state.components.find(cc => cc.id === state.selectedId);
          if (!c) return;
          const inv   = group.getAbsoluteTransform().copy().invert();
          const local = inv.point({ x: this.x(), y: this.y() });
          c.params.L  = Math.max(0.01, snapMm(pxToMm(local.x)));
          // Refresh just the component shape without destroying handles yet
          const existing = layers.comp.findOne('#' + c.id);
          if (existing) existing.destroy();
          renderComponent(c);
          layers.comp.batchDraw();
          // Re-snap handle to actual new endpoint
          const tf    = layers.comp.findOne('#' + c.id);
          if (tf) { const p = tf.getAbsoluteTransform().point({ x: mmToPx(c.params.L), y: 0 }); this.x(p.x); this.y(p.y); }
          layers.ui.batchDraw();
        }, finishResize);

        // Green: bottom-center handle → changes W
        makeHandle(L / 2, W / 2, '#4caf50', 'ns-resize', function() {
          const c = state.components.find(cc => cc.id === state.selectedId);
          if (!c) return;
          const inv   = group.getAbsoluteTransform().copy().invert();
          const local = inv.point({ x: this.x(), y: this.y() });
          c.params.W  = Math.max(0.001, snapMm(Math.abs(pxToMm(local.y)) * 2));
          const existing = layers.comp.findOne('#' + c.id);
          if (existing) existing.destroy();
          renderComponent(c);
          layers.comp.batchDraw();
          layers.ui.batchDraw();
        }, finishResize);
      }

      if (hasR) {
        const r = mmToPx(comp.params.radius || (comp.params.pad || 0.5) / 2);
        // Cyan: right-edge handle → changes radius
        makeHandle(r, 0, '#00bcd4', 'ew-resize', function() {
          const c = state.components.find(cc => cc.id === state.selectedId);
          if (!c) return;
          const inv   = group.getAbsoluteTransform().copy().invert();
          const local = inv.point({ x: this.x(), y: this.y() });
          const newR  = Math.max(0.01, snapMm(pxToMm(Math.hypot(local.x, local.y))));
          if (c.params.radius !== undefined) c.params.radius = newR;
          if (c.params.pad    !== undefined) c.params.pad    = snapMm(newR * 2);
          const existing = layers.comp.findOne('#' + c.id);
          if (existing) existing.destroy();
          renderComponent(c);
          layers.comp.batchDraw();
          layers.ui.batchDraw();
        }, finishResize);
      }
    }

    // ── Component CRUD ─────────────────────────────────────────────────
    function defaultParams(type) {
      const d = state.defaults;
      switch (type) {
        case 'microstrip'    : return { W: d.W,  L: d.L };
        case 'bend90'        : return { W: d.W,  L: d.L, miter: true };
        case 'tee'           : return { W: d.W,  L: d.L };
        case 'coupled'       : return { W: d.W,  L: d.L, gap: d.gap };
        case 'via'           : return { drill: 0.2, pad: 0.5 };
        case 'port'          : return { W: d.W,  portNum: countByType('port') + 1 };
        case 'open_stub'     : return { W: d.W,  L: d.L / 2 };
        case 'short_stub'    : return { W: d.W,  L: d.L / 2 };
        // Commit 2 shapes
        case 'line'          : return { strokeW: 0.1 };
        case 'polyline'      : return { strokeW: 0.1 };
        case 'arc_shape'     : return { strokeW: 0.1 };
        case 'rect_shape'    : return { W: d.W, L: d.L, strokeW: 0.05, filled: false };
        case 'circle_shape'  : return { radius: 2.0, strokeW: 0.05, filled: false };
        case 'polygon_shape' : return { strokeW: 0.1, filled: false };
        case 'text_ann'      : return { text: 'Label', fontSize: 0.5, color: '#e0e0e0' };
        case 'dim_h'         : return { dimType: 'h' };
        case 'dim_v'         : return { dimType: 'v' };
        case 'dim_align'     : return { dimType: 'align' };
        case 'leader'        : return { text: '' };
        default              : return { W: d.W,  L: d.L };
      }
    }

    function countByType(type) {
      return state.components.filter(c => c.type === type).length;
    }

    function addComponent(type, wx, wy) {
      // Normalise palette alias types
      if (type === 'ms') type = 'microstrip';
      const sx = snapMm(wx);
      const sy = snapMm(wy);
      const abbr = {
        microstrip:'MS', bend90:'B90', tee:'TEE', coupled:'CPL',
        via:'VIA', port:'P', open_stub:'OS', short_stub:'SS',
        line:'LN', polyline:'PL', arc_shape:'ARC', rect_shape:'RCT',
        circle_shape:'CIR', polygon_shape:'PLY', text_ann:'TXT',
        dim_h:'DH', dim_v:'DV', dim_align:'DA', leader:'LD'
      };
      const prefix = abbr[type] || type.toUpperCase().slice(0, 3);
      const comp = {
        id       : uid(),
        type     : type,
        name     : prefix + (countByType(type) + 1),
        x        : sx,
        y        : sy,
        rotation : 0,
        layer    : state.defaults.layer,
        params   : defaultParams(type)
      };
      state.components.push(comp);
      reRenderAll();
      selectComponent(comp.id);
      syncComponents();
      return comp;
    }

    // Add a fully assembled shape component (used by drawing tools)
    function addShapeComponent(type, fields) {
      const abbr = {
        line:'LN', polyline:'PL', arc_shape:'ARC', rect_shape:'RCT',
        circle_shape:'CIR', polygon_shape:'PLY', text_ann:'TXT',
        dim_h:'DH', dim_v:'DV', dim_align:'DA', leader:'LD'
      };
      const prefix = abbr[type] || type.slice(0,3).toUpperCase();
      const comp = Object.assign({
        id       : uid(),
        type     : type,
        name     : prefix + (countByType(type) + 1),
        rotation : 0,
        layer    : state.defaults.layer,
        params   : defaultParams(type)
      }, fields);
      state.components.push(comp);
      reRenderAll();
      selectComponent(comp.id);
      syncComponents();
      return comp;
    }

    function selectComponent(id) {
      state.selectedId = id;
      reRenderAll();
      const comp = state.components.find(c => c.id === id) || null;
      syncSelected(comp);
      updateStatus();
      if (typeof rfCalc !== 'undefined') {
        rfCalc.updateDisplay('rfcad_rf_params_' + state.instanceId, comp, state.substrate, state.freqGHz);
      }
    }

    function deselectAll() {
      state.selectedId = null;
      reRenderAll();
      syncSelected(null);
      if (typeof rfCalc !== 'undefined') {
        rfCalc.updateDisplay('rfcad_rf_params_' + state.instanceId, null, null, null);
      }
    }

    function deleteSelected() {
      if (!state.selectedId) return;
      state.components = state.components.filter(c => c.id !== state.selectedId);
      state.selectedId = null;
      reRenderAll();
      syncComponents();
    }

    function updateParam(id, paramKey, value) {
      const comp = state.components.find(c => c.id === id);
      if (!comp) return;
      if (paramKey.startsWith('params.')) {
        comp.params[paramKey.slice(7)] = isNaN(+value) ? value : +value;
      } else if (paramKey === 'rotation') {
        comp.rotation = +value;
      } else if (paramKey === 'name') {
        comp.name = value;
      } else if (paramKey === 'layer') {
        comp.layer = value;
      } else {
        comp[paramKey] = isNaN(+value) ? value : +value;
      }
      reRenderAll();
      syncComponents();
      const updated = state.components.find(c => c.id === id);
      if (updated) syncSelected(updated);
    }

    // ── Tool management ────────────────────────────────────────────────
    function setTool(toolName) {
      // Cancel in-progress multi-point operations
      state.isDrawing = false;
      state.drawStart = null;
      state.polyPts   = [];
      state.arcPts    = [];
      clearDrawPreview();
      state.tool = toolName;
      if (toolName !== 'ruler') { state.measurePts = []; drawMeasureOverlay(); }
      stage.container().style.cursor = toolName === 'select' ? 'default' : 'crosshair';
      syncTool();
      document.querySelectorAll('.rfcad-tool-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.tool === toolName);
      });
    }

    // ── Draw preview ───────────────────────────────────────────────────
    function clearDrawPreview() {
      if (state.drawPreview) {
        state.drawPreview.destroy();
        state.drawPreview = null;
        layers.ui.batchDraw();
      }
    }

    // ── Measurement overlay ────────────────────────────────────────────
    function drawMeasureOverlay() {
      // Remove existing measure nodes
      layers.ui.getChildren(n => n.name() === 'measure').forEach(n => n.destroy());
      const pts = state.measurePts;
      const sc  = stage.scaleX();
      if (pts.length === 0) { layers.ui.batchDraw(); return; }

      // Draw start point
      layers.ui.add(new Konva.Circle({
        name: 'measure', x: mmToPx(pts[0].x), y: mmToPx(pts[0].y),
        radius: 5 / sc, fill: '#00e5ff', stroke: '#fff',
        strokeWidth: 1 / sc, listening: false
      }));

      if (pts.length < 2) { layers.ui.batchDraw(); return; }

      const p1 = pts[0], p2 = pts[1];
      const dx   = p2.x - p1.x, dy = p2.y - p1.y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const ang  = (Math.atan2(dy, dx) * 180 / Math.PI).toFixed(1);

      // Measurement line
      layers.ui.add(new Konva.Line({
        name: 'measure',
        points: [mmToPx(p1.x), mmToPx(p1.y), mmToPx(p2.x), mmToPx(p2.y)],
        stroke: '#00e5ff', strokeWidth: 1.5 / sc,
        dash: [5 / sc, 3 / sc], listening: false
      }));

      // End point
      layers.ui.add(new Konva.Circle({
        name: 'measure', x: mmToPx(p2.x), y: mmToPx(p2.y),
        radius: 5 / sc, fill: '#00e5ff', stroke: '#fff',
        strokeWidth: 1 / sc, listening: false
      }));

      // Tick marks at ends
      const perp = { x: -dy / dist, y: dx / dist };
      const tk   = 4 / sc;
      [p1, p2].forEach(p => {
        layers.ui.add(new Konva.Line({
          name: 'measure',
          points: [
            mmToPx(p.x + perp.x * tk), mmToPx(p.y + perp.y * tk),
            mmToPx(p.x - perp.x * tk), mmToPx(p.y - perp.y * tk)
          ],
          stroke: '#00e5ff', strokeWidth: 1 / sc, listening: false
        }));
      });

      // Distance + angle label
      const mx  = (p1.x + p2.x) / 2;
      const my  = (p1.y + p2.y) / 2;
      const fs  = Math.max(8, 11 / sc);
      const lbl = dist.toFixed(3) + ' mm  \u2220' + ang + '\u00b0';
      layers.ui.add(new Konva.Rect({
        name: 'measure',
        x: mmToPx(mx) - (lbl.length * fs * 0.31),
        y: mmToPx(my) - fs * 1.8,
        width: lbl.length * fs * 0.62, height: fs * 1.5,
        fill: 'rgba(0,0,30,0.78)', cornerRadius: 3, listening: false
      }));
      layers.ui.add(new Konva.Text({
        name: 'measure',
        x: mmToPx(mx) - (lbl.length * fs * 0.31),
        y: mmToPx(my) - fs * 1.75,
        width: lbl.length * fs * 0.62,
        text: lbl, fontSize: fs, fill: '#00e5ff',
        align: 'center', listening: false
      }));

      layers.ui.batchDraw();
    }

    function updateDrawPreview() {
      clearDrawPreview();
      const pos = pointerMm();
      const sc  = stage.scaleX();
      const sw  = 1 / sc;
      const tool = state.tool;

      // ── Multi-point in-progress preview (polyline / polygon) ──────────
      if ((tool === 'polyline' || tool === 'polygon') && state.polyPts.length > 0) {
        const snapped = snapAngle45(pos.x - state.polyPts[state.polyPts.length - 1].x,
                                    pos.y - state.polyPts[state.polyPts.length - 1].y);
        const ep = { x: state.polyPts[state.polyPts.length - 1].x + snapped.dx,
                     y: state.polyPts[state.polyPts.length - 1].y + snapped.dy };
        const allPts = state.polyPts.concat([ep]);
        const flatPts = [];
        allPts.forEach(p => { flatPts.push(mmToPx(p.x), mmToPx(p.y)); });
        state.drawPreview = new Konva.Group({ listening: false });
        state.drawPreview.add(new Konva.Line({
          points: flatPts, stroke: SEL_COLOR, strokeWidth: sw,
          lineCap: 'round', lineJoin: 'round',
          dash: [6 / sc, 3 / sc]
        }));
        // Vertex dots for already-placed points
        state.polyPts.forEach(p => {
          state.drawPreview.add(new Konva.Circle({
            x: mmToPx(p.x), y: mmToPx(p.y),
            radius: 3 / sc, fill: SEL_COLOR
          }));
        });
        layers.ui.add(state.drawPreview);
        layers.ui.batchDraw();
        return;
      }

      // ── Arc 3-point preview ───────────────────────────────────────────
      if (tool === 'arc' && state.arcPts.length > 0) {
        const pts = [...state.arcPts, { x: snapMm(pos.x), y: snapMm(pos.y) }];
        state.drawPreview = new Konva.Group({ listening: false });
        pts.forEach((p, i) => {
          state.drawPreview.add(new Konva.Circle({
            x: mmToPx(p.x), y: mmToPx(p.y),
            radius: 3 / sc, fill: i === 0 ? '#4caf50' : SEL_COLOR
          }));
        });
        if (pts.length >= 2) {
          const fp = [];
          pts.forEach(p => { fp.push(mmToPx(p.x), mmToPx(p.y)); });
          state.drawPreview.add(new Konva.Line({
            points: fp, stroke: SEL_COLOR + '88', strokeWidth: sw, listening: false
          }));
        }
        layers.ui.add(state.drawPreview);
        layers.ui.batchDraw();
        return;
      }

      // ── Two-point rubber-band preview ─────────────────────────────────
      if (!state.drawStart) return;
      const sx = state.drawStart.x, sy = state.drawStart.y;
      const { dx, dy } = snapAngle45(pos.x - sx, pos.y - sy);
      const ex = sx + dx, ey = sy + dy;

      state.drawPreview = new Konva.Group({ listening: false });

      if (tool === 'microstrip' || tool === 'ms') {
        const L   = Math.sqrt(dx * dx + dy * dy);
        if (L < 0.01) return;
        const W   = mmToPx(state.defaults.W);
        const rot = Math.atan2(dy, dx) * 180 / Math.PI;
        const g   = new Konva.Group({ x: mmToPx(sx), y: mmToPx(sy), rotation: rot });
        g.add(new Konva.Rect({
          x: 0, y: -W / 2, width: mmToPx(snapMm(L)), height: W,
          fill: COMP_COLORS.metal_top + 'aa', stroke: SEL_COLOR, strokeWidth: sw
        }));
        g.add(new Konva.Text({
          x: mmToPx(L / 2), y: -(W / 2 + 12 / sc),
          text: snapMm(L).toFixed(3) + ' mm',
          fontSize: 10 / sc, fill: SEL_COLOR, align: 'center'
        }));
        state.drawPreview.add(g);

      } else if (tool === 'line') {
        state.drawPreview.add(new Konva.Line({
          points: [mmToPx(sx), mmToPx(sy), mmToPx(ex), mmToPx(ey)],
          stroke: SEL_COLOR, strokeWidth: sw, lineCap: 'round',
          dash: [6 / sc, 3 / sc]
        }));
        const L = Math.sqrt(dx * dx + dy * dy);
        state.drawPreview.add(new Konva.Text({
          x: mmToPx((sx + ex) / 2), y: mmToPx((sy + ey) / 2) - 12 / sc,
          text: snapMm(L).toFixed(3) + ' mm', fontSize: 9 / sc, fill: SEL_COLOR
        }));

      } else if (tool === 'rect') {
        const x0 = Math.min(sx, ex), y0 = Math.min(sy, ey);
        const rw = Math.abs(dx), rh = Math.abs(dy);
        state.drawPreview.add(new Konva.Rect({
          x: mmToPx(x0), y: mmToPx(y0), width: mmToPx(rw), height: mmToPx(rh),
          stroke: SEL_COLOR, strokeWidth: sw, dash: [6 / sc, 3 / sc]
        }));
        state.drawPreview.add(new Konva.Text({
          x: mmToPx(x0), y: mmToPx(y0) - 14 / sc,
          text: snapMm(rw).toFixed(3) + ' × ' + snapMm(rh).toFixed(3) + ' mm',
          fontSize: 9 / sc, fill: SEL_COLOR
        }));

      } else if (tool === 'circle') {
        const r = Math.sqrt(dx * dx + dy * dy);
        state.drawPreview.add(new Konva.Circle({
          x: mmToPx(sx), y: mmToPx(sy), radius: mmToPx(r),
          stroke: SEL_COLOR, strokeWidth: sw, dash: [6 / sc, 3 / sc]
        }));
        state.drawPreview.add(new Konva.Text({
          x: mmToPx(sx) + mmToPx(r) + 4 / sc, y: mmToPx(sy) - 7 / sc,
          text: 'r=' + snapMm(r).toFixed(3) + ' mm', fontSize: 9 / sc, fill: SEL_COLOR
        }));
        // Center dot
        state.drawPreview.add(new Konva.Circle({
          x: mmToPx(sx), y: mmToPx(sy), radius: 3 / sc, fill: SEL_COLOR
        }));

      } else if (tool === 'dim_h' || tool === 'dim_v' || tool === 'dim_align') {
        state.drawPreview.add(new Konva.Line({
          points: [mmToPx(sx), mmToPx(sy), mmToPx(ex), mmToPx(ey)],
          stroke: '#00e5ff', strokeWidth: sw, dash: [4 / sc, 2 / sc]
        }));
        const L = Math.sqrt(dx * dx + dy * dy);
        state.drawPreview.add(new Konva.Text({
          x: mmToPx((sx + ex) / 2), y: mmToPx((sy + ey) / 2) - 12 / sc,
          text: snapMm(L).toFixed(3) + ' mm', fontSize: 9 / sc, fill: '#00e5ff'
        }));
      }

      layers.ui.add(state.drawPreview);
      layers.ui.batchDraw();
    }

    // ── Status bar update ──────────────────────────────────────────────
    function updateStatus() {
      const statusEl = document.getElementById('rfcad_status_' + state.instanceId);
      if (!statusEl) return;
      let xMm = 0, yMm = 0;
      const pos = stage.getPointerPosition();
      if (pos) {
        const inv = layers.comp.getAbsoluteTransform().copy().invert();
        const lp  = inv.point(pos);
        xMm = pxToMm(lp.x).toFixed(3);
        yMm = pxToMm(lp.y).toFixed(3);
      }
      const selComp = state.components.find(c => c.id === state.selectedId);
      const selInfo = selComp ? `  |  Selected: ${selComp.name} (${selComp.type})` : '';
      statusEl.textContent =
        `(${xMm}, ${yMm}) mm  |  Grid: ${state.gridSizeMm} mm  |  ` +
        `Zoom: ${Math.round(state.zoom * 100)}%  |  ${state.components.length} component(s)${selInfo}`;
    }

    function fitToContent() {
      if (state.components.length === 0) {
        stage.scale({ x: BASE_SCALE, y: BASE_SCALE });
        stage.position({ x: stage.width() / 2, y: stage.height() / 2 });
      } else {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        state.components.forEach(c => {
          const L = c.params.L || 1;
          const W = c.params.W || 1;
          x0 = Math.min(x0, c.x - W / 2);
          y0 = Math.min(y0, c.y - W / 2);
          x1 = Math.max(x1, c.x + L);
          y1 = Math.max(y1, c.y + W / 2);
        });
        const margin = 3;
        x0 -= margin; y0 -= margin; x1 += margin; y1 += margin;
        const worldW = x1 - x0;
        const worldH = y1 - y0;
        const sx = stage.width()  / (worldW * BASE_SCALE);
        const sy = stage.height() / (worldH * BASE_SCALE);
        const sc = Math.min(sx, sy) * BASE_SCALE;
        stage.scale({ x: sc, y: sc });
        stage.position({
          x: stage.width()  / 2 - mmToPx((x0 + x1) / 2) * sc / BASE_SCALE,
          y: stage.height() / 2 - mmToPx((y0 + y1) / 2) * sc / BASE_SCALE
        });
        state.zoom = sc / BASE_SCALE;
      }
      drawGrid();
      reRenderAll();
      updateStatus();
      syncZoom();
    }

    // ── Event bindings ─────────────────────────────────────────────────
    function bindEvents() {
      // Zoom: mouse wheel
      stage.on('wheel', (e) => {
        e.evt.preventDefault();
        const scaleBy  = 1.15;
        const oldScale = stage.scaleX();
        const ptr      = stage.getPointerPosition();
        const mouseAt  = {
          x: (ptr.x - stage.x()) / oldScale,
          y: (ptr.y - stage.y()) / oldScale
        };
        const newScale = e.evt.deltaY < 0
          ? Math.min(oldScale * scaleBy, BASE_SCALE * 30)
          : Math.max(oldScale / scaleBy, BASE_SCALE * 0.05);
        stage.scale({ x: newScale, y: newScale });
        stage.position({
          x: ptr.x - mouseAt.x * newScale,
          y: ptr.y - mouseAt.y * newScale
        });
        state.zoom = newScale / BASE_SCALE;
        drawGrid();
        reRenderAll();
        updateStatus();
        syncZoom();
      });

      // Keyboard shortcuts
      let spaceDown = false;
      document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;
        if (e.code === 'Space') { spaceDown = true; stage.container().style.cursor = 'grab'; }
        if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') { state.shiftDown = true; }

        // Backspace: undo last vertex in polyline/polygon
        if (e.code === 'Backspace') {
          if (state.polyPts.length > 0) {
            e.preventDefault();
            state.polyPts.pop();
            if (state.polyPts.length === 0) {
              state.isDrawing = false;
              clearDrawPreview();
            } else {
              updateDrawPreview();
            }
            return;
          }
          if (state.arcPts.length > 0) {
            e.preventDefault();
            state.arcPts.pop();
            updateDrawPreview();
            return;
          }
          // Otherwise delete selected component
          deleteSelected();
        }
        if (e.code === 'Delete') deleteSelected();
        if (e.code === 'Escape') {
          // Cancel in-progress drawing first; if nothing in progress, deselect
          if (state.isDrawing || state.polyPts.length > 0 || state.arcPts.length > 0) {
            state.isDrawing = false; state.drawStart = null;
            state.polyPts = []; state.arcPts = [];
            clearDrawPreview();
          } else {
            deselectAll();
            setTool('select');
          }
        }
        if (e.code === 'KeyR' && state.selectedId) {
          const comp = state.components.find(c => c.id === state.selectedId);
          if (comp) { comp.rotation = (comp.rotation + 45) % 360; reRenderAll(); syncComponents(); }
        }
      });
      document.addEventListener('keyup', (e) => {
        if (e.code === 'Space') {
          spaceDown = false;
          stage.container().style.cursor = state.tool === 'select' ? 'default' : 'crosshair';
        }
        if (e.code === 'ShiftLeft' || e.code === 'ShiftRight') { state.shiftDown = false; }
      });

      stage.on('mousedown touchstart', (e) => {
        // Middle button, Space+drag, or Pan tool → pan
        if (e.evt.button === 1 || spaceDown || state.tool === 'pan') {
          stage.draggable(true);
          state.isPanning = true;
          stage.container().style.cursor = 'grabbing';
          return;
        }
        // Right button → pan (like lineup canvas right-drag)
        if (e.evt.button === 2) {
          stage.draggable(true);
          state.isPanning = true;
          stage.container().style.cursor = 'grabbing';
          e.evt.preventDefault();
          return;
        }
        // Select tool + drag on background → pan after 4px threshold
        if (state.tool === 'select' && e.target === stage) {
          const startPos = stage.getPointerPosition();
          const _onMove = () => {
            const cur = stage.getPointerPosition();
            if (!cur || !startPos) return;
            const d = Math.hypot(cur.x - startPos.x, cur.y - startPos.y);
            if (d > 4 && !state.isPanning) {
              stage.draggable(true);
              state.isPanning = true;
              stage.container().style.cursor = 'grabbing';
            }
          };
          stage.on('mousemove.pandetect', _onMove);
          stage.on('mouseup.pandetect',   () => { stage.off('mousemove.pandetect'); stage.off('mouseup.pandetect'); });
        }
      });

      // Prevent context menu on right-click (used for pan)
      stage.container().addEventListener('contextmenu', e => e.preventDefault());

      stage.on('mouseup touchend', () => {
        if (state.isPanning) {
          stage.draggable(false);
          state.isPanning = false;
          stage.container().style.cursor = state.tool === 'select' ? 'default' : 'crosshair';
          drawGrid();
        }
      });

      stage.on('mousemove touchmove', () => {
        updateStatus();
        if (state.isDrawing || state.polyPts.length > 0 || state.arcPts.length > 0) {
          updateDrawPreview();
        }
      });

      // Double-click: finish polyline / polygon
      stage.on('dblclick dbltap', (e) => {
        if (state.isPanning) return;
        const tool = state.tool;
        if (tool === 'polyline' && state.polyPts.length >= 2) {
          e.evt.preventDefault();
          const pts = [...state.polyPts];
          state.polyPts = []; state.isDrawing = false;
          clearDrawPreview();
          addShapeComponent('polyline', { x: pts[0].x, y: pts[0].y, pts, closed: false });
          return;
        }
        if (tool === 'polygon' && state.polyPts.length >= 3) {
          e.evt.preventDefault();
          const pts = [...state.polyPts];
          state.polyPts = []; state.isDrawing = false;
          clearDrawPreview();
          addShapeComponent('polygon_shape', { x: pts[0].x, y: pts[0].y, pts });
          return;
        }
      });

      // Click to place / draw
      stage.on('click tap', (e) => {
        if (state.isPanning) return;
        // Ignore dblclick second click
        if (e.evt.detail === 2) return;

        const isBackground = e.target === stage;
        const pos = pointerMm();
        const tool = state.tool;

        if (tool === 'select') {
          if (isBackground) deselectAll();
          return;
        }

        if (!isBackground && !['polyline', 'polygon', 'arc'].includes(tool)) return;

        // ── Microstrip (2-click draw) ──────────────────────────────────
        if (tool === 'microstrip' || tool === 'ms') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const dx = pos.x - state.drawStart.x;
            const dy = pos.y - state.drawStart.y;
            const L  = Math.sqrt(dx * dx + dy * dy);
            if (L > 0.01) {
              const rot  = Math.atan2(dy, dx) * 180 / Math.PI;
              const comp = addComponent('microstrip', state.drawStart.x, state.drawStart.y);
              comp.params.L = parseFloat(snapMm(L).toFixed(4));
              comp.rotation = parseFloat(rot.toFixed(2));
              reRenderAll(); syncComponents();
            }
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Line (2-click draw) ────────────────────────────────────────
        if (tool === 'line') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const A = state.drawStart;
            const { dx, dy } = snapAngle45(pos.x - A.x, pos.y - A.y);
            const B = { x: snapMm(A.x + dx), y: snapMm(A.y + dy) };
            const L = Math.sqrt(dx * dx + dy * dy);
            if (L > 0.01) {
              addShapeComponent('line', {
                x: A.x, y: A.y,
                pts: [{ x: 0, y: 0 }, { x: B.x - A.x, y: B.y - A.y }],
                params: { strokeW: state.defaults.strokeW }
              });
            }
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Rect (2-click draw) ────────────────────────────────────────
        if (tool === 'rect') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const A = state.drawStart;
            const ex = snapMm(pos.x), ey = snapMm(pos.y);
            const W = Math.abs(ex - A.x), L = Math.abs(ey - A.y);
            if (W > 0.01 && L > 0.01) {
              addShapeComponent('rect_shape', {
                x: Math.min(A.x, ex), y: Math.min(A.y, ey),
                params: { W, L, strokeW: state.defaults.strokeW, filled: false }
              });
            }
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Circle (2-click: center then edge) ────────────────────────
        if (tool === 'circle') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const A = state.drawStart;
            const dx = pos.x - A.x, dy = pos.y - A.y;
            const r  = snapMm(Math.sqrt(dx * dx + dy * dy));
            if (r > 0.01) {
              addShapeComponent('circle_shape', {
                x: A.x, y: A.y,
                params: { radius: r, strokeW: state.defaults.strokeW, filled: false }
              });
            }
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Polyline (N-click, dblclick to finish) ─────────────────────
        if (tool === 'polyline') {
          const pt = { x: snapMm(pos.x), y: snapMm(pos.y) };
          state.polyPts.push(pt);
          state.isDrawing = true;
          updateDrawPreview();
          return;
        }

        // ── Polygon (N-click, dblclick to finish) ─────────────────────
        if (tool === 'polygon') {
          const pt = { x: snapMm(pos.x), y: snapMm(pos.y) };
          state.polyPts.push(pt);
          state.isDrawing = true;
          updateDrawPreview();
          return;
        }

        // ── Arc (3-click: start, mid, end) ────────────────────────────
        if (tool === 'arc') {
          const pt = { x: snapMm(pos.x), y: snapMm(pos.y) };
          state.arcPts.push(pt);
          updateDrawPreview();
          if (state.arcPts.length === 3) {
            const [p1, pm, p2] = state.arcPts;
            state.arcPts = []; state.isDrawing = false;
            clearDrawPreview();
            // Compute circumcircle
            const ax = p1.x, ay = p1.y, bx = pm.x, by = pm.y, cx2 = p2.x, cy2 = p2.y;
            const D = 2 * (ax * (by - cy2) + bx * (cy2 - ay) + cx2 * (ay - by));
            if (Math.abs(D) > 1e-9) {
              const ux = ((ax*ax+ay*ay)*(by-cy2)+(bx*bx+by*by)*(cy2-ay)+(cx2*cx2+cy2*cy2)*(ay-by)) / D;
              const uy = ((ax*ax+ay*ay)*(cx2-bx)+(bx*bx+by*by)*(ax-cx2)+(cx2*cx2+cy2*cy2)*(bx-ax)) / D;
              const radius = Math.sqrt((ux-ax)**2+(uy-ay)**2);
              const startAngle = Math.atan2(ay-uy, ax-ux) * 180 / Math.PI;
              let arcAngle = Math.atan2(cy2-uy, cx2-ux) * 180 / Math.PI - startAngle;
              if (arcAngle < 0) arcAngle += 360;
              addShapeComponent('arc_shape', {
                x: ux, y: uy, cx: 0, cy: 0, radius, startAngle, arcAngle,
                pts: [p1, pm, p2],
                params: { strokeW: state.defaults.strokeW }
              });
            }
          }
          return;
        }

        // ── Dimension (2-click) ────────────────────────────────────────
        if (tool === 'dim_h' || tool === 'dim_v' || tool === 'dim_align') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const A = state.drawStart;
            const B = { x: snapMm(pos.x), y: snapMm(pos.y) };
            addShapeComponent(tool, {
              x: A.x, y: A.y,
              pts: [{ x: 0, y: 0 }, { x: B.x - A.x, y: B.y - A.y }],
              params: { dimType: tool.replace('dim_', '') }
            });
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Text annotation (single-click) ────────────────────────────
        if (tool === 'text') {
          const label = window.prompt('Enter annotation text:', 'Label');
          if (label && label.trim()) {
            addShapeComponent('text_ann', {
              x: snapMm(pos.x), y: snapMm(pos.y),
              params: { text: label.trim(), fontSize: 0.5, color: '#e0e0e0' }
            });
          }
          return;
        }

        // ── Leader annotation (2-click) ────────────────────────────────
        if (tool === 'leader') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            const A = state.drawStart;
            const B = { x: snapMm(pos.x), y: snapMm(pos.y) };
            const label = window.prompt('Leader text:', '');
            addShapeComponent('leader', {
              x: A.x, y: A.y,
              pts: [{ x: 0, y: 0 }, { x: B.x - A.x, y: B.y - A.y }],
              params: { text: (label || '').trim() }
            });
            state.isDrawing = false; state.drawStart = null;
            clearDrawPreview();
          }
          return;
        }

        // ── Ruler ──────────────────────────────────────────────────────
        if (tool === 'ruler') {
          const snapped = { x: snapMm(pos.x), y: snapMm(pos.y) };
          state.measurePts.push(snapped);
          if (state.measurePts.length > 2) state.measurePts.shift();
          drawMeasureOverlay();
          return;
        }

        // ── Single-click placement for RF component tools only ────────
        // Non-RF tool names (pan, select, ruler, etc.) must NOT be placed
        const RF_PLACE_TOOLS = new Set([
          'microstrip', 'ms', 'bend90', 'tee', 'coupled',
          'via', 'port', 'open_stub', 'short_stub'
        ]);
        if (RF_PLACE_TOOLS.has(tool)) {
          addComponent(tool, pos.x, pos.y);
        }
        // All other tools (pan, chamfer, fillet, label, angle_dim, schematic…)
        // are handled by their own cases above and do nothing on a blind click.
      });
    }

    // ── Design serialization ───────────────────────────────────────────
    function getDesignJSON() {
      return JSON.stringify({
        version    : '1.0',
        substrate  : state.substrate,
        components : state.components
      }, null, 2);
    }

    function loadDesignJSON(jsonStr) {
      let design;
      try { design = JSON.parse(jsonStr); } catch (e) { console.error('[RFCAD] parse error', e); return; }
      if (design.substrate) Object.assign(state.substrate, design.substrate);
      state.components = design.components || design; // support both wrapped and bare array
      // Re-derive nextId
      state.nextId = state.components.reduce((m, c) => {
        const n = parseInt((c.id || '').replace('cmp_', ''), 10) || 0;
        return Math.max(m, n + 1);
      }, 1);
      state.selectedId = null;
      reRenderAll();
      syncComponents();
      fitToContent();
    }

    // ── Go! ────────────────────────────────────────────────────────────
    drawGrid();
    bindEvents();
    // Restore last session first; fall back to empty canvas
    if (!sessionLoad()) {
      updateStatus();
    }

    // Resize observer
    if (window.ResizeObserver) {
      new ResizeObserver(() => {
        stage.width(container.offsetWidth);
        stage.height(container.offsetHeight);
        drawGrid();
        reRenderAll();
      }).observe(container);
    }

    // ── Public API ─────────────────────────────────────────────────────
    return {
      setTool,
      addComponent,
      deleteSelected,
      fitToContent,
      drawGrid,
      getDesignJSON,
      loadDesignJSON,
      getComponents : () => state.components,
      getState      : () => state,
      updateParam,
      updateStatus,
      // Alias used by toolbar Export button (matches convention in toolbar onclick)
      exportJSON() { return getDesignJSON(); },
      // Export canvas as SVG data-URL using Konva's built-in toDataURL
      exportSVG() {
        try {
          // Konva stage.toDataURL does not produce SVG natively;
          // build a minimal SVG from component bounding boxes instead.
          const comps  = state.components;
          if (!comps || comps.length === 0) return null;
          const SCALE  = state.gridSizeMm || 1; // mm per logical unit
          const pad    = 5;
          let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
          comps.forEach(c => {
            const W = (c.params && c.params.W) ? +c.params.W : 1;
            const L = (c.params && c.params.L) ? +c.params.L : 10;
            minX = Math.min(minX, c.x - L / 2);
            maxX = Math.max(maxX, c.x + L / 2);
            minY = Math.min(minY, c.y - W / 2);
            maxY = Math.max(maxY, c.y + W / 2);
          });
          const vw = maxX - minX + pad * 2;
          const vh = maxY - minY + pad * 2;
          const COMP_COL = { metal_top:'#c8a84b', metal_bot:'#7b9fc7',
                             metal_inner_1:'#8fcf70', metal_inner_2:'#c878c8' };
          let rects = '';
          comps.forEach(c => {
            const W   = (c.params && c.params.W) ? +c.params.W : 1;
            const L   = (c.params && c.params.L) ? +c.params.L : 10;
            const col = COMP_COL[c.layer] || '#c8a84b';
            const rx  = c.x - minX + pad - L / 2;
            const ry  = c.y - minY + pad - W / 2;
            rects += `<rect x="${rx.toFixed(3)}" y="${ry.toFixed(3)}" ` +
                     `width="${L.toFixed(3)}" height="${W.toFixed(3)}" ` +
                     `fill="${col}" stroke="#333" stroke-width="0.05" ` +
                     `transform="rotate(${c.rotation||0},${(c.x-minX+pad).toFixed(3)},${(c.y-minY+pad).toFixed(3)})" />\n`;
          });
          const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${vw.toFixed(3)} ${vh.toFixed(3)}"
     width="${(vw*10).toFixed(0)}" height="${(vh*10).toFixed(0)}">
  <rect width="100%" height="100%" fill="#1a1a2e"/>
${rects}</svg>`;
          return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
        } catch(e) { console.error('exportSVG:', e); return null; }
      },
      // Zoom by a scale factor
      zoomBy(factor) {
        const s = Math.min(Math.max(stage.scaleX() * factor, BASE_SCALE * 0.05), BASE_SCALE * 30);
        stage.scale({ x: s, y: s });
        state.zoom = s / BASE_SCALE;
        drawGrid(); reRenderAll(); updateStatus(); syncZoom();
      },
      // Rotate selected component by deg
      rotateSelected(deg) {
        const comp = state.components.find(c => c.id === state.selectedId);
        if (comp) {
          comp.rotation = (comp.rotation + deg) % 360;
          reRenderAll(); syncComponents();
          syncSelected(state.components.find(c => c.id === state.selectedId));
        }
      },
      // Clear all components and session
      clearAll() {
        try { localStorage.removeItem(SESSION_KEY); } catch(e) {}
        state.components = []; state.selectedId = null; state.nextId = 1;
        reRenderAll(); syncComponents(); updateStatus();
      },
      // New session: same as clearAll but with user intent (keeps session key clear)
      clearSession() {
        try { localStorage.removeItem(SESSION_KEY); } catch(e) {}
        state.components = []; state.selectedId = null; state.nextId = 1;
        reRenderAll(); updateStatus();
      },
      // Explicitly save current state to localStorage
      saveSession() { sessionSave(); },
      // Reload from localStorage (useful after external edits)
      loadSession()  { return sessionLoad(); },
      // Set grid size in mm
      setGrid(sizeMm) {
        state.gridSizeMm = sizeMm || 0.5;
        drawGrid(); updateStatus();
      },
      // Enable/disable snap-to-grid
      setSnap(enabled) {
        state.snapEnabled = !!enabled;
      },
      // Clear ruler measurement
      clearMeasure() {
        state.measurePts = []; drawMeasureOverlay();
      },

      // ── Layer management ───────────────────────────────────────
      setLayerVisible(layerId, visible) {
        state.layerVisibility = state.layerVisibility || {};
        state.layerVisibility[layerId] = !!visible;
        reRenderAll();
      },
      setLayerLocked(layerId, locked) {
        state.layerLocked = state.layerLocked || {};
        state.layerLocked[layerId] = !!locked;
      },
      setActiveLayer(layerId) {
        state.defaults = state.defaults || {};
        state.defaults.layer = layerId;
        const LAYER_NAMES = {
          metal_top: 'Metal Top', metal_bot: 'Metal Bot',
          metal_inner_1: 'Inner 1', metal_inner_2: 'Inner 2',
          substrate: 'Substrate', silkscreen: 'Silkscreen', drc: 'DRC'
        };
        const LAYER_COLORS = {
          metal_top: '#c8a84b', metal_bot: '#7b9fc7',
          metal_inner_1: '#8fcf70', metal_inner_2: '#c878c8',
          substrate: '#4a8a4a', silkscreen: '#eeeeee', drc: '#f44444'
        };
        // Update active-layer badge in properties header
        const badge = document.getElementById(state.instanceId + '_active_layer_badge');
        if (badge) {
          badge.textContent = LAYER_NAMES[layerId] || layerId;
          badge.style.background = LAYER_COLORS[layerId] || '#555';
          badge.style.color = '#000';
        }
        // Update layer name buttons in layer panel
        const panel = document.getElementById(state.instanceId + '_layer_panel');
        if (panel) {
          panel.querySelectorAll('.rfcad-layer-name').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.layer === layerId);
          });
        }
        // Update status bar layer segment
        const layerSpan = document.getElementById(state.instanceId + '_status_layer');
        if (layerSpan) layerSpan.textContent = LAYER_NAMES[layerId] || layerId;
      },

      // ── Modify: mirror, copy, array, offset ───────────────────
      mirrorSelected(axis) {
        const comp = state.components.find(c => c.id === state.selectedId);
        if (!comp) return;
        if (axis === 'h') {
          comp.scaleX = (comp.scaleX || 1) * -1;
        } else {
          comp.scaleY = (comp.scaleY || 1) * -1;
        }
        reRenderAll(); syncComponents();
      },
      copySelected() {
        const comp = state.components.find(c => c.id === state.selectedId);
        if (!comp) return;
        const copy = JSON.parse(JSON.stringify(comp));
        copy.id   = 'c' + Date.now() + Math.random().toString(36).slice(2, 6);
        copy.x   += (state.gridSizeMm || 1) * 4;
        copy.y   += (state.gridSizeMm || 1) * 4;
        copy.name = comp.name + '_copy';
        state.components.push(copy);
        reRenderAll(); selectComponent(copy.id); syncComponents();
      },
      arraySelected() {
        const comp = state.components.find(c => c.id === state.selectedId);
        if (!comp) return;
        const cols = parseInt(window.prompt('Columns:', '3') || '0', 10);
        const rows = parseInt(window.prompt('Rows:',    '3') || '0', 10);
        const dx   = parseFloat(window.prompt('X spacing (mm):', '5') || '0');
        const dy   = parseFloat(window.prompt('Y spacing (mm):', '5') || '0');
        if (!cols || !rows) return;
        for (let r = 0; r < rows; r++) {
          for (let c = 0; c < cols; c++) {
            if (r === 0 && c === 0) continue;
            const copy = JSON.parse(JSON.stringify(comp));
            copy.id   = 'c' + Date.now() + '_' + r + '_' + c;
            copy.x    = comp.x + c * dx;
            copy.y    = comp.y + r * dy;
            copy.name = comp.name + '_' + r + '_' + c;
            state.components.push(copy);
          }
        }
        reRenderAll(); syncComponents();
      },
      offsetSelected() {
        const comp = state.components.find(c => c.id === state.selectedId);
        if (!comp || !comp.params) return;
        // Simple uniform outward expansion of W and L by grid size
        const d = state.gridSizeMm || 0.5;
        if (comp.params.W !== undefined) comp.params.W = Math.max(0.01, comp.params.W + d);
        if (comp.params.L !== undefined) comp.params.L = Math.max(0.01, comp.params.L + d);
        if (comp.params.radius !== undefined) comp.params.radius = Math.max(0.01, comp.params.radius + d);
        reRenderAll(); syncComponents();
        syncSelected(state.components.find(c => c.id === state.selectedId));
      },

      // ── Symbol / Schematic mode ────────────────────────────────
      setSymbolMode(bool) {
        state.symbolMode = !!bool;
        reRenderAll();
        const btn = document.querySelector(
          '#' + state.instanceId + '_tb [data-tool="schematic"]'
        );
        if (btn) btn.classList.toggle('active', state.symbolMode);
        // Also mark the global schematic button if present
        document.querySelectorAll('[data-tool="schematic"]').forEach(b => {
          if (b.closest && b.closest('#' + state.instanceId + '_tb')) {
            b.classList.toggle('active', state.symbolMode);
          }
        });
      },
      toggleSymbolMode() {
        this.setSymbolMode(!state.symbolMode);
      },

      setFreq(f) {
        state.freqGHz = parseFloat(f) || 2.4;
        const comp = state.components.find(c => c.id === state.selectedId) || null;
        if (typeof rfCalc !== 'undefined') {
          rfCalc.updateDisplay(
            'rfcad_rf_params_' + state.instanceId,
            comp, state.substrate, state.freqGHz
          );
        }
      },
      // Direct param update from Shiny
      handleShinyMsg(type, msg) {
        switch (type) {
          case 'rfcad_set_tool'        : setTool(msg.tool); break;
          case 'rfcad_update_param': {
            const cid  = msg.componentId || msg.id;
            const comp = state.components.find(c => c.id === cid);
            if (comp) {
              if (msg.name     !== undefined) comp.name     = msg.name;
              if (msg.rotation !== undefined) comp.rotation = +msg.rotation;
              if (msg.layer    !== undefined) comp.layer    = msg.layer;
              if (msg.mat      !== undefined) comp.mat      = msg.mat;
              if (msg.params && typeof msg.params === 'object') Object.assign(comp.params, msg.params);
              // also accept flat {param, value} for programmatic use
              if (msg.param !== undefined) {
                if (msg.param.startsWith('params.')) comp.params[msg.param.slice(7)] = isNaN(+msg.value) ? msg.value : +msg.value;
                else comp[msg.param] = isNaN(+msg.value) ? msg.value : +msg.value;
              }
              reRenderAll(); syncComponents();
              const up = state.components.find(c => c.id === cid);
              if (up) {
                syncSelected(up);
                if (typeof rfCalc !== 'undefined')
                  rfCalc.updateDisplay('rfcad_rf_params_' + state.instanceId, up, state.substrate, state.freqGHz);
              }
            }
            break;
          }
          case 'rfcad_load_design'     : loadDesignJSON(msg.json); break;
          case 'rfcad_clear'           : state.components = []; state.selectedId = null; state.nextId = 1; reRenderAll(); syncComponents(); break;
          case 'rfcad_set_grid'        :
            if (msg.gridSizeMm  !== undefined) state.gridSizeMm  = msg.gridSizeMm;
            if (msg.snapEnabled !== undefined) state.snapEnabled = msg.snapEnabled;
            if (msg.gridVisible !== undefined) state.gridVisible = msg.gridVisible;
            drawGrid(); break;
          case 'rfcad_update_substrate':
            Object.assign(state.substrate, msg);
            // Refresh RF params if a component is selected
            if (typeof rfCalc !== 'undefined') {
              const comp = state.components.find(c => c.id === state.selectedId) || null;
              rfCalc.updateDisplay(
                'rfcad_rf_params_' + state.instanceId,
                comp, state.substrate, state.freqGHz
              );
            }
            break;
          case 'rfcad_set_freq':
            state.freqGHz = parseFloat(msg.freq_GHz) || 2.4;
            { const selComp = state.components.find(c => c.id === state.selectedId) || null;
              if (typeof rfCalc !== 'undefined')
                rfCalc.updateDisplay('rfcad_rf_params_' + state.instanceId, selComp, state.substrate, state.freqGHz);
            }
            break;
          case 'rfcad_fit_view'        : fitToContent(); break;
          case 'rfcad_set_symbol_mode' :
            state.symbolMode = !!msg.enabled;
            reRenderAll();
            break;
          case 'rfcad_zoom_in'         :
            { const s = Math.min(stage.scaleX() * 1.3, BASE_SCALE * 30); stage.scale({ x: s, y: s }); state.zoom = s / BASE_SCALE; drawGrid(); reRenderAll(); updateStatus(); syncZoom(); } break;
          case 'rfcad_zoom_out'        :
            { const s = Math.max(stage.scaleX() / 1.3, BASE_SCALE * 0.05); stage.scale({ x: s, y: s }); state.zoom = s / BASE_SCALE; drawGrid(); reRenderAll(); updateStatus(); syncZoom(); } break;
          case 'rfcad_delete_selected' : deleteSelected(); break;
          case 'rfcad_rotate_selected' :
            { const comp = state.components.find(c => c.id === state.selectedId); if (comp) { comp.rotation = (comp.rotation + (msg.angle || 45)) % 360; reRenderAll(); syncComponents(); } } break;
          case 'rfcad_export_json'     :
            shinySend('rfcad_export_data', getDesignJSON()); break;
        }
      }
    };
  } // end createCanvas

  // ── Global Shiny message router ────────────────────────────────────────
  // All message handlers are registered once and dispatch to the correct canvas
  const MSG_TYPES = [
    'rfcad_init', 'rfcad_set_tool', 'rfcad_update_param', 'rfcad_load_design',
    'rfcad_clear', 'rfcad_set_grid', 'rfcad_update_substrate', 'rfcad_fit_view',
    'rfcad_zoom_in', 'rfcad_zoom_out', 'rfcad_delete_selected', 'rfcad_rotate_selected',
    'rfcad_export_json', 'rfcad_set_freq'
  ];

  function registerShinyHandlers() {
    if (typeof Shiny === 'undefined') return;

    Shiny.addCustomMessageHandler('rfcad_init', (msg) => {
      const id  = msg.instanceId  || 'default';
      const cid = msg.containerId || 'rfcad_canvas';
      const ns  = msg.nsPrefix    || '';
      if (canvases[id]) return; // already initialized
      function tryInit() {
        const el = document.getElementById(cid);
        if (el && el.offsetWidth > 0) {
          canvases[id] = createCanvas(cid, ns, id);
        } else {
          setTimeout(tryInit, 200);
        }
      }
      tryInit();
    });

    MSG_TYPES.slice(1).forEach(type => {
      Shiny.addCustomMessageHandler(type, (msg) => {
        const id = msg.instanceId || 'default';
        const cv = canvases[id];
        if (cv) cv.handleShinyMsg(type, msg);
      });
    });
  }

  // ── Bootstrap ─────────────────────────────────────────────────────────
  function bootstrap() {
    registerShinyHandlers();

    // Download trigger: server asks JS to click a Shiny downloadButton
    if (typeof Shiny !== 'undefined') {
      Shiny.addCustomMessageHandler('rfcad_trigger_download', function(msg) {
        // msg.url = output ID; msg.filename = suggested filename (hint only)
        var anchor = document.createElement('a');
        anchor.href     = 'session/' + msg.url + '/dataobj/' + msg.filename +
                          '?w=&rand=' + Math.floor(Math.random() * 1e9);
        anchor.download  = msg.filename;
        anchor.style.display = 'none';
        document.body.appendChild(anchor);
        anchor.click();
        setTimeout(function() { document.body.removeChild(anchor); }, 2000);
      });
    }

    // For standalone (non-Shiny) use: auto-init if rfcad_canvas exists
    if (typeof Shiny === 'undefined') {
      const el = document.getElementById('rfcad_canvas');
      if (el) canvases['default'] = createCanvas('rfcad_canvas', '', 'default');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootstrap);
  } else {
    bootstrap();
  }

  // Also bootstrap after Shiny session starts
  if (typeof $ !== 'undefined') {
    $(document).on('shiny:sessioninitialized', () => registerShinyHandlers());
  }

  // ── Public namespace ───────────────────────────────────────────────────
  global.RFCAD = {
    canvases,
    getCanvas   : (id) => canvases[id || 'default'],
    createCanvas,
    registerShinyHandlers
  };

})(window);
