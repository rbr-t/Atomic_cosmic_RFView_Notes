// ============================================================
// PA Lineup Interactive Canvas
// D3.js-based drag-and-drop lineup builder
// ============================================================

// ============================================================
// Global Toggle Functions - Defined First for Immediate Availability
// ============================================================

function toggleCanvasSidebar() {
  const sidebar = document.getElementById('canvas_sidebar');
  
  if (!sidebar) {
    console.error('Sidebar not found!');
    return;
  }
  
  // Toggle between collapsed and expanded states
  if (sidebar.classList.contains('collapsed')) {
    sidebar.classList.remove('collapsed');
    sidebar.classList.add('expanded');
    console.log('Sidebar expanded');
  } else {
    sidebar.classList.remove('expanded');
    sidebar.classList.add('collapsed');
    console.log('Sidebar collapsed');
  }
}

function toggleCanvasTopSidebar() {
  const sidebar = document.getElementById('canvas_top_sidebar');
  
  if (!sidebar) {
    console.error('Top sidebar not found!');
    return;
  }
  
  // Toggle between collapsed and expanded states
  if (sidebar.classList.contains('collapsed')) {
    sidebar.classList.remove('collapsed');
    sidebar.classList.add('expanded');
    console.log('Top sidebar expanded');
  } else {
    sidebar.classList.remove('expanded');
    sidebar.classList.add('collapsed');
    console.log('Top sidebar collapsed');
  }
}

function toggleCanvasFullscreen() {
  const container = document.getElementById('pa_lineup_canvas_container');
  const button = document.getElementById('canvas_fullscreen_btn');
  
  if (!container) {
    console.error('Canvas container not found!');
    return;
  }
  
  if (!document.fullscreenElement) {
    // Enter fullscreen
    container.requestFullscreen().then(() => {
      console.log('Entered fullscreen');
      container.classList.add('fullscreen-mode');
      if (button) {
        button.innerHTML = '<i class="fa fa-compress"></i>';
        button.title = 'Exit Fullscreen (ESC)';
      }
    }).catch((err) => {
      console.error('Error entering fullscreen:', err);
      alert('Fullscreen mode is not supported or blocked by your browser.');
    });
  } else {
    // Exit fullscreen
    document.exitFullscreen().then(() => {
      console.log('Exited fullscreen');
      container.classList.remove('fullscreen-mode');
      if (button) {
        button.innerHTML = '<i class="fa fa-expand"></i>';
        button.title = 'Toggle Fullscreen';
      }
    }).catch((err) => {
      console.error('Error exiting fullscreen:', err);
    });
  }
}

// Listen for fullscreen change events (including ESC key)
document.addEventListener('fullscreenchange', () => {
  const container = document.getElementById('pa_lineup_canvas_container');
  const button = document.getElementById('canvas_fullscreen_btn');
  
  if (!document.fullscreenElement) {
    // Exited fullscreen (including via ESC key)
    if (container) {
      container.classList.remove('fullscreen-mode');
    }
    if (button) {
      button.innerHTML = '<i class="fa fa-expand"></i>';
      button.title = 'Toggle Fullscreen';
    }
    console.log('Fullscreen exited (possibly via ESC)');
  }
});

// Make functions globally accessible
window.toggleCanvasSidebar = toggleCanvasSidebar;
window.toggleCanvasTopSidebar = toggleCanvasTopSidebar;
window.toggleCanvasFullscreen = toggleCanvasFullscreen;

console.log('✓ Toggle functions loaded and exposed to window');

// ============================================================
// PALineupCanvas Class
// ============================================================

class PALineupCanvas {
  constructor(containerId, config = {}) {
    this.containerId = containerId;
    this.width = config.width || 1200;
    this.height = config.height || 600;
    this.components = [];
    this.connections = [];
    this.selectedComponent = null;
    this.selectedComponents = []; // Array for multi-select
    this.selectedConnection = null;
    this.draggedComponent = null;
    this.nextId = 1;
    this.wireMode = false;
    this.wireStart = null;
    this.tempWireLine = null;  // Temporary line while drawing wire
    this.hoveredPort = null;   // Track hovered port for snap detection
    this.boxSelectMode = false;
    this.selectionBox = null;
    this.selectionStart = null;
    
    // Lock canvas editing
    this.locked = false;
    
    // Undo/Redo functionality
    this.history = [];
    this.historyIndex = -1;
    this.maxHistorySize = 50;
    
    // Clipboard for cut/copy/paste
    this.clipboard = null;
    
    // Initialize global clipboard for cross-canvas copy/paste
    if (typeof window.paCanvasClipboard === 'undefined') {
      window.paCanvasClipboard = null;
    }
    
    // Text repositioning mode (activated by F5 key)
    this.textDragMode = false;
    this.textDragComponent = null;
    this.textDragStart = null;
    this.textOriginalOffset = null;
    
    // Power display columns
    this.showPowerDisplay = false;
    this.powerColumns = [];
    this.powerUnit = 'dBm'; // 'dBm', 'W', or 'both'
    
    // Impedance display columns
    this.showImpedanceDisplay = false;
    this.impedanceColumns = [];
    this.impedanceUnit = 'rectangular'; // 'rectangular' (50+j10), 'polar' (51∠11°), or 'vswr'
    this.impedanceMode = 'full'; // 'full' or 'backoff' - NEW: show full power or backoff impedance

    // Gain display
    this.showGainDisplay = false;

    // PAE display
    this.showPAEDisplay = false;

    // Phase display
    this.showPhaseDisplay = false;

    // Calculation rationale display
    this.showCalculationRationale = false;
    
    // Central divider lines
    this.showHorizontalLine = true;
    this.showVerticalLine = true;
    this.showGrid = true;  // Show full matrix grid (100px spacing)
    
    // Canvas origin (center point where crosshairs meet)
    this.originX = this.width / 2;  // 600
    this.originY = this.height / 2; // 300
    
    this.init();
  }
  
  init() {
    console.log('Initializing canvas with containerId:', this.containerId);
    
    // Create SVG canvas
    this.svg = d3.select(`#${this.containerId}`)
      .append('svg')
      .attr('width', this.width)
      .attr('height', this.height)
      .style('border', '1px solid #333')
      .style('background', '#1a1a1a')
      .style('border-radius', '8px');
    
    console.log('SVG created:', this.svg.node());
    
    // Create defs for reusable elements
    const defs = this.svg.append('defs');
    
    // Arrow marker for connections (9x9 for better visibility)
    defs.append('marker')
      .attr('id', 'arrowhead')
      .attr('markerWidth', 9)
      .attr('markerHeight', 9)
      .attr('refX', 7)
      .attr('refY', 3)
      .attr('orient', 'auto')
      .append('polygon')
      .attr('points', '0 0, 9 3, 0 6')
      .attr('fill', '#ff7f11');
    
    // Create groups for layers
    this.gridLayer = this.svg.append('g').attr('class', 'grid-layer');
    this.centralLineLayer = this.svg.append('g').attr('class', 'central-line-layer');
    this.powerLayer = this.svg.append('g').attr('class', 'power-layer');
    this.impedanceLayer = this.svg.append('g').attr('class', 'impedance-layer');
    this.gainLayer = this.svg.append('g').attr('class', 'gain-layer');
    this.paeLayer   = this.svg.append('g').attr('class', 'pae-layer');
    this.phaseLayer = this.svg.append('g').attr('class', 'phase-layer');
    this.calculationRationaleLayer = this.svg.append('g').attr('class', 'calculation-rationale-layer');
    this.connectionsLayer = this.svg.append('g').attr('class', 'connections-layer');
    this.componentsLayer = this.svg.append('g').attr('class', 'components-layer');

    // Create zoom group that contains all drawable layers
    this.zoomGroup = this.svg.insert('g', ':first-child').attr('class', 'zoom-group');
    this.zoomGroup.node().appendChild(this.gridLayer.node());
    this.zoomGroup.node().appendChild(this.centralLineLayer.node());
    this.zoomGroup.node().appendChild(this.powerLayer.node());
    this.zoomGroup.node().appendChild(this.impedanceLayer.node());
    this.zoomGroup.node().appendChild(this.gainLayer.node());
    this.zoomGroup.node().appendChild(this.paeLayer.node());
    this.zoomGroup.node().appendChild(this.phaseLayer.node());
    this.zoomGroup.node().appendChild(this.calculationRationaleLayer.node());
    this.zoomGroup.node().appendChild(this.connectionsLayer.node());
    this.zoomGroup.node().appendChild(this.componentsLayer.node());
    
    // Draw central divider line
    this.drawGuideLines();
    
    // Add zoom behavior
    this.zoom = d3.zoom()
      .scaleExtent([0.1, 4])
      .on('zoom', (event) => {
        console.log('Zoom event - transform:', event.transform.toString());
        this.zoomGroup.attr('transform', event.transform);
      });
    
    this.svg.call(this.zoom);
    
    // Reset zoom to identity (scale=1, translate=0,0) on initialization
    console.log('Resetting zoom to identity...');
    this.svg.call(this.zoom.transform, d3.zoomIdentity);
    console.log('Zoom reset complete. Transform should be: translate(0,0) scale(1)');
    
    // Initialize drag behavior for components
    this.drag = d3.drag()
      .on('start', (event, d) => this.onDragStart(event, d))
      .on('drag', (event, d) => this.onDrag(event, d))
      .on('end', (event, d) => this.onDragEnd(event, d));
    
    // Add instruction text
    this.instructionText = this.svg.append('text')
      .attr('x', this.width / 2)
      .attr('y', this.height / 2)
      .attr('text-anchor', 'middle')
      .attr('fill', '#666')
      .attr('font-size', '18px')
      .attr('font-family', 'sans-serif')
      .text('← Drag components from palette or select a template above');
    
    // Draw grid
    this.drawGrid();
    
    // Create component palette (sidebar)
    this.createPalette();
    
    // Set up event handlers
    this.setupEventHandlers();
    
    console.log('Canvas initialization complete');
  }
  
  drawGrid() {
    const gridSize = 20;
    
    // Vertical lines
    for (let x = 0; x < this.width; x += gridSize) {
      this.gridLayer.append('line')
        .attr('x1', x)
        .attr('y1', 0)
        .attr('x2', x)
        .attr('y2', this.height)
        .attr('stroke', '#2a2a2a')
        .attr('stroke-width', 0.5);
    }
    
    // Horizontal lines
    for (let y = 0; y < this.height; y += gridSize) {
      this.gridLayer.append('line')
        .attr('x1', 0)
        .attr('y1', y)
        .attr('x2', this.width)
        .attr('y2', y)
        .attr('stroke', '#2a2a2a')
        .attr('stroke-width', 0.5);
    }
  }
  
  // ── Shared helper: detect distinct rows / cols from component positions ──
  _detectRows() {
    const rows = [];
    this.components.forEach(c => {
      if (!rows.some(r => Math.abs(r - c.y) < 60)) rows.push(c.y);
    });
    return rows.sort((a, b) => a - b);
  }

  _detectCols() {
    const cols = [];
    this.components.forEach(c => {
      if (!cols.some(cx => Math.abs(cx - c.x) < 60)) cols.push(c.x);
    });
    return cols.sort((a, b) => a - b);
  }

  drawGuideLines() {
    this.centralLineLayer.selectAll('*').remove();
    const W = this.width, H = this.height;
    const HC = 60; // half cell (120 px grid)

    // ── Helpers ────────────────────────────────────────────────────────────
    const hLine = (y, mid) => {
      this.centralLineLayer.append('line')
        .attr('x1', 0).attr('y1', y).attr('x2', W).attr('y2', y)
        .attr('stroke', mid ? '#00ddff' : '#00aaff')
        .attr('stroke-width', mid ? 2.5 : 1)
        .attr('stroke-dasharray', mid ? '12,4' : '6,4')
        .attr('opacity', mid ? 0.45 : 0.22);
    };
    const vLine = (x) => {
      this.centralLineLayer.append('line')
        .attr('x1', x).attr('y1', 0).attr('x2', x).attr('y2', H)
        .attr('stroke', '#00aaff')
        .attr('stroke-width', 1)
        .attr('stroke-dasharray', '6,4')
        .attr('opacity', 0.22);
    };

    // ── No components: uniform reference grid ──────────────────────────────
    if (this.components.length === 0) {
      if (this.showHorizontalLine) {
        for (let y = HC; y < H + HC; y += 2 * HC) {
          hLine(y, Math.abs(y - H / 2) < 2);
        }
      }
      if (this.showVerticalLine) {
        for (let x = HC; x < W + HC; x += 2 * HC) vLine(x);
      }
      return;
    }

    const rows = this._detectRows();
    const cols = this._detectCols();

    // ── Horizontal lines (N_rows + 1, plus explicit midline if needed) ─────
    if (this.showHorizontalLine) {
      // Compute all boundary Y values
      const hYs = new Set();
      hYs.add(rows[0] - HC);                              // top boundary
      for (let i = 0; i < rows.length - 1; i++) {
        hYs.add((rows[i] + rows[i + 1]) / 2);             // between rows
      }
      hYs.add(rows[rows.length - 1] + HC);                // bottom boundary

      // Midline = midpoint between topmost and bottommost row
      const midY = rows.length > 1
        ? (rows[0] + rows[rows.length - 1]) / 2
        : null;

      // Add midline explicitly if it isn't already a boundary
      if (midY !== null) hYs.add(midY);

      [...hYs].sort((a, b) => a - b).forEach(y => {
        hLine(y, midY !== null && Math.abs(y - midY) < 1);
      });

      // Label
      if (midY !== null) {
        this.centralLineLayer.append('text')
          .attr('x', W - 145).attr('y', midY - 8)
          .attr('fill', '#00ddff').attr('font-size', '11px').attr('opacity', 0.6)
          .text('── Main / Aux ──');
      }
    }

    // ── Vertical lines (one per stage column at right boundary) ────────────
    if (this.showVerticalLine) {
      cols.forEach(cx => vLine(cx + HC)); // right edge of each stage
    }

    // Crosshair dot at midline × first-stage right boundary
    if (this.showHorizontalLine && this.showVerticalLine
        && rows.length > 1 && cols.length > 0) {
      const midY = (rows[0] + rows[rows.length - 1]) / 2;
      this.centralLineLayer.append('circle')
        .attr('cx', cols[0] + HC).attr('cy', midY)
        .attr('r', 4).attr('fill', '#00ddff').attr('opacity', 0.55);
    }
  }
  
  toggleHorizontalLine() {
    this.showHorizontalLine = !this.showHorizontalLine;
    this.drawGuideLines();
    
    // Update button state
    const btn = document.getElementById('toggle_horizontal_line');
    if (btn) {
      btn.style.backgroundColor = this.showHorizontalLine ? '#28a745' : '';
      btn.style.color = this.showHorizontalLine ? '#fff' : '';
    }
    
    console.log('Horizontal line:', this.showHorizontalLine ? 'ON' : 'OFF');
  }
  
  toggleVerticalLine() {
    this.showVerticalLine = !this.showVerticalLine;
    this.drawGuideLines();
    
    // Update button state
    const btn = document.getElementById('toggle_vertical_line');
    if (btn) {
      btn.style.backgroundColor = this.showVerticalLine ? '#28a745' : '';
      btn.style.color = this.showVerticalLine ? '#fff' : '';
    }
    
    console.log('Vertical line:', this.showVerticalLine ? 'ON' : 'OFF');
  }
  
  createPalette() {
    console.log('Creating component palette...');
    
    // In multi-canvas mode, don't create individual palettes
    // Check if shared palette already exists
    if (document.getElementById('shared_component_palette')) {
      console.log('Shared palette detected, skipping individual palette creation');
      return;
    }
    
    // Check if canvas layout is set (indicates multi-canvas initialization)
    if (window.canvasLayout && window.canvasLayout !== "1x1") {
      console.log(`Multi-canvas mode (${window.canvasLayout}) detected, skipping individual palette creation`);
      return;
    }
    
    // Also check array length as fallback
    if (window.paCanvases && window.paCanvases.length > 1) {
      console.log('Multi-canvas mode detected, skipping individual palette creation');
      return;
    }
    
    const palette = d3.select(`#${this.containerId}`)
      .insert('div', ':first-child')
      .attr('class', 'component-palette')
      .style('position', 'absolute')
      .style('left', '0')
      .style('top', '0')
      .style('width', '60px')
      .style('height', this.height + 'px')
      .style('background', 'rgba(30, 30, 30, 0.95)')
      .style('border-right', '2px solid #ff7f11')
      .style('display', 'flex')
      .style('flex-direction', 'column')
      .style('align-items', 'center')
      .style('padding', '10px 0')
      .style('gap', '15px')
      .style('transition', 'width 0.3s')
      .style('z-index', '1100')  // Higher than sidebars to stay visible
      .on('mouseenter', function() {
        d3.select(this).style('width', '180px');
        d3.selectAll('.palette-label').style('display', 'block');
      })
      .on('mouseleave', function() {
        d3.select(this).style('width', '60px');
        d3.selectAll('.palette-label').style('display', 'none');
      });
    
    const components = [
      { type: 'transistor', icon: '▲', label: 'Transistor', color: '#00bfff', useIcon: true },
      { type: 'matching', icon: 'M', label: 'Matching', color: '#00ff88', useIcon: false },
      { type: 'splitter', icon: 'Y', label: 'Splitter', color: '#ffaa00', useIcon: false },
      { type: 'combiner', icon: 'Ψ', label: 'Combiner', color: '#ff00aa', useIcon: false },
      { type: 'termination', icon: '⏚', label: 'Termination', color: '#888888', useIcon: true },
      { type: 'wire', icon: '━', label: 'Wire Mode', color: '#ff7f11', isAction: true, useIcon: true }
    ];
    
    console.log('Adding components to palette:', components.length);
    
    components.forEach(comp => {
      const item = palette.append('div')
        .attr('class', comp.isAction ? 'palette-action' : 'palette-item')
        .attr('data-type', comp.type)
        .style('display', 'flex')
        .style('align-items', 'center')
        .style('gap', '10px')
        .style('cursor', 'pointer')
        .style('padding', '10px')
        .style('border-radius', '5px')
        .style('transition', 'background 0.2s')
        .on('mouseenter', function() {
          d3.select(this).style('background', 'rgba(255, 127, 17, 0.2)');
        })
        .on('mouseleave', function() {
          d3.select(this).style('background', 'transparent');
        })
        .on('click', () => {
          if (comp.isAction) {
            if (comp.type === 'wire') {
              this.toggleWireMode();
            }
          } else {
            this.addComponentFromPalette(comp.type);
          }
        });
      
      // Create SVG icon for matching, splitter, combiner (same as shared palette)
      if (!comp.useIcon && (comp.type === 'matching' || comp.type === 'splitter' || comp.type === 'combiner')) {
        const iconSvg = item.append('svg')
          .attr('width', 30)
          .attr('height', 30)
          .style('overflow', 'visible');
        
        const g = iconSvg.append('g')
          .attr('transform', 'translate(15, 15)');
        
        if (comp.type === 'matching') {
          // Matching: Small transformer/inductor symbol
          g.append('path')
            .attr('d', 'M-10,0 L-5,0')
            .attr('stroke', comp.color)
            .attr('stroke-width', 2)
            .attr('fill', 'none');
          
          // Coil/transformer
          g.append('path')
            .attr('d', 'M-5,0 Q-3,-5 0,-5 Q3,-5 5,0 Q3,5 0,5 Q-3,5 -5,0')
            .attr('stroke', comp.color)
            .attr('stroke-width', 2)
            .attr('fill', 'none');
          
          g.append('path')
            .attr('d', 'M5,0 L10,0')
            .attr('stroke', comp.color)
            .attr('stroke-width', 2)
            .attr('fill', 'none');
        } else if (comp.type === 'splitter') {
          // Splitter: Y-junction (input on left, outputs on right)
          g.append('line')
            .attr('x1', -10).attr('y1', 0)
            .attr('x2', 0).attr('y2', 0)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
          
          g.append('line')
            .attr('x1', 0).attr('y1', 0)
            .attr('x2', 10).attr('y2', -8)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
          
          g.append('line')
            .attr('x1', 0).attr('y1', 0)
            .attr('x2', 10).attr('y2', 8)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
        } else if (comp.type === 'combiner') {
          // Combiner: Inverted Y-junction (inputs on left, output on right)
          g.append('line')
            .attr('x1', -10).attr('y1', -8)
            .attr('x2', 0).attr('y2', 0)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
          
          g.append('line')
            .attr('x1', -10).attr('y1', 8)
            .attr('x2', 0).attr('y2', 0)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
          
          g.append('line')
            .attr('x1', 0).attr('y1', 0)
            .attr('x2', 10).attr('y2', 0)
            .attr('stroke', comp.color)
            .attr('stroke-width', 2);
        }
      } else {
        // Use text icon for transistor, termination, wire
        item.append('div')
          .style('font-size', '24px')
          .style('color', comp.color)
          .text(comp.icon);
      }
      
      item.append('div')
        .attr('class', 'palette-label')
        .style('color', '#fff')
        .style('font-size', '12px')
        .style('display', 'none')
        .text(comp.label);
    });
  }
  
  addComponentFromPalette(type) {
    // Check if canvas is locked
    if (this.locked) {
      console.warn('Canvas is locked! Cannot add components.');
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Canvas is locked. Press Ctrl+L to unlock.',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    // Calculate staggered default positions based on component type
    // This prevents all components from appearing on top of each other
    const centerX = this.width / 2;
    const centerY = this.height / 2;
    const padding = 80; // Distance from center for each type
    
    let x, y;
    switch(type) {
      case 'transistor':
        // Center-left position
        x = centerX - padding;
        y = centerY;
        break;
      case 'matching':
        // Top-center position
        x = centerX;
        y = centerY - padding;
        break;
      case 'splitter':
        // Left-top position
        x = centerX - padding * 1.5;
        y = centerY - padding * 0.8;
        break;
      case 'combiner':
        // Right-center position
        x = centerX + padding;
        y = centerY;
        break;
      case 'termination':
        // Bottom-right position
        x = centerX + padding;
        y = centerY + padding;
        break;
      default:
        // Default center position
        x = centerX;
        y = centerY;
    }
    
    // For matching, splitter, and combiner: prompt for sub-type
    if (type === 'matching') {
      const matchTypes = ['generic', 'L', 'Pi', 'T', 'Transformer', 'TL-stub'];
      const matchLabels = {
        'generic': 'Generic (Double TL)',
        'L': 'L-section',
        'Pi': 'Pi Network',
        'T': 'T Network',
        'Transformer': 'Transformer (λ/4)',
        'TL-stub': 'TL with Stub'
      };
      
      let selection = prompt(
        'Select Matching Network Type:\n\n' +
        '1) Generic (Double TL)\n' +
        '2) L-section\n' +
        '3) Pi Network\n' +
        '4) T Network\n' +
        '5) Transformer (λ/4)\n' +
        '6) TL with Stub\n\n' +
        'Enter number (1-6):', '1'
      );
      
      if (selection === null) return; // User cancelled
      const index = parseInt(selection) - 1;
      if (index >= 0 && index < matchTypes.length) {
        this.addComponent(type, x, y, { matchType: matchTypes[index] });
      } else {
        this.addComponent(type, x, y, { matchType: 'generic' });
      }
      
    } else if (type === 'splitter') {
      const splitterTypes = ['Wilkinson', 'Hybrid', '90-degree', 'Rat-race', 'Asymmetric'];
      
      let selection = prompt(
        'Select Splitter Type:\n\n' +
        '1) Wilkinson (Equal power)\n' +
        '2) Hybrid (90° phase)\n' +
        '3) 90-degree\n' +
        '4) Rat-race\n' +
        '5) Asymmetric (2:1 ratio)\n\n' +
        'Enter number (1-5):', '1'
      );
      
      if (selection === null) return; // User cancelled
      const index = parseInt(selection) - 1;
      if (index >= 0 && index < splitterTypes.length) {
        this.addComponent(type, x, y, { type: splitterTypes[index] });
      } else {
        this.addComponent(type, x, y, { type: 'Wilkinson' });
      }
      
    } else if (type === 'combiner') {
      const combinerTypes = ['Doherty', 'Wilkinson', 'Hybrid', 'Corporate', 'Inverted-Doherty', 'Symmetric-Doherty'];
      
      let selection = prompt(
        'Select Combiner Type:\n\n' +
        '1) Doherty (Load modulation)\n' +
        '2) Wilkinson (Equal power)\n' +
        '3) Hybrid (90° phase)\n' +
        '4) Corporate\n' +
        '5) Inverted Doherty\n' +
        '6) Symmetric Doherty\n\n' +
        'Enter number (1-6):', '1'
      );
      
      if (selection === null) return; // User cancelled
      const index = parseInt(selection) - 1;
      if (index >= 0 && index < combinerTypes.length) {
        this.addComponent(type, x, y, { type: combinerTypes[index] });
      } else {
        this.addComponent(type, x, y, { type: 'Doherty' });
      }
      
    } else {
      // For other types (transistor, blank), add normally
      this.addComponent(type, x, y);
    }
  }
  
  addComponent(type, x, y, properties = {}) {
    console.log(`=== addComponent called ===`);
    console.log('Type:', type, 'Position:', x, y, 'Properties:', properties);
    
    // Check if canvas is locked (skip check for template loading)
    if (this.locked && !this._loadingTemplate) {
      console.warn('Canvas is locked! Cannot add components.');
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Canvas is locked. Press Ctrl+L to unlock.',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const component = {
      id: this.nextId++,
      type: type,
      x: x,
      y: y,
      rotation: 0,
      flipH: false,
      flipV: false,
      textOffset: { x: 0, y: 0 },  // For text repositioning feature
      properties: this.getDefaultProperties(type, properties)
    };
    
    this.components.push(component);
    
    // Render the component
    this.renderComponent(component);
    
    // Hide instruction text when first component is added
    if (this.instructionText && this.components.length > 0) {
      this.instructionText.style('display', 'none');
    }
    
    // Redraw power columns if enabled
    if (this.showPowerDisplay) {
      this.drawPowerColumns();
    }
    
    // Save to history
    this.saveHistory();
    
    // Notify Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
    }
    
    console.log('Component added:', type, '(ID:', component.id + ') Total:', this.components.length);
    
    return component;
  }
  
  getDefaultProperties(type, overrides = {}) {
    const defaults = {
      transistor: {
        label: 'PA',
        technology: 'GaN',
        biasClass: 'AB',
        pout: 43,
        p1db: 43,
        gain: 15,
        pae: 50,
        vdd: 28,
        rth: 2.5
      },
      matching: {
        label: 'Match',
        type: 'L-section',
        matchType: overrides.matchType || 'generic',
        loss: 0.5,
        z_in: 50,
        z_out: 50,
        bandwidth: 10,
        display: ['label', 'loss']
      },
      splitter: {
        label: 'Splitter',
        type: overrides.type || 'Wilkinson',
        loss: 0.3,
        isolation: 20,
        split_ratio: 0,
        display: ['label', 'loss']
      },
      combiner: {
        label: 'Combiner',
        type: overrides.type || 'Wilkinson',
        loss: 0.3,
        isolation: 20,
        load_modulation: false,
        modulation_factor: 2.0,
        display: ['label', 'loss']
      },
      termination: {
        label: 'Load',
        impedance: 50,
        power_rating: 10,
        vswr: 1.0,
        display: ['label', 'impedance']
      }
    };
    
    return { ...defaults[type], ...overrides };
  }
  
  renderComponent(component) {
    const group = this.componentsLayer.append('g')
      .attr('class', `component component-${component.type}`)
      .attr('data-id', component.id);
    
    // Apply rotation and flip transformations
    let transform = `translate(${component.x}, ${component.y})`;
    
    if (component.rotation || component.flipH || component.flipV) {
      // Add rotation
      if (component.rotation) {
        transform += ` rotate(${component.rotation})`;
      }
      
      // Add flipping
      let scaleX = component.flipH ? -1 : 1;
      let scaleY = component.flipV ? -1 : 1;
      if (scaleX !== 1 || scaleY !== 1) {
        transform += ` scale(${scaleX}, ${scaleY})`;
      }
    }
    
    group.attr('transform', transform);
    
    // Render based on type
    switch (component.type) {
      case 'transistor':
        this.renderTransistor(group, component);
        break;
      case 'matching':
        this.renderMatching(group, component);
        break;
      case 'splitter':
        this.renderSplitter(group, component);
        break;
      case 'combiner':
        this.renderCombiner(group, component);
        break;
      case 'termination':
        this.renderTermination(group, component);
        break;
      default:
        console.warn('Unknown component type:', component.type);
    }
    
    // Store component reference in DOM for drag behavior
    group.datum(component);
    
    // Add drag behavior using the initialized drag handler
    if (this.drag) {
      group.call(this.drag);
    }
    
    // Add click behavior (with Ctrl+click for multi-select)
    group.on('click', (event) => {
      event.stopPropagation();
      
      // CRITICAL: Set this canvas as active when any component is clicked
      if (window.paCanvases && window.paCanvases.length > 1) {
        const canvasIndex = window.paCanvases.findIndex(c => c === this);
        if (canvasIndex >= 0) {
          setActiveCanvas(canvasIndex);
        }
      }
      
      // Ctrl+click (or Cmd+click on Mac) for multi-select
      if (event.ctrlKey || event.metaKey) {
        this.toggleComponentSelection(component);
      } else {
        this.selectComponent(component);
      }
    });
    
    // Add hover behavior for power display
    group.on('mouseenter', (event) => {
      this.showPowerTooltip(component, event);
    });
    
    group.on('mouseleave', () => {
      this.hidePowerTooltip();
    });
  }
  
