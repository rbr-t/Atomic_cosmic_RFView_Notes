#!/usr/bin/env Rscript
#
# PA Design Trade-off Visualization in R
# ======================================
#
# This script generates professional trade-off plots for PA design analysis
# Including:
# - Linearity vs Efficiency
# - Pareto front visualization
# - Manufacturing yield analysis
# - Multi-dimensional trade-off surfaces
#
# Author: PA Design Reference Manual Project
# Date: February 1, 2026
#

# Required libraries
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  ggplot2,      # Plotting
  dplyr,        # Data manipulation
  tidyr,        # Data tidying
  plotly,       # Interactive 3D plots
  viridis,      # Color scales
  gridExtra,    # Multi-panel plots
  RColorBrewer, # Additional color palettes
  scales        # Scale functions
)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

generate_pa_sweep_data <- function(n_samples = 50) {
  #' Generate PA design sweep data (simulated)
  #' 
  #' @param n_samples Number of samples per dimension
  #' @return Data frame with design parameters and performance
  
  set.seed(42)
  
  # Design space
  iq_range <- seq(20, 80, length.out = n_samples)
  zl_range <- seq(30, 80, length.out = n_samples)
  
  # Expand grid
  design_space <- expand.grid(
    iq_ma = iq_range,
    zl_ohm = zl_range
  )
  
  # Simulate performance (simplified model)
  design_space <- design_space %>%
    mutate(
      # Output power model
      pout_dbm = 43 + 0.5 * (zl_ohm - 55) / 25 + rnorm(n(), 0, 0.3),
      
      # PAE model (efficiency vs bias trade-off)
      pae_percent = 70 * (1 - iq_ma / 100) * (1 - 0.5 * abs(zl_ohm - 50) / 30) + 
                    rnorm(n(), 0, 2),
      
      # IM3 model (linearity improves with higher bias)
      im3_dbc = -55 + 20 * (1 - iq_ma / 100) + 5 * abs(zl_ohm - 50) / 30 + 
                rnorm(n(), 0, 1.5),
      
      # ACPR (correlated with IM3)
      acpr_dbc = im3_dbc - 5,
      
      # Gain
      gain_db = 15 - 0.5 * abs(zl_ohm - 50) / 25 + rnorm(n(), 0, 0.2),
      
      # Cost model
      cost_usd = 5 + (zl_ohm - 30) / 10 + rnorm(n(), 0, 0.5),
      
      # Yield model (based on margins)
      margin_im3 = im3_dbc - (-40),  # Spec is -40 dBc
      margin_pae = pae_percent - 45,  # Spec is 45%
      yield_percent = pmin(100, 50 + 10 * pmax(0, margin_im3) + 
                                 5 * pmax(0, margin_pae)),
      
      # Figure of merit
      fom = -im3_dbc * 2 + pae_percent * 0.5 + pout_dbm * 0.3
    ) %>%
    mutate(
      # Clip to realistic ranges
      pae_percent = pmin(pmax(pae_percent, 20), 70),
      im3_dbc = pmin(pmax(im3_dbc, -60), -30),
      yield_percent = pmin(pmax(yield_percent, 50), 100)
    )
  
  return(design_space)
}

find_pareto_front <- function(data, obj1, obj2, maximize1 = TRUE, maximize2 = TRUE) {
  #' Find Pareto-optimal points
  #' 
  #' @param data Data frame
  #' @param obj1 First objective column name
  #' @param obj2 Second objective column name
  #' @param maximize1 TRUE to maximize obj1, FALSE to minimize
  #' @param maximize2 TRUE to maximize obj2, FALSE to minimize
  #' @return Data frame with pareto_optimal flag
  
  data$pareto_optimal <- FALSE
  
  for (i in 1:nrow(data)) {
    point <- data[i, ]
    
    # Check if any other point dominates this one
    is_dominated <- FALSE
    
    for (j in 1:nrow(data)) {
      if (i == j) next
      
      other_point <- data[j, ]
      
      obj1_better <- ifelse(maximize1,
                           other_point[[obj1]] > point[[obj1]],
                           other_point[[obj1]] < point[[obj1]])
      
      obj2_better <- ifelse(maximize2,
                           other_point[[obj2]] > point[[obj2]],
                           other_point[[obj2]] < point[[obj2]])
      
      obj1_equal <- abs(other_point[[obj1]] - point[[obj1]]) < 0.01
      obj2_equal <- abs(other_point[[obj2]] - point[[obj2]]) < 0.01
      
      if ((obj1_better && (obj2_better || obj2_equal)) ||
          (obj2_better && (obj1_better || obj1_equal))) {
        is_dominated <- TRUE
        break
      }
    }
    
    if (!is_dominated) {
      data$pareto_optimal[i] <- TRUE
    }
  }
  
  return(data)
}

