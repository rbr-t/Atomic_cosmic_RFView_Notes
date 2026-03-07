# ============================================================
# server_settings.R
# Server module: Settings tab.
#
# Theme switching works by toggling a class on <body>:
#   dark:        no class  (CSS :root tokens apply)
#   light:       body.theme-light
#   colorblind:  body.theme-colorblind
# ============================================================

serverSettings <- function(input, output, session, state) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  # ── Theme class toggle (instant, no reload) ───────────────────
  observeEvent(input$theme_select, {
    theme <- input$theme_select %||% "dark"
    shinyjs::runjs(sprintf(
      'document.body.classList.remove("theme-light","theme-colorblind");
       if ("%s" !== "dark") document.body.classList.add("theme-%s");',
      theme, theme
    ))
  }, ignoreInit = TRUE)

  # ── Accent colour override ────────────────────────────────────
  observeEvent(input$accent_color, {
    col <- input$accent_color %||% "#f08030"
    shinyjs::runjs(sprintf(
      'var r=document.documentElement;
       r.style.setProperty("--accent",      "%s");
       r.style.setProperty("--accent-hi",   "%s");
       r.style.setProperty("--accent-dim",  "%s");
       r.style.setProperty("--accent-glow", "%scc");
       r.style.setProperty("--accent-tint", "%s22");',
      col, col, col, col, col
    ))
  }, ignoreInit = TRUE)

  # ── Live preview card ─────────────────────────────────────────
  output$settings_theme_preview <- renderUI({
    theme  <- input$theme_select %||% "dark"
    accent <- input$accent_color %||% "#f08030"

    cfg <- switch(theme,
      light = list(
        page = "#edf0f5", card = "#ffffff",
        t1 = "#1a1b2e",  t2 = "#4e5068",
        ok = "#186f3d",  err = "#b02828",
        bdr = "#c8cad8", label = "Light Mode"
      ),
      colorblind = list(
        page = "#0d0d16", card = "#1a1b2e",
        t1 = "#ecedf8",   t2 = "#9a9bac",
        ok = "#009988",   err = "#994f00",
        bdr = "#2e3050",  label = "Colorblind-Friendly (Dark)"
      ),
      list(
        page = "#0d0d16", card = "#1a1b2e",
        t1 = "#ecedf8",   t2 = "#9a9bac",
        ok = "#4cbb7f",   err = "#e05252",
        bdr = "#2e3050",  label = "Dark Mode"
      )
    )

    div(
      style = sprintf(
        "background:%s; border-radius:8px; padding:14px 16px; border:1px solid %s; margin-top:12px;",
        cfg$page, cfg$bdr
      ),
      div(
        style = sprintf(
          "background:%s; border-radius:5px; padding:14px 16px; border-left:4px solid %s;",
          cfg$card, accent
        ),
        div(style = sprintf("color:%s; font-weight:700; font-size:13px; margin-bottom:10px;", cfg$t1),
            icon("eye"), " Preview — ", cfg$label),
        div(style = sprintf("color:%s; font-size:13px; margin-bottom:4px;", cfg$t1),
            "Primary text — readable on this background"),
        div(style = sprintf("color:%s; font-size:12px; margin-bottom:12px;", cfg$t2),
            "Secondary / muted text — distinguishable from primary"),
        div(
          style = "display:flex; gap:8px; flex-wrap:wrap;",
          div(style = sprintf("background:%s; color:#fff; padding:5px 14px; border-radius:3px; font-size:12px; font-weight:600;", accent), "Accent"),
          div(style = sprintf("background:%s; color:#fff; padding:5px 14px; border-radius:3px; font-size:12px;", cfg$ok),  "OK"),
          div(style = sprintf("background:%s; color:#fff; padding:5px 14px; border-radius:3px; font-size:12px;", cfg$err), "Error")
        )
      )
    )
  })

  # ── Status badge ──────────────────────────────────────────────
  output$settings_active_theme <- renderUI({
    theme  <- input$theme_select %||% "dark"
    accent <- input$accent_color %||% "#f08030"

    info <- switch(theme,
      light      = list(icon = "sun",              text = "Light Mode active"),
      colorblind = list(icon = "universal-access", text = "Colorblind-Friendly active"),
      list(icon = "moon", text = "Dark Mode active")
    )

    div(
      style = sprintf(
        "border-left:4px solid %s; background:var(--c-ok-bg); padding:8px 12px; border-radius:3px; color:var(--c-ok); font-size:12px; margin-top:6px;",
        accent
      ),
      icon(info$icon), " ", info$text, " — changes apply instantly."
    )
  })

}