  renderTransistor(group, component) {
    // Triangle symbol (scaled up 1.5x for better visibility)
    group.append('polygon')
      .attr('points', '0,-30 45,0 0,30')
      .attr('fill', '#00aaff')
      .attr('stroke', '#fff')
      .attr('stroke-width', 3);
    
    // Input port (left) - adjusted for larger size
    const inputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -8)
      .attr('cy', 0)
      .attr('r', 5)
      .attr('fill', '#00ff88')
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 2)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'))
      .on('mouseenter', () => this.onPortHover(inputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(inputPort.node(), false));
    
    // Output port (right) - adjusted for larger size
    const outputPort = group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 53)
      .attr('cy', 0)
      .attr('r', 5)
      .attr('fill', '#ff7f11')
      .attr('stroke', '#ff7f11')
      .attr('stroke-width', 2)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'))
      .on('mouseenter', () => this.onPortHover(outputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(outputPort.node(), false));
    
    // Create a text group for offset positioning
    const textOffset = component.textOffset || { x: 0, y: 0 };
    const textGroup = group.append('g')
      .attr('class', 'component-text-group')
      .attr('transform', `translate(${textOffset.x}, ${textOffset.y})`);
    
    // Label - positioned ABOVE component to avoid overlap
    textGroup.append('text')
      .attr('x', 22)
      .attr('y', -35)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '14px')
      .attr('font-weight', 'bold')
      .text(component.properties.label || 'PA');
    
    // Display technology text in center of triangle
    const technology = component.properties.technology || 'GaN';
    textGroup.append('text')
      .attr('x', 22)
      .attr('y', 5)
      .attr('text-anchor', 'middle')
      .attr('fill', '#ffffff')
      .attr('font-size', '11px')
      .attr('font-weight', 'bold')
      .text(technology);
    
    // Display options
    const display = component.properties.display || ['pout'];
    let yOffset = 50;  // Start below the component
    
    if (display.includes('label')) {
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffffff')
        .attr('font-size', '8px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'PA');
      yOffset += 10;
    }
    
    if (display.includes('biasClass')) {
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#aaddff')
        .attr('font-size', '8px')
        .text(`Class ${component.properties.biasClass || 'AB'}`);
      yOffset += 10;
    }
    
    if (display.includes('gain')) {
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#88ff88')
        .attr('font-size', '8px')
        .text(`Gain: ${component.properties.gain || 10} dB`);
      yOffset += 10;
    }
    
    if (display.includes('pae')) {
      // Check if dual operating point efficiency data is available
      const hasDualOp = component.properties.pae_pavg !== undefined && component.properties.pae_p3db !== undefined;
      
      if (hasDualOp) {
        // Display efficiency at both operating points
        textGroup.append('text')
          .attr('x', 15)
          .attr('y', yOffset)
          .attr('text-anchor', 'middle')
          .attr('fill', '#ffdd44')
          .attr('font-size', '8px')
          .attr('font-weight', 'bold')
          .text(`PAE@Pavg: ${component.properties.pae_pavg}%`);
        yOffset += 10;
        
        textGroup.append('text')
          .attr('x', 15)
          .attr('y', yOffset)
          .attr('text-anchor', 'middle')
          .attr('fill', '#ffee88')
          .attr('font-size', '8px')
          .text(`PAE@P3dB: ${component.properties.pae_p3db}%`);
        yOffset += 10;
      } else {
        // Legacy single efficiency display
        textGroup.append('text')
          .attr('x', 15)
          .attr('y', yOffset)
          .attr('text-anchor', 'middle')
          .attr('fill', '#ffdd44')
          .attr('font-size', '8px')
          .text(`PAE: ${component.properties.pae || 50}%`);
        yOffset += 10;
      }
    }
    
// ===== DUAL OPERATING POINT DISPLAY =====
      // Show Pin at BOTH Pavg and P3dB if available
      if (display.includes('pin')) {
        // Check if dual operating point data is available
        const hasDualOp = component.properties.pin_pavg !== undefined && component.properties.pin_p3db !== undefined;
        
        if (hasDualOp) {
          // Display both operating points
          const pinPavgText = this.formatPower(component.properties.pin_pavg, this.powerUnit);
          const pinP3dbText = this.formatPower(component.properties.pin_p3db, this.powerUnit);
          
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#66ccff')
            .attr('font-size', '8px')
            .attr('font-weight', 'bold')
            .text(`Pin@Pavg: ${pinPavgText}`);
          yOffset += 10;
          
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#88ddff')
            .attr('font-size', '8px')
            .text(`Pin@P3dB: ${pinP3dbText}`);
          yOffset += 10;
        } else {
          // Legacy single operating point display
          const pinValue = component.properties.pin || 30;
          const pinText = this.formatPower(pinValue, this.powerUnit);
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#66ccff')
            .attr('font-size', '8px')
            .text(`Pin: ${pinText}`);
          yOffset += 10;
        }
      }
      
      // Show Pout at BOTH Pavg and P3dB if available
      if (display.includes('pout') || display.includes('p3db')) {
        // Check if dual operating point data is available
        const hasDualOp = component.properties.pout_pavg !== undefined && component.properties.pout_p3db !== undefined;
        
        if (hasDualOp) {
          // Display both operating points
          const poutPavgText = this.formatPower(component.properties.pout_pavg, this.powerUnit);
          const poutP3dbText = this.formatPower(component.properties.pout_p3db, this.powerUnit);
          
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#ff88ff')
            .attr('font-size', '8px')
            .attr('font-weight', 'bold')
            .text(`Pout@Pavg: ${poutPavgText}`);
          yOffset += 10;
          
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#ffaaff')
            .attr('font-size', '8px')
            .text(`Pout@P3dB: ${poutP3dbText}`);
          yOffset += 10;
        } else {
          // Legacy single operating point display
          const p3dbValue = component.properties.p3db || component.properties.pout || 40;
          const p3dbText = this.formatPower(p3dbValue, this.powerUnit);
          textGroup.append('text')
            .attr('x', 15)
            .attr('y', yOffset)
            .attr('text-anchor', 'middle')
            .attr('fill', '#ff88ff')
            .attr('font-size', '8px')
            .text(`Pout(P3dB): ${p3dbText}`);
          yOffset += 10;
        }
      }
      
      // P1dB must always be below P3dB (1dB compression point)
      if (display.includes('p1db')) {
        const p3dbValue = component.properties.p3db || component.properties.pout || 40;
        // P1dB should be 2dB below P3dB for solid state devices (typical)
        const p1dbValue = component.properties.p1db || (p3dbValue - 2);
        
        // Sanity check: P1dB must be less than P3dB
        const validP1db = Math.min(p1dbValue, p3dbValue - 0.5);
        
        // Debug logging if P1dB validation fails
        if (p1dbValue > p3dbValue) {
          console.warn(`[Display] ${component.label}: P1dB (${p1dbValue.toFixed(2)}) > P3dB (${p3dbValue.toFixed(2)}) - correcting to ${validP1db.toFixed(2)}`);
        }
        
        const p1dbText = this.formatPower(validP1db, this.powerUnit);
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffaa00')
        .attr('font-size', '8px')
        .text(`P1dB: ${p1dbText}`);
      yOffset += 10;
    }
    
    if (display.includes('vdd')) {
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff6666')
        .attr('font-size', '8px')
        .text(`VDD: ${component.properties.vdd || 28}V`);
      yOffset += 10;
    }
    
    if (display.includes('freq')) {
      textGroup.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#cc88ff')
        .attr('font-size', '8px')
        .text(`f: ${component.properties.freq || 2.6} GHz`);
      yOffset += 10;
    }
    
    // Zin / Zout impedance annotations (shown when properties are explicitly set)
    const zIn  = component.properties.z_in;
    const zOut = component.properties.z_out;
    if (zIn !== undefined && zIn !== null) {
      group.append('text')
        .attr('x', -8).attr('y', -38)
        .attr('text-anchor', 'end')
        .attr('fill', 'rgba(100,220,255,0.9)').attr('font-size', '8px')
        .text('Zin:' + zIn + '\u03a9');
    }
    if (zOut !== undefined && zOut !== null) {
      group.append('text')
        .attr('x', 55).attr('y', -38)
        .attr('text-anchor', 'start')
        .attr('fill', 'rgba(255,160,100,0.9)').attr('font-size', '8px')
        .text('Zout:' + zOut + '\u03a9');
    }
  }
  
  renderMatching(group, component) {
    // Get matching type
    const matchType = component.properties.matchType || 'generic';
    
    // Draw based on type  
    if (matchType === 'L') {
      // L-section matching: series-shunt
      // Box container
      group.append('rect')
        .attr('x', -25)
        .attr('y', -12)
        .attr('width', 50)
        .attr('height', 24)
        .attr('fill', 'none')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Series inductor (horizontal line with coil)
      group.append('path')
        .attr('d', 'M -15,-0 Q -10,-5 -5,0 Q 0,5 5,0')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
      
      // Shunt capacitor (vertical line with plates)
      group.append('line')
        .attr('x1', 5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      group.append('line')
        .attr('x1', 2)
        .attr('y1', 8)
        .attr('x2', 8)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
        
    } else if (matchType === 'Pi') {
      // Pi matching: shunt-series-shunt
      group.append('rect')
        .attr('x', -25)
        .attr('y', -12)
        .attr('width', 50)
        .attr('height', 24)
        .attr('fill', 'none')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Left shunt cap
      group.append('line')
        .attr('x1', -10)
        .attr('y1', 0)
        .attr('x2', -10)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      group.append('line')
        .attr('x1', -13)
        .attr('y1', 8)
        .attr('x2', -7)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Series inductor
      group.append('path')
        .attr('d', 'M -10,0 Q -5,-5 0,0 Q 5,5 10,0')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
      
      // Right shunt cap
      group.append('line')
        .attr('x1', 10)
        .attr('y1', 0)
        .attr('x2', 10)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      group.append('line')
        .attr('x1', 7)
        .attr('y1', 8)
        .attr('x2', 13)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
        
    } else if (matchType === 'T') {
      // T matching: series-shunt-series
      group.append('rect')
        .attr('x', -25)
        .attr('y', -12)
        .attr('width', 50)
        .attr('height', 24)
        .attr('fill', 'none')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Left series inductor
      group.append('path')
        .attr('d', 'M -15,0 Q -12,-4 -9,0')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
      
      // Center shunt cap
      group.append('line')
        .attr('x1', 0)
        .attr('y1', 0)
        .attr('x2', 0)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      group.append('line')
        .attr('x1', -3)
        .attr('y1', 8)
        .attr('x2', 3)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Right series inductor
      group.append('path')
        .attr('d', 'M 9,0 Q 12,-4 15,0')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
        
    } else if (matchType === 'Transformer') {
      // Transformer symbol
      group.append('rect')
        .attr('x', -25)
        .attr('y', -12)
        .attr('width', 50)
        .attr('height', 24)
        .attr('fill', 'none')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Left coil
      group.append('path')
        .attr('d', 'M -10,-6 Q -10,-2 -8,0 Q -10,2 -10,6')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
      
      // Right coil
      group.append('path')
        .attr('d', 'M 10,-6 Q 10,-2 8,0 Q 10,2 10,6')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2)
        .attr('fill', 'none');
      
      // Core
      group.append('line')
        .attr('x1', -2)
        .attr('y1', -8)
        .attr('x2', -2)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1);
      group.append('line')
        .attr('x1', 2)
        .attr('y1', -8)
        .attr('x2', 2)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1);
        
    } else if (matchType === 'TL-stub') {
      // Transmission line stub
      group.append('rect')
        .attr('x', -25)
        .attr('y', -12)
        .attr('width', 50)
        .attr('height', 24)
        .attr('fill', 'none')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 2);
      
      // Main transmission line
      group.append('line')
        .attr('x1', -15)
        .attr('y1', 0)
        .attr('x2', 15)
        .attr('y2', 0)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 3);
      
      // Stub (perpendicular line)
      group.append('line')
        .attr('x1', 0)
        .attr('y1', 0)
        .attr('x2', 0)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 3);
      group.append('line')
        .attr('x1', -3)
        .attr('y1', 8)
        .attr('x2', 3)
        .attr('y2', 8)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 3);
        
    } else {
      // Generic matching (double transmission line - original design)
      group.append('line')
        .attr('x1', -20)
        .attr('y1', 0)
        .attr('x2', 20)
        .attr('y2', 0)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 4);
      
      group.append('line')
        .attr('x1', -20)
        .attr('y1', -3)
        .attr('x2', 20)
        .attr('y2', -3)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1);
      
      group.append('line')
        .attr('x1', -20)
        .attr('y1', 3)
        .attr('x2', 20)
        .attr('y2', 3)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1);
    }
    
    // Input port
    const matchInputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -25)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#00ff88')
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'))
      .on('mouseenter', () => this.onPortHover(matchInputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(matchInputPort.node(), false));
    
    // Output port
    const matchOutputPort = group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 25)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#ff7f11')
      .attr('stroke', '#ff7f11')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'))
      .on('mouseenter', () => this.onPortHover(matchOutputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(matchOutputPort.node(), false));
    
    // Labels - configurable display
    const display = component.properties.display || ['label', 'loss'];
    
    // Position label ABOVE the component to avoid overlap
    if (display.includes('label')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', -25)  // Above the component
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '12px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'Match');
    }
    
    // Property text below the component with proper spacing
    let yOffset = 20;
    
    if (display.includes('loss')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#88ffaa')
        .attr('font-size', '9px')
        .text(`Loss: ${component.properties.loss || 0.5}dB`);
      yOffset += 11;
    }
    
    if (display.includes('type')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#aaffaa')
        .attr('font-size', '8px')
        .text(matchType);
      yOffset += 10;
    }
    
    if (display.includes('z_in')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#88ddff')
        .attr('font-size', '8px')
        .text(`Zin: ${component.properties.z_in || 50}Ω`);
      yOffset += 10;
    }
    
    if (display.includes('z_out')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff88dd')
        .attr('font-size', '8px')
        .text(`Zout: ${component.properties.z_out || 50}Ω`);
      yOffset += 10;
    }
    
    if (display.includes('bandwidth')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffdd88')
        .attr('font-size', '8px')
        .text(`BW: ${component.properties.bandwidth || 10}%`);
      yOffset += 10;
    }
  }
  
  renderSplitter(group, component) {
    // Enhanced industry-standard splitter representation with 2-way or 3-way support
    const portCount = component.properties.portCount || 2;
    
    // Background box to show it's a packaged component
    group.append('rect')
      .attr('x', -25)
      .attr('y', portCount === 3 ? -30 : -20)
      .attr('width', 50)
      .attr('height', portCount === 3 ? 60 : 40)
      .attr('fill', '#1a1a1a')
      .attr('stroke', '#ffaa00')
      .attr('stroke-width', 2)
      .attr('rx', 4);
    
    // Input line
    group.append('line')
      .attr('x1', -25)
      .attr('y1', 0)
      .attr('x2', -5)
      .attr('y2', 0)
      .attr('stroke', '#ffaa00')
      .attr('stroke-width', 3);
    
    // Junction node
    group.append('circle')
      .attr('cx', -5)
      .attr('cy', 0)
      .attr('r', 3)
      .attr('fill', '#ffaa00');
    
    if (portCount === 3) {
      // 3-way splitter configuration
      // Y-junction with three branches
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', -20)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', 20)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 3);
      
      // Output λ/4 transformers (shown as thick segments)
      group.append('line')
        .attr('x1', 5)
        .attr('y1', -20)
        .attr('x2', 25)
        .attr('y2', -20)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', 5)
        .attr('y1', 0)
        .attr('x2', 25)
        .attr('y2', 0)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', 5)
        .attr('y1', 20)
        .attr('x2', 25)
        .attr('y2', 20)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      // Isolation resistor indicators (between outputs)
      group.append('line')
        .attr('x1', 15)
        .attr('y1', -20)
        .attr('x2', 15)
        .attr('y2', 0)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
      
      group.append('line')
        .attr('x1', 15)
        .attr('y1', 0)
        .attr('x2', 15)
        .attr('y2', 20)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
      
    } else {
      // 2-way splitter configuration (original)
      // Y-junction with quarter-wave transformers
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', -10)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', 10)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 3);
      
      // Output λ/4 transformers (shown as thick segments)
      group.append('line')
        .attr('x1', 5)
        .attr('y1', -10)
        .attr('x2', 25)
        .attr('y2', -10)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', 5)
        .attr('y1', 10)
        .attr('x2', 25)
        .attr('y2', 10)
        .attr('stroke', '#ffaa00')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      // Isolation resistor indicator (line between outputs)
      group.append('line')
        .attr('x1', 15)
        .attr('y1', -10)
        .attr('x2', 15)
        .attr('y2', 10)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
    }
    
    // Input port
    const splitInputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -28)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#00ff88')
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'))
      .on('mouseenter', () => this.onPortHover(splitInputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(splitInputPort.node(), false));
    
    // Output ports - create based on port count
    if (portCount === 3) {
      const splitOutput1 = group.append('circle')
        .attr('class', 'port port-output')
        .attr('data-port-id', 'output1')
        .attr('cx', 28)
        .attr('cy', -20)
        .attr('r', 4)
        .attr('fill', '#ff7f11')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'output1'))
        .on('mouseenter', () => this.onPortHover(splitOutput1.node(), true))
        .on('mouseleave', () => this.onPortHover(splitOutput1.node(), false));
      
      const splitOutput2 = group.append('circle')
        .attr('class', 'port port-output')
        .attr('data-port-id', 'output2')
        .attr('cx', 28)
        .attr('cy', 0)
        .attr('r', 4)
        .attr('fill', '#ff7f11')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'output2'))
        .on('mouseenter', () => this.onPortHover(splitOutput2.node(), true))
        .on('mouseleave', () => this.onPortHover(splitOutput2.node(), false));
      
      const splitOutput3 = group.append('circle')
        .attr('class', 'port port-output')
        .attr('data-port-id', 'output3')
        .attr('cx', 28)
        .attr('cy', 20)
        .attr('r', 4)
        .attr('fill', '#ff7f11')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'output3'))
        .on('mouseenter', () => this.onPortHover(splitOutput3.node(), true))
        .on('mouseleave', () => this.onPortHover(splitOutput3.node(), false));
      
    } else {
      const splitOutput1 = group.append('circle')
        .attr('class', 'port port-output')
        .attr('data-port-id', 'output1')
        .attr('cx', 28)
        .attr('cy', -10)
        .attr('r', 4)
        .attr('fill', '#ff7f11')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'output1'))
        .on('mouseenter', () => this.onPortHover(splitOutput1.node(), true))
        .on('mouseleave', () => this.onPortHover(splitOutput1.node(), false));
      
      const splitOutput2 = group.append('circle')
        .attr('class', 'port port-output')
        .attr('data-port-id', 'output2')
        .attr('cx', 28)
        .attr('cy', 10)
        .attr('r', 4)
        .attr('fill', '#ff7f11')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'output2'))
        .on('mouseenter', () => this.onPortHover(splitOutput2.node(), true))
        .on('mouseleave', () => this.onPortHover(splitOutput2.node(), false));
    }
    
    // Labels - configurable display
    const display = component.properties.display || ['label', 'loss'];
    
    // Position label ABOVE the component to avoid overlap
    if (display.includes('label')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', -35)  // Above the splitter
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '11px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'Split');
    }
    
    // Property text below the component with proper spacing
    let yOffset = 32;
    
    if (display.includes('loss')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffcc88')
        .attr('font-size', '8px')
        .text(`${component.properties.loss || 0.3}dB`);
      yOffset += 10;
    }
    
    if (display.includes('type')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffddaa')
        .attr('font-size', '7px')
        .text(component.properties.type || 'Wilkinson');
      yOffset += 10;
    }
    
    if (display.includes('isolation')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff6666')
        .attr('font-size', '8px')
        .text(`Iso: ${component.properties.isolation || 20}dB`);
      yOffset += 10;
    }
    
    if (display.includes('split_ratio')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#88aaff')
        .attr('font-size', '8px')
        .text(`Ratio: ${component.properties.split_ratio || 0}dB`);
      yOffset += 10;
    }
  }
  
  renderCombiner(group, component) {
    // Enhanced industry-standard combiner representation (mirror of splitter) with 2-way or 3-way support
    const portCount = component.properties.portCount || 2;
    
    // Background box to show it's a packaged component
    group.append('rect')
      .attr('x', -25)
      .attr('y', portCount === 3 ? -30 : -20)
      .attr('width', 50)
      .attr('height', portCount === 3 ? 60 : 40)
      .attr('fill', '#1a1a1a')
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 2)
      .attr('rx', 4);
    
    if (portCount === 3) {
      // 3-way combiner configuration
      // Input λ/4 transformers (shown as thick segments)
      group.append('line')
        .attr('x1', -25)
        .attr('y1', -20)
        .attr('x2', -5)
        .attr('y2', -20)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', -25)
        .attr('y1', 0)
        .attr('x2', -5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', -25)
        .attr('y1', 20)
        .attr('x2', -5)
        .attr('y2', 20)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      // Y-junction convergence (three branches to center)
      group.append('line')
        .attr('x1', -5)
        .attr('y1', -20)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 0)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 20)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 3);
      
      // Isolation resistor indicators (between inputs)
      group.append('line')
        .attr('x1', -15)
        .attr('y1', -20)
        .attr('x2', -15)
        .attr('y2', 0)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
      
      group.append('line')
        .attr('x1', -15)
        .attr('y1', 0)
        .attr('x2', -15)
        .attr('y2', 20)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
      
    } else {
      // 2-way combiner configuration (original)
      // Input λ/4 transformers (shown as thick segments)
      group.append('line')
        .attr('x1', -25)
        .attr('y1', -10)
        .attr('x2', -5)
        .attr('y2', -10)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      group.append('line')
        .attr('x1', -25)
        .attr('y1', 10)
        .attr('x2', -5)
        .attr('y2', 10)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 4)
        .style('opacity', 0.8);
      
      // Y-junction convergence
      group.append('line')
        .attr('x1', -5)
        .attr('y1', -10)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 3);
      
      group.append('line')
        .attr('x1', -5)
        .attr('y1', 10)
        .attr('x2', 5)
        .attr('y2', 0)
        .attr('stroke', '#ff00aa')
        .attr('stroke-width', 3);
      
      // Isolation resistor indicator (line between inputs)
      group.append('line')
        .attr('x1', -15)
        .attr('y1', -10)
        .attr('x2', -15)
        .attr('y2', 10)
        .attr('stroke', '#ff6666')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '2,2')
        .style('opacity', 0.6);
    }
    
    // Output line
    group.append('line')
      .attr('x1', 5)
      .attr('y1', 0)
      .attr('x2', 25)
      .attr('y2', 0)
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 3);
    
    // Junction node
    group.append('circle')
      .attr('cx', 5)
      .attr('cy', 0)
      .attr('r', 3)
      .attr('fill', '#ff00aa');
    
    // Input ports - create based on port count
    if (portCount === 3) {
      const combInput1 = group.append('circle')
        .attr('class', 'port port-input')
        .attr('data-port-id', 'input1')
        .attr('cx', -28)
        .attr('cy', -20)
        .attr('r', 4)
        .attr('fill', '#00ff88')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'input1'))
        .on('mouseenter', () => this.onPortHover(combInput1.node(), true))
        .on('mouseleave', () => this.onPortHover(combInput1.node(), false));
      
      const combInput2 = group.append('circle')
        .attr('class', 'port port-input')
        .attr('data-port-id', 'input2')
        .attr('cx', -28)
        .attr('cy', 0)
        .attr('r', 4)
        .attr('fill', '#00ff88')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'input2'))
        .on('mouseenter', () => this.onPortHover(combInput2.node(), true))
        .on('mouseleave', () => this.onPortHover(combInput2.node(), false));
      
      const combInput3 = group.append('circle')
        .attr('class', 'port port-input')
        .attr('data-port-id', 'input3')
        .attr('cx', -28)
        .attr('cy', 20)
        .attr('r', 4)
        .attr('fill', '#00ff88')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'input3'))
        .on('mouseenter', () => this.onPortHover(combInput3.node(), true))
        .on('mouseleave', () => this.onPortHover(combInput3.node(), false));
      
    } else {
      const combInput1 = group.append('circle')
        .attr('class', 'port port-input')
        .attr('data-port-id', 'input1')
        .attr('cx', -28)
        .attr('cy', -10)
        .attr('r', 4)
        .attr('fill', '#00ff88')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'input1'))
        .on('mouseenter', () => this.onPortHover(combInput1.node(), true))
        .on('mouseleave', () => this.onPortHover(combInput1.node(), false));
      
      const combInput2 = group.append('circle')
        .attr('class', 'port port-input')
        .attr('data-port-id', 'input2')
        .attr('cx', -28)
        .attr('cy', 10)
        .attr('r', 4)
        .attr('fill', '#00ff88')
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .style('cursor', 'pointer')
        .on('click', (event) => this.handlePortClick(event, component, 'input2'))
        .on('mouseenter', () => this.onPortHover(combInput2.node(), true))
        .on('mouseleave', () => this.onPortHover(combInput2.node(), false));
    }
    
    // Output port
    const combOutputPort = group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 28)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#ff7f11')
      .attr('stroke', '#ff7f11')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'))
      .on('mouseenter', () => this.onPortHover(combOutputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(combOutputPort.node(), false));
    
    // Labels - configurable display
    const display = component.properties.display || ['label', 'loss'];
    
    // Position label ABOVE the component to avoid overlap
    if (display.includes('label')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', -35)  // Above the combiner
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '11px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'Combine');
    }
    
    // Property text below the component with proper spacing
    let yOffset = 32;
    
    if (display.includes('loss')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffaacc')
        .attr('font-size', '8px')
        .text(`${component.properties.loss || 0.3}dB`);
      yOffset += 10;
    }
    
    if (display.includes('type')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffccdd')
        .attr('font-size', '7px')
        .text(component.properties.type || 'Wilkinson');
      yOffset += 10;
    }
    
    if (display.includes('isolation')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff6666')
        .attr('font-size', '8px')
        .text(`Iso: ${component.properties.isolation || 20}dB`);
      yOffset += 10;
    }
    
    if (display.includes('load_modulation')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#aaff88')
        .attr('font-size', '8px')
        .text(`LoadMod: ${component.properties.load_modulation || '6dB'}`);
      yOffset += 10;
    }
  }
  
  renderTermination(group, component) {
    // ADS-style termination: port at centre line (y=0), symbol body hangs below
    const termColor = '#888888';
    const impedance = component.properties.impedance || 50;
    
    // Short vertical line from port (y=0) down to resistor top (y=15)
    group.append('line')
      .attr('x1', 0).attr('y1', 0)
      .attr('x2', 0).attr('y2', 15)
      .attr('stroke', termColor)
      .attr('stroke-width', 3);
    
    // Resistor box (y=15 to y=25)
    const resistorWidth = 20;
    const resistorHeight = 10;
    
    group.append('rect')
      .attr('x', -resistorWidth/2)
      .attr('y', 15)
      .attr('width', resistorWidth)
      .attr('height', resistorHeight)
      .attr('fill', 'none')
      .attr('stroke', termColor)
      .attr('stroke-width', 2)
      .attr('rx', 2);
    
    // Zigzag inside resistor (centred at y=20, peaks at 18/22)
    group.append('path')
      .attr('d', `M${-resistorWidth/2+3},20 L${-resistorWidth/2+7},18 L${-resistorWidth/2+10},22 L${-resistorWidth/2+13},18 L${-resistorWidth/2+17},20`)
      .attr('stroke', termColor)
      .attr('stroke-width', 1.5)
      .attr('fill', 'none');
    
    // Vertical line from resistor bottom (y=25) to ground top (y=35)
    group.append('line')
      .attr('x1', 0).attr('y1', 25)
      .attr('x2', 0).attr('y2', 35)
      .attr('stroke', termColor)
      .attr('stroke-width', 3);
    
    // Ground symbol (three horizontal lines below y=35)
    for (let i = 0; i < 3; i++) {
      const width = 24 - i * 6;
      const y = 35 + i * 4;
      group.append('line')
        .attr('x1', -width/2)
        .attr('y1', y)
        .attr('x2', width/2)
        .attr('y2', y)
        .attr('stroke', termColor)
        .attr('stroke-width', 2);
    }
    
    // Connection port — at centre line (cy=0)
    const inputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('data-port-id', 'input')
      .attr('cx', 0)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#00ff88')
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'))
      .on('mouseenter', () => this.onPortHover(inputPort.node(), true))
      .on('mouseleave', () => this.onPortHover(inputPort.node(), false));
    
    // Labels
    const display = component.properties.display || ['label', 'impedance'];
    
    if (display.includes('label')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', -10)
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '11px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'Term');
    }
    
    // Impedance value inside resistor box
    group.append('text')
      .attr('x', 0)
      .attr('y', 23)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .attr('font-weight', 'bold')
      .text(`${impedance}Ω`);
  }
  
  onDragStart(event, component) {
    // Check if canvas is locked
    if (this.locked) {
      event.sourceEvent.stopPropagation();
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Canvas is locked. Press Ctrl+L to unlock.',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    this.draggedComponent = component;
    d3.select(`.component[data-id="${component.id}"]`)
      .style('opacity', 0.7);
  }
  
  onDrag(event, component) {
    component.x = event.x;
    component.y = event.y;
    
    d3.select(`.component[data-id="${component.id}"]`)
      .attr('transform', `translate(${component.x}, ${component.y})`);
    
    this.updateConnections();
  }
  
  onDragEnd(event, component) {
    this.draggedComponent = null;
    d3.select(`.component[data-id="${component.id}"]`)
      .style('opacity', 1);
    
    // Re-render connections to update their positions
    this.renderConnections();
    
    // Redraw power columns if enabled
    if (this.showPowerDisplay) {
      this.drawPowerColumns();
    }
    
    // Save to history after drag completes
    this.saveHistory();
    
    // Notify Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), { priority: 'event'});
    }
  }
  
  selectComponent(component) {
    // Clear multi-selection and deselect all
    this.selectedComponents = [];
    d3.selectAll('.component').classed('selected', false).classed('multi-selected', false);
    
    // Select new - store the ID, not the full component object
    this.selectedComponent = component.id;
    d3.select(`.component[data-id="${component.id}"]`)
      .classed('selected', true);
    
    // Notify Shiny - send only the component ID, not the full object
    if (window.Shiny) {
      Shiny.setInputValue('lineup_selected_component', component.id, {priority: 'event'});
    }
    
    console.log('Component selected, ID sent:', component.id);
  }
  
  toggleComponentSelection(component) {
    // Check if already in multi-selection
    const index = this.selectedComponents.findIndex(c => c.id === component.id);
    
    if (index >= 0) {
      // Remove from selection
      this.selectedComponents.splice(index, 1);
      d3.select(`.component[data-id="${component.id}"]`)
        .classed('multi-selected', false);
      console.log(`Removed component ${component.id} from multi-selection`);
    } else {
      // Add to selection
      this.selectedComponents.push(component);
      d3.select(`.component[data-id="${component.id}"]`)
        .classed('multi-selected', true);
      console.log(`Added component ${component.id} to multi-selection`);
    }
    
    // Clear single selection when multi-selecting
    this.selectedComponent = null;
    d3.selectAll('.component').classed('selected', false);
    
    console.log(`Multi-selected components: ${this.selectedComponents.length}`);
    
    // Show notification
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: `${this.selectedComponents.length} component(s) selected`,
        type: 'message',
        duration: 1
      });
    }
  }
  
  updateConnections() {
    // Auto-connect nearby components (simplified for now)
    // Full implementation would detect input/output ports
  }
  
  /**
   * Get the actual port position for a component based on type and port type
   * Returns {x, y} in canvas coordinates
   */
  getPortPosition(component, portId = 'output') {
    const baseX = component.x;
    const baseY = component.y;
    
    switch (component.type) {
      case 'termination':
        // Port at centre line — same Y as all other components so wires are horizontal
        return { x: baseX, y: baseY };
      
      case 'transistor':
        return portId === 'input' || portId.startsWith('input')
          ? { x: baseX - 25, y: baseY }    // Input port at left
          : { x: baseX + 35, y: baseY };    // Output port at right
      
      case 'matching':
        return portId === 'input' || portId.startsWith('input')
          ? { x: baseX - 20, y: baseY }    // Input port
          : { x: baseX + 20, y: baseY };    // Output port
      
      case 'splitter':
        if (portId === 'input' || portId.startsWith('input')) {
          return { x: baseX - 20, y: baseY };  // Single input
        } else if (portId === 'output1') {
          return { x: baseX + 20, y: baseY - 15 };  // Upper output
        } else if (portId === 'output2') {
          return { x: baseX + 20, y: baseY + 15 };  // Lower output
        } else {
          // Default to first output for legacy
          return { x: baseX + 20, y: baseY - 15 };
        }
      
      case 'combiner':
        if (portId === 'input1') {
          return { x: baseX - 20, y: baseY - 15 };  // Upper input
        } else if (portId === 'input2') {
          return { x: baseX - 20, y: baseY + 15 };  // Lower input
        } else if (portId === 'input' || portId.startsWith('input')) {
          // Default to first input for legacy
          return { x: baseX - 20, y: baseY - 15 };
        } else {
          return { x: baseX + 20, y: baseY };    // Single output
        }
      
      default:
        console.warn('Unknown component type:', component.type);
        return { x: baseX, y: baseY };
    }
  }
  
  loadPreset(presetName) {
    console.log('=== loadPreset called ===');
    console.log('Preset name:', presetName);
    console.log('Canvas initialized?', !!this.svg);
    
    this.clear();
    
    switch(presetName) {
      case 'single_doherty':
        console.log('Loading Single Driver Doherty...');
        this.createSingleDriverDoherty();
        break;
      case 'dual_doherty':
        console.log('Loading Dual Driver Doherty...');
        this.createDualDriverDoherty();
        break;
      case 'conventional_doherty':
        console.log('Loading Conventional Doherty...');
        this.createConventionalDoherty();
        break;
      case 'inverted_doherty':
        console.log('Loading Inverted Doherty...');
        this.createInvertedDoherty();
        break;
      case 'symmetric_doherty':
        console.log('Loading Symmetric Doherty...');
        this.createSymmetricDoherty();
        break;
      case 'asymmetric_doherty':
        console.log('Loading Asymmetric Doherty...');
        this.createAsymmetricDoherty();
        break;
      case 'envelope_tracking_doherty':
        console.log('Loading Envelope Tracking Doherty...');
        this.createEnvelopeTrackingDoherty();
        break;
      case '3way_symmetric_doherty':
        console.log('Loading 3-Way Symmetric Doherty...');
        this.create3WaySymmetricDoherty();
        break;
      case '3way_asymmetric_doherty':
        console.log('Loading 3-Way Asymmetric Doherty...');
        this.create3WayAsymmetricDoherty();
        break;
      case 'triple_stage':
        console.log('Loading Triple Stage...');
        this.createTripleStage();
        break;
      default:
        console.warn('Unknown preset:', presetName);
    }
    
    console.log('=== loadPreset complete ===');
    console.log('Total components after preset:', this.components.length);
    if (this.svg) this.drawPaGroupBoxes();
  }
  
  createSingleDriverDoherty() {
    console.log('Creating Single Driver Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source       = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     technology: 'GaN', biasClass: 'A',  gain: 15, pae: 40, p1db: 35, pout: 35, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'Pi',          loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: 'Splitter',   type: 'Wilkinson' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main Match', matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, p1db: 46, pout: 46, z_in: 4,  z_out: 8 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 43, pout: 43, z_in: 4,  z_out: 8 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'Main λ/4',   matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'Aux Offset', matchType: 'TL-stub',     loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Doherty',    type: 'doherty', subtype: 'Load-Modulation', ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires (while loading flag is still set)
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Single Driver Doherty created with connections');
  }
  
  createDualDriverDoherty() {
    console.log('Creating Dual Driver Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source         = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const mainDriver     = this.addComponent('transistor',  180, 180, { label: 'Main Driver', technology: 'GaN', biasClass: 'A',  gain: 15, pout: 35, z_in: 8,  z_out: 20 });
    const auxDriver      = this.addComponent('transistor',  180, 420, { label: 'Aux Driver',  technology: 'GaN', biasClass: 'A',  gain: 15, pout: 35, z_in: 8,  z_out: 20 });
    const mainInterstage = this.addComponent('matching',    300, 180, { label: 'Main Match',  matchType: 'Pi',          loss: 0.3, z_in: 20, z_out: 4 });
    const auxInterstage  = this.addComponent('matching',    300, 420, { label: 'Aux Match',   matchType: 'TL-stub',     loss: 0.3, z_in: 20, z_out: 4 });
    const mainPA         = this.addComponent('transistor',  420, 180, { label: 'Main PA',     technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, pout: 46, z_in: 4,  z_out: 8 });
    const auxPA          = this.addComponent('transistor',  420, 420, { label: 'Aux PA',      technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, pout: 43, z_in: 4,  z_out: 8 });
    const mainOutMatch   = this.addComponent('matching',    540, 180, { label: 'Main λ/4',    matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const auxOutMatch    = this.addComponent('matching',    540, 420, { label: 'Aux Offset',  matchType: 'TL-stub',     loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner       = this.addComponent('combiner',    660, 300, { label: 'Doherty',     type: 'doherty', subtype: 'Load-Modulation', ways: 2 });
    const load           = this.addComponent('termination', 780, 300, { label: 'Load',        impedance: 50 });

    // Create pre-connected wires (while loading flag is still set)
    this.createConnection(source.id, mainDriver.id, 'output', 'input');
    this.createConnection(source.id, auxDriver.id, 'output', 'input');
    this.createConnection(mainDriver.id, mainInterstage.id, 'output', 'input');
    this.createConnection(auxDriver.id, auxInterstage.id, 'output', 'input');
    this.createConnection(mainInterstage.id, mainPA.id, 'output', 'input');
    this.createConnection(auxInterstage.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Dual Driver Doherty created with connections');
  }
  
  createTripleStage() {
    console.log('Creating Triple Stage preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px cell grid (cell centres at 180,300,...1020)
    const source    = this.addComponent('termination', 180, 300, { label: 'Source',     impedance: 50 });
    const predriver = this.addComponent('transistor',  300, 300, { label: 'Pre-driver', technology: 'GaN', biasClass: 'A',  gain: 12, pae: 40, pout: 30, z_in: 12, z_out: 30 });
    const match1    = this.addComponent('matching',    420, 300, { label: 'Match 1',    matchType: 'Pi',          loss: 0.3, z_in: 30, z_out: 8 });
    const driver    = this.addComponent('transistor',  540, 300, { label: 'Driver',     technology: 'GaN', biasClass: 'A',  gain: 15, pae: 45, pout: 35, z_in: 8,  z_out: 20 });
    const match2    = this.addComponent('matching',    660, 300, { label: 'Match 2',    matchType: 'Pi',          loss: 0.3, z_in: 20, z_out: 4 });
    const finalPA   = this.addComponent('transistor',  780, 300, { label: 'Final PA',   technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, pout: 46, z_in: 4,  z_out: 8 });
    const outMatch  = this.addComponent('matching',    900, 300, { label: 'Output',     matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 50 });
    const load      = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires (while loading flag is still set)
    this.createConnection(source.id, predriver.id, 'output', 'input');
    this.createConnection(predriver.id, match1.id, 'output', 'input');
    this.createConnection(match1.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match2.id, 'output', 'input');
    this.createConnection(match2.id, finalPA.id, 'output', 'input');
    this.createConnection(finalPA.id, outMatch.id, 'output', 'input');
    this.createConnection(outMatch.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Triple Stage created with connections');
  }
  
  createConventionalDoherty() {
    console.log('Creating Conventional Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source       = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     biasClass: 'A',  gain: 15, pout: 35, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'L',          loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: '90° Splitter', type: 'Hybrid' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main Match', matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pout: 46, pae: 55, z_in: 4,  z_out: 8 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pout: 43, pae: 50, z_in: 4,  z_out: 8 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'λ/4',        matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'Offset',     matchType: 'TL-stub',     loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Doherty',    type: 'doherty', subtype: 'Load-Modulation',   ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires (while loading flag is still set)
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Conventional Doherty created with connections');
  }
  
  createInvertedDoherty() {
    console.log('Creating Inverted Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source       = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     biasClass: 'A',  gain: 15, pout: 35, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'Pi',          loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: 'Splitter',   type: 'Wilkinson' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main λ/4',   matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pout: 46, z_in: 4,  z_out: 8 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pout: 43, z_in: 4,  z_out: 8 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'Out Match',  matchType: 'L',           loss: 0.2, z_in: 8,  z_out: 50 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'λ/4',        matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Inverted',   type: 'doherty', subtype: 'Inverted-Doherty',  ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();

    console.log('Inverted Doherty created with connections');
  }
  
  createSymmetricDoherty() {
    console.log('Creating Symmetric Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source       = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     biasClass: 'A',  gain: 15, pout: 36, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'T',           loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: 'Splitter',   type: 'Wilkinson' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main Match', matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pout: 46, pae: 55, z_in: 4,  z_out: 8 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pout: 46, pae: 55, z_in: 4,  z_out: 8 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'λ/4',        matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'λ/4',        matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Symmetric',  type: 'doherty', subtype: 'Symmetric-Doherty',  ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Symmetric Doherty created with connections');
  }
  
  createAsymmetricDoherty() {
    console.log('Creating Asymmetric Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    const source       = this.addComponent('termination', 60,  300, { label: 'Source',     impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     biasClass: 'A',  gain: 15, pout: 36, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'L',           loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: '2:1 Splitter', type: 'Asymmetric' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main Match', matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'L',           loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pout: 49, pae: 55, z_in: 4,  z_out: 6 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pout: 43, pae: 50, z_in: 4,  z_out: 8 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'λ/4 (25Ω)', matchType: 'Transformer', loss: 0.2, z_in: 6,  z_out: 25 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'λ/4 (50Ω)', matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 50 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Asymmetric 2:1', type: 'doherty', subtype: 'Asymmetric-Doherty', ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create pre-connected wires
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Asymmetric Doherty created with connections');
  }
  
  createEnvelopeTrackingDoherty() {
    console.log('Creating Envelope Tracking Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; rows: main=180, center=300, aux=420
    // DC supply nodes sit one row above/below their respective PAs (rows 60 / 540)
    const source       = this.addComponent('termination', 60,  300, { label: 'RF Source',  impedance: 50 });
    const driver       = this.addComponent('transistor',  180, 300, { label: 'Driver',     technology: 'GaN', biasClass: 'A',  gain: 15, pout: 35, z_in: 8,  z_out: 20 });
    const match        = this.addComponent('matching',    300, 300, { label: 'Interstage', matchType: 'Pi',          loss: 0.5, z_in: 20, z_out: 50 });
    const splitter     = this.addComponent('splitter',    420, 300, { label: 'Splitter',   type: 'Wilkinson' });
    const mainMatch    = this.addComponent('matching',    540, 180, { label: 'Main Match', matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA       = this.addComponent('transistor',  660, 180, { label: 'Main PA',    technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, p1db: 46, pout: 46, z_in: 4,  z_out: 8 });
    const mainDC       = this.addComponent('dc_supply',   660,  60, { label: 'VDD Main (ET)', vdd: 28, maxCurrent: 5 });
    const auxMatch     = this.addComponent('matching',    540, 420, { label: 'Aux Match',  matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const auxPA        = this.addComponent('transistor',  660, 420, { label: 'Aux PA',     technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 43, pout: 43, z_in: 4,  z_out: 8 });
    const auxDC        = this.addComponent('dc_supply',   660, 540, { label: 'VDD Aux (ET)',  vdd: 28, maxCurrent: 3 });
    const mainOutMatch = this.addComponent('matching',    780, 180, { label: 'Main λ/4',   matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const auxOutMatch  = this.addComponent('matching',    780, 420, { label: 'Aux Offset', matchType: 'TL-stub',     loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner     = this.addComponent('combiner',    900, 300, { label: 'Doherty',    type: 'doherty', subtype: 'Load-Modulation',  ways: 2 });
    const load         = this.addComponent('termination', 1020, 300, { label: 'Load',      impedance: 50 });

    // Create RF path connections
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, auxMatch.id, 'output2', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(auxMatch.id, auxPA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(auxPA.id, auxOutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(auxOutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Create DC supply connections
    this.createConnection(mainDC.id, mainPA.id, 'output', 'dc');
    this.createConnection(auxDC.id, auxPA.id, 'output', 'dc');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('Envelope Tracking Doherty created with connections');
  }
  
  create3WaySymmetricDoherty() {
    console.log('Creating 3-Way Symmetric Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; 3 rows: top=180, mid=300, bot=420
    const source        = this.addComponent('termination', 60,  300, { label: 'Source',       impedance: 50 });
    const driver        = this.addComponent('transistor',  180, 300, { label: 'Driver',       technology: 'GaN', biasClass: 'A',  gain: 16, pout: 38, z_in: 8,  z_out: 20 });
    const match         = this.addComponent('matching',    300, 300, { label: 'Interstage',   matchType: 'Pi',          loss: 0.4, z_in: 20, z_out: 50 });
    const splitter      = this.addComponent('splitter',    420, 300, { label: '3-Way Equal',  type: 'Corporate', portCount: 3 });
    const mainMatch     = this.addComponent('matching',    540, 180, { label: 'Main Match',   matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const peak1Match    = this.addComponent('matching',    540, 300, { label: 'Peak1 Match',  matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const peak2Match    = this.addComponent('matching',    540, 420, { label: 'Peak2 Match',  matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA        = this.addComponent('transistor',  660, 180, { label: 'Main PA',      technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, p1db: 45, pout: 45, z_in: 4,  z_out: 8 });
    const peak1PA       = this.addComponent('transistor',  660, 300, { label: 'Peak PA 1',    technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 45, pout: 45, z_in: 4,  z_out: 8 });
    const peak2PA       = this.addComponent('transistor',  660, 420, { label: 'Peak PA 2',    technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 45, pout: 45, z_in: 4,  z_out: 8 });
    const mainOutMatch  = this.addComponent('matching',    780, 180, { label: 'λ/4 Main',     matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const peak1OutMatch = this.addComponent('matching',    780, 300, { label: 'λ/4 Peak1',    matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const peak2OutMatch = this.addComponent('matching',    780, 420, { label: 'λ/4 Peak2',    matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 25 });
    const combiner      = this.addComponent('combiner',    900, 300, { label: '3-Way Doherty', type: 'doherty', subtype: '3-Way',           portCount: 3, ways: 3 });
    const load          = this.addComponent('termination', 1020, 300, { label: 'Load',        impedance: 50 });

    // Create connections
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, peak1Match.id, 'output2', 'input');
    this.createConnection(splitter.id, peak2Match.id, 'output3', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(peak1Match.id, peak1PA.id, 'output', 'input');
    this.createConnection(peak2Match.id, peak2PA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(peak1PA.id, peak1OutMatch.id, 'output', 'input');
    this.createConnection(peak2PA.id, peak2OutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(peak1OutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(peak2OutMatch.id, combiner.id, 'output', 'input3');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('3-Way Symmetric Doherty created with connections');
  }
  
  create3WayAsymmetricDoherty() {
    console.log('Creating 3-Way Asymmetric Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    
    
    // Component positions aligned to 120px grid; 3 rows: top=180, mid=300, bot=420
    const source        = this.addComponent('termination', 60,  300, { label: 'Source',           impedance: 50 });
    const driver        = this.addComponent('transistor',  180, 300, { label: 'Driver',           technology: 'GaN', biasClass: 'A',  gain: 17, pout: 39, z_in: 8,  z_out: 20 });
    const match         = this.addComponent('matching',    300, 300, { label: 'Interstage',       matchType: 'Pi',          loss: 0.4, z_in: 20, z_out: 50 });
    const splitter      = this.addComponent('splitter',    420, 300, { label: '3-Way 2:1:1',      type: 'Asymmetric', portCount: 3 });
    const mainMatch     = this.addComponent('matching',    540, 180, { label: 'Main Match',       matchType: 'Pi',          loss: 0.3, z_in: 50, z_out: 4 });
    const peak1Match    = this.addComponent('matching',    540, 300, { label: 'Peak1 Match',      matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const peak2Match    = this.addComponent('matching',    540, 420, { label: 'Peak2 Match',      matchType: 'TL-stub',     loss: 0.3, z_in: 50, z_out: 4 });
    const mainPA        = this.addComponent('transistor',  660, 180, { label: 'Main PA (50%)',    technology: 'GaN', biasClass: 'AB', gain: 12, pae: 55, p1db: 48, pout: 48, z_in: 4,  z_out: 6 });
    const peak1PA       = this.addComponent('transistor',  660, 300, { label: 'Peak PA 1 (25%)', technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 42, pout: 42, z_in: 4,  z_out: 8 });
    const peak2PA       = this.addComponent('transistor',  660, 420, { label: 'Peak PA 2 (25%)', technology: 'GaN', biasClass: 'C',  gain: 12, pae: 50, p1db: 42, pout: 42, z_in: 4,  z_out: 8 });
    const mainOutMatch  = this.addComponent('matching',    780, 180, { label: 'λ/4 (25Ω)',       matchType: 'Transformer', loss: 0.2, z_in: 6,  z_out: 25 });
    const peak1OutMatch = this.addComponent('matching',    780, 300, { label: 'λ/4 (50Ω)',       matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 50 });
    const peak2OutMatch = this.addComponent('matching',    780, 420, { label: 'λ/4 (50Ω)',       matchType: 'Transformer', loss: 0.2, z_in: 8,  z_out: 50 });
    const combiner      = this.addComponent('combiner',    900, 300, { label: '3-Way Asym 2:1:1', type: 'doherty', subtype: '3-Way-Asymmetric', portCount: 3, ways: 3 });
    const load          = this.addComponent('termination', 1020, 300, { label: 'Load',            impedance: 50 });

    // Create connections
    this.createConnection(source.id, driver.id, 'output', 'input');
    this.createConnection(driver.id, match.id, 'output', 'input');
    this.createConnection(match.id, splitter.id, 'output', 'input');
    this.createConnection(splitter.id, mainMatch.id, 'output1', 'input');
    this.createConnection(splitter.id, peak1Match.id, 'output2', 'input');
    this.createConnection(splitter.id, peak2Match.id, 'output3', 'input');
    this.createConnection(mainMatch.id, mainPA.id, 'output', 'input');
    this.createConnection(peak1Match.id, peak1PA.id, 'output', 'input');
    this.createConnection(peak2Match.id, peak2PA.id, 'output', 'input');
    this.createConnection(mainPA.id, mainOutMatch.id, 'output', 'input');
    this.createConnection(peak1PA.id, peak1OutMatch.id, 'output', 'input');
    this.createConnection(peak2PA.id, peak2OutMatch.id, 'output', 'input');
    this.createConnection(mainOutMatch.id, combiner.id, 'output', 'input1');
    this.createConnection(peak1OutMatch.id, combiner.id, 'output', 'input2');
    this.createConnection(peak2OutMatch.id, combiner.id, 'output', 'input3');
    this.createConnection(combiner.id, load.id, 'output', 'input');
    
    // Clear loading flag and save one history entry for entire template
    this._loadingTemplate = false;
    this.saveHistory();
    
    console.log('3-Way Asymmetric Doherty created with connections');
  }
  
  // Zoom control methods
  zoomIn() {
    this.svg.transition().duration(300).call(
      this.zoom.scaleBy, 1.3
    );
    console.log('Zoom in');
  }
  
  zoomOut() {
    this.svg.transition().duration(300).call(
      this.zoom.scaleBy, 0.77
    );
    console.log('Zoom out');
  }
  
  resetZoom() {
    // Center the view on the origin (crosshair intersection)
    const scale = 1;
    const translateX = this.width / 2 - this.originX * scale;
    const translateY = this.height / 2 - this.originY * scale;
    
    this.svg.transition().duration(500).call(
      this.zoom.transform,
      d3.zoomIdentity.translate(translateX, translateY).scale(scale)
    );
    console.log('Zoom reset to origin:', this.originX, this.originY);
  }
  
  handlePortClick(event, component, portType) {
    if (!this.wireMode) return;
    
    event.stopPropagation();
    
    if (!this.wireStart) {
      // First port clicked - start wire
      this.wireStart = {
        componentId: component.id,
        portType: portType,
        component: component
      };
      
      // Highlight the starting port
      d3.select(event.target)
        .attr('stroke', '#ffff00')
        .attr('stroke-width', 3);
      
      // Set up mouse move listener for live wire drawing
      this.setupLiveWireDrawing();
      
      console.log('Wire start:', this.wireStart);
    } else {
      // Second port clicked - complete wire
      // Validate connection (output -> input, and not same component)
      const isOutputPort = portType.startsWith('output');
      const isInputPort = portType.startsWith('input');
      const isStartOutput = this.wireStart.portType.startsWith('output');
      
      if (isStartOutput && isInputPort && 
          this.wireStart.componentId !== component.id) {
        this.createConnection(
          this.wireStart.componentId, 
          component.id, 
          this.wireStart.portType, 
          portType
        );
        
        // Clear highlighted port
        this.clearPortHighlights();
      } else {
        let message = 'Invalid connection: ';
        if (this.wireStart.portType !== 'output') {
          message += 'Start from an output port';
        } else if (portType !== 'input') {
          message += 'End at an input port';
        } else if (this.wireStart.componentId === component.id) {
          message += 'Cannot connect component to itself';
        }
        
        console.warn(message);
        if (window.Shiny && window.Shiny.notifications) {
          Shiny.notifications.show({
            message: message,
            type: 'warning',
            duration: 3
          });
        }
        
        this.clearPortHighlights();
      }
      
      // Clear temporary wire line
      if (this.tempWireLine) {
        this.tempWireLine.remove();
        this.tempWireLine = null;
      }
      
      this.wireStart = null;
      this.removeLiveWireDrawing();
    }
  }
  
  createConnection(fromId, toId, fromPort = 'output', toPort = 'input') {
    // Check if connection already exists from same port
    const existing = this.connections.find(c => 
      c.from === fromId && c.to === toId && c.fromPort === fromPort && c.toPort === toPort
    );
    
    if (existing) {
      console.warn('Connection already exists between these ports');
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Connection already exists',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const connection = {
      id: this.connections.length + 1,
      from: fromId,
      to: toId,
      fromPort: fromPort,
      toPort: toPort,
      properties: {
        impedance: 50,
        length: 0.25,
        type: 'microstrip'
      }
    };
    
    this.connections.push(connection);
    this.renderConnections();
    
    // Save to history (skip if loading template)
    if (!this._loadingTemplate) {
      this.saveHistory();
    }
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_connections', JSON.stringify(this.connections), {priority: 'event'});
    }
    
    console.log('Connection created:', connection);
    console.log('Total connections:', this.connections.length);
  }
  
  
  setupLiveWireDrawing() {
    // Create temporary line for visual feedback
    this.tempWireLine = this.connectionsLayer.append('line')
      .attr('class', 'temp-wire')
      .attr('stroke', '#ffff00')
      .attr('stroke-width', 2)
      .attr('stroke-dasharray', '5,5')
      .attr('opacity', 0.7);
    
    // Track mouse movement with port snapping
    const self = this;
    this.svg.on('mousemove', function(event) {
      if (!self.wireStart || !self.tempWireLine) return;
      
      const [mx, my] = d3.pointer(event, self.zoomGroup.node());
      const startComp = self.components.find(c => c.id === self.wireStart.componentId);
      if (!startComp) return;
      
      const x1 = startComp.x + 35;  // Output port position
      const y1 = startComp.y;
      
      // Find nearest input port within snap distance
      let snapToPort = null;
      const snapDistance = 30; // pixels
      
      self.components.forEach(comp => {
        if (comp.id === self.wireStart.componentId) return; // Skip source component
        
        // Check distance to input port
        const portX = comp.x - 8; // Input port position
        const portY = comp.y;
        const distance = Math.sqrt(Math.pow(mx - portX, 2) + Math.pow(my - portY, 2));
        
        if (distance < snapDistance) {
          if (!snapToPort || distance < snapToPort.distance) {
            snapToPort = { x: portX, y: portY, distance: distance, comp: comp };
          }
        }
      });
      
      // Use snapped position if available, otherwise use mouse position
      let x2 = mx;
      let y2 = my;
      
      if (snapToPort) {
        x2 = snapToPort.x;
        y2 = snapToPort.y;
        
        // Highlight the port being snapped to
        self.highlightSnapPort(snapToPort.comp, 'input');
        self.hoveredPort = { comp: snapToPort.comp, portType: 'input' };
      } else {
        // Clear any previous port highlight
        if (self.hoveredPort) {
          self.clearPortHighlights();
          self.hoveredPort = null;
        }
      }
      
      self.tempWireLine
        .attr('x1', x1)
        .attr('y1', y1)
        .attr('x2', x2)
        .attr('y2', y2);
    });
  }
  
  highlightSnapPort(component, portType) {
    // Clear previous highlights
    this.componentsLayer.selectAll('.port-input, .port-output')
      .attr('stroke', function() {
        return d3.select(this).classed('port-input') ? '#00ff88' : '#ff7f11';
      })
      .attr('stroke-width', 2);
    
    // Highlight the target port
    const compGroup = this.componentsLayer.select(`[data-id="${component.id}"]`);
    const portClass = portType.startsWith('input') ? '.port-input' : '.port-output';
    compGroup.selectAll(portClass)
      .attr('stroke', '#ffff00')
      .attr('stroke-width', 4);
  }
  
  removeLiveWireDrawing() {
    this.svg.on('mousemove', null);
    if (this.tempWireLine) {
      this.tempWireLine.remove();
      this.tempWireLine = null;
    }
  }
  
  clearPortHighlights() {
    // Reset all port styling
    this.componentsLayer.selectAll('.port-input, .port-output')
      .attr('stroke', function() {
        return d3.select(this).classed('port-input') ? '#00ff88' : '#ff7f11';
      })
      .attr('stroke-width', 2)
      .attr('r', 5);
  }
  
  onPortHover(portElement, isEntering) {
    if (!this.wireMode) return;  // Only show hover effects in wire mode
    
    const port = d3.select(portElement);
    
    if (isEntering) {
      port.attr('r', 7)
          .attr('stroke', '#ffff00')
          .attr('stroke-width', 3);
    } else {
      // Don't reset if this is the wireStart port
      if (this.wireStart) {
        const isStartPort = port.attr('class').includes(this.wireStart.portType);
        if (isStartPort) return;
      }
      
      port.attr('r', 5)
          .attr('stroke', port.classed('port-input') ? '#00ff88' : '#ff7f11')
          .attr('stroke-width', 2);
    }
  }
  
  renderConnections() {
    // Clear existing connections
    this.connectionsLayer.selectAll('*').remove();
    
    // Draw each connection
    this.connections.forEach(connection => {
      const fromComp = this.components.find(c => c.id === connection.from);
      const toComp = this.components.find(c => c.id === connection.to);
      
      if (!fromComp || !toComp) {
        console.warn('Cannot draw connection - component not found:', connection);
        return;
      }
      
      // Get actual port positions using port IDs from connection
      const fromPortId = connection.fromPort || 'output';
      const toPortId = connection.toPort || 'input';
      const fromPort = this.getPortPosition(fromComp, fromPortId);
      const toPort = this.getPortPosition(toComp, toPortId);
      
      const x1 = fromPort.x;
      const y1 = fromPort.y;
      const x2 = toPort.x;
      const y2 = toPort.y;
      
      // Calculate control points for smooth curve
      const dx = x2 - x1;
      const dy = y2 - y1;
      const dist = Math.sqrt(dx*dx + dy*dy);
      const controlOffset = Math.min(dist * 0.4, 100);
      
      // Draw curved path with arrow
      const path = this.connectionsLayer.append('path')
        .attr('d', `M ${x1},${y1} C ${x1 + controlOffset},${y1} ${x2 - controlOffset},${y2} ${x2},${y2}`)
        .attr('stroke', '#00ff88')
        .attr('stroke-width', 1)
        .attr('fill', 'none')
        .attr('marker-end', 'url(#arrowhead)')
        .attr('data-connection-id', connection.id)
        .attr('class', 'connection-line')
        .style('cursor', 'pointer')
        .on('click', (event) => {
          event.stopPropagation();
          this.selectConnection(connection);
        })
        .on('mouseenter', function() {
          d3.select(this)
            .attr('stroke', '#ffff00')
            .attr('stroke-width', 2);
        })
        .on('mouseleave', function() {
          d3.select(this)
            .attr('stroke', '#00ff88')
            .attr('stroke-width', 1);
        });
    });
    
    console.log('Rendered', this.connections.length, 'connections');
  }
  
  selectConnection(connection) {
    console.log('Connection selected:', connection);
    
    // Deselect previous
    d3.selectAll('.connection-line').classed('selected', false);
    
    // Select this connection
    this.selectedConnection = connection;
    d3.select(`.connection-line[data-connection-id="${connection.id}"]`)
      .classed('selected', true);
    
    // Deselect any selected component
    this.selectedComponent = null;
    d3.selectAll('.component').classed('selected', false);
    
    console.log('Connection selected for deletion (press Delete key)');
  }
  
  deleteSelectedConnection() {
    if (!this.selectedConnection) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No connection selected',
          type: 'warning'
        });
      }
      return;
    }
    
    const id = this.selectedConnection.id;
    
    // Remove from array
    this.connections = this.connections.filter(c => c.id !== id);
    
    // Redraw connections
    this.renderConnections();
    
    // Clear selection
    this.selectedConnection = null;
    
    // Save to history
    this.saveHistory();
    
    console.log('Connection deleted:', id);
  }
  
  drawConnection(connection) {
    // Get component positions
    const fromComp = this.components.find(c => c.id === connection.from.component);
    const toComp = this.components.find(c => c.id === connection.to.component);
    
    if (!fromComp || !toComp) return;
    
    // Calculate port positions
    const x1 = fromComp.x + 35;  // Output port
    const y1 = fromComp.y;
    const x2 = toComp.x - 5;     // Input port
    const y2 = toComp.y;
    
    // Draw curved line
    const line = this.connectionsLayer.append('path')
      .attr('d', `M ${x1},${y1} C ${(x1 + x2) / 2},${y1} ${(x1 + x2) / 2},${y2} ${x2},${y2}`)
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 1)
      .attr('fill', 'none')
      .attr('marker-end', 'url(#arrowhead)')
      .attr('data-connection-id', connection.id);
    
    // Add arrowhead marker if not exists
    if (this.svg.select('#arrowhead').empty()) {
      this.svg.append('defs').append('marker')
        .attr('id', 'arrowhead')
        .attr('markerWidth', 8)
        .attr('markerHeight', 8)
        .attr('refX', 6)
        .attr('refY', 2.5)
        .attr('orient', 'auto')
        .append('polygon')
        .attr('points', '0 0, 8 2.5, 0 5')
        .attr('fill', '#00ff88');
    }
    
    // Deprecated - use renderConnections() instead
  }
  
  updateComponent(id, properties) {
    console.log('=== updateComponent method called ===');
    console.log('ID:', id, 'Type:', typeof id);
    console.log('Properties:', properties);
    console.log('Current components:', this.components);
    
    // Find component by ID
    const comp = this.components.find(c => {
      console.log('Checking component:', c.id, 'Type:', typeof c.id, 'Match:', c.id == id);
      return c.id == id; // Use == for loose comparison
    });
    
    if (!comp) {
      console.warn('Component not found with ID:', id);
      console.warn('Available component IDs:', this.components.map(c => c.id));
      return;
    }
    
    console.log('Found component:', comp);
    console.log('Old properties:', JSON.stringify(comp.properties));
    
    // Ensure properties object exists
    if (!comp.properties) {
      console.warn('Component has no properties object! Creating one...');
      comp.properties = {};
    }
    
    // Update properties safely
    try {
      Object.assign(comp.properties, properties);
      console.log('New properties:', JSON.stringify(comp.properties));
    } catch (e) {
      console.error('Error in Object.assign:', e);
      // Fallback: manual property copy
      for (let key in properties) {
        if (properties.hasOwnProperty(key)) {
          comp.properties[key] = properties[key];
        }
      }
    }
    
    // Re-render the component
    const compElement = this.componentsLayer.select(`[data-id="${id}"]`);
    console.log('Found DOM element:', !compElement.empty());
    
    if (!compElement.empty()) {
      compElement.remove();
      console.log('Removed old element');
    }
    
    // Render updated component
    const g = this.componentsLayer.append('g')
      .attr('class', 'component')
      .attr('data-id', comp.id)
      .attr('transform', `translate(${comp.x}, ${comp.y})`)
      .classed('selected', this.selectedComponent && this.selectedComponent.id === comp.id);
    
    console.log('Created new group element');
    
    if (comp.type === 'transistor') {
      this.renderTransistor(g, comp);
    } else if (comp.type === 'matching') {
      this.renderMatching(g, comp);
    } else if (comp.type === 'splitter') {
      this.renderSplitter(g, comp);
    } else if (comp.type === 'combiner') {
      this.renderCombiner(g, comp);
    }
    
    console.log('Rendered component of type:', comp.type);
    
    // Store component reference and reapply drag behavior
    g.datum(comp);
    if (this.drag) {
      g.call(this.drag);
    } else {
      console.error('this.drag is undefined in updateComponent!');
    }
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
    }
    
    console.log('=== Component update complete ===');
  }
  
  deleteSelected() {
    // Check if multiple components selected
    if (this.selectedComponents.length > 0) {
      this.deleteSelectedMultiple();
      return;
    }
    
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No component selected',
          type: 'warning'
        });
      }
      return;
    }
    
    const id = this.selectedComponent;
    
    // Remove from array
    this.components = this.components.filter(c => c.id !== id);
    
    // Remove from canvas
    this.componentsLayer.select(`[data-id="${id}"]`).remove();
    
    // Remove any connections to/from this component (using simplified structure)
    this.connections = this.connections.filter(conn => 
      conn.from !== id && conn.to !== id
    );
    
    // Redraw connections
    this.renderConnections();
    
    // Redraw power columns if enabled
    if (this.showPowerDisplay) {
      this.drawPowerColumns();
    }
    
    // Clear selection
    this.selectedComponent = null;
    
    // Save to history after deletion
    this.saveHistory();
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
      Shiny.setInputValue('lineup_selected_component', null, {priority: 'event'});
      Shiny.setInputValue('lineup_connections', JSON.stringify(this.connections), {priority: 'event'});
    }
    
    console.log('Component deleted:', id);
    console.log('Connections remaining:', this.connections.length);
  }
  
  toggleWireMode() {
    this.wireMode = !this.wireMode;
    
    // Update palette wire button visual state
    const paletteWireBtn = d3.select('.palette-action[data-type="wire"]');
    if (!paletteWireBtn.empty()) {
      if (this.wireMode) {
        paletteWireBtn.style('background', 'rgba(255, 127, 17, 0.5)')
                      .style('border', '2px solid #ff7f11');
      } else {
        paletteWireBtn.style('background', 'transparent')
                      .style('border', 'none');
      }
    }
    
    // Reset wire drawing state
    this.wireStart = null;
    
    console.log('Wire mode:', this.wireMode ? 'ON' : 'OFF');
  }
  
  clear() {
    console.log('=== clear() called ===');
    console.log('Components before clear:', this.components.length);
    
    this.components = [];
    this.connections = [];
    this.selectedComponent = null;
    this.componentsLayer.selectAll('*').remove();
    this.connectionsLayer.selectAll('*').remove();
    if (this.powerLayer)     this.powerLayer.selectAll('*').remove();
    if (this.gainLayer)      this.gainLayer.selectAll('*').remove();
    if (this.paeLayer)       this.paeLayer.selectAll('*').remove();
    if (this.phaseLayer)     this.phaseLayer.selectAll('*').remove();
    if (this.impedanceLayer) this.impedanceLayer.selectAll('*').remove();
    
    // Show instruction text again
    if (this.instructionText) {
      this.instructionText.style('display', 'block');
    }
    
    console.log('Canvas cleared. Components:', this.components.length);
  }
  
  setupEventHandlers() {
    // Click on canvas to deselect (unless in box select mode or wire mode)
    this.svg.on('click', () => {
      if (!this.boxSelectMode && !this.wireMode) {
        this.selectedComponent = null;
        this.selectedComponents = [];
        this.selectedConnection = null;
        d3.selectAll('.component').classed('selected', false);
        d3.selectAll('.connection-line').classed('selected', false);
        
        if (window.Shiny) {
          Shiny.setInputValue('lineup_selected_component', null, {priority: 'event'});
        }
      }
    });
    
    // Box select mouse handlers (double-click to activate)
    this.svg.on('dblclick', (event) => {
      if (this.boxSelectMode && event.button === 0) {
        event.preventDefault();
        
        // Mark selection as active (zoom is already disabled by toggleBoxSelect)
        this.boxSelectActive = true;
        
        const [x, y] = d3.pointer(event);
        this.selectionStart = { x, y };
        
        // Create selection box rectangle
        this.selectionBox = this.svg.append('rect')
          .attr('class', 'selection-box')
          .attr('x', x)
          .attr('y', y)
          .attr('width', 0)
          .attr('height', 0)
          .style('stroke', '#ff7f11')
          .style('stroke-width', 2)
          .style('stroke-dasharray', '5,5')
          .style('fill', 'rgba(255, 127, 17, 0.1)')
          .style('pointer-events', 'none');
      }
    });
    
    // Store mousemove handler reference for box selection
    this.boxSelectMouseMove = (event) => {
      if (this.boxSelectMode && this.selectionBox && this.selectionStart) {
        const [x, y] = d3.pointer(event);
        const width = x - this.selectionStart.x;
        const height = y - this.selectionStart.y;
        
        // Update selection box
        this.selectionBox
          .attr('x', width < 0 ? x : this.selectionStart.x)
          .attr('y', height < 0 ? y : this.selectionStart.y)
          .attr('width', Math.abs(width))
          .attr('height', Math.abs(height));
      }
    };
    
    this.svg.on('mousemove', this.boxSelectMouseMove);
    
    this.svg.on('mouseup', (event) => {
      if (this.boxSelectMode && this.selectionBox && this.selectionStart) {
        const [x, y] = d3.pointer(event);
        const boxX1 = Math.min(this.selectionStart.x, x);
        const boxY1 = Math.min(this.selectionStart.y, y);
        const boxX2 = Math.max(this.selectionStart.x, x);
        const boxY2 = Math.max(this.selectionStart.y, y);
        
        // Find components within selection box
        this.selectedComponents = this.components.filter(comp => {
          return comp.x >= boxX1 && comp.x <= boxX2 && 
                 comp.y >= boxY1 && comp.y <= boxY2;
        });
        
        // Highlight selected components
        d3.selectAll('.component').classed('selected', false);
        this.selectedComponents.forEach(comp => {
          d3.select(`[data-component-id=\"${comp.id}\"]`).classed('selected', true);
        });
        
        console.log('Selected components:', this.selectedComponents.length);
        
        // Remove selection box
        this.selectionBox.remove();
        this.selectionBox = null;
        this.selectionStart = null;
        this.boxSelectActive = false;
        
        // Note: Zoom remains disabled until box select mode is turned off via toggleBoxSelect()
        console.log('Box selection complete. Zoom will re-enable when box select mode is turned off.');
      }
    });  
    
    // Keyboard event handlers
    document.addEventListener('keydown', (event) => {
      // Prevent actions when editing inputs
      if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') {
        return;
      }
      
      // Box Select: Ctrl+B
      if (event.ctrlKey && event.key === 'b') {
        event.preventDefault();
        this.toggleBoxSelect();
      }
      
      // Lock/Unlock Canvas: Ctrl+L
      if (event.ctrlKey && event.key === 'l') {
        event.preventDefault();
        this.toggleLock();
      }
      
      // Delete key - delete selected component(s) or connection
      if (event.key === 'Delete' || event.key === 'Backspace') {
        event.preventDefault();
        
        // Check if canvas is locked
        if (this.locked) {
          if (window.Shiny && window.Shiny.notifications) {
            Shiny.notifications.show({
              message: 'Canvas is locked. Press Ctrl+L to unlock.',
              type: 'warning',
              duration: 2
            });
          }
          return;
        }
        
        if (this.selectedComponents.length > 0) {
          this.deleteSelectedMultiple();
        } else if (this.selectedComponent) {
          this.deleteSelected();
        } else if (this.selectedConnection) {
          this.deleteSelectedConnection();
        }
      }
      
      // Escape key - cancel modes and deselect
      if (event.key === 'Escape') {
        event.preventDefault();
        if (this.boxSelectMode) {
          this.toggleBoxSelect();
        }
        if (this.wireMode) {
          this.toggleWireMode();
        }
        this.selectedComponent = null;
        this.selectedComponents = [];
        this.selectedConnection = null;
        d3.selectAll('.component').classed('selected', false);
        d3.selectAll('.connection-line').classed('selected', false);
      }
      
      // Undo: Ctrl+Z
      if (event.ctrlKey && event.key === 'z' && !event.shiftKey) {
        event.preventDefault();
        this.undo();
      }
      
      // Redo: Ctrl+Shift+Z or Ctrl+Y
      if ((event.ctrlKey && event.shiftKey && event.key === 'Z') || (event.ctrlKey && event.key === 'y')) {
        event.preventDefault();
        this.redo();
      }
      
      // Cut: Ctrl+X
      if (event.ctrlKey && event.key === 'x') {
        event.preventDefault();
        
        // Check if canvas is locked
        if (this.locked) {
          if (window.Shiny && window.Shiny.notifications) {
            Shiny.notifications.show({
              message: 'Canvas is locked. Press Ctrl+L to unlock.',
              type: 'warning',
              duration: 2
            });
          }
          return;
        }
        
        this.cut();
      }
      
      // Copy: Ctrl+C
      if (event.ctrlKey && event.key === 'c') {
        event.preventDefault();
        this.copy();
      }
      
      // Paste: Ctrl+V
      if (event.ctrlKey && event.key === 'v') {
        event.preventDefault();
        
        // Check if canvas is locked
        if (this.locked) {
          if (window.Shiny && window.Shiny.notifications) {
            Shiny.notifications.show({
              message: 'Canvas is locked. Press Ctrl+L to unlock.',
              type: 'warning',
              duration: 2
            });
          }
          return;
        }
        
        this.paste();
      }
      
      // Rotate: R key
      if (event.key === 'r' || event.key === 'R') {
        event.preventDefault();
        this.rotateSelected();
      }
      
      // Flip horizontal: H key
      if (event.key === 'h' || event.key === 'H') {
        event.preventDefault();
        this.flipSelected('horizontal');
      }
      
      // Flip vertical: V key  
      if (event.key === 'v' || event.key === 'V') {
        event.preventDefault();
        this.flipSelected('vertical');
      }
      
      // Text repositioning mode: F5 key
      if (event.key === 'F5') {
        event.preventDefault();
        this.toggleTextDragMode();
      }
      
      // Cancel text drag mode: Escape
      if (event.key === 'Escape' && this.textDragMode) {
        event.preventDefault();
        this.exitTextDragMode();
      }
    });
  }
  
  // ============================================================
  // UNDO/REDO FUNCTIONALITY
  // ============================================================
  
  saveHistory() {
    // Create a snapshot of current state
    const state = {
      components: JSON.parse(JSON.stringify(this.components)),
      connections: JSON.parse(JSON.stringify(this.connections)),
      nextId: this.nextId
    };
    
    // Remove any states after current index (when undoing then making new changes)
    this.history = this.history.slice(0, this.historyIndex + 1);
    
    // Add new state
    this.history.push(state);
    
    // Limit history size
    if (this.history.length > this.maxHistorySize) {
      this.history.shift();
    } else {
      this.historyIndex++;
    }
    
    this.updateUndoRedoButtons();
  }
  
  undo() {
    if (this.historyIndex <= 0) {
      console.log('Nothing to undo');
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Nothing to undo',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    this.historyIndex--;
    this.restoreState(this.history[this.historyIndex]);
    
    console.log('Undo - history index:', this.historyIndex);
    this.updateUndoRedoButtons();
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: 'Undo',
        type: 'message',
        duration: 1
      });
    }
  }
  
  redo() {
    if (this.historyIndex >= this.history.length - 1) {
      console.log('Nothing to redo');
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Nothing to redo',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    this.historyIndex++;
    this.restoreState(this.history[this.historyIndex]);
    
    console.log('Redo - history index:', this.historyIndex);
    this.updateUndoRedoButtons();
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: 'Redo',
        type: 'message',
        duration: 1
      });
    }
  }
  
  restoreState(state) {
    this.components = JSON.parse(JSON.stringify(state.components));
    this.connections = JSON.parse(JSON.stringify(state.connections));
    this.nextId = state.nextId;
    
    // Clear and re-render
    this.componentsLayer.selectAll('*').remove();
    this.connectionsLayer.selectAll('*').remove();
    
    this.components.forEach(comp => {
      this.renderComponent(comp);
    });
    
    this.renderConnections();
    this.drawPaGroupBoxes();
  }
  
  updateUndoRedoButtons() {
    const undoBtn = document.getElementById('lineup_undo');
    const redoBtn = document.getElementById('lineup_redo');
    
    if (undoBtn) {
      undoBtn.disabled = this.historyIndex <= 0;
      undoBtn.style.opacity = this.historyIndex <= 0 ? '0.5' : '1';
    }
    
    if (redoBtn) {
      redoBtn.disabled = this.historyIndex >= this.history.length - 1;
      redoBtn.style.opacity = this.historyIndex >= this.history.length - 1 ? '0.5' : '1';
    }
  }
  
  // ============================================================
  // CUT/COPY/PASTE FUNCTIONALITY
  // ============================================================
  // Cut/Copy/Paste Operations
  // ============================================================
  
  toggleBoxSelect() {
    this.boxSelectMode = !this.boxSelectMode;
    
    // Update button visual state
    const boxSelectBtn = document.getElementById('box_select_btn');
    if (boxSelectBtn) {
      if (this.boxSelectMode) {
        boxSelectBtn.classList.add('active');
        boxSelectBtn.style.backgroundColor = '#ff7f11';
        boxSelectBtn.style.color = '#fff';
      } else {
        boxSelectBtn.classList.remove('active');
        boxSelectBtn.style.backgroundColor = '';
        boxSelectBtn.style.color = '';
      }
    }
    
    // Disable/enable zoom when toggling box select mode
    if (this.boxSelectMode) {
      // Disable zoom and pan
      this.svg.on('.zoom', null);
      this.svg.style('cursor', 'crosshair');
      console.log('🔒 Zoom disabled for box select mode');
    } else {
      // Re-enable zoom and pan
      if (this.zoom) {
        this.svg.call(this.zoom);
      }
      this.svg.style('cursor', 'default');
      console.log('🔓 Zoom re-enabled');
    }
    
    console.log('Box select mode:', this.boxSelectMode ? 'ON' : 'OFF');
  }
  

  
  toggleLock() {
    this.locked = !this.locked;
    
    // Visual feedback on canvas
    const container = document.getElementById(this.containerId);
    if (container) {
      if (this.locked) {
        container.style.border = '3px solid #ff0000';
        container.style.boxShadow = '0 0 20px rgba(255, 0, 0, 0.5)';
      } else {
        container.style.border = '';
        container.style.boxShadow = '';
      }
    }
    
    // Update cursor
    if (this.locked) {
      this.svg.style('cursor', 'not-allowed');
    } else {
      this.svg.style('cursor', 'default');
    }
    
    console.log('Canvas locked:', this.locked ? 'YES' : 'NO');
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: this.locked ? '🔒 Canvas Locked (Ctrl+L to unlock)' : '🔓 Canvas Unlocked',
        type: this.locked ? 'warning' : 'message',
        duration: 2
      });
    }
  }
  selectAll() {
    // Deselect all (equivalent to pressing Esc)
    this.selectedComponent = null;
    this.selectedComponents = [];
    this.selectedConnection = null;
    d3.selectAll('.component').classed('selected', false);
    d3.selectAll('.connection-line').classed('selected', false);
    
    if (this.wireMode) {
      this.wireMode = false;
      this.wireStart = null;
      if (this.tempWireLine) {
        this.tempWireLine.remove();
        this.tempWireLine = null;
      }
      // Update palette wire button
      const paletteWireBtn = d3.select('.palette-action[data-type="wire"]');
      if (!paletteWireBtn.empty()) {
        paletteWireBtn.style('background', 'transparent')
                      .style('border', 'none');
      }
    }
    
    if (this.boxSelectMode) {
      this.toggleBoxSelect();
    }
    
    console.log('Deselected all components and connections');
  }
  
  copy() {
    // Check if multiple components selected
    if (this.selectedComponents.length > 0) {
      const clipboardData = JSON.parse(JSON.stringify(this.selectedComponents));
      this.clipboard = clipboardData;
      
      // Only enable global clipboard in single-canvas mode
      if (!window.paCanvases || window.paCanvases.length <= 1) {
        window.paCanvasClipboard = clipboardData;
      }
      
      console.log('Copied components:', this.selectedComponents.length);
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: `Copied ${this.selectedComponents.length} component(s)`,
          type: 'message',
          duration: 2
        });
      }
      return;
    }
    
    // Single component copy
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No component selected to copy',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const comp = this.components.find(c => c.id === this.selectedComponent);
    if (comp) {
      const clipboardData = [JSON.parse(JSON.stringify(comp))];
      this.clipboard = clipboardData;
      
      // Only enable global clipboard in single-canvas mode
      if (!window.paCanvases || window.paCanvases.length <= 1) {
        window.paCanvasClipboard = clipboardData;
      }
      
      console.log('Copied component:', comp.properties.label);
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: `Copied: ${comp.properties.label || comp.type}`,
          type: 'message',
          duration: 2
        });
      }
    }
  }
  
  cut() {
    // Check if multiple components selected
    if (this.selectedComponents.length > 0) {
      const clipboardData = JSON.parse(JSON.stringify(this.selectedComponents));
      this.clipboard = clipboardData;
      
      // Only enable global clipboard in single-canvas mode
      if (!window.paCanvases || window.paCanvases.length <= 1) {
        window.paCanvasClipboard = clipboardData;
      }
      
      console.log('Cut components:', this.selectedComponents.length);
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: `Cut ${this.selectedComponents.length} component(s)`,
          type: 'message',
          duration: 2
        });
      }
      
      // Delete the components
      this.deleteSelectedMultiple();
      return;
    }
    
    // Single component cut
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No component selected to cut',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const comp = this.components.find(c => c.id === this.selectedComponent);
    if (comp) {
      const clipboardData = [JSON.parse(JSON.stringify(comp))];
      this.clipboard = clipboardData;
      
      // Only enable global clipboard in single-canvas mode
      if (!window.paCanvases || window.paCanvases.length <= 1) {
        window.paCanvasClipboard = clipboardData;
      }
      
      console.log('Cut component:', comp.properties.label);
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: `Cut: ${comp.properties.label || comp.type}`,
          type: 'message',
          duration: 2
        });
      }
      
      // Delete the component
      this.deleteSelected();
    }
  }
  
  paste() {
    // In multi-canvas mode, only use local clipboard (no cross-canvas paste)
    // In single-canvas mode, try global clipboard first
    const clipboardSource = (window.paCanvases && window.paCanvases.length > 1) 
      ? this.clipboard 
      : (window.paCanvasClipboard || this.clipboard);
    
    if (!clipboardSource || clipboardSource.length === 0) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Clipboard is empty',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    // Paste multiple components
    if (Array.isArray(clipboardSource)) {
      const offsetX = 50;
      const offsetY = 50;
      
      clipboardSource.forEach(comp => {
        const newX = comp.x + offsetX;
        const newY = comp.y + offsetY;
        
        this.addComponent(
          comp.type,
          newX,
          newY,
          JSON.parse(JSON.stringify(comp.properties))
        );
      });
      
      console.log('Pasted components:', clipboardSource.length, sourceInfo);
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: `Pasted ${clipboardSource.length} component(s)${sourceInfo}`,
          type: 'message',
          duration: 2
        });
      }
    }
  }
  
  deleteSelectedMultiple() {
    if (this.selectedComponents.length === 0) return;
    
    const count = this.selectedComponents.length;
    const componentIds = this.selectedComponents.map(c => c.id);
    
    // Remove components
    this.components = this.components.filter(c => !componentIds.includes(c.id));
    
    // Remove connections related to deleted components
    this.connections = this.connections.filter(conn => 
      !componentIds.includes(conn.from) && !componentIds.includes(conn.to)
    );
    
    // Clear selection
    this.selectedComponents = [];
    
    // Re-render
    this.render();
    
    // Save history
    this.saveHistory();
    
    console.log(`Deleted ${count} component(s)`);
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: `Deleted ${count} component(s)`,
        type: 'message',
        duration: 2
      });
    }
  }
  
  // ============================================================
  // ROTATE/FLIP FUNCTIONALITY
  // ============================================================
  
  rotateSelected() {
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No component selected to rotate',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const comp = this.components.find(c => c.id === this.selectedComponent);
    if (!comp) return;
    
    // Rotate 90 degrees clockwise
    comp.rotation = ((comp.rotation || 0) + 90) % 360;
    
    // Re-render component
    this.componentsLayer.select(`[data-id="${comp.id}"]`).remove();
    this.renderComponent(comp);
    this.renderConnections();
    
    console.log('Rotated component to:', comp.rotation);
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: `Rotated: ${comp.rotation}°`,
        type: 'message',
        duration: 1
      });
    }
    
    this.saveHistory();
  }
  
  flipSelected(direction) {
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'No component selected to flip',
          type: 'warning',
          duration: 2
        });
      }
      return;
    }
    
    const comp = this.components.find(c => c.id === this.selectedComponent);
    if (!comp) return;
    
    if (direction === 'horizontal') {
      comp.flipH = !comp.flipH;
    } else {
      comp.flipV = !comp.flipV;
    }
    
    // Re-render component
    this.componentsLayer.select(`[data-id="${comp.id}"]`).remove();
    this.renderComponent(comp);
    this.renderConnections();
    
    console.log('Flipped component', direction);
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: `Flipped ${direction}`,
        type: 'message',
        duration: 1
      });
    }
    
    this.saveHistory();
  }
  
  // ============================================================
  // TEXT REPOSITIONING MODE (F5)
  // ============================================================
  
  toggleTextDragMode() {
    if (!this.selectedComponent) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Select a component first, then press F5 to reposition its text',
          type: 'warning',
          duration: 3
        });
      }
      return;
    }
    
    this.textDragMode = !this.textDragMode;
    
    if (this.textDragMode) {
      this.textDragComponent = this.selectedComponent;
      
      // Change cursor to crosshair
      this.svg.style('cursor', 'crosshair');
      
      // Highlight the component's text elements
      const comp = this.components.find(c => c.id === this.textDragComponent);
      if (comp) {
        const group = this.componentsLayer.select(`[data-id="${comp.id}"]`);
        group.selectAll('text').classed('text-drag-highlight', true);
        
        // Initialize textOffset if not present
        if (!comp.textOffset) {
          comp.textOffset = { x: 0, y: 0 };
        }
      }
      
      // Set up text drag mouse handlers
      this.setupTextDragHandlers();
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Text reposition mode ON. Click and drag to move text. Press ESC or F5 to exit.',
          type: 'message',
          duration: 4
        });
      }
      
      console.log('Text drag mode enabled for component:', this.textDragComponent);
    } else {
      this.exitTextDragMode();
    }
  }
  
  setupTextDragHandlers() {
    // Mouse down - start text drag
    this.textDragMouseDown = (event) => {
      if (this.textDragMode && this.textDragComponent) {
        const [x, y] = d3.pointer(event);
        this.textDragStart = { x, y };
        
        const comp = this.components.find(c => c.id === this.textDragComponent);
        if (comp) {
          this.textOriginalOffset = { ...comp.textOffset };
        }
        
        console.log('Text drag started at:', this.textDragStart);
      }
    };
    
    // Mouse move - update text offset
    this.textDragMouseMove = (event) => {
      if (this.textDragMode && this.textDragStart && this.textDragComponent) {
        const [x, y] = d3.pointer(event);
        const dx = x - this.textDragStart.x;
        const dy = y - this.textDragStart.y;
        
        const comp = this.components.find(c => c.id === this.textDragComponent);
        if (comp) {
          comp.textOffset = {
            x: this.textOriginalOffset.x + dx,
            y: this.textOriginalOffset.y + dy
          };
          
          // Re-render the component to show new text position
          this.componentsLayer.select(`[data-id="${comp.id}"]`).remove();
          this.renderComponent(comp);
          
          // Re-highlight text
          const group = this.componentsLayer.select(`[data-id="${comp.id}"]`);
          group.selectAll('text').classed('text-drag-highlight', true);
        }
      }
    };
    
    // Mouse up - finish text drag
    this.textDragMouseUp = (event) => {
      if (this.textDragMode && this.textDragStart) {
        console.log('Text drag ended');
        this.textDragStart = null;
        this.textOriginalOffset = null;
        
        // Save to history
        this.saveHistory();
        
        if (window.Shiny) {
          Shiny.setInputValue('lineup_components', JSON.stringify(this.components), { priority: 'event'});
        }
      }
    };
    
    this.svg.on('mousedown.textdrag', this.textDragMouseDown);
    this.svg.on('mousemove.textdrag', this.textDragMouseMove);
    this.svg.on('mouseup.textdrag', this.textDragMouseUp);
  }
  
  exitTextDragMode() {
    if (!this.textDragMode) return;
    
    this.textDragMode = false;
    this.textDragStart = null;
    this.textOriginalOffset = null;
    
    // Reset cursor
    this.svg.style('cursor', 'default');
    
    // Remove text drag mouse handlers
    this.svg.on('mousedown.textdrag', null);
    this.svg.on('mousemove.textdrag', null);
    this.svg.on('mouseup.textdrag', null);
    
    // Remove highlight from text elements
    if (this.textDragComponent) {
      const comp = this.components.find(c => c.id === this.textDragComponent);
      if (comp) {
        const group = this.componentsLayer.select(`[data-id="${comp.id}"]`);
        group.selectAll('text').classed('text-drag-highlight', false);
      }
    }
    
    this.textDragComponent = null;
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: 'Text reposition mode OFF',
        type: 'message',
        duration: 1
      });
    }
    
    console.log('Text drag mode disabled');
  }
  
  // ============================================================
  // POWER DISPLAY COLUMNS
  // ============================================================
  
  togglePowerUnit() {
    // Cycle through dBm -> W -> both -> dBm
    const units = ['dBm', 'W', 'both'];
    const currentIndex = units.indexOf(this.powerUnit);
    this.powerUnit = units[(currentIndex + 1) % units.length];
    
    console.log('Power unit changed to:', this.powerUnit);
    
    // Update button text while preserving icon
    const btn = document.getElementById('power_unit_toggle');
    if (btn) {
      const icon = btn.querySelector('i');
      const labels = { 'dBm': 'dBm', 'W': 'Watts', 'both': 'Both' };
      
      if (icon) {
        btn.innerHTML = '';  // Clear
        btn.appendChild(icon);  // Re-add icon first
        btn.appendChild(document.createTextNode(` Unit: ${labels[this.powerUnit]}`));
      } else {
        btn.innerHTML = `<i class="fa fa-ruler"></i> Unit: ${labels[this.powerUnit]}`;
      }
    }
    
    // Re-render all components to update Pout display
    this.componentsLayer.selectAll('*').remove();
    this.components.forEach(comp => {
      this.renderComponent(comp);
    });
    
    // Re-render connections
    this.renderConnections();
    
    // Redraw power display if active
    if (this.showPowerDisplay) {
      this.drawPowerColumns();
    }
    
    if (window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: `Power unit: ${this.powerUnit}`,
        type: 'message',
        duration: 1
      });
    }
  }
  
  showPowerTooltip(component, event) {
    // Calculate power for this component
    const index = this.components.findIndex(c => c.id === component.id);
    
    // Get previous component's output power
    let previousPout = 0;
    if (index > 0) {
      const sortedComponents = [...this.components].sort((a, b) => a.x - b.x);
      const sortedIndex = sortedComponents.findIndex(c => c.id === component.id);
      if (sortedIndex > 0) {
        const prevComp = sortedComponents[sortedIndex - 1];
        const prevPowerInfo = this.calculateComponentPower(prevComp, 0, sortedIndex - 1 === 0);
        previousPout = prevPowerInfo.pout_dbm;
      }
    }
    
    const powerInfo = this.calculateComponentPower(component, previousPout, index === 0);
    
    // Create or update tooltip
    if (!this.powerTooltip) {
      this.powerTooltip = this.svg.append('g')
        .attr('class', 'power-tooltip')
        .style('pointer-events', 'none');
    }
    
    this.powerTooltip.selectAll('*').remove();
    
    // Position tooltip near component
    const tooltipX = component.x + 80;
    const tooltipY = component.y - 60;
    
    // Background
    this.powerTooltip.append('rect')
      .attr('x', tooltipX)
      .attr('y', tooltipY)
      .attr('width', 150)
      .attr('height', powerInfo.power_bo_dbm ? 95 : 80)
      .attr('fill', '#000')
      .attr('stroke', '#00aaff')
      .attr('stroke-width', 2)
      .attr('rx', 5)
      .attr('opacity', 0.95);
    
    let yPos = tooltipY + 20;
    
    // Input power
    const pinText = this.formatPower(powerInfo.pin_dbm, this.powerUnit);
    this.powerTooltip.append('text')
      .attr('x', tooltipX + 10)
      .attr('y', yPos)
      .attr('fill', '#00ff88')
      .attr('font-size', '11px')
      .text(`Pin: ${pinText}`);
    yPos += 18;
    
    // Output power
    const poutText = this.formatPower(powerInfo.pout_dbm, this.powerUnit);
    this.powerTooltip.append('text')
      .attr('x', tooltipX + 10)
      .attr('y', yPos)
      .attr('fill', '#ff7f11')
      .attr('font-size', '11px')
      .text(`Pout: ${poutText}`);
    yPos += 18;
    
    // P1dB (if available)
    if (powerInfo.p1db_dbm) {
      const p1dbText = this.formatPower(powerInfo.p1db_dbm, this.powerUnit);
      this.powerTooltip.append('text')
        .attr('x', tooltipX + 10)
        .attr('y', yPos)
        .attr('fill', '#ffaa00')
        .attr('font-size', '11px')
        .text(`P1dB: ${p1dbText}`);
      yPos += 18;
    }
    
    // Power at back-off
    if (powerInfo.power_bo_dbm) {
      const pboText = this.formatPower(powerInfo.power_bo_dbm, this.powerUnit);
      this.powerTooltip.append('text')
        .attr('x', tooltipX + 10)
        .attr('y', yPos)
        .attr('fill', '#ffaa00')
        .attr('font-size', '11px')
        .text(`P_BO: ${pboText}`);
    }
  }
  
  hidePowerTooltip() {
    if (this.powerTooltip) {
      this.powerTooltip.remove();
      this.powerTooltip = null;
    }
  }
  
  togglePowerDisplay() {
    this.showPowerDisplay = !this.showPowerDisplay;
    
    const btn = document.getElementById('power_display_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showPowerDisplay ? '#28a745' : '';
      btn.style.color = this.showPowerDisplay ? '#fff' : '';
    }
    
    if (this.showPowerDisplay) {
      this.drawPowerColumns();
      if (this.showImpedanceDisplay) this.drawImpedanceColumns();
      if (this.showGainDisplay)      this.drawGainColumns();
      if (this.showPAEDisplay)       this.drawPAEColumns();
      if (this.showPhaseDisplay)     this.drawPhaseColumns();
      console.log('Power display enabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Power display enabled',
          type: 'message',
          duration: 2
        });
      }
    } else {
      // Clear power display layer
      if (this.powerLayer) {
        this.powerLayer.selectAll('*').remove();
      }
      if (this.showImpedanceDisplay) this.drawImpedanceColumns();
      if (this.showGainDisplay)      this.drawGainColumns();
      if (this.showPAEDisplay)       this.drawPAEColumns();
      if (this.showPhaseDisplay)     this.drawPhaseColumns();
      console.log('Power display disabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Power display disabled',
          type: 'message',
          duration: 2
        });
      }
    }
  }
  
  toggleImpedanceDisplay() {
    this.showImpedanceDisplay = !this.showImpedanceDisplay;
    
    const btn = document.getElementById('impedance_display_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showImpedanceDisplay ? '#28a745' : '';
      btn.style.color = this.showImpedanceDisplay ? '#fff' : '';
    }
    
    if (this.showImpedanceDisplay) {
      this.drawImpedanceColumns();
      if (this.showPowerDisplay) this.drawPowerColumns();
      if (this.showPhaseDisplay) this.drawPhaseColumns();
      console.log('Impedance display enabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Impedance display enabled',
          type: 'message',
          duration: 2
        });
      }
    } else {
      // Clear impedance display layer
      if (this.impedanceLayer) {
        this.impedanceLayer.selectAll('*').remove();
      }
      if (this.showPowerDisplay) this.drawPowerColumns();
      if (this.showPhaseDisplay) this.drawPhaseColumns();
      console.log('Impedance display disabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Impedance display disabled',
          type: 'message',
          duration: 2
        });
      }
    }
  }

  toggleGainDisplay() {
    this.showGainDisplay = !this.showGainDisplay;
    const btn = document.getElementById('gain_display_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showGainDisplay ? '#28a745' : '';
      btn.style.color = this.showGainDisplay ? '#fff' : '';
    }
    if (this.showGainDisplay) {
      this.drawGainColumns();
    } else {
      if (this.gainLayer) this.gainLayer.selectAll('*').remove();
    }
    // Redraw co-active layers so slots re-pack correctly
    if (this.showPowerDisplay)     this.drawPowerColumns();
    if (this.showImpedanceDisplay) this.drawImpedanceColumns();
    if (this.showPAEDisplay)       this.drawPAEColumns();
    if (this.showPhaseDisplay)     this.drawPhaseColumns();
  }

  togglePAEDisplay() {
    this.showPAEDisplay = !this.showPAEDisplay;
    const btn = document.getElementById('pae_display_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showPAEDisplay ? '#28a745' : '';
      btn.style.color = this.showPAEDisplay ? '#fff' : '';
    }
    if (this.showPAEDisplay) {
      this.drawPAEColumns();
    } else {
      if (this.paeLayer) this.paeLayer.selectAll('*').remove();
    }
    // Redraw co-active layers so slots re-pack correctly
    if (this.showPowerDisplay)     this.drawPowerColumns();
    if (this.showImpedanceDisplay) this.drawImpedanceColumns();
    if (this.showGainDisplay)      this.drawGainColumns();
    if (this.showPhaseDisplay)     this.drawPhaseColumns();
  }

  togglePhaseDisplay() {
    this.showPhaseDisplay = !this.showPhaseDisplay;
    const btn = document.getElementById('phase_display_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showPhaseDisplay ? '#28a745' : '';
      btn.style.color = this.showPhaseDisplay ? '#fff' : '';
    }
    if (this.showPhaseDisplay) {
      this.drawPhaseColumns();
    } else {
      if (this.phaseLayer) this.phaseLayer.selectAll('*').remove();
    }
    // Redraw co-active layers so slots re-pack correctly
    if (this.showPowerDisplay)     this.drawPowerColumns();
    if (this.showImpedanceDisplay) this.drawImpedanceColumns();
    if (this.showGainDisplay)      this.drawGainColumns();
    if (this.showPAEDisplay)       this.drawPAEColumns();
  }
  
  calculateOptimalImpedance(component, powerLevelDbm) {
    // Get Vdd from component properties (default to 28V for GaN)
    const vdd = component.properties.vdd || 28;
    
    // Convert power from dBm to Watts
    const powerWatts = Math.pow(10, (powerLevelDbm - 30) / 10);
    
    // Calculate optimal load impedance: Z = Vdd^2 / (2 * P)
    const impedance = (vdd * vdd) / (2 * powerWatts);
    
    return impedance;
  }
  
  toggleCalculationRationale() {
    this.showCalculationRationale = !this.showCalculationRationale;
    
    const btn = document.getElementById('calculation_rationale_toggle');
    if (btn) {
      btn.style.backgroundColor = this.showCalculationRationale ? '#28a745' : '';
      btn.style.color = this.showCalculationRationale ? '#fff' : '';
    }
    
    if (this.showCalculationRationale) {
      this.drawCalculationRationale();
      console.log('Calculation rationale enabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Calculation details displayed',
          type: 'message',
          duration: 2
        });
      }
    } else {
      // Clear calculation rationale layer
      if (this.calculationRationaleLayer) {
        this.calculationRationaleLayer.selectAll('*').remove();
      }
      console.log('Calculation rationale disabled');
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: 'Calculation details hidden',
          type: 'message',
          duration: 2
        });
      }
    }
  }
  
  drawCalculationRationale() {
    if (!this.showCalculationRationale) return;
    
    // Clear existing display
    this.calculationRationaleLayer.selectAll('*').remove();
    
    // Position panel in upper-right corner of canvas
    const panelX = this.width - 320;
    const panelY = 20;
    const panelWidth = 300;
    const panelHeight = 380;
    
    // Create draggable panel group
    const panel = this.calculationRationaleLayer.append('g')
      .attr('transform', `translate(${panelX}, ${panelY})`)
      .attr('class', 'calculation-rationale-panel')
      .style('cursor', 'move');
    
    // Add drag behavior
    const drag = d3.drag()
      .on('start', function(event) {
        d3.select(this).raise().style('opacity', 0.95);
      })
      .on('drag', function(event) {
        const currentTransform = d3.select(this).attr('transform');
        const match = currentTransform.match(/translate\(([^,]+),([^)]+)\)/);
        if (match) {
          const newX = parseFloat(match[1]) + event.dx;
          const newY = parseFloat(match[2]) + event.dy;
          d3.select(this).attr('transform', `translate(${newX}, ${newY})`);
        }
      })
      .on('end', function(event) {
        d3.select(this).style('opacity', 1);
      });
    
    panel.call(drag);
    
    // Background panel
    panel.append('rect')
      .attr('width', panelWidth)
      .attr('height', panelHeight)
      .attr('fill', '#ffffff')
      .attr('stroke', '#3498db')
      .attr('stroke-width', 2)
      .attr('rx', 8)
      .attr('filter', 'drop-shadow(2px 2px 4px rgba(0,0,0,0.3))');
    
    // Title
    panel.append('text')
      .attr('x', panelWidth / 2)
      .attr('y', 25)
      .attr('text-anchor', 'middle')
      .attr('font-size', '16px')
      .attr('font-weight', 'bold')
      .attr('fill', '#2c3e50')
      .text('PA Design Calculations');
    
    // Formulas section
    const formulas = [
      { label: 'Power Conversion:', formula: 'P(W) = 10^((P(dBm) - 30) / 10)' },
      { label: '', formula: 'P(dBm) = 10·log₁₀(P(W)) + 30' },
      { label: '', formula: '' },
      { label: 'Optimal Impedance:', formula: 'Z_opt = V_dd² / (2 · P_out)' },
      { label: '', formula: '' },
      { label: 'Backoff Power:', formula: 'P_backoff (dBm) = P_3dB (dBm) − BO (dB)' },
      { label: '', formula: 'BO (dB) = P_3dB − P_backoff   [linear subtraction]' },
      { label: '', formula: '' },
      { label: 'Power Added Efficiency:', formula: 'PAE = (P_out - P_in) / P_DC × 100%' },
      { label: '', formula: 'P_DC = V_dd · I_dd' },
      { label: '', formula: '' },
      { label: 'Gain:', formula: 'G(dB) = 10·log₁₀(P_out / P_in)' },
      { label: '', formula: 'P_out = P_in · 10^(G/10)' }
    ];
    
    let yPos = 50;
    formulas.forEach((item, index) => {
      if (item.label) {
        // Label (bold)
        panel.append('text')
          .attr('x', 15)
          .attr('y', yPos)
          .attr('font-size', '11px')
          .attr('font-weight', 'bold')
          .attr('fill', '#2980b9')
          .text(item.label);
        yPos += 18;
      }
      
      if (item.formula) {
        // Formula (monospace)
        panel.append('text')
          .attr('x', 25)
          .attr('y', yPos)
          .attr('font-size', '11px')
          .attr('font-family', 'Consolas, Monaco, monospace')
          .attr('fill', '#34495e')
          .text(item.formula);
        yPos += 18;
      } else {
        yPos += 8; // Small spacing for empty lines
      }
    });
    
    // Close button
    const closeBtn = panel.append('g')
      .attr('transform', `translate(${panelWidth - 25}, 10)`)
      .style('cursor', 'pointer')
      .on('click', () => this.toggleCalculationRationale());
    
    closeBtn.append('circle')
      .attr('r', 10)
      .attr('fill', '#e74c3c');
    
    closeBtn.append('text')
      .attr('text-anchor', 'middle')
      .attr('dominant-baseline', 'central')
      .attr('font-size', '14px')
      .attr('font-weight', 'bold')
      .attr('fill', '#fff')
      .text('×');
  }
  
  drawImpedanceColumns() {
    if (!this.showImpedanceDisplay) return;

    this.impedanceLayer.selectAll('*').remove();
    if (this.components.length === 0) return;

    const W = this.width, H = this.height;
    const HC = 60;
    const PAD = 4;
    const backoffDb = window.getGlobalBackoff ? window.getGlobalBackoff() : 6;

    // ── Component-aware rows & cols (same logic as drawGuideLines) ──────────
    const rows = this._detectRows();
    const cols = this._detectCols();
    const midY = rows.length > 1 ? (rows[0] + rows[rows.length - 1]) / 2 : H / 2;

    const rowZone = (targetRi) => {
      if (targetRi < 0)            return { topY: 0, botY: rows[0] - HC };
      if (targetRi >= rows.length) return { topY: rows[rows.length - 1] + HC, botY: H };
      const topY = targetRi === 0
        ? rows[0] - HC
        : (rows[targetRi - 1] + rows[targetRi]) / 2;
      const botY = targetRi === rows.length - 1
        ? rows[rows.length - 1] + HC
        : (rows[targetRi] + rows[targetRi + 1]) / 2;
      return { topY, botY };
    };

    const occupied = new Set();
    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      if (ri >= 0 && ci >= 0) occupied.add(`${ri},${ci}`);
    });

    const componentsWithImpedance = this.components.filter(c =>
      c.type === 'transistor' || c.type === 'matching' ||
      c.type === 'splitter'   || c.type === 'combiner' || c.type === 'termination'
    );

    if (componentsWithImpedance.length === 0) return;

    componentsWithImpedance.forEach((comp) => {
      let zFullPower, zBackoff, p1dbValue, backoffPower;

      if (comp.type === 'transistor') {
        p1dbValue    = comp.properties.p1db || comp.properties.pout || 40;
        backoffPower = p1dbValue - backoffDb;
        zFullPower   = this.calculateOptimalImpedance(comp, p1dbValue);
        zBackoff     = this.calculateOptimalImpedance(comp, backoffPower);
      } else if (comp.type === 'termination') {
        zFullPower   = comp.properties.impedance || 50;
        zBackoff     = zFullPower;
        p1dbValue    = null;
        backoffPower = null;
      } else {
        // matching / splitter / combiner
        zFullPower   = comp.properties.z_in  || comp.properties.impedance || 50;
        zBackoff     = comp.properties.z_out || zFullPower;
        p1dbValue    = null;
        backoffPower = null;
      }

      // Point 12: flag when both ports are at reference 50Ω (matched assumption)
      const isMatched = Math.abs(zFullPower - 50) < 0.5 &&
                        (comp.type === 'transistor' || Math.abs(zBackoff - 50) < 0.5);
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      const isMainSide = comp.y <= midY;
      let targetRi;
      if (isMainSide) {
        const prefer = ri - 1;
        if (prefer < 0 || !occupied.has(`${prefer},${ci}`)) {
          targetRi = prefer;
        } else {
          const alt = ri + 1;
          targetRi = (alt >= rows.length || !occupied.has(`${alt},${ci}`)) ? alt : prefer;
        }
      } else {
        const prefer = ri + 1;
        if (prefer >= rows.length || !occupied.has(`${prefer},${ci}`)) {
          targetRi = prefer;
        } else {
          const alt = ri - 1;
          targetRi = (alt < 0 || !occupied.has(`${alt},${ci}`)) ? alt : prefer;
        }
      }

      // Zone — impedance uses its dedicated slot (slot 3 = bottom position)
      const { topY: zTop, botY: zBot } = rowZone(targetRi);
      const { topY, botY } = this._getDisplaySlotBounds(zTop, zBot, 3);  // slot 3 = Impedance
      const cellH = Math.max(30, botY - topY);

      const BOX_W  = 2 * HC - 2 * PAD;  // 112 px — fills 120 px column
      const lineH  = Math.max(9, Math.min(13, Math.floor(cellH / 8)));
      const titleH = lineH + 2;
      const nLines = 2 + (comp.type === 'transistor' ? 1 : 0);  // full/BO + ref
      const contentH = titleH + lineH + nLines * lineH + PAD;
      const BOX_H  = Math.min(cellH - 2 * PAD, Math.max(contentH, 40));

      const boxX = comp.x - BOX_W / 2;
      const boxY = topY + (cellH - BOX_H) / 2;

      if (!comp.impedanceBoxOffset) comp.impedanceBoxOffset = { x: 0, y: 0 };

      const infoGroup = this.impedanceLayer.append('g')
        .attr('class', 'impedance-info-group')
        .attr('data-component-id', comp.id)
        .attr('transform', `translate(${boxX + comp.impedanceBoxOffset.x}, ${boxY + comp.impedanceBoxOffset.y})`)
        .style('cursor', 'move')
        .style('pointer-events', 'all');

      const drag = d3.drag()
        .on('start', (e) => { e.sourceEvent.stopPropagation(); infoGroup.raise().style('opacity', 0.7); })
        .on('drag',  (e) => {
          e.sourceEvent.stopPropagation();
          comp.impedanceBoxOffset.x += e.dx;
          comp.impedanceBoxOffset.y += e.dy;
          infoGroup.attr('transform', `translate(${boxX + comp.impedanceBoxOffset.x}, ${boxY + comp.impedanceBoxOffset.y})`);
        })
        .on('end', () => { infoGroup.style('opacity', 1); this.saveHistory(); });
      infoGroup.call(drag);

      const titleText = comp.type === 'transistor' ? 'Z_opt' :
                        comp.type === 'termination' ? 'Z_load' : 'Z_match';
      const titleColor = isMatched ? '#00e5ff' : '#ff7f11';

      // Background — border turns cyan when matched (50Ω assumption confirmed)
      infoGroup.append('rect')
        .attr('x', 0).attr('y', 0)
        .attr('width', BOX_W).attr('height', BOX_H)
        .attr('fill', '#1a2838').attr('stroke', titleColor)
        .attr('stroke-width', 1).attr('rx', 3);

      // Title
      infoGroup.append('text')
        .attr('x', BOX_W / 2).attr('y', titleH)
        .attr('text-anchor', 'middle').attr('fill', '#fff')
        .attr('font-size', `${titleH}px`).attr('font-weight', 'bold')
        .text(isMatched ? `${titleText} ✓` : titleText);

      let yo = titleH + lineH;  // full line-height gap after title

      const firstLabel = comp.type === 'transistor' ? 'Full' :
                         comp.type === 'termination' ? 'Z' : 'Z_in';
      infoGroup.append('text').attr('x', PAD).attr('y', yo)
        .attr('fill', '#00ff88').attr('font-size', `${lineH}px`)
        .text(`${firstLabel}: ${zFullPower.toFixed(1)}Ω`);
      yo += lineH;

      const secondLabel = comp.type === 'transistor' ? 'BO' :
                          comp.type === 'termination' ? '--' : 'Z_out';
      const secondValue  = comp.type === 'termination' ? '--' : `${zBackoff.toFixed(1)}Ω`;
      infoGroup.append('text').attr('x', PAD).attr('y', yo)
        .attr('fill', '#ffaa00').attr('font-size', `${lineH}px`)
        .text(`${secondLabel}: ${secondValue}`);
      yo += lineH;

      if (comp.type === 'transistor' && p1dbValue && backoffPower) {
        infoGroup.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#aaa').attr('font-size', `${Math.max(8, lineH - 2)}px`)
          .text(`(${p1dbValue.toFixed(1)} / ${backoffPower.toFixed(1)} dBm)`);
      } else if (isMatched) {
        // Point 12: explicit confirmation that port matching assumption holds
        infoGroup.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#00e5ff').attr('font-size', `${Math.max(8, lineH - 2)}px`)
          .text('matched (50\u03a9)');
      } else {
        infoGroup.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#aaa').attr('font-size', `${Math.max(8, lineH - 2)}px`)
          .text(`(${comp.properties.label || comp.type})`);
      }
    });

    console.log('Impedance columns drawn for', componentsWithImpedance.length, 'components');
  }

  /**
   * Draw dashed PA group boxes that visually encompass each transistor together
   * with its input matching network (IMN) and output matching network (OMN).
   * Also labels IMN/OMN with their z_in→z_out impedance transformation.
   */
  drawPaGroupBoxes() {
    // Remove previous group box overlays before redrawing
    this.componentsLayer.selectAll('.pa-group-box').remove();

    const transistors = this.components.filter(c => c.type === 'transistor');
    transistors.forEach(tx => {
      // IMN: matching net whose output port connects to transistor input
      const inputMatches = this.connections
        .filter(conn => String(conn.to) === String(tx.id) && conn.toPort === 'input')
        .map(conn => this.components.find(c => String(c.id) === String(conn.from)))
        .filter(c => c && c.type === 'matching');

      // OMN: matching net whose input port is connected from transistor output
      const outputMatches = this.connections
        .filter(conn => String(conn.from) === String(tx.id) && conn.fromPort === 'output')
        .map(conn => this.components.find(c => String(c.id) === String(conn.to)))
        .filter(c => c && c.type === 'matching');

      if (inputMatches.length === 0 && outputMatches.length === 0) return;

      const groupComps = [...inputMatches, tx, ...outputMatches];
      const xs = groupComps.map(c => c.x);
      const ys = groupComps.map(c => c.y);
      const pad = 38;
      const x1 = Math.min(...xs) - pad;
      const y1 = Math.min(...ys) - pad - 12;
      const x2 = Math.max(...xs) + pad + 42;
      const y2 = Math.max(...ys) + pad + 12;

      // Dashed bounding rectangle (inserted behind existing elements)
      this.componentsLayer.insert('rect', ':first-child')
        .attr('class', 'pa-group-box')
        .attr('x', x1).attr('y', y1)
        .attr('width', x2 - x1).attr('height', y2 - y1)
        .attr('rx', 8)
        .attr('fill', 'rgba(0,180,255,0.04)')
        .attr('stroke', 'rgba(0,180,255,0.40)')
        .attr('stroke-width', 1.5)
        .attr('stroke-dasharray', '6,4')
        .style('pointer-events', 'none');

      // Group label (top-left corner of the box)
      this.componentsLayer.append('text')
        .attr('class', 'pa-group-box')
        .attr('x', x1 + 6).attr('y', y1 + 12)
        .attr('fill', 'rgba(0,200,255,0.75)').attr('font-size', '9px')
        .attr('font-style', 'italic')
        .style('pointer-events', 'none')
        .text('PA: ' + (tx.properties.label || 'Transistor'));

      // IMN impedance label (above the input matching network)
      if (inputMatches.length > 0) {
        const imn  = inputMatches[0];
        const zIn  = (imn.properties.z_in  !== undefined) ? imn.properties.z_in  : 50;
        const zOut = (imn.properties.z_out !== undefined) ? imn.properties.z_out : 4;
        this.componentsLayer.append('text')
          .attr('class', 'pa-group-box')
          .attr('x', imn.x).attr('y', imn.y - 48)
          .attr('text-anchor', 'middle')
          .attr('fill', 'rgba(100,220,255,0.9)').attr('font-size', '8px')
          .style('pointer-events', 'none')
          .text('IMN: ' + zIn + '\u2192' + zOut + '\u03a9');
      }

      // OMN impedance label (above the output matching network)
      if (outputMatches.length > 0) {
        const omn  = outputMatches[0];
        const zIn  = (omn.properties.z_in  !== undefined) ? omn.properties.z_in  : 8;
        const zOut = (omn.properties.z_out !== undefined) ? omn.properties.z_out : 50;
        this.componentsLayer.append('text')
          .attr('class', 'pa-group-box')
          .attr('x', omn.x).attr('y', omn.y - 48)
          .attr('text-anchor', 'middle')
          .attr('fill', 'rgba(255,160,100,0.9)').attr('font-size', '8px')
          .style('pointer-events', 'none')
          .text('OMN: ' + zIn + '\u2192' + zOut + '\u03a9');
      }
    });
  }

  /**
   * Topology-aware component ordering using Kahn's BFS topological sort.
   * Falls back to left-to-right X-position sort when no connections exist.
   * This enables blank-canvas builds (point 14): components connected manually
   * by the user are traversed in signal-flow order, not visual position order.
   */
  _topoSortComponents() {
    const comps = this.components;
    if (!comps.length) return [];
    if (!this.connections || !this.connections.length) {
      // No wires drawn yet — fall back to X-position order
      return [...comps].sort((a, b) => a.x - b.x);
    }

    // Build adjacency: edges go from comp.id → successor comp.id
    const inDegree = new Map();
    const outEdges = new Map();
    comps.forEach(c => { inDegree.set(c.id, 0); outEdges.set(c.id, []); });

    this.connections.forEach(conn => {
      const fromId = String(conn.from);
      const toId   = String(conn.to);
      if (outEdges.has(fromId) && inDegree.has(toId)) {
        outEdges.get(fromId).push(toId);
        inDegree.set(toId, inDegree.get(toId) + 1);
      }
    });

    // Kahn's BFS — stable (X-sorted) when in-degree ties exist
    const compById = new Map(comps.map(c => [String(c.id), c]));
    const queue = comps
      .filter(c => inDegree.get(c.id) === 0)
      .sort((a, b) => a.x - b.x)
      .map(c => String(c.id));

    const result = [];
    while (queue.length) {
      const id = queue.shift();
      const comp = compById.get(id);
      if (comp) result.push(comp);
      (outEdges.get(id) || []).forEach(nextId => {
        inDegree.set(nextId, inDegree.get(nextId) - 1);
        if (inDegree.get(nextId) === 0) {
          // Insert into queue in X-sorted position
          const nextComp = compById.get(nextId);
          let inserted = false;
          for (let i = 0; i < queue.length; i++) {
            if ((compById.get(queue[i])?.x || 0) > (nextComp?.x || 0)) {
              queue.splice(i, 0, nextId);
              inserted = true;
              break;
            }
          }
          if (!inserted) queue.push(nextId);
        }
      });
    }

    // Append any remaining (disconnected) components in X order
    const resultIds = new Set(result.map(c => String(c.id)));
    comps
      .filter(c => !resultIds.has(String(c.id)))
      .sort((a, b) => a.x - b.x)
      .forEach(c => result.push(c));

    return result;
  }

  drawPowerColumns() {
    if (!this.showPowerDisplay) return;

    this.powerLayer.selectAll('*').remove();
    if (this.components.length === 0) return;

    const W = this.width, H = this.height;
    const HC = 60;
    const PAD = 4;

    // ── Component-aware rows & cols ──────────────────────────────────────────
    const rows = this._detectRows();   // sorted ascending Y
    const cols = this._detectCols();   // sorted ascending X

    const midY = rows.length > 1
      ? (rows[0] + rows[rows.length - 1]) / 2
      : (H / 2);

    // ── Structural lines (match drawGuideLines exactly) ─────────────────────
    const pLine = (x1, y1, x2, y2, mid) => {
      this.powerLayer.append('line')
        .attr('x1', x1).attr('y1', y1).attr('x2', x2).attr('y2', y2)
        .attr('stroke', mid ? '#00ddff' : '#00aaff')
        .attr('stroke-width', mid ? 2.5 : 1)
        .attr('stroke-dasharray', mid ? '12,4' : '6,4')
        .attr('opacity', mid ? 0.45 : 0.22);
    };

    // Horizontal boundaries + midline
    const hYs = new Set();
    hYs.add(rows[0] - HC);
    for (let i = 0; i < rows.length - 1; i++) hYs.add((rows[i] + rows[i + 1]) / 2);
    hYs.add(rows[rows.length - 1] + HC);
    if (rows.length > 1) hYs.add(midY);

    [...hYs].sort((a, b) => a - b).forEach(y => pLine(0, y, W, y, Math.abs(y - midY) < 1));

    // Vertical right-edge of each col
    cols.forEach(cx => pLine(cx + HC, 0, cx + HC, H, false));

    // ── Per-component power info box (one per element) ────────────────────
    // ── Helper: Y bounds for a row zone by index ────────────────────────────
    // targetRi: -1 = above-top zone,  rows.length = below-bottom zone
    const rowZone = (targetRi) => {
      if (targetRi < 0)
        return { topY: 0, botY: rows[0] - HC };
      if (targetRi >= rows.length)
        return { topY: rows[rows.length - 1] + HC, botY: H };
      const topY = targetRi === 0
        ? rows[0] - HC
        : (rows[targetRi - 1] + rows[targetRi]) / 2;
      const botY = targetRi === rows.length - 1
        ? rows[rows.length - 1] + HC
        : (rows[targetRi] + rows[targetRi + 1]) / 2;
      return { topY, botY };
    };

    // ── Build occupied-cell set ──────────────────────────────────────────────
    const occupied = new Set();
    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      if (ri >= 0 && ci >= 0) occupied.add(`${ri},${ci}`);
    });

    // ── Per-component power info boxes ───────────────────────────────────────
    // Use topology-aware ordering: connection-traversal order when wires exist,
    // otherwise fall back to X-position order (supports blank-canvas builds)
    const sorted = this._topoSortComponents();
    let currentPower = 0;

    sorted.forEach((comp, index) => {
      const powerInfo = this.calculateComponentPower(comp, currentPower, index === 0);
      currentPower = powerInfo.pout_dbm;

      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);

      // Main PA side (≤ midY) → prefer empty cell ABOVE; Aux PA side → prefer BELOW
      const isMainSide = comp.y <= midY;
      let targetRi;
      if (isMainSide) {
        const prefer = ri - 1;   // < 0 → above-top zone (always empty)
        if (prefer < 0 || !occupied.has(`${prefer},${ci}`)) {
          targetRi = prefer;
        } else {
          const alt = ri + 1;
          targetRi = (alt >= rows.length || !occupied.has(`${alt},${ci}`)) ? alt : prefer;
        }
      } else {
        const prefer = ri + 1;   // ≥ rows.length → below-bottom zone (always empty)
        if (prefer >= rows.length || !occupied.has(`${prefer},${ci}`)) {
          targetRi = prefer;
        } else {
          const alt = ri - 1;
          targetRi = (alt < 0 || !occupied.has(`${alt},${ci}`)) ? alt : prefer;
        }
      }

      // Cell bounds — power box occupies its dedicated slot within the zone
      const { topY: zTop, botY: zBot } = rowZone(targetRi);
      const { topY, botY } = this._getDisplaySlotBounds(zTop, zBot, 0);  // slot 0 = Power
      const cellH = Math.max(30, botY - topY);

      // Box sized to fill the 120 px column cell
      const BOX_W = 2 * HC - 2 * PAD;          // 112 px
      const lineH  = Math.max(9, Math.min(13, Math.floor(cellH / 8)));
      const titleH = lineH + 2;
      const nLines = 2 + (powerInfo.p1db_dbm ? 1 : 0) + (powerInfo.power_bo_dbm ? 1 : 0);
      const contentH = titleH + lineH + nLines * lineH + PAD;  // full line-gap after title
      const BOX_H = Math.min(cellH - 2 * PAD, Math.max(contentH, 40));

      // Centred in the target cell at the component's column
      const boxX = comp.x - BOX_W / 2;
      const boxY = topY + (cellH - BOX_H) / 2;

      if (!comp.powerBoxOffset) comp.powerBoxOffset = { x: 0, y: 0 };

      const infoGroup = this.powerLayer.append('g')
        .attr('class', 'power-info-group')
        .attr('data-component-id', comp.id)
        .attr('transform', `translate(${boxX + comp.powerBoxOffset.x}, ${boxY + comp.powerBoxOffset.y})`)
        .style('cursor', 'move')
        .style('pointer-events', 'all');

      const drag = d3.drag()
        .on('start', (e) => { e.sourceEvent.stopPropagation(); infoGroup.raise().style('opacity', 0.7); })
        .on('drag',  (e) => {
          e.sourceEvent.stopPropagation();
          comp.powerBoxOffset.x += e.dx;
          comp.powerBoxOffset.y += e.dy;
          infoGroup.attr('transform', `translate(${boxX + comp.powerBoxOffset.x}, ${boxY + comp.powerBoxOffset.y})`);
        })
        .on('end', () => { infoGroup.style('opacity', 1); this.saveHistory(); });
      infoGroup.call(drag);

      // Background rect
      infoGroup.append('rect')
        .attr('x', 0).attr('y', 0)
        .attr('width', BOX_W).attr('height', BOX_H)
        .attr('fill', '#1a1a1a').attr('stroke', '#00aaff')
        .attr('stroke-width', 1).attr('rx', 3);

      // Title
      infoGroup.append('text')
        .attr('x', BOX_W / 2).attr('y', titleH)
        .attr('text-anchor', 'middle').attr('fill', '#fff')
        .attr('font-size', `${titleH}px`).attr('font-weight', 'bold')
        .text(comp.properties.label || comp.type);

      let yo = titleH + lineH;  // full line-height gap separates heading from data
      infoGroup.append('text').attr('x', PAD).attr('y', yo)
        .attr('fill', '#00ff88').attr('font-size', `${lineH}px`)
        .text(`Pin: ${this.formatPower(powerInfo.pin_dbm, this.powerUnit)}`);
      yo += lineH;

      infoGroup.append('text').attr('x', PAD).attr('y', yo)
        .attr('fill', '#ff7f11').attr('font-size', `${lineH}px`)
        .text(`Pout: ${this.formatPower(powerInfo.pout_dbm, this.powerUnit)}`);
      yo += lineH;

      if (powerInfo.p1db_dbm) {
        infoGroup.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ffaa00').attr('font-size', `${lineH}px`)
          .text(`P1dB: ${this.formatPower(powerInfo.p1db_dbm, this.powerUnit)}`);
        yo += lineH;
      }

      if (powerInfo.power_bo_dbm) {
        infoGroup.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ffaa00').attr('font-size', `${lineH}px`)
          .text(`P_BO: ${this.formatPower(powerInfo.power_bo_dbm, this.powerUnit)}`);
      }
    });

    console.log('Power columns drawn for', sorted.length, 'components');
  }
  
  formatPower(power_dbm, unit) {
    // Guard against null / undefined / NaN
    const v = parseFloat(power_dbm);
    if (!isFinite(v)) return '—';

    // dBm → Watts:  P(W) = 10^((P(dBm)−30)/10)
    const power_w = Math.pow(10, (v - 30) / 10);

    // Smart W/mW/µW scaling
    const fmtW = (w) => {
      if (w >= 1)       return `${w.toFixed(2)} W`;
      if (w >= 0.001)   return `${(w * 1000).toFixed(1)} mW`;
      return `${(w * 1e6).toFixed(0)} µW`;
    };

    switch (unit) {
      case 'dBm': return `${v.toFixed(1)} dBm`;
      case 'W':   return fmtW(power_w);
      case 'both': return `${v.toFixed(1)} dBm (${fmtW(power_w)})`;
      default:    return `${v.toFixed(1)} dBm`;
    }
  }
  
  calculateComponentPower(component, previousPout, isFirst) {
    const props = component.properties;
    let pin_dbm, pout_dbm, p1db_dbm, backoff_db, power_bo_dbm;
    
    // Get input power — prefer R-synced values when available
    if (isFirst) {
      // First component: use R-synced pin_p3db if set, else spec pin, else 0
      pin_dbm = props.pin_p3db ?? props.pin ?? (window.currentLineupSpecs
        ? (window.currentLineupSpecs.p3db - (window.currentLineupSpecs.gain || 30))
        : 0);
    } else {
      // Subsequent components: use R-synced input if set, else carry previous output
      pin_dbm = props.pin_p3db ?? previousPout;
    }
    
    // If R has already computed and synced pout_p3db, use it directly (source of truth)
    // Guard: skip R-synced value if it parsed to NaN (e.g., R returned "NaN" string)
    const rPout = parseFloat(props.pout_p3db);
    if (props.pout_p3db !== undefined && props.pout_p3db !== null && isFinite(rPout)) {
      pout_dbm = rPout;
      // For P1dB: must be AT MOST equal to pout (P1dB ≤ Pout — compression point is at or below operating Pout)
      const rawP1dB = props.p1db ?? props.pout ?? 40;
      p1db_dbm = Math.min(parseFloat(rawP1dB), pout_dbm);
      // Backoff from R-synced values
      const rPavg = parseFloat(props.pout_pavg);
      if (props.pout_pavg !== undefined && props.pout_pavg !== null && isFinite(rPavg)) {
        power_bo_dbm = rPavg;
        backoff_db   = pout_dbm - power_bo_dbm;
      } else {
        const par = window.currentLineupSpecs ? (window.currentLineupSpecs.par || 8) : 8;
        backoff_db   = par;
        power_bo_dbm = pout_dbm - backoff_db;
      }
      return { pin_dbm, pout_dbm, p1db_dbm, backoff_db, power_bo_dbm };
    }
    
    // Calculate output power based on component type (fallback when R hasn't synced yet)
    switch (component.type) {
      case 'transistor':
        const gain = props.gain || 10;
        pout_dbm = pin_dbm + gain;
        // P1dB: compression point is at or below Pout.  Use explicit p1db property
        // if set; fall back to pout - 2 (2 dB below operating point — typical 1dB compression offset)
        const rawP1dB = props.p1db ?? (pout_dbm - 2);
        p1db_dbm = Math.min(parseFloat(rawP1dB), pout_dbm);
        
        // Back-off power
        const par = window.currentLineupSpecs ? (window.currentLineupSpecs.par || 8) : 8;
        if (props.backoff_db !== undefined) {
          backoff_db = props.backoff_db;
        } else if (props.papr_db !== undefined) {
          backoff_db = props.papr_db;
        } else {
          backoff_db = par;
        }
        power_bo_dbm = pout_dbm - backoff_db;
        break;
        
      case 'matching':
        const loss = props.loss || 0.5;
        pout_dbm = pin_dbm - loss;
        break;
        
      case 'splitter':
        const split_loss = props.loss || 3;
        pout_dbm = pin_dbm - split_loss;
        break;
        
      case 'combiner': {
        const combine_loss = props.loss || 0.3;

        // ── Recursive helper: follow connections backwards through passives ──
        // Returns the true RF output power (dBm) at the output port of `comp`,
        // propagating losses through matching/splitter stages until a transistor
        // (or source node) is reached.
        const traceOutputPower = (comp, _visited = new Set()) => {
          if (!comp || _visited.has(comp.id)) return 40; // cycle guard / missing
          _visited.add(comp.id);

          if (comp.type === 'transistor') {
            // Prefer JS dual-op values set by applySpecsToComponents; else legacy fields
            return comp.properties.pout_p3db
              ?? comp.properties.pout
              ?? comp.properties.p1db
              ?? 40;
          }

          // Passive component — find its single predecessor and subtract its loss
          const predConn = this.connections.find(c => c.to == comp.id);
          if (!predConn) {
            // Source-node passive (unusual) — use stored pout if any, else chain value
            return comp.properties.pout ?? comp.properties.p3db ?? pin_dbm;
          }
          const pred = this.components.find(c => c.id == predConn.from);
          const predPout = traceOutputPower(pred, _visited);

          if (comp.type === 'matching') {
            return predPout - (comp.properties.loss ?? 0.5);
          }
          if (comp.type === 'splitter') {
            const nWays = Math.max(this.connections.filter(c => c.from == comp.id).length, 2);
            return predPout - 10 * Math.log10(nWays) - (comp.properties.loss ?? 0.3);
          }
          // Unknown passive — pass through
          return predPout - (comp.properties.loss ?? 0);
        };

        // ── Find all wires connected into this combiner ───────────────────
        const inputConns = this.connections.filter(c => c.to == component.id);

        if (inputConns.length >= 2) {
          // Sum all predecessor outputs (traced back through passives) in watts
          let totalWatts = 0;
          inputConns.forEach(conn => {
            const predComp = this.components.find(c => c.id == conn.from);
            const p_dbm = traceOutputPower(predComp);
            totalWatts += Math.pow(10, (p_dbm - 30) / 10);
            console.log(`[Combiner] input from ${predComp?.properties?.label ?? conn.from}: ${p_dbm.toFixed(2)} dBm`);
          });
          pin_dbm  = totalWatts > 0 ? 10 * Math.log10(totalWatts) + 30 : pin_dbm;
          pout_dbm = pin_dbm - combine_loss;
          console.log(`[Combiner] ${inputConns.length}-way sum → combined_in=${pin_dbm.toFixed(2)} dBm, pout=${pout_dbm.toFixed(2)} dBm`);

        } else if (inputConns.length === 1) {
          // Single-wire input (degenerate combiner) — just trace and subtract loss
          const predComp = this.components.find(c => c.id == inputConns[0].from);
          pin_dbm  = traceOutputPower(predComp);
          pout_dbm = pin_dbm - combine_loss;

        } else {
          // No connections — assume N equal inputs from the linear chain value
          const ways = props.ways || 2;
          pout_dbm = pin_dbm + 10 * Math.log10(ways) - combine_loss;
        }
        break;
      }
        
      default:
        pout_dbm = pin_dbm;
    }
    
    return {
      pin_dbm,
      pout_dbm,
      p1db_dbm,
      backoff_db,
      power_bo_dbm
    };
  }

  // ── Slot-aware zone helper ───────────────────────────────────────────────
  // Divides each row-zone cell into 4 vertical slots when multiple displays
  // are active simultaneously, preventing overlap.
  // Slot layout (top → bottom within the cell):
  //   0 = Power   (top quarter)
  //   1 = Gain    (second quarter)
  //   2 = PAE     (third quarter)
  //   3 = Impedance (bottom quarter)
  _getDisplaySlotBounds(topY, botY, slotIndex) {
    // Displays are split into two NON-OVERLAPPING groups so they never compete
    // for the same vertical space:
    //   Group A (top half of zone)  — Power (0), Gain (1)
    //   Group B (bottom half of zone) — PAE (2), Impedance (3), Phase (4)
    const isTopGroup = slotIndex <= 1;
    const midY = (topY + botY) / 2;
    const zoneTop = isTopGroup ? topY  : midY;
    const zoneBot = isTopGroup ? midY  : botY;

    const topGroupOrder = [];
    if (this.showPowerDisplay) topGroupOrder.push(0);
    if (this.showGainDisplay)  topGroupOrder.push(1);

    const botGroupOrder = [];
    if (this.showPAEDisplay)       botGroupOrder.push(2);
    if (this.showImpedanceDisplay) botGroupOrder.push(3);
    if (this.showPhaseDisplay)     botGroupOrder.push(4);

    const order = isTopGroup ? topGroupOrder : botGroupOrder;
    const nSlots = order.length || 1;
    const slotH  = (zoneBot - zoneTop) / nSlots;
    const pos    = order.indexOf(slotIndex);
    if (pos < 0) return { topY, botY };  // not active — shouldn't happen
    return {
      topY: zoneTop + pos * slotH,
      botY: zoneTop + (pos + 1) * slotH
    };
  }

  // ── Draw Gain per-stage info boxes ─────────────────────────────────────────
  drawGainColumns() {
    if (!this.showGainDisplay) return;
    this.gainLayer.selectAll('*').remove();
    if (this.components.length === 0) return;

    const HC = 60, PAD = 4;
    const rows = this._detectRows();
    const cols = this._detectCols();
    const midY = rows.length > 1 ? (rows[0] + rows[rows.length - 1]) / 2 : this.height / 2;

    const rowZone = (targetRi) => {
      if (targetRi < 0)            return { topY: 0, botY: rows[0] - HC };
      if (targetRi >= rows.length) return { topY: rows[rows.length - 1] + HC, botY: this.height };
      const topY = targetRi === 0 ? rows[0] - HC : (rows[targetRi-1] + rows[targetRi]) / 2;
      const botY = targetRi === rows.length - 1 ? rows[rows.length-1] + HC : (rows[targetRi] + rows[targetRi+1]) / 2;
      return { topY, botY };
    };

    const occupied = new Set();
    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      if (ri >= 0 && ci >= 0) occupied.add(`${ri},${ci}`);
    });

    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      const isMainSide = comp.y <= midY;
      let targetRi;
      if (isMainSide) {
        const prefer = ri - 1;
        targetRi = (prefer < 0 || !occupied.has(`${prefer},${ci}`)) ? prefer
          : (!occupied.has(`${ri+1},${ci}`) ? ri + 1 : prefer);
      } else {
        const prefer = ri + 1;
        targetRi = (prefer >= rows.length || !occupied.has(`${prefer},${ci}`)) ? prefer
          : (ri - 1 < 0 || !occupied.has(`${ri-1},${ci}`) ? ri - 1 : prefer);
      }

      const { topY: zTop, botY: zBot } = rowZone(targetRi);
      const { topY, botY } = this._getDisplaySlotBounds(zTop, zBot, 1);  // slot 1 = Gain
      const cellH = Math.max(24, botY - topY);

      const BOX_W = 2 * HC - 2 * PAD;
      const lineH  = Math.max(8, Math.min(12, Math.floor(cellH / 6)));
      const titleH = lineH + 2;
      const BOX_H  = Math.min(cellH - 2 * PAD, Math.max(titleH + 3 * lineH + PAD, 32));
      const boxX = comp.x - BOX_W / 2;
      const boxY = topY + (cellH - BOX_H) / 2;

      if (!comp.gainBoxOffset) comp.gainBoxOffset = { x: 0, y: 0 };

      const g = this.gainLayer.append('g')
        .attr('class', 'gain-info-group')
        .attr('data-component-id', comp.id)
        .attr('transform', `translate(${boxX + comp.gainBoxOffset.x}, ${boxY + comp.gainBoxOffset.y})`)
        .style('cursor', 'move').style('pointer-events', 'all');

      g.call(d3.drag()
        .on('start', (e) => { e.sourceEvent.stopPropagation(); g.raise().style('opacity', 0.7); })
        .on('drag',  (e) => { e.sourceEvent.stopPropagation();
          comp.gainBoxOffset.x += e.dx; comp.gainBoxOffset.y += e.dy;
          g.attr('transform', `translate(${boxX + comp.gainBoxOffset.x}, ${boxY + comp.gainBoxOffset.y})`); })
        .on('end', () => { g.style('opacity', 1); this.saveHistory(); }));

      g.append('rect').attr('x', 0).attr('y', 0)
        .attr('width', BOX_W).attr('height', BOX_H)
        .attr('fill', '#1a2010').attr('stroke', '#4CAF50')
        .attr('stroke-width', 1).attr('rx', 3);

      g.append('text').attr('x', BOX_W/2).attr('y', titleH)
        .attr('text-anchor', 'middle').attr('fill', '#fff')
        .attr('font-size', `${titleH}px`).attr('font-weight', 'bold')
        .text('Gain');

      let yo = titleH + lineH;
      const props = comp.properties;

      // Prefer R-synced values; fall back to component property inputs
      const gainP3dB = props.gain_full_db ?? props.gain_p3db ?? props.gain ?? null;
      const gainBO   = props.gain_bo_db   ?? props.gain_bo   ?? gainP3dB;

      if (gainP3dB !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#00ff88').attr('font-size', `${lineH}px`)
          .text(`@P3dB: ${parseFloat(gainP3dB).toFixed(1)} dB`);
        yo += lineH;
      }
      if (gainBO !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ffaa00').attr('font-size', `${lineH}px`)
          .text(`@BO:   ${parseFloat(gainBO).toFixed(1)} dB`);
        yo += lineH;
      }
      if (comp.type === 'matching' || comp.type === 'splitter' || comp.type === 'combiner') {
        const lossVal = props.loss ?? 0.5;
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ff7777').attr('font-size', `${lineH}px`)
          .text(`Loss: ${parseFloat(lossVal).toFixed(2)} dB`);
      }
    });
    console.log('Gain columns drawn for', this.components.length, 'components');
  }

  // ── Draw PAE per-stage info boxes ─────────────────────────────────────────
  drawPAEColumns() {
    if (!this.showPAEDisplay) return;
    this.paeLayer.selectAll('*').remove();
    if (this.components.length === 0) return;

    const HC = 60, PAD = 4;
    const rows = this._detectRows();
    const cols = this._detectCols();
    const midY = rows.length > 1 ? (rows[0] + rows[rows.length - 1]) / 2 : this.height / 2;

    const rowZone = (targetRi) => {
      if (targetRi < 0)            return { topY: 0, botY: rows[0] - HC };
      if (targetRi >= rows.length) return { topY: rows[rows.length - 1] + HC, botY: this.height };
      const topY = targetRi === 0 ? rows[0] - HC : (rows[targetRi-1] + rows[targetRi]) / 2;
      const botY = targetRi === rows.length - 1 ? rows[rows.length-1] + HC : (rows[targetRi] + rows[targetRi+1]) / 2;
      return { topY, botY };
    };

    const occupied = new Set();
    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      if (ri >= 0 && ci >= 0) occupied.add(`${ri},${ci}`);
    });

    this.components.forEach(comp => {
      if (comp.type !== 'transistor') return;  // PAE only meaningful for transistors
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      const isMainSide = comp.y <= midY;
      let targetRi;
      if (isMainSide) {
        const prefer = ri - 1;
        targetRi = (prefer < 0 || !occupied.has(`${prefer},${ci}`)) ? prefer
          : (!occupied.has(`${ri+1},${ci}`) ? ri + 1 : prefer);
      } else {
        const prefer = ri + 1;
        targetRi = (prefer >= rows.length || !occupied.has(`${prefer},${ci}`)) ? prefer
          : (ri - 1 < 0 || !occupied.has(`${ri-1},${ci}`) ? ri - 1 : prefer);
      }

      const { topY: zTop, botY: zBot } = rowZone(targetRi);
      const { topY, botY } = this._getDisplaySlotBounds(zTop, zBot, 2);  // slot 2 = PAE
      const cellH = Math.max(24, botY - topY);

      const BOX_W = 2 * HC - 2 * PAD;
      const lineH  = Math.max(8, Math.min(12, Math.floor(cellH / 6)));
      const titleH = lineH + 2;
      const BOX_H  = Math.min(cellH - 2 * PAD, Math.max(titleH + 4 * lineH + PAD, 36));
      const boxX = comp.x - BOX_W / 2;
      const boxY = topY + (cellH - BOX_H) / 2;

      if (!comp.paeBoxOffset) comp.paeBoxOffset = { x: 0, y: 0 };

      const g = this.paeLayer.append('g')
        .attr('class', 'pae-info-group')
        .attr('data-component-id', comp.id)
        .attr('transform', `translate(${boxX + comp.paeBoxOffset.x}, ${boxY + comp.paeBoxOffset.y})`)
        .style('cursor', 'move').style('pointer-events', 'all');

      g.call(d3.drag()
        .on('start', (e) => { e.sourceEvent.stopPropagation(); g.raise().style('opacity', 0.7); })
        .on('drag',  (e) => { e.sourceEvent.stopPropagation();
          comp.paeBoxOffset.x += e.dx; comp.paeBoxOffset.y += e.dy;
          g.attr('transform', `translate(${boxX + comp.paeBoxOffset.x}, ${boxY + comp.paeBoxOffset.y})`); })
        .on('end', () => { g.style('opacity', 1); this.saveHistory(); }));

      g.append('rect').attr('x', 0).attr('y', 0)
        .attr('width', BOX_W).attr('height', BOX_H)
        .attr('fill', '#1a1020').attr('stroke', '#9c27b0')
        .attr('stroke-width', 1).attr('rx', 3);

      g.append('text').attr('x', BOX_W/2).attr('y', titleH)
        .attr('text-anchor', 'middle').attr('fill', '#fff')
        .attr('font-size', `${titleH}px`).attr('font-weight', 'bold')
        .text('PAE / DE');

      let yo = titleH + lineH;
      const props = comp.properties;

      // Prefer R-synced values
      const paeP3dB = props.pae_p3db ?? props.pae ?? null;
      const paeBO   = props.pae_pavg ?? props.pae_bo ?? paeP3dB;
      const deP3dB  = props.de_p3db  ?? null;
      const deBO    = props.de_pavg  ?? null;

      if (paeP3dB !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#00ff88').attr('font-size', `${lineH}px`)
          .text(`PAE@P3dB: ${parseFloat(paeP3dB).toFixed(0)}%`);
        yo += lineH;
      }
      if (paeBO !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ffaa00').attr('font-size', `${lineH}px`)
          .text(`PAE@BO:   ${parseFloat(paeBO).toFixed(0)}%`);
        yo += lineH;
      }
      if (deP3dB !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#cc88ff').attr('font-size', `${lineH}px`)
          .text(`DE@P3dB:  ${parseFloat(deP3dB).toFixed(0)}%`);
        yo += lineH;
      }
      if (deBO !== null) {
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ff88aa').attr('font-size', `${lineH}px`)
          .text(`DE@BO:    ${parseFloat(deBO).toFixed(0)}%`);
      }
    });
    console.log('PAE columns drawn for', this.components.filter(c => c.type === 'transistor').length, 'transistors');
  }

  // ── Phase shift per component (default rules) ─────────────────────────────
  _getComponentPhaseShift(comp, fromPort) {
    // Explicit override takes priority
    if (comp.properties.phase_shift !== undefined) return comp.properties.phase_shift;
    switch (comp.type) {
      case 'transistor':  return 0;
      case 'termination': return 0;
      case 'combiner':    return 0;
      case 'dc_supply':   return 0;
      case 'splitter':
        // 90° hybrid: output2 gets an extra 90° applied at the edge level
        return 0;
      case 'matching': {
        const mt = comp.properties.matchType || 'generic';
        if (mt === 'Transformer' || mt === 'TL-stub') return 90;
        return 0;
      }
      default: return 0;
    }
  }

  // ── Compute running phase for every component (BFS signal-flow) ──────────
  _computeSignalPaths() {
    // Returns Map<String(comp.id), {phaseIn, phaseShift, phaseOut, portPhases}>
    // portPhases: {portName: phase} — for combiners shows both inputs
    const phaseAtPort = new Map(); // key: "compId:port" → phase (degrees)

    // Seed sources (components with no incoming connections)
    const incomingIds = new Set(this.connections.map(c => String(c.to)));
    this.components
      .filter(c => !incomingIds.has(String(c.id)))
      .forEach(src => {
        phaseAtPort.set(`${src.id}:input`,  0);
        phaseAtPort.set(`${src.id}:input1`, 0);
        phaseAtPort.set(`${src.id}:input2`, 0);
      });

    // Walk in topological order
    const sorted = this._topoSortComponents();
    const info = new Map();

    sorted.forEach(comp => {
      const cid = String(comp.id);
      // Gather all input port phases for this component
      const portPhases = {};
      this.connections
        .filter(c => String(c.to) === cid)
        .forEach(c => {
          const key = `${c.from}:${c.fromPort}`;
          const srcPhase = phaseAtPort.get(key) ?? 0;
          portPhases[c.toPort] = srcPhase;
        });

      // Dominant input = first port found, or 0
      const phaseIn = Object.values(portPhases)[0] ?? 0;
      const phaseShift = this._getComponentPhaseShift(comp);
      const phaseOut   = phaseIn + phaseShift;

      info.set(cid, { phaseIn, phaseShift, phaseOut, portPhases });

      // Propagate outgoing
      this.connections
        .filter(c => String(c.from) === cid)
        .forEach(c => {
          let propagated = phaseOut;
          // 90° hybrid splitter: second output gets +90° relative to first
          if (comp.type === 'splitter' &&
              (comp.properties.type === 'Hybrid' || comp.properties.type === '90° Hybrid') &&
              c.fromPort === 'output2') {
            propagated = phaseIn + 90;
          }
          phaseAtPort.set(`${c.from}:${c.fromPort}`, propagated);
          // Store at destination port too
          phaseAtPort.set(`${c.to}:${c.toPort}`, propagated);
        });
    });

    return info;
  }

  // ── Normalise angle to [0, 360) ───────────────────────────────────────────
  _normPhase(deg) { return ((deg % 360) + 360) % 360; }

  // ── Draw Phase per-stage info boxes ───────────────────────────────────────
  drawPhaseColumns() {
    if (!this.showPhaseDisplay) return;
    this.phaseLayer.selectAll('*').remove();
    if (this.components.length === 0) return;

    const phaseInfo  = this._computeSignalPaths();
    const HC = 60, PAD = 4;
    const rows = this._detectRows();
    const cols = this._detectCols();
    const midY = rows.length > 1 ? (rows[0] + rows[rows.length - 1]) / 2 : this.height / 2;

    const rowZone = (targetRi) => {
      if (targetRi < 0)            return { topY: 0, botY: rows[0] - HC };
      if (targetRi >= rows.length) return { topY: rows[rows.length - 1] + HC, botY: this.height };
      const topY = targetRi === 0 ? rows[0] - HC : (rows[targetRi - 1] + rows[targetRi]) / 2;
      const botY = targetRi === rows.length - 1
        ? rows[rows.length - 1] + HC
        : (rows[targetRi] + rows[targetRi + 1]) / 2;
      return { topY, botY };
    };

    const occupied = new Set();
    this.components.forEach(comp => {
      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      if (ri >= 0 && ci >= 0) occupied.add(`${ri},${ci}`);
    });

    this.components.forEach(comp => {
      const cid   = String(comp.id);
      const pInfo = phaseInfo.get(cid);
      if (!pInfo) return;

      const ri = rows.findIndex(r => Math.abs(r - comp.y) < 60);
      const ci = cols.findIndex(c => Math.abs(c - comp.x) < 60);
      const isMainSide = comp.y <= midY;

      // Phase (slot 4) is in Group B → prefer BELOW for main, ABOVE for aux
      let targetRi;
      if (isMainSide) {
        const prefer = ri + 1;  // below
        targetRi = (prefer < rows.length && !occupied.has(`${prefer},${ci}`)) ? prefer
          : (ri - 1 >= 0 && !occupied.has(`${ri - 1},${ci}`) ? ri - 1 : prefer);
      } else {
        const prefer = ri - 1;  // above
        targetRi = (prefer >= 0 && !occupied.has(`${prefer},${ci}`)) ? prefer
          : (ri + 1 < rows.length && !occupied.has(`${ri + 1},${ci}`) ? ri + 1 : prefer);
      }

      const { topY: zTop, botY: zBot } = rowZone(targetRi);
      const { topY, botY } = this._getDisplaySlotBounds(zTop, zBot, 4); // slot 4 = Phase
      const slotH = Math.max(20, botY - topY);

      const BOX_W   = 2 * HC - 2 * PAD;
      const lineH   = Math.max(7, Math.min(11, Math.floor((slotH - 12 - PAD) / 3)));
      const titleH  = lineH + 2;
      // Combiner gets extra lines for multi-port phase display
      const isCombiner = comp.type === 'combiner';
      const nLines  = isCombiner
        ? Math.max(Object.keys(pInfo.portPhases).length + 1, 2)
        : 2;
      const BOX_H   = Math.min(slotH - 2 * PAD, titleH + nLines * lineH + PAD);
      const boxX    = comp.x - BOX_W / 2;
      const boxY    = topY + (slotH - BOX_H) / 2;

      if (!comp.phaseBoxOffset) comp.phaseBoxOffset = { x: 0, y: 0 };

      const g = this.phaseLayer.append('g')
        .attr('class', 'phase-info-group')
        .attr('data-component-id', cid)
        .attr('transform', `translate(${boxX + comp.phaseBoxOffset.x}, ${boxY + comp.phaseBoxOffset.y})`)
        .style('cursor', 'move').style('pointer-events', 'all');

      g.call(d3.drag()
        .on('start', (e) => { e.sourceEvent.stopPropagation(); g.raise().style('opacity', 0.7); })
        .on('drag',  (e) => {
          e.sourceEvent.stopPropagation();
          comp.phaseBoxOffset.x += e.dx;
          comp.phaseBoxOffset.y += e.dy;
          g.attr('transform', `translate(${boxX + comp.phaseBoxOffset.x}, ${boxY + comp.phaseBoxOffset.y})`);
        })
        .on('end', () => { g.style('opacity', 1); this.saveHistory(); }));

      // Combiner: check if inputs are in-phase (within ±10°)
      let borderColor = '#e040fb'; // default magenta
      if (isCombiner && Object.keys(pInfo.portPhases).length >= 2) {
        const vals = Object.values(pInfo.portPhases).map(p => this._normPhase(p));
        const spread = Math.max(...vals) - Math.min(...vals);
        const balanced = spread <= 10 || spread >= 350;
        borderColor = balanced ? '#00e676' : '#ff1744';
      }

      g.append('rect').attr('x', 0).attr('y', 0)
        .attr('width', BOX_W).attr('height', BOX_H)
        .attr('fill', '#120a1e').attr('stroke', borderColor)
        .attr('stroke-width', isCombiner ? 2 : 1).attr('rx', 3);

      g.append('text').attr('x', BOX_W / 2).attr('y', titleH)
        .attr('text-anchor', 'middle').attr('fill', '#fff')
        .attr('font-size', `${titleH}px`).attr('font-weight', 'bold')
        .text('Phase');

      let yo = titleH + lineH;

      if (isCombiner) {
        // Show each input port's incoming phase
        const ports = Object.entries(pInfo.portPhases);
        ports.forEach(([port, ph]) => {
          const norm = this._normPhase(ph);
          const label = port.replace('input', 'In');
          g.append('text').attr('x', PAD).attr('y', yo)
            .attr('fill', '#e040fb').attr('font-size', `${lineH}px`)
            .text(`${label}: ${norm.toFixed(0)}\u00b0`);
          yo += lineH;
        });
        if (ports.length >= 2) {
          const vals   = ports.map(([, p]) => this._normPhase(p));
          const spread = Math.abs(vals[0] - vals[1]);
          const diff   = Math.min(spread, 360 - spread);
          const ok     = diff <= 10;
          g.append('text').attr('x', PAD).attr('y', yo)
            .attr('fill', ok ? '#00e676' : '#ff1744')
            .attr('font-size', `${lineH}px`).attr('font-weight', 'bold')
            .text(ok ? `\u2206=${diff.toFixed(0)}\u00b0 \u2714 In-phase` : `\u2206=${diff.toFixed(0)}\u00b0 \u26a0 OOphase`);
        }
      } else {
        // Regular component: show Δφ and running phase out
        const dPhase = pInfo.phaseShift;
        const phOut  = this._normPhase(pInfo.phaseOut);
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#e040fb').attr('font-size', `${lineH}px`)
          .text(`\u0394\u03c6: ${dPhase >= 0 ? '+' : ''}${dPhase}\u00b0`);
        yo += lineH;
        g.append('text').attr('x', PAD).attr('y', yo)
          .attr('fill', '#ce93d8').attr('font-size', `${lineH}px`)
          .text(`\u03c6out: ${phOut.toFixed(0)}\u00b0`);
      }
    });

    console.log('Phase columns drawn for', this.components.length, 'components');
  }

  exportConfiguration() {
    return {
      components: this.components,
      connections: this.connections,
      metadata: {
        timestamp: new Date().toISOString(),
        version: '1.0'
      }
    };
  }
  
  importConfiguration(config) {
    this.clear();
    config.components.forEach(comp => {
      this.addComponent(comp.type, comp.x, comp.y, comp.properties);
    });
  }
  
  /**
   * Validate that all components are properly connected
   * Returns {valid: boolean, errors: string[], warnings: string[]}
   */
  validateConnections() {
    const errors = [];
    const warnings = [];
    
    if (this.components.length === 0) {
      errors.push('No components in lineup');
      return { valid: false, errors, warnings };
    }
    
    if (this.components.length === 1) {
      warnings.push('Only one component - no connections needed');
      return { valid: true, errors, warnings };
    }
    
    // Check each component (except first) has input connection
    this.components.forEach((comp, index) => {
      if (index === 0) return; // First component doesn't need input
      
      const hasInput = this.connections.some(conn => conn.to === comp.id);
      if (!hasInput) {
        errors.push(`${comp.properties.label || 'Component ' + comp.id} has no input connection`);
      }
    });
    
    // Check each component (except last) has output connection
    this.components.forEach((comp, index) => {
      if (index === this.components.length - 1) return; // Last component doesn't need output
      
      const hasOutput = this.connections.some(conn => conn.from === comp.id);
      if (!hasOutput) {
        warnings.push(`${comp.properties.label || 'Component ' + comp.id} has no output connection`);
      }
    });
    
    // Check for isolated components (no connections at all)
    this.components.forEach(comp => {
      const hasConnection = this.connections.some(conn => 
        conn.from === comp.id || conn.to === comp.id
      );
      if (!hasConnection && this.components.length > 1) {
        errors.push(`${comp.properties.label || 'Component ' + comp.id} is completely disconnected`);
      }
    });
    
    return {
      valid: errors.length === 0,
      errors,
      warnings
    };
  }
  
  /**
   * Show validation results with visual feedback
   */
  showValidationResults() {
    const result = this.validateConnections();
    
    // Clear previous highlights
    this.componentsLayer.selectAll('.component')
      .classed('invalid', false)
      .classed('warning', false);
    
    if (result.valid && result.warnings.length === 0) {
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: '✓ All components properly connected',
          type: 'message'
        });
      }
      return true;
    }
    
    // Highlight disconnected components
    if (result.errors.length > 0) {
      this.components.forEach(comp => {
        const hasConnection = this.connections.some(conn =>
          conn.from === comp.id || conn.to === comp.id
        );
        if (!hasConnection) {
          d3.select(`.component[data-id="${comp.id}"]`)
            .classed('invalid', true);
        }
      });
      
      if (window.Shiny && window.Shiny.notifications) {
        Shiny.notifications.show({
          message: '✗ Connection errors: ' + result.errors.join('; '),
          type: 'error',
          duration: 10
        });
      }
    }
    
    if (result.warnings.length > 0 && window.Shiny && window.Shiny.notifications) {
      Shiny.notifications.show({
        message: '⚠ Warnings: ' + result.warnings.join('; '),
        type: 'warning',
        duration: 8
      });
    }
    
    return result.valid;
  }
}