# ============================================================================
# PLOTTING FUNCTIONS
# ============================================================================

plot_linearity_efficiency_tradeoff <- function(data, specs) {
  #' Plot PAE vs IM3 trade-off
  #' 
  #' @param data Design sweep data
  #' @param specs List of specifications
  
  p <- ggplot(data, aes(x = im3_dbc, y = pae_percent)) +
    geom_point(aes(color = pout_dbm, size = yield_percent), alpha = 0.6) +
    geom_vline(xintercept = specs$im3_max, linetype = "dashed", 
               color = "red", size = 1.2) +
    geom_hline(yintercept = specs$pae_min, linetype = "dashed", 
               color = "orange", size = 1.2) +
    scale_color_viridis(option = "plasma", name = "Pout\n(dBm)") +
    scale_size_continuous(range = c(2, 8), name = "Yield\n(%)") +
    labs(
      title = "Linearity vs Efficiency Trade-off",
      subtitle = "PA Design Space Exploration",
      x = "IM3 (dBc)",
      y = "PAE (%)"
    ) +
    annotate("text", x = specs$im3_max + 2, y = 25, 
             label = "IM3 Spec", color = "red", angle = 90, size = 4) +
    annotate("text", x = -55, y = specs$pae_min + 2, 
             label = "PAE Spec", color = "orange", size = 4) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(size = 12),
      legend.position = "right",
      panel.grid.major = element_line(color = "gray90"),
      panel.grid.minor = element_line(color = "gray95")
    )
  
  return(p)
}

plot_power_linearity_tradeoff <- function(data, specs) {
  #' Plot Pout vs IM3 trade-off
  #' 
  #' @param data Design sweep data
  #' @param specs List of specifications
  
  p <- ggplot(data, aes(x = pout_dbm, y = im3_dbc)) +
    geom_point(aes(color = iq_ma, size = pae_percent), alpha = 0.6) +
    geom_vline(xintercept = specs$pout_min, linetype = "dashed", 
               color = "red", size = 1.2) +
    geom_hline(yintercept = specs$im3_max, linetype = "dashed", 
               color = "orange", size = 1.2) +
    scale_color_viridis(option = "magma", name = "Iq\n(mA)") +
    scale_size_continuous(range = c(2, 8), name = "PAE\n(%)") +
    labs(
      title = "Power vs Linearity Trade-off",
      subtitle = "Operating Point Selection",
      x = "Output Power (dBm)",
      y = "IM3 (dBc)"
    ) +
    annotate("text", x = specs$pout_min + 0.2, y = -30, 
             label = "Pout Spec", color = "red", angle = 90, size = 4) +
    annotate("text", x = 42, y = specs$im3_max + 1, 
             label = "IM3 Spec", color = "orange", size = 4) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(size = 12),
      legend.position = "right",
      panel.grid.major = element_line(color = "gray90")
    )
  
  return(p)
}

plot_pareto_front <- function(data, specs) {
  #' Plot Pareto front for PAE vs IM3
  #' 
  #' @param data Design sweep data with pareto_optimal flag
  #' @param specs List of specifications
  
  pareto_data <- data %>% filter(pareto_optimal == TRUE)
  
  p <- ggplot(data, aes(x = im3_dbc, y = pae_percent)) +
    geom_point(aes(color = "All Designs"), alpha = 0.3, size = 2) +
    geom_point(data = pareto_data, aes(color = "Pareto Optimal"), 
               size = 6, shape = 18) +
    geom_line(data = pareto_data %>% arrange(im3_dbc), 
              aes(color = "Pareto Front"), size = 1.5, linetype = "dashed") +
    geom_vline(xintercept = specs$im3_max, linetype = "dotted", 
               color = "red", size = 1) +
    geom_hline(yintercept = specs$pae_min, linetype = "dotted", 
               color = "red", size = 1) +
    scale_color_manual(
      name = "Design Type",
      values = c("All Designs" = "gray70", 
                 "Pareto Optimal" = "darkred",
                 "Pareto Front" = "darkred")
    ) +
    labs(
      title = "Pareto Front: Efficiency vs Linearity",
      subtitle = sprintf("%d Pareto-Optimal Designs Identified", 
                        nrow(pareto_data)),
      x = "IM3 (dBc)",
      y = "PAE (%)"
    ) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(size = 12, color = "darkred"),
      legend.position = "right"
    )
  
  return(p)
}

