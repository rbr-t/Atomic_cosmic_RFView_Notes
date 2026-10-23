# Offline oracle generation only.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
path <- file.path(root, "PA design App/src/modules/rf_tools/sp_parsers.R")
source(path)
matrices <- list(
  matched = matrix(0+0i, 2, 2),
  unilateral = matrix(c(0.1, 2, 0, 0.2), 2, 2),
  asymmetric = matrix(c(0.1+0.2i, 2-0.5i, 0.03+0.04i, -0.2+0.1i), 2, 2),
  unstable = matrix(c(0.8, 3, 0.5, 0.8), 2, 2),
  boundary = matrix(c(0, 1, 1, 0), 2, 2),
  active = matrix(c(1.1, 2, 0.1, 0.3), 2, 2),
  no_forward = matrix(c(0.1, 0, 0.1, 0.2), 2, 2),
  tiny_reverse = matrix(c(0.2, 2, 1e-16, 0.3), 2, 2)
)
encode <- function(s) {
  lapply(1:2, function(row) lapply(1:2, function(col) {
    list(real = Re(s[row,col]), imag = Im(s[row,col]))
  }))
}
cases <- lapply(names(matrices), function(name) {
  s <- matrices[[name]]
  result <- as.list(sp_stability(list(s), 1)[1,])
  result$freq_ghz <- NULL
  k_infinite <- is.infinite(result$K)
  if (k_infinite) result$K <- NA_real_
  list(name = name, s = encode(s), k_infinite = k_infinite, expected = result)
})
temporary <- tempfile()
writeBin(charToRaw(paste0(paste(readLines(path, warn=FALSE, encoding="UTF-8"),
                             collapse="\n"), "\n")), temporary)
hash <- unname(tools::md5sum(temporary))
unlink(temporary)
jsonlite::write_json(list(
  provenance = list(runtime = R.version.string, source_md5 = hash),
  cases = cases
), file.path(root, "python_app/tests/fixtures/stability_reference.json"),
   pretty=TRUE, auto_unbox=TRUE, digits=16, na="null", null="null")
cat("Exported", length(cases), "stability cases\n")
