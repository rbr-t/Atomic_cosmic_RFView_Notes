# Offline synthetic-fixture oracle; runtime and tests do not require R.
args <- commandArgs(trailingOnly=FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash="/")
path <- file.path(root, "PA design App/src/modules/rf_tools/lp_parsers.R")
source(path)
normalized_md5 <- function(path) {
  temporary <- tempfile()
  writeBin(charToRaw(paste0(paste(readLines(path, warn=FALSE, encoding="UTF-8"),
                               collapse="\n"), "\n")), temporary)
  hash <- unname(tools::md5sum(temporary))
  unlink(temporary)
  hash
}
formats <- c(spl="reference.spl", focus="reference.focus",
  lpcwave="reference.lpcwave", mdf="reference.mdf", amcad="reference.amcad.csv",
  anteverta="reference.anteverta.csv", mdif="reference.mdif")
fields <- c("gl_r","gl_i","gs_r","gs_i","pout_dbm","pin_dbm","pout_w","pin_w",
            "gain_db","pae_pct","de_pct","idc_a","vdc_v","pdc_w","freq_ghz")
cases <- lapply(names(formats), function(fmt) {
  file <- file.path(root, "python_app/tests/fixtures/loadpull", formats[[fmt]])
  result <- parse_lp_file(file, fmt)
  if (!result$success) stop(paste(fmt, result$error))
  list(format=fmt, filename=formats[[fmt]], fixture_md5=normalized_md5(file),
       points=result$points[,fields])
})
hash <- normalized_md5(path)
jsonlite::write_json(list(provenance=list(runtime=R.version.string, source_md5=hash),
  cases=cases), file.path(root, "python_app/tests/fixtures/loadpull_reference.json"),
  pretty=TRUE, auto_unbox=TRUE, digits=16, na="null", null="null")
cat("Exported", length(cases), "load-pull adapter cases\n")
