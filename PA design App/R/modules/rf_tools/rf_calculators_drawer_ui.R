# ============================================================
# rf_calculators_drawer_ui.R
# Utility drawer UI for RF Calculators panel.
# ============================================================

rfCalculatorsDrawerUI <- function() {
  tagList(
    div(style = "padding:4px 0 10px 0;",
      p(style = "color:#aaa; font-size:12px; margin:0 0 8px 0;",
        icon("calculator"), " Quick-access RF engineering calculators."),
      tabsetPanel(id = "rf_calc_tabs",

        # Power Converter (dBm, dBW, W, mW, uW)
        tabPanel(tagList(icon("bolt"), " Power"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_power_val", "Value", value = 0, step = 0.1),
                selectInput("calc_power_unit", "Unit",
                  choices  = c("dBm" = "dBm", "dBW" = "dBW",
                               "W"   = "W",   "mW"  = "mW",  "\u00b5W" = "uW"),
                  selected = "dBm")
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Conversions", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_power_result")
              )
            )
          )
        ),

        # Frequency / Wavelength
        tabPanel(tagList(icon("wave-square"), " Freq / Wave"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_freq_val", "Frequency",
                  value = 2400, min = 0.001, step = 1),
                selectInput("calc_freq_unit", "Unit",
                  choices  = c("Hz" = "Hz", "kHz" = "kHz",
                               "MHz" = "MHz", "GHz" = "GHz"),
                  selected = "MHz"),
                numericInput("calc_freq_er",
                  "Dielectric \u03b5r (for guided \u03bb)",
                  value = 1, min = 1, max = 100, step = 0.1)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Results", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_freq_result")
              )
            )
          )
        ),

        # Gamma to Impedance
        tabPanel(tagList(icon("project-diagram"), " Gamma -> Z"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_gamma_mag", "|Gamma|", value = 0.25, min = 0, max = 0.9999, step = 0.01),
                numericInput("calc_gamma_phase", "Angle Gamma (deg)", value = 0, min = -180, max = 180, step = 1),
                numericInput("calc_gamma_z0", "Z0 (Ohm)", value = 50, min = 0.1, step = 0.1)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Impedance", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_gamma_imp_result")
              )
            )
          )
        ),

        # Gamma (Re+jIm) to Impedance -- Smith chart variant
        tabPanel(tagList(icon("project-diagram"), " Gamma (Re+jIm) -> Z"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                p(style = "color:#aaa; font-size:11px; margin:0 0 8px 0;",
                  "Enter \u0393 as rectangular coordinates (e.g. from a Smith chart click)."),
                numericInput("calc_gamma_re", "Re(\u0393)", value = 0.2, step = 0.01),
                numericInput("calc_gamma_im", "Im(\u0393)", value = 0.1, step = 0.01),
                numericInput("calc_gamma_rect_z0", "Z0 (\u03a9)", value = 50, min = 0.1, step = 0.1)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Impedance & reflection", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_gamma_rect_result")
              )
            )
          )
        ),

        # Gamma to VSWR
        tabPanel(tagList(icon("signal"), " Gamma -> VSWR"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_gamma_vswr_mag", "|Gamma|", value = 0.25, min = 0, max = 0.9999, step = 0.01)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("VSWR / Return Loss", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_gamma_vswr_result")
              )
            )
          )
        ),

        # MTTF (Arrhenius)
        tabPanel(tagList(icon("hourglass-half"), " MTTF"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Arrhenius parameters", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_mttf_ref", "Reference MTTF0 (hours)",
                  value = 1e6, min = 1, step = 1),
                numericInput("calc_mttf_t0", "Reference temp T0 (C)",
                  value = 125, step = 1),
                numericInput("calc_mttf_tj", "Operating junction Tj (C)",
                  value = 150, step = 1),
                numericInput("calc_mttf_ea", "Activation energy Ea (eV)",
                  value = 0.7, min = 0.1, max = 3, step = 0.05)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("MTTF at Tj operating", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_mttf_result")
              )
            )
          )
        ),

        # Thermal
        tabPanel(tagList(icon("thermometer-half"), " Thermal"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Thermal stack", style = "color:#f0f0f0; margin-top:0;"),
                numericInput("calc_th_pdiss",  "Pdiss (W)",
                  value = 10, min = 0, step = 0.5),
                numericInput("calc_th_rth_jc", "Rth_jc (C/W)",
                  value = 3,  min = 0, step = 0.1),
                numericInput("calc_th_rth_cs", "Rth_cs (C/W)",
                  value = 1,  min = 0, step = 0.1),
                numericInput("calc_th_rth_sa", "Rth_sa heatsink (C/W)",
                  value = 5,  min = 0, step = 0.1),
                numericInput("calc_th_tamb",   "Tambient (C)",
                  value = 25, step = 1)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Results", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_thermal_result")
              )
            )
          )
        )
      )
    )
  )
}
