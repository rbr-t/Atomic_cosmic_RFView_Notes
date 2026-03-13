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
  const GRID_MAJOR_CLR = '#252540';
  const GRID_MINOR_CLR = '#1a1a30';
  const COMP_COLORS    = {
    metal_top : '#c8a84b',
    metal_bot : '#7b9fc7',
    via       : '#d4d4d4',
    port      : '#ff6b6b',
    default   : '#c8a84b'
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
      instanceId  : instanceId || 'default',
      nsPrefix    : nsPrefix   || '',
      tool        : 'select',
      zoom        : 1.0,
      gridSizeMm  : 0.5,
      snapEnabled : true,
      gridVisible : true,
      components  : [],
      nextId      : 1,
      selectedId  : null,
      isPanning   : false,
      isDrawing   : false,
      drawStart   : null,
      drawPreview : null,
      substrate   : { h: 0.254, er: 4.3, tand: 0.0027, t: 0.035 },
      freqGHz    : 2.4,
      defaults    : { W: 0.5, L: 5.0, gap: 0.2, layer: 'metal_top' }
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

    function syncComponents() {
      shinySend('rfcad_components', JSON.stringify(state.components));
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

    function renderComponent(comp) {
      const isSel = comp.id === state.selectedId;
      const color = COMP_COLORS[comp.layer] || COMP_COLORS.default;
      const curScale = stage.scaleX();

      const group = new Konva.Group({
        id       : comp.id,
        x        : mmToPx(comp.x),
        y        : mmToPx(comp.y),
        rotation : comp.rotation || 0,
        draggable: true
      });

      switch (comp.type) {
        case 'microstrip'  : buildMicrostrip(group, comp, color, isSel); break;
        case 'bend90'      : buildBend90(group, comp, color, isSel); break;
        case 'tee'         : buildTee(group, comp, color, isSel); break;
        case 'coupled'     : buildCoupled(group, comp, color, isSel); break;
        case 'via'         : buildVia(group, comp, isSel); break;
        case 'port'        : buildPort(group, comp, isSel); break;
        case 'open_stub'   : buildOpenStub(group, comp, color, isSel); break;
        case 'short_stub'  : buildShortStub(group, comp, color, isSel); break;
        default            : buildMicrostrip(group, comp, color, isSel);
      }

      // Component name label
      if (comp.name) {
        const fs = Math.max(7, 11 / curScale);
        group.add(new Konva.Text({
          x: 2, y: -(fs + 3) / curScale,
          text: comp.name, fontSize: fs, fill: LABEL_COLOR, listening: false
        }));
      }

      // Selection outline ring on top of everything
      if (isSel) {
        const bb = group.getClientRect({ relativeTo: layers.comp });
        layers.ui.destroyChildren();
        const pad = 4 / curScale;
        layers.ui.add(new Konva.Rect({
          x: bb.x - pad, y: bb.y - pad,
          width: (bb.width / curScale) + pad * 2,
          height: (bb.height / curScale) + pad * 2,
          strokeWidth: 2 / curScale, stroke: SEL_COLOR,
          dash: [4 / curScale, 4 / curScale],
          fill: 'transparent', listening: false,
          transformsEnabled: 'position'
        }));
        layers.ui.batchDraw();
      }

      // Drag events
      group.on('click tap', () => selectComponent(comp.id));
      group.on('dragstart', () => selectComponent(comp.id));
      group.on('dragmove', () => updateStatus());
      group.on('dragend', () => {
        const sx = snapMm(pxToMm(group.x()));
        const sy = snapMm(pxToMm(group.y()));
        group.x(mmToPx(sx));
        group.y(mmToPx(sy));
        const c = state.components.find(c => c.id === comp.id);
        if (c) { c.x = sx; c.y = sy; }
        syncComponents();
        layers.comp.batchDraw();
      });

      layers.comp.add(group);
    }

    function reRenderAll() {
      layers.comp.destroyChildren();
      layers.ui.destroyChildren();
      state.components.forEach(c => renderComponent(c));
      layers.comp.batchDraw();
      layers.ui.batchDraw();
    }

    // ── Component CRUD ─────────────────────────────────────────────────
    function defaultParams(type) {
      const d = state.defaults;
      switch (type) {
        case 'microstrip' : return { W: d.W,  L: d.L };
        case 'bend90'     : return { W: d.W,  L: d.L, miter: true };
        case 'tee'        : return { W: d.W,  L: d.L };
        case 'coupled'    : return { W: d.W,  L: d.L, gap: d.gap };
        case 'via'        : return { drill: 0.2, pad: 0.5 };
        case 'port'       : return { W: d.W,  portNum: countByType('port') + 1 };
        case 'open_stub'  : return { W: d.W,  L: d.L / 2 };
        case 'short_stub' : return { W: d.W,  L: d.L / 2 };
        default           : return { W: d.W,  L: d.L };
      }
    }

    function countByType(type) {
      return state.components.filter(c => c.type === type).length;
    }

    function addComponent(type, wx, wy) {
      const sx = snapMm(wx);
      const sy = snapMm(wy);
      const abbr = { microstrip:'MS', bend90:'B90', tee:'TEE', coupled:'CPL', via:'VIA', port:'P', open_stub:'OS', short_stub:'SS' };
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

    function selectComponent(id) {
      state.selectedId = id;
      reRenderAll();
      const comp = state.components.find(c => c.id === id) || null;
      syncSelected(comp);
      updateStatus();
      // Phase 2: update RF params display
      if (typeof rfCalc !== 'undefined') {
        rfCalc.updateDisplay(
          'rfcad_rf_params_' + state.instanceId,
          comp, state.substrate, state.freqGHz
        );
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
      state.tool      = toolName;
      state.isDrawing = false;
      state.drawStart = null;
      clearDrawPreview();
      stage.container().style.cursor = toolName === 'select' ? 'default' : 'crosshair';
      syncTool();
      // Update toolbar button highlights
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

    function updateDrawPreview() {
      clearDrawPreview();
      if (!state.drawStart || state.tool !== 'microstrip') return;
      const pos = pointerMm();
      const dx  = pos.x - state.drawStart.x;
      const dy  = pos.y - state.drawStart.y;
      const L   = Math.sqrt(dx * dx + dy * dy);
      if (L < 0.01) return;
      const W   = mmToPx(state.defaults.W);
      const rot = Math.atan2(dy, dx) * 180 / Math.PI;
      state.drawPreview = new Konva.Group({
        x: mmToPx(state.drawStart.x), y: mmToPx(state.drawStart.y),
        rotation: rot, listening: false
      });
      state.drawPreview.add(new Konva.Rect({
        x: 0, y: -W / 2, width: mmToPx(snapMm(L)), height: W,
        fill: COMP_COLORS.metal_top + 'aa', stroke: SEL_COLOR,
        strokeWidth: 1 / stage.scaleX()
      }));
      // Length annotation
      state.drawPreview.add(new Konva.Text({
        x: mmToPx(L / 2), y: -(W / 2 + 12 / stage.scaleX()),
        text: snapMm(L).toFixed(3) + ' mm',
        fontSize: 10 / stage.scaleX(), fill: SEL_COLOR,
        listening: false, align: 'center'
      }));
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

      // Pan: middle-mouse or Space+drag
      let spaceDown = false;
      document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;
        if (e.code === 'Space') { spaceDown = true; stage.container().style.cursor = 'grab'; }
        if (e.code === 'Delete' || e.code === 'Backspace') deleteSelected();
        if (e.code === 'Escape') { deselectAll(); setTool('select'); }
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
      });

      stage.on('mousedown touchstart', (e) => {
        if (e.evt.button === 1 || spaceDown) {
          stage.draggable(true);
          state.isPanning = true;
          stage.container().style.cursor = 'grabbing';
          return;
        }
        if (e.evt.button === 2) return; // right click
      });

      stage.on('mouseup touchend', () => {
        if (state.isPanning) {
          stage.draggable(false);
          state.isPanning = false;
          stage.container().style.cursor = state.tool === 'select' ? 'default' : 'crosshair';
          drawGrid();
        }
      });

      stage.on('mousemove', () => {
        updateStatus();
        if (state.isDrawing) updateDrawPreview();
      });

      // Click to place / draw
      stage.on('click tap', (e) => {
        if (state.isPanning) return;
        const isBackground = e.target === stage;

        if (state.tool === 'select') {
          if (isBackground) deselectAll();
          return;
        }

        if (!isBackground) return; // clicked a component, not background

        const pos = pointerMm();

        if (state.tool === 'microstrip') {
          if (!state.isDrawing) {
            state.isDrawing = true;
            state.drawStart = { x: snapMm(pos.x), y: snapMm(pos.y) };
          } else {
            // Finish microstrip by length
            const dx = pos.x - state.drawStart.x;
            const dy = pos.y - state.drawStart.y;
            const L  = Math.sqrt(dx * dx + dy * dy);
            if (L > 0.01) {
              const rot  = Math.atan2(dy, dx) * 180 / Math.PI;
              const comp = addComponent('microstrip', state.drawStart.x, state.drawStart.y);
              comp.params.L = parseFloat(snapMm(L).toFixed(4));
              comp.rotation = parseFloat(rot.toFixed(2));
              reRenderAll();
              syncComponents();
            }
            state.isDrawing = false;
            state.drawStart = null;
            clearDrawPreview();
          }
        } else {
          // Single-click placement for all other tools
          addComponent(state.tool, pos.x, pos.y);
        }
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
    updateStatus();

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
          case 'rfcad_update_param'    : updateParam(msg.id, msg.param, msg.value); break;
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
