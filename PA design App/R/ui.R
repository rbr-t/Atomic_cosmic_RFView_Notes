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
    )
  ),
  
  # Sidebar
  dashboardSidebar(
    useShinyjs(),
    sidebarMenu(
      id = "sidebar_menu",
      menuItem("Dashboard", tabName = "dashboard", icon = icon("tachometer-alt")),
      menuItem("Projects", tabName = "projects", icon = icon("folder-open")),
      menuItem("Design Flow", tabName = "design", icon = icon("project-diagram"),
        menuSubItem("First Principles", tabName = "first_principles"),
        menuSubItem("Theoretical Calc", tabName = "theoretical_calc"),
        menuSubItem("Architecture", tabName = "architecture"),
        menuSubItem("Simulation", tabName = "simulation"),
        menuSubItem("Layout", tabName = "layout"),
        menuSubItem("Measurement", tabName = "measurement")
      ),
      menuItem("Data Manager", tabName = "data", icon = icon("database")),
      menuItem("RF Tools", tabName = "rf_tools", icon = icon("tools"),
        menuSubItem("Smith Chart", tabName = "smith_chart"),
        menuSubItem("RF Converters", tabName = "rf_converters"),
        menuSubItem("MTTF Calculator", tabName = "mttf_calc"),
        menuSubItem("Thermal Analysis", tabName = "thermal_calc")
      ),
      menuItem("AI Agents", tabName = "agents", icon = icon("robot")),
      menuItem("Knowledge Base", tabName = "knowledge", icon = icon("book")),
      menuItem("Settings", tabName = "settings", icon = icon("cog"))
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
      tags$style(HTML("
        /* Hardcoded fallbacks removed — all theming now in custom.css */
      "))
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
      tabItem(tabName = "theoretical_calc",
        h2("Theoretical Calculation Module"),
        fluidRow(
          box(
            title = "Project Selection",
            width = 12,
            status = "primary",
            solidHeader = TRUE,
            collapsible = TRUE,
            selectInput("calc_project_select", "Select Project", choices = NULL),
            verbatimTextOutput("calc_project_specs")
          )
        ),
        fluidRow(
          tabBox(
            width = 12,
            id = "theoretical_calc_tabs",
            
            # ======================================
            # Tab 1: Frequency Planning Tool
            # ======================================
            tabPanel(
              title = tagList(icon("satellite-dish"), "Frequency Planning"),
              value = "freq_planning",
              
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
                      numericInput("freq_target_power", "Target Power (W)", value = 20, min = 0.1, max = 1000)
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
              
              hr(),
              
              # Tabset for Technology References
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
                    <div style='background-color: #f8f9fa; padding: 15px; border-left: 4px solid #17a2b8; margin: 10px 0;'>
                      <h5><i class='fa fa-info-circle'></i> Selection Rule of Thumb</h5>
                      <p><strong>For operating frequency fop, select technology with: fT > 5 × fop</strong></p>
                      <p style='color: #666; font-size: 13px;'>This ensures sufficient gain and prevents instability at the design frequency.</p>
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
                    <div style='background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 10px 0;'>
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
                        <div style='background: #f8f9fa; padding: 15px; border-radius: 5px; height: 100%;'>
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
                        <div style='background: #f8f9fa; padding: 15px; border-radius: 5px; height: 100%;'>
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
                    <div style='background: #e7f3ff; padding: 15px; border-left: 4px solid #007bff; margin: 10px 0;'>
                      <p style='margin: 0;'><strong>G<sub>available</sub>(f<sub>op</sub>) ≈ 20 × log<sub>10</sub>(fT / f<sub>op</sub>) dB</strong></p>
                      <p style='margin: 5px 0 0 0; font-size: 13px; color: #666;'>Example: With fT = 100 GHz at f<sub>op</sub> = 10 GHz → G ≈ 20 dB</p>
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
                        <div style='background: #d4edda; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745;'>
                          <h6><strong><i class='fa fa-check-circle'></i> Safe Range</strong></h6>
                          <p style='font-size: 14px; margin: 0;'>f<sub>op</sub> < fT / 10</p>
                          <p style='font-size: 12px; color: #666; margin: 5px 0 0 0;'>High gain, excellent stability, easy matching</p>
                        </div>
                      </div>
                      <div class='col-md-4'>
                        <div style='background: #fff3cd; padding: 15px; border-radius: 5px; border-left: 4px solid #ffc107;'>
                          <h6><strong><i class='fa fa-exclamation-triangle'></i> Acceptable Range</strong></h6>
                          <p style='font-size: 14px; margin: 0;'>fT / 10 < f<sub>op</sub> < fT / 5</p>
                          <p style='font-size: 12px; color: #666; margin: 5px 0 0 0;'>Moderate gain, requires attention to stability</p>
                        </div>
                      </div>
                      <div class='col-md-4'>
                        <div style='background: #f8d7da; padding: 15px; border-radius: 5px; border-left: 4px solid #dc3545;'>
                          <h6><strong><i class='fa fa-times-circle'></i> Avoid</strong></h6>
                          <p style='font-size: 14px; margin: 0;'>f<sub>op</sub> > fT / 5</p>
                          <p style='font-size: 12px; color: #666; margin: 5px 0 0 0;'>Low gain, stability issues, difficult matching</p>
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
                    
                    <div style='background-color: #e7f3ff; padding: 15px; border-left: 4px solid #007bff; margin: 20px 0;'>
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
            
            # ======================================
            # Tab 2: Link Budget Calculator
            # ======================================
            tabPanel(
              title = tagList(icon("link"), "Link Budget"),
              value = "link_budget",
              
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
            ),
            
            # ======================================
            # Tab 3: Passive Component Loss Curves
            # ======================================
            tabPanel(
              title = tagList(icon("chart-line"), "Loss Curves"),
              value = "loss_curves",
              
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
                          div(style = "background-color: #f8f9fa; padding: 15px; border-left: 4px solid #ff851b; margin-top: 10px;",
                            h4(icon("arrow-right"), " Estimated Loss:"),
                            h3(textOutput("loss_calc_result", inline = TRUE), style = "color: #ff851b; margin: 5px 0;"),
                            p("dB", style = "color: #666; margin: 0;")
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
                          <div style='background-color: #d1ecf1; padding: 15px; border-left: 4px solid #0c5460; margin-bottom: 15px;'>
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
                          <p style='background-color: #f8f9fa; padding: 10px; font-family: monospace;'>
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
                          
                          <div style='background-color: #fff3cd; padding: 15px; border-left: 4px solid #856404; margin-top: 15px;'>
                            <h5><i class='fa fa-lightbulb'></i> Pro Tip</h5>
                            <p><strong>At mmWave (>20 GHz):</strong> Passive losses can exceed active device gains! Consider integrated approaches or waveguide structures to minimize interconnect.</p>
                          </div>
                        ")
                      )
                    )
                  )
                )
              )
            ),
            
            # ======================================
            # Tab 4: Performance Guardrails
            # ======================================
            tabPanel(
              title = tagList(icon("shield-alt"), "Performance Guardrails"),
              value = "perf_guardrails",

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
                    p(style = "font-size:12px; color:#aaa;",
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
                    p(style = "font-size:12px; color:#aaa; margin-bottom:8px;",
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
                    p(style = "font-size:11px; font-weight:bold; color:#aaa; text-transform:uppercase;",
                      "Saved Devices:"),
                    uiOutput("grd_saved_devices_list")
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
                        style = "background:#1e2d1e; border-left:4px solid #70AD47; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:#ccc;",
                          icon("info-circle"), " ",
                          strong(style="color:#fff;", "How to read this chart:"),
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
                        style = "background:#1e2428; border-left:4px solid #4472C4; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:#ccc;",
                          icon("info-circle"), " ",
                          strong(style="color:#fff;", "Gain envelope from fT:"),
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
                        style = "background:#2a1e1e; border-left:4px solid #FFC000; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:#ccc;",
                          icon("info-circle"), " ",
                          strong(style="color:#fff;", "PAE backoff behaviour by PA class:"),
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
                          p(style="font-size:11px;color:#aaa;", "= PAR / system BO from P3dB")
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
                        style = "background:#1e1e2a; border-left:4px solid #7030A0; padding:10px 15px; margin-bottom:12px; border-radius:3px;",
                        p(style = "margin:0; font-size:13px; color:#ccc;",
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
            ),

            # ======================================
            # Tab 5: PA Lineup Calculator (Enhanced Interactive)
            # ======================================
            tabPanel(
              title = tagList(icon("project-diagram"), "PA Lineup"),
              value = "pa_lineup",
              
              fluidRow(
                # Left: Interactive Canvas
                column(8,
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
                          " Templates"
                        ),
                        
                        # Top sidebar content
                        div(
                          class = "top-sidebar-content",
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
                            tags$div(class = "sidebar-section-label", style = "font-size: 10px; color: #999; margin: 15px 10px 5px 10px; text-transform: uppercase; letter-spacing: 0.5px; border-top: 1px solid rgba(255,255,255,0.1); padding-top: 10px;", "USER SAVED TEMPLATES"),
                            tags$div(id = "user_templates_top_sidebar",
                              uiOutput("user_templates_top_display")
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
                column(4,
                  # Specifications Box (NEW)
                  box(
                    title = tagList(icon("clipboard-list"), "Specifications"),
                    width = 12,
                    status = "info",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    collapsed = TRUE,
                    
                    # PRIMARY LINEUP DRIVING PARAMETERS (highlighted)
                    div(style = "background-color: #fff3cd; padding: 10px; border-left: 4px solid #ff851b; margin-bottom: 15px;",
                      h5(icon("star"), " PRIMARY LINEUP DRIVERS", style = "color: #ff851b; margin-top: 0;"),
                      fluidRow(
                        column(6,
                          div(style = "border: 2px solid #ff851b; border-radius: 4px; padding: 5px; background-color: #fffbf5;",
                            numericInput("spec_frequency", 
                              tags$strong("⚡ Frequency (MHz)", style = "color: #ff851b;"), 
                              value = 1805, min = 100, max = 10000, step = 1)
                          )
                        ),
                        column(6,
                          div(style = "border: 2px solid #ff851b; border-radius: 4px; padding: 5px; background-color: #fffbf5;",
                            numericInput("spec_p3db", 
                              tags$strong("⚡ P3dB Output (dBm)", style = "color: #ff851b;"), 
                              value = 55.3, min = 0, max = 80, step = 0.1)
                          )
                        ),
                        column(6,
                          div(style = "border: 2px solid #ff851b; border-radius: 4px; padding: 5px; background-color: #fffbf5;",
                            numericInput("spec_par", 
                              tags$strong("⚡ PAR / BO (dB)", style = "color: #ff851b;"), 
                              value = 8.0, min = 0, max = 20, step = 0.1),
                            tags$small("Pavg = P3dB - PAR", style = "color: #999;")
                          )
                        )
                      ),
                      fluidRow(
                        column(6,
                          div(style = "border: 2px solid #ff851b; border-radius: 4px; padding: 5px; background-color: #fffbf5;",
                            numericInput("spec_gain", 
                              tags$strong("⚡ Total Gain (dB)", style = "color: #ff851b;"), 
                              value = 41.5, min = 0, max = 80, step = 0.1)
                          )
                        ),
                        column(6,
                          numericInput("spec_supply_voltage", "Supply Voltage (V)", 
                            value = 30, min = 5, max = 50, step = 1)
                        )
                      ),
                      fluidRow(
                        column(4,
                          numericInput("spec_bw_lower", "BW Lower Margin (%)", 
                            value = 10, min = 0, max = 50, step = 1)
                        ),
                        column(4,
                          numericInput("spec_bw_upper", "BW Upper Margin (%)", 
                            value = 10, min = 0, max = 50, step = 1)
                        ),
                        column(4,
                          div(style = "margin-top: 25px;",
                            strong("Bandwidth:"),
                            textOutput("spec_bandwidth_display", inline = TRUE),
                            tags$span(" MHz", style = "color: #666;")
                          )
                        )
                      )
                    ),
                    
                    # SECONDARY SPECIFICATIONS
                    h5(icon("sliders-h"), " Secondary Specifications", style = "margin-top: 5px;"),
                    fluidRow(
                      column(6,
                        numericInput("spec_efficiency", "Efficiency (%)", value = 47, min = 0, max = 100, step = 1)
                      ),
                      column(6,
                        numericInput("spec_vbw", "VBW (MHz)", value = 225, min = 1, max = 1000, step = 1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("spec_am_pm_p3db", "AM-PM @ P3dB (deg)", value = -25, min = -50, max = 50, step = 0.1)
                      ),
                      column(6,
                        numericInput("spec_am_pm_dispersion", "AM-PM Dispersion (deg)", value = 8, min = 0, max = 50, step = 0.1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("spec_group_delay", "Group Delay Flatness (ns)", value = 1, min = 0, max = 100, step = 0.1)
                      ),
                      column(6,
                        numericInput("spec_efficiency", "Efficiency (%)", value = 47, min = 0, max = 100, step = 1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("spec_acp", "ACP (dBc)", value = -30, min = -80, max = 0, step = 0.1)
                      ),
                      column(6,
                        numericInput("spec_gain_ripple_inband", "Gain Ripple In-band (dB)", value = 1.0, min = 0, max = 10, step = 0.1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("spec_gain_ripple_3xband", "Gain Ripple 3x Band (dB)", value = 3.0, min = 0, max = 10, step = 0.1)
                      ),
                      column(6,
                        numericInput("spec_input_return_loss", "Input Return Loss (dB)", value = -15, min = -50, max = 0, step = 0.1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("spec_vbw", "VBW (MHz)", value = 225, min = 1, max = 1000, step = 1)
                      ),
                      column(6,
                        selectInput("spec_test_conditions", "Test Conditions",
                          choices = c(
                            "DC" = "dc",
                            "CW" = "cw",
                            "NVA Sweep 25ms" = "nva_25ms",
                            "Nokia LTE 1c 10MHz" = "nokia_lte",
                            "Low Freq Resonance" = "low_freq_res"
                          ),
                          selected = "cw"
                        )
                      )
                    ),
                    helpText(icon("info-circle"), " Target specifications for the PA lineup design."),
                    hr(),
                    div(style = "display: flex; gap: 10px; margin-top: 10px;",
                      actionButton("apply_specs_to_lineup", 
                                   "Apply Specs to Lineup ↓", 
                                   class = "btn-primary btn-block", 
                                   icon = icon("arrow-down"),
                                   style = "flex: 1;"),
                      actionButton("apply_specs_to_global", 
                                   "Update Global Params ↓", 
                                   class = "btn-info", 
                                   icon = icon("sync"),
                                   style = "flex: 1;")
                    ),
                    helpText(icon("lightbulb"), " 'Apply to Lineup' adapts current template. 'Update Global' only updates frequency/power.")
                  ),
                  
                  # Global Lineup Parameters
                  box(
                    title = tagList(icon("globe"), "Global Lineup Parameters"),
                    width = 12,
                    status = "primary",
                    solidHeader = TRUE,
                    collapsible = TRUE,
                    fluidRow(
                      column(6,
                        numericInput("global_frequency", "Frequency (GHz)", 
                          value = 2.6, min = 0.1, max = 100, step = 0.1)
                      ),
                      column(6,
                        numericInput("global_pout_p3db", tags$strong("Pout (P3dB) (dBm)"), 
                          value = 55.3, min = 0, max = 80, step = 0.1)
                      )
                    ),
                    fluidRow(
                      column(6,
                        numericInput("global_backoff", "Back-off (dB)", 
                          value = 6, min = 0, max = 20, step = 0.5)
                      ),
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
                          tags$span(" (from specs)", style = "color: #999; font-size: 12px;")
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
                  box(
                    title = "Component Properties",
                    width = 12,
                    collapsible = TRUE,
                    status = "warning",
                    solidHeader = TRUE,
                    uiOutput("lineup_property_editor")
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
                    uiOutput("pa_lineup_tables_dynamic")
                  ),
                  
                  # Equations View
                  tabPanel(
                    title = tagList(icon("calculator"), "Equations & Rationale"),
                    uiOutput("pa_lineup_equations_dynamic")
                  )
                )
              )
            )
          )
        )
      ),
      
      # Placeholder tabs (to be implemented)
      tabItem(tabName = "first_principles",
        h2("First Principles Module"),
        p("Module under construction - validates design feasibility based on fundamental RF theory.")
      ),
      
      tabItem(tabName = "architecture",
        h2("Architecture Selection Module"),
        p("Module under construction - recommends PA architecture and topology.")
      ),
      
      tabItem(tabName = "simulation",
        h2("Simulation Module"),
        p("Module under construction - integrates with ADS/AWR via MCP.")
      ),
      
      tabItem(tabName = "layout",
        h2("Layout Module"),
        p("Module under construction - reviews layout for RF best practices.")
      ),
      
      tabItem(tabName = "measurement",
        h2("Measurement Module"),
        p("Module under construction - controls lab equipment and analyzes data.")
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
      
      # RF Tools: MTTF Calculator
      tabItem(tabName = "mttf_calc",
        h2("⏱️ MTTF (Mean Time To Failure) Calculator"),
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
      
      # RF Tools: Thermal Analysis
      tabItem(tabName = "thermal_calc",
        h2("🌡️ Thermal Analysis"),
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
      
      # Settings Tab
      tabItem(tabName = "settings",
        h2("Application Settings"),
        fluidRow(
          # ── Theme & Appearance ───────────────────────────────────────
          box(
            title = "Theme & Appearance", status = "primary", width = 6,
            p(style = "color:#aaa; font-size:12px; margin-bottom:12px;",
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
          ),
          # ── RF Design Defaults ─────────────────────────────────────
          box(
            title = "RF Design Defaults", status = "primary", width = 6,
            p(style = "color:#aaa; font-size:12px; margin-bottom:12px;",
              "Default values pre-populated in new design calculations."),
            numericInput("default_freq_ghz", "Default Frequency (GHz)",
                         value = 3.5, min = 0.1, max = 300, step = 0.1),
            selectInput("default_technology", "Default Technology",
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
            numericInput("default_vdd", "Default Supply Voltage (V)",
                         value = 28, min = 1, max = 65, step = 1)
          )
        )
      )
    )
  )
)

