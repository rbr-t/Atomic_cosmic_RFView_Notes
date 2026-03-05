# ============================================================
# server_freq_planning.R
# ============================================================

serverFreqPlanning <- function(input, output, session, state) {
  # Unpack shared state
  rv                  <- state$rv
  lineup_components   <- state$lineup_components
  lineup_connections  <- state$lineup_connections
  lineup_calc_results <- state$lineup_calc_results
  canvas_data         <- state$canvas_data
  active_canvas_index <- state$active_canvas_index
  getUserTemplates    <- state$getUserTemplates
  getCanvasCount      <- state$getCanvasCount
  userTemplates       <- state$userTemplates

  # ============================================================
  # RF Frequency Planning Tool (Integrated)
  # ============================================================
  
  # Physical Models
  atm_loss_model <- function(fGHz) {
    o2_peak <- 15 * exp(-((fGHz - 60)^2) / (2*5^2))
    h2o_peak <- 8 * exp(-((fGHz - 22)^2) / (2*3^2))
    baseline <- 0.01 * fGHz
    baseline + o2_peak + h2o_peak
  }
  
  eff_ldmos <- function(f) pmax(65 - 0.8*f, 5)
  eff_gan   <- function(f) pmax(70 - 0.3*f, 20)
  eff_sige  <- function(f) pmax(50 - 0.15*f, 10)
  
  # Frequency Planning Canvas
  output$freq_planning_canvas <- renderPlotly({
    
    f <- seq(0.1, 300, length.out = 800)
    
    fig <- plot_ly()
    
    # Technology Suitability Map
    if(input$freq_show_tech){
      tech_map <- data.frame(
        tech = c("LDMOS","GaN","SiGe"),
        fmin = c(0.01, 1, 20),
        fmax = c(4, 100, 300),
        color = c("rgba(0,0,255,0.15)",
                  "rgba(0,255,0,0.15)",
                  "rgba(255,0,0,0.15)")
      )
      
      for(i in 1:nrow(tech_map)){
        fig <- fig %>%
          add_trace(
            x = c(tech_map$fmin[i], tech_map$fmax[i],
                  tech_map$fmax[i], tech_map$fmin[i], tech_map$fmin[i]),
            y = c(0, 0, 100, 100, 0),
            type = "scatter",
            mode = "lines",
            fill = "toself",
            fillcolor = tech_map$color[i],
            line = list(width = 0),
            name = tech_map$tech[i],
            hoverinfo = "text",
            text = paste("Technology:", tech_map$tech[i])
          )
      }
    }
    
    # Efficiency curves
    if(input$freq_show_eff){
      fig <- fig %>%
        add_lines(x = f, y = eff_ldmos(f), name = "LDMOS Efficiency (%)") %>%
        add_lines(x = f, y = eff_gan(f), name = "GaN Efficiency (%)") %>%
        add_lines(x = f, y = eff_sige(f), name = "SiGe Efficiency (%)")
    }
    
    # Atmospheric attenuation
    if(input$freq_show_atm){
      fig <- fig %>%
        add_lines(x = f, y = atm_loss_model(f),
                  name = "Atmospheric Loss (dB/km)",
                  yaxis = "y2")
    }
    
    # 6G band
    if(input$freq_show_6g){
      fig <- fig %>%
        add_trace(
          x = c(100, 300, 300, 100, 100),
          y = c(0, 0, 100, 100, 0),
          type = "scatter",
          fill = "toself",
          fillcolor = "rgba(200,0,200,0.2)",
          line = list(width = 0),
          name = "6G Sub-THz",
          hoverinfo = "text",
          text = "6G Candidate Band"
        )
    }
    
    # Target marker
    fig <- fig %>%
      add_markers(x = input$freq_target_freq,
                  y = 60,
                  marker = list(size = 12, color = "red"),
                  name = "Target Frequency")
    
    fig %>%
      layout(
        title = "Interactive Frequency Planning Canvas",
        xaxis = list(title = "Frequency (GHz)", type = "log",
                     range = c(log10(0.1), log10(300))),
        yaxis = list(title = "Efficiency (%)"),
        yaxis2 = list(title = "Atmospheric Loss (dB/km)",
                      overlaying = "y",
                      side = "right"),
        legend = list(orientation = "h"),
        hovermode = "closest"
      )
  })
  
  # Frequency Planning Table
  output$freq_planning_table <- renderDT({
    f_target <- input$freq_target_freq
    
    data <- data.frame(
      Parameter = c("Target Frequency", "LDMOS Efficiency", "GaN Efficiency", "SiGe Efficiency",
                    "Atmospheric Loss", "Wavelength (free space)", "Recommended Technology"),
      Value = c(
        sprintf("%.2f GHz", f_target),
        sprintf("%.1f%%", eff_ldmos(f_target)),
        sprintf("%.1f%%", eff_gan(f_target)),
        sprintf("%.1f%%", eff_sige(f_target)),
        sprintf("%.2f dB/km", atm_loss_model(f_target)),
        sprintf("%.2f mm", 3e8 / (f_target * 1e9) * 1000),
        if(f_target < 4) "LDMOS" else if(f_target < 100) "GaN" else "SiGe"
      )
    )
    
    datatable(data, options = list(pageLength = 10, dom = 't'), rownames = FALSE)
  })
  
  # Technology Recommendation
  output$freq_recommendation <- renderUI({
    
    f <- input$freq_target_freq
    
    tech <- if(f < 4) {
      "LDMOS (High power, macro base stations)"
    } else if(f < 100) {
      "GaN (Best tradeoff efficiency & power density)"
    } else {
      "SiGe / Advanced GaN MMIC (Sub-THz)"
    }
    
    HTML(paste0(
      "<h4>Recommended Technology</h4>",
      "<b>Frequency:</b> ", f, " GHz<br>",
      "<b>Output Power:</b> ", input$freq_target_power, " W<br><br>",
      "<b>Suggested Device:</b> ", tech
    ))
  })
  
  # Technology Selection based on fT and global frequency
  output$technology_fT_recommendation <- renderUI({
    # Use global frequency if available, otherwise use freq_target_freq
    freq <- input$global_frequency
    if(is.null(freq)) freq <- input$freq_target_freq
    if(is.null(freq)) return(NULL)
    
    required_fT <- freq * 5
    
    # Determine recommended technology based on fT requirement
    if(freq < 4) {
      tech <- "Si LDMOS"
      fT_range <- "20-40 GHz"
      expected_gain <- "15-18 dB"
      color <- "primary"
    } else if(freq < 12) {
      tech <- "GaAs pHEMT or GaN HEMT"
      fT_range <- "30-100 GHz"
      expected_gain <- "12-15 dB"
      color <- "success"
    } else if(freq < 40) {
      tech <- "GaN HEMT"
      fT_range <- "50-100 GHz"
      expected_gain <- "10-12 dB"
      color <- "success"
    } else if(freq < 100) {
      tech <- "SiGe HBT or GaN MMIC"
      fT_range <- "200-300 GHz"
      expected_gain <- "8-10 dB"
      color <- "warning"
    } else {
      tech <- "InP HEMT or Advanced SiGe"
      fT_range <- "300-600 GHz"
      expected_gain <- "6-8 dB"
      color <- "danger"
    }
    
    div(
      class = paste0("alert alert-", color),
      style = "margin-top: 15px;",
      HTML(sprintf("
        <h5><i class='fa fa-calculator'></i> Technology Recommendation for %.1f GHz</h5>
        <ul style='margin-bottom: 0;'>
          <li><strong>Minimum required fT:</strong> %.1f GHz (5 × %.1f GHz)</li>
          <li><strong>Recommended Technology:</strong> %s</li>
          <li><strong>Typical fT Range:</strong> %s</li>
          <li><strong>Expected Stage Gain:</strong> %s</li>
        </ul>
      ", freq, required_fT, freq, tech, fT_range, expected_gain))
    )
  })
  

}
