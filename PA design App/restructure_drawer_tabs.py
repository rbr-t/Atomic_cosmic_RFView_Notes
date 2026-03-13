#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
restructure_drawer_tabs.py
--------------------------
Restructures utility drawer cases in R/server.R:
  1. Replace "smith_chart" case (lines 97-143) with "rf_calc" (calculators)
  2. Replace "lp_viewer" opening header (line 146-152) with "rf_tools" wrapper
     containing Smith Chart sub-tab + Load Pull Viewer sub-tab
  3. Extend "lp_viewer" closing (lines 344-346) with the two extra parens needed
     to close the new rf_tools wrapper
  4. Insert reactive renderUI outputs for the 4 calculators before the
     module-registration block
"""

import sys

SERVER_R = "R/server.R"

with open(SERVER_R, "r", encoding="utf-8") as fh:
    lines = fh.readlines()

N = len(lines)
print(f"Read {N} lines from {SERVER_R}")

# ─────────────────────────────────────────────────────────────────────────────
# 1. RF Calc content (replaces lines 97-143, i.e. 0-indexed 96..142 inclusive)
# ─────────────────────────────────────────────────────────────────────────────
RF_CALC = """\
      # ── RF Calculators: Power \u00b7 Freq/\u03bb \u00b7 MTTF \u00b7 Thermal \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      "rf_calc" = tagList(
        div(style = "padding:4px 0 10px 0;",
          tabsetPanel(id = "rfcalc_tabs",

            # ── Power Converter \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("Power",
              br(),
              fluidRow(
                column(5,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("exchange-alt"), " Power Converter",
                       style = "color:#f0f0f0; margin-top:0;"),
                    numericInput("rfcalc_power_in", "Input value", value = 0),
                    selectInput("rfcalc_power_in_unit", "Input unit",
                      choices  = c("dBm", "W", "mW", "dBW"),
                      selected = "dBm"),
                    p(class = "text-muted", style = "font-size:11px; margin-top:8px;",
                      "Result updates automatically as you type.")
                  )
                ),
                column(7,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Converted values", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("rfcalc_power_results")
                  )
                )
              )
            ),

            # ── Frequency / Wavelength \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("Freq / \\u03bb",
              br(),
              fluidRow(
                column(5,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("wave-square"), " Frequency \\u2194 Wavelength",
                       style = "color:#f0f0f0; margin-top:0;"),
                    numericInput("rfcalc_freq_in", "Frequency",
                      value = 2400, min = 0.001, max = 300000),
                    selectInput("rfcalc_freq_unit", "Unit",
                      choices  = c("MHz", "GHz", "kHz", "Hz"),
                      selected = "MHz"),
                    numericInput("rfcalc_freq_er",
                      "Relative permittivity \\u03b5r (1 = free space)",
                      value = 1, min = 1, max = 100, step = 0.1),
                    p(class = "text-muted", style = "font-size:11px;",
                      "Common \\u03b5r: FR4 \\u2248 4.5 \\u00b7 RO4003C \\u2248 3.55 \\u00b7 Air = 1.")
                  )
                ),
                column(7,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5("Wavelength results", style = "color:#f0f0f0; margin-top:0;"),
                    uiOutput("rfcalc_freq_results")
                  )
                )
              )
            ),

            # ── MTTF (Arrhenius) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("MTTF",
              br(),
              fluidRow(
                column(5,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("heartbeat"), " MTTF (Arrhenius)",
                       style = "color:#f0f0f0; margin-top:0;"),
                    numericInput("rfcalc_mttf_tj",
                      "Junction temperature Tj (\\u00b0C)",
                      value = 150, min = -55, max = 500),
                    numericInput("rfcalc_mttf_t0",
                      "Reference temperature T\\u2080 (\\u00b0C)",
                      value = 150, min = -55, max = 500),
                    numericInput("rfcalc_mttf_ref",
                      "Reference MTTF at T\\u2080 (hours)",
                      value = 1e7, min = 1),
                    numericInput("rfcalc_mttf_ea",
                      "Activation energy E\\u2090 (eV)",
                      value = 1.1, min = 0.1, max = 3.0, step = 0.01),
                    p(class = "text-muted", style = "font-size:11px;",
                      "Typical E\\u2090: GaAs HEMT 0.7\\u20130.9 eV \\u00b7 GaN HEMT 1.1\\u20132.0 eV.")
                  )
                ),
                column(7,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    uiOutput("rfcalc_mttf_results")
                  )
                )
              )
            ),

            # ── Thermal Calculator \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("Thermal",
              br(),
              fluidRow(
                column(5,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("thermometer-half"), " Thermal Calculator",
                       style = "color:#f0f0f0; margin-top:0;"),
                    numericInput("rfcalc_therm_pdiss",
                      "Dissipated power Pdiss (W)",
                      value = 10, min = 0, max = 100000),
                    numericInput("rfcalc_therm_tamb",
                      "Ambient temperature Tamb (\\u00b0C)",
                      value = 25, min = -55, max = 125),
                    hr(),
                    h6("Thermal resistances (\\u00b0C/W)",
                       style = "color:#d0d0d0; font-size:12px;"),
                    p(class = "text-muted", style = "font-size:11px; margin-bottom:6px;",
                      "Fill R\\u03b8ja directly, or R\\u03b8jc + R\\u03b8ca separately."),
                    numericInput("rfcalc_therm_rja",
                      "R\\u03b8ja (junction \\u2192 ambient)",
                      value = NULL, min = 0),
                    numericInput("rfcalc_therm_rjc",
                      "R\\u03b8jc (junction \\u2192 case)",
                      value = NULL, min = 0),
                    numericInput("rfcalc_therm_rca",
                      "R\\u03b8ca (case \\u2192 ambient/heatsink)",
                      value = NULL, min = 0)
                  )
                ),
                column(7,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    uiOutput("rfcalc_therm_results")
                  )
                )
              )
            )
          )
        )
      ),

