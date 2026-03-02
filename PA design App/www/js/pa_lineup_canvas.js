// ============================================================
// PA Lineup Interactive Canvas
// D3.js-based drag-and-drop lineup builder
// ============================================================

class PALineupCanvas {
  constructor(containerId, config = {}) {
    this.containerId = containerId;
    this.width = config.width || 1200;
    this.height = config.height || 600;
    this.components = [];
    this.connections = [];
    this.selectedComponent = null;
    this.draggedComponent = null;
    this.nextId = 1;
    
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
    
    // Arrow marker for connections
    defs.append('marker')
      .attr('id', 'arrowhead')
      .attr('markerWidth', 10)
      .attr('markerHeight', 10)
      .attr('refX', 8)
      .attr('refY', 3)
      .attr('orient', 'auto')
      .append('polygon')
      .attr('points', '0 0, 10 3, 0 6')
      .attr('fill', '#ff7f11');
    
    // Create groups for layers
    this.connectionsLayer = this.svg.append('g').attr('class', 'connections-layer');
    this.componentsLayer = this.svg.append('g').attr('class', 'components-layer');
    this.gridLayer = this.svg.insert('g', ':first-child').attr('class', 'grid-layer');
    
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
  
  createPalette() {
    console.log('Creating component palette...');
    
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
      .style('z-index', '100')
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
      { type: 'combiner', icon: '⊤', label: 'Combiner', color: '#ff00aa' }
    ];
    
    console.log('Adding components to palette:', components.length);
    
    components.forEach(comp => {
      const item = palette.append('div')
        .attr('class', 'palette-item')
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
        .on('click', () => this.addComponentFromPalette(comp.type));
      
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
    const x = this.width / 2;
    const y = this.height / 2;
    this.addComponent(type, x, y);
  }
  
  addComponent(type, x, y, properties = {}) {
    const component = {
      id: this.nextId++,
      type: type,
      x: x,
      y: y,
      properties: this.getDefaultProperties(type, properties)
    };
    
    this.components.push(component);
    this.renderComponent(component);
    
    // Hide instruction text when first component is added
    if (this.instructionText && this.components.length > 0) {
      this.instructionText.style('display', 'none');
    }
    
    // Notify Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', this.components, {priority: 'event'});
    }
    
    console.log('Component added:', component);
    
    return component;
  }
  
  getDefaultProperties(type, overrides = {}) {
    const defaults = {
      transistor: {
        name: 'PA',
        technology: 'GaN',
        class: 'AB',
        gain_db: 12,
        pae: 50,
        p1db_dbm: 40,
        pout_dbm: 40,
        vdd: 28,
        idq_ma: 100,
        rth_cw: 5
      },
      matching: {
        name: 'Match',
        loss_db: 0.5,
        phase_deg: 0,
        vswr: 1.2,
        type: 'L-section'
      },
      splitter: {
        name: 'Split',
        topology: 'Wilkinson',
        n_way: 2,
        loss_db: 0.3,
        isolation_db: 20,
        phase_balance_deg: 1,
        amplitude_balance_db: 0.2
      },
      combiner: {
        name: 'Combine',
        topology: 'Wilkinson',
        n_way: 2,
        loss_db: 0.3,
        efficiency: 95,
        isolation_db: 20
      }
    };
    
    return { ...defaults[type], ...overrides };
  }
  
  renderComponent(component) {
    const group = this.componentsLayer.append('g')
      .attr('class', `component component-${component.type}`)
      .attr('data-id', component.id)
      .attr('transform', `translate(${component.x}, ${component.y})`);
    
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
    }
    
    // Add drag behavior
    group.call(d3.drag()
      .on('start', (event) => this.onDragStart(event, component))
      .on('drag', (event) => this.onDrag(event, component))
      .on('end', (event) => this.onDragEnd(event, component))
    );
    
    // Add click behavior
    group.on('click', (event) => {
      event.stopPropagation();
      this.selectComponent(component);
    });
  }
  
  renderTransistor(group, component) {
    // Triangle symbol
    group.append('polygon')
      .attr('points', '0,-20 30,0 0,20')
      .attr('fill', '#00aaff')
      .attr('stroke', '#fff')
      .attr('stroke-width', 2);
    
    // Label
    group.append('text')
      .attr('x', 15)
      .attr('y', 35)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '10px')
      .text(component.properties.name);
    
