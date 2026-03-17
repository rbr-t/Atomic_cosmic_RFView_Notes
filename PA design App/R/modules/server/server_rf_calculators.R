# ============================================================
# server_rf_calculators.R
# RF Calculators logic used by the utility drawer RF Calc panel.
# ============================================================

.registerPowerCalculator <- function(input, output) {
  output$calc_power_result <- renderUI({
    val  <- input$calc_power_val %||% 0
    unit <- input$calc_power_unit %||% "dBm"

    val_w <- switch(unit,
      dBm = 10^((val - 30) / 10),
      dBW = 10^(val / 10),
      W   = val,
      mW  = val / 1e3,
      uW  = val / 1e6
    )

    if (is.null(val_w) || is.na(val_w) || !is.finite(val_w) || val_w <= 0) {
      return(p(style = "color:#d62728;", "Input must map to positive power"))
    }

    from_w <- calc_power_from_watts(val_w)
    fmt <- function(x) formatC(signif(x, 5), format = "g")

    tags$table(class = "table table-condensed",
      style = "color:#f0f0f0; font-size:13px; margin:0;",
      tags$thead(tags$tr(tags$th("Unit"), tags$th("Value"))),
      tags$tbody(
        tags$tr(tags$td("dBm"), tags$td(fmt(from_w$dbm))),
        tags$tr(tags$td("dBW"), tags$td(fmt(from_w$dbw))),
        tags$tr(tags$td("W"), tags$td(fmt(from_w$watt))),
        tags$tr(tags$td("mW"), tags$td(fmt(from_w$watt * 1e3))),
        tags$tr(tags$td("uW"), tags$td(fmt(from_w$watt * 1e6)))
      )
    )
  })
}

.registerFrequencyCalculator <- function(input, output) {
  output$calc_freq_result <- renderUI({
    freq_val  <- input$calc_freq_val %||% 2400
    freq_unit <- input$calc_freq_unit %||% "MHz"
    er        <- max(1, input$calc_freq_er %||% 1)

    freq_ghz <- switch(freq_unit,
      Hz = freq_val / 1e9,
      kHz = freq_val / 1e6,
      MHz = freq_val / 1e3,
      GHz = freq_val
    )

    if (is.null(freq_ghz) || is.na(freq_ghz) || !is.finite(freq_ghz) || freq_ghz <= 0) {
      return(p(style = "color:#d62728;", "Enter a positive frequency"))
    }

    wl <- calc_wavelengths(freq_ghz, er)
    period_ns <- 1e9 / (freq_ghz * 1e9)
    fmt <- function(x) formatC(signif(x, 5), format = "g")

    tags$table(class = "table table-condensed",
      style = "color:#f0f0f0; font-size:13px; margin:0;",
      tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
      tags$tbody(
        tags$tr(tags$td("Freq (MHz)"), tags$td(fmt(wl$freq_mhz))),
        tags$tr(tags$td("Period (ns)"), tags$td(fmt(period_ns))),
        tags$tr(tags$td("Lambda free-space (mm)"), tags$td(fmt(wl$lambda_mm))),
        tags$tr(tags$td("Lambda/4 free-space (mm)"), tags$td(fmt(wl$lambda_mm / 4))),
        tags$tr(tags$td("Lambda guided (mm)"), tags$td(fmt(wl$lambda_eff_mm))),
        tags$tr(tags$td("Lambda/4 guided (mm)"), tags$td(fmt(wl$quarter_wave_mm)))
      )
    )
  })
}

