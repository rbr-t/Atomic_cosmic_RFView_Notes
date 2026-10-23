# Offline oracle generation only; reuse the qualified stability input matrices.
args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash = "/")
path <- file.path(root, "PA design App/src/modules/rf_tools/sp_parsers.R")
source(path)
input <- jsonlite::read_json(file.path(root, "python_app/tests/fixtures/stability_reference.json"))
cases <- lapply(input$cases, function(case) {
  s <- matrix(0+0i, 2, 2)
  for (row in 1:2) for (col in 1:2) {
    value <- case$s[[row]][[col]]
    s[row,col] <- complex(real=value$real, imaginary=value$imag)
  }
  result <- sp_stab_circles(list(s), 1)
  encode <- function(row) {
    if (is.na(row$radius)) return(NULL)
    as.list(row[c("center_r", "center_i", "radius")])
  }
  list(name=case$name, s=case$s,
       expected=list(load=encode(result$load[1,]), source=encode(result$source[1,])))
})
temporary <- tempfile()
writeBin(charToRaw(paste0(paste(readLines(path, warn=FALSE, encoding="UTF-8"),
                             collapse="\n"), "\n")), temporary)
hash <- unname(tools::md5sum(temporary))
unlink(temporary)
jsonlite::write_json(list(
  provenance=list(runtime=R.version.string, source_md5=hash), cases=cases),
  file.path(root, "python_app/tests/fixtures/stability_circles_reference.json"),
  pretty=TRUE, auto_unbox=TRUE, digits=16, na="null", null="null")
cat("Exported", length(cases), "stability circle cases\n")