// ============================================================
// Multi-Canvas System
// Support for split-screen comparison of multiple architectures
// ============================================================

// Global state for multi-canvas
window.paCanvases = [];
window.canvasLabels = [];
window.activeCanvasIndex = 0;
window.canvasLayout = "1x1";

// Create shared palette for multi-canvas mode
function createSharedPalette() {
  console.log('Creating shared component palette for multi-canvas...');
  
  // Remove existing palette if any
  d3.select('#shared_component_palette').remove();
  
  // Find the main container
  const mainContainer = document.getElementById('pa_lineup_canvas_container');
  if (!mainContainer) {
    console.warn('Main container not found for shared palette');
    return;
  }
  
  const palette = d3.select(mainContainer)
    .insert('div', ':first-child')
    .attr('id', 'shared_component_palette')
    .attr('class', 'component-palette')
    .style('position', 'absolute')
    .style('top', '10px')
    .style('left', '10px')
    .style('width', '60px')
    .style('background', 'rgba(44, 62, 80, 0.95)')
    .style('border-radius', '8px')
    .style('padding', '15px 8px')
    .style('box-shadow', '0 4px 20px rgba(0, 0, 0, 0.5)')
    .style('z-index', '200')
    .style('display', 'flex')
    .style('flex-direction', 'column')
    .style('gap', '8px')
    .style('transition', 'all 0.3s ease');
  
  // Add hover behavior to expand palette
  palette
    .on('mouseenter', function() {
      d3.select(this).style('width', '180px');
      d3.selectAll('#shared_component_palette .palette-label').style('display', 'block');
    })
    .on('mouseleave', function() {
      d3.select(this).style('width', '60px');
      d3.selectAll('#shared_component_palette .palette-label').style('display', 'none');
    });
  
  const components = [
    { type: 'transistor', icon: '▲', label: 'Transistor', color: '#00bfff', useIcon: true },
    { type: 'matching', icon: 'M', label: 'Matching', color: '#00ff88', useIcon: false },
    { type: 'splitter', icon: 'Y', label: 'Splitter', color: '#ffaa00', useIcon: false },
    { type: 'combiner', icon: 'Ψ', label: 'Combiner', color: '#ff00aa', useIcon: false },
    { type: 'termination', icon: '⏚', label: 'Termination', color: '#888888', useIcon: true },
    { type: 'wire', icon: '━', label: 'Wire Mode', color: '#ff7f11', isAction: true, useIcon: true }
  ];
  
  components.forEach(comp => {
    const item = palette.append('div')
      .attr('class', comp.isAction ? 'palette-action' : 'palette-item')
      .attr('data-type', comp.type)
      .style('display', 'flex')
      .style('align-items', 'center')
      .style('gap', '10px')
      .style('cursor', 'pointer')
      .style('padding', '10px')
      .style('border-radius', '5px')
      .style('transition', 'background 0.2s')
      .on('mouseenter', function() {
        d3.select(this).style('background', 'rgba(255, 127, 17, 0.2)');
      })
      .on('mouseleave', function() {
        d3.select(this).style('background', 'transparent');
      })
      .on('click', () => {
        // Reference the active canvas from window
        const activeCanvas = window.paCanvas;
        if (!activeCanvas) {
          console.error('No active canvas found!');
          alert('Please hover over a canvas first');
          return;
        }
        
        if (comp.isAction) {
          if (comp.type === 'wire') {
            activeCanvas.toggleWireMode();
          }
        } else {
          activeCanvas.addComponentFromPalette(comp.type);
        }
      });
    
    // Create SVG icon for matching, splitter, combiner
    if (!comp.useIcon && (comp.type === 'matching' || comp.type === 'splitter' || comp.type === 'combiner')) {
      const iconSvg = item.append('svg')
        .attr('width', 30)
        .attr('height', 30)
        .style('overflow', 'visible');
      
      const g = iconSvg.append('g')
        .attr('transform', 'translate(15, 15)');
      
      if (comp.type === 'matching') {
        // Matching: Small transformer/inductor symbol
        g.append('path')
          .attr('d', 'M-10,0 L-5,0')
          .attr('stroke', comp.color)
          .attr('stroke-width', 2)
          .attr('fill', 'none');
        
        // Coil/transformer
        g.append('path')
          .attr('d', 'M-5,0 Q-3,-5 0,-5 Q3,-5 5,0 Q3,5 0,5 Q-3,5 -5,0')
          .attr('stroke', comp.color)
          .attr('stroke-width', 2)
          .attr('fill', 'none');
        
        g.append('path')
          .attr('d', 'M5,0 L10,0')
          .attr('stroke', comp.color)
          .attr('stroke-width', 2)
          .attr('fill', 'none');
      } else if (comp.type === 'splitter') {
        // Splitter: Y-junction (input on left, outputs on right)
        g.append('line')
          .attr('x1', -10).attr('y1', 0)
          .attr('x2', 0).attr('y2', 0)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
        
        g.append('line')
          .attr('x1', 0).attr('y1', 0)
          .attr('x2', 10).attr('y2', -8)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
        
        g.append('line')
          .attr('x1', 0).attr('y1', 0)
          .attr('x2', 10).attr('y2', 8)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
      } else if (comp.type === 'combiner') {
        // Combiner: Inverted Y-junction (inputs on left, output on right)
        g.append('line')
          .attr('x1', -10).attr('y1', -8)
          .attr('x2', 0).attr('y2', 0)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
        
        g.append('line')
          .attr('x1', -10).attr('y1', 8)
          .attr('x2', 0).attr('y2', 0)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
        
        g.append('line')
          .attr('x1', 0).attr('y1', 0)
          .attr('x2', 10).attr('y2', 0)
          .attr('stroke', comp.color)
          .attr('stroke-width', 2);
      }
    } else {
      // Use text icon for transistor, termination, wire
      item.append('div')
        .style('font-size', '24px')
        .style('color', comp.color)
        .text(comp.icon);
    }
    
    item.append('div')
      .attr('class', 'palette-label')
      .style('color', '#fff')
      .style('font-size', '12px')
      .style('display', 'none')
      .text(comp.label);
  });
  
  console.log('✅ Shared palette created successfully');
}

