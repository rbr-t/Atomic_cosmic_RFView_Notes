# PA Figure Generation Scripts
# Collection of R functions to generate common power amplifier plots
# Author: PA Design Reference Manual
# Date: February 1, 2026

library(ggplot2)
library(dplyr)
library(gridExtra)
library(scales)

# ============================================================================
# THEME SETUP
# ============================================================================

# Custom theme for PA plots
theme_pa <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 2),
      plot.subtitle = element_text(size = base_size, color = "gray40"),
      axis.title = element_text(face = "bold"),
      legend.position = "bottom",
      legend.title = element_text(face = "bold"),
      panel.grid.minor = element_line(color = "gray95"),
      panel.grid.major = element_line(color = "gray90")
    )
}

# Color palette for PA plots
pa_colors <- c(
  "#1f77b4",  # Blue
  "#ff7f0e",  # Orange
  "#2ca02c",  # Green
  "#d62728",  # Red
  "#9467bd",  # Purple
  "#8c564b",  # Brown
  "#e377c2",  # Pink
  "#7f7f7f"   # Gray
)

# ============================================================================
# 1. GAIN vs POWER PLOTS
# ============================================================================

#' Plot Gain vs Input Power (AM-AM Compression)
#' 
#' @param pin_dbm Input power in dBm (vector)
#' @param gain_db Gain in dB (vector)
#' @param title Plot title
#' @param subtitle Plot subtitle
#' @param p1db_point Mark 1-dB compression point (TRUE/FALSE)
#' @return ggplot object
plot_gain_vs_power <- function(pin_dbm, gain_db, 
                                title = "Gain vs Input Power",
                                subtitle = "AM-AM Characteristics",
                                p1db_point = TRUE) {
  
  # Create data frame
  data <- data.frame(Pin_dBm = pin_dbm, Gain_dB = gain_db)
  
  # Find small-signal gain (average of first 3 points)
  small_signal_gain <- mean(data$Gain_dB[1:min(3, length(gain_db))])
  
  # Find 1-dB compression point
  if (p1db_point) {
    compression <- small_signal_gain - data$Gain_dB
    p1db_idx <- which(compression >= 1.0)[1]
    if (!is.na(p1db_idx)) {
      p1db_pin <- data$Pin_dBm[p1db_idx]
      p1db_gain <- data$Gain_dB[p1db_idx]
    }
  }
  
  # Create plot
  p <- ggplot(data, aes(x = Pin_dBm, y = Gain_dB)) +
    geom_line(color = pa_colors[1], linewidth = 1.2) +
    geom_point(color = pa_colors[1], size = 2) +
    geom_hline(yintercept = small_signal_gain, 
               linetype = "dashed", color = "gray50", linewidth = 0.8) +
    annotate("text", x = min(pin_dbm), y = small_signal_gain, 
             label = paste0("Small-signal gain = ", round(small_signal_gain, 1), " dB"),
             hjust = 0, vjust = -0.5, size = 3.5, color = "gray40")
  
  # Add 1-dB compression point marker
  if (p1db_point && !is.na(p1db_idx)) {
    p <- p + 
      geom_point(x = p1db_pin, y = p1db_gain, 
                 color = "red", size = 4, shape = 18) +
      annotate("text", x = p1db_pin, y = p1db_gain,
               label = paste0("P1dB = ", round(p1db_pin, 1), " dBm"),
               hjust = -0.1, vjust = 1.5, size = 3.5, color = "red", fontface = "bold")
  }
  
  p <- p +
    labs(title = title,
         subtitle = subtitle,
         x = "Input Power (dBm)",
         y = "Gain (dB)") +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 2. PAE vs POWER PLOTS
# ============================================================================

#' Plot PAE vs Output Power
#' 
#' @param pout_dbm Output power in dBm (vector)
#' @param pae_percent PAE in percent (vector)
#' @param title Plot title
#' @param subtitle Plot subtitle
#' @param spec_line PAE specification line (optional, in percent)
#' @return ggplot object
plot_pae_vs_power <- function(pout_dbm, pae_percent,
                               title = "PAE vs Output Power",
                               subtitle = "",
                               spec_line = NULL) {
  
  data <- data.frame(Pout_dBm = pout_dbm, PAE_percent = pae_percent)
  
  p <- ggplot(data, aes(x = Pout_dBm, y = PAE_percent)) +
    geom_line(color = pa_colors[2], linewidth = 1.2) +
    geom_point(color = pa_colors[2], size = 2.5)
  
  # Add specification line if provided
  if (!is.null(spec_line)) {
    p <- p + 
      geom_hline(yintercept = spec_line, 
                 linetype = "dashed", color = "red", linewidth = 0.8) +
      annotate("text", x = min(pout_dbm), y = spec_line,
               label = paste0("Spec: PAE > ", spec_line, "%"),
               hjust = 0, vjust = -0.5, size = 3.5, color = "red")
  }
  
  p <- p +
    labs(title = title,
         subtitle = subtitle,
         x = "Output Power (dBm)",
         y = "PAE (%)") +
    scale_y_continuous(limits = c(0, max(pae_percent) * 1.1)) +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 3. MULTI-PARAMETER vs POWER
# ============================================================================

#' Plot Gain, Power, and PAE vs Input Power
#' 
#' @param pin_dbm Input power in dBm (vector)
#' @param gain_db Gain in dB (vector)
#' @param pout_dbm Output power in dBm (vector)
#' @param pae_percent PAE in percent (vector)
#' @param title Plot title
#' @return ggplot object with dual y-axis
plot_multi_param_vs_power <- function(pin_dbm, gain_db, pout_dbm, pae_percent,
                                      title = "PA Performance vs Input Power") {
  
  # Normalize PAE to fit on gain scale for dual axis
  pae_scale_factor <- max(gain_db) / max(pae_percent) * 0.8
  
  data <- data.frame(
    Pin_dBm = pin_dbm,
    Gain_dB = gain_db,
    Pout_dBm = pout_dbm,
    PAE_scaled = pae_percent * pae_scale_factor,
    PAE_percent = pae_percent
  )
  
  p <- ggplot(data, aes(x = Pin_dBm)) +
    # Gain
    geom_line(aes(y = Gain_dB, color = "Gain"), linewidth = 1.2) +
    geom_point(aes(y = Gain_dB, color = "Gain"), size = 2) +
    # PAE (scaled)
    geom_line(aes(y = PAE_scaled, color = "PAE"), linewidth = 1.2) +
    geom_point(aes(y = PAE_scaled, color = "PAE"), size = 2) +
    # Styling
    scale_color_manual(values = c("Gain" = pa_colors[1], "PAE" = pa_colors[2])) +
    scale_y_continuous(
      name = "Gain (dB)",
      sec.axis = sec_axis(~ . / pae_scale_factor, name = "PAE (%)")
    ) +
    labs(title = title,
         x = "Input Power (dBm)",
         color = "Parameter") +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 4. FREQUENCY SWEEP PLOTS
# ============================================================================

#' Plot Gain and PAE vs Frequency
#' 
#' @param freq_ghz Frequency in GHz (vector)
#' @param gain_db Gain in dB (vector or matrix if multiple power levels)
#' @param pae_percent PAE in percent (vector or matrix)
#' @param power_levels Power level labels (if matrix input)
#' @param title Plot title
#' @return ggplot object
plot_gain_pae_vs_frequency <- function(freq_ghz, gain_db, pae_percent,
                                       power_levels = NULL,
                                       title = "PA Performance vs Frequency") {
  
  # Check if single sweep or multiple power levels
  if (is.null(dim(gain_db))) {
    # Single sweep
    data <- data.frame(
      Freq_GHz = freq_ghz,
      Gain_dB = gain_db,
      PAE_percent = pae_percent,
      Power_Level = "Single"
    )
  } else {
    # Multiple sweeps
    n_sweeps <- ncol(gain_db)
    data <- data.frame()
    for (i in 1:n_sweeps) {
      temp <- data.frame(
        Freq_GHz = freq_ghz,
        Gain_dB = gain_db[, i],
        PAE_percent = pae_percent[, i],
        Power_Level = if(!is.null(power_levels)) power_levels[i] else paste0("Power ", i)
      )
      data <- rbind(data, temp)
    }
  }
  
  # Normalize PAE for dual axis
  pae_scale <- max(data$Gain_dB) / max(data$PAE_percent) * 0.8
  data$PAE_scaled <- data$PAE_percent * pae_scale
  
  p <- ggplot(data, aes(x = Freq_GHz)) +
    geom_line(aes(y = Gain_dB, color = Power_Level, linetype = "Gain"), linewidth = 1.1) +
    geom_point(aes(y = Gain_dB, color = Power_Level), size = 2, shape = 16) +
    geom_line(aes(y = PAE_scaled, color = Power_Level, linetype = "PAE"), linewidth = 1.1) +
    geom_point(aes(y = PAE_scaled, color = Power_Level), size = 2, shape = 17) +
    scale_color_manual(values = pa_colors) +
    scale_linetype_manual(values = c("Gain" = "solid", "PAE" = "dashed")) +
    scale_y_continuous(
      name = "Gain (dB)",
      sec.axis = sec_axis(~ . / pae_scale, name = "PAE (%)")
    ) +
    labs(title = title,
         x = "Frequency (GHz)",
         color = "Power Level",
         linetype = "Parameter") +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 5. LINEARITY PLOTS (ACLR, EVM)
# ============================================================================

#' Plot ACLR vs Output Power
#' 
#' @param pout_dbm Output power in dBm (vector)
#' @param aclr_lower_dbc ACLR lower channel in dBc (vector, negative values)
#' @param aclr_upper_dbc ACLR upper channel in dBc (vector, negative values)
#' @param spec_limit ACLR specification limit (e.g., -45 dBc)
#' @param title Plot title
#' @return ggplot object
plot_aclr_vs_power <- function(pout_dbm, aclr_lower_dbc, aclr_upper_dbc,
                                spec_limit = -45,
                                title = "ACLR vs Output Power") {
  
  data <- data.frame(
    Pout_dBm = rep(pout_dbm, 2),
    ACLR_dBc = c(aclr_lower_dbc, aclr_upper_dbc),
    Channel = rep(c("Lower", "Upper"), each = length(pout_dbm))
  )
  
  p <- ggplot(data, aes(x = Pout_dBm, y = ACLR_dBc, color = Channel)) +
    geom_line(linewidth = 1.2) +
    geom_point(size = 2.5) +
    geom_hline(yintercept = spec_limit, 
               linetype = "dashed", color = "red", linewidth = 0.8) +
    annotate("text", x = min(pout_dbm), y = spec_limit,
             label = paste0("Spec: ACLR < ", spec_limit, " dBc"),
             hjust = 0, vjust = -0.5, size = 3.5, color = "red") +
    annotate("rect", xmin = min(pout_dbm), xmax = max(pout_dbm),
             ymin = -60, ymax = spec_limit, alpha = 0.05, fill = "green") +
    scale_color_manual(values = c("Lower" = pa_colors[1], "Upper" = pa_colors[2])) +
    scale_y_reverse() +
    labs(title = title,
         subtitle = "Adjacent Channel Leakage Ratio (lower is better)",
         x = "Output Power (dBm)",
         y = "ACLR (dBc)",
         color = "Channel") +
    theme_pa()
  
  return(p)
}

#' Plot EVM vs Output Power
#' 
#' @param pout_dbm Output power in dBm (vector)
#' @param evm_percent EVM in percent (vector)
#' @param spec_limit EVM specification limit (e.g., 3%)
#' @param title Plot title
#' @return ggplot object
plot_evm_vs_power <- function(pout_dbm, evm_percent,
                               spec_limit = 3,
                               title = "EVM vs Output Power") {
  
  data <- data.frame(Pout_dBm = pout_dbm, EVM_percent = evm_percent)
  
  p <- ggplot(data, aes(x = Pout_dBm, y = EVM_percent)) +
    geom_line(color = pa_colors[3], linewidth = 1.2) +
    geom_point(color = pa_colors[3], size = 2.5) +
    geom_hline(yintercept = spec_limit,
               linetype = "dashed", color = "red", linewidth = 0.8) +
    annotate("text", x = min(pout_dbm), y = spec_limit,
             label = paste0("Spec: EVM < ", spec_limit, "%"),
             hjust = 0, vjust = -0.5, size = 3.5, color = "red") +
    annotate("rect", xmin = min(pout_dbm), xmax = max(pout_dbm),
             ymin = 0, ymax = spec_limit, alpha = 0.05, fill = "green") +
    labs(title = title,
         subtitle = "Error Vector Magnitude (lower is better)",
         x = "Output Power (dBm)",
         y = "EVM (%)") +
    scale_y_continuous(limits = c(0, max(evm_percent) * 1.1)) +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 6. LOAD-PULL CONTOUR PLOTS
# ============================================================================

#' Plot Load-Pull Contours on Smith Chart
#' 
#' @param gamma_real Real part of reflection coefficient (vector)
#' @param gamma_imag Imaginary part of reflection coefficient (vector)
#' @param performance Performance metric (e.g., Pout in dBm)
#' @param contour_levels Contour levels to draw
#' @param title Plot title
#' @param metric_label Label for performance metric (e.g., "Pout (dBm)")
#' @return ggplot object
plot_loadpull_contours <- function(gamma_real, gamma_imag, performance,
                                    contour_levels = NULL,
                                    title = "Load-Pull Contours",
                                    metric_label = "Performance") {
  
  # Create data frame
  data <- data.frame(
    Gamma_Real = gamma_real,
    Gamma_Imag = gamma_imag,
    Performance = performance
  )
  
  # Auto-generate contour levels if not provided
  if (is.null(contour_levels)) {
    contour_levels <- pretty(performance, n = 8)
  }
  
  # Smith chart circle
  theta <- seq(0, 2*pi, length.out = 100)
  circle <- data.frame(x = cos(theta), y = sin(theta))
  
  # Constant resistance circles (optional, for reference)
  r_circles <- data.frame()
  for (r in c(0.2, 0.5, 1.0, 2.0, 5.0)) {
    center_x <- r / (1 + r)
    radius <- 1 / (1 + r)
    x <- center_x + radius * cos(theta)
    y <- radius * sin(theta)
    r_circles <- rbind(r_circles, data.frame(x = x, y = y, r = as.factor(r)))
  }
  
  p <- ggplot() +
    # Smith chart outer circle
    geom_path(data = circle, aes(x = x, y = y), color = "gray40", linewidth = 0.8) +
    # Constant R circles
    geom_path(data = r_circles, aes(x = x, y = y, group = r), 
              color = "gray80", linewidth = 0.3) +
    # Contour plot
    geom_contour_filled(data = data, aes(x = Gamma_Real, y = Gamma_Imag, z = Performance),
                        breaks = contour_levels, alpha = 0.7) +
    geom_contour(data = data, aes(x = Gamma_Real, y = Gamma_Imag, z = Performance),
                 breaks = contour_levels, color = "black", linewidth = 0.5) +
    # Center point (50 ohm)
    geom_point(x = 0, y = 0, color = "red", size = 3, shape = 4, stroke = 2) +
    annotate("text", x = 0, y = 0, label = "50Ω", hjust = -0.3, vjust = -0.5, 
             color = "red", fontface = "bold") +
    coord_fixed() +
    labs(title = title,
         subtitle = "Reflection Coefficient (Gamma)",
         x = expression(paste("Real(", Gamma, ")")),
         y = expression(paste("Imag(", Gamma, ")")),
         fill = metric_label) +
    theme_pa() +
    theme(legend.position = "right")
  
  return(p)
}

# ============================================================================
# 7. DOHERTY-SPECIFIC PLOTS
# ============================================================================

#' Plot Doherty Efficiency vs Power Backoff
#' 
#' @param backoff_db Power backoff in dB (vector)
#' @param pae_doherty PAE for Doherty PA (vector)
#' @param pae_classab PAE for Class AB comparison (vector, optional)
#' @param title Plot title
#' @return ggplot object
plot_doherty_efficiency <- function(backoff_db, pae_doherty, pae_classab = NULL,
                                    title = "Doherty Efficiency vs Backoff") {
  
  data <- data.frame(
    Backoff_dB = backoff_db,
    PAE_Doherty = pae_doherty
  )
  
  p <- ggplot(data, aes(x = Backoff_dB)) +
    geom_line(aes(y = PAE_Doherty, color = "Doherty"), linewidth = 1.3) +
    geom_point(aes(y = PAE_Doherty, color = "Doherty"), size = 3)
  
  # Add Class AB comparison if provided
  if (!is.null(pae_classab)) {
    data$PAE_ClassAB <- pae_classab
    p <- p + 
      geom_line(aes(y = PAE_ClassAB, color = "Class AB"), linewidth = 1.3, linetype = "dashed") +
      geom_point(aes(y = PAE_ClassAB, color = "Class AB"), size = 3, shape = 17)
  }
  
  # Mark 6 dB backoff point (Doherty peak)
  backoff_6db_idx <- which.min(abs(backoff_db - 6))
  pae_at_6db <- pae_doherty[backoff_6db_idx]
  
  p <- p +
    geom_vline(xintercept = 6, linetype = "dotted", color = "gray50") +
    annotate("text", x = 6, y = max(pae_doherty),
             label = "6 dB Backoff\n(Doherty Peak)",
             hjust = -0.1, size = 3.5, color = "gray40") +
    scale_color_manual(values = c("Doherty" = pa_colors[1], "Class AB" = pa_colors[4])) +
    labs(title = title,
         subtitle = "Power Added Efficiency",
         x = "Power Backoff from Peak (dB)",
         y = "PAE (%)",
         color = "Architecture") +
    scale_x_continuous(breaks = seq(0, max(backoff_db), 2)) +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 8. DPD PERFORMANCE PLOTS
# ============================================================================

#' Plot ACLR Before and After DPD
#' 
#' @param pout_dbm Output power in dBm (vector)
#' @param aclr_no_dpd ACLR without DPD in dBc (vector)
#' @param aclr_with_dpd ACLR with DPD in dBc (vector)
#' @param spec_limit Specification limit (e.g., -45 dBc)
#' @param title Plot title
#' @return ggplot object
plot_dpd_comparison <- function(pout_dbm, aclr_no_dpd, aclr_with_dpd,
                                spec_limit = -45,
                                title = "DPD Linearization Performance") {
  
  data <- data.frame(
    Pout_dBm = rep(pout_dbm, 2),
    ACLR_dBc = c(aclr_no_dpd, aclr_with_dpd),
    Condition = rep(c("Without DPD", "With DPD"), each = length(pout_dbm))
  )
  
  p <- ggplot(data, aes(x = Pout_dBm, y = ACLR_dBc, color = Condition, linetype = Condition)) +
    geom_line(linewidth = 1.3) +
    geom_point(size = 2.5) +
    geom_hline(yintercept = spec_limit,
               linetype = "dashed", color = "red", linewidth = 0.8) +
    annotate("text", x = min(pout_dbm), y = spec_limit,
             label = paste0("Spec: ACLR < ", spec_limit, " dBc"),
             hjust = 0, vjust = -0.5, size = 3.5, color = "red") +
    scale_color_manual(values = c("Without DPD" = pa_colors[4], "With DPD" = pa_colors[3])) +
    scale_linetype_manual(values = c("Without DPD" = "dashed", "With DPD" = "solid")) +
    scale_y_reverse() +
    labs(title = title,
         subtitle = "ACLR Improvement through Digital Pre-Distortion",
         x = "Output Power (dBm)",
         y = "ACLR (dBc, lower is better)",
         color = "Condition",
         linetype = "Condition") +
    theme_pa()
  
  return(p)
}

# ============================================================================
# 9. UTILITY FUNCTIONS
# ============================================================================

#' Convert dBm to Watts
#' @param dbm Power in dBm
#' @return Power in Watts
dbm_to_watts <- function(dbm) {
  return(10^((dbm - 30) / 10))
}

#' Convert Watts to dBm
#' @param watts Power in Watts
#' @return Power in dBm
watts_to_dbm <- function(watts) {
  return(10 * log10(watts) + 30)
}

#' Calculate PAE from DC power, output power, gain
#' @param pout_dbm Output power in dBm
#' @param gain_db Gain in dB
#' @param vdd Supply voltage in V
#' @param idd Supply current in A
#' @return PAE in percent
calculate_pae <- function(pout_dbm, gain_db, vdd, idd) {
  pout_watts <- dbm_to_watts(pout_dbm)
  pdc_watts <- vdd * idd
  pae_percent <- (pout_watts / pdc_watts) * 100
  return(pae_percent)
}

#' Generate example PA sweep data for testing plots
#' @return List containing example data
generate_example_data <- function() {
  # Input power sweep
  pin_dbm <- seq(0, 30, 1)
  
  # Gain (compresses at high power)
  small_signal_gain <- 15
  gain_db <- small_signal_gain - 0.5 * (pin_dbm / 30)^3 * small_signal_gain
  
  # Output power
  pout_dbm <- pin_dbm + gain_db
  
  # PAE (peaks near compression)
  pae_percent <- 65 * (1 - exp(-pin_dbm/10)) * (1 - 0.3*(pin_dbm/30)^2)
  
  # ACLR (degrades at high power)
  aclr_dbc <- -52 + 20 * (pin_dbm / 30)^2
  
  # EVM
  evm_percent <- 1.0 + 3.0 * (pin_dbm / 30)^2
  
  return(list(
    pin_dbm = pin_dbm,
    gain_db = gain_db,
    pout_dbm = pout_dbm,
    pae_percent = pae_percent,
    aclr_dbc = aclr_dbc,
    evm_percent = evm_percent
  ))
}

# ============================================================================
# EXAMPLE USAGE
# ============================================================================

# Generate example data
# example_data <- generate_example_data()

# Create plots
# p1 <- plot_gain_vs_power(example_data$pin_dbm, example_data$gain_db)
# p2 <- plot_pae_vs_power(example_data$pout_dbm, example_data$pae_percent, spec_line = 50)
# p3 <- plot_aclr_vs_power(example_data$pout_dbm, example_data$aclr_dbc, example_data$aclr_dbc, spec_limit = -45)

# Display
# print(p1)
# ggsave("gain_vs_power.png", p1, width = 10, height = 6, dpi = 300)