"""

# ─────────────────────────────────────────────────────────────────────────────
# 2. rf_tools opening header (replaces lines 145-152, i.e. 0-indexed 144..151)
#    Line 145 (0-idx 144): blank line before the lp_viewer comment
#    Line 146 (0-idx 145): # ── Load Pull Viewer... comment
#    Line 147 (0-idx 146): "lp_viewer" = tagList(
#    Lines 148-152 (0-idx 147-151): div + p + icon + two strings
#    Line 153 (0-idx 152): tabsetPanel(id = "lp_tabs",
# We replace 0-indexed 144..152 (inclusive) with the rf_tools header
# ─────────────────────────────────────────────────────────────────────────────
RF_TOOLS_OPEN = """\

      # ── RF Tools: Smith Chart + Load Pull Viewer \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      "rf_tools" = tagList(
        div(style = "padding:4px 0 10px 0;",
          tabsetPanel(id = "rf_tools_tabs",

            # ── Smith Chart \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("Smith Chart",
              br(),
              fluidRow(
                column(3,
                  div(class = "well",
                    style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("crosshairs"), " Impedance Entry", style = "color:#f0f0f0; margin-top:0;"),
                    numericInput("smith_z0",    "Reference Z\\u2080 (\\u03a9)",   value = 50, min = 0.1, max = 1000, step = 1),
                    numericInput("smith_z_real","Z Real (\\u03a9)",              value = 50, min = -2000, max = 2000),
                    numericInput("smith_z_imag","Z Imaginary (\\u03a9)",         value = 25, min = -2000, max = 2000),
                    textInput("smith_label", "Point Label", value = "", placeholder = "e.g. Zin @ 2.4 GHz"),
                    fluidRow(
                      column(6, actionButton("smith_add_point", "Add",
                        icon = icon("plus"),  class = "btn-primary btn-block btn-sm")),
                      column(6, actionButton("smith_clear", "Clear",
                        icon = icon("trash"), class = "btn-warning btn-block btn-sm"))
                    ),
                    hr(),
                    h5(icon("sliders-h"), " Chart options", style = "color:#f0f0f0;"),
                    selectInput("smith_mode", "Display Mode",
                      choices  = c("Impedance (Z)" = "Z", "Admittance (Y)" = "Y", "Both (Z+Y)" = "ZY"),
                      selected = "Z"),
                    hr(),
                    h5(icon("calculator"), " Matching Network", style = "color:#f0f0f0;"),
                    selectInput("smith_match_type", "Network Type",
                      choices = c("L-Section", "Pi-Network", "T-Network", "Single Stub", "Double Stub")),
                    actionButton("smith_design_match", "Synthesise",
                      icon = icon("calculator"), class = "btn-success btn-block btn-sm"),
                    p(class = "text-muted", style = "font-size:11px; margin-top:8px;",
                      "Select 2 points then click Synthesise to compute element values.")
                  )
                ),
                column(9,
                  div(class = "well", style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                    h5(icon("chart-bar"), " Smith Chart (interactive \\u2014 hover/click points)",
                       style = "color:#f0f0f0; margin-top:0;"),
                    plotlyOutput("smith_chart_plot", height = "490px"),
                    hr(),
                    h5("Point Summary & Matching Network", style = "color:#f0f0f0;"),
                    verbatimTextOutput("smith_components")
                  )
                )
              )
            ),

            # ── Load Pull Viewer \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
            tabPanel("Load Pull Viewer",
              br(),
              p(style = "color:#aaa; font-size:12px; margin:0 0 10px 0;",
                icon("chart-area"),
                " Import and visualise load-pull / source-pull measurement files.",
                " Formats: SPL, Focus Microwaves, Maury MDF, AMCAD, Anteverta-mw, ADS MDIF."),
              tabsetPanel(id = "lp_tabs",
"""

# ─────────────────────────────────────────────────────────────────────────────
# 3. rf_tools extra closing lines (inserted at 0-indexed 344, after lp_tabs closes)
#    Current lines (0-indexed 343-345):
#      343: '            )\n'   ← close tabPanel("LP Report")
#      344: '          )\n'     ← close tabsetPanel(id="lp_tabs")
#      345: '        )\n'       ← close outer div
#      346: '      ),\n'        ← close tagList
#    We need to insert after 344 (after lp_tabs close):
#      '            )\n'  ← close tabPanel("Load Pull Viewer")
#      '          )\n'   ← close tabsetPanel(id="rf_tools_tabs")
# ─────────────────────────────────────────────────────────────────────────────
EXTRA_CLOSE = ['            )\n', '          )\n']

# ─────────────────────────────────────────────────────────────────────────────
# 4. Reactive outputs for the 4 calculators
# ─────────────────────────────────────────────────────────────────────────────
CALC_OUTPUTS = """\
  # ── RF Calculator reactive outputs (drawer rf_calc panel) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

  output$rfcalc_power_results <- renderUI({
    req(input$rfcalc_power_in, input$rfcalc_power_in_unit)
    val  <- input$rfcalc_power_in
    unit <- input$rfcalc_power_in_unit
    w <- tryCatch(switch(unit,
      "dBm" = 10^((val - 30) / 10),
      "W"   = val,
      "mW"  = val / 1000,
      "dBW" = 10^(val / 10)
    ), error = function(e) NA_real_)
    if (is.na(w) || !is.finite(w) || w <= 0)
      return(p(icon("exclamation-triangle"), " Enter a valid positive value.", class = "text-muted"))
    dbm <- 10 * log10(w * 1000)
    dbw <- 10 * log10(w)
    mw  <- w * 1000
    uw  <- w * 1e6
    kw  <- w / 1000
    rows <- list(
      c("dBm",  sprintf("%.4f",  dbm)),
      c("dBW",  sprintf("%.4f",  dbw)),
      c("W",    sprintf("%.6g",  w)),
      c("mW",   sprintf("%.4g",  mw)),
      c("\\u00b5W", sprintf("%.4g", uw)),
      c("kW",   sprintf("%.4g",  kw))
    )
    tags$table(class = "table table-condensed",
      style = "font-size:13px; margin-top:4px;",
      tags$thead(tags$tr(tags$th("Unit"), tags$th("Value"))),
      tags$tbody(lapply(rows, function(r) tags$tr(
        tags$td(style = "color:#aaa;", r[1]),
        tags$td(style = "color:#f0f0f0; font-family:monospace;", r[2])
      )))
    )
  })

  output$rfcalc_freq_results <- renderUI({
    req(input$rfcalc_freq_in, input$rfcalc_freq_unit, input$rfcalc_freq_er)
    f    <- input$rfcalc_freq_in
    unit <- input$rfcalc_freq_unit
    er   <- max(1, input$rfcalc_freq_er)
    fhz  <- switch(unit, "Hz" = f, "kHz" = f*1e3, "MHz" = f*1e6, "GHz" = f*1e9)
    if (is.na(fhz) || fhz <= 0)
      return(p("Enter a valid frequency.", class = "text-muted"))
    lam <- 3e8 / (fhz * sqrt(er))
    rows <- list(
      c("Wavelength \\u03bb",      sprintf("%.5g m  /  %.5g cm  /  %.5g mm", lam, lam*100, lam*1000)),
      c("\\u03bb/2 (half-wave)",   sprintf("%.5g m  /  %.5g cm  /  %.5g mm", lam/2, lam*50, lam*500)),
      c("\\u03bb/4 (quarter-wave)",sprintf("%.5g m  /  %.5g cm  /  %.5g mm", lam/4, lam*25, lam*250)),
      c("Frequency",               sprintf("%.6g Hz  (%s %s)", fhz, f, unit)),
      c("\\u03b5r (medium)",       sprintf("%.3g", er))
    )
    tags$table(class = "table table-condensed",
      style = "font-size:13px; margin-top:4px;",
      tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
      tags$tbody(lapply(rows, function(r) tags$tr(
        tags$td(style = "color:#aaa;", r[1]),
        tags$td(style = "color:#f0f0f0; font-family:monospace;", r[2])
      )))
    )
  })

  output$rfcalc_mttf_results <- renderUI({
    req(input$rfcalc_mttf_tj, input$rfcalc_mttf_t0,
        input$rfcalc_mttf_ref, input$rfcalc_mttf_ea)
    tj  <- input$rfcalc_mttf_tj  + 273.15
    t0  <- input$rfcalc_mttf_t0  + 273.15
    ref <- input$rfcalc_mttf_ref
    ea  <- input$rfcalc_mttf_ea
    k   <- 8.617333e-5  # Boltzmann constant (eV/K)
    if (any(c(tj, t0, ref, ea) <= 0))
      return(p("Check input values \u2014 all must be positive.", class = "text-muted"))
    mttf <- ref * exp(ea / k * (1/tj - 1/t0))
    if (!is.finite(mttf))
      return(p("Result out of range. Reduce \\u0394T or E\\u2090.", class = "text-muted"))
    rows <- list(
      c("MTTF",          sprintf("%.4g hours", mttf)),
      c("MTTF",          sprintf("%.4g years",  mttf / 8760)),
      c("Tj",            sprintf("%.1f \\u00b0C  (%.1f K)", input$rfcalc_mttf_tj, tj)),
      c("T\\u2080",      sprintf("%.1f \\u00b0C  (%.1f K)", input$rfcalc_mttf_t0, t0)),
      c("E\\u2090",      sprintf("%.3f eV", ea)),
      c("Accel. factor", sprintf("%.3g\\u00d7 vs T\\u2080", ref / mttf))
    )
    tagList(
      tags$table(class = "table table-condensed",
        style = "font-size:13px; margin-top:4px;",
        tags$thead(tags$tr(tags$th("Parameter"), tags$th("Value"))),
        tags$tbody(lapply(rows, function(r) tags$tr(
          tags$td(style = "color:#aaa;", r[1]),
          tags$td(style = "color:#f0f0f0; font-family:monospace;", r[2])
        )))
      ),
      p(class = "text-muted", style = "font-size:10px; margin-top:4px;",
        "Arrhenius: MTTF(Tj) = MTTF(T\\u2080) \\u00d7 exp(E\\u2090/k \\u00d7 (1/T\\u2080 \\u2212 1/Tj))")
    )
  })

  output$rfcalc_therm_results <- renderUI({
    req(input$rfcalc_therm_pdiss, input$rfcalc_therm_tamb)
    pd   <- input$rfcalc_therm_pdiss
    tamb <- input$rfcalc_therm_tamb
    rja  <- input$rfcalc_therm_rja
    rjc  <- input$rfcalc_therm_rjc
    rca  <- input$rfcalc_therm_rca
    rows <- list()
    has_rja <- !is.null(rja) && !is.na(rja) && is.numeric(rja) && rja > 0
    has_rjc <- !is.null(rjc) && !is.na(rjc) && is.numeric(rjc) && rjc > 0
    has_rca <- !is.null(rca) && !is.na(rca) && is.numeric(rca) && rca > 0
    if (has_rja)
      rows[[length(rows)+1]] <- c("Tj (via R\\u03b8ja)",
        sprintf("%.1f \\u00b0C", tamb + pd * rja))
    if (has_rjc && has_rca) {
      rows[[length(rows)+1]] <- c("Tj (via R\\u03b8jc + R\\u03b8ca)",
        sprintf("%.1f \\u00b0C", tamb + pd * (rjc + rca)))
      rows[[length(rows)+1]] <- c("Tcase",
        sprintf("%.1f \\u00b0C", tamb + pd * rca))
    }
    if (length(rows) == 0)
      return(p(icon("info-circle"), " Enter at least one thermal resistance.", class = "text-muted"))
    rows[[length(rows)+1]] <- c("Pdiss", sprintf("%.4g W",   pd))
    rows[[length(rows)+1]] <- c("Tamb",  sprintf("%.1f \\u00b0C", tamb))
    tags$table(class = "table table-condensed",
      style = "font-size:13px; margin-top:4px;",
      tags$thead(tags$tr(tags$th("Parameter"), tags$th("Value"))),
      tags$tbody(lapply(rows, function(r) tags$tr(
        tags$td(style = "color:#aaa;", r[1]),
        tags$td(style = "color:#f0f0f0; font-family:monospace;", r[2])
      )))
    )
  })

"""

# =============================================================================
# Apply all changes
# =============================================================================

# Verify expected content at key line positions
assert '"smith_chart" = tagList(' in lines[96], f"Expected smith_chart at line 97, got: {lines[96]!r}"
assert '"lp_viewer" = tagList(' in lines[145], f"Expected lp_viewer at line 146, got: {lines[145]!r}"
assert 'uiOutput("lp_rpt_preview")' in lines[338], f"Expected lp_rpt_preview at line 339, got: {lines[338]!r}"
# Find serverDashboard line
server_dash_idx = next(i for i, l in enumerate(lines) if 'serverDashboard(' in l)
print(f"serverDashboard found at line {server_dash_idx + 1}")

# Change 1: Replace smith_chart case (0-indexed 96..142) with rf_calc
rf_calc_lines = RF_CALC.splitlines(keepends=True)
new_lines = lines[:96] + rf_calc_lines + lines[143:]  # skip lines[96..142]
print(f"After change 1: {len(new_lines)} lines (delta={(len(rf_calc_lines)-47):+d})")

# Recalculate the lp_viewer opening position (it shifted by delta)
delta1 = len(rf_calc_lines) - 47
lp_open_start = 144 + delta1  # original line 145 (0-indexed 144) + shift

# Verify
assert '"lp_viewer" = tagList(' in new_lines[lp_open_start + 1], \
    f"lp_viewer not at expected position {lp_open_start+2}, got: {new_lines[lp_open_start+1]!r}"

# Change 2: Replace lp_viewer opening header
# Replace lines lp_open_start..lp_open_start+8 (blank+comment+"lp_viewer"+div+p+icon+string1+string2) + tabsetPanel
# That's: line 144(blank), 145(comment), 146("lp_viewer"), 147(div), 148(p), 149(icon), 150(str1), 151(str2), 152(tabsetPanel)
# = 9 lines (0-indexed lp_open_start to lp_open_start+8)
rf_tools_open_lines = RF_TOOLS_OPEN.splitlines(keepends=True)
new_lines = new_lines[:lp_open_start] + rf_tools_open_lines + new_lines[lp_open_start + 9:]
print(f"After change 2: {len(new_lines)} lines (delta={(len(rf_tools_open_lines)-9):+d})")

# Recalculate lp_viewer end position
delta2 = len(rf_tools_open_lines) - 9
# Original lp end: line 344 (0-indexed 343) = tabPanel("LP Report") close
# = line 343 + delta1 + delta2
lp_close_idx = 343 + delta1 + delta2

# Verify: line at lp_close_idx should be '            )\n' (tabPanel LP Report close)
# and next line should be '          )\n' (tabsetPanel lp_tabs close)
print(f"lp_close_idx={lp_close_idx+1}: {new_lines[lp_close_idx]!r}")
print(f"lp_close_idx+1={lp_close_idx+2}: {new_lines[lp_close_idx+1]!r}")

assert new_lines[lp_close_idx].strip() == ')', f"Expected ) at {lp_close_idx+1}: {new_lines[lp_close_idx]!r}"
assert new_lines[lp_close_idx+1].strip() == ')', f"Expected ) at {lp_close_idx+2}: {new_lines[lp_close_idx+1]!r}"

# Change 3: Insert extra closing parens after the tabsetPanel(lp_tabs) close line
# Insert after lp_close_idx+1 (the lp_tabs close)
insert_pos = lp_close_idx + 2  # position AFTER the lp_tabs close line
new_lines = new_lines[:insert_pos] + EXTRA_CLOSE + new_lines[insert_pos:]
print(f"After change 3: {len(new_lines)} lines (+2 extra closing parens)")

# Change 4: Insert reactive outputs before serverDashboard
delta3 = 2  # from change 3
server_dash_idx2 = server_dash_idx + delta1 + delta2 + delta3
# Find serverDashboard again to be safe
server_dash_idx2 = next(i for i, l in enumerate(new_lines) if 'serverDashboard(' in l)
print(f"serverDashboard now at line {server_dash_idx2 + 1}")
calc_output_lines = CALC_OUTPUTS.splitlines(keepends=True)
new_lines = new_lines[:server_dash_idx2] + calc_output_lines + new_lines[server_dash_idx2:]
print(f"After change 4: {len(new_lines)} lines")

with open(SERVER_R, "w", encoding="utf-8") as fh:
    fh.writelines(new_lines)

print(f"\nDone. Wrote {len(new_lines)} lines to {SERVER_R}")