// Get layout dimensions
function getLayoutDimensions(layout) {
  const layouts = {
    "1x1": { rows: 1, cols: 1, count: 1 },
    "1x2": { rows: 1, cols: 2, count: 2 },
    "2x1": { rows: 2, cols: 1, count: 2 },
    "2x2": { rows: 2, cols: 2, count: 4 },
    "2x3": { rows: 2, cols: 3, count: 6 },
    "3x2": { rows: 3, cols: 2, count: 6 },  // NEW
    "1x3": { rows: 1, cols: 3, count: 3 },
    "1x4": { rows: 1, cols: 4, count: 4 },  // NEW
    "4x1": { rows: 4, cols: 1, count: 4 },  // NEW
    "3x3": { rows: 3, cols: 3, count: 9 },
    "4x2": { rows: 4, cols: 2, count: 8 },  // NEW
    "2x4": { rows: 2, cols: 4, count: 8 },  // NEW
    "2+1": { rows: 2, cols: 2, count: 3, special: "2plus1" },
    "1+2": { rows: 2, cols: 2, count: 3, special: "1plus2" }  // NEW: 2 small on top, 1 large below
  };
  return layouts[layout] || layouts["1x1"];
}

// Initialize multi-canvas system
function initializeMultiCanvas(layout = "1x1") {
  console.log(`🎨 Initializing multi-canvas system with layout: ${layout}`);
  
  const mainContainer = document.getElementById('pa_lineup_canvas_container');
  if (!mainContainer) {
    console.warn('PA Lineup canvas container not found');
    return false;
  }
  
  // Check if D3.js is loaded
  if (typeof d3 === 'undefined') {
    console.error('D3.js not loaded!');
    return false;
  }
  
  // Store layout
  window.canvasLayout = layout;
  const dimensions = getLayoutDimensions(layout);
  
  // Clear existing canvases
  window.paCanvases.forEach(canvas => {
    if (canvas && canvas.svg) {
      try {
        canvas.svg.remove();
      } catch(e) {
        console.warn('Error removing canvas:', e);
      }
    }
  });
  window.paCanvases = [];
  
  // Clear shared palette before creating new layout
  d3.select('#shared_component_palette').remove();
  window.canvasLabels = [];
  
  // Find or create the canvas grid container
  let gridContainer = mainContainer.querySelector('#pa_canvas_grid');
  if (!gridContainer) {
    gridContainer = document.createElement('div');
    gridContainer.id = 'pa_canvas_grid';
    mainContainer.appendChild(gridContainer);
  }
  
  // Apply grid layout
  if (dimensions.special === "2plus1") {
    // Special 2+1 layout: 1 large canvas on top, 2 small below
    gridContainer.style.cssText = `
      display: grid;
      gap: 5px;
      width: 100%;
      height: 600px;
      grid-template-rows: 2fr 1fr;
      grid-template-columns: 1fr 1fr;
    `;
  } else {
    gridContainer.style.cssText = `
      display: grid;
      gap: 5px;
      width: 100%;
      height: 600px;
      grid-template-rows: repeat(${dimensions.rows}, 1fr);
      grid-template-columns: repeat(${dimensions.cols}, 1fr);
    `;
  }
  gridContainer.innerHTML = ''; // Clear existing canvas divs
  
  // Create canvas divs
  for (let i = 0; i < dimensions.count; i++) {
    const canvasDiv = document.createElement('div');
    canvasDiv.id = `pa_lineup_canvas_${i}`;
    canvasDiv.className = 'canvas-cell';
    canvasDiv.setAttribute('data-canvas-index', i);
    
    // Special styling for 2+1 layout (first canvas spans 2 columns)
    if (dimensions.special === "2plus1" && i === 0) {
      canvasDiv.style.gridColumn = 'span 2';
    }
    
    // Special styling for 1+2 layout (last canvas spans 2 columns)
    if (dimensions.special === "1plus2" && i === dimensions.count - 1) {
      canvasDiv.style.gridColumn = 'span 2';
    }
    
    canvasDiv.style.cssText += `
      position: relative;
      border: 2px solid transparent;
      background: #ecf0f1;
      border-radius: 4px;
      overflow: hidden;
      transition: border-color 0.2s, box-shadow 0.2s;
    `;
    
    // Add canvas label
    const label = document.createElement('div');
    label.className = 'canvas-label';
    label.textContent = `Canvas ${i + 1}`;
    label.style.cssText = `
      position: absolute;
      top: 5px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(52, 73, 94, 0.9);
      color: white;
      padding: 5px 15px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: bold;
      z-index: 50;
      pointer-events: none;
      text-align: center;
      white-space: nowrap;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
    `;
    canvasDiv.appendChild(label);
    
    // Store label reference for later updates
    window.canvasLabels[i] = label;
    
    gridContainer.appendChild(canvasDiv);
    
    // Initialize canvas instance
    try {
      const canvas = new PALineupCanvas(`pa_lineup_canvas_${i}`);
      window.paCanvases.push(canvas);
      console.log(`✅ Canvas ${i} initialized`);
      
      // Add hover listeners for active canvas switching
      canvasDiv.addEventListener('mouseenter', function() {
        if (!window.stickyActiveCanvas) {
          setActiveCanvas(i);
        }
      });
      
      // Add click listener for sticky active canvas selection (priority over hover)
      canvasDiv.addEventListener('click', function(e) {
        // Only if clicking canvas background, not components
        if (e.target.tagName === 'svg' || e.target.classList.contains('canvas-cell')) {
          window.stickyActiveCanvas = true;
          setActiveCanvas(i);
          console.log(`🔒 Canvas ${i} locked as active`);
          
          // Clear sticky after 5 seconds of no interaction
          clearTimeout(window.stickyTimeout);
          window.stickyTimeout = setTimeout(() => {
            window.stickyActiveCanvas = false;
            console.log('🔓 Sticky active canvas cleared');
          }, 5000);
        }
      });
      
    } catch (error) {
      console.error(`❌ Error initializing canvas ${i}:`, error);
    }
  }
  
  // Set first canvas as active
  if (window.paCanvases.length > 0) {
    setActiveCanvas(0);
  }
  
  // IMPORTANT: Only create shared palette if NOT in single canvas mode
  if (layout !== '1x1') {
    createSharedPalette();
    console.log('✓ Shared palette created for multi-canvas layout');
  } else {
    console.log('📌 Single canvas mode - palette disabled (use right sidebar)');
  }
  
  console.log(`✅ Multi-canvas initialized: ${dimensions.count} canvases`);
  return true;
}

