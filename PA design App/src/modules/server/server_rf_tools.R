# ============================================================
# server_rf_tools.R
# ============================================================

serverRfTools <- function(input, output, session, state) {
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
  # RF Tools: Converters (Placeholder Implementation)
  # ============================================================
  
  output$conv_power_results <- renderText({
    watt <- input$conv_power_watt
    dbm <- 10 * log10(watt * 1000)
    dbw <- 10 * log10(watt)
    paste0(
      "Power Conversions:\n",
      "================\n",
      sprintf("%.4f W = %.2f dBm = %.2f dBW\n", watt, dbm, dbw)
    )
  })
  
  output$conv_dbm_results <- renderText({
    dbm <- input$conv_power_dbm
    watt <- 10^(dbm/10) / 1000
    dbw <- dbm - 30
    paste0(
      "Power Conversions:\n",
      "================\n",
      sprintf("%.2f dBm = %.6f W = %.2f dBW\n", dbm, watt, dbw)
    )
  })
  
  output$conv_voltage_results <- renderText({
    v <- input$conv_voltage
    z <- input$conv_impedance
    power_w <- v^2 / z
    power_dbm <- 10 * log10(power_w * 1000)
    current_a <- v / z
    paste0(
      "Voltage/Power Conversions:\n",
      "=========================\n",
      sprintf("Voltage: %.4f V\n", v),
      sprintf("Impedance: %.2f \u03a9\n", z),
      sprintf("Power: %.4f W (%.2f dBm)\n", power_w, power_dbm),
      sprintf("Current: %.4f A\n", current_a)
    )
  })
  
  output$conv_freq_results <- renderText({
    freq_ghz <- input$conv_freq
    freq_hz <- freq_ghz * 1e9
    er <- if(input$conv_medium == "0") input$conv_er_custom else as.numeric(input$conv_medium)
    lambda_m <- 3e8 / freq_hz
    lambda_eff_m <- lambda_m / sqrt(er)
    lambda_mm <- lambda_m * 1000
    lambda_eff_mm <- lambda_eff_m * 1000
    paste0(
      "Frequency/Wavelength Conversions:\n",
      "=================================\n",
      sprintf("Frequency: %.4f GHz = %.2f MHz\n", freq_ghz, freq_ghz * 1000),
      sprintf("Free Space Wavelength: %.2f mm\n", lambda_mm),
      sprintf("Effective Wavelength (\u03b5r=%.2f): %.2f mm\n", er, lambda_eff_mm),
      sprintf("Quarter-wave: %.2f mm\n", lambda_eff_mm / 4),
      sprintf("Half-wave: %.2f mm\n", lambda_eff_mm / 2)
    )
  })
  
  output$conv_sparams_results <- renderText({
    s11_mag <- input$conv_s11_mag
    s11_phase <- input$conv_s11_phase
    gamma_real <- s11_mag * cos(s11_phase * pi/180)
    gamma_imag <- s11_mag * sin(s11_phase * pi/180)
    return_loss_db <- -20 * log10(s11_mag)
    vswr <- (1 + s11_mag) / (1 - s11_mag)
    paste0(
      "S-Parameter Conversions:\n",
      "=======================\n",
      sprintf("S11: %.4f \u2220 %.2f\u00b0\n", s11_mag, s11_phase),
      sprintf("\u0393: %.4f %+.4fj\n", gamma_real, gamma_imag),
      sprintf("Return Loss: %.2f dB\n", return_loss_db),
      sprintf("VSWR: %.2f:1\n", vswr)
    )
  })
  
  # ============================================================
  # RF Tools: Smith Chart — full implementation
  # ============================================================

  # ── Helper: generate all Smith Chart grid traces ─────────────────────────
  .smith_grid <- function() {
    GRID   <- "rgba(80,100,80,0.55)"
    GRID_H <- "rgba(130,170,130,0.8)"   # highlighted (r=0,1 / x=±1)
    n      <- 300
    theta  <- seq(0, 2 * pi, length.out = n)
    traces <- list()

    # Unit circle
    traces <- c(traces, list(list(
      x = cos(theta), y = sin(theta),
      line = list(color = "rgba(200,210,200,0.75)", width = 1.6),
      name = "|Γ|=1"
    )))

    # Real axis
    traces <- c(traces, list(list(
      x = c(-1, 1), y = c(0, 0),
      line = list(color = "rgba(160,160,160,0.45)", width = 0.8),
      name = "real_ax"
    )))

    # Constant-R circles: center=(r/(1+r),0), radius=1/(1+r)
    for (r in c(0, 0.2, 0.5, 1, 2, 5, 10)) {
      cx  <- r / (1 + r)
      rad <- 1 / (1 + r)
      col <- if (r %in% c(0, 1)) GRID_H else GRID
      lw  <- if (r %in% c(0, 1)) 1.0 else 0.65
      traces <- c(traces, list(list(
        x    = cx + rad * cos(theta),
        y    =      rad * sin(theta),
        line = list(color = col, width = lw),
        name = paste0("R=", r)
      )))
    }

    # Constant-X arcs: center=(1,1/x), radius=1/|x|, clipped to |Γ|≤1
    for (xv in c(0.2, 0.5, 1, 2, 5, 10, -0.2, -0.5, -1, -2, -5, -10)) {
      cx  <- 1
      cy  <- 1 / xv
      rad <- 1 / abs(xv)
      px  <- cx + rad * cos(theta)
      py  <- cy + rad * sin(theta)
      outside     <- (px^2 + py^2) > 1.0005
      px[outside] <- NA
      py[outside] <- NA
      col <- if (abs(xv) == 1) GRID_H else GRID
      lw  <- if (abs(xv) == 1) 1.0 else 0.65
      traces <- c(traces, list(list(
        x = px, y = py,
        line = list(color = col, width = lw),
        name = paste0("X=", xv)
      )))
    }
    traces
  }

  # ── Reactive: stored impedance points ────────────────────────────────────
  smith_pts <- reactiveVal(data.frame(
    label  = character(),
    z_real = numeric(),
    z_imag = numeric(),
    color  = character(),
    stringsAsFactors = FALSE
  ))

  # z → Γ helper
  .z_to_gamma <- function(z_real, z_imag, z0 = 50) {
    z     <- complex(real = z_real, imaginary = z_imag)
    gamma <- (z - z0) / (z + z0)
    list(re = Re(gamma), im = Im(gamma))
  }

  # Add point button
  observeEvent(input$smith_add_point, {
    req(input$smith_z_real)
    z0  <- as.numeric(input$smith_z0 %||% 50)
    pts <- smith_pts()
    lbl <- if (!is.null(input$smith_label) && nzchar(input$smith_label))
      input$smith_label else paste0("Z", nrow(pts) + 1)
    cols <- c("#ff7f11","#1f77b4","#2ca02c","#d62728","#9467bd","#8c564b","#e377c2")
    col  <- cols[(nrow(pts) %% length(cols)) + 1]
    new_row <- data.frame(
      label  = lbl,
      z_real = as.numeric(input$smith_z_real),
      z_imag = as.numeric(input$smith_z_imag),
      color  = col,
      stringsAsFactors = FALSE
    )
    smith_pts(rbind(pts, new_row))
  })

  # Clear
  observeEvent(input$smith_clear, {
    smith_pts(data.frame(label=character(), z_real=numeric(),
                         z_imag=numeric(), color=character(),
                         stringsAsFactors=FALSE))
  })

  # ── Main Smith Chart plot ─────────────────────────────────────────────────
  output$smith_chart_plot <- renderPlotly({
    z0   <- as.numeric(input$smith_z0 %||% 50)
    grid <- .smith_grid()

    p <- plot_ly()

    # Grid traces
    for (tr in grid) {
      p <- p %>% add_trace(
        type = "scatter", mode = "lines",
        x = tr$x, y = tr$y,
        line = tr$line,
        name = tr$name,
        hoverinfo = "none",
        showlegend = FALSE
      )
    }

    pts <- smith_pts()
    if (nrow(pts) > 0) {
      z     <- complex(real = pts$z_real, imaginary = pts$z_imag)
      gamma <- (z - z0) / (z + z0)
      hover <- sprintf(
        "<b>%s</b><br>Z = %.2f %+.2fj Ω<br>Γ = %.3f %+.3fj<br>|Γ| = %.3f",
        pts$label, pts$z_real, pts$z_imag, Re(gamma), Im(gamma), Mod(gamma)
      )
      p <- p %>% add_trace(
        type      = "scatter",
        mode      = "markers+text",
        x         = Re(gamma),
        y         = Im(gamma),
        text      = pts$label,
        textposition = "top center",
        hovertext = hover,
        hoverinfo = "text",
        marker    = list(size = 11, color = pts$color,
                         line = list(color = "white", width = 1.2)),
        showlegend = TRUE,
        name      = "Points"
      )
    }

    p %>% layout(
      paper_bgcolor = "#1b1b2b",
      plot_bgcolor  = "#1b1b2b",
      xaxis = list(
        title      = "Real(\u0393)",
        range      = c(-1.25, 1.25),
        zeroline   = FALSE,
        showgrid   = FALSE,
        color      = "#aaa",
        tickfont   = list(color = "#aaa"),
        scaleanchor = "y",
        scaleratio  = 1
      ),
      yaxis = list(
        title    = "Imag(\u0393)",
        range    = c(-1.25, 1.25),
        zeroline = FALSE,
        showgrid = FALSE,
        color    = "#aaa",
        tickfont = list(color = "#aaa")
      ),
      title  = list(text = paste0("Smith Chart  (Z\u2080 = ", z0, " \u03a9)"),
                    font = list(color = "#eee", size = 14)),
      font   = list(color = "#aaa"),
      legend = list(font = list(color = "#aaa"), bgcolor = "rgba(0,0,0,0.35)",
                    x = 1.02, y = 1),
      margin = list(l = 50, r = 10, t = 50, b = 50)
    )
  })

  # ── Matching network synthesis text ──────────────────────────────────────
  output$smith_components <- renderText({
    pts <- smith_pts()
    z0  <- as.numeric(input$smith_z0 %||% 50)
    if (nrow(pts) == 0) {
      return("Add impedance points using the controls on the left.\n\nTip: enter Z real/imag + optional label, then click Add Point.")
    }
    z    <- complex(real = pts$z_real, imaginary = pts$z_imag)
    gam  <- (z - z0) / (z + z0)
    lines_out <- c(
      sprintf("%-8s  Z (Ω)              Γ              |Γ|    RL (dB)",
              "Label"),
      strrep("-", 60)
    )
    for (i in seq_len(nrow(pts))) {
      rl <- if (Mod(gam[i]) > 0) -20 * log10(Mod(gam[i])) else Inf
      lines_out <- c(lines_out,
        sprintf("%-8s  %6.2f %+6.2fj    %6.3f %+6.3fj   %.3f  %5.1f dB",
                pts$label[i], pts$z_real[i], pts$z_imag[i],
                Re(gam[i]), Im(gam[i]), Mod(gam[i]), rl))
    }

    # Matching between first two points if ≥ 2
    if (nrow(pts) >= 2) {
      z1 <- z[1]; z2 <- z[2]
      lines_out <- c(lines_out, "", strrep("-", 60),
        "L-section matching  (Point 1 → Point 2):",
        "")
      # Simple L-section: series element first
      # Equations: shunt B, series X  to transform Z1 → Z2*
      # Simplified: report qualitative direction
      delta_r <- Re(z2) - Re(z1)
      delta_x <- Im(z2) - Im(z1)
      series_type <- if (delta_x > 0) "Inductor" else if (delta_x < 0) "Capacitor" else "None"
      lines_out <- c(lines_out,
        sprintf("  \u0394R = %+.2f Ω  \u0394X = %+.2f Ω", delta_r, delta_x),
        sprintf("  Series element hint: %s", series_type),
        "",
        "Full lossless L/Pi/T synthesis: coming in next release.")
    }
    paste(lines_out, collapse = "\n")
  })
  
  # ============================================================
  # RF Tools: MTTF Calculator (Placeholder)
  # ============================================================
  
  observeEvent(input$mttf_calculate, {
    output$mttf_results <- renderText({
      tj <- input$mttf_tj
      ta <- input$mttf_ta
      pdiss <- input$mttf_power_diss
      rth <- input$mttf_rth
      Ea <- 0.7; k <- 8.617e-5; T_ref <- 398
      T_op <- tj + 273
      AF <- exp((Ea/k) * (1/T_ref - 1/T_op))
      MTTF_base <- 1e6
      voltage_factor <- input$mttf_voltage_stress^2
      current_factor <- input$mttf_current_stress^2
      MTTF_adj <- MTTF_base * AF / (voltage_factor * current_factor)
      MTTF_years <- MTTF_adj / 8760
      paste0(
        "MTTF Analysis Results:\n",
        "=====================\n\n",
        sprintf("Device Type: %s\n", input$mttf_device_type),
        sprintf("Junction Temperature: %.1f\u00b0C\n", tj),
        sprintf("Ambient Temperature: %.1f\u00b0C\n", ta),
        sprintf("Power Dissipation: %.2f W\n", pdiss),
        sprintf("Temperature Rise: %.1f\u00b0C\n", pdiss * rth),
        "\n",
        sprintf("Acceleration Factor: %.2f\n", AF),
        sprintf("Voltage Stress Factor: %.2f\n", voltage_factor),
        sprintf("Current Stress Factor: %.2f\n", current_factor),
        "\n",
        sprintf("MTTF: %.0f hours (%.1f years)\n", MTTF_adj, MTTF_years),
        sprintf("Failure Rate (\u03bb): %.2e failures/hour\n", 1/MTTF_adj)
      )
    })
    
    output$mttf_plot <- renderPlotly({
      # Placeholder reliability curve
      time <- seq(0, 200000, length.out = 100)
      reliability <- exp(-time / 1e6)
      
      plot_ly(x = time, y = reliability * 100, type = "scatter", mode = "lines",
              line = list(color = "green", width = 2)) %>%
        layout(
          title = "Reliability vs Time",
          xaxis = list(title = "Time (hours)"),
          yaxis = list(title = "Reliability (%)")
        )
    })
    
    output$mttf_recommendations <- renderUI({
      HTML(paste0(
        "<ul>",
        "<li>Reduce junction temperature by improving thermal management</li>",
        "<li>Operate at lower voltage/current for extended lifetime</li>",
        "<li>Consider derating factors for mission-critical applications</li>",
        "<li>Implement temperature monitoring and protection</li>",
        "</ul>"
      ))
    })
  })
  
  # ============================================================
  # RF Tools: Thermal Analysis (Placeholder)
  # ============================================================
  
  output$therm_pdiss <- renderText({
    pout <- input$therm_pout
    pae <- input$therm_efficiency / 100
    pdc <- pout / pae
    pdiss <- pdc - pout
    paste0(
      sprintf("DC Power: %.2f W\n", pdc),
      sprintf("Output Power: %.2f W\n", pout),
      sprintf("Dissipated Power: %.2f W\n", pdiss)
    )
  })
  
  observeEvent(input$therm_calculate, {
    output$therm_results <- renderText({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdc <- pout / pae
      pdiss <- pdc - pout
      rth_jc <- input$therm_rth_jc
      rth_cs <- input$therm_rth_cs
      rth_sa <- input$therm_rth_sa
      rth_total <- rth_jc + rth_cs + rth_sa
      ta <- input$therm_ta
      tj_max <- input$therm_tj_max
      tj <- ta + pdiss * rth_total
      tc <- ta + pdiss * (rth_cs + rth_sa)
      ts <- ta + pdiss * rth_sa
      margin <- tj_max - tj
      margin_line <- if (margin > 0)
        sprintf("\u2713 Thermal margin: %.1f \u00b0C (SAFE)\n", margin)
      else
        sprintf("\u2717 THERMAL VIOLATION: %.1f \u00b0C over limit!\n", -margin)
      paste0(
        "Thermal Analysis Results:\n",
        "========================\n\n",
        sprintf("Power Dissipation: %.2f W\n\n", pdiss),
        "Thermal Resistances:\n",
        sprintf("  R\u03b8jc: %.2f \u00b0C/W\n", rth_jc),
        sprintf("  R\u03b8cs: %.2f \u00b0C/W\n", rth_cs),
        sprintf("  R\u03b8sa: %.2f \u00b0C/W\n", rth_sa),
        sprintf("  R\u03b8ja (total): %.2f \u00b0C/W\n\n", rth_total),
        "Temperature Profile:\n",
        sprintf("  Ambient (Ta): %.1f \u00b0C\n", ta),
        sprintf("  Heatsink (Ts): %.1f \u00b0C\n", ts),
        sprintf("  Case (Tc): %.1f \u00b0C\n", tc),
        sprintf("  Junction (Tj): %.1f \u00b0C\n", tj),
        sprintf("  Max Junction: %.1f \u00b0C\n\n", tj_max),
        margin_line
      )
    })
    
    output$therm_plot <- renderPlotly({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdiss <- (pout / pae) - pout
      
      rth_jc <- input$therm_rth_jc
      rth_cs <- input$therm_rth_cs
      rth_sa <- input$therm_rth_sa
      
      ta <- input$therm_ta
      
      ts <- ta + pdiss * rth_sa
      tc <- ta + pdiss * (rth_cs + rth_sa)
      tj <- ta + pdiss * (rth_jc + rth_cs + rth_sa)
      
      nodes <- c("Ambient", "Heatsink", "Case", "Junction")
      temps <- c(ta, ts, tc, tj)
      colors <- c("blue", "green", "orange", "red")
      
      plot_ly(x = nodes, y = temps, type = "bar",
              marker = list(color = colors)) %>%
        layout(
          title = "Thermal Profile",
          xaxis = list(title = "Location"),
          yaxis = list(title = "Temperature (°C)")
        ) %>%
        add_trace(
          x = nodes,
          y = rep(input$therm_tj_max, length(nodes)),
          type = "scatter",
          mode = "lines",
          line = list(color = "red", dash = "dash"),
          name = "Max Tj Limit"
        )
    })
    
    output$therm_recommendations <- renderUI({
      pout <- input$therm_pout
      pae <- input$therm_efficiency / 100
      pdiss <- (pout / pae) - pout
      
      rth_total <- input$therm_rth_jc + input$therm_rth_cs + input$therm_rth_sa
      tj <- input$therm_ta + pdiss * rth_total
      margin <- input$therm_tj_max - tj
      
      if (margin > 20) {
        HTML("<p style='color:green;'><b>✓ Thermal design is adequate</b></p>
             <ul>
             <li>Current heatsink solution is sufficient</li>
             <li>Consider monitoring for reliability</li>
             </ul>")
      } else if (margin > 0) {
        HTML("<p style='color:orange;'><b>⚠ Marginal thermal design</b></p>
             <ul>
             <li>Improve heatsink or add forced air cooling</li>
             <li>Reduce thermal interface resistance (better TIM)</li>
             <li>Consider active cooling solutions</li>
             </ul>")
      } else {
        HTML("<p style='color:red;'><b>✗ Thermal violation - MUST ADDRESS</b></p>
             <ul>
             <li><b>Critical:</b> Reduce Rθsa or increase heatsink area</li>
             <li>Add forced air or liquid cooling</li>
             <li>Reduce power dissipation (improve PAE or lower output power)</li>
             <li>Split power across multiple devices</li>
             </ul>")
      }
    })
  })
  
  # Cleanup on session end

}
