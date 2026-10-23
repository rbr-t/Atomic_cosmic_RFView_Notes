# Offline reference generation using the existing conversion inputs.
args <- commandArgs(trailingOnly=FALSE)
script <- sub("^--file=", "", args[grepl("^--file=", args)][1])
root <- normalizePath(file.path(dirname(script), "../../.."), winslash="/")
path <- file.path(root, "PA design App/src/modules/rf_tools/sp_parsers.R")
source(path)
inputs <- jsonlite::read_json(file.path(root, "python_app/tests/fixtures/network_parameters_reference.json"))
encode <- function(m) {
  if (any(is.na(m))) return(NULL)
  lapply(1:2, function(r) lapply(1:2, function(c) list(real=Re(m[r,c]), imag=Im(m[r,c]))))
}
cases <- lapply(inputs$cases, function(case) {
  s <- matrix(0+0i, 2, 2)
  for (r in 1:2) for (c in 1:2) {
    v <- case$s[[r]][[c]]
    s[r,c] <- complex(real=v$real, imaginary=v$imag)
  }
  list(name=case$name, s=case$s, z0=case$z0,
       h=encode(sp_s_to_h(s, case$z0)),
       abcd=encode(sp_s_to_abcd(s, case$z0)), t=encode(sp_s_to_t(s)))
})
temporary <- tempfile()
writeBin(charToRaw(paste0(paste(readLines(path, warn=FALSE, encoding="UTF-8"), collapse="\n"), "\n")), temporary)
hash <- unname(tools::md5sum(temporary))
unlink(temporary)
jsonlite::write_json(list(provenance=list(runtime=R.version.string, source_md5=hash), cases=cases),
  file.path(root, "python_app/tests/fixtures/transfer_parameters_reference.json"),
  pretty=TRUE, auto_unbox=TRUE, digits=16, na="null", null="null")