// Set active canvas
function setActiveCanvas(index) {
  if (index < 0 || index >= window.paCanvases.length) return;
  
  window.activeCanvasIndex = index;
  window.paCanvas = window.paCanvases[index];
  
  // Update visual indicator
  document.querySelectorAll('.canvas-cell').forEach((cell, idx) => {
    if (idx === index) {
      cell.style.borderColor = '#3498db';
      cell.style.boxShadow = '0 0 10px rgba(52, 152, 219, 0.5)';
    } else {
      cell.style.borderColor = 'transparent';
      cell.style.boxShadow = 'none';
    }
  });
  
  console.log(`🎯 Active canvas: ${index}`);
  
  // Notify Shiny
  if (window.Shiny && Shiny.setInputValue) {
    Shiny.setInputValue('active_canvas', index);
  }
}

// Initialize canvas with error handling and multiple triggers
function initializePACanvas() {
  console.log('Attempting to initialize PA Lineup Canvas...');
  
  // Check if already initialized
  if (window.paCanvas || (window.paCanvases && window.paCanvases.length > 0)) {
    console.log('⚠️ PA Lineup Canvas already initialized, skipping re-initialization');
    return true;
  }
  
  // Check if container exists
  const container = document.getElementById('pa_lineup_canvas_container');
  if (!container) {
    console.warn('PA Lineup canvas container not found, will retry...');
    return false;
  }
  
  // Check if D3.js is loaded
  if (typeof d3 === 'undefined') {
    console.error('D3.js not loaded! Please check script tag.');
    return false;
  }
  
  // Initialize multi-canvas system (starts with 1x1 layout)
  return initializeMultiCanvas('1x1');
}

