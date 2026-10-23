# Offline reference generation; Python tests/runtime do not require R.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
source_path <- file.path(root, "PA design App/src/modules/rf_tools/sp_parsers.R")
source(source_path)
encode <- function(value) {
  lapply(seq_len(2), function(row) {
    lapply(seq_len(2), function(col) {
      list(real = Re(value[row, col]), imag = Im(value[row, col]))
    })
  })
}
matrices <- list(
  matched = matrix(0+0i, 2, 2),
  diagonal = diag(c(0.2+0.1i, -0.3-0.2i)),
  asymmetric = matrix(c(0.1+0.2i, 2-0.5i, 0.03+0.04i, -0.2+0.1i), 2, 2),
  reciprocal = matrix(c(0.1+0.1i, 0.5-0.2i, 0.5-0.2i, -0.1+0.3i), 2, 2),
  near_z = diag(c(1-1e-12, 0)),
  near_y = diag(c(-1+1e-12, 0))
)
cases <- list()
for (name in names(matrices)) {
  for (z0 in c(25, 50, 75)) {
    s <- matrices[[name]]
    cases[[length(cases)+1]] <- list(
      name = paste(name, z0), s = encode(s), z0 = z0,
      z = encode(sp_s_to_z(s, z0)), y = encode(sp_s_to_y(s, z0))
    )
  }
}
temporary <- tempfile()
writeBin(charToRaw(paste0(paste(
  readLines(source_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"
), "\n")), temporary)
hash <- unname(tools::md5sum(temporary))
unlink(temporary)
jsonlite::write_json(list(
  provenance = list(runtime = R.version.string, source_md5 = hash),
  cases = cases
), file.path(root, "python_app/tests/fixtures/network_parameters_reference.json"),
   auto_unbox = TRUE, pretty = TRUE, digits = 16, null = "null")
cat("Exported", length(cases), "two-port conversion cases\n")
