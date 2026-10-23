# Optional reference regeneration. The Python application does not require R.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
source_path <- file.path(root, "PA design App/src/modules/calculations/calc_guardrails.R")
yaml_path <- file.path(root, "PA design App/config/technology_guardrails.yaml")
source(source_path)
catalog <- yaml::read_yaml(yaml_path)
cases <- list()
capture <- function(name, inputs) {
  result <- do.call(validateDeviceParams, c(inputs, list(guardrails = catalog)))
  cases[[length(cases) + 1]] <<- list(
    name = name,
    inputs = inputs,
    expected = list(
      status = result$status,
      error_count = length(result$errors),
      warning_count = length(result$warnings),
      tech = result$tech,
      freq_ghz = result$freq_ghz,
      max_gain_available = result$max_gain_available,
      pae_max_practical = result$pae_max_practical
    )
  )
}
for (key in names(catalog$technologies)) {
  tech <- catalog$technologies[[key]]
  fr <- tech$freq_range_ghz
  base <- list(
    tech_key = key, freq_ghz = (fr$sweet_spot_min + fr$sweet_spot_max) / 2,
    gain_db = 0, pae_pct = tech$pae_pct$typical_p3db,
    pout_dbm = 30, vdd = tech$vdd$typical
  )
  capture(paste(key, "nominal"), base)
  for (freq in c(fr$min - 0.01, fr$min, fr$sweet_spot_min, fr$sweet_spot_max,
                 fr$max, fr$max + 0.01)) {
    inputs <- base
    inputs$freq_ghz <- freq
    capture(paste(key, "freq", freq), inputs)
  }
  gain <- calcAvailableGain(base$freq_ghz, tech$gain_db$ft_ghz_typical,
                            tech$gain_db$fmax_ghz_typical)
  for (margin in c(3, 3.0001, 6, 6.0001)) {
    inputs <- base
    inputs$gain_db <- gain + margin
    capture(paste(key, "gain margin", margin), inputs)
  }
  for (pae in c(tech$pae_pct$max_practical_p3db,
                tech$pae_pct$max_practical_p3db + 0.0001, 80, 80.0001)) {
    inputs <- base
    inputs$pae_pct <- pae
    capture(paste(key, "pae", pae), inputs)
  }
  for (voltage in c(tech$vdd$max_abs, tech$vdd$max_abs + 0.0001)) {
    inputs <- base
    inputs$vdd <- voltage
    capture(paste(key, "voltage", voltage), inputs)
  }
  for (density in c(tech$pout_density_w_per_mm$max * 0.9,
                    tech$pout_density_w_per_mm$max * 0.9 + 0.0001,
                    tech$pout_density_w_per_mm$max,
                    tech$pout_density_w_per_mm$max + 0.0001)) {
    inputs <- base
    inputs$pout_density <- density
    capture(paste(key, "density", density), inputs)
  }
  inputs <- base
  inputs$freq_ghz <- fr$max + 1
  inputs$gain_db <- 100
  inputs$pae_pct <- 99
  inputs$vdd <- tech$vdd$max_abs + 1
  inputs$pout_density <- tech$pout_density_w_per_mm$max + 1
  capture(paste(key, "combined errors"), inputs)
}
canonical_md5 <- function(path) {
  temp <- tempfile()
  on.exit(unlink(temp))
  text <- paste0(paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
                       collapse = "\n"), "\n")
  writeBin(charToRaw(text), temp)
  unname(tools::md5sum(temp))
}
destination <- file.path(root, "python_app/tests/fixtures/guardrail_reference.json")
jsonlite::write_json(list(
  provenance = list(
    runtime = R.version.string,
    source_md5 = canonical_md5(source_path),
    config_md5 = canonical_md5(yaml_path),
    note = "Statuses, counts and numeric outputs; diagnostic prose deliberately not frozen."
  ),
  cases = cases
), destination, auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
cat("Exported", length(cases), "guardrail cases\n")