// Try multiple initialization methods to ensure reliability
// Method 1: Shiny connected event
if (typeof $ !== 'undefined') {
  $(document).on('shiny:connected', function() {
    console.log('Shiny connected event fired');
    initializePACanvas();
  });
}

// Method 2: Document ready (for when tab is loaded later)
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOM Content Loaded');
  // Wait a bit for Shiny to set up the UI
  setTimeout(initializePACanvas, 500);
});

// Method 3: Immediate initialization attempt (if script loads after container)
if (document.readyState === 'complete' || document.readyState === 'interactive') {
  console.log('Document already loaded, attempting immediate init');
  setTimeout(initializePACanvas, 100);
}

// Method 4: Tab change detection for Shiny Dashboard
if (typeof $ !== 'undefined') {
  $(document).on('shown.bs.tab', 'a[data-value="pa_lineup"]', function() {
    console.log('PA Lineup tab shown');
    if (!window.paCanvas) {
      setTimeout(initializePACanvas, 300);
    }
  });
}

// Setup preset template click handlers
document.addEventListener('DOMContentLoaded', function() {
  console.log('Setting up preset template handlers...');
  
  // Wait for templates to be rendered by Shiny
  setTimeout(function() {
    const templates = document.querySelectorAll('.preset-template');
    console.log('Found preset templates:', templates.length);
    
    if (templates.length === 0) {
      console.warn('No preset templates found! Checking again in 1 second...');
      setTimeout(function() {
        const templates2 = document.querySelectorAll('.preset-template');
        console.log('Second attempt - found templates:', templates2.length);
        if (templates2.length > 0) {
          setupTemplateHandlers(templates2);
        }
      }, 1000);
    } else {
      setupTemplateHandlers(templates);
    }
  }, 1000);
});

function setupTemplateHandlers(templates) {
  console.log('Setting up click handlers for', templates.length, 'templates');
  
  templates.forEach((template, index) => {
    console.log('Template', index, ':', template.getAttribute('data-preset'));
    
    template.addEventListener('click', function() {
      const preset = this.getAttribute('data-preset');
      console.log('=== TEMPLATE CLICKED ===');
      console.log('Preset:', preset);
      console.log('Canvas exists?', !!window.paCanvas);
      
      if (!window.paCanvas) {
        console.error('Canvas not initialized! Attempting to initialize...');
        alert('Initializing canvas...');
        const initialized = initializePACanvas();
        if (!initialized) {
          alert('Canvas not ready. Please try again in a moment.');
          return;
        }
        // Wait a bit for initialization to complete
        setTimeout(() => {
          if (window.paCanvas) {
            console.log('Canvas initialized, loading preset:', preset);
            if (preset === 'blank') {
              window.paCanvas.clear();
            } else {
              window.paCanvas.loadPreset(preset);
            }
          }
        }, 500);
      } else {
        console.log('Canvas ready, loading preset:', preset);
        if (preset === 'blank') {
          window.paCanvas.clear();
        } else {
          window.paCanvas.loadPreset(preset);
        }
      }
      
      // Visual feedback
      templates.forEach(t => t.classList.remove('active'));
      this.classList.add('active');
    });
    
    // Add hover effect
    template.style.cursor = 'pointer';
  });
  
  console.log('✓ All template handlers set up successfully');
}

// ==============================================================================
// SPECIFICATION-DRIVEN DESIGN UTILITIES
// ==============================================================================
// NOTE: These must be defined BEFORE applySpecsToComponents uses them!

/**
 * Technology Selection based on frequency, power, and fT/fmax requirements
 * Reference: fT > 5 × fop rule from Frequency Planning tab
 */
window.selectTechnology = function(freq_ghz, pout_dbm, vdd = 30) {
  const pout_watts = Math.pow(10, (pout_dbm - 30) / 10);
  console.log(`[Tech Select] Frequency: ${freq_ghz} GHz, Pout: ${pout_dbm} dBm (${pout_watts.toFixed(2)}W), Vdd: ${vdd}V`);
  
  const required_fT = 5 * freq_ghz;
  let technology = 'GaN';
  let rationale = '';
  
  if (freq_ghz < 1) {
    if (pout_watts > 100) {
      technology = 'LDMOS';
      rationale = `High power (${pout_watts.toFixed(0)}W) at ${freq_ghz} GHz → Si LDMOS (fT: 20-40 GHz > ${required_fT.toFixed(0)} GHz)`;
    } else {
      technology = 'LDMOS';
      rationale = `Sub-1GHz operation → Si LDMOS or Si BJT`;
    }
  } else if (freq_ghz < 4) {
    if (pout_watts > 50) {
      technology = 'GaN';
      rationale = `High power (${pout_watts.toFixed(0)}W) at ${freq_ghz} GHz → GaN HEMT (fT: 50-100 GHz > ${required_fT.toFixed(0)} GHz)`;
    } else if (pout_watts > 10) {
      technology = 'LDMOS';
      rationale = `Medium power (${pout_watts.toFixed(1)}W) at ${freq_ghz} GHz → Si LDMOS (fT: 20-40 GHz > ${required_fT.toFixed(0)} GHz)`;
    } else {
      technology = 'GaAs';
      rationale = `Low power (${pout_watts.toFixed(1)}W) at ${freq_ghz} GHz → GaAs pHEMT (fT: 30-60 GHz > ${required_fT.toFixed(0)} GHz)`;
    }
  } else if (freq_ghz < 12) {
    if (pout_watts > 10) {
      technology = 'GaN';
      rationale = `${freq_ghz} GHz, ${pout_watts.toFixed(1)}W → GaN HEMT (fT: 50-100 GHz > ${required_fT.toFixed(0)} GHz)`;
    } else {
      technology = 'GaAs';
      rationale = `${freq_ghz} GHz, ${pout_watts.toFixed(1)}W → GaAs pHEMT (fT: 30-60 GHz > ${required_fT.toFixed(0)} GHz)`;
    }
  } else if (freq_ghz < 40) {
    technology = 'GaN';
    rationale = `${freq_ghz} GHz mmWave → GaN HEMT (fT: 50-100 GHz > ${required_fT.toFixed(0)} GHz)`;
  } else if (freq_ghz < 100) {
    technology = 'SiGe';
    rationale = `${freq_ghz} GHz → SiGe HBT (fT: 200-300 GHz > ${required_fT.toFixed(0)} GHz)`;
  } else {
    technology = 'InP';
    rationale = `${freq_ghz} GHz sub-THz → InP HEMT (fT: 300-600 GHz > ${required_fT.toFixed(0)} GHz)`;
  }
  
  console.log(`[Tech Select] Selected: ${technology} - ${rationale}`);
  return { technology: technology, rationale: rationale, required_fT: required_fT };
};

