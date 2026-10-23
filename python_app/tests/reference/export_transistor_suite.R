# Offline oracle regeneration; Python execution does not require R.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
source_path <- file.path(root, "PA design App/src/modules/calculations/calc_transistor_sizing.R")
`%||%` <- function(a, b) if (!is.null(a)) a else b
source(source_path)
strip_formulas <- function(value) {
  if (!is.list(value)) return(value)
  value <- value[!grepl("^formula", names(value))]
  lapply(value, strip_formulas)
}
cases <- list()
capture <- function(name, stage, frequency, topology, er = 3.55, h_mm = 0.508) {
  cases[[length(cases) + 1]] <<- list(
    name = name, stage = stage, freq_ghz = frequency, topology = topology,
    er = er, h_mm = h_mm,
    expected = strip_formulas(calc_transistor_design_suite(
      stage, frequency, topology, er, h_mm
    ))
  )
}
for (topology in c("single_ended", "doherty_symmetric",
                    "doherty_asymmetric_6dB", "doherty_asymmetric_9dB")) {
  capture(paste(topology, "defaults"), list(), 3.5, topology)
  capture(paste(topology, "10W"), list(pout_dbm = 40, pae_pct = 55, vdd_v = 28),
          1.8, topology)
  capture(paste(topology, "48V"), list(pout_dbm = 50, pae_pct = 65, vdd_v = 48),
          6, topology, 4.4, 0.8)
}
capture("unity-input-match", list(
  pout_dbm = 10 * log10(((28 - 2)^2 / (2 * 250)) * 1000),
  pae_pct = 50, vdd_v = 28
), 3.5, "single_ended")
capture("clamped-input-match", list(pout_dbm = 55, pae_pct = 60, vdd_v = 28),
        3.5, "single_ended")
capture("low-efficiency", list(pout_dbm = 40, pae_pct = 1, vdd_v = 28),
        3.5, "doherty_symmetric")
capture("high-efficiency", list(pout_dbm = 40, pae_pct = 100, vdd_v = 28),
        3.5, "doherty_symmetric")
temporary <- tempfile()
text <- paste0(paste(readLines(source_path, warn = FALSE, encoding = "UTF-8"),
                     collapse = "\n"), "\n")
writeBin(charToRaw(text), temporary)
hash <- unname(tools::md5sum(temporary))
unlink(temporary)
jsonlite::write_json(list(
  provenance = list(runtime = R.version.string, source_md5 = hash,
                    note = "All nested numerical/structural fields; formula prose excluded."),
  cases = cases
), file.path(root, "python_app/tests/fixtures/transistor_suite_reference.json"),
   auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null", na = "null")
cat("Exported", length(cases), "transistor suite cases\n")
