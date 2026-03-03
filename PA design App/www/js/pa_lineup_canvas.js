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
    
    // Power display columns
    this.showPowerDisplay = false;
    this.powerColumns = [];
    this.powerUnit = 'dBm'; // 'dBm', 'W', or 'both'
    
    // Impedance display columns
    this.showImpedanceDisplay = false;
    this.impedanceColumns = [];
    this.impedanceUnit = 'rectangular'; // 'rectangular' (50+j10), 'polar' (51∠11°), or 'vswr'
    this.impedanceMode = 'full'; // 'full' or 'backoff' - NEW: show full power or backoff impedance
    
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
    this.calculationRationaleLayer = this.svg.append('g').attr('class', 'calculation-rationale-layer');
    this.connectionsLayer = this.svg.append('g').attr('class', 'connections-layer');
    this.componentsLayer = this.svg.append('g').attr('class', 'components-layer');
    
    // Create zoom group that contains all drawable layers
    this.zoomGroup = this.svg.insert('g', ':first-child').attr('class', 'zoom-group');
    this.zoomGroup.node().appendChild(this.gridLayer.node());
    this.zoomGroup.node().appendChild(this.centralLineLayer.node());
    this.zoomGroup.node().appendChild(this.powerLayer.node());
    this.zoomGroup.node().appendChild(this.impedanceLayer.node());
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
  
  drawGuideLines() {
    // Clear existing guide lines
    this.centralLineLayer.selectAll('*').remove();
    
    // Use origin as center point
    const centerY = this.originY;
    const centerX = this.originX;
    
    // Grid spacing (in pixels) - matches typical component spacing
    const gridSpacing = 100;  // 100px grid for alignment
    
    // Draw horizontal grid lines (create rows)
    if (this.showGrid || this.showHorizontalLine) {
      const numHorizontalLines = Math.ceil(this.height / gridSpacing);
      
      for (let i = 0; i <= numHorizontalLines; i++) {
        const y = i * gridSpacing;
        const isMainDivider = Math.abs(y - centerY) < gridSpacing / 2;
        
        this.centralLineLayer.append('line')
          .attr('x1', 0)
          .attr('y1', y)
          .attr('x2', this.width)
          .attr('y2', y)
          .attr('stroke', isMainDivider ? '#00aaff' : '#444')
          .attr('stroke-width', isMainDivider ? 2 : 1)
          .attr('stroke-dasharray', isMainDivider ? '10,5' : '5,5')
          .attr('opacity', isMainDivider ? 0.3 : 0.15);
      }
      
      // Add main divider label
      if (this.showHorizontalLine) {
        this.centralLineLayer.append('text')
          .attr('x', this.width - 120)
          .attr('y', centerY - 10)
          .attr('fill', '#00aaff')
          .attr('font-size', '12px')
          .attr('opacity', 0.5)
          .text('Main/Aux Divider');
      }
    }
    
    // Draw vertical grid lines (create columns)
    if (this.showGrid || this.showVerticalLine) {
      const numVerticalLines = Math.ceil(this.width / gridSpacing);
      
      for (let i = 0; i <= numVerticalLines; i++) {
        const x = i * gridSpacing;
        const isOrigin = Math.abs(x - centerX) < gridSpacing / 2;
        
        this.centralLineLayer.append('line')
          .attr('x1', x)
          .attr('y1', 0)
          .attr('x2', x)
          .attr('y2', this.height)
          .attr('stroke', isOrigin ? '#00aaff' : '#444')
          .attr('stroke-width', isOrigin ? 2 : 1)
          .attr('stroke-dasharray', isOrigin ? '10,5' : '5,5')
          .attr('opacity', isOrigin ? 0.3 : 0.15);
      }
      
      // Add origin label
      if (this.showVerticalLine) {
        this.centralLineLayer.append('text')
          .attr('x', centerX + 10)
          .attr('y', 30)
          .attr('fill', '#00aaff')
          .attr('font-size', '12px')
          .attr('opacity', 0.5)
          .text('Origin');
      }
    }
   
    // Add origin marker (circle at crosshair intersection)
    if (this.showHorizontalLine && this.showVerticalLine) {
      this.centralLineLayer.append('circle')
        .attr('cx', centerX)
        .attr('cy', centerY)
        .attr('r', 3)
        .attr('fill', '#00aaff')
        .attr('opacity', 0.5);
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
        d3.select(this).style('width', '200px');
        d3.selectAll('.palette-label').style('display', 'block');
      })
      .on('mouseleave', function() {
        d3.select(this).style('width', '60px');
        d3.selectAll('.palette-label').style('display', 'none');
      });
    
    const components = [
      { type: 'transistor', icon: '▲', label: 'Transistor', color: '#00aaff' },
      { type: 'matching', icon: '═', label: 'Matching', color: '#00ff88' },
      { type: 'splitter', icon: '⊥', label: 'Splitter', color: '#ffaa00' },
      { type: 'combiner', icon: '⊤', label: 'Combiner', color: '#ff00aa' },
      { type: 'wire', icon: '━', label: 'Wire Mode', color: '#ff7f11', isAction: true }
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
      
      item.append('div')
        .style('font-size', '24px')
        .style('color', comp.color)
        .text(comp.icon);
      
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
    
    const x = this.width / 2;
    const y = this.height / 2;
    
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
    
    // Label - positioned ABOVE component to avoid overlap
    group.append('text')
      .attr('x', 22)
      .attr('y', -35)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '14px')
      .attr('font-weight', 'bold')
      .text(component.properties.label || 'PA');
    
    // Display technology text in center of triangle
    const technology = component.properties.technology || 'GaN';
    group.append('text')
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
      group.append('text')
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
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#aaddff')
        .attr('font-size', '8px')
        .text(`Class ${component.properties.biasClass || 'AB'}`);
      yOffset += 10;
    }
    
    if (display.includes('gain')) {
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#88ff88')
        .attr('font-size', '8px')
        .text(`Gain: ${component.properties.gain || 10} dB`);
      yOffset += 10;
    }
    
    if (display.includes('pae')) {
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffdd44')
        .attr('font-size', '8px')
        .text(`PAE: ${component.properties.pae || 50}%`);
      yOffset += 10;
    }
    
    if (display.includes('pout')) {
      const poutValue = component.properties.pout || 40;
      const poutText = this.formatPower(poutValue, this.powerUnit);
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff88ff')
        .attr('font-size', '8px')
        .text(`Pout: ${poutText}`);
      yOffset += 10;
    }
    
    if (display.includes('p1db')) {
      const p1dbValue = component.properties.p1db || component.properties.pout || 40;
      const p1dbText = this.formatPower(p1dbValue, this.powerUnit);
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffaa00')
        .attr('font-size', '8px')
        .text(`P1dB: ${p1dbText}`);
      yOffset += 10;
    }
    
    if (display.includes('vdd')) {
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff6666')
        .attr('font-size', '8px')
        .text(`VDD: ${component.properties.vdd || 28}V`);
      yOffset += 10;
    }
    
    if (display.includes('freq')) {
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#cc88ff')
        .attr('font-size', '8px')
        .text(`f: ${component.properties.freq || 2.6} GHz`);
      yOffset += 10;
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
    // Enhanced industry-standard Wilkinson splitter representation
    
    // Background box to show it's a packaged component
    group.append('rect')
      .attr('x', -25)
      .attr('y', -20)
      .attr('width', 50)
      .attr('height', 40)
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
    
    // Junction node
    group.append('circle')
      .attr('cx', -5)
      .attr('cy', 0)
      .attr('r', 3)
      .attr('fill', '#ffaa00');
    
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
    
    // Output ports
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
    // Enhanced industry-standard Wilkinson combiner representation (mirror of splitter)
    
    // Background box to show it's a packaged component
    group.append('rect')
      .attr('x', -25)
      .attr('y', -20)
      .attr('width', 50)
      .attr('height', 40)
      .attr('fill', '#1a1a1a')
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 2)
      .attr('rx', 4);
    
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
    
    // Output line
    group.append('line')
      .attr('x1', 5)
      .attr('y1', 0)
      .attr('x2', 25)
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
    
    // Junction node
    group.append('circle')
      .attr('cx', 5)
      .attr('cy', 0)
      .attr('r', 3)
      .attr('fill', '#ff00aa');
    
    // Input ports
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
    // Ground/termination symbol - triangle with line
    const termColor = '#888888';
    
    // Triangle pointing down
    group.append('polygon')
      .attr('points', '0,-15 -12,0 12,0')
      .attr('fill', termColor)
      .attr('stroke', '#fff')
      .attr('stroke-width', 2);
    
    // Three horizontal lines (resembling ground symbol)
    for (let i = 0; i < 3; i++) {
      const width = 24 - i * 6;
      const y = i * 4 + 2;
      group.append('line')
        .attr('x1', -width/2)
        .attr('y1', y)
        .attr('x2', width/2)
        .attr('y2', y)
        .attr('stroke', '#fff')
        .attr('stroke-width', 2);
    }
    
    // Input port (left)
    const inputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', 0)
      .attr('cy', -20)
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
        .attr('y', -30)
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '11px')
        .attr('font-weight', 'bold')
        .text(component.properties.label || 'Load');
    }
    
    if (display.includes('impedance')) {
      group.append('text')
        .attr('x', 0)
        .attr('y', 20)
        .attr('text-anchor', 'middle')
        .attr('fill', termColor)
        .attr('font-size', '10px')
        .text(`${component.properties.impedance || 50}Ω`);
    }
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
      case 'triple_stage':
        console.log('Loading Triple Stage...');
        this.createTripleStage();
        break;
      default:
        console.warn('Unknown preset:', presetName);
    }
    
    console.log('=== loadPreset complete ===');
    console.log('Total components after preset:', this.components.length);
  }
  
  createSingleDriverDoherty() {
    console.log('Creating Single Driver Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Driver
    const driver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Driver',
      technology: 'GaN',
      biasClass: 'A',
      gain: 15,
      pae: 40,
      p1db: 35,
      pout: 35
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 220 + offsetX, 300 + offsetY, {
      label: 'Interstage',
      matchType: 'Pi',
      loss: 0.5
    });
    
    // Splitter
    const splitter = this.addComponent('splitter', 320 + offsetX, 300 + offsetY, {
      label: 'Splitter',
      type: 'Wilkinson'
    });
    
    // Main path matching
    const mainMatch = this.addComponent('matching', 420 + offsetX, 240 + offsetY, {
      label: 'Main Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Aux path matching
    const auxMatch = this.addComponent('matching', 420 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'TL-stub',
      loss: 0.3
    });
    
    // Main PA
    const mainPA = this.addComponent('transistor', 540 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pae: 55,
      p1db: 46,
      pout: 46
    });
    
    // Auxiliary PA
    const auxPA = this.addComponent('transistor', 540 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pae: 50,
      p1db: 43,
      pout: 43
    });
    
    // Main output matching
    const mainOutMatch = this.addComponent('matching', 660 + offsetX, 240 + offsetY, {
      label: 'Main λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Aux output matching
    const auxOutMatch = this.addComponent('matching', 660 + offsetX, 360 + offsetY, {
      label: 'Aux Offset',
      matchType: 'TL-stub',
      loss: 0.2
    });
    
    // Doherty combiner
    const combiner = this.addComponent('combiner', 780 + offsetX, 300 + offsetY, {
      label: 'Doherty',
      type: 'Load-Modulation'
    });
    
    
    // Load termination
    const load = this.addComponent('termination', 880 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Main driver
    const mainDriver = this.addComponent('transistor', 120 + offsetX, 240 + offsetY, {
      label: 'Main Driver',
      technology: 'GaN',
      biasClass: 'A',
      gain: 15,
      pout: 35
    });
    
    // Aux driver  
    const auxDriver = this.addComponent('transistor', 120 + offsetX, 360 + offsetY, {
      label: 'Aux Driver',
      technology: 'GaN',
      biasClass: 'A',
      gain: 15,
      pout: 35
    });
    
    // Main interstage matching
    const mainInterstage = this.addComponent('matching', 240 + offsetX, 240 + offsetY, {
      label: 'Main Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Aux interstage matching
    const auxInterstage = this.addComponent('matching', 240 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'TL-stub',
      loss: 0.3
    });
    
    // Main PA
    const mainPA = this.addComponent('transistor', 360 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pae: 55,
      pout: 46
    });
    
    // Aux PA
    const auxPA = this.addComponent('transistor', 360 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pae: 50,
      pout: 43
    });
    
    // Main output matching
    const mainOutMatch = this.addComponent('matching', 480 + offsetX, 240 + offsetY, {
      label: 'Main λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Aux output matching
    const auxOutMatch = this.addComponent('matching', 480 + offsetX, 360 + offsetY, {
      label: 'Aux Offset',
      matchType: 'TL-stub',
      loss: 0.2
    });
    
    // Combiner
    const combiner = this.addComponent('combiner', 600 + offsetX, 300 + offsetY, {
      label: 'Doherty',
      type: 'Load-Modulation'
    });
    
    // Load termination
    const load = this.addComponent('termination', 700 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Pre-driver stage (first amplifier)
    const predriver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Pre-driver',
      technology: 'GaN',
      biasClass: 'A',
      gain: 12,
      pae: 40,
      pout: 30
    });
    
    // First interstage matching
    const match1 = this.addComponent('matching', 240 + offsetX, 300 + offsetY, {
      label: 'Match 1',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Driver stage (second amplifier)
    const driver = this.addComponent('transistor', 360 + offsetX, 300 + offsetY, {
      label: 'Driver',
      technology: 'GaN',
      biasClass: 'A',
      gain: 15,
      pae: 45,
      pout: 35
    });
    
    // Second interstage matching
    const match2 = this.addComponent('matching', 480 + offsetX, 300 + offsetY, {
      label: 'Match 2',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Final PA stage (third amplifier)
    const finalPA = this.addComponent('transistor', 600 + offsetX, 300 + offsetY, {
      label: 'Final PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pae: 55,
      pout: 46
    });
    
    // Output matching
    const outMatch = this.addComponent('matching', 720 + offsetX, 300 + offsetY, {
      label: 'Output',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Load termination
    const load = this.addComponent('termination', 820 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Driver
    const driver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Driver',
      biasClass: 'A',
      gain: 15,
      pout: 35
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 220 + offsetX, 300 + offsetY, {
      label: 'Interstage',
      matchType: 'L',
      loss: 0.5
    });
    
    // Splitter (90-degree hybrid)
    const splitter = this.addComponent('splitter', 320 + offsetX, 300 + offsetY, {
      label: '90° Splitter',
      type: 'Hybrid'
    });
    
    // Main path matching
    const mainMatch = this.addComponent('matching', 420 + offsetX, 240 + offsetY, {
      label: 'Main Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Aux path matching (with 90° phase shift)
    const auxMatch = this.addComponent('matching', 420 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'TL-stub',
      loss: 0.3
    });
    
    // Main PA (Class AB)
    const mainPA = this.addComponent('transistor', 540 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pout: 46,
      pae: 55
    });
    
    // Auxiliary PA (Class C)
    const auxPA = this.addComponent('transistor', 540 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pout: 43,
      pae: 50
    });
    
    // Main output matching (impedance transformer)
    const mainOutMatch = this.addComponent('matching', 660 + offsetX, 240 + offsetY, {
      label: 'λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Aux output matching
    const auxOutMatch = this.addComponent('matching', 660 + offsetX, 360 + offsetY, {
      label: 'Offset',
      matchType: 'TL-stub',
      loss: 0.2
    });
    
    // Doherty combiner (load modulation node)
    const combiner = this.addComponent('combiner', 780 + offsetX, 300 + offsetY, {
      label: 'Doherty',
      type: 'Load-Modulation'
    });
    
    // Load termination
    const load = this.addComponent('termination', 880 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Driver
    const driver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Driver',
      biasClass: 'A',
      gain: 15,
      pout: 35
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 220 + offsetX, 300 + offsetY, {
      label: 'Interstage',
      matchType: 'Pi',
      loss: 0.5
    });
    
    // Splitter
    const splitter = this.addComponent('splitter', 320 + offsetX, 300 + offsetY, {
      label: 'Splitter',
      type: 'Wilkinson'
    });
    
    // Main path (inverted - gets 90° delay)
    const mainMatch = this.addComponent('matching', 420 + offsetX, 240 + offsetY, {
      label: 'Main λ/4',
      matchType: 'TL-stub',
      loss: 0.3
    });
    
    // Aux path (no additional phase shift)
    const auxMatch = this.addComponent('matching', 420 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Main PA
    const mainPA = this.addComponent('transistor', 540 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pout: 46
    });
    
    // Auxiliary PA
    const auxPA = this.addComponent('transistor', 540 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pout: 43
    });
    
    // Output matching
    const mainOutMatch = this.addComponent('matching', 660 + offsetX, 240 + offsetY, {
      label: 'Out Match',
      matchType: 'L',
      loss: 0.2
    });
    
    const auxOutMatch = this.addComponent('matching', 660 + offsetX, 360 + offsetY, {
      label: 'λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Inverted Doherty combiner
    const combiner = this.addComponent('combiner', 780 + offsetX, 300 + offsetY, {
      label: 'Inverted',
      type: 'Inverted-Doherty'
    });
    
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
    
    console.log('Inverted Doherty created with connections');
  }
  
  createSymmetricDoherty() {
    console.log('Creating Symmetric Doherty preset...');
    
    // Set flag to skip lock check during template loading
    this._loadingTemplate = true;
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Driver
    const driver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Driver',
      biasClass: 'A',
      gain: 15,
      pout: 36
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 220 + offsetX, 300 + offsetY, {
      label: 'Interstage',
      matchType: 'T',
      loss: 0.5
    });
    
    // Splitter
    const splitter = this.addComponent('splitter', 320 + offsetX, 300 + offsetY, {
      label: 'Splitter',
      type: 'Wilkinson'
    });
    
    // Main and Aux paths (equal power rating - symmetric)
    const mainMatch = this.addComponent('matching', 420 + offsetX, 240 + offsetY, {
      label: 'Main Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    const auxMatch = this.addComponent('matching', 420 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Main PA (equal power)
    const mainPA = this.addComponent('transistor', 540 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pout: 46,
      pae: 55
    });
    
    // Auxiliary PA (equal power - symmetric)
    const auxPA = this.addComponent('transistor', 540 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pout: 46,
      pae: 55
    });
    
    // Output matching (symmetric)
    const mainOutMatch = this.addComponent('matching', 660 + offsetX, 240 + offsetY, {
      label: 'λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    const auxOutMatch = this.addComponent('matching', 660 + offsetX, 360 + offsetY, {
      label: 'λ/4',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Symmetric combiner
    const combiner = this.addComponent('combiner', 780 + offsetX, 300 + offsetY, {
      label: 'Symmetric',
      type: 'Symmetric-Doherty'
    });
    
    // Load termination
    const load = this.addComponent('termination', 880 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
    
    // Center template around origin
    const offsetX = this.originX - 450;
    const offsetY = this.originY - 300;
    
    // Source termination
    const source = this.addComponent('termination', 20 + offsetX, 300 + offsetY, {
      label: 'Source',
      impedance: 50
    });
    
    // Driver
    const driver = this.addComponent('transistor', 120 + offsetX, 300 + offsetY, {
      label: 'Driver',
      biasClass: 'A',
      gain: 15,
      pout: 36
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 220 + offsetX, 300 + offsetY, {
      label: 'Interstage',
      matchType: 'L',
      loss: 0.5
    });
    
    // Unequal power splitter
    const splitter = this.addComponent('splitter', 320 + offsetX, 300 + offsetY, {
      label: '2:1 Splitter',
      type: 'Asymmetric'
    });
    
    // Main path (higher power)
    const mainMatch = this.addComponent('matching', 420 + offsetX, 240 + offsetY, {
      label: 'Main Match',
      matchType: 'Pi',
      loss: 0.3
    });
    
    // Aux path (lower power)
    const auxMatch = this.addComponent('matching', 420 + offsetX, 360 + offsetY, {
      label: 'Aux Match',
      matchType: 'L',
      loss: 0.3
    });
    
    // Main PA (higher power - 2x Aux)
    const mainPA = this.addComponent('transistor', 540 + offsetX, 240 + offsetY, {
      label: 'Main PA',
      technology: 'GaN',
      biasClass: 'AB',
      gain: 12,
      pout: 49,
      pae: 55
    });
    
    // Auxiliary PA (lower power)
    const auxPA = this.addComponent('transistor', 540 + offsetX, 360 + offsetY, {
      label: 'Aux PA',
      technology: 'GaN',
      biasClass: 'C',
      gain: 12,
      pout: 43,
      pae: 50
    });
    
    // Output matching (asymmetric impedance transformation)
    const mainOutMatch = this.addComponent('matching', 660 + offsetX, 240 + offsetY, {
      label: 'λ/4 (25Ω)',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    const auxOutMatch = this.addComponent('matching', 660 + offsetX, 360 + offsetY, {
      label: 'λ/4 (50Ω)',
      matchType: 'Transformer',
      loss: 0.2
    });
    
    // Asymmetric combiner
    const combiner = this.addComponent('combiner', 780 + offsetX, 300 + offsetY, {
      label: 'Asymmetric 2:1',
      type: 'Asymmetric-Doherty'
    });
    
    // Load termination
    const load = this.addComponent('termination', 880 + offsetX, 300 + offsetY, {
      label: 'Load',
      impedance: 50
    });
    
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
      window.paCanvasClipboard = clipboardData; // Global clipboard for cross-canvas paste
      console.log('Copied components:', this.selectedComponents.length, '(cross-canvas enabled)');
      
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
      window.paCanvasClipboard = clipboardData; // Global clipboard for cross-canvas paste
      console.log('Copied component:', comp.properties.label, '(cross-canvas enabled)');
      
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
      window.paCanvasClipboard = clipboardData; // Global clipboard for cross-canvas paste
      console.log('Cut components:', this.selectedComponents.length, '(cross-canvas enabled)');
      
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
      window.paCanvasClipboard = clipboardData; // Global clipboard for cross-canvas paste
      console.log('Cut component:', comp.properties.label, '(cross-canvas enabled)');
      
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
    // Use global clipboard first (for cross-canvas paste), fallback to instance clipboard
    const clipboardSource = window.paCanvasClipboard || this.clipboard;
    
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
    
    // Determine if this is a cross-canvas paste
    const isCrossCanvas = window.paCanvases && window.paCanvases.length > 1;
    const sourceInfo = isCrossCanvas ? ' (from another canvas)' : '';
    
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
      { label: 'Backoff Power:', formula: 'P_backoff = P_1dB - BO(dB)' },
      { label: '', formula: 'BO(dB) = 10·log₁₀(P_1dB / P_backoff)' },
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
    
    // Clear existing impedance display
    this.impedanceLayer.selectAll('*').remove();
    
    if (this.components.length === 0) return;
    
    // Get global backoff value (default 6 dB)
    const backoffDb = window.getGlobalBackoff ? window.getGlobalBackoff() : 6;
    
    // Include all components that have impedance information
    const componentsWithImpedance = this.components.filter(c => 
      c.type === 'transistor' ||  c.type === 'matching' || 
      c.type === 'splitter' || c.type === 'combiner' || c.type === 'termination'
    );
    
    if (componentsWithImpedance.length === 0) return;
    
    componentsWithImpedance.forEach((comp, index) => {
      const x = comp.x;
      const y = comp.y;
      
      let zFullPower, zBackoff, p1dbValue, backoffPower;
      
      // Calculate impedances based on component type
      if (comp.type === 'transistor') {
        // Active device - impedance varies with power
        p1dbValue = comp.properties.p1db || comp.properties.pout || 40;
        backoffPower = p1dbValue - backoffDb;
        zFullPower = this.calculateOptimalImpedance(comp, p1dbValue);
        zBackoff = this.calculateOptimalImpedance(comp, backoffPower);
      } else {
        // Passive device - fixed impedance values
        // Show z_in and z_out (or just impedance for terminati ons)
        if (comp.type === 'termination') {
          zFullPower = comp.properties.impedance || 50;
          zBackoff = zFullPower; // Same at all power levels
        } else {
          // For matching, splitters, combiners: show input/output impedance
          zFullPower = comp.properties.z_in || comp.properties.impedance || 50;
          zBackoff = comp.properties.z_out || zFullPower; // Output impedance at backoff
        }
        p1dbValue = null; // Passives don't have power rating to show
        backoffPower = null;
      }
      
      // Create info box below component (now draggable)
      const infoGroup = this.impedanceLayer.append('g')
        .attr('transform', `translate(${x - 65}, ${y + 55})`)
        .attr('class', 'impedance-info')
        .style('cursor', 'move');
      
      // Add drag behavior to impedance display
      const impedanceDrag = d3.drag()
        .on('start', function(event) {
          d3.select(this).raise().style('opacity', 0.7);
        })
        .on('drag', function(event) {
          const currentTransform = d3.select(this).attr('transform');
          const match = currentTransform.match(/translate\\(([^,]+),([^)]+)\\)/);
          if (match) {
            const newX = parseFloat(match[1]) + event.dx;
            const newY = parseFloat(match[2]) + event.dy;
            d3.select(this).attr('transform', `translate(${newX}, ${newY})`);
          }
        })
        .on('end', function(event) {
          d3.select(this).style('opacity', 1);
        });
      
      infoGroup.call(impedanceDrag);
      
      // Background box
      infoGroup.append('rect')
        .attr('width', 130)
        .attr('height', 75)
        .attr('fill', '#2c3e50')
        .attr('stroke', '#ff7f11')
        .attr('stroke-width', 2)
        .attr('rx', 5);
      
      // Title (adjust for component type)
      const titleText = comp.type === 'transistor' ? 'Z_opt' : 
                       comp.type === 'termination' ? 'Z_load' : 'Z_match';
      infoGroup.append('text')
        .attr('x', 65)
        .attr('y', 18)
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '12px')
        .attr('font-weight', 'bold')
        .text(titleText);
      
      // First impedance line (Full power for transistor, Z_in for passive)
      const firstLabel = comp.type === 'transistor' ? 'Full' : 
                        comp.type === 'termination' ? 'Z' : 'Z_in';
      infoGroup.append('text')
        .attr('x', 65)
        .attr('y', 38)
        .attr('text-anchor', 'middle')
        .attr('fill', '#00ff88')
        .attr('font-size', '12px')
        .text(`${firstLabel}: ${zFullPower.toFixed(1)}Ω`);
      
      // Second impedance line (Backoff for transistor, Z_out for passive)
      const secondLabel = comp.type === 'transistor' ? 'BO' : 
                         comp.type === 'termination' ? '--' : 'Z_out';
      const secondValue = comp.type === 'termination' ? '--' : `${zBackoff.toFixed(1)}Ω`;
      infoGroup.append('text')
        .attr('x', 65)
        .attr('y', 55)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ffaa00')
        .attr('font-size', '12px')
        .text(`${secondLabel}: ${secondValue}`);
      
      // Power levels for reference (only for transistors)
      if (comp.type === 'transistor' && p1dbValue && backoffPower) {
        infoGroup.append('text')
          .attr('x', 65)
          .attr('y', 70)
          .attr('text-anchor', 'middle')
          .attr('fill', '#aaa')
          .attr('font-size', '10px')
          .text(`(${p1dbValue.toFixed(1)} / ${backoffPower.toFixed(1)} dBm)`);
      } else {
        // For passives, show component type
        infoGroup.append('text')
          .attr('x', 65)
          .attr('y', 70)
          .attr('text-anchor', 'middle')
          .attr('fill', '#aaa')
          .attr('font-size', '10px')
          .text(`(${comp.properties.label || comp.type})`);
      }
    });
  }
  
  drawPowerColumns() {
    if (!this.showPowerDisplay) return;
    
    // Clear existing power display
    this.powerLayer.selectAll('*').remove();
    
    if (this.components.length === 0) return;
    
    // Sort components by x position (signal flow left to right)
    const sortedComponents = [...this.components].sort((a, b) => a.x - b.x);
    
    // Calculate 20% padding from boundaries
    const paddingTop = this.height * 0.2;
    const paddingBottom = this.height * 0.8;
    const centerY = this.height / 2;
    
    // Calculate power at each stage
    let currentPower = 0; // Will be set from first component
    
    sortedComponents.forEach((comp, index) => {
      const x = comp.x;
      const columnWidth = 150;
      
      // Draw vertical divider line (transparent and dashed for better clarity)
      this.powerLayer.append('line')
        .attr('x1', x - columnWidth/2)
        .attr('y1', 0)
        .attr('x2', x - columnWidth/2)
        .attr('y2', this.height)
        .attr('stroke', '#00aaff')
        .attr('stroke-width', 2)
        .attr('stroke-dasharray', '8,4')
        .attr('opacity', 0.15);
      
      // Calculate input and output power for this component
      const powerInfo = this.calculateComponentPower(comp, currentPower, index === 0);
      
      // Determine if component is above or below center line
      const isAboveCenterLine = comp.y < centerY;
      
      // Calculate position at midpoint between center line and canvas edge
      const canvasEdge = isAboveCenterLine ? 0 : this.height;
      const infoY = isAboveCenterLine 
        ? centerY / 2 - 50 // Midpoint above center (50 is half box height)
        : centerY + (this.height - centerY) / 2 - 50; // Midpoint below center
      
      // Check if component has custom power box position
      if (!comp.powerBoxOffset) {
        comp.powerBoxOffset = { x: 0, y: 0 };
      }
      
      // Draw power information box with drag behavior
      const infoGroup = this.powerLayer.append('g')
        .attr('class', 'power-info-group')
        .attr('data-component-id', comp.id)
        .attr('transform', `translate(${x - columnWidth/2 + 10 + comp.powerBoxOffset.x}, ${infoY + comp.powerBoxOffset.y})`)
        .style('cursor', 'move');
      
      // Add drag behavior to power info box
      const powerBoxDrag = d3.drag()
        .on('start', (event) => {
          event.sourceEvent.stopPropagation();
          infoGroup.raise(); // Bring to front
        })
        .on('drag', (event) => {
          comp.powerBoxOffset.x += event.dx;
          comp.powerBoxOffset.y += event.dy;
          infoGroup.attr('transform', `translate(${x - columnWidth/2 + 10 + comp.powerBoxOffset.x}, ${infoY + comp.powerBoxOffset.y})`);
        })
        .on('end', () => {
          this.saveHistory();
        });
      
      infoGroup.call(powerBoxDrag);
      
      // Background box (height depends on content)
      const boxHeight = powerInfo.power_bo_dbm ? 100 : 85;
      infoGroup.append('rect')
        .attr('x', 0)
        .attr('y', 0)
        .attr('width', 130)
        .attr('height', boxHeight)
        .attr('fill', '#1a1a1a')
        .attr('stroke', '#00aaff')
        .attr('stroke-width', 1)
        .attr('rx', 3);
      
      // Component label
      infoGroup.append('text')
        .attr('x', 65)
        .attr('y', 15)
        .attr('text-anchor', 'middle')
        .attr('fill', '#fff')
        .attr('font-size', '11px')
        .attr('font-weight', 'bold')
        .text(comp.properties.label || comp.type);
      
      let yOffset = 32;
      
      // Input power
      const pinText = this.formatPower(powerInfo.pin_dbm, this.powerUnit);
      infoGroup.append('text')
        .attr('x', 5)
        .attr('y', yOffset)
        .attr('fill', '#00ff88')
        .attr('font-size', '10px')
        .text(`Pin: ${pinText}`);
      yOffset += 15;
      
      // Output power
      const poutText = this.formatPower(powerInfo.pout_dbm, this.powerUnit);
      infoGroup.append('text')
        .attr('x', 5)
        .attr('y', yOffset)
        .attr('fill', '#ff7f11')
        .attr('font-size', '10px')
        .text(`Pout: ${poutText}`);
      yOffset += 15;
      
      // P1dB (if available)
      if (powerInfo.p1db_dbm) {
        const p1dbText = this.formatPower(powerInfo.p1db_dbm, this.powerUnit);
        infoGroup.append('text')
          .attr('x', 5)
          .attr('y', yOffset)
          .attr('fill', '#ffaa00')
          .attr('font-size', '10px')
          .text(`P1dB: ${p1dbText}`);
        yOffset += 15;
      }
      
      // Power at back-off (if applicable)
      if (powerInfo.power_bo_dbm) {
        const pboText = this.formatPower(powerInfo.power_bo_dbm, this.powerUnit);
        infoGroup.append('text')
          .attr('x', 5)
          .attr('y', yOffset)
          .attr('fill', '#ffaa00')
          .attr('font-size', '10px')
          .text(`P_BO: ${pboText}`);
        yOffset += 15;
      }
      
      // Forward arrow (signal flow direction) - now grouped with info box
      if (index < sortedComponents.length - 1) {
        const nextX = sortedComponents[index + 1].x;
        const arrowMidX = x + (nextX - x) / 2;
        const arrowY_abs = isAboveCenterLine ? paddingTop + 40 : paddingBottom - 60;
        
        // Calculate relative position from info box anchor
        const boxAnchorX = x - columnWidth/2 + 10 + comp.powerBoxOffset.x;
        const boxAnchorY = infoY + comp.powerBoxOffset.y;
        const arrowX_rel = arrowMidX - boxAnchorX;
        const arrowY_rel = arrowY_abs - boxAnchorY;
        
        // Append arrow to info group so it moves with the box
        infoGroup.append('path')
          .attr('d', `M ${arrowX_rel - 20},${arrowY_rel} L ${arrowX_rel + 10},${arrowY_rel} L ${arrowX_rel + 5},${arrowY_rel - 5} M ${arrowX_rel + 10},${arrowY_rel} L ${arrowX_rel + 5},${arrowY_rel + 5}`)
          .attr('stroke', '#00aaff')
          .attr('stroke-width', 2)
          .attr('fill', 'none')
          .attr('class', 'signal-flow-arrow');
      }
      
      // Update current power for next stage
      currentPower = powerInfo.pout_dbm;
    });
    
    console.log('Power columns drawn for', sortedComponents.length, 'components');
  }
  
  formatPower(power_dbm, unit) {
    // Convert dBm to Watts
    const power_w = Math.pow(10, power_dbm / 10) / 1000;
    
    switch (unit) {
      case 'dBm':
        return `${power_dbm.toFixed(1)} dBm`;
      case 'W':
        return `${power_w.toFixed(3)} W`;
      case 'both':
        return `${power_dbm.toFixed(1)} dBm (${power_w.toFixed(3)} W)`;
      default:
        return `${power_dbm.toFixed(1)} dBm`;
    }
  }
  
  calculateComponentPower(component, previousPout, isFirst) {
    const props = component.properties;
    let pin_dbm, pout_dbm, p1db_dbm, backoff_db, power_bo_dbm;
    
    // Get input power
    if (isFirst) {
      // First component: use specified input power or default
      pin_dbm = props.pin || 0;
    } else {
      // Subsequent components: input is previous output
      pin_dbm = previousPout;
    }
    
    // Calculate output power based on component type
    switch (component.type) {
      case 'transistor':
        const gain = props.gain || 10;
        pout_dbm = pin_dbm + gain;
        p1db_dbm = props.pout || 40; // P1dB from properties
        
        // Get back-off value from properties or calculate from PAPR
        if (props.backoff_db !== undefined) {
          backoff_db = props.backoff_db;
        } else if (props.papr_db !== undefined) {
          backoff_db = props.papr_db; // PAPR = back-off for this calculation
        } else {
          backoff_db = p1db_dbm - pout_dbm; // Default: back-off from P1dB
        }
        
        // Calculate power at back-off
        power_bo_dbm = p1db_dbm - backoff_db;
        break;
        
      case 'matching':
        const loss = props.loss || 0.5;
        pout_dbm = pin_dbm - loss;
        break;
        
      case 'splitter':
        const split_loss = props.loss || 3;
        pout_dbm = pin_dbm - split_loss;
        break;
        
      case 'combiner':
        const combine_loss = props.loss || 0.5;
        // Combiner adds power (assuming N-way combiner)
        const ways = props.ways || 2;
        pout_dbm = pin_dbm + 10 * Math.log10(ways) - combine_loss;
        break;
        
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
    { type: 'transistor', icon: '▲', label: 'Transistor', color: '#00bfff' },
    { type: 'matching', icon: '═', label: 'Matching', color: '#00ff88' },
    { type: 'splitter', icon: '⊥', label: 'Splitter', color: '#ffaa00' },
    { type: 'combiner', icon: '⊤', label: 'Combiner', color: '#ff00aa' },
    { type: 'termination', icon: '⏚', label: 'Termination', color: '#888888' },
    { type: 'wire', icon: '━', label: 'Wire Mode', color: '#ff7f11', isAction: true }
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
    
    item.append('div')
      .style('font-size', '24px')
      .style('color', comp.color)
      .text(comp.icon);
    
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
      left: 5px;
      background: rgba(52, 73, 94, 0.8);
      color: white;
      padding: 4px 10px;
      border-radius: 4px;
      font-size: 11px;
      font-weight: bold;
      z-index: 50;
      pointer-events: none;
    `;
    canvasDiv.appendChild(label);
    
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
  
  // Create shared palette for multi-canvas mode
  createSharedPalette();
  
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
    wires: window.paCanvas.wires.map(wire => ({
      fromId: wire.fromId,
      toId: wire.toId,
      fromPort: wire.fromPort,
      toPort: wire.toPort
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

console.log('✓ Save template functions loaded');