plot_design_space_contour <- function(data, metric = "im3_dbc") {
  #' Plot contour map of design space
  #' 
  #' @param data Design sweep data
  #' @param metric Metric to plot (im3_dbc, pae_percent, etc.)
  
  metric_label <- switch(metric,
    "im3_dbc" = "IM3 (dBc)",
    "pae_percent" = "PAE (%)",
    "pout_dbm" = "Pout (dBm)",
    "yield_percent" = "Yield (%)",
    metric
  )
  
  color_scale <- if (metric == "im3_dbc") {
    scale_fill_viridis(option = "A", name = metric_label, direction = -1)
  } else {
    scale_fill_viridis(option = "D", name = metric_label)
  }
  
  p <- ggplot(data, aes(x = iq_ma, y = zl_ohm)) +
    geom_tile(aes(fill = .data[[metric]])) +
    geom_contour(aes(z = .data[[metric]]), color = "white", 
                 alpha = 0.5, size = 0.3) +
    color_scale +
    labs(
      title = paste(metric_label, "Design Space"),
      subtitle = "Bias Current vs Load Impedance",
      x = "Bias Current (mA)",
      y = "Load Impedance (Ω)"
    ) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      legend.position = "right"
    )
  
  return(p)
}

plot_yield_analysis <- function(data, specs) {
  #' Plot manufacturing yield vs design margin
  #' 
  #' @param data Design sweep data
  #' @param specs List of specifications
  
  data <- data %>%
    mutate(im3_margin = im3_dbc - specs$im3_max)
  
  p <- ggplot(data, aes(x = im3_margin, y = yield_percent)) +
    geom_point(aes(color = pae_percent, size = pout_dbm), alpha = 0.6) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "red", size = 1.2) +
    geom_smooth(method = "loess", color = "blue", size = 1.5, se = TRUE) +
    scale_color_viridis(option = "inferno", name = "PAE\n(%)") +
    scale_size_continuous(range = c(2, 8), name = "Pout\n(dBm)") +
    labs(
      title = "Manufacturing Yield Analysis",
      subtitle = "Yield vs Performance Margin",
      x = "IM3 Margin to Spec (dB)",
      y = "Predicted Yield (%)"
    ) +
    annotate("text", x = 0.5, y = 55, label = "Spec Limit", 
             color = "red", angle = 90, size = 4) +
    theme_minimal(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      legend.position = "right"
    )
  
  return(p)
}

