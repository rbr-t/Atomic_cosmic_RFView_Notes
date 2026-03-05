# ============================================================
# server_link_budget.R
# ============================================================

serverLinkBudget <- function(input, output, session, state) {
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
  # Link Budget Calculator
  # ============================================================
  
  # Reactive values for link budget
  link_budget_data <- reactive({
    input$link_calculate
    
    # Calculate FSPL (Free Space Path Loss)
    fspl <- 20 * log10(input$link_distance) + 20 * log10(input$link_freq) + 92.45
    
    # Calculate received power
    p_rx <- input$link_tx_power + input$link_tx_gain - fspl + input$link_rx_gain
    
    # Calculate noise power
    bw_hz <- input$link_bandwidth * 1e6
    noise_power <- -174 + 10 * log10(bw_hz) + input$link_noise_figure
    
    # Calculate SNR
    snr <- p_rx - noise_power
    
    # Calculate margin
    margin <- snr - input$link_snr_req
    
    list(
      fspl = fspl,
      p_rx = p_rx,
      noise_power = noise_power,
      snr = snr,
      margin = margin,
      status = if(margin > 0) "PASS" else "FAIL"
    )
  })
  
  # Link Budget Canvas
  output$link_budget_canvas <- renderPlotly({
    ld <- link_budget_data()
    
    # Visual representation of link budget stages
    stages <- c("Tx Power", "Tx Gain", "Path Loss", "Rx Gain", "Rx Power", "Noise", "SNR")
    values <- c(
      input$link_tx_power,
      input$link_tx_power + input$link_tx_gain,
      input$link_tx_power + input$link_tx_gain - ld$fspl,
      ld$p_rx,
      ld$p_rx,
      ld$noise_power,
      ld$snr
    )
    
    x_pos <- 1:7
    colors <- c("blue", "green", "red", "green", "orange", "purple", 
                if(ld$margin > 0) "green" else "red")
    
    # Create visual flow diagram
    fig <- plot_ly()
    
    # Add bars showing power levels
    for(i in 1:length(stages)) {
      fig <- fig %>%
        add_trace(
          x = x_pos[i],
          y = values[i],
          type = "bar",
          name = stages[i],
          marker = list(color = colors[i]),
          text = sprintf("%s<br>%.2f dBm", stages[i], values[i]),
          hoverinfo = "text"
        )
    }
    
    # Add connection arrows annotations
    annotations <- list()
    for(i in 1:(length(stages)-1)) {
      annotations[[i]] <- list(
        x = x_pos[i] + 0.5,
        y = max(values) * 0.9,
        text = "→",
        showarrow = FALSE,
        font = list(size = 20)
      )
    }
    
    # Add margin line
    fig <- fig %>%
      add_trace(
        x = x_pos,
        y = rep(input$link_snr_req + ld$noise_power, length(x_pos)),
        type = "scatter",
        mode = "lines",
        name = "Required Power",
        line = list(color = "red", dash = "dash", width = 2)
      )
    
    fig %>%
      layout(
        title = sprintf("Link Budget Canvas - Margin: %.2f dB (%s)", ld$margin, ld$status),
        xaxis = list(title = "Link Budget Stages", tickvals = x_pos, ticktext = stages),
        yaxis = list(title = "Power Level (dBm)"),
        showlegend = TRUE,
        annotations = annotations,
        hovermode = "closest"
      )
  })
  
  # Link Budget Table
  output$link_budget_table <- renderDT({
    ld <- link_budget_data()
    
    data <- data.frame(
      Parameter = c(
        "Tx Power", "Tx Antenna Gain", "EIRP", "Free Space Path Loss",
        "Rx Antenna Gain", "Received Power", "Noise Power", "SNR", 
        "Required SNR", "Link Margin", "Status"
      ),
      Value = c(
        sprintf("%.2f dBm", input$link_tx_power),
        sprintf("%.2f dBi", input$link_tx_gain),
        sprintf("%.2f dBm", input$link_tx_power + input$link_tx_gain),
        sprintf("%.2f dB", ld$fspl),
        sprintf("%.2f dBi", input$link_rx_gain),
        sprintf("%.2f dBm", ld$p_rx),
        sprintf("%.2f dBm", ld$noise_power),
        sprintf("%.2f dB", ld$snr),
        sprintf("%.2f dB", input$link_snr_req),
        sprintf("%.2f dB", ld$margin),
        ld$status
      ),
      Unit = c("dBm", "dBi", "dBm", "dB", "dBi", "dBm", "dBm", "dB", "dB", "dB", "-")
    )
    
    datatable(data, options = list(pageLength = 15, dom = 't'), rownames = FALSE) %>%
      formatStyle('Value', 
        target = 'row',
        backgroundColor = styleEqual(c('FAIL', 'PASS'), c('rgba(255,0,0,0.2)', 'rgba(0,255,0,0.2)'))
      )
  })
  
  # Link Budget Summary
  output$link_budget_summary <- renderUI({
    ld <- link_budget_data()
    
    color <- if(ld$margin > 10) "green" else if(ld$margin > 0) "orange" else "red"
    status_icon <- if(ld$margin > 0) "✓" else "✗"
    
    HTML(paste0(
      "<h4 style='color:", color, ";'>", status_icon, " Link Budget Summary</h4>",
      "<b>Distance:</b> ", input$link_distance, " km<br>",
      "<b>Frequency:</b> ", input$link_freq, " GHz<br>",
      "<b>Path Loss:</b> ", sprintf("%.2f dB", ld$fspl), "<br>",
      "<b>Received Power:</b> ", sprintf("%.2f dBm", ld$p_rx), "<br>",
      "<b>SNR:</b> ", sprintf("%.2f dB", ld$snr), "<br>",
      "<b>Link Margin:</b> <span style='font-size:18px;'><b>", sprintf("%.2f dB", ld$margin), "</b></span><br><br>",
      if(ld$margin > 10) {
        "<p style='color:green;'>✓ Excellent link margin - system is robust against fading</p>"
      } else if(ld$margin > 3) {
        "<p style='color:orange;'>⚠ Adequate margin but consider adding fade margin for reliability</p>"
      } else if(ld$margin > 0) {
        "<p style='color:orange;'>⚠ Marginal - vulnerable to atmospheric effects and multipath</p>"
      } else {
        "<p style='color:red;'>✗ Insufficient margin - link will fail. Increase Tx power, antenna gain, or reduce distance</p>"
      }
    ))
  })
  

}