/**
 * Estimate passive component losses based on frequency
 */
window.estimatePassiveLoss = function(component_type, freq_ghz, length_lambda = 0.25) {
  let loss_db = 0;
  let rationale = '';
  
  switch(component_type) {
    case 'matching':
    case 'transformer':
      if (freq_ghz < 2) {
        loss_db = 0.1 + 0.05 * length_lambda;
      } else if (freq_ghz < 6) {
        loss_db = 0.15 + 0.1 * length_lambda;
      } else if (freq_ghz < 30) {
        loss_db = 0.25 + 0.15 * length_lambda;
      } else {
        loss_db = 0.5 + 0.3 * length_lambda;
      }
      rationale = `Matching network at ${freq_ghz} GHz: ${loss_db.toFixed(2)} dB`;
      break;
    case 'splitter':
      if (freq_ghz < 6) {
        loss_db = 0.2;
      } else if (freq_ghz < 30) {
        loss_db = 0.3 + 0.01 * freq_ghz;
      } else {
        loss_db = 0.5 + 0.02 * freq_ghz;
      }
      rationale = `Splitter at ${freq_ghz} GHz: ${loss_db.toFixed(2)} dB`;
      break;
    case 'combiner':
      if (freq_ghz < 6) {
        loss_db = 0.25;
      } else if (freq_ghz < 30) {
        loss_db = 0.35 + 0.01 * freq_ghz;
      } else {
        loss_db = 0.6 + 0.02 * freq_ghz;
      }
      rationale = `Combiner at ${freq_ghz} GHz: ${loss_db.toFixed(2)} dB`;
      break;
    case 'doherty_combiner':
      loss_db = estimatePassiveLoss('matching', freq_ghz, 0.25).loss + 0.1;
      rationale = `Doherty combiner at ${freq_ghz} GHz: ${loss_db.toFixed(2)} dB`;
      break;
    default:
      loss_db = 0.3;
      rationale = `Generic passive at ${freq_ghz} GHz: ${loss_db.toFixed(2)} dB`;
  }
  
  return { loss: loss_db, rationale: rationale };
};

/**
 * Distribute gain across stages based on total gain requirement
 */
window.distributeGain = function(total_gain_db, topology = 'balanced', targetStages = null) {
  console.log(`[Gain Distribution] Total: ${total_gain_db} dB, Topology: ${topology}, Target Stages: ${targetStages}`);
  
  let stages = [];
  let num_stages = 1;
  
  // If targetStages specified, use it directly
  if (targetStages !== null && targetStages > 0) {
    num_stages = targetStages;
    console.log(`[Gain Distribution] Using target stage count: ${num_stages}`);
  } else {
    // Auto-determine based on gain  
    if (total_gain_db < 15) {
      num_stages = 1;
    } else if (total_gain_db < 30) {
      num_stages = 2;
    } else if (total_gain_db < 45) {
      num_stages = 3;
    } else {
      num_stages = 4;
    }
  }
  
  const max_stage_gain = 18;
  
  if (topology === 'doherty' || topology === 'balanced') {
    if (num_stages === 1) {
      stages = [{ name: 'PA', gain: total_gain_db, type: 'pa' }];
    } else if (num_stages === 2) {
      let driver_gain = Math.min(max_stage_gain, total_gain_db / 2);
      driver_gain = Math.max(10, driver_gain);
      let pa_gain = total_gain_db - driver_gain;
      stages = [
        { name: 'Driver', gain: driver_gain, type: 'driver' },
        { name: 'PA', gain: pa_gain, type: 'pa' }
      ];
    } else {
      let predriver_gain = Math.min(15, total_gain_db / 3);
      let driver_gain = Math.min(max_stage_gain, (total_gain_db - predriver_gain) / 2);
      let pa_gain = total_gain_db - predriver_gain - driver_gain;
      stages = [
        { name: 'Pre-Driver', gain: predriver_gain, type: 'predriver' },
        { name: 'Driver', gain: driver_gain, type: 'driver' },
        { name: 'PA', gain: pa_gain, type: 'pa' }
      ];
    }
  }
  
  console.log('[Gain Distribution] Stages:', stages);
  return { num_stages: num_stages, stages: stages };
};

/**
 * Calculate P1dB from P3dB
 */
window.calculateP1dB = function(p3db) {
  return p3db - 2;
};

/**
 * Estimate PAE (Power Added Efficiency)
 */
window.estimatePAE = function(bias_class, topology = 'conventional', freq_ghz = 2.6) {
  let pae = 40;
  
  if (topology === 'doherty') {
    if (bias_class === 'AB') {
      pae = 50;
    } else if (bias_class === 'C') {
      pae = 45;
    } else {
      pae = 45;
    }
  } else {
    switch(bias_class) {
      case 'A': pae = 30; break;
      case 'AB': pae = 45; break;
      case 'B': pae = 50; break;
      case 'C': pae = 55; break;
      default: pae = 40;
    }
  }
  
  if (freq_ghz > 10) pae *= 0.9;
  if (freq_ghz > 30) pae *= 0.85;
  
  return Math.round(pae);
};

/**
 * Select appropriate bias class
 */
window.selectBiasClass = function(efficiency_target, topology = 'conventional', pa_role = 'main') {
  if (topology === 'doherty') {
    if (pa_role === 'main') return 'AB';
    else if (pa_role === 'aux' || pa_role === 'auxiliary') return 'C';
  }
  
  if (efficiency_target < 35) return 'A';
  else if (efficiency_target < 48) return 'AB';
  else if (efficiency_target < 55) return 'B';
  else return 'C';
};

/**
 * Calculate power cascade through lineup stages
 */
window.calculatePowerCascade = function(pout_final_dbm, gain_stages) {
  let cascade = [];
  let current_pout = pout_final_dbm;
  
  for (let i = gain_stages.length - 1; i >= 0; i--) {
    let stage = gain_stages[i];
    let pin = current_pout - stage.gain;
    cascade.unshift({
      stage: stage.name,
      gain: stage.gain,
      pin: pin,
      pout: current_pout
    });
    current_pout = pin;
  }
  
  console.log('[Power Cascade]', cascade);
  return cascade;
};

console.log('✓ Specification-driven design utilities loaded');

// ==============================================================================
// APPLY SPECIFICATIONS TO COMPONENTS
// ==============================================================================

/**
 * Apply specifications to existing lineup components
 * Updates transistor parameters based on specs
 */
function applySpecsToComponents(specs) {
  console.log('[Apply Specs] Starting component adaptation...');
  
  if (!window.paCanvas || !window.paCanvas.components) {
    console.error('[Apply Specs] Canvas or components not available');
    return;
  }
  
  const components = window.paCanvas.components;
  console.log(`[Apply Specs] Found ${components.length} components`);
  
  // Select technology based on frequency and power
  const techSelection = selectTechnology(specs.frequency_ghz, specs.p3db, specs.supply_voltage);
  console.log('[Apply Specs] Technology selected:', techSelection.technology);
  
  // Calculate passive losses
  const matchingLoss = estimatePassiveLoss('matching', specs.frequency_ghz, 0.25).loss;
  const splitterLoss = estimatePassiveLoss('splitter', specs.frequency_ghz).loss;
  const combinerLoss = estimatePassiveLoss('doherty_combiner', specs.frequency_ghz).loss;
  
  console.log('[Apply Specs] Estimated losses:', { matchingLoss, splitterLoss, combinerLoss });
  
  // Distribute gain across stages
  let gainDist = distributeGain(specs.gain, 'doherty');  // Assume Doherty for now
  console.log('[Apply Specs] Initial gain distribution:', gainDist);
  
  // CRITICAL FIX: For Doherty architecture, calculatePowerCascade needs the PER-PA power
  // requirement, not the system output power. For balanced Doherty:
  // P_system = 10*log10(P_main_watts + P_aux_watts) = P_PA + 3.01 dB (for equal PAs)
  // Therefore: P_PA_target = P_system - 3.01 dB + combiner_loss
  const topology = 'doherty';  // TODO: Get from template metadata
  const powerCombiningFactor = 3.01;  // dB for 2-way power combining
  const pa_target_power = topology === 'doherty' 
    ? specs.p3db - powerCombiningFactor + combinerLoss 
    : specs.p3db;  // For conventional, use system target directly
  
  console.log(`[Apply Specs] Power cascade input: ${pa_target_power.toFixed(2)} dBm (system target: ${specs.p3db} dBm, topology: ${topology})`);
  
  // CRITICAL: Extract PAR and Pavg from specs
  const par_db = specs.par || 8.0;  // Peak-to-Average Ratio (dB)
  const pavg_dbm = specs.pavg || (specs.p3db - par_db);  // Average/backoff power
  
  console.log(`[Apply Specs] Operating Points: Pavg=${pavg_dbm.toFixed(2)} dBm (BO), P3dB=${specs.p3db.toFixed(2)} dBm (Peak), PAR=${par_db.toFixed(1)} dB`);
  
  // Calculate power cascade at P3dB (peak power) with correct per-PA target
  let powerCascade_p3db = calculatePowerCascade(pa_target_power, gainDist.stages);
  console.log('[Apply Specs] Power cascade at P3dB (Peak):', powerCascade_p3db);
  
  // Calculate power cascade at Pavg (backoff power)
  // For Doherty: at backoff, ONLY Main PA is active (Aux is off).
  // There is NO combining gain at backoff — Main PA must supply the full system Pavg
  // alone, losing only the combiner insertion loss. Therefore do NOT subtract
  // powerCombiningFactor here (that 3 dB only applies when both PAs are active).
  const pavg_pa_target = topology === 'doherty'
    ? pavg_dbm + combinerLoss  // Main PA only at backoff; no combining gain
    : pavg_dbm;
  let powerCascade_pavg = calculatePowerCascade(pavg_pa_target, gainDist.stages);
  console.log('[Apply Specs] Power cascade at Pavg (Backoff):', powerCascade_pavg);
  
  // Find transistor components
  const transistors = components.filter(c => c.type === 'transistor');
  console.log(`[Apply Specs] Found ${transistors.length} transistors`);
  
  // Identify component roles based on labels
  let driver = null, mainPA = null, auxPA = null, preDriver = null;
  
  transistors.forEach(t => {
    const label = t.properties.label.toLowerCase();
    if (label.includes('pre') || label.includes('predriver')) {
      preDriver = t;
    } else if (label.includes('driver') && !label.includes('main') && !label.includes('aux')) {
      driver = t;
    } else if (label.includes('main')) {
      mainPA = t;
    } else if (label.includes('aux')) {
      auxPA = t;
    }
  });
  
  console.log('[Apply Specs] Identified components:', {
    preDriver: preDriver?.properties.label,
    driver: driver?.properties.label,
    mainPA: mainPA?.properties.label,
    auxPA: auxPA?.properties.label
  });
  
  // ═══ CRITICAL FIX: Adapt gain distribution to actual component count ═══
  // For Doherty: Main PA + Aux PA count as ONE power stage
  // Actual stages = (preDriver ? 1 : 0) + (driver ? 1 : 0) + (mainPA || auxPA ? 1 : 0)
  let actualStages = 0;
  if (preDriver) actualStages++;
  if (driver) actualStages++;
  if (mainPA || auxPA) actualStages++;  // PA pair counts as one stage
  
  console.log(`[Apply Specs] Actual component stages: ${actualStages} (Pre=${!!preDriver}, Driver=${!!driver}, PA=${!!(mainPA||auxPA)})`);
  
  // If gain distribution created more stages than components exist, collapse it
  if (gainDist.num_stages > actualStages) {
    console.warn(`[Apply Specs] Gain distribution created ${gainDist.num_stages} stages but only ${actualStages} exist. Redistributing...`);
    gainDist = distributeGain(specs.gain, topology, actualStages);  // Force correct stage count
    console.log('[Apply Specs] Redistributed gain:', gainDist);
    
    // CRITICAL: Recalculate power cascades with corrected gain distribution
    const powerCascade_p3db_new = calculatePowerCascade(pa_target_power, gainDist.stages);
    const powerCascade_pavg_new = calculatePowerCascade(pavg_pa_target, gainDist.stages);
    console.log('[Apply Specs] Recalculated P3dB cascade:', powerCascade_p3db_new);
    console.log('[Apply Specs] Recalculated Pavg cascade:', powerCascade_pavg_new);
    
    // Update the cascade variables
    powerCascade_p3db = powerCascade_p3db_new;
    powerCascade_pavg = powerCascade_pavg_new;
  }
  
  // Update frequency for all components
  components.forEach(comp => {
    if (comp.properties) {
      comp.properties.frequency = specs.frequency_ghz;
    }
  });
  
  // Update passive component losses using the already-calculated values
  components.filter(c => c.type === 'matching').forEach(m => {
    m.properties.loss = matchingLoss;
  });
  
  components.filter(c => c.type === 'splitter').forEach(s => {
    s.properties.loss = splitterLoss;
  });
  
  components.filter(c => c.type === 'combiner').forEach(c => {
    c.properties.loss = combinerLoss;
  });

  // ═══ FIX: Override idealized gain distribution with ACTUAL component gains ═══
  // This ensures the power cascade is consistent with the real transistor parameters
  // in the template (e.g. Driver gain=15, PA gain=12) rather than the auto-distributed
  // idealized values which can be very different from the component properties.
  const actualGainStages = [];
  if (preDriver) actualGainStages.push({
    name: 'Pre-Driver',
    // Driver sees splitter loss; pre-driver does not — account for interstage match only
    gain: Number(preDriver.properties.gain) || 12,
    type: 'predriver'
  });
  if (driver) actualGainStages.push({
    name: 'Driver',
    // Driver Pout must overcome splitter loss to deliver correct Pin to each PA
    gain: (Number(driver.properties.gain) || 15) - splitterLoss,
    type: 'driver'
  });
  if (mainPA || auxPA) actualGainStages.push({
    name: 'PA',
    gain: Number((mainPA || auxPA).properties.gain) || 12,
    type: 'pa'
  });

  if (actualGainStages.length > 0) {
    gainDist.stages = actualGainStages;
    gainDist.num_stages = actualGainStages.length;
    powerCascade_p3db = calculatePowerCascade(pa_target_power, actualGainStages);
    powerCascade_pavg = calculatePowerCascade(pavg_pa_target, actualGainStages);
    console.log('[Apply Specs] Actual-gain P3dB cascade:', powerCascade_p3db);
    console.log('[Apply Specs] Actual-gain Pavg cascade:', powerCascade_pavg);
  }

  // Doherty backoff efficiency factor (used below for Main PA Pavg PAE)
  // η_BO = η_peak / (2√α)  where α = 10^(-OBO_dB/10)
  // Reference: Cripps, "RF Power Amplifiers for Wireless Communications", Ch.12
  const alpha_bo = Math.pow(10, -par_db / 10);
  const doherty_pae_bo_factor = 1.0 / (2.0 * Math.sqrt(alpha_bo));
  console.log(`[Apply Specs] Doherty BO efficiency factor: ${doherty_pae_bo_factor.toFixed(3)} (PAR=${par_db}dB, α=${alpha_bo.toFixed(4)})`);

  // Update transistors based on cascade and topology
  console.log(`[Apply Specs] Applying to ${gainDist.num_stages}-stage configuration`);
  
  if (gainDist.num_stages === 2) {
    // Driver + PA configuration
    console.log('[Apply Specs] Using 2-stage path (Driver + PA)');
    
    if (driver) {
      const driverStage_p3db = powerCascade_p3db.find(s => s.stage === 'Driver');
      const driverStage_pavg = powerCascade_pavg.find(s => s.stage === 'Driver');
      
      if (!driverStage_p3db || !driverStage_pavg) {
        console.error(`[Apply Specs] Could not find Driver stage in power cascade!`);
        console.error(`  Available stages (P3dB):`, powerCascade_p3db.map(s => s.stage));
        console.error(`  Available stages (Pavg):`, powerCascade_pavg.map(s => s.stage));
      } else {
        console.log(`[Apply Specs] Found Driver stage - P3dB: ${driverStage_p3db.pout.toFixed(2)} dBm, Pavg: ${driverStage_pavg.pout.toFixed(2)} dBm`);
      
        driver.properties.frequency = specs.frequency_ghz;
        driver.properties.technology = techSelection.technology;
        driver.properties.gain = driverStage_p3db.gain;
      
        // ===== OPERATING POINT: P3dB (Peak Power) =====
        driver.properties.pout_p3db = driverStage_p3db.pout;
        driver.properties.pin_p3db = driverStage_p3db.pin;
        driver.properties.p3db = driverStage_p3db.pout;  // P3dB equals Pout at peak
        driver.properties.p1db = driverStage_p3db.pout - 2;  // P1dB ≤ Pout (1dB compression point)
        
        // ===== OPERATING POINT: Pavg (Backoff Power) =====
        driver.properties.pout_pavg = driverStage_pavg.pout;
        driver.properties.pin_pavg = driverStage_pavg.pin;
        driver.properties.pavg = driverStage_pavg.pout;
        
        // Efficiency at both operating points
        driver.properties.biasClass = 'A';  // Driver typically Class A
        driver.properties.pae_p3db = estimatePAE('A', 'conventional', specs.frequency_ghz);
        driver.properties.pae_pavg = estimatePAE('A', 'conventional', specs.frequency_ghz);  // Class A has constant efficiency
        driver.properties.pae = driver.properties.pae_p3db;  // Default display
        driver.properties.vdd = specs.supply_voltage;
        
        // CRITICAL: Check driver compression at BOTH operating points
        const driver_compressed_p3db = driver.properties.pout_p3db >= driver.properties.p1db;
        const driver_compressed_pavg = driver.properties.pout_pavg >= driver.properties.p1db;
        
        if (driver_compressed_p3db) {
          console.warn(`⚠️ DRIVER COMPRESSED AT P3dB: Pout=${driver.properties.pout_p3db.toFixed(2)} dBm >= P1dB=${driver.properties.p1db.toFixed(2)} dBm`);
          console.warn(`   → Driver needs higher P1dB capability or lower output power requirement`);
        }
        if (driver_compressed_pavg) {
          console.warn(`⚠️ DRIVER COMPRESSED AT Pavg: Pout=${driver.properties.pout_pavg.toFixed(2)} dBm >= P1dB=${driver.properties.p1db.toFixed(2)} dBm`);
          console.warn(`   → Driver must operate in linear region at backoff!`);
        }
        
        // Store compression status
        driver.properties.compressed_p3db = driver_compressed_p3db;
        driver.properties.compressed_pavg = driver_compressed_pavg;
        
        // Legacy fields for backward compatibility
        driver.properties.pout = driverStage_p3db.pout;
        driver.properties.pin = driverStage_p3db.pin;
        
        console.log('[Apply Specs] Updated Driver:');
        console.log(`  At P3dB: Pin=${driver.properties.pin_p3db.toFixed(2)} dBm, Pout=${driver.properties.pout_p3db.toFixed(2)} dBm, PAE=${driver.properties.pae_p3db}%, Compressed=${driver_compressed_p3db}`);
        console.log(`  At Pavg: Pin=${driver.properties.pin_pavg.toFixed(2)} dBm, Pout=${driver.properties.pout_pavg.toFixed(2)} dBm, PAE=${driver.properties.pae_pavg}%, Compressed=${driver_compressed_pavg}`);
      }
    }
    
    // Update Main PA
    if (mainPA) {
      const paStage_p3db = powerCascade_p3db.find(s => s.stage === 'PA');
      const paStage_pavg = powerCascade_pavg.find(s => s.stage === 'PA');
      
      mainPA.properties.frequency = specs.frequency_ghz;
      mainPA.properties.technology = techSelection.technology;
      mainPA.properties.gain = paStage_p3db.gain;
      
      // CRITICAL: For Doherty architecture, power combining depends on operating point
      // At P3dB (Peak): Both Main and Aux contribute equally → P_combined = P_PA + 3.01 dB
      // At Pavg (Backoff): Mainly Main PA, Aux is off/low → P_combined ≈ P_main
      
      const powerCombiningFactor = 3.01;  // dB, accounts for 2 PAs combining
      
      // ===== OPERATING POINT: P3dB (Peak Power) =====
      // Each PA must produce power such that combined output reaches system target
      const pa_p3db_target = specs.p3db - powerCombiningFactor + combinerLoss;
      mainPA.properties.pout_p3db = pa_p3db_target;  // Each PA contributes ~52.8 dBm
      mainPA.properties.pin_p3db = pa_p3db_target - paStage_p3db.gain;
      mainPA.properties.p3db = pa_p3db_target;
      mainPA.properties.p1db = pa_p3db_target - 2.0;  // P1dB ≤ Pout
      
      // ===== OPERATING POINT: Pavg (Backoff Power) =====
      // At backoff, Main PA handles ALL the power (Aux is off — Doherty principle).
      // No combining gain at backoff, so Main PA pout = system_Pavg + combiner_loss.
      const pa_pavg_target = pavg_dbm + combinerLoss;  // No -powerCombiningFactor at BO
      mainPA.properties.pout_pavg = pa_pavg_target;
      mainPA.properties.pin_pavg = pa_pavg_target - paStage_pavg.gain;
      mainPA.properties.pavg = pa_pavg_target;
      
      // Efficiency at both operating points (Doherty optimizes efficiency at backoff!)
      mainPA.properties.biasClass = 'AB';  // Main PA in Doherty
      mainPA.properties.pae_p3db = estimatePAE('AB', 'doherty', specs.frequency_ghz);  // ~50%
      mainPA.properties.pae_pavg = Math.round(estimatePAE('AB', 'doherty', specs.frequency_ghz) * 1.1);  // ~55% (Doherty efficiency boost at backoff)
      mainPA.properties.pae = mainPA.properties.pae_p3db;  // Default display
      mainPA.properties.vdd = specs.supply_voltage;
      
      // Legacy fields for backward compatibility
      mainPA.properties.pout = pa_p3db_target;
      mainPA.properties.pin = mainPA.properties.pin_p3db;
      
      console.log(`[Apply Specs] Updated Main PA (Doherty):`);
      console.log(`  At P3dB: Pin=${mainPA.properties.pin_p3db.toFixed(2)} dBm, Pout=${mainPA.properties.pout_p3db.toFixed(2)} dBm, PAE=${mainPA.properties.pae_p3db}% → Combined=${specs.p3db.toFixed(2)} dBm`);
      console.log(`  At Pavg: Pin=${mainPA.properties.pin_pavg.toFixed(2)} dBm, Pout=${mainPA.properties.pout_pavg.toFixed(2)} dBm, PAE=${mainPA.properties.pae_pavg}% (Efficiency Boost!) → Combined=${pavg_dbm.toFixed(2)} dBm`);
    }
    
    // Update Aux PA (should match Main PA power for balanced Doherty)
    if (auxPA) {
      const paStage_p3db = powerCascade_p3db.find(s => s.stage === 'PA');
      const paStage_pavg = powerCascade_pavg.find(s => s.stage === 'PA');
      
      auxPA.properties.frequency = specs.frequency_ghz;
      auxPA.properties.technology = techSelection.technology;
      auxPA.properties.gain = paStage_p3db.gain;
      
      // For balanced Doherty: Aux PA matches Main PA at peak, but is OFF/minimal at backoff
      const powerCombiningFactor = 3.01;  // dB
      
      // ===== OPERATING POINT: P3dB (Peak Power) =====
      // At peak, Aux PA contributes equally with Main PA
      const pa_p3db_target = specs.p3db - powerCombiningFactor + combinerLoss;
      auxPA.properties.pout_p3db = pa_p3db_target;  // Same as Main PA
      auxPA.properties.pin_p3db = pa_p3db_target - paStage_p3db.gain;
      auxPA.properties.p3db = pa_p3db_target;
      auxPA.properties.p1db = pa_p3db_target - 2.0;
      
      // ===== OPERATING POINT: Pavg (Backoff Power) =====
      // CRITICAL: At backoff, Aux PA is OFF or very low power (Doherty principle!)
      // Aux PA turns on only as power increases beyond backoff point.
      // Reference target = Main PA Pavg target (same as pa_pavg_target above),
      // then reduce by aux_backoff_reduction to model the near-off condition.
      const aux_pa_pavg_target = pavg_dbm + combinerLoss;  // Same ref as Main PA Pavg target
      const aux_backoff_reduction = 10;  // dB reduction at backoff (Aux PA mostly off)
      auxPA.properties.pout_pavg = aux_pa_pavg_target - aux_backoff_reduction;  // Minimal output
      auxPA.properties.pin_pavg = auxPA.properties.pout_pavg - paStage_pavg.gain;
      auxPA.properties.pavg = auxPA.properties.pout_pavg;
      
      // Efficiency at both operating points
      auxPA.properties.biasClass = 'C';  // Aux PA in Doherty (Class C)
      auxPA.properties.pae_p3db = estimatePAE('C', 'doherty', specs.frequency_ghz);  // ~45%
      auxPA.properties.pae_pavg = 15;  // Low efficiency at backoff (Aux PA mostly off)
      auxPA.properties.pae = auxPA.properties.pae_p3db;  // Default display
      auxPA.properties.vdd = specs.supply_voltage;
      
      // Legacy fields for backward compatibility
      auxPA.properties.pout = pa_p3db_target;
      auxPA.properties.pin = auxPA.properties.pin_p3db;
      
      console.log(`[Apply Specs] Updated Aux PA (Doherty):`);
      console.log(`  At P3dB: Pin=${auxPA.properties.pin_p3db.toFixed(2)} dBm, Pout=${auxPA.properties.pout_p3db.toFixed(2)} dBm, PAE=${auxPA.properties.pae_p3db}% (Active)`);
      console.log(`  At Pavg: Pin=${auxPA.properties.pin_pavg.toFixed(2)} dBm, Pout=${auxPA.properties.pout_pavg.toFixed(2)} dBm, PAE=${auxPA.properties.pae_pavg}% (Mostly OFF - Doherty principle)`);
    }
  } else if (gainDist.num_stages === 3) {
    // Three-stage configuration: Pre-Driver + Driver + PA (Main + Aux)
    console.log('[Apply Specs] Configuring 3-stage lineup: Pre-Driver + Driver + PA');
    
    // Update Pre-Driver
    if (preDriver) {
      const preDriverStage_p3db = powerCascade_p3db.find(s => s.stage === 'Pre-Driver');
      const preDriverStage_pavg = powerCascade_pavg.find(s => s.stage === 'Pre-Driver');
      
      preDriver.properties.frequency = specs.frequency_ghz;
      preDriver.properties.technology = techSelection.technology;
      preDriver.properties.gain = preDriverStage_p3db.gain;
      
      // Operating points
      preDriver.properties.pout_p3db = preDriverStage_p3db.pout;
      preDriver.properties.pin_p3db = preDriverStage_p3db.pin;
      preDriver.properties.p3db = preDriverStage_p3db.pout;
      preDriver.properties.p1db = preDriverStage_p3db.pout - 2;
      
      preDriver.properties.pout_pavg = preDriverStage_pavg.pout;
      preDriver.properties.pin_pavg = preDriverStage_pavg.pin;
      preDriver.properties.pavg = preDriverStage_pavg.pout;
      
      preDriver.properties.biasClass = 'A';
      preDriver.properties.pae_p3db = estimatePAE('A', 'conventional', specs.frequency_ghz);
      preDriver.properties.pae_pavg = estimatePAE('A', 'conventional', specs.frequency_ghz);
      preDriver.properties.pae = preDriver.properties.pae_p3db;
      preDriver.properties.vdd = specs.supply_voltage;
      
      preDriver.properties.compressed_p3db = preDriver.properties.pout_p3db >= preDriver.properties.p1db;
      preDriver.properties.compressed_pavg = preDriver.properties.pout_pavg >= preDriver.properties.p1db;
      
      preDriver.properties.pout = preDriverStage_p3db.pout;
      preDriver.properties.pin = preDriverStage_p3db.pin;
      
      console.log('[Apply Specs] Updated Pre-Driver:');
      console.log(`  At P3dB: Pin=${preDriver.properties.pin_p3db.toFixed(2)} dBm, Pout=${preDriver.properties.pout_p3db.toFixed(2)} dBm, PAE=${preDriver.properties.pae_p3db}%`);
      console.log(`  At Pavg: Pin=${preDriver.properties.pin_pavg.toFixed(2)} dBm, Pout=${preDriver.properties.pout_pavg.toFixed(2)} dBm, PAE=${preDriver.properties.pae_pavg}%`);
    }
    
    // Update Driver
    if (driver) {
      const driverStage_p3db = powerCascade_p3db.find(s => s.stage === 'Driver');
      const driverStage_pavg = powerCascade_pavg.find(s => s.stage === 'Driver');
      
      driver.properties.frequency = specs.frequency_ghz;
      driver.properties.technology = techSelection.technology;
      driver.properties.gain = driverStage_p3db.gain;
      
      // Operating points
      driver.properties.pout_p3db = driverStage_p3db.pout;
      driver.properties.pin_p3db = driverStage_p3db.pin;
      driver.properties.p3db = driverStage_p3db.pout;
      driver.properties.p1db = driverStage_p3db.pout - 2;
      
      driver.properties.pout_pavg = driverStage_pavg.pout;
      driver.properties.pin_pavg = driverStage_pavg.pin;
      driver.properties.pavg = driverStage_pavg.pout;
      
      driver.properties.biasClass = 'A';
      driver.properties.pae_p3db = estimatePAE('A', 'conventional', specs.frequency_ghz);
      driver.properties.pae_pavg = estimatePAE('A', 'conventional', specs.frequency_ghz);
      driver.properties.pae = driver.properties.pae_p3db;
      driver.properties.vdd = specs.supply_voltage;
      
      const driver_compressed_p3db = driver.properties.pout_p3db >= driver.properties.p1db;
      const driver_compressed_pavg = driver.properties.pout_pavg >= driver.properties.p1db;
      
      if (driver_compressed_p3db) {
        console.warn(`⚠️ DRIVER COMPRESSED AT P3dB: Pout=${driver.properties.pout_p3db.toFixed(2)} dBm >= P1dB=${driver.properties.p1db.toFixed(2)} dBm`);
      }
      if (driver_compressed_pavg) {
        console.warn(`⚠️ DRIVER COMPRESSED AT Pavg: Pout=${driver.properties.pout_pavg.toFixed(2)} dBm >= P1dB=${driver.properties.p1db.toFixed(2)} dBm`);
      }
      
      driver.properties.compressed_p3db = driver_compressed_p3db;
      driver.properties.compressed_pavg = driver_compressed_pavg;
      
      driver.properties.pout = driverStage_p3db.pout;
      driver.properties.pin = driverStage_p3db.pin;
      
      console.log('[Apply Specs] Updated Driver:');
      console.log(`  At P3dB: Pin=${driver.properties.pin_p3db.toFixed(2)} dBm, Pout=${driver.properties.pout_p3db.toFixed(2)} dBm, PAE=${driver.properties.pae_p3db}%, Compressed=${driver_compressed_p3db}`);
      console.log(`  At Pavg: Pin=${driver.properties.pin_pavg.toFixed(2)} dBm, Pout=${driver.properties.pout_pavg.toFixed(2)} dBm, PAE=${driver.properties.pae_pavg}%, Compressed=${driver_compressed_pavg}`);
    }
    
    // Update Main PA (same as 2-stage case)
    if (mainPA) {
      const paStage_p3db = powerCascade_p3db.find(s => s.stage === 'PA');
      const paStage_pavg = powerCascade_pavg.find(s => s.stage === 'PA');
      
      mainPA.properties.frequency = specs.frequency_ghz;
      mainPA.properties.technology = techSelection.technology;
      mainPA.properties.gain = paStage_p3db.gain;
      
      const powerCombiningFactor = 3.01;
      
      // P3dB operating point
      const pa_p3db_target = specs.p3db - powerCombiningFactor + combinerLoss;
      mainPA.properties.pout_p3db = pa_p3db_target;
      mainPA.properties.pin_p3db = pa_p3db_target - paStage_p3db.gain;
      mainPA.properties.p3db = pa_p3db_target;
      mainPA.properties.p1db = pa_p3db_target - 2.0;
      
      // Pavg operating point — only Main PA active at backoff, no combining gain
      const pa_pavg_target = pavg_dbm + combinerLoss;  // No -powerCombiningFactor at BO
      mainPA.properties.pout_pavg = pa_pavg_target;
      mainPA.properties.pin_pavg = pa_pavg_target - paStage_pavg.gain;
      mainPA.properties.pavg = pa_pavg_target;
      
      mainPA.properties.biasClass = 'AB';
      mainPA.properties.pae_p3db  = estimatePAE('AB', 'doherty', specs.frequency_ghz);
      mainPA.properties.pae_pavg  = Math.min(85, Math.round(
        mainPA.properties.pae_p3db * doherty_pae_bo_factor
      ));
      mainPA.properties.pae = mainPA.properties.pae_p3db;
      mainPA.properties.vdd = specs.supply_voltage;

      mainPA.properties.pout = mainPA.properties.pout_p3db;
      mainPA.properties.pin  = mainPA.properties.pin_p3db;

      console.log(`[Apply Specs] Updated Main PA (Doherty, 3-stage):`);
      console.log(`  At P3dB: Pin=${mainPA.properties.pin_p3db.toFixed(2)} dBm, Pout=${mainPA.properties.pout_p3db.toFixed(2)} dBm, PAE=${mainPA.properties.pae_p3db}%`);
      console.log(`  At Pavg: Pin=${mainPA.properties.pin_pavg.toFixed(2)} dBm, Pout=${mainPA.properties.pout_pavg.toFixed(2)} dBm, PAE=${mainPA.properties.pae_pavg}%`);
    }

    // Update Aux PA (3-stage path)
    if (auxPA) {
      const paStage_p3db = powerCascade_p3db.find(s => s.stage === 'PA');
      const paStage_pavg = powerCascade_pavg.find(s => s.stage === 'PA');

      auxPA.properties.frequency  = specs.frequency_ghz;
      auxPA.properties.technology = techSelection.technology;
      auxPA.properties.gain       = paStage_p3db.gain;

      // P3dB: both PAs active → per-PA target = pa_target_power
      auxPA.properties.pout_p3db = pa_target_power;
      auxPA.properties.pin_p3db  = pa_target_power - paStage_p3db.gain;
      auxPA.properties.p3db      = pa_target_power;
      auxPA.properties.p1db      = pa_target_power - 2.0;

      // Pavg: Aux PA mostly off (Doherty)
      const aux_pavg_pout_3s = pavg_pa_target - 10;
      auxPA.properties.pout_pavg = aux_pavg_pout_3s;
      auxPA.properties.pin_pavg  = aux_pavg_pout_3s - paStage_pavg.gain;
      auxPA.properties.pavg      = aux_pavg_pout_3s;

      auxPA.properties.biasClass = 'C';
      auxPA.properties.pae_p3db  = estimatePAE('C', 'doherty', specs.frequency_ghz);
      auxPA.properties.pae_pavg  = Math.round(auxPA.properties.pae_p3db * 0.25);
      auxPA.properties.pae       = auxPA.properties.pae_p3db;
      auxPA.properties.vdd       = specs.supply_voltage;

      auxPA.properties.pout = auxPA.properties.pout_p3db;
      auxPA.properties.pin  = auxPA.properties.pin_p3db;

      console.log(`[Apply Specs] Updated Aux PA (Doherty, 3-stage):`);
      console.log(`  At P3dB: Pin=${auxPA.properties.pin_p3db.toFixed(2)} dBm, Pout=${auxPA.properties.pout_p3db.toFixed(2)} dBm, PAE=${auxPA.properties.pae_p3db}%`);
      console.log(`  At Pavg: Pin=${auxPA.properties.pin_pavg.toFixed(2)} dBm, Pout=${auxPA.properties.pout_pavg.toFixed(2)} dBm, PAE=${auxPA.properties.pae_pavg}%`);
    }
  }
  
  // Trigger canvas redraw
  if (window.paCanvas && window.paCanvas.render) {
    window.paCanvas.render();
    console.log('[Apply Specs] Canvas redrawn');
  }
  
  // ═══ SYSTEM PAE: (Pout_system − Pin_system) / PDC_total × 100 ═══
  const pout_sys_w = Math.pow(10, (specs.p3db - 30) / 10);
  const pin_sys_w  = Math.pow(10, ((specs.p3db - specs.gain) - 30) / 10);
  let total_pdc_est_w = 0;
  components.filter(c => c.type === 'transistor').forEach(t => {
    const p_out_t = Math.pow(10, ((t.properties.pout_p3db || t.properties.pout || 40) - 30) / 10);
    const pae_t   = (t.properties.pae_p3db || t.properties.pae || 40) / 100;
    if (pae_t > 0) total_pdc_est_w += p_out_t / pae_t;
  });
  const pae_system = total_pdc_est_w > 0
    ? Math.max(0, ((pout_sys_w - pin_sys_w) / total_pdc_est_w) * 100)
    : 0;
  console.log(`[Apply Specs] System PAE: ${pae_system.toFixed(1)}% | Pout=${pout_sys_w.toFixed(2)}W | Pin=${pin_sys_w.toFixed(4)}W | PDC_est=${total_pdc_est_w.toFixed(2)}W`);

  // ═══ Send updated components + system metrics back to Shiny ═══
  if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
    Shiny.setInputValue('lineup_components', JSON.stringify(components), {priority: 'event'});
    Shiny.setInputValue('spec_pae_system_calc', parseFloat(pae_system.toFixed(1)), {priority: 'event'});
    console.log('[Apply Specs] Sent updated components & system PAE to Shiny');
  }

  alert(`✓ Specifications applied!\n\nTechnology: ${techSelection.technology}\nFrequency: ${specs.frequency_ghz} GHz\nP3dB: ${specs.p3db} dBm\nGain: ${specs.gain} dB\n\nComponents updated. Click "Calculate Lineup" to see results.`);
}