# ---- Unified Gamma <-> Z (polar or rect input, bidirectional) ----------------
.registerGammaZCalculator <- function(input, output) {
  output$calc_gz_result <- renderUI({
    direction <- input$calc_gz_direction %||% "g2z"
    z0        <- input$calc_gz_z0 %||% 50
    fmt       <- function(x) formatC(signif(x, 6), format = "g")
    f_rl      <- function(gm) if (gm == 0) "\u221e dB" else paste0(fmt(-20 * log10(gm)), " dB")
    f_vswr    <- function(gm) if (gm >= 1) "\u221e" else paste0(fmt((1 + gm) / (1 - gm)), ":1")

    if (is.na(z0) || z0 <= 0)
      return(p(style = "color:#d62728;", "Z\u2080 must be > 0"))

    if (direction == "g2z") {
      # ---- Gamma -> Z ----
      fmt_type <- input$calc_gz_fmt %||% "polar"
      gamma <- if (fmt_type == "polar") {
        mag <- input$calc_gz_mag %||% 0.25
        ang <- input$calc_gz_ang %||% 0
        if (any(is.na(c(mag, ang)))) return(p(style = "color:#d62728;", "Invalid input"))
        mag * exp(1i * ang * pi / 180)
      } else {
        re <- input$calc_gz_re %||% 0.2
        im <- input$calc_gz_im %||% 0.1
        if (any(is.na(c(re, im)))) return(p(style = "color:#d62728;", "Invalid input"))
        complex(real = re, imaginary = im)
      }

      gm  <- Mod(gamma)
      zin <- z0 * (1 + gamma) / (1 - gamma)
      warn <- if (gm >= 1)
        p(style = "color:#e8a000; font-size:11px; margin:6px 0 0 0;",
          icon("exclamation-triangle"),
          " |\u0393| \u2265 1: active/unstable region \u2014 Z shown for reference")
      else NULL

      div(
        tags$table(class = "table table-condensed",
          style = "color:#f0f0f0; font-size:13px; margin:0;",
          tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
          tags$tbody(
            tags$tr(tags$td("|\u0393|"),            tags$td(fmt(gm))),
            tags$tr(tags$td("\u2220\u0393 (deg)"),  tags$td(fmt(Arg(gamma) * 180 / pi))),
            tags$tr(tags$td("Re(\u0393)"),          tags$td(fmt(Re(gamma)))),
            tags$tr(tags$td("Im(\u0393)"),          tags$td(fmt(Im(gamma)))),
            tags$tr(tags$td("R (\u03a9)"),          tags$td(fmt(Re(zin)))),
            tags$tr(tags$td("X (\u03a9)"),          tags$td(fmt(Im(zin)))),
            tags$tr(tags$td("Z (\u03a9)"),          tags$td(sprintf("%s %+.5gj", fmt(Re(zin)), Im(zin)))),
            tags$tr(tags$td("VSWR"),                tags$td(f_vswr(gm))),
            tags$tr(tags$td("Return Loss"),         tags$td(f_rl(gm)))
          )
        ),
        warn
      )
    } else {
      # ---- Z -> Gamma ----
      r_val <- input$calc_gz_r %||% 75
      x_val <- input$calc_gz_x %||% 25
      if (any(is.na(c(r_val, x_val))))
        return(p(style = "color:#d62728;", "Invalid input"))

      zin   <- complex(real = r_val, imaginary = x_val)
      gamma <- (zin - z0) / (zin + z0)
      gm    <- Mod(gamma)
      warn  <- if (r_val < 0)
        p(style = "color:#e8a000; font-size:11px; margin:6px 0 0 0;",
          icon("exclamation-triangle"),
          " R < 0: active region \u2014 |\u0393| may be \u2265 1")
      else NULL

      div(
        tags$table(class = "table table-condensed",
          style = "color:#f0f0f0; font-size:13px; margin:0;",
          tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
          tags$tbody(
            tags$tr(tags$td("|\u0393|"),            tags$td(fmt(gm))),
            tags$tr(tags$td("\u2220\u0393 (deg)"),  tags$td(fmt(Arg(gamma) * 180 / pi))),
            tags$tr(tags$td("Re(\u0393)"),          tags$td(fmt(Re(gamma)))),
            tags$tr(tags$td("Im(\u0393)"),          tags$td(fmt(Im(gamma)))),
            tags$tr(tags$td("VSWR"),                tags$td(f_vswr(gm))),
            tags$tr(tags$td("Return Loss"),         tags$td(f_rl(gm)))
          )
        ),
        warn
      )
    }
  })
}