    // Technology badge
    group.append('text')
      .attr('x', 15)
      .attr('y', -30)
      .attr('text-anchor', 'middle')
      .attr('fill', '#ff7f11')
      .attr('font-size', '9px')
      .attr('font-weight', 'bold')
      .text(component.properties.technology);
  }
  
  renderMatching(group, component) {
    // Transmission line
    group.append('line')
      .attr('x1', -20)
      .attr('y1', 0)
      .attr('x2', 20)
      .attr('y2', 0)
      .attr('stroke', '#00ff88')
      .attr('stroke-width', 4);
    
    // Double line for emphasis
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
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 20)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(`${component.properties.loss_db}dB`);
  }
  
  renderSplitter(group, component) {
    // Inverted T shape
    group.append('line')
      .attr('x1', -20)
      .attr('y1', 0)
      .attr('x2', 0)
      .attr('y2', 0)
      .attr('stroke', '#ffaa00')
      .attr('stroke-width', 3);
    
    group.append('line')
      .attr('x1', 0)
      .attr('y1', 0)
      .attr('x2', 20)
      .attr('y2', -15)
      .attr('stroke', '#ffaa00')
      .attr('stroke-width', 3);
    
    group.append('line')
      .attr('x1', 0)
      .attr('y1', 0)
      .attr('x2', 20)
      .attr('y2', 15)
      .attr('stroke', '#ffaa00')
      .attr('stroke-width', 3);
    
    // Circle at junction
    group.append('circle')
      .attr('cx', 0)
      .attr('cy', 0)
      .attr('r', 5)
      .attr('fill', '#ffaa00');
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 30)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(`${component.properties.n_way}-way`);
  }
  
  renderCombiner(group, component) {
    // T shape (reversed splitter)
    group.append('line')
      .attr('x1', -20)
      .attr('y1', -15)
      .attr('x2', 0)
      .attr('y2', 0)
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 3);
    
    group.append('line')
      .attr('x1', -20)
      .attr('y1', 15)
      .attr('x2', 0)
      .attr('y2', 0)
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 3);
    
    group.append('line')
      .attr('x1', 0)
      .attr('y1', 0)
      .attr('x2', 20)
      .attr('y2', 0)
      .attr('stroke', '#ff00aa')
      .attr('stroke-width', 3);
    
    // Circle at junction
    group.append('circle')
      .attr('cx', 0)
      .attr('cy', 0)
      .attr('r', 5)
      .attr('fill', '#ff00aa');
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 30)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(`${component.properties.n_way}-way`);
  }
  
  onDragStart(event, component) {
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
    
    // Notify Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', this.components, {priority: 'event'});
    }
  }
  
  selectComponent(component) {
    // Deselect previous
    d3.selectAll('.component').classed('selected', false);
    
    // Select new
    this.selectedComponent = component;
    d3.select(`.component[data-id="${component.id}"]`)
      .classed('selected', true);
    
    // Notify Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_selected_component', component, {priority: 'event'});
    }
  }
  
  updateConnections() {
    // Auto-connect nearby components (simplified for now)
    // Full implementation would detect input/output ports
  }
  
  loadPreset(presetName) {
    this.clear();
    
    switch(presetName) {
      case 'single_doherty':
        this.createSingleDriverDoherty();
        break;
      case 'dual_doherty':
        this.createDualDriverDoherty();
        break;
      case 'triple_stage':
        this.createTripleStage();
        break;
    }
  }
  
  createSingleDriverDoherty() {
    // Driver
    const driver = this.addComponent('transistor', 150, 300, {
      name: 'Driver',
      gain_db: 15,
      pae: 40,
      p1db_dbm: 35
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 250, 300, {
      name: 'Interstage',
      loss_db: 0.5
    });
    
    // Splitter
    const splitter = this.addComponent('splitter', 350, 300, {
      topology: 'Wilkinson',
      n_way: 2
    });
    
    // Main PA
    const mainPA = this.addComponent('transistor', 500, 250, {
      name: 'Main PA',
      gain_db: 12,
      pae: 55,
      p1db_dbm: 46,
      class: 'AB'
    });
    
    // Auxiliary PA (with λ/4 offset)
    const auxPA = this.addComponent('transistor', 500, 350, {
      name: 'Aux PA',
      gain_db: 12,
      pae: 50,
      p1db_dbm: 43,
      class: 'C'
    });
    
    // Doherty combiner
    const combiner = this.addComponent('combiner', 650, 300, {
      name: 'Doherty',
      topology: 'Doherty',
      n_way: 2
    });
  }
  
  createDualDriverDoherty() {
    // Dual drivers implementation
    // Similar to single but with two driver paths
  }
  
  createTripleStage() {
    // Simple 3-stage cascade
    this.addComponent('transistor', 150, 300, {name: 'Pre-driver'});
    this.addComponent('matching', 250, 300);
    this.addComponent('transistor', 350, 300, {name: 'Driver'});
    this.addComponent('matching', 450, 300);
    this.addComponent('transistor', 550, 300, {name: 'Final PA'});
  }
  
  clear() {
    this.components = [];
    this.connections = [];
    this.selectedComponent = null;
    this.componentsLayer.selectAll('*').remove();
    this.connectionsLayer.selectAll('*').remove();
    
    // Show instruction text again
    if (this.instructionText) {
      this.instructionText.style('display', 'block');
    }
    
    console.log('Canvas cleared');
  }
  
  setupEventHandlers() {
    // Click on canvas to deselect
    this.svg.on('click', () => {
      this.selectedComponent = null;
      d3.selectAll('.component').classed('selected', false);
      
      if (window.Shiny) {
        Shiny.setInputValue('lineup_selected_component', null, {priority: 'event'});
      }
    });
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
}

// Initialize canvas with error handling and multiple triggers
function initializePACanvas() {
  console.log('Attempting to initialize PA Lineup Canvas...');
  
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
  
  // Initialize canvas
  try {
    window.paCanvas = new PALineupCanvas('pa_lineup_canvas_container');
    console.log('PA Lineup Canvas initialized successfully!');
    console.log('Canvas object:', window.paCanvas);
    return true;
  } catch (error) {
    console.error('Error initializing PA Lineup Canvas:', error);
    return false;
  }
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
    
    templates.forEach(template => {
      template.addEventListener('click', function() {
        const preset = this.getAttribute('data-preset');
        console.log('Preset clicked:', preset);
        
        if (!window.paCanvas) {
          console.error('Canvas not initialized! Attempting to initialize...');
          const initialized = initializePACanvas();
          if (!initialized) {
            alert('Canvas not ready. Please try again in a moment.');
            return;
          }
          // Wait a bit for initialization to complete
          setTimeout(() => {
            if (window.paCanvas) {
              if (preset === 'blank') {
                window.paCanvas.clear();
              } else {
                window.paCanvas.loadPreset(preset);
              }
            }
          }, 500);
        } else {
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
  }, 1000);
});