// Custom message handlers for Shiny
console.log('pa_lineup_canvas.js: Script loaded at', new Date().toISOString());
console.log('pa_lineup_canvas.js: Shiny object available?', typeof Shiny !== 'undefined');
console.log('pa_lineup_canvas.js: window.Shiny available?', typeof window.Shiny !== 'undefined');

// Function to register message handler (can be called multiple times safely)
function registerMessageHandlers() {
  if (typeof Shiny === 'undefined' && typeof window.Shiny === 'undefined') {
    console.warn('Shiny not available yet, will retry...');
    return false;
  }
  
  const ShinyObj = typeof Shiny !== 'undefined' ? Shiny : window.Shiny;
  
  console.log('Registering Shiny custom message handlers');
  
  // Remove existing handler if present
  if (ShinyObj.addCustomMessageHandler) {
    // Handler 1: Update Component
    ShinyObj.addCustomMessageHandler('updateComponent', function(data) {
      console.log('=== RECEIVED updateComponent MESSAGE FROM R ===');
      console.log('Timestamp:', new Date().toISOString());
      console.log('Data:', data);
      console.log('Component ID:', data.id, 'Type:', typeof data.id);
      console.log('Properties:', data.properties);
      console.log('window.paCanvas exists?', !!window.paCanvas);
      
      if (!window.paCanvas) {
        console.error('ERROR: paCanvas not found! Attempting to initialize...');
        alert('Canvas not initialized! Check console for details.');
        const success = initializePACanvas();
        if (!success) {
          console.error('Failed to initialize paCanvas');
          alert('Canvas initialization failed. Please refresh the page.');
          return;
        }
        // Wait a moment and try again
        setTimeout(() => {
          if (window.paCanvas) {
            console.log('Canvas initialized, retrying update...');
            window.paCanvas.updateComponent(data.id, data.properties);
          }
        }, 500);
      } else {
        console.log('Calling paCanvas.updateComponent with ID:', data.id);
        try {
          window.paCanvas.updateComponent(data.id, data.properties);
          console.log('Update completed successfully');
        } catch (e) {
          console.error('Error updating component:', e);
          console.error('Stack trace:', e.stack);
          alert('Error updating component: ' + e.message);
        }
      }
    });
    
    // Handler 2: Load Configuration
    ShinyObj.addCustomMessageHandler('loadConfiguration', function(config) {
      console.log('=== RECEIVED loadConfiguration MESSAGE FROM R ===');
      console.log('Config:', config);
      
      if (!window.paCanvas) {
        console.error('ERROR: paCanvas not found!');
        alert('Canvas not initialized!');
        return;
      }
      
      try {
        // Clear existing lineup
        window.paCanvas.clear();
        
        // Load components
        if (config.components && Array.isArray(config.components)) {
          console.log('Loading', config.components.length, 'components...');
          config.components.forEach((comp, index) => {
            console.log(`Loading component ${index}:`, comp.type, 'at', comp.x, comp.y);
            window.paCanvas.addComponent(
              comp.type,
              comp.x,
              comp.y,
              comp.properties || {}
            );
          });
        }
        
        // Load connections
        if (config.connections && Array.isArray(config.connections)) {
          console.log('Loading', config.connections.length, 'connections...');
          window.paCanvas.connections = config.connections;
          window.paCanvas.renderConnections();
        }
        
        console.log('✓ Configuration loaded successfully');
        alert('Configuration loaded successfully!');
        
      } catch (e) {
        console.error('Error loading configuration:', e);
        alert('Error loading configuration: ' + e.message);
      }
    });
    
    // Handler 3: Validate and Calculate
    ShinyObj.addCustomMessageHandler('validateAndCalculate', function(data) {
      console.log('=== RECEIVED validateAndCalculate MESSAGE FROM R ===');
      
      if (!window.paCanvas) {
        console.error('ERROR: paCanvas not found!');
        return;
      }
      
      // Run validation with visual feedback
      const isValid = window.paCanvas.showValidationResults();
      
      if (!isValid) {
        console.log('Validation failed - calculation blocked');
      } else {
        console.log('Validation passed - calculation will proceed');
      }
    });
    
    // Handler 4: Update User Templates
    ShinyObj.addCustomMessageHandler('updateUserTemplates', function(templates) {
      console.log('=== RECEIVED updateUserTemplates MESSAGE FROM R ===');
      console.log('Templates:', templates);
      
      // Find the templates container
      const container = document.querySelector('.top-sidebar-templates');
      if (!container) {
        console.error('Templates container not found!');
        return;
      }
      
      // Remove existing user templates
      const existingUserTemplates = container.querySelectorAll('[data-preset^="user_"]');
      existingUserTemplates.forEach(t => t.remove());
      
      // Add user templates
      templates.forEach(function(template) {
        const div = document.createElement('div');
        div.className = 'preset-template';
        div.setAttribute('data-preset', template.id);
        div.setAttribute('data-template-type', 'user');
        
        const h5 = document.createElement('h5');
        h5.textContent = template.name;
        
        const p = document.createElement('p');
        p.textContent = `Custom template (${template.components_count} components)`;
        p.style.color = '#88ccff';
        
        div.appendChild(h5);
        div.appendChild(p);
        container.appendChild(div);
        
        // Add click handler
        div.addEventListener('click', function() {
          const preset = this.getAttribute('data-preset');
          console.log('User template clicked:', preset);
          
          // Request template data from server
          if (typeof Shiny !== 'undefined') {
            Shiny.setInputValue('load_user_template', preset, {priority: 'event'});
          }
          
          // Visual feedback
          const all_templates = container.querySelectorAll('.preset-template');
          all_templates.forEach(t => t.classList.remove('active'));
          this.classList.add('active');
        });
        
        div.style.cursor = 'pointer';
      });
      
      console.log('✓ User templates added to UI');
    });
    
    // Handler 5: Load User Template Data
    ShinyObj.addCustomMessageHandler('loadUserTemplateData', function(template_data) {
      console.log('=== RECEIVED loadUserTemplateData MESSAGE FROM R ===');
      console.log('Template:', template_data.name);
      
      if (!window.paCanvas) {
        console.error('Canvas not initialized!');
        alert('Canvas not ready. Please try again.');
        return;
      }
      
      // Clear canvas
      window.paCanvas.clear();
      
      // Set loading flag
      window.paCanvas._loadingTemplate = true;
      
      // Add components
      const componentMap = new Map();
      template_data.components.forEach(comp => {
        const newComp = window.paCanvas.addComponent(
          comp.type,
          comp.x,
          comp.y,
          comp.properties
        );
        componentMap.set(comp.id, newComp.id);
      });
      
      // Add wires
      template_data.wires.forEach(wire => {
        const newFromId = componentMap.get(wire.fromId);
        const newToId = componentMap.get(wire.toId);
        if (newFromId && newToId) {
          window.paCanvas.createConnection(
            newFromId,
            newToId,
            wire.fromPort,
            wire.toPort
          );
        }
      });
      
      // Clear loading flag
      window.paCanvas._loadingTemplate = false;
      
      console.log('✓ User template loaded successfully');
    });
    
   // Handler 6: Reload User Templates
    ShinyObj.addCustomMessageHandler('reloadUserTemplates', function(data) {
      console.log('=== RECEIVED reloadUserTemplates MESSAGE FROM R ===');
      // Trigger re-render by requesting updated list
      // The observer in R will automatically send updateUserTemplates
    });
    
    // Handler 7: Apply Specifications to Lineup
    ShinyObj.addCustomMessageHandler('applySpecsToLineup', function(specs) {
      console.log('=== RECEIVED applySpecsToLineup MESSAGE FROM R ===');
      console.log('Specifications:', specs);
      
      if (!window.paCanvas) {
        console.error('Canvas not initialized!');
        alert('Canvas not initialized. Please wait for canvas to load.');
        return;
      }
      
      // Store specs globally for current canvas
      window.currentLineupSpecs = specs;
      
      // Get current components to determine if we have a template loaded
      const components = window.paCanvas.components;
      
      if (!components || components.length === 0) {
        // No template loaded - inform user
        console.log('[Apply Specs] No template loaded');
        alert('Please load a template first (e.g., Single Doherty from Architecture Templates), then apply specifications.');
        return;
      }
      
      // Apply specs to existing components
      applySpecsToComponents(specs);
      
      console.log('✓ Specifications applied to lineup');
    });

    // Handler 8: Sync Lineup Specs — PAR/P3dB/frequency changes from R Specifications panel
    ShinyObj.addCustomMessageHandler('syncLineupSpecs', function(specs) {
      console.log('[Sync Lineup Specs] Received:', specs);
      window.currentLineupSpecs = Object.assign(window.currentLineupSpecs || {}, specs);
      // Redraw active display overlays so Pavg values (driven by PAR) refresh immediately
      if (window.paCanvas) {
        if (window.paCanvas.showPowerDisplay)     window.paCanvas.drawPowerColumns();
        if (window.paCanvas.showGainDisplay)      window.paCanvas.drawGainColumns();
        if (window.paCanvas.showPAEDisplay)       window.paCanvas.drawPAEColumns();
        if (window.paCanvas.showImpedanceDisplay) window.paCanvas.drawImpedanceColumns();
        if (window.paCanvas.showPhaseDisplay)     window.paCanvas.drawPhaseColumns();
        window.paCanvas.drawPaGroupBoxes();
      }
    });

    // Handler 9: Redraw Canvas Display — called after R Calculate/Optimize pushes new values
    ShinyObj.addCustomMessageHandler('redrawCanvasDisplay', function(msg) {
      if (!window.paCanvas) return;
      if (window.paCanvas.showPowerDisplay)     window.paCanvas.drawPowerColumns();
      if (window.paCanvas.showGainDisplay)      window.paCanvas.drawGainColumns();
      if (window.paCanvas.showPAEDisplay)       window.paCanvas.drawPAEColumns();
      if (window.paCanvas.showImpedanceDisplay) window.paCanvas.drawImpedanceColumns();
      if (window.paCanvas.showPhaseDisplay)     window.paCanvas.drawPhaseColumns();
      window.paCanvas.drawPaGroupBoxes();
      window.paCanvas.render();
      console.log('[Redraw Canvas] All active display layers refreshed');
    });

    // Handler 10: Update Device Portfolio (saved single-transistor devices from Guardrails tab)
    ShinyObj.addCustomMessageHandler('updateDevicePortfolio', function(devices) {
      console.log('=== RECEIVED updateDevicePortfolio MESSAGE FROM R ===');
      console.log('Devices:', devices.length);

      // Find the dedicated Device Library column in the two-column top sidebar
      let container = document.getElementById('top_sidebar_device_col');
      if (!container) {
        console.warn('Device Library column not found — device portfolio will not render.');
        return;
      }

      // Remove any previous portfolio section
      const existingSection = document.getElementById('device-portfolio-section');
      if (existingSection) existingSection.remove();

      // Show/hide empty hint
      const emptyHint = container.querySelector('.top-sidebar-empty-hint');
      if (!devices || devices.length === 0) {
        if (emptyHint) emptyHint.style.display = '';
        return;
      }
      if (emptyHint) emptyHint.style.display = 'none';

      // Build section wrapper (no heading — column title already shows "Device Library")
      const section = document.createElement('div');
      section.id = 'device-portfolio-section';

      const statusColors = { ok: '#27ae60', warning: '#f39c12', error: '#e74c3c' };

      devices.forEach(function(dev) {
        const div = document.createElement('div');
        div.className = 'preset-template';
        div.setAttribute('data-preset', dev.id);
        div.setAttribute('data-device-type', 'portfolio');
        const props = dev.canvas_component || {};

        // Title row
        const h5 = document.createElement('h5');
        h5.textContent = dev.label || dev.id;
        h5.style.marginBottom = '2px';

        // Subtitle row
        const p = document.createElement('p');
        const sc = statusColors[dev.validation_status] || '#aaa';
        p.innerHTML = (dev.tech_label || dev.technology || '') +
          ' · ' + (dev.freq_ghz || '') + ' GHz · G=' + (dev.gain_db || '') +
          ' dB · PAE=' + (dev.pae_pct || '') + '%' +
          ' <span style="color:' + sc + '; font-size:10px;">[' +
          (dev.validation_status || '').toUpperCase() + ']</span>';
        p.style.fontSize = '11px';
        p.style.color = '#aaa';
        p.style.marginBottom = '0';

        div.appendChild(h5);
        div.appendChild(p);
        section.appendChild(div);

        // Click handler — adds transistor at canvas centre with saved properties
        div.style.cursor = 'pointer';
        div.style.borderLeft = '3px solid ' + sc;
        div.addEventListener('click', function() {
          if (!window.paCanvas) {
            alert('Canvas not ready. Please wait and try again.');
            return;
          }
          // Place in the middle of the visible canvas area
          const canvasEl = document.getElementById('pa-canvas');
          const cx = canvasEl ? Math.round(canvasEl.getBoundingClientRect().width  / 2) : 400;
          const cy = canvasEl ? Math.round(canvasEl.getBoundingClientRect().height / 2) : 300;

          const techName = (props.technology || dev.technology || 'GaN').replace(/_/g, ' ');
          const compProps = {
            label     : props.label      || dev.label || 'PA',
            technology: techName,
            biasClass : props.biasClass  || 'AB',
            pout      : props.pout       || dev.pout_dbm || 43,
            p1db      : props.p1db       || dev.p1db_dbm || 41,
            gain      : props.gain       || dev.gain_db  || 15,
            pae       : props.pae        || dev.pae_pct  || 50,
            vdd       : props.vdd        || dev.vdd      || 28,
            rth       : 2.5,
            freq      : props.freq       || dev.freq_ghz || 3.5
          };

          console.log('Adding portfolio device to canvas:', compProps);
          window.paCanvas.addComponent('transistor', cx, cy, compProps);

          // Visual feedback
          const allTpl = container.querySelectorAll('.preset-template');
          allTpl.forEach(t => t.classList.remove('active'));
          this.classList.add('active');
        });
      });

      container.appendChild(section);
      console.log('✓ Device portfolio rendered (' + devices.length + ' devices)');
    });

    console.log('✓ Shiny message handlers registered successfully');
    return true;
  } else {
    console.error('ShinyObj.addCustomMessageHandler not available!');
    return false;
  }
}

// Try to register immediately
if (typeof Shiny !== 'undefined' || typeof window.Shiny !== 'undefined') {
  registerMessageHandlers();
} else {
  console.warn('Shiny object not available - will register on DOMContentLoaded');
}

// Also try on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded: Attempting to register message handlers');
  registerMessageHandlers();
});

// And on window load
window.addEventListener('load', function() {
  console.log('Window load: Attempting to register message handlers');
  registerMessageHandlers();
});

// And when Shiny is connected
if (typeof $ !== 'undefined') {
  $(document).on('shiny:connected', function() {
    console.log('Shiny connected event: Registering message handlers');
    registerMessageHandlers();
  });
}

// ============================================================
// Global Parameter Accessors
// These functions retrieve global lineup parameters from Shiny inputs
// Used for frequency, backoff, PAR, and Pavg in calculations
// ============================================================

function getGlobalFrequency() {
  if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$inputValues) {
    return Shiny.shinyapp.$inputValues.global_frequency || 2.6;
  }
  return 2.6; // fallback default
}

function getGlobalBackoff() {
  if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$inputValues) {
    return Shiny.shinyapp.$inputValues.global_backoff || 6;
  }
  return 6; // fallback default
}

function getGlobalPAR() {
  if (window.Shiny && Shiny.shinyapp && Shiny.shinyapp.$inputValues) {
    return Shiny.shinyapp.$inputValues.global_PAR || 8;
  }
  return 8; // fallback default
}

// Expose to window for global access
window.getGlobalFrequency = getGlobalFrequency;
window.getGlobalBackoff = getGlobalBackoff;
window.getGlobalPAR = getGlobalPAR;

console.log('✓ Global parameter accessors loaded');

// ============================================================
// Canvas Sidebar Toggle Function
// ============================================================

function toggleCanvasSidebar() {
  const sidebar = document.getElementById('canvas_sidebar');
  const toggle = document.getElementById('sidebar_toggle');
  
  if (!sidebar) {
    console.error('Sidebar not found!');
    return;
  }
  
  // Toggle between collapsed and expanded states
  if (sidebar.classList.contains('collapsed')) {
    sidebar.classList.remove('collapsed');
    sidebar.classList.add('expanded');
    console.log('Sidebar expanded');
  } else {
    sidebar.classList.remove('expanded');
    sidebar.classList.add('collapsed');
    console.log('Sidebar collapsed');
  }
}

// Initialize sidebars as collapsed on page load
document.addEventListener('DOMContentLoaded', function() {
  const sidebar = document.getElementById('canvas_sidebar');
  if (sidebar) {
    sidebar.classList.add('collapsed');
    console.log('Right sidebar initialized in collapsed state');
  }
  
  const topSidebar = document.getElementById('canvas_top_sidebar');
  if (topSidebar) {
    topSidebar.classList.add('collapsed');
    console.log('Top sidebar initialized in collapsed state');
  }
});

// ============================================================
// Shiny Custom Message Handlers
// ============================================================

// Handler for canvas layout changes
if (typeof Shiny !== 'undefined') {
  Shiny.addCustomMessageHandler('updateCanvasLayout', function(message) {
    console.log('📐 Received canvas layout update:', message.layout);
    
    if (initializeMultiCanvas(message.layout)) {
      console.log('✅ Canvas layout updated successfully');
    } else {
      console.error('❌ Failed to update canvas layout');
    }
  });
  
  // Handler for updating canvas names
  Shiny.addCustomMessageHandler('updateCanvasNames', function(message) {
    console.log('🏷️ Received canvas names update:', message.names);
    
    if (message.names && Array.isArray(message.names)) {
      message.names.forEach((name, index) => {
        if (window.canvasLabels && window.canvasLabels[index]) {
          window.canvasLabels[index].textContent = name;
          console.log(`✅ Updated canvas ${index} label to: ${name}`);
        }
      });
    }
  });
  
  // Handler for requesting all canvas data (for Calculate All Canvases)
  Shiny.addCustomMessageHandler('requestAllCanvasData', function(message) {
    console.log('📊 Received request for all canvas data');
    
    if (!window.paCanvases || window.paCanvases.length === 0) {
      console.warn('No canvases available');
      return;
    }
    
    // Send data from each canvas to R
    window.paCanvases.forEach((canvas, index) => {
      console.log(`📤 Sending data for canvas ${index}`);
      
      // Temporarily set as active to ensure Shiny receives correct canvas index
      const previousActive = window.activeCanvasIndex;
      setActiveCanvas(index);
      
      // Send components and connections
      if (canvas.components && canvas.components.length > 0) {
        Shiny.setInputValue('lineup_components', JSON.stringify(canvas.components), {priority: 'event'});
      }
      if (canvas.connections && canvas.connections.length > 0) {
        Shiny.setInputValue('lineup_connections', JSON.stringify(canvas.connections), {priority: 'event'});
      }
      
      // Wait a bit before processing next canvas
      // Note: This is synchronous in practice due to event loop
    });
    
    console.log('✅ All canvas data sent to R');
  });
  
  console.log('✅ Shiny message handlers registered');
}

// ============================================================
// Canvas Comparison Table
// ============================================================

let comparisonTableVisible = false;

function toggleCanvasComparison() {
  comparisonTableVisible = !comparisonTableVisible;
  
  if (comparisonTableVisible) {
    showComparisonTable();
  } else {
    hideComparisonTable();
  }
}

function showComparisonTable() {
  // Remove existing table if any
  d3.select('#canvas_comparison_table').remove();
  
  if (!window.paCanvases || window.paCanvases.length <= 1) {
    console.warn('Comparison requires multiple canvases');
    return;
  }
  
  // Collect metrics from all canvases
  const comparisonData = window.paCanvases.map((canvas, index) => {
    if (!canvas || !canvas.components) {
      return {
        index: index,
        label: `Canvas ${index + 1}`,
        components: 0,
        stages: 0,
        totalGain: 0,
        finalPout: 0,
        totalLoss: 0,
        transistorCount: 0,
        technologies: []
      };
    }
    
    const components = canvas.components;
    const transistors = components.filter(c => c.type === 'transistor');
    const lossy = components.filter(c => ['matching', 'splitter', 'combiner'].includes(c.type));
    
    // Calculate total gain
    let totalGain = 0;
    transistors.forEach(t => {
      totalGain += t.properties.gain || 0;
    });
    
    // Calculate total loss
    let totalLoss = 0;
    lossy.forEach(l => {
      totalLoss += l.properties.loss || 0;
    });
    
    // Get final output power (from last transistor)
    let finalPout = 0;
    if (transistors.length > 0) {
      const sorted = [...components].sort((a, b) => a.x - b.x);
      const lastTransistor = sorted.reverse().find(c => c.type === 'transistor');
      if (lastTransistor) {
        finalPout = lastTransistor.properties.pout || 0;
      }
    }
    
    // Get unique technologies
    const technologies = [...new Set(transistors.map(t => t.properties.technology || 'Unknown'))];
    
    // Calculate average PAE
    let avgPAE = 0;
    if (transistors.length > 0) {
      const totalPAE = transistors.reduce((sum, t) => sum + (t.properties.pae || 0), 0);
      avgPAE = totalPAE / transistors.length;
    }
    
    return {
      index: index,
      label: `Canvas ${index + 1}`,
      components: components.length,
      stages: transistors.length,
      totalGain: totalGain.toFixed(1),
      finalPout: finalPout.toFixed(1),
      totalLoss: totalLoss.toFixed(2),
      transistorCount: transistors.length,
      technologies: technologies.join(', '),
      avgPAE: avgPAE.toFixed(1)
    };
  });
  
  // Create comparison table overlay
  const container = document.getElementById('pa_lineup_canvas_container');
  if (!container) return;
  
  const table = d3.select(container)
    .append('div')
    .attr('id', 'canvas_comparison_table')
    .style('position', 'absolute')
    .style('top', '50%')
    .style('left', '50%')
    .style('transform', 'translate(-50%, -50%)')
    .style('background', 'rgba(26, 26, 26, 0.98)')
    .style('border', '2px solid #ff7f11')
    .style('border-radius', '10px')
    .style('padding', '20px')
    .style('max-width', '90%')
    .style('max-height', '80%')
    .style('overflow', 'auto')
    .style('z-index', '2000')
    .style('box-shadow', '0 10px 40px rgba(0, 0, 0, 0.8)');
  
  // Header
  table.append('div')
    .style('display', 'flex')
    .style('justify-content', 'space-between')
    .style('align-items', 'center')
    .style('margin-bottom', '20px')
    .html(`
      <h3 style="color: #ff7f11; margin: 0;">
        <i class="fa fa-columns"></i> Canvas Comparison
      </h3>
      <button onclick="hideComparisonTable()" style="
        background: #ff7f11;
        border: none;
        color: white;
        padding: 8px 15px;
        border-radius: 5px;
        cursor: pointer;
        font-size: 14px;">
        <i class="fa fa-times"></i> Close
      </button>
    `);
  
  // Create HTML table
  let tableHTML = `
    <table style="
      width: 100%;
      border-collapse: collapse;
      color: #fff;
      font-size: 14px;">
      <thead>
        <tr style="background: rgba(255, 127, 17, 0.2); border-bottom: 2px solid #ff7f11;">
          <th style="padding: 12px; text-align: left; border-right: 1px solid #444;">Metric</th>
  `;
  
  comparisonData.forEach(data => {
    tableHTML += `<th style="padding: 12px; text-align: center; border-right: 1px solid #444;">${data.label}</th>`;
  });
  
  tableHTML += `
        </tr>
      </thead>
      <tbody>
        <tr style="background: rgba(255, 255, 255, 0.05);">
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Total Components</td>
  `;
  
  comparisonData.forEach(data => {
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444;">${data.components}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr>
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">PA Stages</td>
  `;
  
  comparisonData.forEach(data => {
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444;">${data.stages}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr style="background: rgba(255, 255, 255, 0.05);">
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Total Gain (dB)</td>
  `;
  
  comparisonData.forEach(data => {
    const isMax = parseFloat(data.totalGain) === Math.max(...comparisonData.map(d => parseFloat(d.totalGain)));
    const style = isMax ? 'color: #00ff88; font-weight: bold;' : '';
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444; ${style}">${data.totalGain}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr>
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Final Pout (dBm)</td>
  `;
  
  comparisonData.forEach(data => {
    const isMax = parseFloat(data.finalPout) === Math.max(...comparisonData.map(d => parseFloat(d.finalPout)));
    const style = isMax ? 'color: #00ff88; font-weight: bold;' : '';
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444; ${style}">${data.finalPout}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr style="background: rgba(255, 255, 255, 0.05);">
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Total Loss (dB)</td>
  `;
  
  comparisonData.forEach(data => {
    const isMin = parseFloat(data.totalLoss) === Math.min(...comparisonData.map(d => parseFloat(d.totalLoss)));
    const style = isMin ? 'color: #00ff88; font-weight: bold;' : '';
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444; ${style}">${data.totalLoss}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr>
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Avg PAE (%)</td>
  `;
  
  comparisonData.forEach(data => {
    const isMax = parseFloat(data.avgPAE) === Math.max(...comparisonData.map(d => parseFloat(d.avgPAE)));
    const style = isMax ? 'color: #00ff88; font-weight: bold;' : '';
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444; ${style}">${data.avgPAE}</td>`;
  });
  
  tableHTML += `
        </tr>
        <tr style="background: rgba(255, 255, 255, 0.05);">
          <td style="padding: 10px; font-weight: bold; border-right: 1px solid #444;">Technologies</td>
  `;
  
  comparisonData.forEach(data => {
    tableHTML += `<td style="padding: 10px; text-align: center; border-right: 1px solid #444; font-size: 12px;">${data.technologies || 'None'}</td>`;
  });
  
  tableHTML += `
        </tr>
      </tbody>
    </table>
  `;
  
  table.append('div').html(tableHTML);
  
  // Add note
  table.append('div')
    .style('margin-top', '15px')
    .style('padding', '10px')
    .style('background', 'rgba(255, 127, 17, 0.1)')
    .style('border-radius', '5px')
    .style('font-size', '12px')
    .style('color', '#aaa')
    .html(`
      <i class="fa fa-info-circle"></i> 
      <strong>Note:</strong> Best values are highlighted in green. 
      This comparison shows metrics from all active canvases in the current layout.
    `);
  
  console.log('📊 Comparison table displayed');
}

function hideComparisonTable() {
  d3.select('#canvas_comparison_table').remove();
  comparisonTableVisible = false;
  console.log('📊 Comparison table hidden');
}

window.toggleCanvasComparison = toggleCanvasComparison;
window.showComparisonTable = showComparisonTable;
window.hideComparisonTable = hideComparisonTable;

console.log('✓ Canvas comparison functions loaded');
// ========================================
// Save as Template Function
// ========================================

function saveCurrentAsTemplate() {
  console.log('=== saveCurrentAsTemplate called ===');
  
  if (!window.paCanvas) {
    alert('Canvas not initialized!');
    return;
  }
  
  // Get template name from input
  const templateName = $('#template_name').val();
  if (!templateName || templateName.trim() === '') {
    alert('Please enter a template name');
    return;
  }
  
  // Check if canvas has components
  if (window.paCanvas.components.length === 0) {
    alert('Canvas is empty! Add some components before saving as a template.');
    return;
  }
  
  // Serialize canvas state
  const templateData = {
    name: templateName.trim(),
    components: window.paCanvas.components.map(comp => ({
      id: comp.id,
      type: comp.type,
      x: comp.x,
      y: comp.y,
      properties: comp.properties
    })),
    connections: (window.paCanvas.connections || []).map(conn => ({
      fromId: conn.fromId,
      toId: conn.toId,
      fromPort: conn.fromPort,
      toPort: conn.toPort
    }))
  };
  
  console.log('Template data:', templateData);
  
  // Send to Shiny
  if (typeof Shiny !== 'undefined') {
    Shiny.setInputValue('save_template_data', templateData, {priority: 'event'});
    console.log('Template data sent to Shiny');
    
    // Clear the input field
    $('#template_name').val('');
    
    // Show success message
    setTimeout(() => {
      alert(`Template "${templateName}" saved successfully!`);
    }, 100);
  } else {
    console.error('Shiny not available!');
    alert('Error: Cannot save template (Shiny not connected)');
  }
}

window.saveCurrentAsTemplate = saveCurrentAsTemplate;

// Edit/Rename Template
function editTemplate(filename, currentName) {
  const newName = prompt(`Rename template "${currentName}" to:`, currentName);
  
  if (newName && newName.trim() !== '' && newName !== currentName) {
    // Send to R Shiny
    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue('edit_template_filename', filename);
      Shiny.setInputValue('edit_template_newname', newName.trim());
      Shiny.setInputValue('edit_template_submit', Math.random(), {priority: 'event'});
      console.log(`📝 Editing template: ${filename} -> ${newName}`);
    }
  }
}

window.editTemplate = editTemplate;

// Load User Template Function
function loadUserTemplate(filename) {
  console.log('=== loadUserTemplate called ===');
  console.log('Filename:', filename);
  
  if (!window.paCanvas) {
    alert('Canvas not initialized!');
    return;
  }
  
  // Send to Shiny to load the template
  if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
    Shiny.setInputValue('load_user_template_filename', filename, {priority: 'event'});
    console.log(`📂 Loading user template: ${filename}`);
  } else {
    console.error('Shiny not available!');
    alert('Error: Cannot load template (Shiny not connected)');
  }
}

window.loadUserTemplate = loadUserTemplate;

console.log('✓ Save template functions loaded');
// ============================================================
// Sticky Canvas Functionality
// ============================================================

function initStickyCanvas() {
  console.log('=== initStickyCanvas called ===');
  
  const stickyBox = document.getElementById('sticky_canvas_box');
  
  if (!stickyBox) {
    console.warn('⚠ Sticky canvas box NOT found - element with id="sticky_canvas_box" does not exist');
    return;
  }
  
  console.log('✓ Found sticky canvas box element');
  console.log('Current computed position:', window.getComputedStyle(stickyBox).position);
  
  // Ensure parent containers support sticky positioning
  let parent = stickyBox.parentElement;
  let depth = 0;
  while (parent && depth < 5) {
    const styles = window.getComputedStyle(parent);
    if (styles.overflow === 'hidden' || styles.overflow === 'auto') {
      console.warn('⚠ Parent container has overflow:', styles.overflow, '- this may prevent sticky behavior');
    }
    parent = parent.parentElement;
    depth++;
  }
  
  // Monitor scroll to add/remove stuck class for visual effect
  const observer = new IntersectionObserver(
    ([entry]) => {
      const isStuck = entry.intersectionRatio < 1;
      console.log('Intersection changed - Stuck:', isStuck, 'Ratio:', entry.intersectionRatio);
      
      if (isStuck) {
        stickyBox.classList.add('stuck');
      } else {
        stickyBox.classList.remove('stuck');
      }
    },
    { threshold: [1] }
  );
  
  observer.observe(stickyBox);
  
  console.log('✓ Sticky canvas initialized with IntersectionObserver');
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initStickyCanvas);
} else {
  initStickyCanvas();
}

// Also reinitialize after Shiny renders
if (window.Shiny) {
  Shiny.addCustomMessageHandler('reinit_sticky', function() {
    setTimeout(initStickyCanvas, 100);
  });
}

console.log('✓ Sticky canvas script loaded');

