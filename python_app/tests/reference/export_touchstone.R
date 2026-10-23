# Offline oracle generation only; synthetic files are committed with the tests.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
source_path <- file.path(root, "PA design App/src/modules/rf_tools/sp_parsers.R")
source(source_path)
canonical_md5 <- function(path) {
  temp <- tempfile()
  on.exit(unlink(temp))
  text <- paste0(paste(readLines(path, warn = FALSE, encoding = "UTF-8"),
                       collapse = "\n"), "\n")
  writeBin(charToRaw(text), temp)
  unname(tools::md5sum(temp))
}
files <- list.files(file.path(root, "python_app/tests/fixtures/touchstone"),
                    pattern = "\\.s[12]p$", full.names = TRUE)
cases <- lapply(files, function(path) {
  result <- parse_sp_file(path)
  stopifnot(isTRUE(result$success))
  list(filename = basename(path), md5 = canonical_md5(path),
       expected = result[c("nports", "freq_ghz", "freq_unit", "data_format",
                            "param_type", "z0", "dataset_tag", "points")])
})
jsonlite::write_json(list(
  provenance = list(runtime = R.version.string, source_md5 = canonical_md5(source_path)),
  cases = cases
), file.path(root, "python_app/tests/fixtures/touchstone_reference.json"),
   auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
cat("Exported", length(cases), "Touchstone fixture cases\n")