# ---- Unified Gamma <-> VSWR (polar or rect input, bidirectional) -------------
.registerGammaVswrCalculator <- function(input, output) {
  output$calc_gv_result <- renderUI({
    direction <- input$calc_gv_direction %||% "g2v"
    fmt       <- function(x) formatC(signif(x, 6), format = "g")
    f_rl      <- function(gm) if (gm == 0) "\u221e dB" else paste0(fmt(-20 * log10(gm)), " dB")

    if (direction == "g2v") {
      # ---- Gamma -> VSWR ----
      fmt_type <- input$calc_gv_fmt %||% "polar"
      if (fmt_type == "polar") {
        gm <- input$calc_gv_mag %||% 0.25
        if (is.na(gm) || gm < 0)
          return(p(style = "color:#d62728;", "|\u0393| must be \u2265 0"))
        if (gm >= 1)
          return(div(
            p(style = "color:#f0f0f0;", paste0("|\u0393| = ", fmt(gm))),
            p(style = "color:#f0f0f0;", "VSWR = \u221e"),
            p(style = "color:#aaa; font-size:11px;", "Return Loss \u2192 0 dB as |\u0393| \u2192 1")
          ))
        tags$table(class = "table table-condensed",
          style = "color:#f0f0f0; font-size:13px; margin:0;",
          tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
          tags$tbody(
            tags$tr(tags$td("|\u0393|"),       tags$td(fmt(gm))),
            tags$tr(tags$td("VSWR"),           tags$td(paste0(fmt((1 + gm) / (1 - gm)), ":1"))),
            tags$tr(tags$td("Return Loss"),    tags$td(f_rl(gm)))
          )
        )
      } else {
        re <- input$calc_gv_re %||% 0.2
        im <- input$calc_gv_im %||% 0.1
        if (any(is.na(c(re, im))))
          return(p(style = "color:#d62728;", "Invalid input"))
        gm  <- sqrt(re^2 + im^2)
        ang <- atan2(im, re) * 180 / pi
        if (gm >= 1)
          return(div(
            p(style = "color:#f0f0f0;", paste0("|\u0393| = ", fmt(gm), "  \u2220 ", fmt(ang), "\u00b0")),
            p(style = "color:#f0f0f0;", "VSWR = \u221e"),
            p(style = "color:#aaa; font-size:11px;", "Return Loss \u2192 0 dB as |\u0393| \u2192 1")
          ))
        tags$table(class = "table table-condensed",
          style = "color:#f0f0f0; font-size:13px; margin:0;",
          tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
          tags$tbody(
            tags$tr(tags$td("|\u0393|"),       tags$td(fmt(gm))),
            tags$tr(tags$td("\u2220\u0393 (deg)"), tags$td(fmt(ang))),
            tags$tr(tags$td("VSWR"),           tags$td(paste0(fmt((1 + gm) / (1 - gm)), ":1"))),
            tags$tr(tags$td("Return Loss"),    tags$td(f_rl(gm)))
          )
        )
      }
    } else {
      # ---- VSWR -> Gamma ----
      vswr_val <- input$calc_gv_vswr %||% 2.0
      if (is.na(vswr_val) || vswr_val < 1)
        return(p(style = "color:#d62728;", "VSWR must be \u2265 1"))
      gm <- (vswr_val - 1) / (vswr_val + 1)
      tags$table(class = "table table-condensed",
        style = "color:#f0f0f0; font-size:13px; margin:0;",
        tags$thead(tags$tr(tags$th("Quantity"), tags$th("Value"))),
        tags$tbody(
          tags$tr(tags$td("VSWR"),        tags$td(paste0(fmt(vswr_val), ":1"))),
          tags$tr(tags$td("|\u0393|"),    tags$td(fmt(gm))),
          tags$tr(tags$td("Return Loss"), tags$td(f_rl(gm)))
        )
      )
    }
  })
}

