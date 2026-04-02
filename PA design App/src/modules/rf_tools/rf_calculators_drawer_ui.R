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

        # Gamma <-> Z (unified: polar or rect input, bidirectional)
        tabPanel(tagList(icon("project-diagram"), " \u0393 \u2194 Z"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                radioButtons("calc_gz_direction", label = NULL,
                  choices  = c("\u0393 \u2192 Z" = "g2z", "Z \u2192 \u0393" = "z2g"),
                  selected = "g2z", inline = TRUE),
                hr(style = "border-color:#3a3a4a; margin:6px 0;"),
                # --- Gamma -> Z inputs ---
                conditionalPanel("input.calc_gz_direction === 'g2z'",
                  radioButtons("calc_gz_fmt", "\u0393 format",
                    choices  = c("Mag / Phase" = "polar", "Re + jIm" = "rect"),
                    selected = "polar", inline = TRUE),
                  conditionalPanel("input.calc_gz_fmt === 'polar'",
                    numericInput("calc_gz_mag", "|\u0393|",
                      value = 0.25, min = 0, max = 2, step = 0.01),
                    numericInput("calc_gz_ang", "\u2220\u0393 (deg)",
                      value = 0, min = -180, max = 180, step = 1)
                  ),
                  conditionalPanel("input.calc_gz_fmt === 'rect'",
                    numericInput("calc_gz_re", "Re(\u0393)", value =  0.2, step = 0.01),
                    numericInput("calc_gz_im", "Im(\u0393)", value =  0.1, step = 0.01)
                  )
                ),
                # --- Z -> Gamma inputs ---
                conditionalPanel("input.calc_gz_direction === 'z2g'",
                  numericInput("calc_gz_r", "R (\u03a9)", value =  75, step = 1),
                  numericInput("calc_gz_x", "X (\u03a9)", value =  25, step = 1)
                ),
                hr(style = "border-color:#3a3a4a; margin:6px 0;"),
                numericInput("calc_gz_z0", "Z\u2080 (\u03a9)", value = 50, min = 0.1, step = 0.1)
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Results", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_gz_result")
              )
            )
          )
        ),

        # Gamma <-> VSWR (unified: polar or rect input, bidirectional)
        tabPanel(tagList(icon("signal"), " \u0393 \u2194 VSWR"),
          br(),
          fluidRow(
            column(5,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Input", style = "color:#f0f0f0; margin-top:0;"),
                radioButtons("calc_gv_direction", label = NULL,
                  choices  = c("\u0393 \u2192 VSWR" = "g2v", "VSWR \u2192 \u0393" = "v2g"),
                  selected = "g2v", inline = TRUE),
                hr(style = "border-color:#3a3a4a; margin:6px 0;"),
                # --- Gamma -> VSWR inputs ---
                conditionalPanel("input.calc_gv_direction === 'g2v'",
                  radioButtons("calc_gv_fmt", "\u0393 format",
                    choices  = c("Mag / Phase" = "polar", "Re + jIm" = "rect"),
                    selected = "polar", inline = TRUE),
                  conditionalPanel("input.calc_gv_fmt === 'polar'",
                    numericInput("calc_gv_mag", "|\u0393|",
                      value = 0.25, min = 0, max = 2, step = 0.01)
                  ),
                  conditionalPanel("input.calc_gv_fmt === 'rect'",
                    numericInput("calc_gv_re", "Re(\u0393)", value =  0.2, step = 0.01),
                    numericInput("calc_gv_im", "Im(\u0393)", value =  0.1, step = 0.01)
                  )
                ),
                # --- VSWR -> Gamma input ---
                conditionalPanel("input.calc_gv_direction === 'v2g'",
                  numericInput("calc_gv_vswr", "VSWR", value = 2.0, min = 1, step = 0.1)
                )
              )
            ),
            column(7,
              div(class = "well",
                style = "background:#1e1e2e; border:1px solid #2a2a3a; padding:12px;",
                h5("Results", style = "color:#f0f0f0; margin-top:0;"),
                uiOutput("calc_gv_result")
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
