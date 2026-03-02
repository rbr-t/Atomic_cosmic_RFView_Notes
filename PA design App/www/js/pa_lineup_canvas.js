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
    this.wireMode = false;
    this.wireStart = null;
    
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
    this.gridLayer = this.svg.append('g').attr('class', 'grid-layer');
    this.connectionsLayer = this.svg.append('g').attr('class', 'connections-layer');
    this.componentsLayer = this.svg.append('g').attr('class', 'components-layer');
    
    // Create zoom group that contains all drawable layers
    this.zoomGroup = this.svg.insert('g', ':first-child').attr('class', 'zoom-group');
    this.zoomGroup.node().appendChild(this.gridLayer.node());
    this.zoomGroup.node().appendChild(this.connectionsLayer.node());
    this.zoomGroup.node().appendChild(this.componentsLayer.node());
    
    // Add zoom behavior
    this.zoom = d3.zoom()
      .scaleExtent([0.1, 4])
      .on('zoom', (event) => {
        this.zoomGroup.attr('transform', event.transform);
      });
    
    this.svg.call(this.zoom);
    
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
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
    }
    
    console.log('Component added:', component);
    
    return component;
  }
  
  getDefaultProperties(type, overrides = {}) {
    const defaults = {
      transistor: {
        label: 'PA',
        technology: 'GaN',
        pout: 43,
        p1db: 43,
        gain: 15,
        pae: 50,
        vdd: 28,
        rth: 2.5,
        freq: 2.6
      },
      matching: {
        label: 'Match',
        type: 'L-section',
        loss: 0.5,
        z_in: 50,
        z_out: 50,
        bandwidth: 10
      },
      splitter: {
        label: 'Splitter',
        type: 'Wilkinson',
        loss: 0.3,
        isolation: 20,
        split_ratio: 0
      },
      combiner: {
        label: 'Combiner',
        type: 'Wilkinson',
        loss: 0.3,
        isolation: 20,
        load_modulation: false,
        modulation_factor: 2.0
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
    
    // Input port (left)
    const inputPort = group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -5)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#44ff44')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'));
    
    // Output port (right)
    const outputPort = group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 35)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#ff4444')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'));
    
    // Label
    group.append('text')
      .attr('x', 15)
      .attr('y', 35)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '10px')
      .text(component.properties.label || 'PA');
    
    // Display options
    const display = component.properties.display || ['technology', 'pout'];
    let yOffset = 45;
    
    if (display.includes('technology')) {
      group.append('text')
        .attr('x', 15)
        .attr('y', -30)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff7f11')
        .attr('font-size', '9px')
        .attr('font-weight', 'bold')
        .text(component.properties.technology || 'GaN');
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
      group.append('text')
        .attr('x', 15)
        .attr('y', yOffset)
        .attr('text-anchor', 'middle')
        .attr('fill', '#ff88ff')
        .attr('font-size', '8px')
        .text(`Pout: ${component.properties.pout || 40} dBm`);
      yOffset += 10;
    }
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
    
    // Input port
    group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -20)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#44ff44')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'));
    
    // Output port
    group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 20)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#ff4444')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'));
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 20)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(`${component.properties.loss || 0.5}dB`);
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
    
    // Input port
    group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -20)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#44ff44')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'));
    
    // Output ports
    group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 20)
      .attr('cy', -15)
      .attr('r', 4)
      .attr('fill', '#ff4444')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'));
    
    group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 20)
      .attr('cy', 15)
      .attr('r', 4)
      .attr('fill', '#ff4444')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'));
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 30)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(component.properties.label || 'Split');
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
    
    // Input ports
    group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -20)
      .attr('cy', -15)
      .attr('r', 4)
      .attr('fill', '#44ff44')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'));
    
    group.append('circle')
      .attr('class', 'port port-input')
      .attr('cx', -20)
      .attr('cy', 15)
      .attr('r', 4)
      .attr('fill', '#44ff44')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'input'));
    
    // Output port
    group.append('circle')
      .attr('class', 'port port-output')
      .attr('cx', 20)
      .attr('cy', 0)
      .attr('r', 4)
      .attr('fill', '#ff4444')
      .attr('stroke', '#fff')
      .attr('stroke-width', 1)
      .style('cursor', 'pointer')
      .on('click', (event) => this.handlePortClick(event, component, 'output'));
    
    // Label
    group.append('text')
      .attr('x', 0)
      .attr('y', 30)
      .attr('text-anchor', 'middle')
      .attr('fill', '#fff')
      .attr('font-size', '9px')
      .text(component.properties.label || 'Combine');
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
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
    }
  }
  
  selectComponent(component) {
    // Deselect previous
    d3.selectAll('.component').classed('selected', false);
    
    // Select new
    this.selectedComponent = component;
    d3.select(`.component[data-id="${component.id}"]`)
      .classed('selected', true);
    
    // Notify Shiny - send only the component ID, not the full object
    if (window.Shiny) {
      Shiny.setInputValue('lineup_selected_component', component.id, {priority: 'event'});
    }
    
    console.log('Component selected, ID sent:', component.id);
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
    console.log('Creating Single Driver Doherty preset...');
    
    // Driver
    const driver = this.addComponent('transistor', 150, 300, {
      label: 'Driver',
      gain: 15,
      pae: 40,
      p1db: 35,
      pout: 35
    });
    
    // Interstage matching
    const match = this.addComponent('matching', 250, 300, {
      label: 'Interstage',
      loss: 0.5
    });
    
    // Splitter
    const splitter = this.addComponent('splitter', 350, 300, {
      label: 'Splitter',
      type: 'Wilkinson'
    });
    
    // Main PA
    const mainPA = this.addComponent('transistor', 500, 250, {
      label: 'Main PA',
      gain: 12,
      pae: 55,
      p1db: 46,
      pout: 46
    });
    
    // Auxiliary PA
    const auxPA = this.addComponent('transistor', 500, 350, {
      label: 'Aux PA',
      gain: 12,
      pae: 50,
      p1db: 43,
      pout: 43
    });
    
    // Doherty combiner
    const combiner = this.addComponent('combiner', 650, 300, {
      label: 'Doherty',
      type: 'Doherty',
      load_modulation: true
    });
    
    console.log('Single Driver Doherty created');
  }
  
  createDualDriverDoherty() {
    console.log('Creating Dual Driver Doherty preset...');
    
    // Main driver
    this.addComponent('transistor', 100, 250, {label: 'Main Driver'});
    // Aux driver  
    this.addComponent('transistor', 100, 350, {label: 'Aux Driver'});
    // Matching networks
    this.addComponent('matching', 200, 250);
    this.addComponent('matching', 200, 350);
    // Main PA
    this.addComponent('transistor', 350, 250, {label: 'Main PA', pout: 46});
    // Aux PA
    this.addComponent('transistor', 350, 350, {label: 'Aux PA', pout: 43});
    // Combiner
    this.addComponent('combiner', 500, 300, {
      label: 'Doherty',
      type: 'Doherty',
      load_modulation: true
    });
    
    console.log('Dual Driver Doherty created');
  }
  
  createTripleStage() {
    console.log('Creating Triple Stage preset...');
    
    // Simple 3-stage cascade
    this.addComponent('transistor', 150, 300, {label: 'Pre-driver', gain: 12});
    this.addComponent('matching', 250, 300);
    this.addComponent('transistor', 350, 300, {label: 'Driver', gain: 15});
    this.addComponent('matching', 450, 300);
    this.addComponent('transistor', 550, 300, {label: 'Final PA', gain: 12, pout: 46});
    
    console.log('Triple Stage created');
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
    this.svg.transition().duration(500).call(
      this.zoom.transform,
      d3.zoomIdentity
    );
    console.log('Zoom reset');
  }
  
  handlePortClick(event, component, portType) {
    if (!this.wireMode) return;
    
    event.stopPropagation();
    
    if (!this.wireStart) {
      // First port clicked - start wire
      this.wireStart = {
        componentId: component.id,
        portType: portType,
        x: component.x + (portType === 'input' ? -5 : 35),
        y: component.y
      };
      console.log('Wire start:', this.wireStart);
    } else {
      // Second port clicked - complete wire
      const wireEnd = {
        componentId: component.id,
        portType: portType,
        x: component.x + (portType === 'input' ? -5 : 35),
        y: component.y
      };
      
      // Validate connection (output -> input)
      if (this.wireStart.portType === 'output' && portType === 'input') {
        this.createConnection(this.wireStart, wireEnd);
      } else {
        if (window.Shiny && window.Shiny.notifications) {
          Shiny.notifications.show({
            message: 'Invalid connection: Must connect output to input',
            type: 'warning'
          });
        }
      }
      
      this.wireStart = null;
    }
  }
  
  createConnection(start, end) {
    const connection = {
      id: this.connections.length + 1,
      from: {
        component: start.componentId,
        port: start.portType
      },
      to: {
        component: end.componentId,
        port: end.portType
      },
      properties: {
        impedance: 50,
        length: 0.25,
        type: 'microstrip'
      }
    };
    
    this.connections.push(connection);
    this.drawConnection(connection);
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_connections', this.connections, {priority: 'event'});
    }
    
    console.log('Connection created:', connection);
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
      .attr('stroke-width', 2)
      .attr('fill', 'none')
      .attr('marker-end', 'url(#arrowhead)')
      .attr('data-connection-id', connection.id);
    
    // Add arrowhead marker if not exists
    if (this.svg.select('#arrowhead').empty()) {
      this.svg.append('defs').append('marker')
        .attr('id', 'arrowhead')
        .attr('markerWidth', 10)
        .attr('markerHeight', 10)
        .attr('refX', 8)
        .attr('refY', 3)
        .attr('orient', 'auto')
        .append('polygon')
        .attr('points', '0 0, 10 3, 0 6')
        .attr('fill', '#00ff88');
    }
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
    
    // Update properties
    Object.assign(comp.properties, properties);
    
    console.log('New properties:', JSON.stringify(comp.properties));
    
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
    
    // Reapply drag behavior
    g.call(this.drag);
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
    }
    
    console.log('=== Component update complete ===');
  }
  
  deleteSelected() {
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
    
    // Remove any connections to/from this component
    this.connections = this.connections.filter(conn => 
      conn.from.component !== id && conn.to.component !== id
    );
    
    // Redraw connections
    this.connectionsLayer.selectAll('*').remove();
    // TODO: Re-render all connections
    
    // Clear selection
    this.selectedComponent = null;
    
    // Update Shiny
    if (window.Shiny) {
      Shiny.setInputValue('lineup_components', JSON.stringify(this.components), {priority: 'event'});
      Shiny.setInputValue('lineup_selected_component', null, {priority: 'event'});
      Shiny.setInputValue('lineup_connections', this.connections, {priority: 'event'});
    }
    
    console.log('Component deleted:', id);
  }
  
  toggleWireMode() {
    this.wireMode = !this.wireMode;
    
    const button = document.getElementById('lineup_wire_mode');
    if (button) {
      if (this.wireMode) {
        button.classList.add('active');
        button.style.backgroundColor = '#00cc66';
        button.textContent = 'Wire Mode: ON';
      } else {
        button.classList.remove('active');
        button.style.backgroundColor = '';
        button.textContent = 'Wire Mode';
      }
    }
    
    // Reset wire drawing state
    this.wireStart = null;
    
    console.log('Wire mode:', this.wireMode ? 'ON' : 'OFF');
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
  
  console.log('Registering Shiny custom message handler: updateComponent');
  
  // Remove existing handler if present
  if (ShinyObj.addCustomMessageHandler) {
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
    
    console.log('✓ Shiny message handler registered successfully');
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