.registerMttfCalculator <- function(input, output) {
  output$calc_mttf_result <- renderUI({
    mttf0 <- input$calc_mttf_ref %||% 1e6
    t0    <- input$calc_mttf_t0 %||% 125
    tj    <- input$calc_mttf_tj %||% 150
    ea    <- input$calc_mttf_ea %||% 0.7

    if (any(is.na(c(mttf0, t0, tj, ea))) || mttf0 <= 0 || ea <= 0) {
      return(p(style = "color:#d62728;", "Check inputs (MTTF0 and Ea must be > 0)"))
    }

    m <- calc_mttf(
      tj_c = tj,
      voltage_stress = 1,
      current_stress = 1,
      mttf_base_hours = mttf0,
      Ea = ea,
      T_ref_c = t0
    )

    fmt <- function(x) formatC(signif(x, 4), format = "g")

    tags$table(class = "table table-condensed",
      style = "color:#f0f0f0; font-size:13px; margin:0;",
      tags$thead(tags$tr(tags$th("Parameter"), tags$th("Value"))),
      tags$tbody(
        tags$tr(tags$td("Acceleration factor"), tags$td(fmt(m$acceleration_factor))),
        tags$tr(tags$td("MTTF at Tj (hours)"), tags$td(fmt(m$mttf_hours))),
        tags$tr(tags$td("MTTF at Tj (years)"), tags$td(fmt(m$mttf_years))),
        tags$tr(tags$td("Ea (eV)"), tags$td(fmt(m$activation_energy_eV))),
        tags$tr(tags$td("T0 (K)"), tags$td(sprintf("%.2f", t0 + 273.15))),
        tags$tr(tags$td("Tj (K)"), tags$td(sprintf("%.2f", tj + 273.15)))
      )
    )
  })
}

.registerThermalCalculator <- function(input, output) {
  output$calc_thermal_result <- renderUI({
    pdiss <- input$calc_th_pdiss %||% 10
    rjc   <- input$calc_th_rth_jc %||% 3
    rcs   <- input$calc_th_rth_cs %||% 1
    rsa   <- input$calc_th_rth_sa %||% 5
    tamb  <- input$calc_th_tamb %||% 25

    if (any(is.na(c(pdiss, rjc, rcs, rsa, tamb))) || any(c(rjc, rcs, rsa) < 0)) {
      return(p(style = "color:#d62728;", "Check thermal inputs"))
    }

    rth_tot <- rjc + rcs + rsa
    t_case <- tamb + pdiss * rsa
    t_junc <- tamb + pdiss * rth_tot
    warn_s <- if (t_junc > 200) "color:#d62728; font-weight:600;" else "color:#f0f0f0;"
    f1 <- function(x) sprintf("%.1f C", x)

    div(
      tags$table(class = "table table-condensed",
        style = "color:#f0f0f0; font-size:13px; margin:0;",
        tags$thead(tags$tr(tags$th("Node"), tags$th("Temperature"))),
        tags$tbody(
          tags$tr(tags$td("Tambient"), tags$td(f1(tamb))),
          tags$tr(tags$td("Tcase"), tags$td(f1(t_case))),
          tags$tr(tags$td("Tjunction"), tags$td(tags$span(style = warn_s, f1(t_junc))))
        )
      ),
      p(style = "color:#aaa; font-size:11px; margin-top:6px;",
        paste0("Rth_total = ", sprintf("%.2f", rth_tot), " C/W | Pdiss = ", sprintf("%.1f", pdiss), " W"))
    )
  })
}

serverRfCalculators <- function(input, output, session, state) {
  .registerPowerCalculator(input, output)
  .registerFrequencyCalculator(input, output)
  .registerGammaZCalculator(input, output)
  .registerGammaVswrCalculator(input, output)
  .registerMttfCalculator(input, output)
  .registerThermalCalculator(input, output)
}
