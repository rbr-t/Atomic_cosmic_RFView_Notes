# ============================================================
# server_settings.R
# Server module: Settings tab.
#
# Handles:
#   - Theme switching (dark / light / colorblind)
#   - Accent colour via CSS custom property
#   - Live theme preview card
#
# Requires shinyjs (useShinyjs() already present in ui.R sidebar).
# ============================================================

serverSettings <- function(input, output, session, state) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── Apply theme immediately when the selector changes ────────
  observeEvent(input$theme_select, {
    theme <- input$theme_select %||% "dark"
    # Remove any previously-applied theme classes, then add the new one.
    # "dark" is the CSS baseline (no class needed), others need a class.
    shinyjs::runjs(sprintf('
      document.body.classList.remove("theme-light", "theme-colorblind");
      if ("%s" !== "dark") { document.body.classList.add("theme-%s"); }
    ', theme, theme))
  }, ignoreInit = TRUE)

  # ── Accent colour via CSS custom property on <html> ──────────
  # Derived rules (hover, etc.) computed at same time.
  observeEvent(input$accent_color, {
    col <- input$accent_color %||% "#ff7f11"
    shinyjs::runjs(sprintf(
      'document.documentElement.style.setProperty("--app-accent", "%s");',
      col
    ))
  }, ignoreInit = TRUE)

  # ── Live preview card ─────────────────────────────────────────
  output$settings_theme_preview <- renderUI({
    theme  <- input$theme_select %||% "dark"
    accent <- input$accent_color %||% "#ff7f11"

    cfg <- switch(theme,
      light      = list(bg = "#ffffff", page = "#f0f2f5",
                        text = "#1a1a1a", sub = "#666",
                        label = "Light Mode"),
      colorblind = list(bg = "#1b1b1b", page = "#0a0a1e",
                        text = "#e0e0e0", sub = "#aaa",
                        label = "Colorblind-Friendly (Dark)"),
      # dark is default
      list(bg = "#1b1b1b", page = "#0b0b0b",
           text = "#e0e0e0", sub = "#aaa",
           label = "Dark Mode")
    )

    div(
      style = sprintf(
        "background:%s; border-radius:8px; padding:14px 16px; border:1px solid #444; margin-top:12px;",
        cfg$page
      ),
      div(
        style = sprintf(
          "background:%s; border-radius:6px; padding:12px 16px; border-left:4px solid %s;",
          cfg$bg, accent
        ),
        div(
          style = sprintf("color:%s; font-weight:bold; font-size:13px; margin-bottom:8px;",
                          cfg$text),
          icon("eye"), " Preview — ", cfg$label
        ),
        div(style = sprintf("color:%s; font-size:12px;", cfg$text),
            "Primary text — readable on this background"),
        div(style = sprintf("color:%s; font-size:11px; margin-top:4px;", cfg$sub),
            "Secondary / muted text — should be distinguishable"),
        div(
          style = "margin-top:10px; display:flex; gap:8px; flex-wrap:wrap;",
          div(
            style = sprintf(
              "background:%s; color:#fff; padding:5px 12px; border-radius:4px; font-size:12px; font-weight:bold;",
              accent
            ),
            "Accent Button"
          ),
          div(style = "background:#27ae60; color:#fff; padding:5px 12px; border-radius:4px; font-size:12px;",
              "Success"),
          div(style = "background:#e74c3c; color:#fff; padding:5px 12px; border-radius:4px; font-size:12px;",
              "Error")
        )
      )
    )
  })

  # ── Active theme indicator ────────────────────────────────────
  output$settings_active_theme <- renderUI({
    theme  <- input$theme_select %||% "dark"
    accent <- input$accent_color %||% "#ff7f11"

    icon_name <- switch(theme,
      light      = "sun",
      colorblind = "universal-access",
      "moon"
    )
    label <- switch(theme,
      light      = "Light Mode active",
      colorblind = "Colorblind-Friendly active",
      "Dark Mode active"
    )

    div(
      style = sprintf(
        "border-left:4px solid %s; background:#1a2a1a; padding:8px 12px; border-radius:3px; color:#7fff7f; font-size:12px; margin-top:6px;",
        accent
      ),
      icon(icon_name), " ", label, " — changes apply instantly."
    )
  })

}