plot_3d_tradeoff <- function(data) {
  #' Create interactive 3D trade-off plot
  #' 
  #' @param data Design sweep data
  
  fig <- plot_ly(data, 
                 x = ~pout_dbm, 
                 y = ~pae_percent, 
                 z = ~-im3_dbc,  # Flip sign for better visualization
                 color = ~fom,
                 colors = viridis(100),
                 marker = list(size = 5, opacity = 0.6)) %>%
    add_markers() %>%
    layout(
      title = list(
        text = "3D Performance Trade-off Space",
        font = list(size = 18, weight = "bold")
      ),
      scene = list(
        xaxis = list(title = "Output Power (dBm)"),
        yaxis = list(title = "PAE (%)"),
        zaxis = list(title = "Linearity (-IM3 dBc)")
      )
    )
  
  return(fig)
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main <- function() {
  cat("\n", rep("=", 70), "\n", sep = "")
  cat(" PA Design Trade-off Analysis and Visualization\n")
  cat(rep("=", 70), "\n\n", sep = "")
  
  # Define specifications
  specs <- list(
    freq_ghz = 3.5,
    pout_min = 43.0,
    pae_min = 45.0,
    im3_max = -40.0,
    acpr_max = -45.0
  )
  
  cat("Target Specifications:\n")
  cat(sprintf("  Frequency:     %.1f GHz\n", specs$freq_ghz))
  cat(sprintf("  Output Power: >%.1f dBm\n", specs$pout_min))
  cat(sprintf("  PAE:          >%.1f %%\n", specs$pae_min))
  cat(sprintf("  IM3:          <%.1f dBc (CRITICAL)\n", specs$im3_max))
  cat(sprintf("  ACPR:         <%.1f dBc\n\n", specs$acpr_max))
  
  # Generate design sweep data
  cat("Generating design sweep data (50x50 = 2,500 points)...\n")
  data <- generate_pa_sweep_data(n_samples = 50)
  
  # Find Pareto front
  cat("Finding Pareto-optimal designs...\n")
  data <- find_pareto_front(data, "pae_percent", "im3_dbc", 
                            maximize1 = TRUE, maximize2 = FALSE)
  
  n_pareto <- sum(data$pareto_optimal)
  cat(sprintf("  → %d Pareto-optimal designs found (%.1f%%)\n\n", 
              n_pareto, 100 * n_pareto / nrow(data)))
  
  # Create output directory
  output_dir <- "PA_Design_Reference_Manual/Output"
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  # Generate plots
  cat("Generating trade-off plots...\n")
  
  cat("  [1/6] Linearity vs Efficiency...\n")
  p1 <- plot_linearity_efficiency_tradeoff(data, specs)
  
  cat("  [2/6] Power vs Linearity...\n")
  p2 <- plot_power_linearity_tradeoff(data, specs)
  
  cat("  [3/6] Pareto Front...\n")
  p3 <- plot_pareto_front(data, specs)
  
  cat("  [4/6] IM3 Design Space...\n")
  p4 <- plot_design_space_contour(data, "im3_dbc")
  
  cat("  [5/6] PAE Design Space...\n")
  p5 <- plot_design_space_contour(data, "pae_percent")
  
  cat("  [6/6] Manufacturing Yield...\n")
  p6 <- plot_yield_analysis(data, specs)
  
  # Save multi-panel figure
  cat("\nSaving multi-panel figure...\n")
  output_file <- file.path(output_dir, "PA_Tradeoff_Analysis.png")
  
  png(output_file, width = 16, height = 10, units = "in", res = 300)
  grid.arrange(p1, p2, p3, p4, p5, p6, ncol = 3, nrow = 2)
  dev.off()
  
  cat(sprintf("  → Saved to: %s\n", output_file))
  
  # Generate interactive 3D plot
  cat("\nGenerating interactive 3D plot...\n")
  fig_3d <- plot_3d_tradeoff(data)
  output_file_3d <- file.path(output_dir, "PA_Tradeoff_3D.html")
  htmlwidgets::saveWidget(fig_3d, output_file_3d, selfcontained = TRUE)
  cat(sprintf("  → Saved to: %s\n", output_file_3d))
  
  # Summary statistics
  cat("\n", rep("=", 70), "\n", sep = "")
  cat(" ANALYSIS SUMMARY\n")
  cat(rep("=", 70), "\n\n", sep = "")
  
  cat("Design Space Statistics:\n")
  cat(sprintf("  Total designs evaluated:  %d\n", nrow(data)))
  cat(sprintf("  Pareto-optimal designs:   %d\n", n_pareto))
  cat(sprintf("  Designs meeting specs:    %d\n", 
              sum(data$im3_dbc < specs$im3_max & 
                  data$pae_percent > specs$pae_min &
                  data$pout_dbm > specs$pout_min)))
  
  cat("\nPerformance Ranges:\n")
  cat(sprintf("  Output Power: [%.2f, %.2f] dBm\n", 
              min(data$pout_dbm), max(data$pout_dbm)))
  cat(sprintf("  PAE:          [%.1f, %.1f] %%\n", 
              min(data$pae_percent), max(data$pae_percent)))
  cat(sprintf("  IM3:          [%.1f, %.1f] dBc\n", 
              min(data$im3_dbc), max(data$im3_dbc)))
  cat(sprintf("  Yield:        [%.1f, %.1f] %%\n", 
              min(data$yield_percent), max(data$yield_percent)))
  
  cat("\nPareto Front Characteristics:\n")
  pareto_data <- data %>% filter(pareto_optimal == TRUE)
  cat(sprintf("  IM3 range:    [%.1f, %.1f] dBc\n", 
              min(pareto_data$im3_dbc), max(pareto_data$im3_dbc)))
  cat(sprintf("  PAE range:    [%.1f, %.1f] %%\n", 
              min(pareto_data$pae_percent), max(pareto_data$pae_percent)))
  
  best_design <- data %>% arrange(desc(fom)) %>% slice(1)
  cat("\nRecommended Design (Highest FOM):\n")
  cat(sprintf("  Bias Current:  %.1f mA\n", best_design$iq_ma))
  cat(sprintf("  Load Impedance: %.1f Ω\n", best_design$zl_ohm))
  cat(sprintf("  → Pout:        %.2f dBm\n", best_design$pout_dbm))
  cat(sprintf("  → PAE:         %.1f %%\n", best_design$pae_percent))
  cat(sprintf("  → IM3:         %.1f dBc\n", best_design$im3_dbc))
  cat(sprintf("  → Yield:       %.1f %%\n", best_design$yield_percent))
  
  cat("\n", rep("=", 70), "\n", sep = "")
  cat(" Analysis complete! Review plots for detailed trade-offs.\n")
  cat(rep("=", 70), "\n\n", sep = "")
}

# Run main function
if (!interactive()) {
  main()
}
