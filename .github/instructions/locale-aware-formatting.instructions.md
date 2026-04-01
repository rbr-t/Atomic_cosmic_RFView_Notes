---
description: "Use when: writing or editing any R Shiny module that displays dates, times, numbers, currencies, or user-facing text strings. Enforces locale-aware formatting so values respect rv$lang and feel natural to a native speaker of the chosen language."
applyTo: "R/modules/**"
---

# Locale-Aware Formatting in Shiny Modules

These rules apply to **every file under `R/modules/`**. The app supports 54 languages via `rv$lang` (a reactive character value holding a BCP-47 code). All user-visible output must respect this value.

---

## 1. User-Visible Strings — Always Use `t()`

`t()` is defined in `R/i18n.R`:
```r
t(key, lang = getOption("album_lang", "en"), default = NULL)
```

**Rules:**
- ALL `showNotification()` arguments must use `t("key")` — never a bare English string.
- ALL `validate()` / `need()` error messages must use `t("key")`.
- ALL `tags$*` label text that is user-visible must have a `data-i18n="key"` attribute so the browser JS (`i18n_apply`) can update it reactively.
- When a message is dynamic (includes a variable), use `sprintf(t("key"), variable)` — never `paste()` with raw English.

**Good:**
```r
showNotification(t("photo_saved"), type = "message", duration = 2)
showNotification(sprintf(t("photos_imported_n"), n), type = "message")
validate(need(!is.null(rv$photos), t("no_photos_loaded")))
```

**Bad:**
```r
showNotification("Photo saved!", type = "message", duration = 2)   # ❌ hard-coded
showNotification(paste(n, "photos imported"), type = "message")    # ❌ hard-coded
validate(need(!is.null(rv$photos), "Please upload photos first"))  # ❌ hard-coded
```

If the key doesn't exist in `R/i18n.R` yet, **add it** to the `en` block first, then add it to `es`, `fr`, `de`, `ja`, `zh` blocks.

---

## 2. Date Formatting

Use `format_date_locale()` (defined in `R/i18n.R`) or apply these rules manually:

```r
# Pattern: use rv$lang to choose format
format_date_for_lang <- function(date, lang = getOption("album_lang", "en")) {
  switch(
    substr(lang, 1, 2),
    "en" = format(date, "%m/%d/%Y"),         # US: 03/31/2026
    "de" = format(date, "%d.%m.%Y"),         # Germany: 31.03.2026
    "fr" = format(date, "%d/%m/%Y"),         # France: 31/03/2026
    "ja" = format(date, "%Y\u5e74%m\u6708%d\u65e5"), # Japan: 2026年03月31日
    "zh" = format(date, "%Y\u5e74%m\u6708%d\u65e5"), # Chinese: same as Japanese
    "ko" = format(date, "%Y\u b144 %m\uc6d4 %d\uc77c"), # Korean
    "ar" = format(date, "%d/%m/%Y"),         # Arabic: uses Gregorian in modern apps
    format(date, "%d/%m/%Y")                 # Default: DD/MM/YYYY (most of world)
  )
}
```

**Rule:** Never hard-code `format(date, "%m/%d/%Y")` without a locale check. Wrap in the helper above or use `lubridate::stamp_date()` with a locale-aware template.

---

## 3. Number Formatting

```r
# For large numbers: thousands separator and decimal mark vary by locale
format_number_locale <- function(n, lang = getOption("album_lang", "en")) {
  lc <- substr(lang, 1, 2)
  if (lc %in% c("de", "fr", "es", "it", "pt", "nl", "pl", "ru", "uk")) {
    # European: period for thousands, comma for decimal
    formatC(n, format = "f", digits = 0, big.mark = ".", decimal.mark = ",")
  } else if (lc %in% c("en", "ja", "zh", "ko")) {
    # Anglo/CJK: comma for thousands, period for decimal
    formatC(n, format = "f", digits = 0, big.mark = ",", decimal.mark = ".")
  } else {
    # Safe default
    formatC(n, format = "f", digits = 0, big.mark = ",", decimal.mark = ".")
  }
}
```

**Apply to:** photo counts, page counts, file sizes, any `renderText()` output showing a number to the user.

---

## 4. Currency Formatting

Currency is handled by `R/pricing_config.R`. When displaying a price in a module:

```r
# Always fetch currency symbol from config — never hard-code "$"
cfg   <- get_pricing_config()
sym   <- cfg$currency[[rv$lang]] %||% "$"
price <- cfg$tiers[[tier]]$price_monthly

# Render: symbol position varies by locale
# LTR languages: "$9.99"   RTL languages: "9.99 $" (space before symbol)
langs       <- get_available_languages()
is_rtl      <- isTRUE(langs$rtl[langs$code == rv$lang])
price_str   <- if (is_rtl) paste(format(price, nsmall=2), sym) else paste0(sym, format(price, nsmall=2))
```

---

## 5. RTL-Safe Dynamic String Construction

For languages marked `rtl = TRUE` in `get_available_languages()` (Arabic `ar`, Hebrew `he`, Persian `fa`, Urdu `ur`):

- Numbers within RTL strings must remain LTR — wrap them in HTML `<bdi>` tags in `renderUI()` outputs:
  ```r
  tags$p(t("page_n_of_m"),
    tags$bdi(current_page),
    t("of"),
    tags$bdi(total_pages))
  ```
- Do NOT use `paste(total, t("photos_uploaded"))` for RTL — the word order may reverse. Use `sprintf(t("n_photos_uploaded"), total)` so translators control word order.

---

## 6. Plurals

English uses singular/plural. Many languages have more forms (Russian: 3, Arabic: 6). Keep plural logic in the translation key, not R code:

```r
# BAD:
msg <- if (n == 1) "1 photo added" else paste(n, "photos added")  # ❌ English-only logic

# GOOD:
# Add key "photos_added_n" = "%d photos added" in English
# Arabic translator provides: "%d صورة مضافة" / "%d صورتان مضافتان" etc.
msg <- sprintf(t("photos_added_n"), n)
```

For now (while only 6 languages have full coverage), acceptable to keep simple plurals. Document the key in `i18n.R` with a comment: `# plural-aware key — update when adding languages with complex plural rules`.

---

## Quick Checklist Before Committing a Module Edit

- [ ] No bare English strings in `showNotification()`, `validate()`, `need()`
- [ ] Date display uses locale-aware format function
- [ ] Number display uses locale-aware separators
- [ ] Currency symbol sourced from `pricing_config.R`, not hard-coded
- [ ] Any new translation key added to `en` + 5 full-coverage language blocks in `i18n.R`
- [ ] `data-i18n="key"` attribute present on all static label elements
