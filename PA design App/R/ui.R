ui <- dashboardPage(
  skin = "black",
  
  # Header
  dashboardHeader(
    title = span(
      icon("microchip"),
      "PA Design Assistant"
    ),
    tags$li(class = "dropdown",
      tags$a(href = "#", icon("user"), "Profile")
    ),
    # ── TOP UTILITY BAR ──────────────────────────────────────────────────────
    tags$li(class = "dropdown utility-nav",
      tags$a(href = "javascript:void(0);", class = "utility-link", `data-panel` = "util_data",
        icon("database"), " Data Manager")
    ),
    tags$li(class = "dropdown utility-nav",
      tags$a(href = "javascript:void(0);", class = "utility-link", `data-panel` = "smith_chart",
        icon("tools"), " RF Tools")
    ),
    tags$li(class = "dropdown utility-nav",
      tags$a(href = "javascript:void(0);", class = "utility-link", `data-panel` = "util_agents",
        icon("robot"), " AI Agents")
    ),
    tags$li(class = "dropdown utility-nav",
      tags$a(href = "javascript:void(0);", class = "utility-link", `data-panel` = "util_knowledge",
        icon("book"), " Knowledge Base")
    ),
    tags$li(class = "dropdown utility-nav",
      tags$a(href = "javascript:void(0);", class = "utility-link", `data-panel` = "settings",
        icon("cog"), " Settings")
    )
  ),
  
  # Sidebar
  dashboardSidebar(
    useShinyjs(),
    sidebarMenu(
      id = "sidebar_menu",
      menuItem("Dashboard",  tabName = "dashboard", icon = icon("tachometer-alt")),
      menuItem("Projects",   tabName = "projects",  icon = icon("folder-open")),

      # ── DESIGN FLOW ──────────────────────────────────────────────────────────
      tags$li(class = "header", "DESIGN FLOW"),

      menuItem("1 · First Principles", tabName = "first_principles", icon = icon("atom"),
        menuSubItem("1.1  Atoms & Charge",       tabName = "fp_atoms"),
        menuSubItem("1.2  EM Wave Origin",        tabName = "fp_em_waves"),
        menuSubItem("1.3  RF Materials",          tabName = "fp_materials"),
        menuSubItem("1.4  Transmission Lines",    tabName = "fp_tlines"),
        menuSubItem("1.5  Thermal Effects",       tabName = "fp_thermal")
      ),

      menuItem("2 · System Level", tabName = "system_level", icon = icon("network-wired"),
        menuSubItem("2.1  Frequency Planning",    tabName = "sys_freq_planning"),
        menuSubItem("2.2  TX Architectures",      tabName = "sys_tx_arch"),
        menuSubItem("2.3  RX Architectures",      tabName = "sys_rx_arch"),
        menuSubItem("2.4  Link Budget",           tabName = "sys_link_budget"),
        menuSubItem("2.5  System Architecture",   tabName = "sys_architecture")
      ),

      menuItem("3 · Technology Level", tabName = "tech_level", icon = icon("microchip"),
        menuSubItem("3.1  Technology Selection",  tabName = "tech_selection"),
        menuSubItem("3.2  Guardrails",            tabName = "tech_guardrails"),
        menuSubItem("3.3  Device Library",        tabName = "tech_device_lib"),
        menuSubItem("3.4  Loss Curves",           tabName = "tech_loss_curves"),
        menuSubItem("3.5  Technology Stack",      tabName = "tech_stack"),
        menuSubItem("3.6  Portfolio",             tabName = "tech_portfolio")
      ),

      menuItem("4 · Device Level", tabName = "device_level", icon = icon("draw-polygon"),
        menuSubItem("4.1  PA Specifications",          tabName = "dev_specs"),
        menuSubItem("4.2  Architecture & Design Canvas", tabName = "dev_architecture"),
        menuSubItem("4.3  Interstage & Passives",      tabName = "dev_interstage")
      ),

      menuItem("5 · Product Level", tabName = "product_level", icon = icon("industry"),
        menuSubItem("5.1  Transistor Design",     tabName = "prod_transistor"),
        menuSubItem("5.2  PA Stage Design",       tabName = "prod_pa_stage"),
        menuSubItem("5.3  Module Design",         tabName = "prod_module"),
        menuSubItem("5.4  Reliability",           tabName = "prod_reliability"),
        menuSubItem("5.5  Prototype",             tabName = "prod_prototype"),
        menuSubItem("5.6  CV Measurements",       tabName = "prod_cv_meas"),
        menuSubItem("5.7  Analysis",              tabName = "prod_analysis")
      ),

      menuItem("6 · Lessons Learnt",  tabName = "lessons_learnt",  icon = icon("graduation-cap")),
      menuItem("7 · Reporting",       tabName = "reporting",        icon = icon("file-alt")),
      menuItem("8 · App Download",    tabName = "app_download",     icon = icon("download"))
    )
  ),
  
  # Body
  dashboardBody(
    # Custom CSS and JS
    tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
      tags$link(rel = "stylesheet", type = "text/css", href = "css/pa_lineup.css"),
      tags$script(src = "https://d3js.org/d3.v7.min.js"),
      tags$script(src = "js/pa_lineup_canvas.js"),
      tags$script(src = "js/utility_drawer.js"),
      tags$style(HTML("
        /* Hardcoded fallbacks removed — all theming now in custom.css */
      ")),
      tags$script(HTML("
$(document).ready(function() {
  // ── Right-panel accordion: expand on hover, collapse on leave ───────────
  var hoverOpenedBox = null;
  var leaveTimer = null;

  function expandBox($box) {
    if ($box.hasClass('collapsed-box')) {
      $box.find('[data-widget=\"collapse\"]').trigger('click');
    }
  }

  function collapseBox($box) {
    if (!$box.hasClass('collapsed-box')) {
      $box.find('[data-widget=\"collapse\"]').trigger('click');
    }
  }

  // Hover enter: expand if collapsed
  $(document).on('mouseenter', '#right-panel-col .box', function() {
    var $box = $(this);
    clearTimeout(leaveTimer);
    if ($box.hasClass('collapsed-box')) {
      hoverOpenedBox = $box[0];
      expandBox($box);
    }
  });

  // Hover leave: collapse after short delay if opened by hover (not pinned)
  $(document).on('mouseleave', '#right-panel-col .box', function() {
    var $box = $(this);
    if ($box.data('rp-pinned')) return;
    var boxEl = $box[0];
    leaveTimer = setTimeout(function() {
      if (boxEl === hoverOpenedBox) {
        collapseBox($box);
        hoverOpenedBox = null;
      }
    }, 200);
  });

  // Manual toggle click: pin the box so hover-leave won't collapse it
  $(document).on('click', '#right-panel-col [data-widget=\"collapse\"]', function() {
    var $box = $(this).closest('.box');
    setTimeout(function() {
      $box.data('rp-pinned', !$box.hasClass('collapsed-box'));
      if (!$box.hasClass('collapsed-box')) hoverOpenedBox = null;
    }, 50);
  });

  // ── Component selected: expand Component Properties, collapse others ────
  $(document).on('shiny:inputchanged', function(e) {
    if (e.name !== 'lineup_selected_component') return;
    var $compProps = $('#panel_comp_props .box');
    var $allBoxes  = $('#right-panel-col .box');

    if (e.value) {
      // Collapse & unpin all except Component Properties
      $allBoxes.not($compProps).each(function() {
        $(this).data('rp-pinned', false);
        collapseBox($(this));
      });
      // Expand & pin Component Properties
      $compProps.data('rp-pinned', true);
      expandBox($compProps);
      hoverOpenedBox = null;
    } else {
      // Deselected — unpin Component Properties so hover works again
      $compProps.data('rp-pinned', false);
    }
  });

  // Utility drawer logic lives in www/js/utility_drawer.js (loaded from tags$head).
  // jQuery delegation and global function declarations are defined there,
  // avoiding all R string-escaping issues.
});
      "))
    ),

    # ── UTILITY DRAWER ────────────────────────────────────────────────────────
    # Slides in from the right when a utility-bar icon is clicked.
    # Main content remains interactive underneath.
    tags$div(id = "utility-drawer",
      # Header bar
      tags$div(id = "utility-drawer-header",
        tags$span(id = "utility-drawer-icon",  class = "drawer-icon"),
        tags$span(id = "utility-drawer-title", "Utility Panel"),
        # "Expand to full view" button
        tags$button(class = "drawer-hdr-btn", id = "drawer-full-btn",
          title = "Open full screen view",
          tags$i(class = "fa fa-expand-arrows-alt"), " Full View"
        ),
        # "Open in new tab" button
        tags$button(class = "drawer-hdr-btn", id = "drawer-popout-btn",
          title = "Open in new browser tab",
          tags$i(class = "fa fa-external-link-alt"), " New Tab"
        ),
        # Close button
        tags$button(class = "drawer-hdr-btn btn-close-drawer", id = "drawer-close-btn",
          title = "Close panel",
          tags$i(class = "fa fa-times")
        )
      ),
      # Scrollable body — content rendered by server
      tags$div(id = "utility-drawer-body",
        uiOutput("utility_drawer_content")
      )
    ),

    tabItems(
      # Dashboard Tab
      tabItem(tabName = "dashboard",
        fluidRow(
          valueBoxOutput("total_projects", width = 3),
          valueBoxOutput("active_projects", width = 3),
          valueBoxOutput("success_rate", width = 3),
          valueBoxOutput("avg_cycle_time", width = 3)
        ),
        fluidRow(
          box(
            title = "Recent Projects",
            width = 8,
            status = "primary",
            solidHeader = TRUE,
            DTOutput("recent_projects_table")
          ),
          box(
            title = "Design Phase Distribution",
            width = 4,
            status = "info",
            solidHeader = TRUE,
            plotlyOutput("phase_distribution")
          )
        ),
        fluidRow(
          box(
            title = "AI Agent Activity",
            width = 12,
            status = "success",
            solidHeader = TRUE,
            plotlyOutput("agent_activity")
          )
        )
      ),
      
      # Projects Tab
      tabItem(tabName = "projects",
        fluidRow(
          box(
            title = "Create New Project",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            textInput("new_project_name", "Project Name"),
            selectInput("new_project_arch", "Architecture Type",
              choices = c("Class-A", "Class-B", "Class-AB", "Class-C",
                         "Class-D", "Class-E", "Class-F", "Doherty")),
            numericInput("new_project_freq", "Frequency (GHz)", value = 2.4, min = 0.1, max = 100),
            numericInput("new_project_pout", "Target Pout (dBm)", value = 30, min = 0, max = 60),
            selectInput("new_project_technology", "Technology",
              choices = c(
                "GaN HEMT (SiC)" = "GaN_SiC",
                "GaN HEMT (Si)"  = "GaN_Si",
                "Si LDMOS"       = "LDMOS",
                "GaAs pHEMT"     = "GaAs_pHEMT",
                "SiGe HBT"       = "SiGe_HBT",
                "InP HEMT"       = "InP_HEMT"
              ),
              selected = "GaN_SiC"
            ),
            numericInput("new_project_vdd", "Supply Voltage — Vdd (V)", value = 28, min = 1, max = 65, step = 1),
            actionButton("create_project_btn", "Create Project",
                        class = "btn-primary", icon = icon("plus"))
          ),
          box(
            title = "All Projects",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            DTOutput("all_projects_table")
          )
        )
      ),
      
      # Theoretical Calculation Tab
      # ── 2.1 Frequency Planning ────────────────────────────────────────────────
      tabItem(tabName = "sys_freq_planning",
        fluidRow(
          box(
            title = "Project Selection",
            width = 12,
            status = "primary",
            solidHeader = TRUE,
            collapsible = TRUE,
            selectInput("calc_project_select", "Select Project", choices = NULL),
            textOutput("calc_project_specs")
          )
        ),
              
              fluidRow(
                column(3,
                  h4("View Mode:"),
                  radioButtons("freq_view_mode", NULL,
                    choices = c("Canvas" = "canvas", "Table" = "table", "Equations" = "equations"),
                    selected = "canvas", inline = TRUE)
                ),
                column(9,
                  fluidRow(
                    column(4,
                      numericInput("freq_target_freq", "Target Frequency (GHz)", value = 28, min = 0.1, max = 300),
                      div(
                        fluidRow(
                          column(6,
                            numericInput("freq_target_power", "Target Power", value = 43, min = -30, max = 100)
                          ),
                          column(6,
                            selectInput("freq_target_power_unit", "Unit",
                              choices = c("dBm" = "dbm", "W" = "w"),
                              selected = "dbm", width = "100%")
                          )
                        ),
                        uiOutput("freq_target_power_display")
                      )
                    ),
                    column(8,
                      checkboxInput("freq_show_eff", "PA Efficiency Curves", TRUE),
                      checkboxInput("freq_show_atm", "Atmospheric Attenuation", TRUE),
                      checkboxInput("freq_show_tech", "Technology Suitability", TRUE),
                      checkboxInput("freq_show_6g", "6G Candidate Band", TRUE)
                    )
                  )
                )
              ),
              hr(),
              
              # Canvas View
              conditionalPanel(
                condition = "input.freq_view_mode == 'canvas'",
                plotlyOutput("freq_planning_canvas", height = "600px")
              ),
              
              # Table View
              conditionalPanel(
                condition = "input.freq_view_mode == 'table'",
                DTOutput("freq_planning_table")
              ),
              
              # Equations View
              conditionalPanel(
                condition = "input.freq_view_mode == 'equations'",
                wellPanel(
                  h4("Frequency Planning Equations"),
                  HTML("
                    <h5>PA Efficiency Models:</h5>
                    <ul>
                      <li><b>LDMOS:</b> η<sub>LDMOS</sub>(f) = max(65 - 0.8f, 5%)</li>
                      <li><b>GaN:</b> η<sub>GaN</sub>(f) = max(70 - 0.3f, 20%)</li>
                      <li><b>SiGe:</b> η<sub>SiGe</sub>(f) = max(50 - 0.15f, 10%)</li>
                    </ul>
                    <h5>Atmospheric Attenuation:</h5>
                    <ul>
                      <li><b>O<sub>2</sub> Absorption:</b> L<sub>O2</sub>(f) = 15·exp(-((f-60)²)/(2·5²)) dB/km</li>
                      <li><b>H<sub>2</sub>O Absorption:</b> L<sub>H2O</sub>(f) = 8·exp(-((f-22)²)/(2·3²)) dB/km</li>
                      <li><b>Total:</b> L<sub>atm</sub>(f) = 0.01f + L<sub>O2</sub>(f) + L<sub>H2O</sub>(f)</li>
                    </ul>
                    <h5>Technology Selection:</h5>
                    <ul>
                      <li><b>LDMOS:</b> 0.01 - 4 GHz (High power, macro base stations)</li>
                      <li><b>GaN:</b> 1 - 100 GHz (Best efficiency/power density tradeoff)</li>
                      <li><b>SiGe:</b> 20 - 300 GHz (Sub-THz, 6G applications)</li>
                    </ul>
                  ")
                )
              ),
              
      ),  # closes tabItem(sys_freq_planning)

      # ── 2.4 Link Budget ───────────────────────────────────────────────────────
      tabItem(tabName = "sys_link_budget",
              
              fluidRow(
                column(3,
                  h4("View Mode:"),
                  radioButtons("link_view_mode", NULL,
                    choices = c("Canvas" = "canvas", "Table" = "table", "Equations" = "equations"),
                    selected = "canvas", inline = TRUE)
                ),
                column(9,
                  h4("Link Budget Parameters:"),
                  fluidRow(
                    column(6,
                      numericInput("link_tx_power", "Tx Power (dBm)", value = 43, min = -20, max = 80),
                      numericInput("link_tx_gain", "Tx Antenna Gain (dBi)", value = 15, min = -10, max = 50),
                      numericInput("link_freq", "Frequency (GHz)", value = 28, min = 0.1, max = 100),
                      numericInput("link_distance", "Distance (km)", value = 1, min = 0.001, max = 100)
                    ),
                    column(6,
                      numericInput("link_rx_gain", "Rx Antenna Gain (dBi)", value = 15, min = -10, max = 50),
                      numericInput("link_noise_figure", "Rx Noise Figure (dB)", value = 5, min = 0, max = 20),
                      numericInput("link_bandwidth", "Bandwidth (MHz)", value = 100, min = 0.001, max = 10000),
                      numericInput("link_snr_req", "Required SNR (dB)", value = 20, min = 0, max = 50)
                    )
                  ),
                  actionButton("link_calculate", "Calculate Link Budget", class = "btn-success", icon = icon("calculator"))
                )
              ),
              hr(),
              
              # Canvas View
              conditionalPanel(
                condition = "input.link_view_mode == 'canvas'",
                plotlyOutput("link_budget_canvas", height = "600px")
              ),
              
              # Table View
              conditionalPanel(
                condition = "input.link_view_mode == 'table'",
                DTOutput("link_budget_table")
              ),
              
              # Equations View
              conditionalPanel(
                condition = "input.link_view_mode == 'equations'",
                wellPanel(
                  h4("Link Budget Equations"),
                  HTML("
                    <h5>Free Space Path Loss:</h5>
                    <p><b>FSPL (dB)</b> = 20·log<sub>10</sub>(d) + 20·log<sub>10</sub>(f) + 92.45</p>
                    <p>where: d = distance (km), f = frequency (GHz)</p>
                    
                    <h5>Received Power:</h5>
                    <p><b>P<sub>rx</sub> (dBm)</b> = P<sub>tx</sub> + G<sub>tx</sub> - FSPL + G<sub>rx</sub></p>
                    
                    <h5>Thermal Noise Power:</h5>
                    <p><b>N (dBm)</b> = -174 + 10·log<sub>10</sub>(BW) + NF</p>
                    <p>where: BW = bandwidth (Hz), NF = noise figure (dB)</p>
                    
                    <h5>Signal-to-Noise Ratio:</h5>
                    <p><b>SNR (dB)</b> = P<sub>rx</sub> - N</p>
                    
                    <h5>Link Margin:</h5>
                    <p><b>Margin (dB)</b> = SNR - SNR<sub>required</sub></p>
                    
                    <h5>Additional Losses (typical):</h5>
                    <ul>
                      <li><b>Atmospheric:</b> 0.1 - 2 dB/km (frequency dependent)</li>
                      <li><b>Rain:</b> 0.5 - 20 dB (rain rate dependent)</li>
                      <li><b>Polarization mismatch:</b> 0.5 - 3 dB</li>
                      <li><b>Implementation loss:</b> 1 - 3 dB</li>
                    </ul>
                  ")
                )
              ),
              
              hr(),
              htmlOutput("link_budget_summary")
      ),  # closes tabItem(sys_link_budget)

      # ── 3.4 Loss Curves ───────────────────────────────────────────────────────
      tabItem(tabName = "tech_loss_curves",
              
              fluidRow(
                column(12,
                  box(
                    title = tagList(icon("chart-area"), "Passive Component Loss vs Frequency"),
                    width = 12,
                    status = "warning",
                    solidHeader = TRUE,
                    
                    fluidRow(
                      column(8,
                        plotlyOutput("loss_curves_plot", height = "550px")
                      ),
                      column(4,
                        wellPanel(
                          h4(icon("wrench"), " Component Selection"),
                          
                          checkboxGroupInput("loss_curve_components",
                            "Display Components:",
                            choices = c(
                              "Wilkinson Splitter (2-way)" = "wilkinson_splitter",
                              "Wilkinson Combiner (2-way)" = "wilkinson_combiner",
                              "Quadrature Hybrid (90°)" = "quadrature_hybrid",
                              "T-Junction Splitter" = "t_junction",
                              "Transmission Line (10cm)" = "transmission_line",
                              "Doherty Combiner" = "doherty_combiner",
                              "Transformer (1:1)" = "transformer"
                            ),
                            selected = c("wilkinson_splitter", "wilkinson_combiner", "doherty_combiner", "transmission_line")
                          ),
                          
                          hr(),
                          
                          h5(icon("calculator"), " Quick Calculator"),
                          numericInput("loss_calc_freq", "Frequency (GHz)", value = 2.6, min = 0.1, max = 30, step = 0.1),
                          selectInput("loss_calc_type", "Component Type",
                            choices = c(
                              "Wilkinson Splitter" = "wilkinson_splitter",
                              "Wilkinson Combiner" = "wilkinson_combiner",
                              "Quadrature Hybrid" = "quadrature_hybrid",
                              "T-Junction" = "t_junction",
                              "Transmission Line (10cm)" = "transmission_line",
                              "Doherty Combiner" = "doherty_combiner",
                              "Transformer" = "transformer"
                            )
                          ),
                          div(class = "callout callout-accent", style = "margin-top: 10px;",
                            h4(icon("arrow-right"), " Estimated Loss:"),
                            h3(textOutput("loss_calc_result", inline = TRUE), style = "color: var(--accent); margin: 5px 0;"),
                            p("dB", style = "color: var(--tx-med); margin: 0;")
                          )
                        )
                      )
                    ),
                    
                    hr(),
                    
                    h4(icon("book"), " Loss Estimation Models & Academic References"),
                    
                    tabsetPanel(
                      tabPanel("Formulas",
                        br(),
                        HTML("
                          <h5>1. Wilkinson Splitter/Combiner</h5>
                          <p><strong>Model:</strong> L<sub>wilk</sub>(f) = 3.0 + 0.1 + 0.05·f [dB]</p>
                          <ul>
                            <li>3.0 dB: Ideal power split (2-way)</li>
                            <li>0.1 dB: Quarter-wave transformer insertion loss (baseline)</li>
                            <li>0.05·f: Frequency-dependent losses (skin effect, dielectric)</li>
                          </ul>
                          <p><strong>Reference:</strong> Wilkinson, E.J. 'An N-Way Hybrid Power Divider' (IEEE Trans. MTT, 1960)</p>
                          
                          <h5>2. Quadrature Hybrid (90° Coupler)</h5>
                          <p><strong>Model:</strong> L<sub>quad</sub>(f) = 0.3 + 0.08·f + 0.02·f<sup>1.5</sup> [dB]</p>
                          <ul>
                            <li>Coupled-line structure with directivity limitations</li>
                            <li>Higher frequency → Reduced directivity → Increased loss</li>
                          </ul>
                          <p><strong>Reference:</strong> Mongia et al. 'RF and Microwave Coupled-Line Circuits' (Artech House, 2007)</p>
                          
                          <h5>3. Transmission Line (Microstrip on FR4)</h5>
                          <p><strong>Model:</strong> L<sub>line</sub>(f) = (0.05 + 0.15·√f + 0.02·f) × L/10 [dB]</p>
                          <ul>
                            <li>Skin effect losses: ∝ √f</li>
                            <li>Dielectric losses: ∝ f (tanδ = 0.02 for FR4)</li>
                            <li>L: Length in cm</li>
                          </ul>
                          <p><strong>Reference:</strong> Wadell, B.C. 'Transmission Line Design Handbook' (Artech House, 1991), Section 3.4</p>
                          
                          <h5>4. Doherty Combiner</h5>
                          <p><strong>Model:</strong> L<sub>doh</sub>(f) = 0.2 + 0.02·f + 0.01·f<sup>1.3</sup> [dB]</p>
                          <ul>
                            <li>Lower loss than Wilkinson (impedance transformation, no resistor)</li>
                            <li>Quarter-wave impedance inverter</li>
                          </ul>
                          <p><strong>Reference:</strong> Cripps, S.C. 'RF Power Amplifiers for Wireless Communications' Ch.9 (Artech House, 2006)</p>
                          
                          <h5>5. Transformer (1:1 ratio)</h5>
                          <p><strong>Model:</strong></p>
                          <ul>
                            <li>f < 0.5 GHz: L = 0.3 + 0.05·f (core loss dominant)</li>
                            <li>0.5 - 3 GHz: L = 0.2 + 0.03·(f - 0.5) (optimal range)</li>
                            <li>f > 3 GHz: L = 0.4 + 0.1·(f - 3) (winding/stray capacitance)</li>
                          </ul>
                          <p><strong>Reference:</strong> Sevick, J. 'Transmission Line Transformers' (Noble Publishing, 2001)</p>
                          
                          <h5>6. T-Junction Splitter</h5>
                          <p><strong>Model:</strong> L<sub>tjunc</sub>(f) = 0.05 + 0.03·f [dB]</p>
                          <ul>
                            <li>Very low loss but poor isolation</li>
                            <li>Simple transmission line junction</li>
                          </ul>
                        ")
                      ),
                      
                      tabPanel("Usage in Lineup",
                        br(),
                        HTML("
                          <div class='callout callout-info' style='margin-bottom: 15px;'>
                            <h5><i class='fa fa-info-circle'></i> Automatic Loss Application</h5>
                            <p>When you apply specifications to a lineup, these loss curves are <strong>automatically</strong> consulted to populate passive component parameters at the appropriate frequency.</p>
                          </div>
                          
                          <h5>How Loss Curves Impact Lineup Design</h5>
                          
                          <h6>1. Power Budget Calculations</h6>
                          <p>Each passive component reduces available power:</p>
                          <ul>
                            <li><strong>Splitters:</strong> P<sub>out</sub> = P<sub>in</sub> - 10·log<sub>10</sub>(N) - L<sub>insertion</sub></li>
                            <li><strong>Transmission Lines:</strong> Cumulative loss through cascade</li>
                            <li><strong>Combiners:</strong> Slightly reduce combined output power</li>
                          </ul>
                          
                          <h6>2. Gain Reduction</h6>
                          <p>Total lineup gain is reduced by passive losses:</p>
                          <p class='code-block'>
                            G<sub>total</sub> = Σ(G<sub>transistor</sub>) - Σ(L<sub>passive</sub>)
                          </p>
                          
                          <h6>3. Frequency-Dependent Behavior</h6>
                          <table class='table table-sm table-striped'>
                            <thead>
                              <tr>
                                <th>Frequency</th>
                                <th>Wilkinson Loss</th>
                                <th>Transmission Line (10cm)</th>
                                <th>Impact</th>
                              </tr>
                            </thead>
                            <tbody>
                              <tr>
                                <td>1 GHz</td>
                                <td>~3.2 dB</td>
                                <td>~0.37 dB</td>
                                <td>Manageable</td>
                              </tr>
                              <tr>
                                <td>5 GHz</td>
                                <td>~3.35 dB</td>
                                <td>~0.89 dB</td>
                                <td>Moderate</td>
                              </tr>
                              <tr>
                                <td>10 GHz</td>
                                <td>~3.60 dB</td>
                                <td>~1.45 dB</td>
                                <td>Significant</td>
                              </tr>
                              <tr>
                                <td>28 GHz</td>
                                <td>~3.80 dB</td>
                                <td>~3.50 dB</td>
                                <td>Critical (mmWave)</td>
                              </tr>
                            </tbody>
                          </table>
                          
                          <h6>4. Design Strategies</h6>
                          <ul>
                            <li><strong>Minimize Interconnect Length:</strong> Each cm matters at mmWave</li>
                            <li><strong>Choose Low-Loss Substrate:</strong> Rogers/Alumina vs FR4 at high freq</li>
                            <li><strong>Prefer Doherty Combiner:</strong> ~0.5 dB vs 3.2 dB for Wilkinson</li>
                            <li><strong>Use T-Junction When Isolation Not Critical:</strong> Lowest loss option</li>
                          </ul>
                          
                          <div class='callout callout-warn' style='margin-top: 15px;'>
                            <h5><i class='fa fa-lightbulb'></i> Pro Tip</h5>
                            <p><strong>At mmWave (>20 GHz):</strong> Passive losses can exceed active device gains! Consider integrated approaches or waveguide structures to minimize interconnect.</p>
                          </div>
                        ")
                      )
                    )
                  )
                )
              )
      ),  # closes tabItem(tech_loss_curves)

      # ── 3.2 Guardrails ────────────────────────────────────────────────────────
      tabItem(tabName = "tech_guardrails",

              fluidRow(
                # ── Left column: Technology selector & Sanity Check ──
                column(3,
                  box(
                    title = tagList(icon("microchip"), "Technology"),
                    width = 12, status = "primary", solidHeader = TRUE,
                    selectInput("grd_tech_select", "Select Technology",
                      choices = c(
                        "GaN HEMT (SiC)"  = "GaN_SiC",
                        "GaN HEMT (Si)"   = "GaN_Si",
                        "Si LDMOS"        = "LDMOS",
                        "GaAs pHEMT"      = "GaAs_pHEMT",
                        "SiGe HBT"        = "SiGe_HBT",
                        "InP HEMT"        = "InP_HEMT"
                      ),
                      selected = "GaN_SiC"
                    ),
                    hr(),
                    h5(icon("sliders-h"), " Filter Design Space"),
                    checkboxGroupInput("grd_tech_overlay",
                      "Show technologies:",
                      choices = c(
                        "GaN HEMT (SiC)"  = "GaN_SiC",
                        "GaN HEMT (Si)"   = "GaN_Si",
                        "Si LDMOS"        = "LDMOS",
                        "GaAs pHEMT"      = "GaAs_pHEMT",
                        "SiGe HBT"        = "SiGe_HBT",
                        "InP HEMT"        = "InP_HEMT"
                      ),
                      selected = c("GaN_SiC", "GaN_Si", "LDMOS", "GaAs_pHEMT")
                    )
                  ),

                  box(
                    title = tagList(icon("check-circle"), "Sanity Check"),
                    width = 12, status = "warning", solidHeader = TRUE,
                    p(style = "font-size:12px; color:var(--tx-med);",
                      "Enter your device parameters to validate against guardrails:"),
                    numericInput("grd_chk_freq",  "Frequency (GHz)",  value = 3.5,  min = 0.1,  max = 300,  step = 0.1),
                    numericInput("grd_chk_gain",  "Gain (dB)",        value = 15,   min = 1,    max = 35,   step = 0.5),
                    numericInput("grd_chk_pae",   "PAE @ P3dB (%)",   value = 60,   min = 1,    max = 85,   step = 1),
                    numericInput("grd_chk_pout",  "Pout (dBm)",       value = 43,   min = 0,    max = 60,   step = 0.5),
                    numericInput("grd_chk_vdd",   "Vdd (V)",          value = 28,   min = 1,    max = 100,  step = 1),
                    numericInput("grd_chk_pdensity", "Pout density (W/mm)\n(0 = skip)",
                                 value = 0, min = 0, max = 20, step = 0.1),
                    actionButton("grd_run_check", "Validate",
                      class = "btn-warning btn-block", icon = icon("flask")),
                    br(),
                    uiOutput("grd_validation_result")
                  ),

                  # ── Save to Device Library ──────────────────────────
                  box(
                    title = tagList(icon("save"), "Save to Device Library"),
                    width = 12, status = "success", solidHeader = TRUE,
                    collapsible = TRUE,
                    p(style = "font-size:12px; color:var(--tx-med); margin-bottom:8px;",
                      "Save the current parameters as a reusable transistor component.",
                      " It will appear in the PA Lineup canvas palette under 'Device Library'."),
                    textInput("grd_save_label", "Device Label",
                              placeholder = "e.g. GaN_3p5G_43dBm"),
                    textInput("grd_save_notes", "Notes (optional)",
                              placeholder = "e.g. 3.5 GHz driver stage"),
                    actionButton("grd_save_device", "Save to Library",
                      class = "btn-success btn-block", icon = icon("save")),
                    uiOutput("grd_save_result"),
                    br(),
                    p(style = "font-size:11px; font-weight:bold; color:var(--tx-med); text-transform:uppercase;",
                      "Saved Devices:"),
                    uiOutput("grd_saved_devices_list"),
                    br(),
                    div(style = "border-top:1px solid rgba(255,255,255,0.1); padding-top:8px;",
                      p(style = "font-size:11px; font-weight:bold; color:#00ccff; text-transform:uppercase; margin-bottom:4px;",
                        icon("chart-line"), " Overlay on Plots:"),
                      uiOutput("grd_device_lib_select_ui"),
                      fluidRow(
                        column(6, actionLink("grd_lib_select_all", "Select all", style = "font-size:11px;")),
                        column(6, actionLink("grd_lib_select_none", "Clear", style = "font-size:11px; float:right;"))
                      )
                    )
                  )
                ),

                # ── Right column: Plots ──
                column(9,
                  tabsetPanel(
                    id = "grd_plot_tabs",

                    # ── Plot 1: Technology Design Space (4D bubble) ──
                    tabPanel(
                      title = tagList(icon("rocket"), "Design Space"),
                      value = "grd_design_space",
                      br(),
                      div(
                        style = "background:var(--s-raised); border-left:4px solid #70AD47; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:var(--tx-med);",
                          icon("info-circle"), " ",
                          strong(style="color:var(--tx-hi);", "How to read this chart:"),
                          " Each bubble = one technology. X = frequency, Y = Pout density (W/mm). ",
                          "Bubble SIZE = typical PAE at P3dB. Bubble COLOR = technology. ",
                          "The shaded band = sweet-spot operating range. ",
                          strong("Your device"), " appears as a ★ marker showing where it falls."
                        )
                      ),
                      fluidRow(
                        column(6,
                          radioButtons("grd_yaxis_mode", "Y-axis:",
                            choices = c("Pout density (W/mm)" = "density", "Pout (dBm)" = "pout_dbm"),
                            selected = "density", inline = TRUE)
                        ),
                        column(6,
                          radioButtons("grd_bubble_size", "Bubble size encodes:",
                            choices = c("PAE (%)" = "pae", "Gain (dB)" = "gain"),
                            selected = "pae", inline = TRUE)
                        )
                      ),
                      plotlyOutput("grd_design_space_plot", height = "480px")
                    ),

                    # ── Plot 2: Gain vs Frequency ──
                    tabPanel(
                      title = tagList(icon("chart-line"), "Gain vs Frequency"),
                      value = "grd_gain_bw",
                      br(),
                      div(
                        style = "background:var(--s-raised); border-left:4px solid #4472C4; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:var(--tx-med);",
                          icon("info-circle"), " ",
                          strong(style="color:var(--tx-hi);", "Gain envelope from fT:"),
                          " Solid line = typical gain (20·log₁₀(fT/f) blended with fmax model). ",
                          "Shaded upper region = best-case (max fT process). ",
                          "Your ★ marker shows where your design point lands."
                        )
                      ),
                      checkboxInput("grd_gain_show_ft_rule",
                        "Show pure 20 dB/decade fT/f reference line", value = TRUE),
                      plotlyOutput("grd_gain_bw_plot", height = "480px")
                    ),

                    # ── Plot 3: PAE vs Backoff ──
                    tabPanel(
                      title = tagList(icon("battery-half"), "PAE vs Backoff"),
                      value = "grd_pae_bo",
                      br(),
                      div(
                        style = "background:var(--s-raised); border-left:4px solid #FFC000; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:var(--tx-med);",
                          icon("info-circle"), " ",
                          strong(style="color:var(--tx-hi);", "PAE backoff behaviour by PA class:"),
                          " Shows how PAE degrades as you back off from P3dB. ",
                          "Class A collapses fastest; Doherty stays flat over the BO window. ",
                          "Your ★ marks your operating point (P3dB vs Pavg)."
                        )
                      ),
                      fluidRow(
                        column(4,
                          checkboxGroupInput("grd_pae_classes",
                            "PA classes to show:",
                            choices = c("Class A" = "A", "Class AB" = "AB",
                                        "Class B" = "B", "Doherty" = "Doherty",
                                        "Class F" = "F"),
                            selected = c("AB", "Doherty", "B")
                          )
                        ),
                        column(4,
                          numericInput("grd_pae_pavg_bo", "Your operating backoff (dB)",
                            value = 8, min = 0, max = 20, step = 0.5),
                          p(style="font-size:11px;color:var(--tx-med);", "= PAR / system BO from P3dB")
                        )
                      ),
                      plotlyOutput("grd_pae_bo_plot", height = "480px")
                    ),

                    # ── Tab 4: Guardrail Reference Table ──
                    tabPanel(
                      title = tagList(icon("table"), "Reference Table"),
                      value = "grd_ref_table",
                      br(),
                      div(
                        style = "background:var(--s-raised); border-left:4px solid #7030A0; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:var(--tx-med);",
                          icon("info-circle"), " ",
                          "Physics-grounded limits per technology. ",
                          "All values derived from process data and first-principles models. ",
                          "Use these as starting points for component portfolio entries."
                        )
                      ),
                      DTOutput("grd_ref_table_dt"),
                      br(),
                      box(
                        title = tagList(icon("book"), "Key Design Rules"),
                        width = 12, status = "primary", collapsible = TRUE, collapsed = FALSE,
                        HTML("
                          <table class='table table-sm table-bordered' style='font-size:13px;'>
                            <thead><tr>
                              <th>Rule</th><th>Formula / Limit</th><th>Derivation</th>
                            </tr></thead>
                            <tbody>
                              <tr>
                                <td><strong>Gain limit</strong></td>
                                <td>G<sub>av</sub> ≈ 20·log<sub>10</sub>(f<sub>T</sub>/f<sub>op</sub>)</td>
                                <td>Current gain h<sub>21</sub> rolls at 20 dB/decade from f<sub>T</sub></td>
                              </tr>
                              <tr>
                                <td><strong>Technology selection</strong></td>
                                <td>Choose tech where f<sub>T</sub> &gt; 5·f<sub>op</sub></td>
                                <td>Ensures ≥14 dB available gain and stability margin</td>
                              </tr>
                              <tr>
                                <td><strong>Max PAE (Class B)</strong></td>
                                <td>PAE<sub>max</sub> = π/4 ≈ 78.5%</td>
                                <td>Ideal Class-B, no knee voltage, no parasitics</td>
                              </tr>
                              <tr>
                                <td><strong>Max PAE (Class A)</strong></td>
                                <td>PAE<sub>max</sub> = 50%</td>
                                <td>Constant DC bias regardless of output swing</td>
                              </tr>
                              <tr>
                                <td><strong>PAE at backoff (Class AB)</strong></td>
                                <td>PAE(BO) ≈ PAE<sub>P3dB</sub> · (P<sub>out</sub>/P<sub>3dB</sub>)<sup>0.6</sup></td>
                                <td>Intermediate between Class A (exp=1) and B (exp=0.5)</td>
                              </tr>
                              <tr>
                                <td><strong>Vdd reliability</strong></td>
                                <td>V<sub>dd</sub> &lt; V<sub>br</sub> × 0.4</td>
                                <td>Hot-carrier + electromigration lifetime &gt;10<sup>6</sup> h</td>
                              </tr>
                              <tr>
                                <td><strong>Pout density</strong></td>
                                <td>P<sub>den</sub> = V<sub>dd</sub>² / (8·R<sub>opt</sub>·f<sub>gate</sub>)</td>
                                <td>Limited by V<sub>br</sub> swing, I<sub>max</sub>, and thermal conductivity</td>
                              </tr>
                              <tr>
                                <td><strong>Thermal limit</strong></td>
                                <td>T<sub>j</sub> = T<sub>a</sub> + P<sub>diss</sub>·θ<sub>JC</sub></td>
                                <td>P<sub>diss</sub> = P<sub>DC</sub> − P<sub>out</sub>; keep T<sub>j</sub> &lt; T<sub>j,max</sub> − 20°C</td>
                              </tr>
                            </tbody>
                          </table>
                        ")
                      )
                    )
                  )
                )
              )
      ),  # closes tabItem(tech_guardrails)

      # ── 4.2 Architecture & Design Canvas (PA Lineup) ────────────────────────
      tabItem(tabName = "dev_architecture",
              
              fluidRow(
                # Left: Interactive Canvas
                column(9, id = "canvas-col",
                  box(
                    title = tagList(
                      icon("paint-brush"), 
                      "Interactive PA Lineup Canvas",
                      div(style = "float: right;",
                        tags$button(
                          id = "canvas_fullscreen_btn",
                          class = "btn btn-sm btn-default",
                          style = "margin-top: -5px;",
                          onclick = "toggleCanvasFullscreen();",
                          icon("expand"),
                          title = "Toggle Fullscreen"
                        )
                      )
                    ),
                    width = 12,
                    status = "info",
                    solidHeader = TRUE,
                    id = "sticky_canvas_box",
                    div(
                      id = "pa_lineup_canvas_container", 
                      style = "position: relative;",
                      
                      # Floating top sidebar for architecture templates
                      div(
                        id = "canvas_top_sidebar",
                        class = "canvas-top-sidebar collapsed",
                        
                        # Toggle button
                        tags$button(
                          id = "top_sidebar_toggle",
                          class = "top-sidebar-toggle",
                          onclick = "toggleCanvasTopSidebar()",
                          icon("chevron-down"),
                          " Templates & Devices"
                        ),
                        
                        # Top sidebar content
                        div(
                          class = "top-sidebar-content top-sidebar-two-col",

                          # ── Left column: Architecture Templates ──────────
                          div(
                            class = "top-sidebar-col",
                            div(class = "top-sidebar-title", icon("layer-group"), " Architecture Templates"),
                            div(class = "top-sidebar-templates",
                              div(class = "preset-template", `data-preset` = "triple_stage",
                                h5("3-Stage Cascade"),
                                p("Pre-driver → Driver → Final PA")
                              ),
                              div(class = "preset-template", `data-preset` = "single_doherty",
                                h5("Single Driver Doherty"),
                                p("Driver → Splitter → Main/Aux PA")
                              ),
                              div(class = "preset-template", `data-preset` = "dual_doherty",
                                h5("Dual Driver Doherty"),
                                p("Dual drivers → Main/Aux paths")
                              ),
                              div(class = "preset-template", `data-preset` = "conventional_doherty",
                                h5("Conventional Doherty"),
                                p("Standard λ/4 impedance transformation")
                              ),
                              div(class = "preset-template", `data-preset` = "inverted_doherty",
                                h5("Inverted Doherty"),
                                p("Inverted phase configuration")
                              ),
                              div(class = "preset-template", `data-preset` = "symmetric_doherty",
                                h5("Symmetric Doherty"),
                                p("Equal power Main & Aux PAs")
                              ),
                              div(class = "preset-template", `data-preset` = "asymmetric_doherty",
                                h5("Asymmetric Doherty"),
                                p("2:1 power ratio for extended efficiency")
                              ),
                              div(class = "preset-template", `data-preset` = "envelope_tracking_doherty",
                                h5("Envelope Tracking Doherty"),
                                p("Main/Aux with VDD modulation")
                              ),
                              div(class = "preset-template", `data-preset` = "3way_symmetric_doherty",
                                h5("3-Way Symmetric Doherty"),
                                p("1 main + 2 equal peaking PAs")
                              ),
                              div(class = "preset-template", `data-preset` = "3way_asymmetric_doherty",
                                h5("3-Way Asymmetric Doherty"),
                                p("1 main (50%) + 2 peaking (25% each)")
                              ),
                              div(class = "preset-template", `data-preset` = "blank",
                                h5("Blank Canvas"),
                                p("Start from scratch")
                              ),
                              # User Saved Templates Section
                              tags$div(class = "sidebar-section-label", style = "font-size: 10px; color: var(--tx-low); margin: 15px 10px 5px 10px; text-transform: uppercase; letter-spacing: 0.5px; border-top: 1px solid rgba(255,255,255,0.1); padding-top: 10px;", "USER SAVED TEMPLATES"),
                              tags$div(id = "user_templates_top_sidebar",
                                uiOutput("user_templates_top_display")
                              )
                            )
                          ),

                          # ── Right column: Device Library ─────────────────
                          div(
                            class = "top-sidebar-col top-sidebar-col-devices",
                            div(class = "top-sidebar-title", icon("microchip"), " Device Library"),
                            div(
                              id = "top_sidebar_device_col",
                              class = "top-sidebar-templates",
                              p(class = "top-sidebar-empty-hint",
                                icon("info-circle"), " Save devices from the ",
                                tags$strong("Guardrails"), " tab to populate this panel."
                              )
                            )
                          )
                        )
                      ),
                      
                      # Floating right sidebar for canvas actions
                      div(
                        id = "canvas_sidebar",
                        class = "canvas-sidebar collapsed",
                        
                        # Toggle button
                        tags$button(
                          id = "sidebar_toggle",
                          class = "sidebar-toggle",
                          onclick = "toggleCanvasSidebar()",
                          icon("chevron-left"),
                          title = "Canvas Actions"
                        ),
                        
                        # Sidebar content
                        div(
                          class = "sidebar-content",
                          
                          # Zoom Controls Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("search"), " Zoom"),
                            div(class = "icon-button-group",
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.zoomIn();",
                                class = "btn btn-default btn-icon",
                                icon("search-plus"),
                                title = "Zoom In"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.zoomOut();",
                                class = "btn btn-default btn-icon",
                                icon("search-minus"),
                                title = "Zoom Out"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.resetZoom();",
                                class = "btn btn-default btn-icon",
                                icon("home"),
                                title = "Reset View"
                              )
                            )
                          ),
                          
                          # Component Actions Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("cogs"), " Actions"),
                            div(class = "icon-button-group",
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.toggleBoxSelect();",
                                id = "box_select_btn",
                                class = "btn btn-default btn-icon",
                                icon("object-group"),
                                title = "Box Select (Ctrl+B)"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.deleteSelected();",
                                class = "btn btn-danger btn-icon",
                                icon("trash"),
                                title = "Delete (Del)"
                              )
                            ),
                            div(class = "icon-button-group",
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.copy();",
                                id = "copy_btn",
                                class = "btn btn-default btn-icon",
                                icon("copy"),
                                title = "Copy (Ctrl+C)"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.cut();",
                                id = "cut_btn",
                                class = "btn btn-default btn-icon",
                                icon("cut"),
                                title = "Cut (Ctrl+X)"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.paste();",
                                id = "paste_btn",
                                class = "btn btn-default btn-icon",
                                icon("paste"),
                                title = "Paste (Ctrl+V)"
                              )
                            ),
                            div(class = "icon-button-group",
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.undo();",
                                id = "lineup_undo",
                                class = "btn btn-default btn-icon",
                                icon("undo"),
                                title = "Undo (Ctrl+Z)"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.redo();",
                                id = "lineup_redo",
                                class = "btn btn-default btn-icon",
                                icon("redo"),
                                title = "Redo (Ctrl+Y)"
                              )
                            ),
                            # Guide Lines Section
                            div(class = "sidebar-section-title", icon("grip-lines"), " Guide Lines"),
                            div(class = "icon-button-group",
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.toggleHorizontalLine();",
                                id = "toggle_horizontal_line",
                                class = "btn btn-success btn-icon",
                                style = "background-color: #28a745; color: #fff;",
                                icon("minus"),
                                title = "Horizontal Line"
                              ),
                              tags$button(
                                onclick = "if(window.paCanvas) paCanvas.toggleVerticalLine();",
                                id = "toggle_vertical_line",
                                class = "btn btn-success btn-icon",
                                style = "background-color: #28a745; color: #fff;",
                                HTML("|"),
                                title = "Vertical Line"
                              )
                            ),
                            tags$button(
                              onclick = "if(window.paCanvas) paCanvas.clear();",
                              class = "btn btn-warning btn-block btn-sm",
                              icon("eraser"),
                              " Clear All"
                            )
                          ),
                          
                          # File Actions Section
                          div(
                            class = "sidebar-section",
                            div(class = "sidebar-section-title", icon("file"), " File"),
                            actionButton("lineup_save_config", "Save", icon = icon("save"), class = "btn-success btn-block btn-sm"),
                            actionButton("lineup_load_config", "Load", icon = icon("folder-open"), class = "btn-default btn-block btn-sm"),
                            actionButton("lineup_export_diagram", "Export", icon = icon("image"), class = "btn-default btn-block btn-sm"),
                            actionButton("lineup_generate_report", "Report", icon = icon("file-pdf"), class = "btn-default btn-block btn-sm")
                          ),
                          
                          # Canvas Naming (only shown in multi-canvas mode)
                          conditionalPanel(
                            condition = "input.canvas_layout != '1x1'",
                            div(
                              class = "sidebar-section",
                              div(class = "sidebar-section-title", icon("tag"), " Canvas Names"),
                              actionButton("edit_canvas_names", 
                                "Edit Names", 
                                icon = icon("edit"), 
                                class = "btn-default btn-block btn-sm")
                            )
                          ),
                          
                          # Template Actions Section (only shown in single canvas mode)
                          conditionalPanel(
                            condition = "input.canvas_layout == '1x1'",
                            div(
                              class = "sidebar-section",
                              div(class = "sidebar-section-title", icon("bookmark"), " Save as Template"),
                              textInput("template_name", 
                                label = NULL, 
                                placeholder = "Template name...",
                                width = "100%"),
                              actionButton("save_as_template", 
                                "Save Template", 
                                icon = icon("bookmark"), 
                                class = "btn-info btn-block btn-sm",
                                onclick = "saveCurrentAsTemplate();")
                            ),
                            div(
                              class = "sidebar-section",
                              style = "margin-top: 10px;",
                              div(class = "sidebar-section-title", icon("list"), " Manage Templates"),
                              uiOutput("user_templates_manager")
                            )
                          )
                        )
                      ),
                      
                      # Floating lower sidebar for display options
                      div(
                        id = "canvas_lower_sidebar",
                        class = "canvas-lower-sidebar",
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.togglePowerDisplay();",
                          id = "power_display_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 140px;",
                          icon("bolt"),
                          " Power Display"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.togglePowerUnit();",
                          id = "power_unit_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 120px;",
                          icon("ruler"),
                          " Unit: dBm"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.toggleImpedanceDisplay();",
                          id = "impedance_display_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 160px;",
                          icon("infinity"),
                          " Impedance Display"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.toggleGainDisplay();",
                          id = "gain_display_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 140px;",
                          icon("chart-line"),
                          " Gain Display"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.togglePAEDisplay();",
                          id = "pae_display_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 140px;",
                          icon("percentage"),
                          " PAE Display"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.togglePhaseDisplay();",
                          id = "phase_display_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 150px;",
                          icon("rotate"),
                          " Phase Display"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvas) paCanvas.toggleCalculationRationale();",
                          id = "calculation_rationale_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 180px;",
                          icon("calculator"),
                          " Calculation Details"
                        ),
                        
                        tags$button(
                          onclick = "if(window.paCanvases && window.paCanvases.length > 1) window.toggleCanvasComparison(); else alert('Comparison requires multiple canvases');",
                          id = "canvas_comparison_toggle",
                          class = "btn btn-default btn-sm",
                          style = "min-width: 180px;",
                          icon("table"),
                          " Canvas Comparison"
                        )
                      )
                    )
                  )
                ),
                
                # Right: Component Properties & Results
                column(3, id = "right-panel-col",
                  # Line-up Specifications Box — tabset matrix layout
                  box(
                    title = tagList(icon("clipboard-list"), "Line-up Specifications"),
                    width = 12,
                    status = "info",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,

                    # Inline legend
                    div(style = "display:flex; gap:16px; margin-bottom:8px; font-size:11px;",
                      tags$span(style = "color:#ff851b; font-weight:600;", "⚡ Primary"),
                      tags$span(style = "color:var(--tx-med);", "○ Secondary"),
                      tags$span(style = "color:#5bc0de; font-style:italic;", "← Derived (read-only)")
                    ),

                    tabsetPanel(
                      id = "spec_tabs",

                      # ── Tab 1: Power & Frequency ─────────────────────────
                      tabPanel(
                        title = tagList(icon("bolt"), "Power & Freq"),
                        value = "tab_power_freq",
                        br(),
                        # PRIMARY
                        tags$p(tags$strong("⚡ Primary", style = "color:#ff851b;"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase; letter-spacing:.05em;"),
                        div(class = "input-highlight",
                          numericInput("spec_frequency",
                            tags$strong("⚡ Center Frequency (MHz)", style = "color:#ff851b;"),
                            value = 1805, min = 100, max = 10000, step = 1)
                        ),
                        fluidRow(
                          column(6,
                            div(class = "input-highlight",
                              numericInput("spec_p3db",
                                tags$strong("⚡ Pout (dBm)", style = "color:#ff851b;"),
                                value = 55.3, min = 0, max = 80, step = 0.1)
                            )
                          ),
                          column(6,
                            div(class = "input-highlight",
                              selectInput("spec_compression_point",
                                tags$strong("⚡ Pout = P(X)dB", style = "color:#ff851b;"),
                                choices = c("P1dB" = 1, "P2dB" = 2, "P3dB" = 3, "P5dB" = 5),
                                selected = 3, width = "100%")
                            )
                          )
                        ),
                        div(style = "background:rgba(255,183,77,.10); border-left:3px solid #ff851b; padding:5px 8px; border-radius:3px; margin-bottom:8px; font-size:11px; color:var(--tx-med);",
                          icon("info-circle"), " Pout is the output power at the selected compression point. ",
                          tags$em("All cascade calculations use this as the operating Pout.")
                        ),
                        fluidRow(
                          column(6,
                            div(class = "input-highlight",
                              numericInput("spec_par",
                                tags$strong("⚡ PAR / BO (dB)", style = "color:#ff851b;"),
                                value = 8.0, min = 0, max = 20, step = 0.1)
                            )
                          )
                        ),
                        # Derived row
                        fluidRow(
                          column(6,
                            div(style = "background:rgba(91,192,222,.08); border-left:3px solid #5bc0de; padding:6px 8px; border-radius:3px; margin-bottom:8px;",
                              tags$label("← Pavg (dBm)", style = "font-size:10px; color:#5bc0de; display:block; margin:0;"),
                              strong(textOutput("spec_pavg_display", inline = TRUE),
                                     style = "color:#5bc0de; font-size:13px;"),
                              tags$span(" = P3dB − PAR", style = "font-size:10px; color:var(--tx-med);")
                            )
                          ),
                          column(6,
                            div(style = "background:rgba(150,150,150,.08); border-left:3px solid #888; padding:6px 8px; border-radius:3px; margin-bottom:8px;",
                              tags$label("← Pin (dBm, back-calc)", style = "font-size:10px; color:#888; display:block; margin:0;"),
                              strong(textOutput("spec_pin_display", inline = TRUE),
                                     style = "color:#aaa; font-size:13px;"),
                              tags$span(" = P3dB − Gain", style = "font-size:10px; color:var(--tx-med);")
                            )
                          )
                        ),
                        hr(style = "margin:6px 0;"),
                        # SECONDARY
                        tags$p(tags$span("○ Secondary — Bandwidth & Supply", style = "color:var(--tx-med);"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase;"),
                        fluidRow(
                          column(6,
                            numericInput("spec_bw_lower", "BW Lower (%)", value = 10, min = 0, max = 50, step = 1)
                          ),
                          column(6,
                            numericInput("spec_bw_upper", "BW Upper (%)", value = 10, min = 0, max = 50, step = 1)
                          )
                        ),
                        fluidRow(
                          column(6,
                            div(style = "background:rgba(91,192,222,.08); border-left:3px solid #5bc0de; padding:6px 8px; border-radius:3px; margin-bottom:8px;",
                              tags$label("← Bandwidth (MHz)", style = "font-size:10px; color:#5bc0de; display:block; margin:0;"),
                              strong(textOutput("spec_bandwidth_display", inline = TRUE),
                                     style = "color:#5bc0de; font-size:13px;")
                            )
                          ),
                          column(6,
                            numericInput("spec_supply_voltage", "Vdd (V)", value = 30, min = 5, max = 50, step = 1)
                          )
                        )
                      ), # end tab Power & Freq

                      # ── Tab 2: Gain & Efficiency ─────────────────────────
                      tabPanel(
                        title = tagList(icon("tachometer-alt"), "Gain & Eff"),
                        value = "tab_gain_eff",
                        br(),
                        tags$p(tags$strong("⚡ Primary", style = "color:#ff851b;"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase;"),
                        div(class = "input-highlight",
                          numericInput("spec_gain",
                            tags$strong("⚡ Total Gain (dB)", style = "color:#ff851b;"),
                            value = 41.5, min = 0, max = 80, step = 0.1)
                        ),
                        div(class = "input-highlight",
                          numericInput("spec_pae",
                            tags$strong("⚡ System PAE Target (%)", style = "color:#ff851b;"),
                            value = 47, min = 1, max = 100, step = 1)
                        ),
                        hr(style = "margin:6px 0;"),
                        tags$p(tags$span("○ Secondary — Gain Flatness", style = "color:var(--tx-med);"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase;"),
                        fluidRow(
                          column(6,
                            numericInput("spec_gain_ripple_inband",
                              "Gain Ripple In-band (dB)", value = 1.0, min = 0, max = 10, step = 0.1)
                          ),
                          column(6,
                            numericInput("spec_gain_ripple_3xband",
                              "Gain Ripple 3× Band (dB)", value = 3.0, min = 0, max = 10, step = 0.1)
                          )
                        )
                      ), # end tab Gain & Eff

                      # ── Tab 3: Linearity ──────────────────────────────────
                      tabPanel(
                        title = tagList(icon("wave-square"), "Linearity"),
                        value = "tab_linearity",
                        br(),
                        tags$p(tags$strong("⚡ Primary", style = "color:#ff851b;"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase;"),
                        fluidRow(
                          column(6,
                            div(class = "input-highlight",
                              numericInput("spec_am_pm_p3db",
                                tags$strong("⚡ AM-PM @ P3dB (°)", style = "color:#ff851b;"),
                                value = -25, min = -50, max = 50, step = 0.1)
                            )
                          ),
                          column(6,
                            div(class = "input-highlight",
                              numericInput("spec_acp",
                                tags$strong("⚡ ACP (dBc)", style = "color:#ff851b;"),
                                value = -30, min = -80, max = 0, step = 0.1)
                            )
                          )
                        ),
                        hr(style = "margin:6px 0;"),
                        tags$p(tags$span("○ Secondary — Distortion detail", style = "color:var(--tx-med);"),
                               style = "margin:0 0 4px; font-size:11px; text-transform:uppercase;"),
                        fluidRow(
                          column(6,
                            numericInput("spec_am_pm_dispersion",
                              "AM-PM Dispersion (°)", value = 8, min = 0, max = 50, step = 0.1)
                          ),
                          column(6,
                            numericInput("spec_input_return_loss",
                              "Input RL (dB)", value = -15, min = -50, max = 0, step = 0.1)
                          )
                        ),
                        fluidRow(
                          column(6,
                            numericInput("spec_vbw",
                              "VBW (MHz)", value = 225, min = 1, max = 1000, step = 1)
                          ),
                          column(6,
                            numericInput("spec_group_delay",
                              "Group Delay Flat. (ns)", value = 1, min = 0, max = 100, step = 0.1)
                          )
                        )
                      ), # end tab Linearity

                      # ── Tab 4: Conditions ────────────────────────────────
                      tabPanel(
                        title = tagList(icon("cog"), "Conditions"),
                        value = "tab_conditions",
                        br(),
                        selectInput("spec_test_conditions", "Test Conditions",
                          choices = c(
                            "DC" = "dc",
                            "CW" = "cw",
                            "NVA Sweep 25ms" = "nva_25ms",
                            "Nokia LTE 1c 10MHz" = "nokia_lte",
                            "Low Freq Resonance" = "low_freq_res"
                          ),
                          selected = "cw"
                        ),
                        helpText(icon("info-circle"), " Test condition affects linearity and efficiency budgets.")
                      ) # end tab Conditions

                    ), # end tabsetPanel

                    hr(),
                    div(style = "display: flex; gap: 10px; margin-top: 8px;",
                      actionButton("apply_specs_to_lineup",
                                   "Apply Specs to Lineup ↓",
                                   class = "btn-primary btn-block",
                                   icon = icon("arrow-down"),
                                   style = "flex: 1;"),
                      actionButton("apply_specs_to_global",
                                   "Update Global Params",
                                   class = "btn-info",
                                   icon = icon("sync"),
                                   style = "flex: 1;")
                    ),
                    helpText(icon("lightbulb"), " 'Apply to Lineup' adapts all components to specs. 'Update Global' only syncs freq/power.")
                  ),
                  
                  # Global Lineup Parameters
                  box(
                    title = tagList(icon("globe"), "Global Lineup Parameters"),
                    width = 12,
                    status = "primary",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,
                    fluidRow(
                      column(6,
                        numericInput("global_frequency", "Frequency (GHz)", 
                          value = 2.6, min = 0.1, max = 100, step = 0.1)
                      ),
                      column(6,
                        numericInput("global_pout_p3db", tags$strong("Pout (dBm)"), 
                          value = 55.3, min = 0, max = 80, step = 0.1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        selectInput("global_compression_point", "Pout = P(X)dB",
                          choices = c("P1dB" = 1, "P2dB" = 2, "P3dB" = 3, "P5dB" = 5),
                          selected = 3, width = "100%")
                      ),
                      column(6,
                        numericInput("global_backoff", "Back-off (dB)", 
                          value = 6, min = 0, max = 20, step = 0.5)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("global_PAR", "PAR (dB)", 
                          value = 8, min = 0, max = 15, step = 0.5)
                      )
                    ),
                    fluidRow(
                      column(6,
                        div(style = "margin-top: 25px;",
                          strong("Pavg (dBm):"),
                          textOutput("calculated_Pavg", inline = TRUE)
                        )
                      ),
                      column(6,
                        div(style = "margin-top: 25px;",
                          strong("Pin (dBm):"),
                          textOutput("calculated_Pin_global", inline = TRUE),
                          tags$span(" (from specs)", style = "color: var(--tx-med); font-size: 12px;")
                        )
                      )
                    ),
                    helpText(icon("info-circle"), " These parameters apply to the entire lineup. Pout(P3dB) typically derived from Specifications.")
                  ),
                  
                  # Canvas Layout Selector
                  box(
                    title = tagList(icon("th"), "Canvas Layout"),
                    width = 12,
                    status = "info",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,
                    
                    p("Compare multiple architectures side-by-side:"),
                    
                    selectInput("canvas_layout", "Layout Configuration",
                      choices = c(
                        "Single Canvas (1x1)" = "1x1",
                        "Horizontal Split (1x2)" = "1x2",
                        "Vertical Split (2x1)" = "2x1",
                        "Quad Split (2x2)" = "2x2",
                        "2x3 Grid" = "2x3",
                        "3x2 Grid" = "3x2",
                        "Horizontal Triple (1x3)" = "1x3",
                        "Horizontal Quad (1x4)" = "1x4",
                        "Vertical Quad (4x1)" = "4x1",
                        "3x3 Grid" = "3x3",
                        "4x2 Grid" = "4x2",
                        "2x4 Grid" = "2x4",
                        "2+1 Layout (1 large + 2 small)" = "2+1",
                        "1+2 Layout (2 small + 1 large)" = "1+2"
                      ),
                      selected = "1x1"
                    ),
                    
                    helpText(icon("info-circle"), " Active canvas follows cursor. Each canvas has independent components but shares global parameters."),
                    
                    div(id = "canvas_labels", style = "margin-top: 10px;")
                  ),
                  
                  # Component Property Editor
                  div(id = "panel_comp_props",
                    box(
                      title = "Component Properties",
                      width = 12,
                      collapsible = TRUE,
                      collapsed = TRUE,
                      status = "warning",
                      solidHeader = TRUE,
                      uiOutput("lineup_property_editor")
                    )
                  ),
                  
                  # Calculation Results
                  box(
                    title = "Calculation Results",
                    width = 12,
                    status = "success",
                    solidHeader = TRUE,
                    div(style = "display: flex; gap: 10px; align-items: center; margin-bottom: 10px;",
                      div(style = "flex: 1;",
                        actionButton("lineup_calculate", "Calculate Lineup", class = "btn-success btn-block", icon = icon("calculator"))
                      ),
                      div(style = "flex: 0 0 180px;",
                        numericInput("backoff_db", "Backoff (dB):", value = 6, min = 0, max = 20, step = 0.5, width = "100%")
                      )
                    ),
                    # Optimize button moved to Architecture tab (see ARCHITECTURE tab)
                    # Multi-canvas comparison button (only show in multi-canvas mode)
                    conditionalPanel(
                      condition = "input.canvas_layout != '1x1'",
                      actionButton("lineup_calculate_all", "Calculate All Canvases", 
                                   class = "btn-info btn-block", 
                                   icon = icon("layer-group"),
                                   style = "margin-bottom: 10px;")
                    ),
                    hr(),
                    tabsetPanel(
                      id = "calc_results_tabs",
                      tabPanel(
                        title = "Current Canvas",
                        value = "current_results",
                        icon = icon("chart-line"),
                        br(),
                        uiOutput("lineup_calc_results")
                      ),
                      tabPanel(
                        title = "Comparison",
                        value = "comparison_results",
                        icon = icon("table"),
                        br(),
                        uiOutput("lineup_comparison_results")
                      )
                    )
                  ),
                  
                  # Version Control
                  box(
                    title = "Version Control",
                    width = 12,
                    status = "primary",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,
                    textInput("lineup_version_name", "Version Name", placeholder = "v1.0"),
                    textAreaInput("lineup_version_notes", "Notes", placeholder = "Description of changes...", rows = 3),
                    actionButton("lineup_save_version", "Save as New Version", class = "btn-primary btn-block", icon = icon("code-branch")),
                    hr(),
                    uiOutput("lineup_version_list")
                  )
                )
              ),
              
              # View Tabs Below Canvas
              fluidRow(
                tabBox(
                  width = 12,
                  
                  # Table View
                  tabPanel(
                    title = tagList(icon("table"), "Table View"),
                    # Single-canvas: DTOutput is always in the DOM (conditionalPanel
                    # uses CSS show/hide, not DOM insertion) so DataTables can
                    # initialise correctly regardless of layout switches.
                    conditionalPanel(
                      condition = "input.canvas_layout == null || input.canvas_layout == '1x1'",
                      DTOutput("pa_lineup_table")
                    ),
                    # Multi-canvas: server builds one tab per canvas
                    conditionalPanel(
                      condition = "input.canvas_layout != null && input.canvas_layout != '1x1'",
                      uiOutput("pa_lineup_tables_dynamic")
                    )
                  ),
                  
                  # Equations View
                  tabPanel(
                    title = tagList(icon("calculator"), "Equations & Rationale"),
                    uiOutput("pa_lineup_equations_dynamic")
                  )
                )
              )
      ),  # closes tabItem(dev_architecture)

      # ── 4.3 Interstage & Passives stub ────────────────────────────────────
      # (dev_interstage stub is further below in the file)
      # ── 5.x Product Level stubs (prod_transistor, prod_pa_stage, prod_module) below ──

      # Placeholder tabs (to be implemented)
      # ── 1. First Principles (landing) ────────────────────────────────────────
      tabItem(tabName = "first_principles",
        h2(icon("atom"), " First Principles"),
        p("Select a sub-topic from the sidebar to explore atomic-level foundations of RF design."),
        fluidRow(
          lapply(
            list(
              list("fp_atoms",     "atom",             "1.1 Atoms & Charge",
                   "Electron/charge models, quantum basics, semiconductor fundamentals."),
              list("fp_em_waves",  "broadcast-tower",  "1.2 EM Wave Origin",
                   "Maxwell equations, EM field propagation mechanisms."),
              list("fp_materials", "cubes",            "1.3 RF Materials",
                   "Dielectrics, conductors, substrates and their RF constraints."),
              list("fp_tlines",    "project-diagram",  "1.4 Transmission Lines",
                   "TL theory, waveguides, return paths with simple worked examples."),
              list("fp_thermal",   "thermometer-half", "1.5 Thermal Effects",
                   "Temperature impact on GaN, LDMOS, GaAs, SiGe performance.")
            ),
            function(item) {
              column(4,
                box(
                  title = tagList(icon(item[[2]]), " ", item[[3]]),
                  width = 12, status = "primary", solidHeader = TRUE,
                  p(item[[4]]),
                  actionButton(paste0("goto_", item[[1]]), "Open",
                               class = "btn-sm btn-default",
                               onclick = paste0("Shiny.setInputValue(\'sidebar_menu\', \'",
                                                item[[1]], "\', {priority:\'event\'})"))
                )
              )
            }
          )
        )
      ),
      # 1.1 Atoms & Charge
      # 1.1 Atoms & Charge
      # 1.1 Atoms & Charge
      tabItem(tabName = "fp_atoms",
        h2(icon("atom"), " 1.1 Atoms, Electrons, Charge & Molecules"),
        tabsetPanel(
          tabPanel("Electron Model",
            h4("Bohr / Quantum Model"),
            p("Energy levels, electron shells, and ionisation energy underpin semiconductor doping and band-gap engineering."),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Parameter</th><th>Si</th><th>GaAs</th><th>GaN</th><th>SiGe</th></tr></thead>
              <tbody>
                <tr><td>Band gap (eV)</td><td>1.12</td><td>1.42</td><td>3.4</td><td>0.67–1.12</td></tr>
                <tr><td>Electron mobility (cm²/Vs)</td><td>1400</td><td>8500</td><td>1500 (2DEG ~2000)</td><td>~1000</td></tr>
                <tr><td>Breakdown field (MV/cm)</td><td>0.3</td><td>0.4</td><td>3.3</td><td>0.3</td></tr>
              </tbody></table>"),
            p(class="text-muted", "Interactive periodic-table explorer — coming soon.")
          ),
          tabPanel("Semiconductor Fundamentals",
            h4("Doping, Carrier Concentration, pn-Junctions"),
            p("N-type and P-type doping create the charge carriers exploited in FETs and BJTs."),
            wellPanel(
              h5("Key relationships"),
              HTML("<ul>
                <li>Intrinsic carrier density: n<sub>i</sub> = √(N<sub>c</sub>·N<sub>v</sub>) · exp(−E<sub>g</sub>/2kT)</li>
                <li>Depletion width: W<sub>d</sub> ∝ √(V<sub>bi</sub>/N<sub>d</sub>)</li>
                <li>Threshold voltage V<sub>t</sub> = V<sub>FB</sub> − Q<sub>dep</sub>/C<sub>ox</sub> − 2φ<sub>F</sub></li>
              </ul>")
            )
          ),
          tabPanel("HEMT 2DEG Physics",
            h4("Two-Dimensional Electron Gas"),
            p("In GaN/AlGaN HEMTs, spontaneous + piezoelectric polarisation creates a high-density 2DEG without doping — enabling GaN's outstanding Pout density."),
            wellPanel(
              HTML("<ul>
                <li>2DEG sheet charge density n<sub>s</sub> ~ 10¹³ cm⁻²</li>
                <li>Polarisation discontinuity ΔP = P<sub>sp,AlGaN</sub> + P<sub>pe,AlGaN</sub> − P<sub>sp,GaN</sub></li>
                <li>Conduction band offset ΔEc ≈ 0.7 eV for Al₀.₂₅Ga₀.₇₅N/GaN</li>
              </ul>")
            ),
            p(class="text-muted", "Simulation canvas — under construction.")
          )
        )
      ),


      # 1.2 EM Wave Origin
      # 1.2 EM Wave Origin
      # 1.2 EM Wave Origin
      tabItem(tabName = "fp_em_waves",
        h2(icon("broadcast-tower"), " 1.2 EM Wave Origin & Propagation"),
        tabsetPanel(
          tabPanel("Maxwell Equations",
            h4("Maxwell in Differential Form"),
            HTML("<div class='code-block'>
              ∇ × E = −∂B/∂t &nbsp;&nbsp;(Faraday)<br>
              ∇ × H = J + ∂D/∂t &nbsp;&nbsp;(Ampère-Maxwell)<br>
              ∇ · D = ρ_free &nbsp;&nbsp;(Gauss – electric)<br>
              ∇ · B = 0 &nbsp;&nbsp;(Gauss – magnetic)
            </div>"),
            p("Wave equation derived from the above: ∇²E = με ∂²E/∂t² → plane-wave speed v = 1/√(με).")
          ),
          tabPanel("Wave Propagation",
            h4("Plane Wave Parameters"),
            wellPanel(
              HTML("<ul>
                <li>Wavelength: λ = c / (f √ε<sub>r</sub>)</li>
                <li>Skin depth: δ = √(2ρ / ωμ) — sets conductor surface current concentration</li>
                <li>Wave impedance: η = √(μ/ε) — 377 Ω in free space, ~50 Ω in GaAs MMIC</li>
                <li>Phase velocity in dielectric: v<sub>p</sub> = c / √(ε<sub>r</sub> μ<sub>r</sub>)</li>
              </ul>")
            ),
            p(class="text-muted", "Interactive 2D propagation visualisation — under construction.")
          ),
          tabPanel("Near vs Far Field",
            h4("Reactive Near Field / Radiative Far Field"),
            p("At distances r < λ/2π from a radiating element, the reactive near-field energy dominates and the wave cannot propagate freely. PA output matching networks operate in this near-field regime."),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Zone</th><th>Distance</th><th>Relevance to PA design</th></tr></thead>
              <tbody>
                <tr><td>Reactive near field</td><td>r < λ/2π</td><td>Matching network, bond-wire inductance</td></tr>
                <tr><td>Radiating near field</td><td>λ/2π – 2D²/λ</td><td>Package, PCB edge coupling</td></tr>
                <tr><td>Far field</td><td>r > 2D²/λ</td><td>Antenna, OTA test</td></tr>
              </tbody></table>")
          )
        )
      ),


      # 1.3 RF Materials
      # 1.3 RF Materials
      # 1.3 RF Materials
      tabItem(tabName = "fp_materials",
        h2(icon("cubes"), " 1.3 RF Materials & Constraints"),
        tabsetPanel(
          tabPanel("Substrate Comparison",
            h4("Common RF Substrate Properties"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Material</th><th>ε<sub>r</sub></th><th>tan δ</th><th>Thermal (W/mK)</th><th>Notes</th></tr></thead>
              <tbody>
                <tr><td>Rogers RO4003C</td><td>3.55</td><td>0.0027</td><td>0.71</td><td>Low-loss PCB, mmWave capable</td></tr>
                <tr><td>GaN on SiC</td><td>9.7</td><td>~0</td><td>490</td><td>Best thermal for power GaN</td></tr>
                <tr><td>GaAs</td><td>12.9</td><td>~0</td><td>46</td><td>Standard III-V MMIC substrate</td></tr>
                <tr><td>Si (bulk)</td><td>11.7</td><td>high</td><td>148</td><td>Lossy at RF — avoid hi-Q passives</td></tr>
                <tr><td>SiO₂ (oxide)</td><td>3.9</td><td>low</td><td>1.4</td><td>Back-end dielectric, low thermal</td></tr>
              </tbody></table>")
          ),
          tabPanel("Conductor Losses",
            h4("Skin Effect & Conductor Q"),
            p("At RF/mmWave, current crowds into the conductor surface within the skin depth δ = √(2ρ/ωμ), increasing effective resistance."),
            wellPanel(
              HTML("<ul>
                <li>R<sub>s</sub> = √(ρωμ/2) — surface resistance (Ω/□)</li>
                <li>Gold at 50 GHz: R<sub>s</sub> ≈ 0.055 Ω/□, δ ≈ 0.35 μm</li>
                <li>Copper at 50 GHz: R<sub>s</sub> ≈ 0.052 Ω/□, δ ≈ 0.37 μm</li>
                <li>Thick metals reduce series resistance; min 3–5× skin depths rule of thumb</li>
              </ul>")
            )
          ),
          tabPanel("Die Attach & Packaging",
            h4("Thermal Interface Materials"),
            p("Die-attach material controls θ_jc — the dominant thermal resistance for power PAs."),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Material</th><th>Thermal (W/mK)</th><th>Notes</th></tr></thead>
              <tbody>
                <tr><td>AuSn solder</td><td>57</td><td>Best for GaN on SiC, hermetic</td></tr>
                <tr><td>Ag epoxy</td><td>3–5</td><td>Low cost, lower performance</td></tr>
                <tr><td>Indium foil</td><td>84</td><td>Soft, good for lab evaluation</td></tr>
              </tbody></table>")
          )
        )
      ),


      # 1.4 Transmission Lines
      # 1.4 Transmission Lines
      # 1.4 Transmission Lines
      tabItem(tabName = "fp_tlines",
        h2(icon("project-diagram"), " 1.4 Transmission Lines, Waveguides & Return Paths"),
        tabsetPanel(
          tabPanel("TL Theory",
            h4("Telegrapher Equations"),
            wellPanel(
              HTML("<div class='code-block'>
                ∂V/∂x = −L′ ∂I/∂t − R′ I<br>
                ∂I/∂x = −C′ ∂V/∂t − G′ V<br><br>
                Characteristic impedance:  Z₀ = √((R′+jωL′)/(G′+jωC′))<br>
                Lossless:  Z₀ = √(L′/C′),  v<sub>p</sub> = 1/√(L′C′)
              </div>")
            ),
            p("Reflection coefficient Γ = (Z_L − Z₀)/(Z_L + Z₀); VSWR = (1+|Γ|)/(1−|Γ|).")
          ),
          tabPanel("Microstrip Design",
            h4("Microstrip — Width vs Z₀"),
            p("For a 50 Ω line on Rogers RO4003C (ε_r = 3.55, h = 0.813 mm): W ≈ 1.8 mm."),
            wellPanel(
              HTML("<ul>
                <li>Effective dielectric: ε<sub>eff</sub> = (ε<sub>r</sub>+1)/2 + (ε<sub>r</sub>−1)/2 · F(W/h)</li>
                <li>Guided wavelength: λ<sub>g</sub> = λ₀ / √ε<sub>eff</sub></li>
                <li>Quarter-wave transformer length: λ<sub>g</sub>/4 at centre frequency</li>
              </ul>")
            ),
            p(class="text-muted", "Microstrip calculator widget — under construction.")
          ),
          tabPanel("Return Paths",
            h4("Current Return Path & Ground Plane"),
            p("RF current returns via the path of least inductance, not least resistance. Slots, vias, and splits in the ground plane create uncontrolled impedance transitions."),
            div(class="callout callout-warning",
              HTML("<strong>PA layout rule of thumb:</strong> Place via-stitching within λ/20 of any RF trace to provide continuous ground return and suppress parallel-plate modes.")
            )
          ),
          tabPanel("Smith Chart",
            h4("Smith Chart Navigation"),
            p("The Smith Chart maps the complex reflection coefficient Γ on the unit circle. Constant |Γ| circles correspond to constant VSWR. Use it for:"),
            HTML("<ul>
              <li>Impedance transformation (series/shunt L, C)</li>
              <li>Stability circle overlay</li>
              <li>Load-pull contour display</li>
              <li>Matching network synthesis</li>
            </ul>"),
            actionButton("goto_smith_chart_fp", "Open Smith Chart Tool",
              class = "btn-primary",
              onclick = "Shiny.setInputValue('goto_utility_tab', 'smith_chart', {priority:'event'})")
          )
        )
      ),


      # 1.5 Thermal Effects
      # 1.5 Thermal Effects
      # 1.5 Thermal Effects
      tabItem(tabName = "fp_thermal",
        h2(icon("thermometer-half"), " 1.5 Impact of Temperature on Technologies"),
        tabsetPanel(
          tabPanel("Thermal Resistance Network",
            h4("Junction → Ambient Thermal Chain"),
            HTML("<div class='code-block'>
              T<sub>j</sub> = T<sub>amb</sub> + P<sub>diss</sub> × (θ<sub>jc</sub> + θ<sub>cs</sub> + θ<sub>sa</sub>)<br><br>
              θ<sub>jc</sub>: die → case (dominated by die-attach and substrate)<br>
              θ<sub>cs</sub>: case → heatsink (TIM layer)<br>
              θ<sub>sa</sub>: heatsink → ambient
            </div>"),
            p("For GaN on SiC: θ_jc ≈ 0.5–2 K/W per mm² gate periphery — best in class.")
          ),
          tabPanel("Technology Temperature Coefficients",
            h4("How Temperature Shifts Key Parameters"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Parameter</th><th>GaN</th><th>LDMOS</th><th>GaAs pHEMT</th></tr></thead>
              <tbody>
                <tr><td>I<sub>dss</sub> vs T</td><td>−0.15%/°C</td><td>−0.4%/°C</td><td>−0.2%/°C</td></tr>
                <tr><td>V<sub>t</sub> vs T</td><td>+1 mV/°C</td><td>+2 mV/°C</td><td>+1 mV/°C</td></tr>
                <tr><td>Gain vs T</td><td>−0.05 dB/°C</td><td>−0.1 dB/°C</td><td>−0.08 dB/°C</td></tr>
                <tr><td>fT vs T</td><td>−0.1%/°C</td><td>−0.3%/°C</td><td>−0.2%/°C</td></tr>
              </tbody></table>")
          ),
          tabPanel("Reliability & MTTF",
            h4("Temperature-Accelerated Lifetime (Arrhenius)"),
            wellPanel(
              HTML("<div class='code-block'>
                MTTF = A · exp(E<sub>a</sub> / k<sub>B</sub> T<sub>j</sub>)<br>
                Acceleration factor AF = exp(E<sub>a</sub>/k<sub>B</sub> · (1/T<sub>use</sub> − 1/T<sub>test</sub>))<br><br>
                Typical E<sub>a</sub>: GaN = 1.8 eV, GaAs = 1.6 eV, LDMOS = 1.0 eV
              </div>")
            ),
            p("Rule of thumb: every 10 °C rise doubles the failure rate (E_a ~ 0.7 eV equivalent)."),
            actionButton("goto_reliability_fp", "Open Reliability Calculator (5.4)",
              class = "btn-primary",
              onclick = "Shiny.setInputValue('sidebar_menu', 'prod_reliability', {priority:'event'})")
          )
        )
      ),


      
      # dev_architecture now defined above (canvas block)
      
      # ── System-level stubs ────────────────────────────────────────────────────
      tabItem(tabName = "system_level",
        h2(icon("network-wired"), " 2 · System Level"),
        p("Select a sub-topic from the sidebar.")
      ),
      tabItem(tabName = "sys_tx_arch",
        h2(icon("broadcast-tower"), " 2.2 TX Architectures"),
        tabsetPanel(
          tabPanel("Architecture Types",
            h4("Common TX Chain Topologies"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Architecture</th><th>Complexity</th><th>PAE</th><th>Linearity</th><th>Typical Use</th></tr></thead>
              <tbody>
                <tr><td>Direct conversion (homodyne)</td><td>Low</td><td>High</td><td>DC offset sensitive</td><td>5G NR, Wi-Fi</td></tr>
                <tr><td>Superheterodyne</td><td>Medium</td><td>Medium</td><td>Excellent</td><td>Microwave backhaul</td></tr>
                <tr><td>Direct digital (RFDAC)</td><td>High</td><td>Power-hungry DAC</td><td>Very good</td><td>Massive MIMO</td></tr>
                <tr><td>Polar TX</td><td>High</td><td>Best PA efficiency</td><td>Bandwidth limited</td><td>Handset PA</td></tr>
              </tbody></table>")
          ),
          tabPanel("PA Position & Gain Budget",
            h4("TX Signal Chain Gain Budget"),
            p("Define the gain and power at each stage from baseband to antenna:"),
            wellPanel(
              HTML("<ul>
                <li>Baseband → DAC: digital scale sets TX power headroom</li>
                <li>Up-converter / Mixer: conversion loss −6 to −8 dB typical</li>
                <li>Pre-driver / Driver: +20–25 dB gain, sets P1dB headroom for PA</li>
                <li>PA final stage: target P_sat (module-level)</li>
                <li>Filter + duplexer: −2 to −3 dB before antenna</li>
              </ul>")
            ),
            p(class="text-muted", "TX gain budget calculator — under construction.")
          ),
          tabPanel("Linearisation",
            h4("DPD & Pre-distortion Techniques"),
            p("Modern wideband signals (100–400 MHz) require digital pre-distortion (DPD) to meet ACLR/EVM specs with Class AB or Doherty PAs."),
            HTML("<ul>
              <li>Memory polynomial DPD: models AM/AM, AM/PM and memory effects</li>
              <li>Bandwidth expansion: DPD signal BW = 3–5× modulation BW</li>
              <li>Observation receiver needed for closed-loop adaptation</li>
            </ul>")
          )
        )
      ),


      tabItem(tabName = "sys_rx_arch",
        h2(icon("satellite-dish"), " 2.3 RX Architectures"),
        tabsetPanel(
          tabPanel("Noise Figure Chain",
            h4("Friis Formula — Cascaded NF"),
            wellPanel(
              HTML("<div class='code-block'>
                NF<sub>total</sub> = NF₁ + (NF₂−1)/G₁ + (NF₃−1)/(G₁G₂) + ...<br>
                F<sub>total</sub> = F₁ + (F₂−1)/G₁ + (F₃−1)/(G₁G₂) + ...
              </div>")
            ),
            p("First stage NF dominates — LNA design governs system sensitivity. Minimum detectable signal MDS = −174 + NF + 10·log(BW) dBm.")
          ),
          tabPanel("IP3 & Dynamic Range",
            h4("IIP3 Cascade & SFDR"),
            wellPanel(
              HTML("<div class='code-block'>
                1/IIP3<sub>total</sub> ≈ 1/IIP3₁ + G₁/IIP3₂ + G₁G₂/IIP3₃ + ...<br>
                SFDR = (2/3)(IIP3 − NF − 10·log(BW)) dB·Hz<sup>2/3</sup>
              </div>")
            ),
            p("Trade-off: increasing LNA gain improves NF but reduces IIP3; attenuators before LNA improve IIP3 at the cost of NF.")
          ),
          tabPanel("RX Topologies",
            h4("Direct Conversion vs Superheterodyne"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Issue</th><th>Direct Conv.</th><th>Superhet</th></tr></thead>
              <tbody>
                <tr><td>DC offset</td><td>Critical</td><td>Not an issue</td></tr>
                <tr><td>IQ mismatch</td><td>Critical</td><td>Moderate</td></tr>
                <tr><td>Image rejection</td><td>Requires DSP</td><td>Image reject filter</td></tr>
                <tr><td>Integration level</td><td>High (single chip)</td><td>Lower</td></tr>
              </tbody></table>")
          )
        )
      ),


      tabItem(tabName = "sys_architecture",
        h2(icon("network-wired"), " 2.5 System Architecture"),
        tabsetPanel(
          tabPanel("Block Diagram Canvas",
            h4("System Signal Chain — Block Diagram"),
            div(class="callout callout-info",
              p(icon("info-circle"), " Interactive canvas coming. For now, document your system architecture in the fields below.")
            ),
            wellPanel(
              h5("Architecture Description"),
              textAreaInput("sys_arch_description", NULL,
                value = "",
                placeholder = "Describe your TX/RX chain topology, key partitioning decisions, frequency plan...",
                width = "100%", height = "120px"),
              fluidRow(
                column(4, numericInput("sys_arch_freq_ghz",  "Center Frequency (GHz)", value = 3.5, min = 0.1, max = 300, step = 0.5)),
                column(4, numericInput("sys_arch_bw_mhz",   "Channel BW (MHz)",       value = 100, min = 1,   max = 2000, step = 10)),
                column(4, numericInput("sys_arch_pout_dbm",  "System P_out (dBm)",     value = 43,  min = 0,   max = 70,   step = 1))
              )
            )
          ),
          tabPanel("Partitioning",
            h4("PA Module Partitioning"),
            p("Define what is integrated vs discrete:"),
            HTML("<ul>
              <li>MMIC die vs board-level implementation</li>
              <li>Number of PA stages (driver chain depth)</li>
              <li>Bias circuit integration (on-chip vs off-chip PMIC)</li>
              <li>Duplexer / diplexer placement</li>
              <li>DPD / DSP processing location (baseband vs near-antenna)</li>
            </ul>"),
            p(class="text-muted", "Partitioning decision tree — under construction.")
          ),
          tabPanel("Spec Allocation",
            h4("System → Subsystem Spec Allocation"),
            p("Allocate the system EVM, ACLR, P_out, and gain budget between subsystems:"),
            wellPanel(
              HTML("<table class='table table-sm'>
                <thead><tr><th>Subsystem</th><th>Gain (dB)</th><th>NF (dB)</th><th>IIP3 (dBm)</th><th>P_sat (dBm)</th></tr></thead>
                <tbody>
                  <tr><td>IQ Mod / DAC</td><td>0</td><td>—</td><td>+20</td><td>+10</td></tr>
                  <tr><td>Up-converter</td><td>−7</td><td>—</td><td>+15</td><td>+8</td></tr>
                  <tr><td>Driver PA</td><td>+25</td><td>—</td><td>+30</td><td>+28</td></tr>
                  <tr><td>Final PA</td><td>+12</td><td>—</td><td>+48</td><td>+46</td></tr>
                  <tr><td>Filter + switch</td><td>−2</td><td>—</td><td>—</td><td>—</td></tr>
                </tbody></table>"),
              p(class="text-muted", "Editable allocation table — under construction.")
            )
          )
        )
      ),



      # ── Technology-level stubs ────────────────────────────────────────────────
      tabItem(tabName = "tech_level",
        h2(icon("microchip"), " 3 · Technology Level"),
        p("Select a sub-topic from the sidebar.")
      ),
      tabItem(tabName = "tech_selection",
        h2(icon("microchip"), " 3.1 Technology Selection"),
        p("Choose the right transistor technology for your operating frequency.
           The selection rules, fT/fmax plots and design guidelines below are
           transferred from the Frequency Planning tool (2.1).
"),
                tabsetPanel(
          id = "freq_tech_tabs",
          type = "tabs",
          
          # Tab 1: Technology Selection Guide
          tabPanel(
            title = tagList(icon("microchip"), "Technology Selection"),
            value = "tech_select",
            
            br(),
            h4(icon("info-circle"), " Transition Frequency (fT) and Maximum Oscillation Frequency (fmax)"),
            p("For selecting the appropriate transistor technology based on operating frequency:"),
            
            HTML("
              <div class='callout callout-info' style='margin: 10px 0;'>
                <h5><i class='fa fa-info-circle'></i> Selection Rule of Thumb</h5>
                <p><strong>For operating frequency fop, select technology with: fT > 5 × fop</strong></p>
                <p style='font-size: 13px;'>This ensures sufficient gain and prevents instability at the design frequency.</p>
              </div>
              
              <h5 style='margin-top: 20px;'>Technology Comparison</h5>
              <table class='table table-striped table-sm'>
                <thead>
                  <tr>
                    <th>Technology</th>
                    <th>fT Range</th>
                    <th>fmax Range</th>
                    <th>Recommended Frequency</th>
                    <th>Key Applications</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><strong>Si LDMOS</strong></td>
                    <td>20-40 GHz</td>
                    <td>30-60 GHz</td>
                    <td>< 4 GHz</td>
                    <td>Base stations, high power</td>
                  </tr>
                  <tr>
                    <td><strong>GaAs pHEMT</strong></td>
                    <td>30-60 GHz</td>
                    <td>80-150 GHz</td>
                    <td>2-12 GHz</td>
                    <td>Microwave, mmWave</td>
                  </tr>
                  <tr>
                    <td><strong>GaN HEMT</strong></td>
                    <td>50-100 GHz</td>
                    <td>150-300 GHz</td>
                    <td>2-40 GHz</td>
                    <td>5G, radar, satellite</td>
                  </tr>
                  <tr>
                    <td><strong>SiGe HBT</strong></td>
                    <td>200-300 GHz</td>
                    <td>400-500 GHz</td>
                    <td>20-100 GHz</td>
                    <td>mmWave, sub-THz</td>
                  </tr>
                  <tr>
                    <td><strong>InP HEMT</strong></td>
                    <td>300-600 GHz</td>
                    <td>600-1000 GHz</td>
                    <td>60-300 GHz</td>
                    <td>Sub-THz, 6G research</td>
                  </tr>
                </tbody>
              </table>
            "),
            
            # Dynamic recommendation
            uiOutput("technology_fT_recommendation")
          ),
          
          # Tab 2: fT/fmax Plots
          tabPanel(
            title = tagList(icon("chart-line"), "fT/fmax Plots"),
            value = "ft_fmax_plots",
            
            br(),
            h4(icon("chart-area"), " Transistor Frequency Performance"),
            
            HTML("
              <div class='callout callout-warn' style='margin: 10px 0;'>
                <h5><i class='fa fa-exclamation-triangle'></i> Note</h5>
                <p>Detailed fT and fmax plots with technology evolution trends are available in:</p>
                <p><strong><a href='../PA_Design_Reference_Manual/Chapters/Chapter_01_Transistor_Fundamentals.html#section-2-2' target='_blank'>
                  <i class='fa fa-external-link'></i> Chapter 1: Transistor Fundamentals - Section 2.2 (High-Frequency Parameters)
                </a></strong></p>
                <p style='margin-bottom: 0; font-size: 13px;'>Includes detailed figures showing fT and fmax evolution over time for different technologies.</p>
              </div>
              
              <h5 style='margin-top: 25px;'>Key Frequency Relationships:</h5>
              <div class='row' style='margin-top: 15px;'>
                <div class='col-md-6'>
                  <div class='callout callout-neutral' style='border-radius: 5px; height: 100%;'>
                    <h6><strong>Transition Frequency  (fT)</strong></h6>
                    <ul style='font-size: 14px;'>
                      <li>Frequency where current gain h<sub>21</sub> = 1 (0 dB)</li>
                      <li>Indicates amplification capability</li>
                      <li>Higher fT → Better high-frequency performance</li>
                      <li><strong>Formula:</strong> fT ≈ g<sub>m</sub> / (2πC<sub>gs</sub>)</li>
                    </ul>
                  </div>
                </div>
                <div class='col-md-6'>
                  <div class='callout callout-neutral' style='border-radius: 5px; height: 100%;'>
                    <h6><strong>Maximum Oscillation Frequency (fmax)</strong></h6>
                    <ul style='font-size: 14px;'>
                      <li>Frequency where power gain U = 1 (0 dB)</li>
                      <li>Practical upper limit for oscillators/amplifiers</li>
                      <li>Always: fmax ≥ fT</li>
                      <li><strong>Formula:</strong> fmax ≈ √(fT / (8πR<sub>g</sub>C<sub>gd</sub>))</li>
                    </ul>
                  </div>
                </div>
              </div>
              
              <h5 style='margin-top: 25px;'>Available Gain at Operating Frequency:</h5>
              <div class='callout callout-info' style='margin: 10px 0;'>
                <p style='margin: 0;'><strong>G<sub>available</sub>(f<sub>op</sub>) ≈ 20 × log<sub>10</sub>(fT / f<sub>op</sub>) dB</strong></p>
                <p style='margin: 5px 0 0 0; font-size: 13px;'>Example: With fT = 100 GHz at f<sub>op</sub> = 10 GHz → G ≈ 20 dB</p>
              </div>
              
              <h5 style='margin-top: 25px;'>Technology Evolution Trends:</h5>
              <table class='table table-bordered table-sm'>
                <thead>
                  <tr>
                    <th>Year Range</th>
                    <th>Si LDMOS fT</th>
                    <th>GaN HEMT fT</th>
                    <th>SiGe HBT fT</th>
                    <th>InP HEMT fT</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>2000-2005</td>
                    <td>~20 GHz</td>
                    <td>~30 GHz</td>
                    <td>~120 GHz</td>
                    <td>~200 GHz</td>
                  </tr>
                  <tr>
                    <td>2005-2010</td>
                    <td>~30 GHz</td>
                    <td>~50 GHz</td>
                    <td>~200 GHz</td>
                    <td>~350 GHz</td>
                  </tr>
                  <tr>
                    <td>2010-2015</td>
                    <td>~35 GHz</td>
                    <td>~70 GHz</td>
                    <td>~250 GHz</td>
                    <td>~500 GHz</td>
                  </tr>
                  <tr>
                    <td>2015-2020</td>
                    <td>~40 GHz</td>
                    <td>~90 GHz</td>
                    <td>~300 GHz</td>
                    <td>~600 GHz</td>
                  </tr>
                  <tr>
                    <td><strong>2020+</strong></td>
                    <td><strong>~40 GHz</strong></td>
                    <td><strong>~100 GHz</strong></td>
                    <td><strong>~350 GHz</strong></td>
                    <td><strong>~700+ GHz</strong></td>
                  </tr>
                </tbody>
              </table>
              
              <p style='margin-top: 15px; font-size: 13px; color: #666;'>
                <i class='fa fa-book'></i> <strong>References:</strong>
              </p>
              <ul style='font-size: 13px; color: #666;'>
                <li>Figures 2.2.4, 2.2.5 in <a href='../PA_Design_Reference_Manual/Chapters/Chapter_01_Transistor_Fundamentals.html' target='_blank'>Chapter 1</a></li>
                <li>ITRS Roadmap for RF and Analog/Mixed-Signal Technologies</li>
                <li>IEEE Transactions on Electron Devices (various years)</li>
              </ul>
            ")
          ),
          
          # Tab 3: Design Guidelines
          tabPanel(
            title = tagList(icon("lightbulb"), "Design Guidelines"),
            value = "design_guide",
            
            br(),
            h4(icon("tools"), " Practical Design Rules"),
            
            HTML("
              <h5>Frequency Selection Criteria:</h5>
              <div class='row' style='margin-top: 15px;'>
                <div class='col-md-4'>
                  <div class='callout callout-ok' style='border-radius: 5px;'>
                    <h6><strong><i class='fa fa-check-circle'></i> Safe Range</strong></h6>
                    <p style='font-size: 14px; margin: 0;'>f<sub>op</sub> < fT / 10</p>
                    <p style='font-size: 12px; margin: 5px 0 0 0;'>High gain, excellent stability, easy matching</p>
                  </div>
                </div>
                <div class='col-md-4'>
                  <div class='callout callout-warn' style='border-radius: 5px;'>
                    <h6><strong><i class='fa fa-exclamation-triangle'></i> Acceptable Range</strong></h6>
                    <p style='font-size: 14px; margin: 0;'>fT / 10 < f<sub>op</sub> < fT / 5</p>
                    <p style='font-size: 12px; margin: 5px 0 0 0;'>Moderate gain, requires attention to stability</p>
                  </div>
                </div>
                <div class='col-md-4'>
                  <div class='callout callout-danger' style='border-radius: 5px;'>
                    <h6><strong><i class='fa fa-times-circle'></i> Avoid</strong></h6>
                    <p style='font-size: 14px; margin: 0;'>f<sub>op</sub> > fT / 5</p>
                    <p style='font-size: 12px; margin: 5px 0 0 0;'>Low gain, stability issues, difficult matching</p>
                  </div>
                </div>
              </div>
              
              <h5 style='margin-top: 25px;'>Design Examples:</h5>
              <table class='table table-bordered'>
                <thead>
                  <tr>
                    <th>Application</th>
                    <th>Frequency</th>
                    <th>Required fT</th>
                    <th>Technology Choice</th>
                    <th>Expected Gain</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><strong>LTE Base Station</strong></td>
                    <td>1.8 GHz</td>
                    <td>> 9 GHz</td>
                    <td>Si LDMOS (fT ~40 GHz)</td>
                    <td>~25 dB per stage</td>
                  </tr>
                  <tr>
                    <td><strong>5G Sub-6GHz</strong></td>
                    <td>3.5 GHz</td>
                    <td>> 17.5 GHz</td>
                    <td>GaN HEMT (fT ~100 GHz)</td>
                    <td>~28 dB per stage</td>
                  </tr>
                  <tr>
                    <td><strong>5G mmWave</strong></td>
                    <td>28 GHz</td>
                    <td>> 140 GHz</td>
                    <td>SiGe HBT (fT ~300 GHz) or GaN</td>
                    <td>~10-12 dB per stage</td>
                  </tr>
                  <tr>
                    <td><strong>6G Research (Sub-THz)</strong></td>
                    <td>140 GHz</td>
                    <td>> 700 GHz</td>
                    <td>InP HEMT (fT ~700+ GHz)</td>
                    <td>~6-8 dB per stage</td>
                  </tr>
                </tbody>
              </table>
              
              <div class='callout callout-info' style='margin: 20px 0;'>
                <h5><i class='fa fa-calculator'></i> Quick Calculator:</h5>
                <p><strong>For your current global frequency: </strong><span id='calc_freq'></span></p>
                <p><strong>Minimum Required fT: </strong><span id='calc_ft_min'></span></p>
                <p><strong>Recommended fT: </strong><span id='calc_ft_rec'></span></p>
                <p><strong>Suggested Technologies: </strong><span id='calc_tech'></span></p>
                <script>
                  // Update calculator when frequency changes
                  $(document).ready(function() {
                    function updateCalc() {
                      if (typeof Shiny !== 'undefined' && Shiny.shinyapp && Shiny.shinyapp.$inputValues) {
                        var freq = Shiny.shinyapp.$inputValues.global_frequency || 2.6;
                        var ft_min = freq * 5;
                        var ft_rec = freq * 10;
                        
                        $('#calc_freq').text(freq.toFixed(2) + ' GHz');
                        $('#calc_ft_min').text(ft_min.toFixed(1) + ' GHz');
                        $('#calc_ft_rec').text(ft_rec.toFixed(1) + ' GHz');
                        
                        var tech = [];
                        if (ft_rec < 40) tech.push('Si LDMOS');
                        if (ft_rec < 100) tech.push('GaN HEMT');
                        if (ft_rec < 300) tech.push('SiGe HBT');
                        if (ft_rec >= 200) tech.push('InP HEMT');
                        
                        $('#calc_tech').text(tech.join(', ') || 'Advanced research technologies required');
                      }
                    }
                    
                    // Update on load and when frequency changes
                    updateCalc();
                    setInterval(updateCalc, 1000);
                  });
                </script>
              </div>
              
              <h5 style='margin-top: 25px;'>Key Takeaways:</h5>
              <ul>
                <li><strong>Always check fT before selecting a technology</strong> - It's the single most important parameter for frequency selection</li>
                <li><strong>Use the 5× rule as minimum</strong> - fT should be at least 5× your operating frequency</li>
                <li><strong>Higher fT = More margin</strong> - Provides better gain, easier matching, and improved stability</li>
                <li><strong>Consider fmax for oscillators</strong> - For VCOs and oscillators, use fmax instead of fT as the limit</li>
                <li><strong>Technology roadmaps matter</strong> - fT has improved steadily, enabling higher frequency designs each year</li>
              </ul>
            ")
          )
        ),
        
        htmlOutput("freq_recommendation")
      ),
      tabItem(tabName = "tech_device_lib",
        h2(icon("th-large"), " 3.3 Device Library"),
        tabsetPanel(
          tabPanel("Browse Devices",
            h4("Transistor & Device Catalogue"),
            div(class="callout callout-info",
              p(icon("info-circle"), " Devices characterised and saved in the Transistor Library (5.1) appear here for cross-project reuse.")
            ),
            fluidRow(
              column(3, selectInput("dev_lib_tech", "Technology",
                choices = c("All", "GaN HEMT", "GaAs pHEMT", "LDMOS", "SiGe HBT"),
                selected = "All")),
              column(3, sliderInput("dev_lib_freq", "Frequency range (GHz)",
                min=0.1, max=100, value=c(1,40), step=0.5)),
              column(3, sliderInput("dev_lib_pout", "P_out density (W/mm)",
                min=0.1, max=10, value=c(0.5,6), step=0.1))
            ),
            p(class="text-muted", "Device table with filter/sort/compare — under construction.")
          ),
          tabPanel("Device Detail",
            h4("Selected Device — Parameters"),
            p(class="text-muted", "Click a device in Browse to open detail view — under construction.")
          ),
          tabPanel("Compare",
            h4("Side-by-side Device Comparison"),
            p(class="text-muted", "Select 2–4 devices and compare fT, Pout, PAE, gain, VBR — under construction.")
          )
        )
      ),


      tabItem(tabName = "tech_stack",
        h2(icon("layer-group"), " 3.5 Technology Stack"),
        tabsetPanel(
          tabPanel("Process Overview",
            h4("Technology Process Definition"),
            wellPanel(
              fluidRow(
                column(6,
                  selectInput("ts_foundry", "Foundry / PDK",
                    choices = c("Custom/Other", "WIN Semiconductors", "UMS", "Wolfspeed", "RFMD", "Tower Jazz")),
                  textInput("ts_node", "Process Node", placeholder = "e.g. 0.25 µm GaN on SiC"),
                  numericInput("ts_vdd", "Nominal V_DD (V)", value = 28, min=1, max=100)
                ),
                column(6,
                  numericInput("ts_ft", "fT (GHz)", value = 40, min=1, max=500),
                  numericInput("ts_fmax", "fmax (GHz)", value = 80, min=1, max=1000),
                  numericInput("ts_pout_density", "P_out density (W/mm)", value = 5, min=0.1, max=15, step=0.1)
                )
              )
            )
          ),
          tabPanel("Metal Stack",
            h4("Back-end-of-line (BEOL) Metal Layers"),
            p("Define conductor layers available in the PDK for matching network synthesis:"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Layer</th><th>Metal</th><th>Thickness (μm)</th><th>Sheet R (mΩ/□)</th><th>Use</th></tr></thead>
              <tbody>
                <tr><td>M1</td><td>Au/Ti</td><td>0.5</td><td>70</td><td>FET gate / active</td></tr>
                <tr><td>M2</td><td>Au</td><td>1.5</td><td>20</td><td>Interconnect</td></tr>
                <tr><td>M3 (thick)</td><td>Au</td><td>4.0</td><td>8</td><td>Transmission lines, inductors</td></tr>
                <tr><td>Backside</td><td>Au</td><td>10</td><td>3</td><td>Ground, thermal path</td></tr>
              </tbody></table>"),
            p(class="text-muted", "Editable PDK metal stack — under construction.")
          ),
          tabPanel("Assembly & Packaging",
            h4("Package Options"),
            HTML("<ul>
              <li><strong>Bare die (flip-chip / wire-bond)</strong>: minimal parasitics, highest performance</li>
              <li><strong>Plastic QFN / LGA</strong>: low cost, moderate thermal; good for LDMOS</li>
              <li><strong>Metal-ceramic (CuW / AlN)</strong>: best thermal; standard for GaN power modules</li>
              <li><strong>HTCC / LTCC</strong>: multi-chip, hermetic, for space and military</li>
            </ul>")
          )
        )
      ),


      tabItem(tabName = "tech_portfolio",
        h2(icon("chart-bar"), " 3.6 Portfolio Generation"),
        tabsetPanel(
          tabPanel("Radar Plot",
            h4("Technology / Module Portfolio — Radar Chart"),
            div(class="callout callout-info",
              p(icon("info-circle"), " Compare designs across key axes: Frequency, P_out, PAE, Gain, Linearity, Cost.")
            ),
            p(class="text-muted", "D3.js radar chart — under construction.")
          ),
          tabPanel("Pareto Analysis",
            h4("PAE vs Linearity Pareto Front"),
            p("For each candidate design, plot PAE (y) vs ACLR back-off from P_sat (x). The Pareto front shows which designs are non-dominated."),
            p(class="text-muted", "Pareto scatter plot — under construction.")
          ),
          tabPanel("Export",
            h4("Portfolio Export"),
            p("Export your technology comparison portfolio as:"),
            fluidRow(
              column(4, actionButton("portfolio_export_csv",  "CSV",  icon = icon("file-csv"),  class="btn-default btn-block")),
              column(4, actionButton("portfolio_export_html", "HTML", icon = icon("file-code"), class="btn-default btn-block")),
              column(4, actionButton("portfolio_export_pdf",  "PDF",  icon = icon("file-pdf"),  class="btn-default btn-block"))
            ),
            p(class="text-muted", "Export handlers — under construction.")
          )
        )
      ),



      # ── Device-level stubs ────────────────────────────────────────────────────
      tabItem(tabName = "device_level",
        h2(icon("draw-polygon"), " 4 · Device Level"),
        p("Select a sub-topic from the sidebar. The architecture canvas (4.2) drives design choices for each stage.")
      ),
      tabItem(tabName = "dev_specs",
        h2(icon("clipboard-list"), " 4.1 PA Specifications"),
        tabsetPanel(
          tabPanel("Target Specs",
            h4("PA Design Specification Entry"),
            fluidRow(
              column(6,
                wellPanel(
                  h5(icon("broadcast-tower"), " RF Performance"),
                  fluidRow(
                    column(6, numericInput("spec_freq_lo",  "Freq Low (GHz)",   value = 3.3, min=0.1, max=300, step=0.1)),
                    column(6, numericInput("spec_freq_hi",  "Freq High (GHz)",  value = 3.8, min=0.1, max=300, step=0.1))
                  ),
                  fluidRow(
                    column(6, numericInput("spec_pout",     "P_out (dBm)",      value = 43,  min=0, max=70, step=0.5)),
                    column(6, numericInput("spec_gain",     "Gain (dB)",        value = 25,  min=0, max=60, step=0.5))
                  ),
                  fluidRow(
                    column(6, numericInput("spec_pae",      "PAE target (%)",   value = 40,  min=1, max=90, step=1)),
                    column(6, numericInput("spec_p1db",     "P1dB (dBm)",       value = 40,  min=0, max=70, step=0.5))
                  )
                )
              ),
              column(6,
                wellPanel(
                  h5(icon("bolt"), " Linearity"),
                  fluidRow(
                    column(6, numericInput("spec_aclr",     "ACLR (dBc)",       value = -45, min=-70, max=-20, step=1)),
                    column(6, numericInput("spec_evm",      "EVM (%)",          value = 3,   min=0.1, max=10, step=0.1))
                  ),
                  fluidRow(
                    column(6, numericInput("spec_backoff",  "Back-off (dB)",    value = 8,   min=0, max=20, step=0.5)),
                    column(6, selectInput("spec_modulation","Modulation", choices=c("5G NR 256-QAM","OFDM 64-QAM","CW","Custom")))
                  )
                )
              )
            )
          ),
          tabPanel("Supply & Bias",
            h4("DC Operating Point"),
            fluidRow(
              column(4, numericInput("spec_vdd",    "V_DD (V)",          value=28, min=1, max=100, step=1)),
              column(4, numericInput("spec_idd_ma", "I_DD at P_sat (mA)", value=1200, min=1, max=20000, step=50)),
              column(4, numericInput("spec_temp_c", "T_case (°C)",       value=85, min=-40, max=150, step=5))
            ),
            p(class="text-muted", "Bias optimisation tool — under construction.")
          ),
          tabPanel("Compliance Matrix",
            h4("Spec Tracking — Target vs Simulated vs Measured"),
            p(class="text-muted", "Compliance matrix linking to simulation and measurement results — under construction.")
          )
        )
      ),


      tabItem(tabName = "dev_interstage",
        h2(icon("random"), " 4.3 Interstage & Passives"),
        tabsetPanel(
          tabPanel("Splitters / Combiners",
            h4("Power Splitter / Combiner Topologies"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Type</th><th>BW</th><th>Isolation</th><th>Insertion Loss</th><th>Notes</th></tr></thead>
              <tbody>
                <tr><td>Wilkinson</td><td>Narrowband</td><td>Good (20–30 dB)</td><td>~0.3 dB</td><td>In-phase; resistor dissipates reflected power</td></tr>
                <tr><td>Hybrid coupler (90°)</td><td>Octave</td><td>Excellent</td><td>~0.5 dB</td><td>Used in balanced amplifier topologies</td></tr>
                <tr><td>Rat-race (180°)</td><td>~30%</td><td>Good</td><td>~0.5 dB</td><td>Sum/difference port; push-pull PA</td></tr>
                <tr><td>Corporate Wilkinson (N-way)</td><td>Narrowband</td><td>Port-to-port</td><td>0.3+0.3n dB</td><td>Phased array, spatial combining</td></tr>
              </tbody></table>")
          ),
          tabPanel("Interstage Matching",
            h4("Driver → Final Stage Matching Network"),
            p("The interstage network simultaneously conjugate-matches the driver output and presents the optimum load to the final stage input:"),
            wellPanel(
              HTML("<ul>
                <li>Source pull: find optimum source impedance Z<sub>S,opt</sub> for final stage at each frequency</li>
                <li>Driver output must present Z<sub>S,opt</sub>* for maximum power transfer</li>
                <li>Bandwidth-efficiency trade-off: wider BW → lower gain, higher mismatch loss</li>
              </ul>")
            ),
            p(class="text-muted", "Matching network synthesis tool (L/π/T networks, Chebyshev) — under construction.")
          ),
          tabPanel("Passive Q & Loss",
            h4("On-chip vs Off-chip Passives"),
            HTML("<table class='table table-sm table-striped'>
              <thead><tr><th>Component</th><th>On-chip Q</th><th>Off-chip Q</th><th>Notes</th></tr></thead>
              <tbody>
                <tr><td>Spiral inductor (1 nH, 5 GHz)</td><td>15–30</td><td>50–200</td><td>SMD wirewound: best Q</td></tr>
                <tr><td>MIM capacitor (1 pF, 5 GHz)</td><td>50–100</td><td>200–500</td><td>Ceramic SMD (C0G/NP0)</td></tr>
                <tr><td>λ/4 line (50 Ω, 5 GHz)</td><td>Radiation Q dependent</td><td>Stripline > microstrip</td><td>PCB loss ~0.1 dB/cm at 5 GHz</td></tr>
              </tbody></table>")
          )
        )
      ),



      # ── Product-level stubs ───────────────────────────────────────────────────
      # ── Product-level: three product tiers + shared flow ───────────────────────────
      tabItem(tabName = "product_level",
        h2(icon("industry"), " 5 · Product Level"),
        p("Three product tiers: a single transistor, a PA stage, or a fully assembled module/line-up."),
        p("Each tier builds a library that feeds the next: Module (5.3) pulls from PA Stage Library; PA Stage (5.2) pulls from Transistor Library (5.1).")
      ),

      # 5.1 Transistor Design (as product — builds Transistor Library)
      tabItem(tabName = "prod_transistor",
        h2(icon("microchip"), " 5.1 Transistor Design"),
        tabsetPanel(
          tabPanel("Specifications",
            p("Under construction — Target specs: fT, Pout density, PAE, gain at Vdd/Id bias.")
          ),
          tabPanel("LP Performance",
            p("Under construction — Bias, load-pull, gain circles, Cripps optimum load.")
          ),
          tabPanel("Linearity",
            p("Under construction — AM/AM, AM/PM, IIP3, IMD3 analysis.")
          ),
          tabPanel("Stability",
            p("Under construction — K-factor, MSG, MAG, stability circles, stabilisation networks.")
          ),
          tabPanel("Transistor Library",
            div(class = "callout callout-info",
              p(icon("info-circle"), " Characterised transistors appear in the Design Canvas palette (4.2)
                and in PA Stage Design (5.2) as building blocks.")
            ),
            p("Under construction — Transistor library: browse, compare, tag, export.")
          )
        )
      ),

      # 5.2 PA Stage Design (individual stage as product — builds PA Stage Library)
      tabItem(tabName = "prod_pa_stage",
        h2(icon("bolt"), " 5.2 PA Stage Design"),
        tabsetPanel(
          tabPanel("Specifications",
            p("Under construction — Stage-level target spec (Driver / Main / Aux).")
          ),
          tabPanel("Architecture Choices",
            p("Under construction — Class selection, biasing, topology (Class A/AB/B/F/Doherty).")
          ),
          tabPanel("Performance",
            p("Under construction — Gain, PAE, P1dB, P3dB, load-pull across frequency.")
          ),
          tabPanel("Linearity",
            p("Under construction — Stage-level linearity, IMD, AM/AM within lineup context.")
          ),
          tabPanel("Stability",
            p("Under construction — Stage stability inside module embedding environment.")
          ),
          tabPanel("PA Stage Library",
            div(class = "callout callout-info",
              p(icon("info-circle"), " Characterised PA stages are building blocks for Module Design (5.3).
                Each entry links back to its transistor(s) from the Transistor Library (5.1).")
            ),
            p("Under construction — PA stage library: browse, compare, tag, export.")
          )
        )
      ),

      # 5.3 Module / Line-up Design (final assembled product)
      tabItem(tabName = "prod_module",
        h2(icon("industry"), " 5.3 Module Design"),
        tabsetPanel(
          tabPanel("Specifications",
            p("Under construction — Module-level spec (full line-up Pout, gain, PAE, compliance targets).")
          ),
          tabPanel("Line-up Design",
            div(class = "callout callout-info",
              p(icon("info-circle"), strong(" Architecture canvas (4.2)"),
                " defines the topology. Pull PA stages from the ",
                strong("PA Stage Library (5.2)"),
                " and assemble into a module, then run cascade simulations.")
            ),
            p("Under construction — Line-up cascade with PA-stage library components.")
          ),
          tabPanel("Doherty Design",
            p("Under construction — Doherty combiner network, OBO tuning, efficiency vs back-off.")
          ),
          tabPanel("Optimisation",
            p("Under construction — Automated sweep, Pareto front (PAE vs linearity).")
          ),
          tabPanel("Reliability & Thermal",
            p("Under construction — Module-level MTTF and thermal network (links to 5.4 Reliability).")
          ),
          tabPanel("Module Library",
            div(class = "callout callout-info",
              p(icon("info-circle"), " Completed modules are archived here for reuse, cross-project comparison and App Download (8).")
            ),
            p("Under construction — Module library: browse, tag, export.")
          )
        )
      ),
      tabItem(tabName = "prod_prototype",
        h2(icon("tools"), " 5.5 Prototype"),
        tabsetPanel(
          tabPanel("Test Structures", p("Under construction.")),
          tabPanel("Layout",          p("Under construction — layout review for RF best practices.")),
          tabPanel("Tapeout",         p("Under construction.")),
          tabPanel("Assembly",        p("Under construction.")),
          tabPanel("BOM",             p("Under construction."))
        )
      ),
      tabItem(tabName = "prod_cv_meas",
        h2(icon("flask"), " 5.6 CV Measurements"),
        tabsetPanel(
          tabPanel("DC",                p("Under construction — DC characterisation.")),
          tabPanel("S-parameter",       p("Under construction — S-parameter measurements.")),
          tabPanel("Load-pull",         p("Under construction — load-pull setup and data.")),
          tabPanel("RF Large-Signal",   p("Under construction — large-signal RF performance.")),
          tabPanel("DPD Linearity",     p("Under construction — DPD and linearity measurements."))
        )
      ),
      tabItem(tabName = "prod_analysis",
        h2(icon("balance-scale"), " 5.7 Analysis"),
        tabsetPanel(
          tabPanel("Sim vs Measurement", p("Under construction — comparison plots and tables.")),
          tabPanel("Modelling",          p("Under construction — extraction and model validation.")),
          tabPanel("Compliance Matrix",  p("Under construction — spec compliance tracking.")),
          tabPanel("Lessons Learnt",     p("Under construction — stage-specific lessons."))
        )
      ),

      # ── Lessons Learnt ────────────────────────────────────────────────────────
      # ── Lessons Learnt ─────────────────────────────────────────────────────────
      # ── Lessons Learnt ─────────────────────────────────────────────────────────
      tabItem(tabName = "lessons_learnt",
        h2(icon("graduation-cap"), " 6 · Lessons Learnt"),
        tabsetPanel(
          tabPanel("Browse Lessons",
            h4("Searchable Cross-Project Lessons Database"),
            fluidRow(
              column(3, selectInput("ll_tech_filter", "Technology",
                choices = c("All", "GaN", "LDMOS", "GaAs pHEMT", "SiGe HBT"), selected = "All")),
              column(3, selectInput("ll_stage_filter", "Design Stage",
                choices = c("All", "System", "Technology", "Device", "Product"), selected = "All")),
              column(3, selectInput("ll_band_filter", "Frequency Band",
                choices = c("All", "< 1 GHz", "1–6 GHz", "6–30 GHz", "> 30 GHz"), selected = "All")),
              column(3, textInput("ll_keyword", "Keyword search", placeholder = "e.g. stability, Doherty..."))
            ),
            p(class="text-muted", "Lessons table with tagging and filter — under construction.")
          ),
          tabPanel("Add Lesson",
            h4("Record a New Lesson"),
            wellPanel(
              textInput("ll_title",       "Title",        placeholder = "Short one-line summary"),
              selectInput("ll_category",  "Category",
                choices = c("Design Rule", "Process Insight", "Measurement Gotcha", "Simulation vs Reality", "Tool/Flow", "Other")),
              textAreaInput("ll_body",    "Description",  height = "120px",
                placeholder = "What happened? What was the root cause? What is the corrective action?"),
              fluidRow(
                column(4, textInput("ll_tags",      "Tags (comma-separated)", placeholder = "e.g. GaN, stability")),
                column(4, textInput("ll_project",   "Project / Tapeout",     placeholder = "e.g. PA_5G_2025")),
                column(4, selectInput("ll_severity", "Severity",
                  choices = c("Info", "Warning", "Critical")))
              ),
              actionButton("ll_save", "Save Lesson", icon = icon("save"), class = "btn-primary")
            )
          ),
          tabPanel("Hot Issues",
            h4("Critical / Recurring Issues"),
            p("Lessons tagged as Critical that appear in multiple projects are listed here automatically."),
            p(class="text-muted", "Hot-issue aggregation — under construction.")
          )
        )
      ),



      # ── Reporting ─────────────────────────────────────────────────────────────
      # ── 7 · Reporting ─────────────────────────────────────────────────────────
      # ── 7 · Reporting ─────────────────────────────────────────────────────────
      tabItem(tabName = "reporting",
        h2(icon("file-alt"), " 7 · Reporting"),

        tabsetPanel(id = "reporting_tabs",

          # ── Stage Reports ──────────────────────────────────────────────────
          tabPanel("Stage Reports",
            br(),
            fluidRow(
              column(8,
                h4(icon("list-check"), " Stage Report Status"),
                p(class="text-muted",
                  "Each design stage can generate a self-contained HTML section.
                   Completed stages are shown in green; stubs in grey."),

                # Stage cards — rendered server-side so status is reactive
                uiOutput("reporting_stage_cards")
              ),
              column(4,
                wellPanel(
                  h5(icon("sliders-h"), " Report Options"),
                  checkboxGroupInput("report_include_stages",
                    "Include stages:",
                    choices = list(
                      "1 · First Principles"  = "first_principles",
                      "2 · System Level"      = "system_level",
                      "3 · Technology"        = "tech_level",
                      "4 · Device Level"      = "device_level",
                      "5 · Product Level"     = "product_level",
                      "6 · Lessons Learnt"    = "lessons_learnt"
                    ),
                    selected = c("tech_level","device_level","product_level")
                  ),
                  selectInput("report_detail_level", "Detail level",
                    choices = c(
                      "Summary (exec)"    = "summary",
                      "Standard"          = "standard",
                      "Full (all data)"   = "full"
                    ),
                    selected = "standard"
                  ),
                  hr(),
                  downloadButton("report_download_stages", "Download Stage Reports",
                    class = "btn-primary btn-block")
                )
              )
            )
          ),

          # ── Master Report ──────────────────────────────────────────────────
          tabPanel("Master Report",
            br(),
            fluidRow(
              column(7,
                h4(icon("file-pdf"), " Master Design Report"),
                wellPanel(
                  fluidRow(
                    column(6, textInput("report_title",   "Report Title",
                             value = "PA Design Report",
                             placeholder = "Project / Design Name")),
                    column(6, textInput("report_author",  "Author(s)",
                             placeholder = "Your name"))
                  ),
                  fluidRow(
                    column(6, textInput("report_revision", "Revision",  value = "1.0")),
                    column(6, selectInput("report_format",  "Output Format",
                             choices = c("Self-contained HTML" = "html_self",
                                         "HTML (linked)"       = "html_linked",
                                         "PDF (via pandoc)"    = "pdf")))
                  ),
                  textAreaInput("report_abstract", "Abstract / Executive Summary",
                    height = "90px",
                    placeholder = "High-level description of the design, target spec, and key results."),
                  checkboxInput("report_include_toc",    "Include table of contents", value = TRUE),
                  checkboxInput("report_include_charts", "Embed interactive charts",  value = TRUE),
                  checkboxInput("report_include_tables", "Embed data tables",         value = TRUE)
                ),
                fluidRow(
                  column(6, actionButton("report_preview_btn", "Preview (HTML)",
                    icon = icon("eye"), class = "btn-default btn-block")),
                  column(6, downloadButton("report_download_master", "Download Master Report",
                    class = "btn-success btn-block"))
                )
              ),
              column(5,
                h4(icon("eye"), " Report Preview"),
                div(style = "border:1px solid #444; border-radius:6px; min-height:300px; padding:12px;",
                  uiOutput("report_preview_html")
                )
              )
            )
          ),

          # ── Report Config ──────────────────────────────────────────────────
          tabPanel("Report Config",
            br(),
            h4(icon("cog"), " Report Configuration"),
            fluidRow(
              column(6,
                wellPanel(
                  h5("Company & Branding"),
                  textInput("report_company",     "Company / Organisation", placeholder = "Infineon Technologies"),
                  textInput("report_logo_url",    "Logo URL or path",       placeholder = "/path/to/logo.png"),
                  selectInput("report_colour_scheme", "Colour scheme",
                    choices = c("Dark (default)" = "dark",
                                "Light / print"  = "light",
                                "Corporate blue" = "blue")),
                  checkboxInput("report_confidential", "Mark as Confidential", value = TRUE)
                )
              ),
              column(6,
                wellPanel(
                  h5("Pandoc & PDF Settings"),
                  textInput("report_pandoc_path",   "Pandoc path (optional)", placeholder = "auto-detected"),
                  textInput("report_latex_engine",  "LaTeX engine",           value = "xelatex"),
                  numericInput("report_font_size",  "Body font size (pt)",    value = 11, min=8, max=14, step=1),
                  selectInput("report_page_size",   "Page size",
                    choices = c("A4" = "a4paper", "Letter" = "letterpaper"))
                )
              )
            ),
            fluidRow(
              column(12,
                wellPanel(
                  h5("Custom CSS / Header Snippet"),
                  textAreaInput("report_custom_css", NULL,
                    height = "80px",
                    placeholder = "/* Optional extra CSS for the HTML report */")
                )
              )
            )
          )
        )
      ),



      # ── App Download ──────────────────────────────────────────────────────────
      # ── 8 · App Download ──────────────────────────────────────────────────────
      # ── 8 · App Download ──────────────────────────────────────────────────────
      tabItem(tabName = "app_download",
        h2(icon("download"), " 8 · App Download"),
        p(class="text-muted",
          "Export the current design as a self-contained sub-app, a data snapshot, or a reusable template."),
        br(),

        tabsetPanel(id = "download_tabs",

          # ── Dataset Snapshot ───────────────────────────────────────────────
          tabPanel("Dataset Snapshot",
            br(),
            fluidRow(
              column(4,
                div(class = "download-option-box",
                  div(class = "download-icon", icon("file-code")),
                  h5("HTML Data Report"),
                  p("Freeze all charts and tables into a portable self-contained HTML file."),
                  br(),
                  downloadButton("snap_download_html", "Download HTML",
                    class = "btn-primary btn-block")
                )
              ),
              column(4,
                div(class = "download-option-box",
                  div(class = "download-icon", icon("file-csv")),
                  h5("CSV / Excel Export"),
                  p("Export all data tables (specs, results, library items) as a zip of CSV files."),
                  br(),
                  downloadButton("snap_download_csv", "Download CSV",
                    class = "btn-default btn-block")
                )
              ),
              column(4,
                div(class = "download-option-box",
                  div(class = "download-icon", icon("database")),
                  h5("RDS / JSON Snapshot"),
                  p("Full R project state as RDS (for re-import) or JSON (for external tools)."),
                  br(),
                  downloadButton("snap_download_rds", "Download RDS",
                    class = "btn-default btn-block")
                )
              )
            ),
            br(),
            wellPanel(
              h5(icon("cog"), " Snapshot options"),
              fluidRow(
                column(4, checkboxInput("snap_include_canvas",  "Include canvas state (JSON)", value = TRUE)),
                column(4, checkboxInput("snap_include_charts",  "Embed charts",               value = TRUE)),
                column(4, checkboxInput("snap_include_models",  "Include model parameters",   value = TRUE))
              ),
              fluidRow(
                column(6, textInput("snap_project_tag", "Project tag",
                  value = "", placeholder = "e.g. PA_5G_R1 — appended to filename")),
                column(6, selectInput("snap_compression", "Compression",
                  choices = c("None" = "none", "gzip" = "gz", "bzip2" = "bz2"), selected = "gz"))
              )
            )
          ),

          # ── Sub-App Export ─────────────────────────────────────────────────
          tabPanel("Sub-App Export",
            br(),
            h4(icon("cube"), " Export a Focused Sub-Application"),
            p("Choose a subset of design sections to bundle as a standalone Shiny app — useful for sharing a specific design with colleagues who only need one segment."),
            fluidRow(
              column(6,
                wellPanel(
                  h5("Select sections to include"),
                  checkboxGroupInput("subapp_sections",
                    NULL,
                    choices = list(
                      "1 · First Principles"           = "first_principles",
                      "2 · System Level"               = "system_level",
                      "2.1  Frequency Planning"        = "sys_freq_planning",
                      "2.4  Link Budget"               = "sys_link_budget",
                      "3 · Technology Level"           = "tech_level",
                      "3.1  Technology Selection"      = "tech_selection",
                      "3.4  Loss Curves"               = "tech_loss_curves",
                      "4 · Device Level"               = "device_level",
                      "4.2  Architecture Canvas"       = "dev_architecture",
                      "5.1  Transistor Design"         = "prod_transistor",
                      "5.2  PA Stage Design"           = "prod_pa_stage",
                      "5.3  Module Design"             = "prod_module",
                      "5.4  Reliability"               = "prod_reliability",
                      "RF Tools (Smith Chart etc.)"    = "rf_tools",
                      "7 · Reporting"                  = "reporting"
                    ),
                    selected = c("tech_selection","dev_architecture","prod_transistor","prod_pa_stage","prod_module")
                  )
                )
              ),
              column(6,
                wellPanel(
                  h5("Sub-app settings"),
                  textInput("subapp_name",   "Sub-app name",  placeholder = "e.g. Doherty_PA_Tool"),
                  textInput("subapp_author", "Author",        placeholder = "Your name"),
                  textInput("subapp_version","Version",       value = "1.0"),
                  checkboxInput("subapp_standalone", "Include all dependencies (larger file)", value = TRUE),
                  br(),
                  actionButton("subapp_preview_manifest", "Preview file manifest",
                    icon = icon("list"), class = "btn-default btn-block"),
                  br(),
                  downloadButton("subapp_download_zip", "Download sub-app ZIP",
                    class = "btn-success btn-block")
                ),
                uiOutput("subapp_manifest_preview")
              )
            )
          ),

          # ── Template Store ─────────────────────────────────────────────────
          tabPanel("Template Store",
            br(),
            fluidRow(
              column(6,
                h4(icon("save"), " Save Current App as Template"),
                wellPanel(
                  textInput("tmpl_name",        "Template name",
                    placeholder = "e.g. 5G NR n77 PA — GaN 28V"),
                  textInput("tmpl_description", "Description",
                    placeholder = "Brief description of the design configuration"),
                  fluidRow(
                    column(6, textInput("tmpl_tech",    "Technology",   placeholder = "GaN on SiC 0.25 µm")),
                    column(6, textInput("tmpl_band",    "Band",         placeholder = "Sub-6 GHz 5G NR"))
                  ),
                  actionButton("tmpl_save_btn", "Save Template",
                    icon = icon("save"), class = "btn-primary btn-block")
                )
              ),
              column(6,
                h4(icon("folder-open"), " Saved Templates"),
                uiOutput("tmpl_list_ui"),
                p(class="text-muted", "Templates are stored as JSON in the app data directory.")
              )
            )
          )
        )
      ),



      # ── Utilities (reached via top utility bar) ───────────────────────────────
      tabItem(tabName = "util_data",
        h2(icon("database"), " Data Manager"),
        p("Under construction — database browser, metadata, tagging system, import/export.")
      ),
      tabItem(tabName = "util_agents",
        h2(icon("robot"), " AI Agents"),
        p("Under construction — agent manager, prompt store, external knowledge access.")
      ),
      tabItem(tabName = "util_knowledge",
        h2(icon("book"), " Knowledge Base"),
        p("Under construction — internal notes, datasheets, references and IFX notes library.")
      ),

      # RF Tools: Smith Chart
      tabItem(tabName = "smith_chart",
        h2("📊 Smith Chart Visualization"),
        fluidRow(
          box(
            title = "Impedance/Admittance Entry",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            selectInput("smith_mode", "Chart Mode",
              choices = c("Impedance", "Admittance", "Combined")),
            numericInput("smith_z_real", "Z Real (Ω)", value = 50, min = -500, max = 500),
            numericInput("smith_z_imag", "Z Imaginary (Ω)", value = 0, min = -500, max = 500),
            numericInput("smith_freq", "Frequency (GHz)", value = 2.4, min = 0.1, max = 100),
            hr(),
            actionButton("smith_add_point", "Add Point", class = "btn-primary", icon = icon("plus")),
            actionButton("smith_clear", "Clear All", class = "btn-warning", icon = icon("trash")),
            hr(),
            h4("Matching Network Design:"),
            selectInput("smith_match_type", "Network Type",
              choices = c("Single Stub", "Double Stub", "L-Section", "Pi-Network", "T-Network")),
            actionButton("smith_design_match", "Design Network", class = "btn-success", icon = icon("calculator"))
          ),
          box(
            title = "Smith Chart",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            p("Interactive Smith Chart with matching network visualization"),
            plotlyOutput("smith_chart_plot", height = "600px"),
            hr(),
            h4("Component Values:"),
            verbatimTextOutput("smith_components")
          )
        )
      ),
      
      # RF Tools: Converters
      tabItem(tabName = "rf_converters",
        h2("🔄 RF Unit Converters"),
        fluidRow(
          box(
            title = "Power Conversions",
            width = 6,
            status = "primary",
            solidHeader = TRUE,
            numericInput("conv_power_watt", "Power (Watt)", value = 1, min = 0),
            verbatimTextOutput("conv_power_results"),
            hr(),
            numericInput("conv_power_dbm", "Power (dBm)", value = 30, min = -100, max = 100),
            verbatimTextOutput("conv_dbm_results")
          ),
          box(
            title = "Voltage/Field Conversions",
            width = 6,
            status = "info",
            solidHeader = TRUE,
            numericInput("conv_voltage", "Voltage (V)", value = 1, min = 0),
            numericInput("conv_impedance", "Impedance (Ω)", value = 50, min = 0.1),
            verbatimTextOutput("conv_voltage_results")
          )
        ),
        fluidRow(
          box(
            title = "Frequency/Wavelength Conversions",
            width = 6,
            status = "warning",
            solidHeader = TRUE,
            numericInput("conv_freq", "Frequency (GHz)", value = 2.4, min = 0.001),
            selectInput("conv_medium", "Medium",
              choices = c("Free Space" = 1, "FR4 (εr=4.4)" = 4.4, "Rogers RO4003 (εr=3.55)" = 3.55, "Custom" = 0)),
            conditionalPanel(
              condition = "input.conv_medium == 0",
              numericInput("conv_er_custom", "Custom εr", value = 1, min = 1, max = 20)
            ),
            verbatimTextOutput("conv_freq_results")
          ),
          box(
            title = "S-Parameters & Reflection Coefficient",
            width = 6,
            status = "success",
            solidHeader = TRUE,
            numericInput("conv_s11_mag", "S11 Magnitude", value = 0.1, min = 0, max = 1, step = 0.01),
            numericInput("conv_s11_phase", "S11 Phase (degrees)", value = 0, min = -180, max = 180),
            verbatimTextOutput("conv_sparams_results")
          )
        )
      ),

      # ── 5.2 Prod Reliability (MTTF + Thermal consolidated) ────────────────────
      tabItem(tabName = "prod_reliability",
        h2(icon("heartbeat"), " 5.4 Reliability & Thermal Analysis"),
        tabsetPanel(
          tabPanel("MTTF Calculator",
            h3(icon("stopwatch"), " MTTF (Mean Time To Failure) Calculator"),
        fluidRow(
          box(
            title = "Device Parameters",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            selectInput("mttf_device_type", "Device Type",
              choices = c("LDMOS", "GaN HEMT", "SiGe HBT", "GaAs MESFET", "Custom")),
            numericInput("mttf_tj", "Junction Temperature (°C)", value = 125, min = -55, max = 300),
            numericInput("mttf_ta", "Ambient Temperature (°C)", value = 25, min = -55, max = 150),
            numericInput("mttf_power_diss", "Power Dissipation (W)", value = 10, min = 0.1, max = 1000),
            numericInput("mttf_rth", "Thermal Resistance Rθjc (°C/W)", value = 5, min = 0.1, max = 100),
            hr(),
            h4("Stress Factors:"),
            numericInput("mttf_voltage_stress", "Voltage Stress Factor", value = 1.0, min = 0.5, max = 2, step = 0.1),
            numericInput("mttf_current_stress", "Current Stress Factor", value = 1.0, min = 0.5, max = 2, step = 0.1),
            hr(),
            actionButton("mttf_calculate", "Calculate MTTF", class = "btn-success", icon = icon("calculator"))
          ),
          box(
            title = "Reliability Results",
            width = 8,
            status = "info",
            solidHeader = TRUE,
            h4("MTTF Analysis:"),
            verbatimTextOutput("mttf_results"),
            hr(),
            plotlyOutput("mttf_plot", height = "400px"),
            hr(),
            h4("Reliability Recommendations:"),
            htmlOutput("mttf_recommendations")
          )
        )
      ),
      
          tabPanel("Thermal Analysis",
            h3(icon("fire"), " Thermal Analysis"),
        fluidRow(
          box(
            title = "Thermal Network Parameters",
            width = 4,
            status = "primary",
            solidHeader = TRUE,
            h4("Power Dissipation:"),
            numericInput("therm_pout", "Output Power (W)", value = 20, min = 0.1, max = 1000),
            numericInput("therm_efficiency", "PAE (%)", value = 50, min = 1, max = 90),
            verbatimTextOutput("therm_pdiss"),
            hr(),
            h4("Thermal Resistances:"),
            numericInput("therm_rth_jc", "Rθjc (Junction-to-Case) (°C/W)", value = 2, min = 0.1, max = 50),
            numericInput("therm_rth_cs", "Rθcs (Case-to-Sink) (°C/W)", value = 0.5, min = 0.01, max = 10),
            numericInput("therm_rth_sa", "Rθsa (Sink-to-Ambient) (°C/W)", value = 3, min = 0.1, max = 50),
            hr(),
            numericInput("therm_ta", "Ambient Temperature (°C)", value = 25, min = -55, max = 150),
            numericInput("therm_tj_max", "Max Junction Temp (°C)", value = 150, min = 50, max = 300),
            hr(),
            actionButton("therm_calculate", "Calculate Thermal Profile", class = "btn-success", icon = icon("fire"))
          ),
          box(
            title = "Thermal Analysis Results",
            width = 8,
            status = "danger",
            solidHeader = TRUE,
            h4("Temperature Profile:"),
            verbatimTextOutput("therm_results"),
            hr(),
            plotlyOutput("therm_plot", height = "400px"),
            hr(),
            h4("Heatsink Recommendations:"),
            htmlOutput("therm_recommendations")
          )
        )
      ),
      
        )  # close tabsetPanel in prod_reliability
      ),  # closes tabItem(prod_reliability)

      # Settings Tab
      tabItem(tabName = "settings",
        h2("Application Settings"),
        fluidRow(
          # ── Theme & Appearance ───────────────────────────────────────
          box(
            title = "Theme & Appearance", status = "primary", width = 6,
            p(style = "color:var(--tx-med); font-size:12px; margin-bottom:12px;",
              "Changes apply instantly — no reload needed."),
            selectInput("theme_select", "Colour Theme",
              choices = c(
                "Dark Mode (default)"   = "dark",
                "Light Mode"            = "light",
                "Colorblind-Friendly"   = "colorblind"
              ),
              selected = "dark"
            ),
            selectInput("accent_color", "Accent Colour",
              choices = c(
                "Orange (default)" = "#ff7f11",
                "Blue"             = "#1f77b4",
                "Green"            = "#2ca02c"
              ),
              selected = "#ff7f11"
            ),
            uiOutput("settings_active_theme"),
            uiOutput("settings_theme_preview")
          )
        )
      )
    )
  )
) # dashboardBody

